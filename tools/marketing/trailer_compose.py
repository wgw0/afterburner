"""
Afterburner: finishes the trailer frames (trailer_render.py): fades up from black, brings the wordmark in over
the last shot, and has Blender encode the MP4 (trailer_encode.py).

  python tools/marketing/trailer_compose.py <frames dir> [--out docs/art/marketing/trailer.mp4] [--fps 30]
"""

import argparse
import glob
import os
import subprocess

from PIL import Image, ImageDraw

from icon_compose import wordmark

BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
FADE_UP = 0.5  # seconds from black at the start
MARK_FROM, MARK_TO = 11.6, 12.6  # the wordmark fades in over this, then holds


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))
    parser = argparse.ArgumentParser()
    parser.add_argument("frames")
    parser.add_argument("--out", default=os.path.join(root, "docs", "art", "marketing", "trailer.mp4"))
    parser.add_argument("--fps", type=int, default=30)
    args = parser.parse_args()
    files = sorted(glob.glob(os.path.join(args.frames, "frame_*.png")))
    done = os.path.join(args.frames, "final")
    os.makedirs(done, exist_ok=True)
    mark = None
    for i, f in enumerate(files):
        t = i / args.fps
        img = Image.open(f).convert("RGBA")
        w, h = img.size
        if mark is None:
            mark = wordmark("AFTERBURNER", round(w * 0.55))
        k = min(max((t - MARK_FROM) / (MARK_TO - MARK_FROM), 0), 1)
        if k > 0:
            shade = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            sd = ImageDraw.Draw(shade)
            band = round(h * 0.42)
            for y in range(band):
                sd.line([(0, y), (w, y)], fill=(6, 20, 50, round(80 * k * (1 - y / band))))
            img = Image.alpha_composite(img, shade)
            faded = mark.copy()
            faded.putalpha(faded.getchannel("A").point(lambda a: round(a * k)))
            img.alpha_composite(faded, ((w - mark.width) // 2, round(h * 0.08)))
        if t < FADE_UP:
            black = Image.new("RGBA", (w, h), (0, 0, 0, round(255 * (1 - t / FADE_UP))))
            img = Image.alpha_composite(img, black)
        img.convert("RGB").save(os.path.join(done, f"frame_{i + 1:04d}.png"))
    print("composed", len(files), "frames")
    subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.join(here, "trailer_encode.py"), "--",
                    done, args.out, str(args.fps)], check=True)


if __name__ == "__main__":
    main()
