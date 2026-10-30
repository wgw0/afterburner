"""
Afterburner: puts the wordmark on the icon render (tools/marketing/icon_render.py) and writes the 512 x 512
experience icon. The wordmark matches the thumbnail's: heavy capitals, cream at the top warming to orange,
with a dark outline and shadow so it reads at the small sizes Roblox shows icons at.

  python tools/marketing/icon_compose.py <render.png> [--out docs/art/marketing/icon.png]
"""

import argparse
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 512
FONT = r"C:\Windows\Fonts\impact.ttf"
TOP, BOTTOM = (255, 244, 222), (255, 128, 48)  # the gradient down the letters
OUTLINE = (10, 22, 46)


def wordmark(text, width):
    """The wordmark as an RGBA image `width` px wide (outline and shadow included)."""
    size = 200
    font = ImageFont.truetype(FONT, size)
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    while probe.textlength(text, font=font) > width * 0.92 and size > 20:
        size -= 2
        font = ImageFont.truetype(FONT, size)
    l, t, r, b = probe.textbbox((0, 0), text, font=font)
    w, h = r - l, b - t
    pad = 16
    canvas = (w + pad * 2, h + pad * 2)
    mask = Image.new("L", canvas, 0)
    ImageDraw.Draw(mask).text((pad - l, pad - t), text, font=font, fill=255)
    stroke = Image.new("L", canvas, 0)
    ImageDraw.Draw(stroke).text((pad - l, pad - t), text, font=font, fill=255, stroke_width=5,
                                stroke_fill=255)
    gradient = Image.new("RGB", canvas)
    gd = ImageDraw.Draw(gradient)
    for y in range(canvas[1]):
        k = min(max((y - pad) / max(h, 1), 0), 1)
        gd.line([(0, y), (canvas[0], y)], fill=tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * k) for i in range(3)))
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    shadow = Image.new("RGBA", canvas, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 170), (0, 0), stroke.filter(ImageFilter.GaussianBlur(6)))
    out = Image.alpha_composite(out, shadow.transform(canvas, Image.AFFINE, (1, 0, -3, 0, 1, -5)))
    outline = Image.new("RGBA", canvas, OUTLINE + (255,))
    out.paste(outline, (0, 0), stroke)
    out.paste(gradient, (0, 0), mask)
    return out


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))
    parser = argparse.ArgumentParser()
    parser.add_argument("render")
    parser.add_argument("--out", default=os.path.join(root, "docs", "art", "marketing", "icon.png"))
    args = parser.parse_args()
    img = Image.open(args.render).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    # A soft darkening at the top so the wordmark sits on calm sky
    shade = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for y in range(140):
        sd.line([(0, y), (SIZE, y)], fill=(6, 20, 50, round(90 * (1 - y / 140))))
    img = Image.alpha_composite(img, shade)
    mark = wordmark("AFTERBURNER", SIZE)
    img.alpha_composite(mark, ((SIZE - mark.width) // 2, 18))
    img.convert("RGB").save(args.out)
    print("icon written to", args.out, img.size)


if __name__ == "__main__":
    main()
