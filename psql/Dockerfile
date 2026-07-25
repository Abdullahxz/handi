# syntax=docker/dockerfile:1

ARG BASE_IMAGE=abdullahxz/alpine:3.24.1

FROM ${BASE_IMAGE}

ARG PG_MAJOR=17

RUN set -eux; \
    apk --no-cache upgrade; \
    apk --no-cache add "postgresql${PG_MAJOR}-client"; \
    find / -xdev -type f -perm -4000 -exec chmod u-s {} ';'; \
    find / -xdev -type f -perm -2000 -exec chmod g-s {} ';'

USER 65532:65532
WORKDIR /home/nonroot

# ~/.psql_history otherwise accumulates inlined credentials and production query results
ENV HOME=/home/nonroot \
    PSQL_HISTORY=/dev/null

ARG VCS_REF=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="handi-psql" \
      org.opencontainers.image.description="PostgreSQL client tools on a minimal hardened Alpine base" \
      org.opencontainers.image.version="${PG_MAJOR}" \
      org.opencontainers.image.source="https://github.com/Abdullahxz/handi" \
      org.opencontainers.image.base.name="${BASE_IMAGE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

CMD ["/bin/sh"]
