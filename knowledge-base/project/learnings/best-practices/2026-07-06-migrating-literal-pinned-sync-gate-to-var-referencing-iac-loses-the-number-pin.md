---
title: "Migrating a literal-pinned sync gate to a var-referencing IaC declaration silently drops the number pin"
date: 2026-07-06
category: best-practices
tags: [terraform, drift-guard, sync-gate, iac, code-review, integration-id]
issue: 6072
pr: 6079
module: infra/github
---

# Learning: migrating a canonical↔SSOT sync gate from an inline literal to a `var`-referencing `.tf` drops the end-to-end number pin

## Problem

#6072 Terraform-ified the "CLA Required" GitHub ruleset, moving the SSOT from an
imperative `scripts/create-cla-required-ruleset.sh` (whose heredoc carried the
**literal** `integration_id: 15368`) to `infra/github/ruleset-cla-required.tf`
(which binds each `required_check` to `var.actions_integration_id` **by name**).
The two canonical↔SSOT sync gates (`T-cla-1`/`T-cla-1b`) were repointed at the
`.tf`, mirroring the CI ruleset's `T-rsc-9`.

The repointed `T-cla-1` asserted:
- canonical rows are all `15368` (self-referential), and
- the `.tf` binds `var.actions_integration_id` (by name).

It never read `infra/github/variables.tf` to confirm that var's **default == 15368**.
The literal `15368` had moved into `variables.tf` as the var default — the new home
of the number — but nothing pinned it. So editing `default = 15368 → 57789` (the
CodeQL/GHAS app id) would change the deployed integration_id while the gate stayed
green (canonical still says 15368; the `.tf` still binds the var *name*). The
`create-script`-pinned gate had closed this via the inline literal; the naive
var-name migration re-opened it. `test-design-reviewer` caught the unverified last
link in the `canonical:15368 → .tf:var.actions_integration_id → variables.tf:15368`
chain; `data-integrity-guardian` and `pattern-recognition-specialist` independently
flagged the same gap.

## Solution

When a sync/drift gate migrates from an **inline-literal** SSOT to a
**variable-referencing** IaC declaration, add an assertion that the referenced
`var`'s **default equals the literal** the old gate pinned. Restores the
end-to-end lock:

```bash
# T-cla-1: pin the integration_id NUMBER end-to-end.
actions_default=$(awk '/variable "actions_integration_id"/{f=1}
  f&&/^[[:space:]]*default[[:space:]]*=/{gsub(/[^0-9]/,"",$0); print; exit}' \
  "$REPO_ROOT/infra/github/variables.tf")
# ... && "$actions_default" == "15368" ... in the pass condition.
```

RED-proof: flip `variables.tf` default `15368 → 57789` → the gate fails
(`actions_default=57789`). This is the pin the old create-script literal provided
for free.

Two companion robustness fixes surfaced in the same review and are worth carrying
whenever a gate greps/awks an HCL file with comment-naive patterns:

1. **Comment-safe negative checks.** A "must NOT bind codeql" check must match the
   actual `= var.codeql_integration_id` *binding*, never the bare token
   `codeql_integration_id` — a future comment naming the token would false-fail the
   gate. Same SE-3 class as the `context = "..."` header-hygiene rule.
2. **Strip comments before greedy `.*=` value slices.** An awk field extractor that
   does `sub(/.*=[[:space:]]*/,"",v)` on an assignment line will over-consume into a
   trailing `# ... = ...` comment. Strip `sub(/#.*/,"",v)` FIRST, so an inline
   comment containing a stray `=` cannot corrupt the extracted value.

## Key Insight

**A literal pin and a variable-reference pin are not equivalent.** When you move a
number out of an inline literal into a Terraform `var` default, the gate that used
to compare against the literal now compares against a *name* — and the name→number
link is unverified unless you assert the var default. The security-load-bearing
value (here an `integration_id` that gates which app can satisfy a required check)
silently loses its pin. This is a coverage regression that `tsc`/the passing suite
cannot see; a multi-agent review that traces the full `canonical → .tf-var →
variables.tf-default` chain catches it. Note the *existing* CI gate (`T-rsc-9`) has
the same var-name-only shape — so this is a pattern-consistent gap the migration
inherited, worth closing for the security-relevant number.

## Session Errors

1. **Planning subagent Write blocked by `hr-all-infrastructure-provisioning-servers`** —
   the plan's "Apply path" section contained the literal `doppler secrets set` inside
   a *negation* ("no `doppler secrets set` step"), which the PreToolUse hook matched.
   Recovery: rephrased to "no secret-provisioning step." **Prevention:** when a plan/doc
   needs to state that a step is deliberately absent, describe the *absence* without the
   literal provisioning command (say "no secret-provisioning step", not "no `doppler
   secrets set` step"). The hook is intentionally conservative and does not parse
   negation; rephrasing is the correct cheap workaround, not a hook change.
2. **`security-sentinel` agent spawn failed (agent-type not found)** — spawned the
   unqualified display name; the Agent registry requires the fully-qualified
   `soleur:engineering:review:security-sentinel`. Recovery: relaunched with the
   qualified name (the error message enumerated valid names). **Prevention:** the
   `review` skill lists agents by short display name; map each to its
   `soleur:engineering:{review,research}:<name>` form when spawning. Self-documenting
   (the error lists valid names), so no workflow change warranted.
