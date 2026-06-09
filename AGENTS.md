schema_version: "1.0"
project:
  id: "docker-build-template"
  type: "devops.template.docker"
  status: "active"
scope:
  owns:
    - "docker/Dockerfile"
    - "docker/Dockerfile.multistage"
    - "buildx/docker-bake.hcl"
    - "scripts/build-image.sh"
    - "scripts/push-image.sh"
    - "config/image.env.example"
  excludes:
    kubernetes_deploy:
      repository: "../k8s-platform-template"
    jenkins_pipeline:
      repository: "../jenkins-pipeline-template"
    cloud_infra:
      repository: "../cloud-infra-template"
instructions:
  template_rules:
    keep_context_configurable: true
    keep_registry_configurable: true
    support_multi_platform_builds: true
    default_push: false
    avoid_application_specific_runtime: true
  validation:
    required:
      - command: "bash -n scripts/build-image.sh scripts/push-image.sh"
        when: "shell scripts change"
      - command: "docker buildx bake --file buildx/docker-bake.hcl --print"
        when: "bake file changes and docker is available"
automation:
  enabled: true
  entrypoints:
    build: "scripts/build-image.sh"
    push: "scripts/push-image.sh"
    bake: "buildx/docker-bake.hcl"
