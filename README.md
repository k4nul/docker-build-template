# Docker Build Template

Reusable Dockerfile, Buildx, and image build/push structure.

Use this template when a project needs a repeatable Docker build entrypoint with
registry pushes disabled by default, configurable image metadata, optional SBOM
and provenance attestations, and a validation step that checks the build plan
before anything is pushed.

## Open Source

This repository is prepared for public collaboration under the [MIT License](LICENSE).
See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before opening issues or pull requests.
Do not commit registry credentials, local non-example `config/*.env` files,
generated image archives, or build cache output.

## Quick Use

```bash
cp config/image.env.example config/image.env
CONFIG_FILE=config/image.env \
BAKE_PLAN_OUTPUT=out/no-push-bake-plan.json \
./scripts/validate-build-plan.sh
CONFIG_FILE=config/image.env ./scripts/build-image.sh
docker buildx bake --file buildx/docker-bake.hcl --print # defaults or exported env only
```

Edit `config/image.env` for the target registry, image name, tag, context,
Dockerfile, platforms, attestation modes, and OCI image metadata. Keep
`PUSH=false`, `SBOM=false`, and `PROVENANCE=false` until the no-push plan is
validated. Replace the example `OCI_SOURCE` and `OCI_REVISION` values with the
public source URL and CI commit SHA before publishing. After registry login,
use `CONFIG_FILE=config/image.env ./scripts/push-image.sh` for the push path so
the wrapper can rerun no-push validation before enabling registry output.

For a first-time adoption sequence that explains config precedence, no-push
validation, direct Bake limitations, local builds, and the CI push handoff, see
[docs/onboarding.md](docs/onboarding.md).
For the review record to complete before allowing registry pushes, multi-platform
output, SBOMs, or provenance attestations, see
[docs/no-push-validation.md](docs/no-push-validation.md).

## Configuration

`scripts/build-config.sh` loads `CONFIG_FILE` when it is set; otherwise it uses
`config/image.env.example`. Values in the environment take precedence over values
from the config file, so CI jobs can override tags, registries, platforms, and
revision metadata without editing files. Keep project-specific config files under
the existing `config/*.env` ignore contract, or add an equivalent ignore rule for
any custom config path before validating a local build context.

| Setting | Default | Purpose |
| --- | --- | --- |
| `REGISTRY` | empty | Optional slash-terminated registry prefix, such as `ghcr.io/acme/`. |
| `IMAGE_NAME` | `example-app` | Lowercase image repository path, such as `team/example-app`. |
| `IMAGE_TAG` | `0.1.0` | Image tag. |
| `CONTEXT` | `.` | Build context. Local paths must stay inside the repository; remote contexts are allowed but must be reviewed separately. |
| `DOCKERFILE` | `docker/Dockerfile` | Dockerfile path. |
| `PLATFORMS` | `linux/amd64` | Comma-separated Buildx platform list without spaces or empty entries. |
| `PUSH` | `false` | Uses `--load` when false; registry `--push` must go through `scripts/push-image.sh`. |
| `SBOM` | `false` | Set to `true` only after reviewing the no-push plan. |
| `PROVENANCE` | `false` | Supports `true`, `mode=min`, and `mode=max`. |
| `OCI_*` | example values | Open Containers image label values passed as build arguments. |

The computed image reference is `${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}`. Do not
store registry credentials in `config/image.env`; authenticate with the registry
through the Docker client or CI secret store before running a push job. Values
that flow into image references, build arguments, or OCI labels are public build
metadata; validation rejects URL userinfo and common token or private-key
markers before Docker is called. Registry prefixes must not be URLs, must not
contain credential-shaped userinfo, and must end in `/` when set so the image
reference cannot silently join the registry namespace and image name. Image
names must use lowercase Docker repository path components with only letters,
numbers, periods, underscores, dashes, and slashes, and each path component must
start and end with a lowercase letter or number. Platform lists must use
Docker-style values such as `linux/amd64,linux/arm64`; whitespace, empty comma
entries, URL syntax, and credential-shaped userinfo are rejected before Docker is
called. Private registry names,
internal paths, and overly specific source metadata still require human review
before publishing outside the intended registry boundary.

## Validation Flow

Run `scripts/validate-build-plan.sh` before enabling a registry push. The script
requires `PUSH=false` and checks:

- config shape and supported values.
- image reference and OCI metadata values do not include URL userinfo or
  obvious credential material.
- platform lists are comma-separated Docker platform values without whitespace or
  empty entries.
- local build context and Dockerfile paths stay inside the repository. Remote
  contexts such as URL or `git@` contexts skip the local directory check and
  need separate source and context-hygiene review; the validator still checks
  the template repository's root `.dockerignore`, which does not prove remote
  ignore behavior.
- local Dockerfile symlinks resolve inside the repository before the plan is
  rendered.
- selected and repository template Dockerfile base image defaults use explicit
  tags or digests instead of `latest`.
- selected and repository template Dockerfiles bind required OCI metadata
  arguments to OCI labels.
- the effective local build context `.dockerignore` excludes local config,
  dotenv files, credentials, caches, generated outputs, and image archives from
  the build context.
- `docs/build-contract.md` contains the supply-chain guidance enforced by the
  template.
- `docker buildx bake --file buildx/docker-bake.hcl --print` renders
  cache-only output while `PUSH=false` and matches the requested SBOM and
  provenance settings without pushing an image.

