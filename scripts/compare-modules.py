#!/usr/bin/env python3
"""Compare vendor module vermagic and symbol CRCs with a new kernel.

Inputs:
  --symvers out/vmlinux.symvers  (generated with CONFIG_MODVERSIONS=y)
  --vmlinux out/vmlinux          (used to read the exact vermagic string)
  --config out/.config
  --release out/kernel-release.txt
  --module-root out/vendor-modules/vendor_boot-root
  --module-root out/vendor-modules/vendor_dlkm-root

The vendor modules in this repository are from a different GKI build
(5.10.160-gki-gd28eeb36ae86), so vermagic mismatches are expected.  CRC
mismatches are still reported per module in module-compat.csv.
"""

import argparse
import csv
import re
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

COMPRESSED_SUFFIXES = {
    ".xz": ["xz", "-dc"],
    ".gz": ["gzip", "-dc"],
    ".zst": ["zstd", "-dc"],
    ".lz4": ["lz4", "-dc"],
}
MODULE_SUFFIXES = (".ko", ".ko.xz", ".ko.zst", ".ko.gz", ".ko.lz4")


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, **kwargs)


def parse_config(path: Path) -> dict:
    values = {}
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        m = re.match(r"^(CONFIG_[A-Za-z0-9_]+)=(.*)$", line)
        if m:
            values[m.group(1)] = m.group(2).strip()
        elif line.startswith("# CONFIG_") and line.endswith(" is not set"):
            values[line[2:-11]] = "n"
    return values


def parse_symvers(path: Path) -> dict:
    """Return symbol -> CRC integer.  Empty dict means no usable symvers."""
    symvers = {}
    if not path or not path.is_file():
        return symvers
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        try:
            crc = int(parts[0], 16)
        except ValueError:
            continue
        symvers[parts[1]] = crc & 0xFFFFFFFF
    return symvers


def kernel_vermagic(config: dict, release: str, vmlinux: Path | None, log: list) -> str:
    bits = [release]
    if config.get("CONFIG_SMP") == "y":
        bits.append("SMP")
    if config.get("CONFIG_PREEMPT_RT") == "y":
        bits.append("preempt_rt")
    elif config.get("CONFIG_PREEMPT") == "y":
        bits.append("preempt")
    if config.get("CONFIG_MODULE_UNLOAD") == "y":
        bits.append("mod_unload")
    if config.get("CONFIG_MODVERSIONS") == "y":
        bits.append("modversions")
    bits.append("aarch64")
    constructed = " ".join(bits)

    if vmlinux and vmlinux.is_file():
        try:
            proc = run(["strings", "-a", str(vmlinux)], timeout=120)
            pattern = re.compile(r"^" + re.escape(release) + r" .*aarch64$")
            for line in proc.stdout.splitlines():
                if pattern.match(line.strip()):
                    if line.strip() != constructed:
                        log.append(f"vmlinux vermagic: {line.strip()}")
                    return line.strip()
        except Exception as exc:  # noqa: BLE001 - best effort diagnostic only
            log.append(f"could not read vermagic from vmlinux: {exc}")
    return constructed


def find_modules(root: Path) -> list:
    modules = []
    if not root.is_dir():
        return modules
    for path in root.rglob("*"):
        if path.is_file() and path.name.endswith(MODULE_SUFFIXES):
            modules.append(path)
    return sorted(modules)


def module_vermagic(path: Path, tmpdir: Path) -> tuple:
    """Return (path-to-decompressed-module, vermagic, error)."""
    read_path = path
    suffix = next((s for s in MODULE_SUFFIXES[1:] if path.name.endswith(s)), None)
    if suffix:
        cmd = COMPRESSED_SUFFIXES[suffix]
        out = tmpdir / (path.name[:-len(suffix)] + ".ko")
        try:
            with out.open("wb") as fh:
                proc = subprocess.run(
                    cmd + [str(path)], stdout=fh, stderr=subprocess.PIPE, timeout=120
                )
            if proc.returncode != 0:
                return path, "", f"decompress failed: {proc.stderr.decode(errors='replace')[:160]}"
        except Exception as exc:  # noqa: BLE001
            return path, "", f"decompress error: {exc}"
        read_path = out

    proc = run(["modinfo", "-F", "vermagic", str(read_path)], timeout=60)
    if proc.returncode != 0:
        return read_path, "", f"modinfo failed: {proc.stderr.strip()[:160]}"
    return read_path, proc.stdout.strip().splitlines()[0] if proc.stdout.strip() else "", ""


