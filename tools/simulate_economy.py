"""경제 시뮬레이션 (BuildFarm_Economy_v1.0.md 10-8): 게임 데이터 파일을 그대로 읽어 계산한다.

    python tools/simulate_economy.py

1부 (계산표)  작물 1칸 28일·112일 이익 · 레시피 부가가치 · 비료 회수 · 기계 회수 기간 · 제련 · 광산
2부 (1년 모델) 112일 동안 돈이 어떻게 늘어나는지 전략별로 (가정은 ASSUME 에, 실제 플레이와 다를 수 있음)
"""
import io
import json
import math
import random
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"


def load(name):
    return json.loads(io.open(DATA / name, encoding="utf-8").read())


ITEMS = load("items.json")
RECIPES = {k: v for k, v in load("recipes.json").items() if not k.startswith("_")}
PLACE = load("placeables.json")
QUALITY = load("quality.json")
MINE = load("mine.json")
OBS = load("obstacles.json")["types"]
CAL = load("calendar.json")
DAYS = CAL["days_per_season"]
SEASONS = CAL["seasons"]

# 2부 가정 (실제 플레이로 확인 필요)
ASSUME = {
    "start_money": 500,
    "hand_tiles": 30,          # 하루 15분 안에 손으로 심고 물 주는 칸 수 (물뿌리개 12회 + 우물 왕복)
    "reserve": 300,            # 씨앗값으로 남겨 두는 돈
    "water_infra": ["pump", "water_tank", "small_generator"],   # 스프링클러를 처음 살 때 함께
    "sprinkler": "sprinkler_1",
    "mine_floors_per_day": 2,  # 광산 전략: 하루에 내려가는 층
    "mine_hand_tiles_lost": 10,  # 광산에 가는 날 손으로 돌보는 칸이 줄어듦
    "wood_price_for_power": None,  # None = items.json 목재 판매가 (발전기 연료를 팔지 않고 태우는 값)
}


def name(i):
    return ITEMS[i]["name"]


def price(i):
    return ITEMS.get(i, {}).get("sell_price", 0)


def qmult():
    return {q: t["multiplier"] for q, t in QUALITY["types"].items()}


def quality_ev(table):
    m = qmult()
    ch = QUALITY["harvest_chances"][table]
    tot = sum(ch.values())
    return sum(ch[q] / tot * math.floor(m[q] * 1000) / 1000 for q in ch)


def seeds():
    return {k: v for k, v in ITEMS.items() if isinstance(v, dict) and v.get("kind") == "seed"}


def yield_avg(sd):
    return (sd["yield_min"] + sd["yield_max"]) / 2


def season_profit(sd, days=DAYS, ev=1.0):
    """한 칸에서 days 일 동안 (매일 물, 바로 다시 심기) 기대 이익"""
    g, r, sell, seed = sd["grow_days"], sd["regrow_days"], price(sd["grows"]), sd["buy_price"]
    per = yield_avg(sd) * sell * ev
    if r > 0:
        n = (days - g) // r + 1 if days >= g else 0
        return n, n * per - seed
    n = days // g
    return n, n * (per - seed)


def power_cost_per_hour(power):
    """발전기 연료를 목재로 쓸 때 시간당 비용 (목재를 팔지 않고 태우는 값)"""
    gen = PLACE["small_generator"]["generator"]
    wood_energy = gen["fuels"]["wood"]
    wood = ASSUME["wood_price_for_power"] or price("wood")
    return power / wood_energy * wood


def recipe_va(r):
    cost = sum(price(i) * n for i, n in r["inputs"].items())
    return r["count"] * price(r["output"]) - cost, cost


def proc_cfg(mid):
    return PLACE[mid]["processor"]


# ---------------------------------------------------------------- 1부

