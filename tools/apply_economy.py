"""경제 숫자 적용기: data/balance/economy_v1.json → items.json · quality.json · placeables.json

    python tools/apply_economy.py            바뀌는 값을 보여 주고 파일에 써 넣는다
    python tools/apply_economy.py --dry-run  바뀌는 값만 보여 준다 (파일은 그대로)
    python tools/apply_economy.py --report   작물 이익 · 제련 이익 표만 출력한다

JSON 파일은 사람이 맞춘 줄 모양을 지키도록 통째로 다시 쓰지 않고, 바꿀 값이 있는 자리만 글자로 고친다.
economy_v1.json 의 'later' 는 아직 적용하지 않는 값이라 읽지 않는다.
"""
import io
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
ECON = DATA / "balance" / "economy_v1.json"


class JsonText:
    """JSON 파일을 글자 그대로 들고, 정해진 키의 값만 바꾼다 (줄 모양·주석 키 유지)"""

    def __init__(self, path):
        self.path = path
        raw = io.open(path, encoding="utf-8", newline="").read()
        self.nl = "\r\n" if "\r\n" in raw else "\n"
        self.s = raw.replace("\r\n", "\n")
        self.changes = []

    def _value_span(self, start):
        """start 위치에서 시작하는 JSON 값의 끝 (괄호 짝·문자열을 따라간다)"""
        s, i = self.s, start
        if s[i] in "{[":
            depth, in_str, esc = 0, False, False
            while True:
                ch = s[i]
                if in_str:
                    if esc:
                        esc = False
                    elif ch == "\\":
                        esc = True
                    elif ch == '"':
                        in_str = False
                elif ch == '"':
                    in_str = True
                elif ch in "{[":
                    depth += 1
                elif ch in "}]":
                    depth -= 1
                    if depth == 0:
                        return i + 1
                i += 1
        if s[i] == '"':
            i += 1
            while s[i] != '"':
                i += 2 if s[i] == "\\" else 1
            return i + 1
        m = re.compile(r"[^,\n}\]]+").match(s, i)
        return i + len(m.group(0).rstrip())

    def _object_span(self, path):
        """키 경로 (예: ["carrot_seed"]) 가 가리키는 객체의 { } 범위"""
        lo, hi = self.s.index("{"), None
        hi = self._value_span(lo)
        for key in path:
            lo, hi = self._key_value(key, lo, hi)
        return lo, hi

    def _key_value(self, key, lo, hi):
        """lo~hi 객체 안 바로 아래 단계의 key 값 범위"""
        s = self.s
        i, depth = lo + 1, 0
        pat = '"%s"' % key
        while i < hi:
            ch = s[i]
            if ch == '"':
                end = self._value_span(i)
                if depth == 0 and s[i:end] == pat:
                    j = end
                    while s[j] in " \t\n:":
                        j += 1
                    return j, self._value_span(j)
                i = end
                continue
            if ch in "{[":
                depth += 1
            elif ch in "}]":
                depth -= 1
            i += 1
        raise KeyError("/".join([key]))

    def get(self, path):
        lo, hi = self._object_span(path[:-1])
        a, b = self._key_value(path[-1], lo, hi)
        return json.loads(self.s[a:b])

    def set(self, path, value):
        """path 의 값을 value 로 (한 줄 JSON). 값이 같으면 그대로"""
        lo, hi = self._object_span(path[:-1])
        a, b = self._key_value(path[-1], lo, hi)
        old = json.loads(self.s[a:b])
        if old == value:
            return False
        text = json.dumps(value, ensure_ascii=False, separators=(", ", ": "))
        self.s = self.s[:a] + text + self.s[b:]
        self.changes.append(("/".join(path), old, value))
        return True

    def set_or_add(self, path, value, after):
        """키가 없으면 같은 객체의 after 키 줄 바로 다음에 새 줄로 넣는다 (예: 팔 수 없던 아이템에 sell_price)"""
        lo, hi = self._object_span(path[:-1])
        try:
            self._key_value(path[-1], lo, hi)
        except KeyError:
            a, b = self._key_value(after, lo, hi)
            line_start = self.s.rfind("\n", 0, a) + 1
            indent = re.match(r"[ \t]*", self.s[line_start:]).group(0)
            text = ",\n%s\"%s\": %s" % (indent, path[-1], json.dumps(value, ensure_ascii=False))
            self.s = self.s[:b] + text + self.s[b:]
            self.changes.append(("/".join(path), None, value))
            return True
        return self.set(path, value)

    def save(self):
        json.loads(self.s)
        io.open(self.path, "w", encoding="utf-8", newline="").write(self.s.replace("\n", self.nl))


