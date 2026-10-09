"""BuildFarm 픽셀 아트 생성기.

외부 라이브러리 없이 모든 그래픽을 코드로 찍어 assets/art/ 에 PNG로 저장한다.
16px 도트 기준이며 게임에서는 4배로 확대해 선명하게 보여준다. (UI 테두리는 3배로 미리 키워 저장)
둥글고 따뜻한 톤: 외곽선은 검정 대신 갈색, 모서리는 둥글게, 회색 대신 모래·크림색.

실행: python tools/make_art.py
"""

import math
import random
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "art"
T = 16  # 타일 크기


# ---------------------------------------------------------------- 캔버스

def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


CLEAR = (0, 0, 0, 0)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[CLEAR] * w for _ in range(h)]

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return CLEAR

    def set(self, x, y, c):
        if c is None:
            return
        if 0 <= x < self.w and 0 <= y < self.h:
            if len(c) == 4 and c[3] < 255 and c[3] > 0:
                # 반투명은 아래 색과 섞는다
                b = self.px[y][x]
                a = c[3] / 255
                if b[3] == 0:
                    self.px[y][x] = c
                else:
                    self.px[y][x] = tuple(int(c[i] * a + b[i] * (1 - a)) for i in range(3)) + (255,)
            else:
                self.px[y][x] = c

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, c)

    def ellipse(self, cx, cy, rx, ry, c):
        for yy in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for xx in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if ((xx + 0.5 - cx) / rx) ** 2 + ((yy + 0.5 - cy) / ry) ** 2 <= 1.0:
                    self.set(xx, yy, c)

    def template(self, rows, palette, ox=0, oy=0, flip=False):
        for y, row in enumerate(rows):
            row = row.ljust(T if len(row) <= T else len(row), ".")
            for x, ch in enumerate(row):
                if ch == ".":
                    continue
                xx = (len(row) - 1 - x) if flip else x
                self.set(ox + xx, oy + y, palette[ch])

    def outline(self, color, region=None):
        """불투명 픽셀 둘레의 빈칸에 외곽선을 친다."""
        x0, y0, x1, y1 = region or (0, 0, self.w, self.h)
        marks = []
        for y in range(y0, y1):
            for x in range(x0, x1):
                if self.get(x, y)[3] != 0:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if x0 <= nx < x1 and y0 <= ny < y1 and self.get(nx, ny)[3] == 255:
                        marks.append((x, y))
                        break
        for x, y in marks:
            self.set(x, y, color)

    def blit(self, other, ox, oy):
        for y in range(other.h):
            for x in range(other.w):
                c = other.px[y][x]
                if c[3]:
                    self.set(ox + x, oy + y, c)

    def scaled(self, k):
        out = Canvas(self.w * k, self.h * k)
        for y in range(self.h):
            for x in range(self.w):
                out.rect(x * k, y * k, k, k, self.px[y][x])
        return out

    def save(self, name):
        OUT.mkdir(parents=True, exist_ok=True)
        raw = b"".join(b"\x00" + bytes(v for p in row for v in p) for row in self.px)

        def chunk(tag, data):
            return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
        (OUT / name).write_bytes(png)
        print(f"  {name}  {self.w}x{self.h}")


def sub(canvas, col, row, size=T):
    """아틀라스의 (col,row) 칸에 그릴 작은 캔버스와, 다 그린 뒤 붙이는 함수."""
    c = Canvas(size, size)
    return c, lambda: canvas.blit(c, col * size, row * size)


# ---------------------------------------------------------------- 팔레트 (따뜻하고 부드러운 톤)

INK = hexc("5b3a29")  # 외곽선: 검정 대신 따뜻한 갈색이라 전체가 부드러워 보인다

P = {
    "grass": [hexc("63904a"), hexc("76a65a"), hexc("88b768"), hexc("a2c97e")],
    "meadow": [hexc("67924b"), hexc("7ba95c"), hexc("8dba6a"), hexc("a8cc80")],
    "dirt": [hexc("a8754a"), hexc("bf8a5a"), hexc("cf9c69"), hexc("ddb07d")],
    "soil": [hexc("6e452b"), hexc("8a5a3a"), hexc("a06b45"), hexc("b8865a")],
    "wet": [hexc("4f3122"), hexc("64412d"), hexc("764f37"), hexc("8a6044")],
    "sand": [hexc("c49a6a"), hexc("dcb985"), hexc("e8cc9c"), hexc("f4e0b6")],
    "water": [hexc("5a9fc8"), hexc("6eb3d6"), hexc("89c5e0"), hexc("dcf2f8")],
    "stone": [hexc("a99782"), hexc("c8b9a2"), hexc("ddd1bd"), hexc("efe7d8")],
    "wood": [hexc("7a4e32"), hexc("a8714a"), hexc("c98f5e"), hexc("e6b77f")],
    "leaf": [hexc("3d6b35"), hexc("4f8a3f"), hexc("64a64a"), hexc("7fc05a"), hexc("a8dc78")],
    "ink": INK,
}
SOFT_SHADOW = (91, 58, 41, 60)


def noise_fill(c, colors, weights, rng):
    for y in range(c.h):
        for x in range(c.w):
            c.set(x, y, rng.choices(colors, weights)[0])


def rrect(c, x, y, w, h, r, col):
    """모서리가 둥근 사각형"""
    for yy in range(h):
        for xx in range(w):
            px, py = xx + 0.5, yy + 0.5
            cx = min(max(px, r), w - r)
            cy = min(max(py, r), h - r)
            if (px - cx) ** 2 + (py - cy) ** 2 <= r * r + 0.25:
                c.set(x + xx, y + yy, col)


def blob(c, circles, pal, outline=None, light=(-0.5, -0.6)):
    """여러 원을 합친 둥근 덩어리를 4단계 명암으로 칠한다 (디더링 없이 매끈하게)."""
    for y in range(c.h):
        for x in range(c.w):
            best = None
            for cx, cy, r in circles:
                d = math.hypot(x + 0.5 - cx, y + 0.5 - cy) / r
                if d <= 1.0 and (best is None or d < best[0]):
                    best = (d, cx, cy, r)
            if best is None:
                continue
            _, cx, cy, r = best
            nx, ny = (x + 0.5 - cx) / r, (y + 0.5 - cy) / r
            v = -(nx * light[0] + ny * light[1])
            idx = 1 if v < -0.45 else 2 if v < 0.05 else 3 if v < 0.5 else 4
            c.set(x, y, pal[min(idx, len(pal) - 1)])
    if outline:
        c.outline(outline)


# ---------------------------------------------------------------- 지형 타일 (tiles.png, 8x3칸)

def tuft(c, x, y, g=None):
    g = g or P["grass"]
    c.set(x, y + 1, g[0])
    c.set(x - 1, y, g[2]); c.set(x + 1, y, g[2])
    c.set(x, y - 1, g[3])


def grass(c, rng, flowers=0, pal=None):
    """부드러운 잔디. 은은한 색 얼룩과 풀잎 몇 개만 둬서 깔끔하게."""
    g = pal or P["grass"]
    noise_fill(c, [g[1], g[2]], [14, 2], rng)
    for _ in range(2):
        cx, cy = rng.randrange(2, 14), rng.randrange(2, 14)
        for y in range(cy - 2, cy + 3):
            for x in range(cx - 3, cx + 4):
                if 0 <= x < T and 0 <= y < T and (x - cx) ** 2 / 9 + (y - cy) ** 2 / 4 <= 1 and rng.random() < 0.7:
                    c.set(x, y, g[2])
    for _ in range(2):
        tuft(c, rng.randrange(2, 14), rng.randrange(2, 13), g)
    flower_colors = [(hexc("fff6e8"), hexc("f7c548")), (hexc("f4b4c0"), hexc("fff1a8")), (hexc("cdb8ec"), hexc("fffbe8"))]
    for i in range(flowers):
        x, y = rng.randrange(3, 13), rng.randrange(3, 12)
        petal, center = flower_colors[(i + flowers) % 3]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            c.set(x + dx, y + dy, petal)
        c.set(x, y, center)
        c.set(x, y + 2, g[0])


def dirt(c, rng):
    d = P["dirt"]
    noise_fill(c, [d[1], d[2]], [12, 3], rng)
    for _ in range(3):
        x, y = rng.randrange(2, 14), rng.randrange(2, 14)
        c.set(x, y, d[3]); c.set(x, y + 1, d[0])


def cobbles(c, rng, sizes, count, mortar):
    """둥근 돌을 겹치지 않게 흩뿌린다. 돌마다 왼쪽 위는 밝고 아래는 그늘."""
    st = P["stone"]
    noise_fill(c, mortar, [10, 3], rng)
    placed = []
    for _ in range(count * 30):
        if len(placed) >= count:
            break
        w, h = rng.choice(sizes)
        x, y = rng.randrange(0, T - w + 1), rng.randrange(0, T - h + 1)
        if any(x < px + pw + 1 and px < x + w + 1 and y < py + ph + 1 and py < y + h + 1 for px, py, pw, ph in placed):
            continue
        placed.append((x, y, w, h))
        rrect(c, x, y, w, h, 1.6, st[0])
        rrect(c, x, y, w, h - 1, 1.6, st[1])
        rrect(c, x + 1, y, w - 2, h - 2, 1.2, st[2])
        c.set(x + 1, y + 1, st[3])
        if w > 4:
            c.set(x + 2, y + 1, st[3])


def path(c, rng):
    s = P["sand"]
    cobbles(c, rng, [(5, 4), (4, 4), (6, 5), (4, 3), (5, 5)], 6, [s[1], s[2]])


def plaza(c, rng):
    s = P["sand"]
    cobbles(c, rng, [(7, 6), (6, 7), (7, 7), (5, 6)], 4, [s[2], s[3]])


def water(c, rng, phase):
    w = P["water"]
    noise_fill(c, [w[1], w[2]], [12, 2], rng)
    for i, (x, y) in enumerate([(2, 3), (9, 7), (4, 11), (11, 13)]):
        x = (x + phase * 2) % 13
        c.set(x, y, w[3]); c.set(x + 1, y + 1, w[3]); c.set(x + 2, y, w[3])
    c.set((6 + phase * 5) % 16, 5, hexc("ffffff"))


def soil(c, pal, wet):
    s = pal
    rrect(c, 1, 1, 14, 14, 3.5, s[0])
    rrect(c, 2, 2, 12, 12, 2.5, s[1])
    for y in (5, 9, 13):
        c.rect(4, y - 1, 8, 1, s[3])
        c.rect(3, y, 10, 1, s[0] if y < 13 else s[1])
        c.set(3, y - 1, s[2]); c.set(12, y - 1, s[2])
    c.rect(4, 2, 8, 1, s[2])
    if wet:
        for x, y in ((5, 6), (10, 10), (7, 11), (11, 5)):
            c.set(x, y, hexc("bfe4f2"))


def post(c, x, top=3, height=11):
    w = P["wood"]
    rrect(c, x, top, 4, height, 1.6, w[2])
    c.rect(x + 1, top + 1, 1, height - 2, w[3])
    c.rect(x + 3, top + 2, 1, height - 3, w[1])
    c.outline(INK, (x - 1, top - 1, x + 5, top + height + 1))


def fence_h(c):
    w = P["wood"]
    for y in (6, 10):
        rrect(c, 0, y, T, 2, 0.5, w[2])
        c.rect(0, y, T, 1, w[3])
        c.rect(0, y + 2, T, 1, SOFT_SHADOW)
    post(c, 6)


def fence_v(c):
    w = P["wood"]
    for x in (6, 9):
        c.rect(x, 0, 1, T, w[2])
    c.rect(7, 0, 2, T, w[3])
    post(c, 6, top=4)


def cursor(c):
    """선택 칸 표시: 네 모서리만 둥글게 감싼 얇은 크림색 선. 게임에서 은은하게 깜빡인다."""
    cream, warm = hexc("fff8e6"), hexc("f2cf86")
    for x in range(T):
        for y in range(T):
            if 5 <= x <= 10 or 5 <= y <= 10:
                continue
            px, py = x + 0.5, y + 0.5
            cx = min(max(px, 4.5), T - 4.5)
            cy = min(max(py, 4.5), T - 4.5)
            d = math.hypot(px - cx, py - cy)
            if 2.8 <= d <= 4.4:
                c.set(x, y, cream if d < 3.6 else warm)


def make_tiles():
    """tiles.png (8x4칸)
    0줄: 잔디 4, 꽃잔디 2, 흙, 돌길1 / 1줄: 물 2프레임, 밭, 젖은 밭, 울타리 3 /
    2줄: 커서, 따뜻한 풀밭 4, 돌길2~4 / 3줄: 상점 앞 넓은 돌바닥 2"""
    rng = random.Random(11)
    atlas = Canvas(8 * T, 4 * T)
    for i in range(4):
        c, done = sub(atlas, i, 0); grass(c, rng); done()
    for i in range(2):
        c, done = sub(atlas, 4 + i, 0); grass(c, rng, flowers=2 + i); done()
    c, done = sub(atlas, 6, 0); dirt(c, rng); done()
    c, done = sub(atlas, 7, 0); path(c, random.Random(101)); done()
    for i in range(2):
        c, done = sub(atlas, i, 1); water(c, random.Random(3), i); done()
    c, done = sub(atlas, 2, 1); soil(c, P["soil"], False); done()
    c, done = sub(atlas, 3, 1); soil(c, P["wet"], True); done()
    c, done = sub(atlas, 4, 1); fence_h(c); done()
    c, done = sub(atlas, 5, 1); fence_v(c); done()
    c, done = sub(atlas, 6, 1); post(c, 6); done()
    c, done = sub(atlas, 0, 2); cursor(c); done()
    for i in range(4):
        c, done = sub(atlas, 1 + i, 2); grass(c, rng, pal=P["meadow"]); done()
    for i in range(3):
        c, done = sub(atlas, 5 + i, 2); path(c, random.Random(102 + i)); done()
    for i in range(2):
        c, done = sub(atlas, i, 3); plaza(c, random.Random(201 + i)); done()
    c, done = sub(atlas, 2, 3); bridge(c); done()
    atlas.save("tiles.png")


def bridge(c):
    """개울을 가로지르는 나무다리. 위아래는 물, 가운데 판자, 양쪽 난간."""
    water(c, random.Random(3), 0)
    w = P["wood"]
    c.rect(0, 2, T, 12, w[2])
    for x in range(0, T, 4):
        c.rect(x, 2, 1, 12, w[1])
        c.rect(x + 1, 3, 2, 1, w[3])
    for y in (1, 13):
        c.rect(0, y, T, 2, w[1])
        c.rect(0, y, T, 1, w[3])
    c.rect(0, 14, T, 1, SOFT_SHADOW)


# ---------------------------------------------------------------- 잔디 장식 (details.png)
# 잔디 위에 드문드문 얹는 작은 장식. 같은 잔디가 반복돼 보이지 않게 한다.
# 0 풀, 1 긴 풀, 2~4 꽃(흰·노랑·분홍), 5 클로버, 6 조약돌, 7 버섯

DETAIL_COUNT = 14


