# No-Push Validation Review

Use this checklist before a project enables registry pushes, multi-platform
output, SBOM attestations, or provenance attestations. It turns the
`scripts/validate-build-plan.sh` result and optional checked Bake plan artifact
into a small review record that can be kept with a CI change, release checklist,
or pull request.

## Review Command

Run the config-aware validator with the same project config and CI-style
overrides that the push job will use:

```bash
CONFIG_FILE=config/image.env \
BAKE_PLAN_OUTPUT=out/no-push-bake-plan.json \
IMAGE_TAG="$CI_COMMIT_SHA" \
OCI_SOURCE="$PUBLIC_REPOSITORY_URL" \
OCI_REVISION="$CI_COMMIT_SHA" \
./scripts/validate-build-plan.sh
```

The validator requires `PUSH=false`. Keep `PUSH=false` in `config/image.env`
and let `scripts/push-image.sh` set `PUSH=true` internally after validation
passes.

## What To Capture

Record these facts from the successful validator run:

| Field | Expected evidence |
| --- | --- |
| Config source | `CONFIG_FILE` points at the intended project config. |
| Image reference | `${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}` names the intended repository and tag. |
| Output mode | The captured Bake plan uses `type=cacheonly`, not registry output. |
| Context | Local `CONTEXT` and `DOCKERFILE` resolve inside the repository, or a remote context has separate source review. |
| Ignore file | The selected local context has its own `.dockerignore` with the required config, credential, cache, and output exclusions. |
| Platforms | Platform values are comma-separated without spaces or empty entries; a single platform is used for local `--load`, and comma-separated platforms are reserved for the validated push wrapper. |
| Metadata | `OCI_SOURCE`, `OCI_REVISION`, and other `OCI_*` values are public-safe and do not include credentials or private paths. |
| Attestations | `SBOM` and `PROVENANCE` match the reviewed rollout stage. |

The success line should read `No-push build plan validation passed for ...`.
When `BAKE_PLAN_OUTPUT` is set, the validator also writes the checked
config-aware Bake JSON to that path and prints the artifact path.
Do not treat a direct `docker buildx bake --file buildx/docker-bake.hcl --print`
as the review record unless every relevant variable has been exported; direct
Bake does not load `CONFIG_FILE`.

## Context Hygiene Evidence

For local contexts, Docker reads `.dockerignore` from the selected context root.
The validator checks that effective file, not only the repository root. For
remote contexts such as URL or `git@` contexts, the local path gate is skipped
and the validator checks the template repository's root `.dockerignore`; that
proves the template contract is present, but it does not prove the remote
repository has equivalent ignore rules.

The enforced ignore contract includes these patterns:

```text
.git
config/*.env
config/image.env
.env
.env.*
.codex
AGENTS.md
docs/management
out
node_modules
dist
build
coverage
.cache
.npm
*.log
*.tar
*.tar.gz
*.oci
*.pem
*.key
id_rsa
id_ed25519
```

Before approving a remote context, review that remote source and its own context
ignore behavior separately.

## Attestation Rollout Order

Use one no-push review per rollout step:

1. Validate with `SBOM=false` and `PROVENANCE=false`.
2. Enable `SBOM=true`, rerun validation with `BAKE_PLAN_OUTPUT` set, and review
   the captured plan.
3. Enable `PROVENANCE=mode=min`, rerun validation with `BAKE_PLAN_OUTPUT` set,
   and review generated metadata before publishing outside the intended
   registry boundary.
4. Use `PROVENANCE=mode=max` only after reviewing whether the additional
   metadata is acceptable for the project and registry audience.

The validator rejects URL userinfo and common token or private-key markers in
public build values. It cannot decide whether a private registry name, internal
path, source URL, or revision value is acceptable to publish; that remains a
human review item.

## Push Approval Boundary

Only after the review record is complete should CI call:

```bash
CONFIG_FILE=config/image.env \
IMAGE_TAG="$CI_COMMIT_SHA" \
OCI_SOURCE="$PUBLIC_REPOSITORY_URL" \
OCI_REVISION="$CI_COMMIT_SHA" \
./scripts/push-image.sh
```

The push wrapper reruns no-push validation with `PUSH=false`, then exports
`PUSH=true` for the shared `docker buildx build --push` command. Direct
`scripts/build-image.sh` calls with `PUSH=true` are rejected so the registry
path cannot bypass this approval boundary.
