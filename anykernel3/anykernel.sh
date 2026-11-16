### AnyKernel3 Ramdisk Mod Script
## Zyomi16 / POCO F5 (marble, marblein)
## Kernel: @KERNEL_RELEASE@ (@LTO_MODE@ LTO, git @GIT_SHA@)
## The GKI DTB stays in vendor_boot; this zip only installs Image.

### AnyKernel setup
properties() { '
kernel.string=Zyomi16 @KERNEL_RELEASE@ (@LTO_MODE@ LTO) for POCO F5
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=marble
device.name2=marblein
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=1;
SLOT_SELECT=active;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=false;
NO_VBMETA_PARTITION_PATCH=1;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# Unpack the existing boot image and preserve its ramdisk.
dump_boot;

# Required Zyomi16 cmdline additions.  patch_cmdline also strips duplicate
# entries and leading/trailing spaces.
patch_cmdline "cgroup.memory" "cgroup.memory=nokmem";
patch_cmdline "kasan" "kasan=off";
patch_cmdline "audit" "audit=0";

# Repack and write boot.  Do not touch vendor_boot: the marble DTB lives there.
write_boot;

## The original boot.img is a GKI boot image; its ramdisk is kept unchanged.
## The upstream vendor_boot DTB and the stock vendor modules are not modified.
