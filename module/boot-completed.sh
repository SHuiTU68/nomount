#!/system/bin/sh

NOMOUNT_DATA="/data/adb/nomount"
LOG_FILE="$NOMOUNT_DATA/nomount.log"
BOOT_SEMAPHORE="$NOMOUNT_DATA/.booting"

if [ -f "$BOOT_SEMAPHORE" ]; then
    rm -f "$BOOT_SEMAPHORE"
    echo "[OK] Boot completed safely." >> "$LOG_FILE"
else
    # Module disabled / skip_mount this boot
    # or metamount.sh already cleaned up to avoid bootloop
    exit 0
fi

# resolve nm binary: from update dir first, then live module
NM_BIN=""
NM_DIR=""
for d in /data/adb/modules_update/nomount /data/adb/modules/nomount; do
    if [ -x "$d/bin/nm" ]; then
        NM_BIN="$d/bin/nm"
        NM_DIR="$d"
        break
    fi
done
[ -f "$NOMOUNT_DATA/disable" ] && exit 0

# Re-apply persistent whiteouts (paths hidden from stock ROM that are
# themselves a tell). The list lives in /data/adb/nomount/whiteouts.txt
# and survives reboots; whiteouts are runtime-only in the engine, so this
# pass is what makes a hide durable.
WHITEOUT_FILE="$NOMOUNT_DATA/whiteouts.txt"
if [ -n "$NM_BIN" ] && [ -f "$WHITEOUT_FILE" ] && "$NM_BIN" version >/dev/null 2>&1; then
    # One nm process for the whole list: nm batches internally per 4K payload
    # page. A leading-slash grep filters comments, blanks and relative paths.
    grep -E '^[[:space:]]*/' "$WHITEOUT_FILE" | tr '\n' '\0' | xargs -0 -r "$NM_BIN" rule add --whiteout >/dev/null 2>&1
    echo "[OK] Re-applied persistent whiteouts." >> "$LOG_FILE"
fi

# Convert leftover module bind mounts into VFS rules (last pass: catches
# mounts created by late-boot components such as theme engines)
if [ -n "$NM_DIR" ]; then
    sh "$NM_DIR/hide-mounts.sh" || true
fi

exit 0
