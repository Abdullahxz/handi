# Handi

Dockerfiles for the tool images I reach for regularly.

`Handy images = Handi`

These run as debug sidecars, ephemeral containers, break-glass shells. So: small by default, unprivileged by default, and rebuilt on a schedule rather than pinned and forgotten.

| Image | Build | Contents | Runs as |
| --- | --- | --- | --- |
| `alpine:3.24.1` | `make alpine` | Checksum-verified Alpine minirootfs, patched | `root` (it is a base) |
| `netshoot:<tag>` | `make netshoot` | 18 core network tools | `65532` |
| `netshoot:<tag>-full` | `make netshoot-full` | core + 34 more | `65532` |
| `psql:17-<tag>` | `make psql` | PostgreSQL client tools | `65532` |

Set `REGISTRY` in the Makefile to control the image prefix.

```console
$ make help          # all targets
$ make all           # build everything locally
$ make lint scan     # the gates CI enforces
```

## netshoot

Two variants, because attack surface and usability pull in opposite directions and the right answer depends on where the image runs.

**core** is the default — `docker build` with no `--target` gives you this. It covers name resolution, TCP reachability, TLS, HTTP, routing, NAT/conntrack, interface counters and packet capture:

`bash` · `bind-tools` · `ca-certificates` · `conntrack-tools` · `curl` · `ethtool` · `file` · `iproute2` · `iptables` · `iputils` · `jq` · `libcap-utils` · `mtr` · `netcat-openbsd` · `nftables` · `openssl` · `socat` · `tcpdump`

**full** (`--target full`) adds scanners, protocol dissectors, tracers, load generators, routing daemons, an SSH client and an editor — see `netshoot/Dockerfile` for the list. Use it on a jump host or a short-lived container, not as a resident DaemonSet: `nmap-scripts` is a large third-party Lua corpus, `tshark` dissectors have a long CVE history, and `speedtest-cli` talks to the public internet from inside your network.

Raw-socket tools carry `cap_net_raw` as a file capability rather than setuid root, so capture works as UID 65532 under the default capability sets of both Docker and Kubernetes — no extra flags:

```console
$ docker run --rm -it netshoot:dev tcpdump -i eth0

$ kubectl debug -it pod/api-7f9c --image=netshoot:dev --target=api -- bash
```

If the runtime drops `NET_RAW` (`--cap-drop=ALL`, or a `restricted` pod security profile) those binaries will not execute at all: the kernel refuses to exec a file whose effective capabilities fall outside the container's bounding set. Restore it with `--cap-add=NET_RAW` or `kubectl debug --profile=netadmin`. Promiscuous capture needs root.

## psql

```console
$ docker run --rm -it -e PGPASSWORD=... psql:17-dev \
      psql "host=db.internal user=app sslmode=verify-full sslrootcert=/certs/ca.pem"
```

`pg_dump`, `pg_restore` and `pg_isready` are present too, so no `ENTRYPOINT` forces one of them. Client major is `--build-arg PG_MAJOR=` (default 17). `PSQL_HISTORY=/dev/null` is set — `~/.psql_history` otherwise collects inlined credentials and production query results in a container others can `exec` into.

## Design notes

- **One trust hop.** The base builds `FROM scratch` out of Alpine's release tarball, checksum-verified during the build, rather than inheriting a third-party image.
- **Stable branch only.** Mixing `edge` into a stable base makes apk resolve nearly everything from `edge`. `swaks` is the sole package not in stable; it is scoped to one `--repository` call and drops out with `--build-arg WITH_EDGE_TOOLS=false`.
- **Packages are not version-pinned.** Alpine keeps only the newest build per branch, so exact pins go unbuildable within weeks. Determinism comes from the pinned branch, digest-pinned bases and a weekly rebuild instead.
- **Non-root, capabilities over root.** Leaf images run as UID `65532` (as a named `USER` fails Kubernetes `runAsNonRoot`). All setuid bits are stripped; `cap_net_raw` goes on the few binaries that need it, which is what neither Docker nor Kubernetes grants ambiently to a non-root process.
- **Scanned bytes are the published bytes.** CI pushes to a GHCR staging registry, scans those digests, then promotes to Docker Hub with `imagetools create` — a manifest copy, not a rebuild. `make promote` fails if the published digest differs from the scanned one, and the staging copies are deleted either way. Images carry SBOM and provenance attestations and are signed with keyless cosign after the gate passes.
