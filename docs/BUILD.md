# Building the Zyomi16 marble kernel

## What this builds

- Kernel: `5.10.271-Zyomi16` from the `Templar-LinuxStable` snapshot.
- Device: POCO F5 / Redmi Note 12 Turbo (`marble`, `marblein`, SM7475).
- Base config: `configs/base-marble-5.10.236.config`, extracted from the kernel
  inside the supplied `boot.img` (GSI `5.10.236-android12-9-00003-gfb24cf99ad97-ab14313284`).
- Requested changes: `configs/zyomi16-marble.fragment`.
- KernelSU: BakaSU **`main` HEAD at build time**, installed with the official
  setup script from <https://bakasu.org/guide/build>
  (`kernel/setup.sh`).  The script clones BakaSU into `KernelSU/`, checks out
  and pulls `main`, and creates the `drivers/kernelsu` symlink; the full clone
  also contains the top-level `uapi/` directory that `kernel/include/uapi`
  points to.  The commit, KernelSU version code and full version are recorded
  in `integration-info.txt`, the job log and the artifact name.
- SUSFS: the latest `simonpunk/susfs4ksu` **`gki-android12-5.10`** branch at
  build time (v2.4.0 at the time of writing), including patch 50 and the three
  source/header files.  The version and commit are recorded in the log.
- Hook mode: **SUSFS Inline Hook** (`CONFIG_KSU_SUSFS=y`).  No hand-written
  manual sucompat hook is added, and `CONFIG_KSU_MANUAL_HOOK`,
  `CONFIG_KSU_TRACEPOINT_HOOK` and `CONFIG_KPROBES` stay off.  The
  KernelSU-side `10_enable_susfs_for_ksu.patch` is deliberately not applied
  because BakaSU already contains its SUSFS integration.
- Patch safety: SUSFS patch 50 is applied with `--fuzz=0` and no forcing.  If a
  hunk is rejected, the workflow prints the patch output plus every `.rej`
  file/hunk and uploads them as `susfs-rejects/`; it does not continue.
- Logging-off compatibility: SUSFS v2.4.0 calls `SUSFS_LOGI_RL()` even when
  `CONFIG_KSU_SUSFS_ENABLE_LOG=n`, but defines that macro only in the
  logging-enabled branch.  `patches/0002-susfs-log-off-ratelimited-macros.patch`
  adds guarded no-op definitions after the logging block and is applied after
  the SUSFS sources are copied, also with `--fuzz=0`.  It is skipped
  automatically if a later SUSFS revision already defines them.  Patch 50
  itself is unchanged.
- Manager APK: the latest BakaSU GitHub release (including pre-releases) is
  downloaded as an artifact together with `manager-info.txt`, which also links
  the userspace module <https://github.com/sidex15/ksu_module_susfs>.
- Outputs: AnyKernel3 zip, magiskboot-repacked `boot.img`, raw `Image`,
  final `.config`, Kconfig audit, vendor-module vermagic/CRC report and the
  separate tweaks module.

## Toolchain

The base `.config` was produced by Android Clang `r416183b` (12.0.5), so the
workflow installs that exact prebuilt:

```
https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-12.0.0_r1/clang-r416183b.tar.gz
```

Gitiles generates this archive on demand, and two downloads of the same tag can
have different compressed bytes (and even a different uncompressed tar stream
order).  The workflow therefore logs the downloaded SHA-256 for provenance but
does not pin it; instead it rejects a moved tag or a partial download by
checking `AndroidVersion.txt` (`12.0.5`, `based on r416183b`) and the
`clang --version` / `ld.lld --version` output after extraction.

The kernel is built with `LLVM=1 LLVM_IAS=1`.  No `-O3`, `-march` or `-mtune`
is added.  `CONFIG_WERROR=y` is kept in the final config; the workflow passes
`KCFLAGS="-Wno-error"` so warnings from third-party KernelSU/SUSFS code do not
abort the build.  This does not change any Kconfig value.

The workflow uses `ubuntu-latest`, frees the large preinstalled toolchains,
adds a 16 GB swap file, restores the AOSP Clang tarball from the Actions cache
and restores a 4 GB ccache.

## Run the workflow

1. Push the branch containing `.github/workflows/build-zyomi16-marble.yml`.
2. Open **Actions → Build Zyomi16 marble kernel → Run workflow**.
3. Choose one of:
   - `config-only` — apply the patches, generate the final `.config`, run the
     audit and upload the report.  No long build.
   - `full` — Full LTO build, then Thin LTO fallback on failure/timeout.
   - `thin` — Thin LTO only.
4. Keep `thin_fallback` enabled for a Full LTO run.

The reusable implementation is `.github/workflows/_build-kernel.yml`.  The
Full LTO build is limited to 5 h 30 min and the job to 5 h 55 min; a failure,
OOM or timeout triggers the Thin LTO job when `thin_fallback` is enabled.

## Local command equivalents

