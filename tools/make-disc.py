#!/usr/bin/env python3
"""Make an enlarged standalone Bagua disc from the filled mockup.

Input : /tmp/musicfox-player3.jpg.png (916x1717, cyan bars already filled)
Output: tools/bagua-disc.png (RGBA, ~1.5x enlarged)

Recorded geometry (mockup pixels) -- 2026-09-19:
  dial center (460, 796), outer ring R = 416
  scale vs artwork (784x1312): 416/374 = 1.112, offset (24, 138)
  baked buttons: prev (79.6, 783), next (840.4, 783), r = 55.6
  mockup cyan (this one) ......... (33, 230, 240)
  previous cyan (for next fills) .. (53, 224, 255)

Steps: tight square crop -> circular cut (outside transparent) ->
black-out button discs -> redraw ring arcs over the gaps ->
cyan bars to transparent -> 1.5x enlarge.
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = '/tmp/musicfox-player3.jpg.png'
OUT = 'tools/bagua-disc.png'
CX, CY, R = 460, 796, 416
BTN_R = 59
PREV = (79.6, 783.0)
NEXT = (840.4, 783.0)
ENLARGE = 1.5


def main():
    im = Image.open(SRC).convert('RGB')
    a = np.asarray(im).astype(int)
    H, W, _ = a.shape
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]

    # tight square crop around dial
    m = 8
    x0, y0 = int(CX - R - m), int(CY - R - m)
    side = int(2 * (R + m))
    crop = im.crop((x0, y0, x0 + side, y0 + side)).convert('RGBA')
    ca = np.asarray(crop).astype(int)
    cr, cg, cb = ca[:, :, 0], ca[:, :, 1], ca[:, :, 2]
    yy, xx = np.mgrid[0:side, 0:side].astype(float)
    dcx, dcy = side / 2, side / 2

    # ring gold color from the dial ring band (away from buttons/trigrams)
    rr = np.sqrt((xx - dcx) ** 2 + (yy - dcy) ** 2)
    ring = (np.abs(rr - R) <= 3) & (cr > 150) & (cg > 100) & (cb < 150)
    gold = np.array([cr[ring].mean(), cg[ring].mean(), cb[ring].mean()])
    print('ring gold:', gold.round(1), 'px:', int(ring.sum()))

    # alpha: circular cut (keep the full ring line), feather 1.5
    alpha = np.where(rr <= R + 4, 255, 0).astype(np.uint8)
    alpha = np.asarray(Image.fromarray(alpha).filter(
        ImageFilter.GaussianBlur(1.5)))

    # work image
    work = crop.convert('RGB')
    dw = ImageDraw.Draw(work)

    # black-out baked button discs (crop coords)
    for bx, by in (PREV, NEXT):
        lx, ly = bx - x0, by - y0
        dw.ellipse([lx - BTN_R, ly - BTN_R, lx + BTN_R, ly + BTN_R],
                   fill=(0, 0, 0))

    # redraw ring arcs over the blacked gaps
    import math
    for bx, by in (PREV, NEXT):
        lx, ly = bx - x0, by - y0
        ang = math.degrees(math.atan2(ly - dcy, lx - dcx))
        half = math.degrees(math.asin((BTN_R + 4) / math.hypot(lx - dcx, ly - dcy))) + 2.0
        dw.arc([dcx - R, dcy - R, dcx + R, dcy + R],
               start=ang - half, end=ang + half,
               fill=tuple(int(v) for v in gold), width=5)

    # cyan bars -> transparent (feather 1.5)
    wa = np.asarray(work).astype(int)
    wr, wg, wb = wa[:, :, 0], wa[:, :, 1], wa[:, :, 2]
    cyan = (wb > 150) & (wg > 150) & (wr < 120)
    print('cyan px in crop:', int(cyan.sum()))
    holes = np.where(cyan, 0, 255).astype(np.uint8)
    holes = np.asarray(Image.fromarray(holes).filter(
        ImageFilter.GaussianBlur(1.5)))
    alpha = (alpha.astype(int) * holes.astype(int) // 255).astype(np.uint8)

    out = work.convert('RGBA')
    out.putalpha(Image.fromarray(alpha))
    out = out.resize((int(side * ENLARGE),) * 2, Image.LANCZOS)
    out.save(OUT)
    print('saved %s %s' % (OUT, out.size))

    # numeric check: redrawn arc pixels are gold-ish
    chk = np.asarray(out.convert('RGB')).astype(int)
    print('done')


if __name__ == '__main__':
    main()
