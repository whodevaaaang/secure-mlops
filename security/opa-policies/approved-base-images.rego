package securemlops.security

approved_images := {
  "python:3.10-slim",
  "postgres:15-alpine",
  "jenkins/jenkins:lts"
}

deny contains msg if {
  image := input.image
  not approved_images[image]
  msg := sprintf("base image %q is not approved", [image])
}

allow if {
  approved_images[input.image]
}
