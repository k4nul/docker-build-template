#!/usr/bin/env sh

load_image_config() {
  image_config_file=$1

  while IFS= read -r image_config_line || [ -n "$image_config_line" ]; do
    case "$image_config_line" in
      ''|'#'*)
        continue
        ;;
      export\ *)
        image_config_line=${image_config_line#export }
        ;;
    esac

    case "$image_config_line" in
      *=*) ;;
      *)
        printf '%s\n' "Invalid config line in $image_config_file: $image_config_line" >&2
        exit 2
        ;;
    esac

    image_config_key=${image_config_line%%=*}
    image_config_value=${image_config_line#*=}

    case "$image_config_value" in
      \"*)
        image_config_value=${image_config_value#\"}
        image_config_value=${image_config_value%\"}
        ;;
      \'*)
        image_config_value=${image_config_value#\'}
        image_config_value=${image_config_value%\'}
        ;;
    esac

    case "$image_config_key" in
      REGISTRY)
        REGISTRY=${REGISTRY:-$image_config_value}
        ;;
      IMAGE_NAME)
        IMAGE_NAME=${IMAGE_NAME:-$image_config_value}
        ;;
      IMAGE_TAG)
        IMAGE_TAG=${IMAGE_TAG:-$image_config_value}
        ;;
      CONTEXT)
        CONTEXT=${CONTEXT:-$image_config_value}
        ;;
      DOCKERFILE)
        DOCKERFILE=${DOCKERFILE:-$image_config_value}
        ;;
      PLATFORMS)
        PLATFORMS=${PLATFORMS:-$image_config_value}
        ;;
      PUSH)
        PUSH=${PUSH:-$image_config_value}
        ;;
      OCI_TITLE)
        OCI_TITLE=${OCI_TITLE:-$image_config_value}
        ;;
      OCI_DESCRIPTION)
        OCI_DESCRIPTION=${OCI_DESCRIPTION:-$image_config_value}
        ;;
      OCI_SOURCE)
        OCI_SOURCE=${OCI_SOURCE:-$image_config_value}
        ;;
      OCI_REVISION)
        OCI_REVISION=${OCI_REVISION:-$image_config_value}
        ;;
      OCI_LICENSES)
        OCI_LICENSES=${OCI_LICENSES:-$image_config_value}
        ;;
      *)
        printf '%s\n' "Unsupported config key in $image_config_file: $image_config_key" >&2
        exit 2
        ;;
    esac
  done < "$image_config_file"
}

apply_image_config_defaults() {
  REGISTRY="${REGISTRY:-}"
  IMAGE_NAME="${IMAGE_NAME:-example-app}"
  IMAGE_TAG="${IMAGE_TAG:-0.1.0}"
  CONTEXT="${CONTEXT:-.}"
  DOCKERFILE="${DOCKERFILE:-docker/Dockerfile}"
  PLATFORMS="${PLATFORMS:-linux/amd64}"
  PUSH="${PUSH:-false}"
  OCI_TITLE="${OCI_TITLE:-Example App}"
  OCI_DESCRIPTION="${OCI_DESCRIPTION:-Reusable Docker build template image}"
  OCI_SOURCE="${OCI_SOURCE:-https://example.com/repository}"
  OCI_REVISION="${OCI_REVISION:-unknown}"
  OCI_LICENSES="${OCI_LICENSES:-MIT}"
}

load_image_build_settings() {
  CONFIG_FILE="${CONFIG_FILE:-config/image.env.example}"

  if [ -f "$CONFIG_FILE" ]; then
    load_image_config "$CONFIG_FILE"
  fi

  apply_image_config_defaults
  validate_image_build_settings
}

image_build_ref() {
  printf '%s:%s\n' "${REGISTRY}${IMAGE_NAME}" "$IMAGE_TAG"
}

image_build_output_flag() {
  if [ "$PUSH" = "true" ]; then
    printf '%s\n' "--push"
  else
    printf '%s\n' "--load"
  fi
}

export_image_build_settings() {
  export REGISTRY
  export IMAGE_NAME
  export IMAGE_TAG
  export CONTEXT
  export DOCKERFILE
  export PLATFORMS
  export PUSH
  export OCI_TITLE
  export OCI_DESCRIPTION
  export OCI_SOURCE
  export OCI_REVISION
  export OCI_LICENSES
}

validate_image_build_settings() {
  if [ -z "${IMAGE_NAME:-}" ]; then
    printf '%s\n' "IMAGE_NAME must not be empty" >&2
    exit 2
  fi

  if [ -z "${IMAGE_TAG:-}" ]; then
    printf '%s\n' "IMAGE_TAG must not be empty" >&2
    exit 2
  fi

  if [ -z "${CONTEXT:-}" ]; then
    printf '%s\n' "CONTEXT must not be empty" >&2
    exit 2
  fi

  if [ -z "${DOCKERFILE:-}" ]; then
    printf '%s\n' "DOCKERFILE must not be empty" >&2
    exit 2
  fi

  if [ -z "${PLATFORMS:-}" ]; then
    printf '%s\n' "PLATFORMS must not be empty" >&2
    exit 2
  fi

  case "${PUSH:-}" in
    true|false) ;;
    *)
      printf '%s\n' "PUSH must be true or false" >&2
      exit 2
      ;;
  esac

  if [ -z "${OCI_TITLE:-}" ]; then
    printf '%s\n' "OCI_TITLE must not be empty" >&2
    exit 2
  fi

  if [ -z "${OCI_DESCRIPTION:-}" ]; then
    printf '%s\n' "OCI_DESCRIPTION must not be empty" >&2
    exit 2
  fi

  if [ -z "${OCI_SOURCE:-}" ]; then
    printf '%s\n' "OCI_SOURCE must not be empty" >&2
    exit 2
  fi

  if [ -z "${OCI_REVISION:-}" ]; then
    printf '%s\n' "OCI_REVISION must not be empty" >&2
    exit 2
  fi

  if [ -z "${OCI_LICENSES:-}" ]; then
    printf '%s\n' "OCI_LICENSES must not be empty" >&2
    exit 2
  fi
}
