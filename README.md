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
CONFIG_FILE=config/image.env ./scripts/build-image.sh
PUSH=true CONFIG_FILE=config/image.env ./scripts/push-image.sh
docker buildx bake --file buildx/docker-bake.hcl --print
```

Edit `config/image.env` for the target registry, image name, tag, context, Dockerfile, and platforms.
