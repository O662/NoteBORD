"""Renders pen strokes the way CROHME's images look (white strokes on black,
binary), to be ported to Dart as is."""
import math
import re
import xml.etree.ElementTree as ET

import numpy as np


def read_inkml(path):
    ns = {'i': 'http://www.w3.org/2003/InkML'}
    root = ET.parse(path).getroot()
    label = None
    for a in root.findall('i:annotation', ns):
        if a.get('type') == 'normalizedLabel':
            label = a.text
        if label is None and a.get('type') == 'label':
            label = a.text
    strokes = []
    for tr in root.findall('i:trace', ns):
        pts = []
        for p in tr.text.strip().split(','):
            v = p.split()
            pts.append((float(v[0]), float(v[1])))
        strokes.append(pts)
    return label, strokes


def writing_size(strokes):
    """The size of the writing: the median height of strokes that aren't
    flat (minus signs, fraction bars and dots don't count)."""
    hs = []
    for s in strokes:
        xs = [p[0] for p in s]
        ys = [p[1] for p in s]
        w, h = max(xs) - min(xs), max(ys) - min(ys)
        if h >= 0.5 * w and h > 0:
            hs.append(h)
    if not hs:
        hs = [max(max(p[1] for p in s) - min(p[1] for p in s), max(p[0] for p in s) - min(p[0] for p in s)) for s in strokes]
    hs.sort()
    m = hs[len(hs) // 2] if hs else 1.0
    return max(m, 1e-3)


def render(strokes, symbol_px=30.0, line_px=3.0, margin=4):
    """-> float32 array [H, W] in [0, 1], white ink (1) on black (0)."""
    size = writing_size(strokes)
    k = symbol_px / size
    xs = [p[0] for s in strokes for p in s]
    ys = [p[1] for s in strokes for p in s]
    x0, y0 = min(xs), min(ys)
    w = (max(xs) - x0) * k
    h = (max(ys) - y0) * k
    # CoMER's limits: at most 256 high and 1024 wide.
    fit = min(1.0, (256 - 2 * margin - line_px) / max(h, 1e-6), (1024 - 2 * margin - line_px) / max(w, 1e-6))
    k *= fit
    r = line_px / 2
    off = margin + r
    W = int(math.ceil((max(xs) - x0) * k + 2 * off))
    H = int(math.ceil((max(ys) - y0) * k + 2 * off))
    W, H = max(W, 16), max(H, 16)
    img = np.zeros((H, W), np.float32)
    for s in strokes:
        pts = [((p[0] - x0) * k + off, (p[1] - y0) * k + off) for p in s]
        if len(pts) == 1:
            pts = pts * 2
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            _segment(img, ax, ay, bx, by, r)
    return img


def _segment(img, ax, ay, bx, by, r):
    """Pixels whose centre is within r of the segment become 1."""
    H, W = img.shape
    x_lo = max(0, int(math.floor(min(ax, bx) - r)))
    x_hi = min(W - 1, int(math.ceil(max(ax, bx) + r)))
    y_lo = max(0, int(math.floor(min(ay, by) - r)))
    y_hi = min(H - 1, int(math.ceil(max(ay, by) + r)))
    dx, dy = bx - ax, by - ay
    ll = dx * dx + dy * dy
    yy, xx = np.mgrid[y_lo:y_hi + 1, x_lo:x_hi + 1]
    px, py = xx + 0.5, yy + 0.5
    if ll == 0:
        t = np.zeros_like(px)
    else:
        t = np.clip(((px - ax) * dx + (py - ay) * dy) / ll, 0, 1)
    qx, qy = ax + t * dx - px, ay + t * dy - py
    hit = qx * qx + qy * qy <= r * r
    img[y_lo:y_hi + 1, x_lo:x_hi + 1][hit] = 1.0


_CMD = re.compile(r'\\[A-Za-z]+|\\.|[^\s]')


def tokens(latex):
    return _CMD.findall(latex)


def norm(latex_tokens):
    """For comparing labels from different datasets."""
    out = []
    for t in latex_tokens:
        if t in ('\\log', '\\sin', '\\cos', '\\tan', '\\lim', '\\ln', '\\exp'):
            out.extend(list(t[1:]))
        elif t == '\\limits':
            continue
        else:
            out.append(t)
    return ''.join(out)
