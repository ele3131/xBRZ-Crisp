#!/usr/bin/env python3
"""Headless renderer for docs/img/ interactive comparison assets (*-crisp10, *-crisp20, *-crisp30, *-xbrz).

Uses surfaceless EGL + OpenGL ES via tools/verify.py and skips overwriting PNGs whose pixel content
has not changed (--changed-only, enabled by default) to prevent unnecessary Git binary churn.

Usage:
    python3 tools/render-docs.py                   # Update only changed docs/img/*-{crisp10,20,30}.png
    python3 tools/render-docs.py --include-xbrz    # Also update docs/img/*-xbrz.png (4-pass plain multipass)
    python3 tools/render-docs.py --force           # Rewrite all PNGs even if pixels are identical
    python3 tools/render-docs.py --dry-run         # Report which files would change without writing
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS_DIR)
SHADERS_DIR = os.path.join(ROOT, "shaders")
DOCS_IMG_DIR = os.path.join(ROOT, "docs", "img")

sys.path.insert(0, TOOLS_DIR)
from verify import HeadlessGLES  # noqa: E402


def save_if_changed(rgb: np.ndarray, path: str, force: bool = False, dry_run: bool = False, tol_lsb: int = 1) -> bool:
    if not force and os.path.isfile(path):
        old = np.array(Image.open(path).convert("RGB"), dtype=np.uint8)
        if old.shape == rgb.shape:
            max_delta = int(np.max(np.abs(old.astype(np.int16) - rgb.astype(np.int16))))
            if max_delta <= tol_lsb:
                return False
    if not dry_run:
        Image.fromarray(rgb, "RGB").save(path, format="PNG", optimize=True, compress_level=9)
    return True


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--include-xbrz", action="store_true", help="Also render 4-pass plain *-xbrz.png")
    ap.add_argument("--force", action="store_true", help="Rewrite PNGs even when pixels are unchanged")
    ap.add_argument("--dry-run", action="store_true", help="Report changes without touching disk")
    ap.add_argument("--exact", action="store_true", help="Treat even 1-LSB float rounding as a change")
    args = ap.parse_args()

    tol_lsb = 0 if args.exact else 1
    crisp_glsl = os.path.join(SHADERS_DIR, "shaders_glsl", "xbrz", "shaders", "xbrz-crisp")
    scenes = sorted(glob.glob(os.path.join(DOCS_IMG_DIR, "*-original.png")))
    if not scenes:
        sys.exit(f"No *-original.png scenes found in {DOCS_IMG_DIR}")

    gles = HeadlessGLES()
    tmp_mp = None
    try:
        crisp_progs = [
            gles.compile_program(os.path.join(crisp_glsl, f"xbrz-crisp-{p}.glsl"), "#version 300 es", True)
            for p in ("point", "pass0", "resolve", "match", "pass1")
        ]
        mp_progs = []
        if args.include_xbrz:
            tmp_mp = tempfile.mkdtemp(prefix="xbrz_docs_mp_")
            subprocess.check_call([sys.executable, os.path.join(TOOLS_DIR, "make-multipass.py"), tmp_mp], stdout=subprocess.DEVNULL)
            mp_glsl = os.path.join(tmp_mp, "glsl-shaders", "xbrz", "shaders", "xbrz-freescale-multipass")
            mp_progs = [
                gles.compile_program(os.path.join(mp_glsl, f"xbrz-freescale-{p}.glsl"), "#version 300 es", True)
                for p in ("point", "pass0", "resolve", "pass1")
            ]

        updated, skipped = 0, 0
        for sp in scenes:
            sid = os.path.basename(sp).replace("-original.png", "")
            inp = np.ascontiguousarray(np.array(Image.open(sp).convert("RGBA"), dtype=np.uint8))
            for minc_val, suffix in ((10.0, "crisp10"), (20.0, "crisp20"), (30.0, "crisp30")):
                rgb = gles.render_pipeline(crisp_progs, inp, scale=6, minc=minc_val, diag=100.0, tol=15.0, steep=3.2, dom=3.8)
                out_p = os.path.join(DOCS_IMG_DIR, f"{sid}-{suffix}.png")
                if save_if_changed(rgb, out_p, force=args.force, dry_run=args.dry_run, tol_lsb=tol_lsb):
                    updated += 1
                    print(f"  [{'DRY' if args.dry_run else 'UPD'}] {os.path.basename(out_p)}")
                else:
                    skipped += 1

            if mp_progs:
                rgb_x = gles.render_pipeline(mp_progs, inp, scale=6, minc=0.0, diag=0.0, tol=15.0, steep=3.2, dom=3.8)
                out_x = os.path.join(DOCS_IMG_DIR, f"{sid}-xbrz.png")
                if save_if_changed(rgb_x, out_x, force=args.force, dry_run=args.dry_run, tol_lsb=tol_lsb):
                    updated += 1
                    print(f"  [{'DRY' if args.dry_run else 'UPD'}] {os.path.basename(out_x)}")
                else:
                    skipped += 1

        for p in crisp_progs + mp_progs:
            gles.gl.glDeleteProgram(p)
        print(f"[render-docs] Done: {updated} updated, {skipped} unchanged (skipped).")
    finally:
        gles.close()
        if tmp_mp:
            shutil.rmtree(tmp_mp, ignore_errors=True)


if __name__ == "__main__":
    main()
