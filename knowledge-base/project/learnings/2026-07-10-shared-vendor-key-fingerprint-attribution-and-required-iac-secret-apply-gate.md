---
title: "Shared-vendor-key spend is invisible without per-consumer attribution (fingerprint, not name); a new required IaC secret var is an all-or-nothing apply gate"
module: System
date: 2026-07-10
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "Anthropic 'github-claude-code-key' burning ~$50 every 3-4 days with no per-consumer breakdown"
  - "Spend attributed to a key whose named consumer (CI review) last ran Feb 12 and is dormant"
  - "Byte-identical key value across Doppler soleur/ci, soleur/prd, soleur/prd_cla — all prod cron/agent spend silently rolls up under the 'github' label"
root_cause: config_error
resolution_type: workflow_improvement
severity: high
rule_id: hr-tf-variable-no-operator-mint-default
status: open
tags: [cost-attribution, vendor-key, fingerprint, anthropic, observability, terraform, iac-sequencing, one-shot, pr-6266]
synced_to: [deepen-plan]
---

# Anthropic cost attribution (PR #6266) — two load-bearing lessons

One-shot session that added `SOLEUR_CLAUDE_COST` pino-WARN spend markers at three
Anthropic choke points (cost-writer sessions, `spawnClaudeEval` crons,
`postAnthropicMessage` HTTP crons) plus a daily `cron-anthropic-cost-report`. The
trigger was an operator observation: the "github-claude-code-key" was burning ~$50
every 3-4 days.

## 1. Shared-vendor-key spend is invisible without per-consumer attribution — verify consumers by key FINGERPRINT, never by the key's name

The diagnosis that mattered was not "which key is expensive" but "what is actually
spending on this key." The key's **name** — `github-claude-code-key` — was actively
misleading: it implies the GitHub CI review workflow is the spender. It is not. That
CI review key is **dormant** (last run Feb 12). The real finding came from
**fingerprinting the secret value** (length + last-4) across every Doppler config:

- The key value is **byte-identical** across `soleur/ci`, `soleur/prd`, and
  `soleur/prd_cla`.
- So the ENTIRE production Inngest cron-fleet + agent-runner spend is charged to the
  same Anthropic key that carries the "github" label — a single line item hides three
  independent consumer classes.

**Generalizable method for diagnosing shared-vendor spend:**

1. **Fingerprint the secret, don't trust the label.** Compute a non-secret
   fingerprint (`length` + last-4 chars, or a salted hash) and compare it across
   *every* config/environment. A name describes intent at mint time; reuse drifts the
   value away from the name silently. Identical fingerprints across configs = true
   reuse = shared blame.
2. **Enumerate real consumers from telemetry + code, not the key name.** Pull the
   actual callers from logs (who emitted requests) and from `git grep` of the env-var
   name across the codebase — the label tells you who was *supposed* to use it, the
   code + telemetry tell you who *does*.
3. **Instrument at the spend choke points, not the key.** The fix was per-consumer
   markers at the three points where Anthropic dollars are actually spent
   (`cost-writer.persistTurnCost` sessions, `spawnClaudeEval` crons,
   `postAnthropicMessage` HTTP crons) — so future attribution is self-servable from
   Better Stack without re-running this forensic exercise.

**Why this works:** a shared credential collapses N consumers into one billing row.
The only way back to per-consumer cost is to (a) prove the sharing by value, and (b)
tag spend at emit time with the consumer identity. The key's name can never do either
— it is a mint-time artifact, not a runtime fact.

## 2. A new REQUIRED IaC secret variable with NO default is an all-or-nothing apply gate — sequence the resource AFTER the mint, ship the fail-open consumer now

Phase 3 of the feature added a daily Anthropic Admin Cost/Usage cron whose Terraform
introduced a new **required, no-default** variable (`TF_VAR_anthropic_admin_key`).
On an auto-applied infra root, Terraform resolves *every* root variable before
`-target` pruning — so an unprovisioned no-default var fails the **entire** prod
`terraform apply`, not just its own resource. The whole feature's other value (the
per-cron `SOLEUR_CLAUDE_COST` markers, which are pure code) would have been held
hostage to the operator/vendor mint of the Admin key.

**The winning pattern (applied in this PR at review time):**

- **Ship the fail-open consumer now.** The markers are pure code (no `*.tf`), so they
  merge immediately and deliver the measurable outcome (per-consumer attribution) on
  their own. The Admin cron self-reports `key-missing` benignly when the secret is
  absent — fail-open, no crash, no apply gate.
- **Land the `.tf` + the mint in a follow-up.** The Admin-key IaC + vendor-console
  mint were removed from this PR and re-sequenced to a post-mint follow-up. Keeping
  the no-default var is correct (per `hr-tf-variable-no-operator-mint-default`) — only
  the *sequencing* changes: code (no `*.tf` change → the merge-triggered apply does
  not fire) merges first; the IaC PR merges after the mint + `TF_VAR_*` provisioning.

