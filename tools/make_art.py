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
    # 무드 이미지의 꿀색 자갈 (돌길·광장 바닥). 줄눈은 따뜻한 갈색
    "cobble": [hexc("bf8d5a"), hexc("dcae7c"), hexc("e9c595"), hexc("f6dfb6")],
    "mortar": [hexc("c49468"), hexc("b8885c"), hexc("cf9f71")],
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


def cobbles(c, rng, sizes, count, mortar, st=None):
    """둥근 돌을 겹치지 않게 흩뿌린다. 돌마다 왼쪽 위는 밝고 아래는 그늘."""
    st = st or P["stone"]
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


def packed_cobbles(c, rng, row_h=4):
    """무드 이미지의 꿀색 자갈: 엇갈린 줄로 빽빽이 깐 둥근 돌. 줄눈 1px, 돌마다 색을 조금씩 달리한다.
    가로로 이어 붙여도 이음매가 안 보이게 줄마다 16px 안에서 폭을 나눈다"""
    st, m = P["cobble"], P["mortar"]
    c.rect(0, 0, T, T, m[1])
    for row, y in enumerate(range(0, T, row_h)):
        widths, total = [], 0
        while total < T:
            wdt = rng.choice((4, 5, 5, 6))
            wdt = min(wdt, T - total) if T - total - wdt < 3 else wdt
            widths.append(wdt)
            total += wdt
        x = rng.randrange(0, 4) if row % 2 else 0
        for wdt in widths:
            tone = rng.choice((0, 1, 1, 2))
            for xx in range(wdt - 1):
                for yy in range(row_h - 1):
                    px, py = (x + xx) % T, y + yy
                    corner = (xx in (0, wdt - 2)) and (yy in (0, row_h - 2))
                    if corner:
                        continue
                    c.set(px, py, st[tone + 1] if yy == 0 or xx == 0 else st[tone])
            c.set((x + 1) % T, y, st[3])
            x += wdt


def path(c, rng):
    packed_cobbles(c, rng)


def plaza(c, rng):
    packed_cobbles(c, rng, row_h=5)


def embankment(c, rng):
    """개울가 석축 (무드 이미지): 위에서 본 돌담. 회갈색 돌을 엇갈려 쌓고 아래쪽은 그늘"""
    st = [hexc("6f6a5c"), hexc("8a8574"), hexc("a39d8a"), hexc("bdb7a3")]
    c.rect(0, 0, T, T, st[0])
    for row, y in enumerate((0, 5, 10)):
        off = 0 if row % 2 == 0 else 4
        for x in range(-off, T, 8):
            rrect(c, x + 1, y + 1, 7, 4, 1.2, st[1])
            rrect(c, x + 1, y + 1, 6, 3, 1.0, st[2])
            c.set(x + 2, y + 1, st[3])
    c.rect(0, 15, T, 1, hexc("4f4a40"))


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
    c, done = sub(atlas, 3, 3); embankment(c, random.Random(301)); done()
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
    """16x20 (무드 이미지 3단계): 하급 나무 말뚝 + 쇠 십자 관 / 중급 청록 관 + 돌 받침 / 상급 금빛 머리 + 하늘색 빛 + 둥근 돌 받침"""
    w = P["wood"]
    iron, iron_l = hexc("3c3d44"), hexc("6a6c76")
    copper, copper_l = hexc("b8733a"), hexc("e0a060")
    teal, teal_d, teal_l = hexc("3f8a7a"), hexc("2f6a5e"), hexc("6fbfa8")
    gold, gold_d, gold_l = hexc("d6a83a"), hexc("a8782a"), hexc("f3d36b")
    stone, stone_l = hexc("8a8574"), hexc("bdb7a3")
    spray, spray_l = hexc("7cc4e6"), hexc("c2ecfa")
    for tier in (1, 2, 3):
        c = Canvas(T, 20)
        c.ellipse(8, 18.5, 6, 1.3, SOFT_SHADOW)
        if tier == 1:
            c.ellipse(8, 18, 4, 1.5, P["leaf"][2]); c.set(5, 17, FLOWERS[0]); c.set(11, 17, FLOWERS[0])
            c.rect(7, 9, 3, 9, w[1]); c.rect(7, 9, 1, 9, w[2])           # 나무 말뚝
            c.rect(2, 6, 12, 2, iron); c.rect(2, 6, 12, 1, iron_l)        # 쇠 십자 관
            c.rect(1, 5, 2, 4, iron); c.rect(13, 5, 2, 4, iron)
            c.rect(7, 3, 3, 5, iron); c.set(7, 3, iron_l)
            rrect(c, 6, 1, 5, 3, 1, copper); c.set(7, 1, copper_l)       # 구리 마개
        elif tier == 2:
            rrect(c, 4, 14, 9, 5, 1, stone); c.rect(5, 14, 7, 1, stone_l)  # 돌 받침
            c.set(3, 17, P["leaf"][2]); c.set(13, 17, P["leaf"][2])
            c.rect(7, 6, 3, 9, teal); c.rect(7, 6, 1, 9, teal_l)          # 청록 관
            c.rect(8, 6, 2, 9, teal_d)
            c.rect(2, 7, 13, 2, copper); c.rect(2, 7, 13, 1, copper_l)    # 구리 팔
            c.rect(1, 6, 2, 4, teal_d); c.rect(14, 6, 2, 4, teal_d)
            rrect(c, 6, 2, 5, 5, 1, copper); c.set(7, 3, copper_l)
            c.rect(6, 11, 5, 1, copper)
        else:
            c.ellipse(8, 17, 6.5, 2.5, stone); c.ellipse(8, 16.5, 5.5, 1.8, stone_l)   # 둥근 돌 받침
            c.rect(7, 8, 3, 8, gold_d); c.rect(7, 8, 1, 8, gold)          # 금빛 기둥
            for dx in (-1, 1):                                            # 팔 넷
                c.rect(8 + dx * 3 - (1 if dx < 0 else 0), 5, 3, 2, gold); c.rect(8 + dx * 6 - (1 if dx < 0 else 0), 4, 2, 4, gold_d)
            rrect(c, 4, 2, 9, 7, 2, gold); c.rect(5, 2, 7, 1, gold_l)     # 육각 머리
            rrect(c, 6, 3, 5, 5, 1.5, hexc("3fc8e0")); c.rect(7, 4, 2, 2, hexc("c2f4fc"))   # 하늘색 빛
            c.set(8, 0, gold_l); c.rect(7, 1, 3, 1, gold)
        c.outline(INK)
        arcs = {1: ((0, 3), (15, 3)), 2: ((0, 2), (15, 2), (1, 0), (14, 0)), 3: ((0, 1), (15, 1), (1, 0), (14, 0), (0, 4), (15, 4))}
        for x, y in arcs[tier]:
            c.set(x, y, spray)
        if tier == 3:
            c.set(0, 0, spray_l)
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


# ---------------------------------------------------------------- 펌프·물탱크 (§14)
#   펌프 (1x1칸, 16x26): 돌 받침 + 쇠 몸통 + 손잡이 바퀴 + 물가로 내려가는 관
#   물탱크 (2x2칸, 32x48): 나무 다리 위 나무통 + 쇠띠 + 물 높이 창

def make_pump():
    st = [hexc("9a8b7d"), hexc("b5a696"), hexc("cdbfae")]
    m, md, ml = hexc("8fa3b8"), hexc("6f8296"), hexc("c6d3df")
    c = Canvas(T, 26)
    c.ellipse(8, 24.5, 6, 1.3, SOFT_SHADOW)
    rrect(c, 2, 19, 12, 6, 1.5, st[1]); c.rect(3, 19, 10, 1, st[2])
    rrect(c, 4, 8, 8, 12, 2, m); c.rect(5, 9, 2, 10, ml); c.rect(10, 9, 1, 10, md)
    c.rect(11, 12, 4, 2, md); c.rect(13, 12, 2, 8, md)           # 관 (물가로)
    c.set(14, 20, SKY_BLUE); c.set(13, 21, SKY_BLUE)              # 물방울
    c.ellipse(8, 6, 3.5, 3.5, P["wood"][1]); c.ellipse(8, 6, 1.6, 1.6, P["wood"][3])   # 손잡이 바퀴
    c.rect(7, 2, 2, 2, P["wood"][0])
    c.outline(INK)
    c.save("pump.png")


def make_water_tank():
    w = P["wood"]
    c = Canvas(32, 48)
    c.ellipse(16, 46.5, 14, 1.6, SOFT_SHADOW)
    for x in (4, 26):                                             # 다리
        c.rect(x, 30, 3, 16, w[0]); c.rect(x, 30, 1, 16, w[1])
    c.rect(6, 38, 21, 2, w[1])                                    # 가로대
    rrect(c, 2, 6, 28, 26, 4, w[2])                               # 통
    for x in range(5, 30, 4):
        c.rect(x, 8, 1, 22, w[1])
    for y in (10, 25):                                            # 쇠띠
        c.rect(2, y, 28, 2, hexc("8fa3b8")); c.rect(2, y, 28, 1, hexc("c6d3df"))
    c.ellipse(16, 6, 13, 3, w[3]); c.ellipse(16, 6, 10, 2, SKY_BLUE)   # 위에서 보이는 물
    rrect(c, 20, 13, 6, 10, 1, hexc("2f78a8")); c.rect(21, 14, 4, 4, SKY_BLUE_L)  # 물 높이 창
    c.outline(INK)
    c.save("water_tank.png")


# ---------------------------------------------------------------- 분배기·합류기·필터 분배기 (1x1칸, §62)
#   회전 0 = 앞이 아래. 뒤(위)에서 들어온다. 네 방향 그림을 돌려서 저장 (_0~_3, 게임의 turns 와 같은 순서)
#   필터 분배기 출구 색: 흐름 기준 왼쪽 = 하늘색, 오른쪽 = 분홍 (회전 0 에서 왼쪽 출구는 화면 오른쪽)

ROUTER_LEFT = hexc("7cc4e6")
ROUTER_RIGHT = hexc("f29bb0")


def rotated_cw(c):
    out = Canvas(c.h, c.w)
    for y in range(c.h):
        for x in range(c.w):
            out.set(c.h - 1 - y, x, c.px[y][x])
    return out


def router_base():
    c = Canvas(T, T)
    rrect(c, 1, 1, 14, 14, 3, P["wood"][1])
    rrect(c, 2, 2, 12, 12, 2.5, BELT[0])
    c.rect(3, 2, 10, 1, P["wood"][2])
    return c


def arrow(c, x, y, d, col):
    """(x, y) 끝을 가진 작은 화살표. d = 'down'/'left'/'right'/'up'"""
    pts = {"down": [(0, 0), (-1, -1), (1, -1), (-2, -2), (2, -2)], "up": [(0, 0), (-1, 1), (1, 1), (-2, 2), (2, 2)],
           "left": [(0, 0), (1, -1), (1, 1), (2, -2), (2, 2)], "right": [(0, 0), (-1, -1), (-1, 1), (-2, -2), (-2, 2)]}[d]
    for dx, dy in pts:
        c.set(x + dx, y + dy, col)


def make_routers():
    mark = BELT_MARK
    kinds = {}

    def fork(c, left_col, right_col, down_col):
        """위에서 들어와 가운데에서 세 갈래로 나가는 가는 선 + 바깥쪽 화살촉"""
        c.rect(8, 3, 1, 5, mark)                   # 들어오는 줄기
        c.rect(5, 8, 7, 1, mark)                   # 가로 막대
        c.rect(8, 8, 1, 3, down_col)
        arrow(c, 3, 8, "left", left_col)
        arrow(c, 13, 8, "right", right_col)
        arrow(c, 8, 12, "down", down_col)

    # 분배기: 하나 들어와 세 갈래로
    c = router_base()
    fork(c, mark, mark, mark)
    kinds["splitter"] = c
    # 합류기: 세 쪽에서 안쪽을 가리키는 화살촉 → 가운데 → 아래로
    c = router_base()
    c.rect(8, 5, 1, 7, mark)                       # 위 → 가운데 → 아래
    c.rect(5, 8, 7, 1, mark)                       # 왼·오른쪽 → 가운데
    arrow(c, 8, 5, "down", mark)                   # 가장자리에서 안쪽을 가리키는 화살촉
    arrow(c, 5, 8, "right", mark)
    arrow(c, 11, 8, "left", mark)
    c.rect(7, 12, 3, 1, mark); c.set(8, 13, mark)  # 아래로 나가는 굵은 끝
    kinds["merger"] = c
    # 필터 분배기: 분배기 + 출구 색 (흐름 왼쪽 = 화면 오른쪽 하늘색, 흐름 오른쪽 = 화면 왼쪽 분홍) + 가운데 깔때기
    c = router_base()
    fork(c, ROUTER_RIGHT, ROUTER_LEFT, mark)
    c.rect(6, 4, 5, 1, hexc("f6e2a4")); c.rect(7, 5, 3, 1, hexc("f6e2a4"))
    kinds["filter_splitter"] = c
    for name, c in kinds.items():
        c.outline(INK)
        for turn in range(4):
            c.save(f"{name}_{turn}.png")
            c = rotated_cw(c)


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

