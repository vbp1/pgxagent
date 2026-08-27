#!/usr/bin/env bash
set -euo pipefail

# Fetch XAgent and unpack it, ready to install.
#
#   curl -fsSL https://raw.githubusercontent.com/vbp1/pgxagent/main/install.sh | bash
#
# What it does NOT do is run the installer for you. The installer asks questions — the port, the
# database credentials, which model provider to use — and a script fed to a shell through a pipe has no
# terminal to ask them on. So this script stops once everything is in place and prints the one command
# to run next.
#
# Options (also readable as environment variables):
#   --version <x.y.z>   Which release to fetch. Default: the newest one.
#   --dir <path>        Where to unpack. Default: the current directory.
#   --offline           Fetch the archive that carries the images inside it (~320 MB) instead of the
#                       one that downloads them (~35 MB). For a machine that has internet now but will
#                       not have it when the time comes to install.

REPO="${XAGENT_REPO:-vbp1/pgxagent}"
VERSION="${XAGENT_VERSION:-}"
TARGET_DIR="${XAGENT_DIR:-.}"
FLAVOUR="online"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --dir) TARGET_DIR="${2:-}"; shift 2 ;;
    --offline) FLAVOUR="offline"; shift ;;
    -h|--help) sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

for tool in curl unzip; do
  command -v "$tool" >/dev/null || { echo "This script needs ${tool}. Install it and try again." >&2; exit 2; }
done

api="https://api.github.com/repos/${REPO}/releases"
if [ -n "$VERSION" ]; then
  VERSION="${VERSION#v}"
  api="${api}/tags/v${VERSION}"
else
  api="${api}/latest"
fi

echo "Looking up the release…"
release="$(curl -fsSL "$api")" || {
  echo "No such release in ${REPO}. See https://github.com/${REPO}/releases" >&2
  exit 1
}

VERSION="$(printf '%s' "$release" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"v\{0,1\}\([^"]*\)"$/\1/')"
[ -n "$VERSION" ] || { echo "The release carries no version tag — cannot tell what to fetch." >&2; exit 1; }

archive="xagent-${VERSION}-linux-amd64-${FLAVOUR}.zip"
sums="SHA256SUMS-${VERSION}.txt"
base="https://github.com/${REPO}/releases/download/v${VERSION}"

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

echo "Downloading ${archive}"
curl -fL --progress-bar -o "$archive" "${base}/${archive}"

# The checksums are published beside the archive rather than inside it — a list packed into the archive
# it describes cannot vouch for that archive.
echo "Checking what arrived"
curl -fsSL -o "$sums" "${base}/${sums}"
if ! grep -F "$archive" "$sums" | sha256sum -c --status -; then
  rm -f "$archive"
  echo "The downloaded archive does not match the published checksum. It was removed; try again." >&2
  exit 1
fi

echo "Unpacking"
unzip -q -o "$archive"

echo ""
echo "=== Ready ==="
echo "  cd $(pwd)/xagent-${VERSION}"
echo "  ./xagent-installer verify"
echo "  sudo ./xagent-installer install --path /opt/xagent --up"
echo ""
echo "The guide: https://github.com/${REPO}/blob/main/docs/ru/install-guide.md"
