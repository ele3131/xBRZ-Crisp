#!/usr/bin/env python3
"""Build a self-contained offline Studio v4 HTML comparator (Desktop + Mobile).

Usage examples (run from repo root):
  # Compare current working-tree shaders against git HEAD (default):
  python3 tools/studio/build_studio.py --out build/xbrz_crisp_studio.html

  # Build a Desktop App-safe (< 900 KB) diff-only comparator against a git tag:
  python3 tools/studio/build_studio.py --baseline-ref 4.1 --preset desktop --out build/v42_desktop.studio.html

  # Compare against pre-rendered 6x baseline PNGs in a cache directory:
  python3 tools/studio/build_studio.py --baseline-dir /path/to/baseline_6x --out build/studio.html
"""
import argparse
import base64
import glob
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

os.environ.setdefault("LP_NATIVE_VECTOR_WIDTH", "128")

STUDIO_DIR = Path(__file__).resolve().parent
REPO_ROOT = STUDIO_DIR.parents[1]
TOOLS_DIR = REPO_ROOT / "tools"
TEMPLATE_PATH = STUDIO_DIR / "studio_template.html"
DEFAULT_SUITE_DIR = Path(os.environ.get("XBRZ_SUITE_DIR", str(Path.home() / ".cache" / "xbrz-crisp" / "suite50")))

sys.path.insert(0, str(TOOLS_DIR))
import numpy as np
from PIL import Image
from verify import HeadlessGLES

SHADER_REL_PATHS = [
    "shaders/shaders_glsl/xbrz/shaders/xbrz-crisp/xbrz-crisp-point.glsl",
    "shaders/shaders_glsl/xbrz/shaders/xbrz-crisp/xbrz-crisp-pass0.glsl",
    "shaders/shaders_glsl/xbrz/shaders/xbrz-crisp/xbrz-crisp-resolve.glsl",
    "shaders/shaders_glsl/xbrz/shaders/xbrz-crisp/xbrz-crisp-match.glsl",
    "shaders/shaders_glsl/xbrz/shaders/xbrz-crisp/xbrz-crisp-pass1.glsl",
]

PLACEHOLDER = "/*__STUDIO_DATA__*/[]"
META_PLACEHOLDER = "/*__STUDIO_META__*/{}"

