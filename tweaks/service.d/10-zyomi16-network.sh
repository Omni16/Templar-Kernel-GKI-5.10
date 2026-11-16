#!/system/bin/sh
# BBR + fq/cake, larger socket buffers, conntrack timeouts.
# This is userspace policy only; the kernel image does not contain these values.

write_sysctl() {
    sysctl -w "$1=$2" >/dev/null 2>&1 || true
}

# BBR is the compiled default; set it again for ROMs that overwrite it.
echo bbr > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || true
echo fq > /proc/sys/net/core/default_qdisc 2>/dev/null || true

write_sysctl net.core.rmem_max 25165824
write_sysctl net.core.wmem_max 25165824
write_sysctl net.core.optmem_max 25165824
write_sysctl net.ipv4.tcp_rmem "4096 87380 25165824"
write_sysctl net.ipv4.tcp_wmem "4096 65536 25165824"
write_sysctl net.ipv4.tcp_fastopen 3
write_sysctl net.ipv4.tcp_mtu_probing 1
write_sysctl net.ipv4.tcp_slow_start_after_idle 0
write_sysctl net.ipv4.tcp_notsent_lowat 131072
write_sysctl net.core.netdev_max_backlog 16384
write_sysctl net.core.somaxconn 4096
write_sysctl net.ipv4.tcp_max_syn_backlog 8192
write_sysctl net.ipv4.tcp_fin_timeout 15

write_sysctl net.netfilter.nf_conntrack_max 262144
write_sysctl net.netfilter.nf_conntrack_tcp_timeout_established 86400
write_sysctl net.netfilter.nf_conntrack_tcp_timeout_fin_wait 120
write_sysctl net.netfilter.nf_conntrack_tcp_timeout_time_wait 120
write_sysctl net.netfilter.nf_conntrack_tcp_timeout_close_wait 60
write_sysctl net.netfilter.nf_conntrack_udp_timeout 60
write_sysctl net.netfilter.nf_conntrack_generic_timeout 600

# CAKE on Wi-Fi/ethernet when the qdisc is available; fq on mobile data.
if command -v tc >/dev/null 2>&1; then
    for dev in wlan0 eth0; do
        [ -e "/sys/class/net/$dev" ] || continue
        tc qdisc replace dev "$dev" root cake besteffort >/dev/null 2>&1 || \
            tc qdisc replace dev "$dev" root fq >/dev/null 2>&1 || true
    done
    for dev in rmnet_data0 rmnet_data1 rmnet_data2; do
        [ -e "/sys/class/net/$dev" ] || continue
        tc qdisc replace dev "$dev" root fq >/dev/null 2>&1 || true
    done
fi
