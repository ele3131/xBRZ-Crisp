#!/usr/bin/env python3
"""Build a self-contained offline Studio v4 HTML comparator (Desktop + Mobile).

Usage examples (run from repo root):
  # Compare current working-tree shaders against git HEAD (default):
  python3 tools/studio/build_studio.py --out build/xbrz_crisp_studio.html

  # Compare against a specific git tag/commit and include extra native PNG scenes:
  python3 tools/studio/build_studio.py --baseline-ref 3.6 --extra-dir /path/to/suite50 --out /path/to/studio.html

  # Compare against pre-rendered 6x baseline PNGs in a cache directory:
  python3 tools/studio/build_studio.py --baseline-dir /path/to/baseline_6x --extra-dir /path/to/suite50 --out /path/to/studio.html
"""
import argparse
import base64
import glob
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
         autoSpots=[{"x": 124, "y": 82, "label": "Isaac"}, {"x": 122, "y": 84, "label": "Peito"}]),
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
         box=(0, 0, 112, 34), autoSpots=[]),
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
         box=(4, 48, 84, 108), autoSpots=[]),
    dict(id="fire_emblem", cat="other", sceneId="s50_gba_fire_emblem",
         title="Fire Emblem — Mapa & Sprites", badge="GBA",
         note="Cavalaria, lança diagonal e arcos de pedra.",
         box=(128, 52, 200, 112), autoSpots=[]),
    dict(id="md_ps4", cat="other", sceneId="s50_md_ps4",
         title="Phantasy Star IV — Texturas", badge="Mega Drive",
         note="Pedras e folhagem de alta complexidade.",
         box=(228, 4, 304, 60), autoSpots=[]),
]


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


def encode_webp_uri(rgb: np.ndarray) -> str:
    buf = io.BytesIO()
    Image.fromarray(rgb, "RGB").save(buf, format="WEBP", lossless=True, quality=100, method=4)
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


def assemble_html(template_path: Path, data_json: str, out_path: Path) -> None:
    tpl = template_path.read_text(encoding="utf-8")
    if PLACEHOLDER not in tpl:
        raise RuntimeError(f"Placeholder {PLACEHOLDER!r} not found in {template_path}")
    html = tpl.replace(PLACEHOLDER, data_json, 1)
    validate_html_js(html)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html, encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description="Build offline Studio v4 HTML comparator.")
    ap.add_argument("--baseline-ref", default="HEAD", help="Git ref for 'Antes' baseline shaders (default: HEAD)")
    ap.add_argument("--baseline-dir", default=None, help="Optional directory of cached 6x baseline PNGs (<sceneId>.png)")
    ap.add_argument("--extra-dir", default=None, help="Optional directory of extra native 1x PNG scenes")
    ap.add_argument("--template", default=str(TEMPLATE_PATH), help="Path to studio_template.html")
    ap.add_argument("--data-out", default=None, help="Optional path to save raw JSON data payload")
    ap.add_argument("--out", default=str(REPO_ROOT / "build/xbrz_crisp_studio.html"), help="Output HTML path")
    args = ap.parse_args()

    scenes = discover_scenes(args.extra_dir)
    active_items = [it for it in DEFAULT_ITEMS if it["sceneId"] in scenes]
    if not active_items:
        raise RuntimeError("No matching scenes found.")

    gles = HeadlessGLES()
    new_progs = [gles.compile_program(str(REPO_ROOT / rel), "#version 300 es") for rel in SHADER_REL_PATHS]

    tmp_dir_ctx = tempfile.TemporaryDirectory() if not args.baseline_dir else None
    try:
        old_progs = None
        if not args.baseline_dir:
            td = Path(tmp_dir_ctx.name)
            old_progs = []
            for i, rel in enumerate(SHADER_REL_PATHS):
                src = subprocess.check_output(["git", "show", f"{args.baseline_ref}:{rel}"], cwd=str(REPO_ROOT)).decode("utf-8")
                sp = td / f"old_{i}.glsl"
                sp.write_text(src, encoding="utf-8")
                old_progs.append(gles.compile_program(str(sp), "#version 300 es"))

        cache: dict[str, tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]] = {}

        def get_renders(scene_id: str):
            if scene_id not in cache:
                rgba = np.array(Image.open(scenes[scene_id]).convert("RGBA"), dtype=np.uint8)
                orig = rgba[:, :, :3]
                new_c = render_crisp(gles, new_progs, rgba)
                xbrz = render_xbrz(gles, new_progs, rgba)
                if args.baseline_dir:
                    old_c = np.array(Image.open(Path(args.baseline_dir) / f"{scene_id}.png").convert("RGB"), dtype=np.uint8)
                else:
                    old_c = render_crisp(gles, old_progs, rgba)
                cache[scene_id] = (orig, xbrz, old_c, new_c)
            return cache[scene_id]

        payload = []
        for it in active_items:
            orig, xbrz, old_c, new_c = get_renders(it["sceneId"])
            h1, w1 = orig.shape[:2]
            if it["box"] is None:
                x0, y0, x1, y1 = 0, 0, w1, h1
            else:
                x0, y0, x1, y1 = max(0, it["box"][0]), max(0, it["box"][1]), min(w1, it["box"][2]), min(h1, it["box"][3])
            oc = old_c[y0 * 6 : y1 * 6, x0 * 6 : x1 * 6]
            nc = new_c[y0 * 6 : y1 * 6, x0 * 6 : x1 * 6]
            xc = xbrz[y0 * 6 : y1 * 6, x0 * 6 : x1 * 6]
            diff_mask = np.any(oc != nc, axis=2)
            dpx = int(diff_mask.sum())
            diff_vis = (nc.astype(np.float32) * 0.45).astype(np.uint8)
            diff_vis[diff_mask] = (255, 55, 130)

            spots = [s for s in it["autoSpots"] if x0 <= s["x"] < x1 and y0 <= s["y"] < y1]
            payload.append({
                "id": it["id"],
                "cat": it["cat"],
                "sceneId": it["sceneId"],
                "title": it["title"],
                "badge": it["badge"],
                "note": it["note"],
                "ox": x0,
                "oy": y0,
                "w1": x1 - x0,
                "h1": y1 - y0,
                "dpx": dpx,
                "autoSpots": spots,
                "orig": encode_webp_uri(orig[y0:y1, x0:x1]),
                "xbrz": encode_webp_uri(xc),
                "old": encode_webp_uri(oc),
                "new": encode_webp_uri(nc),
                "diff": encode_webp_uri(diff_vis),
            })
            print(f"  [{it['cat']:5s}] {it['id']:18s} ({x1-x0:3d}x{y1-y0:3d}) diff={dpx:5d} px")
    finally:
        gles.close()
        if tmp_dir_ctx is not None:
            tmp_dir_ctx.cleanup()

    data_json = json.dumps(payload, separators=(",", ":"))
    if args.data_out:
        Path(args.data_out).write_text(data_json, encoding="utf-8")
    out_path = Path(args.out)
    assemble_html(Path(args.template), data_json, out_path)
    print(f"Wrote {out_path} ({out_path.stat().st_size / 1024:.1f} KB, {len(payload)} items) — node --check OK!")


if __name__ == "__main__":
    main()
