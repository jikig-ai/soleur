# Learning: merge_queue IaC — probing a provider block schema offline + sweeping positional ruleset readers when a second rule type lands

## Problem

PR-2 of #5780 added a `merge_queue {}` block as a **second rule type** inside
`github_repository_ruleset.ci_required` (sibling to `required_status_checks`).
Two non-obvious traps surfaced:

1. **Verifying the `merge_queue` block schema on the locked provider** without R2
   backend credentials. `terraform init -backend=false` succeeds, but
   `terraform providers schema -json` then fails with
   `Backend initialization required, please run "terraform init"` and emits a
   **0-byte** JSON dump (easy to miss if stderr is suppressed — the empty dump
   looks like "field absent").
2. **A second rule type silently breaks every positional `.rules[0]` reader.**
   Before this PR, `.rules[0].parameters.required_status_checks` was correct
   because the ruleset had exactly one rule. Adding `merge_queue` means GitHub may
   return `rules[]` in any order, so `.rules[0]` can now address the wrong rule.

## Solution

**1. Probe a provider block schema from a scratch dir (no backend needed):**

```bash
SCRATCH=$(mktemp -d)
cat > "$SCRATCH/main.tf" <<'EOF'
terraform {
  required_providers {
    github = { source = "integrations/github", version = "6.12.1" }  # the LOCKED version
  }
}
EOF
( cd "$SCRATCH" && terraform init -input=false >/dev/null && terraform providers schema -json ) \
  | jq '.provider_schemas["registry.terraform.io/integrations/github"]
        .resource_schemas.github_repository_ruleset.block.block_types.rules.block
        .block_types.merge_queue.block.attributes | keys'
rm -rf "$SCRATCH"
```

The scratch dir has no `backend "s3"` block, so `providers schema` runs offline.
Pin the version to the one in `.terraform.lock.hcl` so you read the schema you'll
actually apply. This confirmed all 7 `merge_queue` fields exist on 6.12.1
(`merge_method`, `grouping_strategy`, `max_entries_to_merge`,
`min_entries_to_merge`, `check_response_timeout_minutes`, plus
`max_entries_to_build` + `min_entries_to_merge_wait_minutes` left at default).

**2. Sweep EVERY positional reader to select-by-type when adding a second rule:**

```bash
grep -rn '\.rules\[0\]' scripts/ .github/workflows/ infra/github/ knowledge-base/
# Each executable + documented probe must become:
#   .rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks
```

Executable readers (`apply-github-infra.yml`, `audit-ruleset-bypass.sh`,
`update-ci-required-ruleset.sh`, `create-ci-required-ruleset.sh`,
`destroy-guard-filter.jq`) were already order-independent OR fixed in this PR.
Review caught two **doc** probes left positional — `infra/github/README.md` Phase 3
and `ADR-032` AC16 — in the *same file* where the PR added the "never `.rules[0]`"
mandate. Lesson: when you add a "never do X" mandate, `grep` the same file for
existing X in the same edit.

## Key Insight

- `terraform providers schema -json` needs a real backend OR a backend-less
  scratch dir; `-backend=false` on the real root is NOT sufficient. Always check
  stderr + the dump size — a 0-byte dump is an error, not "field absent."
- Adding a sibling rule to a `github_repository_ruleset` is a **cross-reader
  refactor**: positional `.rules[N]` indexing (executable and documented) must
  move to `select(.type==...)`. The destroy-guard correctly treats a rule
  *addition* as `0 destroy` (no `[ack-destroy]`).
- A hardcoded param literal replicated across a `.tf` and a DR-restore script
  needs a parity test (mirrors the `required_status_checks` T-rsc-9 gate); the
  sync-guard comment alone is an unenforced "MUST."
- Recovering a session-limit-killed planning subagent from the pre-existing
  committed master plan (already deepened for PR-1) beats re-planning — saves
  budget and avoids re-hitting the limit.

## Session Errors

1. **Planning subagent killed by Anthropic session limit** (reset 22:20 Europe/Paris)
   before emitting its Session Summary; its deepen pass left no artifact (git clean).
   **Recovery:** used one-shot's partial-artifact fallback — recovered from the
   committed #5780 master plan (already deepened during PR-1). **Prevention:** none
   needed — one-shot's fallback path already handles this; the recovery is the
   documented pattern. Do NOT re-run a heavy plan+deepen subagent when a deepened
   plan already exists on disk.
2. **`terraform providers schema -json` returned 0 bytes** after `init -backend=false`
   (`Backend initialization required`), with stderr initially suppressed so the
   empty dump read as "field absent." **Recovery:** scratch-dir probe (above).
   **Prevention:** never suppress stderr on a schema/plan probe; check dump size;
   use a backend-less scratch dir for provider-block schema inspection.
3. **`terraform fmt` flagged comment alignment** on the new merge_queue block.
   **Recovery:** `terraform fmt`. **Prevention:** run `terraform fmt` (not just
   `validate`) before committing; CI `infra-validation.yml` runs `fmt -check`.
4. **Positional `.rules[0]` left in README Phase 3 + ADR AC16** while the PR added
   a "never `.rules[0]`" mandate to the same file. **Recovery:** fixed inline at
   review (select-by-type). **Prevention:** when adding a "never do X" mandate,
   `grep` the same file (and sibling runbooks) for existing X in the same edit.
5. **merge_queue param parity test missing** (replicated literal `.tf` ↔ DR script,
   no gate). **Recovery:** added T-mq-1 (RED-verified). **Prevention:** already a
   known review defect class ("replicated literal across ≥2 source files without
   parity test → P2 inline-fix"); add the gate when introducing the replication.

## Tags
category: integration-issues
module: infra/github, terraform, github-merge-queue