**Why this works:** a required no-default variable is a merge-time precondition on the
whole apply, not a per-resource one. Bundling it with fail-open code couples a
shippable improvement to an operator action with unknown latency. Splitting on the
`*.tf`-touch boundary lets the code half ship independently while the infra half waits
for the credential it genuinely needs. This is the same class as ADR-065
(`RESEND_RECEIVING_API_KEY`) and is already codified at `plan/SKILL.md` (no-default
Terraform variable sequencing) and `hr-tf-variable-no-operator-mint-default`.

## Session Errors

**`git grep <pattern>` from a bare-repo root exits 128.**
- **Recovery:** Ran `git grep <pattern> main` (pin the ref) instead.
- **Prevention:** Already covered by existing bare-repo learnings — `git grep` in a
  bare repo has no working tree, so it needs an explicit tree-ish (`main`).

**Queried the wrong Doppler project (`web-platform` → no access).**
- **Recovery:** Switched to the correct project `soleur`.
- **Prevention:** Run `doppler projects` first to confirm the project slug before any
  `doppler secrets`/`configs` call — the app name is not necessarily the Doppler
  project name.

**Doppler config listing awk-mangled (cosmetic).**
- **Recovery:** None needed — the fingerprint comparison still worked; the mangling was
  display-only.
- **Prevention:** Prefer `doppler secrets get <NAME> --plain` (or `--json`) for a
  single value rather than awk-slicing a formatted table.

**Playwright MCP disconnected mid-session; QA was skipped.**
- **Recovery:** QA skipped — the PR has no executable UI surface (markers + cron are
  server-only), so there were no browser steps to run.
- **Prevention:** For server-only / observability-only PRs, confirm up front there is
  no browser-testable surface so a Playwright drop is a no-op, not a silent gap.

**`iac-plan-write-guard` PreToolUse hook blocked 2 plan writes (hook worked as designed).**
- **Recovery:** Reworded per the hook: literal `doppler secrets set` → routed through a
  `doppler_secret` Terraform resource; "out-of-band" → "independently".
- **Prevention:** No change — the hook is correct; author IaC-secret provisioning as a
  `doppler_secret` resource and avoid imperative `doppler secrets set` in plans.

**3 expected TDD test failures fixed during impl.**
- **Recovery:** Fixed cc-dispatcher call-arg, #5566 tf-`-target` parity, and
  compiled-C4 freshness.
- **Prevention:** One-off — these are the normal RED→GREEN transitions of TDD, not
  process errors.

**[review, P1] ADR ordinal collision — planning subagent picked ADR-103 while ADR-103/104/105 were ALREADY merged on origin/main.**
- **Recovery:** Renumbered ADR-103 → ADR-106 (commit `1f34ab409`); swept the feature's
  artifact set for the stale ordinal.
- **Prevention:** `plan`/`deepen-plan` MUST derive the next ADR number from a
  **freshly-fetched** `origin/main` via
  `ls knowledge-base/engineering/architecture/decisions | grep -oE 'ADR-[0-9]+' | sort -t- -k2 -n | tail -1`,
  NOT the branch base — ADRs merged after the branch point are invisible to a stale
  local `main`. The exact command already lives in `/work` Sharp Edges (SKILL.md:634)
  and the provisional-ordinal + ship-reverify discipline in `plan/SKILL.md:534`, but
  the *planning* subagent had no plan-time derivation bullet. Routed to `deepen-plan`
  Sharp Edges this session (see `synced_to`).

**[review, P2] a new REQUIRED no-default Terraform variable (`TF_VAR_anthropic_admin_key`) fails the ENTIRE prod `terraform apply` until minted.**
- **Recovery:** Removed the Admin-cost-report `.tf` from the PR and re-sequenced it to a
  post-mint follow-up; the cron self-reports `key-missing` benignly meanwhile.
- **Prevention:** See Lesson 2 above. Cross-checked against
  `hr-tf-variable-no-operator-mint-default` and the `plan/SKILL.md:857` no-default-var
  sequencing Sharp Edge — both already codify it; this session confirmed the pattern
  under a real spend feature.

## Related Issues

- `hr-tf-variable-no-operator-mint-default` (AGENTS.core.md) — the no-default IaC var rule.
- `plan/SKILL.md:857` — no-default Terraform variable sequencing Sharp Edge (ADR-065 precedent).
- `plan/SKILL.md:534` — provisional ADR ordinal + `/ship` ADR-Ordinal Collision Gate.
- `work/SKILL.md:634` — next-free ADR number derivation command.
- See also: [operator-mint-tf-var-must-sequence-before-auto-applied-iac.md](workflow-patterns/2026-06-17-operator-mint-tf-var-must-sequence-before-auto-applied-iac.md)
