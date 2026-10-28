"""
Afterburner: the Ground Roamer's Decals texture (badge and number plates), for the hand-laid UV strip made by
groundroamer_generate.py: u 0..0.4 the front plate (white), 0.4..0.8 the rear plate (yellow), 0.8..1 the oval
GROUND ROAMER badge. Run with Python 3 and Pillow (not Blender):

  python tools/blender/groundroamer_decals.py --out <dir> [--plate "GR 88 MAP"]

Writes GroundRoamer_Decals_{Color,Roughness,Metalness,Normal}.png (1024 x 256).
"""

import argparse
import os

from PIL import Image, ImageDraw, ImageFont

W, H = 1024, 256
FONTS = ["C:/Windows/Fonts/arialbd.ttf", "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
         "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]


def font(size):
    for path in FONTS:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def centred(draw, box, text, fnt, fill):
    x0, y0, x1, y1 = box
    l, t, r, b = draw.textbbox((0, 0), text, font=fnt)
    draw.text(((x0 + x1 - (r - l)) / 2 - l, (y0 + y1 - (b - t)) / 2 - t), text, font=fnt, fill=fill)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--plate", default="GR 88 MAP")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)

    img = Image.new("RGB", (W, H), (30, 30, 30))
    # Each piece is drawn at its real proportions (plates 520 x 111 mm, badge 240 x 35 mm), then fitted to its
    # region of the strip, which the UVs stretch back to shape.
    for (x0, x1), fill in (((0.0, 0.4), (238, 238, 232)), ((0.4, 0.8), (244, 200, 30))):
        plate = Image.new("RGB", (1040, 222), (20, 20, 20))
        d = ImageDraw.Draw(plate)
        d.rectangle((6, 6, 1033, 215), fill=fill)
        centred(d, (0, 0, 1040, 222), args.plate, font(170), (16, 16, 16))
        img.paste(plate.resize((int(W * (x1 - x0)), H), Image.LANCZOS), (int(W * x0), 0))
    badge = Image.new("RGB", (960, 140), (60, 64, 58))
    d = ImageDraw.Draw(badge)
    d.ellipse((8, 8, 951, 131), fill=(222, 222, 214), outline=(40, 40, 40), width=8)
    centred(d, (0, 0, 960, 140), "GROUND ROAMER", font(84), (30, 60, 40))
    img.paste(badge.resize((W - int(W * 0.8), H), Image.LANCZOS), (int(W * 0.8), 0))
    # Drawn as they appear: the UV strip's v runs up the plates, which is the image's top-to-bottom upright
    img.save(os.path.join(args.out, "GroundRoamer_Decals_Color.png"))
    Image.new("L", (W, H), 150).save(os.path.join(args.out, "GroundRoamer_Decals_Roughness.png"))
    Image.new("L", (W, H), 0).save(os.path.join(args.out, "GroundRoamer_Decals_Metalness.png"))
    Image.new("RGB", (W, H), (128, 128, 255)).save(os.path.join(args.out, "GroundRoamer_Decals_Normal.png"))
    print("wrote", os.path.join(args.out, "GroundRoamer_Decals_*.png"))


if __name__ == "__main__":
    main()
