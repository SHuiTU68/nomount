#!/system/bin/sh

NOMOUNT_DATA="/data/adb/nomount"
LOG_FILE="$NOMOUNT_DATA/nomount.log"
BOOT_SEMAPHORE="$NOMOUNT_DATA/.booting"
NM_BIN=""

# resolve nm binary: from update dir first, then live module
for d in /data/adb/modules_update/nomount /data/adb/modules/nomount; do
    if [ -x "$d/bin/nm" ]; then
        NM_BIN="$d/bin/nm"
        break
    fi
done

if [ -f "$BOOT_SEMAPHORE" ]; then
    rm -f "$BOOT_SEMAPHORE"
    echo "[OK] Boot completed safely." >> "$LOG_FILE"
else
    # Module disabled / skip_mount this boot
    # or metamount.sh already cleaned up to avoid bootloop
    exit 0
fi

# Re-apply persistent whiteouts (paths hidden from stock ROM that are
# themselves a tell). The list lives in /data/adb/nomount/whiteouts.txt
# and survives reboots; whiteouts are runtime-only in the engine, so this
# pass is what makes a hide durable. See Suite's whiteout.rs for the idea.
WHITEOUT_FILE="$NOMOUNT_DATA/whiteouts.txt"
if [ -n "$NM_BIN" ] && [ -f "$WHITEOUT_FILE" ]; then
    # only apply once after boot; skip if engine unavailable
    if "$NM_BIN" version >/dev/null 2>&1; then
        grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$WHITEOUT_FILE" | while IFS= read -r wpath; do
            case "$wpath" in
                /*) # absolute path only; ignore malformed entries
                    "$NM_BIN" rule add --whiteout "$wpath" >/dev/null 2>&1
                    ;;
            esac
        done
        echo "[OK] Re-applied persistent whiteouts." >> "$LOG_FILE"
    fi
fi

exit 0