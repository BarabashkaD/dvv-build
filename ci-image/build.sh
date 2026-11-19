#!/usr/bin/env bash
# The one build command of the CI image (ci-image/Dockerfile), with its fixed buildx options.
#
# Usage: ci-image/build.sh load <local name>    build and load the image into the local Docker
#        ci-image/build.sh push <repository>    build and push it by digest only (no tag), then
#                                               print digest=sha256:<64 hex digits>
# Both need DVV_CI_IMAGE_INPUTS (the inputs hash, 64 hex digits) and DVV_CI_IMAGE_SOURCE (the URL
# of the dvv-build repository, the image's org.opencontainers.image.source). The context is the
# repository root; the builder is the docker-container builder dvv-ci-image, created when absent,
# so that push reuses load's build cache.
set -euo pipefail

usage() {
  echo "usage: ci-image/build.sh load <local name> | push <repository>" >&2
  exit 2
}
fail() {
  echo "ci-image/build.sh: $*" >&2
  exit 1
}

[ $# -eq 2 ] || usage
mode=$1
target=$2
[[ ${DVV_CI_IMAGE_INPUTS:-} =~ ^[0-9a-f]{64}$ ]] ||
  fail "DVV_CI_IMAGE_INPUTS must be 64 hex digits, got '${DVV_CI_IMAGE_INPUTS:-}'"
[ -n "${DVV_CI_IMAGE_SOURCE:-}" ] || fail "DVV_CI_IMAGE_SOURCE is not set"

root=$(cd "$(dirname "$0")/.." && pwd)
builder=dvv-ci-image
if ! docker buildx inspect "$builder" > /dev/null 2>&1; then
  docker buildx create --name "$builder" --driver docker-container > /dev/null
fi

args=(
  --builder "$builder"
  --platform linux/amd64
  --provenance=false
  --sbom=false
  -f "$root/ci-image/Dockerfile"
  --build-arg "DVV_CI_IMAGE_INPUTS=$DVV_CI_IMAGE_INPUTS"
  --build-arg "DVV_CI_IMAGE_SOURCE=$DVV_CI_IMAGE_SOURCE"
)

case $mode in
  load)
    docker buildx build "${args[@]}" --load --tag "$target" "$root"
    ;;
  push)
    metadata=$(mktemp)
    trap 'rm -f "$metadata"' EXIT
    output="type=image,name=$target,push-by-digest=true,name-canonical=true,push=true"
    output+=",oci-mediatypes=true,compression=zstd,force-compression=true"
    docker buildx build "${args[@]}" --output "$output" --metadata-file "$metadata" "$root"
    digest=$(sed -n 's/.*"containerimage\.digest": *"\(sha256:[0-9a-f]\{64\}\)".*/\1/p' "$metadata")
    [[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] ||
      fail "no containerimage.digest in the build metadata: $(cat "$metadata")"
    echo "digest=$digest"
    ;;
  *)
    usage
    ;;
esac
