#!/system/bin/sh

MODDIR=${0%/*}
NM_BIN="$MODDIR/bin/nm"
NOMOUNT_DATA="/data/adb/nomount"
LOG_FILE="$NOMOUNT_DATA/nomount.log"

# Hide root-manager bind mounts by converting them into NoMount VFS rules.
#
# Modules and theme engines bind-mount files from /data/adb/modules onto
# system paths, e.g. LSPosed replacing dex2oat or ADB-applied theme
# wallpapers. Those mounts show up in every process' /proc/self/mounts and
# /proc/self/mountinfo, and the mountinfo root field carries the literal
# /adb/modules token - a strong root signal for detectors.
#
# This pass unmounts such binds and adds a VFS redirection rule from the
# mountpoint to the module file, so the path keeps resolving to the module's
# copy while the mount record disappears from every mount table. Mounts whose
# source no longer exists (mountinfo marks them with a trailing //deleted)
# are simply unmounted: their file is gone and stock content shows through.
#
# The pass is idempotent and safe to run repeatedly (metamount.sh, service.sh
# and boot-completed.sh all call it to cover every hook order and late
# mounts). Only file/symlink binds are redirected; directory binds are left
# untouched.

[ -x "$NM_BIN" ] || exit 0
[ -f "$NOMOUNT_DATA/disable" ] && exit 0

# Snapshot first: unmounting while streaming mountinfo reshuffles the file
snapshot=$(cat /proc/self/mountinfo 2>/dev/null) || exit 0
[ -n "$snapshot" ] || exit 0

converted=0
removed=0
started=0

while read -r _id _pid _dev root mpoint _rest; do
    case "$root" in /adb/modules/*) ;; *) continue ;; esac
    [ -n "$mpoint" ] || continue

    if [ "$started" = 0 ]; then
        started=1
        echo "=== Mount Hide | Started: $(date) ===" >> "$LOG_FILE"
    fi

    # mountinfo escapes whitespace as octal; decode before use
    mpoint=$(printf '%b' "$mpoint")
    # strip the "//deleted" marker: the source file was removed after the bind
    src="/data$(printf '%b' "${root%//deleted}")"

    if ! umount "$mpoint" 2>/dev/null && ! umount -l "$mpoint" 2>/dev/null; then
        echo "[WARN] $mpoint: umount failed; mount left in place" >> "$LOG_FILE"
        continue
    fi

    if [ -f "$src" ] || [ -L "$src" ]; then
        if "$NM_BIN" rule add "$mpoint" "$src" >/dev/null 2>&1; then
            echo "[INFO] $mpoint: bind unmounted, redirected to $src" >> "$LOG_FILE"
            converted=$((converted + 1))
        else
            echo "[WARN] $mpoint: bind unmounted, rule add failed" >> "$LOG_FILE"
        fi
    elif [ -d "$src" ]; then
        echo "[WARN] $mpoint: directory binds are not supported; no redirect added" >> "$LOG_FILE"
    else
        echo "[WARN] $mpoint: source $src is gone; unmounted without redirect" >> "$LOG_FILE"
        removed=$((removed + 1))
    fi
done <<EOF
$snapshot
EOF

[ "$started" = 1 ] && echo "=== Mount Hide Complete: $converted redirected, $removed cleaned | $(date) ===" >> "$LOG_FILE"

exit 0
