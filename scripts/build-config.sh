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
      *)
        printf '%s\n' "Unsupported config key in $image_config_file: $image_config_key" >&2
        exit 2
        ;;
    esac
  done < "$image_config_file"
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
}
