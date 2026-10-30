"""
Afterburner: the wing-art decals (Config/Cosmetics "WingArt", SHP-07), painted on top of each wing. Each is
512 x 256 with a transparent background, drawn pointing right for the right wing and mirrored for the left, so
both point outboard. Upload both and put the ids in Config/Cosmetics as Images = { right, left }.

  python tools/cosmetics/wing_art.py [--out tools/cosmetics/out]
"""

import argparse
import math
import os

from PIL import Image, ImageDraw, ImageFont

W, H = 1024, 512  # drawn at twice the size, then halved (smooth edges)
OUTLINE = (18, 20, 26, 255)
WHITE = (245, 245, 240, 255)
RED = (200, 30, 36, 255)
FONT = r"C:\Windows\Fonts\impact.ttf"


def canvas():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def shark():
    """The shark mouth: a red grin with white teeth, open towards the nose and curling up at the back, with an
    eye over the back of the mouth."""
    img, d = canvas()
    n = 100

    def centre(t):  # the line the mouth opens about: curls up at the back (t = 0), level at the front
        return 120 + t * 860, 250 + 120 * t - 70 * t * t

    upper, lower = [], []
    for i in range(n + 1):
        t = i / n
        x, y = centre(t)
        upper.append((x, y - 165 * t ** 1.4))
        lower.append((x, y + 105 * t ** 1.7))
    mouth = upper + lower[::-1]
    d.polygon(mouth, fill=OUTLINE)
    inner = [(x, y + 9) for x, y in upper[4:]] + [(x, y - 9) for x, y in lower[::-1][:-4]]
    d.polygon(inner, fill=RED)
    # Teeth along each lip, pointing into the mouth, bigger towards the front
    for lip, sign in ((upper, 1), (lower, -1)):
        for i in range(22, n, 7):
            x, y = lip[i]
            size = 10 + i * 0.36
            d.polygon([(x - size * 0.55, y + sign * 4), (x + size * 0.55, y + sign * 4),
                       (x + size * 0.1, y + sign * (size * 1.45))], fill=WHITE, outline=OUTLINE)
    # The eye, above the back of the mouth
    d.ellipse((300, 60, 420, 140), fill=WHITE, outline=OUTLINE, width=8)
    d.ellipse((352, 78, 402, 128), fill=OUTLINE)
    return img


def ace():
    """A tilted ace of spades."""
    card = Image.new("RGBA", (300, 420), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle((6, 6, 294, 414), radius=28, fill=WHITE, outline=OUTLINE, width=8)
    # The spade: a heart upside down and a stem
    cx, cy = 150, 200
    d.ellipse((cx - 92, cy - 30, cx + 4, cy + 66), fill=OUTLINE)
    d.ellipse((cx - 4, cy - 30, cx + 92, cy + 66), fill=OUTLINE)
    d.polygon([(cx - 88, cy + 28), (cx + 88, cy + 28), (cx, cy - 120)], fill=OUTLINE)
    d.polygon([(cx, cy + 30), (cx - 40, cy + 120), (cx + 40, cy + 120)], fill=OUTLINE)
    font = ImageFont.truetype(FONT, 70)
    d.text((28, 18), "A", font=font, fill=RED)
    d.text((272, 402), "A", font=font, fill=RED, anchor="rd")
    img, _ = canvas()
    tilted = card.rotate(-14, expand=True, resample=Image.BICUBIC)
    img.alpha_composite(tilted, ((W - tilted.width) // 2, (H - tilted.height) // 2))
    return img


def bolt():
    """A lightning bolt striking forward."""
    img, d = canvas()
    pts = [(60, 250), (430, 120), (400, 225), (760, 90), (700, 230), (980, 210),
           (520, 400), (560, 290), (240, 400), (300, 290)]
    d.polygon(pts, fill=OUTLINE)
    inset = [(x + (8 if x < 500 else -8), y + (8 if y < 250 else -8)) for x, y in pts]
    d.polygon(inset, fill=(255, 205, 40, 255))
    d.line([(150, 255), (420, 170)], fill=(255, 245, 190, 255), width=14)
    return img


def eight():
    """A lucky 8-ball with speed lines behind it."""
    img, d = canvas()
    for i, y in enumerate((170, 256, 342)):
        d.line([(110 + i * 20, y), (430, y)], fill=WHITE, width=18)
        d.line([(110 + i * 20, y), (430, y)], fill=OUTLINE, width=6)
    cx, cy, r = 640, 256, 210
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=OUTLINE)
    d.ellipse((cx - r + 30, cy - r + 30, cx - r + 120, cy - r + 90), fill=(90, 92, 100, 255))
    d.ellipse((cx - 90, cy - 90, cx + 90, cy + 90), fill=WHITE)
    font = ImageFont.truetype(FONT, 150)
    d.text((cx, cy + 4), "8", font=font, fill=OUTLINE, anchor="mm")
    return img


ART = {"WingShark": shark, "WingAce": ace, "WingBolt": bolt, "WingEight": eight}


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(here, "out"))
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name, draw in ART.items():
        right = draw().resize((W // 2, H // 2), Image.LANCZOS)
        right.save(os.path.join(args.out, f"{name}_R.png"))
        right.transpose(Image.FLIP_LEFT_RIGHT).save(os.path.join(args.out, f"{name}_L.png"))
        print("wrote", name)


if __name__ == "__main__":
    main()
