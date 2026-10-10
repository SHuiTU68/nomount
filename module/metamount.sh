#!/system/bin/sh

MODDIR=${0%/*}
LOADER="$MODDIR/bin/nm"
MODULES_DIR="/data/adb/modules"
NOMOUNT_DATA="/data/adb/nomount"
LOG_FILE="$NOMOUNT_DATA/nomount.log"
BOOT_SEMAPHORE="$NOMOUNT_DATA/.booting"
TARGET_PARTITIONS="system system_ext vendor odm product apex oem optics prism
                    mi_ext my_bigball my_carrier my_company my_engineering my_heytap
                    my_manifest my_preload my_product my_region my_reserve my_stock"
PROP_FILE="$MODDIR/module.prop"
BASE_DESC="A metamodule that replaces OverlayFS/MagicMount with VFS path redirection."

echo "=== NoMount Injection | Started: $(date) ===" >> "$LOG_FILE"

if ! "$LOADER" version >/dev/null 2>&1; then
    echo "[FATAL] NoMount API not responding; skipping rule injection." >> "$LOG_FILE"
    rm -f "$BOOT_SEMAPHORE"
    exit 1
fi

if [ -f "$NOMOUNT_DATA/disable" ]; then
    echo "[INFO] Safe Mode active. Skipping rule injection." >> "$LOG_FILE"
    rm -f "$BOOT_SEMAPHORE"
    exit 0
fi

for mod_path in "$MODULES_DIR"/*; do
    [ -d "$mod_path" ] || continue
    mod_name="${mod_path##*/}"
    [ "$mod_name" = "nomount" ] && continue

    if [ -f "$mod_path/disable" ] || [ -f "$mod_path/remove" ] || [ -f "$mod_path/skip_mount" ]; then
        echo "[SKIP] Module $mod_name is disabled/removed/skipped" >> "$LOG_FILE"; continue
    fi

    for partition in $TARGET_PARTITIONS; do
        if [ -d "$mod_path/$partition" ]; then
            [ -d "/$partition" ] || [ -d "/system/$partition" ] || continue
            echo "[INFO] Mounting module: $mod_name (/$partition)" >> "$LOG_FILE"
            # nm batches internally per 4K payload page, so xargs can pass as
            # many paths as ARG_MAX allows: one nm process per module instead
            # of one per 200 paths.
            find -L "$mod_path/$partition" \( -type d -o -type c -o -name ".replace" \) -exec sh "$MODDIR/rule-paths.sh" path "$mod_path" {} + 2>/dev/null | xargs -0 -r "$LOADER" rule add --whiteout >> "$LOG_FILE" 2>&1

            find -L "$mod_path/$partition" \( -type f -o -type l \) ! -name ".replace" -exec sh "$MODDIR/rule-paths.sh" pair "$mod_path" {} + 2>/dev/null | xargs -0 -r "$LOADER" rule add >> "$LOG_FILE" 2>&1
        fi
    done
done

echo "=== Injection Complete: $(date) ===" >> "$LOG_FILE"

rm -f "$BOOT_SEMAPHORE"
sed -i "s|^description=.*|description=$BASE_DESC|" "$PROP_FILE"

# Keep the boot log small: the full rule dump would write thousands of lines
# for large modules on every boot. The WebUI queries `nm rule list --json`
# directly, so a one-line count is all the log needs for a sanity check.
echo "[INFO] Active rules: $("$LOADER" rule list | wc -l)" >> "$LOG_FILE"

# Convert leftover module bind mounts into VFS rules (hide /adb/modules
# traces from mountinfo; see hide-mounts.sh).
sh "$MODDIR/hide-mounts.sh" || true

exit 0
