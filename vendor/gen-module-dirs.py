#!/usr/bin/env python3
# encoding: utf-8
"""
gen-module-dirs.py — gom module .ko đã build thành 2 bộ thư mục cho AK3
(vendor_boot_modules/ + vendor_dlkm_modules/), thay cho phần cp/strip/rename
của build_bouquet.sh (Pzqqt). Chỉ dùng thư viện chuẩn Python 3.

Ví dụ:
  python3 gen-module-dirs.py \
      --out   kernel/out \
      --lists vendor/modules \
      --dest  ~/zyomi_out/modules \
      --strip "$(command -v llvm-strip)" \
      --report ~/zyomi_out/modules-report.txt

Quy ước (chốt 19-10-2026, đối chiếu build_bouquet.sh dòng 572-582):
  * Danh sách ghi basename; bỏ dòng trống / dòng bắt đầu bằng '#'.
  * Rename DUY NHẤT (theo build_bouquet.sh): qca6490.ko -> qca_cld3_qca6490.ko.
  * bộ vendor_boot = both ∪ vendor_boot   (v2/dump-stock: 314 .ko ship)
  * bộ vendor_dlkm = both ∪ vendor_dlkm   (v2/dump-stock: 265 .ko ship)
  * Module không build được:
      - có trong known-missing.txt -> WARN (chấp nhận thiếu)
      - còn lại                    -> FAIL (exit 2), in đủ danh sách
  * modules.load / modules.load.recovery: LỌC theo bộ ship tương ứng, giữ
    nguyên thứ tự baseline; KHÔNG tự thêm dòng mới (first-stage giữ như stock).
  * modules.blocklist / modules.options: copy nguyên trạng baseline.
  * Mọi .ko copy bằng `llvm-strip -S` (đúng như strip_kmod gốc).
"""

import argparse
import os
import shutil
import subprocess
import sys
import time

RENAME = {"qca6490.ko": "qca_cld3_qca6490.ko"}

PART_DIRS = {"vendor_boot": "vendor_boot_modules", "vendor_dlkm": "vendor_dlkm_modules"}

# fname trong thư mục đích -> (fragment nguồn, có lọc theo bộ ship hay không)
LOAD_FILES = {
    "vendor_boot": [
        ("modules.load", True),
        ("modules.load.recovery", True),
        ("modules.blocklist", False),
    ],
    "vendor_dlkm": [
        ("modules.load", True),
        ("modules.blocklist", False),
        ("modules.options", False),
    ],
}


def die(msg):
    print("!! %s" % msg)
    sys.exit(2)


def read_name_list(path):
    names = []
    if not os.path.isfile(path):
        return names
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            names.append(line.split()[0])
    return names


