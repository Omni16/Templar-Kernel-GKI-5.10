# Compatibility notes

## Short version

The kernel builds from a GKI 5.10 tree.  The supplied device images contain
stock vendor modules built for **another** GKI kernel
(`5.10.160-gki-gd28eeb36ae86`).  A boot-only flash of this project's
`boot.img`/AnyKernel3 zip cannot make those modules load.  Test on a matching
ROM or with matching vendor modules, and keep the stock images ready for
rollback.

## Device inputs

| Image | Contents | Count |
| --- | --- | ---: |
| `boot.img` | GKI kernel + generic ramdisk | 1 kernel |
| `vendor_boot.img` | vendor ramdisk + marble DTB | 356 modules |
| `vendor_dlkm_a.img` | EROFS vendor_dlkm, slot A | 312 modules |
| `vbmeta.img` | AVB metadata for the supplied images | — |
| `vendor_dlkm_b` | **0 bytes** in the supplied dump | unusable |

The base config inside `boot.img` identifies the build as
`5.10.236-android12-9-00003-gfb24cf99ad97-ab14313284`.  The stock vendor
modules identify themselves as
`5.10.160-gki-gd28eeb36ae86 SMP preempt mod_unload modversions aarch64`.

This project builds `5.10.271-Zyomi16`, whose vermagic is:

```
5.10.271-Zyomi16 SMP preempt mod_unload modversions aarch64
```

The kernel refuses to load a module unless everything before the first space
(the release string) matches exactly.  Therefore **all 668 supplied vendor
modules report a vermagic mismatch**.  This is reported by
`scripts/compare-modules.py` as 668 mismatches, even if every CRC were equal.
The CRC comparison is still produced from `vmlinux.symvers`; `module_layout`
is intentionally versioned and is expected to differ between unrelated GKI
builds.

## What this means in practice

- Replacing only `boot` (the AnyKernel3 zip or the repacked `boot.img`) leaves
  `vendor_boot` and `vendor_dlkm` untouched.  Their modules still have the old
  vermagic and will fail with `Invalid module format` / `Exec format error`.
  Display, touch, camera, Wi-Fi, audio and other vendor drivers may be among
  them, so the device may not boot.
- Building the vendor modules for this kernel requires the matching
  `vendor`/`vendor_dlkm` source and the exact 5.10.271 config/ABI.  This GKI
  tree does not include marble/sm7475 DTS or vendor drivers, so the workflow
  does not rebuild them.
- A custom ROM whose vendor modules were built for this exact kernel release
  can use the image; a stock 5.10.160 ROM cannot, unless its modules are
  rebuilt.  This is a property of Android GKI, not a packaging bug.
- `vendor_dlkm_b` is 0 bytes in the supplied dump.  Slot B cannot be compared
  or restored from these inputs.

## DTB and vendor_boot

The kernel source is GKI and does not contain the marble/sm7475 device tree.
The workflow therefore reuses the DTB already present in `vendor_boot.img`.
AnyKernel3 is configured with `do.modules=0` and contains only `Image`; it
does not bundle or replace the DTB.  Do not flash a different `vendor_boot`
unless you have a matching stock/custom one.

## AVB / verified boot

The repacked `boot.img` and AnyKernel3 zip are **not AVB-signed**.  The
bootloader will reject them unless verity/verification is disabled (or the
image is signed with the device's keys).  See `docs/ROLLBACK.md` for the
fastboot flags and rollback sequence.

## KernelSU / SUSFS mode

- BakaSU **`main` HEAD at build time**, installed with the official
  `kernel/setup.sh` from <https://bakasu.org/guide/build>.  The exact commit,
  KernelSU version code and full version are in `integration-info.txt`, the job
  log and the artifact name; there is no stale pinned commit.
- `CONFIG_KSU=y`, `CONFIG_KSU_SUSFS=y` (BakaSU's "SUSFS Inline Hook").
- `CONFIG_KSU_MANUAL_HOOK=n`, `CONFIG_KSU_TRACEPOINT_HOOK=n`,
  `CONFIG_KPROBES=n`.
- SUSFS is fetched from the latest `gki-android12-5.10` branch at build time
  (v2.4.0 at the time of writing).  Patch 50 supplies the execve, faccessat,
  stat, read, input, setuid and reboot hooks; the integration script verifies
  each hook after patching.  If a hunk is rejected, the build stops and uploads
  the patch log plus the `.rej` files under `susfs-rejects/`.
- `CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT` is enabled only if the BakaSU Kconfig
  defines it.  `CONFIG_KSU_SUSFS_SUS_SU` is forced off if it exists, because
  the SUSFS inline-hook mode and manual-hook/SUS_SU mode must not be combined.

Do **not** apply `KernelSU/10_enable_susfs_for_ksu.patch`; BakaSU already has
its own SUSFS integration and the extra patch is not part of this build.  Do
not add a hand-written manual sucompat hook in inline-hook mode.

## Configuration compatibility

The final config is derived from the extracted GSI config, not from a stock
Xiaomi 5.10.160 defconfig.  `CONFIG_TRIM_UNUSED_KSYMS` is disabled because the
GSI config's `CONFIG_UNUSED_KSYMS_WHITELIST` is an AOSP build-host path; this
also keeps all exports in `vmlinux.symvers` for module CRC checks.  All requested values are audited by
`scripts/check-config.py`; see `docs/KCONFIG-OVERRIDES.md`.  Six requested
`n` symbols are hidden by Kconfig and remain effectively off (`DEBUG_INFO`,
`SCHED_DEBUG`, three KASAN variants and `ZSWAP`).

## Reporting

The build writes:

- `module-compat.md` and `module-compat.csv` — per-module vermagic, CRC
  mismatch and missing-export counts, plus the full vendor-module list.
- `config-report.md` — requested-vs-final Kconfig audit.
- `integration-info.txt` — BakaSU/SUSFS commit and hook status.

The workflow prints a warning annotation when the vermagic mismatch count is
non-zero; this is expected with the supplied images and is not treated as a
build failure.