# Curated Golden Sun + multi-console showcase items.
# Items whose sceneId is not present (e.g., optional --extra-dir scenes) are skipped cleanly.
DEFAULT_ITEMS = [
    # ---- Golden Sun dedicated section ----
    dict(id="gs1_isaac_vil", cat="gs", sceneId="docs_gs_village",
         title="GS1 Vila — Isaac", badge="R26 + b1",
         note="Pescoço, gola e peito do Isaac sem lascas órfãs, preservando olhos e diagonais.",
         box=(108, 68, 136, 96),
         autoSpots=[{"x": 124, "y": 82, "label": "Pescoço"}, {"x": 123, "y": 83, "label": "Gola"}, {"x": 122, "y": 84, "label": "Peito"}]),
    dict(id="gs1_fireball", cat="gs", sceneId="docs_gs_menu",
         title="GS1 Menu — Fireball", badge="Regra 49",
         note="Remove a mordida azul no anel amarelo do ícone Fireball.",
         box=(116, 30, 146, 52),
         autoSpots=[{"x": 125, "y": 37, "label": "Fireball R49"}]),
    dict(id="gs1_hud_hp", cat="gs", sceneId="docs_gs_battle",
         title="GS1 Batalha — HUD HP/PP", badge="Regra 44",
         note="Remove as lascas azuis na sombra preta dentro de todos os 'HP'.",
         box=(138, 0, 238, 28),
         autoSpots=[{"x": 147, "y": 12, "label": "HP Isaac"}, {"x": 195, "y": 12, "label": "HP Garet"}]),
    dict(id="gs1_slimes", cat="gs", sceneId="docs_gs_battle",
         title="GS1 Batalha — Slimes", badge="Sprites",
         note="Verifica contornos, olhos e focinhos dos 3 Slimes.",
         box=(42, 95, 96, 128),
         autoSpots=[{"x": 52, "y": 108, "label": "Olho Slime"}, {"x": 75, "y": 105, "label": "Slime Meio"}]),
    dict(id="gs2_hud_jenna", cat="gs", sceneId="docs_gs2_battle",
         title="GS2 Batalha — HUD Jenna", badge="Regra 44",
         note="Remove lascas azuis no 'H'/'6' e a lasca cinza na barra #0000FF sob o '4'.",
         box=(138, 0, 238, 28),
         autoSpots=[{"x": 147, "y": 12, "label": "HP Jenna"}, {"x": 169, "y": 12, "label": "'6' R44"}, {"x": 169, "y": 23, "label": "Barra PP"}]),
    dict(id="gs2_jenna_sheba", cat="gs", sceneId="docs_gs2_battle",
         title="GS2 Batalha — Jenna & Sheba", badge="Sprites",
         note="Verifica capas, cabelos e contornos da Jenna e da Sheba.",
         box=(156, 78, 212, 122),
         autoSpots=[{"x": 166, "y": 96, "label": "Capa Jenna"}, {"x": 188, "y": 91, "label": "Cabelo Sheba"}]),
    dict(id="gs2_felix_cape", cat="gs", sceneId="docs_gs2_battle",
         title="GS2 Batalha — Capa do Felix", badge="Contorno",
         note="Inspeção da bainha e dobras azuis da capa do Felix.",
         box=(122, 94, 158, 126),
         autoSpots=[{"x": 132, "y": 112, "label": "Bainha Felix"}]),
    dict(id="gs2_jp_jenna", cat="gs", sceneId="s50_gba_gs2_jp_snap",
         title="GS2 Overworld JP — Jenna", badge="Overworld",
         note="Cabelo e vestido roxo da Jenna no overworld de The Lost Age.",
         box=(116, 98, 160, 142),
         autoSpots=[{"x": 134, "y": 127, "label": "Vestido Roxo"}, {"x": 135, "y": 118, "label": "Cabelo Jenna"}]),
    dict(id="gs1_camelot", cat="gs", sceneId="s50_gba_gs1_title",
         title="GS1 Título — 'CAMELOT'", badge="Regra 10",
         note="Curva interna do 'C' em 'CAMELOT' limpa sem dente branco quadrado.",
         box=(138, 136, 214, 158),
         autoSpots=[{"x": 151, "y": 147, "label": "'C' CAMELOT"}]),
    dict(id="gs2_wheel", cat="gs", sceneId="s50_gba_gs2_title",
         title="GS2 Título — Roda Dourada", badge="Título",
         note="Inspeção da roda radial dourada e tipografia de The Lost Age.",
         box=(6, 8, 96, 96),
         autoSpots=[{"x": 71, "y": 29, "label": "Roda (71,29)"}]),
    dict(id="gs1_village_full", cat="gs", sceneId="docs_gs_village",
         title="GS1 Vila — Cena Completa", badge="240×160",
         note="Cena completa da vila de Vale (grama, sprites, casa, ponte).",
         box=None,
         autoSpots=[{"x": 14, "y": 115, "label": "Rampa 2:1→45° (14,115)"}, {"x": 14, "y": 110, "label": "Rosa (14,110)"}, {"x": 15, "y": 108, "label": "Cinza (15,108)"}, {"x": 12, "y": 112, "label": "Azul (12,112)"}]),
    dict(id="gs1_menu_full", cat="gs", sceneId="docs_gs_menu",
         title="GS1 Menu — Cena Completa", badge="240×160",
         note="Menu Psinergia completo: ícones, mini-sprites e sombras suaves das letras.",
         box=None,
         autoSpots=[{"x": 125, "y": 37, "label": "Fireball"}]),
    dict(id="gs1_battle_full", cat="gs", sceneId="docs_gs_battle",
         title="GS1 Batalha — Cena Completa", badge="240×160",
         note="Batalha completa de Golden Sun 1 (HUD, Slimes, Garet, Isaac, árvores).",
         box=None,
         autoSpots=[{"x": 147, "y": 12, "label": "HP Isaac"}, {"x": 52, "y": 108, "label": "Olho Slime"}]),
    dict(id="gs2_battle_full", cat="gs", sceneId="docs_gs2_battle",
         title="GS2 Batalha — Cena Completa", badge="240×160",
         note="Batalha completa de Golden Sun 2 (HUD, Wild Wolf, Felix, Jenna, Sheba).",
         box=None,
         autoSpots=[{"x": 147, "y": 12, "label": "HP Jenna"}, {"x": 169, "y": 23, "label": "Barra PP"}]),

    # ---- Multi-console regression checks ----
    dict(id="mc_link", cat="other", sceneId="docs_mc_eu",
         title="Zelda: Minish Cap — Link", badge="GBA",
         note="Sobrancelha (Regra 10) e rosto do Link sem regressão.",
         box=(102, 48, 142, 88),
         autoSpots=[{"x": 122, "y": 68, "label": "Sobrancelha Link"}]),
    dict(id="kof98_gauge", cat="other", sceneId="micro_kof98_gauge",
         title="KOF '98 — Gauge 50% Mesh", badge="Neo Geo",
         note="Malha 50% (Regra 46) 100% quadrada até bordas e cantos.",
         box=None, autoSpots=[]),
    dict(id="cv_aria_hud", cat="other", sceneId="docs_cv_aria",
         title="Castlevania: Aria of Sorrow", badge="GBA",
         note="Moldura dourada, barras retas e '280' suave.",
         box=(0, 0, 112, 34), autoSpots=[{"x": 26, "y": 18, "label": "Canto (26,18)"}]),
    dict(id="ffta_boy", cat="other", sceneId="docs_ffta",
         title="Final Fantasy Tactics Advance", badge="GBA",
         note="Ombro do garoto (Regra 49) e contornos sem regressão.",
         box=(80, 60, 165, 130), autoSpots=[]),
    dict(id="tales_stone", cat="other", sceneId="docs_tales",
         title="Tales of Phantasia — Pedras", badge="GBA",
         note="Textura de pedras e rosto do Cless.",
         box=(90, 56, 174, 112), autoSpots=[]),
    dict(id="dbz_title", cat="other", sceneId="docs_dbz_title",
         title="DBZ: Buu's Fury — Título", badge="GBA",
         note="Cabelo e traços finos em alta densidade.",
         box=(4, 48, 84, 108), autoSpots=[{"x": 59, "y": 89, "label": "Diag (59,89)"}]),
    dict(id="fire_emblem", cat="other", sceneId="s50_gba_fire_emblem",
         title="Fire Emblem — Mapa & Sprites", badge="GBA",
         note="Cavalaria, lança diagonal e arcos de pedra.",
         box=(128, 52, 200, 112), autoSpots=[]),
    dict(id="md_ps4", cat="other", sceneId="s50_md_ps4",
         title="Phantasy Star IV — Texturas", badge="Mega Drive",
         note="Pedras e folhagem de alta complexidade.",
         box=(228, 4, 304, 60), autoSpots=[]),
]


