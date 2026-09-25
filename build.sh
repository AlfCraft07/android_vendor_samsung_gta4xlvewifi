#!/usr/bin/env bash
set -euo pipefail

# Standalone vendor.img builder for android_vendor_samsung_gta4xlvewifi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

OUT_DIR="${1:-$REPO_ROOT/out}"
FS_TYPE="${2:-erofs}"
OUT_IMG="$OUT_DIR/vendor.img"

SOURCE_DIR="$REPO_ROOT/vendor"
FS_CONFIG="$REPO_ROOT/config/vendor_fs_config"
FILE_CONTEXTS="$REPO_ROOT/config/vendor_file_contexts"
SIZE_FILE="$REPO_ROOT/config/vendor_size.txt"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "[-] Error: $SOURCE_DIR not found!" >&2
    exit 1
fi

if [ ! -f "$FS_CONFIG" ] || [ ! -f "$FILE_CONTEXTS" ]; then
    echo "[-] Error: config files (vendor_fs_config / vendor_file_contexts) missing!" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_IMG"

echo "=============================================="
echo " Building vendor.img ($FS_TYPE)               "
echo "=============================================="

if [ "$FS_TYPE" = "erofs" ]; then
    MKFS_EROFS="$(command -v mkfs.erofs || true)"
    if [ -z "$MKFS_EROFS" ]; then
        echo "[-] Error: mkfs.erofs not found in PATH." >&2
        echo "[-] Please install erofs-utils (e.g. 'sudo apt install erofs-utils')." >&2
        exit 1
    fi

    echo "[+] Packing $SOURCE_DIR -> $OUT_IMG"

    "$MKFS_EROFS" \
        --mount-point="/vendor" \
        --fs-config-file="$FS_CONFIG" \
        --file-contexts="$FILE_CONTEXTS" \
        -z lz4hc \
        -b 4096 \
        -T 1199145600 \
        "$OUT_IMG" "$SOURCE_DIR"

elif [ "$FS_TYPE" = "ext4" ]; then
    MAKE_EXT4FS="$(command -v make_ext4fs || true)"
    if [ -z "$MAKE_EXT4FS" ]; then
        echo "[-] Error: make_ext4fs not found in PATH." >&2
        exit 1
    fi

    EXTRACTED_SIZE=$(du -sb --apparent-size "$SOURCE_DIR" 2>/dev/null | cut -f1 || du -sk "$SOURCE_DIR" | awk '{print $1 * 1024}')
    SIZE=$(((EXTRACTED_SIZE + 4095) / 4096 * 4096))
    EXTENDED_SIZE=$((SIZE + SIZE / 5))
    [ "$EXTENDED_SIZE" -lt 4349952 ] && EXTENDED_SIZE=4349952

    echo "[+] Packing $SOURCE_DIR -> $OUT_IMG (ext4)"

    "$MAKE_EXT4FS" \
        -l "$EXTENDED_SIZE" \
        -J \
        -b 4096 \
        -S "$FILE_CONTEXTS" \
        -C "$FS_CONFIG" \
        -a "/vendor" \
        -L "vendor" \
        "$OUT_IMG" "$SOURCE_DIR"

    if command -v resize2fs >/dev/null 2>&1; then
        resize2fs -M "$OUT_IMG"
    fi
else
    echo "[-] Error: Unsupported filesystem: $FS_TYPE" >&2
    exit 1
fi

if [ -f "$SIZE_FILE" ]; then
    PARTITION_MAX_SIZE=$(tr -d '[:space:]' < "$SIZE_FILE")
    IMG_SIZE=$(stat -c%s "$OUT_IMG" 2>/dev/null || stat -f%z "$OUT_IMG")
    echo "[+] Built vendor.img: $IMG_SIZE bytes (partition limit: $PARTITION_MAX_SIZE bytes)"
    if [ -n "$PARTITION_MAX_SIZE" ] && [ "$IMG_SIZE" -gt "$PARTITION_MAX_SIZE" ]; then
        echo "[-] Error: vendor.img ($IMG_SIZE bytes) exceeds limit ($PARTITION_MAX_SIZE bytes)!" >&2
        exit 1
    fi
fi

echo "[+] Successfully created $OUT_IMG"
