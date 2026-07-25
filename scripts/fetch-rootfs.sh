#!/usr/bin/env bash
# Fetch an Alpine minirootfs and pin its checksum.
#
#   scripts/fetch-rootfs.sh <alpine-version> [arch ...]
#   scripts/fetch-rootfs.sh 3.21.4 x86_64 aarch64
#
# The expected hash comes from Alpine's published .sha256 and is checked against
# the downloaded bytes, so a bad download cannot become the pinned value.
set -euo pipefail

VERSION="${1:-}"
shift || true
ARCHES=("${@:-x86_64}")

MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${REPO_ROOT}/alpine"

if [[ -z "${VERSION}" ]]; then
    echo "usage: $(basename "$0") <alpine-version> [arch ...]" >&2
    exit 2
fi

BRANCH="v${VERSION%.*}"

for arch in "${ARCHES[@]}"; do
    tarball="alpine-minirootfs-${VERSION}-${arch}.tar.gz"
    base_url="${MIRROR}/${BRANCH}/releases/${arch}/${tarball}"

    echo ">> downloading ${tarball}"
    curl -fsSL --retry 3 -o "${DEST}/${tarball}" "${base_url}"
    expected="$(curl -fsSL --retry 3 "${base_url}.sha256" | awk '{print $1}')"

    actual="$(cd "${DEST}" && { command -v sha256sum >/dev/null && sha256sum "${tarball}" || shasum -a 256 "${tarball}"; } | awk '{print $1}')"

    if [[ "${expected}" != "${actual}" ]]; then
        echo "!! checksum mismatch for ${tarball}" >&2
        echo "   upstream: ${expected}" >&2
        echo "   local:    ${actual}" >&2
        rm -f "${DEST}/${tarball}"
        exit 1
    fi

    tmp="$(mktemp)"
    grep -v " ${tarball}\$" "${DEST}/SHA256SUMS" 2>/dev/null > "${tmp}" || true
    printf '%s  %s\n' "${expected}" "${tarball}" >> "${tmp}"
    LC_ALL=C sort -k2 "${tmp}" > "${DEST}/SHA256SUMS"
    rm -f "${tmp}"

    echo ">> verified ${tarball} (${expected})"
done

cat <<EOF

Next steps:
  1. make verify
  2. make all ALPINE_VERSION=${VERSION}
  3. delete the superseded alpine-minirootfs-*.tar.gz and its SHA256SUMS line
  4. rebuild the dependent images against the new base digest
EOF
