# Contributing to Docker Build Template

This project is a reusable Docker build template. Keep registry, context,
Dockerfile, image name, tag, platform, and push behavior configurable.

## Local Setup

```bash
bash -n scripts/build-image.sh scripts/push-image.sh
docker buildx bake --file buildx/docker-bake.hcl --print
```

To test an actual image build, use a local or disposable registry target and
keep `PUSH=false` unless the change explicitly concerns publishing.

## Pull Request Checklist

- Do not commit `config/image.env`, registry credentials, image archives, or build output.
- Keep public examples safe to run without private registries.
- Preserve `PUSH=false` as the default.
- Update `docs/build-contract.md` when build inputs or outputs change.

## Example App Policy

The example app exists only to prove the Dockerfile and build scripts. Avoid
turning it into a product-specific runtime.
