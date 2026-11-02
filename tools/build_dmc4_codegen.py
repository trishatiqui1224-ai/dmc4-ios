#!/usr/bin/env python3
"""
tools/build_dmc4_codegen.py
Automated PowerPC-to-C++ AOT Static Recompilation, Switch Table Extractor,
and Unresolved Branch Healing Pipeline for:
Devil May Cry 4 (Xbox 360, Title ID: 434307DF, Capcom MT Framework)
"""

import argparse
import os
import pathlib
import re
import shutil
import struct
import subprocess
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
PROJECT_ROOT = REPO_ROOT.parent

# Candidate locations for DMC4 default.xex
XEX_CANDIDATES = [
    REPO_ROOT / "xex" / "dmc4_default.xex",
    REPO_ROOT / "game" / "default.xex",
    REPO_ROOT / "default.xex",
    PROJECT_ROOT / "default.xex",
    PROJECT_ROOT / "dmc4-ios" / "xex" / "dmc4_default.xex",
]

# Candidate locations for host rexglue CLI
REXGLUE_CANDIDATES = [
    REPO_ROOT / "tools" / "rexglue",
    REPO_ROOT / "tools" / "rexglue.exe",
    PROJECT_ROOT / "rexglue-sdk-ios" / "out" / "rexglue",
    PROJECT_ROOT / "rexglue-sdk-ios" / "out" / "rexglue.exe",
    pathlib.Path(r"E:\Project\NFS Carbon Switch\nfsc-nx\reference\nfsmw-nx\sdk\out\win-amd64\rexglue.exe"),
]

# Critical DMC4 MT Framework Ground-Truth Symbols
DMC4_KNOWN_SYMBOLS = [
    (0x822901D0, "xstart", "DMC4 CRT entry point / startup (__security_init_cookie, xstart)"),
    (0x82290208, "main_dispatch", "DMC4 primary CRT initialization dispatch"),
    (0x8227EB98, "security_init_cookie", "MSVC security cookie initialization"),
    (0x8229D088, "dmc4_main", "MT Framework primary engine entry / WinMain wrapper"),
]


def find_xex() -> pathlib.Path:
    for c in XEX_CANDIDATES:
        if c.is_file() and c.stat().st_size > 3_000_000:
            return c.resolve()
    raise FileNotFoundError("Could not find DMC4 default.xex in known locations.")


def find_rexglue(custom_path: str = None) -> pathlib.Path:
    if custom_path:
        p = pathlib.Path(custom_path).resolve()
        if p.is_file():
            return p
        raise FileNotFoundError(f"Custom rexglue binary not found at {custom_path}")

    which_rex = shutil.which("rexglue") or shutil.which("rexglue.exe")
    if which_rex:
        return pathlib.Path(which_rex).resolve()

    for c in REXGLUE_CANDIDATES:
        if c.is_file():
            return c.resolve()

    return None


def extract_pe_data(xex_path: pathlib.Path):
    sys.path.insert(0, str(SCRIPT_DIR))
    from xex_image import load_xex_image, secciones
    print(f"[build_dmc4_codegen] Unpacking PE image & parsing .pdata from {xex_path.name}...")
    img, pdata = load_xex_image(str(xex_path))
    secs = secciones(img)
    print(f"[build_dmc4_codegen] Decrypted image: {len(img):,} bytes, {len(pdata):,} .pdata functions.")
    return img, pdata, secs


