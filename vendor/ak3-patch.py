#!/usr/bin/env python3
# encoding: utf-8
"""
ak3-patch.py — vá AK3 gốc của Pzqqt (branch Marble-Melt của Pzqqt/AnyKernel3)
thành bộ AK3 "Zyomi16 vendor":

  anykernel.sh      : rebrand, 1 Image duy nhất (SHA1_IMAGE), bỏ các prompt
                      không dùng (KSU-patch/360Hz/real-battery/OSS-zram/GPU/ntsync),
                      bỏ copy module _alt (prebuilt vermagic khác), chặn ROM
                      không phải HyperOS/MIUI, giữ nguyên luồng flash gốc.
  make_package.py   : 1 Image (bỏ hdiff/bs_patches), đọc VMLINUX_SYMVERS_FILE +
                      OUTPUT_ZIP_NAME từ env.
  langs/{en,cn}.lang: "Melt Kernel" -> "<kernel_name> Kernel".
  _restore/_rollback: rebrand kernel.string.
  banner            : thay bằng banner của dự án.

Mọi thay thế đều có assert (đúng 1 vị trí / đếm cụ thể) — sai lệch thì FAIL
ngay chứ không âm thầm tạo zip hỏng.

Dùng:
  python3 vendor/ak3-patch.py --ak3 <thư_mục_AK3> --kernel-name Zyomi16 \
      [--banner vendor/banner]
"""

import argparse
import os
import py_compile
import sys

TAB = "\t"


def die(msg):
    print("!! %s" % msg, file=sys.stderr)
    sys.exit(2)


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write(path, content):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)


def visible(s):
    return s.replace(TAB, "<TAB>")


def replace_exact(text, old, new, what, file_name, count=1):
    n = text.count(old)
    if n != count:
        dump = "ak3-patch-debug.txt"
        with open(dump, "w", encoding="utf-8") as f:
            f.write("### %s — mong đợi %d vị trí, tìm thấy %d\n" % (what, count, n))
            f.write("### KHỐI CẦN TÌM (tab hiển thị <TAB>):\n")
            f.write(visible(old))
            f.write("\n")
        die("khối '%s' trong %s: mong đợi %d vị trí, tìm thấy %d (xem %s)"
            % (what, file_name, count, n, dump))
    return text.replace(old, new)


