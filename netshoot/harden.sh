#!/bin/sh
# File capabilities, not setuid root, and not a root container: neither Docker
# nor Kubernetes grants ambient capabilities to a non-root process, so without
# these an unprivileged netshoot cannot capture even with NET_RAW granted.
# Tools degrade to "permission denied" when the runtime withholds the cap.
set -eu

find / -xdev -type f -perm -4000 -exec chmod u-s {} ';'
find / -xdev -type f -perm -2000 -exec chmod g-s {} ';'

setcap_present() {
    caps="$1"
    shift
    for name in "$@"; do
        path="$(command -v "${name}" 2>/dev/null || true)"
        [ -n "${path}" ] || continue
        setcap "${caps}" "${path}"
        printf 'hardened: setcap %s %s\n' "${caps}" "${path}"
    done
}

# Promiscuous mode needs NET_ADMIN on top of NET_RAW.
setcap_present 'cap_net_raw,cap_net_admin+ep' tcpdump tshark dumpcap

setcap_present 'cap_net_raw+ep' \
    ping ping6 tracepath tracepath6 traceroute6 \
    mtr mtr-packet fping fping6 oping noping \
    nmap nping tcptraceroute dhcping
