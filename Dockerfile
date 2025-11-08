FROM registry.suse.com/bci/bci-base:16.0-10.3

ARG LIBWEBP_VERSION=1.4.0
ARG LIBAVIF_VERSION=1.3.0

ENV WEBP_QUALITY=85 \
    AVIF_MIN=30 \
    AVIF_MAX=50

RUN zypper --non-interactive ref && \
    zypper --non-interactive install --no-recommends \
      bash \
      coreutils \
      findutils \
      curl \
      tar \
      unzip \
      ca-certificates && \
    zypper clean -a

WORKDIR /tmp/build

RUN curl -Ls "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${LIBWEBP_VERSION}-linux-x86-64.tar.gz" -o libwebp.tar.gz && \
    tar -xzf libwebp.tar.gz && \
    install -Dm755 "libwebp-${LIBWEBP_VERSION}-linux-x86-64/bin/cwebp" /usr/local/bin/cwebp

RUN curl -Ls "https://github.com/AOMediaCodec/libavif/releases/download/v${LIBAVIF_VERSION}/linux-artifacts.zip" -o linux-artifacts.zip && \
    unzip -q linux-artifacts.zip && \
    install -Dm755 avifenc /usr/local/bin/avifenc

RUN rm -rf /tmp/build

COPY convert-webp-avif /usr/local/bin/convert-webp-avif
RUN chmod +x /usr/local/bin/convert-webp-avif

WORKDIR /work

USER 65532:65532

ENTRYPOINT ["convert-webp-avif"]