def make_details():
    g = P["grass"]
    atlas = Canvas(DETAIL_COUNT * T, T)
    c, done = sub(atlas, 0, 0)
    tuft(c, 6, 9, g); tuft(c, 9, 11, g); done()
    c, done = sub(atlas, 1, 0)
    for x, h in ((6, 5), (8, 7), (10, 4)):
        c.rect(x, 13 - h, 1, h, g[2]); c.set(x, 13 - h, g[3]); c.set(x, 13, g[0])
    done()
    for col, (petal, center) in enumerate([(hexc("fff6e8"), hexc("f7c548")), (hexc("f7d26a"), hexc("fff3c0")), (hexc("f4b4c0"), hexc("fff1a8"))]):
        c, done = sub(atlas, 2 + col, 0)
        for x, y in ((5, 6), (10, 9), (6, 11)):
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                c.set(x + dx, y + dy, petal)
            c.set(x, y, center); c.set(x, y + 2, g[0])
        done()
    c, done = sub(atlas, 5, 0)
    for x, y in ((6, 8), (10, 10)):
        for dx, dy in ((0, -1), (-1, 0), (1, 0)):
            c.set(x + dx, y + dy, g[3])
        c.set(x, y, g[2]); c.set(x, y + 1, g[0])
    done()
    c, done = sub(atlas, 6, 0)
    st = P["stone"]
    for x, y in ((5, 9), (9, 7), (10, 11)):
        c.rect(x, y, 2, 2, st[2]); c.set(x, y, st[3]); c.set(x + 1, y + 1, st[1])
    done()
    c, done = sub(atlas, 7, 0)
    c.rect(8, 10, 1, 3, hexc("f6ead6"))
    c.ellipse(8.5, 9.5, 2.5, 1.6, hexc("e0715f")); c.set(7, 9, hexc("fff6e8"))
    c.outline(INK)
    done()
    # 8 아주 작은 풀잎 두 가닥
    c, done = sub(atlas, 8, 0)
    for x, y in ((6, 9), (10, 6)):
        c.set(x, y, g[3]); c.set(x, y + 1, g[2]); c.set(x + 1, y + 1, g[3])
    done()
    # 9 어두운 잔디 얼룩 (톤 변화)
    c, done = sub(atlas, 9, 0)
    for x, y in ((5, 6), (6, 7), (8, 6), (7, 9), (10, 10), (11, 9)):
        c.set(x, y, g[0])
    done()
    # 10 밝은 잔디 얼룩
    c, done = sub(atlas, 10, 0)
    for x, y in ((4, 9), (5, 8), (9, 5), (10, 6), (11, 11)):
        c.set(x, y, g[3])
    done()
    # 11 작은 돌 하나
    c, done = sub(atlas, 11, 0)
    st = P["stone"]
    c.rect(7, 9, 3, 2, st[2]); c.set(7, 9, st[3]); c.set(9, 10, st[1])
    c.rect(8, 11, 3, 1, SOFT_SHADOW)
    done()
    # 12 씨앗 달린 잡초 (드물게)
    c, done = sub(atlas, 12, 0)
    for x, h in ((7, 6), (9, 4)):
        c.rect(x, 12 - h, 1, h, g[2]); c.set(x, 12, g[0])
    c.set(7, 5, hexc("d9b36a")); c.set(6, 6, hexc("d9b36a")); c.set(9, 7, hexc("e8c87a"))
    done()
    # 13 아주 작은 흰 꽃 하나
    c, done = sub(atlas, 13, 0)
    c.set(8, 7, hexc("fff6e8")); c.set(7, 8, hexc("fff6e8")); c.set(9, 8, hexc("fff6e8")); c.set(8, 9, hexc("fff6e8"))
    c.set(8, 8, hexc("f7c548")); c.set(8, 10, g[0])
    done()
    atlas.save("details.png")


# ---------------------------------------------------------------- 경계 (edges.png)
# 길·물·흙 칸 위에 덮어서, 옆 칸이 잔디면 그쪽 가장자리를 잔디가 살짝 덮게 한다.
# 줄: 0 길, 1 물, 2 흙 / 칸: 잔디 이웃 비트 (북1 동2 남4 서8)

EDGE_KINDS = ["path", "water", "dirt"]
## 같은 경계 모양이 줄지어 반복되지 않게 종류마다 변형을 여러 개 만든다 (줄 = 종류 × EDGE_VARIANTS + 변형)
EDGE_VARIANTS = 3


def edge_tile(kind, mask, variant=0):
    c = Canvas(T, T)
    g = P["grass"]
    rng = random.Random(EDGE_KINDS.index(kind) * 7 + 1 + variant * 101)
    # 잔디가 덮는 깊이: 1~3px 사이로 들쭉날쭉, 이웃끼리 너무 튀지 않게 한 번 고른다
    depth = [rng.choice([1, 2, 2, 2, 3]) for _ in range(T)]
    depth = [max(1, min(3, round((depth[i - 1] + depth[i] * 2 + depth[(i + 1) % T]) / 4 + rng.uniform(-0.4, 0.4)))) for i in range(T)]
    under = {"path": SOFT_SHADOW, "dirt": SOFT_SHADOW, "water": P["water"][3]}[kind]

    def pos(side, i, k):
        return {1: (i, k), 4: (i, T - 1 - k), 8: (k, i), 2: (T - 1 - k, i)}[side]

    for side in (1, 2, 4, 8):
        if not mask & side:
            continue
        for i in range(T):
            d = depth[i]
            for k in range(d):
                x, y = pos(side, i, k)
                c.set(x, y, g[1] if k < d - 1 else g[2])
            x, y = pos(side, i, d)
            if c.get(x, y)[3] == 0:
                c.set(x, y, under)
        # 경계 밖으로 삐져나온 풀잎 몇 개 (물가는 제외)
        if kind != "water":
            for _ in range(rng.choice([1, 2, 2, 3])):
                i = rng.randrange(2, T - 2)
                d = depth[i]
                x, y = pos(side, i, d)
                c.set(x, y, g[2])
                x, y = pos(side, i, d + 1)
                if rng.random() < 0.6:
                    c.set(x, y, g[3])
    # 두 변이 만나는 안쪽 모서리는 둥글게 채운다
    for a, b, (cx, cy) in ((1, 8, (0, 0)), (1, 2, (T - 1, 0)), (4, 8, (0, T - 1)), (4, 2, (T - 1, T - 1))):
        if mask & a and mask & b:
            for y in range(5):
                for x in range(5):
                    if x + y < 5:
                        px = cx + (x if cx == 0 else -x)
                        py = cy + (y if cy == 0 else -y)
                        c.set(px, py, g[1])
    return c


def corner_tile(kind, mask):
    """안쪽 모서리 둥글리기: 길(물·흙) 칸의 대각선 이웃만 잔디일 때 그 모서리에 잔디를 조금 채운다.
    비트: 북동1 남동2 남서4 북서8"""
    c = Canvas(T, T)
    g = P["grass"]
    under = P["water"][3] if kind == "water" else SOFT_SHADOW
    for bit, (cx, cy) in ((1, (T - 1, 0)), (2, (T - 1, T - 1)), (4, (0, T - 1)), (8, (0, 0))):
        if not mask & bit:
            continue
        sx = -1 if cx else 1
        sy = -1 if cy else 1
        for y in range(4):
            for x in range(4):
                if x + y <= 2:
                    c.set(cx + sx * x, cy + sy * y, g[1] if x + y < 2 else g[2])
                elif x + y == 3:
                    c.set(cx + sx * x, cy + sy * y, under)
    return c


def make_edges():
    atlas = Canvas(16 * T, len(EDGE_KINDS) * EDGE_VARIANTS * T)
    for k, kind in enumerate(EDGE_KINDS):
        for v in range(EDGE_VARIANTS):
            for mask in range(16):
                atlas.blit(edge_tile(kind, mask, v), mask * T, (k * EDGE_VARIANTS + v) * T)
    atlas.save("edges.png")
    corners = Canvas(16 * T, len(EDGE_KINDS) * T)
    for k, kind in enumerate(EDGE_KINDS):
        for mask in range(16):
            corners.blit(corner_tile(kind, mask), mask * T, k * T)
    corners.save("edge_corners.png")


# ---------------------------------------------------------------- 소품 (나무, 바위)

# 나무 (BUILD_FARM 월드 마감): 큰 동그라미 하나가 아니라 잎 덩어리 여러 개가 겹친 실루엣.
#   덩어리마다 왼쪽 위가 밝고(빛 방향은 다른 그림과 같음) 아래쪽이 어둡다. 뒤 덩어리와 겹치는 가장자리는
#   한 단계 어두운 선으로 나눠 잎 뭉치가 보이게 하고, 밝은 쪽에는 작은 잎 무늬를 몇 개 찍는다.
#   변형 4종 (넓은 / 높은 / 비대칭 / 열매) — 같은 색·같은 외곽선, 실루엣만 다르다.

TREE_VARIANTS = [
    # 이름, 캔버스 (w, h), 줄기 (x, 위 y, 굵기), 잎 덩어리 [(cx, cy, r)] 뒤 → 앞 순서, 열매 수, 가지 갈래
    ("tree_wide", (38, 36), (19, 20, 6), [(10, 18, 7), (28, 18, 7), (19, 9, 8), (12, 11, 6.5), (26, 11, 6.5), (19, 19, 8)], 0, [(-4, 23), (5, 22)]),
    ("tree_tall", (30, 44), (15, 26, 5), [(15, 7, 6), (9, 15, 6), (21, 15, 6), (15, 15, 7), (9, 24, 6), (21, 24, 6.5), (15, 25, 7)], 0, [(-3, 30)]),
    ("tree_lean", (36, 40), (15, 23, 5), [(9, 21, 6), (24, 10, 7), (14, 11, 7.5), (28, 18, 6), (19, 19, 8), (8, 13, 5)], 0, [(-5, 26), (6, 24)]),
    ("tree_fruit", (34, 38), (17, 22, 6), [(9, 19, 6.5), (25, 19, 6.5), (17, 10, 8), (10, 12, 5.5), (24, 12, 6), (17, 20, 7.5)], 5, [(4, 25)]),
]


def _wobble(cx, cy, r, x, y, seed):
    """덩어리 가장자리를 살짝 울퉁불퉁하게: 각도에 따라 반지름이 조금씩 다르다"""
    ang = math.atan2(y - cy, x - cx)
    return r * (1.0 + 0.10 * math.sin(ang * 5 + seed) + 0.05 * math.sin(ang * 9 + seed * 2.3))


