#!/usr/bin/env python3
"""Packages the RetroArch release zip (shaders_glsl/, shaders_slang/, LICENSE).

Matches the exact archive structure published on GitHub Releases so the zip contents
can be extracted straight into RetroArch's shaders directory on Android, PC, or handhelds.

Usage:
    python3 tools/make-release.py [out.zip]   (default: build/xbrz-crisp.zip)
"""
import os
import sys
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHADERS_ROOT = os.path.join(ROOT, "shaders")
LICENSE_PATH = os.path.join(ROOT, "LICENSE")
DEFAULT_OUT = os.path.join(ROOT, "build", "xbrz-crisp.zip")


def build_zip(out_path: str) -> int:
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    count = 0
    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for dirpath, dirnames, filenames in os.walk(SHADERS_ROOT):
            dirnames.sort()
            filenames.sort()
            rel_dir = os.path.relpath(dirpath, SHADERS_ROOT).replace(os.sep, "/")
            if rel_dir != ".":
                mtime = time.localtime(os.path.getmtime(dirpath))[:6]
                dir_info = zipfile.ZipInfo(rel_dir.rstrip("/") + "/", date_time=mtime)
                dir_info.external_attr = (0o40755 << 16) | 0x10
                zf.writestr(dir_info, b"")
            for fn in filenames:
                if fn.startswith("."):
                    continue
                full = os.path.join(dirpath, fn)
                arcname = os.path.relpath(full, SHADERS_ROOT).replace(os.sep, "/")
                zf.write(full, arcname)
                count += 1
        if os.path.isfile(LICENSE_PATH):
            zf.write(LICENSE_PATH, "LICENSE")
            count += 1
    return count


def main() -> None:
    out_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    count = build_zip(out_path)
    size_kb = os.path.getsize(out_path) / 1024.0
    print(f"Wrote {out_path} ({count} files, {size_kb:.1f} KB)")


if __name__ == "__main__":
    main()
