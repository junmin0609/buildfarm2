"""BuildFarm 맵 설계도 → scripts/world/map_layout.gd 의 ROWS 를 만든다.

맵은 두 구역으로 나뉜다.
  서쪽: 플레이어 개인 농장  (생산·농사·건설·자동화·꾸미기)  - 장식 최소, 넓은 경작지
  동쪽: 메인 광장           (거래·NPC·상점·각종 시설)       - 분수 중심의 작은 마을
두 구역 사이는 넓은 개울과 그 양쪽 숲띠가 확실히 갈라놓고,
숲 사이로 난 오솔길 하나와 나무다리로만 오갈 수 있다.

결과 글자 지도는 map_layout.gd 에 들어간다. 그 뒤로는 글자를 직접 고쳐도 된다.
(이 스크립트를 다시 돌리면 덮어쓴다)

실행: python tools/make_map.py
"""

import math
import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
W, H = 64, 44

g = [["." for _ in range(W)] for _ in range(H)]
rng = random.Random(7)


def inside(x, y):
    return 0 <= x < W and 0 <= y < H


def at(x, y):
    return g[y][x] if inside(x, y) else ""


def put(x, y, ch, over=None):
    """over 가 주어지면 그 글자들 위에만 칠한다."""
    if inside(x, y) and (over is None or g[y][x] in over):
        g[y][x] = ch


def ellipse(cx, cy, rx, ry, ch, over=None, wobble=0.0):
    for y in range(H):
        for x in range(W):
            d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
            if d <= 1.0 + (rng.random() - 0.5) * wobble:
                put(x, y, ch, over)


def stroke(points, ch, radius=0.8, over=None):
    """점들을 잇는 부드러운 곡선(Catmull-Rom)을 붓으로 칠한다."""
    pts = [points[0]] + points + [points[-1]]
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        steps = int(math.dist(p1, p2) * 4) + 1
        for k in range(steps):
            t = k / steps
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            for yy in range(int(y - radius) - 1, int(y + radius) + 2):
                for xx in range(int(x - radius) - 1, int(x + radius) + 2):
                    if (xx - x) ** 2 + (yy - y) ** 2 <= radius * radius:
                        put(xx, yy, ch, over)


def smooth_noise(i, scale, seed):
    r = random.Random(seed)
    knots = [r.random() for _ in range(int(i / scale) + 3)]
    a = int(i / scale)
    t = i / scale - a
    t = t * t * (3 - 2 * t)
    return knots[a] * (1 - t) + knots[a + 1] * t


# ================================================================ 1. 외곽 숲 (들쭉날쭉)

for x in range(W):
    for y in range(2 + int(smooth_noise(x, 5, 1) * 3)):
        put(x, y, "T")
    for y in range(H - 2 - int(smooth_noise(x, 6, 2) * 2), H):
        put(x, y, "T")
for y in range(H):
    for x in range(2 + int(smooth_noise(y, 5, 3) * 3)):
        put(x, y, "T")
    for x in range(W - 2 - int(smooth_noise(y, 5, 4) * 2), W):
        put(x, y, "T")

# ================================================================ 2. 두 구역 사이 개울 (북→남, 살짝 굽이침) - 숲띠와 함께 4번 뒤에 그린다

RIVER = [(35, -1), (34.5, 8), (36.5, 16), (35.5, 24), (33.5, 32), (34.5, 45)]

# ================================================================ 3. 개인 농장 (서쪽)

# 넓은 경작지: 잔디처럼 보이지만 괭이로 갈 수 있는 땅 (g). 울타리 없이 주변과 이어진다.
FARM_BLOBS = [(17, 25, 12.5, 10), (12, 32, 8, 6), (23, 20, 8, 6), (10, 20, 6, 6)]
for cx, cy, rx, ry in FARM_BLOBS:
    ellipse(cx, cy, rx, ry, "g", over=".", wobble=0.15)

# 집 (4x3, 8~11 / 6~8). 문 앞에서 시작한다.
HX, HY = 8, 6
for y in range(HY - 1, HY + 5):
    for x in range(HX - 2, HX + 6):
        put(x, y, ".", over="Tg")
put(HX, HY, "H")
put(HX - 1, HY + 2, "f")
put(HX + 4, HY + 2, "B")

# 처음부터 일궈 둔 작은 흙밭 (집 앞 남동쪽)
ellipse(15.5, 17.5, 5.2, 3.2, "d", over="g.")

# 농장 남서쪽 작은 연못 (나중에 물대기 시설 자리)
ellipse(7.5, 37, 3.4, 2.2, "~", over="g.T")

# ================================================================ 4. 메인 광장 (동쪽)

PCX, PCY = 49, 21
for cx, cy, rx, ry in [(PCX, PCY, 7.5, 5.5), (44, 18.5, 4, 3), (54.5, 23.5, 4, 3), (43.5, 15.5, 3.2, 1.6), (53.5, 14.5, 3.2, 1.6)]:
    ellipse(cx, cy, rx, ry, "p", over=".T")

put(41, 11, "M")       # 잡화점 (41~44, 11~13, 4x3). 씨앗 상점과 작물 판매처를 합친 곳 (사용자 요청, 안에 들어가 NPC 와 거래)
put(52, 12, "f")       # 예전 작물 판매처 자리: 화분 (판매는 잡화점으로 합침)
put(48, 14, "Q")       # 퀘스트 게시판
put(PCX, PCY, "F")     # 분수
for x, y, ch in [(40, 14, "c"), (45, 14, "f"), (51, 13, "b"), (55, 13, "f"),
                 (44, 24, "h"), (52, 26, "h"),
                 (41, 18, "L"), (57, 20, "L"), (47, 26, "L")]:
    put(x, y, ch)

