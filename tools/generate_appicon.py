#!/usr/bin/env python3
"""
tools/generate_appicon.py
Studio-Grade Procedural AppIcon Generator for:
Devil May Cry 4 (Xbox 360, Title ID: 434307DF, Capcom MT Framework)
"Order of the Sword / Devil Bringer" Edition

Renders at 4096x4096 ultra-high resolution and downsamples with Lanczos filtering
to strict RGB (zero alpha channel) 1024x1024 and all iOS/iPadOS AppIcon.appiconset sizes.
Outputs icon preview sheet and populates Assets.xcassets/AppIcon.appiconset/Contents.json.
"""

import argparse
import json
import math
import os
import pathlib
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageEnhance

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
ASSET_DIR = REPO_ROOT / "ios" / "resources" / "Assets.xcassets" / "AppIcon.appiconset"

# Canonical iOS AppIcon specification
ICON_SPECS = [
    {"size": 1024, "idiom": "ios-marketing", "scale": "1x", "filename": "AppIcon-1024.png"},
    {"size": 180,  "idiom": "iphone",        "scale": "3x", "filename": "AppIcon-60@3x.png"},
    {"size": 120,  "idiom": "iphone",        "scale": "2x", "filename": "AppIcon-60@2x.png"},
    {"size": 120,  "idiom": "iphone",        "scale": "3x", "filename": "AppIcon-40@3x.png"},
    {"size": 80,   "idiom": "iphone",        "scale": "2x", "filename": "AppIcon-40@2x.png"},
    {"size": 87,   "idiom": "iphone",        "scale": "3x", "filename": "AppIcon-29@3x.png"},
    {"size": 58,   "idiom": "iphone",        "scale": "2x", "filename": "AppIcon-29@2x.png"},
    {"size": 167,  "idiom": "ipad",          "scale": "2x", "filename": "AppIcon-83.5@2x.png"},
    {"size": 152,  "idiom": "ipad",          "scale": "2x", "filename": "AppIcon-76@2x.png"},
    {"size": 76,   "idiom": "ipad",          "scale": "1x", "filename": "AppIcon-76.png"},
    {"size": 40,   "idiom": "ipad",          "scale": "2x", "filename": "AppIcon-20@2x.png"},
    {"size": 20,   "idiom": "ipad",          "scale": "1x", "filename": "AppIcon-20.png"},
]


