# Docker Build Contract

This contract describes the behavior expected from the shell wrappers,
Dockerfiles, Buildx bake plan, and documentation in this template. Keep it in
sync with `scripts/build-config.sh`, `scripts/validate-build-plan.sh`,
`scripts/build-image.sh`, `scripts/push-image.sh`, and
`buildx/docker-bake.hcl`.

## Inputs And Outputs

- Inputs: `REGISTRY`, `IMAGE_NAME`, `IMAGE_TAG`, `CONTEXT`, `DOCKERFILE`, `PLATFORMS`, `PUSH`, `SBOM`, `PROVENANCE`, `OCI_TITLE`, `OCI_DESCRIPTION`, `OCI_SOURCE`, `OCI_REVISION`, `OCI_LICENSES`
- Default output: local loaded image when `PUSH=false` and `PLATFORMS` names a
  single platform
- Registry output: pushed image when `PUSH=true` through the validated push wrapper
- Bake plan output: cache-only output when `PUSH=false`; registry output is
  rendered only when `PUSH=true`
- Multi-platform behavior: validate with `PLATFORMS=linux/amd64,linux/arm64`
  and `PUSH=false`, then use `scripts/push-image.sh` for registry output. The
  push wrapper sets `PUSH=true` internally after validation.
- Attestation defaults: `SBOM=false` and `PROVENANCE=false` keep generated
  metadata disabled until a project explicitly opts in after no-push plan
  validation.
- CI integration: call `scripts/push-image.sh` from Jenkins or another runner after registry login
- Image metadata: set the `OCI_*` inputs in `config/image.env` or the runner
  environment to stamp Open Containers image labels without editing Dockerfiles.
  Keep defaults public and generic until a project has a real source URL and
  revision value from CI.
- Config-aware review: use `scripts/validate-build-plan.sh` when the plan must
  reflect `CONFIG_FILE`. Direct Bake prints use defaults plus exported
  variables only, so unexported context, Dockerfile, attestation, and OCI
  metadata values fall back to `buildx/docker-bake.hcl`.

## Required Validation

- No-push validation: run `scripts/validate-build-plan.sh` before registry push
  jobs. The validator checks config shape, local context and Dockerfile paths,
  required OCI metadata argument/label bindings, required `.dockerignore`
  entries, public-safe image reference and OCI metadata values, attestation
  controls, explicit cache-only Bake output while `PUSH=false`, and the Buildx
  bake plan without pushing.
  Local context and Dockerfile paths stay inside the repository, so
  parent-directory or host-level paths are rejected before a registry push.
  Remote contexts such as URL or `git@` contexts are allowed by the local path
  gate and require separate source and context-hygiene review.
- Push wrapper behavior: `scripts/push-image.sh` always validates with
  `PUSH=false` first, then exports `PUSH=true` and runs the shared build command.
  Keep this sequence when adapting the template to CI.
  Direct `scripts/build-image.sh` calls with `PUSH=true` are rejected so registry
  output cannot bypass no-push validation. Direct local `scripts/build-image.sh`
  calls with comma-separated `PLATFORMS` are also rejected while `PUSH=false`;
  multi-platform output must use the validated push wrapper.
- Maintenance runbook: keep [docs/maintenance.md](maintenance.md) aligned with
  this contract so users can follow the same no-push validation, CI override,
  multi-platform, and attestation review sequence without reading the scripts.

## Context And Dependencies

- Build context hygiene: keep local configs, dotenv files, credentials, image
  archives, caches, generated outputs, `.codex`, local agent files, and
  management-only docs out of the Docker build context through `.dockerignore`.
- Base image dependencies: treat Dockerfile `*_IMAGE` argument defaults as the
  template's dependency inputs. Use explicit tags or digests, do not use
  `latest`, and review `alpine`, `node`, and `nginx` base image updates as a
  coherent build-template upgrade with the no-push validation suite.

## Secrets And Attestations

- Secret handling: do not pass registry credentials, package tokens, or private
  keys through build arguments, labels, or copied files. Use BuildKit secret
  mounts such as `--secret` in project-specific builds that genuinely need
  short-lived credentials, and keep those secret files out of Git and the build
  context. Public build values that become image references, build arguments, or
  labels must not include URL userinfo or obvious token/private-key markers.
- SBOM and provenance: keep `SBOM=false` and `PROVENANCE=false` until a no-push
  plan has been reviewed. Use `SBOM=true` to include an SBOM attestation and
  prefer `PROVENANCE=mode=min` before `PROVENANCE=mode=max`. Review generated
  metadata before attestation publishing, including private image names,
  internal paths, source URLs, revision values, and registry details. The
  validator rejects URL userinfo and common token or private-key markers in
  public build values; private registry names and internal paths are manual
  review concerns. Do not share attestations outside the intended registry
  boundary before that review.

## Review Checklist

- Keep `PUSH=false` during local validation and first CI plan review.
- Confirm `.dockerignore` excludes local config, credentials, caches, generated
  files, and image archive outputs.
- Confirm each Dockerfile used by the template declares OCI metadata arguments
  and label bindings.
- Confirm base image defaults use explicit tags or digests.
- Confirm registry login happens outside the template scripts.
- Confirm `OCI_SOURCE` and `OCI_REVISION` come from public source and CI commit
  data before registry publishing.
- Confirm image identity and OCI metadata values do not contain URL userinfo,
  package tokens, or private keys.
- Confirm manual review has cleared private registry names, internal paths, and
  source metadata before publishing attestations outside the intended boundary.