# 나중에 지을 시설 터 (맨흙). 광장 둘레에 몇 군데 비워 둔다.
for cx, cy, rx, ry in [(59, 14, 2.4, 2.0), (41.5, 29, 3.0, 2.0), (57.5, 28.5, 2.6, 2.0)]:
    ellipse(cx, cy, rx, ry, "x", over=".")

# 대장간 (§43, 3x2, 57~59 / 12~13). 광장 동쪽 시설 터 위쪽, 아래 두 줄은 다음 시설 터로 남긴다
put(57, 12, "K")

# 레시피 상점 (셰프 §71, 3x2, 40~42 / 27~28). 광장 남서쪽 시설 터 위쪽, 나머지는 다음 시설 터로 남긴다
put(40, 27, "C")

# 기계상점 (3x2, 57~59 / 14~15). 대장간 아래 시설 터. 공장·자동화 기계를 아이템으로 판다 (사용자 결정)
put(57, 14, "J")

# 오래된 비행선 정류장 (§89, 4x3, 55~58 / 27~29). 광장 남동쪽 시설 터. 복구하면 하늘섬으로 가는 비행선
put(55, 27, "A")

# ================================================================ 4.5 구역 경계: 개울 양쪽 숲띠 + 넓은 개울

stroke(RIVER, "T", radius=4.3, over=".")       # 농장·광장 사이 빈 땅을 숲으로 메운다
stroke(RIVER, "~", radius=1.8, over=".T")     # 넓어진 개울

# ================================================================ 5. 길

# 농장 집 앞 → 흙밭 위쪽을 돌아 → 다리 → 광장
farm_road = [(HX + 2.5, HY + 3.4), (HX + 3.5, HY + 4.6), (16, 11), (23, 10.6), (28.5, 12.5), (32, 16.5), (36, 17.6), (40.5, 18.2)]
# 숲띠를 지나는 구간은 길 양옆을 조금 틔워 오솔길처럼
stroke([p for p in farm_road if 27 <= p[0] <= 42], ".", radius=1.7, over="T")
stroke(farm_road, "s", radius=0.85, over=".T")
for x in range(28, 42):
    for y in (17, 18):
        if at(x, y) == "~":
            put(x, y, "#")

# 광장 → 북쪽 출구 (다음 지역)
stroke([(50.5, 14), (50.5, 9), (49, 5), (49.5, -1)], "s", radius=0.85, over=".T")
put(51, 5, "n", over=".")
# 광장 → 동쪽 출구 (다음 지역)
stroke([(56.5, 21), (60, 21.5), (64, 21)], "s", radius=0.85, over=".T")
put(60, 19, "n", over=".")
# 광장 → 남쪽 숲길 연못
stroke([(49, 26), (48, 31), (50, 35)], "s", radius=0.75, over=".")
ellipse(52.5, 37, 4, 2.4, "~", over=".")

put(HX + 2, HY + 4, "@")

# ================================================================ 6. 자연 꾸미기 (농장 경작지 g 와 길·광장은 비워 둔다)

for y in range(H):
    for x in range(W):
        if at(x, y) == "." and any(at(x + dx, y + dy) == "T" for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            r = rng.random()
            if r < 0.18:
                put(x, y, "Y")
            elif r < 0.30:
                put(x, y, "B")

for y in range(H):
    for x in range(W):
        if at(x, y) == "." and any(at(x + dx, y + dy) == "~" for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            r = rng.random()
            if r < 0.22:
                put(x, y, "r")
            elif r < 0.28:
                put(x, y, "R")

for cx, cy in ((44, 9), (57, 9), (39, 33), (58, 33), (27, 6)):
    ellipse(cx, cy, 2.2, 1.4, ",", over=".", wobble=0.6)


def clear_around(x, y, r):
    return all(at(xx, yy) in ".," for yy in range(y - r, y + r + 1) for xx in range(x - r, x + r + 1))


placed = 0
for _ in range(600):
    x, y = rng.randrange(3, W - 3), rng.randrange(3, H - 3)
    if not clear_around(x, y, 2):
        continue
    put(x, y, rng.choice("RBYYBT"))
    placed += 1
    if placed >= 22:
        break

# ================================================================ 5.5 우물 (§14)
# 집과 흙밭 사이, 집 앞 길 옆 (2x2, 14~15 / 8~9). 장식을 다 놓은 뒤에 두어 다른 배치(난수 순서)를 바꾸지 않는다.
WX, WY = HX + 6, HY + 2
for y in range(WY, WY + 3):
    for x in range(WX, WX + 2):
        put(x, y, ".")
put(WX, WY, "W")

# 출하함 (§83, 2x1, 5~6 / 8). 집 왼쪽, 문 앞에서 몇 걸음
OX, OY = HX - 3, HY + 2
for y in range(OY, OY + 2):
    for x in range(OX, OX + 2):
        put(x, y, ".")
put(OX, OY, "O")

# ================================================================ 저장

rows = ["".join(r) for r in g]
assert all(len(r) == W for r in rows)
for ch in "HMWOKCAJ@":
    assert sum(r.count(ch) for r in rows) == 1, ch

layout = ROOT / "scripts" / "world" / "map_layout.gd"
src = layout.read_text(encoding="utf-8")
block = "const ROWS := [\n" + "".join(f'\t"{r}",\n' for r in rows) + "]"
src = re.sub(r"const ROWS := \[\n.*?\n\]", block, src, flags=re.S)
layout.write_text(src, encoding="utf-8")
print("\n".join(rows))
print("farmable:", sum(r.count("g") + r.count("d") for r in rows))
