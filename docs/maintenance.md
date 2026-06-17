# Docker Build Template Maintenance

Use this runbook when adapting the template for a project, reviewing a build
change, or wiring the scripts into CI. It is intentionally centered on no-push
validation first: registry pushes, SBOMs, and provenance attestations should be
enabled only after the local build plan is visible and reviewed.

For the template test suite, Docker-stubbed checks, and the boundary between
fast shell tests and real Docker Buildx validation, see
[docs/testing.md](testing.md).

For first-time project adoption, config precedence, and the CI handoff sequence,
see [docs/onboarding.md](onboarding.md).

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
   changes. Prefer the validator for config-aware review because it loads
   `CONFIG_FILE` and exports the resolved settings before calling Bake:

   ```bash
   CONFIG_FILE=config/image.env ./scripts/validate-build-plan.sh
   ```

   A direct Bake command reads Buildx defaults plus exported environment
   variables, not `config/image.env` by itself. Use it only for default-template
   inspection or after exporting every setting relevant to the review, including
   `CONTEXT`, `DOCKERFILE`, `PLATFORMS`, `SBOM`, `PROVENANCE`, and `OCI_*`.
   A no-push Bake plan should render cache-only output. Registry output should
   appear in direct Bake output only when `PUSH=true`; the push wrapper's real
   publish step uses the shared `docker buildx build --push` command after
   no-push validation passes.

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

Keep `PUSH=false` in the project config for validation. `scripts/push-image.sh`
forces `PUSH=false` for
`scripts/validate-build-plan.sh`, then exports `PUSH=true` before running the
shared build command. Keep that order when adapting the template so the registry
push path cannot bypass no-push validation. The Bake target also keeps
`PUSH=false` plans cache-only and renders registry output only when `PUSH=true`.
Direct `scripts/build-image.sh` calls with `PUSH=true` are rejected; `PUSH=true`
is an internal push-wrapper phase, not the value to use for standalone
validation.

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
PUSH=false
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
The validator rejects URL userinfo and common token or private-key markers, but
private registry names and internal paths are human-review items.

## Build Context And Secret Handling

The validator requires `.dockerignore` to exclude local config, dotenv files,
credentials, caches, generated outputs, and image archives from the build
context. Keep project-specific secret files outside Git and outside the build
context.

If a project-specific build needs a short-lived package token or private key,
use BuildKit secret mounts in that project adaptation. Do not pass secrets
through build arguments, OCI labels, or files copied by the Dockerfile. Public
image identity and OCI metadata values must not include URL userinfo, token-like
strings, or private keys. Treat private registry names and internal paths as
manual review items before publishing outside the intended registry boundary.

## Review Checklist

- `CONFIG_FILE` points at the intended project config.
- `PUSH=false` validation passes before any push job runs.
- `REGISTRY`, `IMAGE_NAME`, and `IMAGE_TAG` produce the intended image
  reference.
- `CONTEXT` and `DOCKERFILE` stay inside the repository for local contexts.
  Remote URL or `git@` contexts are reviewed separately because the local path
  check and local `.dockerignore` cannot prove remote context hygiene.
- The no-push Bake plan renders `output=type=cacheonly`, not registry output.
- Base image `*_IMAGE` defaults use explicit tags or digests, not `latest`.
- `.dockerignore` keeps local config, credentials, caches, and generated output
  out of the build context.
- `OCI_SOURCE` is a public source URL and `OCI_REVISION` is the CI commit SHA.
- Public image identity and OCI metadata values do not include URL userinfo,
  token-like strings, or private keys, and manual review has cleared any private
  registry names or internal paths.
- `SBOM` and `PROVENANCE` settings match the reviewed Buildx plan.
