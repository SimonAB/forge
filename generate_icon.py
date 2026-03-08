#!/usr/bin/env python3
"""Generate the Forge app icon — a glowing anvil in a forge with embers."""

import math
import subprocess
import os
import shutil
from PIL import Image, ImageDraw, ImageFilter

ICON_DIR = "/tmp/ForgeIcon.iconset"
ICNS_OUT = "/Applications/Forge.app/Contents/Resources/AppIcon.icns"


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_color(c1, c2, t):
    return tuple(int(lerp(c1[i], c2[i], t)) for i in range(len(c1)))


def draw_icon(size):
    """Render the Forge icon at the given pixel size."""
    s = size
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # --- Background: deep forge gradient (dark at top, warm glow at bottom) ---
    bg = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)
    for y in range(s):
        t = y / s
        r = int(lerp(18, 55, t))
        g = int(lerp(14, 22, t))
        b = int(lerp(22, 18, t))
        bg_draw.line([(0, y), (s - 1, y)], fill=(r, g, b, 255))

    mask = Image.new("L", (s, s), 255)  # Full rect, no rounded outline
    bg.putalpha(mask)
    img = Image.alpha_composite(img, bg)

    # --- Radial fire glow behind the anvil ---
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    gcx, gcy = s * 0.50, s * 0.52
    max_r = s * 0.48
    for i in range(int(max_r), 0, -1):
        t = i / max_r
        alpha = int(60 * (1 - t) ** 2.5)
        r = int(lerp(255, 180, t))
        g = int(lerp(120, 40, t))
        b = int(lerp(20, 5, t))
        glow_draw.ellipse(
            [gcx - i, gcy - i * 0.7, gcx + i, gcy + i * 0.7],
            fill=(r, g, b, alpha),
        )
    glow.putalpha(Image.composite(glow.split()[3], Image.new("L", (s, s), 0), mask))
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)

    cx, cy = s / 2, s / 2

    # --- Anvil ---
    # Darker steel palette with hot-metal highlights
    steel_dark = (55, 52, 58)
    steel_mid = (85, 80, 88)
    steel_light = (120, 115, 125)
    steel_highlight = (160, 155, 170)
    hot_edge = (255, 140, 40)

    # Proportions
    face_w = s * 0.50
    face_h = s * 0.055
    body_top = cy + s * 0.04
    body_h = s * 0.14
    waist_w = s * 0.26
    base_w = s * 0.56
    base_h = s * 0.055
    horn_w = s * 0.20
    horn_tip_y = body_top + face_h * 0.3

    face_top = body_top
    face_bot = face_top + face_h

    # Face (top plate)
    face_pts = [
        (cx - face_w / 2, face_top),
        (cx + face_w / 2, face_top),
        (cx + face_w / 2, face_bot),
        (cx - face_w / 2, face_bot),
    ]
    draw.polygon(face_pts, fill=steel_mid)

    # Face top highlight
    hl = face_h * 0.35
    draw.polygon([
        (cx - face_w / 2 + s * 0.02, face_top),
        (cx + face_w / 2 - s * 0.02, face_top),
        (cx + face_w / 2 - s * 0.02, face_top + hl),
        (cx - face_w / 2 + s * 0.02, face_top + hl),
    ], fill=steel_light)

    # Hot glow line on the striking surface
    glow_h = max(1, int(s * 0.006))
    draw.rectangle(
        [cx - face_w / 2 + s * 0.04, face_top + hl,
         cx + face_w / 2 - s * 0.04, face_top + hl + glow_h],
        fill=hot_edge,
    )

    # Horn (left, pointed)
    horn_pts = [
        (cx - face_w / 2, face_top),
        (cx - face_w / 2 - horn_w, horn_tip_y),
        (cx - face_w / 2, face_bot),
    ]
    draw.polygon(horn_pts, fill=steel_mid)
    # Horn highlight
    horn_hl = [
        (cx - face_w / 2, face_top),
        (cx - face_w / 2 - horn_w * 0.7, horn_tip_y - face_h * 0.1),
        (cx - face_w / 2, face_top + face_h * 0.4),
    ]
    draw.polygon(horn_hl, fill=steel_light)

    # Heel (right, small step)
    heel_w = s * 0.06
    heel_h = s * 0.03
    draw.polygon([
        (cx + face_w / 2, face_top),
        (cx + face_w / 2 + heel_w, face_top),
        (cx + face_w / 2 + heel_w, face_top + heel_h),
        (cx + face_w / 2, face_bot),
    ], fill=steel_dark)

    # Body (tapered waist)
    body_bot = face_bot + body_h
    body_pts = [
        (cx - face_w / 2, face_bot),
        (cx + face_w / 2, face_bot),
        (cx + waist_w / 2, body_bot),
        (cx - waist_w / 2, body_bot),
    ]
    draw.polygon(body_pts, fill=steel_dark)
    # Subtle body highlight (left edge catches light)
    edge_pts = [
        (cx - face_w / 2, face_bot),
        (cx - face_w / 2 + s * 0.03, face_bot),
        (cx - waist_w / 2 + s * 0.03, body_bot),
        (cx - waist_w / 2, body_bot),
    ]
    draw.polygon(edge_pts, fill=steel_mid)

    # Base (feet)
    base_top = body_bot
    base_bot = base_top + base_h
    draw.polygon([
        (cx - base_w / 2, base_top),
        (cx + base_w / 2, base_top),
        (cx + base_w / 2, base_bot),
        (cx - base_w / 2, base_bot),
    ], fill=steel_dark)
    # Base highlight strip
    draw.polygon([
        (cx - base_w / 2, base_top),
        (cx + base_w / 2, base_top),
        (cx + base_w / 2, base_top + base_h * 0.3),
        (cx - base_w / 2, base_top + base_h * 0.3),
    ], fill=steel_mid)

    # --- Glowing hot metal piece on anvil ---
    piece_w = s * 0.14
    piece_h = s * 0.025
    px1 = cx - piece_w / 2 + s * 0.02
    py1 = face_top - piece_h
    # Outer glow
    glow2 = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    g2d = ImageDraw.Draw(glow2)
    for expand in range(int(s * 0.04), 0, -1):
        alpha = int(40 * (1 - expand / (s * 0.04)))
        g2d.rounded_rectangle(
            [px1 - expand, py1 - expand, px1 + piece_w + expand, py1 + piece_h + expand],
            radius=max(1, int(s * 0.01)),
            fill=(255, 100, 10, alpha),
        )
    glow2.putalpha(Image.composite(glow2.split()[3], Image.new("L", (s, s), 0), mask))
    img = Image.alpha_composite(img, glow2)
    draw = ImageDraw.Draw(img)
    # The piece itself — white-hot centre fading to orange
    draw.rounded_rectangle(
        [px1, py1, px1 + piece_w, py1 + piece_h],
        radius=max(1, int(s * 0.008)),
        fill=(255, 200, 80),
    )
    # White-hot core
    core_inset = s * 0.015
    draw.rounded_rectangle(
        [px1 + core_inset, py1 + piece_h * 0.15,
         px1 + piece_w - core_inset, py1 + piece_h * 0.85],
        radius=max(1, int(s * 0.004)),
        fill=(255, 245, 200),
    )

    # --- Hammer ---
    handle_col = (130, 85, 50)
    handle_light = (165, 115, 70)
    head_steel = (150, 148, 155)
    head_light = (200, 198, 205)

    # Handle: grip at upper-left, striking end at anvil (head at anvil end)
    hx1 = cx - s * 0.30
    hy1 = cy - s * 0.32
    hx2 = cx + s * 0.04
    hy2 = face_top - s * 0.05
    angle = math.atan2(hy2 - hy1, hx2 - hx1)
    perp = angle + math.pi / 2
    thick = max(2, s * 0.028)
    dx = math.cos(perp) * thick
    dy = math.sin(perp) * thick

    # Handle shadow
    shadow_off = max(1, s * 0.006)
    handle_shadow = [
        (hx1 - dx + shadow_off, hy1 - dy + shadow_off),
        (hx1 + dx + shadow_off, hy1 + dy + shadow_off),
        (hx2 + dx + shadow_off, hy2 + dy + shadow_off),
        (hx2 - dx + shadow_off, hy2 - dy + shadow_off),
    ]
    draw.polygon(handle_shadow, fill=(0, 0, 0, 60))

    # Handle body
    handle_poly = [
        (hx1 - dx, hy1 - dy), (hx1 + dx, hy1 + dy),
        (hx2 + dx, hy2 + dy), (hx2 - dx, hy2 - dy),
    ]
    draw.polygon(handle_poly, fill=handle_col)
    # Light edge
    light_thick = thick * 0.4
    ldx = math.cos(perp) * light_thick
    ldy = math.sin(perp) * light_thick
    draw.polygon([
        (hx1 - dx, hy1 - dy), (hx1 - dx + ldx, hy1 - dy + ldy),
        (hx2 - dx + ldx, hy2 - dy + ldy), (hx2 - dx, hy2 - dy),
    ], fill=handle_light)

    # Hammer head at striking end (anvil side)
    head_len = s * 0.13
    head_w = s * 0.058
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    cos_p, sin_p = math.cos(perp), math.sin(perp)
    hcx, hcy = hx2, hy2

    def offset(bx, by, along, across):
        return (bx + cos_p * along + cos_a * across,
                by + sin_p * along + sin_a * across)

    # Head extends back toward grip (negative along)
    head_pts = [
        offset(hcx, hcy, -head_len / 2, -head_w / 2),
        offset(hcx, hcy, head_len / 2, -head_w / 2),
        offset(hcx, hcy, head_len / 2, head_w / 2),
        offset(hcx, hcy, -head_len / 2, head_w / 2),
    ]
    draw.polygon(head_pts, fill=head_steel)
    # Light face (top of head)
    draw.polygon([
        head_pts[0], head_pts[1],
        offset(hcx, hcy, head_len / 2, -head_w * 0.1),
        offset(hcx, hcy, -head_len / 2, -head_w * 0.1),
    ], fill=head_light)

    # --- Sparks / embers ---
    import random
    random.seed(42)
    spark_layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    spark_draw = ImageDraw.Draw(spark_layer)

    spark_origin_x = cx + s * 0.02
    spark_origin_y = face_top - s * 0.03

    for _ in range(28):
        angle_s = random.uniform(-math.pi * 0.85, -math.pi * 0.15)
        dist = random.uniform(s * 0.04, s * 0.22)
        sx = spark_origin_x + math.cos(angle_s) * dist
        sy = spark_origin_y + math.sin(angle_s) * dist * 0.8
        sr = max(1, int(s * random.uniform(0.004, 0.010)))
        brightness = random.uniform(0.5, 1.0)
        r = int(lerp(255, 255, brightness))
        g = int(lerp(100, 220, brightness))
        b = int(lerp(10, 80, brightness))
        a = int(lerp(120, 255, brightness))
        spark_draw.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=(r, g, b, a))

    # Glow pass
    glow_sparks = spark_layer.filter(ImageFilter.GaussianBlur(radius=max(1, s * 0.012)))
    glow_sparks.putalpha(Image.composite(glow_sparks.split()[3], Image.new("L", (s, s), 0), mask))
    img = Image.alpha_composite(img, glow_sparks)

    # Sharp sparks on top
    spark_layer.putalpha(Image.composite(spark_layer.split()[3], Image.new("L", (s, s), 0), mask))
    img = Image.alpha_composite(img, spark_layer)

    # --- Rising ember particles (above, faint) ---
    ember_layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ember_draw = ImageDraw.Draw(ember_layer)
    for _ in range(12):
        ex = cx + random.uniform(-s * 0.15, s * 0.15)
        ey = random.uniform(s * 0.08, face_top - s * 0.06)
        er = max(1, int(s * random.uniform(0.003, 0.007)))
        ea = int(random.uniform(60, 160))
        ember_draw.ellipse([ex - er, ey - er, ex + er, ey + er],
                           fill=(255, int(random.uniform(80, 160)), 10, ea))
    ember_layer = ember_layer.filter(ImageFilter.GaussianBlur(radius=max(1, s * 0.006)))
    ember_layer.putalpha(Image.composite(ember_layer.split()[3], Image.new("L", (s, s), 0), mask))
    img = Image.alpha_composite(img, ember_layer)

    return img


def main():
    os.makedirs(ICON_DIR, exist_ok=True)

    icon_sizes = [
        (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
        (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
        (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x"),
    ]

    for px, label in icon_sizes:
        icon = draw_icon(px)
        path = os.path.join(ICON_DIR, f"icon_{label}.png")
        icon.save(path, "PNG")
        print(f"  {label} ({px}px)")

    result = subprocess.run(
        ["iconutil", "-c", "icns", ICON_DIR, "-o", ICNS_OUT],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"iconutil error: {result.stderr}")
        return

    shutil.rmtree(ICON_DIR)
    print(f"\n  Created {ICNS_OUT}")


if __name__ == "__main__":
    main()
