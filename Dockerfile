FROM registry.suse.com/bci/bci-base:16.0 AS deps

ARG LIBWEBP_VERSION=1.4.0
ARG LIBAVIF_VERSION=1.3.0

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
    install -Dm755 "libwebp-${LIBWEBP_VERSION}-linux-x86-64/bin/cwebp" /opt/tools/bin/cwebp

RUN curl -Ls "https://github.com/AOMediaCodec/libavif/releases/download/v${LIBAVIF_VERSION}/linux-artifacts.zip" -o linux-artifacts.zip && \
    unzip -q linux-artifacts.zip && \
    install -Dm755 avifenc /opt/tools/bin/avifenc

FROM registry.suse.com/bci/bci-micro:16.0

ENV WEBP_QUALITY=85 \
    AVIF_MIN=30 \
    AVIF_MAX=50

COPY --from=deps /bin /bin
COPY --from=deps /usr/bin /usr/bin
COPY --from=deps /usr/lib64 /usr/lib64
COPY --from=deps /usr/lib /usr/lib
COPY --from=deps /lib64 /lib64
COPY --from=deps /lib /lib

COPY --from=deps /opt/tools/bin/cwebp /usr/local/bin/cwebp
COPY --from=deps /opt/tools/bin/avifenc /usr/local/bin/avifenc

COPY convert-webp-avif /usr/local/bin/convert-webp-avif
RUN chmod +x /usr/local/bin/convert-webp-avif

WORKDIR /work

USER 65532:65532

ENTRYPOINT ["convert-webp-avif"]
