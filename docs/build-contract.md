# Docker Build Contract

- Inputs: `REGISTRY`, `IMAGE_NAME`, `IMAGE_TAG`, `CONTEXT`, `DOCKERFILE`, `PLATFORMS`, `PUSH`, `SBOM`, `PROVENANCE`, `OCI_TITLE`, `OCI_DESCRIPTION`, `OCI_SOURCE`, `OCI_REVISION`, `OCI_LICENSES`
- Default output: local loaded image when `PUSH=false`
- Registry output: pushed image when `PUSH=true`
- Multi-platform behavior: use `PLATFORMS=linux/amd64,linux/arm64` with `PUSH=true`
- Attestation defaults: `SBOM=false` and `PROVENANCE=false` keep generated
  metadata disabled until a project explicitly opts in after no-push plan
  validation.
- CI integration: call `scripts/build-image.sh` from Jenkins or another runner after registry login
- Image metadata: set the `OCI_*` inputs in `config/image.env` or the runner
  environment to stamp Open Containers image labels without editing Dockerfiles.
  Keep defaults public and generic until a project has a real source URL and
  revision value from CI.
- No-push validation: run `scripts/validate-build-plan.sh` before registry push
  jobs. The validator checks config shape, local context and Dockerfile paths,
  required OCI metadata argument/label bindings, required `.dockerignore`
  entries, attestation controls, and the Buildx bake plan without pushing. Local
  context and Dockerfile paths stay inside the repository so parent-directory or
  host-level paths are rejected before a registry push.
- Build context hygiene: keep local configs, dotenv files, credentials, image
  archives, caches, generated outputs, `.codex`, local agent files, and
  management-only docs out of the Docker build context through `.dockerignore`.
- Base image dependencies: treat Dockerfile `*_IMAGE` argument defaults as the
  template's dependency inputs. Use explicit tags or digests, do not use
  `latest`, and review `alpine`, `node`, and `nginx` base image updates as a
  coherent build-template upgrade with the no-push validation suite.
- Secret handling: do not pass registry credentials, package tokens, or private
  keys through build arguments, labels, or copied files. Use BuildKit secret
  mounts such as `--secret` in project-specific builds that genuinely need
  short-lived credentials, and keep those secret files out of Git and the build
  context.
- SBOM and provenance: keep `SBOM=false` and `PROVENANCE=false` until a no-push
  plan has been reviewed. Use `SBOM=true` to include an SBOM attestation and
  prefer `PROVENANCE=mode=min` before `PROVENANCE=mode=max`. Review generated
  metadata before attestation publishing, including private image names,
  internal paths, source URLs, revision values, and registry details. Do not
  share attestations outside the intended registry boundary before that review.