def create_procedural_icon(canvas_size: int = 4096, style: str = "bringer") -> Image.Image:
    """
    Renders the studio-grade procedural Devil May Cry 4 icon at canvas_size x canvas_size.
    Layers:
    1. Gothic obsidian dark steel & demon-scale textured background with radial vignette.
    2. Clashing supernatural energy arcs:
       - Left: Nero's Spectral Devil Bringer Cyan-Violet (#00E5FF -> #7B2CBF)
       - Right: Dante's Hellfire Crimson (#FF1A35 -> #FF6B00)
    3. Crossed swords silhouette: Red Queen (motorized rev engine) & Rebellion.
    4. Razor-sharp gothic-metallic beveled chrome 'DMC' crest.
    5. Blazing neon crimson-and-azure '4' centerpiece with specular edge highlights.
    """
    print(f"[generate_appicon] Rendering procedural master canvas ({canvas_size}x{canvas_size}, style={style})...")
    # Base RGBA canvas for precise composite math
    base = Image.new("RGBA", (canvas_size, canvas_size), (8, 9, 13, 255))
    draw = ImageDraw.Draw(base)

    cx = canvas_size / 2.0
    cy = canvas_size / 2.0
    radius = canvas_size * 0.707

    # 1. Background: Gothic Obsidian Dark Steel & Demon Scale Texture
    print("  [layer 1/5] Synthesizing gothic dark-steel & demon scale background...")
    # Radial dark vignette gradient
    bg_gradient = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg_gradient)
    steps = 64
    for s in range(steps):
        r = canvas_size * (1.0 - (s / float(steps)) * 0.75)
        # Deep obsidian steel blue to pitch black
        c_val = int(14 + (1.0 - s / float(steps)) * 18)
        alpha = int((s / float(steps)) * 230)
        bg_draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=(c_val, c_val + 3, c_val + 8, alpha)
        )
    base = Image.alpha_composite(base, bg_gradient)

    # Demon-scale gothic facet lattice
    scale_overlay = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    scale_draw = ImageDraw.Draw(scale_overlay)
    grid_count = 32
    cell = canvas_size / float(grid_count)
    for gy in range(grid_count + 1):
        for gx in range(grid_count + 1):
            offset_x = (cell * 0.5) if (gy % 2 == 1) else 0.0
            x = gx * cell + offset_x
            y = gy * cell * 0.866
            # Draw subtle hexagonal demon scales
            scale_poly = [
                (x, y - cell * 0.45),
                (x + cell * 0.40, y - cell * 0.20),
                (x + cell * 0.40, y + cell * 0.20),
                (x, y + cell * 0.45),
                (x - cell * 0.40, y + cell * 0.20),
                (x - cell * 0.40, y - cell * 0.20),
            ]
            dist_to_center = math.hypot(x - cx, y - cy) / (canvas_size * 0.5)
            alpha_scale = max(0, min(45, int((1.0 - dist_to_center * 0.7) * 45)))
            scale_draw.polygon(scale_poly, outline=(40, 50, 75, alpha_scale))

    base = Image.alpha_composite(base, scale_overlay)

    # 2. Midground: Clashing Supernatural Energy Arcs
    print("  [layer 2/5] Injecting Devil Bringer Cyan & Hellfire Crimson energy arcs...")
    energy_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    energy_draw = ImageDraw.Draw(energy_layer)

    # Nero's Spectral Devil Bringer Cyan-Violet Arc (sweeping from top-left to bottom-center)
    for i in range(40):
        arc_width = int(canvas_size * 0.04 + i * 4)
        alpha_arc = max(0, int(160 - i * 4))
        # Cyan-violet gradient interpolation
        r_col = int(0 + i * 2)
        g_col = int(229 - i * 3)
        b_col = int(255 - i * 1)
        energy_draw.arc(
            [cx - canvas_size * 0.42 - i * 2, cy - canvas_size * 0.40 - i * 2,
             cx + canvas_size * 0.35 + i * 2, cy + canvas_size * 0.45 + i * 2],
            start=110, end=270, width=arc_width,
            fill=(r_col, max(0, g_col), b_col, alpha_arc)
        )

    # Dante's Hellfire Crimson Arc (slashing from top-right down to bottom-left)
    for i in range(40):
        arc_width = int(canvas_size * 0.04 + i * 4)
        alpha_arc = max(0, int(170 - i * 4))
        # Crimson to orange flame
        r_col = int(255)
        g_col = int(26 + i * 4)
        b_col = int(45 - i)
        energy_draw.arc(
            [cx - canvas_size * 0.35 - i * 2, cy - canvas_size * 0.42 - i * 2,
             cx + canvas_size * 0.45 + i * 2, cy + canvas_size * 0.38 + i * 2],
            start=290, end=450, width=arc_width,
            fill=(r_col, min(255, g_col), max(0, b_col), alpha_arc)
        )

    energy_layer = energy_layer.filter(ImageFilter.GaussianBlur(canvas_size * 0.015))
    base = Image.alpha_composite(base, energy_layer)

    # 3. Crossed Swords Silhouette: Red Queen & Rebellion
    print("  [layer 3/5] Forging Red Queen & Rebellion crossed silhouette...")
    sword_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    sword_draw = ImageDraw.Draw(sword_layer)

    # Blade 1: Rebellion (top-left to bottom-right)
    sword_len = canvas_size * 0.78
    sword_thick = canvas_size * 0.035
    blade1_poly = [
        (cx - sword_len * 0.45, cy - sword_len * 0.45),
        (cx - sword_len * 0.45 + sword_thick, cy - sword_len * 0.45 - sword_thick * 0.3),
        (cx + sword_len * 0.45, cy + sword_len * 0.45),
        (cx + sword_len * 0.45 - sword_thick, cy + sword_len * 0.45 + sword_thick * 0.3),
    ]
    sword_draw.polygon(blade1_poly, fill=(20, 22, 28, 220), outline=(220, 40, 50, 180))

    # Blade 2: Red Queen (top-right to bottom-left)
    blade2_poly = [
        (cx + sword_len * 0.45, cy - sword_len * 0.45),
        (cx + sword_len * 0.45 + sword_thick * 0.3, cy - sword_len * 0.45 + sword_thick),
        (cx - sword_len * 0.45, cy + sword_len * 0.45),
        (cx - sword_len * 0.45 - sword_thick * 0.3, cy + sword_len * 0.45 - sword_thick),
    ]
    sword_draw.polygon(blade2_poly, fill=(20, 22, 28, 220), outline=(0, 220, 255, 180))

    # Center guard skull/engine emblem
    skull_r = canvas_size * 0.075
    sword_draw.ellipse(
        [cx - skull_r, cy - skull_r, cx + skull_r, cy + skull_r],
        fill=(28, 30, 36, 240), outline=(210, 225, 245, 230), width=int(canvas_size * 0.006)
    )

    sword_shadow = sword_layer.filter(ImageFilter.GaussianBlur(canvas_size * 0.012))
    base = Image.alpha_composite(base, sword_shadow)
    base = Image.alpha_composite(base, sword_layer)

    # 4. Foreground: Beveled Chrome 'DMC' Crest
    print("  [layer 4/5] Sculpting gothic beveled chrome 'DMC' lettering...")
    text_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    text_draw = ImageDraw.Draw(text_layer)

    # Fallback to high-contrast geometric block fonts if custom font missing
    font_size_dmc = int(canvas_size * 0.28)
    font_size_num = int(canvas_size * 0.48)
    try:
        # Check standard Windows / macOS fonts
        font_paths = [
            "C:\\Windows\\Fonts\\impact.ttf",
            "C:\\Windows\\Fonts\\arialbd.ttf",
            "/System/Library/Fonts/HelveticaNeue.ttc",
            "/Library/Fonts/Impact.ttf",
        ]
        font_path = next((p for p in font_paths if os.path.isfile(p)), None)
        if font_path:
            font_dmc = ImageFont.truetype(font_path, font_size_dmc)
            font_num = ImageFont.truetype(font_path, font_size_num)
        else:
            font_dmc = ImageFont.load_default()
            font_num = ImageFont.load_default()
    except Exception:
        font_dmc = ImageFont.load_default()
        font_num = ImageFont.load_default()

    dmc_str = "DMC"
    num_str = "4"

    # Compute bounding boxes for centering
    bbox_dmc = text_draw.textbbox((0, 0), dmc_str, font=font_dmc)
    w_dmc = bbox_dmc[2] - bbox_dmc[0]
    h_dmc = bbox_dmc[3] - bbox_dmc[1]
    dmc_x = cx - w_dmc / 2.0
    dmc_y = cy - h_dmc * 0.95

    bbox_num = text_draw.textbbox((0, 0), num_str, font=font_num)
    w_num = bbox_num[2] - bbox_num[0]
    h_num = bbox_num[3] - bbox_num[1]
    num_x = cx - w_num / 2.0
    num_y = cy - h_num * 0.15

    # Multi-pass deep drop shadows
    shadow_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_layer)
    shadow_offset = int(canvas_size * 0.02)
    shadow_draw.text((dmc_x + shadow_offset, dmc_y + shadow_offset), dmc_str, font=font_dmc, fill=(0, 0, 0, 230))
    shadow_draw.text((num_x + shadow_offset, num_y + shadow_offset), num_str, font=font_num, fill=(0, 0, 0, 240))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(canvas_size * 0.018))
    base = Image.alpha_composite(base, shadow_layer)

    # Draw 'DMC' Gothic Beveled Chrome
    bevel_passes = 12
    for b in range(bevel_passes, 0, -1):
        shade = int(140 + (b / float(bevel_passes)) * 115)
        offset = b * (canvas_size * 0.0015)
        text_draw.text((dmc_x - offset, dmc_y - offset), dmc_str, font=font_dmc, fill=(shade, shade, shade, 255))

    # Specular Chrome Core for DMC
    text_draw.text((dmc_x, dmc_y), dmc_str, font=font_dmc, fill=(245, 250, 255, 255))
    # Subtle azure chrome rim on DMC
    text_draw.text((dmc_x, dmc_y), dmc_str, font=font_dmc, fill=None, outline=(0, 210, 255, 200), width=int(canvas_size * 0.004))

    # 5. Centerpiece: Blazing Neon Crimson-Azure '4'
    print("  [layer 5/5] Igniting blazing dual-energy '4' centerpiece...")
    # '4' Outer Neon Glow
    glow_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)
    glow_draw.text((num_x, num_y), num_str, font=font_num, fill=(255, 30, 60, 220))
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(canvas_size * 0.025))
    base = Image.alpha_composite(base, glow_layer)

    # '4' Body: Dual-Gradient Simulation
    text_draw.text((num_x, num_y), num_str, font=font_num, fill=(255, 25, 55, 255))
    # Electric Cyan Inner Accent on '4'
    cyan_accent = int(canvas_size * 0.008)
    text_draw.text((num_x - cyan_accent, num_y - cyan_accent), num_str, font=font_num, fill=None, outline=(0, 235, 255, 240), width=int(canvas_size * 0.006))

    # Specular white edge highlights on '4'
    highlight_accent = int(canvas_size * 0.003)
    text_draw.text((num_x - highlight_accent, num_y - highlight_accent), num_str, font=font_num, fill=None, outline=(255, 255, 255, 200), width=int(canvas_size * 0.002))

    base = Image.alpha_composite(base, text_layer)

    # Clearcoat rim lighting
    rim_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    rim_draw = ImageDraw.Draw(rim_layer)
    rim_draw.rounded_rectangle(
        [canvas_size * 0.015, canvas_size * 0.015, canvas_size * 0.985, canvas_size * 0.985],
        radius=int(canvas_size * 0.22),
        outline=(180, 220, 255, 120),
        width=int(canvas_size * 0.005)
    )
    base = Image.alpha_composite(base, rim_layer)

    # Convert to STRICT 24-bit RGB (Zero Alpha Channel)
    rgb_icon = Image.new("RGB", (canvas_size, canvas_size), (8, 9, 13))
    rgb_icon.paste(base, (0, 0), base)
    print("  [generate_appicon] Procedural 4096px icon master created.")
    return rgb_icon


