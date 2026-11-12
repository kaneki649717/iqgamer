"""生成棋境 App 图标 v2：深色靛蓝玻璃底 + 黑白双棋子（独立图层着色）。"""
from PIL import Image, ImageDraw, ImageFilter
import os

S = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "App", "Assets.xcassets")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def stone_layer(radius, dark=True, ss=2):
    """在独立图层渲染棋子（2x 超采样），返回 RGBA 图（含边缘羽化）"""
    size = int(radius * 2.9) * ss
    r = radius * ss
    cx = cy = size / 2
    if dark:
        c_hi, c_lo = (86, 96, 126), (8, 9, 16)
        spec_alpha, spec_col = 235, (245, 248, 255)
        rim_col, rim_alpha = (120, 150, 230), 90
    else:
        c_hi, c_lo = (255, 255, 255), (168, 176, 200)
        spec_alpha, spec_col = 255, (255, 255, 255)
        rim_col, rim_alpha = (90, 120, 200), 70

    # 球面着色：光源在左上
    img = Image.new("RGB", (size, size))
    px = img.load()
    lx, ly = cx - r * 0.42, cy - r * 0.48
    maxd = ((2.1 * r) ** 2 + (2.1 * r) ** 2) ** 0.5
    for y in range(size):
        for x in range(size):
            d = ((x - lx) ** 2 + (y - ly) ** 2) ** 0.5 / maxd
            t = max(0.0, min(1.0, 1.0 - d * 1.35)) ** 1.4
            px[x, y] = lerp(c_lo, c_hi, t)
    # 圆形 alpha
    alpha = Image.new("L", (size, size), 0)
    ImageDraw.Draw(alpha).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    alpha = alpha.filter(ImageFilter.GaussianBlur(ss))
    layer = img.convert("RGBA")
    layer.putalpha(alpha)

    # 镜面高光（小而亮）
    spec = Image.new("L", (size, size), 0)
    sd = ImageDraw.Draw(spec)
    sd.ellipse([cx - r * 0.52, cy - r * 0.72, cx + r * 0.02, cy - r * 0.18], fill=spec_alpha)
    spec = spec.filter(ImageFilter.GaussianBlur(r * 0.10))
    sc = Image.new("RGBA", (size, size), spec_col + (0,))
    sc.putalpha(spec)
    layer.alpha_composite(sc)

    # 底部边缘反光（rim light）
    rim = Image.new("L", (size, size), 0)
    ImageDraw.Draw(rim).arc([cx - r * 0.94, cy - r * 0.94, cx + r * 0.94, cy + r * 0.94],
                            start=35, end=145, fill=rim_alpha, width=int(r * 0.09))
    rim = rim.filter(ImageFilter.GaussianBlur(r * 0.08))
    rc = Image.new("RGBA", (size, size), rim_col + (0,))
    rc.putalpha(rim)
    layer.alpha_composite(rc)

    # 白子加一点底部冷色反弹光
    if not dark:
        bounce = Image.new("L", (size, size), 0)
        ImageDraw.Draw(bounce).ellipse([cx - r * 0.5, cy + r * 0.3, cx + r * 0.5, cy + r * 0.95], fill=90)
        bounce = bounce.filter(ImageFilter.GaussianBlur(r * 0.22))
        bc = Image.new("RGBA", (size, size), (120, 150, 255, 0))
        bc.putalpha(bounce)
        layer.alpha_composite(bc)

    return layer.resize((int(radius * 2.9), int(radius * 2.9)), Image.LANCZOS)


img = Image.new("RGB", (S, S), (15, 17, 34))

# 背景垂直渐变：靛蓝 → 深紫
top, bottom = (34, 40, 84), (12, 12, 28)
px = img.load()
for y in range(S):
    t = y / S
    c = lerp(top, bottom, t)
    for x in range(S):
        px[x, y] = c

# 两个柔和光斑
blobs = Image.new("RGB", (S, S), (0, 0, 0))
bd = ImageDraw.Draw(blobs)
bd.ellipse([S * -0.05, S * -0.1, S * 0.5, S * 0.35], fill=(120, 80, 160))
bd.ellipse([S * 0.55, S * 0.6, S * 1.15, S * 1.15], fill=(40, 90, 190))
blobs = blobs.filter(ImageFilter.GaussianBlur(150))
img = Image.blend(img, blobs, 0.45)

# 棋子投影
shadow = Image.new("L", (S, S), 0)
sd = ImageDraw.Draw(shadow)
sd.ellipse([S * 0.14, S * 0.58, S * 0.72, S * 0.86], fill=170)
sd.ellipse([S * 0.5, S * 0.78, S * 0.94, S * 0.98], fill=140)
shadow = shadow.filter(ImageFilter.GaussianBlur(48))
sh = Image.new("RGB", (S, S), (0, 0, 0))
img = Image.composite(sh, img, shadow)

# 棋子（独立图层贴入）
b_layer = stone_layer(S * 0.30, dark=True)
w_layer = stone_layer(S * 0.215, dark=False)
img.paste(b_layer, (int(S * 0.42 - S * 0.30 * 1.45), int(S * 0.42 - S * 0.30 * 1.45)), b_layer)
img.paste(w_layer, (int(S * 0.64 - S * 0.215 * 1.45), int(S * 0.63 - S * 0.215 * 1.45)), w_layer)

os.makedirs(os.path.join(OUT, "AppIcon.appiconset"), exist_ok=True)
img.save(os.path.join(OUT, "AppIcon.appiconset", "icon1024.png"), "PNG")

with open(os.path.join(OUT, "AppIcon.appiconset", "Contents.json"), "w", encoding="utf-8") as f:
    f.write(
        '{\n  "images" : [\n    {\n      "filename" : "icon1024.png",\n'
        '      "idiom" : "universal",\n      "platform" : "ios",\n      "size" : "1024x1024"\n    }\n  ],\n'
        '  "info" : { "author" : "xcode", "version" : 1 }\n}\n'
    )
with open(os.path.join(OUT, "Contents.json"), "w", encoding="utf-8") as f:
    f.write('{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n')
print("ICON_OK")
