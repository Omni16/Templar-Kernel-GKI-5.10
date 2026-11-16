# SUSFS patch snapshot

Vendored from `simonpunk/susfs4ksu`, branch `gki-android12-5.10`, commit
`784ac9e6fd49bb02499b5b60c57ccc9d0c680204` (2026-11-15):

- `50_add_susfs_in_gki-android12-5.10.patch` — SHA-256
  `bc7b152944cf13384f17238df43fc3c97025c254b61e47afb9864cca1051e041`
- `fs/susfs.c`
- `include/linux/susfs.h`
- `include/linux/susfs_def.h`

The build applies only patch 50 and these source files.  It deliberately does
**not** apply `KernelSU/10_enable_susfs_for_ksu.patch`: BakaSU already contains
SUSFS-aware Kconfig/code and its own SUSFS inline hook mode.

`50_add_susfs...` is tested against the `Templar-LinuxStable` 5.10.271 tree with
`patch -p1 --forward --fuzz=3`; it applies with offsets only and supplies the
required hooks:

```
fs/exec.c:          ksu_handle_execveat
fs/open.c:          ksu_handle_faccessat
fs/read_write.c:    ksu_handle_sys_read
fs/stat.c:          ksu_handle_stat / ksu_handle_vfs_fstat
kernel/sys.c:       ksu_handle_setresuid
kernel/reboot.c:    ksu_handle_sys_reboot
drivers/input/input.c: ksu_handle_input_handle_event
```

This is the non-kprobes path.  `CONFIG_KPROBES=n` is intentional.
