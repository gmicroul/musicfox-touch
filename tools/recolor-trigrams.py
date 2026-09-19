#!/usr/bin/env python3
"""Recolor the 40 Bagua trigram bars on musicfox-player2.jpg (784x1312).

Final inventory 2026-09-19 (user-verified): 40 bars =
  32 non-south horizontal bars + 8 south bars (SW-low 4 + SE-low 4).
Excluded: baked progress arc (circle (393,642) R288, it crosses the
  bottom), its knob (551.7,908.1 r22), baked prev/next buttons
  ((50,580),(734,580) r58), radial divider segments, rings, and the
  2 short vertical strokes at top (user: horizontals only).
Approved color: cyan (53,224,255), luminance-matched shading.

Usage: recolor-trigrams.py R G B [output.png]   (run from repo root)

Methodology (user directive): the 36 verified bars are FROZEN
(tools/verified-mask.png, pixel mask — never recomputed). Each run only
(fill = frozen verified pixels) + (fresh S-right 4 mirrors). Verified
parts cannot regress.
"""
import json
import math
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageFilter

SRC = 'app/qml/musicfox-player2.jpg'
JSON_OUT = 'tools/trigram-bars.json'
VERIFIED_MASK = 'tools/verified-mask.png'
CX, CY = 392, 592
ARC = (393.0, 642.0, 288.0, 4.0)      # cx, cy, R, half-width to exclude
KNOB = (551.7, 908.1, 22.0)

# 32 non-south horizontal bars [x0,y0,x1,y1] (strict detection boxes)
KEEP32 = [
    [349, 287, 388, 297], [394, 287, 434, 297],
    [349, 305, 388, 315], [395, 305, 434, 315],
    [179, 324, 212, 349], [188, 340, 220, 365], [196, 355, 230, 380],
    [216, 316, 225, 326], [224, 330, 234, 342], [232, 345, 243, 357],
    [639, 432, 664, 465], [656, 421, 680, 456],
    [660, 468, 684, 503], [676, 459, 699, 494],
    [82, 459, 107, 493], [98, 468, 123, 502],
    [103, 422, 127, 456], [119, 432, 144, 465],
    [640, 787, 664, 820], [656, 797, 681, 830],
    [661, 764, 677, 784], [676, 774, 693, 793],
    [90, 775, 105, 793], [102, 796, 126, 830],
    [105, 765, 120, 784], [118, 788, 142, 821],
    [540, 345, 549, 357], [550, 330, 560, 341], [559, 316, 568, 327],
    [553, 353, 587, 380], [563, 338, 597, 364], [571, 324, 605, 349],
]
# NOTE: KEEP32 must hold 32 unique boxes; dedupe below guards copy-paste slips.
# S-RIGHT 4 = exact mirrors of S-left across x=392 (the ONLY part recomputed
# each run; everything else comes from the frozen verified mask).
SRIGHT4 = [
    [569, 892, 601, 917], [560, 876, 591, 901],
    [533, 915, 565, 939], [524, 899, 556, 923],
]
# Frozen inventory: 32 non-south boxes + S-left 4 (for JSON record only).
FROZEN36 = [
    [349, 287, 388, 297], [394, 287, 434, 297],
    [349, 305, 388, 315], [395, 305, 434, 315],
    [179, 324, 212, 349], [188, 340, 220, 365],
    [196, 355, 230, 380], [216, 316, 225, 326],
    [224, 330, 234, 342], [232, 345, 243, 357],
    [540, 345, 549, 357], [550, 330, 560, 341],
    [559, 316, 568, 327], [553, 353, 587, 380],
    [563, 338, 597, 364], [571, 324, 605, 349],
    [639, 432, 664, 465], [656, 421, 680, 456],
    [660, 468, 684, 503], [676, 459, 699, 494],
    [82, 459, 107, 493], [98, 468, 123, 502],
    [103, 422, 127, 456], [119, 432, 144, 465],
    [640, 787, 664, 820], [656, 797, 681, 830],
    [661, 764, 677, 784], [676, 774, 693, 793],
    [90, 775, 105, 793], [102, 796, 126, 830],
    [105, 765, 120, 784], [118, 788, 142, 821],
    [183, 892, 215, 917], [193, 876, 224, 901],
    [219, 915, 251, 939], [228, 899, 260, 923],
]