def part1():
    ev0 = quality_ev("none")
    print("=" * 72)
    print("1부. 계산표 (게임 데이터 그대로)")
    print("=" * 72)
    print(f"\n[1] 작물 1칸 기대 이익 (수확량 평균 2개, 출하함 100%, 비료 없음 품질 기댓값 ×{ev0:.3f})")
    print(f"  {'작물':8} {'계절':10} {'성장':>4} {'재수확':>5} {'28일':>8} {'112일(제철만)':>13}")
    rows = []
    for sid, sd in seeds().items():
        n, p28 = season_profit(sd, ev=ev0)
        seasons = sd["seasons"]
        outdoor = [s for s in seasons if s not in CAL["no_outdoor_planting"]]
        # 여러 계절 작물: 이어지는 계절이면 한 번 심어 쭉 (재수확), 아니면 계절마다
        if sd["regrow_days"] > 0 and len(outdoor) > 1:
            _, p112 = season_profit(sd, days=DAYS * len(outdoor), ev=ev0)
        else:
            p112 = p28 * len(outdoor)
        rows.append((p28, name(sd["grows"]), "·".join(CAL["names"][s] for s in seasons), sd["grow_days"], sd["regrow_days"], p112, outdoor))
    for p28, nm, ss, g, r, p112, outdoor in sorted(rows, reverse=True):
        note = "" if outdoor else "  (온실 전용)"
        print(f"  {nm:8} {ss:10} {g:>4} {r if r else '-':>5} {p28:8.0f} {p112:13.0f}{note}")

    print("\n[2] 레시피 부가가치 (재료를 그냥 팔았을 때보다 더 버는 돈)")
    pc_e = power_cost_per_hour(proc_cfg("electric_processor")["power"])
    pc_m = power_cost_per_hour(proc_cfg("mid_processor")["power"])
    print(f"  전기료(목재 연료 환산): 전기 가공기 시간당 {pc_e:.1f} G, 중급 가공기 {pc_m:.1f} G")
    print(f"  {'레시피':12} {'등급':>4} {'시간':>4} {'재료값':>6} {'완성품':>6} {'1회 +':>6} {'시간당(전기)':>11} {'시간당(중급)':>11}")
    best = {}
    for rid, r in RECIPES.items():
        va, cost = recipe_va(r)
        tier, mt = r["tier"], r.get("machine_tier", r["tier"])
        e_h = va * 60 / r["minutes"] - pc_e if mt <= 1 else None
        m_h = va * 60 / (r["minutes"] / proc_cfg("mid_processor").get("speed", 1)) - pc_m
        best[rid] = (va, e_h, m_h)
        e_txt = f"{e_h:11.1f}" if e_h is not None else f"{'-':>11}"
        print(f"  {name(r['output']):12} {'하중상'[tier - 1]:>4} {r['minutes']:>4} {cost:6} {r['count'] * price(r['output']):6} {va:+6} {e_txt} {m_h:11.1f}")
    neg = [rid for rid, (va, _, _) in best.items() if va <= 0]
    print("  손해 보는 레시피: " + (", ".join(neg) if neg else "없음"))

    print("\n[3] 비료 회수 (한 번 쓰면 한 번 수확 작물은 그 수확까지, 재수확 작물은 그 계절 내내)")
    evs = {t: quality_ev(t) for t in QUALITY["harvest_chances"] if not t.startswith("_")}
    print("  품질 기댓값 배율: " + ", ".join(f"{t} ×{v:.3f}" for t, v in evs.items()))
    ferts = [(k, v) for k, v in ITEMS.items() if isinstance(v, dict) and v.get("kind") == "fertilizer"]
    print(f"  {'작물':8} " + " ".join(f"{name(k):>12}" for k, _ in ferts))
    for sid, sd in sorted(seeds().items(), key=lambda kv: price(kv[1]["grows"])):
        cells = []
        n = season_profit(sd)[0] if sd["regrow_days"] > 0 else 1
        for k, v in ferts:
            gain = (evs[v["quality_table"]] - ev0) * yield_avg(sd) * price(sd["grows"]) * n - v["buy_price"]
            cells.append(f"{gain:+12.0f}")
        print(f"  {name(sd['grows']):8} " + " ".join(cells))
    print("  (+ 이면 비료값보다 더 벎, − 이면 손해. 한 번 수확 작물은 수확 1번 기준)")

    print("\n[4] 기계 회수 기간 (하루 24시간 = 깨어 있는 19시간 + 야간 생산 5시간 돌린다고 가정, 재료는 넉넉)")
    for mid in ("electric_processor", "mid_processor"):
        cfg = proc_cfg(mid)
        speed = cfg.get("speed", 1)
        cand = [(va * 60 * 24 / (r["minutes"] / speed), rid) for rid, r in RECIPES.items()
                for va in [recipe_va(r)[0]] if r.get("machine_tier", r["tier"]) <= cfg["tier"]]
        day_va, rid = max(cand)
        day_power = power_cost_per_hour(cfg["power"]) * 24
        cost = ITEMS[mid]["buy_price"]
        net = day_va - day_power
        print(f"  {name(mid):8} {cost:6} G  가장 좋은 레시피 {name(RECIPES[rid]['output'])}: 하루 +{day_va:.0f} − 전기 {day_power:.0f} = {net:.0f} G → {cost / net:.1f}일에 회수")
        need = {i: n * 60 * 24 / (RECIPES[rid]['minutes'] / speed) for i, n in RECIPES[rid]['inputs'].items()}
        print("     하루에 필요한 재료: " + ", ".join(f"{name(i)} {v:.0f}개" for i, v in need.items()))
    for sp in ("sprinkler_1", "sprinkler_2", "sprinkler_3"):
        a = PLACE[sp]["area"]
        tiles = 4 if a["shape"] == "plus" else (2 * a["radius"] + 1) ** 2 - 1
        print(f"  {name(sp):14} {ITEMS[sp]['buy_price']:6} G  {tiles:2}칸 자동 물 → 칸당 {ITEMS[sp]['buy_price'] / tiles:.0f} G")

    print("\n[5] 제련 (석탄값 포함)")
    fr = PLACE["furnace"]["furnace"]["recipes"]
    for ore, r in fr.items():
        cost = r["ore"] * price(ore) + r["coal"] * price("coal")
        out = price(r["output"])
        print(f"  {name(r['output']):6} 판매 {out} − 재료 {cost} = {out - cost:+} G ({(out - cost) / cost:.0%}), {r['minutes']}분 → 시간당 {(out - cost) * 60 / r['minutes']:.0f} G")

    print("\n[6] 광산 (바위 하나·한 층·사다리를 찾을 때까지)")
    for start, per_rock, until in mine_rows():
        print(f"  {start:2}층부터  바위 하나 {per_rock:5.1f} G  사다리까지 평균 {until[0]:.1f}개 → {until[1]:5.0f} G  (다 깨면 {per_rock * sum(MINE['rocks']) / 2:5.0f} G)")