def canopy(c, lumps, seed, pal=None):
    pal = pal or P["leaf"]
    owner = {}  # (x, y) -> 덩어리 번호 (앞 덩어리가 덮는다)
    for k, (cx, cy, r) in enumerate(lumps):
        for y in range(int(cy - r) - 2, int(cy + r) + 3):
            for x in range(int(cx - r) - 2, int(cx + r) + 3):
                if 0 <= x < c.w and 0 <= y < c.h and math.hypot(x + 0.5 - cx, y + 0.5 - cy) <= _wobble(cx, cy, r, x + 0.5, y + 0.5, seed + k):
                    owner[(x, y)] = k
    rng = random.Random(seed)
    for (x, y), k in owner.items():
        cx, cy, r = lumps[k]
        px, py = x + 0.5, y + 0.5
        # 초승달 명암: 왼쪽 위로 밀린 원 안은 밝게, 그보다 작은 원은 하이라이트, 밀린 원 밖(오른쪽 아래)은 그늘
        if math.hypot(px - (cx - 0.38 * r), py - (cy - 0.42 * r)) <= 0.3 * r:
            idx = 4
        elif math.hypot(px - (cx - 0.22 * r), py - (cy - 0.26 * r)) <= 0.72 * r:
            idx = 3
        elif math.hypot(px - (cx - 0.16 * r), py - (cy - 0.2 * r)) <= 0.98 * r:
            idx = 2
        else:
            idx = 1
        # 뒤 덩어리 위에 얹힌 가장자리는 진한 선으로 나눠 잎 뭉치가 보이게 (아래·오른쪽만 — 그림자 방향)
        for dx, dy in ((0, 1), (1, 0), (1, 1)):
            o = owner.get((x + dx, y + dy))
            if o is not None and o < k:
                idx = min(idx, 1) if dy == 0 else 0
                break
        c.set(x, y, pal[idx])
    # 밝은 쪽에 잎 끝 몇 개 (작은 하이라이트 점) — 너무 많지 않게
    for k, (cx, cy, r) in enumerate(lumps):
        for _ in range(1 + int(r // 4)):
            ang = rng.uniform(math.pi * 1.1, math.pi * 1.55)
            dist = rng.uniform(0.55, 0.8) * r
            x, y = int(cx + math.cos(ang) * dist), int(cy + math.sin(ang) * dist)
            if owner.get((x, y)) == k and c.get(x, y) == pal[3]:
                c.set(x, y, pal[4])
    return owner


def trunk(c, x, top, width, bottom, forks):
    w = P["wood"]
    x0 = x - width // 2
    rrect(c, x0, top, width, bottom - top, 1.5, w[1])
    c.rect(x0 + 1, top + 1, 1, bottom - top - 3, w[2])            # 밝은 왼쪽
    c.rect(x0 + width - 2, top + 2, 1, bottom - top - 3, w[0])    # 어두운 오른쪽
    for yy in range(top + 3, bottom - 2, 4):                       # 나무껍질 결
        c.set(x0 + 2 + (yy // 4) % max(1, width - 3), yy, w[0])
    # 뿌리 퍼짐 (바닥에 닿는 느낌)
    c.rect(x0 - 1, bottom - 2, width + 2, 2, w[1])
    c.set(x0 - 2, bottom - 1, w[1]); c.set(x0 + width + 1, bottom - 1, w[0])
    c.rect(x0, bottom - 1, width, 1, w[0])
    # 잎 사이로 보이는 가지
    for dx, fy in forks:
        sx = x + (width // 2 - 1 if dx > 0 else -width // 2)
        for k in range(abs(dx)):
            c.set(sx + (k if dx > 0 else -k), fy - k // 2 - 1, w[1])
            c.set(sx + (k if dx > 0 else -k), fy - k // 2, w[0])


def make_trees():
    for n, (name, (W, H), (tx, ttop, tw), lumps, fruits, forks) in enumerate(TREE_VARIANTS):
        c = Canvas(W, H)
        foot = H - 2
        c.ellipse(W / 2 + 1, foot + 0.3, W * 0.36, 2.2, SOFT_SHADOW)    # 접지 그림자 (빛 반대쪽으로 1px)
        c.ellipse(W / 2 + 1, foot + 0.2, W * 0.2, 1.3, SOFT_SHADOW)
        trunk(c, tx, ttop, tw, foot + 1, forks)
        leaves = Canvas(W, H)
        owner = canopy(leaves, lumps, 11 + n * 17)
        rng = random.Random(5 + n)
        spots = [pos for pos, k in owner.items() if leaves.get(pos[0], pos[1]) in (P["leaf"][2], P["leaf"][3])]
        rng.shuffle(spots)
        placed = []
        for x, y in spots:
            if len(placed) >= fruits:
                break
            if all(abs(x - px) + abs(y - py) > 5 for px, py in placed) and owner.get((x + 1, y + 1)) is not None:
                leaves.rect(x, y, 2, 2, hexc("e8705a"))
                leaves.set(x, y, hexc("ffb09a"))
                placed.append((x, y))
        c.blit(leaves, 0, 0)
        c.outline(INK)
        c.save(name + ".png")
    # 예전 이름(tree.png)은 넓은 나무와 같게 둔다 (다른 곳에서 쓰는 경우 대비)
    first = TREE_VARIANTS[0]
    c = Canvas(*first[1])
    foot = first[1][1] - 2
    c.ellipse(first[1][0] / 2 + 1, foot + 0.3, first[1][0] * 0.36, 2.2, SOFT_SHADOW)
    c.ellipse(first[1][0] / 2 + 1, foot + 0.2, first[1][0] * 0.2, 1.3, SOFT_SHADOW)
    trunk(c, first[2][0], first[2][1], first[2][2], foot + 1, first[5])
    leaves = Canvas(*first[1])
    canopy(leaves, first[3], 11)
    c.blit(leaves, 0, 0)
    c.outline(INK)
    c.save("tree.png")


def make_undergrowth():
    """숲 가장자리에 섞는 작은 수풀 2종 (지나갈 수 있는 장식). 나무와 같은 잎 표현"""
    for n, lumps in enumerate([[(5, 9, 3.5), (11, 9, 3.5), (8, 7, 4)], [(4, 10, 3), (9, 8, 4), (13, 10, 2.8)]]):
        c = Canvas(T, 13)
        c.ellipse(8.5, 11.6, 6.5, 1.3, SOFT_SHADOW)
        leaves = Canvas(T, 13)
        canopy(leaves, lumps, 70 + n * 9)
        for x, y in ((3, 11), (7, 11), (12, 11)):
            leaves.set(x, y, P["leaf"][1])
        c.blit(leaves, 0, 0)
        c.outline(INK)
        c.save("undergrowth_%d.png" % n)


def make_rock():
    c = Canvas(T, T)
    c.ellipse(8, 13.8, 6.5, 1.6, SOFT_SHADOW)
    s = [hexc("7d6f63"), hexc("9a8b7d"), hexc("b5a696"), hexc("cdbfae"), hexc("e6dccd")]
    blob(c, [(8, 10, 5.2), (5, 11.5, 3.4), (11, 11.5, 3.6)], s)
    c.set(5, 7, s[4]); c.set(6, 7, s[4])
    c.outline(INK)
    g = P["grass"]
    c.set(2, 13, g[2]); c.set(3, 12, g[3]); c.set(4, 13, g[2])
    c.save("rock.png")


# ---------------------------------------------------------------- 건물

def make_house():
    W, H = 64, 48
    c = Canvas(W, H)
    wall, wall_line, wall_shade = hexc("f6e6c8"), hexc("ead4ae"), hexc("dcc29a")
    roof_mid, roof_dark, roof_light = hexc("e07a62"), hexc("bf5f4c"), hexc("f29b80")
    # 벽
    rrect(c, 4, 18, 56, 30, 2, wall)
    for y in range(24, 44, 5):
        c.rect(5, y, 54, 1, wall_line)
    c.rect(4, 42, 56, 6, hexc("e3c9a0"))
    c.rect(4, 42, 56, 1, hexc("cfb085"))
    # 지붕 (둥근 비늘 기와)
    for y in range(1, 23):
        inset = max(0, int(12 - (y - 1) * 0.72))
        x0, x1 = inset, W - inset
        for x in range(x0, x1):
            c.set(x, y, roof_mid)
    for r in range(6):
        y0 = 2 + r * 4
        for x in range(0, W):
            if c.get(x, y0)[3] == 0 and c.get(x, y0 + 3)[3] == 0:
                continue
            local = (x + (r % 2) * 3) % 6
            off = [2, 3, 3, 3, 3, 2][local]
            if c.get(x, y0 + off)[3]:
                c.set(x, y0 + off, roof_dark)
            if local in (1, 2) and c.get(x, y0 + 1)[3]:
                c.set(x, y0 + 1, roof_light)
    rrect(c, 9, 0, 46, 3, 1.5, roof_dark)
    c.rect(11, 0, 42, 1, roof_light)
    c.rect(2, 22, 60, 1, roof_dark)
    c.rect(4, 23, 56, 2, wall_shade)  # 처마 그림자
    # 굴뚝
    rrect(c, 46, 0, 7, 10, 1.5, hexc("c9806a"))
    c.rect(46, 0, 7, 2, hexc("e09a82"))
    c.rect(47, 5, 5, 1, hexc("a9644f"))
    # 문 (아치)
    rrect(c, 26, 29, 12, 19, 5, hexc("8a5a3a"))
    rrect(c, 27, 30, 10, 18, 4.5, hexc("b5784a"))
    c.rect(31, 32, 1, 16, hexc("95603a")); c.rect(32, 32, 1, 16, hexc("c98c5c"))
    c.ellipse(32, 35.5, 2, 2, hexc("a8dcef")); c.set(31, 34, hexc("ffffff"))
    c.rect(34, 40, 2, 2, hexc("f5c542"))
    rrect(c, 24, 46, 16, 2, 1, hexc("d9b98a"))
    c.rect(4, 46, 20, 2, hexc("d6b98c")); c.rect(40, 46, 20, 2, hexc("d6b98c"))  # 벽 밑동 (바닥에 닿는 쪽을 조금 어둡게)
    c.rect(26, 45, 12, 1, hexc("6e452b"))  # 문 아래 그늘
    # 창문 + 커튼 + 화분
    for x in (8, 43):
        rrect(c, x, 27, 13, 10, 2, hexc("fffaf0"))
        rrect(c, x + 1, 28, 11, 8, 1.5, hexc("a8dcef"))
        c.rect(x + 2, 29, 3, 2, hexc("e4f6fc"))
        c.rect(x + 6, 28, 1, 8, hexc("fffaf0")); c.rect(x + 1, 32, 11, 1, hexc("fffaf0"))
        for k in range(3):  # 커튼
            c.set(x + 1 + k, 28 + k, hexc("f6b8a0")); c.set(x + 1, 28 + k, hexc("f6b8a0"))
            c.set(x + 11 - k, 28 + k, hexc("f6b8a0")); c.set(x + 11, 28 + k, hexc("f6b8a0"))
        rrect(c, x - 1, 37, 15, 3, 1, hexc("b5784a"))
        c.rect(x, 37, 13, 1, hexc("d49a68"))
        c.rect(x, 40, 13, 1, wall_shade)  # 화분 받침 아래 그림자
        for i, col in enumerate(["ef7f7a", "f7c548", "f7a8b8", "ef7f7a", "fff6e8", "c9b0ee"]):
            fx = x + 1 + i * 2
            c.set(fx, 36, hexc(col)); c.set(fx + 1, 36, P["leaf"][3])
    c.outline(INK)
    c.save("house.png")


def make_shop():
    W, H = 48, 32
    c = Canvas(W, H)
    w = P["wood"]
    for x in (4, 41):
        rrect(c, x, 9, 3, 14, 1, w[2]); c.rect(x, 10, 1, 12, w[3])
    # 진열대
    rrect(c, 1, 17, 46, 15, 2.5, w[2])
    for x in range(5, 46, 6):
        c.rect(x, 20, 1, 11, w[1])
    c.rect(2, 17, 44, 2, w[3])
    c.rect(2, 19, 44, 1, w[1])
    # 바구니와 작물
    for i, (col, dark) in enumerate([("fbf3f6", "b77fd0"), ("e3bd85", "b88a50"), ("ef5b5b", "c23e4a"), ("f7a24a", "d97a2a")]):
        bx = 4 + i * 10
        rrect(c, bx, 12, 9, 6, 2, hexc("c98c5c"))
        c.rect(bx + 1, 14, 7, 1, hexc("a8714a"))
        for k in range(3):
            gx, gy = bx + 1 + k * 3, 10 + (k % 2)
            c.ellipse(gx + 1, gy + 1, 1.6, 1.6, hexc(col))
            c.set(gx + 1, gy + 2, hexc(dark))
    # 차양 (둥근 물결 끝)
    for x in range(0, W):
        stripe = hexc("ea7d6b") if (x // 6) % 2 == 0 else hexc("fdf3e1")
        for y in range(1, 8):
            c.set(x, y, stripe)
        local = x % 6
        if local in (1, 2, 3, 4):
            c.set(x, 8, stripe)
        if local in (2, 3):
            c.set(x, 9, stripe)
    rrect(c, 0, 0, W, 3, 1.5, hexc("d9604f"))
    # 꼭대기 동전 간판
    c.ellipse(24, 2.5, 3.5, 3.5, hexc("f5c542"))
    c.ellipse(24, 2.5, 2, 2, hexc("ffe07a"))
    c.set(23, 1, hexc("fff6c8"))
    c.outline(INK)
    c.save("shop.png")


def make_shop_decor():
    w = P["wood"]
    c = Canvas(T, T)  # 나무통
    c.ellipse(8, 14.5, 6, 1.4, SOFT_SHADOW)
    rrect(c, 3, 3, 10, 12, 3, w[2])
    c.rect(4, 4, 2, 10, w[3]); c.rect(11, 4, 1, 10, w[1])
    for y in (5, 11):
        c.rect(3, y, 10, 1, hexc("9a8a78"))
    c.ellipse(8, 3.5, 4.5, 1.5, w[1])
    c.outline(INK)
    c.save("barrel.png")
    c = Canvas(T, T)  # 사과 상자
    c.ellipse(8, 14.5, 7, 1.4, SOFT_SHADOW)
    rrect(c, 2, 6, 12, 9, 1.5, w[2])
    c.rect(3, 9, 10, 1, w[1]); c.rect(3, 12, 10, 1, w[1]); c.rect(3, 7, 10, 1, w[3])
    for x in (4, 7, 10):
        c.ellipse(x + 1, 5.5, 1.7, 1.7, hexc("e8705a")); c.set(x, 4, hexc("ffb09a"))
    c.outline(INK)
    c.save("crate.png")
    c = Canvas(T, T)  # 꽃 화분
    c.ellipse(8, 14.5, 5, 1.3, SOFT_SHADOW)
    rrect(c, 4, 9, 8, 6, 1.5, hexc("d98a62"))
    c.rect(4, 9, 8, 1, hexc("eba67e"))
    leaves = Canvas(T, T)
    blob(leaves, [(8, 6, 4), (5.5, 7.5, 2.6), (10.5, 7.5, 2.6)], P["leaf"], outline=P["leaf"][0])
    for x, y, col in ((6, 4, "f4b4c0"), (10, 6, "fff6e8"), (8, 7, "f7c548")):
        leaves.set(x, y, hexc(col))
    c.blit(leaves, 0, 0)
    c.outline(INK)
    c.save("flowerpot.png")
    c = Canvas(T, 24)  # 간판
    c.ellipse(8, 22.5, 5, 1.3, SOFT_SHADOW)
    c.rect(7, 10, 2, 13, w[1])
    rrect(c, 1, 2, 14, 10, 2, w[3])
    rrect(c, 2, 3, 12, 8, 1.5, hexc("fbeccf"))
    c.ellipse(5.5, 7, 2.2, 2.2, hexc("f5c542")); c.set(5, 6, hexc("fff3b0"))
    c.ellipse(10.5, 7.5, 2.2, 2, hexc("fbf3f6")); c.ellipse(10.5, 6.3, 2, 1, hexc("b77fd0"))
    c.outline(INK)
    c.save("sign.png")
    c = Canvas(T, T)  # 둥근 덤불 (산딸기) — 나무와 같은 잎 뭉치 표현
    c.ellipse(8.5, 14.4, 6.5, 1.5, SOFT_SHADOW)
    leaves = Canvas(T, T)
    canopy(leaves, [(4.5, 11, 3.5), (11.5, 11, 3.5), (8, 9, 4.8)], 41)
    for x, y in ((5, 9), (10, 8), (8, 12)):
        leaves.set(x, y, hexc("d9536a")); leaves.set(x + 1, y, hexc("f08a9a"))
    c.blit(leaves, 0, 0)
    c.outline(INK)
    c.save("bush.png")
    c = Canvas(T, 24)  # 어린 나무 — 나무와 같은 잎 뭉치 표현
    c.ellipse(8.5, 22.5, 5.5, 1.4, SOFT_SHADOW)
    c.rect(7, 13, 2, 10, w[1]); c.set(7, 14, w[2]); c.set(8, 18, w[0]); c.rect(6, 21, 4, 1, w[1])
    leaves = Canvas(T, 24)
    canopy(leaves, [(5, 11, 3.4), (11, 11, 3.4), (8, 7, 4.6), (8, 11.5, 3.6)], 53)
    c.blit(leaves, 0, 0)
    c.outline(INK)
    c.save("young_tree.png")
    c = Canvas(T, T)  # 갈대 (물가)
    for x, h, top in ((4, 8, 1), (7, 11, 1), (10, 9, 1), (12, 6, 0)):
        c.rect(x, 15 - h, 1, h, P["leaf"][2])
        c.set(x, 15 - h + 1, P["leaf"][3])
        if top:
            c.rect(x - 1 + (x % 2), 15 - h - 2, 2, 3, hexc("a8714a"))
    c.outline(P["leaf"][0])
    c.save("reeds.png")
    c = Canvas(12, 4)  # 캐릭터 발밑 그림자
    c.ellipse(6, 2, 5.5, 1.8, (91, 58, 41, 70))
    c.save("shadow.png")


# ---------------------------------------------------------------- 광장 시설 (판매대, 분수, 게시판, 벤치, 가로등)

def make_plaza_props():
    w = P["wood"]
    # 작물 판매처: 초록 차양 + 저울 + 수확물 상자
    W, H = 48, 32
    c = Canvas(W, H)
    for x in (4, 41):
        rrect(c, x, 9, 3, 14, 1, w[2]); c.rect(x, 10, 1, 12, w[3])
    rrect(c, 1, 17, 46, 15, 2.5, w[2])
    for x in range(5, 46, 6):
        c.rect(x, 20, 1, 11, w[1])
    c.rect(2, 17, 44, 2, w[3]); c.rect(2, 19, 44, 1, w[1])
    # 저울
    c.rect(10, 9, 1, 8, hexc("8a7a6a"))
    c.rect(6, 9, 9, 1, hexc("8a7a6a"))
    c.ellipse(7, 12, 2.5, 1, hexc("d9c9b0")); c.ellipse(14, 11, 2.5, 1, hexc("d9c9b0"))
    c.ellipse(7, 11, 1.4, 1.2, hexc("ef5b5b"))
    # 수확물 상자
    for i, (col, dark) in enumerate([("e0b97f", "b88a50"), ("fbf3f6", "b77fd0"), ("ef5b5b", "c23e4a")]):
        bx = 19 + i * 8
        rrect(c, bx, 12, 7, 6, 1.5, hexc("c98c5c"))
        for k in range(2):
            c.ellipse(bx + 2 + k * 3, 11.5, 1.6, 1.6, hexc(col)); c.set(bx + 2 + k * 3, 12, hexc(dark))
    # 차양 (초록 줄무늬)
    for x in range(0, W):
        stripe = hexc("7fb069") if (x // 6) % 2 == 0 else hexc("fdf3e1")
        for y in range(1, 8):
            c.set(x, y, stripe)
        local = x % 6
        if local in (1, 2, 3, 4):
            c.set(x, 8, stripe)
        if local in (2, 3):
            c.set(x, 9, stripe)
    rrect(c, 0, 0, W, 3, 1.5, hexc("5f9050"))
    c.ellipse(24, 2.5, 3.5, 3.5, hexc("f5c542")); c.ellipse(24, 2.5, 2, 2, hexc("ffe07a")); c.set(23, 1, hexc("fff6c8"))
    c.outline(INK)
    c.save("sell_stand.png")

    # 분수 (광장 한가운데)
    c = Canvas(32, 32)
    c.ellipse(16, 27, 14, 4, SOFT_SHADOW)
    st = P["stone"]
    c.ellipse(16, 22, 14, 7, st[1])
    c.ellipse(16, 21, 14, 6.5, st[2])
    c.ellipse(16, 21.5, 11.5, 4.6, P["water"][1])
    c.ellipse(13, 20.5, 5, 1.6, P["water"][2])
    for x, y in ((9, 21), (21, 23), (15, 19)):
        c.set(x, y, P["water"][3])
    rrect(c, 13, 9, 6, 12, 2, st[2])
    c.rect(14, 10, 1, 10, st[3])
    c.ellipse(16, 9, 5, 2, st[1]); c.ellipse(16, 8.5, 4, 1.4, P["water"][2])
    for dx, h in ((-4, 4), (4, 4), (0, 6)):
        for k in range(h):
            c.set(16 + dx * k // h, 8 - k + (k * k) // 6, P["water"][3])
    c.outline(INK)
    c.save("fountain.png")

    # 퀘스트 게시판
    c = Canvas(32, 24)
    c.ellipse(16, 22.5, 12, 1.5, SOFT_SHADOW)
    for x in (4, 26):
        c.rect(x, 4, 2, 19, w[1])
    rrect(c, 1, 2, 30, 15, 2, w[2])
    rrect(c, 3, 4, 26, 11, 1, hexc("c98c5c"))
    for x, y, col in ((5, 5, "fbeccf"), (13, 6, "fff6e8"), (21, 5, "fbeccf")):
        c.rect(x, y, 6, 8, hexc(col)); c.set(x + 2, y, hexc("e0715f"))
        c.rect(x + 1, y + 3, 4, 1, hexc("d9c9b0")); c.rect(x + 1, y + 5, 3, 1, hexc("d9c9b0"))
    rrect(c, 8, 0, 16, 4, 1.5, w[3])
    c.outline(INK)
    c.save("board.png")

    # 벤치
    c = Canvas(T * 2, T)
    c.ellipse(16, 14.5, 13, 1.4, SOFT_SHADOW)
    for x in (4, 26):
        c.rect(x, 9, 2, 6, w[1])
    rrect(c, 2, 8, 28, 3, 1, w[2]); c.rect(3, 8, 26, 1, w[3])
    rrect(c, 2, 3, 28, 4, 1, w[2]); c.rect(3, 3, 26, 1, w[3]); c.rect(3, 5, 26, 1, w[1])
    c.outline(INK)
    c.save("bench.png")

    # 가로등
    c = Canvas(T, 32)
    c.ellipse(8, 30.5, 5, 1.3, SOFT_SHADOW)
    c.rect(7, 9, 2, 22, hexc("6b5a4a")); c.rect(7, 9, 1, 22, hexc("8a7a6a"))
    rrect(c, 5, 28, 6, 3, 1, hexc("6b5a4a"))
    rrect(c, 4, 2, 8, 8, 2, hexc("6b5a4a"))
    rrect(c, 5, 3, 6, 6, 1.5, hexc("ffe9a6"))
    c.rect(6, 4, 2, 2, hexc("fff8e0"))
    c.rect(5, 1, 6, 2, hexc("6b5a4a"))
    c.outline(INK)
    c.save("lamp.png")


# ---------------------------------------------------------------- 설치 시설 (data/placeables.json 의 그림)
# 그림의 아래쪽 size 칸만큼이 바닥을 차지하고, 그 위는 위로 솟는 부분이다.

def make_placeables():
    w = P["wood"]
    # 허수아비 (1x1, 그림 16x26)
    c = Canvas(T, 26)
    c.ellipse(8, 24.5, 5, 1.3, SOFT_SHADOW)
    c.rect(7, 9, 2, 16, w[1])
    c.rect(1, 12, 14, 2, w[1])
    rrect(c, 4, 11, 8, 8, 2, hexc("8fb7d9"))          # 옷
    c.rect(4, 15, 8, 1, hexc("e0715f"))
    for x, y in ((2, 14), (13, 14)):
        c.set(x, y, hexc("f6d06e")); c.set(x, y + 1, hexc("f6d06e"))  # 손 짚
    c.ellipse(8, 7, 3.6, 3.6, hexc("f2e2b8"))         # 자루 얼굴
    c.set(7, 7, INK); c.set(9, 7, INK); c.rect(7, 9, 3, 1, hexc("c98f5e"))
    rrect(c, 2, 3, 12, 2, 1, hexc("f6d06e"))          # 밀짚모자
    rrect(c, 5, 0, 6, 4, 1.5, hexc("f6d06e"))
    c.rect(5, 3, 6, 1, hexc("e0715f"))
    c.outline(INK)
    c.save("scarecrow.png")

    # 나무 창고 (2x2, 그림 32x40)
    c = Canvas(32, 40)
    c.ellipse(16, 38.5, 15, 1.6, SOFT_SHADOW)
    rrect(c, 2, 16, 28, 23, 1.5, w[2])
    for x in range(5, 30, 4):
        c.rect(x, 17, 1, 21, w[1])
    c.rect(2, 16, 28, 1, w[3])
    # 지붕 (초록 지붕널)
    roof, roof_d, roof_l = hexc("7fb069"), hexc("5f9050"), hexc("a6cf8c")
    for y in range(2, 18):
        inset = max(0, int(9 - (y - 2) * 0.75))
        for x in range(inset, 32 - inset):
            c.set(x, y, roof_d if (y - 2) % 4 == 3 else roof)
    rrect(c, 7, 0, 18, 3, 1.5, roof_d)
    c.rect(8, 0, 16, 1, roof_l)
    # 문 (두 짝)
    rrect(c, 10, 24, 12, 15, 1.5, w[0])
    rrect(c, 11, 25, 10, 14, 1, w[1])
    c.rect(16, 25, 1, 14, w[0])
    for x0, x1 in ((11, 15), (17, 21)):
        for k in range(5):
            c.set(x0 + k, 26 + k * 2, w[3])
    c.set(14, 32, hexc("f5c542")); c.set(18, 32, hexc("f5c542"))
    # 작은 창
    rrect(c, 4, 21, 5, 4, 1, hexc("a8dcef")); c.set(5, 22, hexc("e4f6fc"))
    rrect(c, 23, 21, 5, 4, 1, hexc("a8dcef")); c.set(24, 22, hexc("e4f6fc"))
    c.outline(INK)
    c.save("shed.png")


# ---------------------------------------------------------------- 퇴비통 (2x1칸, 그림 32x28)

def make_compost_bin():
    w = P["wood"]
    c = Canvas(32, 28)
    c.ellipse(16, 26.5, 15, 1.4, SOFT_SHADOW)
    # 나무판을 엮은 상자 (앞면)
    rrect(c, 2, 11, 28, 16, 1.5, w[1])
    for y in range(12, 26, 4):
        c.rect(3, y, 26, 3, w[2])
        c.rect(3, y, 26, 1, w[3])
    for x in (2, 15, 28):
        c.rect(x, 9, 2, 18, w[0])
        c.rect(x, 9, 1, 18, w[1])
    # 위에서 들여다본 퇴비 더미 (짙은 흙 + 풀잎 조각)
    c.ellipse(16, 10, 13.5, 4.2, w[0])
    c.ellipse(16, 9.5, 12, 3.2, hexc("5a3d28"))
    c.ellipse(13, 8.5, 6, 1.8, hexc("6e4a30"))
    for x, y, col in ((9, 9, "7fb069"), (14, 8, "a6cf8c"), (20, 10, "7fb069"), (23, 9, "e3c45a"), (17, 11, "8a6044"), (11, 11, "a6cf8c")):
        c.set(x, y, hexc(col)); c.set(x + 1, y, hexc(col))
    c.outline(INK)
    c.save("compost_bin.png")


# ---------------------------------------------------------------- 스프링클러·자동 수확기 (1x1칸, 하급·중급·상급)
#   단계 색: 하급 구리 / 중급 은 / 상급 금. 밭 사이에 놓이는 작은 기계

TIER_METAL = {
    1: (hexc("d98c4f"), hexc("a8643a"), hexc("f2b98a")),   # 구리
    2: (hexc("c9d3dc"), hexc("94a3b2"), hexc("eef3f7")),   # 은
    3: (hexc("f2c443"), hexc("c9922a"), hexc("fbe39a")),   # 금
}


def make_sprinklers():
    """16x20: 나무 말뚝 위 둥근 분사 머리 + 물방울"""
    w = P["wood"]
    for tier, (m, md, ml) in TIER_METAL.items():
        c = Canvas(T, 20)
        c.ellipse(8, 18.5, 5, 1.3, SOFT_SHADOW)
        c.rect(7, 11, 2, 8, w[1])
        c.rect(7, 11, 1, 8, w[2])
        rrect(c, 3, 7, 10, 5, 2, m)
        c.rect(4, 10, 8, 1, md)
        c.rect(5, 8, 3, 1, ml)
        rrect(c, 6, 4, 4, 4, 1, m)
        c.set(7, 5, ml)
        # 단계만큼 노즐 (하급 1 · 중급 2 · 상급 3)
        for k in range(tier):
            x = 8 - tier + 2 * k
            c.set(x, 3, md); c.set(x, 2, md)
        c.outline(INK)
        for x, y in ((1, 2), (14, 3), (2, 6), (13, 7)):
            c.set(x, y, hexc("7cc4e6"))
        c.set(1, 3, hexc("c2ecfa")); c.set(14, 4, hexc("c2ecfa"))
        c.save(f"sprinkler_{tier}.png")


def make_harvesters():
    """16x22: 초록 몸통 + 단계 색 집게 팔 + 앞(아래)쪽 배출구"""
    green, green_d, green_l = hexc("7fb069"), hexc("5f9050"), hexc("a6cf8c")
    for tier, (m, md, ml) in TIER_METAL.items():
        c = Canvas(T, 22)
        c.ellipse(8, 20.5, 6.5, 1.4, SOFT_SHADOW)
        rrect(c, 2, 9, 12, 11, 2, green)
        c.rect(3, 18, 10, 1, green_d)
        c.rect(4, 10, 6, 1, green_l)
        # 창 (안에 거둔 작물이 보이는 느낌)
        rrect(c, 5, 12, 6, 4, 1, hexc("fbeccf"))
        c.set(6, 13, hexc("e0715f")); c.set(8, 14, hexc("f2c443")); c.set(9, 13, hexc("7fb069"))
        # 배출구 (앞쪽)
        rrect(c, 6, 18, 4, 3, 1, md)
        # 집게 팔
        c.rect(7, 3, 2, 7, md)
        c.rect(7, 3, 1, 7, m)
        rrect(c, 3, 1, 10, 3, 1, m)
        c.rect(4, 1, 7, 1, ml)
        for x in (3, 12):
            c.rect(x, 3, 1, 3, md)
        # 단계 별 (하급 1 · 중급 2 · 상급 3)
        for k in range(tier):
            c.set(4 + k * 2, 16, m)
        c.outline(INK)
        c.save(f"harvester_{tier}.png")


# ---------------------------------------------------------------- 컨베이어 (1x1칸, conveyor.png 64x48)
#   줄: 0 직선 / 1 왼쪽에서 들어와 아래로 꺾임 / 2 오른쪽에서 들어와 아래로 꺾임. 칸: 무늬가 흐르는 4장
#   모두 회전 0(아래로 흐름) 기준이고 게임에서 90°씩 돌려 쓴다. 양옆 나무 난간 + 가운데 짙은 벨트 + 흐르는 V 무늬

BELT_RAIL = (P["wood"][0], P["wood"][2])          # 바깥쪽, 안쪽
BELT = (hexc("7d6656"), hexc("6e5848"))            # 벨트 바탕, 이음매
BELT_MARK = hexc("e6cfa4")


def belt_pixel(a, s, frame, thick=False):
    """벨트 가로 위치 a(0~16, 난간 포함)와 흐름 위치 s(0~16)의 색. 없으면 None.
    thick: 꺾인 칸은 V 무늬가 곡선을 따라 휘며 끊어지므로 흐름 방향으로 2픽셀 두께로 그린다"""
    if a < 1 or a >= 15:
        return None
    if a < 2 or a >= 14:
        return BELT_RAIL[0]
    if a < 3 or a >= 13:
        return BELT_RAIL[1]
    d = int(abs(a - 8) // 1)                       # 가운데에서 떨어진 정도 0~4
    along = int(s // 1) - frame * 2
    if d <= 3 and (along - (3 - d)) % 8 in ((0, 1) if thick else (0,)):
        return BELT_MARK
    return BELT[1] if (int(s // 1) - frame * 2) % 8 == 7 else BELT[0]


def make_conveyor():
    atlas = Canvas(4 * T, 3 * T)
    for frame in range(4):
        # 직선: a = x, s = y
        c, done = sub(atlas, frame, 0)
        for y in range(T):
            for x in range(T):
                c.set(x, y, belt_pixel(x + 0.5, y + 0.5, frame))
        done()
        # 왼쪽에서 들어와 아래로: 왼쪽 아래 모서리를 축으로 한 4분의 1 원. a = 축에서 거리, s = 각도(0 왼쪽 → 16 아래)
        c, done = sub(atlas, frame, 1)
        for y in range(T):
            for x in range(T):
                vx, vy = x + 0.5, y + 0.5 - T
                r = math.hypot(vx, vy)
                s = math.atan2(vx, -vy) / (math.pi / 2) * T
                c.set(x, y, belt_pixel(r, s, frame, thick=True))
        done()
        # 오른쪽에서 들어와 아래로: 위 그림을 좌우로 뒤집은 것
        c2, done = sub(atlas, frame, 2)
        for y in range(T):
            for x in range(T):
                c2.set(x, y, c.get(T - 1 - x, y))
        done()
    atlas.save("conveyor.png")


# ---------------------------------------------------------------- 창고 (4x4칸, 그림 64x84)
#   돌 기초 + 세로 판자 벽 + 박공지붕(남색 지붕널) + 가운데 큰 미닫이문 + 옆에 쌓인 상자

def make_warehouse():
    w = P["wood"]
    c = Canvas(64, 84)
    c.ellipse(32, 82.5, 31, 1.8, SOFT_SHADOW)
    # 벽 (세로 판자)
    rrect(c, 3, 34, 58, 46, 1.5, w[2])
    for x in range(6, 60, 4):
        c.rect(x, 35, 1, 42, w[1])
    c.rect(3, 34, 58, 1, w[3])
    # 돌 기초
    stone, stone_d, stone_l = hexc("b8b0a4"), hexc("8f877c"), hexc("d6cfc4")
    c.rect(2, 76, 60, 6, stone)
    for i, x in enumerate(range(2, 62, 6)):
        c.rect(x, 76 + (i % 2) * 3, 1, 3, stone_d)
    c.rect(2, 79, 60, 1, stone_d)
    c.rect(2, 76, 60, 1, stone_l)
    # 박공지붕 (남색 지붕널, 처마가 벽보다 조금 넓다)
    roof, roof_d, roof_l = hexc("6f8fb5"), hexc("4f6d92"), hexc("9db8d6")
    for y in range(4, 38):
        inset = max(0, int(24 - (y - 4) * 0.75))
        for x in range(inset, 64 - inset):
            c.set(x, y, roof_d if (y - 4) % 5 == 4 else roof)
    rrect(c, 22, 1, 20, 4, 1.5, roof_d)
    c.rect(23, 1, 18, 1, roof_l)
    c.rect(0, 37, 64, 1, roof_d)
    # 박공 아래 둥근 환기창
    c.ellipse(32, 26, 4.5, 4.5, w[0])
    c.ellipse(32, 26, 3.4, 3.4, hexc("a8dcef"))
    c.rect(31, 23, 1, 6, w[0]); c.rect(29, 26, 6, 1, w[0])
    c.set(30, 24, hexc("e4f6fc"))
    # 큰 미닫이문 (두 짝 + X 버팀목) 과 문 위 레일
    c.rect(16, 44, 32, 2, hexc("6d6259"))
    rrect(c, 18, 46, 28, 30, 1, w[0])
    for x0 in (19, 33):
        rrect(c, x0, 47, 12, 29, 1, w[1])
        for k in range(12):
            c.set(x0 + k, 48 + int(k * 2.3), w[3])
            c.set(x0 + 11 - k, 48 + int(k * 2.3), w[3])
    c.rect(32, 47, 1, 29, w[0])
    c.set(30, 62, hexc("f5c542")); c.set(34, 62, hexc("f5c542"))
    # 작은 창 두 개
    for x in (6, 50):
        rrect(c, x, 48, 8, 7, 1, w[0])
        rrect(c, x + 1, 49, 6, 5, 1, hexc("a8dcef"))
        c.rect(x + 4, 49, 1, 5, w[0])
        c.set(x + 2, 50, hexc("e4f6fc"))
    # 왼쪽 앞 상자 더미
    for x, y in ((4, 68), (11, 68), (7, 61)):
        rrect(c, x, y, 8, 8, 1, hexc("d9a066"))
        c.rect(x + 1, y + 1, 6, 1, hexc("f0c48a"))
        c.rect(x + 1, y + 4, 6, 1, hexc("b07a45"))
    # 오른쪽 앞 자루
    c.ellipse(55, 72, 4.5, 4, hexc("e8d6ae"))
    c.ellipse(55, 68, 2.5, 1.5, hexc("cbb488"))
    c.set(54, 71, hexc("f6ecd2"))
    c.outline(INK)
    c.save("warehouse.png")


# ---------------------------------------------------------------- 수동 가공기 (2x2칸, 그림 32x40)
#   나무 작업대 위에 손잡이를 돌리는 맷돌(왼쪽)과 작은 솥(오른쪽)

def make_processor():
    w = P["wood"]
    c = Canvas(32, 40)
    c.ellipse(16, 38.5, 15, 1.6, SOFT_SHADOW)
    # 작업대 다리와 아래 선반
    for x in (3, 26):
        c.rect(x, 24, 3, 15, w[0])
        c.rect(x, 24, 1, 15, w[1])
    rrect(c, 4, 31, 24, 3, 1, w[1])
    c.rect(5, 31, 22, 1, w[3])
    # 선반 위 자루
    c.ellipse(10, 29, 3.5, 2.5, hexc("efe2c4"))
    c.set(9, 28, hexc("fffaf0"))
    # 상판
    rrect(c, 1, 20, 30, 6, 1.5, w[2])
    c.rect(2, 20, 28, 1, w[3])
    c.rect(2, 24, 28, 1, w[1])
    # 맷돌 (돌 두 단 + 손잡이)
    st = [hexc("8f877c"), hexc("b8b0a4"), hexc("d6cfc4")]
    c.ellipse(9, 18, 6.5, 2.6, st[0])
    rrect(c, 3, 13, 13, 6, 2, st[1])
    c.ellipse(9, 13, 6.5, 2.4, st[2])
    c.ellipse(9, 13, 1.6, 0.9, st[0])
    c.rect(14, 10, 1, 4, w[0])
    rrect(c, 13, 7, 3, 4, 1, hexc("e0715f"))
    # 솥 (구리색) + 김
    cu, cu_d, cu_l = hexc("d08a4e"), hexc("a8692e"), hexc("eab676")
    c.ellipse(24, 19, 5.5, 2, cu_d)
    rrect(c, 18, 13, 12, 7, 3, cu)
    c.ellipse(24, 13, 6, 2, cu_d)
    c.ellipse(24, 13, 4.6, 1.3, hexc("f29a3a"))
    c.rect(19, 15, 1, 3, cu_l)
    for x, y in ((22, 9), (23, 7), (25, 8), (26, 5)):
        c.set(x, y, hexc("fffaf0"))
    c.outline(INK)
    c.save("processor.png")


# ---------------------------------------------------------------- 소형 발전기 (2x2칸, 그림 32x40)
#   초록 철제 상자 + 배기통 + 앞면 번개 표시 + 계기판

def make_generator():
    body, body_d, body_l = hexc("6f9a6a"), hexc("517a4e"), hexc("9cc394")
    metal, metal_d = hexc("b8b0a4"), hexc("8f877c")
    c = Canvas(32, 40)
    c.ellipse(16, 38.5, 15, 1.6, SOFT_SHADOW)
    # 받침
    rrect(c, 1, 33, 30, 5, 1, metal_d)
    c.rect(2, 33, 28, 1, metal)
    # 몸통
    rrect(c, 3, 14, 26, 20, 2, body)
    c.rect(4, 14, 24, 2, body_l)
    c.rect(4, 31, 24, 2, body_d)
    for y in (18, 22, 26):
        c.rect(19, y, 8, 1, body_d)   # 환기구
    # 번개 표시 (노란 원판)
    c.ellipse(11, 23, 5, 5, hexc("f5d76e"))
    for x, y in ((12, 19), (11, 20), (10, 21), (10, 22), (11, 22), (12, 22), (12, 23), (11, 24), (10, 25), (10, 26)):
        c.set(x, y, hexc("5b3a29"))
    # 배기통 + 연기
    c.rect(22, 5, 4, 10, metal_d)
    c.rect(22, 5, 1, 10, metal)
    rrect(c, 21, 3, 6, 3, 1, metal)
    for x, y in ((23, 1), (25, 0)):
        c.set(x, y, hexc("e6dccd"))
    # 계기판
    rrect(c, 5, 8, 10, 7, 1.5, metal)
    c.ellipse(10, 11.5, 3, 2.5, hexc("fbf0da"))
    c.set(10, 11, hexc("c0503a")); c.set(11, 10, hexc("c0503a"))
    c.outline(INK)
    c.save("generator.png")


# ---------------------------------------------------------------- 전기 가공기 (3x3칸, 그림 48x60)
#   남색 철제 기계 + 위 깔때기(투입구) + 가운데 창 + 옆 배출구 + 번개 표시

def make_electric_processor():
    body, body_d, body_l = hexc("6f8fb5"), hexc("4f6d92"), hexc("9db8d6")
    metal, metal_d = hexc("b8b0a4"), hexc("8f877c")
    c = Canvas(48, 60)
    c.ellipse(24, 58.5, 23, 1.8, SOFT_SHADOW)
    rrect(c, 1, 52, 46, 6, 1, metal_d)
    c.rect(2, 52, 44, 1, metal)
    # 몸통
    rrect(c, 3, 22, 42, 31, 2.5, body)
    c.rect(4, 22, 40, 2, body_l)
    c.rect(4, 50, 40, 2, body_d)
    # 위 깔때기
    for y in range(6, 23):
        inset = max(0, (22 - y) // 2)
        c.rect(12 + (y - 6) // 3, y, 24 - 2 * ((y - 6) // 3), 1, metal if y % 4 else metal_d)
    rrect(c, 9, 3, 30, 5, 1.5, metal)
    c.rect(10, 3, 28, 1, hexc("d6cfc4"))
    # 들여다보는 창 + 안의 내용물
    rrect(c, 9, 28, 20, 14, 2, metal_d)
    rrect(c, 11, 30, 16, 10, 2, hexc("a8dcef"))
    c.ellipse(19, 38, 6, 2.2, hexc("f0c48a"))
    c.set(13, 31, hexc("e4f6fc")); c.set(14, 31, hexc("e4f6fc"))
    # 번개 판 + 불빛
    rrect(c, 32, 28, 10, 10, 1.5, hexc("f5d76e"))
    for x, y in ((38, 29), (37, 30), (36, 31), (35, 32), (36, 32), (37, 32), (38, 33), (37, 34), (36, 35), (35, 36)):
        c.set(x, y, hexc("5b3a29"))
    c.ellipse(34, 44, 1.6, 1.6, hexc("8fd16a"))
    c.ellipse(39, 44, 1.6, 1.6, hexc("f29a3a"))
    # 아래 배출구
    rrect(c, 13, 45, 14, 6, 1, body_d)
    c.rect(14, 46, 12, 1, hexc("3b4f6b"))
    c.outline(INK)
    c.save("electric_processor.png")


# ---------------------------------------------------------------- 온실 (8x7칸, 그림 128x132)
#   지붕 없이 유리벽만 그린다 (안쪽 밭이 보이게). 게임에서는 뒷벽(위 36px)·옆벽·앞벽(아래 16px)으로 잘라 쓴다:
#   위 20px 는 발자리 위로 솟은 뒷벽, 그 아래 한 줄(16px)이 뒷벽 자리, 맨 아래 한 줄이 앞벽, 양옆 16px 가 옆벽.

GH_W, GH_H, GH_ROOF = 8, 7, 20


def glass_panel(c, x, y, w, h):
    """유리 칸: 옅은 하늘색 반투명 + 비스듬한 반사광"""
    glass, light = hexc("bfe6f2", 210), hexc("ffffff", 190)
    c.rect(x, y, w, h, glass)
    for k in range(0, w + h, 9):
        for t in range(3):
            xx, yy = x + k - t, y + t
            if x <= xx < x + w and y <= yy < y + h:
                c.set(xx, yy, light)


def make_greenhouse():
    W, H, R = GH_W * T, GH_H * T, GH_ROOF
    frame, shade = hexc("f4f1e6"), hexc("cfc6b0")
    st = P["stone"]
    c = Canvas(W, H + R)
    # 뒷벽: 위쪽 끝이 둥근 큰 유리벽 + 돌 기초
    rrect(c, 1, 2, W - 2, R + T - 2, 3, frame)
    glass_panel(c, 3, 5, W - 6, R + T - 11)
    for x in range(1, W, 16):
        c.rect(x, 4, 2, R + T - 8, frame)
    c.rect(1, 17, W - 2, 2, frame)
    c.rect(4, 2, W - 8, 1, hexc("ffffff"))
    c.rect(1, R + T - 5, W - 2, 5, st[1])
    c.rect(1, R + T - 5, W - 2, 1, st[2])
    for x in range(6, W - 2, 10):
        c.set(x, R + T - 2, st[0])
    # 옆벽 (위에서 내려다본 낮은 유리벽)
    for x0 in (1, W - T + 1):
        top = R + T
        c.rect(x0, top, T - 2, H - 2 * T, frame)
        glass_panel(c, x0 + 3, top, T - 8, H - 2 * T)
        c.rect(x0 + T - 4, top, 1, H - 2 * T, shade)
        for y in range(top + 14, top + H - 2 * T, 16):
            c.rect(x0, y, T - 2, 2, frame)
    # 앞벽: 낮은 유리벽 + 돌 기초, 가운데 문 (두 칸)
    y0 = R + H - T
    door0, door1 = (GH_W - 2) // 2 * T, (GH_W - 2) // 2 * T + 2 * T
    for x_from, x_to in ((1, door0 - 1), (door1 + 1, W - 1)):
        c.rect(x_from, y0, x_to - x_from, 3, frame)
        glass_panel(c, x_from, y0 + 3, x_to - x_from, 8)
        for x in range(x_from, x_to, 16):
            c.rect(x, y0 + 3, 2, 8, frame)
        c.rect(x_to - 2, y0 + 3, 2, 8, frame)
        c.rect(x_from, y0 + 11, x_to - x_from, 5, st[1])
        c.rect(x_from, y0 + 11, x_to - x_from, 1, st[2])
    # 문틀 기둥 (문 칸은 비워 둔다. 앞벽 줄 안에만 그려야 게임에서 잘리지 않는다)
    for x in (door0 - 3, door1 + 1):
        c.rect(x, y0, 3, 16, frame)
        c.rect(x + 2, y0, 1, 16, shade)
    c.outline(INK)
    # 문턱 돌 (외곽선 없이 바닥에 깔린 느낌)
    for x in range(door0 + 2, door1 - 2, 7):
        rrect(c, x, y0 + 12, 6, 3, 1, st[2])
    c.save("greenhouse.png")


# ---------------------------------------------------------------- 우물 (농장 물 긷는 곳, 2x2칸, 그림 32x40)

def make_well():
    w, st, wa = P["wood"], P["stone"], P["water"]
    c = Canvas(32, 40)
    c.ellipse(16, 38.5, 15, 1.6, SOFT_SHADOW)
    # 돌을 둥글게 쌓은 몸통
    rrect(c, 3, 24, 26, 15, 3, st[1])
    for row, y in enumerate(range(28, 38, 4)):
        c.rect(4, y, 24, 1, st[0])
        for x in range(4 if row % 2 else 8, 28, 8):
            c.rect(x, y + 1, 1, 3, st[0])
    # 나무 기둥 두 개
    for x in (4, 25):
        c.rect(x, 8, 3, 18, w[1])
        c.rect(x + 1, 8, 1, 18, w[2])
    # 위에서 본 우물 입구 (돌 테두리 + 물)
    c.ellipse(16, 25, 12.5, 3.8, st[2])
    c.rect(6, 23, 20, 1, st[3])
    c.ellipse(16, 25.5, 9.5, 2.3, wa[0])
    c.rect(12, 25, 6, 1, wa[2])
    # 도르래 가로대, 밧줄, 두레박
    c.rect(6, 11, 20, 2, w[0])
    c.ellipse(16, 12, 2, 2, w[2])
    c.rect(15, 14, 1, 5, hexc("e8d3a8"))
    rrect(c, 12, 18, 7, 6, 1.5, w[2])
    c.rect(12, 20, 7, 1, w[0])
    c.rect(13, 18, 5, 1, w[3])
    # 지붕 (집과 같은 붉은 지붕)
    roof, roof_d, roof_l = hexc("e07a62"), hexc("bf5f4c"), hexc("f29b80")
    for y in range(0, 10):
        inset = max(0, int(10 - y * 1.2))
        for x in range(inset, 32 - inset):
            c.set(x, y, roof_d if y % 3 == 2 else roof)
    c.rect(10, 0, 12, 1, roof_l)
    c.outline(INK)
    c.save("well.png")


# ---------------------------------------------------------------- 출하함 (농장 판매함, 2x1칸, 그림 32x26)

def make_shipping_bin():
    w = P["wood"]
    c = Canvas(32, 26)
    c.ellipse(16, 24.5, 15, 1.4, SOFT_SHADOW)
    # 나무 상자 몸통 (가로 판자)
    rrect(c, 2, 9, 28, 16, 2, w[2])
    for y in (13, 17, 21):
        c.rect(3, y, 26, 1, w[1])
    c.rect(3, 10, 26, 1, w[3])
    # 모서리 쇠붙이
    for x in (3, 26):
        c.rect(x, 11, 3, 13, hexc("b5a696"))
        c.rect(x + 1, 11, 1, 13, hexc("cdbfae"))
    # 살짝 열린 뚜껑
    rrect(c, 1, 3, 30, 7, 2, w[1])
    c.rect(2, 4, 28, 1, w[3])
    c.rect(2, 8, 28, 1, w[0])
    # 앞면 표시: 동전 그림 판
    rrect(c, 11, 14, 10, 7, 1.5, hexc("fbeccf"))
    c.ellipse(16, 17.5, 2.3, 2.3, hexc("f5c542"))
    c.set(15, 16, hexc("fff3c0"))
    c.outline(INK)
    c.save("shipping_bin.png")


# ---------------------------------------------------------------- 대장간 (광장, 3x2칸, 그림 48x44)

def make_blacksmith():
    w = P["wood"]
    st = [hexc("7d6f63"), hexc("9a8b7d"), hexc("b5a696"), hexc("cdbfae"), hexc("e6dccd")]
    c = Canvas(48, 44)
    c.ellipse(24, 42.5, 23, 1.6, SOFT_SHADOW)
    # 돌벽
    rrect(c, 2, 18, 44, 25, 2, st[2])
    for row, y in enumerate(range(21, 42, 4)):
        c.rect(3, y, 42, 1, st[1])
        for x in range(4 if row % 2 else 9, 45, 10):
            c.rect(x, y + 1, 1, 3, st[1])
    # 굴뚝과 연기
    rrect(c, 34, 2, 7, 14, 1, st[1])
    c.rect(34, 2, 7, 2, st[0])
    for x, y, r in ((38, 0.5, 1.6), (35.5, -1, 1.2)):
        c.ellipse(x, y, r, r, hexc("efe7d8"))
    # 지붕 (짙은 청회색 널)
    roof, roof_d, roof_l = hexc("6f7f96"), hexc("56647a"), hexc("93a3b8")
    for y in range(6, 20):
        inset = max(0, int(10 - (y - 6) * 0.8))
        for x in range(inset, 48 - inset):
            c.set(x, y, roof_d if (y - 6) % 4 == 3 else roof)
    c.rect(10, 6, 28, 1, roof_l)
    # 넓은 문 (안에 불빛)
    rrect(c, 17, 27, 14, 16, 2, w[0])
    rrect(c, 18, 28, 12, 15, 1.5, hexc("5b3a29"))
    c.ellipse(24, 38, 4, 3, hexc("f29b50"))
    c.ellipse(24, 38.5, 2, 1.5, hexc("ffd27a"))
    # 모루 간판
    rrect(c, 4, 25, 10, 8, 1.5, w[2])
    c.rect(6, 27, 6, 2, hexc("6f7f96"))
    c.rect(8, 29, 2, 2, hexc("6f7f96"))
    c.rect(6, 31, 6, 1, hexc("56647a"))
    # 창
    rrect(c, 35, 26, 8, 6, 1, hexc("ffd27a")); c.rect(39, 26, 1, 6, w[1])
    c.outline(INK)
    c.save("blacksmith.png")


# ---------------------------------------------------------------- 레시피 상점 (셰프, 광장, 3x2칸, 그림 48x44)
#   크림색 회벽 + 붉은 기와 지붕 + 줄무늬 차양 + 요리사 모자 간판 + 굴뚝 김

def make_recipe_shop():
    w = P["wood"]
    c = Canvas(48, 44)
    c.ellipse(24, 42.5, 23, 1.6, SOFT_SHADOW)
    # 회벽 + 나무 기둥
    rrect(c, 2, 18, 44, 25, 2, hexc("f4e6c8"))
    c.rect(2, 39, 44, 4, hexc("e2cfa6"))
    for x in (2, 44):
        c.rect(x, 18, 2, 25, w[1])
    # 굴뚝과 김
    rrect(c, 8, 3, 6, 13, 1, hexc("c7826a"))
    c.rect(8, 3, 6, 2, hexc("a8654f"))
    for x, y, r in ((11, 1.0, 1.5), (13.5, -0.5, 1.1)):
        c.ellipse(x, y, r, r, hexc("fbf6ec"))
    # 지붕 (붉은 기와)
    roof, roof_d, roof_l = hexc("d9775a"), hexc("b85d44"), hexc("eda083")
    for y in range(6, 20):
        inset = max(0, int(10 - (y - 6) * 0.8))
        for x in range(inset, 48 - inset):
            c.set(x, y, roof_d if (y - 6) % 4 == 3 else roof)
    c.rect(10, 6, 28, 1, roof_l)
    # 줄무늬 차양 (문 위)
    for x in range(14, 34):
        col = hexc("e0715f") if (x // 3) % 2 == 0 else hexc("fff8ea")
        c.rect(x, 22, 1, 4, col)
        c.set(x, 26, col if x % 3 != 2 else CLEAR)
    c.rect(14, 22, 20, 1, hexc("b85d44"))
    # 문
    rrect(c, 18, 28, 12, 15, 2, w[0])
    rrect(c, 19, 29, 10, 14, 1.5, w[2])
    c.rect(24, 29, 1, 14, w[1])
    c.set(22, 36, hexc("f5c542")); c.set(26, 36, hexc("f5c542"))
    # 요리사 모자 간판 (왼쪽)
    rrect(c, 4, 26, 10, 10, 1.5, w[2])
    c.ellipse(9, 29.5, 3.2, 2.2, hexc("ffffff"))
    c.rect(7, 30, 5, 3, hexc("ffffff"))
    c.rect(7, 33, 5, 1, hexc("d9c9a8"))
    # 창 (오른쪽, 따뜻한 불빛 + 화분)
    rrect(c, 35, 27, 8, 7, 1, hexc("ffd27a")); c.rect(39, 27, 1, 7, w[1]); c.rect(35, 30, 8, 1, w[1])
    rrect(c, 34, 34, 10, 3, 1, w[1])
    for x, col in ((36, "7fb069"), (38, "e0715f"), (40, "7fb069"), (42, "f5c542")):
        c.set(x, 33, hexc(col))
    c.outline(INK)
    c.save("recipe_shop.png")


# ---------------------------------------------------------------- 개간 장애물 (data/obstacles.json 의 그림)
# 모두 한 칸을 차지하고, 그림 아래쪽 가운데가 칸 바닥에 놓인다.

def make_obstacles():
    g = P["leaf"]
    w = P["wood"]
    st = [hexc("7d6f63"), hexc("9a8b7d"), hexc("b5a696"), hexc("cdbfae"), hexc("e6dccd")]

    for name, seed in (("weed", 1), ("weed2", 2)):  # 잡초 두 가지 모양
        c = Canvas(T, T)
        r = random.Random(seed)
        for _ in range(7):
            x = r.randrange(3, 13)
            h = r.randrange(4, 9)
            lean = r.choice((-1, 0, 1))
            for k in range(h):
                c.set(x + (lean * k) // 3, 14 - k, g[3] if k > h - 3 else g[2])
        for _ in range(2):
            x, y = r.randrange(4, 12), r.randrange(6, 10)
            c.set(x, y, hexc("e8e0a8")); c.set(x + 1, y, hexc("e8e0a8"))
        c.outline(g[0])
        c.save(f"{name}.png")

    c = Canvas(T, T)  # 작은 돌
    c.ellipse(8, 13.8, 5, 1.2, SOFT_SHADOW)
    blob(c, [(8, 11, 3.8), (6, 12, 2.6), (10.5, 12, 2.4)], st)
    c.set(6, 9, st[4])
    c.outline(INK)
    c.save("small_rock.png")

    c = Canvas(T, T)  # 나뭇가지
    for k in range(11):
        c.set(3 + k, 12 - k // 3, w[2]); c.set(3 + k, 13 - k // 3, w[1])
    for k in range(4):
        c.set(7 + k, 10 - k, w[2])
    c.set(10, 6, g[3]); c.set(11, 6, g[3]); c.set(11, 5, g[2])
    c.outline(INK)
    c.save("branch.png")

    c = Canvas(T, T)  # 그루터기
    c.ellipse(8, 14, 6.5, 1.5, SOFT_SHADOW)
    rrect(c, 3, 7, 10, 8, 2, w[2])
    c.rect(4, 8, 2, 6, w[3]); c.rect(10, 9, 2, 5, w[1])
    c.ellipse(8, 7.5, 5, 2, hexc("e8c48e"))
    c.ellipse(8, 7.5, 2.6, 1, hexc("d4a86c")); c.set(8, 7, w[1])
    c.rect(1, 13, 3, 2, w[1]); c.rect(12, 13, 3, 2, w[1])
    c.outline(INK)
    c.save("stump.png")

    c = Canvas(24, 22)  # 큰 바위 (칸보다 크게 솟음)
    c.ellipse(12, 20, 11, 2, SOFT_SHADOW)
    blob(c, [(12, 12, 8.5), (6.5, 15, 5.5), (17.5, 15, 5.5), (12, 7, 5.5)], st)
    for x, y in ((7, 6), (8, 5), (9, 5)):
        c.set(x, y, st[4])
    c.rect(13, 11, 4, 1, st[0]); c.set(16, 12, st[0])
    for x in (4, 5, 18, 19):
        c.set(x, 20, P["grass"][2])
    c.outline(INK)
    c.save("big_rock.png")

    c = Canvas(24, 22)  # 큰 그루터기
    c.ellipse(12, 20, 11, 2, SOFT_SHADOW)
    rrect(c, 4, 6, 16, 15, 3, w[2])
    c.rect(6, 8, 3, 11, w[3]); c.rect(16, 9, 2, 10, w[1])
    c.ellipse(12, 6.5, 8, 3, hexc("e8c48e"))
    c.ellipse(12, 6.5, 5, 1.8, hexc("d4a86c")); c.ellipse(12, 6.5, 2, 0.8, hexc("c49a5c"))
    c.rect(1, 18, 5, 3, w[1]); c.rect(18, 18, 5, 3, w[1]); c.rect(10, 20, 4, 2, w[1])
    for x, y in ((5, 12), (6, 13), (18, 11)):
        c.set(x, y, P["leaf"][3])
    c.outline(INK)
    c.save("big_stump.png")


# ---------------------------------------------------------------- 플레이어 (16x24, 4프레임 x 3방향, 밀짚모자)

PLAYER_PAL = {
    "o": INK, "h": hexc("8a5a3a"), "H": hexc("a8714a"),
    "s": hexc("ffd8b5"), "S": hexc("f2b894"), "c": hexc("f59a8a"), "e": hexc("4a2e20"),
    "y": hexc("f6d06e"), "Y": hexc("d9a944"), "r": hexc("e0715f"),
    "w": hexc("f08a6c"), "W": hexc("d06f55"), "l": hexc("f8ab8e"),
    "p": hexc("6f97c9"), "P": hexc("5a7fb2"), "b": hexc("8a5a3a"), "k": hexc("f6d06e"),
}

HEAD_DOWN = [
    "................",
    ".....oooooo.....",
    "....oyyyyyyo....",
    "....orrrrrro....",
    ".oyyyYyyyyYyyyo.",
    "..oYYYYYYYYYYo..",
    "...ohssssssho...",
    "...osesssseso...",
    "...oscsssscso...",
    "....oSssssSo....",
]
HEAD_UP = [
    "................",
    ".....oooooo.....",
    "....oyyyyyyo....",
    "....orrrrrro....",
    ".oyyyYyyyyYyyyo.",
    "..oYYYYYYYYYYo..",
    "...ohhhhhhhho...",
    "...ohHhhhhHho...",
    "...ohhhhhhhho...",
    "....ohhhhhho....",
]
HEAD_SIDE = [
    "................",
    ".....oooooo.....",
    "....oyyyyyyo....",
    "....orrrrrro....",
    "..oyyyyyyyyyyyo.",
    "...oYYYYYYYYYo..",
    "...ohhhsssssso..",
    "...ohhssssesso..",
    "...ohhssscsso...",
    "....ohSssso.....",
]
BODY_FRONT = [
    "....oowwwwoo....",
    "...owpwlwwpwo...",
    "..owlpwwwwpwlo..",
    "..owwppppppwwo..",
    "..osWppkkppWso..",
    "..oSoppppppoSo..",
    "...oppppppppo...",
    "...oppppppppo...",
    "...opppPPpppo...",
]
BODY_SIDE = [
    ".....owwwwo.....",
    "....owwwpwwo....",
    "....owwlpwwo....",
    "....owwlppwo....",
    "....owwsppwo....",
    "....oppppppo....",
    "....oppppppo....",
    "....oppppppo....",
    "....oppPPppo....",
]
LEGS_FRONT = {
    "idle": ["....opo..opo....", "....opo..opo....", "....oPo..oPo....", "...obbo..obbo...", "...oooo..oooo..."],
    "step": ["....opo..opo....", "....oPo..opo....", "...obbo..oPo....", "...oooo..obbo...", ".........oooo..."],
}
LEGS_SIDE = {
    "idle": [".....oppppo.....", ".....oppppo.....", ".....oPPPPo.....", ".....obbbbbo....", ".....ooooooo...."],
    "step": ["....oppo.oppo...", "...oppo...oppo..", "..oPPo.....oPPo.", ".obbbo.....obbbo", ".ooooo.....ooooo"],
}


def player_frame(direction, legs, bob, mirror_legs=False):
    c = Canvas(T, 24)
    head = {"down": HEAD_DOWN, "up": HEAD_UP, "side": HEAD_SIDE}[direction]
    body = BODY_SIDE if direction == "side" else BODY_FRONT
    leg_set = LEGS_SIDE if direction == "side" else LEGS_FRONT
    c.template(leg_set[legs], PLAYER_PAL, 0, 19, flip=mirror_legs)
    c.template(body, PLAYER_PAL, 0, 10 + bob)
    c.template(head, PLAYER_PAL, 0, 0 + bob)
    return c


def make_player():
    sheet = Canvas(4 * T, 3 * 24)
    for row, d in enumerate(["down", "up", "side"]):
        frames = [
            player_frame(d, "idle", 0),
            player_frame(d, "step", 1),
            player_frame(d, "idle", 0),
            player_frame(d, "step", 1, mirror_legs=d != "side"),
        ]
        for col, f in enumerate(frames):
            sheet.blit(f, col * T, row * 24)
    sheet.save("player.png")


# ---------------------------------------------------------------- 작물 (crops.png: 줄=작물, 칸=단계 0~4)

CROPS = {
    "carrot": P["leaf"],
    "potato": [hexc("3d6b35"), hexc("4a8442"), hexc("5f9f50"), hexc("7cba62"), hexc("a2d47e")],
    "strawberry": [hexc("3d6b35"), hexc("4f8a3f"), hexc("67aa4a"), hexc("86c75e"), hexc("aee283")],
    # 여름·가을 작물 (BUILD_FARM_PLAN §36 밀, §37, §38). 줄 순서 = items.json 의 crop_row
    "wheat": [hexc("6b6a2e"), hexc("8a8a3a"), hexc("a8a84c"), hexc("c4c063"), hexc("dcd88a")],
    "tomato": [hexc("3d6b35"), hexc("4a8442"), hexc("5f9f50"), hexc("7cba62"), hexc("a2d47e")],
    "blueberry": [hexc("35603f"), hexc("447a4f"), hexc("569463"), hexc("72ad7c"), hexc("9ccca2")],
    "corn": [hexc("3d6b35"), hexc("528d40"), hexc("6aa84e"), hexc("8cc463"), hexc("b4dc88")],
    "watermelon": [hexc("3d6b35"), hexc("4a8442"), hexc("5f9f50"), hexc("7cba62"), hexc("a2d47e")],
    "sweet_potato": [hexc("3f5f33"), hexc("547a3f"), hexc("6b944c"), hexc("88ae62"), hexc("b0cc88")],
    "eggplant": [hexc("3d6b35"), hexc("4f7d44"), hexc("639656"), hexc("80b06b"), hexc("a8cc90")],
    "pumpkin": [hexc("4a6b2e"), hexc("5f8a3a"), hexc("78a64a"), hexc("95c060"), hexc("bcd888")],
    "radish": [hexc("3d6b35"), hexc("4f8a3f"), hexc("64a64a"), hexc("7fc05a"), hexc("a8dc78")],
    # 겨울 작물 (§40, 온실 전용)
    "spinach": [hexc("2f5a2e"), hexc("3b7038"), hexc("4a8a44"), hexc("62a55a"), hexc("8cc47e")],
    "broccoli": [hexc("35603f"), hexc("447a4f"), hexc("5a9463"), hexc("78ad7c"), hexc("a2cca2")],
    "sugar_beet": [hexc("3d6b35"), hexc("4f8a3f"), hexc("64a64a"), hexc("7fc05a"), hexc("a8dc78")],
}

# 작물별 그림 정보 (나중에 그림을 바꿀 때 여기와 produce() 만 고치면 된다)
#   field_y: 밭에서 다 자란 열매를 그릴 높이, seed: 씨앗 봉지 색
CROP_ART = {
    "carrot": {"field_y": 12, "seed": "f0913a"},
    "potato": {"field_y": 12.5, "seed": "d9a868"},
    "strawberry": {"field_y": 8, "seed": "ef5b5b"},
    "wheat": {"field_y": 5, "seed": "e3c45a"},
    "tomato": {"field_y": 8, "seed": "e5483f"},
    "blueberry": {"field_y": 8, "seed": "4f6fc4"},
    "corn": {"field_y": 7, "seed": "f2d14b"},
    "watermelon": {"field_y": 12, "seed": "3f9a4a"},
    "sweet_potato": {"field_y": 12.5, "seed": "b85a86"},
    "eggplant": {"field_y": 9, "seed": "7b4a9e"},
    "pumpkin": {"field_y": 12, "seed": "f08a2c"},
    "radish": {"field_y": 12, "seed": "e9e4d4"},
    "spinach": {"field_y": 10, "seed": "3f8a3a"},
    "broccoli": {"field_y": 7, "seed": "5aa04a"},
    "sugar_beet": {"field_y": 12, "seed": "d65a7a"},
}


def leaf(c, x, y, rx, ry, pal):
    c.ellipse(x, y, rx, ry, pal[2])
    c.set(int(x - rx / 2), int(y - ry / 2), pal[4])


def plant(c, stage, pal):
    if stage == 0:
        for x, y in ((5, 11), (9, 10), (11, 12), (7, 13)):
            c.set(x, y, hexc("f4e2b0")); c.set(x, y + 1, hexc("a8754a"))
        return
    stem = pal[1]
    if stage == 1:
        c.rect(8, 10, 1, 4, stem)
        for x, y in ((6, 9), (7, 10), (5, 8), (10, 9), (9, 10), (11, 8)):
            c.set(x, y, pal[3])
        c.set(6, 8, pal[4]); c.set(10, 8, pal[4])
        return
    height = {2: 6, 3: 8, 4: 8}[stage]
    base_y = 13
    c.rect(8, base_y - height, 1, height, stem)
    rx, ry = {2: (2.6, 1.7), 3: (3.4, 2.1), 4: (3.4, 2.1)}[stage]
    top = base_y - height
    leaf(c, 8 - rx, top + 1, rx, ry, pal)
    leaf(c, 8 + 1 + rx, top + 1, rx, ry, pal)
    leaf(c, 8 - rx * 0.8, top + 4, rx * 0.9, ry, pal)
    leaf(c, 9 + rx * 0.8, top + 4, rx * 0.9, ry, pal)
    if stage >= 3:
        leaf(c, 8.5, top - 0.5, rx * 0.7, ry * 1.1, pal)


def produce(c, kind, cx, cy, big=False):
    k = 1.6 if big else 1.0
    if kind == "carrot":
        orange, light, line = hexc("f0913a"), hexc("ffc07a"), hexc("c9682a")
        if big:
            # 비스듬히 누운 당근: 오른쪽 위가 굵고 왼쪽 아래로 가늘어진다
            for t in range(10):
                r = max(2.8 - t * 0.26, 0.7)
                c.ellipse(cx + 2 - t * 0.6, cy - 2 + t * 0.8, r, r, orange)
            c.set(int(cx + 1), int(cy - 3), light)
            c.set(int(cx + 2), int(cy - 2), light)
            for t in (3, 6):
                c.set(int(cx + 3 - t * 0.6), int(cy - 2 + t * 0.8), line)
        else:
            # 밭에서는 흙 위로 주황 어깨만 살짝 보인다
            c.ellipse(cx, cy, 3.0 * k, 1.8 * k, orange)
            c.set(int(cx - 1), int(cy - 1), light)
            c.set(int(cx + 1), int(cy + 1), line)
    elif kind == "potato":
        for dx, dy in ((-2.5, 0.5), (2.5, 0), (0, 1.5)):
            c.ellipse(cx + dx * k, cy + dy * k, 2.6 * k, 2.0 * k, hexc("e0b97f"))
            c.set(int(cx + dx * k - 1), int(cy + dy * k - 1), hexc("f4d8a6"))
            c.set(int(cx + dx * k + 1), int(cy + dy * k + 1), hexc("b88a50"))
    elif kind in CROP_ART and kind not in ("carrot", "potato", "strawberry"):
        produce_more(c, kind, cx, cy, big)
    elif kind == "strawberry":
        spots = ((-3, 0), (3, -1), (0, 2)) if not big else ((0, 0),)
        for dx, dy in spots:
            x, y = cx + dx, cy + dy
            r = 4.2 if big else 1.9
            c.ellipse(x, y, r, r * 1.1, hexc("ef5b5b"))
            c.ellipse(x - r * 0.3, y - r * 0.3, r * 0.5, r * 0.5, hexc("ff8a80"))
            for sx, sy in ((-0.5, 0), (0.5, 0.6), (0, -0.6)):
                if big or (sx, sy) == (0.5, 0.6):
                    c.set(int(x + sx * r), int(y + sy * r), hexc("ffe7a0"))
            c.rect(int(x - 1), int(y - r * 1.1), 3, 1, hexc("67aa4a"))


def produce_more(c, kind, cx, cy, big):
    """여름·가을 작물의 열매. big=True 는 아이콘(16x16 가득), False 는 밭(잎 사이에 작게)."""
    if kind == "wheat":
        gold, light, stalk = hexc("e3c45a"), hexc("f6e39a"), hexc("b59a3a")
        xs = (-3.5, 0, 3.5) if big else (-3, 0, 3)
        for dx in xs:
            x = cx + dx
            if big:
                c.rect(int(x), int(cy), 1, 7, stalk)
            c.ellipse(x, cy - (1 if big else 0), 1.6 if big else 1.1, 3.4 if big else 2.4, gold)
            c.set(int(x), int(cy - (3 if big else 2)), light)
    elif kind == "tomato":
        red, light = hexc("e5483f"), hexc("ff8a7a")
        spots = ((0, 0.5),) if big else ((-3, 0), (2.5, 1))
        for dx, dy in spots:
            r = 5.0 if big else 1.9
            c.ellipse(cx + dx, cy + dy, r, r * 0.9, red)
            c.ellipse(cx + dx - r * 0.35, cy + dy - r * 0.35, r * 0.35, r * 0.3, light)
            c.rect(int(cx + dx - 1), int(cy + dy - r * 0.9), 3, 1, hexc("5f9f50"))
    elif kind == "blueberry":
        blue, dark, light = hexc("4f6fc4"), hexc("3a52a0"), hexc("a8bdf0")
        spots = ((-2.5, 1), (2.5, 1.5), (0, -2)) if big else ((-3, 0), (-1.5, 1.5), (2.5, 0.5), (3.5, 2))
        for dx, dy in spots:
            r = 2.8 if big else 1.2
            c.ellipse(cx + dx, cy + dy, r, r, blue)
            c.set(int(cx + dx), int(cy + dy + r * 0.5), dark)
            c.set(int(cx + dx - r * 0.4), int(cy + dy - r * 0.4), light)
    elif kind == "corn":
        yellow, light, husk = hexc("f2d14b"), hexc("fff0a0"), hexc("7cba62")
        rx, ry = (2.8, 6.0) if big else (1.6, 3.2)
        c.ellipse(cx - rx * 0.9, cy + ry * 0.35, rx * 0.7, ry * 0.7, husk)
        c.ellipse(cx + rx * 0.9, cy + ry * 0.35, rx * 0.7, ry * 0.7, husk)
        c.ellipse(cx, cy, rx, ry, yellow)
        for k in range(-2, 3):
            c.set(int(cx), int(cy + k * ry / 3), light)
    elif kind == "watermelon":
        green, dark, light = hexc("4fa654"), hexc("2f7a3a"), hexc("8cd48a")
        rx, ry = (6.2, 4.6) if big else (3.8, 2.4)
        c.ellipse(cx, cy, rx, ry, green)
        for dx in (-rx * 0.55, 0, rx * 0.55):
            c.rect(int(cx + dx), int(cy - ry * 0.7), 1, int(ry * 1.4) + 1, dark)
        c.ellipse(cx - rx * 0.4, cy - ry * 0.45, rx * 0.25, ry * 0.2, light)
    elif kind == "sweet_potato":
        skin, light, dark = hexc("c25f8a"), hexc("e892b4"), hexc("8f3f66")
        if big:
            for t in range(9):
                r = 2.6 + 0.9 * (1 - abs(t - 4) / 4)
                c.ellipse(cx - 4 + t, cy + 1.5 - t * 0.35, r, r * 0.85, skin)
            c.set(int(cx - 2), int(cy), light); c.set(int(cx + 1), int(cy - 1), light)
            c.set(int(cx + 2), int(cy + 1), dark)
        else:
            c.ellipse(cx, cy, 3.2, 1.6, skin)
            c.set(int(cx - 1), int(cy - 1), light)
    elif kind == "eggplant":
        purple, light, cap = hexc("7b4a9e"), hexc("a77bd0"), hexc("5f9f50")
        rx, ry = (3.8, 5.2) if big else (1.8, 2.8)
        c.ellipse(cx, cy + ry * 0.25, rx, ry, purple)
        c.ellipse(cx - rx * 0.4, cy - ry * 0.05, rx * 0.3, ry * 0.3, light)
        c.ellipse(cx, cy - ry * 0.65, rx * 0.8, ry * 0.25, cap)
        c.rect(int(cx), int(cy - ry * 1.0), 1, 2, cap)
    elif kind == "pumpkin":
        orange, dark, light, stem = hexc("f08a2c"), hexc("c96a1a"), hexc("ffb866"), hexc("6b8a3a")
        rx, ry = (6.4, 4.8) if big else (3.8, 2.6)
        c.ellipse(cx, cy, rx, ry, orange)
        for dx in (-rx * 0.45, rx * 0.45):
            c.rect(int(cx + dx), int(cy - ry * 0.6), 1, int(ry * 1.2) + 1, dark)
        c.ellipse(cx - rx * 0.55, cy - ry * 0.4, rx * 0.18, ry * 0.25, light)
        c.rect(int(cx), int(cy - ry - 1), 2, 2, stem)
    elif kind == "radish":
        white, shade, top = hexc("f4f1e6"), hexc("d9d3c0"), hexc("c9e3a0")
        if big:
            c.ellipse(cx - 2, cy - 5, 1.6, 3, hexc("7fc05a")); c.ellipse(cx + 2, cy - 5, 1.6, 2.6, hexc("64a64a"))
            c.ellipse(cx, cy + 1.5, 3.0, 5.0, white)
            c.ellipse(cx, cy - 2.2, 2.8, 1.4, top)
            c.set(int(cx + 1), int(cy + 3), shade); c.set(int(cx - 1), int(cy + 5), shade)
        else:
            c.ellipse(cx, cy, 2.6, 1.8, white)
            c.ellipse(cx, cy - 1, 2.4, 0.9, top)
    elif kind == "spinach":
        dark, mid, light, vein = hexc("2f6b2e"), hexc("3f8a3a"), hexc("62a55a"), hexc("9ccf8a")
        if not big:  # 밭에서는 잎 사이에서 보이도록 밝은 새 잎
            dark, mid, light, vein = hexc("4f8a3f"), hexc("8cd06e"), hexc("c4eba0"), hexc("e4f7cc")
        leaves = ((-3, 1, -0.6), (3, 1, 0.6), (0, -1.5, 0)) if big else ((-2.5, 0, -0.6), (2.5, 0, 0.6))
        for dx, dy, tilt in leaves:
            rx, ry = (3.0, 4.6) if big else (1.8, 2.4)
            for t in range(int(ry * 2)):
                yy = cy + dy - ry + t
                c.ellipse(cx + dx + tilt * (t - ry) * 0.4, yy, rx * (1 - abs(t - ry) / (ry + 1)), 0.8, mid)
            c.rect(int(cx + dx), int(cy + dy - ry + 1), 1, int(ry * 2) - 1, vein)
            c.set(int(cx + dx - 1), int(cy + dy - 1), light)
            c.set(int(cx + dx + 1), int(cy + dy + ry - 1), dark)
    elif kind == "broccoli":
        head, dark, light, stem = hexc("4f9a3f"), hexc("33702e"), hexc("86c46a"), hexc("a8d48a")
        if big:
            c.rect(int(cx - 1), int(cy + 1), 3, 6, stem)
            spots = ((-3, -1, 2.8), (3, -1, 2.8), (0, -3, 3.0), (-1.5, 1, 2.6), (1.5, 1, 2.6))
        else:
            spots = ((-1.5, 0, 1.6), (1.5, 0, 1.6), (0, -1.2, 1.7))
        for dx, dy, r in spots:
            c.ellipse(cx + dx, cy + dy, r, r * 0.9, head)
            c.set(int(cx + dx - r * 0.4), int(cy + dy - r * 0.4), light)
            c.set(int(cx + dx + r * 0.3), int(cy + dy + r * 0.4), dark)
    elif kind == "sugar_beet":
        root, shade, top = hexc("efe3c8"), hexc("cdb994"), hexc("d65a7a")
        if big:
            c.ellipse(cx - 2, cy - 5, 1.6, 3, hexc("7fc05a")); c.ellipse(cx + 2, cy - 5, 1.6, 2.6, hexc("64a64a"))
            for t in range(9):
                r = max(3.6 - t * 0.38, 0.7)
                c.ellipse(cx, cy - 1.5 + t, r, 1.0, root)
            c.ellipse(cx, cy - 2.2, 3.2, 1.2, top)
            c.set(int(cx + 1), int(cy + 2), shade); c.set(int(cx - 1), int(cy + 4), shade)
        else:
            c.ellipse(cx, cy, 3.0, 2.0, root)
            c.ellipse(cx, cy - 1.2, 2.6, 0.9, top)
            c.set(int(cx + 1), int(cy + 1), shade)


def make_crops():
    atlas = Canvas(5 * T, len(CROPS) * T)
    for row, (kind, pal) in enumerate(CROPS.items()):
        for stage in range(5):
            c, done = sub(atlas, stage, row)
            plant(c, stage, pal)
            if stage == 4:
                produce(c, kind, 8.5, CROP_ART[kind]["field_y"])
            if stage > 0:
                c.outline(pal[0])
            done()
    atlas.save("crops.png")


# ---------------------------------------------------------------- 아이템 아이콘 (items.png)

ICON_PAL = {
    "o": INK, "w": P["wood"][2], "W": P["wood"][1], "L": P["wood"][3],
    "M": hexc("dfe6ec"), "m": hexc("b2bec8"), "n": hexc("ffffff"),
    "B": hexc("7cc4e6"), "b": hexc("5aa3cc"), "C": hexc("c2ecfa"),
}

# 강화 도구: 같은 모양, 쇠 부분을 구리색으로 (물뿌리개는 청록색 몸통)
ICON_PAL_2 = dict(ICON_PAL, M=hexc("f2bb84"), m=hexc("cf8a52"), n=hexc("ffe9cc"),
                  B=hexc("72cdb4"), b=hexc("4fae95"), C=hexc("c6f0e3"))

HOE = [
    "................",
    "...........ooo..",
    "..........onMMo.",
    ".........onMMmo.",
    "........oMMmmo..",
    "........oommo...",
    ".......owo.oo...",
    "......owLo......",
    ".....owLo.......",
    "....owLo........",
    "...owLo.........",
    "..owLo..........",
    ".oWLo...........",
    ".oWo............",
    "..o.............",
]
CAN = [
    "................",
    "................",
    ".....oooo.......",
    "....oMmmMo......",
    "....om..mo......",
    "..ooooooooo.....",
    "..oCCBBBBBbo..oo",
    ".oBCBBBBBBbooBbo",
    ".oBCBBBBBBbbbbo.",
    ".oBBBBBBBBbbbo..",
    ".oBBBBBBBBbbo...",
    ".obBBBBBBbbbo...",
    "..obbbbbbbbo....",
    "...oooooooo.....",
]


AXE = [
    "................",
    ".......oooo.....",
    "......oMMMMo....",
    ".....onMMMmmo...",
    ".....onMMmmo....",
    "......oMMoWo....",
    ".......oooWo....",
    "........oWLo....",
    "........oWLo....",
    "........oWLo....",
    "........oWLo....",
    "........oWLo....",
    "........oWLo....",
    "........oWWo....",
    ".........oo.....",
]
PICKAXE = [
    "................",
    "...ooo....ooo...",
    "..onMMoooomMMo..",
    "..oMmMMMMMMmmo..",
    "...oo.oWLo.oo...",
    "......oWLo......",
    "......oWLo......",
    "......oWLo......",
    "......oWLo......",
    "......oWLo......",
    "......oWLo......",
    "......oWLo......",
    "......oWWo......",
    ".......oo.......",
]


def material_icon(c, kind):
    if kind == "fiber":
        g = P["leaf"]
        for x, lean in ((5, -1), (7, 0), (9, 1), (11, 1)):
            for k in range(9):
                c.set(x + (lean * k) // 4, 13 - k, g[3] if k > 5 else g[2])
        rrect(c, 4, 9, 9, 3, 1, hexc("d9b36a"))
        c.rect(5, 10, 7, 1, hexc("f0d08a"))
    elif kind == "wood":
        w = P["wood"]
        for y, x0 in ((9, 2), (5, 4)):
            rrect(c, x0, y, 11, 5, 2, w[2])
            c.rect(x0 + 1, y + 1, 8, 1, w[3])
            c.ellipse(x0 + 9.5, y + 2.5, 2, 2.4, hexc("e8c48e"))
            c.set(x0 + 9, y + 2, w[1])
    elif kind == "stone":
        st = [hexc("7d6f63"), hexc("9a8b7d"), hexc("b5a696"), hexc("cdbfae"), hexc("e6dccd")]
        blob(c, [(8, 9.5, 4.8), (5.5, 10.5, 3), (10.5, 10.5, 3.2)], st)
        c.set(6, 7, st[4]); c.set(7, 7, st[4])
    elif kind == "conveyor":
        # 돌돌 만 벨트 한 칸: 나무 난간 두 줄 사이 짙은 벨트 + V 무늬 (비스듬히)
        for y in range(3, 14):
            for x in range(2, 14):
                a = (x - 2) * 16 / 12
                col = belt_pixel(a, y - 3 + 0.5, 0)
                if col is not None:
                    c.set(x, y, col)
    c.outline(INK)


FERTILIZER_COLORS = {
    "basic_fertilizer": (hexc("8fb35a"), hexc("6e8f42")),      # 풀색
    "advanced_fertilizer": (hexc("6fb3d9"), hexc("4f8fb8")),   # 하늘색
    "premium_fertilizer": (hexc("f2c443"), hexc("d19a2a")),    # 금색
}


def fertilizer_bag(c, item):
    """비료 자루: 크림색 자루 + 등급 색 띠 + 새싹 그림"""
    band, band_d = FERTILIZER_COLORS[item]
    rrect(c, 3, 4, 10, 11, 2.5, hexc("ead3a8"))
    c.rect(5, 3, 6, 2, hexc("d9bf8f"))
    c.rect(6, 2, 4, 1, hexc("c9a978"))
    c.rect(3, 8, 10, 4, band)
    c.rect(3, 11, 10, 1, band_d)
    c.set(8, 9, hexc("fffaf0")); c.set(7, 10, hexc("fffaf0")); c.set(9, 10, hexc("fffaf0"))
    if item == "premium_fertilizer":
        c.set(5, 6, hexc("fff3c0")); c.set(11, 6, hexc("fff3c0"))
    c.outline(INK)


def seed_packet(c, color):
    rrect(c, 3, 2, 10, 13, 2, hexc("fbeccf"))
    c.rect(4, 3, 8, 2, hexc("ead3a8"))
    c.ellipse(8, 10, 3.2, 3.2, color)
    c.set(7, 9, hexc("ffffff"))
    c.outline(INK)


# ---------------------------------------------------------------- 가공품 아이콘 (§73, 아이콘 44번부터)

PRODUCTS = ["flour", "dough", "bread", "sugar", "strawberry_jam", "blueberry_jam", "watermelon_juice", "fruit_syrup",
            "tomato_puree", "tomato_sauce", "bottled_sauce", "potato_starch", "potato_snack", "dried_sweet_potato",
            "sweet_potato_dessert", "corn_flour", "corn_bread", "pumpkin_puree", "pumpkin_pie"]


def product_sack(c, band, band_d, dust):
    """가루 자루: 크림색 자루 + 색 띠 + 위로 살짝 보이는 가루"""
    rrect(c, 3, 5, 10, 10, 2.5, hexc("efe2c4"))
    c.ellipse(8, 5, 4, 1.6, hexc(dust))
    c.rect(3, 9, 10, 3, hexc(band))
    c.rect(3, 11, 10, 1, hexc(band_d))
    c.set(5, 7, hexc("fffaf0")); c.set(6, 6, hexc("fffaf0"))


def product_jar(c, fill, fill_d, lid="d9a066"):
    """유리병: 둥근 병 + 안의 내용물 + 천 뚜껑"""
    rrect(c, 3, 5, 10, 10, 3, hexc("e4f1f2"))
    rrect(c, 4, 7, 8, 7, 2.5, hexc(fill))
    c.rect(4, 12, 8, 1, hexc(fill_d))
    c.rect(5, 8, 1, 3, hexc("ffffff"))
    rrect(c, 4, 2, 8, 4, 1, hexc(lid))
    c.rect(4, 4, 8, 1, hexc("b07a45"))


def product_bottle(c, fill, fill_d, cap):
    """긴 병: 목이 좁은 병 + 내용물 + 마개 + 라벨"""
    rrect(c, 4, 6, 8, 9, 2.5, hexc(fill))
    c.rect(4, 12, 8, 2, hexc(fill_d))
    c.rect(6, 3, 4, 4, hexc(fill))
    c.rect(6, 1, 4, 2, hexc(cap))
    rrect(c, 5, 8, 6, 3, 1, hexc("fbeccf"))
    c.set(5, 7, hexc("ffffff")); c.set(5, 12, hexc("ffffff"))


def product_loaf(c, crust, crust_d, top):
    """빵 덩어리: 둥근 빵 + 칼집"""
    c.ellipse(8, 10, 6.5, 4.2, hexc(crust_d))
    c.ellipse(8, 9.3, 6, 3.6, hexc(crust))
    c.ellipse(7, 8, 3.5, 1.4, hexc(top))
    for x in (5, 8, 11):
        c.set(x, 9, hexc(crust_d)); c.set(x + 1, 8, hexc(crust_d))


def product_plate(c, food, food_d, top):
    """접시에 올린 디저트: 크림색 접시 + 쐐기 모양 조각"""
    c.ellipse(8, 12.5, 7, 2.2, hexc("f6ecd8"))
    c.ellipse(8, 12.5, 5, 1.3, hexc("e6d6b8"))
    for y in range(5, 12):
        w = (y - 4)
        c.rect(8 - w // 2 - 2, y, w + 3, 1, hexc(food))
    c.rect(4, 10, 10, 2, hexc(food_d))
    c.rect(5, 5, 4, 1, hexc(top)); c.rect(4, 6, 6, 1, hexc(top))


def product_icon(c, item):
    if item == "flour":
        product_sack(c, "e8c45a", "c9a03a", "fffaf0")
    elif item == "corn_flour":
        product_sack(c, "f2c443", "d19a2a", "fbe39a")
    elif item == "potato_starch":
        product_sack(c, "c9a27a", "a5805a", "fffaf0")
    elif item == "sugar":
        # 하얀 각설탕 세 개
        for x, y in ((3, 8), (9, 8), (6, 3)):
            rrect(c, x, y, 6, 6, 1, hexc("fdfbf6"))
            c.rect(x + 1, y + 4, 4, 1, hexc("ddd6ca"))
            c.set(x + 1, y + 1, hexc("ffffff"))
    elif item == "dough":
        c.ellipse(8, 10.5, 6, 3.8, hexc("e6cfa0"))
        c.ellipse(8, 9.5, 5.4, 3.2, hexc("f6e6c4"))
        c.ellipse(6.5, 8.5, 2.2, 1.1, hexc("fffaf0"))
    elif item == "bread":
        product_loaf(c, "d99a4e", "a8692e", "eab676")
    elif item == "corn_bread":
        product_loaf(c, "f0c04a", "c9922a", "f8dc7a")
    elif item == "strawberry_jam":
        product_jar(c, "e0484f", "b02f3a")
    elif item == "blueberry_jam":
        product_jar(c, "5a64b8", "3f468c")
    elif item == "tomato_puree":
        product_jar(c, "e8603c", "c2442a", lid="e8e0d0")
    elif item == "tomato_sauce":
        product_jar(c, "c23a2a", "92281e", lid="7fb069")
    elif item == "pumpkin_puree":
        product_jar(c, "f29a3a", "d07624", lid="e8e0d0")
    elif item == "fruit_syrup":
        product_bottle(c, "c4345e", "952448", "f6d06e")
    elif item == "watermelon_juice":
        product_bottle(c, "f07a8a", "d0566a", "7fb069")
    elif item == "bottled_sauce":
        product_bottle(c, "b8302a", "88221e", "4f6d92")
    elif item == "potato_snack":
        # 과자 봉지
        rrect(c, 3, 3, 10, 12, 2, hexc("f2c443"))
        c.rect(3, 3, 10, 2, hexc("d19a2a")); c.rect(3, 13, 10, 2, hexc("d19a2a"))
        c.ellipse(8, 9, 3, 2.4, hexc("f6e2a4"))
        c.set(7, 8, hexc("c9922a")); c.set(9, 10, hexc("c9922a"))
    elif item == "dried_sweet_potato":
        # 말린 고구마 조각 세 개
        for x, y in ((3, 4), (7, 6), (5, 9)):
            rrect(c, x, y, 6, 4, 1.5, hexc("e8913a"))
            c.rect(x, y, 6, 1, hexc("a4484e"))
            c.set(x + 2, y + 2, hexc("f6b866"))
    elif item == "sweet_potato_dessert":
        product_plate(c, "e8a04a", "c27a2e", "a4484e")
    elif item == "pumpkin_pie":
        product_plate(c, "f29a3a", "c98f5e", "fbe39a")
    c.outline(INK)


def make_items():
    order = ["hoe", "watering_can", "carrot_seed", "potato_seed", "strawberry_seed", "carrot", "potato", "strawberry",
             "axe", "pickaxe", "fiber", "wood", "stone",
             "basic_fertilizer", "advanced_fertilizer", "premium_fertilizer",
             "hoe_2", "watering_can_2", "axe_2", "pickaxe_2"]
    # 여름·가을 작물: 씨앗, 작물 순서로 (아이콘 20번부터)
    # 겨울 작물 (아이콘 38번부터)
    for kind in ("wheat", "tomato", "blueberry", "corn", "watermelon", "sweet_potato", "eggplant", "pumpkin", "radish",
                 "spinach", "broccoli", "sugar_beet"):
        order += [kind + "_seed", kind]
    order += PRODUCTS  # 가공품 (아이콘 44번부터)
    order += ["conveyor"]  # 컨베이어 (아이콘 63번)
    atlas = Canvas(len(order) * T, T)
    for col, item in enumerate(order):
        c, done = sub(atlas, col, 0)
        if item in ("hoe_2", "watering_can_2", "axe_2", "pickaxe_2"):
            c.template({"hoe_2": HOE, "watering_can_2": CAN, "axe_2": AXE, "pickaxe_2": PICKAXE}[item], ICON_PAL_2)
            c.set(13, 13, hexc("fff3c0")); c.set(14, 12, hexc("fff3c0"))  # 반짝임
        elif item == "hoe":
            c.template(HOE, ICON_PAL)
        elif item == "watering_can":
            c.template(CAN, ICON_PAL)
        elif item == "axe":
            c.template(AXE, ICON_PAL)
        elif item == "pickaxe":
            c.template(PICKAXE, ICON_PAL)
        elif item in ("fiber", "wood", "stone", "conveyor"):
            material_icon(c, item)
        elif item.endswith("_fertilizer"):
            fertilizer_bag(c, item)
        elif item.endswith("_seed"):
            seed_packet(c, hexc(CROP_ART[item[:-5]]["seed"]))
        elif item in PRODUCTS:
            product_icon(c, item)
        else:
            pal = CROPS[item]
            if item == "carrot":
                c.ellipse(10, 3, 1.6, 2.8, pal[3]); c.ellipse(13, 4, 1.6, 2.4, pal[2]); c.rect(11, 3, 1, 4, pal[1])
                produce(c, item, 8, 9, big=True)
            elif item == "potato":
                c.ellipse(8, 9, 5.5, 4.2, hexc("e0b97f"))
                c.ellipse(6.5, 7.5, 2.5, 1.5, hexc("f4d8a6"))
                for x, y in ((5, 10), (10, 8), (9, 11)):
                    c.set(x, y, hexc("b88a50"))
            elif item == "strawberry":
                produce(c, item, 8, 9.5, big=True)
            else:
                produce(c, item, 8, 8.5, big=True)
            c.outline(INK)
        done()
    atlas.save("items.png")


# ---------------------------------------------------------------- UI (3배로 키워 저장)

UI = {
    "outline": hexc("8a5a3b"), "text": hexc("5b3a29"),
}


def round_frame(w, h, r, fill, wood, light, outline):
    """얇은 테두리: 바깥 1px 부드러운 갈색 + 1px 밝은 나무색 + 크림 바탕."""
    c = Canvas(w, h)
    rrect(c, 0, 0, w, h, r, outline)
    rrect(c, 1, 1, w - 2, h - 2, r - 1, wood)
    rrect(c, 2, 2, w - 4, h - 4, max(r - 2, 1), fill)
    c.rect(int(r), 1, w - 2 * int(r), 1, light)
    return c


def button(w, h, fill, light, shade, outline, pressed=False):
    c = Canvas(w, h)
    rrect(c, 0, 0, w, h, 4, outline)
    if pressed:
        rrect(c, 1, 1, w - 2, h - 2, 3, shade)
        rrect(c, 1, 2, w - 2, h - 3, 3, fill)
    else:
        rrect(c, 1, 1, w - 2, h - 2, 3, shade)
        rrect(c, 1, 1, w - 2, h - 3, 3, fill)
        c.rect(4, 2, w - 8, 1, light)
    return c


def make_ui():
    ui = {
        "ui_panel.png": round_frame(16, 16, 5, hexc("fff8ea"), hexc("ebc790"), hexc("f8e2bc"), hexc("b8875a")),
        "ui_slot.png": round_frame(12, 12, 4, hexc("fbf0da"), hexc("efdcb8"), hexc("fbf0da"), hexc("d2ab7a")),
        "ui_slot_selected.png": round_frame(12, 12, 4, hexc("fff4cc"), hexc("f7cf62"), hexc("ffe9a6"), hexc("d99a34")),
        "ui_button.png": button(12, 12, hexc("f8d69c"), hexc("fff0d0"), hexc("e3b673"), hexc("b8875a")),
        "ui_button_hover.png": button(12, 12, hexc("ffe2b0"), hexc("fff8e6"), hexc("ebc283"), hexc("b8875a")),
        "ui_button_pressed.png": button(12, 12, hexc("efc685"), hexc("efc685"), hexc("d9a865"), hexc("b8875a"), pressed=True),
        "ui_button_disabled.png": button(12, 12, hexc("f2e8d8"), hexc("f8f2e8"), hexc("e3d6c2"), hexc("d2bfa3")),
        "ui_key.png": button(12, 12, hexc("fffaf0"), hexc("ffffff"), hexc("ead9bb"), hexc("b8875a")),
    }
    for name, c in ui.items():
        c.scaled(3).save(name)
    make_ui_icons()


def make_ui_icons():
    """ui_icons.png: 0 해, 1 달, 2 동전, 3 말풍선(!)"""
    atlas = Canvas(4 * T, T)
    c, done = sub(atlas, 0, 0)
    for a in range(8):
        ang = a * math.pi / 4
        x, y = 8 + math.cos(ang) * 6.5, 8 + math.sin(ang) * 6.5
        c.rect(int(x), int(y), 1 + (a % 2 == 0), 1 + (a % 2 == 0), hexc("f5b942"))
    c.ellipse(8, 8, 4.2, 4.2, hexc("ffcf5a"))
    c.ellipse(7, 7, 2, 2, hexc("ffe79a"))
    c.outline(hexc("c98a2e"))
    done()
    c, done = sub(atlas, 1, 0)
    c.ellipse(8, 8, 5.5, 5.5, hexc("fff1b0"))
    for y in range(T):
        for x in range(T):
            if (x + 0.5 - 11) ** 2 + (y + 0.5 - 6) ** 2 <= 4.6 ** 2:
                c.set(x, y, CLEAR)
    c.set(5, 9, hexc("f2dc8a")); c.set(6, 11, hexc("f2dc8a"))
    c.outline(hexc("c9a65a"))
    done()
    c, done = sub(atlas, 2, 0)
    c.ellipse(8, 8, 5.5, 5.5, hexc("f5c542"))
    c.ellipse(8, 8, 3.8, 3.8, hexc("e0a82e"))
    c.ellipse(8, 8, 2.8, 2.8, hexc("f8d25a"))
    c.rect(8, 6, 1, 5, hexc("e0a82e"))
    c.set(5, 5, hexc("fff3b0")); c.set(6, 4, hexc("fff3b0"))
    c.outline(hexc("a8701e"))
    done()
    c, done = sub(atlas, 3, 0)
    rrect(c, 2, 1, 12, 10, 3.5, hexc("fffaf0"))
    c.set(6, 11, hexc("fffaf0")); c.set(7, 11, hexc("fffaf0")); c.set(6, 12, hexc("fffaf0"))
    c.rect(7, 3, 2, 4, hexc("e0715f")); c.rect(7, 8, 2, 1, hexc("e0715f"))
    c.outline(INK)
    done()
    atlas.save("ui_icons.png")


if __name__ == "__main__":
    print("BuildFarm art ->", OUT)
    make_tiles()
    make_details()
    make_edges()
    make_trees()
    make_undergrowth()
    make_rock()
    make_house()
    make_shop()
    make_shop_decor()
    make_plaza_props()
    make_placeables()
    make_greenhouse()
    make_compost_bin()
    make_conveyor()
    make_sprinklers()
    make_harvesters()
    make_warehouse()
    make_processor()
    make_generator()
    make_electric_processor()
    make_well()
    make_shipping_bin()
    make_blacksmith()
    make_recipe_shop()
    make_obstacles()
    make_player()
    make_crops()
    make_items()
    make_ui()