def extract_switch_tables(img: bytes, pdata: list[tuple[int, int]], text_range: tuple[int, int]):
    """
    Scans code for PowerPC Xbox 360 compiler switch idioms:
    lis rX, hi; addi rX, rX, lo; slwi/rlwinm; lwzx; mtctr; bctr.
    Returns:
      switch_tables: dict { table_addr: [target_addrs] }
      indirect_targets: set of target addresses
    """
    print("[build_dmc4_codegen] Scanning for PowerPC compiler switch/jump tables...")
    bctr_inst = 0x4E800420
    text_start, text_end = text_range
    tables = {}
    indirect_targets = set()

    for i in range(16, len(img) - 3, 4):
        inst = struct.unpack_from('>I', img, i)[0]
        if inst == bctr_inst:
            bctr_addr = 0x82000000 + i
            table_base = None

            # Look back up to 10 instructions for lis + addi table address formation
            for back in range(1, 11):
                prev_inst = struct.unpack_from('>I', img, i - back * 4)[0]
                op = prev_inst >> 26
                if op == 14:  # addi
                    rt = (prev_inst >> 21) & 0x1F
                    ra = (prev_inst >> 16) & 0x1F
                    simm = prev_inst & 0xFFFF
                    if simm & 0x8000:
                        simm -= 0x10000
                    # Check instruction immediately before for lis
                    if i - (back + 1) * 4 >= 0:
                        prev_prev = struct.unpack_from('>I', img, i - (back + 1) * 4)[0]
                        if (prev_prev >> 26) == 15:  # addis / lis
                            rt2 = (prev_prev >> 21) & 0x1F
                            ra2 = (prev_prev >> 16) & 0x1F
                            uimm = prev_prev & 0xFFFF
                            if ra2 == 0 and (rt == rt2 or ra == rt2):
                                tbl = (uimm << 16) + simm
                                if 0x82000000 <= tbl < 0x82C00000:
                                    table_base = tbl
                                    break

            if table_base:
                # Read sequential pointer entries
                off = table_base - 0x82000000
                targets = []
                for entry_idx in range(256):
                    if off + entry_idx * 4 + 4 > len(img):
                        break
                    val = struct.unpack_from('>I', img, off + entry_idx * 4)[0]
                    # Check if val is a valid code pointer in text_range aligned to 4 bytes
                    if text_start <= val < text_end and (val & 3) == 0:
                        targets.append(val)
                        indirect_targets.add(val)
                    else:
                        break
                if len(targets) >= 2:
                    tables[table_base] = targets

    print(f"[build_dmc4_codegen] Identified {len(tables):,} switch tables with {len(indirect_targets):,} branch targets.")
    return tables, indirect_targets


def scan_function_pointers(img: bytes, secs: list, text_range: tuple[int, int]):
    """
    Scans .rdata, .data, and MT Framework C++ vtables for 4-byte big-endian pointers.
    Also scans .text for basic-block lis+addi formations and orphaned prologues.
    """
    print("[build_dmc4_codegen] Scanning .rdata, .data, and MT Framework vtables for function pointers...")
    text_start, text_end = text_range
    fn_pointers = set()

    # 1. Scan .rdata and .data sections
    for name, start, end in secs:
        if name in [".rdata", ".data", ".embsec_"]:
            off = start - 0x82000000
            size = end - start
            sec_bytes = img[off:off + size]
            for i in range(0, size - 3, 4):
                val = struct.unpack_from('>I', sec_bytes, i)[0]
                if text_start <= val < text_end and (val & 3) == 0:
                    fn_pointers.add(val)

    # 2. Scan .text for lis rX, hi + addi/ori rX, rX, lo address formations
    off_text = text_start - 0x82000000
    len_text = text_end - text_start
    for i in range(off_text, off_text + len_text - 7, 4):
        inst1 = struct.unpack_from('>I', img, i)[0]
        if (inst1 >> 26) == 15:  # lis (addis rx, 0, imm)
            rt1 = (inst1 >> 21) & 0x1F
            ra1 = (inst1 >> 16) & 0x1F
            uimm = inst1 & 0xFFFF
            if ra1 == 0 and uimm == 0x82:  # 0x82xx address range
                inst2 = struct.unpack_from('>I', img, i + 4)[0]
                op2 = inst2 >> 26
                if op2 == 14:  # addi
                    rt2 = (inst2 >> 21) & 0x1F
                    ra2 = (inst2 >> 16) & 0x1F
                    simm = inst2 & 0xFFFF
                    if simm & 0x8000:
                        simm -= 0x10000
                    if ra2 == rt1:
                        addr = (uimm << 16) + simm
                        if text_start <= addr < text_end and (addr & 3) == 0:
                            fn_pointers.add(addr)
                elif op2 == 24:  # ori
                    rt2 = (inst2 >> 21) & 0x1F
                    ra2 = (inst2 >> 16) & 0x1F
                    uimm2 = inst2 & 0xFFFF
                    if ra2 == rt1:
                        addr = (uimm << 16) | uimm2
                        if text_start <= addr < text_end and (addr & 3) == 0:
                            fn_pointers.add(addr)

    print(f"[build_dmc4_codegen] Discovered {len(fn_pointers):,} valid code references in memory & text.")
    return fn_pointers