def rock_value(t):
    return sum((d["min"] + d["max"]) / 2 * price(d["item"]) for d in OBS[t]["drops"])


def rocks_until_ladder():
    """사다리가 나올 때까지 깨는 바위 수 기댓값 (확률 = base + per_rock × 깬 수, 마지막 바위는 반드시)"""
    cfg = MINE["ladder"]
    n_rocks = sum(MINE["rocks"]) / 2
    exp, alive = 0.0, 1.0
    k = 1
    while alive > 1e-6 and k <= n_rocks:
        p = 1.0 if k >= n_rocks else min(1.0, cfg["base"] + cfg["per_rock"] * k)
        exp += alive * p * k
        alive *= 1 - p
        k += 1
    return exp


def mine_rows():
    k = rocks_until_ladder()
    out = []
    for row in MINE["depths"]:
        w = row["rocks"]
        per = sum(w[t] / sum(w.values()) * rock_value(t) for t in w)
        out.append((row["from"], per, (k, k * per)))
    return out


def mine_floor_income(depth):
    rows = mine_rows()
    per = rows[0][1]
    for start, p, _ in rows:
        if depth >= start:
            per = p
    return rocks_until_ladder() * per


# ---------------------------------------------------------------- 2부: 1년 모델

def best_seed(season, money):
    """지금 계절에 밖에 심을 수 있는 씨앗 중 하루당 이익이 가장 큰 것 (살 수 있는 값)"""
    best, best_v = None, 0
    ev0 = quality_ev("none")
    for sid, sd in seeds().items():
        if season not in sd["seasons"] or sd["buy_price"] > money:
            continue
        n, p = season_profit(sd, ev=ev0)
        v = p / DAYS
        if v > best_v:
            best, best_v = sid, v
    return best


