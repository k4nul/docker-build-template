# Docker Build Template Maintenance

Use this runbook when adapting the template for a project, reviewing a build
change, or wiring the scripts into CI. It is intentionally centered on no-push
validation first: registry pushes, SBOMs, and provenance attestations should be
enabled only after the local build plan is visible and reviewed.

## Local Validation Sequence

1. Copy the example configuration and edit only project-specific values:

   ```bash
   cp config/image.env.example config/image.env
   ```

2. Keep these defaults during the first review:

   ```text
   PUSH=false
   SBOM=false
   PROVENANCE=false
   ```

3. Set the image identity and metadata:

   ```text
   REGISTRY=registry.example.com/team/
   IMAGE_NAME=my-app
   IMAGE_TAG=0.1.0
   OCI_SOURCE=https://example.com/team/my-app
   OCI_REVISION=<commit-sha-from-ci>
   ```

4. Validate the no-push plan:

   ```bash
   CONFIG_FILE=config/image.env ./scripts/validate-build-plan.sh
   ```

5. Inspect the rendered Buildx plan when reviewing attestation or platform
   changes:

   ```bash
   CONFIG_FILE=config/image.env docker buildx bake --file buildx/docker-bake.hcl --print
   ```

6. Build locally only after validation passes:

   ```bash
   CONFIG_FILE=config/image.env ./scripts/build-image.sh
   ```

With `PUSH=false`, `scripts/build-image.sh` uses `docker buildx build --load`.
That path is best for a single local platform such as `linux/amd64`.

## CI Push Sequence

CI should authenticate to the registry before calling the template scripts. Do
not store registry credentials in `config/image.env`, Docker build arguments,
OCI labels, copied files, or committed documentation.

Use environment overrides in CI instead of editing the config file:

```bash
CONFIG_FILE=config/image.env \
IMAGE_TAG="$CI_COMMIT_SHA" \
OCI_REVISION="$CI_COMMIT_SHA" \
./scripts/push-image.sh
```

`scripts/push-image.sh` forces `PUSH=false` for
`scripts/validate-build-plan.sh`, then exports `PUSH=true` before running the
shared build command. Keep that order when adapting the template so the registry
push path cannot bypass no-push validation. Direct `scripts/build-image.sh`
calls with `PUSH=true` are rejected.

## Multi-Platform Publishing

Use a single platform for local `--load` builds:

```text
PLATFORMS=linux/amd64
PUSH=false
```

Direct `scripts/build-image.sh` runs reject comma-separated `PLATFORMS` values
while `PUSH=false` because local `--load` output is a single-platform workflow.

Use comma-separated platforms for registry publishing:

```text
PLATFORMS=linux/amd64,linux/arm64
PUSH=true
```

Buildx multi-platform output is intended for registry pushes. Validate the plan
with `PUSH=false` first, then use `scripts/push-image.sh` after registry login so
the push cannot bypass no-push validation.

## SBOM And Provenance Review

Start with attestations disabled:

```text
SBOM=false
PROVENANCE=false
```

When a project is ready to publish attestations, enable one change at a time and
review the printed Buildx plan before pushing:

```text
SBOM=true
PROVENANCE=mode=min
```

Prefer `PROVENANCE=mode=min` before `PROVENANCE=mode=max`. Before publishing
outside the intended registry boundary, review generated metadata for private
image names, internal paths, source URLs, revision values, and registry details.

## Build Context And Secret Handling

The validator requires `.dockerignore` to exclude local config, dotenv files,
credentials, caches, generated outputs, and image archives from the build
context. Keep project-specific secret files outside Git and outside the build
context.

If a project-specific build needs a short-lived package token or private key,
use BuildKit secret mounts in that project adaptation. Do not pass secrets
through build arguments, OCI labels, or files copied by the Dockerfile. Public
image identity and OCI metadata values must not include URL userinfo, token-like
strings, private keys, private registry names, or internal paths.

## Review Checklist

- `CONFIG_FILE` points at the intended project config.
- `PUSH=false` validation passes before any push job runs.
- `REGISTRY`, `IMAGE_NAME`, and `IMAGE_TAG` produce the intended image
  reference.
- `CONTEXT` and `DOCKERFILE` stay inside the repository for local contexts.
- Base image `*_IMAGE` defaults use explicit tags or digests, not `latest`.
- `.dockerignore` keeps local config, credentials, caches, and generated output
  out of the build context.
- `OCI_SOURCE` is a public source URL and `OCI_REVISION` is the CI commit SHA.
- Public image identity and OCI metadata values do not include URL userinfo,
  token-like strings, private keys, private registry names, or internal paths.
- `SBOM` and `PROVENANCE` settings match the reviewed Buildx plan.
