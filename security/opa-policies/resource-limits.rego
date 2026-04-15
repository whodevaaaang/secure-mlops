# OPA Rego policies for resource governance
# Prevents resource abuse and enforces quotas for ML workloads

package k8s.resource_limits

import rego.v1

# Maximum memory limit for containers (2Gi)
max_memory_bytes := 2147483648

# Maximum CPU limit (2 cores)
max_cpu_millicores := 2000

# Deny memory requests exceeding maximum
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	memory_limit := container.resources.limits.memory
	is_above_max_memory(memory_limit)
	msg := sprintf("Container '%s' memory limit '%s' exceeds maximum allowed (2Gi)", [container.name, memory_limit])
}

# Deny CPU requests exceeding maximum
deny contains msg if {
	input.kind == "Deployment"
	container := input.spec.template.spec.containers[_]
	cpu_limit := container.resources.limits.cpu
	is_above_max_cpu(cpu_limit)
	msg := sprintf("Container '%s' CPU limit '%s' exceeds maximum allowed (2000m)", [container.name, cpu_limit])
}

# Deny replica count above 10
deny contains msg if {
	input.kind == "Deployment"
	input.spec.replicas > 10
	msg := sprintf("Deployment '%s' has %d replicas - maximum allowed is 10", [input.metadata.name, input.spec.replicas])
}

# Deny PVCs larger than 10Gi
deny contains msg if {
	input.kind == "PersistentVolumeClaim"
	storage := input.spec.resources.requests.storage
	is_above_max_storage(storage)
	msg := sprintf("PVC '%s' requests '%s' storage - maximum allowed is 10Gi", [input.metadata.name, storage])
}

# Helper: check if memory string exceeds 2Gi
is_above_max_memory(mem) if {
	endswith(mem, "Gi")
	num := to_number(trim_suffix(mem, "Gi"))
	num > 2
}

is_above_max_memory(mem) if {
	endswith(mem, "Mi")
	num := to_number(trim_suffix(mem, "Mi"))
	num > 2048
}

# Helper: check if CPU string exceeds 2000m
is_above_max_cpu(cpu) if {
	endswith(cpu, "m")
	num := to_number(trim_suffix(cpu, "m"))
	num > 2000
}

is_above_max_cpu(cpu) if {
	num := to_number(cpu)
	num > 2
}

# Helper: check if storage exceeds 10Gi
is_above_max_storage(storage) if {
	endswith(storage, "Gi")
	num := to_number(trim_suffix(storage, "Gi"))
	num > 10
}
