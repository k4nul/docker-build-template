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

target "default" {
  context    = CONTEXT
  dockerfile = DOCKERFILE
  tags       = ["${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}"]
  platforms  = split(",", PLATFORMS)
}
