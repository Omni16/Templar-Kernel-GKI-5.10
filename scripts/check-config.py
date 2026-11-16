#!/usr/bin/env python3
"""Audit the requested Zyomi16 options against a kernel .config.

The fragment is the user's request.  Kconfig is allowed to hide an option that
was requested as "n"; that is still effectively disabled.  An option requested
as "y"/"m" that disappears or changes value is a hard failure.

Exit code is 0 when all requested options are satisfied, 1 otherwise.  The
markdown report also lists the known tree-specific cases (for example
ZRAM_DEF_COMP_LZ4 does not exist in this Android 5.10 tree).
"""

import argparse
import re
import sys
from pathlib import Path

ABSENT = "<absent>"

# Options that are expected to be hidden when DEBUG_KERNEL is off, or because
# a dependency such as FRONTSWAP is off.  They are still reported in the table.
KNOWN_HIDDEN = {
    "CONFIG_DEBUG_INFO",
    "CONFIG_DEBUG_INFO_REDUCED",
    "CONFIG_DEBUG_INFO_DWARF4",
    "CONFIG_SCHED_DEBUG",
    "CONFIG_KASAN_GENERIC",
    "CONFIG_KASAN_SW_TAGS",
    "CONFIG_KASAN_HW_TAGS",
    "CONFIG_ZSWAP",
}

# These are the options that make this build special.  They are also present
# in the fragment, but checking them by name makes a failure much easier to
# spot in the workflow log.
CRITICAL = [
    "CONFIG_AUDIT",
    "CONFIG_AUDITSYSCALL",
    "CONFIG_KALLSYMS_ALL",
    "CONFIG_KSU",
    "CONFIG_KSU_SUSFS",
    "CONFIG_KSU_MANUAL_HOOK",
    "CONFIG_KSU_TRACEPOINT_HOOK",
    "CONFIG_KPROBES",
    "CONFIG_DEBUG_KERNEL",
    "CONFIG_SLUB_DEBUG",
    "CONFIG_FTRACE",
    "CONFIG_PROFILING",
    "CONFIG_ZRAM",
    "CONFIG_ZSWAP",
    "CONFIG_ZRAM_WRITEBACK",
    "CONFIG_TRANSPARENT_HUGEPAGE",
    "CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS",
    "CONFIG_TCP_CONG_BBR",
    "CONFIG_DEFAULT_BBR",
    "CONFIG_CGROUPS",
    "CONFIG_MEMCG",
    "CONFIG_CGROUP_BPF",
    "CONFIG_USER_NS",
    "CONFIG_OVERLAY_FS",
    "CONFIG_FUSE_FS",
    "CONFIG_SECCOMP",
    "CONFIG_BINFMT_MISC",
]

FORCE_ENABLED_WATCH = [
    "CONFIG_DEBUG_KERNEL",
    "CONFIG_EXPERT",
    "CONFIG_EMBEDDED",
    "CONFIG_SLUB_DEBUG",
    "CONFIG_AUDITSYSCALL",
    "CONFIG_KPROBES",
    "CONFIG_FTRACE",
    "CONFIG_PROFILING",
    "CONFIG_KASAN",
    "CONFIG_ZSWAP",
    "CONFIG_SCHED_DEBUG",
    "CONFIG_DEBUG_INFO",
]


def parse_fragment(path: Path) -> dict:
    wanted = {}
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line:
            continue
        m = re.match(r"^(CONFIG_[A-Za-z0-9_]+)=(.*)$", line)
        if m:
            wanted[m.group(1)] = m.group(2).strip()
            continue
        m = re.match(r"^#\s+(CONFIG_[A-Za-z0-9_]+) is not set$", line)
        if m:
            wanted[m.group(1)] = "n"
    return wanted


def parse_config(path: Path) -> dict:
    values = {}
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line:
            continue
        m = re.match(r"^(CONFIG_[A-Za-z0-9_]+)=(.*)$", line)
        if m:
            values[m.group(1)] = m.group(2).strip()
            continue
        m = re.match(r"^#\s+(CONFIG_[A-Za-z0-9_]+) is not set$", line)
        if m:
            values[m.group(1)] = "n"
    return values


