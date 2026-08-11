#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/docker-build-template-reproducible-metadata.XXXXXX")
FIRST_PLAN="$TEST_ROOT/first-plan.json"
SECOND_PLAN="$TEST_ROOT/second-plan.json"
IMAGE_TAG_PREFIX="docker-build-template-metadata-test:$$"
BUILT_IMAGES=

cleanup() {
  if [ -n "$BUILT_IMAGES" ]; then
    # These tags are unique to this test process and are safe to discard.
    docker image rm --force $BUILT_IMAGES >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT HUP INT TERM

cd "$REPO_ROOT"

render_plan() {
  REGISTRY= \
    IMAGE_NAME=reproducible-metadata-app \
    IMAGE_TAG=1.0.0 \
    CONTEXT=. \
    DOCKERFILE=docker/Dockerfile \
    PLATFORMS=linux/amd64 \
    PUSH=false \
    SBOM=false \
    PROVENANCE=false \
    OCI_TITLE="Reproducible Metadata App" \
    OCI_DESCRIPTION="Deterministic Buildx metadata fixture" \
    OCI_SOURCE=https://example.com/reproducible-metadata-app \
    OCI_REVISION=0123456789abcdef \
    OCI_CREATED=2026-01-02T03:04:05Z \
    OCI_LICENSES=MIT \
    docker buildx bake --file buildx/docker-bake.hcl --print > "$1"
}

render_plan "$FIRST_PLAN"
render_plan "$SECOND_PLAN"

if ! cmp -s "$FIRST_PLAN" "$SECOND_PLAN"; then
  printf '%s\n' "Buildx bake output changed for identical reproducible metadata inputs" >&2
  exit 1
fi

for required_metadata in \
  '"OCI_REVISION": "0123456789abcdef"' \
  '"OCI_CREATED": "2026-01-02T03:04:05Z"'
do
  if ! grep -F -- "$required_metadata" "$FIRST_PLAN" >/dev/null; then
    printf '%s\n' "Buildx bake plan is missing reproducible metadata: $required_metadata" >&2
    exit 1
  fi
done

validate_dockerfile_label_contract() {
  REGISTRY= \
    IMAGE_NAME=reproducible-metadata-app \
    IMAGE_TAG=1.0.0 \
    CONTEXT=. \
    DOCKERFILE="$1" \
    PLATFORMS=linux/amd64 \
    PUSH=false \
    SBOM=false \
    PROVENANCE=false \
    OCI_TITLE="Reproducible Metadata App" \
    OCI_DESCRIPTION="Deterministic Buildx metadata fixture" \
    OCI_SOURCE=https://example.com/reproducible-metadata-app \
    OCI_REVISION=0123456789abcdef \
    OCI_CREATED=2026-01-02T03:04:05Z \
    OCI_LICENSES=MIT \
    ./scripts/validate-build-plan.sh >/dev/null
}

validate_dockerfile_label_contract docker/Dockerfile
validate_dockerfile_label_contract docker/Dockerfile.multistage

assert_image_label() {
  image_ref=$1
  label_name=$2
  expected_value=$3
  actual_value=$(docker image inspect \
    --format "{{ index .Config.Labels \"$label_name\" }}" \
    "$image_ref")

  if [ "$actual_value" != "$expected_value" ]; then
    printf '%s\n' \
      "$image_ref label $label_name mismatch: expected $expected_value, got $actual_value" >&2
    exit 1
  fi
}

build_and_inspect_template() {
  dockerfile=$1
  image_suffix=$2
  image_ref="${IMAGE_TAG_PREFIX}-${image_suffix}"

  docker buildx build \
    --load \
    --platform linux/amd64 \
    --file "$dockerfile" \
    --tag "$image_ref" \
    --build-arg "OCI_TITLE=Reproducible Metadata App" \
    --build-arg "OCI_DESCRIPTION=Deterministic Buildx metadata fixture" \
    --build-arg "OCI_SOURCE=https://example.com/reproducible-metadata-app" \
    --build-arg "OCI_REVISION=0123456789abcdef" \
    --build-arg "OCI_CREATED=2026-01-02T03:04:05Z" \
    --build-arg "OCI_LICENSES=MIT" \
    examples/app >/dev/null

  BUILT_IMAGES="$BUILT_IMAGES $image_ref"
  assert_image_label "$image_ref" org.opencontainers.image.revision 0123456789abcdef
  assert_image_label "$image_ref" org.opencontainers.image.created 2026-01-02T03:04:05Z
}

build_and_inspect_template docker/Dockerfile runtime
build_and_inspect_template docker/Dockerfile.multistage multistage

printf '%s\n' "Reproducible build metadata contract passed"
