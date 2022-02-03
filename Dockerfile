ARG ALPINE_VER=3.15
ARG GOLANG_VER=1.16
#
# build stage
#
FROM golang:${GOLANG_VER}-alpine${ALPINE_VER} AS builder

ARG TARGETARCH

RUN mkdir -p /bar

ENV GOBIN=/bar/usr/local/bin

RUN \
    echo "**** install build packages ****" && \
    apk add --update --no-cache curl unzip bash

ARG GO_CRON_VERSION=0.0.4
ARG GO_CRON_SHA256=6c8ac52637150e9c7ee88f43e29e158e96470a3aaa3fcf47fd33771a8a76d959

RUN \
    echo "**** build go-cron v${GO_CRON_VERSION} ****" && \
    curl -sL -o go-cron.tar.gz https://github.com/djmaze/go-cron/archive/v${GO_CRON_VERSION}.tar.gz && \
    echo "${GO_CRON_SHA256}  go-cron.tar.gz" | sha256sum -c - && \
    tar xzf go-cron.tar.gz && \
    cd go-cron-${GO_CRON_VERSION} && \
    go install

RUN \
    echo "**** add rclone ****" && \
    curl -fsSL https://rclone.org/install.sh | bash && \
    mv $(which rclone) /bar/usr/local/bin/

ARG RESTIC_VERSION=0.12.1
ARG RESTIC_SHA256_AMD64=11d6ee35ec73058dae73d31d9cd17fe79661090abeb034ec6e13e3c69a4e7088
ARG RESTIC_SHA256_ARM=f27c3b271ad36896e22e411dea4c1c14d5ec75a232538c62099771ab7472765a
ARG RESTIC_SHA256_ARM64=c7e58365d0b888a60df772e7857ce8a0b53912bbd287582e865e3c5e17db723f

RUN case "$TARGETARCH" in \
    amd64 ) \
        echo "${RESTIC_SHA256_AMD64}" > RESTIC_SHA256 ; \
        ;; \
    arm ) \
        echo "${RESTIC_SHA256_ARM}" > RESTIC_SHA256 ; \
        ;; \
    arm64 ) \
        echo "${RESTIC_SHA256_ARM64}" > RESTIC_SHA256 ; \
        ;; \
    *) \
        echo "unknown architecture '${TARGETARCH}'" ; \
        exit 1 ; \
        ;; \
    esac

RUN \
    echo "**** add restic ****" && \
    curl -sL --fail -o restic.bz2 https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_${TARGETARCH}.bz2 && \
    echo "$(cat RESTIC_SHA256)  restic.bz2" | sha256sum -c - && \
    bzip2 -d -v restic.bz2 && \
    mv restic /bar/usr/local/bin/restic

# add local files
COPY root/ /bar/

#
# Final image
#
FROM alpine:${ALPINE_VER}
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
