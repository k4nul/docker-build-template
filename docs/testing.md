# Testing And Validation

Use this guide when changing the template, adapting it for a project, or
reviewing a CI integration. The repository has two validation layers:
shell-based contract tests that stub Docker, and real Buildx plan validation
that calls the local Docker CLI.

## Fast Template Tests

Run the shell syntax check first:

```bash
bash -n \
  scripts/build-config.sh \
  scripts/build-image.sh \
  scripts/push-image.sh \
  scripts/validate-build-plan.sh \
  tests/build-config.test.sh \
  tests/build-image.test.sh \
  tests/validate-build-plan.test.sh
```

Then run the template test suite:

```bash
bash tests/build-config.test.sh
bash tests/build-image.test.sh
bash tests/validate-build-plan.test.sh
```

The tests create temporary fixtures under `${TMPDIR:-/tmp}` and remove them on
exit. `tests/build-image.test.sh` and `tests/validate-build-plan.test.sh` install
a temporary `docker` stub on `PATH`, so they can check the wrapper behavior
without building or pushing an image. These tests verify config parsing,
environment override precedence, image reference construction, output mode
selection, no-push validation gates, push-wrapper sequencing, attestation flag
forwarding, context path checks, `.dockerignore` requirements, Dockerfile OCI
label bindings, and the required supply-chain guidance in
`docs/build-contract.md`.

`scripts/validate-build-plan.sh` checks `docs/build-contract.md` for required
literal guidance phrases before it prints a Buildx plan. When editing the build
contract, keep the substance and key wording for context hygiene, base image
dependencies, secret handling, SBOM/provenance modes, and rejected direct
`PUSH=true` builds intact.

## Real Buildx Plan Validation

Run the real no-push validator before any registry push path:

```bash
CONFIG_FILE=config/image.env ./scripts/validate-build-plan.sh
```

This command requires a working Docker CLI with Buildx because it loads
`CONFIG_FILE`, exports the resolved build settings, and runs:

```bash
docker buildx bake --file buildx/docker-bake.hcl --print
```

A direct `docker buildx bake --file buildx/docker-bake.hcl --print` command
does not read `CONFIG_FILE`; it uses Buildx defaults plus variables already
exported in the environment. Any unexported variable falls back to
`buildx/docker-bake.hcl`, including context, Dockerfile, attestation settings,
and OCI metadata. Use direct Bake output for default-template checks or for
deliberate review after exporting the full set of variables relevant to the
plan.

The validator must run with `PUSH=false`. It exports the loaded image settings
into the Buildx bake environment and checks that the printed plan matches the
requested `SBOM` and `PROVENANCE` controls with cache-only output while
`PUSH=false`, without building or pushing an image. It also performs local
checks before Docker is called, including supported config keys, URL userinfo
and common token or private-key markers in public build values,
repository-bound local context and Dockerfile paths, explicit base image tags or
digests for the selected Dockerfile and repository template Dockerfiles,
Dockerfile OCI metadata bindings, required `.dockerignore` patterns,
and required build-contract guidance.

Remote contexts such as URL or `git@` contexts skip the local directory check.
Treat them as a separate review item: local `.dockerignore` validation proves
the template contract exists, but it does not prove that a remote context has
equivalent hygiene.

## Local Build Validation

After no-push validation passes, run a local build only for a single platform:

```bash
CONFIG_FILE=config/image.env ./scripts/build-image.sh
```

With `PUSH=false`, the build wrapper uses `docker buildx build --load`.
Comma-separated `PLATFORMS` values are rejected on this path because local
`--load` output is single-platform. For multi-platform output, validate the
no-push plan first and then use the push wrapper after registry login.

## Push Path Validation

Use the push wrapper in CI after authenticating with the registry through the
Docker client or CI secret store:

```bash
CONFIG_FILE=config/image.env \
IMAGE_TAG="$CI_COMMIT_SHA" \
OCI_REVISION="$CI_COMMIT_SHA" \
./scripts/push-image.sh
```

`scripts/push-image.sh` forces `PUSH=false` for
`scripts/validate-build-plan.sh`, then exports `PUSH=true` before running the
shared build command. Direct `scripts/build-image.sh` calls with `PUSH=true` are
rejected so registry output cannot bypass no-push validation.

## Validation Troubleshooting

- `docker: not found` or Buildx errors: run the shell tests first, then install
  or expose Docker Buildx before running the real validator.
- `No-push validation requires PUSH=false`: unset an environment-level
  `PUSH=true` override when running `scripts/validate-build-plan.sh` directly.
- `PUSH=false local loads require a single platform`: use one platform for
  `scripts/build-image.sh`, or use `scripts/push-image.sh` for multi-platform
  registry output after validation.
- `Buildx bake plan enables ... while ...=false`: inspect environment overrides
  as well as `config/image.env`; environment values take precedence over the
  config file.
- `Buildx bake plan is missing explicit no-push output`: restore the Bake target
  output contract so `PUSH=false` renders cache-only output.
- `docs/build-contract.md is required`: restore the build contract before
  validating a public supply-chain build plan.
- `docs/build-contract.md is missing required security guidance`: restore the
  required contract wording or update the validator and tests together.

For the first-time adoption path that combines config setup, validation, local
builds, direct Bake limitations, and CI push handoff, see
[docs/onboarding.md](onboarding.md).
