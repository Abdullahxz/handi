# syntax=docker/dockerfile:1

ARG BOOTSTRAP_IMAGE=busybox:uclibc

FROM --platform=$BUILDPLATFORM ${BOOTSTRAP_IMAGE} AS rootfs

ARG ALPINE_VERSION=3.24.1
ARG TARGETARCH

WORKDIR /src
COPY SHA256SUMS alpine-minirootfs-*.tar.gz ./

# Verification must stay in a stage the final image copies from: BuildKit prunes
# a stage nothing consumes, and the check would silently never run.
RUN set -eu; \
    case "${TARGETARCH:-amd64}" in \
        amd64) alpine_arch=x86_64 ;; \
        arm64) alpine_arch=aarch64 ;; \
        *) echo "unsupported TARGETARCH='${TARGETARCH}'" >&2; exit 1 ;; \
    esac; \
    tarball="alpine-minirootfs-${ALPINE_VERSION}-${alpine_arch}.tar.gz"; \
    if [ ! -f "${tarball}" ]; then \
        echo "missing ${tarball} — run: scripts/fetch-rootfs.sh ${ALPINE_VERSION} ${alpine_arch}" >&2; \
        exit 1; \
    fi; \
    grep " ${tarball}\$" SHA256SUMS > /tmp/expected.sha256; \
    sha256sum -c /tmp/expected.sha256; \
    mkdir -p /rootfs; \
    tar -xzf "${tarball}" -C /rootfs

FROM scratch AS base

COPY --from=rootfs /rootfs/ /

ARG ALPINE_VERSION=3.24.1
ARG ALPINE_MIRROR=https://dl-cdn.alpinelinux.org/alpine
ARG NONROOT_UID=65532
ARG NONROOT_GID=65532

RUN set -eux; \
    branch="v${ALPINE_VERSION%.*}"; \
    printf '%s\n' \
        "${ALPINE_MIRROR}/${branch}/main" \
        "${ALPINE_MIRROR}/${branch}/community" \
        > /etc/apk/repositories; \
    apk --no-cache upgrade; \
    apk --no-cache add ca-certificates; \
    addgroup -g "${NONROOT_GID}" -S nonroot; \
    adduser -u "${NONROOT_UID}" -G nonroot -h /home/nonroot -s /sbin/nologin -S -D nonroot; \
    mkdir -p /home/nonroot; \
    chown "${NONROOT_UID}:${NONROOT_GID}" /home/nonroot; \
    chmod 0750 /home/nonroot; \
    find / -xdev -type f -perm -4000 -exec chmod u-s {} ';'; \
    find / -xdev -type f -perm -2000 -exec chmod g-s {} ';'

# Base image: stays root so children can install packages. Leaf images drop to 65532.
# hadolint ignore=DL3002
USER root
WORKDIR /

ARG VCS_REF=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="handi-alpine" \
      org.opencontainers.image.description="Minimal Alpine base built from a checksum-verified upstream minirootfs" \
      org.opencontainers.image.version="${ALPINE_VERSION}" \
      org.opencontainers.image.source="https://github.com/Abdullahxz/handi" \
      org.opencontainers.image.base.name="scratch" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

CMD ["/bin/sh"]
