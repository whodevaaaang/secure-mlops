package securemlops.security

deny contains msg if {
  some container in input.spec.containers
  not container.securityContext.runAsNonRoot
  msg := sprintf("container %q must set securityContext.runAsNonRoot=true", [container.name])
}

deny contains msg if {
  some container in input.spec.containers
  container.securityContext.runAsUser == 0
  msg := sprintf("container %q must not run as UID 0", [container.name])
}
