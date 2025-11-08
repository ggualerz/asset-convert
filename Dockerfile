FROM registry.suse.com/bci/bci-base:16.0-10.3 AS builder

ARG LIBWEBP_VERSION=1.4.0
ARG LIBAVIF_VERSION=1.3.0
ARG MOZJPEG_VERSION=4.1.1
ARG PNGQUANT_VERSION=2.18.0
ARG OXIPNG_VERSION=9.1.5
ARG GIFSICLE_VERSION=1.94
ARG GIFLIB_VERSION=5.2.1

RUN zypper --non-interactive ref && \
    zypper --non-interactive install --no-recommends \
      bash \
      coreutils \
      findutils \
      curl \
      tar \
      unzip \
      ca-certificates \
      gcc \
      gcc-c++ \
      make \
      cmake \
      pkgconf-pkg-config \
      autoconf \
      automake \
      libtool \
      git \
      libpng16-devel \
      zlib-devel \
      liblcms2-devel \
      gawk && \
    zypper clean -a

ENV INSTALL_PREFIX=/opt/tools
RUN mkdir -p "${INSTALL_PREFIX}/bin" /tmp/build
WORKDIR /tmp/build

# WebP utilities (cwebp, gif2webp, img2webp, webpinfo)
RUN curl -Ls "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${LIBWEBP_VERSION}-linux-x86-64.tar.gz" -o libwebp.tar.gz && \
    tar -xzf libwebp.tar.gz && \
    install -Dm755 "libwebp-${LIBWEBP_VERSION}-linux-x86-64/bin/cwebp" "${INSTALL_PREFIX}/bin/cwebp" && \
    install -Dm755 "libwebp-${LIBWEBP_VERSION}-linux-x86-64/bin/gif2webp" "${INSTALL_PREFIX}/bin/gif2webp" && \
    install -Dm755 "libwebp-${LIBWEBP_VERSION}-linux-x86-64/bin/img2webp" "${INSTALL_PREFIX}/bin/img2webp" && \
    install -Dm755 "libwebp-${LIBWEBP_VERSION}-linux-x86-64/bin/webpinfo" "${INSTALL_PREFIX}/bin/webpinfo"

# AVIF encoder
RUN curl -Ls "https://github.com/AOMediaCodec/libavif/releases/download/v${LIBAVIF_VERSION}/linux-artifacts.zip" -o linux-artifacts.zip && \
    unzip -q linux-artifacts.zip && \
    install -Dm755 avifenc "${INSTALL_PREFIX}/bin/avifenc"

# mozjpeg (JPEG optimizer toolkit)
RUN curl -Ls "https://github.com/mozilla/mozjpeg/archive/refs/tags/v${MOZJPEG_VERSION}.tar.gz" -o mozjpeg.tar.gz && \
    tar -xzf mozjpeg.tar.gz && \
    cmake -S "mozjpeg-${MOZJPEG_VERSION}" -B build-mozjpeg \
      -DCMAKE_BUILD_TYPE=Release \
      -DENABLE_SHARED=OFF \
      -DWITH_SIMD=0 \
      -DPNG_SUPPORTED=OFF \
      -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" && \
    cmake --build build-mozjpeg -j"$(nproc)" && \
    cmake --install build-mozjpeg

# pngquant (lossy PNG quantizer)
RUN curl -Ls "https://pngquant.org/pngquant-${PNGQUANT_VERSION}-src.tar.gz" -o pngquant.tar.gz && \
    tar -xzf pngquant.tar.gz && \
    cd "pngquant-${PNGQUANT_VERSION}" && \
    ./configure --prefix="${INSTALL_PREFIX}" && \
    make -j"$(nproc)" && \
    make install

# giflib (dependency for gifsicle)
RUN curl -Ls "https://downloads.sourceforge.net/project/giflib/giflib-${GIFLIB_VERSION}.tar.gz" -o giflib.tar.gz && \
    tar -xzf giflib.tar.gz && \
    cd "giflib-${GIFLIB_VERSION}" && \
    make -j"$(nproc)" && \
    make install PREFIX="${INSTALL_PREFIX}"

# gifsicle (GIF optimizer)
RUN curl -Ls "https://www.lcdf.org/gifsicle/gifsicle-${GIFSICLE_VERSION}.tar.gz" -o gifsicle.tar.gz && \
    tar -xzf gifsicle.tar.gz && \
    cd "gifsicle-${GIFSICLE_VERSION}" && \
    PKG_CONFIG_PATH="${INSTALL_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}" ./configure --prefix="${INSTALL_PREFIX}" && \
    make -j"$(nproc)" && \
    make install

# oxipng (lossless PNG optimizer)
RUN curl -Ls "https://github.com/shssoichiro/oxipng/releases/download/v${OXIPNG_VERSION}/oxipng-${OXIPNG_VERSION}-x86_64-unknown-linux-musl.tar.gz" -o oxipng.tar.gz && \
    tar -xzf oxipng.tar.gz && \
    install -Dm755 "oxipng-${OXIPNG_VERSION}-x86_64-unknown-linux-musl/oxipng" "${INSTALL_PREFIX}/bin/oxipng"

FROM registry.suse.com/bci/bci-base:16.0-10.3

ENV WEBP_QUALITY=85 \
    AVIF_MIN=30 \
    AVIF_MAX=50

RUN zypper --non-interactive ref && \
    zypper --non-interactive install --no-recommends findutils && \
    zypper clean -a

COPY --from=builder /opt/tools /opt/tools

RUN set -euo pipefail && \
    mkdir -p /usr/local/bin && \
    for bin in /opt/tools/bin/*; do \
      ln -sf "$bin" /usr/local/bin/"$(basename "$bin")"; \
    done && \
    if ! getent group 65532 >/dev/null; then groupadd --gid 65532 nonroot; fi && \
    if ! id -u 65532 >/dev/null 2>&1; then useradd --uid 65532 --gid 65532 --home-dir /work --shell /bin/bash nonroot; fi

COPY convert-webp-avif /usr/local/bin/convert-webp-avif
RUN chmod +x /usr/local/bin/convert-webp-avif

WORKDIR /work

USER 65532:65532

ENTRYPOINT ["convert-webp-avif"]
