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
      SBOM)
        SBOM=${SBOM:-$image_config_value}
        ;;
      PROVENANCE)
        PROVENANCE=${PROVENANCE:-$image_config_value}
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
  SBOM="${SBOM:-false}"
  PROVENANCE="${PROVENANCE:-false}"
  OCI_TITLE="${OCI_TITLE:-Example App}"
  OCI_DESCRIPTION="${OCI_DESCRIPTION:-Reusable Docker build template image}"
  OCI_SOURCE="${OCI_SOURCE:-https://example.com/repository}"
  OCI_REVISION="${OCI_REVISION:-unknown}"
  OCI_LICENSES="${OCI_LICENSES:-MIT}"
}

load_image_build_settings() {
  CONFIG_FILE_WAS_SET=${CONFIG_FILE+x}
  CONFIG_FILE="${CONFIG_FILE:-config/image.env.example}"

  if [ -f "$CONFIG_FILE" ]; then
    load_image_config "$CONFIG_FILE"
  elif [ -n "$CONFIG_FILE_WAS_SET" ]; then
    printf '%s\n' "CONFIG_FILE does not exist: $CONFIG_FILE" >&2
    exit 2
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

contains_url_userinfo() {
  public_value=$1

  case "$public_value" in
    *://*)
      public_url_authority=${public_value#*://}
      public_url_authority=${public_url_authority%%/*}
      case "$public_url_authority" in
        *@*) return 0 ;;
      esac
      ;;
  esac

  return 1
}

require_public_build_value() {
  public_setting_name=$1
  public_setting_value=$2

  if contains_url_userinfo "$public_setting_value"; then
    printf '%s\n' "$public_setting_name must not include URL userinfo or credentials" >&2
    exit 2
  fi

  case "$public_setting_value" in
    *ghp_*|*github_pat_*|*glpat-*|*xoxb-*|*xoxp-*|*"-----BEGIN "*"PRIVATE KEY-----"*)
      printf '%s\n' "$public_setting_name must not contain credential-like token material" >&2
      exit 2
      ;;
  esac
}

require_image_reference_value() {
  image_setting_name=$1
  image_setting_value=$2

  case "$image_setting_value" in
    *[[:space:]]*)
      printf '%s\n' "$image_setting_name must not contain whitespace" >&2
      exit 2
      ;;
    *://*)
      printf '%s\n' "$image_setting_name must be a Docker image reference value, not a URL" >&2
      exit 2
      ;;
    *@*)
      printf '%s\n' "$image_setting_name must not include credentials or userinfo" >&2
      exit 2
      ;;
  esac
}

require_registry_prefix() {
  if [ -z "$REGISTRY" ]; then
    return 0
  fi

  require_image_reference_value REGISTRY "$REGISTRY"

  case "$REGISTRY" in
    */) ;;
    *)
      printf '%s\n' "REGISTRY must be empty or end with /" >&2
      exit 2
      ;;
  esac
}

require_image_tag_value() {
  require_image_reference_value IMAGE_TAG "$IMAGE_TAG"

  case "$IMAGE_TAG" in
    .*)
      printf '%s\n' "IMAGE_TAG must not start with ." >&2
      exit 2
      ;;
    -*)
      printf '%s\n' "IMAGE_TAG must not start with -" >&2
      exit 2
      ;;
    *[!A-Za-z0-9_.-]*)
      printf '%s\n' \
        "IMAGE_TAG must contain only letters, numbers, underscores, periods, or dashes" >&2
      exit 2
      ;;
  esac
}

require_image_name_value() {
  require_image_reference_value IMAGE_NAME "$IMAGE_NAME"

  case "$IMAGE_NAME" in
    *[!a-z0-9._/-]*)
      printf '%s\n' \
        "IMAGE_NAME must contain only lowercase letters, numbers, periods, underscores, dashes, or slashes" >&2
      exit 2
      ;;
    /*|*/|*//*)
      printf '%s\n' "IMAGE_NAME must not contain empty slash-separated components" >&2
      exit 2
      ;;
  esac

  old_ifs=$IFS
  IFS=/
  for image_name_component in $IMAGE_NAME; do
    IFS=$old_ifs
    case "$image_name_component" in
      [!a-z0-9]*|*[!a-z0-9])
        printf '%s\n' \
          "IMAGE_NAME path components must start and end with a lowercase letter or number" >&2
        exit 2
        ;;
    esac
    IFS=/
  done
  IFS=$old_ifs
}