def resolve_extra_dir(extra_dir: str | None, no_extra: bool = False) -> str | None:
    if no_extra:
        return None
    if extra_dir:
        return extra_dir
    if DEFAULT_SUITE_DIR.is_dir():
        return str(DEFAULT_SUITE_DIR)
    return None


def discover_scenes(extra_dir: str | None) -> dict[str, Path]:
    scenes: dict[str, Path] = {}
    for p in sorted(glob.glob(str(REPO_ROOT / "docs/img/*-original.png"))):
        name = "docs_" + Path(p).name.replace("-original.png", "")
        scenes[name] = Path(p)
    for p in sorted(glob.glob(str(REPO_ROOT / "tools/assets/micro/*-original.png"))):
        name = "micro_" + Path(p).name.replace("-original.png", "")
        scenes[name] = Path(p)
    if extra_dir:
        for p in sorted(glob.glob(str(Path(extra_dir) / "*.png"))):
            name = "s50_" + Path(p).stem
            scenes[name] = Path(p)
    return scenes


def shader_sources_hash(sources: list[str], salt: str = "crisp20") -> str:
    h = hashlib.sha256(salt.encode("utf-8"))
    for s in sources:
        h.update(b"\0")
        h.update(s.encode("utf-8"))
    return h.hexdigest()[:12]


