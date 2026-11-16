#!/system/bin/sh
# Zyomi16 tweaks module entry point.
# Runs after boot.  Every setting is written only if the corresponding kernel
# interface exists, so the module is safe on kernels without a given feature.

MODDIR=${0%/*}
LOG=/data/local/tmp/zyomi16-tweaks.log
SYSCTL_FILE="$MODDIR/system/etc/sysctl.d/99-zyomi16-network.conf"

mkdir -p /data/local/tmp 2>/dev/null
: > "$LOG"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

# Wait for Android userspace, but never block the boot indefinitely.
i=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$i" -lt 60 ]; do
    sleep 5
    i=$((i + 1))
done

# Apply the plain sysctl file first.  Android's toybox sysctl accepts
# "key=value"; values containing spaces are passed as one argument.
if [ -f "$SYSCTL_FILE" ]; then
    log "applying $SYSCTL_FILE"
    while IFS= read -r line; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        case "$line" in
            *=*)
                sysctl -w "$line" >> "$LOG" 2>&1 || log "sysctl skipped: $line"
                ;;
        esac
    done < "$SYSCTL_FILE"
fi

for script in "$MODDIR"/service.d/*.sh; do
    [ -f "$script" ] || continue
    log "running ${script##*/}"
    sh "$script" >> "$LOG" 2>&1 || log "${script##*/} failed"
done

log "done"