def patch_anykernel(path, name):
    text = read(path)
    orig_len = len(text)

    # R1 — kernel.string
    text = replace_exact(
        text,
        "kernel.string=Melt Kernel by Pzqqt",
        "kernel.string=%s Kernel by Omni16" % name,
        "R1 kernel.string", "anykernel.sh",
    )

    # R2 — 3 placeholder SHA1 -> 1 Image duy nhất
    text = replace_exact(
        text,
        'SHA1_STOCK="@SHA1_STOCK@"\nSHA1_KSU="@SHA1_KSU@"\nSHA1_SUSFS="@SHA1_SUSFS@"',
        'SHA1_IMAGE="@SHA1_IMAGE@"',
        "R2 SHA1 placeholders", "anykernel.sh",
    )

    # R3 — check SHA1 Image
    text = replace_exact(
        text,
        '[ "$(sha1 ${home}/Image)" == "$SHA1_STOCK" ] || abort "! $_LANG_KERNEL_IMAGE_CORRUPTED"',
        '[ "$(sha1 ${home}/Image)" == "$SHA1_IMAGE" ] || abort "! $_LANG_KERNEL_IMAGE_CORRUPTED"',
        "R3 check SHA1", "anykernel.sh",
    )

    # R4 — chặn ROM không phải HyperOS/MIUI (thêm ngay sau khối "Check rom type")
    text = replace_exact(
        text,
        "# Check rom type\n"
        "is_miui_rom=false\n"
        "is_aospa_rom=false\n"
        "is_oss_kernel_rom=false\n"
        "if [ -f /system/framework/MiuiBooster.jar ] && keycode_select \"$_LANG_GUESS_ROM_MIUI\"; then\n"
        + TAB + "is_miui_rom=true\n"
        "elif grep -qiE 'aospa|neoteric' /system/build.prop && keycode_select \"$_LANG_GUESS_ROM_AOSPA\"; then\n"
        + TAB + "is_aospa_rom=true\n"
        "elif keycode_select \"$_LANG_GUESS_ROM_OSS_KERNEL\"; then\n"
        + TAB + "is_oss_kernel_rom=true\n"
        "fi\n",
        "# Check rom type\n"
        "is_miui_rom=false\n"
        "is_aospa_rom=false\n"
        "is_oss_kernel_rom=false\n"
        "if [ -f /system/framework/MiuiBooster.jar ] && keycode_select \"$_LANG_GUESS_ROM_MIUI\"; then\n"
        + TAB + "is_miui_rom=true\n"
        "elif grep -qiE 'aospa|neoteric' /system/build.prop && keycode_select \"$_LANG_GUESS_ROM_AOSPA\"; then\n"
        + TAB + "is_aospa_rom=true\n"
        "elif keycode_select \"$_LANG_GUESS_ROM_OSS_KERNEL\"; then\n"
        + TAB + "is_oss_kernel_rom=true\n"
        "fi\n"
        "\n"
        "# Zyomi16 vendor: CHI ho tro ROM HyperOS/MIUI stock (cac module _alt la placeholder)\n"
        "if ! ${is_miui_rom}; then\n"
        + TAB + "ui_print \" \" \"- Zyomi16 Vendor: chi ho tro ROM HyperOS/MIUI stock\"\n"
        + TAB + "ui_print \"  (AOSP/OSS/AOSPA khong duoc ho tro boi ban build nay)\"\n"
        + TAB + "sleep 3\n"
        + TAB + "abort \"$_LANG_ABORTING\"\n"
        "fi\n",
        "R4 ROM guard", "anykernel.sh",
    )

    # R5 — KernelSU: bake sẵn trong Image, bỏ mọi prompt patch ramdisk
    start_marker = "# KernelSU\n[ -f ${split_img}/ramdisk.cpio ]"
    end_marker = "unset exist_ksu_lkm magisk_patched"
    if text.count(start_marker) != 1:
        die("R5: không tìm thấy đúng 1 mốc bắt đầu 'KernelSU'")
    if text.count(end_marker) != 1:
        die("R5: không tìm thấy đúng 1 mốc kết thúc 'unset exist_ksu_lkm magisk_patched'")
    s = text.index(start_marker)
    e = text.index(end_marker, s) + len(end_marker)
    new_ksu = (
        "# KernelSU (Zyomi16: BakaSU + SUSFS da bake san trong Image tu CI — khong patch ramdisk)\n"
        "[ -f ${split_img}/ramdisk.cpio ] || abort \"! $_LANG_CANNOT_FOUND ramdisk.cpio!\"\n"
        "${bin}/magiskboot cpio ${split_img}/ramdisk.cpio test\n"
        "magisk_patched=$?\n"
        "exist_ksu_lkm=false\n"
        "if ${bin}/magiskboot cpio ${split_img}/ramdisk.cpio \"exists kernelsu.ko\"; then\n"
        + TAB + "${bin}/magiskboot cpio ${split_img}/ramdisk.cpio \"extract kernelsu.ko ${home}/kernelsu.ko\" || \\\n"
        + TAB*2 + "abort \"! $_LANG_FAILED_TO_EXTRACT kernelsu.ko!\"\n"
        + TAB + "if strings ${home}/kernelsu.ko | grep -q 'clang version 12.0.5'; then\n"
        + TAB*2 + "exist_ksu_lkm=true\n"
        + TAB + "else\n"
        + TAB*2 + "ui_print \"- $_LANG_DETECTED_INCOMPATIBLE_KSU_LKM\"\n"
        + TAB*2 + "ui_print \"- $_LANG_UNINSTALLING_KSU_LKM\"\n"
        + TAB*2 + "# TODO: chmod init\n"
        + TAB*2 + "if ${bin}/magiskboot cpio ${split_img}/ramdisk.cpio \\\n"
        + TAB*2 + "    \"rm kernelsu.ko\" \\\n"
        + TAB*2 + "    \"rm init\" \\\n"
        + TAB*2 + "    \"mv init.real init\"; then\n"
        + TAB*3 + "ui_print \"- $_LANG_UNINSTALLING_KSU_LKM_SUCCESS\"\n"
        + TAB*3 + "sleep 3\n"
        + TAB*2 + "else\n"
        + TAB*3 + "abort \"! $_LANG_UNINSTALLING_KSU_LKM_FAILED\"\n"
        + TAB*2 + "fi\n"
        + TAB + "fi\n"
        + TAB + "rm ${home}/kernelsu.ko\n"
        "fi\n"
        "if ${exist_ksu_lkm}; then\n"
        + TAB + "ui_print \"- $_LANG_DETECTED_COMPATIBLE_KSU_LKM_PROMPT_1\"\n"
        + TAB + "ui_print \"- $_LANG_DETECTED_COMPATIBLE_KSU_LKM_PROMPT_2\"\n"
        + TAB + "if [ \"$magisk_patched\" -eq 1 ]; then\n"
        + TAB*2 + "ui_print \"- $_LANG_DETECTED_COMPATIBLE_KSU_LKM_WITH_MAGISK_PROMPT_1\"\n"
        + TAB*2 + "ui_print \"- $_LANG_DETECTED_COMPATIBLE_KSU_LKM_WITH_MAGISK_PROMPT_2\"\n"
        + TAB*2 + "sleep 3\n"
        + TAB + "fi\n"
        "fi\n"
        "unset exist_ksu_lkm magisk_patched"
    )
    text = text[:s] + new_ksu + text[e:]

    # R6 — bỏ module _alt qti_battery_charger_main (NEW/NEW2)
    text = replace_exact(
        text,
        "if ${is_hyperos_fw_with_newer_adsp2}; then\n"
        + TAB + "cp -f ${home}/_alt/NEW2-qti_battery_charger_main.ko ${home}/_vendor_dlkm_modules/qti_battery_charger_main.ko\n"
        + TAB + "cp -f ${home}/_alt/NEW2-qti_battery_charger_main.ko ${home}/_vendor_boot_modules/qti_battery_charger_main.ko\n"
        "elif ${is_hyperos_fw_with_new_adsp2}; then\n"
        + TAB + "cp -f ${home}/_alt/NEW-qti_battery_charger_main.ko ${home}/_vendor_dlkm_modules/qti_battery_charger_main.ko\n"
        + TAB + "cp -f ${home}/_alt/NEW-qti_battery_charger_main.ko ${home}/_vendor_boot_modules/qti_battery_charger_main.ko\n"
        "fi\n",
        "# Zyomi16: qti_battery_charger_main.ko duoc build TU CUNG CAY voi kernel\n"
        "# (da ho tro adsp2 moi — max_life_vol co trong source) — khong dung module\n"
        "# prebuilt cua Pzqqt (vermagic khac se khong nap duoc).\n",
        "R6 battery _alt", "anykernel.sh",
    )

    # R7 — bỏ prompt lineage xiaomi_touch (chi ship ban stock)
    text = replace_exact(
        text,
        "# xiaomi_touch.ko\n"
        "if ${is_lineageos_xiaomi_touch}; then\n"
        + TAB + "ui_print \" \"\n"
        + TAB + "ui_print \"- $_LANG_DETECTED_OSS_XIAOMI_TOUCH_PROMPT_1\"\n"
        + TAB + "ui_print \"- $_LANG_DETECTED_OSS_XIAOMI_TOUCH_PROMPT_2\"\n"
        + TAB + "cp -f ${home}/_alt/xiaomi_touch_los/panel_event_notifier.ko ${home}/_vendor_boot_modules/\n"
        + TAB + "cp -f ${home}/_alt/xiaomi_touch_los/* ${home}/_vendor_dlkm_modules/\n"
        + TAB + "need_depmod_regen_vendor_boot=true\n"
        + TAB + "need_depmod_regen_vendor_dlkm=true\n"
        "fi\n"
        "unset is_lineageos_xiaomi_touch\n",
        "# xiaomi_touch.ko: ban Zyomi16 vendor chi ship xiaomi_touch.ko stock (cung cay kernel).\n"
        "unset is_lineageos_xiaomi_touch\n",
        "R7 lineage touch", "anykernel.sh",
    )

    # R8 — bỏ prompt 360Hz
    text = replace_exact(
        text,
        "# goodix_core.ko\n"
        "if keycode_select \\\n"
        "    \"$_LANG_SELECT_360HZ\" \\\n"
        "    \" \" \\\n"
        "    \"$_LANG_NOTES\" \\\n"
        "    \"$_LANG_SELECT_360HZ_PROMPT_1\" \\\n"
        "    \"$_LANG_SELECT_360HZ_PROMPT_2\"; then\n"
        + TAB + "echo \"options goodix_core force_high_report_rate=y\" >> $vendor_dlkm_modules_options_file\n"
        "fi\n",
        "# goodix_core.ko: prompt 360Hz da bo o ban vendor v1 (giu hanh vi stock).\n",
        "R8 360Hz", "anykernel.sh",
    )

    # R9 — bỏ prompt real battery (giữ biến cho khối fix_battery_usage phía sau)
    text = replace_exact(
        text,
        "# qti_battery_charger_main.ko\n"
        "qti_battery_charger_mod_options=\"\"\n"
        "if keycode_select \\\n"
        "    \"$_LANG_SELECT_REAL_BATTERY\" \\\n"
        "    \" \" \\\n"
        "    \"$_LANG_NOTES\" \\\n"
        "    \"$_LANG_SELECT_REAL_BATTERY_PROMPT_1\" \\\n"
        "    \"$_LANG_SELECT_REAL_BATTERY_PROMPT_2\"; then\n"
        + TAB + "qti_battery_charger_mod_options=\"${qti_battery_charger_mod_options} report_real_capacity=y\"\n"
        "fi\n",
        "# qti_battery_charger_main.ko\n"
        "qti_battery_charger_mod_options=\"\"\n",
        "R9 real battery prompt", "anykernel.sh",
    )

    # R10 — bỏ OSS zram prompt (dùng bản build cùng cây)
    text = replace_exact(
        text,
        "# OSS zram.ko & zsmalloc.ko\n"
        "if ${is_miui_rom}; then\n"
        + TAB + "if ! keycode_select \\\n"
        + TAB + "    \"$_LANG_SELECT_OSS_ZRAM\" \\\n"
        + TAB + "    \" \" \\\n"
        + TAB + "    \"$_LANG_NOTES\" \\\n"
        + TAB + "    \"$_LANG_SELECT_OSS_ZRAM_PROMPT_1\" \\\n"
        + TAB + "    \"$_LANG_SELECT_OSS_ZRAM_PROMPT_2\" \\\n"
        + TAB + "    \"$_LANG_SELECT_OSS_ZRAM_PROMPT_3\" \\\n"
        + TAB + "    \"$_LANG_SELECT_OSS_ZRAM_PROMPT_4\"; then\n"
        + TAB*2 + "cp -f ${home}/_alt/MI-zram.ko     ${home}/_vendor_dlkm_modules/zram.ko\n"
        + TAB*2 + "cp -f ${home}/_alt/MI-zram.ko     ${home}/_vendor_boot_modules/zram.ko\n"
        + TAB*2 + "cp -f ${home}/_alt/MI-zsmalloc.ko ${home}/_vendor_dlkm_modules/zsmalloc.ko\n"
        + TAB*2 + "cp -f ${home}/_alt/MI-zsmalloc.ko ${home}/_vendor_boot_modules/zsmalloc.ko\n"
        + TAB + "fi\n"
        "fi\n",
        "# OSS zram.ko & zsmalloc.ko: dung ban build tu cung cay kernel (khong prebuilt MI).\n",
        "R10 OSS zram", "anykernel.sh",
    )

    # R11 — bỏ prompt giả GPU
    text = replace_exact(
        text,
        "# Disguised the GPU model as Adreno730v3\n"
        "disguised_adreno730=false\n"
        "if keycode_select \\\n"
        "    \"$_LANG_SELECT_DISGUISED_ADRENO730\" \\\n"
        "    \" \" \\\n"
        "    \"$_LANG_NOTES\" \\\n"
        "    \"$_LANG_SELECT_DISGUISED_ADRENO730_PROMPT_1\" \\\n"
        "    \"$_LANG_SELECT_DISGUISED_ADRENO730_PROMPT_2\" \\\n"
        "    \"$_LANG_SELECT_DISGUISED_ADRENO730_PROMPT_3\" \\\n"
        "    \"$_LANG_SELECT_DISGUISED_ADRENO730_PROMPT_4\"; then\n"
        + TAB + "disguised_adreno730=true\n"
        "fi\n",
        "# Disguised the GPU model as Adreno730v3\n"
        "disguised_adreno730=false   # Zyomi16 vendor: prompt gia GPU da bo (giu mac dinh)\n",
        "R11 GPU disguise", "anykernel.sh",
    )

    # R12 — bỏ ntsync
    text = replace_exact(
        text,
        "# ntsync.ko\n"
        "if keycode_select \\\n"
        "    \"$_LANG_SELECT_NTSYNC\" \\\n"
        "    \" \" \\\n"
        "    \"$_LANG_NOTES\" \\\n"
        "    \"$_LANG_SELECT_NTSYNC_PROMPT_1\"; then\n"
        + TAB + "cp -f ${home}/_alt/ntsync.ko ${home}/_vendor_dlkm_modules/ntsync.ko\n"
        + TAB + "echo 'ntsync.ko' >> ${home}/_vendor_dlkm_modules/modules.load\n"
        + TAB + "need_depmod_regen_vendor_dlkm=true\n"
        "fi\n",
        "# ntsync.ko: khong ship o ban vendor v1.\n",
        "R12 ntsync", "anykernel.sh",
    )

    # R13 — tên backup zip
    text = replace_exact(
        text,
        'backup_package=/sdcard/Melt-restore-kernel-$(file_getprop /system/build.prop ro.build.version.incremental)-$(date +"%Y%m%d-%H%M%S").zip',
        'backup_package=/sdcard/%s-restore-kernel-$(file_getprop /system/build.prop ro.build.version.incremental)-$(date +"%%Y%%m%%d-%%H%%M%%S").zip' % name,
        "R13 backup name", "anykernel.sh",
    )

    # R14 — bỏ khối OSS msm_drm (mọi nhánh đều copy module _alt placeholder — không ship)
    text = replace_exact(
        text,
        "# OSS msm_drm.ko\n"
        "use_oss_msm_drm=false\n"
        "if ${is_oss_kernel_rom} || ${is_aospa_rom} || [ -f /vendor/bin/sensor-notifier ]; then\n"
        + TAB + "use_oss_msm_drm=true\n"
        "elif ! ${is_miui_rom}; then  # For roms ported from other OS\n"
        + TAB + "use_oss_msm_drm=false\n"
        "elif keycode_select \\\n"
        "    \"$_LANG_SELECT_OSS_MSM_DRM\" \\\n"
        "    \" \" \\\n"
        "    \"$_LANG_NOTES\" \\\n"
        "    \"$_LANG_SELECT_OSS_MSM_DRM_PROMPT_1\"; then\n"
        + TAB + "use_oss_msm_drm=true\n"
        "fi\n"
        "if ${use_oss_msm_drm}; then\n"
        + TAB + "if [ -f /vendor/etc/displayconfig/display_id_4630946370515662721.xml ] || [ -f /vendor/etc/displayconfig/display_id_4630946480857061761.xml ]; then\n"
        + TAB*2 + "# https://github.com/cupid-development/android_device_xiaomi_marble/commit/eee64379280d5bc680e91371679d788b63fe5039\n"
        + TAB*2 + "cp -f ${home}/_alt/OSS-msm_drm-2.ko ${home}/_vendor_dlkm_modules/msm_drm.ko\n"
        + TAB*2 + "cp -f ${home}/_alt/OSS-msm_drm-2.ko ${home}/_vendor_boot_modules/msm_drm.ko\n"
        + TAB + "else\n"
        + TAB*2 + "cp -f ${home}/_alt/OSS-msm_drm.ko ${home}/_vendor_dlkm_modules/msm_drm.ko\n"
        + TAB*2 + "cp -f ${home}/_alt/OSS-msm_drm.ko ${home}/_vendor_boot_modules/msm_drm.ko\n"
        + TAB + "fi\n"
        "fi\n"
        "unset use_oss_msm_drm\n",
        "# OSS msm_drm.ko: bo o ban Zyomi16 vendor — AK3 goc chi co placeholder _alt;\n"
        "# ROM stock dung msm_drm.ko build tu CUNG cay kernel (khong thay the).\n",
        "R14 OSS msm_drm", "anykernel.sh",
    )

    # R15 — bỏ khối OSS camera (cùng lý do)
    text = replace_exact(
        text,
        "# OSS camera.ko\n"
        "use_oss_camera_driver=false\n"
        "if ${is_oss_kernel_rom} || ${is_aospa_rom}; then\n"
        + TAB + "use_oss_camera_driver=true\n"
        "elif ! ${is_miui_rom}; then  # For roms ported from other OS\n"
        + TAB + "use_oss_camera_driver=false\n"
        "elif keycode_select \\\n"
        "    \"$_LANG_SELECT_OSS_CAMERA\" \\\n"
        "    \" \" \\\n"
        "    \"$_LANG_NOTES\" \\\n"
        "    \"$_LANG_SELECT_OSS_CAMERA_PROMPT_1\"; then\n"
        + TAB + "use_oss_camera_driver=true\n"
        "fi\n"
        "if ${use_oss_camera_driver}; then\n"
        + TAB + "cp -f ${home}/_alt/OSS-camera.ko ${home}/_vendor_dlkm_modules/camera.ko\n"
        "fi\n"
        "unset use_oss_camera_driver\n",
        "# OSS camera.ko: bo o ban Zyomi16 vendor — AK3 goc chi co placeholder _alt.\n",
        "R15 OSS camera", "anykernel.sh",
    )

    # kiểm tra tổng
    if "@SHA1_IMAGE@" not in text:
        die("anykernel.sh thiếu @SHA1_IMAGE@ (make_package cần placeholder này)")
    for bad in ("@SHA1_STOCK@", "@SHA1_KSU@", "@SHA1_SUSFS@"):
        if bad in text:
            die("anykernel.sh còn %s" % bad)
    if "bs_patches" in text:
        die("anykernel.sh còn tham chiếu bs_patches")
    for gone in ("Melt Kernel", "Melt-restore-kernel",
                 "use_oss_msm_drm", "use_oss_camera_driver",
                 "_alt/OSS-msm_drm", "_alt/OSS-camera",
                 "_alt/NEW2-", "_alt/NEW-",
                 "_alt/ntsync", "_alt/xiaomi_touch_los",
                 "_alt/MI-zram", "_alt/MI-zsmalloc"):
        if gone in text:
            die("anykernel.sh còn chuỗi '%s'" % gone)

    write(path, text)
    print("[ok] anykernel.sh: %d -> %d bytes" % (orig_len, len(text)))