SEASON_NAME = {"spring": "봄", "summer": "여름", "autumn": "가을", "winter": "겨울"}


def seed_description(items, seed_id):
    """씨앗 설명: 성장일·재수확·수확량을 숫자에 맞춰 다시 쓴다 (계절·온실 안내는 지금 데이터 그대로)"""
    seed = items.get([seed_id])
    g, r = seed["grow_days"], seed["regrow_days"]
    lo, hi = seed["yield_min"], seed["yield_max"]
    count = f"{lo}~{hi}개" if lo != hi else f"{lo}개"
    if r > 0:
        text = f"{g}일이면 열리고, 거둔 뒤에도 {r}일마다 다시 열려요. 한 번에 {count}씩."
    else:
        text = f"{g}일이면 자라요. 한 번에 {count}를 거둬요."
    seasons = seed.get("seasons", [])
    if seasons == ["winter"]:
        text += " 겨울 작물이라 온실에서 키워요."
    elif len(seasons) > 1:
        text = "·".join(SEASON_NAME[x] for x in seasons) + "에 심어요. " + text
    return text


def apply(econ, dry_run):
    items = JsonText(DATA / "items.json")
    quality = JsonText(DATA / "quality.json")
    places = JsonText(DATA / "placeables.json")

    # 품질 배율 · 비료 확률 · 비료 가격
    for q, m in econ["quality"]["multipliers"].items():
        quality.set(["types", q, "multiplier"], m)
    for table, chances in econ["quality"]["harvest_chances"].items():
        for q, c in chances.items():
            quality.set(["harvest_chances", table, q], c)
    for fid, price in econ["fertilizer_prices"].items():
        items.set([fid, "buy_price"], price)

    # 작물 (씨앗 = <id>_seed)
    for crop, c in econ["crops"].items():
        seed = crop + "_seed"
        assert items.get([seed, "grows"]) == crop, seed
        items.set([seed, "buy_price"], c["seed"])
        items.set([crop, "sell_price"], c["sell"])
        items.set([seed, "grow_days"], c["grow_days"])
        items.set([seed, "regrow_days"], c["regrow_days"])
        items.set([seed, "yield_min"], c["yield"][0])
        items.set([seed, "yield_max"], c["yield"][1])
        items.set([seed, "description"], seed_description(items, seed))

    # 재료 · 광석 · 주괴 · 석탄 (목재·돌·섬유처럼 팔 수 없던 것은 sell_price 줄을 새로 넣는다)
    for mid, price in econ["materials"].items():
        items.set_or_add([mid, "sell_price"], price, after="kind")

    # 용광로 (석탄 연료 유지)
    f = econ["furnace"]
    for ore, minutes in f["minutes"].items():
        places.set(["furnace", "furnace", "recipes", ore, "ore"], f["ore_per_bar"])
        places.set(["furnace", "furnace", "recipes", ore, "coal"], f["coal_per_bar"])
        places.set(["furnace", "furnace", "recipes", ore, "minutes"], minutes)
    n = f["ore_per_bar"]
    items.set(["furnace", "description"], f"광석 {n}개 + 석탄 {f['coal_per_bar']}개를 넣으면 주괴 1개를 구워요. 광석을 들고 클릭해서 넣어요.")
    places.set(["furnace", "description"], f"광석 {n}개 + 석탄 {f['coal_per_bar']}개 → 주괴 1개. 광석을 들고 클릭해서 넣고, [E] 로 꺼내요.")
    for bar, ore in (("copper_bar", "구리 광석"), ("iron_bar", "철 광석"), ("gold_bar", "금 광석")):
        tier = {"copper_bar": "구리", "iron_bar": "철", "gold_bar": "금"}[bar]
        items.set([bar, "description"], f"용광로에서 {ore} {n}개를 구운 것. {tier} 도구로 강화하는 데 써요.")

    # 기계 구매가
    for mid, price in econ["machines"].items():
        items.set([mid, "buy_price"], price)

    # 도구 강화 비용 · 주괴 개수 · 물뿌리개 용량
    t = econ["tools"]
    bars = ["copper_bar", "iron_bar", "gold_bar"]
    for tool, prices in t["upgrade_price"].items():
        for step, price in enumerate(prices):
            src = tool if step == 0 else f"{tool}_{step + 1}"
            items.set([src, "upgrade", "price"], price)
            items.set([src, "upgrade", "materials"], {bars[step]: t["upgrade_bars"][step]})
    for step, cap in enumerate(t["watering_can_capacity"]):
        items.set(["watering_can" if step == 0 else f"watering_can_{step + 1}", "capacity"], cap)
    for step in (2, 3):
        cap = t["watering_can_capacity"][step]
        old = items.get([f"watering_can_{step + 1}", "description"])
        items.set([f"watering_can_{step + 1}", "description"], re.sub(r"물이 \d+번", f"물이 {cap}번", old))

    for f_ in (items, quality, places):
        for path, old, new in f_.changes:
            print(f"  {f_.path.name:16} {path:48} {old!r} → {new!r}")
        if not dry_run and f_.changes:
            f_.save()
    total = sum(len(f_.changes) for f_ in (items, quality, places))
    print(f"{'바뀔' if dry_run else '바꾼'} 값 {total}개")


