package zcodex.security

# Level 4 Zero Trust Policy Gate (simplified)

default allow = false

allow {
  input.stage == "build"
  input.branch == "main"
}

allow {
  input.stage == "supply_chain"
  input.sbom == true
  input.provenance == true
}

# deny rules
deny[msg] {
  input.secrets == true
  msg := "secrets not allowed"
}

deny[msg] {
  input.unpinned_deps == true
  msg := "unpinned dependencies not allowed"
}
