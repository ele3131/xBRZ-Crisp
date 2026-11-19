#!/usr/bin/env python3
"""Packages the RetroArch release zip (shaders_glsl/, shaders_slang/, LICENSE).

Matches the exact archive structure published on GitHub Releases so the zip contents
can be extracted straight into RetroArch's shaders directory on Android, PC, or handhelds.

Usage:
    python3 tools/make-release.py [out.zip]   (default: build/xbrz-crisp.zip)
"""
import hashlib
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHADERS_ROOT = os.path.join(ROOT, "shaders")
LICENSE_PATH = os.path.join(ROOT, "LICENSE")
DEFAULT_OUT = os.path.join(ROOT, "build", "xbrz-crisp.zip")
FIXED_DATE_TIME = (2026, 1, 1, 0, 0, 0)


def _write_deterministic_file(zf: zipfile.ZipFile, src_path: str, arcname: str) -> None:
    with open(src_path, "rb") as f:
        data = f.read()
    info = zipfile.ZipInfo(arcname, date_time=FIXED_DATE_TIME)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    zf.writestr(info, data)


def build_zip(out_path: str) -> tuple[int, str]:
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    count = 0
    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for dirpath, dirnames, filenames in os.walk(SHADERS_ROOT):
            dirnames.sort()
            filenames.sort()
            rel_dir = os.path.relpath(dirpath, SHADERS_ROOT).replace(os.sep, "/")
            if rel_dir != ".":
                dir_info = zipfile.ZipInfo(rel_dir.rstrip("/") + "/", date_time=FIXED_DATE_TIME)
                dir_info.external_attr = (0o40755 << 16) | 0x10
                zf.writestr(dir_info, b"")
            for fn in filenames:
                if fn.startswith("."):
                    continue
                full = os.path.join(dirpath, fn)
                arcname = os.path.relpath(full, SHADERS_ROOT).replace(os.sep, "/")
                _write_deterministic_file(zf, full, arcname)
                count += 1
        if os.path.isfile(LICENSE_PATH):
            _write_deterministic_file(zf, LICENSE_PATH, "LICENSE")
            count += 1
    with open(out_path, "rb") as f:
        sha256 = hashlib.sha256(f.read()).hexdigest()
    return count, sha256


def main() -> None:
    out_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    count, sha256 = build_zip(out_path)
    size_kb = os.path.getsize(out_path) / 1024.0
    print(f"Wrote {out_path} ({count} files, {size_kb:.1f} KB, sha256={sha256[:16]}...)")


if __name__ == "__main__":
    main()
