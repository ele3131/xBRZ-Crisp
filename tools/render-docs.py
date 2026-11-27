#!/usr/bin/env python3
"""Headless renderer for docs/img/ comparator scenes, docs/img/explain/ diagrams, and docs/sheets/ README visuals.

Uses surfaceless EGL + OpenGL ES via tools/verify.py and skips overwriting PNGs whose pixel content
has not changed by default (--force overrides).

Usage:
    python3 tools/render-docs.py                           # Update only changed docs/img/*-{crisp10,20,30}.png
    python3 tools/render-docs.py --include-xbrz            # Also update docs/img/*-xbrz.png (4-pass plain multipass)
    python3 tools/render-docs.py --all --include-xbrz      # Also build docs/img/explain/* and docs/sheets/* (README)
    python3 tools/render-docs.py --all --force             # Force-rebuild all generated visual assets
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile

os.environ.setdefault("LP_NATIVE_VECTOR_WIDTH", "128")

import numpy as np
from PIL import Image, ImageDraw, ImageFont

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS_DIR)
SHADERS_DIR = os.path.join(ROOT, "shaders")
DOCS_DIR = os.path.join(ROOT, "docs")
DOCS_IMG_DIR = os.path.join(DOCS_DIR, "img")
EXPLAIN_DIR = os.path.join(DOCS_IMG_DIR, "explain")
SHEETS_DIR = os.path.join(DOCS_DIR, "sheets")
MICRO_DIR = os.path.join(TOOLS_DIR, "assets", "micro")
SPEC_PATH = os.path.join(TOOLS_DIR, "sheets_spec.json")

sys.path.insert(0, TOOLS_DIR)
from verify import HeadlessGLES  # noqa: E402

# Palette matching GitHub Dark Dimmed / Modern Showcase cards
BG_CARD = (13, 17, 23)
BG_PANEL = (22, 27, 34)
BORDER_SUBTLE = (48, 54, 61)
BORDER_RED = (248, 81, 73)
BORDER_GREEN = (63, 185, 80)
BORDER_BLUE = (56, 139, 253)
TEXT_MAIN = (240, 246, 252)
TEXT_MUTED = (139, 148, 158)
TEXT_RED = (255, 123, 114)
TEXT_GREEN = (86, 211, 100)
TEXT_BLUE = (121, 192, 255)

PLAT_COLORS = {
    "NEO GEO":    ((58, 42, 14),  (210, 153, 34), (242, 204, 96)),
    "SNES":       ((45, 29, 71),  (163, 113, 247),(210, 168, 255)),
    "MEGA DRIVE": ((19, 43, 77),  (56, 139, 253), (121, 192, 255)),
    "GBA":        ((18, 52, 59),  (47, 179, 196), (118, 227, 234)),
    "NES":        ((69, 25, 25),  (248, 81, 73),  (255, 161, 152)),
    "GBC":        ((22, 54, 34),  (63, 185, 80),  (126, 231, 135)),
}


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = (
        [
            "/usr/share/fonts/truetype/roboto/unhinted/RobotoTTF/Roboto-Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        ]
        if bold
        else [
            "/usr/share/fonts/truetype/roboto/unhinted/RobotoTTF/Roboto-Regular.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        ]
    )
    for path in candidates:
        if os.path.isfile(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def save_if_changed(rgb: np.ndarray, path: str, force: bool = False, dry_run: bool = False, tol_lsb: int = 1) -> bool:
    if not force and os.path.isfile(path):
        old = np.array(Image.open(path).convert("RGB"), dtype=np.uint8)
        if old.shape == rgb.shape:
            max_delta = int(np.max(np.abs(old.astype(np.int16) - rgb.astype(np.int16))))
            if max_delta <= tol_lsb:
                return False
    if not dry_run:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        Image.fromarray(rgb, "RGB").save(path, format="PNG", optimize=True, compress_level=9)
    return True


def text_size(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont) -> tuple[int, int]:
    bb = draw.textbbox((0, 0), text, font=font)
    return bb[2] - bb[0], bb[3] - bb[1]


def draw_pill(
    draw: ImageDraw.ImageDraw,
    x: int,
    y: int,
    text: str,
    font: ImageFont.ImageFont,
    fill: tuple[int, int, int],
    outline: tuple[int, int, int],
    fg: tuple[int, int, int],
    px: int = 8,
    py: int = 3,
    radius: int = 6,
) -> int:
    tw, th = text_size(draw, text, font)
    w = tw + 2 * px
    h = th + 2 * py
    draw.rounded_rectangle([x, y, x + w, y + h], radius=radius, fill=fill, outline=outline, width=1)
    bb = draw.textbbox((0, 0), text, font=font)
    draw.text((x + px - bb[0], y + py - bb[1]), text, font=font, fill=fg)
    return w


def draw_centered_pill(
    draw: ImageDraw.ImageDraw,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    text: str,
    font: ImageFont.ImageFont,
    fill: tuple[int, int, int],
    outline: tuple[int, int, int],
    fg: tuple[int, int, int],
    radius: int = 6,
) -> None:
    draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=fill, outline=outline, width=1)
    bb = draw.textbbox((0, 0), text, font=font)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    tx = x0 + (x1 - x0 - tw) // 2 - bb[0]
    ty = y0 + (y1 - y0 - th) // 2 - bb[1]
    draw.text((tx, ty), text, font=font, fill=fg)


def fit_image(img: Image.Image, target_w: int, target_h: int, smooth: bool = False) -> Image.Image:
    """Scale image to exact target box (aspect-preserving center crop if needed).

    Uses nearest-neighbor for raw 1x pixel art (smooth=False) and Lanczos for already-upscaled
    6x anti-aliased renders (smooth=True) so fractional panel scaling does not introduce jagged
    sawtooth steps along smooth diagonal contours.
    """
    sw, sh = img.size
    if sw == target_w and sh == target_h:
        return img
    scale = max(target_w / sw, target_h / sh)
    nw = max(target_w, int(round(sw * scale)))
    nh = max(target_h, int(round(sh * scale)))
    resample = Image.Resampling.LANCZOS if smooth else Image.Resampling.NEAREST
    scaled = img.resize((nw, nh), resample)
    ox = (nw - target_w) // 2
    oy = (nh - target_h) // 2
    return scaled.crop((ox, oy, ox + target_w, oy + target_h))


def paste_framed(
    canvas: Image.Image,
    img: Image.Image,
    x: int,
    y: int,
    w: int,
    h: int,
    border_col: tuple[int, int, int],
    bw: int = 2,
    smooth: bool = True,
) -> None:
    fitted = fit_image(img, w - 2 * bw, h - 2 * bw, smooth=smooth)
    draw = ImageDraw.Draw(canvas)
    draw.rectangle([x, y, x + w - 1, y + h - 1], fill=border_col)
    canvas.paste(fitted, (x + bw, y + bw))


def load_or_render_sources(
    spec: dict,
    gles: HeadlessGLES,
    crisp_progs: list[int],
    docs_renders: dict[tuple[str, str], Image.Image],
) -> dict[str, dict[str, Image.Image]]:
    """Build {source_id: {'original': PIL, 'xbrzcpp': PIL, 'crisp20': PIL, ...}} at 6x scale."""
    out: dict[str, dict[str, Image.Image]] = {}
    for sid, cfg in spec["sources"].items():
        if cfg["kind"] == "micro":
            orig_full = Image.open(os.path.join(MICRO_DIR, f"{sid}-original.png")).convert("RGBA")
            px0, py0, px1, py1 = cfg["pad_crop"]
            orig_crop = orig_full.convert("RGB").crop((px0, py0, px1, py1))
            orig_6x = orig_crop.resize((orig_crop.width * 6, orig_crop.height * 6), Image.Resampling.NEAREST)
            xbrz_6x = Image.open(os.path.join(MICRO_DIR, f"{sid}-xbrzcpp.png")).convert("RGB")
            inp = np.ascontiguousarray(np.array(orig_full, dtype=np.uint8))
            crisp_full = Image.fromarray(
                gles.render_pipeline(crisp_progs, inp, scale=6, minc=20.0, diag=100.0, tol=15.0, steep=3.2, dom=3.8),
                "RGB",
            )
            crisp_6x = crisp_full.crop((px0 * 6, py0 * 6, px1 * 6, py1 * 6))
            out[sid] = {"original": orig_6x, "xbrzcpp": xbrz_6x, "crisp20": crisp_6x}
        else:
            sc = cfg["scene"]
            x0, y0, x1, y1 = cfg["box"]
            b6 = (x0 * 6, y0 * 6, x1 * 6, y1 * 6)
            orig_1x = Image.open(os.path.join(DOCS_IMG_DIR, f"{sc}-original.png")).convert("RGB").crop((x0, y0, x1, y1))
            entry = {
                "original": orig_1x.resize((orig_1x.width * 6, orig_1x.height * 6), Image.Resampling.NEAREST),
                "xbrzcpp": Image.open(os.path.join(DOCS_IMG_DIR, f"{sc}-xbrzcpp.png")).convert("RGB").crop(b6),
            }
            for suffix in ("crisp10", "crisp20", "crisp30"):
                if (sc, suffix) in docs_renders:
                    entry[suffix] = docs_renders[(sc, suffix)].crop(b6)
            out[sid] = entry
    return out


def render_banner(spec: dict, sources: dict, docs_renders: dict) -> np.ndarray:
    cfg = spec["banner"]
    W, H = 1040, 392
    bg_src = docs_renders[(cfg["bg_scene"], "crisp20")]
    bx0, by0, bx1, by1 = cfg["bg_box_6x"]
    bg_crop = fit_image(bg_src.crop((bx0, by0, bx1, by1)), W, H, smooth=True)

    # Darken background smoothly with left-heavy readability gradient
    bg_arr = np.array(bg_crop, dtype=np.float32)
    xs = np.linspace(0.0, 1.0, W, dtype=np.float32)[None, :, None]
    tint = 0.44 + 0.14 * (1.0 - xs)
    bg_arr = np.clip(bg_arr * tint * 0.92 + np.array([8.0, 11.0, 16.0]) * 0.35, 0, 255).astype(np.uint8)
    canvas = Image.fromarray(bg_arr, "RGB")

    # Apply rounded outer frame over dark backdrop
    outer = Image.new("RGB", (W, H), BG_CARD)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, H - 1], radius=12, fill=255)
    outer.paste(canvas, (0, 0), mask)
    draw = ImageDraw.Draw(outer)
    draw.rounded_rectangle([0, 0, W - 1, H - 1], radius=12, outline=BORDER_SUBTLE, width=1)

    # Left column typography
    f_pill = load_font(12, bold=True)
    f_title = load_font(54, bold=True)
    f_sub = load_font(20, bold=True)
    f_bul = load_font(15, bold=False)
    f_foot = load_font(13, bold=False)

    draw_pill(draw, 32, 34, cfg["pill"], f_pill, fill=(18, 52, 29), outline=BORDER_GREEN, fg=TEXT_GREEN, px=12, py=5, radius=12)

    # Drop shadow + title
    draw.text((34, 86), cfg["title"], font=f_title, fill=(6, 9, 14))
    draw.text((32, 84), cfg["title"], font=f_title, fill=TEXT_MAIN)

    y_sub = 152
    for line in cfg["subtitle"].splitlines():
        draw.text((32, y_sub), line, font=f_sub, fill=(224, 232, 240))
        y_sub += 26

    y_b = 224
    for btxt in cfg["bullets"]:
        cx, cy = 40, y_b + 9
        draw.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=(18, 58, 32), outline=BORDER_GREEN, width=1)
        draw.line([(cx - 4, cy), (cx - 1, cy + 3), (cx + 4, cy - 3)], fill=TEXT_GREEN, width=2)
        draw.text((58, y_b), btxt, font=f_bul, fill=(220, 228, 236))
        y_b += 31

    draw.text((32, 346), cfg["footnote"], font=f_foot, fill=(165, 174, 184))

    # Right column: 2 stacked dark showcase cards
    f_head = load_font(14, bold=True)
    f_tag = load_font(12, bold=True)
    card_x, card_w = 428, 588
    card_h, card_gap = 168, 16
    card_ys = [20, 20 + card_h + card_gap]
    for card_cfg, cy0 in zip(cfg["cards"], card_ys):
        draw.rounded_rectangle(
            [card_x, cy0, card_x + card_w, cy0 + card_h],
            radius=10,
            fill=(15, 20, 27),
            outline=BORDER_SUBTLE,
            width=1,
        )
        draw.text((card_x + 14, cy0 + 10), card_cfg["heading"], font=f_head, fill=TEXT_MAIN)
        src = sources[card_cfg["source"]]
        pw = (card_w - 36) // 2
        ph = card_h - 46
        py0 = cy0 + 34
        lx = card_x + 12
        rx = lx + pw + 12
        paste_framed(outer, src["xbrzcpp"], lx, py0, pw, ph, BORDER_RED, bw=2)
        paste_framed(outer, src["crisp20"], rx, py0, pw, ph, BORDER_GREEN, bw=2)
        draw_pill(draw, lx + 8, py0 + 8, "xBRZ 1.9", f_tag, fill=(84, 24, 24), outline=BORDER_RED, fg=(255, 210, 205), px=8, py=3, radius=5)
        draw_pill(draw, rx + 8, py0 + 8, "xBRZ Crisp", f_tag, fill=(18, 66, 33), outline=BORDER_GREEN, fg=(205, 255, 215), px=8, py=3, radius=5)

    return np.array(outer, dtype=np.uint8)


def render_hero_triptych(spec: dict, sources: dict) -> np.ndarray:
    cfg = spec["hero_triptych"]
    src_meta = spec["sources"][cfg["source"]]
    src = sources[cfg["source"]]
    W = 1040
    pad = 16
    gap = 12
    pw = (W - 2 * pad - 2 * gap) // 3
    ph = int(round(pw * (src["crisp20"].height / src["crisp20"].width)))
    H = 54 + ph + 40

    im = Image.new("RGB", (W, H), BG_CARD)
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle([0, 0, W - 1, H - 1], radius=10, fill=BG_CARD, outline=BORDER_SUBTLE, width=1)

    f_plat = load_font(12, bold=True)
    f_head = load_font(16, bold=True)
    f_tag = load_font(12, bold=True)
    f_cap = load_font(13, bold=False)

    pf, po, pt = PLAT_COLORS[src_meta["platform"]]
    pw_badge = draw_pill(draw, pad, 14, src_meta["platform"], f_plat, pf, po, pt, px=8, py=3, radius=5)
    draw.text((pad + pw_badge + 10, 14), cfg["heading"], font=f_head, fill=TEXT_MAIN)

    y0 = 50
    specs = [
        ("original", "Original 1×",         BORDER_SUBTLE, (28, 33, 40),  BORDER_SUBTLE, TEXT_MAIN,  TEXT_MUTED),
        ("xbrzcpp",  "xBRZ 1.9 (Problem)",  BORDER_RED,    (74, 22, 22),  BORDER_RED,    TEXT_RED,   TEXT_RED),
        ("crisp20",  "xBRZ Crisp (Solved)", BORDER_GREEN,  (17, 60, 30),  BORDER_GREEN,  TEXT_GREEN, TEXT_GREEN),
    ]
    for idx, (var, tag, bcol, pfill, pout, pfg, ccol) in enumerate(specs):
        x0 = pad + idx * (pw + gap)
        paste_framed(im, src[var], x0, y0, pw, ph, bcol, bw=2, smooth=(var != "original"))
        draw_pill(draw, x0 + 10, y0 + 10, tag, f_tag, pfill, pout, pfg, px=9, py=4, radius=5)
        cap = cfg["captions"][idx]
        cw, _ = text_size(draw, cap, f_cap)
        draw.text((x0 + (pw - cw) // 2, y0 + ph + 10), cap, font=f_cap, fill=ccol)

    return np.array(im, dtype=np.uint8)


def render_strip(strip_cfg: dict, spec: dict, sources: dict) -> np.ndarray:
    W = 1040
    pad = 16
    gap = 12
    pw = (W - 2 * pad - 2 * gap) // 3
    row_heights = []
    for r in strip_cfg["rows"]:
        ref_im = sources[r["source"]]["crisp20"]
        rh = int(round(pw * (ref_im.height / ref_im.width)))
        rh = max(112, min(260, rh))
        row_heights.append(rh)

    header_h = 84
    row_meta_h = 28
    row_gap = 16
    H = header_h + sum(row_meta_h + rh for rh in row_heights) + row_gap * (len(row_heights) - 1) + 18

    im = Image.new("RGB", (W, H), BG_CARD)
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle([0, 0, W - 1, H - 1], radius=10, fill=BG_CARD, outline=BORDER_SUBTLE, width=1)

    f_badge = load_font(12, bold=True)
    f_title = load_font(17, bold=True)
    f_col = load_font(13, bold=True)
    f_game = load_font(13, bold=False)

    bw_pill = draw_pill(draw, pad, 14, strip_cfg["badge"], f_badge, (17, 54, 29), BORDER_GREEN, TEXT_GREEN, px=8, py=3, radius=5)
    draw.text((pad + bw_pill + 10, 14), strip_cfg["title"], font=f_title, fill=TEXT_MAIN)

    cols = [
        ("Original 1×",                  (22, 27, 34), BORDER_SUBTLE, TEXT_MAIN),
        ("xBRZ 1.9 (Original) — Problem",(56, 20, 22), BORDER_RED,    TEXT_RED),
        ("xBRZ Crisp — Solution",        (16, 48, 28), BORDER_GREEN,  TEXT_GREEN),
    ]
    for i, (lbl, fill, out, fg) in enumerate(cols):
        x0 = pad + i * (pw + gap)
        draw_centered_pill(draw, x0, 46, x0 + pw - 1, 74, lbl, f_col, fill, out, fg, radius=6)

    y = header_h
    for r, rh in zip(strip_cfg["rows"], row_heights):
        meta = spec["sources"][r["source"]]
        src = sources[r["source"]]
        pf, po, pt = PLAT_COLORS[meta["platform"]]
        pw_p = draw_pill(draw, pad, y + 2, meta["platform"], f_badge, pf, po, pt, px=7, py=2, radius=5)
        draw.text((pad + pw_p + 8, y + 4), f"{meta['game']}  —  {r['caption']}", font=f_game, fill=(195, 203, 212))
        y += row_meta_h
        for i, (var, bcol) in enumerate([("original", BORDER_SUBTLE), ("xbrzcpp", BORDER_RED), ("crisp20", BORDER_GREEN)]):
            x0 = pad + i * (pw + gap)
            paste_framed(im, src[var], x0, y, pw, rh, bcol, bw=2, smooth=(var != "original"))
        y += rh + row_gap

    return np.array(im, dtype=np.uint8)


def render_console_tile(tile_cfg: dict, spec: dict, sources: dict) -> np.ndarray:
    W, H = 330, 178
    pad = 12
    gap = 6
    pw = (W - 2 * pad - gap) // 2
    ph = 116
    im = Image.new("RGB", (W, H), BG_CARD)
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle([0, 0, W - 1, H - 1], radius=8, fill=BG_CARD, outline=BORDER_SUBTLE, width=1)

    meta = spec["sources"][tile_cfg["source"]]
    src = sources[tile_cfg["source"]]
    f_plat = load_font(11, bold=True)
    f_title = load_font(14, bold=True)
    f_foot = load_font(12, bold=True)

    pf, po, pt = PLAT_COLORS[meta["platform"]]
    pw_b = draw_pill(draw, pad, 10, meta["platform"], f_plat, pf, po, pt, px=7, py=2, radius=5)
    draw.text((pad + pw_b + 8, 11), tile_cfg["title"], font=f_title, fill=TEXT_MAIN)

    y0 = 36
    paste_framed(im, src["xbrzcpp"], pad, y0, pw, ph, BORDER_RED, bw=2)
    paste_framed(im, src["crisp20"], pad + pw + gap, y0, pw, ph, BORDER_GREEN, bw=2)

    draw.text((pad + 2, y0 + ph + 6), "xBRZ 1.9", font=f_foot, fill=TEXT_RED)
    rw, _ = text_size(draw, "xBRZ Crisp", f_foot)
    draw.text((W - pad - rw - 2, y0 + ph + 6), "xBRZ Crisp", font=f_foot, fill=TEXT_GREEN)
    return np.array(im, dtype=np.uint8)


def render_presets_strip(spec: dict, sources: dict) -> np.ndarray:
    cfg = spec["presets"]
    src = sources[cfg["source"]]
    W, H = 1020, 316
    pad = 16
    gap = 12
    cols = cfg["columns"]
    cw = (W - 2 * pad - gap * (len(cols) - 1)) // len(cols)
    ph = cw

    im = Image.new("RGB", (W, H), BG_CARD)
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle([0, 0, W - 1, H - 1], radius=10, fill=BG_CARD, outline=BORDER_SUBTLE, width=1)

    f_title = load_font(17, bold=True)
    f_sub = load_font(13, bold=False)
    f_lbl = load_font(13, bold=True)
    f_note = load_font(12, bold=False)

    draw.text((pad, 14), cfg["title"], font=f_title, fill=TEXT_MAIN)
    sw, _ = text_size(draw, cfg["subtitle"], f_sub)
    draw.text((W - pad - sw, 17), cfg["subtitle"], font=f_sub, fill=TEXT_MUTED)

    style_map = {
        "neutral": ((22, 27, 34), BORDER_SUBTLE, TEXT_MAIN,  BORDER_SUBTLE, TEXT_MUTED),
        "red":     ((56, 20, 22), BORDER_RED,    TEXT_RED,   BORDER_RED,    TEXT_MUTED),
        "blue":    ((18, 38, 66), BORDER_BLUE,   TEXT_BLUE,  BORDER_SUBTLE, TEXT_MUTED),
        "green":   ((16, 52, 28), BORDER_GREEN,  TEXT_GREEN, BORDER_GREEN,  TEXT_GREEN),
    }
    y_lbl = 52
    y_img = 84
    for i, col in enumerate(cols):
        x0 = pad + i * (cw + gap)
        pfill, pout, pfg, bcol, ncol = style_map[col["style"]]
        if col["style"] == "green":
            draw.rounded_rectangle(
                [x0 - 4, y_lbl - 4, x0 + cw + 3, y_img + ph + 30],
                radius=9,
                fill=(13, 33, 21),
                outline=BORDER_GREEN,
                width=2,
            )
        draw_centered_pill(draw, x0, y_lbl, x0 + cw - 1, y_lbl + 26, col["label"], f_lbl, pfill, pout, pfg, radius=6)
        paste_framed(im, src[col["variant"]], x0, y_img, cw, ph, bcol, bw=2, smooth=(col["variant"] != "original"))
        nw, _ = text_size(draw, col["note"], f_note)
        draw.text((x0 + (cw - nw) // 2, y_img + ph + 8), col["note"], font=f_note, fill=ncol)

    return np.array(im, dtype=np.uint8)


def render_explain_diagram(ecfg: dict, docs_renders: dict) -> np.ndarray:
    labels = {
        "original": "Original",
        "xbrzcpp":  "xBRZ (original)",
        "crisp10":  "Crisp 10",
        "crisp20":  "xBRZ Crisp",
        "crisp30":  "Crisp 30",
    }
    variants = ecfg["variants"]
    if len(variants) == 5:
        labels["crisp20"] = "Crisp 20"

    rows_spec = ecfg["multi_rows"] if "multi_rows" in ecfg else [
        {"scene": ecfg["scene"], "box": ecfg["box"], "zoom": ecfg["zoom"]}
    ]
    pad, gap, head_h = 10, 10, 34
    f_hdr = load_font(13, bold=True)

    rendered_rows = []
    for r in rows_spec:
        sc = r["scene"]
        x0, y0, x1, y1 = r["box"]
        z = r["zoom"]
        w_out = (x1 - x0) * 6 * z
        h_out = (y1 - y0) * 6 * z
        b6 = (x0 * 6, y0 * 6, x1 * 6, y1 * 6)
        orig_1x = Image.open(os.path.join(DOCS_IMG_DIR, f"{sc}-original.png")).convert("RGB").crop((x0, y0, x1, y1))
        xbrz_6x = Image.open(os.path.join(DOCS_IMG_DIR, f"{sc}-xbrzcpp.png")).convert("RGB").crop(b6)
        row_imgs = []
        for v in variants:
            if v == "original":
                sub = orig_1x.resize((w_out, h_out), Image.Resampling.NEAREST)
            elif v == "xbrzcpp":
                sub = xbrz_6x.resize((w_out, h_out), Image.Resampling.NEAREST)
            else:
                sub = docs_renders[(sc, v)].crop(b6).resize((w_out, h_out), Image.Resampling.NEAREST)
            row_imgs.append(sub)
        rendered_rows.append((w_out, h_out, row_imgs))

    panel_w = rendered_rows[0][0]
    W = pad * 2 + len(variants) * panel_w + (len(variants) - 1) * gap
    H = head_h + sum(h for _, h, _ in rendered_rows) + gap * (len(rendered_rows) - 1) + pad

    im = Image.new("RGB", (W, H), (24, 24, 28))
    draw = ImageDraw.Draw(im)
    for idx, v in enumerate(variants):
        x0 = pad + idx * (panel_w + gap)
        lbl = labels[v]
        tw, _ = text_size(draw, lbl, f_hdr)
        col = TEXT_GREEN if v == "crisp20" else (TEXT_RED if v == "xbrzcpp" else TEXT_MAIN)
        draw.text((x0 + (panel_w - tw) // 2, 10), lbl, font=f_hdr, fill=col)

    y = head_h
    for _, h_out, row_imgs in rendered_rows:
        for idx, sub in enumerate(row_imgs):
            x0 = pad + idx * (panel_w + gap)
            im.paste(sub, (x0, y))
        y += h_out + gap

    return np.array(im, dtype=np.uint8)


def _render_docs_chunk(args_tuple: tuple) -> tuple[int, int, list[str], dict[tuple[str, str], str]]:
    """Worker process: renders a chunk of docs/img/*-original.png scenes and saves updated PNGs."""
    os.environ["LP_NATIVE_VECTOR_WIDTH"] = "128"
    crisp_glsl, mp_glsl, scene_paths, force, dry_run, tol_lsb, keep_all = args_tuple
    gles = HeadlessGLES()
    crisp_progs = [
        gles.compile_program(os.path.join(crisp_glsl, f"xbrz-crisp-{p}.glsl"), "#version 300 es", True)
        for p in ("point", "pass0", "resolve", "match", "pass1")
    ]
    mp_progs = (
        [
            gles.compile_program(os.path.join(mp_glsl, f"xbrz-freescale-{p}.glsl"), "#version 300 es", True)
            for p in ("point", "pass0", "resolve", "pass1")
        ]
        if mp_glsl
        else []
    )
    updated, skipped = 0, 0
    logs: list[str] = []
    saved_paths: dict[tuple[str, str], str] = {}
    try:
        for sp in scene_paths:
            sid = os.path.basename(sp).replace("-original.png", "")
            inp = np.ascontiguousarray(np.array(Image.open(sp).convert("RGBA"), dtype=np.uint8))
            for minc_val, suffix in ((10.0, "crisp10"), (20.0, "crisp20"), (30.0, "crisp30")):
                rgb = gles.render_pipeline(crisp_progs, inp, scale=6, minc=minc_val, diag=100.0, tol=15.0, steep=3.2, dom=3.8)
                out_p = os.path.join(DOCS_IMG_DIR, f"{sid}-{suffix}.png")
                if save_if_changed(rgb, out_p, force=force, dry_run=dry_run, tol_lsb=tol_lsb):
                    updated += 1
                    logs.append(f"  [{'DRY' if dry_run else 'UPD'}] img/{os.path.basename(out_p)}")
                else:
                    skipped += 1
                if keep_all:
                    saved_paths[(sid, suffix)] = out_p
            if mp_progs:
                rgb_x = gles.render_pipeline(mp_progs, inp, scale=6, minc=0.0, diag=0.0, tol=15.0, steep=3.2, dom=3.8)
                out_x = os.path.join(DOCS_IMG_DIR, f"{sid}-xbrz.png")
                if save_if_changed(rgb_x, out_x, force=force, dry_run=dry_run, tol_lsb=tol_lsb):
                    updated += 1
                    logs.append(f"  [{'DRY' if dry_run else 'UPD'}] img/{os.path.basename(out_x)}")
                else:
                    skipped += 1
    finally:
        for p in crisp_progs + mp_progs:
            gles.delete_program(p)
        gles.close()
    return updated, skipped, logs, saved_paths


def main() -> None:
    import concurrent.futures

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--include-xbrz", action="store_true", help="Also render 4-pass plain *-xbrz.png")
    ap.add_argument("--all", action="store_true", help="Also render docs/img/explain/* and docs/sheets/* README visuals")
    ap.add_argument("--force", action="store_true", help="Rewrite PNGs even when pixels are unchanged")
    ap.add_argument("--dry-run", action="store_true", help="Report changes without touching disk")
    ap.add_argument("--exact", action="store_true", help="Treat even 1-LSB float rounding as a change")
    ap.add_argument("--workers", type=int, default=1, help="Parallel worker processes for scene rendering (default: 1)")
    args = ap.parse_args()

    tol_lsb = 0 if args.exact else 1
    crisp_glsl = os.path.join(SHADERS_DIR, "shaders_glsl", "xbrz", "shaders", "xbrz-crisp")
    scenes = sorted(glob.glob(os.path.join(DOCS_IMG_DIR, "*-original.png")))
    if not scenes:
        sys.exit(f"No *-original.png scenes found in {DOCS_IMG_DIR}")

    tmp_mp = None
    mp_glsl = None
    try:
        if args.include_xbrz:
            tmp_mp = tempfile.mkdtemp(prefix="xbrz_docs_mp_")
            subprocess.check_call([sys.executable, os.path.join(TOOLS_DIR, "make-multipass.py"), tmp_mp], stdout=subprocess.DEVNULL)
            mp_glsl = os.path.join(tmp_mp, "glsl-shaders", "xbrz", "shaders", "xbrz-freescale-multipass")

        updated, skipped = 0, 0
        docs_renders: dict[tuple[str, str], Image.Image] = {}

        w = max(1, min(args.workers, len(scenes)))
        if w > 1 and not args.dry_run:
            chunks = [scenes[i::w] for i in range(w)]
            jobs = [(crisp_glsl, mp_glsl, c, args.force, args.dry_run, tol_lsb, args.all) for c in chunks]
            with concurrent.futures.ProcessPoolExecutor(max_workers=w) as ex:
                for u, s, logs, saved in ex.map(_render_docs_chunk, jobs):
                    updated += u
                    skipped += s
                    for ln in logs:
                        print(ln)
                    if args.all:
                        for key, pth in saved.items():
                            docs_renders[key] = Image.open(pth).convert("RGB")
            if args.all:
                gles = HeadlessGLES()
                try:
                    crisp_progs = [
                        gles.compile_program(os.path.join(crisp_glsl, f"xbrz-crisp-{p}.glsl"), "#version 300 es", True)
                        for p in ("point", "pass0", "resolve", "match", "pass1")
                    ]
                    with open(SPEC_PATH, "r", encoding="utf-8") as f:
                        spec = json.load(f)
                    sources = load_or_render_sources(spec, gles, crisp_progs, docs_renders)
                    for p in crisp_progs:
                        gles.delete_program(p)
                finally:
                    gles.close()
        else:
            gles = HeadlessGLES()
            try:
                crisp_progs = [
                    gles.compile_program(os.path.join(crisp_glsl, f"xbrz-crisp-{p}.glsl"), "#version 300 es", True)
                    for p in ("point", "pass0", "resolve", "match", "pass1")
                ]
                mp_progs = (
                    [
                        gles.compile_program(os.path.join(mp_glsl, f"xbrz-freescale-{p}.glsl"), "#version 300 es", True)
                        for p in ("point", "pass0", "resolve", "pass1")
                    ]
                    if mp_glsl
                    else []
                )
                for sp in scenes:
                    sid = os.path.basename(sp).replace("-original.png", "")
                    inp = np.ascontiguousarray(np.array(Image.open(sp).convert("RGBA"), dtype=np.uint8))
                    for minc_val, suffix in ((10.0, "crisp10"), (20.0, "crisp20"), (30.0, "crisp30")):
                        rgb = gles.render_pipeline(crisp_progs, inp, scale=6, minc=minc_val, diag=100.0, tol=15.0, steep=3.2, dom=3.8)
                        if args.all:
                            docs_renders[(sid, suffix)] = Image.fromarray(rgb, "RGB")
                        out_p = os.path.join(DOCS_IMG_DIR, f"{sid}-{suffix}.png")
                        if save_if_changed(rgb, out_p, force=args.force, dry_run=args.dry_run, tol_lsb=tol_lsb):
                            updated += 1
                            print(f"  [{'DRY' if args.dry_run else 'UPD'}] img/{os.path.basename(out_p)}")
                        else:
                            skipped += 1

                    if mp_progs:
                        rgb_x = gles.render_pipeline(mp_progs, inp, scale=6, minc=0.0, diag=0.0, tol=15.0, steep=3.2, dom=3.8)
                        out_x = os.path.join(DOCS_IMG_DIR, f"{sid}-xbrz.png")
                        if save_if_changed(rgb_x, out_x, force=args.force, dry_run=args.dry_run, tol_lsb=tol_lsb):
                            updated += 1
                            print(f"  [{'DRY' if args.dry_run else 'UPD'}] img/{os.path.basename(out_x)}")
                        else:
                            skipped += 1
                if args.all:
                    with open(SPEC_PATH, "r", encoding="utf-8") as f:
                        spec = json.load(f)
                    sources = load_or_render_sources(spec, gles, crisp_progs, docs_renders)
                for p in crisp_progs + mp_progs:
                    gles.delete_program(p)
            finally:
                gles.close()

        if args.all:
            sheet_jobs = [
                (spec["banner"]["output"], render_banner(spec, sources, docs_renders)),
                (spec["hero_triptych"]["output"], render_hero_triptych(spec, sources)),
                (spec["presets"]["output"], render_presets_strip(spec, sources)),
            ]
            for scfg in spec["strips"]:
                sheet_jobs.append((scfg["output"], render_strip(scfg, spec, sources)))
            for tcfg in spec["console_tiles"]:
                sheet_jobs.append((tcfg["output"], render_console_tile(tcfg, spec, sources)))

            for fname, arr in sheet_jobs:
                out_p = os.path.join(SHEETS_DIR, fname)
                if save_if_changed(arr, out_p, force=args.force, dry_run=args.dry_run, tol_lsb=tol_lsb):
                    updated += 1
                    print(f"  [{'DRY' if args.dry_run else 'UPD'}] sheets/{fname}")
                else:
                    skipped += 1

            for ecfg in spec["explain"]:
                arr = render_explain_diagram(ecfg, docs_renders)
                out_p = os.path.join(EXPLAIN_DIR, ecfg["output"])
                if save_if_changed(arr, out_p, force=args.force, dry_run=args.dry_run, tol_lsb=tol_lsb):
                    updated += 1
                    print(f"  [{'DRY' if args.dry_run else 'UPD'}] img/explain/{ecfg['output']}")
                else:
                    skipped += 1

        print(f"[render-docs] Done: {updated} updated, {skipped} unchanged (skipped).")
    finally:
        if tmp_mp:
            shutil.rmtree(tmp_mp, ignore_errors=True)


if __name__ == "__main__":
    main()
