# README — asset-convert

Convert JPG/PNG to WebP and AVIF. Minimal, non-root, CI-friendly.  
Base image: **SUSE BCI Base 16.0-10.3**

## What it does

- Scans your working directory (recursively) for `*.jpg` `*.jpeg` `*.png` `*.gif`.
- Produces matching `*.webp` and `*.avif` beside the originals.
- Runs as non-root out of the box (default UID/GID `65532:65532`).
- Bundles mozjpeg/pngquant/oxipng/gifsicle/webpinfo so you can pre/post-process assets in the same container.

## Requirements

- Docker (or a compatible container runtime).
- A directory containing images to convert (mounted at `/work`).

## Quick start

Build the image locally (choose your own tag/name):

```sh
docker build -t asset-convert:1.0.0-bci-base-16.0-10.3 .
```

Convert everything under the current directory:

```sh
docker run --rm -v "$PWD:/work" asset-convert:1.0.0-bci-base-16.0-10.3
```

Convert only specific files/paths:

```sh
docker run --rm -v "$PWD:/work" asset-convert:1.0.0-bci-base-16.0-10.3 path/to/a.png path/to/b.jpg
```

## Non-root usage

Map your host UID/GID so outputs are owned by you:

```sh
docker run --rm \
  -u "$(id -u)":"$(id -g)" \
  -v "$PWD:/work" \
  asset-convert:1.0.0-bci-base-16.0-10.3
```

## CLI behavior

- **Default command:** `convert-webp-avif`
- **No args:** scans `/work` recursively for JPG/JPEG/PNG/GIF.
- **With args:** processes only the provided files or directories (relative to `/work`).
- Timestamp-aware: re-runs conversions whenever the source image is newer than the existing `.webp` / `.avif`, otherwise skips.
- Animated GIF sources automatically route through `gif2webp` so their frames remain intact in the generated `.webp`.
- Regex-aware `--profile` flags let you override WebP/AVIF quality for matching files.

## Tuning (environment variables)

- `WEBP_QUALITY` (default: `85`) — WebP quality (0–100).
- `AVIF_QUALITY` (default: `37`) — AVIF quality (0–100, higher = better).
- `AVIF_ALPHA_QUALITY` (default: matches `AVIF_QUALITY`) — AVIF alpha-channel quality (0–100).
- `AVIF_MIN` / `AVIF_MAX` — **deprecated** quantizer knobs. When present they are translated to an approximate `AVIF_QUALITY` so existing pipelines keep working, but you should migrate to `AVIF_QUALITY` directly.

Examples:

```sh
# Slightly lighter WebP and AVIF
docker run --rm -v "$PWD:/work" \
  -e WEBP_QUALITY=80 -e AVIF_QUALITY=40 \
  asset-convert:1.0.0-bci-base-16.0-10.3

# Convert only a folder
docker run --rm -v "$PWD:/work" asset-convert:1.0.0-bci-base-16.0-10.3 public/images/
```

## Regex-driven profiles

Match files by regex and adjust encoder settings with one or more `--profile` flags. The first matching profile applies and any omitted qualities fall back to the defaults or environment overrides. `avif-alpha` and `avifAlpha` are interchangeable keys for controlling the AVIF alpha-channel quality per profile.

```sh
# Higher quality for UI icons, lighter touch for thumbnails
docker run --rm -v "$PWD:/work" asset-convert:1.0.0-bci-base-16.0-10.3 \
  --profile 'regex=^public/icons/.*\\.png$;webp=92;avif=42' \
  --profile 'regex=^public/thumbnails/.*;webp=80;avif=38'
```

## Pairing with a webserver (sidecar pattern)

Run this container once at build/deploy time to generate WebP/AVIF assets. Serve originals and modern formats from your webserver (e.g., NGINX/Caddy rules to prefer `.avif`/`.webp` when present).

Typical pipeline steps:

1. Check out code.
2. Run `asset-convert` on your asset directory.
3. Publish the directory (including generated `.webp` / `.avif`) to your CDN/webserver.

## Tips

- Keep originals in source control; generated files can be cached or stored as build artifacts.
- For photographic assets, try `WEBP_QUALITY=82` and `AVIF_QUALITY≈40` for a balanced trade-off.
- For UI/graphics with flat colors, pre-check PNG conversions to avoid visible banding.
- Animated GIFs are preserved when producing WebP (we switch to `gif2webp` under the hood). Keep originals around if you still need GIF outputs or want to re-run `gifsicle` manually.

## Built-in optimizers & helpers

The container now includes a small toolkit so you don't have to build your own extensions:

- **mozjpeg** (`cjpeg`, `jpegtran`, `djpeg`) — re-encode/optimize source JPGs before or after WebP/AVIF conversion.
- **pngquant** (lossy) and **oxipng** (lossless) — shrink PNG sources to reduce the bytes we feed to the encoders.
- **gifsicle** + **gif2webp/img2webp** — inspect/optimize GIFs and reliably convert animated GIFs to animated WebP assets.
- **webpinfo** — inspect WebP metadata (useful in CI).

Example manual optimizations inside the container:

```sh
# Re-encode an original JPG in-place using mozjpeg
docker run --rm -v "$PWD:/work" asset-convert:1.0.0-bci-base-16.0 \
  bash -lc 'jpegtran -optimize -progressive -outfile assets/hero.opt.jpg assets/hero.jpg'

# Lossless shrink on PNGs before running asset-convert
docker run --rm -v "$PWD:/work" asset-convert:1.0.0-bci-base-16.0 \
  bash -lc 'oxipng -o 4 -strip safe -r public/icons'
```

## Extending the image

Need even more tooling (ImageMagick, ffmpeg, fonts, etc.)? Create a thin wrapper image:

```Dockerfile
FROM docker.io/ggualerz/asset-convert:1.0.0-bci-base-16.0-10.3
RUN zypper --non-interactive ref && \
    zypper --non-interactive install --no-recommends ImageMagick && \
    zypper clean -a
```

Rebuild and push your derivative image; the `convert-webp-avif` entrypoint stays the same while your extra CLI utilities are layered on top.

## Publishing to Docker Hub

Use `publish-asset-convert.sh` to build and push tags that follow the `x.y.z-bci-base-16.0-10.3` pattern.

1. Run the script once to generate `release.env`, then edit it with your Docker Hub repository, username, optional extra tags (e.g., `latest`). The script auto-detects `BCI_VARIANT`/`BCI_VERSION` from the `Dockerfile` `FROM` line; override them in `release.env` only if you need a custom value.
2. Execute `./publish-asset-convert.sh` and follow the prompts to bump or set the semantic version (the script appends `-bci-base-16.0-10.3` automatically).
3. When prompted, paste a Docker Hub access token/password so the script can `docker login`, `docker build`, tag, and push the resulting image.

Additional tags defined in `OCI_IMAGE_ADDITIONAL_TAGS` (comma-separated) are applied to the same build, which is helpful for maintaining a `latest` tag alongside versioned releases.

## Troubleshooting

- **“No images found”**: confirm paths or pass explicit files/dirs.
- **Permission issues**: add `-u $(id -u):$(id -g)` when running.
- **Slow conversion**: start with looser AVIF settings (e.g., `AVIF_QUALITY=45`).

## Versioning note

When publishing (e.g., via GitHub Actions to Docker Hub), tag images with the pattern `x.x.x-bci-base-16.0-10.3` to reflect both your release and the SUSE base version.
