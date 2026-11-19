#!/usr/bin/env python3
"""One-command build, verification, libretro multipass export, and GitHub Release preparation.

Usage:
    python3 tools/publish-release.py 3.6                     # Build + verify + deterministic zip + changelog preview
    python3 tools/publish-release.py 3.6 --rebuild-docs      # Also update changed docs/img/*-crisp*.png
    python3 tools/publish-release.py 3.6 --libretro-dir DIR  # Sync 4-pass multipass into local glsl-shaders/slang-shaders clones
    python3 tools/publish-release.py 3.6 --tag               # Create annotated git tag after verifying clean git status
    python3 tools/publish-release.py 3.6 --publish           # Create tag, push, and publish GitHub Release via gh CLI
"""
import argparse
import importlib.util
import os
import shutil
import subprocess
import sys

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS_DIR)
BUILD_DIR = os.path.join(ROOT, "build")


def run_py(script: str, *extra: str) -> None:
    subprocess.check_call([sys.executable, os.path.join(TOOLS_DIR, script), *extra], cwd=ROOT)


def load_make_release():
    spec = importlib.util.spec_from_file_location("make_release", os.path.join(TOOLS_DIR, "make-release.py"))
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def latest_git_tag() -> str:
    try:
        out = subprocess.check_output(["git", "describe", "--tags", "--abbrev=0"], cwd=ROOT, stderr=subprocess.DEVNULL)
        return out.decode("utf-8").strip()
    except subprocess.CalledProcessError:
        return ""


def generate_changelog(prev_tag: str) -> str:
    rev = f"{prev_tag}..HEAD" if prev_tag else "HEAD"
    out = subprocess.check_output(["git", "log", rev, "--no-merges", "--pretty=format:- %s (%h)"], cwd=ROOT)
    text = out.decode("utf-8", "replace").strip()
    return text if text else "- Maintenance and shader updates."


def sync_libretro_clones(lr_root: str) -> None:
    mp_root = os.path.join(BUILD_DIR, "multipass")
    for sub in ("glsl-shaders", "slang-shaders"):
        src = os.path.join(mp_root, sub)
        dst = os.path.join(lr_root, sub)
        if not os.path.isdir(dst):
            print(f"[publish-release] Skipping {dst} (directory not found)")
            continue
        copied = 0
        for dirpath, _, filenames in os.walk(src):
            for fn in filenames:
                s_file = os.path.join(dirpath, fn)
                rel = os.path.relpath(s_file, src)
                d_file = os.path.join(dst, rel)
                os.makedirs(os.path.dirname(d_file), exist_ok=True)
                shutil.copy2(s_file, d_file)
                copied += 1
        print(f"[publish-release] Synced {copied} files -> {dst}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("version", help="Release version tag (e.g., 3.6 or 4.0)")
    ap.add_argument("--rebuild-docs", action="store_true", help="Update changed docs/img/*-crisp*.png headlessly")
    ap.add_argument("--libretro-dir", metavar="DIR", help="Parent directory containing glsl-shaders/ and/or slang-shaders/")
    ap.add_argument("--tag", action="store_true", help="Create annotated git tag after verifying clean git status")
    ap.add_argument("--publish", action="store_true", help="Push tag and create GitHub Release via gh CLI")
    args = ap.parse_args()

    print(f"=== Preparing xBRZ Crisp Release {args.version} ===")
    run_py("build-shaders.py")
    run_py("make-multipass.py")
    run_py("verify.py")

    if args.rebuild_docs:
        run_py("render-docs.py")

    mr = load_make_release()
    zip_path = os.path.join(BUILD_DIR, "xbrz-crisp.zip")
    count, sha256 = mr.build_zip(zip_path)
    size_kb = os.path.getsize(zip_path) / 1024.0
    print(f"[publish-release] Archive ready: {zip_path} ({count} files, {size_kb:.1f} KB)")
    print(f"[publish-release] SHA256: {sha256}")

    if args.libretro_dir:
        sync_libretro_clones(args.libretro_dir)

    prev = latest_git_tag()
    notes = f"## Changes since {prev or 'initial commit'}\n\n{generate_changelog(prev)}\n\n**SHA256 (`xbrz-crisp.zip`):** `{sha256}`\n"
    notes_path = os.path.join(BUILD_DIR, f"release-notes-{args.version}.md")
    with open(notes_path, "w", encoding="utf-8") as f:
        f.write(notes)
    print(f"[publish-release] Release notes written to {notes_path}")

    if args.tag or args.publish:
        dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT).decode("utf-8").strip()
        if dirty:
            sys.exit("[publish-release] Refusing to tag dirty working tree. Commit all changes first.")
        subprocess.check_call(["git", "tag", "-a", args.version, "-m", f"xBRZ Crisp {args.version}"], cwd=ROOT)
        print(f"[publish-release] Created annotated git tag {args.version}")
        if args.publish:
            subprocess.check_call(["git", "push", "origin", "main", args.version], cwd=ROOT)
            subprocess.check_call(
                ["gh", "release", "create", args.version, zip_path, "--title", f"xBRZ Crisp {args.version}", "--notes-file", notes_path],
                cwd=ROOT,
            )
            print(f"[publish-release] Published GitHub Release {args.version}!")
    else:
        print(
            f"\nReady! Once changes are committed & pushed to main, publish with:\n"
            f"  python3 tools/publish-release.py {args.version} --publish"
        )


if __name__ == "__main__":
    main()