NEW_MAIN = '''def main_multi(build_version):
    image = local_path("Image")
    temp_ak_sh = temp_path("anykernel.sh")
    temp_image_7z = temp_path("Image.7z")
    temp_dtb_7z = temp_path("_dtb.7z")
    temp_mods_hos_7z = temp_path("_modules_hyperos.7z")

    assert os.path.exists(image)

    rich.print("[yellow][1/8][/yellow] [green]Generating SHA1 for image file...[/green]")
    sha1_image = get_sha1(image)
    print("SHA1 for Image:", sha1_image)

    rich.print("[yellow][2/8][/yellow] [green]Regenerating module dependency information...[/green]")
    assert do_depmod_regen(local_path("_modules_hyperos", "_vendor_boot_modules"), "/lib/modules/") == 0
    assert do_depmod_regen(local_path("_modules_hyperos", "_vendor_dlkm_modules"), "/vendor/lib/modules/") == 0

    rich.print("[yellow][3/8][/yellow] [green]Simulating loading kernel modules...[/green]")
    assert do_simulate_load_kernel_modules(
        VMLINUX_SYMVERS_FILE,
        local_path("_modules_hyperos", "_vendor_boot_modules", "modules.load.recovery"), "/lib/modules/",
    ) == 0
    assert do_simulate_load_kernel_modules(
        VMLINUX_SYMVERS_FILE,
        local_path("_modules_hyperos", "_vendor_boot_modules", "modules.load"), "/lib/modules/",
        local_path("_modules_hyperos", "_vendor_dlkm_modules", "modules.load"), "/vendor/lib/modules/",
    ) == 0

    try:
        rich.print("[yellow][4/8][/yellow] [green]Compressing Image.7z ...[/green]")
        make_7z(local_path("Image"), temp_image_7z)

        rich.print("[yellow][5/8][/yellow] [green]Compressing _modules_hyperos.7z ...[/green]")
        make_7z(local_path("_modules_hyperos"), temp_mods_hos_7z, extra_args="-mf=off")

        rich.print("[yellow][6/8][/yellow] [green]Compressing _dtb.7z ...[/green]")
        make_7z(local_path("_dtb"), temp_dtb_7z)

        rich.print("[yellow][7/8][/yellow] [green]Making zip package...[/green]")
        with change_dir(BASE_DIR):
            with open("anykernel.sh", "r", encoding='utf-8') as f1:
                with open(temp_ak_sh, "w", encoding='utf-8', newline='\\n') as f2:
                    f2.write(f1.read().replace("@SHA1_IMAGE@", sha1_image))
            zip_file = make_zip(
                "META-INF", "tools", "langs",
                temp_mods_hos_7z, temp_dtb_7z, temp_image_7z, temp_ak_sh,
                "_restore_anykernel.sh", "_rollback_anykernel.sh",
                "LICENSE", "banner",
            )
    finally:
        remove_path(temp_ak_sh)
        remove_path(temp_mods_hos_7z)
        remove_path(temp_dtb_7z)
        remove_path(temp_image_7z)

    rich.print("[yellow][8/8][/yellow] [green]Signing zip package...[/green]")
    if SIGN_ZIP:
        try:
            sign_zip(zip_file)
        except AssertionError:
            remove_path(zip_file)
            raise
    else:
        print("Skipping signing zip package...")

    zip_name = os.environ.get("OUTPUT_ZIP_NAME") or (PACKAGE_NAME_MULTI % build_version)
    dst_zip_file = local_path(zip_name)
    file2file(zip_file, dst_zip_file, move=True)

    print(" ")
    rich.print("[green]Done! Output file: %s[/green]" % dst_zip_file)

'''


