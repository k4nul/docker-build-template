# Docker Build Contract

- Inputs: `REGISTRY`, `IMAGE_NAME`, `IMAGE_TAG`, `CONTEXT`, `DOCKERFILE`, `PLATFORMS`, `PUSH`
- Default output: local loaded image when `PUSH=false`
- Registry output: pushed image when `PUSH=true`
- Multi-platform behavior: use `PLATFORMS=linux/amd64,linux/arm64` with `PUSH=true`
- CI integration: call `scripts/build-image.sh` from Jenkins or another runner after registry login
- No-push validation: run `scripts/validate-build-plan.sh` before registry push
  jobs. The validator checks config shape, local context and Dockerfile paths,
  required `.dockerignore` entries, and the Buildx bake plan without pushing.
- Build context hygiene: keep local configs, dotenv files, credentials, image
  archives, caches, generated outputs, `.codex`, local agent files, and
  management-only docs out of the Docker build context through `.dockerignore`.
- Secret handling: do not pass registry credentials, package tokens, or private
  keys through build arguments, labels, or copied files. Use BuildKit secret
  mounts such as `--secret` in project-specific builds that genuinely need
  short-lived credentials, and keep those secret files out of Git and the build
  context.
- SBOM and provenance: prefer no-push plan validation before enabling SBOM,
  provenance, or attestation publishing. Review generated metadata for internal
  paths, private image names, and registry details before sharing attestations
  outside the intended registry boundary.
