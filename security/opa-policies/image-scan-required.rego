package securemlops.security

default allow := false

allow if {
  input.image_scan.status == "passed"
  input.image_scan.severity_threshold == "HIGH"
  input.image_scan.report != ""
}

deny contains msg if {
  not allow
  msg := "container image scan must pass with HIGH/CRITICAL threshold before deployment"
}
