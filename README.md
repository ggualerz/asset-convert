# README — asset-convert

Convert JPG/PNG to WebP and AVIF. Minimal, non-root, CI-friendly.  
Base image: **SUSE BCI Base**

## What it does

- Scans your working directory (recursively) for `*.jpg` `*.jpeg` `*.png` `*.gif`.
- Produces matching `*.webp` and `*.avif` beside the originals.
- Runs as non-root out of the box (default UID/GID `65532:65532`).

## Requirements

- Docker (or a compatible container runtime).
- A directory containing images to convert (mounted at `/work`).

## Quick start

Build the image locally (choose your own tag/name):

```sh
docker build -t asset-convert:1.0.0-bci-base-16.0 .
```

Convert everything under the current directory:

```sh
docker run --rm -v "$PWD:/work" asset-convert:1.0.0-bci-base-16.0
```

Convert only specific files/paths:

```sh
docker run --rm -v "$PWD:/work" asset-convert:1.0.0-bci-base-16.0 path/to/a.png path/to/b.jpg
```

## Non-root usage

Map your host UID/GID so outputs are owned by you:

```sh
docker run --rm \
  -u "$(id -u)":"$(id -g)" \
  -v "$PWD:/work" \
  asset-convert:1.0.0-bci-base-16.0
```

## CLI behavior

- **Default command:** `convert-webp-avif`
- **No args:** scans `/work` recursively for JPG/JPEG/PNG/GIF.
- **With args:** processes only the provided files or directories (relative to `/work`).
- Timestamp-aware: re-runs conversions whenever the source image is newer than the existing `.webp` / `.avif`, otherwise skips.

## Tuning (environment variables)

- `WEBP_QUALITY` (default: `85`) — WebP quality (0–100).
- `AVIF_MIN` (default: `30`) — AVIF min quantizer (lower = better).
- `AVIF_MAX` (default: `50`) — AVIF max quantizer.

Examples:

```sh
# Slightly lighter WebP and AVIF
docker run --rm -v "$PWD:/work" \
  -e WEBP_QUALITY=80 -e AVIF_MIN=28 -e AVIF_MAX=42 \
  asset-convert:1.0.0-bci-base-16.0

# Convert only a folder
docker run --rm -v "$PWD:/work" asset-convert:1.0.0-bci-base-16.0 public/images/
```

## Pairing with a webserver (sidecar pattern)

Run this container once at build/deploy time to generate WebP/AVIF assets. Serve originals and modern formats from your webserver (e.g., NGINX/Caddy rules to prefer `.avif`/`.webp` when present).

Typical pipeline steps:

1. Check out code.
2. Run `asset-convert` on your asset directory.
3. Publish the directory (including generated `.webp` / `.avif`) to your CDN/webserver.

## Tips

- Keep originals in source control; generated files can be cached or stored as build artifacts.
- For photographic assets, try `WEBP_QUALITY=82` and `AVIF_MAX≈45` for a balanced trade-off.
- For UI/graphics with flat colors, pre-check PNG conversions to avoid visible banding.
- Animated GIFs are flattened during conversion; keep the originals if animation is required elsewhere.

## Publishing to Docker Hub

Use `publish-asset-convert.sh` to build and push tags that follow the `x.y.z-bci-base-16.0` pattern.

1. Run the script once to generate `release.env`, then edit it with your Docker Hub repository, username, optional extra tags (e.g., `latest`). The script auto-detects `BCI_VARIANT`/`BCI_VERSION` from the `Dockerfile` `FROM` line; override them in `release.env` only if you need a custom value.
2. Execute `./publish-asset-convert.sh` and follow the prompts to bump or set the semantic version (the script appends `-bci-base-16.0` automatically).
3. When prompted, paste a Docker Hub access token/password so the script can `docker login`, `docker build`, tag, and push the resulting image.

Additional tags defined in `OCI_IMAGE_ADDITIONAL_TAGS` (comma-separated) are applied to the same build, which is helpful for maintaining a `latest` tag alongside versioned releases.

## Troubleshooting

- **“No images found”**: confirm paths or pass explicit files/dirs.
- **Permission issues**: add `-u $(id -u):$(id -g)` when running.
- **Slow conversion**: start with looser AVIF settings (`AVIF_MIN=32 AVIF_MAX=48`).

## Versioning note

When publishing (e.g., via GitHub Actions to Docker Hub), tag images with the pattern `x.x.x-bci-base-16.0` to reflect both your release and the SUSE base version.