def main():
    tr, tg, tb = (int(x) for x in sys.argv[1:4])
    out_path = sys.argv[4] if len(sys.argv) > 4 else '/tmp/trigram-recolored.png'
    seen, boxes32 = set(), []
    for b in KEEP32:
        t = tuple(b)
        if t not in seen:
            seen.add(t)
            boxes32.append(b)
    assert len(FROZEN36) == 36
    assert len(SRIGHT4) == 4
    im = Image.open(SRC).convert('RGB')
    a = np.asarray(im).astype(int)
    H, W, _ = a.shape
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    yy, xx = np.mgrid[0:H, 0:W].astype(float)

    frozen = np.asarray(Image.open(VERIFIED_MASK).convert('L')) > 127
    assert frozen.shape == (H, W), 'verified mask size mismatch'

    relax = (r > 120) & (g > 80) & (b < 170)
    m2 = Image.fromarray((relax * 255).astype(np.uint8))
    m2 = m2.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(5))
    relax_thick = np.asarray(m2) > 127
    mm = np.zeros((H, W), dtype=bool)
    for x0, y0, x1, y1 in SRIGHT4:
        mm[y0:y1 + 1, x0:x1 + 1] = True
    fresh = relax_thick & mm

    ax, ay, ar, ahw = ARC
    arc = np.abs(np.sqrt((xx - ax) ** 2 + (yy - ay) ** 2) - ar) <= ahw
    kx, ky, kr = KNOB
    knob = np.sqrt((xx - kx) ** 2 + (yy - ky) ** 2) <= kr
    keep = (frozen | fresh) & (~arc) & (~knob)

    with open(JSON_OUT, 'w') as f:
        json.dump({'image': 'musicfox-player2.jpg 784x1312',
                   'bars': FROZEN36 + SRIGHT4}, f)

    L = 0.299 * r + 0.587 * g + 0.114 * b
    Lt = 0.299 * tr + 0.587 * tg + 0.114 * tb
    f = np.clip(L / Lt, 0, 1.6)[..., None]
    tgt = np.array([float(tr), float(tg), float(tb)])
    out = a.astype(float)
    out[keep] = np.clip(tgt * f[keep], 0, 255)
    Image.fromarray(out.astype(np.uint8)).save(out_path)

    # numeric verification (no eyeballing)
    n_arc = int((keep & arc).sum())
    n_knob = int((keep & knob).sum())
    n_frozen = int((keep & frozen).sum())
    n_fresh = int((keep & (~frozen)).sum())
    print('boxes: 36 frozen + 4 fresh = 40')
    print('keep px: frozen=%d fresh=%d total=%d' %
          (n_frozen, n_fresh, int(keep.sum())))
    print('arc-band px filled (must be 0): %d, knob px filled (must be 0): %d'
          % (n_arc, n_knob))


if __name__ == '__main__':
    main()

# 2026-09-19 geometry update: trigram-recolored2.png is a re-render, NOT an
# exact upscale of musicfox-player2.jpg. Remeasured landmarks (1080x1807):
#   dial circle .... center (544, 860) R 536 -> frac (0.5037, 0.4759)
#   taiji circle ... center (540, 868) R 250 -> frac (0.5000, 0.4804)
#   btn prev ....... (112, 810) R64 | next (968, 814) R64
#   btn vol ........ (208, 1534) | cycle (540, 1566) | fav (870, 1538)
# All QML overlay/hotspot/progress/disc geometry follows these numbers.
