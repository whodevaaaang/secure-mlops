package securemlops.security

default min_accuracy := 0.85

deny contains msg if {
  accuracy := input.model.metrics.accuracy
  accuracy < min_accuracy
  msg := sprintf("model accuracy %.3f is below required threshold %.2f", [accuracy, min_accuracy])
}

allow if {
  input.model.metrics.accuracy >= min_accuracy
}
