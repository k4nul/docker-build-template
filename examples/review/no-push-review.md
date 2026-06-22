# No-Push Review Record

Use this record before enabling registry pushes, multi-platform output, SBOM
attestations, or provenance attestations. Do not paste registry credentials,
private tokens, private keys, or internal hostnames into the record.

## Build Inputs

| Field | Value |
| --- | --- |
| Config source | `CONFIG_FILE=...` |
| Image reference | `${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}` |
| Context | `CONTEXT=...` |
| Dockerfile | `DOCKERFILE=...` |
| Platforms | `PLATFORMS=...` |
| SBOM | `SBOM=...` |
| Provenance | `PROVENANCE=...` |
| OCI source | `OCI_SOURCE=...` |
| OCI revision | `OCI_REVISION=...` |

## No-Push Evidence

```bash
CONFIG_FILE=config/image.env \
BAKE_PLAN_OUTPUT=out/no-push-bake-plan.json \
IMAGE_TAG="$CI_COMMIT_SHA" \
OCI_SOURCE="$PUBLIC_REPOSITORY_URL" \
OCI_REVISION="$CI_COMMIT_SHA" \
./scripts/validate-build-plan.sh
```

- Validation result: `No-push build plan validation passed for ...`
- Captured plan artifact: `out/no-push-bake-plan.json`
- Output mode reviewed as `type=cacheonly`: `yes|no`
- Registry output absent from captured plan: `yes|no`
- Selected context has an effective `.dockerignore`: `yes|no`
- Public image identity and OCI metadata are free of credentials: `yes|no`
- Private registry names, internal paths, and source metadata were reviewed for
  the intended publishing boundary: `yes|no`

## Attestation Review

| Step | Evidence |
| --- | --- |
| `SBOM=false`, `PROVENANCE=false` baseline reviewed | `...` |
| `SBOM=true` plan reviewed | `...` |
| `PROVENANCE=mode=min` plan reviewed | `...` |
| `PROVENANCE=mode=max` exception reviewed, if used | `...` |

## Publish Approval

```bash
CONFIG_FILE=config/image.env \
IMAGE_TAG="$CI_COMMIT_SHA" \
OCI_SOURCE="$PUBLIC_REPOSITORY_URL" \
OCI_REVISION="$CI_COMMIT_SHA" \
./scripts/push-image.sh
```

- Registry authentication happened through Docker or the CI secret store, not
  through `config/image.env`, build arguments, labels, or copied files:
  `yes|no`
- `scripts/push-image.sh` was the only command allowed to enter the registry
  push path: `yes|no`
- Reviewer:
- Date:
