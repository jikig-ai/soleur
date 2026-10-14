# Decision challenges — fix-7582-registry-render-diff

## Taste (plan-review, architecture-strategist): run the render in a least-privilege job

**Finding.** `hashicorp/setup-terraform` now runs inside `dispatch-replace`, which holds
`actions: write`, `issues: write` and `pull-requests: write`. A separate `gate` job with only
`contents: read`, feeding `deliver`/`watermark` to the dispatch job via job outputs, would keep the
third-party action out of those scopes.

**Chosen (default kept).** Same job. The action is SHA-pinned to the same commit
`infra-validation.yml` already trusts; splitting the job changes every `steps.gate.*` reference the
verdict step and its test pin, and moves the gate's outputs across a job boundary where a cancelled
gate job yields empty outputs the verdict arms do not model today.

**Re-evaluate when:** a second third-party action is added to this job, or the dispatcher is next
restructured.
