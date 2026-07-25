# syntax=docker/dockerfile:1

ARG BASE_IMAGE=abdullahxz/alpine:3.24.1

FROM ${BASE_IMAGE} AS core-tools

RUN set -eux; \
    apk --no-cache upgrade; \
    apk --no-cache add \
        bash \
        bind-tools \
        ca-certificates \
        conntrack-tools \
        curl \
        ethtool \
        file \
        iproute2 \
        iptables \
        iputils \
        jq \
        libcap-utils \
        mtr \
        netcat-openbsd \
        nftables \
        openssl \
        socat \
        tcpdump

FROM core-tools AS full-tools

ARG ALPINE_EDGE_MIRROR=https://dl-cdn.alpinelinux.org/alpine/edge
ARG WITH_EDGE_TOOLS=true

RUN set -eux; \
    apk --no-cache add \
        apache2-utils \
        bird \
        bridge-utils \
        busybox-extras \
        dhcping \
        drill \
        fping \
        httpie \
        iftop \
        iperf \
        iperf3 \
        ipset \
        iptraf-ng \
        ipvsadm \
        libc6-compat \
        liboping \
        ltrace \
        net-snmp-tools \
        ngrep \
        nmap \
        nmap-nping \
        nmap-scripts \
        openssh-client-default \
        perl-crypt-ssleay \
        perl-net-ssleay \
        scapy \
        speedtest-cli \
        strace \
        tcptraceroute \
        tshark \
        util-linux \
        vim \
        websocat; \
    # Alpine restricts dumpcap to the wireshark group, which means nothing in a
    # single-user container and only makes tshark's live capture fail.
    if [ -e /usr/bin/dumpcap ]; then chmod 0755 /usr/bin/dumpcap; fi

# swaks is the only tool not carried by Alpine stable.
RUN set -eux; \
    if [ "${WITH_EDGE_TOOLS}" = "true" ]; then \
        apk --no-cache add \
            --repository "${ALPINE_EDGE_MIRROR}/community" \
            --repository "${ALPINE_EDGE_MIRROR}/testing" \
            swaks; \
    fi

# Terminal stages — keep the two in sync.
FROM full-tools AS full

RUN --mount=type=bind,source=harden.sh,target=/tmp/harden.sh sh /tmp/harden.sh

# Numeric UID: a named USER fails Kubernetes runAsNonRoot admission.
USER 65532:65532
WORKDIR /home/nonroot
ENV HOME=/home/nonroot

ARG BASE_IMAGE
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="handi-netshoot-full" \
      org.opencontainers.image.description="Network debugging toolbox, full toolset (jump-host use)" \
      org.opencontainers.image.source="https://github.com/Abdullahxz/handi" \
      org.opencontainers.image.base.name="${BASE_IMAGE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

CMD ["/bin/bash"]

# Last stage is the default build target: lean unless --target full.
FROM core-tools AS core

RUN --mount=type=bind,source=harden.sh,target=/tmp/harden.sh sh /tmp/harden.sh

USER 65532:65532
WORKDIR /home/nonroot
ENV HOME=/home/nonroot

ARG BASE_IMAGE
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="handi-netshoot" \
      org.opencontainers.image.description="Network debugging toolbox, core toolset" \
      org.opencontainers.image.source="https://github.com/Abdullahxz/handi" \
      org.opencontainers.image.base.name="${BASE_IMAGE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

CMD ["/bin/bash"]
