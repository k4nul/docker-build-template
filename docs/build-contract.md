# Docker Build Contract

- Inputs: `REGISTRY`, `IMAGE_NAME`, `IMAGE_TAG`, `CONTEXT`, `DOCKERFILE`, `PLATFORMS`, `PUSH`
- Default output: local loaded image when `PUSH=false`
- Registry output: pushed image when `PUSH=true`
- Multi-platform behavior: use `PLATFORMS=linux/amd64,linux/arm64` with `PUSH=true`
- CI integration: call `scripts/build-image.sh` from Jenkins or another runner after registry login
