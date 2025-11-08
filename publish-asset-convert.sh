#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE' >&2
Usage: publish-asset-convert.sh [OPTIONS]

Tag, build, and push the asset-convert container image to Docker Hub (or any OCI registry).

Options:
  --image-repo REPO   Override the OCI image repository (default from release.env).
  --builder TOOL      Force the container builder (docker or podman). Defaults to auto-detect.
  -h, --help          Show this help message and exit.
USAGE
}

log() {
  printf '[asset-convert] %s\n' "$*"
}

error() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Required command '$1' not found in PATH"
  fi
}

increment_version() {
  local version=$1 segment=${2:-patch}
  local major minor patch
  IFS='.' read -r major minor patch <<<"$version"
  if [[ -z ${major:-} || -z ${minor:-} || -z ${patch:-} ]]; then
    error "Version '$version' is not in MAJOR.MINOR.PATCH format"
  fi
  case "$segment" in
    major)
      major=$((major + 1)); minor=0; patch=0;;
    minor)
      minor=$((minor + 1)); patch=0;;
    patch)
      patch=$((patch + 1));;
    *)
      error "Unknown semver segment '$segment'"
      ;;
  esac
  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

update_release_env_version() {
  local env_file=$1
  local new_version=$2
  local tmp
  tmp=$(mktemp)
  awk -v version="$new_version" '
    BEGIN { updated = 0 }
    /^LAST_RELEASE_VERSION=/ { print "LAST_RELEASE_VERSION=" version; updated = 1; next }
    { print }
    END { if (!updated) print "LAST_RELEASE_VERSION=" version }
  ' "$env_file" > "$tmp"
  mv "$tmp" "$env_file"
}

select_builder() {
  local override=${1:-}
  local default_choice=${2:-auto}
  local chosen="${override:-$default_choice}"
  if [[ -z "$chosen" || "$chosen" == auto ]]; then
    if command -v docker >/dev/null 2>&1; then
      echo docker; return
    fi
    if command -v podman >/dev/null 2>&1; then
      echo podman; return
    fi
    error "No container builder found (install docker or podman, or pass --builder)"
  fi
  require_command "$chosen"
  echo "$chosen"
}