def generate_manifest(manifest_path: pathlib.Path, pdata: list[tuple[int, int]],
                      switch_tables: dict, fn_pointers: set,
                      add_entries: list[int] = None, remove_entries: set[int] = None):
    """
    Emits dmc4_manifest.toml using .pdata function bounds as ground truth.
    Filters out any synthetic function start that strictly divides an existing
    .pdata function range (preventing broken loops and unresolved branches).
    """
    print(f"[build_dmc4_codegen] Generating authoritative manifest at {manifest_path.name}...")

    # Start with all .pdata starts
    pdata_starts = {s for s, e in pdata}
    pdata_ranges = pdata

    all_candidates = set(pdata_starts)
    for addr, _, _ in DMC4_KNOWN_SYMBOLS:
        all_candidates.add(addr)

    # Filter function pointers: only accept if NOT strictly dividing a .pdata range
    purged_splits = 0
    for ptr in fn_pointers:
        is_split = False
        for s, e in pdata_ranges:
            if s < ptr < e:
                is_split = True
                break
        if is_split:
            purged_splits += 1
        else:
            all_candidates.add(ptr)

    if add_entries:
        for a in add_entries:
            all_candidates.add(a)

    if remove_entries:
        all_candidates.difference_update(remove_entries)

    cleaned = sorted(all_candidates)
    print(f"[build_dmc4_codegen] Manifest contains {len(cleaned):,} functions ({purged_splits:,} internal splits avoided).")

    lines = [
        "# Devil May Cry 4 (Xbox 360, Title ID: 434307DF, Capcom MT Framework)",
        "# ReXGlue Ahead-Of-Time Codegen Manifest - Verified against .pdata exception table",
        "",
        "[project]",
        'name = "Devil May Cry 4 iOS"',
        'title_id = "434307DF"',
        'version = "1.0.0"',
        'platform = "Xbox 360"',
        'target_architecture = "arm64"',
        'target_os = "iOS"',
        'sdk_version = "0.10.0"',
        'game_root = "game"',
        "",
        "[executable]",
        'file_path = "game/default.xex"',
        'out_directory_path = "generated/default"',
        'entry_point = "0x822901D0"',
        'load_address = "0x82000000"',
        'image_size = "0x00C90000"',
        "",
        "[engine]",
        'name = "MT Framework"',
        'version = "1.4"',
        'developer = "Capcom"',
        'graphics_backend = "Vulkan-MoltenVK"',
        'audio_backend = "CoreAudio"',
        "",
        "[graphics]",
        'target_resolution = [1280, 720]',
        'render_target_path_vulkan = "fbo"',
        'clear_memory_page_state = true',
        'ios_invalidation_widen_kb = 256',
        'occlusion_query_enable = false',
        'readback_memexport = false',
        'readback_resolve = "none"',
        'anisotropic_override = 16',
        "",
        "[audio]",
        'ios_xma_starve_reset = false',
        "",
        "[switch_tables]",
    ]

    for tbl_addr in sorted(switch_tables.keys()):
        targets = switch_tables[tbl_addr]
        targets_str = ", ".join(f"0x{t:08X}" for t in targets)
        lines.append(f"0x{tbl_addr:08X} = [{targets_str}]")

    lines.append("")
    lines.append("[entrypoint]")
    lines.append('file_path = "game/default.xex"')
    lines.append('out_directory_path = "generated/default"')
    lines.append("includes = []")
    lines.append("")
    lines.append("[entrypoint.functions]")

    known_dict = {addr: desc for addr, name, desc in DMC4_KNOWN_SYMBOLS}
    for addr in cleaned:
        desc = known_dict.get(addr)
        if desc:
            lines.append(f"0x{addr:08X} = {{}}  # {desc}")
        else:
            lines.append(f"0x{addr:08X} = {{}}")

    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[build_dmc4_codegen] Wrote {len(cleaned):,} functions to {manifest_path}.")
    return cleaned


