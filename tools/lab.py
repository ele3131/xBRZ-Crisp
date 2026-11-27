#!/usr/bin/env python3
"""Unified local research, debugging, verification, and benchmarking CLI for xBRZ Crisp.

Auto-enforces LP_NATIVE_VECTOR_WIDTH=128 for Mesa llvmpipe, auto-discovers up to 55
scenes (docs/img + tools/assets/micro + ~/.cache/xbrz-crisp/suite50 via XBRZ_SUITE_DIR),
and shares a content-addressed 6x PNG render cache under build/cache/<sha12>/.

Subcommands:
    python3 tools/lab.py diff [--ref HEAD] [--top 12] [--workers 2] [--cards OUT.png]
    python3 tools/lab.py check [--ref HEAD] [--full] [--workers 2]
    python3 tools/lab.py trace <scene> <x> <y> [--ref REF] [--radius 2]
    python3 tools/lab.py bisect <scene> <x> <y> [--ref HEAD] [--radius 2]
    python3 tools/lab.py bench [--ref HEAD] [--iters 7] [--profiles 300,100]
    python3 tools/lab.py studio [--ref HEAD] [--preset desktop|compact|full] [--out PATH]
    python3 tools/lab.py cache-gc [--keep 6]
"""
import argparse
import concurrent.futures
import glob
import hashlib
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

os.environ.setdefault("LP_NATIVE_VECTOR_WIDTH", "128")

TOOLS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOLS_DIR.parent
CACHE_ROOT = REPO_ROOT / "build" / "cache"
DEFAULT_SUITE_DIR = Path(os.environ.get("XBRZ_SUITE_DIR", str(Path.home() / ".cache" / "xbrz-crisp" / "suite50")))

sys.path.insert(0, str(TOOLS_DIR))
import numpy as np
from PIL import Image, ImageDraw
from verify import HeadlessGLES

PASSES = ("point", "pass0", "resolve", "match", "pass1")
SHADER_REL_PATHS = [f"shaders/shaders_glsl/xbrz/shaders/xbrz-crisp/xbrz-crisp-{p}.glsl" for p in PASSES]

# Rec. 2020 YCbCr weights matching tools/src/color.inc
LUMA_W = np.array([0.2627, 0.6780, 0.0593], dtype=np.float64)
SCALE_B = 0.5 / (1.0 - 0.0593)
SCALE_R = 0.5 / (1.0 - 0.2627)


