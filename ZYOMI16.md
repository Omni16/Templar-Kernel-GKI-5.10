# Zyomi16 — Templar GKI 5.10 for POCO F5 (marble)

This repository snapshot builds a **5.10.271-Zyomi16** arm64 GKI kernel for
the POCO F5 / Redmi Note 12 Turbo (`marble`, `marblein`, SM7475), with:

- BakaSU KernelSU + SUSFS in **inline-hook** mode (no kprobes).
- Full LTO by default, with a Thin LTO fallback.
- The exact config from the supplied GSI `boot.img`, changed only by
  `configs/zyomi16-marble.fragment`.
- THP `always`, zram with lz4, `ZSWAP=n`, BBR/FQ/CAKE, conntrack/NAT, TUN,
  RPS/XPS and the requested Droidspace features.
- A separate KernelSU/Magisk tweaks module for BBR, cake, buffers, conntrack,
  zram and THP runtime settings.

## Start here

| Document | What it covers |
| --- | --- |
| [`docs/BUILD.md`](docs/BUILD.md) | Toolchain, local commands, workflow inputs, artifacts. |
| [`docs/KCONFIG-OVERRIDES.md`](docs/KCONFIG-OVERRIDES.md) | Every Kconfig change/override and the hidden-off cases. |
| [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) | Vendor modules, vermagic, CRC, DTB and AVB limitations. |
| [`docs/ROLLBACK.md`](docs/ROLLBACK.md) | Exact fastboot rollback/recovery commands. |
| [`docs/device-inputs-release.md`](docs/device-inputs-release.md) | Input image hashes and the `device-inputs-v1` release. |
| [`configs/README.md`](configs/README.md) | Base config, fragment and tree-specific notes. |
| [`tweaks/README.md`](tweaks/README.md) | Separate userspace tweaks module. |

## Build

The CI entry point is `.github/workflows/build-zyomi16-marble.yml`.  It calls
`.github/workflows/_build-kernel.yml` in one of three modes:

- `config-only`: patch, generate and audit `.config`; no long build.
- `full`: Full LTO; if it fails, OOMs or exceeds 5 h 30 min, the
  `build-thin-fallback` job runs Thin LTO (when `thin_fallback` is enabled).
- `thin`: Thin LTO only.

The workflow uses `ubuntu-latest`, frees the preinstalled toolchains, adds a
16 GB swap file, restores a cached AOSP Clang `r416183b` and a 4 GB ccache,
and builds with `LLVM=1 LLVM_IAS=1`.

## Outputs

A successful run uploads:

- `Zyomi16-marble-<release>-<lto>-r<run>.zip` — AnyKernel3 (Image only).
- `boot-Zyomi16-marble-<release>-<lto>-r<run>.img` — magiskboot repack.
- `Image-...` — raw arm64 Image.
- `config-...txt` and `config-report-....md` — final config and Kconfig audit.
- `module-compat-....md/.csv` — vendor vermagic/CRC comparison.
- `Zyomi16-Tweaks-v1.zip` — separate tweaks module.
- `ReSukiSU_..._arm64-v8a-release.apk` — latest BakaSU manager APK
  (pre-releases included) plus `manager-info.txt` with its version and the
  `sidex15/ksu_module_susfs` link.
- `SHA256SUMS` and `README.txt`.

## Important warning

The supplied stock vendor modules are from a **different** GKI build
(`5.10.160-gki-gd28eeb36ae86`).  This kernel's vermagic is
`5.10.271-Zyomi16 ...`; all 668 modules are expected to fail vermagic, so a
boot-only flash may not boot a stock ROM.  Read
[`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) before flashing and keep
[`docs/ROLLBACK.md`](docs/ROLLBACK.md) handy.

The repacked boot image and AnyKernel3 zip are unsigned.  AVB/verity must be
disabled (or the image signed) for them to boot.  The marble DTB remains in
`vendor_boot`; this project does not replace it.

## KernelSU integration

- BakaSU: **`main` HEAD at build time**, via the official setup script from
  <https://bakasu.org/guide/build>.  The commit and KernelSU version are
  recorded in `integration-info.txt`, the job log and the artifact name.
- SUSFS: latest `gki-android12-5.10` branch at build time (v2.4.0 at the time
  of writing), patch 50 plus its source/header files.  Logging stays off; a
  strict no-op macro fix covers SUSFS v2.4.0's logging-disabled build path.
- `CONFIG_KSU=y`, `CONFIG_KSU_SUSFS=y`, `CONFIG_KSU_MANUAL_HOOK=n`,
  `CONFIG_KSU_TRACEPOINT_HOOK=n`, `CONFIG_KPROBES=n`.
- The integration script verifies every required hook before the build.  A
  rejected SUSFS hunk stops the build and is reported with the file/hunk and
  `.rej` files instead of being forced.
- The manager APK is downloaded from the latest BakaSU GitHub release,
  including pre-releases; the userspace module is
  <https://github.com/sidex15/ksu_module_susfs>.