def scan_unresolved_branches(gen_dir: pathlib.Path) -> list[tuple[int, int, pathlib.Path, int]]:
    """Scans all generated C++ files for 'Unresolved branch from 0x... to 0x...'."""
    pattern = re.compile(r'Unresolved branch from 0x([0-9A-Fa-f]+) to 0x([0-9A-Fa-f]+)')
    unresolved = []
    cpp_files = list(gen_dir.glob("*.cpp"))
    for f in cpp_files:
        try:
            content = f.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        for line_idx, line in enumerate(content.splitlines(), 1):
            for m in pattern.finditer(line):
                src = int(m.group(1), 16)
                dst = int(m.group(2), 16)
                unresolved.append((src, dst, f, line_idx))
    return unresolved


def run_codegen_loop(rexglue_bin: pathlib.Path, manifest_path: pathlib.Path,
                     gen_dir: pathlib.Path, pdata: list[tuple[int, int]],
                     switch_tables: dict, fn_pointers: set,
                     cwd: pathlib.Path, max_passes: int = 3):
    """
    Executes rexglue codegen and iteratively eliminates unresolved branches.
    """
    remove_set = set()
    add_set = []

    for pass_num in range(1, max_passes + 1):
        print(f"\n============================================================")
        print(f"  [DMC4 Codegen Pass {pass_num}/{max_passes}]")
        print(f"============================================================")
        generate_manifest(manifest_path, pdata, switch_tables, fn_pointers,
                          add_entries=add_set, remove_entries=remove_set)

        cmd = [str(rexglue_bin), "codegen", str(manifest_path), "--ignore-stamp"]
        print(f"[build_dmc4_codegen] Executing: {' '.join(cmd)}")
        res = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True)
        if res.returncode != 0:
            print(f"[build_dmc4_codegen] Codegen failed with code {res.returncode}:")
            print(res.stdout[-2000:])
            print(res.stderr[-2000:])
            raise RuntimeError("rexglue codegen failed")

        unresolved = scan_unresolved_branches(gen_dir)
        print(f"[build_dmc4_codegen] Found {len(unresolved)} unresolved branch(es).")
        if not unresolved:
            print("[build_dmc4_codegen] SUCCESS: ZERO (0) unresolved branches detected!")
            break

        remove_set.clear()
        add_set.clear()
        for src, dst, fpath, lno in unresolved:
            print(f"  Unresolved branch: 0x{src:08X} -> 0x{dst:08X} in {fpath.name}:{lno}")
            if dst < src:
                # Backward loop sliced by synthetic function
                print(f"    Loop split at 0x{src:08X} -> 0x{dst:08X}")
                # Remove any synthetic function between dst and src
                for s in list(fn_pointers):
                    if dst < s <= src:
                        remove_set.add(s)
            else:
                # Forward tail call to unmapped function start
                add_set.append(dst)

    # Final assertion
    final_unresolved = scan_unresolved_branches(gen_dir)
    if final_unresolved:
        print(f"\n[build_dmc4_codegen] FATAL: {len(final_unresolved)} unresolved branch(es) remain:")
        for src, dst, fpath, lno in final_unresolved:
            print(f"  FAILED: 0x{src:08X} -> 0x{dst:08X} ({fpath.name}:{lno})")
        sys.exit(1)