def rgb_to_ycbcr(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    r, g, b = rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0
    y = r * LUMA_W[0] + g * LUMA_W[1] + b * LUMA_W[2]
    return y, SCALE_B * (b - y), SCALE_R * (r - y)


def discover_scenes(extra_dir: str | None = None, docs_only: bool = False) -> dict[str, Path]:
    scenes: dict[str, Path] = {}
    for p in sorted(glob.glob(str(REPO_ROOT / "docs/img/*-original.png"))):
        scenes["docs_" + Path(p).name.replace("-original.png", "")] = Path(p)
    if docs_only:
        return scenes
    for p in sorted(glob.glob(str(REPO_ROOT / "tools/assets/micro/*-original.png"))):
        scenes["micro_" + Path(p).name.replace("-original.png", "")] = Path(p)
    ed = Path(extra_dir) if extra_dir else DEFAULT_SUITE_DIR
    if ed.is_dir():
        for p in sorted(glob.glob(str(ed / "*.png"))):
            scenes["s50_" + Path(p).stem] = Path(p)
    return scenes


def resolve_scene(scenes: dict[str, Path], query: str) -> tuple[str, Path]:
    if query in scenes:
        return query, scenes[query]
    matches = [(k, v) for k, v in scenes.items() if query in k]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        sys.exit(f"Scene not found: {query!r}. Available ({len(scenes)}): {', '.join(sorted(scenes)[:10])} ...")
    sys.exit(f"Ambiguous scene {query!r}: matches {[m[0] for m in matches[:8]]}")


def get_shader_sources(ref: str | None) -> list[str]:
    if ref is None:
        return [(REPO_ROOT / rel).read_text(encoding="utf-8") for rel in SHADER_REL_PATHS]
    return [
        subprocess.check_output(["git", "show", f"{ref}:{rel}"], cwd=str(REPO_ROOT)).decode("utf-8")
        for rel in SHADER_REL_PATHS
    ]


def sources_hash(sources: list[str], salt: str = "crisp20") -> str:
    h = hashlib.sha256(salt.encode("utf-8"))
    for s in sources:
        h.update(b"\0")
        h.update(s.encode("utf-8"))
    return h.hexdigest()[:12]


def _render_chunk_worker(args: tuple) -> list[tuple[str, str]]:
    """Worker process: renders cache misses for a list of (scene_id, src_path) into cache_dir."""
    os.environ["LP_NATIVE_VECTOR_WIDTH"] = "128"
    shader_paths, cache_dir, items = args
    gles = HeadlessGLES()
    progs = [gles.compile_program(p, "#version 300 es", True) for p in shader_paths]
    out = []
    try:
        Path(cache_dir).mkdir(parents=True, exist_ok=True)
        for sid, sp in items:
            dst = Path(cache_dir) / f"{sid}.png"
            if not dst.is_file():
                rgba = np.ascontiguousarray(np.array(Image.open(sp).convert("RGBA"), dtype=np.uint8))
                rgb = gles.render_pipeline(progs, rgba, scale=6)
                Image.fromarray(rgb, "RGB").save(dst, compress_level=1)
            out.append((sid, str(dst)))
    finally:
        for p in progs:
            gles.delete_program(p)
        gles.close()
    return out


def ensure_cached_renders(
    ref: str | None, scenes: dict[str, Path], workers: int = 2, cache_root: Path = CACHE_ROOT
) -> tuple[str, Path]:
    srcs = get_shader_sources(ref)
    h = sources_hash(srcs, "crisp20")
    cdir = cache_root / h
    cdir.mkdir(parents=True, exist_ok=True)
    cdir.touch()
    missing = [(sid, str(sp)) for sid, sp in sorted(scenes.items()) if not (cdir / f"{sid}.png").is_file()]
    if not missing:
        return h, cdir

    with tempfile.TemporaryDirectory(prefix="xbrz_lab_sh_") as td:
        sh_paths = []
        for i, src in enumerate(srcs):
            fp = Path(td) / f"pass_{i}.glsl"
            fp.write_text(src, encoding="utf-8")
            sh_paths.append(str(fp))
        w = max(1, min(workers, len(missing)))
        if w == 1:
            _render_chunk_worker((sh_paths, str(cdir), missing))
        else:
            chunks = [missing[i::w] for i in range(w)]
            with concurrent.futures.ProcessPoolExecutor(max_workers=w) as ex:
                list(ex.map(_render_chunk_worker, [(sh_paths, str(cdir), c) for c in chunks]))
    return h, cdir


def decode_word(val: int, pass_name: str) -> str:
    if val == 0:
        return "0"
    if pass_name == "point":
        # 4 corners packed 2 bits each: x=bits6..7, y=bits4..5, w=bits2..3, z=bits0..1
        b = [val >> 6, (val >> 4) & 3, val & 3, (val >> 2) & 3]
        return f"pts=({b[0]},{b[1]},{b[2]},{b[3]})"
    bl = val & 3
    flags = []
    if pass_name == "pass0":
        bl_names = {0: "NONE", 1: "NORM", 2: "DOM", 3: "WEAK"}
    else:
        bl_names = {0: "NONE", 1: "NORM", 2: "THIN", 3: "SMALL"}
    flags.append(bl_names[bl])
    if val & 4:
        flags.append("LINE")
    if val & 8:
        flags.append("SEC")
    sh, st = bool(val & 16), bool(val & 64)
    b5, b7 = bool(val & 32), bool(val & 128)
    if sh:
        flags.append("SH")
    if st:
        flags.append("ST")
    if pass_name == "pass0":
        if b5:
            flags.append("TONE")
        if b7:
            flags.append("BLK")
    elif pass_name == "resolve":
        if b5:
            flags.append("LONG3")
        if b7:
            flags.append("LONG4")
    else:  # match
        if (sh or st) and b5 and b7:
            flags.append("ARC21")
        elif (not sh and not st) and b5 and not b7:
            flags.append("ARC45")
        else:
            if b5:
                flags.append("LONG3")
            if b7:
                flags.append("LONG4")
    return f"{val:3d}[{'|'.join(flags)}]"


def cmd_diff(args: argparse.Namespace) -> None:
    scenes = discover_scenes(args.extra_dir)
    if args.scene:
        scenes = {k: v for k, v in scenes.items() if args.scene in k}
        if not scenes:
            sys.exit(f"No scenes matching {args.scene!r}")
    t0 = time.perf_counter()
    h_ref, dir_ref = ensure_cached_renders(args.ref, scenes, workers=args.workers)
    h_cur, dir_cur = ensure_cached_renders(None, scenes, workers=args.workers)

    rows = []
    total_px = 0
    for sid, sp in sorted(scenes.items()):
        ref = np.array(Image.open(dir_ref / f"{sid}.png").convert("RGB"), dtype=np.uint8)
        cur = np.array(Image.open(dir_cur / f"{sid}.png").convert("RGB"), dtype=np.uint8)
        diff = np.abs(cur.astype(np.int16) - ref.astype(np.int16))
        dmask = np.any(diff > args.tol, axis=2)
        dpx = int(dmask.sum())
        if dpx > 0:
            h1, w1 = ref.shape[0] // 6, ref.shape[1] // 6
            tiles = int(dmask.reshape(h1, 6, w1, 6).any(axis=(1, 3)).sum())
            max_d = int(diff.max())
            rows.append((dpx, tiles, max_d, sid, sp, ref, cur, dmask))
            total_px += dpx

    rows.sort(key=lambda r: (-r[0], r[3]))
    dt = time.perf_counter() - t0
    print(f"[lab diff] ref={args.ref}({h_ref}) -> work({h_cur}) | {len(rows)}/{len(scenes)} scenes changed | {total_px} px (tol={args.tol}) in {dt:.1f}s")
    for dpx, tiles, max_d, sid, *_ in rows[: args.top]:
        print(f"  {sid:26s} | {dpx:6d} px ({tiles:4d} 1x tiles) | max_abs={max_d:3d}")

    if args.cards and rows:
        save_hotspot_cards(rows[: args.cards_n], Path(args.cards))


def save_hotspot_cards(rows: list, out_path: Path) -> None:
    """Save a 4-panel contact sheet (Orig 1x | Ref | Work | Diff) for top diff hotspots."""
    tile_w, tile_h = 192, 192  # 32x32 1x crop at 6x
    pad, hdr = 10, 26
    card_w = 4 * tile_w + 5 * pad
    card_h = hdr + tile_h + pad
    canvas = Image.new("RGB", (card_w, len(rows) * card_h + pad), (18, 22, 28))
    draw = ImageDraw.Draw(canvas)
    for idx, (dpx, tiles, max_d, sid, sp, ref, cur, dmask) in enumerate(rows):
        orig = np.array(Image.open(sp).convert("RGB"), dtype=np.uint8)
        h1, w1 = orig.shape[:2]
        d1 = dmask.reshape(h1, 6, w1, 6).any(axis=(1, 3))
        ys, xs = np.where(d1)
        cx, cy = int(np.median(xs)), int(np.median(ys))
        cw, ch = min(32, w1), min(32, h1)
        x0 = max(0, min(w1 - cw, cx - cw // 2))
        y0 = max(0, min(h1 - ch, cy - ch // 2))
        x1, y1 = x0 + cw, y0 + ch
        oc = Image.fromarray(orig[y0:y1, x0:x1]).resize((cw * 6, ch * 6), Image.Resampling.NEAREST)
        rc = Image.fromarray(ref[y0 * 6 : y1 * 6, x0 * 6 : x1 * 6])
        nc = Image.fromarray(cur[y0 * 6 : y1 * 6, x0 * 6 : x1 * 6])
        dm = dmask[y0 * 6 : y1 * 6, x0 * 6 : x1 * 6]
        vis = (cur[y0 * 6 : y1 * 6, x0 * 6 : x1 * 6].astype(np.float32) * 0.35).astype(np.uint8)
        vis[dm] = np.array([255, 64, 180], dtype=np.uint8)
        dc = Image.fromarray(vis)

        y_top = pad + idx * card_h
        draw.text((pad, y_top + 4), f"#{idx+1} {sid} ({x0},{y0})..({x1},{y1}) | {dpx} px ({tiles} tiles) | Orig | Ref | Work | Diff", fill=(230, 238, 245))
        for j, im in enumerate((oc, rc, nc, dc)):
            canvas.paste(im.resize((tile_w, tile_h), Image.Resampling.NEAREST), (pad + j * (tile_w + pad), y_top + hdr))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)
    print(f"[lab diff] Wrote hotspot cards -> {out_path}")


def _d4_worker(args: tuple) -> tuple[dict[str, list], int]:
    os.environ["LP_NATIVE_VECTOR_WIDTH"] = "128"
    shader_paths, items = args
    gles = HeadlessGLES()
    progs = [gles.compile_program(p, "#version 300 es", True) for p in shader_paths]
    fails: dict[str, list] = {"rot90": [], "rot180": [], "rot270": [], "flipH": []}
    max_d4 = 0
    try:
        for sid, sp in items:
            rgba = np.ascontiguousarray(np.array(Image.open(sp).convert("RGBA"), dtype=np.uint8))
            base = gles.render_pipeline(progs, rgba, scale=6)
            for name, fn, inv in (
                ("rot90",  lambda a: np.ascontiguousarray(np.rot90(a, 1)), lambda a: np.rot90(a, 3)),
                ("rot180", lambda a: np.ascontiguousarray(np.rot90(a, 2)), lambda a: np.rot90(a, 2)),
                ("rot270", lambda a: np.ascontiguousarray(np.rot90(a, 3)), lambda a: np.rot90(a, 1)),
                ("flipH",  lambda a: np.ascontiguousarray(np.fliplr(a)),   lambda a: np.fliplr(a)),
            ):
                got = inv(gles.render_pipeline(progs, fn(rgba), scale=6))
                d = int(np.max(np.abs(got.astype(np.int16) - base.astype(np.int16))))
                max_d4 = max(max_d4, d)
                if d > 1:
                    fails[name].append((sid, d))
    finally:
        for p in progs:
            gles.delete_program(p)
        gles.close()
    return fails, max_d4


def cmd_check(args: argparse.Namespace) -> None:
    scenes = discover_scenes(args.extra_dir, docs_only=not args.full)
    docs_scenes = {k: v for k, v in scenes.items() if k.startswith("docs_")}
    sh_paths = [str(REPO_ROOT / rel) for rel in SHADER_REL_PATHS]

    # 1. ES 1.00 vs ES 3.00 parity on docs scenes
    gles = HeadlessGLES()
    progs300 = [gles.compile_program(p, "#version 300 es", True) for p in sh_paths]
    progs100 = [gles.compile_program(p, "#version 100", True) for p in sh_paths]
    max_es = 0
    es_bad = []
    for sid, sp in sorted(docs_scenes.items()):
        rgba = np.ascontiguousarray(np.array(Image.open(sp).convert("RGBA"), dtype=np.uint8))
        o3 = gles.render_pipeline(progs300, rgba, scale=6)
        o1 = gles.render_pipeline(progs100, rgba, scale=6)
        d = int(np.max(np.abs(o3.astype(np.int16) - o1.astype(np.int16))))
        max_es = max(max_es, d)
        if d > 1:
            es_bad.append((sid, d))
    for p in progs300 + progs100:
        gles.delete_program(p)

    # 2. Plain 4-pass vs --ref on docs scenes
    plain_diff = 0
    with tempfile.TemporaryDirectory(prefix="xbrz_lab_mp_") as td:
        mp_cur = Path(td) / "cur"
        mp_ref = Path(td) / "ref"
        subprocess.check_call([sys.executable, str(TOOLS_DIR / "make-multipass.py"), str(mp_cur)], stdout=subprocess.DEVNULL)
        tar_p = Path(td) / "ref.tar"
        with open(tar_p, "wb") as tf:
            subprocess.check_call(["git", "archive", args.ref], cwd=str(REPO_ROOT), stdout=tf)
        mp_ref.mkdir()
        subprocess.check_call(["tar", "-xf", str(tar_p), "-C", str(mp_ref)])
        subprocess.check_call([sys.executable, str(mp_ref / "tools" / "make-multipass.py"), str(mp_ref / "out")], cwd=str(mp_ref), stdout=subprocess.DEVNULL)
        c_dir = mp_cur / "glsl-shaders" / "xbrz" / "shaders" / "xbrz-freescale-multipass"
        r_dir = mp_ref / "out" / "glsl-shaders" / "xbrz" / "shaders" / "xbrz-freescale-multipass"
        p_cur = [gles.compile_program(str(c_dir / f"xbrz-freescale-{p}.glsl"), "#version 300 es", False) for p in ("point", "pass0", "resolve", "pass1")]
        p_ref = [gles.compile_program(str(r_dir / f"xbrz-freescale-{p}.glsl"), "#version 300 es", False) for p in ("point", "pass0", "resolve", "pass1")]
        for sid, sp in sorted(docs_scenes.items()):
            rgba = np.ascontiguousarray(np.array(Image.open(sp).convert("RGBA"), dtype=np.uint8))
            a = gles.render_pipeline(p_cur, rgba, scale=6)
            b = gles.render_pipeline(p_ref, rgba, scale=6)
            if int(np.max(np.abs(a.astype(np.int16) - b.astype(np.int16)))) > 0:
                plain_diff += 1
        for p in p_cur + p_ref:
            gles.delete_program(p)
    gles.close()

    # 3. Full D4 across selected scenes
    items = [(k, str(v)) for k, v in sorted(scenes.items())]
    w = max(1, min(args.workers, len(items)))
    fails_all: dict[str, list] = {"rot90": [], "rot180": [], "rot270": [], "flipH": []}
    max_d4 = 0
    if w == 1:
        fails_all, max_d4 = _d4_worker((sh_paths, items))
    else:
        chunks = [items[i::w] for i in range(w)]
        with concurrent.futures.ProcessPoolExecutor(max_workers=w) as ex:
            for fl, md in ex.map(_d4_worker, [(sh_paths, c) for c in chunks]):
                max_d4 = max(max_d4, md)
                for k in fails_all:
                    fails_all[k].extend(fl[k])

    print(f"[lab check] ES 1.00 vs ES 3.00 ({len(docs_scenes)} docs): max_abs={max_es}, failures={len(es_bad)} {es_bad}")
    print(f"[lab check] Plain 4-pass vs {args.ref} ({len(docs_scenes)} docs): {plain_diff}/{len(docs_scenes)} changed")
    print(
        f"[lab check] Full D4 ({len(scenes)} scenes): "
        f"rot90={len(fails_all['rot90'])}, rot180={len(fails_all['rot180'])}, "
        f"rot270={len(fails_all['rot270'])}, flipH={len(fails_all['flipH'])}, max_abs={max_d4}"
    )
    if es_bad or plain_diff > 0 or any(fails_all.values()):
        for k, v in fails_all.items():
            if v:
                print(f"   D4 {k} failures:", v[:10])
        sys.exit(1)


def _capture_passes(gles: HeadlessGLES, ref: str | None, rgba: np.ndarray) -> tuple[np.ndarray, list[np.ndarray]]:
    srcs = get_shader_sources(ref)
    with tempfile.TemporaryDirectory(prefix="xbrz_trace_") as td:
        progs = []
        for i, src in enumerate(srcs):
            fp = Path(td) / f"p{i}.glsl"
            fp.write_text(src, encoding="utf-8")
            progs.append(gles.compile_program(str(fp), "#version 300 es", True))
        try:
            return gles.render_pipeline(progs, rgba, scale=6, return_passes=True)
        finally:
            for p in progs:
                gles.delete_program(p)


def cmd_trace(args: argparse.Namespace) -> None:
    scenes = discover_scenes(args.extra_dir)
    sid, sp = resolve_scene(scenes, args.scene)
    rgba = np.ascontiguousarray(np.array(Image.open(sp).convert("RGBA"), dtype=np.uint8))
    h, w, _ = rgba.shape
    cx, cy, rad = args.x, args.y, args.radius
    if not (0 <= cx < w and 0 <= cy < h):
        sys.exit(f"Coordinates ({cx},{cy}) out of bounds for {sid} ({w}x{h})")

    gles = HeadlessGLES()
    try:
        out_cur, passes_cur = _capture_passes(gles, None, rgba)
        passes_ref = None
        if args.ref:
            _, passes_ref = _capture_passes(gles, args.ref, rgba)
    finally:
        gles.close()

    print(f"=== Trace {sid} ({w}x{h}) @ ({cx}, {cy}), radius={rad} ===")
    print("1x RGB neighborhood (with YCbCr at center):")
    for dy in range(-rad, rad + 1):
        row = []
        for dx in range(-rad, rad + 1):
            xx, yy = cx + dx, cy + dy
            if 0 <= xx < w and 0 <= yy < h:
                r, g, b = int(rgba[yy, xx, 0]), int(rgba[yy, xx, 1]), int(rgba[yy, xx, 2])
                tag = "*" if (dx == 0 and dy == 0) else " "
                row.append(f"{tag}#{r:02X}{g:02X}{b:02X}")
            else:
                row.append(" -------")
        print(f"  y={cy+dy:3d}: " + " ".join(row))
    yc = rgb_to_ycbcr((int(rgba[cy, cx, 0]), int(rgba[cy, cx, 1]), int(rgba[cy, cx, 2])))
    print(f"  Center YCbCr = ({yc[0]:.3f}, {yc[1]:+.3f}, {yc[2]:+.3f})")

    print("\nDecision words at center (x=TL, y=TR, z=BR, w=BL):")
    for i, pname in enumerate(("point", "pass0", "resolve", "match")):
        px = passes_cur[i][cy, cx]
        if pname == "point":
            s_cur = decode_word(int(px[3]), pname)
            if passes_ref is not None:
                s_ref = decode_word(int(passes_ref[i][cy, cx, 3]), pname)
                mark = "  <-- DIFF" if s_cur != s_ref else ""
                print(f"  {pname:8s}: work={s_cur:24s} | {args.ref}={s_ref}{mark}")
            else:
                print(f"  {pname:8s}: {s_cur}")
        else:
            s_cur = "  ".join(f"{c}={decode_word(int(px[j]), pname)}" for j, c in enumerate("xyzw"))
            if passes_ref is not None:
                pr = passes_ref[i][cy, cx]
                s_ref = "  ".join(f"{c}={decode_word(int(pr[j]), pname)}" for j, c in enumerate("xyzw"))
                mark = "  <-- DIFF" if not np.array_equal(px, pr) else ""
                print(f"  {pname:8s} [work]: {s_cur}{mark}")
                if mark:
                    print(f"  {pname:8s} [{args.ref}]: {s_ref}")
            else:
                print(f"  {pname:8s}: {s_cur}")


def cmd_bisect(args: argparse.Namespace) -> None:
    scenes = discover_scenes(args.extra_dir)
    sid, sp = resolve_scene(scenes, args.scene)
    rgba = np.ascontiguousarray(np.array(Image.open(sp).convert("RGBA"), dtype=np.uint8))
    h, w, _ = rgba.shape
    cx, cy, rad = args.x, args.y, args.radius

    gles = HeadlessGLES()
    try:
        out_cur, p_cur = _capture_passes(gles, None, rgba)
        out_ref, p_ref = _capture_passes(gles, args.ref, rgba)
    finally:
        gles.close()

    print(f"=== Bisect {sid} @ ({cx},{cy}) radius={rad}: {args.ref} -> working tree ===")
    first_div = None
    for i, pname in enumerate(("point", "pass0", "resolve", "match")):
        diffs = []
        for dy in range(-rad, rad + 1):
            for dx in range(-rad, rad + 1):
                xx, yy = cx + dx, cy + dy
                if 0 <= xx < w and 0 <= yy < h:
                    if pname == "point":
                        a, b = int(p_ref[i][yy, xx, 3]), int(p_cur[i][yy, xx, 3])
                        if a != b:
                            diffs.append((dx, dy, f"{a}->{b}"))
                    else:
                        a, b = p_ref[i][yy, xx], p_cur[i][yy, xx]
                        if not np.array_equal(a, b):
                            ch = [f"{c}:{int(a[j])}->{int(b[j])}" for j, c in enumerate("xyzw") if a[j] != b[j]]
                            diffs.append((dx, dy, ",".join(ch)))
        status = f"DIFF ({len(diffs)} pixels)" if diffs else "IDENTICAL"
        if diffs and first_div is None:
            first_div = pname
        print(f"  pass {i} ({pname:7s}): {status}")
        for dx, dy, desc in diffs[:12]:
            print(f"      ({cx+dx:3d},{cy+dy:3d}) [dx={dx:+d},dy={dy:+d}]: {desc}")

    # Check pass1 6x block at (cx, cy)
    blk_ref = out_ref[cy * 6 : (cy + 1) * 6, cx * 6 : (cx + 1) * 6]
    blk_cur = out_cur[cy * 6 : (cy + 1) * 6, cx * 6 : (cx + 1) * 6]
    d6 = int(np.any(blk_ref != blk_cur, axis=2).sum())
    if d6 > 0 and first_div is None:
        first_div = "pass1"
    print(f"  pass 4 (pass1  ): {'DIFF (' + str(d6) + '/36 subpixels at center)' if d6 else 'IDENTICAL at center'}")
    print(f"  => First diverging pass: {first_div or 'NONE (identical)'}")


def cmd_bench(args: argparse.Namespace) -> None:
    os.environ["LP_NUM_THREADS"] = "1"
    scenes = discover_scenes(args.extra_dir)
    bench_ids = ["docs_gs_village", "docs_gs2_battle", "docs_ffta", "docs_dbz_title", "docs_mc_eu", "docs_tales", "s50_md_sonic2", "s50_snes_ff6"]
    active = [(sid, scenes[sid]) for sid in bench_ids if sid in scenes]
    if not active:
        active = sorted(scenes.items())[:6]

    ref_srcs = get_shader_sources(args.ref)
    new_paths = [str(REPO_ROOT / rel) for rel in SHADER_REL_PATHS]

    with tempfile.TemporaryDirectory(prefix="xbrz_bench_") as td:
        ref_paths = []
        for i, src in enumerate(ref_srcs):
            fp = Path(td) / f"ref_{i}.glsl"
            fp.write_text(src, encoding="utf-8")
            ref_paths.append(str(fp))

        for prof in [p.strip() for p in args.profiles.split(",") if p.strip()]:
            hdr = "#version 300 es" if prof == "300" else "#version 100"
            gles = HeadlessGLES()
            try:
                t0 = time.perf_counter()
                ref_progs = [gles.compile_program(p, hdr, True) for p in ref_paths]
                c_ref = (time.perf_counter() - t0) * 1000.0
                t0 = time.perf_counter()
                new_progs = [gles.compile_program(p, hdr, True) for p in new_paths]
                c_new = (time.perf_counter() - t0) * 1000.0

                print(f"\n=== Profile: {hdr} (compile+link: {args.ref}={c_ref:.0f} ms, work={c_new:.0f} ms, 1-worker) ===")
                print(f"{'Scene':16s} | {'point':>13s} | {'pass0':>13s} | {'resolve':>13s} | {'match':>13s} | {'pass1':>13s} | {'TOTAL (ms)':>19s}")
                print("-" * 116)
                ref_pp_all, new_pp_all, ref_tot_all, new_tot_all = [], [], [], []
                for sid, sp in active:
                    rgba = np.ascontiguousarray(np.array(Image.open(sp).convert("RGBA"), dtype=np.uint8))
                    r_pp, r_tot = gles.render_pipeline_timed(ref_progs, rgba, scale=6, warmup=2, iters=args.iters)
                    n_pp, n_tot = gles.render_pipeline_timed(new_progs, rgba, scale=6, warmup=2, iters=args.iters)
                    ref_pp_all.append(r_pp); new_pp_all.append(n_pp)
                    ref_tot_all.append(r_tot); new_tot_all.append(n_tot)
                    cols = [f"{r:4.1f}->{n:4.1f}({(n-r)/r*100:+3.0f}%)" for r, n in zip(r_pp, n_pp)]
                    print(f"{sid:16s} | " + " | ".join(cols) + f" | {r_tot:5.1f}->{n_tot:5.1f} ({(n_tot-r_tot)/r_tot*100:+5.1f}%)")
                m_rpp = [statistics.mean(x[i] for x in ref_pp_all) for i in range(5)]
                m_npp = [statistics.mean(x[i] for x in new_pp_all) for i in range(5)]
                m_rt = statistics.mean(ref_tot_all)
                m_nt = statistics.mean(new_tot_all)
                cols = [f"{r:4.1f}->{n:4.1f}({(n-r)/r*100:+3.0f}%)" for r, n in zip(m_rpp, m_npp)]
                print("-" * 116)
                print(f"{'MEAN':16s} | " + " | ".join(cols) + f" | {m_rt:5.1f}->{m_nt:5.1f} ({(m_nt-m_rt)/m_rt*100:+5.1f}%)")
                for p in ref_progs + new_progs:
                    gles.delete_program(p)
            finally:
                gles.close()


def cmd_studio(args: argparse.Namespace) -> None:
    cmd = [
        sys.executable,
        str(TOOLS_DIR / "studio" / "build_studio.py"),
        "--baseline-ref", args.ref,
        "--preset", args.preset,
        "--out", args.out,
    ]
    if args.baseline_label:
        cmd += ["--baseline-label", args.baseline_label]
    if args.cand_label:
        cmd += ["--cand-label", args.cand_label]
    if args.title:
        cmd += ["--title", args.title]
    if args.extra_dir:
        cmd += ["--extra-dir", args.extra_dir]
    if args.desktop_budget:
        cmd += ["--desktop-budget", str(args.desktop_budget)]
    subprocess.check_call(cmd, cwd=str(REPO_ROOT))


def cmd_cache_gc(args: argparse.Namespace) -> None:
    if not CACHE_ROOT.is_dir():
        print("[lab cache-gc] Cache directory does not exist.")
        return
    dirs = [d for d in CACHE_ROOT.iterdir() if d.is_dir()]
    dirs.sort(key=lambda d: d.stat().st_mtime, reverse=True)
    removed = 0
    freed_bytes = 0
    for d in dirs[args.keep :]:
        sz = sum(f.stat().st_size for f in d.rglob("*") if f.is_file())
        shutil.rmtree(d, ignore_errors=True)
        removed += 1
        freed_bytes += sz
    print(f"[lab cache-gc] Kept {min(len(dirs), args.keep)} entries, removed {removed} ({freed_bytes / (1024*1024):.1f} MiB freed).")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--extra-dir", default=None, help="Extra native 1x PNG directory (defaults to ~/.cache/xbrz-crisp/suite50)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_diff = sub.add_parser("diff", help="Cached pixel diff across all scenes vs git ref")
    p_diff.add_argument("--ref", default="HEAD")
    p_diff.add_argument("--top", type=int, default=15)
    p_diff.add_argument("--tol", type=int, default=0, help="Per-channel tolerance (default: 0 bit-exact)")
    p_diff.add_argument("--workers", type=int, default=2)
    p_diff.add_argument("--scene", default=None, help="Filter scenes containing substring")
    p_diff.add_argument("--cards", default=None, help="Optional PNG path to save top hotspot 4-panel contact sheet")
    p_diff.add_argument("--cards-n", type=int, default=8)
    p_diff.set_defaults(func=cmd_diff)

    p_chk = sub.add_parser("check", help="ES 1.00/3.00 parity + Full D4 + Plain 4-pass check")
    p_chk.add_argument("--ref", default="HEAD")
    p_chk.add_argument("--full", action="store_true", help="Run Full D4 across all 55 scenes (default: 12 docs/img)")
    p_chk.add_argument("--workers", type=int, default=2)
    p_chk.set_defaults(func=cmd_check)

    p_tr = sub.add_parser("trace", help="Dump 1x RGB/YCbCr neighborhood and decoded 5-pass words at (x, y)")
    p_tr.add_argument("scene")
    p_tr.add_argument("x", type=int)
    p_tr.add_argument("y", type=int)
    p_tr.add_argument("--ref", default=None, help="Optional git ref to compare decision words against")
    p_tr.add_argument("--radius", type=int, default=2)
    p_tr.set_defaults(func=cmd_trace)

    p_bi = sub.add_parser("bisect", help="Pinpoint first pass diverging from --ref at (x, y)")
    p_bi.add_argument("scene")
    p_bi.add_argument("x", type=int)
    p_bi.add_argument("y", type=int)
    p_bi.add_argument("--ref", default="HEAD")
    p_bi.add_argument("--radius", type=int, default=2)
    p_bi.set_defaults(func=cmd_bisect)

    p_bn = sub.add_parser("bench", help="1-worker idle-CPU per-pass + total latency benchmark vs git ref")
    p_bn.add_argument("--ref", default="HEAD")
    p_bn.add_argument("--iters", type=int, default=7)
    p_bn.add_argument("--profiles", default="300,100", help="Comma-separated GLSL ES profiles (300,100)")
    p_bn.set_defaults(func=cmd_bench)

    p_st = sub.add_parser("studio", help="Build offline Studio v4 HTML comparator")
    p_st.add_argument("--ref", default="HEAD")
    p_st.add_argument("--preset", choices=("desktop", "compact", "full"), default="desktop")
    p_st.add_argument("--out", default=str(REPO_ROOT / "build" / "xbrz_crisp.studio.html"))
    p_st.add_argument("--baseline-label", default=None)
    p_st.add_argument("--cand-label", default="Novo")
    p_st.add_argument("--title", default=None)
    p_st.add_argument("--desktop-budget", type=int, default=None)
    p_st.set_defaults(func=cmd_studio)

    p_gc = sub.add_parser("cache-gc", help="Prune old shader-hash cache directories under build/cache/")
    p_gc.add_argument("--keep", type=int, default=6)
    p_gc.set_defaults(func=cmd_cache_gc)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
