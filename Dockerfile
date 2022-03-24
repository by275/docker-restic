ARG ALPINE_VER=3.15

FROM alpine:${ALPINE_VER} AS alpine
FROM ghcr.io/by275/base:alpine${ALPINE_VER} AS prebuilt

#
# BUILD
#
FROM alpine AS builder

RUN mkdir -p /bar/usr/local/bin

RUN \
    echo "**** add rclone ****" && \
    apk add --update --no-cache curl unzip bash && \
    curl -fsSL https://rclone.org/install.sh | bash && \
    mv $(which rclone) /bar/usr/local/bin/

RUN \
    echo "**** add restic ****" && \
    apk add --update --no-cache restic && \
    restic self-update && \
    mv $(which restic) /bar/usr/local/bin/

# add local files
COPY root/ /bar/

# add go-cron
COPY --from=prebuilt /go/bin/go-cron /bar/usr/local/bin/

#
# RELEASE
#
FROM alpine
LABEL maintainer="by275"
LABEL org.opencontainers.image.source https://github.com/by275/docker-restic

# add build artifacts
COPY --from=builder /bar/ /

RUN \
    echo "**** install runtime packages ****" && \
    apk add --update --no-cache \
        ca-certificates \
        fuse \
        nfs-utils \
        openssh \
        tzdata \
        bash \
        bash-completion \
        curl \
        docker-cli \
        procps \
        tini \
        gzip && \
    sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf && \
    echo "**** placeholder: rclone.config ****"  && \
    mkdir -p /root/.config/rclone && \
    echo "**** placeholder: sshkey ****"  && \
    mkdir -p /root/.ssh && \
    echo "**** permissions ****" && \
    chmod a+x /usr/local/bin/* && \
    echo "**** cleanup ****" && \
    rm -rf \
        /tmp/* \
        /root/.cache

# environment settings
ENV LANG=C.UTF-8 \
    PS1="\u@\h:\w\\$ " \
    DATE_FORMAT="+%4Y/%m/%d %H:%M:%S" \
    RCLONE_TPSLIMIT=3 \
    RCLONE_CONFIG_PATH=/run/secrets/rclone.conf \
    SSH_CONFIG_PATH=/run/secrets/.ssh \
    RESTIC_CACHE_DIR=/cache \
    INIT_CHECK_CRON=true

VOLUME /config /cache
WORKDIR /config

ENTRYPOINT ["/sbin/tini", "--", "entrypoint"]
