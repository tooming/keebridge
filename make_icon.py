#!/usr/bin/env python3
"""Generate KeeBridge's app icon: app.icns + the Xcode AppIcon.appiconset.

Same pure-stdlib SDF rasterizer technique as garagediag/OpenDiag's
make_icons.py/build_app.py (same bg gradient + ring color + accent blue,
for a consistent look across the personal-app icon family) — a bridge
arch over a keyhole, rather than OpenDiag's gauge dial.

Regenerate and commit after changing the icon:
    python3 make_icon.py
"""
import math
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))


# ---------------------------------------------------------------------------
# Tiny stdlib PNG writer + anti-aliased SDF rasterizer (ported from
# garagediag/build_app.py, same palette, new motif)
# ---------------------------------------------------------------------------
def _write_png(path, w, h, rgba):
    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data
                + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)  # 8-bit RGBA
    stride = w * 4
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type 0
        raw.extend(rgba[y * stride:(y + 1) * stride])
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def _lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _cov(sd):
    """Anti-aliased coverage for a signed distance (inside = sd<0)."""
    return min(1.0, max(0.0, 0.5 - sd))


def _over(dst, rgb, a):
    """Alpha-composite rgb (coverage a) over dst (opaque)."""
    if a <= 0:
        return dst
    return tuple(round(rgb[i] * a + dst[i] * (1 - a)) for i in range(3))


def _sd_wedge(px, py, x0, y0, x1, y1, r0, r1):
    """Signed distance to a segment whose radius tapers linearly from r0
    (at the start) to r1 (at the end) — a cone/wedge shape. Used for the
    keyhole's blade."""
    vx, vy = x1 - x0, y1 - y0
    denom = vx * vx + vy * vy
    t = 0.0 if denom == 0 else max(0.0, min(1.0, ((px - x0) * vx + (py - y0) * vy) / denom))
    rad = r0 + (r1 - r0) * t
    seg_d = math.hypot(px - (x0 + t * vx), py - (y0 + t * vy))
    return seg_d - rad


def render_icon(path, S=1024):
    top, bot = (17, 38, 61), (9, 20, 34)      # bg gradient — same as OpenDiag
    ring_col = (214, 228, 242)                 # arch color — same as OpenDiag
    accent = (74, 163, 255)                    # keyhole color — same accent blue
    cx, cy = S / 2, S * 0.53

    # rounded-square background (identical params to OpenDiag, for a
    # matching icon family look)
    half = S * 0.46
    corner = S * 0.22

    # bridge arch: a ring with a wide gap at the bottom, so only the top
    # dome + two short "legs" remain — reads as an arch/bridge silhouette
    Rarch, arch_thick = S * 0.34, S * 0.05
    arch_gap_deg = 150  # degrees of the circle left open at the bottom

    # keyhole: circular bow + tapered wedge blade, centered inside the arch
    kx, ky = cx, cy + S * 0.02
    bow_r = S * 0.085
    wedge_top_r = S * 0.065
    wedge_y0 = ky + bow_r * 0.25
    wedge_y1 = ky + S * 0.20

    buf = bytearray(S * S * 4)
    for y in range(S):
        for x in range(S):
            px, py = x + 0.5, y + 0.5

            # background rounded rect (SDF)
            dx, dy = abs(px - S / 2) - (half - corner), abs(py - S / 2) - (half - corner)
            sd_bg = (math.hypot(max(dx, 0), max(dy, 0))
                     + min(max(dx, dy), 0) - corner)
            bg_a = _cov(sd_bg)
            if bg_a <= 0:
                continue
            col = _lerp(top, bot, py / S)

            # arch (annulus masked to the top ~210° of the circle)
            d = math.hypot(px - cx, py - cy)
            sd_arch = abs(d - Rarch) - arch_thick
            ang = math.degrees(math.atan2(py - cy, px - cx)) % 360
            in_gap = abs(((ang - 90 + 180) % 360) - 180) < (arch_gap_deg / 2)
            if not in_gap:
                col = _over(col, ring_col, _cov(sd_arch))

            # keyhole: bow (circle) ∪ wedge (tapered blade)
            sd_bow = math.hypot(px - kx, py - ky) - bow_r
            sd_wedge = _sd_wedge(px, py, kx, wedge_y0, kx, wedge_y1, wedge_top_r, 0)
            sd_key = min(sd_bow, sd_wedge)
            col = _over(col, accent, _cov(sd_key))

            i = (y * S + x) * 4
            buf[i:i + 4] = bytes((col[0], col[1], col[2], round(bg_a * 255)))
    _write_png(path, S, S, buf)


# ---------------------------------------------------------------------------
# macOS .icns (for reference/Finder use outside Xcode)
# ---------------------------------------------------------------------------
def build_icns(dest):
    base = os.path.join(HERE, "_iconbase.png")
    iconset = os.path.join(HERE, "_app.iconset")
    print("  rendering icon...")
    render_icon(base, 1024)
    if os.path.isdir(iconset):
        shutil.rmtree(iconset)
    os.makedirs(iconset)
    sizes = [(16, ""), (16, "@2x"), (32, ""), (32, "@2x"), (128, ""),
              (128, "@2x"), (256, ""), (256, "@2x"), (512, ""), (512, "@2x")]
    for base_sz, suffix in sizes:
        px = base_sz * (2 if suffix else 1)
        out = os.path.join(iconset, f"icon_{base_sz}x{base_sz}{suffix}.png")
        subprocess.run(["sips", "-z", str(px), str(px), base, "--out", out],
                        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", dest], check=True)
    shutil.rmtree(iconset)
    os.remove(base)


# ---------------------------------------------------------------------------
# Xcode asset catalog (AppIcon.appiconset) — what the actual app target uses
# ---------------------------------------------------------------------------
APPICONSET_IMAGES = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

CONTENTS_JSON = {
    "images": [
        {
            "filename": f"icon_{sz}x{sz}{'@2x' if scale == 2 else ''}.png",
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{sz}x{sz}",
        }
        for sz, scale in APPICONSET_IMAGES
    ],
    "info": {"author": "xcode", "version": 1},
}


def build_appiconset(dest_dir):
    import json

    base = os.path.join(HERE, "_iconbase_xc.png")
    render_icon(base, 1024)

    if os.path.isdir(dest_dir):
        shutil.rmtree(dest_dir)
    os.makedirs(dest_dir)

    for sz, scale in APPICONSET_IMAGES:
        px = sz * scale
        out = os.path.join(dest_dir, f"icon_{sz}x{sz}{'@2x' if scale == 2 else ''}.png")
        subprocess.run(["sips", "-z", str(px), str(px), base, "--out", out],
                        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    with open(os.path.join(dest_dir, "Contents.json"), "w") as f:
        json.dump(CONTENTS_JSON, f, indent=2)

    os.remove(base)


def main():
    if sys.platform != "darwin":
        sys.exit("This needs sips/iconutil (macOS only).")

    build_icns(os.path.join(HERE, "app.icns"))
    print("  wrote app.icns")

    appiconset = os.path.join(HERE, "KeeBridge", "Assets.xcassets", "AppIcon.appiconset")
    build_appiconset(appiconset)
    print(f"  wrote {appiconset}")


if __name__ == "__main__":
    main()
