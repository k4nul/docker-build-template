# Docker Build Template

Reusable Dockerfile, buildx, and image build/push structure.

## Quick Use

```bash
cp config/image.env.example config/image.env
CONFIG_FILE=config/image.env ./scripts/build-image.sh
PUSH=true CONFIG_FILE=config/image.env ./scripts/push-image.sh
docker buildx bake --file buildx/docker-bake.hcl --print
```

Edit `config/image.env` for the target registry, image name, tag, context, Dockerfile, and platforms.
