variable "REGISTRY" {
  default = ""
}

variable "IMAGE_NAME" {
  default = "example-app"
}

variable "IMAGE_TAG" {
  default = "0.1.0"
}

variable "CONTEXT" {
  default = "."
}

variable "DOCKERFILE" {
  default = "docker/Dockerfile"
}

variable "PLATFORMS" {
  default = "linux/amd64"
}

variable "OCI_TITLE" {
  default = "Example App"
}

variable "OCI_DESCRIPTION" {
  default = "Reusable Docker build template image"
}

variable "OCI_SOURCE" {
  default = "https://example.com/repository"
}

variable "OCI_REVISION" {
  default = "unknown"
}

variable "OCI_LICENSES" {
  default = "MIT"
}

target "default" {
  context    = CONTEXT
  dockerfile = DOCKERFILE
  tags       = ["${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}"]
  platforms  = split(",", PLATFORMS)
  args = {
    OCI_TITLE       = OCI_TITLE
    OCI_DESCRIPTION = OCI_DESCRIPTION
    OCI_SOURCE      = OCI_SOURCE
    OCI_REVISION    = OCI_REVISION
    OCI_LICENSES    = OCI_LICENSES
  }
}
