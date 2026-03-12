#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH="$ROOT_DIR/config/resource-manifest.lock"

download_http() {
    local url="$1"
    local target="$2"

    mkdir -p "$(dirname "$target")"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$target"
    else
        wget -q "$url" -O "$target"
    fi
}

verify_sha() {
    local target="$1"
    local expected="$2"

    if [ "$expected" = "-" ] || [ -z "$expected" ]; then
        return 0
    fi

    local actual
    actual="$(sha256sum "$target" | awk '{print $1}')"
    [ "$actual" = "$expected" ]
}

fetch_git_repo() {
    local url="$1"
    local ref="$2"
    local target="$3"

    if [ -d "$target/.git" ]; then
        git -C "$target" fetch --tags --force origin
    else
        mkdir -p "$(dirname "$target")"
        git clone "$url" "$target"
    fi

    if [ -n "$ref" ] && [ "$ref" != "-" ] && [ "$ref" != "HEAD" ]; then
        git -C "$target" checkout "$ref"
    fi
}

echo "================================================================"
echo "  FluxEnv 离线资源抓取"
echo "================================================================"

while IFS=$'\t' read -r name type ref url target sha256 note; do
    [ -n "$name" ] || continue
    case "$name" in \#*) continue ;; esac

    full_target="$ROOT_DIR/$target"
    echo ""
    echo "[*] $name"

    case "$type" in
        http)
            download_http "$url" "$full_target"
            chmod +x "$full_target" 2>/dev/null || true
            if ! verify_sha "$full_target" "$sha256"; then
                echo "    sha256 校验失败: $target" >&2
                exit 1
            fi
            ;;
        git)
            fetch_git_repo "$url" "$ref" "$full_target"
            ;;
        manual)
            echo "    跳过 manual 资源: $note"
            ;;
        *)
            echo "    未知资源类型: $type" >&2
            exit 1
            ;;
    esac
done < "$MANIFEST_PATH"

echo ""
echo "================================================================"
echo "  资源抓取完成"
echo "================================================================"
