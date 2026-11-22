#!/usr/bin/env bash
#
# Install ShellCheck and editorconfig-checker into ~/.local/linters/bin at
# pinned releases. A runner image's own ShellCheck moves when the image does,
# and a new version's new warning would turn the build red with nothing here
# changed; the checksums keep each download a build input, not a trust
# decision. ShellCheck publishes no checksum file, so its hash is the release
# asset's own; editorconfig-checker's matches the checksums.txt it publishes.

set -euo pipefail

SHELLCHECK_VERSION="${SHELLCHECK_VERSION:-v0.11.0}"
SHELLCHECK_SHA256="${SHELLCHECK_SHA256:-8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198}"
EC_VERSION="${EC_VERSION:-v4.0.2}"
EC_SHA256="${EC_SHA256:-44efaef3ed14c6ab52eb87481d78e5e5c204796dccf26e2f4598a61ba17f8003}"
PREFIX="${LINTERS_PREFIX:-$HOME/.local/linters}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$PREFIX/bin"

sc="shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz"
curl -fsSL -o "$tmp/$sc" \
    "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/$sc"
echo "$SHELLCHECK_SHA256  $tmp/$sc" | sha256sum -c -
tar -xJf "$tmp/$sc" -C "$tmp"
install -m 0755 "$tmp/shellcheck-${SHELLCHECK_VERSION}/shellcheck" "$PREFIX/bin/shellcheck"

ec="editorconfig-checker-linux-amd64.tar.gz"
curl -fsSL -o "$tmp/$ec" \
    "https://github.com/editorconfig-checker/editorconfig-checker/releases/download/${EC_VERSION}/$ec"
echo "$EC_SHA256  $tmp/$ec" | sha256sum -c -
mkdir "$tmp/ec"
tar -xzf "$tmp/$ec" -C "$tmp/ec"
install -m 0755 "$tmp/ec/editorconfig-checker" "$PREFIX/bin/editorconfig-checker"

"$PREFIX/bin/shellcheck" --version
"$PREFIX/bin/editorconfig-checker" --version
