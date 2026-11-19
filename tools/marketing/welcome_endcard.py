"""The trailer's end card: "WELCOME TO AFTERBURNER", animated, as a 1920x1080 MP4 to drop on the end of a video.

The cover art (docs/art/marketing/cover.png), blurred and darkened, drifts in slowly behind; "WELCOME TO" slides
in, the AFTERBURNER wordmark slams down with a flash and a shake, a light sweeps across it, then the tagline and a
PLAY NOW pill fade up and it holds. Same wordmark font as the cover (Impact).

    python tools/marketing/welcome_endcard.py            -> docs/art/marketing/welcome_endcard.mp4
    python tools/marketing/welcome_endcard.py --frames   also writes the frames as PNGs (out/endcard_frames)
"""

import math
import os
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COVER = os.path.join(ROOT, "docs", "art", "marketing", "cover.png")
OUT = os.path.join(ROOT, "docs", "art", "marketing", "welcome_endcard.mp4")
FRAMES_DIR = os.path.join(ROOT, "tools", "marketing", "out", "endcard_frames")
FONT = r"C:\Windows\Fonts\impact.ttf"

W, H = 1920, 1080
FPS = 30
SECONDS = 6.0
ORANGE = (255, 138, 61)
ORANGE_HOT = (255, 196, 90)
WHITE = (240, 244, 250)


def ease_out(t: float) -> float:
    t = min(max(t, 0.0), 1.0)
    return 1 - (1 - t) ** 3


def ease_out_back(t: float) -> float:
    t = min(max(t, 0.0), 1.0)
    c = 1.4
    return 1 + (c + 1) * (t - 1) ** 3 + c * (t - 1) ** 2


def phase(t: float, start: float, length: float) -> float:
    return min(max((t - start) / length, 0.0), 1.0)


