# Kernel configuration

## Base

`base-marble-5.10.236.config` is the exact 6,726-line config extracted from the
kernel inside the supplied `boot.img` (GSI build
`5.10.236-android12-9-00003-gfb24cf99ad97-ab14313284`).  It is the base for
every build; the workflow copies it to `out/.config` before merging the
fragment.

## Requested fragment

`zyomi16-marble.fragment` contains only the requested changes:

- Full LTO (`LTO`, `LTO_CLANG`, `LTO_CLANG_FULL`), local version `-Zyomi16`.
- BakaSU `KSU=y`, `KSU_SUSFS=y` (SUSFS Inline Hook), with
  `KSU_TRACEPOINT_HOOK=n` and `KSU_MANUAL_HOOK=n`.
- `AUDIT=y`, `AUDITSYSCALL=n`.
- `DEBUG_KERNEL`, `DEBUG_INFO`, `SLUB_DEBUG`, `SCHED_DEBUG`, `FTRACE`,
  `PROFILING`, `KPROBES` and `KASAN` off.
- THP always, ZRAM with lz4, `ZSWAP=n`, `ZRAM_WRITEBACK=n`.
- BBR default plus fq/fq_codel/cake/htb/prio, RPS/XPS, veth/bridge/netfilter,
  conntrack/NAT/masquerade and TUN.
- Droidspace namespaces, cgroups and memory controller, overlayfs, FUSE,
  seccomp, POSIX MQ, SYSVIPC, devtmpfs, tmpfs ACL and binfmt_misc.
- All `IP_NF_*`, `IP6_NF_*` and `NETFILTER_XT_*` options, including
  `IP_VS`/`IP_SET` so the ipvs and set matches are available.

`CONFIG_EXPERT` and `CONFIG_EMBEDDED` are turned off only because they
`select DEBUG_KERNEL`; this is required to keep `DEBUG_KERNEL=n`.

## Build fixes

`build-fixes.fragment` contains one value that is needed to build outside the
AOSP build host:

- `CONFIG_TRIM_UNUSED_KSYMS` is disabled.  The extracted GSI config points
  `CONFIG_UNUSED_KSYMS_WHITELIST` at an absolute `/mnt/disks/build-disk/...`
  path; without that file autoksyms aborts.  Disabling trimming also keeps all
  exports available for out-of-tree/vendor modules.

The requested fragment remains 248 symbols; `configure-kernel.sh` merges this
file separately and the generated report lists it under **Build fixes**.

## Small Kconfig patch

`patches/0001-kconfig-allow-zyomi16-options.patch` makes three
hidden upstream defaults reachable:

- `AUDITSYSCALL` was `def_bool y`; it gets a prompt and `default y` so the
  fragment can turn it off while `AUDIT` stays on for SELinux.
- `SLUB_DEBUG` defaulted to `y` when `EXPERT=n`; its default becomes `n` so it
  can stay off without enabling EXPERT/DEBUG_KERNEL.
- `KALLSYMS_ALL` depended on `DEBUG_KERNEL`; the dependency is removed so all
  symbols remain in kallsyms while `DEBUG_KERNEL=n`.  BakaSU needs this for its
  SELinux hooks; the base config already had `KALLSYMS_ALL=y`.

These are the only Kconfig source changes.  No DTS, thermal threshold,
`-O3`, `-march` or `-mtune` change is made.

## Tree-specific notes

- **`CONFIG_ZRAM_DEF_COMP_LZ4` does not exist in this Android 5.10 tree.**
  `drivers/block/zram/zram_drv.c` uses `lz4` as the hardcoded default when
  `CONFIG_CRYPTO_LZ4=y` (which this config sets).  The tweaks module also writes
  `lz4` to each zram `comp_algorithm` at boot.
- **`CONFIG_ZSWAP` is hidden** because `CONFIG_FRONTSWAP` is off.  Its effective
  value is off, which is what was requested.
- **`CONFIG_DEBUG_INFO`, `CONFIG_SCHED_DEBUG` and KASAN sub-options are hidden**
  when `DEBUG_KERNEL`/`KASAN` are off.  They are effectively disabled and are
  reported as `off (hidden/absent)` by `scripts/check-config.py`.

The workflow prints the final `.config` and writes `config-report.md`, which
lists every requested symbol that Kconfig hid, changed or force-enabled.