def patch_make_package(path):
    text = read(path)

    text = replace_exact(
        text,
        "VMLINUX_SYMVERS_FILE = '/home/pzqqt/working/android_kernel_xiaomi_marble/out/vmlinux.symvers'",
        'VMLINUX_SYMVERS_FILE = os.environ.get("VMLINUX_SYMVERS_FILE", "vmlinux.symvers")',
        "MP1 symvers", "make_package.py",
    )
    text = replace_exact(
        text,
        'assert shutil.which("hdiffz")',
        "# hdiffz: khong dung trong ban Zyomi16 vendor (chi 1 Image duy nhat)",
        "MP2 hdiffz", "make_package.py",
    )
    text = replace_exact(
        text,
        'PACKAGE_NAME_MULTI = "Melt-marble-%s-multi.zip"',
        'PACKAGE_NAME_MULTI = "Zyomi16-vendor-%s.zip"',
        "MP3 package name", "make_package.py",
    )

    s = text.index("def main_multi(build_version):")
    e = text.index('if __name__ == "__main__":', s)
    text = text[:s] + NEW_MAIN + "\n" + text[e:]

    for gone in ("Image_ksu", "Image_susfs", "bs_patches", "@SHA1_STOCK@", "hdiffz("):
        if gone in text:
            die("make_package.py còn '%s' — thay thế chưa trọn" % gone)
    if "@SHA1_IMAGE@" not in text:
        die("make_package.py thiếu @SHA1_IMAGE@")

    write(path, text)
    try:
        py_compile.compile(path, doraise=True)
    except py_compile.PyCompileError as ex:
        die("make_package.py sau patch không compile được: %s" % ex)
    print("[ok] make_package.py đã patch + compile OK")


