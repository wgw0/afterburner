"""
Afterburner: the Discord server icon. The source picture with the AFTERBURNER wordmark across the middle, in the
game icon's style (orange gradient, dark outline, soft shadow). Discord crops icons to a circle, so the word sits
inside the inscribed circle.

  python tools/marketing/discord_icon.py [--src docs/art/marketing/source/discord_icon_source.jpg]
      [--out docs/art/marketing/discord_icon.png]
"""

import argparse

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 1024
FONT = r"C:\Windows\Fonts\ariblk.ttf"
WORD = "AFTERBURNER"
TOP, BOTTOM = (255, 196, 120), (255, 110, 30)  # the gradient down the letters
OUTLINE = (40, 16, 4)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", default="docs/art/marketing/source/discord_icon_source.jpg")
    parser.add_argument("--out", default="docs/art/marketing/discord_icon.png")
    args = parser.parse_args()

    img = Image.open(args.src).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)

    # The largest size that keeps the word inside 84% of the width
    size = 200
    font = ImageFont.truetype(FONT, size)
    while ImageDraw.Draw(img).textlength(WORD, font=font) > SIZE * 0.84:
        size -= 2
        font = ImageFont.truetype(FONT, size)
    stroke = max(int(size * 0.09), 2)
    centre = (SIZE / 2, SIZE / 2)

    # A soft dark band behind the word so it reads over the jet
    band = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(band).rounded_rectangle(
        (SIZE * 0.04, SIZE / 2 - size * 0.62, SIZE * 0.96, SIZE / 2 + size * 0.62), radius=size * 0.3, fill=(8, 14, 30, 120)
    )
    img = Image.alpha_composite(img, band.filter(ImageFilter.GaussianBlur(size * 0.18)))

    # Drop shadow
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text(
        (centre[0] + size * 0.04, centre[1] + size * 0.06), WORD, font=font, anchor="mm", fill=(0, 0, 0, 170), stroke_width=stroke, stroke_fill=(0, 0, 0, 170)
    )
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(size * 0.05)))

    # Outline, then the letters filled with the gradient
    ImageDraw.Draw(img).text(centre, WORD, font=font, anchor="mm", fill=OUTLINE, stroke_width=stroke, stroke_fill=OUTLINE)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).text(centre, WORD, font=font, anchor="mm", fill=255)
    box = mask.getbbox()
    grad = Image.new("RGBA", img.size)
    gd = ImageDraw.Draw(grad)
    for y in range(box[1], box[3] + 1):
        t = (y - box[1]) / max(box[3] - box[1], 1)
        gd.line([(0, y), (SIZE, y)], fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)) + (255,))
    img.paste(grad, (0, 0), mask)

    # A thin highlight along the top of the letters
    hi = Image.new("L", img.size, 0)
    ImageDraw.Draw(hi).text((centre[0], centre[1] - size * 0.025), WORD, font=font, anchor="mm", fill=255)
    hi = Image.composite(hi, Image.new("L", img.size, 0), Image.eval(mask, lambda a: 255 - a))
    img.paste(Image.new("RGBA", img.size, (255, 236, 200, 255)), (0, 0), hi.point(lambda a: a * 0.5))

    img.convert("RGB").save(args.out)
    print("discord icon", args.out, "font", size)


if __name__ == "__main__":
    main()
