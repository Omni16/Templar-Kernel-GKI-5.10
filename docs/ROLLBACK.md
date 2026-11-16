# Fastboot rollback and recovery — POCO F5 (marble)

These instructions assume an **unlocked bootloader** and working
`adb`/`fastboot` (Android platform-tools).  Keep the original
`boot.img`, `vendor_boot.img`, `vendor_dlkm_a.img` and `vbmeta.img` from the
`device-inputs-v1` release on your PC.  Do not relock the bootloader while any
custom image is installed.

## 1. Identify the active slot

```bash
adb reboot bootloader
fastboot getvar current-slot
fastboot getvar unlocked
```

The output is `a` or `b`.  Set it in your shell:

```bash
SLOT=a          # replace with the value printed above
```

Also check which vbmeta partition exists on your device:

```bash
fastboot getvar all 2>&1 | grep -E 'partition-(type|size):vbmeta'
```

Use `vbmeta_${SLOT}` if the device exposes per-slot partitions; otherwise use
`vbmeta`.  Do **not** flash the supplied 8 KiB `vbmeta.img` to
`vbmeta_system`; it is the top-level vbmeta image, not the system one.

## 2. Minimal rollback (you only flashed `boot`)

If you used the AnyKernel3 zip or `fastboot flash boot_${SLOT} boot-....img`,
only the boot partition changed.  Restore it and the original vbmeta:

```bash
fastboot flash boot_${SLOT} boot.img

# Use vbmeta_${SLOT} only if that partition name exists; otherwise use vbmeta.
fastboot flash vbmeta_${SLOT} vbmeta.img

fastboot reboot
```

Flashing the original `vbmeta.img` restores the stock AVB flags.  If you had
disabled verity/verification to boot the custom image, this undoes that.

## 3. Full restore of the supplied images

The custom images do not modify `vendor_boot` or `vendor_dlkm`.  Restore them
only if you flashed something else there.

```bash
fastboot flash boot_${SLOT} boot.img
fastboot flash vendor_boot_${SLOT} vendor_boot.img

# vendor_dlkm_b was supplied as a 0-byte file; only slot A has a usable image.
if [ "$SLOT" = "a" ]; then
    fastboot flash vendor_dlkm_a vendor_dlkm_a.img
fi

fastboot flash vbmeta_${SLOT} vbmeta.img
fastboot reboot
```

If your device uses a single `vbmeta` partition, replace `vbmeta_${SLOT}` with
`vbmeta`.  If `fastboot` reports `Partition not found`, re-run
`fastboot getvar all` and use the exact name.

## 4. Boot the custom image for a test (optional)

```bash
fastboot --disable-verity --disable-verification flash vbmeta_${SLOT} vbmeta.img
fastboot boot boot-Zyomi16-marble-....img
```

`fastboot boot` loads the image without writing it.  It is still subject to
the stock vendor-module vermagic mismatch described in
`docs/COMPATIBILITY.md`, so it may fail before Android starts.

To flash the custom boot image permanently:

```bash
fastboot --disable-verity --disable-verification flash vbmeta_${SLOT} vbmeta.img
fastboot flash boot_${SLOT} boot-Zyomi16-marble-....img
fastboot reboot
```

The AnyKernel3 zip is an alternative for a custom recovery.  It writes
`Image` to the active boot partition, keeps the existing boot ramdisk, adds
`cgroup.memory=nokmem kasan=off audit=0` to the cmdline and leaves
`vendor_boot`/DTB alone.

## 5. If the device bootloops or fastboot is unavailable

1. Hold **Power + Volume Down** to enter fastboot; retry the minimal rollback.
2. If fastboot works but Android does not, flash a complete stock fastboot ROM
   for `marble` with Xiaomi's `flash_all` script (or MiFlash).  Use the ROM
   matching your region/version; it restores every partition, including both
   slots and `vendor_dlkm`.
3. If fastboot is unavailable, use Xiaomi EDL/MiFlash recovery.  EDL access
   may require an authorized account; do not erase arbitrary partitions.
4. Never run `fastboot oem lock` or `fastboot flashing lock` until the stock
   ROM has booted successfully and you intend to relock.

## 6. Notes and warnings

- The repacked `boot.img` and AnyKernel3 zip are **unsigned**.  AVB must be
  disabled (or the image signed with the device keys) for them to boot.
- The supplied vendor modules were built for `5.10.160-gki-gd28eeb36ae86`, not
  this `5.10.271-Zyomi16` kernel.  A boot-only flash does not rebuild them and
  may leave the device unable to start Android.  Keep the stock images and a
  full fastboot ROM available.
- `vendor_dlkm_b` is 0 bytes in the supplied dump.  Do not flash it; restore
  slot B from a complete stock ROM if needed.
- The tweaks module (`Zyomi16-Tweaks-v1.zip`) is installed from KernelSU/
  BakaSU or Magisk and can be removed independently; it does not touch
  partitions.  Disable/uninstall it from the manager if it causes problems.
- Keep a copy of `SHA256SUMS` and verify the images before flashing:
  `sha256sum -c SHA256SUMS`.
