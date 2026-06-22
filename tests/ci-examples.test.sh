#!/usr/bin/env sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TESTS_RUN=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_file_exists() {
  file_path=$1
  if [ ! -f "$REPO_ROOT/$file_path" ]; then
    fail "expected file to exist: $file_path"
  fi
}

assert_file_contains() {
  file_path=$1
  expected_text=$2

  if ! grep -F -- "$expected_text" "$REPO_ROOT/$file_path" >/dev/null; then
    fail "expected $file_path to contain: $expected_text"
  fi
}

assert_file_not_contains() {
  file_path=$1
  unexpected_text=$2

  if grep -F -- "$unexpected_text" "$REPO_ROOT/$file_path" >/dev/null; then
    fail "expected $file_path not to contain: $unexpected_text"
  fi
}

test_ci_publish_example_preserves_no_push_contract() {
  TESTS_RUN=$((TESTS_RUN + 1))
  ci_example=examples/ci/github-actions-publish.yml

  assert_file_exists "$ci_example"
  assert_file_contains "$ci_example" "workflow_dispatch:"
  assert_file_contains "$ci_example" "BAKE_PLAN_OUTPUT: out/no-push-bake-plan.json"
  assert_file_contains "$ci_example" "PLATFORMS: linux/amd64,linux/arm64"
  assert_file_contains "$ci_example" "PUSH: \"false\""
  assert_file_contains "$ci_example" "SBOM: \"true\""
  assert_file_contains "$ci_example" "PROVENANCE: mode=min"
  assert_file_contains "$ci_example" "./scripts/validate-build-plan.sh"
  assert_file_contains "$ci_example" "./scripts/push-image.sh"
  assert_file_contains "$ci_example" "if: \${{ github.event.inputs.publish == 'true' }}"
  assert_file_contains "$ci_example" "password: \${{ github.token }}"
  assert_file_not_contains "$ci_example" "PUSH=true"
  assert_file_not_contains "$ci_example" "REGISTRY_PASSWORD"
  pass "CI publish example captures no-push evidence before the explicit push wrapper"
}

test_no_push_review_template_captures_required_evidence() {
  TESTS_RUN=$((TESTS_RUN + 1))
  review_template=examples/review/no-push-review.md

  assert_file_exists "$review_template"
  assert_file_contains "$review_template" "Config source"
  assert_file_contains "$review_template" "Image reference"
  assert_file_contains "$review_template" "BAKE_PLAN_OUTPUT=out/no-push-bake-plan.json"
  assert_file_contains "$review_template" "No-push build plan validation passed for"
  assert_file_contains "$review_template" "type=cacheonly"
  assert_file_contains "$review_template" "Registry output absent"
  assert_file_contains "$review_template" "SBOM=false"
  assert_file_contains "$review_template" "PROVENANCE=mode=min"
  assert_file_contains "$review_template" "./scripts/push-image.sh"
  assert_file_contains "$review_template" "Registry authentication happened through Docker or the CI secret store"
  pass "no-push review template records plan, metadata, attestation, and push approval evidence"
}

test_docs_link_ci_and_review_examples() {
  TESTS_RUN=$((TESTS_RUN + 1))

  assert_file_contains README.md "examples/ci/github-actions-publish.yml"
  assert_file_contains README.md "examples/review/no-push-review.md"
  assert_file_contains docs/onboarding.md "examples/ci/github-actions-publish.yml"
  assert_file_contains docs/maintenance.md "examples/review/no-push-review.md"
  assert_file_contains docs/no-push-validation.md "examples/review/no-push-review.md"
  assert_file_contains docs/testing.md "tests/ci-examples.test.sh"
  pass "documentation points operators to CI and no-push review examples"
}

test_example_app_context_ignore_matches_public_contract() {
  TESTS_RUN=$((TESTS_RUN + 1))

  assert_file_contains examples/app/.dockerignore "config/*.env"
  assert_file_contains examples/app/.dockerignore "config/image.env"
  assert_file_contains examples/app/.dockerignore "*.pem"
  assert_file_contains examples/app/.dockerignore "*.key"
  pass "example app context ignore file includes required public build exclusions"
}

test_ci_publish_example_preserves_no_push_contract
test_no_push_review_template_captures_required_evidence
test_docs_link_ci_and_review_examples
test_example_app_context_ignore_matches_public_contract

printf '1..%s\n' "$TESTS_RUN"
