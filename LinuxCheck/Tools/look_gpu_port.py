"""Faithful NumPy port of RawLook/Processing/Look.metal + LookFilter.swift table upload.

`ci_origin_flip=True` reproduces what Core Image does with CIImage(bitmapData:):
bitmap row 0 is the TOP of the image, but CI coordinates have a bottom-left origin,
so the kernel's read at y = r + 0.5 lands on bitmap row (H - 1 - r).
"""
import json, numpy as np

def load_pipeline(path):
    return json.load(open(path))["estimated_creative_pipeline"]

def pack(anchors, curves, width=16, rows=5):
    """Exact port of LookTable.pack (16x5 RGBA float, rows: anchors, master, R, G, B)."""
    px = np.zeros((rows * width, 4), np.float32)
    for i, a in enumerate(anchors):
        px[i] = [a["hue_degrees"], a["hue_delta_degrees"], a["saturation_multiplier"], a["lightness_adjustment"]]
    for r, c in enumerate(curves):
        for i, p in enumerate(c):
            px[(r + 1) * width + i, :2] = p
    return px

def fetch_rows_2d(px, ci_origin_flip):
    """Kernel: row r read via table.sample(transform(float2(i+.5, r+.5))) on a 16x5 bitmap."""
    bitmap = px.reshape(5, 16, 4)  # memory order: row 0 first == top of image
    out = []
    for r in range(5):
        mem_row = (5 - 1 - r) if ci_origin_flip else r
        out.append(bitmap[mem_row])
    return out

def fetch_rows_1d(px):
    """Fixed kernel: 80x1 table, entry r*16+i read at float2(r*16+i+.5, .5); no vertical axis."""
    return [px[r * 16:(r + 1) * 16] for r in range(5)]

def enc(v):
    v = v.astype(np.float32)
    return np.where(v <= 0.0031308, 12.92 * v, 1.055 * np.power(np.maximum(v, 0), 1 / 2.4) - 0.055)

def dec(v):
    return np.where(v <= 0.04045, v / 12.92, np.power((np.maximum(v, 0) + 0.055) / 1.055, 2.4))

def wrap(h):
    v = np.fmod(h, 360.0)  # Metal fmod keeps sign of dividend, like C
    return np.where(v < 0, v + 360, v)

def to_hsl(c):
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    hi = np.maximum(r, np.maximum(g, b)); lo = np.minimum(r, np.minimum(g, b))
    d = hi - lo; l = (hi + lo) / 2
    with np.errstate(all="ignore"):
        h = np.where(hi == r, (g - b) / d, np.where(hi == g, (b - r) / d + 2, (r - g) / d + 4))
        s = d / (1 - np.abs(2 * l - 1))
    zero = d == 0
    return np.stack([np.where(zero, 0, wrap(h * 60)), np.where(zero, 0, s), l], -1)

def to_rgb(hsl):
    h = wrap(hsl[..., 0]) / 60; s = hsl[..., 1]; l = hsl[..., 2]
    c = (1 - np.abs(2 * l - 1)) * s
    x = c * (1 - np.abs(np.fmod(h, 2.0) - 1)); z = np.zeros_like(c); m = l - c / 2
    conds = [h < 1, h < 2, h < 3, h < 4, h < 5]
    R = np.select(conds, [c, x, z, z, x], c); G = np.select(conds, [x, c, c, x, z], z); B = np.select(conds, [z, z, x, c, c], x)
    return np.stack([R, G, B], -1) + m[..., None]

def curve(x, pts, count):
    """Port of Metal curve(): linear search over `count` float4 points."""
    out = np.full_like(x, np.nan); done = np.zeros(x.shape, bool)
    a = pts[0]
    m = x <= a[0]; out[m] = a[1]; done |= m
    for i in range(1, count):
        b = pts[i]
        m = (~done) & (x <= b[0])
        with np.errstate(all="ignore"):
            out[m] = a[1] + ((x[m] - a[0]) / (b[0] - a[0])) * (b[1] - a[1])
        done |= m; a = b
    out[~done] = a[1]
    return out

