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

# 옛 광장 (64x44 시절). 넓힌 광장(7번)이 x 41부터 모두 덮어쓴다.
# 여기 ellipse 들은 난수를 쓰므로 지우면 농장 쪽 꾸미기가 바뀐다 → 난수 순서를 지키려고 그대로 둔다
PCX, PCY = 49, 21
for cx, cy, rx, ry in [(PCX, PCY, 7.5, 5.5), (44, 18.5, 4, 3), (54.5, 23.5, 4, 3), (43.5, 15.5, 3.2, 1.6), (53.5, 14.5, 3.2, 1.6)]:
    ellipse(cx, cy, rx, ry, "p", over=".T")

for x, y, ch in [(40, 14, "c"), (45, 14, "f"), (51, 13, "b"), (55, 13, "f"),
                 (44, 24, "h"), (52, 26, "h"),
                 (41, 18, "L"), (57, 20, "L"), (47, 26, "L")]:
    put(x, y, ch)

# 나중에 지을 시설 터 (맨흙). 광장 둘레에 몇 군데 비워 둔다.
for cx, cy, rx, ry in [(59, 14, 2.4, 2.0), (41.5, 29, 3.0, 2.0), (57.5, 28.5, 2.6, 2.0)]:
    ellipse(cx, cy, rx, ry, "x", over=".")

# 대장간 (§43, 3x2, 57~59 / 12~13). 광장 동쪽 시설 터 위쪽, 아래 두 줄은 다음 시설 터로 남긴다

# 레시피 상점 (셰프 §71, 3x2, 40~42 / 27~28). 광장 남서쪽 시설 터 위쪽, 나머지는 다음 시설 터로 남긴다

# 기계상점 (3x2, 57~59 / 14~15). 대장간 아래 시설 터. 공장·자동화 기계를 아이템으로 판다 (사용자 결정)

# 오래된 비행선 정류장 (§89, 4x3, 55~58 / 27~29). 광장 남동쪽 시설 터. 복구하면 하늘섬으로 가는 비행선

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

# ================================================================ 7. 메인 광장 (사용자 요청: 넓게 + 무드 이미지의 아늑한 마을 광장)
# 맵 64x44 → 112x64. 서쪽 x < 41 (농장·개울·다리) 은 위에서 만든 그대로 두어 저장 호환을 지키고,
# 남쪽으로 늘어난 줄은 맨 아래 줄(숲 + 개울)을 이어 붙인다. 동쪽은 새로 그린다.
# 무드: 분수를 가운데 둔 둥근 꿀색 자갈 광장, 가게마다 앞마당·칠판 간판·진열품, 빈 잔디는 꽃밭·나무로 채우고
#       길가·개울가에 낮은 나무 울타리, 남쪽은 석축으로 두른 개울(수련·오리·나루터), 북쪽 숲길에 나무 아치.

KEEP_X = 41
W2, H2 = 112, 64
prng = random.Random(11)
base = g
g = [["T" for _ in range(W2)] for _ in range(H2)]
W, H = W2, H2
for y in range(H2):
    src = base[min(y, len(base) - 1)]
    for x in range(KEEP_X):
        ch = src[x]
        if x >= 38 and ch not in "T~#s.":
            ch = "."  # 옛 광장 끝자락 글자 정리
        g[y][x] = ch


def rect(x0, y0, w, h, ch, over=None):
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            put(x, y, ch, over)


def disc(cx, cy, r, ch, over=None):
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                put(x, y, ch, over)


def walk(points, ch="p", radius=1.5, over=None):
    """곧은 점 잇기 (돌길). stroke 와 달리 난수를 쓰지 않는다"""
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        n = int(math.dist((ax, ay), (bx, by)) * 3) + 1
        for k in range(n + 1):
            t = k / n
            x, y = ax + (bx - ax) * t, ay + (by - ay) * t
            disc(x, y, radius, ch, over)


# 광장 땅 (잔디). 둘레 숲 가장자리는 들쭉날쭉
for y in range(4, 60):
    for x in range(KEEP_X, 108):
        edge = min(x - KEEP_X, 107 - x, y - 4, 59 - y)
        if edge > 1 or prng.random() < 0.55 + 0.2 * edge:
            put(x, y, ".")

# 남쪽 개울: 북쪽 둑은 석축(e), 물에는 수련·오리. 길이 지나는 곳은 나무다리
for x in range(KEEP_X - 2, W2):
    wob = int(round(1.2 * math.sin(x / 5.0)))
    for y in range(52 + wob, 57 + wob):
        put(x, y, "~")
    put(x, 51 + wob, "e")
    put(x, 57 + wob, ".", over="T")

# 꿀색 자갈길: 다리 → 큰길 → 동쪽 출구, 북쪽 숲길, 분수 광장, 남쪽 개울 다리
rect(39, 17, 69, 3, "p")
rect(108, 17, 4, 3, "s")
rect(72, 0, 3, 52, "p")
CX, CY = 74, 30                       # 분수 칸 (3x3 의 가운데)
disc(CX + 0.5, CY + 0.5, 9.5, "p")
rect(72, 50, 3, 10, "#", over="~e")   # 개울 다리
rect(72, 57, 3, 3, "p", over=".T")

# 가게 (글자 = 왼쪽 위 칸) 와 앞마당. 앞마당에서 분수 광장으로 돌길
SHOPS = [("M", 52, 11, 5), ("K", 79, 11, 4), ("J", 85, 11, 5), ("C", 52, 37, 4), ("A", 94, 45, 4)]
for ch, x, y, w in SHOPS:
    rect(x, y, w, 3, "X")             # 건물 자리 (꾸미기가 들어가지 않게 잠시 막아 둔다)
    rect(x - 1, y + 3, w + 2, 2, "p")