def generate_fallback_stubs(gen_dir: pathlib.Path, pdata: list[tuple[int, int]]):
    """
    Generates sources.cmake and stub registration if running in stub/header mode.
    """
    sources_cmake = gen_dir / "sources.cmake"
    register_cpp = gen_dir / "dmc4_register.cpp"

    gen_dir.mkdir(parents=True, exist_ok=True)
    if not register_cpp.exists():
        content = [
            "// Auto-generated DMC4 Recompilation Function Registration Fallback",
            "#include <cstdint>",
            "#include <rex/runtime.h>",
            "",
            "namespace dmc4::recompiled {",
            "",
            "// Ground-truth CRT entry point for Devil May Cry 4 (Title ID: 434307DF)",
            "void sub_822901D0(rex::Context& ctx) {",
            "    // xstart startup stub",
            "}",
            "",
            "void RegisterFunctions() {",
            "    rex::RegisterFunction(0x822901D0, &sub_822901D0);",
            "}",
            "",
            "} // namespace dmc4::recompiled",
        ]
        register_cpp.write_text("\n".join(content) + "\n", encoding="utf-8")

    if not sources_cmake.exists():
        cmake_content = [
            "# Auto-generated sources.cmake for Devil May Cry 4",
            "set(GENERATED_SOURCES",
            '    "${CMAKE_CURRENT_LIST_DIR}/dmc4_register.cpp"',
            ")",
        ]
        sources_cmake.write_text("\n".join(cmake_content) + "\n", encoding="utf-8")
    print(f"[build_dmc4_codegen] Ensured fallback sources registered at {sources_cmake}.")


def main():
    parser = argparse.ArgumentParser(description="DMC4 AOT Codegen & Branch Healing Pipeline")
    parser.add_argument("--xex", help="Path to DMC4 default.xex")
    parser.add_argument("--rexglue", help="Path to host rexglue binary")
    parser.add_argument("--manifest", help="Path to output dmc4_manifest.toml")
    parser.add_argument("--gen-dir", help="Output generated C++ directory")
    parser.add_argument("--force-codegen", action="store_true", help="Run codegen loop")
    args = parser.parse_args()

    xex_path = pathlib.Path(args.xex).resolve() if args.xex else find_xex()
    manifest_path = pathlib.Path(args.manifest).resolve() if args.manifest else REPO_ROOT / "dmc4_manifest.toml"
    gen_dir = pathlib.Path(args.gen_dir).resolve() if args.gen_dir else REPO_ROOT / "generated" / "default"

    print("===============================================================================")
    print("  DEVIL MAY CRY 4 (XBOX 360, 434307DF) - STATIC RECOMPILATION CODEGEN PIPELINE")
    print("===============================================================================")
    print(f"  Target XEX:    {xex_path}")
    print(f"  Manifest:      {manifest_path}")
    print(f"  Generated Dir: {gen_dir}")

    # 1. Decrypt XEX, extract .pdata, sections
    img, pdata, secs = extract_pe_data(xex_path)

    # Find .text bounds
    text_sec = next(s for s in secs if s[0] == ".text")
    text_range = (text_sec[1], text_sec[2])

    # 2. Extract Switch Tables
    switch_tables, switch_targets = extract_switch_tables(img, pdata, text_range)

    # 3. Scan Function Pointers (.rdata, .data, vtables, lis+addi)
    fn_pointers = scan_function_pointers(img, secs, text_range)
    fn_pointers.update(switch_targets)

    # 4. Generate Authoritative Manifest
    generate_manifest(manifest_path, pdata, switch_tables, fn_pointers)

    # 5. Fallback registration check
    generate_fallback_stubs(gen_dir, pdata)

    # 6. If rexglue CLI is available or requested, run the codegen loop
    rexglue_bin = find_rexglue(args.rexglue)
    if rexglue_bin and (args.force_codegen or os.environ.get("DMC4_FORCE_CODEGEN")):
        print(f"[build_dmc4_codegen] Found host rexglue at: {rexglue_bin}")
        run_codegen_loop(rexglue_bin, manifest_path, gen_dir, pdata, switch_tables, fn_pointers, cwd=REPO_ROOT)
    else:
        print("[build_dmc4_codegen] Host rexglue binary not present in local workspace.")
        print("[build_dmc4_codegen] Manifest & fallback stubs prepared for CI build host.")

    print("\n[build_dmc4_codegen] Pipeline stage completed successfully.")


if __name__ == "__main__":
    main()
