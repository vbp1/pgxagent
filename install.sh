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
    -h|--help) sed -n '4,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# Everything lands in a scratch directory first and moves into place only once it has been checked, so
# an interrupted download cannot leave a half-file wearing the name of a complete archive. The scratch
# directory is a sibling of the target rather than /tmp: the archive is large, and the move has to stay
# within one filesystem.
work="$(mktemp -d "${PWD}/.xagent-download-XXXXXX")"
trap 'rm -rf "$work"' EXIT

echo "Downloading ${archive}"
curl -fL --progress-bar -o "$work/$archive" "${base}/${archive}" || {
  echo "Could not download ${archive} from ${base}. Nothing was written." >&2
  exit 1
}

# The checksums are published beside the archive rather than inside it — a list packed into the archive
# it describes cannot vouch for that archive.
echo "Checking what arrived"
curl -fsSL -o "$work/$sums" "${base}/${sums}" || {
  echo "Release v${VERSION} publishes no ${sums}, so the download cannot be checked. Nothing was written." >&2
  echo "Report this, or fetch the archive from https://github.com/${REPO}/releases/tag/v${VERSION} by hand." >&2
  exit 1
}

if ! (cd "$work" && grep -F "$archive" "$sums" | sha256sum -c --status -); then
  echo "The downloaded archive does not match the published checksum. Nothing was written; try again." >&2
  exit 1
fi

mv "$work/$archive" "$archive"
mv "$work/$sums" "$sums"

echo "Unpacking"
unzip -q -o "$archive"

echo ""
echo "=== Ready ==="
printf '  cd %q\n' "$(pwd)/xagent-${VERSION}"
echo "  ./xagent-installer verify"
echo "  sudo ./xagent-installer install --path /opt/xagent --up"
echo ""
echo "The guide: https://github.com/${REPO}/blob/main/docs/ru/install-guide.md"