walk([(54.5, 16), (58, 21)], radius=1.4)
walk([(81, 16), (79, 21)], radius=1.4)
walk([(87.5, 16), (86, 21)], radius=1.4)
walk([(56, 41.5), (62, 38), (67, 35)], radius=1.4)
walk([(81, 36), (90, 42), (96, 47)], radius=1.4)
rect(90, 43, 13, 7, "p")              # 정류장 마당
walk([(84, 30), (92, 30)], radius=1.3)   # 마을 상점 노점 앞
rect(89, 31, 6, 2, "p")

# 분수 둘레: 꽃 화분 고리 (네 방향 입구는 비움) + 벤치 + 가로등
for a in range(0, 360, 8):
    if min(abs(a - d) for d in (0, 90, 180, 270, 360)) < 18:
        continue
    r = math.radians(a)
    put(int(math.floor(CX + 0.5 + 5.6 * math.cos(r))), int(math.floor(CY + 0.5 + 5.6 * math.sin(r))), "P")
for x, y in [(73, 23), (73, 37), (66, 30), (80, 30)]:
    put(x, y, "h")
for x, y in [(68, 24), (80, 24), (68, 36), (80, 36),
             (48, 16), (62, 16), (77, 16), (93, 16), (104, 16), (70, 47), (77, 47), (89, 42), (103, 42), (51, 36)]:
    put(x, y, "L")
put(CX, CY, "F")

# 가게 앞 소품 (무드: 칠판 간판·씨앗 수레·모루·기계 상자)
for x, y, ch in [(51, 14, "1"), (58, 14, "4"), (78, 14, "2"), (83, 14, "5"), (84, 15, "c"), (91, 14, "3"), (90, 15, "6"),
                 (57, 15, "f"), (50, 15, "f"), (89, 13, "b"), (93, 13, "b"), (56, 40, "f"), (51, 40, "c")]:
    put(x, y, ch)
put(66, 22, "Q")                      # 마을 게시판 (분수 광장 북서)
put(90, 29, "7")                      # 마을 상점 노점 (장식)
put(42, 15, "9")                      # "← 내 농장" 팻말 (다리 바로 동쪽)
put(46, 21, "N")                      # 갈림길 이정표
put(73, 6, "G")                       # 북쪽 숲길 아치
rect(84, 48, 6, 3, "#", over=".e")    # 나루터 + 배송함 (장식)
put(86, 49, "8")

# 낮은 나무 울타리 (=): 길가·개울가. 길이 지나는 칸은 비운다
for y, x0, x1 in [(25, 53, 58), (25, 91, 96), (47, 43, 48), (47, 53, 59), (47, 63, 67), (47, 80, 86), (47, 104, 107), (21, 61, 65), (21, 98, 103)]:
    for x in range(x0, x1):
        put(x, y, "=", over=".")

# 빈 시설 터 (나중 시설)
for x, y, w, h in [(98, 10, 5, 4), (44, 39, 5, 4), (58, 43, 5, 4), (99, 27, 5, 4)]:
    rect(x, y, w, h, "x")

# 수련·오리 (개울 위 장식)
for _ in range(60):
    x, y = prng.randrange(KEEP_X, W2), prng.randrange(50, 59)
    if at(x, y) == "~" and at(x, y - 1) != "e":
        put(x, y, "l")
for x, y in [(60, 54), (64, 53), (95, 54), (99, 55)]:
    if at(x, y) == "~":
        put(x, y, "u")

# 잔디 채우기 (무드: 빈 잔디가 없게): 꽃밭 무더기 + 나무·덤불 (길·건물에서 2칸 떨어진 곳)
def open_around(x, y, r):
    return all(at(xx, yy) in ".," for yy in range(y - r, y + r + 1) for xx in range(x - r, x + r + 1))


for cx, cy, r in [(46, 11, 2.2), (65, 12, 2.0), (97, 20, 2.0), (45, 29, 2.6), (58, 32, 2.0), (90, 36, 2.2), (101, 35, 2.4),
                  (50, 46, 1.8), (64, 45, 1.6), (84, 44, 1.6), (104, 50, 1.4), (62, 7, 1.6), (86, 6, 1.6), (101, 6, 1.6), (45, 6, 1.6)]:
    disc(cx, cy, r, "*", over=".")
grown = 0
for _ in range(4000):
    x, y = prng.randrange(KEEP_X + 1, 107), prng.randrange(5, 50)
    if not open_around(x, y, 2):
        continue
    put(x, y, prng.choice("TTYYBB*"))
    grown += 1
    if grown >= 70:
        break
for x, y in [(76, 2), (106, 15)]:
    put(x, y, "n", over=".T")
for ch, x, y, w in SHOPS:
    rect(x, y, w, 3, ".")
    put(x, y, ch)

# ================================================================ 저장

rows = ["".join(r) for r in g]
assert all(len(r) == W for r in rows) and len(rows) == H
for ch in "HMWOKCAJ@":
    assert sum(r.count(ch) for r in rows) == 1, ch

layout = ROOT / "scripts" / "world" / "map_layout.gd"
src = layout.read_text(encoding="utf-8")
block = "const ROWS := [\n" + "".join(f'\t"{r}",\n' for r in rows) + "]"
src = re.sub(r"const ROWS := \[\n.*?\n\]", block, src, flags=re.S)
layout.write_text(src, encoding="utf-8")
print("\n".join(rows))
print("farmable:", sum(r.count("g") + r.count("d") for r in rows))
