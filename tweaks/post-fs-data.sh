#!/system/bin/sh
# Early zram setup.  Android init usually creates zram0 before this runs, but
# guard every path so a ROM without zram is not broken.

LOG=/data/local/tmp/zyomi16-tweaks.log
mkdir -p /data/local/tmp 2>/dev/null
echo "[$(date '+%Y-%m-%d %H:%M:%S')] post-fs-data: zram compressor" >> "$LOG"

for z in /sys/block/zram*; do
    [ -d "$z" ] || continue
    echo lz4 > "$z/comp_algorithm" 2>/dev/null || true
done

# THP is compiled in as "always"; keep runtime state consistent as well.
if [ -w /sys/kernel/mm/transparent_hugepage/enabled ]; then
    echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
fi
