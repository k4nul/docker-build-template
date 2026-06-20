# Docker Build Template Onboarding

Use this guide when adopting the template in a new project. It keeps the first
run in no-push mode, makes config precedence explicit, and points each follow-up
step at the deeper reference docs.

## First Safe Run

1. Create a local project config:

   ```bash
   cp config/image.env.example config/image.env
   ```

2. Edit `config/image.env` for the project image identity and metadata:

   ```text
   REGISTRY=registry.example.com/team/
   IMAGE_NAME=my-app
   IMAGE_TAG=0.1.0
   CONTEXT=.
   DOCKERFILE=docker/Dockerfile
   PLATFORMS=linux/amd64
   PUSH=false
   SBOM=false
   PROVENANCE=false
   OCI_TITLE=My App
   OCI_DESCRIPTION=Container image for My App
   OCI_SOURCE=https://example.com/team/my-app
   OCI_REVISION=<commit-sha-from-ci>
   OCI_LICENSES=MIT
   ```

   Keep `PUSH=false`, `SBOM=false`, and `PROVENANCE=false` until the rendered
   no-push plan has been reviewed with final public-safe OCI metadata values.

3. Run config-aware validation:

   ```bash
   CONFIG_FILE=config/image.env ./scripts/validate-build-plan.sh
   ```

   This loads `CONFIG_FILE`, applies environment overrides, checks the local
   context and Dockerfile path, resolves Dockerfile symlinks, validates the
   effective build context `.dockerignore` and template Dockerfile metadata
   bindings, and prints the Buildx plan with cache-only output while
   `PUSH=false`. A successful dry-run prints
   `No-push build plan validation passed for ...`; the rendered plan must keep
   `type=cacheonly`, omit registry output, and match the requested SBOM and
   provenance settings.

   Capture the review evidence before enabling a push path: image reference,
   cache-only output mode, context and `.dockerignore` status, public-safe
   `OCI_*` metadata, platform list, and attestation settings. The focused
   checklist is in [docs/no-push-validation.md](no-push-validation.md).

4. Build locally only after validation passes:

   ```bash
   CONFIG_FILE=config/image.env ./scripts/build-image.sh
   ```

   Local `PUSH=false` builds use `docker buildx build --load` and require a
   single platform. Multi-platform output belongs on the registry push path.

## Config Precedence

`scripts/build-config.sh` loads `CONFIG_FILE` when it is set; otherwise it uses
`config/image.env.example`. Environment variables win over values from the config
file. This lets CI override `IMAGE_TAG`, `OCI_REVISION`, platforms, and
attestation settings without editing committed files.

Do not store registry credentials in `config/image.env`. Authenticate through
the Docker client or CI secret store before running the push path. When
`REGISTRY` is set, use a slash-terminated prefix such as `ghcr.io/acme/`; do not
use URL syntax or `user:pass@` values.

## Plan Review Boundaries

Prefer `CONFIG_FILE=config/image.env ./scripts/validate-build-plan.sh` for normal
review because it resolves the same settings used by the wrapper scripts before
calling Bake.

A direct Bake print is useful only for default-template checks or for deliberate
inspection with every needed variable exported:

```bash
docker buildx bake --file buildx/docker-bake.hcl --print
```

That direct command does not read `CONFIG_FILE`. Any unexported variable falls
back to the default in `buildx/docker-bake.hcl`, including context, Dockerfile,
attestation settings, and OCI metadata.

## CI Push Handoff

CI should keep `PUSH=false` in the project config, authenticate to the registry
outside the template scripts, and call the push wrapper:

```bash
CONFIG_FILE=config/image.env \
IMAGE_TAG="$CI_COMMIT_SHA" \
OCI_SOURCE="$PUBLIC_REPOSITORY_URL" \
OCI_REVISION="$CI_COMMIT_SHA" \
./scripts/push-image.sh
```

`scripts/push-image.sh` validates with `PUSH=false` first, then exports
`PUSH=true` internally and runs the shared `docker buildx build --push` command.
Direct `scripts/build-image.sh` calls with `PUSH=true` are rejected.

## Where To Go Next

- [docs/build-contract.md](build-contract.md) defines the template behavior that
  wrapper scripts, Dockerfiles, Bake, and documentation must preserve.
- [docs/no-push-validation.md](no-push-validation.md) provides the approval
  record to complete before registry pushes, multi-platform output, SBOMs, or
  provenance attestations.
- [docs/testing.md](testing.md) lists the shell checks, stubbed tests, real
  Buildx validation, and troubleshooting steps.
- [docs/maintenance.md](maintenance.md) provides the operator runbook for
  local validation, CI pushes, multi-platform publishing, and attestation review.
