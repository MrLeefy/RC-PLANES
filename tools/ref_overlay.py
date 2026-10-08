#!/usr/bin/env python3
"""Overlay our orthographic silhouette on a real three-view drawing or photo, to compare proportions.

  tools/ref_overlay.py --ref drawing.png --box x0,y0,x1,y1 --ours id_os.png --view os --out overlay.png [--rot 90|180|270] [--flip]

--box     pixel box of ONE view inside the reference image (tight around the whole aircraft in that view;
          the drawing's propeller disc / pitot tubes count as part of the extent, as they do in our render).
--rot     rotate the crop clockwise first so the nose points where ours does (side view: nose left, plan: nose up,
          front view: upright).  --flip mirrors it horizontally after rotating.
--ours    black-on-white silhouette written by tests/turntable.gd (views os / ot / of).

The reference crop is scaled so its width matches the width of our silhouette (side: overall length, plan and
front: span), centred horizontally, and aligned at the nose (plan) or the bottom (side, front). Our silhouette is
drawn translucent red over the drawing; the printed ratios compare the other dimension, which is where
proportion errors show up.  Prints JSON-ish numbers: our aspect ratio vs the reference's.
"""
import argparse
from PIL import Image, ImageChops


def bbox_dark(img, thresh=128):
    g = img.convert("L").point(lambda v: 255 if v < thresh else 0)
    return g.getbbox(), g


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True)
    ap.add_argument("--box", required=True)
    ap.add_argument("--ours", required=True)
    ap.add_argument("--view", required=True, choices=["os", "ot", "of"])
    ap.add_argument("--out", required=True)
    ap.add_argument("--rot", type=int, default=0)
    ap.add_argument("--flip", action="store_true")
    a = ap.parse_args()

    ref = Image.open(a.ref).convert("RGBA")
    bg = Image.new("RGBA", ref.size, (255, 255, 255, 255))
    ref = Image.alpha_composite(bg, ref).convert("L")
    x0, y0, x1, y1 = [int(v) for v in a.box.split(",")]
    crop = ref.crop((x0, y0, x1, y1))
    if a.rot:
        crop = crop.rotate(-a.rot, expand=True, fillcolor=255)
    if a.flip:
        crop = crop.transpose(Image.FLIP_LEFT_RIGHT)

    ours = Image.open(a.ours).convert("L")
    ob, omask = bbox_dark(ours)
    rb, _ = bbox_dark(crop, 160)
    if ob is None or rb is None:
        raise SystemExit("empty silhouette or empty reference crop")
    ow, oh = ob[2] - ob[0], ob[3] - ob[1]
    rw, rh = rb[2] - rb[0], rb[3] - rb[1]
    s = ow / rw
    crop_s = crop.resize((max(1, int(crop.width * s)), max(1, int(crop.height * s))), Image.LANCZOS)
    rb_s = (rb[0] * s, rb[1] * s, rb[2] * s, rb[3] * s)
    canvas = Image.new("RGB", ours.size, (255, 255, 255))
    # horizontal: centre of the dark extents; vertical: nose edge (plan) or bottom edge (side, front)
    dx = (ob[0] + ob[2]) / 2 - (rb_s[0] + rb_s[2]) / 2
    dy = ob[1] - rb_s[1] if a.view == "ot" else ob[3] - rb_s[3]
    canvas.paste(crop_s.convert("RGB"), (int(dx), int(dy)))
    red = Image.new("RGB", ours.size, (230, 30, 30))
    over = Image.composite(red, canvas, omask.point(lambda v: 110 if v else 0))
    over.save(a.out)
    print("ours  w x h px: %d x %d  (h/w %.3f)" % (ow, oh, oh / ow))
    print("ref   w x h px: %d x %d  (h/w %.3f)" % (rw, rh, rh / rw))
    print("height/width ratio ours/ref: %.3f  (1.00 = same proportions)" % ((oh / ow) / (rh / rw)))


if __name__ == "__main__":
    main()