def simulate(strategy, seed=1):
    rng = random.Random(seed)
    money = ASSUME["start_money"]
    ev0 = quality_ev("none")
    plots = []  # 각 칸: {"seed": id, "grown": 일, "regrowing": bool} 또는 None
    hand = ASSUME["hand_tiles"] - (ASSUME["mine_hand_tiles_lost"] if strategy == "mine" else 0)
    auto = 0
    infra = False
    spent = {"씨앗": 0, "설비": 0}
    earned = {"작물": 0, "광산": 0}
    depth = 0
    log = []
    for day in range(DAYS * 4):
        season = SEASONS[day // DAYS]
        if day % DAYS == 0:
            # 계절이 바뀌면 그 계절에 못 사는 작물은 시듦
            plots = [p if p and season in seeds()[p["seed"]]["seasons"] else None for p in plots]
        size = hand + auto
        while len(plots) < size:
            plots.append(None)
        outdoor = season not in CAL["no_outdoor_planting"]
        # 심기
        if outdoor:
            for i in range(size):
                if plots[i] is None:
                    sid = best_seed(season, money - 0)
                    if sid and money >= seeds()[sid]["buy_price"]:
                        money -= seeds()[sid]["buy_price"]
                        spent["씨앗"] += seeds()[sid]["buy_price"]
                        plots[i] = {"seed": sid, "grown": 0, "regrowing": False}
        # 하루 자라기 (물은 손 + 스프링클러로 다 준다고 가정) · 수확
        for i, p in enumerate(plots):
            if p is None:
                continue
            sd = seeds()[p["seed"]]
            p["grown"] += 1
            need = sd["regrow_days"] if p["regrowing"] else sd["grow_days"]
            if p["grown"] >= need:
                n = rng.randint(sd["yield_min"], sd["yield_max"])
                got = n * price(sd["grows"]) * ev0
                money += got
                earned["작물"] += got
                if sd["regrow_days"] > 0:
                    p["grown"], p["regrowing"] = 0, True
                else:
                    plots[i] = None
        # 광산
        if strategy == "mine":
            for _ in range(ASSUME["mine_floors_per_day"]):
                depth = min(MINE["bottom"], depth + 1)
                got = mine_floor_income(depth)
                money += got
                earned["광산"] += got
        # 투자: 스프링클러 (처음엔 펌프·물탱크·발전기)
        if strategy in ("sprinkler", "mine_sprinkler"):
            while True:
                cost = ITEMS[ASSUME["sprinkler"]]["buy_price"] + (0 if infra else sum(ITEMS[i]["buy_price"] for i in ASSUME["water_infra"]))
                if money < cost + ASSUME["reserve"]:
                    break
                money -= cost
                spent["설비"] += cost
                infra = True
                auto += 4
        if (day + 1) % DAYS == 0:
            log.append((CAL["names"][season], round(money), hand + auto))
    return log, spent, earned


def part2():
    print("\n" + "=" * 72)
    print("2부. 1년 모델 (가정: " + ", ".join(f"{k}={v}" for k, v in ASSUME.items() if v is not None) + ")")
    print("=" * 72)
    print("  매일 물을 다 주고, 계절마다 하루당 이익이 가장 큰 제철 작물을 심고, 출하함에 판다고 가정.")
    print("  겨울은 바깥에 못 심음 (지금 규칙). 온실·가공·비료는 넣지 않은 보수적인 모델.")
    names = {"farm": "농사만 (손 30칸)", "sprinkler": "농사 + 스프링클러 투자", "mine": "농사 20칸 + 광산 하루 2층"}
    for st in ("farm", "sprinkler", "mine"):
        runs = [simulate(st, seed=s) for s in range(20)]
        log = [(runs[0][0][i][0], sum(r[0][i][1] for r in runs) / len(runs), runs[0][0][i][2]) for i in range(4)]
        sp = {k: sum(r[1][k] for r in runs) / len(runs) for k in runs[0][1]}
        er = {k: sum(r[2][k] for r in runs) / len(runs) for k in runs[0][2]}
        print(f"\n  [{names[st]}]  (20번 평균)")
        for season, money, tiles in log:
            print(f"    {season} 끝: {money:8.0f} G   밭 {tiles}칸")
        print("    1년 번 돈: " + ", ".join(f"{k} {v:.0f}" for k, v in er.items() if v) + "  /  쓴 돈: " + ", ".join(f"{k} {v:.0f}" for k, v in sp.items() if v))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    part1()
    part2()
