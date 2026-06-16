# Docker Build Template

Reusable Dockerfile, buildx, and image build/push structure.

Use this template when a project needs a repeatable Docker build entrypoint with
registry pushes disabled by default, configurable image metadata, optional SBOM
and provenance attestations, and a validation step that checks the build plan
before anything is pushed.

## Open Source

This repository is prepared for public collaboration under the [MIT License](LICENSE).
See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before opening issues or pull requests.
Do not commit registry credentials, local `config/image.env`, generated image
archives, or build cache output.

## Quick Use

```bash
cp config/image.env.example config/image.env
CONFIG_FILE=config/image.env ./scripts/validate-build-plan.sh
CONFIG_FILE=config/image.env ./scripts/build-image.sh
CONFIG_FILE=config/image.env ./scripts/push-image.sh # after registry login
docker buildx bake --file buildx/docker-bake.hcl --print # defaults or exported env only
```

Edit `config/image.env` for the target registry, image name, tag, context,
Dockerfile, platforms, attestation modes, and OCI image metadata. Keep
`PUSH=false`, `SBOM=false`, and `PROVENANCE=false` until the no-push plan is
validated. Replace the example `OCI_SOURCE` and `OCI_REVISION` values with the
public source URL and CI commit SHA before publishing.

## Configuration

`scripts/build-config.sh` loads `CONFIG_FILE` when it is set; otherwise it uses
`config/image.env.example`. Values in the environment take precedence over values
from the config file, so CI jobs can override tags, registries, platforms, and
revision metadata without editing files.

| Setting | Default | Purpose |
| --- | --- | --- |
| `REGISTRY` | empty | Optional registry prefix, such as `ghcr.io/acme/`. |
| `IMAGE_NAME` | `example-app` | Image repository name. |
| `IMAGE_TAG` | `0.1.0` | Image tag. |
| `CONTEXT` | `.` | Build context. Local paths must stay inside the repository; remote contexts are allowed but must be reviewed separately. |
| `DOCKERFILE` | `docker/Dockerfile` | Dockerfile path. |
| `PLATFORMS` | `linux/amd64` | Comma-separated Buildx platform list. |
| `PUSH` | `false` | Uses `--load` when false; registry `--push` must go through `scripts/push-image.sh`. |
| `SBOM` | `false` | Set to `true` only after reviewing the no-push plan. |
| `PROVENANCE` | `false` | Supports `true`, `mode=min`, and `mode=max`. |
| `OCI_*` | example values | Open Containers image label values passed as build arguments. |

The computed image reference is `${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}`. Do not
store registry credentials in `config/image.env`; authenticate with the registry
through the Docker client or CI secret store before running a push job. Values
that flow into image references, build arguments, or OCI labels are public build
metadata; validation rejects URL userinfo and common token or private-key
markers before Docker is called. Private registry names, internal paths, and
overly specific source metadata still require human review before publishing
outside the intended registry boundary.

## Validation Flow

Run `scripts/validate-build-plan.sh` before enabling a registry push. The script
requires `PUSH=false` and checks:

- config shape and supported values.
- image reference and OCI metadata values do not include URL userinfo or
  obvious credential material.
- local build context and Dockerfile paths stay inside the repository. Remote
  contexts such as URL or `git@` contexts skip the local directory check and
  need separate source and context-hygiene review.
- Dockerfile base image defaults use explicit tags or digests instead of
  `latest`.
- Dockerfile OCI metadata arguments are bound to OCI labels.
- `.dockerignore` excludes local config, dotenv files, credentials, caches,
  generated outputs, and image archives from the build context.
- `docs/build-contract.md` contains the supply-chain guidance enforced by the
  template.
- `docker buildx bake --file buildx/docker-bake.hcl --print` matches the
  requested SBOM and provenance settings without pushing an image.

Use `scripts/validate-build-plan.sh` when you need a config-aware rendered
Buildx plan check. A direct
`docker buildx bake --file buildx/docker-bake.hcl --print` command does not read
`CONFIG_FILE`; it uses Buildx defaults plus any exported variables in the
environment. Use `scripts/build-image.sh` for validated local `PUSH=false`
builds. Direct `PUSH=true` calls to `scripts/build-image.sh` are rejected; use
`scripts/push-image.sh` for CI push jobs because it validates with `PUSH=false`
first, then exports `PUSH=true` internally for the build.

For an operator-focused sequence that covers local validation, CI overrides,
multi-platform publishing, and attestation review, see
[docs/maintenance.md](docs/maintenance.md). For the template test suite, Docker
stubs, and real Buildx validation boundaries, see
[docs/testing.md](docs/testing.md).

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
When enabling attestations, prefer `PROVENANCE=mode=min` before
`PROVENANCE=mode=max`, then review generated metadata for private image names,
internal paths, source URLs, revision values, and registry details before
publishing outside the intended registry boundary. The validator catches URL
userinfo and common token or private-key markers; reviewers must still check for
private registry names, internal paths, and source metadata that should not be
shared beyond the intended registry boundary.

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
- `must not contain credential-like token material`: replace token-looking
  metadata with public-safe values before validating or publishing.
- `Build context must stay inside repository`: use a repository-local context
  path. Parent-directory and host-level paths are rejected for local contexts.
- `.dockerignore is missing required pattern`: add the missing exclusion before
  publishing so local config, credentials, caches, and generated files do not
  enter the build context.
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