Use `scripts/validate-build-plan.sh` when you need a config-aware rendered
Buildx plan check. Set `BAKE_PLAN_OUTPUT=out/no-push-bake-plan.json` to keep
the checked config-aware plan as a review artifact after validation passes.
`BAKE_PLAN_OUTPUT` is an environment-only validator control, not a
`config/*.env` key. A direct
`docker buildx bake --file buildx/docker-bake.hcl --print` command does not read
`CONFIG_FILE`; it uses Buildx defaults plus any exported variables in the
environment. The Bake target renders `output=type=cacheonly` while `PUSH=false`
and `output=type=registry` only when `PUSH=true`. Use `scripts/build-image.sh`
after validation for local `PUSH=false` builds. Direct `PUSH=true` calls to
`scripts/build-image.sh` are rejected; use `scripts/push-image.sh` for CI push
jobs because it validates with `PUSH=false` first, then exports `PUSH=true`
internally for the shared `docker buildx build --push` command.

For onboarding and operator-focused sequences that cover local validation, CI
overrides, multi-platform publishing, and attestation review, see
[docs/onboarding.md](docs/onboarding.md) and
[docs/maintenance.md](docs/maintenance.md). For the template test suite, Docker
stubs, and real Buildx validation boundaries, see
[docs/testing.md](docs/testing.md).
For a compact approval checklist that captures the successful no-push plan
before registry publishing, see
[docs/no-push-validation.md](docs/no-push-validation.md).

## Multi-Platform Builds

For a single local test build, keep `PLATFORMS=linux/amd64` and `PUSH=false` so
the result can be loaded into the local Docker image store. For multi-platform
publishing, set a comma-separated value such as
`PLATFORMS=linux/amd64,linux/arm64` and run the push path after validation.
Buildx multi-platform output is intended for registry pushes, not local `--load`
workflows. Direct `scripts/build-image.sh` runs reject comma-separated platform
lists while `PUSH=false`; validate the plan first, then use
`scripts/push-image.sh` for multi-platform registry output.

## Metadata And Attestations

The Dockerfiles accept `OCI_TITLE`, `OCI_DESCRIPTION`, `OCI_SOURCE`,
`OCI_REVISION`, and `OCI_LICENSES` as build arguments and stamp them into
Open Containers labels. CI should set `OCI_SOURCE` to the public repository URL
and `OCI_REVISION` to the commit SHA being built. Do not include credentialed
URLs, package tokens, private keys, internal paths, or private registry names in
these values.

Keep `SBOM=false` and `PROVENANCE=false` until a no-push plan has been reviewed.
Validate the final public-safe `OCI_TITLE`, `OCI_DESCRIPTION`, `OCI_SOURCE`,
`OCI_REVISION`, and `OCI_LICENSES` values first with attestations disabled.
When enabling attestations, enable `SBOM=true` and prefer
`PROVENANCE=mode=min`, rerun no-push validation with `BAKE_PLAN_OUTPUT` set, and
inspect the captured plan before pushing. Review generated metadata for private
image names, internal paths, source URLs, revision values, and registry details
before publishing outside the intended registry boundary. The validator catches
URL userinfo and common token or private-key markers; reviewers must still check
for private registry names, internal paths, and source metadata that should not
be shared beyond the intended registry boundary.

## Troubleshooting

- `No-push validation requires PUSH=false`: run the validator before the push
  path or unset an environment-level `PUSH=true` override.
- `PUSH=true builds must run through scripts/push-image.sh`: use the push wrapper
  so registry output cannot bypass no-push validation.
- `PUSH=false local loads require a single platform`: set one local platform for
  `scripts/build-image.sh`, or validate first and use `scripts/push-image.sh`
  for multi-platform registry output.
- `must not include URL userinfo or credentials`: remove embedded usernames,
  passwords, or tokens from public image reference and OCI metadata values.
- `REGISTRY must not include credentials or userinfo`: remove `user:pass@`
  style registry prefixes and authenticate outside the config file.
- `REGISTRY must be empty or end with /`: use a real prefix such as
  `ghcr.io/acme/`, or move the namespace into `IMAGE_NAME`.
- `IMAGE_NAME must contain only lowercase`: use a Docker repository path such
  as `team/example-app`; uppercase names and empty slash components are rejected
  before Docker is called.
- `PLATFORMS must not contain whitespace`: use comma-separated values without
  spaces, such as `linux/amd64,linux/arm64`.
- `PLATFORMS must not contain empty comma-separated entries`: remove leading,
  trailing, or repeated commas from the platform list.
- `must not contain credential-like token material`: replace token-looking
  metadata with public-safe values before validating or publishing.
- `Build context must stay inside repository`: use a repository-local context
  path. Parent-directory and host-level paths are rejected for local contexts.
- `Missing build-context ignore file`: add `.dockerignore` to the selected local
  context directory, not only to the repository root.
- `.dockerignore is missing required pattern`: add the missing exclusion before
  publishing so local config, dotenv files, credentials, agent metadata, caches,
  image archives, and generated files do not enter the build context. The full
  enforced pattern list is in [docs/no-push-validation.md](docs/no-push-validation.md).
- `Dockerfile must not use latest`: pin `*_IMAGE` argument defaults to explicit
  tags or digests.
- `Buildx bake plan enables SBOM attestation while SBOM=false`: inspect the
  config and environment for an unexpected `SBOM` override.
- `Buildx bake plan is missing provenance attestation`: set `PROVENANCE=true`,
  `PROVENANCE=mode=min`, or `PROVENANCE=mode=max` when provenance is intended.

See [docs/build-contract.md](docs/build-contract.md) for the full build contract
and supply-chain guidance. See [docs/maintenance.md](docs/maintenance.md) for a
step-by-step maintenance runbook, and [docs/testing.md](docs/testing.md) for the
validation and test guide.
