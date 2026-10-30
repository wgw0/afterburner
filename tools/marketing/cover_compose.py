"""
Afterburner: puts the wordmark (the icon's, from icon_compose.py) on the cover render (cover_render.py), in the
open sky at the top right, and writes the 1920 x 1080 cover.

  python tools/marketing/cover_compose.py <render.png> [--out docs/art/marketing/cover.png]
"""

import argparse
import os

from PIL import Image, ImageDraw

from icon_compose import wordmark

W, H = 1920, 1080


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))
    parser = argparse.ArgumentParser()
    parser.add_argument("render")
    parser.add_argument("--out", default=os.path.join(root, "docs", "art", "marketing", "cover.png"))
    args = parser.parse_args()
    img = Image.open(args.render).convert("RGBA").resize((W, H), Image.LANCZOS)
    # A soft darkening in the top right so the wordmark sits on calm sky
    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for y in range(360):
        sd.line([(0, y), (W, y)], fill=(6, 20, 50, round(70 * (1 - y / 360))))
    img = Image.alpha_composite(img, shade)
    mark = wordmark("AFTERBURNER", 860)
    img.alpha_composite(mark, (W - mark.width - 60, 50))
    img.convert("RGB").save(args.out)
    print("cover written to", args.out, img.size)


if __name__ == "__main__":
    main()