def make_mid_processor():
    """중급 가공기 (3x3, 48x60): 전기 가공기와 같은 꼴, 구리·청록 몸통 + 톱니 둘 + 2급 표시 (§70)"""
    body, body_d, body_l = hexc("3f8a7a"), hexc("2f6a5e"), hexc("6fbfa8")
    metal, metal_d = hexc("cf8a52"), hexc("a8653a")
    c = Canvas(48, 60)
    c.ellipse(24, 58.5, 23, 1.8, SOFT_SHADOW)
    rrect(c, 1, 52, 46, 6, 1, metal_d); c.rect(2, 52, 44, 1, metal)
    rrect(c, 3, 22, 42, 31, 2.5, body); c.rect(4, 22, 40, 2, body_l); c.rect(4, 50, 40, 2, body_d)
    for y in range(6, 23):
        c.rect(12 + (y - 6) // 3, y, 24 - 2 * ((y - 6) // 3), 1, metal if y % 4 else metal_d)
    rrect(c, 9, 3, 30, 5, 1.5, metal); c.rect(10, 3, 28, 1, hexc("f2bb84"))
    rrect(c, 9, 28, 20, 14, 2, metal_d); rrect(c, 11, 30, 16, 10, 2, hexc("a8dcef"))
    c.ellipse(19, 38, 6, 2.2, hexc("c6d86a")); c.set(13, 31, hexc("e4f6fc")); c.set(14, 31, hexc("e4f6fc"))
    for gx, gy, r in ((37, 31, 4), (40, 38, 2.6)):                                   # 톱니 둘 (빠르게 돈다)
        for a in range(8):
            ang = a * math.pi / 4
            c.set(int(gx + math.cos(ang) * (r + 1)), int(gy + math.sin(ang) * (r + 1)), hexc("f2c443"))
        c.ellipse(gx, gy, r, r, hexc("f2c443")); c.ellipse(gx, gy, r * 0.4, r * 0.4, body_d)
    rrect(c, 31, 42, 12, 6, 1, hexc("fbf3e1"))                                          # 2급 표시 (점 둘)
    c.rect(34, 44, 2, 2, hexc("2f6a5e")); c.rect(38, 44, 2, 2, hexc("2f6a5e"))
    rrect(c, 13, 45, 14, 6, 1, body_d); c.rect(14, 46, 12, 1, hexc("1f4a40"))
    c.outline(INK)
    c.save("mid_processor.png")


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

# ---------------------------------------------------------------- 레시피 상점 (셰프, 광장, 3x2칸, 그림 48x44)
#   크림색 회벽 + 붉은 기와 지붕 + 줄무늬 차양 + 요리사 모자 간판 + 굴뚝 김

# ---------------------------------------------------------------- 들어가는 가게 (사용자 요청) + 상점 NPC
#   잡화점 (4x3칸, 64x60): 크림색 벽 + 초록 차양 + 큰 진열창 + 가운데 문, 씨앗 자루·상자
#   기계상점 (3x2칸, 48x44): 철판 지붕 + 톱니 간판 + 셔터 문
#   NPC (16x24): 잡화점 하나(초록 앞치마) / 대장장이 철수(가죽 앞치마·수염) / 기계상점 미나(파란 작업복·고글)

# ---------------------------------------------------------------- 무드 개편 (사용자가 준 무드 이미지: 아늑한 마을 광장)
#   나무 골조 + 색 지붕 + 줄무늬 차양 + 불 켜진 창 + 걸린 등불 + 꽃 상자 + 간판
#   간판 글자는 게임이 도트 폰트(16px)로 얹는다. 간판 자리는 SIGNS, 게임 쪽 sign_rect 와 맞춘다

WOOD_WALL = [hexc("8a5a34"), hexc("a06d3c"), hexc("b88248"), hexc("cf9a5e")]
GLOW = [hexc("e8a64a"), hexc("ffd27a"), hexc("fff0b8")]
CREAM_BOARD = hexc("f6ead2")
FLOWERS = [hexc("fbf6ec"), hexc("f0a8bd"), hexc("b49be0"), hexc("f3d36b"), hexc("ffffff")]

# 간판 자리 (x, y, 폭, 높이). 게임에서는 판 가운데에 글자를 얹는다
SIGNS = {
    "general_store": (6, 27, 68, 18),   # 씨앗상점 (네 글자라 기계상점처럼 넓은 간판)
    "blacksmith": (6, 25, 52, 18),
    "machine_shop": (11, 27, 68, 18),
    "recipe_shop": (6, 25, 52, 18),
    "arch": (6, 0, 52, 18),
    "farm_sign": (6, 3, 56, 18),
}


def gable_roof(c, x0, x1, y0, y1, pal, slope=0.8):
    """앞에서 본 박공 지붕 (기와 줄 + 줄마다 엇갈린 이음매)"""
    base, dark, light = pal
    inset0 = (y1 - y0) * slope
    for y in range(y0, y1):
        inset = max(0, int(inset0 - (y - y0) * slope))
        row = (y - y0) // 4
        for x in range(x0 + inset, x1 - inset):
            seam = (x + row * 3) % 7 == 0 and (y - y0) % 4 != 0
            c.set(x, y, dark if (y - y0) % 4 == 3 or seam else base)
    top = int(inset0)
    c.rect(x0 + top, y0, max(1, x1 - x0 - 2 * top), 1, light)


def plank_wall(c, x, y, w, h):
    c.rect(x, y, w, h, WOOD_WALL[2])
    for xx in range(x, x + w, 5):
        c.rect(xx, y, 1, h, WOOD_WALL[1])
        c.rect(xx + 1, y, 1, h, WOOD_WALL[3])
    c.rect(x, y, w, 2, WOOD_WALL[0])


def awning(c, x, y, w, col, col2, depth=6, edge=None):
    for xx in range(x, x + w):
        stripe = col if ((xx - x) // 4) % 2 == 0 else col2
        c.rect(xx, y, 1, depth, stripe)
        if (xx - x) % 4 in (1, 2):
            c.set(xx, y + depth, stripe)
    c.rect(x, y, w, 1, edge or col)


def glow_window(c, x, y, w, h, stuff=None):
    rrect(c, x, y, w, h, 1, WOOD_WALL[0])
    c.rect(x + 1, y + 1, w - 2, h - 2, GLOW[1])
    c.rect(x + 1, y + 1, w - 2, 2, GLOW[2])
    c.rect(x + w // 2, y + 1, 1, h - 2, WOOD_WALL[0])
    c.rect(x + 1, y + h // 2, w - 2, 1, WOOD_WALL[0])
    for i, col in enumerate(stuff or []):
        cx = x + 2 + i * 3
        if cx + 2 < x + w - 1:
            c.rect(cx, y + h - 4, 2, 3, col)


def lantern(c, x, y):
    c.rect(x, y, 3, 1, hexc("3a2e28"))
    c.set(x + 1, y + 1, hexc("3a2e28"))
    rrect(c, x, y + 2, 3, 4, 0.8, GLOW[1])
    c.set(x + 1, y + 3, GLOW[2])
    c.rect(x, y + 6, 3, 1, hexc("3a2e28"))


def flower_box(c, x, y, w):
    rrect(c, x, y + 2, w, 3, 0.8, WOOD_WALL[1])
    c.rect(x, y + 2, w, 1, WOOD_WALL[3])
    for k in range(0, w - 1, 2):
        c.set(x + k, y + 1, P["leaf"][2])
        c.set(x + k + 1, y, FLOWERS[(k // 2) % len(FLOWERS)])


def vines(c, pts):
    for i, (x, y) in enumerate(pts):
        c.ellipse(x, y, 2.2, 1.8, P["leaf"][1 + i % 2])
        c.set(int(x), int(y) - 1, FLOWERS[(i % 2) * 4])


def sign_board(c, x, y, w, h):
    """글자 간판 (흰 판 + 나무 테두리). 글자는 게임이 그린다"""
    rrect(c, x, y, w, h, 2, WOOD_WALL[0])
    rrect(c, x + 1, y + 1, w - 2, h - 2, 1.5, CREAM_BOARD)
    c.rect(x + 2, y + h - 3, w - 4, 1, hexc("e2d2b2"))


def chimney(c, x, y, h, col=None):
    col = col or hexc("8a8574")
    rrect(c, x, y, 6, h, 1, col)
    c.rect(x, y, 6, 2, hexc("6f6a5c"))
    for xx, yy, r in ((x + 3, y - 2, 1.6), (x + 1, y - 4.5, 1.2)):
        c.ellipse(xx, yy, r, r, hexc("efe7d8"))


def cozy_shop(W, H, floor_rows, roof_pal, awn, board):
    """가게 공통 모양. 바닥 floor_rows 칸 + 위로 솟는 지붕. 돌려주는 값: (캔버스, 벽 위 y)"""
    c = Canvas(W, H)
    c.ellipse(W / 2, H - 1.5, W / 2 - 1, 1.8, SOFT_SHADOW)
    wall_top = H - floor_rows * T + 8
    plank_wall(c, 2, wall_top, W - 4, H - wall_top - 1)
    c.rect(2, H - 4, W - 4, 3, hexc("8a8574"))                          # 돌 기단
    for x in range(3, W - 3, 6):
        c.set(x, H - 3, hexc("6f6a5c"))
    for x in (2, W - 5):                                                  # 기둥
        c.rect(x, wall_top, 3, H - wall_top - 4, WOOD_WALL[0])
    gable_roof(c, 0, W, 6, wall_top + 1, roof_pal)
    c.rect(1, wall_top, W - 2, 2, WOOD_WALL[0])                           # 처마 들보
    sign_board(c, *board)
    if awn:
        awning(c, 5, wall_top + 3, W - 10, awn[0], awn[1], 5, awn[2])
    return c, wall_top


def shop_door(c, x, y):
    rrect(c, x, y, 14, 23, 2, WOOD_WALL[0])
    rrect(c, x + 1, y + 1, 12, 22, 1.5, WOOD_WALL[1])
    c.rect(x + 3, y + 3, 8, 6, GLOW[1]); c.rect(x + 7, y + 3, 1, 6, WOOD_WALL[0])
    c.set(x + 10, y + 13, hexc("f5c542"))


def make_general_store():
    """잡화점 (5x3칸, 80x86): 초록 기와 + 초록 줄무늬 차양 + 씨앗 진열창 + 덩굴꽃 (무드: 씨앗상점)"""
    W, H = 80, 86
    c, top = cozy_shop(W, H, 3, (hexc("3f6e4c"), hexc("2f5a3c"), hexc("5f8f66")),
                       (hexc("5f9a6d"), hexc("fbf3e1"), hexc("3f6e4c")), SIGNS["general_store"])
    chimney(c, 62, 15, 14)
    door_x = W // 2 - 7
    shop_door(c, door_x, H - 27)
    seeds = [hexc("e0715f"), hexc("7fb069"), hexc("f3d36b"), hexc("b49be0")]
    for x0 in (8, W - 26):
        glow_window(c, x0, H - 28, 18, 13, seeds)
        flower_box(c, x0 - 1, H - 15, 20)
    lantern(c, door_x - 5, top + 9); lantern(c, door_x + 16, top + 9)
    vines(c, [(4, 44), (7, 40), (10, 36), (13, 32), (16, 28), (3, 50), (5, 55), (19, 24)])
    c.outline(INK)
    c.save("general_store.png")


def make_blacksmith():
    """대장간 (4x3칸, 64x82): 짙은 슬레이트 지붕 + 갈색 차양 + 불빛 문 + 수레바퀴 + 망치 깃발 (무드)"""
    W, H = 64, 82
    c, top = cozy_shop(W, H, 3, (hexc("4a4d55"), hexc("383a41"), hexc("6a6e78")),
                       (hexc("8a5a3a"), hexc("ead7b5"), hexc("5b3a29")), SIGNS["blacksmith"])
    chimney(c, 48, 19, 14, hexc("7a7a7a"))
    rrect(c, 22, H - 26, 20, 22, 2, WOOD_WALL[0])                       # 넓은 문 + 화덕 불빛
    rrect(c, 23, H - 25, 18, 21, 1.5, hexc("4a2e1e"))
    c.ellipse(32, H - 11, 6, 4, hexc("f29b50")); c.ellipse(32, H - 10, 3, 2, GLOW[2])
    glow_window(c, W - 17, H - 26, 12, 10)
    cx, cy = 11, H - 18                                                  # 수레바퀴
    c.ellipse(cx, cy, 6, 6, WOOD_WALL[0]); c.ellipse(cx, cy, 4.5, 4.5, WOOD_WALL[3])
    for a in range(4):
        ang = a * math.pi / 4
        for r in range(1, 5):
            c.set(int(cx + math.cos(ang) * r), int(cy + math.sin(ang) * r), WOOD_WALL[0])
            c.set(int(cx - math.cos(ang) * r), int(cy - math.sin(ang) * r), WOOD_WALL[0])
    rrect(c, W - 9, top + 10, 7, 14, 0.5, hexc("3a3d45"))                # 망치 깃발
    for k in range(5):
        c.set(W - 8 + k, top + 13 + k, hexc("d9d4c8")); c.set(W - 4 - k, top + 13 + k, hexc("d9d4c8"))
    c.rect(W - 9, top + 12, 3, 2, hexc("d9d4c8")); c.rect(W - 5, top + 12, 3, 2, hexc("d9d4c8"))
    c.rect(W - 9, top + 8, 7, 2, WOOD_WALL[0])
    lantern(c, 17, top + 9); lantern(c, 44, top + 9)
    c.outline(INK)
    c.save("blacksmith.png")


def make_machine_shop():
    """기계상점 (5x3칸, 80x86): 청록 지붕 + 톱니 + 구리 보일러·파이프 + 파랑 줄무늬 차양 (무드)"""
    W, H = 80, 86
    c, top = cozy_shop(W, H, 3, (hexc("4f6f63"), hexc("3c574d"), hexc("6f9184")),
                       (hexc("507a97"), hexc("f2f0e6"), hexc("3a5a72")), SIGNS["machine_shop"])
    for gx, gy, r in ((34, 17, 5), (44, 19, 3.5)):                        # 박공 톱니
        for a in range(8):
            ang = a * math.pi / 4 + 0.2
            c.rect(int(gx + math.cos(ang) * (r + 0.6)) - 1, int(gy + math.sin(ang) * (r + 0.6)) - 1, 2, 2, hexc("7d838c"))
        c.ellipse(gx, gy, r, r, hexc("9aa0a8")); c.ellipse(gx, gy, r * 0.45, r * 0.45, hexc("4f6f63"))
    rrect(c, 1, top - 4, 9, H - top, 3, hexc("a8653a"))                  # 구리 보일러 + 파이프
    c.rect(2, top - 2, 2, H - top - 6, hexc("cf8a52"))
    for yy in (top + 4, top + 16):
        c.rect(1, yy, 9, 1, hexc("7a4528"))
    c.rect(4, 2, 3, top - 6, hexc("6a6a70")); c.rect(4, 2, 1, top - 6, hexc("8a8a92"))
    door_x = W // 2 - 7
    shop_door(c, door_x, H - 27)
    parts = [hexc("9aa0a8"), hexc("6f7a86"), hexc("c46a3a"), hexc("5f8a6a")]
    glow_window(c, 13, H - 28, 16, 12, parts)
    glow_window(c, W - 26, H - 28, 18, 12, parts)
    lantern(c, door_x - 5, top + 9); lantern(c, door_x + 16, top + 9)
    c.outline(INK)
    c.save("machine_shop.png")


def make_recipe_shop():
    """레시피 상점 (4x3칸, 64x82): 붉은 기와 + 분홍 줄무늬 차양 + 꽃 상자 (무드 톤)"""
    W, H = 64, 82
    c, top = cozy_shop(W, H, 3, (hexc("b8604a"), hexc("94483a"), hexc("d98a6e")),
                       (hexc("e59a9a"), hexc("fbf3e1"), hexc("b85d44")), SIGNS["recipe_shop"])
    chimney(c, 10, 19, 14, hexc("c7826a"))
    shop_door(c, 25, H - 27)
    glow_window(c, 6, H - 26, 14, 11, [hexc("e8a65a"), hexc("fbf6ec"), hexc("d9534f")])
    glow_window(c, W - 20, H - 26, 14, 11, [hexc("fbf6ec"), hexc("e8a65a"), hexc("7fb069")])
    flower_box(c, 5, H - 15, 16); flower_box(c, W - 21, H - 15, 16)
    lantern(c, 20, top + 9); lantern(c, 41, top + 9)
    c.outline(INK)
    c.save("recipe_shop.png")


def make_mood_props():
    w = P["wood"]
    st = [hexc("6f6a5c"), hexc("8a8574"), hexc("a39d8a"), hexc("bdb7a3")]
    water = P["water"]
    # 새싹 석상 분수 (3x3칸, 48x56): 둥근 돌 수반 + 새싹 머리 석상 + 물줄기 + 수련
    c = Canvas(48, 56)
    c.ellipse(24, 50, 23, 5, SOFT_SHADOW)
    c.ellipse(24, 42, 23, 12, st[0]); c.ellipse(24, 41, 23, 11.5, st[2])
    c.ellipse(24, 41.5, 19, 9, water[1]); c.ellipse(20, 40, 9, 3, water[2])
    for x, y in ((12, 44), (34, 39), (28, 46)):
        c.ellipse(x, y, 2.5, 1.5, P["leaf"][2]); c.set(x, y - 1, FLOWERS[1])
    rrect(c, 19, 34, 10, 7, 2, st[1]); c.rect(19, 34, 10, 1, st[3])      # 받침
    c.ellipse(24, 25, 10, 9.5, st[1]); c.ellipse(24, 24.5, 9.5, 9, st[2])  # 둥근 몸통 = 머리
    c.ellipse(20.5, 21, 4, 3.5, st[3])
    c.rect(20, 25, 2, 2, st[0]); c.rect(27, 25, 2, 2, st[0])             # 눈·볼·입
    c.set(18, 28, hexc("c9a59a")); c.set(30, 28, hexc("c9a59a")); c.rect(23, 29, 3, 1, st[0])
    c.rect(24, 11, 1, 6, P["leaf"][1])                                     # 새싹
    c.ellipse(20, 11, 4, 2.4, P["leaf"][2]); c.ellipse(28.5, 10.5, 4, 2.4, P["leaf"][3])
    c.set(19, 10, P["leaf"][4]); c.set(28, 9, P["leaf"][4])
    for sx in (-1, 1):                                                   # 물줄기
        for k in range(9):
            c.set(24 + sx * (11 + k // 2), 30 + k + (k * k) // 10, water[3])
    c.outline(INK)
    c.save("fountain.png")

    # 꽃 화분 상자 (1칸) 3색
    for i, cols in enumerate([(FLOWERS[0], FLOWERS[3]), (FLOWERS[1], FLOWERS[0]), (FLOWERS[2], FLOWERS[4])]):
        c = Canvas(T, 18)
        c.ellipse(8, 16.5, 7, 1.2, SOFT_SHADOW)
        rrect(c, 1, 9, 14, 7, 1.2, w[2]); c.rect(2, 9, 12, 1, w[3]); c.rect(1, 12, 14, 1, w[1])
        c.ellipse(8, 7, 7, 4.5, P["leaf"][1]); c.ellipse(6, 6, 4, 3, P["leaf"][2])
        for k, (x, y) in enumerate(((3, 5), (7, 3), (11, 5), (5, 8), (10, 7), (8, 6))):
            c.set(x, y, cols[k % 2]); c.set(x + 1, y, cols[k % 2])
        c.outline(INK)
        c.save("planter_%d.png" % i)

    # 꽃밭 (1칸) 3종
    for i in range(3):
        rng = random.Random(40 + i)
        c = Canvas(T, T)
        c.ellipse(8, 10, 7.5, 5.5, P["leaf"][0]); c.ellipse(8, 9, 7, 5, P["leaf"][1]); c.ellipse(6, 8, 4, 3, P["leaf"][2])
        for _ in range(9):
            x, y = rng.randrange(2, 14), rng.randrange(5, 13)
            col = FLOWERS[(rng.randrange(5) + i) % 5]
            c.set(x, y, col); c.set(x + 1, y, col); c.set(x, y - 1, col)
        c.outline(INK)
        c.save("flowerbed_%d.png" % i)

    # 나무 아치 (4칸 폭, 64x60): 기둥 둘 + 들보 + 간판(글자는 게임) + 등불 + 덩굴
    c = Canvas(64, 60)
    for x in (4, 54):
        c.ellipse(x + 3, 58, 5, 1.5, SOFT_SHADOW)
        c.rect(x, 12, 6, 46, w[1]); c.rect(x + 1, 12, 2, 46, w[2])
    rrect(c, 0, 14, 64, 5, 1, w[1]); c.rect(1, 14, 62, 1, w[3])
    sign_board(c, *SIGNS["arch"])
    lantern(c, 6, 20); lantern(c, 55, 20)
    vines(c, [(4, 26), (9, 30), (5, 35), (58, 28), (55, 33), (59, 38)])
    c.outline(INK)
    c.save("arch.png")

    # "내 농장" 팻말 (64x34): 왼쪽(농장 쪽)이 뾰족한 판 + 기둥 둘. 글자는 게임이 얹는다
    c = Canvas(64, 34)
    c.ellipse(32, 32.5, 22, 1.3, SOFT_SHADOW)
    for x in (16, 46):
        c.rect(x, 18, 3, 15, w[1]); c.rect(x, 18, 1, 15, w[2])
    bx, by, bw, bh = SIGNS["farm_sign"]
    sign_board(c, bx, by, bw, bh)
    for k in range(5):
        c.rect(bx - 1 - k, by + 2 + k, 1, bh - 4 - 2 * k, WOOD_WALL[0])
    vines(c, [(60, 6), (58, 18), (61, 13)])
    c.outline(INK)
    c.save("farm_sign.png")

    # 이정표 (24x36): 기둥 + 화살표 판 셋 (새싹·망치·톱니 그림)
    c = Canvas(24, 36)
    c.ellipse(12, 34.5, 5, 1.2, SOFT_SHADOW)
    c.rect(11, 4, 3, 31, w[1]); c.rect(11, 4, 1, 31, w[2])
    for i, y in enumerate((5, 14, 23)):
        right = i != 1
        x0 = 1 if right else 4
        rrect(c, x0, y, 19, 7, 1, w[2]); c.rect(x0 + 1, y, 17, 1, w[3])
        for k in range(3):
            tx = (x0 + 19 + k) if right else (x0 - 1 - k)
            c.rect(tx, y + 1 + k, 1, 5 - 2 * k, w[2])
        ix = x0 + 4
        if i == 0:
            c.set(ix, y + 3, P["leaf"][2]); c.set(ix + 1, y + 2, P["leaf"][3]); c.set(ix + 1, y + 4, P["leaf"][1])
        elif i == 1:
            c.rect(ix + 7, y + 2, 4, 2, hexc("5a5a62")); c.rect(ix + 8, y + 4, 1, 2, w[0])
        else:
            c.ellipse(ix + 1, y + 3.5, 2, 2, hexc("8b8f96")); c.set(ix + 1, y + 3, w[2])
    c.outline(INK)
    c.save("signpost.png")

    # 칠판 간판 (16x20): 새싹 / 모루 / 톱니
    chalk = hexc("e8e8d8")
    def seed_icon(cv):
        cv.set(7, 8, P["leaf"][3]); cv.set(8, 7, P["leaf"][3]); cv.set(6, 7, P["leaf"][3]); cv.rect(7, 9, 1, 3, chalk)
    def anvil_icon(cv):
        cv.rect(5, 8, 7, 2, chalk); cv.rect(7, 10, 3, 2, chalk)
    def gear_icon(cv):
        cv.ellipse(8, 9.5, 3, 3, chalk); cv.set(8, 9, hexc("2f3b2f"))
    for name, draw in (("seed", seed_icon), ("smith", anvil_icon), ("gear", gear_icon)):
        c = Canvas(T, 20)
        c.ellipse(8, 18.5, 6, 1.2, SOFT_SHADOW)
        c.rect(2, 12, 1, 7, w[0]); c.rect(13, 12, 1, 7, w[0])
        rrect(c, 2, 3, 12, 12, 1, w[1]); c.rect(3, 4, 10, 10, hexc("2f3b2f"))
        draw(c)
        c.outline(INK)
        c.save("chalk_%s.png" % name)

    # 씨앗 수레 (32x26)
    c = Canvas(32, 26)
    c.ellipse(16, 24, 14, 1.5, SOFT_SHADOW)
    rrect(c, 2, 11, 26, 8, 1, w[2]); c.rect(3, 11, 24, 1, w[3]); c.rect(2, 15, 26, 1, w[1])
    c.rect(27, 8, 4, 2, w[1])
    for x in (8, 22):
        c.ellipse(x, 21, 3.5, 3.5, w[0]); c.ellipse(x, 21, 1.5, 1.5, w[3])
    for x, col in ((6, hexc("e6d3a8")), (13, hexc("e6d3a8")), (20, hexc("d9c39a"))):
        rrect(c, x, 4, 7, 8, 2, col); c.rect(x + 2, 6, 3, 2, P["leaf"][2])
    for x in (4, 26):
        c.ellipse(x, 9, 2.5, 2, P["leaf"][2]); c.set(x, 8, FLOWERS[1])
    c.outline(INK)
    c.save("seed_cart.png")

    # 모루 (16x16)
    c = Canvas(T, T)
    c.ellipse(8, 14.5, 6, 1.2, SOFT_SHADOW)
    rrect(c, 5, 10, 7, 4, 1, w[1])
    c.rect(2, 5, 12, 3, hexc("4a4d55")); c.rect(5, 8, 6, 2, hexc("4a4d55")); c.rect(0, 5, 3, 2, hexc("4a4d55"))
    c.rect(3, 5, 10, 1, hexc("7a7e88"))
    c.outline(INK)
    c.save("anvil.png")

    # 기계 상자 더미 (32x22)
    c = Canvas(32, 22)
    c.ellipse(16, 20.5, 14, 1.3, SOFT_SHADOW)
    for x, y, col in ((1, 9, hexc("6f7a86")), (16, 10, hexc("5f8a6a")), (8, 1, hexc("c46a3a"))):
        rrect(c, x, y, 14, 10, 1, col); c.rect(x + 1, y + 1, 12, 1, hexc("c9ccd1"))
        c.ellipse(x + 7, y + 5.5, 2.5, 2.5, hexc("9aa0a8")); c.set(x + 7, y + 5, hexc("4a4d55"))
    c.outline(INK)
    c.save("machine_crates.png")

    # 마을 상점 노점 (48x42, 장식): 분홍 줄무늬 천막 + 채소 상자 + 깃발 줄
    c = Canvas(48, 42)
    c.ellipse(24, 40.5, 22, 1.5, SOFT_SHADOW)
    for x in (3, 42):
        c.rect(x, 10, 3, 30, w[1])
    rrect(c, 1, 26, 46, 13, 1.5, w[2]); c.rect(2, 26, 44, 1, w[3])
    for i, col in enumerate((hexc("e2603e"), hexc("f0a83a"), hexc("8fb36a"), hexc("d9534f"), hexc("f3d36b"))):
        bx = 4 + i * 8
        rrect(c, bx, 20, 7, 6, 1, w[1])
        for k in range(2):
            c.ellipse(bx + 2 + k * 3, 19.5, 1.7, 1.7, col)
    awning(c, 0, 4, 48, hexc("e59a9a"), hexc("fbf3e1"), 7, hexc("b85d44"))
    for x in range(4, 46, 8):
        c.set(x, 1, (hexc("7fb069"), hexc("f3d36b"), hexc("e59a9a"))[(x // 8) % 3])
    lantern(c, 6, 13)
    c.outline(INK)
    c.save("market_stall.png")

    # 배송함 나루터 상자 (32x28, 장식)
    c = Canvas(32, 28)
    c.ellipse(16, 26.5, 14, 1.3, SOFT_SHADOW)
    rrect(c, 3, 12, 20, 13, 1, w[2]); c.rect(4, 12, 18, 2, w[3]); c.rect(3, 18, 20, 1, w[1])
    rrect(c, 8, 4, 10, 7, 1, CREAM_BOARD); c.rect(11, 6, 4, 3, w[1])
    c.rect(25, 3, 2, 22, w[0]); lantern(c, 25, 5)
    rrect(c, 18, 19, 12, 7, 1, hexc("d9c39a"))
    c.outline(INK)
    c.save("dock_box.png")

    # 수련 2종, 오리 (물 위, 장식)
    for i in range(2):
        c = Canvas(T, T)
        c.ellipse(7 + i, 8, 5, 3, P["leaf"][1]); c.ellipse(6 + i, 7.5, 3.5, 2, P["leaf"][2])
        c.set(9 + i, 8, P["water"][1])
        if i == 1:
            c.set(5, 6, FLOWERS[1]); c.set(6, 5, FLOWERS[0])
        c.save("lily_%d.png" % i)
    c = Canvas(T, T)
    c.ellipse(8, 11, 5, 1, P["water"][2])
    c.ellipse(7, 9, 5, 3, hexc("fbfbf4")); c.ellipse(11, 6, 2.2, 2.2, hexc("fbfbf4"))
    c.rect(13, 6, 2, 1, hexc("f0a83a")); c.set(11, 5, INK)
    c.outline(INK)
    c.save("duck.png")


# ---------------------------------------------------------------- 가게 실내 공통 소품 (등·계산대·깔개·화분·통·새싹/톱니/모루 무늬)
#   방 그림은 아래 make_interior_store · make_interior_smith · make_interior_machine (실내 개편: 18x12칸, 288x192)

def wall_lamp(c, x, y):
    c.rect(x + 1, y, 1, 3, hexc("3a2e28"))
    rrect(c, x - 1, y + 3, 5, 5, 1.2, GLOW[1]); c.set(x + 1, y + 4, GLOW[2])


def counter(c, x0, x1, y):
    rrect(c, x0, y + 2, x1 - x0, T - 1, 1.5, WOOD_WALL[0])
    rrect(c, x0, y + 2, x1 - x0, 5, 1.5, WOOD_WALL[3])
    c.rect(x0 + 1, y + 7, x1 - x0 - 2, 1, WOOD_WALL[1])
    for x in range(x0 + 6, x1 - 4, 10):
        c.rect(x, y + 8, 1, T - 8, WOOD_WALL[1])


def rug(c, x, y, w, h, col, col_d, emblem):
    rrect(c, x, y, w, h, 2, col_d); rrect(c, x + 2, y + 2, w - 4, h - 4, 1.5, col)
    for xx in range(x + 3, x + w - 3, 3):
        c.set(xx, y, col_d); c.set(xx, y + h - 1, col_d)
    emblem(c, x + w // 2, y + h // 2)


def plant_pot(c, x, y):
    rrect(c, x + 3, y + 9, 10, 7, 1.5, hexc("b8653a")); c.rect(x + 3, y + 9, 10, 1, hexc("d9875a"))
    c.ellipse(x + 8, y + 6, 6, 5, P["leaf"][1]); c.ellipse(x + 6, y + 4, 3.5, 3, P["leaf"][2])
    c.set(x + 10, y + 3, FLOWERS[1]); c.set(x + 5, y + 7, FLOWERS[0])


def barrel(c, x, y, top=None):
    rrect(c, x + 2, y + 1, 12, 15, 2.5, WOOD_WALL[1])
    c.rect(x + 2, y + 5, 12, 1, hexc("5b3a29")); c.rect(x + 2, y + 11, 12, 1, hexc("5b3a29"))
    c.ellipse(x + 8, y + 2.5, 5.5, 2, top or WOOD_WALL[2])


def sprout(c, x, y, col=None):
    col = col or hexc("f6ead2")
    c.set(x, y + 1, col); c.set(x, y + 2, col); c.set(x - 1, y, col); c.set(x + 1, y, col); c.set(x - 2, y - 1, col); c.set(x + 2, y - 1, col)


def gear_mark(c, x, y, col=None):
    col = col or hexc("f6ead2")
    c.ellipse(x, y, 3, 3, col); c.set(x, y, hexc("4f7a4a"))
    for dx, dy in ((0, -4), (0, 4), (-4, 0), (4, 0)):
        c.set(x + dx, y + dy, col)


def anvil_mark(c, x, y, col=None):
    col = col or hexc("f6ead2")
    c.rect(x - 4, y - 2, 8, 2, col); c.rect(x - 1, y, 3, 2, col); c.rect(x - 3, y + 2, 7, 1, col)


# ---------------------------------------------------------------- 씨앗상점 실내 (실내 개편: 18x12칸, 288x192)
#   무드: 밝은 나무 마루 · 크림 회벽 · 씨앗 봉투 장 · 모종·꽃 진열대 · 초록 깔개 · 노란 등불 · 벽 덩굴.
#   칸 배치는 scripts/world/interior.gd 의 "store" rows 와 같다 (뒷벽 2줄, NPC (9,2) 계산대 뒤, 문 (8,11)(9,11)).
#   가구는 자기 칸 안에 그리고, 벽에 붙은 가구만 위쪽 벽까지 올라간다 (플레이어가 가구 뒤로 들어가 보이지 않게)

STORE_W, STORE_H = 18, 12
DARK = hexc("3d2618")
PACKS = [hexc("f3e7c8"), hexc("d9eac0"), hexc("f0d0a0"), hexc("f0c0c8"), hexc("dcd4f0")]
GREEN = [hexc("3f6e4c"), hexc("5f9a5d"), hexc("7fb069"), hexc("a8d08a")]
TERRA = [hexc("8a4a2a"), hexc("b8653a"), hexc("d9875a")]


def dk(col, f=0.78):
    return (int(col[0] * f), int(col[1] * f), int(col[2] * f), 255)


def lt(col, f=0.25):
    return tuple(int(col[i] + (255 - col[i]) * f) for i in range(3)) + (255,)


def obox(c, x, y, w, h, col, r=1.5):
    """진한 테두리 상자 (가구 몸통)"""
    rrect(c, x, y, w, h, r, DARK)
    rrect(c, x + 1, y + 1, w - 2, h - 2, max(0.5, r - 1), col)


def glow_pool(c, cx, cy, rx, ry, a=30):
    """등불이 바닥에 비치는 노란 빛 웅덩이 (겹쳐 칠해 가운데가 더 밝다)"""
    for f in (1.0, 0.72, 0.45):
        c.ellipse(cx, cy, rx * f, ry * f, (255, 214, 140, a))


def floor_shadow(c, x, y, w):
    c.rect(x + 1, y, w - 2, 2, SOFT_SHADOW)


def packet7(c, x, y, k):
    """7x9 씨앗 봉투: 봉투 색 + 그림 (해바라기·토마토·당근·새싹·제비꽃)"""
    base = PACKS[k % 5]
    rrect(c, x, y, 7, 9, 0.8, base)
    c.rect(x + 1, y, 5, 1, lt(base, 0.5)); c.rect(x + 1, y + 8, 5, 1, dk(base, 0.82))
    cx, cy = x + 3, y + 4
    icon = (k * 3 + 1) % 5
    if icon == 0:
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            c.set(cx + dx, cy + dy, hexc("f3c94a"))
        c.set(cx, cy, hexc("7a4a2a"))
    elif icon == 1:
        c.rect(cx - 1, cy, 3, 2, hexc("e0533f")); c.set(cx, cy - 1, GREEN[1])
    elif icon == 2:
        c.set(cx, cy - 1, GREEN[2]); c.rect(cx, cy, 1, 3, hexc("ec8a32")); c.set(cx - 1, cy, hexc("ec8a32"))
    elif icon == 3:
        c.set(cx, cy + 1, GREEN[1]); c.set(cx, cy + 2, GREEN[1]); c.set(cx - 1, cy, GREEN[2]); c.set(cx + 1, cy, GREEN[2])
    else:
        c.set(cx, cy, hexc("8a6ad0")); c.set(cx - 1, cy - 1, hexc("b49be0")); c.set(cx + 1, cy - 1, hexc("b49be0")); c.set(cx, cy + 1, GREEN[1])


def leaves(c, cx, cy, rx, ry, seed, n=None):
    """잎 덩어리: 진한 바탕 위에 밝은 잎 점을 흩뿌린다"""
    rnd = random.Random(seed)
    c.ellipse(cx, cy, rx, ry, P["leaf"][1])
    c.ellipse(cx - rx * 0.25, cy - ry * 0.3, rx * 0.7, ry * 0.6, P["leaf"][2])
    for _ in range(n or int(rx * ry / 3) + 2):
        x = cx + rnd.uniform(-rx, rx) * 0.8
        y = cy + rnd.uniform(-ry, ry) * 0.8
        c.set(int(x), int(y), P["leaf"][rnd.choice((3, 3, 4))])
    c.set(int(cx + rx * 0.4), int(cy + ry * 0.5), P["leaf"][0])


def blooms(c, cx, cy, rx, ry, seed, cols, n):
    rnd = random.Random(seed)
    for _ in range(n):
        x = int(cx + rnd.uniform(-rx, rx))
        y = int(cy + rnd.uniform(-ry, ry))
        col = rnd.choice(cols)
        c.set(x, y, col); c.set(x + 1, y, col); c.set(x, y - 1, col); c.set(x, y + 1, dk(col, 0.85))
        c.set(x + 1, y + 1, hexc("f3c94a") if col != hexc("f3c94a") else hexc("b8653a"))


def sunflower(c, x, y, h):
    """x, y = 줄기 밑동. h = 줄기 길이"""
    c.rect(x, y - h, 1, h, GREEN[0]); c.set(x - 1, y - h // 2, GREEN[1]); c.set(x + 1, y - h // 2 - 2, GREEN[1])
    c.ellipse(x + 0.5, y - h - 1, 3.2, 3.2, hexc("f3c94a")); c.ellipse(x + 0.5, y - h - 1, 1.4, 1.4, hexc("7a4a2a"))


def mini_pot(c, x, y, kind, seed=0):
    """8칸 폭 토분 (x, y 는 화분 윗변 왼쪽). kind: 0 잎 · 1 흰꽃 · 2 분홍꽃 · 3 해바라기 · 4 늘어진 덩굴"""
    if kind == 3:
        leaves(c, x + 4, y - 2, 3.5, 2, seed, 4)
        sunflower(c, x + 3, y, 8)
    elif kind == 4:
        leaves(c, x + 4, y - 2, 4.5, 2.5, seed, 6)
        for k, side in enumerate((x - 1, x + 8)):
            for j in range(4):
                c.set(side + (j % 2) * (1 if k == 0 else -1), y + 1 + j * 2, P["leaf"][2 + j % 2])
    else:
        leaves(c, x + 4, y - 3, 4.5, 3.5, seed, 6)
        if kind == 1:
            blooms(c, x + 4, y - 4, 3, 2, seed + 1, [FLOWERS[0], FLOWERS[4]], 3)
        elif kind == 2:
            blooms(c, x + 4, y - 4, 3, 2, seed + 1, [FLOWERS[1], hexc("e0715f")], 3)
    rrect(c, x, y, 8, 6, 1, TERRA[1]); c.rect(x, y, 8, 2, TERRA[2]); c.rect(x + 1, y + 5, 6, 1, TERRA[0])


def crate(c, x, y, w, h, col=None):
    col = col or WOOD_WALL[2]
    obox(c, x, y, w, h, col, 1)
    c.rect(x + 1, y + 1, w - 2, 2, lt(col, 0.2))
    for yy in range(y + 4, y + h - 1, 4):
        c.rect(x + 1, yy, w - 2, 1, dk(col, 0.8))


def jar(c, x, y, fill):
    rrect(c, x, y + 2, 6, 7, 1.2, hexc("cfe3e0"))
    c.rect(x + 1, y + 5, 4, 3, fill); c.set(x + 1, y + 3, hexc("f4fbfa"))
    c.rect(x + 1, y, 4, 2, WOOD_WALL[0]); c.rect(x + 1, y, 4, 1, WOOD_WALL[2])


def sack(c, x, y, w, h, seed_col=None):
    rrect(c, x, y + 3, w, h - 3, 3, hexc("cdb88a"))
    rrect(c, x + 1, y + 3, w - 2, h - 5, 2.5, hexc("e6d3a8"))
    c.rect(x + 3, y + 1, w - 6, 3, hexc("d9c39a")); c.rect(x + 3, y + 4, w - 6, 1, hexc("a8875a"))
    sprout(c, x + w // 2, y + h // 2 + 1, GREEN[1])
    if seed_col:
        c.ellipse(x + w / 2, y + 2, w / 2 - 3, 1.5, seed_col)


def vine_drape(c, x, y, length, seed, side=1):
    """벽·가구 위에서 아래로 늘어진 덩굴"""
    rnd = random.Random(seed)
    for j in range(length):
        xx = x + int(math.sin(j * 0.7 + seed) * 1.5)
        c.set(xx, y + j, P["leaf"][0])
        if j % 3 == 0:
            c.set(xx + side, y + j, P["leaf"][rnd.choice((2, 3))]); c.set(xx + side, y + j + 1, P["leaf"][2])
        if j % 5 == 2:
            c.set(xx - side, y + j, P["leaf"][3])
        if j % 9 == 4 and rnd.random() < 0.6:
            c.set(xx + side * 2, y + j, FLOWERS[rnd.choice((0, 1, 4))])


def make_interior_store():
    W, H = STORE_W * T, STORE_H * T
    c = Canvas(W, H)
    # ---- 바닥: 따뜻한 가로 판자 (이음매 엇갈림, 판마다 색이 조금 다름)
    fl = [hexc("b8784a"), hexc("c08250"), hexc("c88b5a"), hexc("9a6038"), hexc("d69c6a")]
    for y in range(2 * T, H - T + 4):
        band = (y - 2 * T) // 6
        for x in range(T - 4, W - T + 4):
            seam = (x + band * 19) % 52
            col = fl[(band * 5 + (x + band * 19) // 52) % 3]
            if (y - 2 * T) % 6 == 5 or seam == 0:
                col = fl[3]
            elif (y - 2 * T) % 6 == 0:
                col = lt(col, 0.08)
            elif seam in (12, 33) and (y - 2 * T) % 6 == 2:
                col = dk(col, 0.9)   # 나뭇결 옹이
            c.set(x, y, col)
    # ---- 뒷벽 (2칸 높이): 윗보 · 크림 회벽 · 기둥 · 나무 징두리
    c.rect(0, 0, W, 3, WOOD_WALL[0]); c.rect(0, 3, W, 1, DARK)
    c.rect(0, 4, W, 17, hexc("eadbbd"))
    for x in range(4, W, 7):
        c.set(x, 6 + (x * 5) % 13, hexc("e0cfae"))
    for x in (T - 4, 6 * T + 6, 12 * T - 6, W - T + 1):
        c.rect(x, 4, 3, 17, WOOD_WALL[1]); c.rect(x, 4, 1, 17, WOOD_WALL[2])
    c.rect(0, 21, W, 1, WOOD_WALL[3]); c.rect(0, 22, W, 9, WOOD_WALL[2])
    for x in range(2, W, 6):
        c.rect(x, 22, 1, 9, WOOD_WALL[1])
    c.rect(0, 31, W, 1, DARK); c.rect(0, 32, W, 3, SOFT_SHADOW)
    # ---- 옆벽 · 앞벽 (두꺼운 나무, 안쪽 모서리 밝게)
    for x0 in (0, W - T + 4):
        c.rect(x0, 0, T - 4, H, WOOD_WALL[0])
        c.rect(x0 + (T - 6 if x0 == 0 else 0), 0, 2, H, WOOD_WALL[1])
        c.rect(x0 + (0 if x0 == 0 else T - 5), 0, 1, H, DARK)
        for yy in range(6, H, 12):
            c.rect(x0 + 2, yy, T - 8, 1, dk(WOOD_WALL[0], 0.85))
    c.rect(T - 4, 2 * T, 2, H - 3 * T, SOFT_SHADOW); c.rect(W - T + 2, 2 * T, 2, H - 3 * T, SOFT_SHADOW)
    c.rect(0, H - T + 4, W, T - 4, WOOD_WALL[0]); c.rect(0, H - T + 4, W, 1, WOOD_WALL[3]); c.rect(0, H - 1, W, 1, DARK)
    for x in range(3, W, 9):
        c.rect(x, H - T + 6, 1, T - 7, dk(WOOD_WALL[0], 0.85))
    c.rect(8 * T, H - T + 4, 2 * T, T - 4, hexc("6a4428"))                   # 문 자리 + 문턱
    c.rect(8 * T, H - T + 4, 2 * T, 2, hexc("4a2e1e")); c.rect(8 * T + 2, H - 3, 2 * T - 4, 2, hexc("c8b9a2"))
    for px in (8 * T - 4, 10 * T):                                           # 문 기둥 + 등불
        obox(c, px, H - T - 2, 4, T + 2, WOOD_WALL[1], 0.5)
    lantern(c, 8 * T - 11, H - T - 2); lantern(c, 10 * T + 8, H - T - 2)

    # ---- 깔개 (지나갈 수 있음): 가운데 진열대 밑 초록 깔개 · 왼쪽 베이지 깔개 · 오른쪽 작은 깔개 · 문 앞 깔개
    rug(c, 5 * T + 6, 5 * T + 10, 7 * T + 4, 3 * T + 6, GREEN[1], GREEN[0], lambda cv, x, y: None)
    for xx in range(5 * T + 12, 12 * T + 6, 9):
        sprout(c, xx, 8 * T + 9, lt(GREEN[1], 0.45))
    rx0, ry0, rw, rh = 3 * T + 2, 4 * T + 12, 2 * T, 4 * T - 6                 # 왼쪽 베이지 줄무늬 깔개 (술 달림)
    rrect(c, rx0, ry0, rw, rh, 1, hexc("c9ad7e"))
    rrect(c, rx0 + 1, ry0 + 1, rw - 2, rh - 2, 0.5, hexc("ecdcb8"))
    for yy in range(ry0 + 3, ry0 + rh - 2, 8):
        c.rect(rx0 + 2, yy, rw - 4, 1, hexc("b8604a")); c.rect(rx0 + 2, yy + 2, rw - 4, 1, GREEN[1])
        for xx in range(rx0 + 4, rx0 + rw - 3, 6):
            c.set(xx, yy + 5, hexc("d9c39a")); c.set(xx + 1, yy + 4, hexc("d9c39a")); c.set(xx + 1, yy + 6, hexc("d9c39a")); c.set(xx + 2, yy + 5, hexc("d9c39a"))
    for xx in range(rx0 + 1, rx0 + rw - 1, 2):
        c.set(xx, ry0 - 1, hexc("efe0bf")); c.set(xx, ry0 + rh, hexc("efe0bf"))
    rug(c, 13 * T + 2, 3 * T + 8, 2 * T - 4, 2 * T + 4, GREEN[1], GREEN[0], lambda cv, x, y: sprout(cv, x, y, lt(GREEN[1], 0.45)))
    for yy in range(3 * T + 12, 5 * T + 8, 4):
        c.set(13 * T + 4, yy, lt(GREEN[1], 0.3)); c.set(15 * T - 5, yy, lt(GREEN[1], 0.3))
    rug(c, 8 * T + 2, 10 * T + 1, 2 * T - 4, 12, GREEN[1], GREEN[0], lambda cv, x, y: sprout(cv, x, y - 1, lt(GREEN[1], 0.5)))

    # ---- 등불 빛 웅덩이 (바닥)
    for cx, cy, rx, ry in ((7 * T + 4, 3 * T, 22, 10), (12 * T - 4, 3 * T, 22, 10), (2 * T, 5 * T, 18, 14), (W - 2 * T, 5 * T, 18, 14),
                           (9 * T, 9 * T, 30, 14), (9 * T, 10 * T + 8, 26, 9)):
        glow_pool(c, cx, cy, rx, ry)

    # ---- 뒷벽 장식: 새싹 깃발 (NPC 뒤) · 창문 · 말린 꽃 다발 · 벽등 · 시계
    c.rect(9 * T - 14, 3, 30, 2, WOOD_WALL[0])
    rrect(c, 9 * T - 12, 5, 26, 18, 1, GREEN[0]); rrect(c, 9 * T - 11, 6, 24, 15, 1, hexc("f6ead2"))
    for k in range(4):
        c.set(9 * T - 11 + k * 7 + 3, 22, GREEN[0])
    c.rect(9 * T + 1, 11, 2, 7, GREEN[1])
    c.ellipse(9 * T - 2, 10, 3.5, 2, GREEN[1]); c.ellipse(9 * T + 6, 10, 3.5, 2, GREEN[1])
    c.set(9 * T - 3, 9, GREEN[2]); c.set(9 * T + 6, 9, GREEN[2])
    obox(c, 7 * T + 2, 6, 18, 14, WOOD_WALL[1], 0.5)                          # 창문 (따뜻한 바깥 빛)
    c.rect(7 * T + 4, 8, 14, 10, hexc("fbe7b0")); c.rect(7 * T + 10, 8, 2, 10, WOOD_WALL[1]); c.rect(7 * T + 4, 12, 14, 1, WOOD_WALL[1])
    c.rect(7 * T + 4, 8, 6, 4, hexc("fff3cf"))
    mini_pot(c, 7 * T + 7, 17, 2, 41)
    for k, col in enumerate((FLOWERS[2], FLOWERS[0], hexc("e8a65a"))):        # 말린 꽃 다발 (오른쪽)
        bx = 10 * T + 8 + k * 6
        c.set(bx + 1, 4, WOOD_WALL[0]); c.rect(bx, 5, 3, 2, hexc("c9a46a"))
        for j in range(6):
            c.set(bx + (j % 3), 7 + j, col if j < 4 else GREEN[0])
    c.ellipse(11 * T + 12, 12, 5, 5, WOOD_WALL[0]); c.ellipse(11 * T + 12, 12, 4, 4, hexc("fbf6ec"))   # 시계
    c.rect(11 * T + 12, 9, 1, 3, DARK); c.rect(11 * T + 12, 12, 2, 1, DARK)
    wall_lamp(c, 7 * T - 9, 12); wall_lamp(c, 12 * T - 5, 12)
    wall_lamp(c, 4, 66); wall_lamp(c, W - 7, 66)                               # 옆벽 등

    # ---- S 씨앗 봉투 장 (x1~4): 봉투 칸 2줄 + 서랍 + 위에 화분
    x0, x1 = T, 5 * T
    floor_shadow(c, x0, 3 * T, x1 - x0)
    obox(c, x0, 10, x1 - x0, 3 * T - 10, WOOD_WALL[1])
    c.rect(x0 + 1, 11, x1 - x0 - 2, 3, WOOD_WALL[3])
    for row, yy in enumerate((15, 26)):
        c.rect(x0 + 3, yy - 1, x1 - x0 - 6, 11, hexc("6e4426"))
        for k in range(7):
            packet7(c, x0 + 4 + k * 8, yy, k + row * 3)
        c.rect(x0 + 2, yy + 9, x1 - x0 - 4, 2, WOOD_WALL[3])
    for k in range(4):
        dx = x0 + 3 + k * 15
        rrect(c, dx, 38, 13, 8, 0.8, WOOD_WALL[2]); c.rect(dx + 5, 41, 3, 1, hexc("e3c04a"))
    for k, kind in enumerate((4, 1, 0)):
        mini_pot(c, x0 + 4 + k * 22, 4, kind, 11 + k)
    vine_drape(c, T - 2, 4, 40, 3, 1)

    # ---- H 화분 선반 (x5~6): 3단
    x0 = 5 * T
    floor_shadow(c, x0, 3 * T, 2 * T)
    obox(c, x0 + 1, 8, 2 * T - 2, 3 * T - 8, WOOD_WALL[0])
    c.rect(x0 + 3, 10, 2 * T - 6, 3 * T - 12, hexc("7a4e30"))
    for k, yy in enumerate((20, 32, 44)):
        c.rect(x0 + 2, yy, 2 * T - 4, 2, WOOD_WALL[3])
        mini_pot(c, x0 + 5, yy - 6, (1, 3, 2)[k], 21 + k)
        mini_pot(c, x0 + 18, yy - 6, (4, 0, 1)[k], 31 + k)

    # ---- J 씨앗 병 선반 (x12~14)
    x0, x1 = 12 * T, 15 * T
    floor_shadow(c, x0, 3 * T, x1 - x0)
    obox(c, x0, 10, x1 - x0, 3 * T - 10, WOOD_WALL[1])
    fills = [hexc("e6d3a8"), hexc("7fb069"), hexc("a8693a"), hexc("f3d36b"), hexc("d9c39a")]
    for row, yy in enumerate((12, 24)):
        c.rect(x0 + 3, yy, x1 - x0 - 6, 11, hexc("6e4426"))
        for k in range(5):
            jar(c, x0 + 4 + k * 9, yy + 1, fills[(k + row * 2) % 5])
        c.rect(x0 + 2, yy + 10, x1 - x0 - 4, 2, WOOD_WALL[3])
    for k in range(3):
        dx = x0 + 3 + k * 14
        rrect(c, dx, 37, 12, 9, 0.8, WOOD_WALL[2]); c.rect(dx + 5, 40, 2, 1, hexc("e3c04a"))
    mini_pot(c, x0 + 6, 4, 1, 51); mini_pot(c, x0 + 30, 4, 4, 52)
    vine_drape(c, x1 - 2, 6, 26, 7, -1)

    # ---- K 장작 난로 (x15~16) + 연통 + 주전자
    x0 = 15 * T
    floor_shadow(c, x0 + 2, 3 * T, 2 * T - 4)
    c.rect(x0 + 2, 3 * T - 6, 2 * T - 4, 6, hexc("9a8b7d")); c.rect(x0 + 2, 3 * T - 6, 2 * T - 4, 1, hexc("b5a696"))
    c.rect(x0 + 13, 0, 6, 22, hexc("3a3a3e")); c.rect(x0 + 13, 0, 1, 22, hexc("5a5a62")); c.rect(x0 + 12, 8, 8, 2, hexc("2a2a2e"))
    obox(c, x0 + 5, 20, 22, 24, hexc("2f2f33"), 2.5)
    c.rect(x0 + 6, 21, 20, 2, hexc("4a4a50"))
    rrect(c, x0 + 9, 28, 14, 10, 1.5, hexc("1c1c20"))
    c.ellipse(x0 + 16, 34, 5, 3, hexc("ff8a2c")); c.ellipse(x0 + 16, 35, 3, 1.8, hexc("ffd36b")); c.set(x0 + 16, 35, GLOW[2])
    c.rect(x0 + 8, 44, 2, 2, DARK); c.rect(x0 + 22, 44, 2, 2, DARK)
    rrect(c, x0 + 7, 14, 9, 7, 2, hexc("8a6a4a")); c.rect(x0 + 15, 16, 3, 1, hexc("8a6a4a")); c.rect(x0 + 10, 13, 3, 1, DARK)

    # ---- C 계산대 (x6~12): 초록 천 · 장부 · 종 · 돈통 · 등잔 · 꽃 화분
    x0, x1 = 6 * T, 13 * T
    floor_shadow(c, x0, 4 * T, x1 - x0)
    obox(c, x0, 3 * T - 3, x1 - x0, T + 3, WOOD_WALL[0])
    c.rect(x0 + 1, 3 * T - 2, x1 - x0 - 2, 5, WOOD_WALL[3]); c.rect(x0 + 1, 3 * T + 3, x1 - x0 - 2, 1, WOOD_WALL[2])
    for x in range(x0 + 7, x1 - 3, 9):
        c.rect(x, 3 * T + 5, 1, T - 6, dk(WOOD_WALL[0], 0.85))
    rrect(c, 9 * T - 9, 3 * T - 2, 18, T + 1, 0.5, GREEN[0]); rrect(c, 9 * T - 8, 3 * T - 1, 16, T - 1, 0.5, hexc("f6ead2"))
    c.rect(9 * T - 8, 3 * T - 1, 16, 1, GREEN[1])
    sprout(c, 9 * T, 3 * T + 7, GREEN[1])
    rrect(c, 7 * T + 4, 3 * T - 5, 14, 6, 0.5, hexc("fbf6ec")); c.rect(7 * T + 11, 3 * T - 5, 1, 6, hexc("d9c9a8"))
    c.rect(7 * T + 6, 3 * T - 3, 4, 1, hexc("b5a696")); c.rect(7 * T + 13, 3 * T - 3, 4, 1, hexc("b5a696"))
    c.ellipse(6 * T + 22, 3 * T - 3, 2.5, 2, hexc("d6a83a")); c.set(6 * T + 22, 3 * T - 6, DARK)
    obox(c, 10 * T + 6, 3 * T - 7, 12, 7, hexc("4a4d55"), 1); c.rect(10 * T + 8, 3 * T - 6, 8, 1, hexc("7a7e88"))
    rrect(c, 12 * T - 6, 3 * T - 9, 5, 7, 1.5, GLOW[1]); c.set(12 * T - 4, 3 * T - 7, GLOW[2]); c.rect(12 * T - 6, 3 * T - 3, 5, 2, hexc("a8653a"))
    mini_pot(c, 6 * T + 2, 3 * T - 6, 1, 61)

    # ---- V 큰 잎 화분 (1,3) · P 꽃 화분 (1,4) · A 씨앗 자루 (16,3~4)
    leaves(c, T + 8, 3 * T + 3, 7, 7, 71); leaves(c, T + 5, 3 * T - 2, 4, 5, 72)
    rrect(c, T + 3, 4 * T - 9, 10, 9, 1.5, TERRA[1]); c.rect(T + 3, 4 * T - 9, 10, 2, TERRA[2])
    plant_pot(c, T, 4 * T)
    blooms(c, T + 8, 4 * T + 5, 4, 3, 73, [FLOWERS[1], hexc("e0715f")], 3)
    floor_shadow(c, 16 * T, 5 * T, T)
    sack(c, 16 * T, 3 * T, T, T, hexc("e8d7a8")); sack(c, 16 * T, 4 * T, T, T)

    # ---- Y 모종 받침대 (1,5)
    floor_shadow(c, T, 6 * T, T)
    obox(c, T + 1, 5 * T + 6, 14, 6, WOOD_WALL[2], 0.5); c.rect(T + 3, 5 * T + 12, 2, 4, WOOD_WALL[0]); c.rect(T + 11, 5 * T + 12, 2, 4, WOOD_WALL[0])
    for k in range(3):
        sprout(c, T + 4 + k * 4, 5 * T + 4, GREEN[2])

    # ---- L 모종 상자 더미 (x1~2, y6~7)
    floor_shadow(c, T, 8 * T, 2 * T)
    for k, (bx, by) in enumerate(((T, 6 * T + 2), (2 * T, 6 * T + 2), (T, 7 * T + 2), (2 * T, 7 * T + 2))):
        crate(c, bx + 1, by + 4, T - 2, T - 6)
        if k in (0, 3):
            for j in range(3):
                sprout(c, bx + 4 + j * 4, by + 2, GREEN[2])
        else:
            leaves(c, bx + 8, by + 3, 6, 3, 80 + k, 6)
            blooms(c, bx + 8, by + 2, 5, 2, 90 + k, [FLOWERS[0], FLOWERS[2], FLOWERS[1]], 3)

    # ---- G 가운데 진열대 (x6~11, y6~7): 뒤 봉투 진열판 + 앞 모종·채소 상자 + 양 끝 꽃 화분
    x0, x1 = 6 * T, 12 * T
    floor_shadow(c, x0 + 2, 8 * T - 1, x1 - x0 - 4)
    obox(c, x0 + 2, 6 * T + 10, x1 - x0 - 4, 2 * T - 11, WOOD_WALL[1])
    c.rect(x0 + 3, 6 * T + 11, x1 - x0 - 6, 2, WOOD_WALL[3])
    obox(c, x0 + 14, 6 * T - 1, x1 - x0 - 28, 13, WOOD_WALL[2], 1)
    for k in range(8):
        packet7(c, x0 + 17 + k * 8, 6 * T + 1, k + 2)
    for k in range(4):
        bx = x0 + 6 + k * 21
        crate(c, bx, 7 * T, 19, 13, WOOD_WALL[2])
        if k == 0:
            for j in range(4):
                sprout(c, bx + 3 + j * 4, 7 * T - 1, GREEN[2])
        elif k == 1:
            for j in range(5):
                c.ellipse(bx + 3 + j * 3.3, 7 * T + 1, 1.6, 1.6, hexc("e0533f")); c.set(int(bx + 3 + j * 3.3), 7 * T - 1, GREEN[1])
        elif k == 2:
            for j in range(4):
                c.rect(bx + 3 + j * 4, 7 * T - 1, 2, 4, hexc("ec8a32")); c.set(bx + 3 + j * 4, 7 * T - 2, GREEN[2])
        else:
            leaves(c, bx + 9, 7 * T, 8, 3, 101, 8)
            blooms(c, bx + 9, 7 * T - 1, 7, 2, 102, [FLOWERS[2], FLOWERS[0]], 4)
    mini_pot(c, x0, 7 * T + 4, 3, 111); mini_pot(c, x1 - 9, 7 * T + 4, 1, 112)

    # ---- R 씨앗 봉투 진열대 (x15~16, y5~7)
    x0 = 15 * T
    floor_shadow(c, x0 + 2, 8 * T, 2 * T - 4)
    obox(c, x0 + 3, 5 * T + 2, 2 * T - 6, 3 * T - 2, WOOD_WALL[1])
    for row, yy in enumerate((5 * T + 6, 6 * T + 6, 7 * T + 4)):
        c.rect(x0 + 5, yy - 1, 2 * T - 10, 11, hexc("7a4e30"))
        for k in range(3):
            packet7(c, x0 + 6 + k * 7, yy, k + row * 2 + 1)
        c.rect(x0 + 4, yy + 9, 2 * T - 8, 2, WOOD_WALL[3])

    # ---- O 화분 더미 (1,8) · B 통 (16,8~9) · Q 꽃 상자 + 물뿌리개 (1~2,9) · Z 칠판 (14,9) · P 화분 (1,10)(16,10)
    floor_shadow(c, T, 9 * T, T)
    for k, (dx, dy) in enumerate(((2, 9), (4, 4), (6, -1))):
        rrect(c, T + dx, 8 * T + dy, 9, 6, 1, TERRA[1 + k % 2]); c.rect(T + dx, 8 * T + dy, 9, 1, TERRA[2]); c.rect(T + dx + 1, 8 * T + dy + 5, 7, 1, TERRA[0])
    floor_shadow(c, 16 * T, 10 * T, T)
    barrel(c, 16 * T, 8 * T, hexc("6e452b")); barrel(c, 16 * T, 9 * T, hexc("6e452b"))
    leaves(c, 16 * T + 8, 8 * T + 1, 5, 2, 121, 5)
    sunflower(c, 16 * T + 5, 8 * T + 2, 6); sunflower(c, 16 * T + 10, 8 * T + 2, 9)
    for j in range(3):
        sprout(c, 16 * T + 4 + j * 4, 9 * T + 2, GREEN[2])
    floor_shadow(c, T, 10 * T, 2 * T)
    crate(c, T + 1, 9 * T + 6, 2 * T - 12, 10)
    leaves(c, T + 10, 9 * T + 5, 9, 3, 131, 8); blooms(c, T + 10, 9 * T + 4, 8, 2, 132, [FLOWERS[1], FLOWERS[0], FLOWERS[2]], 5)
    rrect(c, 3 * T - 10, 9 * T + 7, 8, 7, 1.5, hexc("7d8a96")); c.rect(3 * T - 10, 9 * T + 7, 8, 1, hexc("aab6c0"))
    c.rect(3 * T - 13, 9 * T + 8, 3, 1, hexc("7d8a96")); c.rect(3 * T - 14, 9 * T + 7, 1, 1, hexc("7d8a96")); c.rect(3 * T - 6, 9 * T + 5, 2, 2, hexc("5d6a76"))
    floor_shadow(c, 14 * T, 10 * T, T)
    c.rect(14 * T + 3, 9 * T + 4, 1, 12, WOOD_WALL[0]); c.rect(14 * T + 12, 9 * T + 4, 1, 12, WOOD_WALL[0])
    obox(c, 14 * T + 2, 9 * T + 1, 12, 11, WOOD_WALL[1], 0.5); c.rect(14 * T + 3, 9 * T + 2, 10, 9, hexc("2f3a33"))
    sprout(c, 14 * T + 8, 9 * T + 5, hexc("f6ead2")); c.rect(14 * T + 5, 9 * T + 9, 6, 1, hexc("cfd8cf"))
    plant_pot(c, T, 10 * T); plant_pot(c, 16 * T, 10 * T)
    blooms(c, T + 8, 10 * T + 5, 4, 3, 141, [FLOWERS[0], FLOWERS[4]], 3)
    blooms(c, 16 * T + 8, 10 * T + 5, 4, 3, 142, [FLOWERS[2], FLOWERS[1]], 3)

    # ---- 벽 덩굴 (윗보에서 늘어짐)
    for x, ln, sd in ((6 * T + 8, 14, 151), (12 * T - 4, 10, 152), (W - T - 2, 46, 153)):
        vine_drape(c, x, 3, ln, sd, -1 if x > W // 2 else 1)
    c.save("interior_store.png")


# ---------------------------------------------------------------- 대장간 · 기계상점 실내 (실내 개편: 18x12칸, 288x192)
#   씨앗상점(밝은 나무·초록·꽃)과 겹치지 않게 성격을 나눈다.
#   대장간 = 불·금속·강화: 짙은 나무 + 석재 + 검은 쇠 + 붉은 주황 불빛. 오른쪽 위 큰 화덕이 주 광원, 그 앞 돌바닥에 모루.
#   기계상점 = 자동화·부품·설계도: 나무 + 회색 금속 + 청동·초록. 벽 배관·압력계·청사진, 가운데 통로는 철판, 오른쪽 컨베이어.
#   칸 배치는 scripts/world/interior.gd 의 rows 와 같다.

METAL = [hexc("3a3c43"), hexc("555963"), hexc("7d838c"), hexc("a9aeb5"), hexc("d3d6da")]
BRONZE = [hexc("6e4522"), hexc("9a6430"), hexc("c48a45"), hexc("e3b46a")]
MGREEN = [hexc("2f4a40"), hexc("3f6455"), hexc("5a8a6e"), hexc("82b08f")]
BLUEP = [hexc("26405e"), hexc("3a5f86"), hexc("a9c6e0"), hexc("e4eef6")]
SWOOD = [hexc("3a2418"), hexc("4e3020"), hexc("63402a"), hexc("7a5234"), hexc("94683f")]
STONE = [hexc("3f3a37"), hexc("57504a"), hexc("6f665e"), hexc("8a7f75"), hexc("a49789")]
IRON = [hexc("1d1d21"), hexc("2c2c32"), hexc("44454d"), hexc("6a6d76"), hexc("9295a0")]
FIRE = [hexc("8a2a14"), hexc("d24a1e"), hexc("f08a2c"), hexc("ffc65a"), hexc("fff0b8")]
ORE_COL = {"iron": hexc("8f8f96"), "copper": hexc("c46a3a"), "gold": hexc("e3c04a"), "coal": hexc("2a2a2e")}


def plank_floor(c, x0, y0, x1, y1, fl, seam, period=52, row=6):
    for y in range(y0, y1):
        band = (y - y0) // row
        for x in range(x0, x1):
            s = (x + band * 19) % period
            col = fl[(band * 5 + (x + band * 19) // period) % len(fl)]
            if (y - y0) % row == row - 1 or s == 0:
                col = seam
            elif (y - y0) % row == 0:
                col = lt(col, 0.06)
            c.set(x, y, col)


def flagstones(c, x0, y0, w, h, cols, mortar, seed):
    """석재 바닥 (엇갈린 크고 작은 판석)"""
    rnd = random.Random(seed)
    c.rect(x0, y0, w, h, mortar)
    y = y0
    while y < y0 + h:
        rh = rnd.choice((6, 7, 8))
        x = x0 - rnd.randint(0, 6)
        while x < x0 + w:
            rw = rnd.choice((8, 10, 12))
            col = rnd.choice(cols)
            for yy in range(max(y + 1, y0), min(y + rh, y0 + h)):
                for xx in range(max(x + 1, x0), min(x + rw, x0 + w)):
                    c.set(xx, yy, col)
            if y + 1 < y0 + h and x + 1 >= x0:
                c.rect(max(x + 1, x0), y + 1, min(rw - 1, x0 + w - max(x + 1, x0)), 1, lt(col, 0.12))
            x += rw
        y += rh


def gear(c, cx, cy, r, col, hole=None, teeth=8):
    for a in range(teeth):
        ang = a * 2 * math.pi / teeth
        tx, ty = cx + math.cos(ang) * (r + 0.8), cy + math.sin(ang) * (r + 0.8)
        c.rect(int(round(tx - 0.5)), int(round(ty - 0.5)), 2, 2, col)
    c.ellipse(cx, cy, r, r, col)
    c.ellipse(cx - 0.6, cy - 0.6, r * 0.55, r * 0.55, lt(col, 0.18))
    c.ellipse(cx, cy, max(1, r * 0.3), max(1, r * 0.3), hole or dk(col, 0.55))


def gauge(c, cx, cy, r=3):
    c.ellipse(cx, cy, r + 1, r + 1, BRONZE[1]); c.ellipse(cx, cy, r, r, hexc("f4efe2"))
    c.set(int(cx), int(cy), METAL[0]); c.set(int(cx) + 1, int(cy) - 1, hexc("c0392b"))
    if r >= 3:
        c.set(int(cx) + 2, int(cy) - 2, hexc("c0392b"))


def hpipe(c, x0, x1, y, col=None):
    col = col or BRONZE
    c.rect(x0, y, x1 - x0, 4, col[1]); c.rect(x0, y, x1 - x0, 1, col[3]); c.rect(x0, y + 3, x1 - x0, 1, col[0])


def vpipe(c, x, y0, y1, col=None):
    col = col or BRONZE
    c.rect(x, y0, 4, y1 - y0, col[1]); c.rect(x, y0, 1, y1 - y0, col[3]); c.rect(x + 3, y0, 1, y1 - y0, col[0])


def joint(c, x, y, col=None):
    col = col or BRONZE
    c.rect(x - 1, y - 1, 6, 6, col[0]); c.rect(x, y, 4, 4, col[2]); c.set(x, y, col[3])


def valve(c, cx, cy):
    c.ellipse(cx, cy, 3, 3, hexc("b8402c")); c.ellipse(cx, cy, 1.5, 1.5, hexc("7a2a1e"))
    c.rect(int(cx) - 3, int(cy), 7, 1, hexc("e0715f")); c.rect(int(cx), int(cy) - 3, 1, 7, hexc("e0715f"))


def rivets(c, x0, y0, x1, y1, step, col):
    for x in range(x0, x1, step):
        c.set(x, y0, col); c.set(x, y1, col)


def metal_case(c, x, y, w, h, col, seed=0):
    """작은 기계 상자 (모서리 리벳 + 위 밝은 면)"""
    obox(c, x, y, w, h, col, 1)
    c.rect(x + 1, y + 1, w - 2, 2, lt(col, 0.25))
    for px, py in ((x + 2, y + 4), (x + w - 3, y + 4), (x + 2, y + h - 3), (x + w - 3, y + h - 3)):
        c.set(px, py, lt(col, 0.45))


def ingot(c, x, y, col):
    c.rect(x + 1, y, 6, 1, lt(col, 0.35)); c.rect(x, y + 1, 8, 3, col); c.rect(x, y + 3, 8, 1, dk(col, 0.75))


def ore_lump(c, x, y, col, seed):
    rnd = random.Random(seed)
    c.ellipse(x, y, 2.6, 2.2, dk(col, 0.82)); c.ellipse(x - 0.5, y - 0.5, 1.8, 1.4, col)
    c.set(int(x) - 1, int(y) - 1, lt(col, 0.4))
    if rnd.random() < 0.5:
        c.set(int(x) + 1, int(y), lt(col, 0.2))


def coal_pile(c, x, y, w, h, seed):
    rnd = random.Random(seed)
    for _ in range(int(w * h / 4)):
        px, py = x + rnd.randint(0, w - 2), y + rnd.randint(0, h - 2)
        c.rect(px, py, 2, 2, rnd.choice((IRON[0], IRON[1], IRON[2])))
        if rnd.random() < 0.2:
            c.set(px, py, IRON[3])


def hammer(c, x, y, ln=9):
    """x, y = 머리 왼쪽 위. 자루는 아래로"""
    c.rect(x + 2, y + 2, 2, ln, SWOOD[3]); c.rect(x + 2, y + 2, 1, ln, SWOOD[4])
    c.rect(x, y, 6, 3, IRON[2]); c.rect(x, y, 6, 1, IRON[4])


def tongs(c, x, y, ln=11):
    c.rect(x, y, 1, ln, IRON[2]); c.rect(x + 2, y, 1, ln, IRON[2]); c.rect(x, y + ln - 3, 3, 1, IRON[3]); c.set(x + 1, y + ln - 4, IRON[1])


def farm_tool(c, x, y, kind, ln=12):
    """반제품·완성 농기구 (괭이·삽·곡괭이·낫) — 무기 대신 농기구"""
    c.rect(x + 2, y + 2, 1, ln, SWOOD[4])
    if kind == 0:   # 괭이
        c.rect(x, y, 5, 2, IRON[3]); c.rect(x, y + 2, 2, 2, IRON[2])
    elif kind == 1:  # 삽
        rrect(c, x, y + ln - 2, 5, 5, 1, IRON[3]); c.set(x + 1, y + ln - 1, IRON[4])
    elif kind == 2:  # 곡괭이
        c.rect(x - 1, y + 1, 7, 1, IRON[3]); c.set(x - 2, y + 2, IRON[3]); c.set(x + 6, y + 2, IRON[3])
    else:            # 낫
        c.rect(x + 2, y, 4, 1, IRON[3]); c.set(x + 6, y + 1, IRON[3]); c.set(x + 6, y + 2, IRON[2])


def room_walls(c, W, H, side, door_col, edge):
    """옆벽·앞벽 + 가운데 문 (세 실내 공통 뼈대). side = 벽 색 4단계"""
    for x0 in (0, W - T + 4):
        c.rect(x0, 0, T - 4, H, side[0])
        c.rect(x0 + (T - 6 if x0 == 0 else 0), 0, 2, H, side[1])
        c.rect(x0 + (0 if x0 == 0 else T - 5), 0, 1, H, edge)
        for yy in range(6, H, 12):
            c.rect(x0 + 2, yy, T - 8, 1, dk(side[0], 0.85))
    c.rect(T - 4, 2 * T, 2, H - 3 * T, SOFT_SHADOW); c.rect(W - T + 2, 2 * T, 2, H - 3 * T, SOFT_SHADOW)
    c.rect(0, H - T + 4, W, T - 4, side[0]); c.rect(0, H - T + 4, W, 1, side[3]); c.rect(0, H - 1, W, 1, edge)
    for x in range(3, W, 9):
        c.rect(x, H - T + 6, 1, T - 7, dk(side[0], 0.85))
    c.rect(8 * T, H - T + 4, 2 * T, T - 4, door_col)
    c.rect(8 * T, H - T + 4, 2 * T, 2, dk(door_col, 0.7)); c.rect(8 * T + 2, H - 3, 2 * T - 4, 2, hexc("c8b9a2"))
    for px in (8 * T - 4, 10 * T):
        obox(c, px, H - T - 2, 4, T + 2, side[1], 0.5)
    lantern(c, 8 * T - 11, H - T - 2); lantern(c, 10 * T + 8, H - T - 2)


# ======================================================================== 기계상점
def make_interior_machine():
    W, H = 18 * T, 12 * T
    c = Canvas(W, H)
    # ---- 바닥: 나무 판자 + 가운데 통로 철판 (문 → 계산대), 진열대 밑은 초록 깔개
    plank_floor(c, T - 4, 2 * T, W - T + 4, H - T + 4, [hexc("a8714a"), hexc("b07a50"), hexc("9c6a44")], hexc("7a5034"))
    px0, px1 = 7 * T, 11 * T
    c.rect(px0, 4 * T, px1 - px0, H - 5 * T + 4, METAL[2])
    for y in range(4 * T, H - T + 4, 16):
        c.rect(px0, y, px1 - px0, 1, METAL[1])
        for x in range(px0 + 2, px1, 4):
            for yy in range(y + 3, min(y + 15, H - T + 4), 4):
                c.set(x + ((yy // 4) % 2) * 2, yy, METAL[3])
    for x in range(px0, px1 + 1, 32):
        c.rect(min(x, px1 - 1), 4 * T, 1, H - 5 * T + 4, METAL[1])
    c.rect(px0, 4 * T, 1, H - 5 * T + 4, METAL[0]); c.rect(px1 - 1, 4 * T, 1, H - 5 * T + 4, METAL[0])
    rivets(c, px0 + 3, 4 * T + 2, px1 - 2, H - T + 1, 8, METAL[4])
    # ---- 뒷벽: 위 나무 판벽 · 아래 철판 징두리(리벳) · 가로 배관 · 압력계 · 밸브
    c.rect(0, 0, W, 3, SWOOD[2]); c.rect(0, 3, W, 1, DARK)
    for x in range(0, W):
        c.rect(x, 4, 1, 14, (hexc("8a6040"), hexc("94683f"), hexc("80583a"))[(x // 9) % 3])
    for x in range(0, W, 9):
        c.rect(x, 4, 1, 14, hexc("6a4428"))
    c.rect(0, 18, W, 13, METAL[2]); c.rect(0, 18, W, 1, METAL[4]); c.rect(0, 30, W, 1, METAL[0])
    for x in range(0, W, 24):
        c.rect(x, 18, 1, 13, METAL[1])
    rivets(c, 3, 20, W, 28, 6, METAL[4])
    c.rect(0, 31, W, 1, DARK); c.rect(0, 32, W, 3, SOFT_SHADOW)
    hpipe(c, T - 4, W - T + 4, 6, BRONZE)
    for x in (3 * T, 6 * T + 4, 12 * T + 8, 15 * T):
        joint(c, x, 6)
    vpipe(c, 6 * T + 4, 9, 18); vpipe(c, 12 * T + 8, 9, 18, METAL[1:] + [METAL[4]])
    gauge(c, 6 * T + 6, 13, 3); valve(c, 12 * T + 10, 13)
    room_walls(c, W, H, [SWOOD[2], SWOOD[3], SWOOD[4], hexc("a87a4a")], hexc("4a3020"), DARK)

    # ---- 바닥 깔개 · 등불 빛
    rug(c, 2 * T + 8, 5 * T + 8, 5 * T - 6, 3 * T, MGREEN[2], MGREEN[0], lambda cv, x, y: None)
    rug(c, 11 * T - 2, 5 * T + 8, 5 * T - 6, 3 * T, MGREEN[2], MGREEN[0], lambda cv, x, y: None)
    rug(c, 8 * T + 2, 10 * T + 1, 2 * T - 4, 12, MGREEN[2], MGREEN[0], lambda cv, x, y: gear_mark(cv, x, y))
    for cx, cy, rx, ry in ((7 * T + 8, 3 * T, 24, 10), (12 * T, 3 * T, 22, 10), (2 * T, 9 * T + 8, 20, 10), (W - 2 * T - 8, 9 * T + 8, 20, 10), (9 * T, 10 * T + 8, 24, 8)):
        glow_pool(c, cx, cy, rx, ry, 24)

    # ---- 계산대 뒤 벽: 청사진 두 장 (기계 설계도) · 톱니 장식 · 공구판
    for k, bx in enumerate((7 * T - 2, 9 * T + 6)):
        obox(c, bx, 7, 26, 18, BLUEP[1], 0.5)
        c.rect(bx + 1, 8, 24, 16, BLUEP[1])
        for gx in range(bx + 2, bx + 25, 4):
            c.rect(gx, 8, 1, 16, lt(BLUEP[1], 0.08))
        if k == 0:
            gear(c, bx + 8, 15, 4, BLUEP[3], BLUEP[1]); gear(c, bx + 16, 12, 2.5, BLUEP[2], BLUEP[1], 6)
            c.rect(bx + 14, 18, 9, 1, BLUEP[3]); c.rect(bx + 14, 21, 6, 1, BLUEP[2])
        else:
            c.rect(bx + 4, 11, 10, 8, BLUEP[3]); c.rect(bx + 5, 12, 8, 6, BLUEP[1]); c.rect(bx + 14, 14, 7, 1, BLUEP[3])
            c.rect(bx + 20, 11, 1, 8, BLUEP[3]); c.ellipse(bx + 9, 15, 2, 2, BLUEP[3])
        c.rect(bx + 1, 7, 2, 2, hexc("d6a83a")); c.rect(bx + 23, 7, 2, 2, hexc("d6a83a"))
    gear(c, 11 * T + 10, 13, 5, BRONZE[2], BRONZE[0])
    gear(c, 11 * T + 2, 20, 3, METAL[3], METAL[1], 6)
    wall_lamp(c, 6 * T + 12, 20); wall_lamp(c, 12 * T + 1, 20)

    # ---- B 보일러 (x1~2, y2): 청동 탱크 + 압력계 + 불창
    x0 = T
    floor_shadow(c, x0, 3 * T, 2 * T)
    vpipe(c, x0 + 13, 0, 12, METAL[1:] + [METAL[4]])
    rrect(c, x0 + 2, 9, 2 * T - 4, 3 * T - 10, 5, BRONZE[0]); rrect(c, x0 + 3, 10, 2 * T - 6, 3 * T - 12, 4, BRONZE[2])
    c.rect(x0 + 5, 12, 3, 3 * T - 18, BRONZE[3])
    for yy in (16, 28, 40):
        c.rect(x0 + 3, yy, 2 * T - 6, 1, BRONZE[0])
    gauge(c, x0 + 22, 20, 3)
    rrect(c, x0 + 9, 31, 14, 9, 1.5, IRON[1]); c.ellipse(x0 + 16, 36, 4.5, 2.5, FIRE[2]); c.ellipse(x0 + 16, 36.5, 2.5, 1.2, FIRE[3])
    c.rect(x0 + 3, 3 * T - 3, 2 * T - 6, 3, METAL[1])

    # ---- P 부품 선반 (x3~5): 철제 선반 + 볼트 통 · 톱니 · 엔진 부품
    x0, x1 = 3 * T, 6 * T
    floor_shadow(c, x0, 3 * T, x1 - x0)
    c.rect(x0 + 1, 8, 2, 3 * T - 8, METAL[1]); c.rect(x1 - 3, 8, 2, 3 * T - 8, METAL[1])
    for k, yy in enumerate((18, 30, 44)):
        c.rect(x0 + 1, yy, x1 - x0 - 2, 2, METAL[3]); c.rect(x0 + 1, yy + 2, x1 - x0 - 2, 1, METAL[0])
    for j in range(4):                                                        # 볼트·너트 통 (1단)
        bx = x0 + 4 + j * 11
        rrect(c, bx, 11, 9, 7, 1, (BRONZE[1], METAL[2], MGREEN[2], BRONZE[1])[j])
        for q in range(3):
            c.set(bx + 2 + q * 2, 12, METAL[4]); c.set(bx + 3 + q * 2, 13, METAL[3])
        c.rect(bx + 2, 15, 5, 2, hexc("f4efe2"))
    gear(c, x0 + 9, 25, 4, METAL[3], METAL[1]); gear(c, x0 + 22, 26, 3, BRONZE[2], BRONZE[0], 6)   # 2단: 톱니
    gear(c, x0 + 35, 25, 4, METAL[2], METAL[0])
    metal_case(c, x0 + 4, 35, 14, 9, METAL[2]); c.rect(x0 + 7, 37, 8, 1, METAL[0])                 # 3단: 엔진 부품
    c.ellipse(x0 + 26, 40, 4, 4, IRON[2]); c.ellipse(x0 + 26, 40, 2, 2, IRON[4])
    metal_case(c, x0 + 33, 36, 11, 8, MGREEN[2])

    # ---- S 도면 서랍장 (x10~12) + 둘둘 만 설계도
    x0, x1 = 10 * T, 13 * T
    floor_shadow(c, x0, 3 * T, x1 - x0)
    obox(c, x0 + 1, 20, x1 - x0 - 2, 3 * T - 20, MGREEN[1])
    c.rect(x0 + 2, 21, x1 - x0 - 4, 2, MGREEN[3])
    for k in range(3):
        yy = 24 + k * 8
        c.rect(x0 + 3, yy, x1 - x0 - 6, 6, MGREEN[2]); c.rect(x0 + 3, yy + 5, x1 - x0 - 6, 1, MGREEN[0])
        c.rect(x0 + 21, yy + 2, 6, 1, METAL[4])
    for k in range(4):
        rx = x0 + 4 + k * 10
        c.rect(rx, 14 - (k % 2) * 2, 8, 4, BLUEP[2 + k % 2]); c.rect(rx, 14 - (k % 2) * 2, 1, 4, BLUEP[1])

    # ---- M 철제 사물함 (x13~16): 초록 캐비닛 + 환기구 + 위 작은 선풍기
    x0, x1 = 13 * T, 17 * T
    floor_shadow(c, x0, 3 * T, x1 - x0)
    for k in range(3):
        lx = x0 + 1 + k * 21
        obox(c, lx, 10, 20, 3 * T - 10, (MGREEN[1], METAL[2], MGREEN[1])[k], 1)
        c.rect(lx + 2, 11, 16, 1, lt((MGREEN[1], METAL[2], MGREEN[1])[k], 0.25))
        for yy in range(14, 24, 3):
            c.rect(lx + 4, yy, 12, 1, dk((MGREEN[1], METAL[2], MGREEN[1])[k], 0.7))
        c.rect(lx + 15, 30, 2, 5, METAL[4])
    c.ellipse(x0 + 52, 6, 4, 4, METAL[2]); gear(c, x0 + 52, 6, 2.5, METAL[4], METAL[1], 4); c.rect(x0 + 51, 9, 2, 2, METAL[1])

    # ---- C 계산대 (x6~10): 나무 몸통 + 철 모서리 + 톱니 명판 · 금전등록기 · 부품 쟁반 · 탁상등
    x0, x1 = 6 * T, 11 * T
    floor_shadow(c, x0, 4 * T, x1 - x0)
    obox(c, x0, 3 * T - 3, x1 - x0, T + 3, SWOOD[3])
    c.rect(x0 + 1, 3 * T - 2, x1 - x0 - 2, 4, METAL[3]); c.rect(x0 + 1, 3 * T + 2, x1 - x0 - 2, 1, METAL[1])
    for x in range(x0 + 8, x1 - 3, 10):
        c.rect(x, 3 * T + 4, 1, T - 5, SWOOD[1])
    rivets(c, x0 + 3, 3 * T - 1, x1 - 2, 3 * T + 13, 10, METAL[4])
    rrect(c, 8 * T + 6, 3 * T + 4, 20, 10, 1, MGREEN[1]); gear(c, 9 * T, 3 * T + 9, 3, hexc("e3d8b8"), MGREEN[1], 6)
    metal_case(c, 9 * T + 12, 3 * T - 10, 14, 8, METAL[2]); c.rect(9 * T + 15, 3 * T - 8, 8, 2, hexc("9fd6a8"))
    rrect(c, 6 * T + 4, 3 * T - 5, 16, 4, 0.5, METAL[1])
    for q in range(5):
        c.set(6 * T + 6 + q * 3, 3 * T - 4, (BRONZE[3], METAL[4])[q % 2])
    c.rect(10 * T + 10, 3 * T - 12, 1, 9, METAL[1]); rrect(c, 10 * T + 7, 3 * T - 14, 7, 4, 1, MGREEN[2]); c.rect(10 * T + 8, 3 * T - 10, 5, 1, GLOW[1])
    c.rect(8 * T - 2, 3 * T - 6, 8, 5, hexc("f4efe2")); c.rect(8 * T, 3 * T - 5, 4, 1, BLUEP[1])

    # ---- X 부품 상자 더미 (x1, y3~4) · T 톱니 걸이판 (x1, y5~7)
    floor_shadow(c, T, 5 * T, T)
    for k, yy in enumerate((3 * T + 1, 4 * T + 1)):
        crate(c, T + 1, yy + 2, 14, 13, SWOOD[4]); gear_mark(c, T + 8, yy + 9, BRONZE[3])
    obox(c, T, 5 * T, 12, 3 * T - 1, hexc("b89a6a"), 0.5)
    for yy in range(5 * T + 3, 8 * T - 2, 4):
        for xx in range(T + 2, T + 11, 3):
            c.set(xx, yy, hexc("8a7050"))
    gear(c, T + 6, 5 * T + 8, 3.5, METAL[3], METAL[1]); gear(c, T + 6, 6 * T + 6, 2.5, BRONZE[2], BRONZE[0], 6)
    c.rect(T + 3, 6 * T + 13, 6, 1, METAL[3]); c.rect(T + 3, 7 * T + 2, 1, 8, METAL[3]); c.rect(T + 2, 7 * T + 2, 3, 2, METAL[3])
    c.rect(T + 7, 7 * T + 3, 1, 8, IRON[3]); c.rect(T + 6, 7 * T + 9, 3, 2, IRON[2])

    # ---- Q 왼쪽 진열대 (x3~6, y6~7): 소형 발전기 · 펌프 · 가격표
    x0, x1 = 3 * T, 7 * T
    floor_shadow(c, x0 + 1, 8 * T - 1, x1 - x0 - 2)
    obox(c, x0 + 1, 6 * T + 12, x1 - x0 - 2, 2 * T - 13, SWOOD[3])
    c.rect(x0 + 2, 6 * T + 13, x1 - x0 - 4, 3, METAL[3]); rivets(c, x0 + 4, 6 * T + 14, x1 - 3, 8 * T - 3, 8, METAL[4])
    metal_case(c, x0 + 4, 6 * T - 2, 24, 16, MGREEN[2])                        # 발전기: 코일 + 청동 계기
    c.ellipse(x0 + 12, 6 * T + 6, 5, 5, BRONZE[1])
    for yy in range(6 * T + 2, 6 * T + 11, 2):
        c.rect(x0 + 8, yy, 9, 1, BRONZE[2])
    gauge(c, x0 + 23, 6 * T + 3, 2); c.rect(x0 + 20, 6 * T + 8, 6, 2, hexc("9fd6a8"))
    metal_case(c, x0 + 33, 6 * T, 20, 14, METAL[2])                           # 펌프: 몸통 + 관 + 손잡이
    c.ellipse(x0 + 42, 6 * T + 7, 4.5, 4.5, METAL[1]); c.ellipse(x0 + 42, 6 * T + 7, 2, 2, METAL[4])
    vpipe(c, x0 + 50, 5 * T + 8, 6 * T + 2, BRONZE); c.rect(x0 + 48, 5 * T + 7, 8, 2, BRONZE[0])
    for k, tx in enumerate((x0 + 10, x0 + 40)):
        c.rect(tx, 7 * T + 4, 9, 6, hexc("f4efe2")); c.rect(tx + 2, 7 * T + 6, 5, 1, METAL[1]); c.set(tx + 1, 7 * T + 4, hexc("c0392b"))

    # ---- E 오른쪽 진열대 (x11~14, y6~7): 필터 · 분배기 · 미니 컨베이어 모형 · 부품 상자
    x0, x1 = 11 * T, 15 * T
    floor_shadow(c, x0 + 1, 8 * T - 1, x1 - x0 - 2)
    obox(c, x0 + 1, 6 * T + 12, x1 - x0 - 2, 2 * T - 13, SWOOD[3])
    c.rect(x0 + 2, 6 * T + 13, x1 - x0 - 4, 3, METAL[3]); rivets(c, x0 + 4, 6 * T + 14, x1 - 3, 8 * T - 3, 8, METAL[4])
    rrect(c, x0 + 4, 5 * T + 10, 10, 18, 3, METAL[2]); rrect(c, x0 + 5, 5 * T + 11, 8, 16, 2.5, METAL[3])      # 필터 (원통)
    for yy in (5 * T + 14, 5 * T + 19, 5 * T + 24):
        c.rect(x0 + 4, yy, 10, 1, BRONZE[1])
    c.rect(x0 + 7, 5 * T + 8, 4, 3, METAL[1])
    metal_case(c, x0 + 17, 6 * T - 1, 18, 14, BRONZE[1])                       # 분배기: 세 갈래 출구
    for k, ox in enumerate((x0 + 19, x0 + 24, x0 + 29)):
        c.rect(ox, 6 * T + 9, 4, 4, IRON[1]); c.set(ox + 1, 6 * T + 10, GLOW[1] if k == 1 else METAL[3])
    c.rect(x0 + 22, 6 * T + 3, 8, 1, BRONZE[3]); c.rect(x0 + 25, 6 * T + 1, 1, 4, BRONZE[3])
    c.rect(x0 + 38, 6 * T + 4, 22, 7, IRON[1]); c.rect(x0 + 38, 6 * T + 4, 22, 1, IRON[3])                    # 미니 컨베이어 모형
    for xx in range(x0 + 40, x0 + 59, 4):
        c.set(xx, 6 * T + 7, IRON[3])
    c.ellipse(x0 + 39, 6 * T + 11, 2, 2, METAL[2]); c.ellipse(x0 + 58, 6 * T + 11, 2, 2, METAL[2])
    rrect(c, x0 + 44, 6 * T, 6, 5, 1, hexc("e3c04a"))
    crate(c, x0 + 38, 7 * T + 1, 18, 9, SWOOD[4])
    for q in range(4):
        gear(c, x0 + 42 + q * 4, 7 * T, 1.5, (METAL[3], BRONZE[2])[q % 2], METAL[0], 4)
    for tx in (x0 + 8, x0 + 22):
        c.rect(tx, 7 * T + 4, 9, 6, hexc("f4efe2")); c.rect(tx + 2, 7 * T + 6, 5, 1, METAL[1]); c.set(tx + 1, 7 * T + 4, hexc("c0392b"))

    # ---- R 시연용 컨베이어 (x16, y3~7) → Z 받는 상자 (x16, y8)
    x0 = 16 * T
    floor_shadow(c, x0, 9 * T, T)
    c.rect(x0 + 1, 3 * T, 14, 5 * T, METAL[1]); c.rect(x0 + 1, 3 * T, 1, 5 * T, METAL[0]); c.rect(x0 + 14, 3 * T, 1, 5 * T, METAL[0])
    c.rect(x0 + 3, 3 * T, 10, 5 * T, IRON[1])
    for yy in range(3 * T + 1, 8 * T, 4):
        c.rect(x0 + 3, yy, 10, 1, IRON[3])
    for yy in range(3 * T + 6, 8 * T, 16):
        c.set(x0 + 1, yy, METAL[4]); c.set(x0 + 14, yy, METAL[4])
    for k, yy in enumerate((3 * T + 6, 5 * T + 2, 6 * T + 12)):
        if k == 1:
            rrect(c, x0 + 4, yy, 8, 7, 1, SWOOD[4]); c.rect(x0 + 4, yy + 3, 8, 1, SWOOD[2])
        else:
            gear(c, x0 + 8, yy + 3, 3, (BRONZE[2], METAL[3])[k // 2], METAL[0], 6)
    crate(c, x0 + 1, 8 * T + 2, 14, 13, SWOOD[4]); gear(c, x0 + 6, 8 * T + 1, 2, METAL[3], METAL[0], 5); gear(c, x0 + 10, 8 * T + 2, 2, BRONZE[2], BRONZE[0], 5)
    c.ellipse(x0 + 8, 3 * T + 2, 3, 2, IRON[3])

    # ---- N 정비 작업대 (x1~2, y9): 바이스 · 렌치 · 등
    x0 = T
    floor_shadow(c, x0, 10 * T, 2 * T)
    obox(c, x0, 9 * T + 4, 2 * T - 2, 9, SWOOD[4]); c.rect(x0 + 2, 9 * T + 13, 2, 3, SWOOD[1]); c.rect(x0 + 24, 9 * T + 13, 2, 3, SWOOD[1])
    c.rect(x0 + 3, 9 * T, 8, 5, IRON[2]); c.rect(x0 + 3, 9 * T, 8, 1, IRON[4]); c.rect(x0 + 10, 9 * T + 2, 4, 1, IRON[3])
    c.rect(x0 + 16, 9 * T + 6, 9, 1, METAL[3]); c.rect(x0 + 15, 9 * T + 5, 2, 3, METAL[3])
    gear(c, x0 + 21, 9 * T + 2, 2, BRONZE[2], BRONZE[0], 5)
    # ---- K 수리 중인 기계 작업대 (x14~16, y9): 뚜껑 열린 기계 + 전선 + 공구함
    x0 = 14 * T
    floor_shadow(c, x0, 10 * T, 3 * T)
    obox(c, x0, 9 * T + 5, 3 * T, 8, SWOOD[4]); c.rect(x0 + 3, 9 * T + 13, 2, 3, SWOOD[1]); c.rect(x0 + 42, 9 * T + 13, 2, 3, SWOOD[1])
    metal_case(c, x0 + 6, 8 * T + 10, 18, 11, METAL[2]); c.rect(x0 + 8, 8 * T + 12, 14, 6, IRON[1])
    gear(c, x0 + 12, 8 * T + 15, 2.5, BRONZE[2], BRONZE[0], 6); c.set(x0 + 18, 8 * T + 14, hexc("9fd6a8"))
    c.rect(x0 + 6, 8 * T + 6, 18, 3, METAL[3])
    c.rect(x0 + 24, 9 * T + 2, 6, 1, hexc("c0392b")); c.rect(x0 + 29, 9 * T + 2, 1, 3, hexc("c0392b")); c.rect(x0 + 24, 9 * T + 4, 4, 1, hexc("e3c04a"))
    obox(c, x0 + 32, 9 * T - 1, 12, 7, hexc("b8402c"), 1); c.rect(x0 + 36, 9 * T - 3, 4, 2, METAL[1])
    # ---- P 화분 (1,10) · B 기름통 (16,10)
    plant_pot(c, T, 10 * T)
    floor_shadow(c, 16 * T, 11 * T, T)
    rrect(c, 16 * T + 2, 10 * T + 1, 12, 15, 2, MGREEN[1]); c.rect(16 * T + 2, 10 * T + 5, 12, 1, MGREEN[0]); c.rect(16 * T + 2, 10 * T + 11, 12, 1, MGREEN[0])
    c.ellipse(16 * T + 8, 10 * T + 2.5, 5.5, 2, MGREEN[3]); c.ellipse(16 * T + 10, 10 * T + 2.5, 1.2, 1, IRON[1])
    c.save("interior_machine.png")


# ======================================================================== 대장간
def make_interior_smith():
    W, H = 18 * T, 12 * T
    c = Canvas(W, H)
    # ---- 바닥: 짙은 판자 + 화덕·모루 주변 석재 바닥 (오른쪽 위)
    plank_floor(c, T - 4, 2 * T, W - T + 4, H - T + 4, [SWOOD[3], hexc("6e4830"), hexc("5c3c28")], SWOOD[1], 68, 6)
    flagstones(c, 10 * T, 4 * T - 4, 7 * T - 4 + 4, 3 * T + 4, STONE[1:4], STONE[0], 7)
    c.rect(10 * T, 7 * T, 7 * T, 1, STONE[0])
    for x in range(10 * T, W - T + 4, 3):                                    # 불똥 자국·그을음
        if (x * 7) % 5 == 0:
            c.set(x, 4 * T + (x * 13) % 40, IRON[1])
    # ---- 뒷벽: 위 그을린 판벽 · 아래 돌 징두리 (벽돌)
    c.rect(0, 0, W, 3, SWOOD[1]); c.rect(0, 3, W, 1, IRON[0])
    for x in range(W):
        c.rect(x, 4, 1, 12, (SWOOD[2], SWOOD[3], hexc("5a3a26"))[(x // 11) % 3])
    for x in range(0, W, 11):
        c.rect(x, 4, 1, 12, SWOOD[0])
    for y0 in range(16, 31, 5):
        off = 0 if (y0 // 5) % 2 else 6
        c.rect(0, y0, W, 5, STONE[2])
        for x in range(-off, W, 12):
            c.rect(x, y0, 1, 5, STONE[0])
        c.rect(0, y0, W, 1, STONE[3]); c.rect(0, y0 + 4, W, 1, STONE[1])
    c.rect(0, 31, W, 1, IRON[0]); c.rect(0, 32, W, 3, SOFT_SHADOW)
    room_walls(c, W, H, [SWOOD[1], SWOOD[2], SWOOD[3], SWOOD[4]], hexc("2a1a12"), IRON[0])

    # ---- 깔개 (지나갈 수 있음) · 불빛 웅덩이 (화덕 쪽은 붉고 크게)
    rug(c, 8 * T + 2, 10 * T + 1, 2 * T - 4, 12, hexc("a85a46"), hexc("6e3226"), lambda cv, x, y: anvil_mark(cv, x, y))
    rug(c, 3 * T + 4, 4 * T + 4, 4 * T + 8, 12, hexc("8a4a36"), hexc("5e2c20"), lambda cv, x, y: anvil_mark(cv, x, y))
    for f, a in ((1.0, 22), (0.75, 26), (0.5, 30), (0.3, 34)):
        c.ellipse(13 * T + 8, 4 * T + 4, 52 * f, 26 * f, (255, 140, 60, a))
    for cx, cy, rx, ry in ((5 * T, 3 * T, 22, 9), (W - 2 * T, 8 * T, 16, 10), (9 * T, 10 * T + 8, 22, 8), (5 * T + 8, 8 * T + 4, 24, 10)):
        glow_pool(c, cx, cy, rx, ry, 22)

    # ---- 계산대 뒤 벽: 교차 망치 현판 · 벽등 · 그을음
    obox(c, 4 * T + 2, 6, 28, 14, SWOOD[3], 0.5); c.rect(4 * T + 3, 7, 26, 12, hexc("e8d6b0"))
    for s in (-1, 1):
        for i in range(8):
            c.set(5 * T + 1 + s * (i - 4), 9 + i, SWOOD[1])
        c.rect(5 * T + 1 + s * 4 - 2, 8, 4, 2, IRON[2])
    wall_lamp(c, 3 * T + 8, 14); wall_lamp(c, 7 * T + 8, 14)

    # ---- R 광석 선반 (x1~2, y2): 칸마다 철·구리·금 광석
    x0 = T
    floor_shadow(c, x0, 3 * T, 2 * T)
    obox(c, x0, 8, 2 * T, 3 * T - 8, SWOOD[3])
    for row, (yy, kinds) in enumerate(((11, ("iron", "copper")), (23, ("gold", "iron")), (35, ("coal", "copper")))):
        c.rect(x0 + 2, yy, 2 * T - 4, 10, SWOOD[0])
        for k, kind in enumerate(kinds):
            for q in range(3):
                ore_lump(c, x0 + 6 + k * 13 + q * 3.5, yy + 6 - (q % 2) * 2, ORE_COL[kind], row * 10 + k * 3 + q)
        c.rect(x0 + 1, yy + 10, 2 * T - 2, 2, SWOOD[4])
        c.rect(x0 + 15, yy, 2, 10, SWOOD[3])

    # ---- T 공구 벽 (x8~9, y2): 망치 · 집게 · 줄 · 반제품 괭이날
    x0 = 8 * T
    floor_shadow(c, x0, 3 * T, 2 * T)
    obox(c, x0 + 1, 8, 2 * T - 2, 3 * T - 10, SWOOD[2])
    c.rect(x0 + 3, 12, 2 * T - 6, 1, IRON[2]); c.rect(x0 + 3, 28, 2 * T - 6, 1, IRON[2])
    hammer(c, x0 + 3, 13, 10); hammer(c, x0 + 11, 13, 12); tongs(c, x0 + 21, 13, 13); tongs(c, x0 + 26, 13, 11)
    c.rect(x0 + 4, 30, 9, 3, IRON[3]); c.rect(x0 + 4, 30, 9, 1, IRON[4]); c.rect(x0 + 16, 30, 11, 2, IRON[2]); c.rect(x0 + 16, 32, 3, 3, IRON[2])
    c.rect(x0 + 3, 3 * T - 4, 2 * T - 6, 2, SWOOD[4])

    # ---- X 석탄 통 (x10, y2)
    floor_shadow(c, 10 * T, 3 * T, T)
    rrect(c, 10 * T + 1, 3 * T - 18, 14, 18, 2, SWOOD[3]); c.rect(10 * T + 1, 3 * T - 12, 14, 1, IRON[1]); c.rect(10 * T + 1, 3 * T - 5, 14, 1, IRON[1])
    coal_pile(c, 10 * T + 2, 3 * T - 21, 12, 6, 31)
    c.rect(10 * T + 12, 3 * T - 26, 1, 8, SWOOD[4]); rrect(c, 10 * T + 10, 3 * T - 27, 5, 3, 0.5, IRON[3])

    # ---- F 큰 화덕 (x11~15, y2~3): 돌 화로 + 아치 + 타오르는 불 + 후드 + 굴뚝 + 풀무
    x0, x1 = 11 * T, 16 * T
    floor_shadow(c, x0, 4 * T, x1 - x0)
    c.rect(x0 + 30, 0, 18, 10, IRON[1]); c.rect(x0 + 30, 0, 2, 10, IRON[3])                         # 굴뚝
    for yy in range(4, 18):                                                                      # 쇠 후드 (사다리꼴)
        inset = max(0, 17 - yy)
        c.rect(x0 + 10 + inset, yy, x1 - x0 - 20 - inset * 2, 1, IRON[2] if yy % 4 else IRON[1])
    c.rect(x0 + 8, 17, x1 - x0 - 16, 2, IRON[3])
    obox(c, x0 + 2, 18, x1 - x0 - 4, 2 * T + 12, STONE[2], 2)                                   # 돌 화로 몸통
    for yy in range(20, 4 * T - 2, 6):
        off = 0 if (yy // 6) % 2 else 5
        c.rect(x0 + 3, yy, x1 - x0 - 6, 1, STONE[1])
        for xx in range(x0 + 3 + off, x1 - 3, 10):
            c.rect(xx, yy, 1, 6, STONE[1])
    c.rect(x0 + 3, 19, x1 - x0 - 6, 1, STONE[4])
    ax, aw = x0 + 14, x1 - x0 - 28                                                              # 아치 + 불
    rrect(c, ax - 2, 26, aw + 4, 26, 6, STONE[0])
    rrect(c, ax, 28, aw, 24, 5, hexc("2a120a"))
    c.ellipse(ax + aw / 2, 46, aw / 2 - 1, 8, FIRE[0]); c.ellipse(ax + aw / 2, 45, aw / 2 - 4, 7, FIRE[1])
    for k, (fx, fh) in enumerate(((0.2, 10), (0.4, 15), (0.6, 13), (0.8, 9))):
        cx = ax + aw * fx
        c.ellipse(cx, 46 - fh / 2, 3.2, fh / 2, FIRE[2]); c.ellipse(cx, 47 - fh / 3, 1.8, fh / 3, FIRE[3])
    c.ellipse(ax + aw / 2, 47, 7, 2.5, FIRE[4])
    coal_pile(c, ax + 2, 49, aw - 4, 3, 41)
    c.rect(ax - 2, 52, aw + 4, 2, IRON[2])
    rrect(c, x1 - 13, 2 * T + 6, 10, 12, 2, hexc("7a4a2a")); c.rect(x1 - 12, 2 * T + 9, 8, 1, hexc("5a3420"))   # 풀무
    c.rect(x1 - 9, 2 * T + 3, 2, 4, SWOOD[4]); c.rect(x1 - 12, 3 * T + 2, 8, 2, IRON[2])
    c.rect(x0 + 4, 2 * T + 8, 8, 2, IRON[3]); c.rect(x0 + 6, 2 * T + 4, 2, 4, IRON[3])                       # 화덕 옆 쇠집게 걸이

    # ---- I 주괴 선반 (x16, y2~3) · G 숫돌 바퀴 (x16, y4)
    x0 = 16 * T
    floor_shadow(c, x0, 4 * T, T)
    obox(c, x0, 12, T, 3 * T + 4 - 12, SWOOD[3])
    for k, (yy, col) in enumerate(((16, ORE_COL["gold"]), (27, ORE_COL["copper"]), (38, ORE_COL["iron"]), (49, ORE_COL["iron"]))):
        c.rect(x0 + 2, yy, 12, 8, SWOOD[0])
        ingot(c, x0 + 4, yy + 3, col); ingot(c, x0 + 3, yy + 5, dk(col, 0.92))
        c.rect(x0 + 1, yy + 8, 14, 2, SWOOD[4])
    floor_shadow(c, x0, 5 * T, T)
    c.rect(x0 + 2, 5 * T - 4, 12, 4, SWOOD[2])
    c.ellipse(x0 + 8, 4 * T + 7, 6, 6, STONE[3]); c.ellipse(x0 + 8, 4 * T + 7, 4, 4, STONE[4]); c.ellipse(x0 + 8, 4 * T + 7, 1.5, 1.5, IRON[1])
    c.rect(x0 + 13, 4 * T + 6, 3, 1, SWOOD[4])

    # ---- C 계산대 (x3~7): 짙은 나무 + 쇠띠 + 붉은 모루 천 · 망치 · 장부 · 수리 맡긴 괭이
    x0, x1 = 3 * T, 8 * T
    floor_shadow(c, x0, 4 * T, x1 - x0)
    obox(c, x0, 3 * T - 3, x1 - x0, T + 3, SWOOD[2])
    c.rect(x0 + 1, 3 * T - 2, x1 - x0 - 2, 4, SWOOD[4]); c.rect(x0 + 1, 3 * T + 2, x1 - x0 - 2, 1, SWOOD[1])
    for yy in (3 * T + 5, 3 * T + 11):
        c.rect(x0 + 1, yy, x1 - x0 - 2, 1, IRON[2])
    rrect(c, 5 * T - 7, 3 * T - 2, 14, T + 1, 0.5, hexc("6e3226")); rrect(c, 5 * T - 6, 3 * T - 1, 12, T - 1, 0.5, hexc("a85a46"))
    anvil_mark(c, 5 * T, 3 * T + 7, hexc("f6ead2"))
    hammer(c, 3 * T + 6, 3 * T - 5, 0); c.rect(3 * T + 8, 3 * T - 2, 9, 2, SWOOD[4])
    rrect(c, 6 * T + 2, 3 * T - 5, 12, 5, 0.5, hexc("e8d6b0")); c.rect(6 * T + 8, 3 * T - 5, 1, 5, hexc("c9b48a"))
    farm_tool(c, 4 * T + 2, 3 * T - 6, 0, 0); c.rect(4 * T + 1, 3 * T - 2, 10, 1, SWOOD[4])

    # ---- O 광석 상자 (x1, y3~4) · B 통 (x1, y5)
    floor_shadow(c, T, 5 * T, T)
    for k, (yy, kind) in enumerate(((3 * T, "iron"), (4 * T, "copper"))):
        crate(c, T + 1, yy + 4, 14, 11, SWOOD[3])
        for q in range(4):
            ore_lump(c, T + 4 + q * 3, yy + 3 + (q % 2), ORE_COL[kind], 50 + k * 5 + q)
    floor_shadow(c, T, 6 * T, T)
    barrel(c, T, 5 * T, IRON[1]); coal_pile(c, T + 4, 5 * T + 1, 8, 3, 61)

    # ---- N 큰 모루 (x12~13, y5) on 그루터기: 달군 괭이날 · 망치 · 불똥
    ax = 12 * T
    floor_shadow(c, ax + 2, 6 * T, 2 * T - 4)
    rrect(c, ax + 9, 5 * T + 6, 14, 10, 2, SWOOD[3]); c.ellipse(ax + 16, 5 * T + 6.5, 7, 1.8, SWOOD[4])
    for xx in range(ax + 11, ax + 22, 3):
        c.rect(xx, 5 * T + 9, 1, 6, SWOOD[2])
    c.rect(ax + 2, 5 * T - 3, 26, 6, IRON[1]); c.rect(ax + 2, 5 * T - 3, 26, 1, IRON[4]); c.rect(ax + 2, 5 * T - 2, 26, 1, IRON[3])
    c.rect(ax - 3, 5 * T - 2, 5, 3, IRON[1]); c.rect(ax - 5, 5 * T - 2, 2, 2, IRON[1]); c.set(ax - 6, 5 * T - 2, IRON[2])
    c.rect(ax + 8, 5 * T + 3, 14, 3, IRON[0]); c.rect(ax + 5, 5 * T + 6, 20, 2, IRON[1]); c.rect(ax + 5, 5 * T + 6, 20, 1, IRON[2])
    rrect(c, ax + 4, 5 * T - 6, 9, 3, 0.5, FIRE[2]); c.rect(ax + 5, 5 * T - 6, 6, 1, FIRE[3]); c.set(ax + 12, 5 * T - 5, FIRE[1])
    hammer(c, ax + 17, 5 * T - 9, 0); c.rect(ax + 19, 5 * T - 6, 9, 2, SWOOD[4])
    for sx, sy in ((ax + 1, 5 * T - 9), (ax + 14, 5 * T - 11), (ax + 9, 5 * T - 13), (ax + 3, 5 * T - 12), (ax + 16, 5 * T - 8)):
        c.set(sx, sy, FIRE[3])
    floor_shadow(c, 14 * T, 6 * T, T)
    rrect(c, 14 * T + 1, 5 * T + 3, 14, 13, 2.5, SWOOD[3]); c.rect(14 * T + 1, 5 * T + 8, 14, 1, IRON[1]); c.rect(14 * T + 1, 5 * T + 13, 14, 1, IRON[1])
    c.ellipse(14 * T + 8, 5 * T + 4.5, 5.5, 2, hexc("3a4a55")); c.set(14 * T + 6, 5 * T + 4, hexc("6f8a99"))
    for k in range(3):
        c.set(14 * T + 5 + k * 3, 5 * T - k % 2, hexc("d8d4cc")); c.set(14 * T + 6 + k * 3, 5 * T - 2 - k % 2, hexc("ece8e0"))

    # ---- H 농기구 걸이 (x1, y6~8): 괭이 · 삽 · 곡괭이 · 낫 (강화 대기)
    obox(c, T, 6 * T, 13, 3 * T, SWOOD[2], 0.5)
    for k in range(4):
        farm_tool(c, T + 4, 6 * T + 2 + k * 11, k, 7)
    c.rect(T + 2, 6 * T + 1, 9, 1, IRON[2])

    # ---- E 강화 작업대 (x4~7, y7): 두꺼운 상판 + 쇠 바이스 + 숫돌 + 달군 날 + 강화석 상자
    x0, x1 = 4 * T, 8 * T
    floor_shadow(c, x0, 8 * T, x1 - x0)
    obox(c, x0, 7 * T + 1, x1 - x0, 13, SWOOD[3])
    c.rect(x0 + 1, 7 * T + 2, x1 - x0 - 2, 3, SWOOD[4]); c.rect(x0 + 1, 7 * T + 7, x1 - x0 - 2, 1, IRON[2])
    c.rect(x0 + 3, 7 * T + 13, 3, 3, SWOOD[1]); c.rect(x1 - 6, 7 * T + 13, 3, 3, SWOOD[1])
    c.rect(x0 + 4, 7 * T - 4, 10, 6, IRON[2]); c.rect(x0 + 4, 7 * T - 4, 10, 1, IRON[4]); c.rect(x0 + 13, 7 * T - 2, 5, 1, IRON[3])
    rrect(c, x0 + 19, 7 * T - 2, 16, 4, 1, FIRE[2]); c.rect(x0 + 20, 7 * T - 2, 12, 1, FIRE[3]); c.set(x0 + 33, 7 * T, FIRE[1])   # 달군 낫날
    c.rect(x0 + 34, 7 * T, 6, 1, SWOOD[4])
    rrect(c, x0 + 42, 7 * T - 3, 14, 6, 1, STONE[3]); c.rect(x0 + 43, 7 * T - 3, 12, 1, STONE[4])                         # 숫돌
    obox(c, x0 + 26, 7 * T + 5, 12, 6, SWOOD[1], 0.5)
    for q in range(3):
        c.rect(x0 + 28 + q * 3, 7 * T + 7, 2, 2, (ORE_COL["gold"], hexc("7fb4d6"), ORE_COL["copper"])[q])                    # 강화 재료
    for sx, sy in ((x0 + 22, 7 * T - 5), (x0 + 30, 7 * T - 6), (x0 + 26, 7 * T - 8)):
        c.set(sx, sy, FIRE[3])

    # ---- M 금속 재료 (x14~16, y7~8): 쇠막대 더미 · 광석 수레 · 석탄 자루
    x0 = 14 * T
    floor_shadow(c, x0, 9 * T, 3 * T)
    for k in range(5):
        c.rect(x0 + 2, 7 * T + 4 + k * 3, 18, 2, (IRON[3], IRON[2])[k % 2]); c.set(x0 + 2, 7 * T + 4 + k * 3, IRON[4])
    c.rect(x0 + 4, 7 * T + 2, 2, 17, SWOOD[3]); c.rect(x0 + 15, 7 * T + 2, 2, 17, SWOOD[3])
    rrect(c, x0 + 22, 7 * T + 8, 24, 14, 2, IRON[2]); c.rect(x0 + 22, 7 * T + 8, 24, 2, IRON[4])                   # 광석 수레
    for q in range(6):
        ore_lump(c, x0 + 26 + q * 3.4, 7 * T + 7 - (q % 2), ORE_COL[("iron", "copper", "iron", "gold", "iron", "copper")[q]], 70 + q)
    for wx in (x0 + 26, x0 + 41):
        c.ellipse(wx, 8 * T + 6, 3.5, 3.5, SWOOD[1]); c.ellipse(wx, 8 * T + 6, 1.5, 1.5, IRON[3])
    rrect(c, x0 + 4, 8 * T + 3, 14, 12, 3, hexc("4a3a30")); c.rect(x0 + 6, 8 * T + 2, 10, 3, hexc("3a2e26"))
    coal_pile(c, x0 + 6, 8 * T, 10, 4, 81)

    # ---- B 물통 (x1, y9) · S 석탄 양동이 (x1, y10)(x16, y10)
    floor_shadow(c, T, 10 * T, T)
    barrel(c, T, 9 * T, hexc("3a4a55"))
    for bx in (T, 16 * T):
        floor_shadow(c, bx, 11 * T, T)
        rrect(c, bx + 3, 10 * T + 5, 10, 10, 2, IRON[2]); c.rect(bx + 3, 10 * T + 5, 10, 1, IRON[4])
        coal_pile(c, bx + 4, 10 * T + 3, 8, 4, 90 + bx)
        c.rect(bx + 2, 10 * T + 2, 1, 5, IRON[3]); c.rect(bx + 13, 10 * T + 2, 1, 5, IRON[3]); c.rect(bx + 2, 10 * T + 1, 12, 1, IRON[3])
    c.save("interior_smith.png")


# ---------------------------------------------------------------- 마을 주민·동물 (무드 이미지: 삼색 고양이 · 누렁 강아지 · 벤치 할머니 · 바구니 든 아이)
#   한 장에 프레임을 가로로 늘어놓는다 (왼쪽부터 0, 1, 2 ...). 오른쪽을 보는 그림이고, 왼쪽은 게임이 뒤집는다

def cat_frame(c, ox, pose):
    """16x14 삼색 고양이. pose: 0 앉기, 1 걷기 A, 2 걷기 B, 3 웅크려 자기"""
    white, orange, black, pink = hexc("fbf6ec"), hexc("e8a050"), hexc("3a2e28"), hexc("f0a8bd")
    c.ellipse(ox + 8, 13, 6, 1.2, SOFT_SHADOW)
    if pose == 3:
        c.ellipse(ox + 8, 10, 6, 3.5, white); c.ellipse(ox + 6, 9, 3, 2.5, orange); c.ellipse(ox + 11, 10, 2, 2, black)
        c.ellipse(ox + 12, 8.5, 3, 2.6, white); c.set(ox + 11, 6, orange); c.set(ox + 14, 6, black)
        c.rect(ox + 11, 9, 2, 1, black)   # 감은 눈
        c.rect(ox + 2, 11, 4, 1, orange)  # 말린 꼬리
        return
    if pose == 0:
        c.ellipse(ox + 7, 9.5, 4, 4, white); c.ellipse(ox + 6, 8, 2.5, 2.5, orange)
        c.rect(ox + 5, 12, 2, 1, white); c.rect(ox + 8, 12, 2, 1, white)
        c.rect(ox + 2, 8, 1, 4, black); c.set(ox + 3, 12, black)          # 꼬리
        hx, hy = 10, 5
    else:
        c.ellipse(ox + 7, 9, 5, 3, white); c.ellipse(ox + 5, 8.5, 2.5, 2, orange); c.ellipse(ox + 9, 8, 1.8, 1.5, black)
        legs = (3, 9) if pose == 1 else (5, 7)
        for lx in legs:
            c.rect(ox + lx, 11, 1, 2, white)
        c.rect(ox + legs[0] + 1, 11, 1, 2, white); c.rect(ox + legs[1] + 2, 11, 1, 2, white)
        c.rect(ox + 1, 6, 1, 3, orange); c.set(ox + 2, 8, orange)
        hx, hy = 12, 6
    c.ellipse(ox + hx, hy + 1.5, 3, 2.8, white)
    c.set(ox + hx - 2, hy - 1, orange); c.set(ox + hx - 2, hy - 2, orange)    # 귀
    c.set(ox + hx + 2, hy - 1, black); c.set(ox + hx + 2, hy - 2, black)
    c.ellipse(ox + hx - 1, hy + 1, 1.5, 1.2, orange)
    c.set(ox + hx, hy + 1, black); c.set(ox + hx + 2, hy + 1, black); c.set(ox + hx + 1, hy + 2, pink)


def dog_frame(c, ox, pose):
    """20x16 누렁 강아지 (무드의 골든 리트리버). pose: 0 앉기, 1 걷기 A, 2 걷기 B, 3 꼬리 흔들기(앉아서)"""
    fur, fur_d, fur_l, ink = hexc("e0a85a"), hexc("b87a3a"), hexc("f3cf8f"), hexc("3a2e28")
    c.ellipse(ox + 10, 15, 8, 1.3, SOFT_SHADOW)
    if pose in (0, 3):
        c.ellipse(ox + 9, 11, 5, 4, fur); c.ellipse(ox + 8, 10, 3, 2.5, fur_l)
        c.rect(ox + 7, 14, 2, 1, fur_d); c.rect(ox + 11, 14, 2, 1, fur_d)
        tail_up = pose == 3
        c.rect(ox + 3, 9 if tail_up else 12, 3, 2, fur_d)
        if tail_up:
            c.set(ox + 2, 8, fur_d)
        hx, hy = 13, 5
    else:
        c.ellipse(ox + 9, 10, 7, 3.5, fur); c.ellipse(ox + 8, 9, 4, 2, fur_l)
        legs = (4, 12) if pose == 1 else (6, 10)
        for lx in legs:
            c.rect(ox + lx, 12, 2, 3, fur_d)
        c.rect(ox + 1, 8, 3, 2, fur_d)
        hx, hy = 15, 5
    c.ellipse(ox + hx, hy + 2, 3.5, 3.2, fur); c.ellipse(ox + hx + 2.5, hy + 3.5, 2, 1.5, fur_l)
    c.ellipse(ox + hx - 2, hy + 2.5, 1.5, 2.5, fur_d)                  # 늘어진 귀
    c.set(ox + hx, hy + 1, ink); c.set(ox + hx + 4, hy + 3, ink)       # 눈·코
    c.set(ox + hx + 3, hy + 5, hexc("e0715f"))                         # 혀


def make_townsfolk():
    # 고양이 4프레임 (64x14), 강아지 4프레임 (80x16)
    c = Canvas(16 * 4, 14)
    for i in range(4):
        cat_frame(c, i * 16, i)
    c.outline(INK)
    c.save("cat.png")
    c = Canvas(20 * 4, 16)
    for i in range(4):
        dog_frame(c, i * 20, i)
    c.outline(INK)
    c.save("dog.png")

    # 벤치 할머니 (앉아서 뜨개질, 2프레임 16x22): 회색 쪽머리 · 안경 · 자주 카디건 · 앞치마 · 털실
    skin, hair, hair_l = hexc("f2d3b0"), hexc("b8b4ac"), hexc("dcd8d0")
    card, card_d, apron = hexc("9a5a7a"), hexc("7a3f5f"), hexc("f6ead2")
    c = Canvas(16 * 2, 22)
    for i in range(2):
        ox = i * 16
        c.ellipse(ox + 8, 21, 5, 1.1, SOFT_SHADOW)
        c.rect(ox + 5, 17, 2, 3, hexc("5b4636")); c.rect(ox + 9, 17, 2, 3, hexc("5b4636"))   # 다리 (앉음)
        rrect(c, ox + 3, 10, 10, 8, 2, card); c.rect(ox + 3, 16, 10, 2, card_d)
        rrect(c, ox + 5, 12, 6, 6, 1, apron)
        c.ellipse(ox + 8, 6.5, 4, 4, skin)
        c.rect(ox + 4, 2, 8, 3, hair); c.set(ox + 4, 5, hair); c.set(ox + 11, 5, hair)
        c.ellipse(ox + 8, 1.5, 2.2, 1.6, hair_l)                                          # 쪽머리
        c.rect(ox + 5, 7, 2, 1, hexc("6b5a4a")); c.rect(ox + 9, 7, 2, 1, hexc("6b5a4a"))  # 안경
        c.set(ox + 8, 9, hexc("e0715f"))
        # 뜨개질: 바늘 두 개 + 털실 뭉치 (프레임마다 바늘이 움직임)
        c.ellipse(ox + 8, 14, 2.5, 1.8, hexc("e0715f")); c.set(ox + 7, 13, hexc("f0a8bd"))
        dy = 0 if i == 0 else 1
        c.rect(ox + 4, 12 + dy, 4, 1, hexc("d9d4c8")); c.rect(ox + 9, 13 - dy, 4, 1, hexc("d9d4c8"))
        c.ellipse(ox + 13, 18, 2, 1.6, hexc("7fb069"))                                    # 바구니 속 털실
    c.outline(INK)
    c.save("grandma.png")

    # 바구니 든 아이 (16x24, 4프레임: 정면 서기 · 정면 걷기 둘 · 옆 걷기): 빨간 두건 · 땋은 머리 · 크림 블라우스 · 갈색 치마 · 채소 바구니
    skin, hair = hexc("f2d3b0"), hexc("7a4e32")
    scarf, scarf_d = hexc("d9534f"), hexc("a83a36")
    blouse, skirt, skirt_d = hexc("fbf3e1"), hexc("8a5a3a"), hexc("6b4528")
    c = Canvas(16 * 4, 24)
    for i in range(4):
        ox = i * 16
        c.ellipse(ox + 8, 22.5, 5, 1.2, SOFT_SHADOW)
        if i == 0:
            lx = (5, 9)
        elif i == 1:
            lx = (4, 9)
        elif i == 2:
            lx = (5, 10)
        else:
            lx = (6, 8)
        for x in lx:
            c.rect(ox + x, 19, 2, 3, hexc("5b4636"))
        rrect(c, ox + 4, 14, 8, 6, 1.5, skirt); c.rect(ox + 4, 18, 8, 2, skirt_d)
        rrect(c, ox + 4, 10, 8, 5, 1.5, blouse)
        c.ellipse(ox + 8, 6.5, 4, 4, skin)
        c.rect(ox + 4, 2, 8, 3, scarf); c.rect(ox + 4, 4, 8, 1, scarf_d); c.set(ox + 12, 5, scarf)   # 두건
        c.rect(ox + 3, 6, 1, 6, hair); c.set(ox + 3, 12, scarf)                                          # 땋은 머리
        if i == 3:
            c.set(ox + 10, 7, INK); c.set(ox + 9, 9, hexc("e0715f"))
        else:
            c.set(ox + 6, 7, INK); c.set(ox + 10, 7, INK); c.set(ox + 8, 9, hexc("e0715f"))
        # 채소 바구니 (오른팔)
        rrect(c, ox + 10, 13, 6, 4, 1, hexc("c98c5c")); c.rect(ox + 10, 13, 6, 1, hexc("e6b77f"))
        c.set(ox + 11, 12, hexc("e8a050")); c.set(ox + 13, 12, hexc("7fb069")); c.set(ox + 14, 11, hexc("d9534f"))
    c.outline(INK)
    c.save("villager.png")


def npc(c, skin, hair, top, top_d, apron=None, extra=None):
    """16x24 정면 서 있는 사람"""
    c.ellipse(8, 22.5, 5, 1.2, SOFT_SHADOW)
    c.rect(5, 18, 2, 4, hexc("5b4636")); c.rect(9, 18, 2, 4, hexc("5b4636"))   # 다리
    rrect(c, 3, 10, 10, 9, 2, top)                               # 몸
    c.rect(3, 16, 10, 2, top_d)
    c.rect(2, 11, 2, 6, top); c.rect(12, 11, 2, 6, top)          # 팔
    c.set(2, 17, skin); c.set(13, 17, skin)
    if apron:
        rrect(c, 5, 12, 6, 7, 1, apron)
    c.ellipse(8, 6.5, 4.2, 4.2, skin)                            # 머리
    c.rect(4, 2, 8, 3, hair); c.set(4, 5, hair); c.set(11, 5, hair)
    c.set(6, 7, INK); c.set(10, 7, INK); c.set(8, 9, hexc("e0715f"))
    if extra:
        extra(c)
    c.outline(INK)


def make_npcs():
    skin = hexc("f2d3b0")
    c = Canvas(T, 24)
    npc(c, skin, hexc("7a4e32"), hexc("fff8ea"), hexc("e6d6b8"), apron=hexc("7fb069"))
    c.save("npc_store.png")
    c = Canvas(T, 24)
    def beard(cv):
        cv.rect(5, 8, 6, 3, hexc("8a5a3a")); cv.set(6, 7, INK); cv.set(10, 7, INK)
    npc(c, hexc("e8b98f"), hexc("5b3a29"), hexc("c0503a"), hexc("92281e"), apron=hexc("8a5a3a"), extra=beard)
    c.save("npc_smith.png")
    c = Canvas(T, 24)
    def goggles(cv):
        cv.rect(4, 3, 8, 2, hexc("6f8296")); cv.set(6, 3, hexc("c2ecfa")); cv.set(10, 3, hexc("c2ecfa"))
    npc(c, skin, hexc("3b2a20"), hexc("5aa3cc"), hexc("3f7fa8"), extra=goggles)
    c.save("npc_machine.png")


# ---------------------------------------------------------------- 하늘시장 (§84~§90)
#   광장 비행선 정류장 (4x3칸, 64x60): 부서진 모습 / 복구한 모습 (계류탑 + 깃발 + 작은 비행선)
#   하늘섬 가판대 (3x2칸, 48x40): 하늘색 줄무늬 천막 / 하늘섬 비행선 (4x3칸, 64x72): 풍선 + 나무 곤돌라

SKY_BLUE, SKY_BLUE_D, SKY_BLUE_L = hexc("7cc4e6"), hexc("5aa3cc"), hexc("c2ecfa")


def balloon(c, cx, cy, rx, ry):
    c.ellipse(cx, cy, rx, ry, SKY_BLUE)
    for k in range(-2, 3):
        x = int(cx + k * rx / 2.6)
        for y in range(int(cy - ry) + 1, int(cy + ry)):
            if c.get(x, y)[3]:
                c.set(x, y, SKY_BLUE_D if k % 2 else hexc("fff8ea"))
    c.ellipse(cx - rx / 3, cy - ry / 2.2, rx / 4, ry / 5, SKY_BLUE_L)


def gondola(c, x, y, w, h):
    wd = P["wood"]
    rrect(c, x, y, w, h, 2, wd[1])
    c.rect(x + 1, y + 1, w - 2, 1, wd[3])
    for xx in range(x + 3, x + w - 2, 4):
        c.rect(xx, y + 2, 1, h - 3, wd[0])


def make_sky_station():
    wd = P["wood"]
    st = [hexc("9a8b7d"), hexc("b5a696"), hexc("cdbfae")]
    for restored in (False, True):
        c = Canvas(64, 60)
        c.ellipse(32, 58.5, 30, 1.6, SOFT_SHADOW)
        # 돌 바닥 받침
        rrect(c, 2, 46, 60, 13, 2, st[1])
        for x in range(4, 60, 8):
            c.rect(x, 47, 1, 11, st[0])
        c.rect(3, 46, 58, 1, st[2])
        # 계류탑 (나무 기둥 + 꼭대기 고리)
        c.rect(46, 10, 4, 37, wd[1]); c.rect(46, 10, 1, 37, wd[2])
        for y in range(16, 46, 7):
            c.rect(44, y, 8, 1, wd[0])
        c.ellipse(48, 9, 4, 3, wd[0]); c.ellipse(48, 9, 2, 1.4, CLEAR)
        # 계단
        for k in range(4):
            c.rect(10 + k * 3, 42 - k * 3, 14 - k * 3, 3, wd[2 if k % 2 else 1])
        if restored:
            # 깃발 + 매어 둔 작은 비행선
            c.rect(48, 2, 1, 8, wd[0]); c.rect(49, 2, 7, 4, hexc("e0715f")); c.rect(49, 5, 7, 1, hexc("b85d44"))
            balloon(c, 22, 14, 15, 10)
            for x in (12, 32):
                c.rect(x, 22, 1, 8, wd[0])
            gondola(c, 10, 29, 24, 9)
            c.rect(34, 13, 12, 1, hexc("d9c9a8"))   # 밧줄
        else:
            # 부서진 판자·쓰러진 깃대·찢어진 천 조각
            c.rect(30, 38, 14, 3, wd[0]); c.rect(33, 35, 3, 4, wd[1])
            for x, y in ((14, 30), (22, 33), (36, 28)):
                c.rect(x, y, 6, 2, wd[2]); c.set(x + 6, y + 1, wd[0])
            c.rect(52, 30, 8, 2, wd[1])
            c.rect(16, 24, 9, 4, hexc("c9d3dc")); c.set(18, 25, hexc("94a3b2")); c.set(22, 26, hexc("94a3b2"))
        c.outline(INK)
        c.save("sky_station.png" if restored else "sky_station_broken.png")


def make_sky_stall():
    wd = P["wood"]
    c = Canvas(48, 40)
    c.ellipse(24, 38.5, 22, 1.5, SOFT_SHADOW)
    rrect(c, 4, 22, 40, 17, 1.5, wd[2])
    c.rect(4, 22, 40, 2, wd[3])
    for x in range(8, 44, 9):
        c.rect(x, 25, 1, 13, wd[1])
    # 판매대 위 상자 (작물·병)
    for x, col in ((8, "e0715f"), (14, "f2c443"), (30, "7fb069"), (36, "5a64b8")):
        rrect(c, x, 18, 5, 5, 1, hexc(col))
    # 기둥 + 하늘색 줄무늬 천막
    for x in (4, 42):
        c.rect(x, 8, 2, 15, wd[1])
    for x in range(0, 48):
        col = SKY_BLUE if (x // 4) % 2 == 0 else hexc("fff8ea")
        c.rect(x, 4, 1, 6, col)
        if x % 4 != 3:
            c.set(x, 10, col)
    c.rect(0, 4, 48, 1, SKY_BLUE_D)
    # 별 간판
    rrect(c, 18, 0, 12, 5, 1.5, hexc("f2c443"))
    c.set(24, 2, hexc("fff3c0"))
    c.outline(INK)
    c.save("sky_stall.png")


def make_airship():
    wd = P["wood"]
    c = Canvas(64, 72)
    c.ellipse(32, 70.5, 28, 1.6, SOFT_SHADOW)
    # 나무 선착장
    rrect(c, 4, 58, 56, 13, 2, wd[1])
    for x in range(6, 58, 6):
        c.rect(x, 59, 1, 11, wd[0])
    c.rect(5, 58, 54, 1, wd[3])
    # 풍선 + 곤돌라
    balloon(c, 32, 18, 26, 17)
    for x in (16, 48):
        c.rect(x, 32, 1, 13, wd[0])
    gondola(c, 12, 44, 40, 12)
    rrect(c, 26, 46, 12, 6, 1, hexc("ffd27a"))  # 창
    c.rect(31, 46, 1, 6, wd[1])
    # 프로펠러
    c.rect(52, 47, 2, 6, wd[0]); c.ellipse(57, 50, 2, 5, hexc("e6dccd"))
    c.outline(INK)
    c.save("airship.png")


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
    # 봄 양배추 (§36, 사용자 결정: 양배추 절임 재료). 줄 번호 15
    "cabbage": [hexc("3d6b35"), hexc("4f8a3f"), hexc("6aa84e"), hexc("8cc463"), hexc("b4dc88")],
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
    "cabbage": {"field_y": 10, "seed": "8fc46a"},
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
    elif kind == "cabbage":
        outer, mid, inner, vein = hexc("6aa84e"), hexc("9ccf6e"), hexc("d6efb0"), hexc("4f8a3f")
        rx, ry = (6.0, 5.0) if big else (3.6, 2.8)
        c.ellipse(cx, cy, rx, ry, outer)
        c.ellipse(cx, cy - ry * 0.15, rx * 0.72, ry * 0.72, mid)
        c.ellipse(cx, cy - ry * 0.25, rx * 0.4, ry * 0.42, inner)
        c.rect(int(cx), int(cy - ry * 0.5), 1, int(ry), vein)
        c.set(int(cx - rx * 0.6), int(cy), vein); c.set(int(cx + rx * 0.6), int(cy), vein)
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
    elif kind in ORE_ICONS or kind == "gold_ore":
        # 광석 덩이: 회갈색 돌 + 광석 알갱이 (석탄은 통째로 검다)
        ore = kind.replace("_ore", "")
        d, m, hi = (hexc(x) for x in ORE[ore])
        base = [d, m, m, hi, hi] if ore == "coal" else CAVE_ROCK
        blob(c, [(8, 9.5, 4.8), (5.5, 10.5, 3), (10.5, 10.5, 3.2)], base)
        if ore != "coal":
            for x, y in ((6, 8), (9, 10), (10, 7), (5, 11)):
                c.set(x, y, m); c.set(x + 1, y, d); c.set(x, y - 1, hi)
        else:
            c.set(6, 7, hi); c.set(7, 7, hi); c.set(10, 9, hi)
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
    elif item == "pickled_cabbage":
        product_jar(c, "c6d86a", "9aae44", lid="c9a03a")
        c.rect(6, 9, 4, 1, hexc("eaf3c0"))
    elif item == "vegetable_pickle_set":
        rrect(c, 1, 10, 14, 5, 1, P["wood"][2]); c.rect(2, 10, 12, 1, P["wood"][3])          # 나무 상자
        for x, fill in ((2, "c6d86a"), (6, "8a5aa8"), (10, "f4f1e6")):
            rrect(c, x, 4, 4, 7, 1.5, hexc("e4f1f2")); rrect(c, x + 1, 6, 2, 4, 1, hexc(fill)); c.rect(x, 3, 4, 2, hexc("c9a03a"))
    elif item == "premium_jam":
        product_jar(c, "c2304a", "8e1f35", lid="f2c443")
        c.set(13, 2, hexc("fff3c0")); c.set(14, 1, hexc("fff3c0")); c.set(12, 1, hexc("fff3c0"))   # 반짝임
    c.outline(INK)


# 기계 아이템 아이콘 (아이콘 64번부터): 기계상점에서 사서 가방에 드는 기계. 시설 그림을 16x16 안에 줄여 그린다
MACHINE_ICONS = [("sprinkler_1", "sprinkler_1"), ("sprinkler_2", "sprinkler_2"), ("sprinkler_3", "sprinkler_3"),
                 ("harvester_1", "harvester_1"), ("harvester_2", "harvester_2"), ("harvester_3", "harvester_3"),
                 ("pump", "pump"), ("water_tank", "water_tank"), ("warehouse", "warehouse"),
                 ("splitter", "splitter_0"), ("merger", "merger_0"), ("filter_splitter", "filter_splitter_0"),
                 ("manual_processor", "processor"), ("electric_processor", "electric_processor"), ("small_generator", "generator"),
                 ("mid_processor", "mid_processor")]  # 중급 가공기 (아이콘 79번)
# 용광로 (97번) 와 주괴 3종 (98번부터): 금 광석 다음에 붙인다
FURNACE_ICONS = ["furnace", "copper_bar", "iron_bar", "gold_bar"]
# 양상추 (101번부터, 사용자 결정: 양배추와 별개). 사용자 그림이 없을 때만 양배추 모양으로 대신 그린다
LETTUCE_ICONS = ["lettuce_seed", "lettuce"]
# 그다음 새 아이템 (아이콘 80번부터): 봄 양배추 · 2급 가공품. 앞 번호를 밀지 않게 맨 뒤에 붙인다
NEW_ICONS = ["cabbage_seed", "cabbage", "pickled_cabbage", "vegetable_pickle_set", "premium_jam"]
NEW_PRODUCTS = ["pickled_cabbage", "vegetable_pickle_set", "premium_jam"]
# 아이템 아이콘 한 칸 (items.png). 사용자 그림을 살리려고 16 → 32 (게임 화면 크기는 그대로)
ICON = 32
USER_ICONS = Path(__file__).resolve().parent.parent / "assets" / "art_src" / "items"
# 광산 광석 (아이콘 85번부터)
ORE_ICONS = ["coal", "copper_ore", "iron_ore"]
# 도구 3·4단계 (철·금, 아이콘 88번부터) + 금 광석 (96번). 그림은 사용자 그림 (assets/art_src/items)
TOOL_ICONS_34 = ["hoe_3", "watering_can_3", "axe_3", "pickaxe_3", "hoe_4", "watering_can_4", "axe_4", "pickaxe_4"]


def load_png(name, folder=None):
    """PNG (8비트 RGBA/RGB, 모든 필터) 를 읽는다. 이 스크립트가 저장한 것과 사용자 그림(assets/art_src) 둘 다"""
    data = ((folder or OUT) / name).read_bytes()
    pos, w, h, idat, ctype = 8, 0, 0, b"", 6
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        tag, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if tag == b"IHDR":
            w, h = struct.unpack(">II", body[:8])
            ctype = body[9]
        elif tag == b"IDAT":
            idat += body
    raw = zlib.decompress(idat)
    bpp = 4 if ctype == 6 else 3
    stride = w * bpp
    c = Canvas(w, h)
    prev = bytearray(stride)
    for y in range(h):
        ft = raw[y * (stride + 1)]
        row = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = row[i - bpp] if i >= bpp else 0
            b = prev[i]
            cc = prev[i - bpp] if i >= bpp else 0
            if ft == 1:
                row[i] = (row[i] + a) & 255
            elif ft == 2:
                row[i] = (row[i] + b) & 255
            elif ft == 3:
                row[i] = (row[i] + (a + b) // 2) & 255
            elif ft == 4:
                p = a + b - cc
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - cc)
                row[i] = (row[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else cc)) & 255
        for x in range(w):
            px = tuple(row[x * bpp:x * bpp + bpp])
            c.px[y][x] = px if bpp == 4 else px + (255,)
        prev = row
    return c


def shrink_icon(c, src):
    """src 를 16x16 안(여백 1칸)에 비율 그대로 줄여 가운데 아래에 놓는다. 가장 가까운 칸을 고른다"""
    s = min(14 / src.w, 15 / src.h, 1.0)
    w, h = max(1, round(src.w * s)), max(1, round(src.h * s))
    ox, oy = (T - w) // 2, T - h
    for y in range(h):
        for x in range(w):
            px = src.get(min(src.w - 1, int((x + 0.5) / s)), min(src.h - 1, int((y + 0.5) / s)))
            if px[3] > 128:
                c.set(ox + x, oy + y, px[:3] + (255,))


# ---------------------------------------------------------------- 광산 (사용자 결정: 광장 북쪽 숲길 끝, 아래로 내려가는 층)

ORE = {  # 광석 무늬 색: [어두운, 밝은, 반짝임]
    "coal": ["2b2b2e", "4a4a50", "77777f"],
    "copper": ["9a4a24", "c46a3a", "f0a070"],
    "iron": ["4f5866", "a9b8cc", "eef3f8"],
    "gold": ["a8741a", "f2c443", "fff3c0"],
}
CAVE = [hexc("3a2f26"), hexc("4a3d33"), hexc("54453a"), hexc("5f4f42"), hexc("6e5c4d")]
CAVE_ROCK = [hexc("5e5650"), hexc("78706a"), hexc("948b82"), hexc("ada398"), hexc("c8beb2")]


def ore_rock(c, ore, seed):
    """광산 바위 (16x16). ore 가 있으면 광석 알갱이를 박는다"""
    c.ellipse(8, 14, 6.5, 1.5, (20, 14, 10, 90))
    blob(c, [(8, 9.5, 5.6), (4.8, 11.5, 3.5), (11.4, 11.2, 3.8)], CAVE_ROCK)
    c.set(5, 6, CAVE_ROCK[4]); c.set(6, 6, CAVE_ROCK[4])
    if ore:
        d, m, hi = (hexc(x) for x in ORE[ore])
        r = random.Random(seed)
        for x, y in r.sample([(4, 9), (7, 7), (10, 8), (6, 11), (9, 11), (11, 10), (5, 12), (8, 9)], 4):
            c.set(x, y, m); c.set(x + 1, y, d); c.set(x, y + 1, d)
            c.set(x, y - 1, hi) if r.random() < 0.6 else None
    c.outline(hexc("231a14"))


def make_furnace():
    """용광로 (1x1, 16x24): 돌 아궁이 + 굴뚝. 아궁이 자리(아래 가운데)에 굽는 동안 불빛을 얹는다 (Furnace._draw_fire)"""
    c = Canvas(T, T + 8)
    H = c.h
    c.ellipse(8, H - 1.5, 7, 1.5, SOFT_SHADOW)
    st = [hexc("6f665e"), hexc("8a8178"), hexc("a39a90"), hexc("bdb3a8")]
    rrect(c, 1, 8, 14, H - 9, 2, st[1])
    for y in range(9, H - 2, 3):          # 돌 줄눈
        off = 0 if (y // 3) % 2 else 2
        for x in range(2 + off, 14, 4):
            c.rect(x, y, 3, 2, st[2])
            c.set(x, y, st[3])
    c.rect(5, 2, 6, 7, st[0]); c.rect(5, 2, 6, 1, st[2]); c.rect(6, 0, 4, 2, hexc("5b5550"))   # 굴뚝
    c.ellipse(8, H - 5.5, 4, 3.2, hexc("2a1d16")); c.rect(4, H - 6, 8, 3, hexc("2a1d16"))   # 아궁이
    c.rect(4, H - 3, 8, 1, hexc("8a5a3a"))
    c.outline(INK)
    c.save("furnace.png")


BAR_COLORS = {"copper_bar": ["9a4a24", "c46a3a", "f0a070"], "iron_bar": ["4f5866", "a9b8cc", "eef3f8"], "gold_bar": ["a8741a", "f2c443", "fff3c0"]}


def bar_icon(c, kind):
    """주괴: 비스듬한 사다리꼴 덩이 두 개"""
    d, m, hi = (hexc(x) for x in BAR_COLORS[kind])
    for oy, ox in ((8, 1), (4, 4)):
        for y in range(5):
            c.rect(ox + y // 2, oy + y, 10 - y // 2 * 2, 1, m if y else hi)
        c.rect(ox, oy + 4, 10, 1, d)
        c.set(ox + 2, oy + 1, hi); c.set(ox + 3, oy + 1, hi)
    c.outline(INK)


def make_mine():
    # 바닥 4가지 (16x16 씩 가로로) + 벽 2가지
    floor = Canvas(T * 4, T)
    for v in range(4):
        c, done = sub(floor, v, 0)
        r = random.Random(700 + v)
        c.rect(0, 0, T, T, CAVE[2])
        for _ in range(20):
            c.set(r.randrange(T), r.randrange(T), CAVE[r.choice((1, 3, 3))])
        for _ in range(2 + v):
            x, y = r.randrange(1, 14), r.randrange(1, 14)
            c.set(x, y, CAVE[4]); c.set(x + 1, y, CAVE[3]); c.set(x, y + 1, CAVE[1])
        done()
    floor.save("mine_floor.png")
    wall = Canvas(T * 2, T)
    for v in range(2):
        c, done = sub(wall, v, 0)
        r = random.Random(720 + v)
        c.rect(0, 0, T, T, CAVE[0])
        for k in range(5):  # 울퉁불퉁한 바위 덩이
            cx, cy = r.randrange(1, 15), r.randrange(1, 13)
            c.ellipse(cx, cy, r.uniform(2.5, 4.2), r.uniform(2, 3.2), hexc("4a3c31"))
            c.set(int(cx) - 1, int(cy) - 1, hexc("6a5646"))
        c.rect(0, 13, T, 3, hexc("2a211a"))  # 아래 그림자 (벽 밑동)
        done()
    wall.save("mine_wall.png")

    for name, ore, seed in (("mine_stone", None, 1), ("mine_coal", "coal", 2), ("mine_copper", "copper", 3), ("mine_iron", "iron", 4), ("mine_gold", "gold", 5)):
        c = Canvas(T, T)
        ore_rock(c, ore, seed)
        c.save(name + ".png")

    w = P["wood"]
    c = Canvas(T, T)  # 내려가는 사다리 (구멍 + 사다리 끝)
    c.ellipse(8, 9, 7, 5.5, hexc("120d0a"))
    c.ellipse(8, 8, 6, 4.2, hexc("1d1612"))
    for x in (5, 10):
        c.rect(x, 3, 1, 10, w[2]); c.set(x, 3, w[3])
    for y in (5, 8, 11):
        c.rect(5, y, 6, 1, w[1])
    c.outline(hexc("231a14"))
    c.save("mine_ladder_down.png")

    c = Canvas(T, T * 2)  # 올라가는 사다리 (벽에 기댐, 16x32)
    for x in (4, 11):
        c.rect(x, 1, 2, 30, w[2]); c.rect(x, 1, 1, 30, w[3])
    for y in range(4, 30, 4):
        c.rect(6, y, 5, 2, w[1]); c.rect(6, y, 5, 1, w[2])
    c.outline(hexc("231a14"))
    c.save("mine_ladder_up.png")

    c = Canvas(T * 2, T * 2 + 8)  # 엘리베이터 (나무 틀 + 철망 + 도르래, 32x40)
    H = c.h
    c.ellipse(16, H - 2, 15, 2, (20, 14, 10, 90))
    c.rect(2, 6, 28, H - 8, hexc("2a211a"))
    for x in (2, 27):
        c.rect(x, 4, 3, H - 6, w[1]); c.rect(x, 4, 1, H - 6, w[2])
    c.rect(1, 3, 30, 4, w[1]); c.rect(1, 3, 30, 1, w[3])
    c.ellipse(16, 4, 3, 3, hexc("8f939a")); c.set(16, 4, hexc("2b2b2e"))
    c.rect(16, 7, 1, 10, hexc("c9a03a"))
    c.rect(6, 17, 20, 2, hexc("8f939a")); c.rect(6, 17, 20, 1, hexc("c9ccd1"))   # 케이지 바닥 가로대
    for x in range(7, 26, 3):
        c.rect(x, 19, 1, H - 23, hexc("6f737a"))
    c.rect(5, H - 5, 22, 3, w[0]); c.rect(5, H - 5, 22, 1, w[2])
    c.rect(22, 22, 3, 4, hexc("f2c443")); c.set(23, 23, hexc("fff3c0"))   # 호출 버튼 등
    c.outline(hexc("231a14"))
    c.save("mine_elevator.png")

    c = Canvas(T, T)  # 보물 상자
    c.ellipse(8, 14, 6.5, 1.5, (20, 14, 10, 90))
    rrect(c, 2, 6, 12, 8, 1, w[1]); c.rect(2, 6, 12, 3, w[2]); c.rect(3, 6, 10, 1, w[3])
    c.rect(2, 9, 12, 1, hexc("c9a03a")); c.rect(7, 8, 2, 3, hexc("f2c443")); c.set(7, 8, hexc("fff3c0"))
    c.outline(hexc("231a14"))
    c.save("mine_chest.png")

    # 광장 북쪽 숲길 끝의 동굴 입구 (3칸 x 3칸 = 48x48). 바위 언덕 + 어두운 굴 + 나무 버팀목 + 등불
    c = Canvas(T * 3, T * 3)
    rock = [hexc("6f665e"), hexc("8a8178"), hexc("a39a90"), hexc("bdb3a8"), hexc("d6cdc2")]
    blob(c, [(24, 26, 21), (8, 34, 10), (40, 34, 10), (24, 12, 14)], rock)
    g = P["leaf"]
    for x, y, rr in ((9, 14, 4), (36, 11, 5), (24, 4, 4), (44, 24, 3)):
        c.ellipse(x, y, rr, rr * 0.8, g[2]); c.ellipse(x - 1, y - 1, rr * 0.6, rr * 0.45, g[3])
    c.ellipse(24, 37, 10, 12, hexc("120d0a"))
    c.rect(14, 37, 21, 11, hexc("120d0a"))
    c.ellipse(24, 38, 8, 10, hexc("1d1612"))
    for x in (12, 34):   # 버팀목 기둥
        c.rect(x, 26, 3, 22, w[1]); c.rect(x, 26, 1, 22, w[2])
    c.rect(11, 24, 27, 3, w[1]); c.rect(11, 24, 27, 1, w[3])
    c.rect(37, 28, 3, 4, hexc("f2c443")); c.set(38, 29, hexc("fff3c0")); c.rect(38, 26, 1, 2, hexc("2b2b2e"))  # 등불
    for x in range(16, 33, 3):   # 굴 안 레일 침목
        c.rect(x, 44, 2, 1, w[0])
    c.rect(15, 45, 19, 1, hexc("8f939a"))
    c.outline(INK)
    c.save("mine_entrance.png")


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
    order += [item for item, _ in MACHINE_ICONS]  # 기계 (아이콘 64번부터)
    order += NEW_ICONS  # 양배추·2급 가공품 (아이콘 80번부터)
    order += ORE_ICONS  # 광석 (아이콘 85번부터)
    order += TOOL_ICONS_34 + ["gold_ore"]  # 철·금 도구 (88번부터), 금 광석 (96번)
    order += FURNACE_ICONS  # 용광로 (97번), 주괴 (98번부터)
    order += LETTUCE_ICONS  # 양상추 씨앗·양상추 (101번부터)
    machine_art = dict(MACHINE_ICONS)
    atlas = Canvas(len(order) * T, T)
    for col, item in enumerate(order):
        c, done = sub(atlas, col, 0)
        if item in TOOL_ICONS_34:  # 사용자 그림이 없을 때만 보이는 대체 그림: 2단계 모양
            base = item[:-2]
            c.template({"hoe": HOE, "watering_can": CAN, "axe": AXE, "pickaxe": PICKAXE}[base], ICON_PAL_2)
        elif item in ("hoe_2", "watering_can_2", "axe_2", "pickaxe_2"):
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
        elif item == "lettuce_seed":
            seed_packet(c, hexc(CROP_ART["cabbage"]["seed"]))
        elif item == "lettuce":
            produce(c, "cabbage", 8, 8.5, big=True)
            c.outline(INK)
        elif item == "furnace":
            shrink_icon(c, load_png("furnace.png"))
        elif item in BAR_COLORS:
            bar_icon(c, item)
        elif item in machine_art:
            shrink_icon(c, load_png(machine_art[item] + ".png"))
        elif item in ("fiber", "wood", "stone", "conveyor", "gold_ore") or item in ORE_ICONS:
            material_icon(c, item)
        elif item.endswith("_fertilizer"):
            fertilizer_bag(c, item)
        elif item.endswith("_seed"):
            seed_packet(c, hexc(CROP_ART[item[:-5]]["seed"]))
        elif item in PRODUCTS or item in NEW_PRODUCTS:
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
    # 사용자 그림 (사용자 결정: 바탕 화면 '이미지' 폴더의 그림으로 아이콘 교체). 32x32 칸 아틀라스:
    # assets/art_src/items/<아이템 id>.png 가 있으면 그것, 없으면 위에서 그린 16x16 을 2배로 키운다
    hd = Canvas(len(order) * ICON, ICON)
    for col, item in enumerate(order):
        path = USER_ICONS / (item + ".png")
        if path.exists():
            hd.blit(load_png(path.name, USER_ICONS), col * ICON, 0)
        else:
            small = Canvas(T, T)
            for y in range(T):
                for x in range(T):
                    small.px[y][x] = atlas.get(col * T + x, y)
            hd.blit(small.scaled(ICON // T), col * ICON, 0)
    hd.save("items.png")


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


# ---------------------------------------------------------------- 마을 다리 · 화단 (마을 그래픽 정리)
# 다리: 칸마다 같은 '가로 다리' 한 장을 깔던 것을 → 놓인 방향과 이웃에 맞춘 타일로 (bridge.png)
#   줄 0 = 동서로 건너는 다리 (판자 이음매가 세로), 줄 1 = 남북으로 건너는 다리 (이음매가 가로)
#   칸 = 난간이 붙는 쪽 비트 (북1 동2 남4 서8): 물·석축과 맞닿은 쪽에만 난간. 길·땅 쪽(다리 끝)은 열림
# 화단: 둥근 꽃덤불 소품 대신 땅에 깐 '마을 장식 화단' (garden_bed.png)
#   칸 = 나무 테두리가 붙는 쪽 비트 (북1 동2 남4 서8: 화단 바깥과 맞닿은 쪽), 줄 = 꽃 배치 변형 3종

def _deck(c, vertical):
    """다리 바닥 판자. vertical=True 면 남북 다리 (판자가 가로로 놓여 이음매가 가로줄)"""
    w = P["wood"]
    c.rect(0, 0, T, T, w[2])
    for i in range(4):
        a = i * 4 + 3  # 이음매 (타일 경계에서도 같은 간격으로 이어지게 4px 주기)
        if vertical:
            c.rect(0, a, T, 1, w[1])
            c.rect(0, a - 3, T, 1, w[3])
            for x in ((i * 5 + 2) % 13 + 1, (i * 5 + 9) % 13 + 1):  # 못 자국 (칸마다 엇갈림)
                c.set(x, a - 1, w[1])
        else:
            c.rect(a, 0, 1, T, w[1])
            c.rect(a - 3, 0, 1, T, w[3])
            for y in ((i * 5 + 2) % 13 + 1, (i * 5 + 9) % 13 + 1):
                c.set(a - 1, y, w[1])


def _rail(c, side):
    """다리 난간 (그 쪽 가장자리 3px): 어두운 바깥선 + 가로대 + 밝은 윗면, 8px 마다 기둥"""
    w = P["wood"]
    if side in ("n", "s"):
        y = 0 if side == "n" else T - 3
        c.rect(0, y, T, 3, w[1])
        c.rect(0, y, T, 1, w[3])
        c.rect(0, y + 2, T, 1, w[0])
        for x in (3, 11):
            c.rect(x, y, 2, 3, w[0]); c.set(x, y, w[1])
        c.rect(0, y + (3 if side == "n" else -1), T, 1, SOFT_SHADOW)
    else:
        x = 0 if side == "w" else T - 3
        c.rect(x, 0, 3, T, w[1])
        c.rect(x + (2 if side == "w" else 0), 0, 1, T, w[3])
        c.rect(x + (0 if side == "w" else 2), 0, 1, T, w[0])
        for y in (3, 11):
            c.rect(x, y, 3, 2, w[0]); c.set(x + 1, y, w[1])
        c.rect(x + (3 if side == "w" else -1), 0, 1, T, SOFT_SHADOW)


def make_bridge_tiles():
    atlas = Canvas(16 * T, 2 * T)
    for row, vertical in enumerate((False, True)):
        for mask in range(16):
            c, done = sub(atlas, mask, row)
            _deck(c, vertical)
            for bit, side in ((1, "n"), (2, "e"), (4, "s"), (8, "w")):
                if mask & bit:
                    _rail(c, side)
            done()
    atlas.save("bridge.png")


def _bloom(c, x, y, petal, center):
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        c.set(x + dx, y + dy, petal)
    c.set(x, y, center)


def _shrub(c, x, y):
    """낮은 관상용 초록 포기 (4x3)"""
    lf = P["leaf"]
    c.rect(x, y + 1, 4, 2, lf[1]); c.rect(x + 1, y, 2, 1, lf[2])
    c.set(x + 1, y + 1, lf[3]); c.set(x + 2, y + 1, lf[2]); c.rect(x, y + 2, 4, 1, lf[0])


def make_garden_beds():
    """마을 장식 화단: 진한 흙 + 꽃·낮은 초록 포기, 바깥쪽에만 나무 테두리 (남쪽은 앞면이 보이게 두껍게)"""
    so, w, lf = P["soil"], P["wood"], P["leaf"]
    flowers = [(hexc("fff6e8"), hexc("f7c548")), (hexc("f7d26a"), hexc("fff3c0")),
               (hexc("f4b4c0"), hexc("fff1a8")), (hexc("c9b4e8"), hexc("fff6e8"))]
    layouts = [  # (종류, x, y): f=꽃(색 번호), s=초록 포기, l=잎 한 점
        [("s", 2, 2), ("f0", 9, 4), ("f2", 5, 9), ("l", 12, 10), ("s", 9, 10), ("f1", 12, 6)],
        [("f2", 4, 4), ("s", 8, 3), ("f3", 11, 9), ("s", 2, 9), ("l", 7, 12), ("f0", 7, 8)],
        [("s", 10, 2), ("f1", 4, 5), ("f3", 8, 7), ("s", 3, 10), ("f2", 12, 11), ("l", 11, 6)],
    ]
    atlas = Canvas(16 * T, len(layouts) * T)
    for row, layout in enumerate(layouts):
        rng = random.Random(500 + row)
        for mask in range(16):
            c, done = sub(atlas, mask, row)
            for y in range(T):  # 낮은 초록 지피식물 (잡초밭·작물밭과 다르게 빈 흙이 거의 안 보이게)
                for x in range(T):
                    c.set(x, y, rng.choices([lf[1], lf[2], lf[0], lf[3]], [6, 4, 2, 1])[0])
            # 테두리 안쪽 한 줄은 흙 (테두리가 또렷하게)
            if mask & 1:
                c.rect(0, 2, T, 1, so[1])
            if mask & 4:
                c.rect(0, T - 4, T, 1, so[0])
            if mask & 8:
                c.rect(2, 0, 1, T, so[1])
            if mask & 2:
                c.rect(T - 3, 0, 1, T, so[1])
            for kind, x, y in layout:
                if kind == "s":
                    _shrub(c, x - 1, y - 1)
                elif kind == "l":
                    c.set(x, y, lf[2]); c.set(x + 1, y - 1, lf[3])
                else:
                    col = flowers[int(kind[1])]
                    _bloom(c, x, y, *col)
                    c.set(x + 2, y + 2, col[0]); c.set(x - 2, y + 1, col[0])  # 옆 작은 꽃송이
            # 테두리 (바깥쪽만). 북·동·서 2px, 남 3px (앞면)
            if mask & 1:
                c.rect(0, 0, T, 2, w[2]); c.rect(0, 0, T, 1, w[3])
            if mask & 4:
                c.rect(0, T - 3, T, 3, w[1]); c.rect(0, T - 3, T, 1, w[3]); c.rect(0, T - 1, T, 1, w[0])
            if mask & 8:
                c.rect(0, 0, 2, T, w[2]); c.rect(0, 0, 1, T, w[3])
            if mask & 2:
                c.rect(T - 2, 0, 2, T, w[1]); c.rect(T - 1, 0, 1, T, w[0])
            if mask & 1 and mask & 8:
                c.set(0, 0, w[1])
            if mask & 4 and mask & 2:
                c.rect(T - 2, T - 3, 2, 3, w[0])
            if mask & 4 and mask & 8:
                c.rect(0, T - 3, 2, 3, w[1]); c.set(0, T - 3, w[3])
            done()
    atlas.save("garden_bed.png")


if __name__ == "__main__":
    print("BuildFarm art ->", OUT)
    make_tiles()
    make_bridge_tiles()
    make_garden_beds()
    make_details()
    make_edges()
    make_trees()
    make_undergrowth()
    make_rock()
    make_house()
    make_shop()
    make_shop_decor()
    make_plaza_props()
    make_mood_props()
    make_interior_store()
    make_interior_smith()
    make_interior_machine()
    make_townsfolk()
    make_placeables()
    make_greenhouse()
    make_compost_bin()
    make_conveyor()
    make_routers()
    make_pump()
    make_water_tank()
    make_sprinklers()
    make_harvesters()
    make_warehouse()
    make_processor()
    make_generator()
    make_electric_processor()
    make_mid_processor()
    make_well()
    make_mine()
    make_furnace()
    make_shipping_bin()
    make_blacksmith()
    make_recipe_shop()
    make_general_store()
    make_machine_shop()
    make_npcs()
    make_sky_station()
    make_sky_stall()
    make_airship()
    make_obstacles()
    make_player()
    make_crops()
    make_items()
    make_ui()