def encode_webp_uri(rgb: np.ndarray) -> str:
    buf = io.BytesIO()
    m = 6 if (rgb.shape[0] * rgb.shape[1] >= 120_000) else 4
    Image.fromarray(rgb, "RGB").save(buf, format="WEBP", lossless=True, quality=100, method=m)
    return "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def encode_webp_rgba_uri(rgba: np.ndarray) -> str:
    buf = io.BytesIO()
    m = 6 if (rgba.shape[0] * rgba.shape[1] >= 80_000) else 4
    Image.fromarray(rgba, "RGBA").save(buf, format="WEBP", lossless=True, quality=100, method=m)
    return "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def render_crisp(gles: HeadlessGLES, progs, rgba: np.ndarray) -> np.ndarray:
    return gles.render_pipeline(progs, np.ascontiguousarray(rgba), scale=6, minc=20.0, diag=100.0, tol=15.0, steep=3.2, dom=3.8)


def render_xbrz(gles: HeadlessGLES, progs, rgba: np.ndarray) -> np.ndarray:
    return gles.render_pipeline(progs, np.ascontiguousarray(rgba), scale=6, minc=0.0, diag=0.0, tol=30.0, steep=2.4, dom=3.6)


def validate_html_js(html_text: str) -> None:
    if not shutil.which("node"):
        return
    scripts = re.findall(r"<script(?:\s[^>]*)?>(.*?)</script>", html_text, flags=re.S)
    with tempfile.TemporaryDirectory() as td:
        for idx, body in enumerate(scripts):
            js_path = Path(td) / f"script_{idx}.js"
            js_path.write_text(body, encoding="utf-8")
            subprocess.run(["node", "--check", str(js_path)], check=True)


def render_html_string(template_text: str, payload: list[dict], meta: dict) -> str:
    data_json = "[\n" + ",\n".join(json.dumps(it, separators=(",", ":")) for it in payload) + "\n]"
    meta_json = json.dumps(meta, separators=(",", ":"), ensure_ascii=False)
    if PLACEHOLDER not in template_text:
        raise RuntimeError(f"Placeholder {PLACEHOLDER!r} not found in template")
    html = template_text.replace(PLACEHOLDER, data_json, 1)
    if META_PLACEHOLDER in html:
        html = html.replace(META_PLACEHOLDER, meta_json, 1)
    return html


def assemble_html(template_path: Path, payload: list[dict], meta: dict, out_path: Path, budget_kb: int | None = None) -> tuple[str, list[dict]]:
    tpl = template_path.read_text(encoding="utf-8")
    kept = list(payload)
    html = render_html_string(tpl, kept, meta)
    if budget_kb and budget_kb > 0:
        limit = budget_kb * 1024
        while len(html.encode("utf-8")) > limit and len(kept) > 1:
            # Prefer trimming auto-filled items, then full-frame duplicates, then lowest-diff non-GS items
            def drop_rank(it: dict) -> tuple[int, int, int]:
                if it["id"].startswith("auto_"):
                    tier = 0
                elif it["id"].endswith("_full"):
                    tier = 1
                elif it["cat"] != "gs":
                    tier = 2
                else:
                    tier = 3
                return (tier, it["dpx"], -it["w1"] * it["h1"])
            victim = min(kept, key=drop_rank)
            kept.remove(victim)
            print(f"  [budget] dropped {victim['id']:18s} (diff={victim['dpx']} px) to fit <= {budget_kb} KB")
            html = render_html_string(tpl, kept, meta)
    validate_html_js(html)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html, encoding="utf-8")
    return html, kept