def sector(color, anchors, count):
    hsl = to_hsl(color)
    hue = hsl[..., 0].copy()
    A = np.broadcast_to(anchors[count - 1], hue.shape + (4,)).copy()
    B = np.broadcast_to(anchors[0], hue.shape + (4,)).copy()
    left = np.full(hue.shape, anchors[count - 1][0]); right = np.full(hue.shape, anchors[0][0] + 360)
    hue = np.where(hue < anchors[0][0], hue + 360, hue)
    found = np.zeros(hue.shape, bool)
    for i in range(1, count):
        u, v = anchors[i - 1], anchors[i]
        m = (~found) & (hue >= u[0]) & (hue < v[0])
        A[m] = u; B[m] = v; left[m] = u[0]; right[m] = v[0]; found |= m
    with np.errstate(all="ignore"):
        par = A[..., 1:] + ((hue - left) / (right - left))[..., None] * (B[..., 1:] - A[..., 1:])
    t = np.clip((hsl[..., 1] - 0.03) / 0.15, 0, 1); w = t * t * (3 - 2 * t)
    delta = w * par[..., 2]
    h = wrap(hsl[..., 0] + w * par[..., 0])
    s = np.clip(hsl[..., 1] * (1 + w * (par[..., 1] - 1)), 0, 1)
    L = hsl[..., 2]
    L = np.clip(L + delta * np.where(delta >= 0, 1 - L, L), 0, 1)
    return to_rgb(np.stack([h, s, L], -1))

def kernel(linear_rgb, rows, counts, flags, options):
    """linear_rgb: straight (alpha=1) linear-sRGB pixels, as Core Image's working space hands them in."""
    anchors, master, red, green, blue = rows
    original = np.clip(enc(linear_rgb), 0, 1)
    color = original
    if flags[0] > 0: color = sector(color, anchors, int(options[0]))
    if flags[1] > 0: color = np.stack([curve(color[..., k], master, int(counts[0])) for k in range(3)], -1)
    if flags[2] > 0:
        color = np.stack([curve(color[..., 0], red, int(counts[1])), curve(color[..., 1], green, int(counts[2])),
                          curve(color[..., 2], blue, int(counts[3]))], -1)
    if flags[3] > 0:
        hsl = to_hsl(color); hsl[..., 1] = np.clip(hsl[..., 1] * options[1], 0, 1); color = to_rgb(hsl)
    if options[3] > 0:
        s = np.clip(options[2], 0, 1)
        color = enc(dec(original) * (1 - s) + dec(color) * s)
    color = np.clip(np.nan_to_num(color), 0, 1)
    return dec(color)

def args_for(p, strength=1.0):
    curves = [p["master_rgb_tone_curve"]["points"], p["per_channel_tone_curves"]["red"],
              p["per_channel_tone_curves"]["green"], p["per_channel_tone_curves"]["blue"]]
    anchors = p["hsl_sector_adjustments"]["anchors"]; order = p["execution_order"]
    counts = [len(c) for c in curves]
    flags = [int(name in order and p[name]["enabled"]) for name in (
        "hsl_sector_adjustments", "master_rgb_tone_curve", "per_channel_tone_curves", "global_hsl_saturation")]
    options = [len(anchors), p["global_hsl_saturation"]["multiplier"], strength, 1 if "strength_blend_linear_srgb" in order else 0]
    return pack(anchors, curves), counts, flags, options

def apply_srgb8(img_u8, p, mode, strength=1.0):
    px, counts, flags, options = args_for(p, strength)
    rows = fetch_rows_1d(px) if mode == "fixed" else fetch_rows_2d(px, ci_origin_flip=(mode == "shipped_ci"))
    lin = dec(img_u8.astype(np.float32) / 255)
    return np.clip(enc(kernel(lin, rows, counts, flags, options)), 0, 1)
