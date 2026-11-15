"""Capsulets のアイコンを描く。

リポジトリのルートで実行すると icon.png（SideStore用）と AppIcon を書き出す:
    python3 tools/draw_icon.py
"""
import math, random
from PIL import Image, ImageDraw, ImageFilter

S = 4096  # 4倍で描いて最後に縮小（アンチエイリアス）
def sc(v): return int(v * 4)
random.seed(9084)

def layer():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))

# 背景：夜空のグラデーション
bg = Image.new("RGB", (S, S))
top, bot = (28, 30, 74), (74, 52, 140)
px = bg.load()
for y in range(S):
    t = y / (S - 1)
    c = tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3))
    for x in range(S):
        px[x, y] = c
img = bg.convert("RGBA")

# 星
stars = layer()
d = ImageDraw.Draw(stars)
for _ in range(70):
    x, y = random.uniform(30, 994), random.uniform(30, 994)
    # カプセルの上には置かない
    if abs((x - 512) + (y - 512)) < 260 and abs((x - 512) - (y - 512)) < 640:
        continue
    r = random.choice((2, 2, 3, 3, 4, 6))
    a = random.randint(120, 255)
    d.ellipse((sc(x - r), sc(y - r), sc(x + r), sc(y + r)), fill=(255, 255, 255, a))
img = Image.alpha_composite(img, stars)

# カプセル：横長に描いてから -45° 回転させる
L, W = 680, 300          # 全長と太さ
cx = cy = 512
cap = layer()
d = ImageDraw.Draw(cap)
x0, x1 = cx - L / 2, cx + L / 2
y0, y1 = cy - W / 2, cy + W / 2
left_col, right_col = (255, 196, 92), (250, 250, 255)

# 左半分（オレンジ）と右半分（白）
left = layer(); dl = ImageDraw.Draw(left)
dl.rounded_rectangle((sc(x0), sc(y0), sc(x1), sc(y1)), radius=sc(W / 2), fill=left_col + (255,))
mask = layer(); ImageDraw.Draw(mask).rectangle((0, 0, sc(cx), S), fill=(0, 0, 0, 255))
cap.paste(left, (0, 0), mask.getchannel("A"))

right = layer(); dr = ImageDraw.Draw(right)
dr.rounded_rectangle((sc(x0), sc(y0), sc(x1), sc(y1)), radius=sc(W / 2), fill=right_col + (255,))
mask = layer(); ImageDraw.Draw(mask).rectangle((sc(cx), 0, S, S), fill=(0, 0, 0, 255))
cap.paste(right, (0, 0), mask.getchannel("A"))

# 合わせ目
d = ImageDraw.Draw(cap)
d.line((sc(cx), sc(y0 + 6), sc(cx), sc(y1 - 6)), fill=(180, 150, 210, 255), width=sc(10))

# ツヤ（上側に細いハイライト）
gloss = layer()
ImageDraw.Draw(gloss).rounded_rectangle(
    (sc(x0 + 70), sc(y0 + 40), sc(x1 - 70), sc(y0 + 92)), radius=sc(26), fill=(255, 255, 255, 120)
)
a = gloss.getchannel("A").filter(ImageFilter.GaussianBlur(sc(5)))
gloss = Image.new("RGBA", (S, S), (255, 255, 255, 0)); gloss.putalpha(a)
cap_alpha = cap.getchannel("A")
gloss.putalpha(Image.composite(gloss.getchannel("A"), Image.new("L", (S, S), 0), cap_alpha))
cap = Image.alpha_composite(cap, gloss)

cap = cap.rotate(45, resample=Image.BICUBIC, center=(sc(cx), sc(cy)))

# 影
shadow = Image.new("RGBA", (S, S), (10, 8, 30, 0))
shadow.putalpha(cap.getchannel("A").point(lambda v: v * 0.55).filter(ImageFilter.GaussianBlur(sc(18))))
shadow = shadow.transform((S, S), Image.AFFINE, (1, 0, -sc(10), 0, 1, -sc(24)))
img = Image.alpha_composite(img, shadow)
img = Image.alpha_composite(img, cap)

out = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
out.save("icon.png")
out.save("Sources/Assets.xcassets/AppIcon.appiconset/icon.png")