def patch_lang(path, name):
    text = read(path)
    n = text.count("Melt Kernel")
    if n < 1:
        die("%s: không thấy 'Melt Kernel'" % path)
    text = text.replace("Melt Kernel", "%s Kernel" % name)
    if "Melt" in text:
        die("%s: còn sót chữ 'Melt' sau rebrand" % path)
    write(path, text)
    print("[ok] %s: rebrand %d chỗ" % (os.path.basename(path), n))


def patch_script_string(path, old, new):
    text = read(path)
    text = replace_exact(text, old, new, "kernel.string", os.path.basename(path))
    write(path, text)
    print("[ok] %s: kernel.string -> rebrand" % os.path.basename(path))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ak3", required=True, help="thư mục AK3 gốc (Pzqqt/AnyKernel3 @ Marble-Melt)")
    ap.add_argument("--kernel-name", default="Zyomi16")
    ap.add_argument("--banner", default="", help="file banner của dự án (ghi đè banner AK3)")
    args = ap.parse_args()

    ak3 = args.ak3
    name = args.kernel_name
    if not os.path.isdir(ak3):
        die("không thấy thư mục AK3: %s" % ak3)
    for rel in ("anykernel.sh", "make_package.py", "langs/en.lang", "langs/cn.lang",
                "_restore_anykernel.sh", "_rollback_anykernel.sh", "META-INF", "tools"):
        if not os.path.exists(os.path.join(ak3, rel)):
            die("AK3 thiếu thành phần: %s" % rel)

    print("== Patch AK3 cho %s ==" % name)
    patch_anykernel(os.path.join(ak3, "anykernel.sh"), name)
    patch_make_package(os.path.join(ak3, "make_package.py"))
    patch_lang(os.path.join(ak3, "langs/en.lang"), name)
    patch_lang(os.path.join(ak3, "langs/cn.lang"), name)
    patch_script_string(os.path.join(ak3, "_restore_anykernel.sh"),
                        "kernel.string=Restore kernel",
                        "kernel.string=Restore kernel (%s)" % name)
    patch_script_string(os.path.join(ak3, "_rollback_anykernel.sh"),
                        "kernel.string=Rollback kernel",
                        "kernel.string=Rollback kernel (%s)" % name)

    banner_dst = os.path.join(ak3, "banner")
    if args.banner:
        if not os.path.isfile(args.banner):
            die("không thấy banner: %s" % args.banner)
        src = read(args.banner)
        if not src.strip():
            die("banner rỗng: %s" % args.banner)
        write(banner_dst, src)
        print("[ok] banner đã thay (%d bytes)" % len(src))
    elif not os.path.isfile(banner_dst):
        die("AK3 không có banner và không truyền --banner")
    else:
        print("[i] giữ banner có sẵn trong AK3")

    print("== PATCH AK3 OK ==")


if __name__ == "__main__":
    main()
