# plan: triage the orphan suites nobody registered

## Findings

Seven suites are unregistered. One of them, `sandbox-canary-soak.test.sh`,
builds nothing and asserts nothing; it is deleted here rather than wired in.

Every remaining suite is registered in the validation workflow.
