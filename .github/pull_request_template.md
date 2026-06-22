## Summary

Describe the build template change and affected Dockerfiles, scripts, or bake targets.

## Validation

List the commands you ran, or explain why a command was not applicable.

## Checklist

- [ ] Local image config and registry credentials are not committed.
- [ ] Push behavior remains opt-in.
- [ ] Registry push behavior still goes through `scripts/push-image.sh` validation.
- [ ] No-push validation evidence is captured with `BAKE_PLAN_OUTPUT` for
      registry, multi-platform, SBOM, or provenance changes.
- [ ] SBOM and provenance attestations remain opt-in.
- [ ] SBOM/provenance rollout steps and disclosure risks are reviewed before
      publishing outside the intended registry boundary.
- [ ] OCI metadata args, labels, and bake args stay aligned.
- [ ] Registry and image names remain configurable, lowercase where required,
      and free of URL userinfo or credential-shaped values.
- [ ] Public examples do not require private infrastructure.
- [ ] BuildKit secrets, registry credentials, tokens, and private keys are not
      passed through build args, labels, copied files, logs, or review artifacts.
- [ ] Build contract docs are updated when inputs or outputs change.
