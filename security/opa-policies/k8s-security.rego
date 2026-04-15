# OPA Rego policies for Kubernetes manifest security validation
# Validates SecureMLOps K8s resources against security best practices

package k8s.security

import rego.v1

# Deny containers running as root
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	not container.securityContext.runAsNonRoot
	msg := sprintf("Container '%s' in Deployment '%s' must set securityContext.runAsNonRoot=true", [container.name, input.metadata.name])
}

# Deny containers without resource limits
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	not container.resources.limits
	msg := sprintf("Container '%s' in Deployment '%s' must define resource limits", [container.name, input.metadata.name])
}

# Deny containers without resource requests
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	not container.resources.requests
	msg := sprintf("Container '%s' in Deployment '%s' must define resource requests", [container.name, input.metadata.name])
}

# Deny containers with privilege escalation
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	container.securityContext.allowPrivilegeEscalation == true
	msg := sprintf("Container '%s' in Deployment '%s' must not allow privilege escalation", [container.name, input.metadata.name])
}

# Deny containers running as privileged
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	container.securityContext.privileged == true
	msg := sprintf("Container '%s' in Deployment '%s' must not run as privileged", [container.name, input.metadata.name])
}

# Deny containers without readiness probes
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	not container.readinessProbe
	msg := sprintf("Container '%s' in Deployment '%s' must define a readiness probe", [container.name, input.metadata.name])
}

# Deny containers without liveness probes
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	not container.livenessProbe
	msg := sprintf("Container '%s' in Deployment '%s' must define a liveness probe", [container.name, input.metadata.name])
}

# Deny services using hostPort
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	port := container.ports[_]
	port.hostPort
	msg := sprintf("Container '%s' in Deployment '%s' must not use hostPort", [container.name, input.metadata.name])
}

# Deny use of latest tag
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	endswith(container.image, ":latest")
	msg := sprintf("Container '%s' in Deployment '%s' must not use 'latest' image tag", [container.name, input.metadata.name])
}

# Deny containers without read-only root filesystem
warn contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	not container.securityContext.readOnlyRootFilesystem
	msg := sprintf("Container '%s' in Deployment '%s' should set readOnlyRootFilesystem=true", [container.name, input.metadata.name])
}

# Deny CronJobs without resource limits
deny contains msg if {
	input.kind == "CronJob"
	container := input.spec.jobTemplate.spec.template.spec.containers[_]
	not container.resources.limits
	msg := sprintf("Container '%s' in CronJob '%s' must define resource limits", [container.name, input.metadata.name])
}

# Warn on NodePort services (acceptable in Minikube but not production)
warn contains msg if {
	input.kind == "Service"
	input.spec.type == "NodePort"
	msg := sprintf("Service '%s' uses NodePort - ensure this is appropriate for the environment", [input.metadata.name])
}
