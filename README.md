# Docker Build Template

Reusable Dockerfile, buildx, and image build/push structure.

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
PUSH=true CONFIG_FILE=config/image.env ./scripts/push-image.sh
docker buildx bake --file buildx/docker-bake.hcl --print
```

Edit `config/image.env` for the target registry, image name, tag, context,
Dockerfile, platforms, attestation modes, and OCI image metadata. Keep
`PUSH=false`, `SBOM=false`, and `PROVENANCE=false` until the no-push plan is
validated. Replace the example `OCI_SOURCE` and `OCI_REVISION` values with the
public source URL and CI commit SHA before publishing. Run
`scripts/validate-build-plan.sh` before enabling a registry push so the template
checks the no-push plan, build context hygiene, OCI labels, and attestation
controls without building, loading, or pushing an image.
