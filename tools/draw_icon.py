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
    if math.hypot(x - 512, y - 512) < 360:
        continue
    r = random.choice((2, 2, 3, 3, 4, 6))
    a = random.randint(120, 255)
    d.ellipse((sc(x - r), sc(y - r), sc(x + r), sc(y + r)), fill=(255, 255, 255, a))
img = Image.alpha_composite(img, stars)

# カプセル：ガチャのような丸いカプセル。上半分が色付き、下半分が白。少し傾ける
R = 330                  # 半径
cx = cy = 512
top_col, bottom_col = (255, 190, 80), (250, 250, 255)
band_col = (205, 190, 235)

cap = layer()
d = ImageDraw.Draw(cap)
box = (sc(cx - R), sc(cy - R), sc(cx + R), sc(cy + R))
d.pieslice(box, 180, 360, fill=top_col + (255,))
d.pieslice(box, 0, 180, fill=bottom_col + (255,))
# 合わせ目の帯（はめ込み部分）
d.rectangle((sc(cx - R), sc(cy - 14), sc(cx + R), sc(cy + 14)), fill=band_col + (255,))
circle = layer()
ImageDraw.Draw(circle).ellipse(box, fill=(0, 0, 0, 255))
cap.putalpha(Image.composite(cap.getchannel("A"), Image.new("L", (S, S), 0), circle.getchannel("A")))

# 立体感：下側に向かって少し暗くする
shade = layer()
ImageDraw.Draw(shade).ellipse(
    (sc(cx - R * 1.25), sc(cy - R * 1.45), sc(cx + R * 0.95), sc(cy + R * 0.75)), fill=(0, 0, 0, 255)
)
inv = Image.eval(shade.getchannel("A").filter(ImageFilter.GaussianBlur(sc(60))), lambda v: int((255 - v) * 0.22))
dark = Image.new("RGBA", (S, S), (40, 20, 90, 0))
dark.putalpha(Image.composite(inv, Image.new("L", (S, S), 0), cap.getchannel("A")))
cap = Image.alpha_composite(cap, dark)

# ツヤ（左上に丸いハイライト）
gloss = layer()
gd = ImageDraw.Draw(gloss)
gd.ellipse((sc(cx - 230), sc(cy - 250), sc(cx - 90), sc(cy - 150)), fill=(255, 255, 255, 170))
gd.ellipse((sc(cx - 70), sc(cy - 275), sc(cx - 30), sc(cy - 245)), fill=(255, 255, 255, 140))
a = gloss.getchannel("A").filter(ImageFilter.GaussianBlur(sc(6)))
gloss = Image.new("RGBA", (S, S), (255, 255, 255, 0)); gloss.putalpha(a)
cap = Image.alpha_composite(cap, gloss)

cap = cap.rotate(-20, resample=Image.BICUBIC, center=(sc(cx), sc(cy)))

# 影
shadow = Image.new("RGBA", (S, S), (10, 8, 30, 0))
shadow.putalpha(cap.getchannel("A").point(lambda v: v * 0.55).filter(ImageFilter.GaussianBlur(sc(18))))
shadow = shadow.transform((S, S), Image.AFFINE, (1, 0, -sc(10), 0, 1, -sc(24)))
img = Image.alpha_composite(img, shadow)
img = Image.alpha_composite(img, cap)

out = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
out.save("icon.png")
out.save("Sources/Assets.xcassets/AppIcon.appiconset/icon.png")
