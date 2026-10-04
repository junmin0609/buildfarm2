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

def make_details():
    g = P["grass"]
    atlas = Canvas(8 * T, T)
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
    atlas.save("details.png")


# ---------------------------------------------------------------- 경계 (edges.png)
# 길·물·흙 칸 위에 덮어서, 옆 칸이 잔디면 그쪽 가장자리를 잔디가 살짝 덮게 한다.
# 줄: 0 길, 1 물, 2 흙 / 칸: 잔디 이웃 비트 (북1 동2 남4 서8)

EDGE_KINDS = ["path", "water", "dirt"]


def edge_tile(kind, mask):
    c = Canvas(T, T)
    g = P["grass"]
    rng = random.Random(EDGE_KINDS.index(kind) * 7 + 1)
    depth = [rng.choice([1, 2, 2, 2, 3]) for _ in range(T)]
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


def make_edges():
    atlas = Canvas(16 * T, len(EDGE_KINDS) * T)
    for row, kind in enumerate(EDGE_KINDS):
        for mask in range(16):
            atlas.blit(edge_tile(kind, mask), mask * T, row * T)
    atlas.save("edges.png")


# ---------------------------------------------------------------- 소품 (나무, 바위)

def make_tree():
    c = Canvas(32, 32)
    c.ellipse(16, 29.5, 11, 2.4, SOFT_SHADOW)
    w = P["wood"]
    rrect(c, 13, 19, 6, 11, 2, w[1])
    c.rect(14, 20, 1, 9, w[2])
    c.rect(17, 21, 1, 8, w[0])
    c.rect(12, 28, 8, 2, w[1])
    c.set(12, 28, CLEAR); c.set(19, 28, CLEAR)
    leaves = Canvas(32, 32)
    blob(leaves, [(16, 11, 10), (8.5, 15.5, 7), (23.5, 15.5, 7), (16, 18, 8), (16, 5.5, 6.5)], P["leaf"], outline=P["leaf"][0])
    for x, y in ((11, 5), (12, 5), (11, 6), (19, 3), (20, 3), (6, 12), (7, 12), (22, 10), (23, 10)):
        leaves.set(x, y, P["leaf"][4])
    for x, y in ((10, 14), (21, 8), (18, 17), (24, 16)):  # 빨간 열매
        leaves.rect(x, y, 2, 2, hexc("e8705a"))
        leaves.set(x, y, hexc("ffb09a"))
    c.blit(leaves, 0, 0)
    c.outline(INK)
    c.save("tree.png")


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
    c = Canvas(T, T)  # 둥근 덤불 (산딸기)
    c.ellipse(8, 14.4, 6.5, 1.5, SOFT_SHADOW)
    leaves = Canvas(T, T)
    blob(leaves, [(8, 9.5, 5), (4.5, 11, 3.5), (11.5, 11, 3.5)], P["leaf"], outline=P["leaf"][0])
    for x, y in ((5, 9), (10, 8), (8, 12)):
        leaves.set(x, y, hexc("d9536a")); leaves.set(x + 1, y, hexc("f08a9a"))
    c.blit(leaves, 0, 0)
    c.outline(INK)
    c.save("bush.png")
    c = Canvas(T, 24)  # 어린 나무
    c.ellipse(8, 22.5, 5.5, 1.4, SOFT_SHADOW)
    c.rect(7, 13, 2, 10, w[1]); c.set(7, 14, w[2])
    leaves = Canvas(T, 24)
    blob(leaves, [(8, 8, 5.5), (5, 10.5, 3.5), (11, 10.5, 3.5)], P["leaf"], outline=P["leaf"][0])
    leaves.set(6, 4, P["leaf"][4]); leaves.set(7, 4, P["leaf"][4])
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


def make_items():
    order = ["hoe", "watering_can", "carrot_seed", "potato_seed", "strawberry_seed", "carrot", "potato", "strawberry",
             "axe", "pickaxe", "fiber", "wood", "stone",
             "basic_fertilizer", "advanced_fertilizer", "premium_fertilizer",
             "hoe_2", "watering_can_2", "axe_2", "pickaxe_2"]
    # 여름·가을 작물: 씨앗, 작물 순서로 (아이콘 20번부터)
    for kind in ("wheat", "tomato", "blueberry", "corn", "watermelon", "sweet_potato", "eggplant", "pumpkin", "radish"):
        order += [kind + "_seed", kind]
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
        elif item in ("fiber", "wood", "stone"):
            material_icon(c, item)
        elif item.endswith("_fertilizer"):
            fertilizer_bag(c, item)
        elif item.endswith("_seed"):
            seed_packet(c, hexc(CROP_ART[item[:-5]]["seed"]))
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
    make_tree()
    make_rock()
    make_house()
    make_shop()
    make_shop_decor()
    make_plaza_props()
    make_placeables()
    make_well()
    make_shipping_bin()
    make_blacksmith()
    make_obstacles()
    make_player()
    make_crops()
    make_items()
    make_ui()