def is_off(value) -> bool:
    return value == "n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fragment", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--lto", choices=("full", "thin"), default="full")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()

    wanted = parse_fragment(args.fragment)
    final = parse_config(args.config)

    if not wanted:
        print("ERROR: empty config fragment", file=sys.stderr)
        return 2

    rows = []
    violations = []
    absent_off = []
    satisfied = 0

    for key in sorted(wanted):
        req = wanted[key]
        got = final.get(key)
        if got is None:
            if req == "n":
                status = "off (hidden/absent)"
                absent_off.append(key)
                satisfied += 1
            else:
                status = "MISSING (requested on)"
                violations.append((key, req, got, status))
        elif got == req:
            status = "ok"
            satisfied += 1
        else:
            status = "CHANGED"
            violations.append((key, req, got, status))
        rows.append((key, req, got, status))

    critical_rows = []
    for key in CRITICAL:
        req = wanted.get(key)
        got = final.get(key)
        ok = False
        if req is None:
            ok = got is None or got == "n"
        elif req == "n":
            ok = got is None or got == "n"
        else:
            ok = got == req
        critical_rows.append((key, req, got, "ok" if ok else "FAIL"))
        if not ok and (key, req, got, "CHANGED") not in violations:
            violations.append((key, req, got, "critical failure"))

    # LTO mode is part of the contract: the full build must be Full LTO, and
    # the fallback must be Thin LTO.
    lto_key = "CONFIG_LTO_CLANG_FULL" if args.lto == "full" else "CONFIG_LTO_CLANG_THIN"
    lto_other = "CONFIG_LTO_CLANG_THIN" if args.lto == "full" else "CONFIG_LTO_CLANG_FULL"
    if final.get(lto_key) != "y" or final.get(lto_other) not in (None, "n"):
        violations.append((lto_key, "y", final.get(lto_key), f"LTO mode {args.lto} not selected"))

    force_enabled = [
        key for key in FORCE_ENABLED_WATCH
        if final.get(key) == "y" and wanted.get(key) != "y"
    ]

    lines = []
    lines.append("# Zyomi16 marble configuration audit")
    lines.append("")
    lines.append(f"- LTO mode: **{args.lto}**")
    lines.append(f"- Base config: `configs/base-marble-5.10.236.config`")
    lines.append(f"- Requested symbols: **{len(wanted)}**")
    lines.append(f"- Satisfied: **{satisfied}**")
    lines.append(f"- Hidden-but-off requested symbols: **{len(absent_off)}**")
    lines.append(f"- Violations: **{len(violations)}**")
    lines.append("")
    lines.append("> Hidden-but-off is not a Kconfig override: the symbol does not exist in the final")
    lines.append("> Kconfig because its dependency is disabled, but its effective value is still off.")
    lines.append("")

    lines.append("## Critical checks")
    lines.append("")
    lines.append("| Symbol | Requested | Final | Result |")
    lines.append("|---|---:|---:|---|")
    for key, req, got, status in critical_rows:
        lines.append(f"| `{key}` | {req or '-'} | {got or ABSENT} | {status} |")
    lines.append("")

    lines.append("## Requested vs final differences")
    lines.append("")
    if not rows:
        lines.append("No differences.")
    else:
        lines.append("| Symbol | Requested | Final | Assessment |")
        lines.append("|---|---:|---:|---|")
        for key, req, got, status in rows:
            if status == "ok":
                continue
            lines.append(f"| `{key}` | {req} | {got or ABSENT} | {status} |")
    lines.append("")

    if force_enabled:
        lines.append("## Options Kconfig enabled although not requested")
        lines.append("")
        for key in force_enabled:
            lines.append(f"- `{key}` = `{final.get(key)}`")
        lines.append("")
    else:
        lines.append("## Options Kconfig enabled although not requested")
        lines.append("")
        lines.append("None of the watched debug/LTO options were force-enabled.")
        lines.append("")

    lines.append("## Tree-specific notes")
    lines.append("")
    lines.append("- `CONFIG_ZRAM_DEF_COMP_LZ4` is not a Kconfig symbol in this Android 5.10 tree.")
    lines.append("  The zram driver hardcodes `lz4` as its default when `CONFIG_CRYPTO_LZ4=y`; the")
    lines.append("  tweaks module also writes `lz4` to each zram `comp_algorithm` at boot.")
    lines.append(f"  Final `CONFIG_CRYPTO_LZ4` = `{final.get('CONFIG_CRYPTO_LZ4', ABSENT)}`.")
    lines.append("- `CONFIG_ZSWAP` is hidden when `CONFIG_FRONTSWAP` is off.  Its effective value is off.")
    lines.append("- `CONFIG_DEBUG_INFO`, `CONFIG_SCHED_DEBUG` and the KASAN sub-options disappear when")
    lines.append("  `CONFIG_DEBUG_KERNEL`/`CONFIG_KASAN` are off; their effective values are off.")
    lines.append("")

    if violations:
        lines.append("## Violations")
        lines.append("")
        for key, req, got, status in violations:
            lines.append(f"- `{key}`: requested `{req}`, got `{got or ABSENT}` ({status})")
        lines.append("")

    report = "\n".join(lines) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(report)

    # Keep the log readable: the report in full, followed by a one-line result.
    print(report)
    if violations:
        print(f"CONFIG AUDIT: FAILED ({len(violations)} violations)", file=sys.stderr)
        return 1
    print(f"CONFIG AUDIT: OK ({len(wanted)} requested symbols checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
