# Kconfig overrides and audit

The build starts from the exact config inside the supplied `boot.img`
(`configs/base-marble-5.10.236.config`) and applies only
`configs/zyomi16-marble.fragment`.  `make olddefconfig` is then allowed to
resolve dependencies.  `scripts/check-config.py` compares every requested
symbol with the final `.config`.

## Kconfig source changes

`patches/0001-kconfig-allow-zyomi16-options.patch` contains the only Kconfig
source changes:

| Symbol | Upstream rule | Change | Why |
| --- | --- | --- | --- |
| `AUDITSYSCALL` | `def_bool y`, no prompt | prompt added, `default y` | Keep `AUDIT=y` for SELinux while allowing `AUDITSYSCALL=n`. |
| `SLUB_DEBUG` | `default y`, prompt only with `EXPERT` | always prompt, `default n` | Disable SLUB debug without enabling `EXPERT`/`DEBUG_KERNEL`. |
| `KALLSYMS_ALL` | `depends on DEBUG_KERNEL && KALLSYMS` | `depends on KALLSYMS` | BakaSU's SELinux hooks need all symbols while `DEBUG_KERNEL=n`; the base config already had `KALLSYMS_ALL=y`. |

## Build fix outside the requested fragment

`configs/build-fixes.fragment` contains one additional change that is needed to
build the extracted GSI config outside the AOSP build host:

| Symbol | Base value | Final | Why |
| --- | --- | --- | --- |
| `CONFIG_TRIM_UNUSED_KSYMS` | `y` | `n` | The base config sets `CONFIG_UNUSED_KSYMS_WHITELIST` to an absolute `/mnt/disks/build-disk/.../abi_symbollist.raw` path that only exists on the AOSP build machine.  Without it, autoksyms aborts (`whitelist file not found`).  Disabling trimming also keeps exports available to out-of-tree/vendor modules. |

The requested fragment itself remains exactly 248 symbols; the build fix is
merged and audited separately, and the generated report lists it under
**Build fixes**.  No DTS, thermal threshold, CPU frequency, `-O3`, `-march` or
`-mtune` change is made.  `CONFIG_WERROR=y`, `CONFIG_CFI_CLANG=y` and
`CONFIG_SHADOW_CALL_STACK=y` are kept from the base config.

## Requested vs final

The fragment requests **248** symbols.  All are satisfied.  Six requested
`n` symbols are hidden by Kconfig because their parent debug option is off;
their effective value is still off:

| Symbol | Requested | Final | Reason |
| --- | ---: | --- | --- |
| `CONFIG_DEBUG_INFO` | n | absent | `DEBUG_KERNEL=n` hides it. |
| `CONFIG_SCHED_DEBUG` | n | absent | `DEBUG_KERNEL=n` hides it. |
| `CONFIG_KASAN_GENERIC` | n | absent | `KASAN=n` hides the choice. |
| `CONFIG_KASAN_SW_TAGS` | n | absent | `KASAN=n` hides the choice. |
| `CONFIG_KASAN_HW_TAGS` | n | absent | `KASAN=n` hides the choice. |
| `CONFIG_ZSWAP` | n | absent | `FRONTSWAP=n` hides it. |

These are not Kconfig overrides: an absent symbol cannot be enabled and the
generated `config-report.md` records them as `off (hidden/absent)`.

## Specific options

- **LTO**: `CONFIG_LTO=y`, `CONFIG_LTO_CLANG=y`,
  `CONFIG_LTO_CLANG_FULL=y` for the default build.  The Thin fallback uses
  `CONFIG_LTO_CLANG_THIN=y`.
- **KernelSU/SUSFS**: `CONFIG_KSU=y`, `CONFIG_KSU_SUSFS=y` (SUSFS Inline
  Hook), `CONFIG_KSU_MANUAL_HOOK=n`, `CONFIG_KSU_TRACEPOINT_HOOK=n`,
  `CONFIG_KPROBES=n`.
- **Audit**: `CONFIG_AUDIT=y`, `CONFIG_AUDITSYSCALL=n`.
- **Debug**: `CONFIG_DEBUG_KERNEL=n`, `CONFIG_SLUB_DEBUG=n`,
  `CONFIG_FTRACE=n`, `CONFIG_PROFILING=n`, `CONFIG_KASAN=n`.
- **Memory**: `CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y`, `CONFIG_ZRAM=y`,
  `CONFIG_ZRAM_WRITEBACK=n`, `CONFIG_ZSWAP=n` (hidden/off).
  `CONFIG_ZRAM_DEF_COMP_LZ4` is not a symbol in this tree; zram defaults to
  `lz4` when `CONFIG_CRYPTO_LZ4=y`, and the tweaks module writes `lz4` to
  `comp_algorithm` at boot.
- **Networking**: BBR is the default (`CONFIG_DEFAULT_BBR=y`,
  `CONFIG_DEFAULT_TCP_CONG="bbr"`), with fq/fq_codel/cake/htb/prio,
  RPS/XPS, veth, bridge, bridge netfilter, conntrack, NAT, masquerade, TUN,
  all `IP_NF_*`, `IP6_NF_*` and `NETFILTER_XT_*` requested options.
  `CONFIG_IP_VS=y` and `CONFIG_IP_SET=y` are added because
  `NETFILTER_XT_MATCH_IPVS` and `NETFILTER_XT_SET` depend on them.
- **Droidspace**: namespaces, cgroups/controllers, overlayfs, FUSE, seccomp,
  POSIX MQ, SYSVIPC, devtmpfs, tmpfs ACL and binfmt_misc.
- **WERROR**: `CONFIG_WERROR=y` remains in `.config`.  The workflow passes
  `KCFLAGS="-Wno-error"` so a warning in third-party KernelSU/SUSFS code does
  not abort the build.  This is a compiler flag, not a Kconfig override.

The user-space tweaks (BBR, fq/cake, buffers, conntrack timeouts, zram
compressor, THP runtime state) are deliberately *not* in the kernel config.
They live in `tweaks/` and are packaged as `Zyomi16-Tweaks-v1.zip`.

The complete machine-readable audit is produced by the workflow as
`config-report.md` / `config-report.txt`; the final `.config` is printed in
the job log and uploaded as an artifact.
