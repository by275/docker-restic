ARG ALPINE_VER=3.20

FROM ghcr.io/by275/base:alpine AS prebuilt
FROM restic/restic:latest AS restic
FROM alpine:${ALPINE_VER} AS base

#
# BUILD
#
FROM base AS rclone

RUN \
    echo "**** add rclone ****" && \
    apk add --no-cache \
        bash \
        curl \
        unzip \
        && \
    curl -fsSL https://rclone.org/install.sh | bash

#
# COLLECT
#
FROM base AS collector

# add rclone
COPY --from=rclone /usr/bin/rclone /bar/usr/local/bin/

# add restic
COPY --from=restic /usr/bin/restic /bar/usr/local/bin/

# add go-cron
COPY --from=prebuilt /go/bin/go-cron /bar/usr/local/bin/

# add local files
COPY root/ /bar/

RUN \
    echo "**** directories ****" && \
    mkdir -p \
        /bar/config \
        /bar/cache \
        /bar/root/.ssh \
        /bar/root/.config/rclone \
        && \
    echo "**** permissions ****" && \
    chmod a+x /bar/usr/local/bin/*

#
# RELEASE
#
FROM base
LABEL maintainer="by275"
LABEL org.opencontainers.image.source=https://github.com/by275/docker-restic

RUN \
    echo "**** install runtime packages ****" && \
    apk add --no-cache \
        bash \
        ca-certificates \
        curl \
        fuse \
        gzip \
        openssh \
        procps \
        tini \
        tzdata \
        && \
    sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf && \
    echo "**** cleanup ****" && \
    rm -rf \
        /tmp/*

# add build artifacts
COPY --from=collector /bar/ /

# environment settings
ENV LANG=C.UTF-8 \
    PS1="\u@\h:\w\\$ " \
    DATE_FORMAT="+%4Y/%m/%d %H:%M:%S" \
    RCLONE_TPSLIMIT=3 \
    RCLONE_CONFIG_PATH=/run/secrets/rclone.conf \
    SSH_CONFIG_PATH=/run/secrets/.ssh \
    RESTIC_FORGET_AFTER_BACKUP=0 \
    RESTIC_FORGET_BEFORE_PRUNE=1 \
    RESTIC_CACHE_DIR=/cache

VOLUME /config /cache

ENTRYPOINT ["/sbin/tini", "--", "entrypoint"]