def text_layer(text: str, size: int, fill, stroke: int = 0, stroke_fill=None, tracking: int = 0) -> Image.Image:
    """A tight RGBA image of the text (optionally letter-spaced)."""
    font = ImageFont.truetype(FONT, size)
    widths = [font.getlength(ch) for ch in text]
    total = int(sum(widths) + tracking * (len(text) - 1)) + stroke * 2 + 8
    ascent, descent = font.getmetrics()
    img = Image.new("RGBA", (total, ascent + descent + stroke * 2 + 8), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    x = stroke + 4
    for ch, w in zip(text, widths):
        draw.text((x, stroke + 4), ch, font=font, fill=fill, stroke_width=stroke, stroke_fill=stroke_fill)
        x += w + tracking
    return img.crop(img.getbbox())


def wordmark() -> tuple[Image.Image, Image.Image]:
    """AFTERBURNER in a hot-to-orange gradient with a dark outline, and its glow."""
    mask = text_layer("AFTERBURNER", 230, (255, 255, 255, 255), tracking=6)
    w, h = mask.size
    gradient = Image.new("RGBA", (w, h))
    px = gradient.load()
    for y in range(h):
        k = y / max(h - 1, 1)
        r = int(ORANGE_HOT[0] + (ORANGE[0] - ORANGE_HOT[0]) * k)
        g = int(ORANGE_HOT[1] + (ORANGE[1] - ORANGE_HOT[1]) * k)
        b = int(ORANGE_HOT[2] + (ORANGE[2] - ORANGE_HOT[2]) * k)
        for x in range(w):
            px[x, y] = (r, g, b, 255)
    alpha = mask.split()[3]
    pad = 40
    logo = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    outline = Image.new("RGBA", (w, h), (20, 10, 4, 255))
    outline.putalpha(alpha.filter(ImageFilter.MaxFilter(9)))
    logo.alpha_composite(outline, (pad, pad))
    fill = gradient.copy()
    fill.putalpha(alpha)
    logo.alpha_composite(fill, (pad, pad))
    glow = Image.new("RGBA", logo.size, ORANGE + (0,))
    glow_alpha = Image.new("L", logo.size, 0)
    glow_alpha.paste(alpha, (pad, pad))
    glow.putalpha(glow_alpha.filter(ImageFilter.GaussianBlur(28)))
    return logo, glow


def background() -> Image.Image:
    """The cover, blurred and darkened, a little larger than the frame so it can drift."""
    cover = Image.open(COVER).convert("RGB")
    # The cover's own wordmark (top left, over the sky) painted out, or it shows through as a second logo
    # (the sky there is a vertical gradient, so each row is filled from the clean sky just right of it, with
    # soft edges)
    arr = np.array(cover).astype(np.float32)
    rows, cols = int(arr.shape[0] * 0.24), int(arr.shape[1] * 0.62)
    sample = arr[:rows, cols : cols + 40].mean(axis=1)  # one colour per row
    patch = arr.copy()
    patch[:rows, :cols] = sample[:, None, :]
    mask = np.zeros(arr.shape[:2], np.float32)
    mask[:rows, :cols] = 1.0
    mask = cv2.GaussianBlur(mask, (0, 0), 30)[..., None]
    arr = patch * mask + arr * (1 - mask)
    cover = Image.fromarray(arr.clip(0, 255).astype(np.uint8)).resize((int(W * 1.15), int(H * 1.15)), Image.LANCZOS)
    cover = cover.filter(ImageFilter.GaussianBlur(10))
    dark = Image.new("RGB", cover.size, (8, 14, 28))
    cover = Image.blend(cover, dark, 0.55)
    # A vignette towards the edges
    vignette = Image.new("L", cover.size, 0)
    ImageDraw.Draw(vignette).ellipse(
        (-cover.size[0] * 0.15, -cover.size[1] * 0.25, cover.size[0] * 1.15, cover.size[1] * 1.25), fill=255
    )
    vignette = vignette.filter(ImageFilter.GaussianBlur(160))
    black = Image.new("RGB", cover.size, (0, 0, 0))
    return Image.composite(cover, black, vignette)


def paste_scaled(frame: Image.Image, layer: Image.Image, cx: float, cy: float, scale: float, opacity: float):
    if opacity <= 0.003 or scale <= 0.01:
        return
    w, h = max(1, int(layer.width * scale)), max(1, int(layer.height * scale))
    img = layer.resize((w, h), Image.LANCZOS) if (w, h) != layer.size else layer
    if opacity < 1:
        a = img.split()[3].point(lambda v: int(v * opacity))
        img = img.copy()
        img.putalpha(a)
    frame.alpha_composite(img, (int(cx - w / 2), int(cy - h / 2)))


def main():
    write_frames = "--frames" in sys.argv
    if write_frames:
        os.makedirs(FRAMES_DIR, exist_ok=True)
    bg = background()
    logo, glow = wordmark()
    welcome = text_layer("WELCOME TO", 72, WHITE + (255,), tracking=18)
    tagline = text_layer("JET DOGFIGHTS  ·  RANKED DUELS  ·  27 FIGHTER JETS", 44, WHITE + (255,), tracking=4)
    pill_text = text_layer("PLAY NOW", 52, (20, 14, 8, 255), tracking=6)
    pill = Image.new("RGBA", (pill_text.width + 110, pill_text.height + 46), (0, 0, 0, 0))
    ImageDraw.Draw(pill).rounded_rectangle((0, 0, pill.width - 1, pill.height - 1), radius=pill.height // 2, fill=ORANGE + (255,))
    pill.alpha_composite(pill_text, ((pill.width - pill_text.width) // 2, (pill.height - pill_text.height) // 2))

    writer = cv2.VideoWriter(OUT, cv2.VideoWriter_fourcc(*"mp4v"), FPS, (W, H))
    total = int(SECONDS * FPS)
    slam_at = 0.9  # when the wordmark lands
    for i in range(total):
        t = i / FPS
        # Background drift: a slow push in and pan
        drift = t / SECONDS
        bw, bh = bg.size
        zoom = 1.0 + 0.06 * drift
        cw, ch = int(W * (bw / W) / zoom), int(H * (bh / H) / zoom)
        x0 = int((bw - cw) * (0.35 + 0.3 * drift))
        y0 = int((bh - ch) * 0.5)
        frame = bg.crop((x0, y0, x0 + cw, y0 + ch)).resize((W, H), Image.BILINEAR).convert("RGBA")

        # Shake just after the slam
        since = t - slam_at
        shake = 18 * math.exp(-since * 9) * math.sin(since * 70) if since > 0 else 0
        cx, cy = W / 2 + shake, H / 2 - 20 + shake * 0.4

        # "WELCOME TO": slides down and fades in
        p = ease_out(phase(t, 0.25, 0.6))
        paste_scaled(frame, welcome, cx, cy - 175 - 40 * (1 - p), 1.0, p)

        # AFTERBURNER: drops in from big, overshoots and settles; the glow pulses as it lands
        p = phase(t, 0.55, slam_at - 0.55)
        if p > 0:
            scale = 2.6 - 1.6 * ease_out_back(p) if p < 1 else 1.0
            opacity = min(1.0, p * 2.5)
            glow_pulse = 0.55 + 0.45 * math.exp(-max(since, 0) * 2.5) if since > 0 else 0.4 * p
            paste_scaled(frame, glow, cx, cy, scale * 1.02, opacity * glow_pulse)
            paste_scaled(frame, logo, cx, cy, scale, opacity)

        # The light sweeping across the wordmark
        p = phase(t, 1.6, 0.8)
        if 0 < p < 1:
            band = Image.new("L", logo.size, 0)
            bx = int(-200 + (logo.width + 400) * ease_out(p))
            ImageDraw.Draw(band).polygon(
                [(bx, 0), (bx + 90, 0), (bx - 60, logo.height), (bx - 150, logo.height)], fill=170
            )
            band = band.filter(ImageFilter.GaussianBlur(14))
            shine = Image.new("RGBA", logo.size, (255, 255, 255, 0))
            shine.putalpha(Image.fromarray(np.minimum(np.array(band), np.array(logo.split()[3]))))
            paste_scaled(frame, shine, cx, cy, 1.0, 1.0)

        # Tagline and PLAY NOW
        p = ease_out(phase(t, 2.2, 0.6))
        paste_scaled(frame, tagline, cx, cy + 170 + 25 * (1 - p), 1.0, p)
        p = ease_out(phase(t, 2.7, 0.5))
        breathe = 1.0 + 0.03 * math.sin(max(t - 3.2, 0) * 3.2)
        paste_scaled(frame, pill, cx, cy + 285, (0.85 + 0.15 * p) * breathe, p)

        # The white flash as it lands
        if 0 <= since < 0.35:
            flash = Image.new("RGBA", (W, H), (255, 240, 220, int(200 * (1 - since / 0.35) ** 2)))
            frame.alpha_composite(flash)

        rgb = frame.convert("RGB")
        if write_frames:
            rgb.save(os.path.join(FRAMES_DIR, f"frame_{i:04d}.png"))
        writer.write(cv2.cvtColor(np.array(rgb), cv2.COLOR_RGB2BGR))
    writer.release()
    print(f"wrote {OUT} ({total} frames, {SECONDS:.0f} s at {FPS} fps)")


if __name__ == "__main__":
    main()