def module_versions(path: Path) -> tuple:
    """Return ([(symbol, crc)], error)."""
    proc = run(["modprobe", "--dump-modversions", str(path)], timeout=60)
    if proc.returncode != 0:
        return [], f"modprobe --dump-modversions failed: {proc.stderr.strip()[:160]}"
    versions = []
    for raw in proc.stdout.splitlines():
        parts = raw.split()
        if len(parts) < 2:
            continue
        try:
            crc = int(parts[0], 16)
        except ValueError:
            continue
        versions.append((parts[1], crc & 0xFFFFFFFF))
    return versions, ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--symvers", type=Path)
    parser.add_argument("--vmlinux", type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--release", required=True, type=Path)
    parser.add_argument("--module-root", action="append", required=True, type=Path)
    parser.add_argument("--out-prefix", required=True, type=Path)
    parser.add_argument("--max-table", type=int, default=100)
    args = parser.parse_args()

    config = parse_config(args.config)
    release = args.release.read_text().strip().splitlines()[0] if args.release.is_file() else str(args.release)
    log = []
    expected_vermagic = kernel_vermagic(config, release, args.vmlinux, log)
    symvers = parse_symvers(args.symvers) if args.symvers else {}

    rows = []
    vendor_vermagics = Counter()
    crc_mismatch_modules = 0
    missing_export_modules = 0
    crc_mismatch_total = 0
    missing_export_total = 0
    mismatch_symbols = Counter()
    missing_symbols = Counter()
    parse_errors = []

    with tempfile.TemporaryDirectory(prefix="module-check-") as tmp:
        tmpdir = Path(tmp)
        for root in args.module_root:
            for module in find_modules(root):
                rel = str(module.relative_to(root))
                read_path, vermagic, vm_error = module_vermagic(module, tmpdir)
                if vm_error:
                    parse_errors.append(f"{rel}: {vm_error}")
                vendor_vermagics[vermagic or "<unknown>"] += 1

                versions, ver_error = module_versions(read_path)
                if ver_error:
                    parse_errors.append(f"{rel}: {ver_error}")

                crc_bad = []
                missing = []
                if symvers and versions:
                    for symbol, crc in versions:
                        kernel_crc = symvers.get(symbol)
                        if kernel_crc is None:
                            missing.append(symbol)
                            missing_symbols[symbol] += 1
                        elif kernel_crc != crc:
                            crc_bad.append(symbol)
                            mismatch_symbols[symbol] += 1
                elif versions and not symvers:
                    # No usable vmlinux.symvers; CRC comparison is unavailable.
                    pass

                if crc_bad:
                    crc_mismatch_modules += 1
                    crc_mismatch_total += len(crc_bad)
                if missing:
                    missing_export_modules += 1
                    missing_export_total += len(missing)

                rows.append({
                    "module": rel,
                    "source": root.name,
                    "vermagic": vermagic,
                    "vermagic_ok": "yes" if vermagic == expected_vermagic else "no",
                    "imports": len(versions),
                    "crc_mismatches": len(crc_bad),
                    "missing_exports": len(missing),
                    "crc_mismatch_symbols": ",".join(sorted(crc_bad)),
                    "missing_symbols": ",".join(sorted(missing)),
                })

    args.out_prefix.parent.mkdir(parents=True, exist_ok=True)
    csv_path = args.out_prefix.with_suffix(".csv")
    with csv_path.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()) if rows else [
            "module", "source", "vermagic", "vermagic_ok", "imports",
            "crc_mismatches", "missing_exports", "crc_mismatch_symbols", "missing_symbols",
        ])
        writer.writeheader()
        writer.writerows(rows)

    total = len(rows)
    vermagic_ok = sum(1 for row in rows if row["vermagic_ok"] == "yes")
    vermagic_bad = total - vermagic_ok

    lines = []
    lines.append("# Vendor module compatibility")
    lines.append("")
    lines.append(f"- New kernel release: `{release}`")
    lines.append(f"- New kernel vermagic: `{expected_vermagic}`")
    lines.append(f"- Vendor modules inspected: **{total}**")
    lines.append(f"- Vermagic matches: **{vermagic_ok}**")
    lines.append(f"- Vermagic mismatches: **{vermagic_bad}**")
    lines.append(f"- Modules with CRC mismatches: **{crc_mismatch_modules}**")
    lines.append(f"- Total CRC mismatched imports: **{crc_mismatch_total}**")
    lines.append(f"- Modules with missing exports: **{missing_export_modules}**")
    lines.append(f"- Total missing exports: **{missing_export_total}**")
    lines.append("")
    lines.append(f"Full per-module data: `{csv_path.name}`")
    lines.append("")

    if vermagic_bad:
        lines.append("## WARNING: vendor modules cannot load")
        lines.append("")
        lines.append("The vendor modules in `vendor_boot.img`/`vendor_dlkm_a.img` were built for a")
        lines.append("different GKI kernel.  The kernel refuses to load a module whose vermagic does")
        lines.append("not match exactly.  With this kernel, stock vendor modules are expected to fail")
        lines.append("with `Exec format error`/`Invalid module format` regardless of CRC values.")
        lines.append("")
        lines.append("A boot image that only replaces `boot` (this project's AnyKernel3/repacked")
        lines.append("boot.img) cannot make the stock vendor modules compatible.  For a stock ROM")
        lines.append("you need a kernel built from the matching 5.10.160 vendor source, or matching")
        lines.append("vendor modules built against this exact kernel.")
        lines.append("")

    if vendor_vermagics:
        lines.append("## Vendor vermagic values")
        lines.append("")
        lines.append("| Vermagic | Modules |")
        lines.append("|---|---:|")
        for value, count in vendor_vermagics.most_common():
            lines.append(f"| `{value or '<unknown>'}` | {count} |")
        lines.append("")

    if not symvers:
        lines.append("## CRC comparison unavailable")
        lines.append("")
        lines.append("`vmlinux.symvers` was missing or empty; per-module CRC values could not be")
        lines.append("compared.  The build still reports vermagic compatibility above.")
        lines.append("")
    else:
        lines.append("## CRC mismatch details")
        lines.append("")
        lines.append("`module_layout` is intentionally versioned by modversions; it is expected to")
        lines.append("differ between unrelated GKI builds.  Other symbols indicate a deeper ABI delta.")
        lines.append("")
        if mismatch_symbols:
            lines.append("Most common mismatched symbols:")
            lines.append("")
            lines.append("| Symbol | Modules importing it |")
            lines.append("|---|---:|")
            for symbol, count in mismatch_symbols.most_common(20):
                lines.append(f"| `{symbol}` | {count} |")
            lines.append("")

        selected = sorted(
            (row for row in rows if row["crc_mismatches"] or row["missing_exports"]),
            key=lambda row: (row["crc_mismatches"] + row["missing_exports"], row["module"]),
            reverse=True,
        )
        lines.append(f"### Modules with CRC mismatches (first {args.max_table})")
        lines.append("")
        if selected:
            lines.append("| Module | Source | CRC mismatches | Missing exports |")
            lines.append("|---|---|---:|---:|")
            for row in selected[:args.max_table]:
                lines.append(f"| `{row['module']}` | {row['source']} | {row['crc_mismatches']} | {row['missing_exports']} |")
            if len(selected) > args.max_table:
                lines.append("")
                lines.append(f"… {len(selected) - args.max_table} more rows in `{csv_path.name}`.")
        else:
            lines.append("No CRC mismatches were found.")
        lines.append("")

    if parse_errors:
        lines.append("## Parse warnings")
        lines.append("")
        for item in parse_errors[:50]:
            lines.append(f"- {item}")
        if len(parse_errors) > 50:
            lines.append(f"- … {len(parse_errors) - 50} more")
        lines.append("")

    if log:
        lines.append("## Notes")
        lines.append("")
        for item in log:
            lines.append(f"- {item}")
        lines.append("")

    report = "\n".join(lines) + "\n"
    md_path = args.out_prefix.with_suffix(".md")
    md_path.write_text(report)
    print(report)

    # A vermagic mismatch is expected with the provided stock modules; it is
    # not a workflow failure.  The report is an artifact and a warning.
    return 0


if __name__ == "__main__":
    sys.exit(main())
