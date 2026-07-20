#!/usr/bin/env bash
set -euo pipefail

repo="errorcatch/gentree"
install_dir="${GENTREE_INSTALL_DIR:-$HOME/.local/bin}"

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
    Linux) platform="linux" ;;
    Darwin) platform="macos" ;;
    *) echo "Unsupported operating system: $os"; exit 1 ;;
esac

case "$arch" in
    x86_64 | amd64) cpu="x86_64" ;;
    arm64 | aarch64) cpu="aarch64" ;;
    *) echo "Unsupported architecture: $arch"; exit 1 ;;
esac

asset="gentree-${platform}-${cpu}"
url="https://github.com/${repo}/releases/latest/download/${asset}"
target="${install_dir}/gentree"

echo "==> Downloading ${asset}..."
mkdir -p "$install_dir"

if command -v curl >/dev/null 2>&1; then
    curl -fSL "$url" -o "$target"
elif command -v wget >/dev/null 2>&1; then
    wget -O "$target" "$url"
else
    echo "Need curl or wget to download gentree."
    exit 1
fi

chmod +x "$target"

if [ "$platform" = "macos" ]; then
    xattr -d com.apple.quarantine "$target" 2>/dev/null || true
fi

echo "==> Installed to ${target}"

case ":$PATH:" in
    *":$install_dir:"*)
        echo "Done. Run 'gentree -V' to check."
        ;;
    *)
        echo "Add ${install_dir} to your PATH, then reopen your terminal:"
        echo "    echo 'export PATH=\"${install_dir}:\$PATH\"' >> ~/.profile"
        ;;
esac
