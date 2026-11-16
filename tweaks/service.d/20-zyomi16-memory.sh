#!/system/bin/sh
# Zram / VM defaults.  No CPU or RAM hard limits are applied.

write_sysctl() {
    sysctl -w "$1=$2" >/dev/null 2>&1 || true
}

for z in /sys/block/zram*; do
    [ -d "$z" ] || continue
    echo lz4 > "$z/comp_algorithm" 2>/dev/null || true
done

echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true

write_sysctl vm.swappiness 100
write_sysctl vm.page-cluster 0
write_sysctl vm.watermark_boost_factor 0
write_sysctl vm.watermark_scale_factor 125
write_sysctl vm.dirty_ratio 10
write_sysctl vm.dirty_background_ratio 5
write_sysctl vm.vfs_cache_pressure 50