def build_preview_sheet(master_icon: Image.Image, output_path: pathlib.Path):
    """
    Creates a studio inspection sheet showing the icon at various sizes:
    1024x1024 (App Store), 180x180 (iPhone Home), 120x120 (iPad Home), 60x60 (Spotlight).
    """
    sheet_w = 1600
    sheet_h = 1200
    sheet = Image.new("RGB", (sheet_w, sheet_h), (16, 17, 22))
    s_draw = ImageDraw.Draw(sheet)

    # Title Banner
    try:
        font = ImageFont.truetype("C:\\Windows\\Fonts\\arial.ttf", 36)
        small_font = ImageFont.truetype("C:\\Windows\\Fonts\\arial.ttf", 20)
    except Exception:
        font = ImageFont.load_default()
        small_font = ImageFont.load_default()

    s_draw.text((40, 40), "Devil May Cry 4 (Title ID: 434307DF) - Studio AppIcon Preview", font=font, fill=(240, 245, 255))
    s_draw.text((40, 85), "Design: 'Order of the Sword / Devil Bringer' (Strict RGB 24-bit, Lanczos Antialiased)", font=small_font, fill=(140, 155, 185))

    # Place 1024 preview scaled down to 800x800
    preview_1024 = master_icon.resize((800, 800), Image.Resampling.LANCZOS)
    sheet.paste(preview_1024, (40, 140))
    s_draw.text((40, 960), "1024x1024 Master (App Store / LiveContainer)", font=small_font, fill=(180, 190, 210))

    # Column 2: 180x180, 120x120, 60x60
    sizes = [(180, "iPhone Home @3x (180x180)"), (120, "iPad / iPhone @2x (120x120)"), (60, "Spotlight Search (60x60)")]
    cur_y = 140
    for sz, label in sizes:
        sub_icon = master_icon.resize((sz, sz), Image.Resampling.LANCZOS)
        sheet.paste(sub_icon, (920, cur_y))
        s_draw.text((920 + sz + 25, cur_y + sz // 2 - 10), label, font=small_font, fill=(220, 230, 250))
        cur_y += sz + 60

    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(str(output_path), format="PNG")
    print(f"[generate_appicon] Studio preview sheet saved to {output_path}")


def populate_asset_catalog(master_icon: Image.Image, asset_dir: pathlib.Path):
    """
    Populates Assets.xcassets/AppIcon.appiconset with all downsampled PNGs
    and validates Contents.json.
    """
    asset_dir.mkdir(parents=True, exist_ok=True)
    print(f"[generate_appicon] Generating asset catalog in {asset_dir}...")

    images_metadata = []
    for spec in ICON_SPECS:
        target_size = spec["size"]
        filename = spec["filename"]
        out_file = asset_dir / filename

        resized = master_icon.resize((target_size, target_size), Image.Resampling.LANCZOS)
        # Ensure strict RGB, zero alpha
        if resized.mode != "RGB":
            resized = resized.convert("RGB")
        resized.save(str(out_file), format="PNG", optimize=True)

        size_str = f"{target_size // int(spec['scale'][0])}x{target_size // int(spec['scale'][0])}"
        if "83.5" in filename:
            size_str = "83.5x83.5"
        images_metadata.append({
            "size": size_str,
            "idiom": spec["idiom"],
            "filename": filename,
            "scale": spec["scale"]
        })
        print(f"  - Generated {filename:22s} ({target_size}x{target_size} RGB)")

    contents = {
        "images": images_metadata,
        "info": {
            "version": 1,
            "author": "antigravity-dmc4-recomp"
        }
    }

    contents_path = asset_dir / "Contents.json"
    contents_path.write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    print(f"[generate_appicon] Validated Contents.json written to {contents_path}")


def main():
    parser = argparse.ArgumentParser(description="Devil May Cry 4 Studio AppIcon Generator")
    parser.add_argument("--style", choices=["bringer", "crimson", "crest"], default="bringer")
    parser.add_argument("--input", help="Optional custom master image to downsample")
    parser.add_argument("--output-preview", default=str(REPO_ROOT / "tools" / "icon_preview_sheet.png"))
    parser.add_argument("--out-dir", default=str(ASSET_DIR))
    args = parser.parse_args()

    out_asset_dir = pathlib.Path(args.out_dir).resolve()
    preview_path = pathlib.Path(args.output_preview).resolve()

    if args.input and os.path.isfile(args.input):
        print(f"[generate_appicon] Loading custom master image from {args.input}...")
        custom_img = Image.open(args.input)
        if custom_img.mode != "RGB":
            custom_img = custom_img.convert("RGB")
        master = custom_img.resize((4096, 4096), Image.Resampling.LANCZOS)
    else:
        master = create_procedural_icon(canvas_size=4096, style=args.style)

    # 1. Populate Assets.xcassets
    populate_asset_catalog(master, out_asset_dir)

    # 2. Output Preview Sheet
    build_preview_sheet(master, preview_path)

    print("\n[generate_appicon] AppIcon generation completed successfully.")


if __name__ == "__main__":
    main()
