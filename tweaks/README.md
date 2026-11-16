# Zyomi16 tweaks module

This is a **separate KernelSU/Magisk module**.  It is not part of the kernel
image and does not enable any kernel config option.

## Install

Install `Zyomi16-Tweaks-v1.zip` with the KernelSU/BakaSU manager (or Magisk).
Reboot.  The module writes its log to `/data/local/tmp/zyomi16-tweaks.log`.

## Files

- `service.sh` — waits for `sys.boot_completed`, applies the sysctl file, then
  runs `service.d/*.sh`.
- `post-fs-data.sh` — sets the zram compressor to lz4 and THP to `always`.
- `service.d/10-zyomi16-network.sh` — BBR, fq/cake, socket buffers, conntrack.
- `service.d/20-zyomi16-memory.sh` — zram/VM/THP settings.
- `system/etc/sysctl.d/99-zyomi16-network.conf` — readable copy of the network
  sysctls.  Android does not guarantee that this directory is applied, so
  `service.sh` applies the same values directly.

Every write is guarded by the existence of the relevant `/proc/sys` or
`/sys/class/net` path; missing features are skipped instead of failing boot.
No CPU frequency/governor, RAM limit or thermal settings are modified.

Uninstall the module from the manager to remove it.
