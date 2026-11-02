"""
tools/ios/patch_engine.py
Shared atomic patch engine for Devil May Cry 4 iOS ReXGlue SDK preparation.
Performs exact text substitution block by block, verifying anchor uniqueness (count == 1),
idempotency, and providing dry-run status and revert support.
"""

import argparse
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def find_sdk(probe_file: str = "CMakeLists.txt") -> pathlib.Path:
    """
    Locates the ReXGlue iOS SDK tree. Checks DMC4_SDK environment variable,
    command line arguments, or defaults to ../rexglue-sdk-ios.
    """
    env_sdk = os.environ.get("DMC4_SDK")
    candidates = []
    if env_sdk:
        candidates.append(pathlib.Path(env_sdk))
    candidates.extend([
        ROOT.parent / "rexglue-sdk-ios",
        ROOT / "rexglue-sdk-ios",
        pathlib.Path(r"E:\Project\NFS Carbon Switch\nfsc-nx\reference\nfsmw-nx\sdk"),
    ])

    for cand in candidates:
        if (cand / probe_file).exists():
            return cand.resolve()

    sys.exit(f"[ERROR] Cannot find ReXGlue SDK containing '{probe_file}'.\n"
             f"        Please set DMC4_SDK environment variable or clone rexglue-sdk to ../rexglue-sdk-ios.")


def read_file_contents(f: pathlib.Path) -> tuple[str, str]:
    with open(f, encoding="utf-8", newline="") as h:
        txt = h.read()
    eol = "\r\n" if "\r\n" in txt else "\n"
    return txt.replace("\r\n", "\n"), eol


def write_file_contents(f: pathlib.Path, txt: str, eol: str):
    with open(f, "w", encoding="utf-8", newline="") as h:
        h.write(txt.replace("\n", eol))


def apply_patch_blocks(name: str, blocks: list, sdk_dir: pathlib.Path, status_only: bool = False, revert: bool = False) -> int:
    files = {}
    for path, _, _, _ in blocks:
        if path not in files:
            f = sdk_dir / path
            if not f.exists():
                print(f"[ERROR] Target file does not exist: {f}")
                return 1
            files[path] = [f, *read_file_contents(f)]

    if status_only:
        applied = sum(1 for path, _, _, new in blocks if new in files[path][1])
        print(f"  {name:30s} {applied} of {len(blocks)} blocks applied")
        for path, desc, _, new in blocks:
            print(f"      {'yes' if new in files[path][1] else 'NO':>3}  {desc}  ({path})")
        return 0

    if revert:
        removed = 0
        for path, desc, anchor, new in reversed(blocks):
            txt = files[path][1]
            if new not in txt:
                continue
            if txt.count(new) != 1:
                print(f"[ERROR] Block '{desc}' appears {txt.count(new)} times in {path}. Aborting revert.")
                return 1
            files[path][1] = txt.replace(new, anchor)
            removed += 1
        if not removed:
            print(f"[ok] {name}: nothing was applied")
            return 0
        for f, txt, eol in files.values():
            write_file_contents(f, txt, eol)
        print(f"[ok] {name}: reverted {removed} blocks")
        return 0

    missing = [b for b in blocks if b[3] not in files[b[0]][1]]
    if not missing:
        print(f"[ok] {name}: all {len(blocks)} blocks already applied")
        return 0

    # Dry-run validation: check every missing block matches its anchor EXACTLY ONCE
    for path, desc, anchor, _ in missing:
        txt = files[path][1]
        matches = txt.count(anchor)
        if matches == 0:
            print(f"[ERROR] Anchor not found for block '{desc}' in {path}.")
            print(f"--- Anchor Preview ---\n{anchor[:200]}...\n----------------------")
            return 1
        if matches > 1:
            print(f"[ERROR] Anchor is ambiguous (found {matches} times) for block '{desc}' in {path}.")
            return 1

    # Apply all missing blocks in memory
    for path, _, anchor, new in missing:
        files[path][1] = files[path][1].replace(anchor, new, 1)

    # Write modified files to disk
    for f, txt, eol in files.values():
        write_file_contents(f, txt, eol)

    print(f"[ok] {name}: successfully applied {len(missing)} blocks")
    return 0