normalize_image_repo() {
  local repo=$1
  repo=${repo#oci://}
  repo=${repo#docker://}
  echo "$repo"
}

infer_bci_from_dockerfile() {
  local dockerfile="$SCRIPT_DIR/Dockerfile"
  [[ ! -f "$dockerfile" ]] && return
  local line image ref name variant version
  line=$(grep -m1 -E '^FROM[[:space:]]+registry\.suse\.com/bci/' "$dockerfile" || true)
  [[ -z "$line" ]] && return
  image=${line#FROM }
  image=${image%% *}
  ref=${image#registry.suse.com/bci/}
  name=${ref%%:*}
  version=${ref##*:}
  if [[ -n "$name" && "$name" != "$ref" && -n "$version" && "$version" != "$ref" ]]; then
    printf '%s:%s\n' "$name" "$version"
  fi
}

login_to_registry() {
  local tool=$1 host=$2 username=$3 prompt=$4
  read -r -s -p "$prompt" registry_secret || true
  echo
  if [[ -z "${registry_secret:-}" ]]; then
    log "Skipping ${tool} login (no secret provided)"
    return
  fi
  if [[ -n "$username" ]]; then
    if ! printf '%s' "$registry_secret" | "$tool" login "$host" --username "$username" --password-stdin; then
      error "$tool login failed for $host"
    fi
  else
    if ! printf '%s' "$registry_secret" | "$tool" login "$host" --password-stdin; then
      error "$tool login failed for $host"
    fi
  fi
}

build_image() {
  local tool=$1 context=$2 image_ref=$3
  log "Building $image_ref"
  "$tool" build -t "$image_ref" "$context"
}

push_image() {
  local tool=$1 image_ref=$2
  log "Pushing $image_ref"
  "$tool" push "$image_ref"
}

image_repo_override=""
builder_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image-repo)
      [[ $# -lt 2 ]] && error "--image-repo requires an argument"
      image_repo_override=$2
      shift 2
      ;;
    --builder)
      [[ $# -lt 2 ]] && error "--builder requires an argument"
      builder_override=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unexpected argument: $1"
      ;;
  esac
done

RELEASE_ENV="$SCRIPT_DIR/release.env"

if [[ ! -f "$RELEASE_ENV" ]]; then
  cat <<'ENV_TEMPLATE' > "$RELEASE_ENV"
# Release configuration for the asset-convert image.
# Fill in these defaults with your Docker Hub (or other registry) settings.
# Example values:
#   OCI_IMAGE_REPOSITORY=docker.io/youruser/asset-convert
#   OCI_IMAGE_USERNAME=youruser
#   OCI_IMAGE_ADDITIONAL_TAGS=latest
#   IMAGE_BUILDER=auto
#   LAST_RELEASE_VERSION=0.1.0
#   BCI_VARIANT=
#   BCI_VERSION=
OCI_IMAGE_REPOSITORY=docker.io/youruser/asset-convert
OCI_IMAGE_USERNAME=
OCI_IMAGE_ADDITIONAL_TAGS=
IMAGE_BUILDER=auto
LAST_RELEASE_VERSION=
BCI_VARIANT=
BCI_VERSION=
ENV_TEMPLATE
  error "release.env created at $RELEASE_ENV. Populate it with your values and rerun."
fi

set +u
source "$RELEASE_ENV"
set -u

if [[ -n "$image_repo_override" ]]; then
  OCI_IMAGE_REPOSITORY=$image_repo_override
fi
OCI_IMAGE_REPOSITORY=${OCI_IMAGE_REPOSITORY:-}
IMAGE_REPOSITORY=$(normalize_image_repo "$OCI_IMAGE_REPOSITORY")

if [[ -z "$IMAGE_REPOSITORY" ]]; then
  error "OCI image repository must be specified (via release.env or --image-repo)"
fi

if [[ -z "${BCI_VARIANT:-}" || -z "${BCI_VERSION:-}" ]]; then
  inferred=$(infer_bci_from_dockerfile || true)
  if [[ -n "$inferred" ]]; then
    IFS=':' read -r inferred_variant inferred_version <<<"$inferred"
    BCI_VARIANT=${BCI_VARIANT:-$inferred_variant}
    BCI_VERSION=${BCI_VERSION:-$inferred_version}
  fi
fi

BCI_VARIANT=${BCI_VARIANT:-bci-base}
BCI_VERSION=${BCI_VERSION:-16.0}
BCI_SUFFIX="-$BCI_VARIANT-$BCI_VERSION"

IMAGE_REGISTRY_HOST=${IMAGE_REPOSITORY%%/*}
if [[ -z "$IMAGE_REGISTRY_HOST" ]]; then
  error "Unable to parse registry host from $IMAGE_REPOSITORY"
fi

current_version=${LAST_RELEASE_VERSION:-0.0.0}
if [[ -z "$current_version" ]]; then
  current_version=0.0.0
fi

log "Current recorded base version: $current_version"

read -r -p "Set version manually? [y/N]: " manual_choice
manual_choice=${manual_choice:-}

if [[ "$manual_choice" =~ ^[Yy]$ ]]; then
  while true; do
    read -r -p "Enter new semantic version (e.g. 0.1.3): " new_version
    if [[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      break
    fi
    echo "Invalid version format. Please use MAJOR.MINOR.PATCH."
  done
else
  while true; do
    read -r -p "Which segment to bump? [major/minor/patch] (default: patch): " bump_choice
    bump_choice=${bump_choice:-patch}
    if [[ "$bump_choice" =~ ^(major|minor|patch)$ ]]; then
      break
    fi
    echo "Invalid choice. Please enter major, minor, or patch."
  done
  new_version=$(increment_version "$current_version" "$bump_choice")
  echo "Auto-incrementing $bump_choice version to $new_version"
fi

SELECTED_BUILDER=$(select_builder "$builder_override" "${IMAGE_BUILDER:-auto}")
log "Using container builder: $SELECTED_BUILDER"

login_to_registry "$SELECTED_BUILDER" "$IMAGE_REGISTRY_HOST" "${OCI_IMAGE_USERNAME:-}" \
  "Enter registry password/token for ${OCI_IMAGE_USERNAME:+${OCI_IMAGE_USERNAME}@}$IMAGE_REGISTRY_HOST (leave blank to skip login): "

image_tag="${new_version}${BCI_SUFFIX}"
image_ref="$IMAGE_REPOSITORY:$image_tag"

build_image "$SELECTED_BUILDER" "$SCRIPT_DIR" "$image_ref"
push_image "$SELECTED_BUILDER" "$image_ref"

if [[ -n "${OCI_IMAGE_ADDITIONAL_TAGS:-}" ]]; then
  IFS=',' read -r -a extra_tags <<<"$OCI_IMAGE_ADDITIONAL_TAGS"
  for raw_tag in "${extra_tags[@]}"; do
    tag=$(echo "$raw_tag" | tr -d '[:space:]')
    [[ -z "$tag" ]] && continue
    extra_ref="$IMAGE_REPOSITORY:$tag"
    log "Tagging $image_ref as $extra_ref"
    "$SELECTED_BUILDER" tag "$image_ref" "$extra_ref"
    push_image "$SELECTED_BUILDER" "$extra_ref"
  done
fi

update_release_env_version "$RELEASE_ENV" "$new_version"

log "Published $image_ref"