def dedup(seq):
    seen, out = set(), []
    for x in seq:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="thư mục out/ của kernel build")
    ap.add_argument("--lists", required=True, help="thư mục chứa both.txt/vendor_boot.txt/vendor_dlkm.txt/known-missing.txt/load/")
    ap.add_argument("--dest", required=True, help="thư mục đích (tạo <part>_modules/ bên trong)")
    ap.add_argument("--strip", default="llvm-strip", help="binary strip (mặc định llvm-strip)")
    ap.add_argument("--report", default="", help="file ghi báo cáo (ngoài stdout)")
    args = ap.parse_args()

    if not os.path.isdir(args.out):
        die("không thấy thư mục out: %s" % args.out)
    if not (shutil.which(args.strip) or os.path.isfile(args.strip)):
        die("không thấy strip binary: %s (cần llvm-strip của toolchain clang)" % args.strip)

    load_dir = os.path.join(args.lists, "load")
    both = read_name_list(os.path.join(args.lists, "both.txt"))
    vbc = read_name_list(os.path.join(args.lists, "vendor_boot.txt"))
    vdc = read_name_list(os.path.join(args.lists, "vendor_dlkm.txt"))
    known_missing = set(read_name_list(os.path.join(args.lists, "known-missing.txt")))
    if not both or not vbc or not vdc:
        die("thiếu danh sách module (both.txt / vendor_boot.txt / vendor_dlkm.txt) trong %s" % args.lists)

    # 1) index mọi *.ko trong out/ (bỏ nhánh scripts/ của kernel)
    index = {}
    for root, dirs, files in os.walk(args.out):
        if os.path.basename(root) == "scripts":
            continue
        for fn in files:
            if fn.endswith(".ko"):
                index.setdefault(fn, []).append(os.path.join(root, fn))

    # 2) phân giải từng tên
    sets = {"vendor_boot": dedup(both + vbc), "vendor_dlkm": dedup(both + vdc)}
    plan = {}
    missing_warn, missing_fatal = [], []
    for part, names in sets.items():
        plan[part] = []
        for n in names:
            paths = index.get(n, [])
            if len(paths) > 1:
                print("!! %s có %d nơi chứa — phải xử lý tường minh:" % (n, len(paths)))
                for p in paths:
                    print("     %s" % p)
                sys.exit(2)
            if not paths:
                (missing_warn if n in known_missing else missing_fatal).append(n)
                continue
            plan[part].append((RENAME.get(n, n), paths[0]))

    missing_fatal = sorted(set(missing_fatal))
    if missing_fatal:
        print("!! FAIL: %d module không build được và KHÔNG có trong known-missing.txt:" % len(missing_fatal))
        for n in missing_fatal:
            print("   - %s" % n)
        print("   Nếu thiếu có chủ ý: thêm tên + lý do vào vendor/modules/known-missing.txt")
        sys.exit(2)

    # 3) copy + strip
    os.makedirs(args.dest, exist_ok=True)
    counts = {}
    for part, items in plan.items():
        dst_dir = os.path.join(args.dest, PART_DIRS[part])
        shutil.rmtree(dst_dir, ignore_errors=True)
        os.makedirs(dst_dir)
        seen = set()
        for shipped, src in items:
            if shipped in seen:
                continue
            seen.add(shipped)
            dst = os.path.join(dst_dir, shipped)
            rc = subprocess.run([args.strip, "-S", src, "-o", dst]).returncode
            if rc != 0:
                shutil.copyfile(src, dst)
                print("   [warn] llvm-strip lỗi với %s — copy nguyên bản" % shipped)
            os.chmod(dst, 0o644)
            if os.path.getsize(dst) < 100:
                die("file quá nhỏ (nghi placeholder): %s" % dst)
        counts[part] = len(seen)

    # 4) load lists: lọc theo bộ ship, giữ nguyên thứ tự
    shipped_sets = {p: {s for s, _ in items} for p, items in plan.items()}
    dropped = {}
    for part, files in LOAD_FILES.items():
        dst_dir = os.path.join(args.dest, PART_DIRS[part])
        for fname, do_filter in files:
            src = os.path.join(load_dir, "%s.%s" % (part, fname))
            if not os.path.isfile(src):
                die("thiếu file baseline: %s" % src)
            dst = os.path.join(dst_dir, fname)
            if not do_filter:
                shutil.copyfile(src, dst)
                os.chmod(dst, 0o644)
                continue
            keep, drop = [], []
            with open(src, "r", encoding="utf-8") as f:
                for line in f:
                    name = line.strip()
                    if not name:
                        continue
                    if name in shipped_sets[part]:
                        keep.append(name)
                    else:
                        drop.append(name)
            with open(dst, "w", encoding="utf-8", newline="\n") as f:
                if keep:
                    f.write("\n".join(keep) + "\n")
            os.chmod(dst, 0o644)
            dropped["%s/%s" % (part, fname)] = drop

    # 5) báo cáo
    lines = []
    lines.append("# Báo cáo gen-module-dirs.py — %s UTC" % time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime()))
    lines.append("out   : %s" % args.out)
    lines.append("lists : %s" % args.lists)
    lines.append("Ship  : vendor_boot=%d module, vendor_dlkm=%d module" % (counts["vendor_boot"], counts["vendor_dlkm"]))
    if missing_warn:
        lines.append("Thiếu (known-missing — chấp nhận): %s" % ", ".join(sorted(set(missing_warn))))
    for key in sorted(dropped):
        v = dropped[key]
        lines.append("Load %s: bỏ %d tên không ship%s" % (key, len(v), (": " + ", ".join(v)) if v else ""))
    for part in ("vendor_boot", "vendor_dlkm"):
        ship = shipped_sets[part]
        ref = set()
        for fname, do_filter in LOAD_FILES[part]:
            if do_filter:
                p = os.path.join(load_dir, "%s.%s" % (part, fname))
                with open(p, "r", encoding="utf-8") as f:
                    ref.update(l.strip() for l in f if l.strip())
        extra = sorted(ship - ref)
        lines.append("Ship %s nhưng không xuất hiện trong load list (thông tin): %d tên%s"
                     % (part, len(extra), (": " + ", ".join(extra)) if extra else ""))
    text = "\n".join(lines) + "\n"
    print(text)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as f:
            f.write(text)

    return 0


if __name__ == "__main__":
    sys.exit(main())