require_platforms_value() {
  require_image_reference_value PLATFORMS "$PLATFORMS"

  case "$PLATFORMS" in
    *,|,*|*,,*)
      printf '%s\n' "PLATFORMS must not contain empty comma-separated entries" >&2
      exit 2
      ;;
    *[!A-Za-z0-9._/,-]*)
      printf '%s\n' \
        "PLATFORMS must contain only letters, numbers, periods, underscores, dashes, slashes, or commas" >&2
      exit 2
      ;;
  esac
}

require_single_platform_load() {
  if [ "$PUSH" = "false" ]; then
    case "$PLATFORMS" in
      *,*)
        printf '%s\n' \
          "PUSH=false local loads require a single platform; use scripts/push-image.sh for multi-platform registry output" >&2
        exit 2
        ;;
    esac
  fi
}

run_image_build() {
  image_build_ref_value=$(image_build_ref)
  image_build_output_flag_value=$(image_build_output_flag)

  set -- docker buildx build \
    --platform "$PLATFORMS" \
    --file "$DOCKERFILE" \
    --tag "$image_build_ref_value" \
    --build-arg "OCI_TITLE=$OCI_TITLE" \
    --build-arg "OCI_DESCRIPTION=$OCI_DESCRIPTION" \
    --build-arg "OCI_SOURCE=$OCI_SOURCE" \
    --build-arg "OCI_REVISION=$OCI_REVISION" \
    --build-arg "OCI_LICENSES=$OCI_LICENSES"

  if [ "$SBOM" != "false" ]; then
    set -- "$@" --sbom "$SBOM"
  fi

  if [ "$PROVENANCE" != "false" ]; then
    set -- "$@" --provenance "$PROVENANCE"
  fi

  set -- "$@" "$image_build_output_flag_value" "$CONTEXT"

  "$@"
}

export_image_build_settings() {
  export REGISTRY
  export IMAGE_NAME
  export IMAGE_TAG
  export CONTEXT
  export DOCKERFILE
  export PLATFORMS
  export PUSH
  export SBOM
  export PROVENANCE
  export OCI_TITLE
  export OCI_DESCRIPTION
  export OCI_SOURCE
  export OCI_REVISION
  export OCI_LICENSES
}

require_non_empty_setting() {
  setting_name=$1
  setting_value=$2

  if [ -z "$setting_value" ]; then
    printf '%s\n' "$setting_name must not be empty" >&2
    exit 2
  fi
}

require_boolean_setting() {
  setting_name=$1
  setting_value=$2

  case "$setting_value" in
    true|false) ;;
    *)
      printf '%s\n' "$setting_name must be true or false" >&2
      exit 2
      ;;
  esac
}

require_provenance_setting() {
  setting_value=$1

  case "$setting_value" in
    false|true|mode=min|mode=max) ;;
    *)
      printf '%s\n' "PROVENANCE must be false, true, mode=min, or mode=max" >&2
      exit 2
      ;;
  esac
}

validate_image_build_settings() {
  require_non_empty_setting IMAGE_NAME "${IMAGE_NAME:-}"
  require_non_empty_setting IMAGE_TAG "${IMAGE_TAG:-}"
  require_non_empty_setting CONTEXT "${CONTEXT:-}"
  require_non_empty_setting DOCKERFILE "${DOCKERFILE:-}"
  require_non_empty_setting PLATFORMS "${PLATFORMS:-}"
  require_boolean_setting PUSH "${PUSH:-}"
  require_boolean_setting SBOM "${SBOM:-}"
  require_provenance_setting "${PROVENANCE:-}"
  require_non_empty_setting OCI_TITLE "${OCI_TITLE:-}"
  require_non_empty_setting OCI_DESCRIPTION "${OCI_DESCRIPTION:-}"
  require_non_empty_setting OCI_SOURCE "${OCI_SOURCE:-}"
  require_non_empty_setting OCI_REVISION "${OCI_REVISION:-}"
  require_non_empty_setting OCI_LICENSES "${OCI_LICENSES:-}"

  require_registry_prefix
  require_image_name_value
  require_image_tag_value
  require_platforms_value

  require_public_build_value REGISTRY "$REGISTRY"
  require_public_build_value IMAGE_NAME "$IMAGE_NAME"
  require_public_build_value IMAGE_TAG "$IMAGE_TAG"
  require_public_build_value PLATFORMS "$PLATFORMS"
  require_public_build_value OCI_TITLE "$OCI_TITLE"
  require_public_build_value OCI_DESCRIPTION "$OCI_DESCRIPTION"
  require_public_build_value OCI_SOURCE "$OCI_SOURCE"
  require_public_build_value OCI_REVISION "$OCI_REVISION"
  require_public_build_value OCI_LICENSES "$OCI_LICENSES"
}