def main() -> None:
    ap = argparse.ArgumentParser(description="Build offline Studio v4 HTML comparator.")
    ap.add_argument("--baseline-ref", default="HEAD", help="Git ref for 'Antes' baseline shaders (default: HEAD)")
    ap.add_argument("--baseline-dir", default=None, help="Optional directory of cached 6x baseline PNGs (<sceneId>.png)")
    ap.add_argument("--baseline-label", default=None, help="Short label for baseline layer (default: baseline-ref or 'Antes')")
    ap.add_argument("--cand-label", default="Novo", help="Short label for candidate layer (default: 'Novo')")
    ap.add_argument("--title", default=None, help="Custom page & header title")
    ap.add_argument("--extra-dir", default=None, help="Optional directory of extra native 1x PNG scenes (auto-uses ~/.cache/xbrz-crisp/suite50 if present)")
    ap.add_argument("--no-extra", action="store_true", help="Disable auto-discovery of extra suite50 scenes")
    ap.add_argument("--cache-dir", default=str(REPO_ROOT / "build" / "cache"), help="Content-addressed 6x PNG render cache directory ('' to disable)")
    ap.add_argument("--template", default=str(TEMPLATE_PATH), help="Path to studio_template.html")
    ap.add_argument("--data-out", default=None, help="Optional path to save raw JSON data payload")
    ap.add_argument("--preset", choices=("compact", "desktop", "full"), default=None, help="Shortcut presets: desktop (--only-diffs --compact --desktop-budget 900), compact, full")
    ap.add_argument("--only-diffs", action="store_true", help="Hide 0-px items and replace with other scenes that have diffs")
    ap.add_argument("--auto-fill", type=int, default=4, help="Max extra diff-bearing scenes to auto-add with --only-diffs (default: 4)")
    ap.add_argument("--compact", action="store_true", default=True, help="Keep HTML compact by focusing full-screen scenes onto 100x80 diff crops (default: on)")
    ap.add_argument("--full-frames", action="store_true", help="Keep full 240x160 full-screen scenes instead of 100x80 diff crops")
    ap.add_argument("--desktop-budget", type=int, default=None, help="Enforce max output HTML size in KB (e.g. 900 for Desktop App preview)")
    ap.add_argument("--out", default=str(REPO_ROOT / "build/xbrz_crisp_studio.html"), help="Output HTML path")
    args = ap.parse_args()

    if args.preset == "desktop":
        args.only_diffs = True
        args.compact = True
        if args.desktop_budget is None:
            args.desktop_budget = 900
    elif args.preset == "full":
        args.full_frames = True
    elif args.preset == "compact":
        args.compact = True

    if args.full_frames:
        args.compact = False

    extra_dir = resolve_extra_dir(args.extra_dir, no_extra=args.no_extra)
    scenes = discover_scenes(extra_dir)
    active_items = [it for it in DEFAULT_ITEMS if it["sceneId"] in scenes]
    if not active_items:
        raise RuntimeError("No matching scenes found.")

    cache_root = Path(args.cache_dir) if args.cache_dir else None

    new_srcs = [(REPO_ROOT / rel).read_text(encoding="utf-8") for rel in SHADER_REL_PATHS]
    new_hash = shader_sources_hash(new_srcs, "crisp20")

    old_srcs = None
    old_hash = None
    if not args.baseline_dir:
        old_srcs = [
            subprocess.check_output(["git", "show", f"{args.baseline_ref}:{rel}"], cwd=str(REPO_ROOT)).decode("utf-8")
            for rel in SHADER_REL_PATHS
        ]
        old_hash = shader_sources_hash(old_srcs, "crisp20")

    gles = HeadlessGLES()
    new_progs = None
    old_progs = None
    plain_progs = None
    plain_hash = None
    tmp_dir_ctx = tempfile.TemporaryDirectory(prefix="xbrz_studio_")
    td = Path(tmp_dir_ctx.name)

    def ensure_new_progs():
        nonlocal new_progs
        if new_progs is None:
            new_progs = [gles.compile_program(str(REPO_ROOT / rel), "#version 300 es") for rel in SHADER_REL_PATHS]
        return new_progs

    def ensure_old_progs():
        nonlocal old_progs
        if old_progs is None:
            assert old_srcs is not None
            old_progs = []
            for i, src in enumerate(old_srcs):
                sp = td / f"old_{i}.glsl"
                sp.write_text(src, encoding="utf-8")
                old_progs.append(gles.compile_program(str(sp), "#version 300 es"))
        return old_progs

    def ensure_plain_progs():
        nonlocal plain_progs, plain_hash
        if plain_progs is None:
            mp_dir = td / "mp"
            subprocess.check_call([sys.executable, str(TOOLS_DIR / "make-multipass.py"), str(mp_dir)], stdout=subprocess.DEVNULL)
            mp_glsl = mp_dir / "glsl-shaders" / "xbrz" / "shaders" / "xbrz-freescale-multipass"
            mp_paths = [mp_glsl / f"xbrz-freescale-{p}.glsl" for p in ("point", "pass0", "resolve", "pass1")]
            plain_hash = "plain_" + shader_sources_hash([p.read_text(encoding="utf-8") for p in mp_paths], "xbrz19")
            plain_progs = [gles.compile_program(str(p), "#version 300 es", True) for p in mp_paths]
        return plain_progs, plain_hash

    def cached_render(hash_key: str | None, scene_id: str, render_fn) -> np.ndarray:
        if cache_root and hash_key:
            cp = cache_root / hash_key / f"{scene_id}.png"
            if cp.is_file():
                return np.array(Image.open(cp).convert("RGB"), dtype=np.uint8)
            rgb = render_fn()
            cp.parent.mkdir(parents=True, exist_ok=True)
            Image.fromarray(rgb, "RGB").save(cp, compress_level=1)
            return rgb
        return render_fn()

    def load_or_render_xbrz(scene_id: str, rgba: np.ndarray) -> np.ndarray:
        src_p = scenes[scene_id]
        h1, w1 = rgba.shape[:2]
        if src_p.name.endswith("-original.png"):
            cpp_p = src_p.with_name(src_p.name.replace("-original.png", "-xbrzcpp.png"))
            if cpp_p.is_file():
                arr = np.array(Image.open(cpp_p).convert("RGB"), dtype=np.uint8)
                if arr.shape == (h1 * 6, w1 * 6, 3):
                    return arr
        p_progs, p_hash = ensure_plain_progs()
        return cached_render(p_hash, scene_id, lambda: render_xbrz(gles, p_progs, rgba))

    try:
        cache: dict[str, tuple[np.ndarray, np.ndarray | None, np.ndarray, np.ndarray]] = {}

        def get_renders(scene_id: str, need_xbrz: bool = True):
            if scene_id not in cache:
                rgba = np.array(Image.open(scenes[scene_id]).convert("RGBA"), dtype=np.uint8)
                orig = rgba[:, :, :3]
                new_c = cached_render(new_hash, scene_id, lambda: render_crisp(gles, ensure_new_progs(), rgba))
                xbrz = load_or_render_xbrz(scene_id, rgba) if need_xbrz else None
                if args.baseline_dir:
                    old_c = np.array(Image.open(Path(args.baseline_dir) / f"{scene_id}.png").convert("RGB"), dtype=np.uint8)
                else:
                    old_c = cached_render(old_hash, scene_id, lambda: render_crisp(gles, ensure_old_progs(), rgba))
                cache[scene_id] = (orig, xbrz, old_c, new_c)
            elif need_xbrz and cache[scene_id][1] is None:
                orig, _, old_c, new_c = cache[scene_id]
                rgba = np.array(Image.open(scenes[scene_id]).convert("RGBA"), dtype=np.uint8)
                cache[scene_id] = (orig, load_or_render_xbrz(scene_id, rgba), old_c, new_c)
            return cache[scene_id]

        def build_item(it: dict) -> dict | None:
            orig, xbrz, old_c, new_c = get_renders(it["sceneId"], need_xbrz=True)
            assert xbrz is not None
            h1, w1 = orig.shape[:2]
            badge = it["badge"]
            if it["box"] is None:
                if args.compact and w1 * h1 > 100 * 80:
                    dm_all = np.any(old_c != new_c, axis=2)
                    ys, xs = np.where(dm_all)
                    if len(xs) > 0:
                        cx = int(np.median(xs) // 6)
                        cy = int(np.median(ys) // 6)
                        cw, ch = min(100, w1), min(80, h1)
                        x0 = max(0, min(w1 - cw, cx - cw // 2))
                        y0 = max(0, min(h1 - ch, cy - ch // 2))
                        x1, y1 = x0 + cw, y0 + ch
                        badge = f"{cw}×{ch}"
                    else:
                        x0, y0, x1, y1 = 0, 0, w1, h1
                else:
                    x0, y0, x1, y1 = 0, 0, w1, h1
            else:
                x0, y0, x1, y1 = max(0, it["box"][0]), max(0, it["box"][1]), min(w1, it["box"][2]), min(h1, it["box"][3])
            oc = old_c[y0 * 6 : y1 * 6, x0 * 6 : x1 * 6]
            nc = new_c[y0 * 6 : y1 * 6, x0 * 6 : x1 * 6]
            xc = xbrz[y0 * 6 : y1 * 6, x0 * 6 : x1 * 6]
            diff_mask = np.any(oc != nc, axis=2)
            dpx = int(diff_mask.sum())
            if args.only_diffs and dpx == 0:
                print(f"  [skip ] {it['id']:18s} ({x1-x0:3d}x{y1-y0:3d}) diff=    0 px")
                return None

            def attach_layer(target_key: str, patch_key: str, arr: np.ndarray, mask: np.ndarray) -> None:
                n_diff = int(mask.sum())
                if n_diff == 0:
                    return
                patch = np.zeros((arr.shape[0], arr.shape[1], 4), dtype=np.uint8)
                patch[mask, :3] = arr[mask]
                patch[mask, 3] = 255
                patch_uri = encode_webp_rgba_uri(patch)
                if n_diff * 50 < arr.shape[0] * arr.shape[1]:
                    item_obj[patch_key] = patch_uri
                else:
                    full_uri = encode_webp_uri(arr)
                    if len(patch_uri) < len(full_uri):
                        item_obj[patch_key] = patch_uri
                    else:
                        item_obj[target_key] = full_uri

            spots = [s for s in it["autoSpots"] if x0 <= s["x"] < x1 and y0 <= s["y"] < y1]
            item_obj = {
                "id": it["id"],
                "cat": it["cat"],
                "sceneId": it["sceneId"],
                "title": it["title"],
                "badge": badge,
                "note": it["note"],
                "ox": x0,
                "oy": y0,
                "w1": x1 - x0,
                "h1": y1 - y0,
                "dpx": dpx,
                "autoSpots": spots,
                "orig": encode_webp_uri(orig[y0:y1, x0:x1]),
                "new": encode_webp_uri(nc),
            }
            attach_layer("old", "oldPatch", oc, diff_mask)
            attach_layer("xbrz", "xbrzPatch", xc, np.any(xc != nc, axis=2))
            print(f"  [{it['cat']:5s}] {it['id']:18s} ({x1-x0:3d}x{y1-y0:3d}) diff={dpx:5d} px")
            return item_obj

        payload = []
        shown_scenes: set[str] = set()
        for it in active_items:
            obj = build_item(it)
            if obj is not None:
                payload.append(obj)
                shown_scenes.add(it["sceneId"])

        if args.only_diffs and args.auto_fill > 0:
            extra_cands = []
            for sid in sorted(scenes.keys()):
                if sid in shown_scenes:
                    continue
                orig, _, old_c, new_c = get_renders(sid, need_xbrz=False)
                diff6 = np.any(old_c != new_c, axis=2)
                dpx_all = int(diff6.sum())
                if dpx_all == 0:
                    continue
                h1, w1 = orig.shape[:2]
                diff1 = diff6.reshape(h1, 6, w1, 6).any(axis=(1, 3))
                ys, xs = np.where(diff1)
                best_x, best_y, best_cnt = int(xs[0]), int(ys[0]), -1
                for tx, ty in zip(xs.tolist(), ys.tolist()):
                    cnt = int(((np.abs(xs - tx) <= 40) & (np.abs(ys - ty) <= 30)).sum())
                    if cnt > best_cnt:
                        best_cnt, best_x, best_y = cnt, tx, ty
                half_w, half_h = min(40, w1 // 2), min(30, h1 // 2)
                x0 = max(0, min(w1 - 2 * half_w, best_x - half_w))
                y0 = max(0, min(h1 - 2 * half_h, best_y - half_h))
                x1 = min(w1, x0 + max(2 * half_w, min(w1, 80)))
                y1 = min(h1, y0 + max(2 * half_h, min(h1, 60)))
                box_dpx = int(diff6[y0 * 6 : y1 * 6, x0 * 6 : x1 * 6].sum())
                in_box = [(int(tx), int(ty)) for tx, ty in zip(xs.tolist(), ys.tolist()) if x0 <= tx < x1 and y0 <= ty < y1]
                auto_spots = []
                for tx, ty in in_box:
                    if all(abs(tx - s["x"]) + abs(ty - s["y"]) > 8 for s in auto_spots):
                        auto_spots.append({"x": tx, "y": ty, "label": f"Diff ({tx},{ty})"})
                        if len(auto_spots) >= 3:
                            break
                extra_cands.append((box_dpx, sid, (x0, y0, x1, y1), auto_spots))

            extra_cands.sort(key=lambda t: (-t[0], t[1]))
            for _, sid, box, auto_spots in extra_cands[: args.auto_fill]:
                pretty = sid.replace("s50_", "").replace("docs_", "").replace("micro_", "").replace("_", " ").title()
                badge = "Auto Diff"
                cat = "gs" if ("gs1" in sid or "gs2" in sid or "gs_" in sid) else "other"
                obj = build_item(dict(
                    id=f"auto_{sid}",
                    cat=cat,
                    sceneId=sid,
                    title=pretty,
                    badge=badge,
                    note=f"Recorte automático focado na maior concentração de diffs em {sid}.",
                    box=box,
                    autoSpots=auto_spots,
                ))
                if obj is not None:
                    payload.append(obj)
                    shown_scenes.add(sid)
    finally:
        for group in (new_progs, old_progs, plain_progs):
            if group:
                for p in group:
                    gles.delete_program(p)
        gles.close()
        tmp_dir_ctx.cleanup()

    old_short = args.baseline_label or (args.baseline_ref if not args.baseline_dir else "Antes")
    new_short = args.cand_label
    meta = {
        "title": args.title or f"xBRZ Crisp Studio ({old_short} → {new_short})",
        "oldShort": old_short,
        "oldLabel": f"Crisp ({old_short})",
        "newShort": new_short,
        "newLabel": f"Crisp ({new_short})",
        "xbrzShort": "xBRZ 1.9",
        "xbrzLabel": "xBRZ 1.9",
    }

    out_path = Path(args.out)
    _, kept = assemble_html(Path(args.template), payload, meta, out_path, budget_kb=args.desktop_budget)
    if args.data_out:
        data_json = "[\n" + ",\n".join(json.dumps(it, separators=(",", ":")) for it in kept) + "\n]"
        Path(args.data_out).write_text(data_json, encoding="utf-8")
    print(f"Wrote {out_path} ({out_path.stat().st_size / 1024:.1f} KB, {len(kept)} items) — node --check OK!")


if __name__ == "__main__":
    main()
