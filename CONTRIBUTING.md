# Contributing to Docker Build Template

This project is a reusable Docker build template. Keep registry, context,
Dockerfile, image name, tag, platform, and push behavior configurable.

## Local Setup

```bash
bash -n scripts/build-config.sh scripts/build-image.sh scripts/push-image.sh scripts/validate-build-plan.sh tests/build-config.test.sh tests/build-image.test.sh tests/validate-build-plan.test.sh
./scripts/validate-build-plan.sh
bash tests/build-config.test.sh
bash tests/build-image.test.sh
bash tests/validate-build-plan.test.sh
docker buildx bake --file buildx/docker-bake.hcl --print # defaults or exported env only
```

To test an actual image build, use a local or disposable registry target and
keep `PUSH=false` unless the change explicitly concerns publishing.
For config-aware Buildx plan validation, use `CONFIG_FILE=... ./scripts/validate-build-plan.sh`;
direct Bake commands do not read `CONFIG_FILE`.

## Pull Request Checklist

- Do not commit `config/image.env`, registry credentials, image archives, or build output.
- Keep public examples safe to run without private registries.
- Preserve `PUSH=false` as the default.
- Preserve `SBOM=false` and `PROVENANCE=false` as public-safe defaults.
- Keep OCI metadata args, labels, and bake args aligned.
- Keep each selected local context `.dockerignore` aligned with `.gitignore` for
  local configs, credentials, generated outputs, and build caches.
- Update `docs/build-contract.md` when build inputs or outputs change.
- Update `SECURITY.md` when metadata, SBOM, provenance, or attestation behavior
  changes.

## Example App Policy

The example app exists only to prove the Dockerfile and build scripts. Avoid
turning it into a product-specific runtime.