def mine_check(econ):
    """광산 한 층을 다 깼을 때 평균 수입 (바위 수 평균 × 층별 바위 비율 × 드롭 평균 × 판매가)"""
    mine = json.loads(io.open(DATA / "mine.json", encoding="utf-8").read())
    obs = json.loads(io.open(DATA / "obstacles.json", encoding="utf-8").read())["types"]
    price = dict(econ["materials"])

    def rock_value(t):
        return sum((d["min"] + d["max"]) / 2 * price.get(d["item"], 0) for d in obs[t]["drops"])

    rocks = sum(mine["rocks"]) / 2
    rows = []
    for row in mine["depths"]:
        w = row["rocks"]
        per_rock = sum(w[k] / sum(w.values()) * rock_value(k) for k in w)
        rows.append((row["from"], per_rock, per_rock * rocks))
    return rows


def crop_profits(econ):
    out = {}
    for crop, c in econ["crops"].items():
        avg = sum(c["yield"]) / 2
        g, r = c["grow_days"], c["regrow_days"]
        if r > 0:
            harvests = (28 - g) // r + 1
            out[crop] = (harvests, harvests * avg * c["sell"] - c["seed"])
        else:
            harvests = 28 // g
            out[crop] = (harvests, harvests * (avg * c["sell"] - c["seed"]))
    return out


def report(econ):
    """문서 10-8: 작물 1칸 28일 기대 이익 (매일 물, 바로 다시 심기, 품질 보너스 없음) · 제련 이익"""
    print("작물 1칸 · 28일 기대 순이익 (수확량 평균 × 판매가 − 씨앗)")
    profits = crop_profits(econ)
    for crop, (harvests, profit) in sorted(profits.items(), key=lambda kv: kv[1][1]):
        print(f"  {crop:13} 수확 {harvests:2}번  {profit:6.0f} G")
    m, f, chk = econ["materials"], econ["furnace"], econ["checks"]
    problems = []
    print(f"제련 (광석 {f['ore_per_bar']} + 석탄 {f['coal_per_bar']} → 주괴 1, 이익률 상한 {chk['smelt_margin_max']:.0%})")
    for ore, bar in (("copper_ore", "copper_bar"), ("iron_ore", "iron_bar"), ("gold_ore", "gold_bar")):
        cost = f["ore_per_bar"] * m[ore] + f["coal_per_bar"] * m["coal"]
        margin = (m[bar] - cost) / cost
        mark = "적자" if m[bar] <= cost else ("과함" if margin > chk["smelt_margin_max"] else "ok")
        if mark != "ok":
            problems.append(f"{bar} 제련 {mark}")
        print(f"  {bar:11} 판매 {m[bar]:4} G − 재료 {cost:4} G = {m[bar] - cost:+4} G  이익률 {margin:4.0%}  ({f['minutes'][ore]}분)  {mark}")
    best = max(p for _, p in profits.values())
    limit = chk["mine_floor_vs_crop_max"] * best
    print(f"광산 한 층을 다 깼을 때 평균 수입 (기준: 가장 좋은 작물 한 칸 한 계절 {best:.0f} G × {chk['mine_floor_vs_crop_max']} = {limit:.0f} G)")
    for start, per_rock, per_floor in mine_check(econ):
        mark = "주의" if per_floor > limit else "ok"
        if mark != "ok":
            problems.append(f"광산 {start}층부터 한 층 {per_floor:.0f} G")
        print(f"  {start:2}층부터  바위 하나 {per_rock:5.1f} G  한 층 {per_floor:5.0f} G  {mark}")
    print("검산: " + ("문제 없음" if not problems else " · ".join(problems)))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    econ = json.loads(io.open(ECON, encoding="utf-8").read())
    if "--report" in sys.argv:
        report(econ)
    else:
        apply(econ, "--dry-run" in sys.argv)