```bash
# 1. Integrate BakaSU main HEAD + latest SUSFS and the small Kconfig changes
#    (network access required: the official BakaSU setup script and GitLab)
bash scripts/apply-ksu-susfs.sh

# 2. Generate .config from the extracted base + requested fragment
OUT_DIR="$PWD/out" LTO_MODE=full bash scripts/configure-kernel.sh

# 3. Build (clang must be in PATH)
make O="$PWD/out" ARCH=arm64 LLVM=1 LLVM_IAS=1 \
  KCFLAGS="-Wno-error" -j"$(nproc)" Image
make -s O="$PWD/out" ARCH=arm64 LLVM=1 LLVM_IAS=1 kernelrelease \
  > "$PWD/out/kernel-release.txt"

# 4. Extract stock vendor modules and compare
VENDOR_BOOT="$PWD/device-inputs/vendor_boot.img" \
VENDOR_DLKM="$PWD/device-inputs/vendor_dlkm_a.img" \
MAGISKBOOT="$PWD/tools/magiskboot" \
DEST="$PWD/out/vendor-modules" WORK="$PWD/out/vendor-extract" \
  bash scripts/extract-vendor-modules.sh

python3 scripts/compare-modules.py \
  --symvers out/vmlinux.symvers --vmlinux out/vmlinux \
  --config out/.config --release out/kernel-release.txt \
  --module-root out/vendor-modules/vendor_boot-root \
  --module-root out/vendor-modules/vendor_dlkm-root \
  --out-prefix out/module-compat

# 5. Package
OUT_DIR="$PWD/out" LTO_MODE=full \
KERNEL_RELEASE="$(cat out/kernel-release.txt)" \
KERNEL_IMAGE="$PWD/out/arch/arm64/boot/Image" \
BOOT_IMAGE="$PWD/device-inputs/boot.img" \
ARTIFACT_DIR="$PWD/artifacts" WORK_DIR="$PWD/package-work" \
MAGISKBOOT="$PWD/tools/magiskboot" MAGISK_APK="$PWD/tools/Magisk-v27.0.apk" \
RUN_NUMBER=local GITHUB_SHA="$(git rev-parse HEAD)" \
  bash scripts/package.sh
```

## Configuration sources

| File | Purpose |
| --- | --- |
| `configs/base-marble-5.10.236.config` | Exact extracted base config. |
| `configs/zyomi16-marble.fragment` | All requested changes, 248 symbols, including the SUSFS feature options. |
| `configs/ksu-susfs-extra.fragment` | Generated by `apply-ksu-susfs.sh`; contains version-dependent options such as `CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT` only when that symbol exists in the BakaSU tree. |
| `configs/build-fixes.fragment` | Disables `CONFIG_TRIM_UNUSED_KSYMS` because the GSI config embeds an AOSP build-host whitelist path. |
| `patches/0001-kconfig-allow-zyomi16-options.patch` | Makes `AUDITSYSCALL`, `SLUB_DEBUG` and `KALLSYMS_ALL` reachable with `DEBUG_KERNEL=n`. |
| `configs/device-inputs.sha256` | Hashes of the release inputs. |

`configure-kernel.sh` copies the base config, merges the fragment (or the Thin
LTO variant) plus the generated SUSFS-extra fragment, runs `olddefconfig`,
asserts `5.10.271-Zyomi16`, prints the final `.config`, writes the full
`CONFIG_KSU*` list to `out/ksu-config.txt`, and runs `scripts/check-config.py`.
Any requested SUSFS option that olddefconfig turns off is a hard audit failure
and is listed in `config-report.md`.

## Kconfig overrides

See `docs/KCONFIG-OVERRIDES.md` and the generated `config-report.md`.  The
only Kconfig source changes are those in the patch above.  The six requested
options that disappear from `.config` are all requested as `n` and remain
effectively off; they are listed in the audit.

## LTO fallback

Full LTO with CFI is the default.  If the Full LTO job fails (including the
linker being OOM-killed) or reaches the 5 h 30 min build timeout, the main
workflow dispatches the same reusable workflow with `lto: thin`.  The Thin
build uses `CONFIG_LTO_CLANG_THIN=y` and the same source/config otherwise.

## Artifacts

The successful build uploads `artifacts/` under an artifact name that includes
the BakaSU short commit, KernelSU version code and SUSFS version, for example
`zyomi16-marble-full-b7b65bde-ksu35262-susfsv2.4.0-r7-1`:

- `Zyomi16-marble-<release>-<lto>-r<run>.zip` — AnyKernel3 (Image only).
- `boot-Zyomi16-marble-<release>-<lto>-r<run>.img` — repacked boot image.
- `Image-Zyomi16-marble-...` — raw arm64 Image.
- `config-Zyomi16-marble-....txt` — final `.config`.
- `config-report-Zyomi16-marble-....md` — requested-vs-final audit, including
  the full `CONFIG_KSU*` list after olddefconfig.
- `module-compat-Zyomi16-marble-....md/.csv` — vermagic/CRC report.
- `Zyomi16-Tweaks-v1.zip` — separate KernelSU/Magisk tweaks module.
- `ReSukiSU_..._arm64-v8a-release.apk` — latest BakaSU manager APK (the exact
  asset name is preserved).
- `manager-info.txt` — manager release/version, SHA-256, release URL and the
  `sidex15/ksu_module_susfs` userspace module link.
- `integration-info.txt`, `ksu-config.txt` — BakaSU/SUSFS commit and version,
  hook mode, and the final `CONFIG_KSU*` values.
- `SHA256SUMS` and `README.txt`.

The config-only run uploads the config and audit files only.
