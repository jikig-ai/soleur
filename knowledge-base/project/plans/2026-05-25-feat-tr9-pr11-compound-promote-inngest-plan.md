---
title: "TR9 PR-11 — migrate scheduled-compound-promote to Inngest cron substrate"
type: feature
issue: "#3948"
parent_issue: "#3948"
branch: feat-one-shot-tr9-pr11-compound-promote-inngest-3948
date: 2026-05-25
status: deepened
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# TR9 PR-11 — migrate scheduled-compound-promote to Inngest cron substrate

## Enhancement Summary

**Deepened on:** 2026-05-25
**Sections enhanced:** 5 (Architecture, FRs, Phases, Acceptance Criteria, Sharp Edges)
**Research sources:** 3 learnings (gray-matter trap, Octokit port pattern, claude-code-spawn reuse), codebase verification (Dockerfile, apply-sentry-infra.yml, cron-monitors.tf)

### Critical Corrections

1. **`gh` CLI unavailable on Hetzner runtime.** The data-flow diagram and several FRs (FR3, FR4, FR11) describe semantics using `gh` CLI syntax, but the Hetzner Dockerfile does NOT install `gh`. ALL GitHub API operations must use Octokit REST calls per TR9 PR-6 learning. The FRs describe the *semantic contract* (what query to run); the implementation is Octokit. This correction applies to: `step.run("dedup-check")` (FR3), `step.run("week-cap")` (FR4), `step.run("apply-and-pr")` conflict guard (FR11), branch push, PR creation, synthetic checks, and issue-list queries.
2. **`apply-sentry-infra.yml` missing `scheduled_stale_deferred_scope_outs` target.** The `.tf` file has `scheduled_stale_deferred_scope_outs` (landed in PR #4457) but the apply workflow's `-target=` list does not include it yet. Phase 3.3 must append BOTH the missing predecessor target AND the new `scheduled_compound_promote` target.
3. **Label `tech-debt` does not exist.** Phase 6 prescribes `--label tech-debt`; the actual label is `type/chore`. Corrected below.

### Learnings Applied

- `2026-05-25-tr9-pr6-gray-matter-yaml11-date-coercion-trap.md` — gray-matter coerces unquoted YAML dates to JS Date objects. Plan already accounts for this (AC10, TS2-TS3). Verified: `promotion-config.yml`'s `enabled:` field is boolean, not date — gray-matter coercion risk is lower but the probe test still catches edge cases (`yes`, `1`, quoted variants).
- `2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern.md` — `gh` CLI absent from Hetzner Dockerfile; all GitHub API calls must use Octokit. CRITICAL: corrected FR3/FR4/FR11 semantics.
- `2026-05-25-tr9-pr7-roadmap-review-claude-code-spawn-pattern-reuse.md` — compound-promote correctly avoids the claude-eval-spawn pattern (pure-TS handler), confirmed by plan's architecture choice.

## Overview

Eleventh in the TR9 substrate migration (umbrella `#3948`). Move the weekly
Layer-2 self-modifying compound-promotion loop from
`.github/workflows/scheduled-compound-promote.yml` (Sundays 00:00 UTC) to an
Inngest cron function on the long-lived Hetzner worker. Sister handlers PR-1
through PR-10 establish the patterns this PR follows.

**Architectural twist vs. PR-7/8/9/10.** The source workflow does NOT use
`anthropics/claude-code-action`. It uses a hand-rolled shell driver
(`scripts/compound-promote.sh`) that:

1. Gates on `knowledge-base/project/promotion-config.yml` `enabled: true`,
2. Derives a per-week PR cap from `gh pr list --label self-healing/auto`,
3. Runs a deterministic shell PII/credential-regex pre-pass over
   `knowledge-base/project/learnings/`,
4. Drops corpus rows whose paths appear in `scripts/retired-rule-ids.txt`
   breadcrumbs,
5. POSTs the surviving corpus (path + `head -n 10` per file) to
   `https://api.anthropic.com/v1/messages` via plain `curl`,
6. Returns base64-encoded JSON clusters via `::compound-promote-clusters-json::`
   stdout sentinels,
7. The workflow then loops over clusters, validates each against an allowlist
   regex + diff-size cap + post-apply byte-budget cap, opens a draft PR per
   cluster with the `self-healing/auto` label, and posts 7 synthetic checks
   per PR (test, dependency-review, e2e, skill-security-scan PR gate, enforce,
   cla-check, cla-evidence).

ADR-027 ("Stateless self-modifying cron — plain Anthropic API, no
claude-code-action wrapper") explicitly chose this shape over a
`claude-code-action`-wrapped two-job split because the wrapper revokes the
GitHub token mid-job, which broke the per-cluster `gh pr create` loop.

**Migration shape choice (locked).** **NOT** the PR-7 claude-eval-spawn
pattern (no `claude` binary, no `--max-turns` budget, no ephemeral repo
clone, no `--allowedTools`). Instead, port the existing shell driver semantics
as a **pure-TS handler** in the PR-6 `cron-strategy-review.ts` shape:

- All API calls via `fetch` (Anthropic Messages) and Octokit (GitHub) inside
  `step.run` for replay memoization.
- Shell PII regex → TS regex constant (preserves the *exact* canonical regex
  bytes; lock via unit test).
- Shell `awk` config parser → `gray-matter` or hand-rolled YAML extraction
  (lock against the YAML 1.1 date-coercion trap; see Sharp Edges).
- Diff allowlist, byte-budget cap, branch-name shape, audit-log row,
  synthetic-check posting → TS port preserving each invariant.
- `git apply --check` / `git apply` / `git commit` / `git push` → spawn `git`
  via `spawnSimple` against an ephemeral clone (the workflow runs `git apply`
  against the checked-out workspace; the Inngest handler clones into
  `/tmp/soleur-cron-compound-promote-*` and pushes from there).

**Why pure-TS and not claude-eval-spawn.** The agent in the GHA workflow is
the Anthropic Messages API directly; it never had `Bash`/`Read`/`Write`/`Edit`
tools, and the workflow's per-cluster gates (allowlist regex, diff-size cap,
post-apply byte-budget, synthetic-checks, branch-name shape assertion) are
*all* implemented in shell BETWEEN the Anthropic call and the PR creation —
they are NOT inside the prompt. Wrapping all of that in a `claude` spawn with
`Bash` access would (a) defeat the architectural reason for ADR-027, (b)
add 165 LoC of substrate per handler that this handler does not need, and
(c) introduce a credential window where a prompt-injected agent could `cat
$GH_TOKEN`. Pure-TS gives us bit-for-bit semantic parity with the shell
driver at smaller blast radius.

**TR9 ADR-033 invariants** still bind: I1 (operations inside `step.run`),
I2 (operator `ANTHROPIC_API_KEY` only — no BYOK; enforced by
`cron-no-byok-lease-sweep.test.ts` which globs `cron-*.ts`), I3 (outer wall-
clock budget via `Promise.race` since there is no claude spawn AbortSignal),
I4 (N/A — no claude binary), I5 (deterministic `step.run` return shapes),
I6 (no event payloads emitted by this handler).

**Substrate extraction follow-up.** After this lands the cron handler count
at the claude-eval substrate is 7 (cron-daily-triage, cron-roadmap-review,
cron-competitive-analysis, cron-bug-fixer, cron-follow-through-monitor,
cron-agent-native-audit, cron-legal-audit). Compound-promote does NOT join
that substrate (it's the pure-TS shape), so the headcount stays at 7 — but
the duplication arithmetic (`~165 LoC × 7 = 1155 LoC`) is unchanged from the
user brief. Phase 6 of this plan files the extraction issue with a sketch of
`_cron-claude-eval-substrate.ts` exporting the shared helpers; the actual
extraction is a separate PR (Phase 6 is *file the issue*, not *do the
extraction*).

**Status:** draft, awaiting plan-review + deepen-plan.

## Issue & branch

- **Branch:** `feat-one-shot-tr9-pr11-compound-promote-inngest-3948`
- **Worktree:** `.worktrees/feat-one-shot-tr9-pr11-compound-promote-inngest-3948/`
- **Closes (post-merge):** umbrella `#3948` is the TR9 parent — DO NOT close
  in PR body; one criterion of #3948 will be ticked off but the umbrella
  remains open for downstream PRs.
- **Refs:** `#2720` (compound-promote v1 plan), `#2718` (parent), `#421`
  (superseded design), `#4017` (TR9 PR-A — ADR-030 + ADR-033 ratified),
  `#4423` (PR-7 reference handler), `#4416` (PR-6 strategy-review — closer
  pure-TS reference), `#4457` (PR-11 cron-stale-deferred-scope-outs — most
  recent merge to substrate).
- **Issue-link line in PR body:** `Refs #3948` (NOT `Closes #3948` — the
  umbrella outlives this PR and one criterion ticked is not the close
  condition).

## User-Brand Impact

**If this lands broken, the user experiences:** the weekly compound-promote
draft PRs stop appearing (silent regression: operator notices weeks later
that learnings have plateaued), OR a malformed handler ships a draft PR
whose contents leak operator-private learning content (PII not redacted,
canonical regex bypass, payload size overflow), OR the substrate clones an
attacker-controlled URL exposing the installation token.

**If this leaks, the user's data is exposed via:** (a) public draft PR body
contains a learning paragraph carrying a PII pattern the regex missed; (b)
Inngest-side log emission contains the installation token (PR-7 redactor
absent); (c) the Anthropic POST body in error-log breadcrumbs includes
content of the corpus.

**Brand-survival threshold:** single-user incident. **Rationale:** a single
public PR body containing a third-party email address or even a
`Sentry.captureException` breadcrumb with the installation token is
operator-visible (the bot opens the PR with its account; the operator-author
of the leaked learning sees it surface in their notifications) and
non-recoverable (the public Git history retains the leak even if the PR is
closed).

`requires_cpo_signoff: true` in frontmatter. CPO sign-off required on the
plan before `/work` begins; carry-forward from #2720's brand-survival framing
applies (the compound-promote loop's plan-time framing was reviewed by CPO at
that time; this PR does not change the framing, only the substrate).

## Architecture (concrete)

### File map

**New file:**

- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
  (handler, ~500 LoC estimated — bounded check below)
- `apps/web-platform/test/server/inngest/cron-compound-promote.test.ts`
  (vitest harness)
- `apps/web-platform/test/server/inngest/cron-compound-promote-graymatter.test.ts`
  (gray-matter YAML-1.1 trap probe; mandatory per Sharp Edges)

**Edit:**

- `apps/web-platform/server/inngest/client.ts` — likely already wires
  cron-* automatically via the registration list in `/api/inngest/route.ts`;
  verify at /work time, no edit if so.
- `apps/web-platform/app/api/inngest/route.ts` — import +
  register `cronCompoundPromote` in the `functions: [...]` list. Insert
  alphabetically between `cronBugFixer` and `cronCompetitiveAnalysis`.
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add
  `resource "sentry_cron_monitor" "scheduled_compound_promote"` mirroring
  the PR-7 / PR-8 / PR-9 / PR-10 / PR-11 shape: name
  `scheduled-compound-promote`, crontab `0 0 * * 0`,
  `checkin_margin_minutes = 30` (Inngest precedent), `max_runtime_minutes =
  10` (pure-TS handler — not claude-eval cohort's 55).
- `.github/workflows/apply-sentry-infra.yml` — append
  `-target=sentry_cron_monitor.scheduled_compound_promote \` (line 192-ish)
  so the auto-apply workflow picks up the new monitor on push to main.

**Delete (same commit, TR9 I-13 hygiene):**

- `.github/workflows/scheduled-compound-promote.yml`
- `scripts/compound-promote.sh` — DEFERRED-DELETE candidate. The script is
  also useful for operator-local hand-testing (the way PR-6 kept
  `scripts/strategy-review-check.sh` per its handler banner). Decision:
  KEEP the script on disk with a banner pointing at the Inngest handler as
  the runtime contract — same precedent as PR-6 cron-strategy-review.ts
  lines 2-5.
- `scripts/compound-promote.test.sh` — keep too (tests the shell script
  which we keep for hand-testing); add a banner noting it does not test the
  runtime contract.

**Out-of-scope (filed as follow-up tracking issues):**

- Substrate extraction: extract shared claude-eval helpers into
  `_cron-claude-eval-substrate.ts`. Issue filed in Phase 6.

### Research Insights — Octokit-Only Constraint

**Critical implementation constraint (from TR9 PR-6 learning):** The data flow below uses `gh` CLI syntax for readability, but ALL GitHub API calls MUST use `@octokit/rest` because the Hetzner Dockerfile (`apps/web-platform/Dockerfile:57-59`) installs only `ca-certificates git bubblewrap socat qpdf` — no `gh` CLI. Affected steps:

- `step.run("dedup-check")` — use `octokit.rest.search.issuesAndPullRequests()`
- `step.run("week-cap")` — use `octokit.rest.search.issuesAndPullRequests()`
- `step.run("apply-and-pr")` conflict guard — use `octokit.rest.search.issuesAndPullRequests()`
- `step.run("apply-and-pr")` PR creation — use `octokit.rest.pulls.create()` + `octokit.rest.issues.addLabels()`
- `step.run("apply-and-pr")` comment posting — use `octokit.rest.issues.createComment()`
- `step.run("apply-and-pr")` synthetic checks — use `octokit.rest.checks.create()`
- Branch push — use `spawnSimple("git", ["push", ...])` (git IS available)

**Reference implementation:** `cron-strategy-review.ts` lines 140-180 demonstrate the Octokit pattern for issue search and creation.

### Data flow (handler internal)

```
Inngest tick (cron: 0 0 * * 0)
  ↓
step.run("mint-installation-token") → installationToken (50-min floor)
  ↓
step.run("read-config") → { enabled: bool }  [gray-matter or hand-rolled awk-equivalent]
  ↓ if !enabled → step.run("sentry-heartbeat-ok-noop") + return { ok: true, status: "disabled" }
  ↓
step.run("dedup-check") → gh issue list --label compound-promote --search '[Scheduled] Compound Promotion in:title' --json number,createdAt
  ↓ if any from last 6 days → step.run("sentry-heartbeat-ok-dedup") + return { ok: true, status: "deduped" }
  ↓
step.run("week-cap") → Octokit `GET /search/issues?q=is:pr is:open label:self-healing/auto repo:jikig-ai/soleur`
  ↓ if remaining <= 0 → sentry-heartbeat-ok + return { ok: true, status: "week-cap-reached" }
  ↓
step.run("collect-corpus") → readdir + read first 10 lines of every learnings/*.md, skip archive/
  ↓
step.run("gdpr-pii-prepass") → drop entries matching PII regex (LOCKED to canonical bytes; unit-tested)
  ↓
step.run("retired-rule-prepass") → drop entries whose path appears in retired-rule-ids.txt breadcrumbs
  ↓ if surviving corpus empty → sentry-heartbeat-ok + return { ok: true, status: "empty-corpus" }
  ↓
step.run("anthropic-cluster") → fetch https://api.anthropic.com/v1/messages with the cluster prompt
  ↓ if stop_reason === "max_tokens" → sentry-heartbeat-ok + return { ok: true, status: "anthropic-truncated" }
  ↓ if response JSON malformed → sentry-heartbeat-error + return { ok: false }
  ↓ hard-slice to REMAINING clusters
  ↓
step.run("setup-ephemeral-workspace") → mkdtemp + git clone --depth=1 + plugin symlink (NOT needed if no claude spawn; defer)
  ↓ [HOLD] do we need an ephemeral workspace? The handler applies diffs and pushes branches.
  ↓     Option A: clone to /tmp, apply + push from there. Matches PR-7's discipline.
  ↓     Option B: drive git ops via Octokit Git Database API (createBlob → createTree → createCommit → createRef).
  ↓     CHOICE: A for parity with the existing workflow's `git apply` flow. Token-redaction discipline applies.
  ↓
step.run("apply-and-pr") for each cluster:
  ├─ target_path allowlist check (regex: ^(AGENTS\.core\.md|plugins/soleur/skills/[A-Za-z0-9_-]+/SKILL\.md)$)
  ├─ MAX_DIFF_BYTES check (16384)
  ├─ diff-path allowlist sweep (every +++ b/<path> matches regex)
  ├─ branch-name shape assertion (^self-healing/auto-[0-9a-f]{64}-[0-9]{4}-[0-9]{2}-[0-9]{2}$)
  ├─ git apply --check → git apply
  ├─ post-apply ALWAYS-LOADED byte cap (AGENTS.md + AGENTS.core.md ≤ 18000)
  ├─ append audit-log row to promotion-log.md
  ├─ git commit -m "<title>" -m "<trailer>"
  ├─ git push -u origin <branch>
  ├─ gh pr create --draft --label self-healing/auto
  └─ POST 7 synthetic checks via Octokit checks API
  ↓
step.run("teardown-ephemeral-workspace") (best-effort)
  ↓
step.run("sentry-heartbeat") → ok/error
  ↓
return { ok, status, clustersOpened }
```

### Workflow flag bindings (verbatim claude_args adoption — N/A here)

The source workflow does NOT use `claude_args:` (no claude-code-action).
Instead, the runtime contract is the Anthropic Messages API payload built in
`scripts/compound-promote.sh:179-184`:

- `model: claude-sonnet-4-6`
- `max_tokens: 16384`
- `messages[0].role: user`, `content: PROMPT + "\n\nCorpus:\n" + JSON.stringify(corpus)`

Preserve these verbatim in the TS port. Lock with a unit test that asserts
the request body keys + the model name (regression-fail any silent model
swap).

### Inngest function registration

```ts
export const cronCompoundPromote = inngest.createFunction(
  {
    id: "cron-compound-promote",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 0 * * 0" },
    { event: "cron/compound-promote.manual-trigger" },
  ],
  cronCompoundPromoteHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
```

### Sentry monitor

```hcl
# TR9 PR-11 (closes one criterion of #3948): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`. NEW
# monitor — the GHA scheduled-compound-promote workflow ran on GHA's runner
# pool with no Sentry check-in. The GHA workflow was deleted in the same
# commit per TR9 I-13 hygiene.
# Weekly Sunday 00:00 UTC. Inngest-fired (not GHA) — 30-min margin per the
# Inngest-fired precedent. Single-miss alert. 10 min mirrors the small-cron
# cohort (scheduled_oauth_probe, scheduled_stale_deferred_scope_outs) — this
# handler is pure-TS with no claude-eval spawn, so the 55-min budget is
# unwarranted.
resource "sentry_cron_monitor" "scheduled_compound_promote" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-compound-promote"
  schedule                = { crontab = "0 0 * * 0" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}
```

## Functional Requirements

| FR  | Description                                                                                           |
|-----|-------------------------------------------------------------------------------------------------------|
| FR1 | `cron-compound-promote` Inngest function fires weekly at Sunday 00:00 UTC via `{ cron: "0 0 * * 0" }`.|
| FR2 | Handler reads `knowledge-base/project/promotion-config.yml` and no-ops with status `"disabled"` if `enabled: false` (default).|
| FR3 | Pre-Anthropic dedup gate: Octokit `GET /search/issues?q=is:issue+is:open+label:self-healing/auto+repo:jikig-ai/soleur+"[Scheduled] Compound Promotion"+in:title` (semantically: find open issues with `self-healing/auto` label whose title contains `[Scheduled] Compound Promotion`); if any result's `created_at` is within the last 6 days, no-op with status `"deduped"`. NEW vs. shell driver — fills the user-flagged gap. **Implementation note:** `gh` CLI is not available on the Hetzner runtime; use Octokit REST per TR9 PR-6 learning.|
| FR4 | Per-week cap derived from `gh pr list --label self-healing/auto --state open`; if remaining ≤ 0, no-op with status `"week-cap-reached"`.|
| FR5 | GDPR PII pre-pass uses the *exact* canonical regex from `scripts/compound-promote.sh:75` (locked by unit test against the byte-for-byte regex string). Emits per-excluded-path log breadcrumb without leaking the matched line content.|
| FR6 | Retired-rule pre-pass parses `scripts/retired-rule-ids.txt` and drops any learning whose path appears in a breadcrumb column.|
| FR7 | Anthropic POST uses `model: "claude-sonnet-4-6"`, `max_tokens: 16384`, payload structure preserved verbatim from `compound-promote.sh:179-184` (locked by unit test).|
| FR8 | Anthropic response truncation (`stop_reason === "max_tokens"`) returns `ok: true, status: "anthropic-truncated"` and emits empty clusters (parity with shell driver).|
| FR9 | Per-cluster: target_path allowlist regex (`^(AGENTS\.core\.md\|plugins/soleur/skills/[A-Za-z0-9_-]+/SKILL\.md)$`), diff-size cap (16384 bytes), diff-path allowlist sweep, branch-name shape assertion, post-apply always-loaded byte cap (18000 bytes for AGENTS.md + AGENTS.core.md combined) — all preserved bit-for-bit from `scheduled-compound-promote.yml:122-208`.|
| FR10| **AGENTS.core.md hr- rule guard.** Pre-apply check: parse the unified diff; if any `-` line on AGENTS.core.md starts with a bullet whose body contains the pattern `\[id: hr-`, REFUSE the cluster with log `agents-core-hr-rule-edit-refused`. Hard rules require human-author edits, not auto-promotion.|
| FR11| **Skill-content conflict guard.** Before applying any cluster whose `target_path` matches `plugins/soleur/skills/`, query Octokit `GET /search/issues?q=is:pr+is:open+repo:jikig-ai/soleur+"plugins/soleur/skills"+in:files` (semantically: `gh pr list --search 'plugins/soleur/skills in:files' --state open`). If any open PR touches that path, post a comment on that PR via Octokit with the proposed diff and SKIP the cluster (do NOT open a conflicting branch). **Implementation note:** `gh` CLI unavailable on Hetzner; use Octokit REST per TR9 PR-6 learning.|
| FR12| Per-cluster commit carries the provenance trailer: `Bot-Author: compound-promotion-loop@<RUN_SHA>\nSource-Learnings: <csv>\nThreshold-Hit: <count>/5\nCluster-Hash: <hex>\nTier: <tier>` (verbatim from `.github/workflows/scheduled-compound-promote.yml:226-227`).|
| FR13| Per-cluster PR body anchors `human review required` (literal phrase, byte-anchored) AND is opened with `--draft` AND carries the `self-healing/auto` label.|
| FR14| 7 synthetic checks posted per PR via Octokit `repos.createCheckRun`: `test`, `dependency-review`, `e2e`, `skill-security-scan PR gate`, `enforce`, `cla-check`, `cla-evidence` (verbatim names + payloads from `scheduled-compound-promote.yml:248-300`).|
| FR15| Append-only audit row written to `knowledge-base/project/learnings/promotion-log.md` in the same Git commit as the diff (preserves existing schema).|
| FR16| Sentry heartbeat POST at end with `status=ok|error`. Domain/project/key validators (`SENTRY_DOMAIN_RE`, `SENTRY_PROJECT_RE`, `SENTRY_PUBLIC_KEY_RE`) mirror PR-7.|
| FR17| Installation token redacted from all stdout/stderr/error-emit paths via `redactToken` helper (verbatim PR-7 shape). NO log line, NO Sentry breadcrumb, NO `reportSilentFallback` extra carries the raw token.|
| FR18| ANTHROPIC_API_KEY redaction: error breadcrumbs must NOT echo the request body (it carries the key in headers but the body also contains the corpus paths). Lock with a unit test against the spawned error path.|
| FR19| The GHA workflow file `.github/workflows/scheduled-compound-promote.yml` is deleted in the same commit per TR9 I-13 hygiene.|
| FR20| `scripts/compound-promote.sh` and `scripts/compound-promote.test.sh` are kept on disk; both files receive a header banner noting the runtime contract has moved to the Inngest handler (parity with PR-6 cron-strategy-review.ts header lines 2-5).|

## Research Reconciliation — Spec vs. Codebase

| Spec/brief claim | Codebase reality | Plan response |
|------------------|------------------|---------------|
| "Same claude-code-spawn pattern as PR-7/8/9/10" | The source workflow does NOT use `claude-code-action` (see `scheduled-compound-promote.yml:64-102` — direct `bash scripts/compound-promote.sh` + inline `gh pr create` loop). ADR-027 explicitly chose this shape to dodge the wrapper's token revocation. | Plan adopts the **PR-6 pure-TS pattern** (`cron-strategy-review.ts`), NOT the PR-7 claude-eval-spawn pattern. Brief is corrected. |
| "compound-promote reads learning files via gray-matter" | `compound-promote.sh:143` reads the first 10 lines via `head -n 10` and passes the raw text to Anthropic. It does NOT call gray-matter or parse frontmatter at all. | Plan preserves the `head -n 10` semantic (Node: split lines, slice(0, 10), join). The gray-matter probe is added because the *handler MIGHT need* to parse frontmatter for the dedup heuristic OR if the future shape adds metadata-aware filtering; even so, the YAML-1.1 trap probe is mandatory (Sharp Edges, cron-strategy-review precedent). |
| "ADR-021 governs stateless self-modifying cron" | `compound-promote.sh:15` references ADR-021. The actual ADR is at `ADR-027-stateless-self-modifying-cron.md` (the v1 plan reserved ADR-021; it was reused by `ADR-021-kb-binary-serving-pattern.md` before ADR-027 was filed). | Plan cites ADR-027 (correct slot). The stale ADR-021 comment in `compound-promote.sh` is out of scope — flag for follow-up in the Sharp Edges list of this plan. |
| "direct-ANTHROPIC_API_KEY classification" | True. Every cron-*.ts handler that uses Anthropic uses `ANTHROPIC_API_KEY` via `buildSpawnEnv` (claude-eval cohort) or `process.env.ANTHROPIC_API_KEY` directly (pure-TS cohort like strategy-review). Both are operator key, not BYOK. `cron-no-byok-lease-sweep.test.ts` covers compound-promote automatically via cron-* glob. | No action needed beyond the I2 invariant statement in the handler banner. |
| "label `compound-promote`" | `gh label list --search compound-promote` returns empty. The label `self-healing/auto` exists (referenced throughout the workflow); `compound-promote` does NOT. | Two options: (a) use the existing `self-healing/auto` label for the dedup-search issue title scope, OR (b) introduce a new `compound-promote` label and create it idempotently in handler. RECOMMENDATION: use `self-healing/auto` (already exists, semantically scoped, no new label needed). FR3 amended in the FR table to use `self-healing/auto` as the dedup-search label. |
| "claude_args" | The workflow has no `claude_args:` field. There is no claude-code-action wrapper. | No claude_args parity to verify. The Anthropic POST body shape is the equivalent contract. |
| "Hetzner runbook + ops/runbooks/compound-promote-runbook.md" | Found at `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`. Read in full at plan time. | Phase 4 updates the runbook to point at the Inngest handler as the runtime contract. The "Opt in" gh-workflow-run instructions become "Trigger via Inngest event `cron/compound-promote.manual-trigger`". |
| "7-handler threshold for substrate extraction" | Verified: 7 handlers grep-positive for `spawnClaudeEval|CLAUDE_CODE_FLAGS` — daily-triage, roadmap-review, competitive-analysis, bug-fixer, follow-through-monitor, agent-native-audit, legal-audit. **Compound-promote does NOT join this cohort** (pure-TS), so it remains at 7 after PR-11. | Phase 6 still files the extraction issue (the threshold was met *before* this PR; we are documenting the technical debt, not blocked on extraction landing first). |

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --json number,title,body --limit 200`. Then per-file grep on planned files (`apps/web-platform/server/inngest/functions/cron-compound-promote.ts`, `apps/web-platform/test/server/inngest/cron-compound-promote.test.ts`, `apps/web-platform/infra/sentry/cron-monitors.tf`, `.github/workflows/apply-sentry-infra.yml`, `apps/web-platform/app/api/inngest/route.ts`, `scripts/compound-promote.sh`, `scripts/compound-promote.test.sh`, `.github/workflows/scheduled-compound-promote.yml`, `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`).

**Result:** None. (No code-review issues currently reference compound-promote
or the cron-substrate files.)

## Domain Review

**Domains relevant:** Engineering (CTO), Security (CISO), Legal (CLO).

### Engineering (CTO)
**Status:** carry-forward from #2720 + TR9 ADR-033 framing.
**Assessment:** Substrate migration; no new architecture. The pure-TS choice
is the correct one (avoids wrapper post-step + the claude-eval substrate's
~165 LoC overhead for a handler that doesn't need agent tools). Substrate
extraction tech debt acknowledged in Phase 6.

### Security (CISO)
**Status:** new sub-assessment for this PR.
**Assessment:** Three new exposure surfaces vs. GHA-era:
1. **Installation token** is now in long-lived process memory (Hetzner Node)
   for the 50-min token lifetime, vs. GHA's job-scoped `GITHUB_TOKEN`. The
   PR-7 redactor pattern + buildSpawnEnv allowlist must be ported verbatim.
2. **ANTHROPIC_API_KEY** is in the worker's env. Pre-existing posture (every
   pure-TS Anthropic-calling handler has the same exposure); no incremental
   risk.
3. **AGENTS.core.md hr- rule edit refusal** (FR10) is a NEW guard not in the
   shell driver. Bumps blast-radius down: even if a cluster proposes a
   hard-rule edit, the handler refuses pre-apply.

### Legal (CLO)
**Status:** carry-forward from #2720 brand-survival framing + DPIA candidate.
**Assessment:** No new DPIA surface — the corpus flow is identical to the
shell driver (path + first-10-lines per file, GDPR shell pre-pass, retired
pre-pass). The "DPIA candidate" note in the existing runbook (line 130-131)
continues to apply; PR-11 does not advance or close it.

### Product/UX Gate
**Tier:** none.
**Decision:** N/A — pure infrastructure migration, no user-facing UI.

## Infrastructure (IaC)

### Terraform changes
- **File edited:** `apps/web-platform/infra/sentry/cron-monitors.tf`
- **New resource:** `sentry_cron_monitor.scheduled_compound_promote`
- **Providers:** `jianyuan/sentry` (existing, no version bump)
- **Sensitive variables:** none new (uses existing `var.sentry_org` and
  `data.sentry_project.web_platform.slug`).

### Apply path
**Auto-apply on push to main** via `.github/workflows/apply-sentry-infra.yml`.
The workflow scopes `terraform apply -target=` to each enumerated monitor
resource. Append the new `-target=sentry_cron_monitor.scheduled_compound_promote
\` to the target list (line 192-ish, after `scheduled_competitive_analysis`).

No operator action needed — the auto-apply workflow fires on push to main
post-merge.

### Distinctness / drift safeguards
- The monitor name `scheduled-compound-promote` mirrors the workflow filename
  convention used by all 16 existing monitors. Sentry slugifies `name` to the
  monitor slug — the `SENTRY_MONITOR_SLUG` const in the handler MUST match
  the slugified form (`scheduled-compound-promote`).
- No `dev/prd` distinction (Sentry is single-org).
- No `lifecycle.ignore_changes` needed (this is a create-not-import path, no
  beta provider quirks per PR-Sentry-Sweep tech debt).

### Vendor-tier reality check
Sentry organization Crons tier: paid (already in use by all 16 monitors). No
new tier gate.

## Observability

```yaml
liveness_signal:
  what: Sentry Crons heartbeat POST to https://<SENTRY_INGEST_DOMAIN>/api/<SENTRY_PROJECT_ID>/cron/scheduled-compound-promote/<SENTRY_PUBLIC_KEY>/?status=ok|error
  cadence: weekly (Sunday 00:00 UTC); fires on each handler invocation
  alert_target: Sentry Crons → projects/web-platform → monitor scheduled-compound-promote → email + Discord (existing channels)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf + apps/web-platform/server/inngest/functions/cron-compound-promote.ts (postSentryHeartbeat)

error_reporting:
  destination: Sentry (`reportSilentFallback` from `@/server/observability`)
  fail_loud: true (errors mirrored to Sentry with structured `feature` + `op` + `extra` per PR-7 pattern; no swallow)

failure_modes:
  - mode: Anthropic API failure (network / 5xx / 429)
    detection: fetch throw OR response.ok === false
    alert_route: Sentry breadcrumb `cron-compound-promote / anthropic-cluster-failed` + Sentry heartbeat `status=error` + missed-checkin alert on next-week failure
  - mode: Anthropic JSON malformed (LLM emitted non-array, broken schema)
    detection: jq-equivalent guard (`if !Array.isArray(parsed)`)
    alert_route: Sentry breadcrumb `cron-compound-promote / anthropic-shape-invalid` + heartbeat `status=error`
  - mode: stop_reason === "max_tokens" (truncated response)
    detection: response.stop_reason check
    alert_route: Sentry warning breadcrumb (NOT error; parity with shell driver "fail-soft" — emit empty clusters, no PRs opened that week)
  - mode: target_path allowlist refusal (cluster proposes write outside allowlist)
    detection: regex test in apply-and-pr loop
    alert_route: Sentry warning breadcrumb `cron-compound-promote / target-path-refused` with the refused path (NOT the full diff body — bound the breadcrumb size)
  - mode: AGENTS.core.md hr- rule edit attempt (FR10)
    detection: parse `-` lines, regex `\[id: hr-`
    alert_route: Sentry breadcrumb `cron-compound-promote / agents-core-hr-rule-edit-refused` with cluster_hash
  - mode: Open PR conflict (FR11 — open PR already touches plugins/soleur/skills)
    detection: gh pr list response non-empty
    alert_route: Sentry info breadcrumb + post comment on the existing PR (the comment is the human-visible signal)
  - mode: post-apply byte-budget overflow (always-loaded payload > 18000)
    detection: wc -c equivalent in TS, post-apply
    alert_route: Sentry breadcrumb `cron-compound-promote / byte-budget-overflow` + revert the apply
  - mode: git apply --check failure (malformed diff)
    detection: git child-process exit code
    alert_route: Sentry breadcrumb `cron-compound-promote / git-apply-check-failed`
  - mode: gray-matter date trap (handler tries to parse promotion-config.yml `enabled:` and YAML 1.1 coerces unexpectedly)
    detection: vitest unit test against real matter() output (Sharp Edges)
    alert_route: caught at CI, not at runtime
  - mode: handler wall-clock budget exceeded (MAX_RUN_DURATION_MS)
    detection: Promise.race wins
    alert_route: Sentry breadcrumb `cron-compound-promote / wall-clock-exceeded` + heartbeat `status=error`

logs:
  where: pino structured logs in Hetzner worker (`fn: "cron-compound-promote"` tag) + Sentry breadcrumbs (via reportSilentFallback)
  retention: pino → Hetzner journald (host disk, ~14 days rotation). Sentry → 90 days per project retention.

discoverability_test:
  command: |
    # 1. Verify the handler is registered:
    curl -s -X PUT https://soleur.ai/api/inngest -H "x-inngest-signature: ..." | jq '.functions | map(select(.id == "cron-compound-promote"))'
    # 2. Verify the Sentry monitor exists:
    curl -s "https://sentry.io/api/0/organizations/$SENTRY_ORG/monitors/scheduled-compound-promote/" -H "Authorization: Bearer $SENTRY_TOKEN"
    # 3. Trigger a manual fire (Inngest event):
    curl -s -X POST https://soleur.ai/api/inngest -H "content-type: application/json" -d '{"name":"cron/compound-promote.manual-trigger","data":{}}'
    # 4. Read the latest run from Inngest UI: https://app.inngest.com/env/production/functions/cron-compound-promote
  expected_output: |
    1. Returns one function record with id "cron-compound-promote" and the cron expression "0 0 * * 0".
    2. Returns 200 + monitor object with last_check_in field populated post-fire.
    3. Returns 200 + event_id from Inngest accepting the manual trigger event.
    4. Browser-visible: most-recent run shows status "Completed" and the step.run("sentry-heartbeat") emitted `status: "ok"` (or `disabled` / `deduped` / `week-cap-reached` / `empty-corpus`).
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` exists and exports `cronCompoundPromote` (the Inngest function) + `cronCompoundPromoteHandler` (the bare handler for tests). Verify: `grep -E "^export (const|async function) (cronCompoundPromote|cronCompoundPromoteHandler)" apps/web-platform/server/inngest/functions/cron-compound-promote.ts` returns 2 matches.
- [ ] **AC2.** Handler is registered in `apps/web-platform/app/api/inngest/route.ts` `functions: [...]` list. Verify: `grep -c "cronCompoundPromote" apps/web-platform/app/api/inngest/route.ts` returns ≥ 2 (import + array entry).
- [ ] **AC3.** Cron expression matches the GHA workflow exactly. Verify: `grep -E 'cron:\s*"0 0 \* \* 0"' apps/web-platform/server/inngest/functions/cron-compound-promote.ts` returns 1 match.
- [ ] **AC4.** Sentry monitor resource exists with `crontab = "0 0 * * 0"`. Verify: `grep -A8 '"scheduled_compound_promote"' apps/web-platform/infra/sentry/cron-monitors.tf | grep -E 'crontab\s*=\s*"0 0 \* \* 0"'` returns 1 match.
- [ ] **AC5.** Sentry auto-apply targets appended (both `scheduled_compound_promote` AND the missing `scheduled_stale_deferred_scope_outs` from PR #4457). Verify: `grep -c '\-target=sentry_cron_monitor.scheduled_compound_promote' .github/workflows/apply-sentry-infra.yml` returns 1 AND `grep -c '\-target=sentry_cron_monitor.scheduled_stale_deferred_scope_outs' .github/workflows/apply-sentry-infra.yml` returns 1.
- [ ] **AC6.** GHA workflow file deleted. Verify: `[[ ! -f .github/workflows/scheduled-compound-promote.yml ]]` returns true (exit 0).
- [ ] **AC7.** `scripts/compound-promote.sh` and `scripts/compound-promote.test.sh` retained on disk WITH a banner pointing at the Inngest handler. Verify: `head -10 scripts/compound-promote.sh | grep -E "Runtime contract has moved to .* cron-compound-promote\.ts"` returns 1 match.
- [ ] **AC8.** Canonical PII regex byte-for-byte matches the shell driver. Verify: the regex string literal in the TS handler is the same character sequence as `awk 'NR==75 && /^PII_REGEX=/' scripts/compound-promote.sh` (single-quoted bash value, character-by-character compare). Unit test in `cron-compound-promote.test.ts` enforces this by importing both and asserting `TS_PII_REGEX.source === BASH_PII_REGEX_STRING`.
- [ ] **AC9.** Anthropic POST body uses `model: "claude-sonnet-4-6"` and `max_tokens: 16384`. Unit-test-locked.
- [ ] **AC10.** gray-matter YAML-1.1 trap probe test exists and passes. Verify: `apps/web-platform/test/server/inngest/cron-compound-promote-graymatter.test.ts` exists AND `bun vitest run cron-compound-promote-graymatter` passes locally. The test feeds `enabled: true` (unquoted YAML scalar) AND `enabled: "true"` (quoted) into `matter()` and asserts the handler's config-extractor normalizes both to the bool `true`. If the handler does NOT use gray-matter (chooses hand-rolled extraction), the test still asserts the same parity against the extraction function — the trap is on the *boolean/date coercion shape*, not on gray-matter specifically.
- [ ] **AC11.** Pure-grep enforcement: handler contains NO `claude` binary spawn. Verify: `grep -E '(claude_args|CLAUDE_BIN|resolveClaudeBin|spawnClaudeEval|--allowedTools)' apps/web-platform/server/inngest/functions/cron-compound-promote.ts` returns 0 matches.
- [ ] **AC12.** `cron-no-byok-lease-sweep.test.ts` passes (auto-glob covers the new handler). Verify: `cd apps/web-platform && bun vitest run cron-no-byok-lease-sweep`.
- [ ] **AC13.** No log line, breadcrumb, or error message in the handler emits a raw installation token. Verify by unit test: spawn the handler with a sentinel token `"INSTALLATION_TOKEN_SENTINEL_DO_NOT_LEAK"`, intercept logger / Sentry calls, assert none contain the sentinel.
- [ ] **AC14.** AGENTS.core.md hr- rule guard (FR10) is enforced. Verify by unit test: feed a synthesized cluster whose diff removes a line containing `[id: hr-foo]`, assert the handler logs `agents-core-hr-rule-edit-refused` and does NOT open a PR.
- [ ] **AC15.** Skill-content conflict guard (FR11) is enforced. Verify by unit test: mock `gh pr list ... in:files` to return a non-empty list when target_path matches `plugins/soleur/skills/`, assert the handler posts a comment on the existing PR (mocked Octokit) and does NOT create a new branch.
- [ ] **AC16.** PR body contains the literal anchor `human review required`. Verify: the PR body template in the handler contains that exact string. (Existing workflow at line 231 uses "Reviewer: verify..."; promote the anchor in the TS port.)
- [ ] **AC17.** Per-cluster commit message trailer matches `Bot-Author: compound-promotion-loop@<sha>\nSource-Learnings: ...\nThreshold-Hit: <count>/5\nCluster-Hash: <hex>\nTier: ...`. Unit-test-locked against a synthesized cluster.
- [ ] **AC18.** Synthetic checks: handler calls Octokit `repos.createCheckRun` exactly 7 times per PR with names `["test", "dependency-review", "e2e", "skill-security-scan PR gate", "enforce", "cla-check", "cla-evidence"]` and `conclusion: "success"`. Unit-test-locked.
- [ ] **AC19.** Runbook updated. Verify: `grep -c "Inngest" knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` returns ≥ 3 (data flow, runtime contract, manual-trigger event name).
- [ ] **AC20.** `bun vitest run cron-compound-promote` passes locally + on CI.
- [ ] **AC21.** `bun tsc --noEmit` passes (no type errors introduced).
- [ ] **AC22.** PR description body contains `Refs #3948` (NOT `Closes #3948`); umbrella stays open per the deferred-scope-out semantic.

### Post-merge (operator)

- [ ] **PM1.** Confirm the auto-apply Sentry infra workflow ran and the new monitor exists. Verify: `gh run list --workflow apply-sentry-infra.yml --limit 1 --json status,conclusion` shows the most-recent run completed; then `curl -s "https://sentry.io/api/0/organizations/$SENTRY_ORG/monitors/scheduled-compound-promote/" -H "Authorization: Bearer $SENTRY_TOKEN"` returns 200.
- [ ] **PM2.** Confirm the next Inngest scheduled run on Sunday 00:00 UTC fires. Verify via Inngest UI (`https://app.inngest.com/env/production/functions/cron-compound-promote`) — at minimum a `disabled` / `deduped` / `week-cap-reached` / `empty-corpus` no-op completion. Note: this is automatable via Inngest's `/api/v1/runs` REST endpoint but requires `INNGEST_API_KEY` Doppler secret; if not yet provisioned, the UI check is acceptable post-merge per the operator-only step justification: "Inngest REST API requires a separate signing key not yet in Doppler — defer to PM3 cycle."
- [ ] **PM3.** Verify the historical GHA cron is NOT firing post-merge. Verify: `gh run list --workflow scheduled-compound-promote.yml --limit 1` returns "no workflow found" (file is deleted).
- [ ] **PM4.** Substrate-extraction follow-up issue filed (Phase 6) and assigned `priority/p3-low`, `domain/engineering`, `tech-debt` labels.

## Phases (TDD)

### Phase 0 — Preconditions & invariants
0.1. Verify worktree CWD is correct (already done at one-shot entry).
0.2. Read all three references end-to-end: `cron-strategy-review.ts` (pure-TS pattern), `cron-roadmap-review.ts` (claude-eval pattern — for contrast), `scripts/compound-promote.sh` (logic to port verbatim).
0.3. Read `apps/web-platform/test/server/cron-strategy-review-graymatter.test.ts` and `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` (the two guard tests that *automatically* fire on the new handler).
0.4. Read the existing `apps/web-platform/app/api/inngest/route.ts` to confirm the registration pattern.
0.5. Read `apps/web-platform/infra/sentry/cron-monitors.tf` lines 251-300 for the PR-7-shaped resource template.
0.6. Confirm the literal `\bcompound-promote\b` label does NOT exist (`gh label list | grep -E '\bcompound-promote\b'` returns empty); use `self-healing/auto` everywhere.

### Phase 1 — RED tests
1.1. Create `apps/web-platform/test/server/inngest/cron-compound-promote.test.ts` with vitest cases for AC8–AC18 (config gate, dedup gate, week-cap gate, PII regex byte-equality, retired-rule pre-pass, Anthropic body shape, max_tokens truncation, target_path allowlist, MAX_DIFF_BYTES, byte-budget cap, AGENTS.core.md hr- guard, skill-conflict guard, redaction, trailer shape, synthetic checks count).
1.2. Create `apps/web-platform/test/server/inngest/cron-compound-promote-graymatter.test.ts` mirroring `cron-strategy-review-graymatter.test.ts` shape, against the config-extractor function from the handler.
1.3. Confirm all tests FAIL (the handler doesn't exist yet).

### Phase 2 — GREEN handler implementation
2.1. Write `cron-compound-promote.ts`. Modules:
- Constants (SENTRY_MONITOR_SLUG, MAX_RUN_DURATION_MS, REPO_OWNER, REPO_NAME, regex constants, allowlist regexes, byte caps).
- Helpers: `readPromotionConfig`, `extractEnabledFlag` (gray-matter or hand-rolled), `dedupCheck`, `weekCapCheck`, `collectCorpus` (with PII pre-pass), `applyRetiredRulePrepass`, `buildAnthropicRequest`, `parseAnthropicResponse`, `applyClusterAndOpenPR`, `postSyntheticChecks`, `redactToken`, `postSentryHeartbeat`, `setupEphemeralWorkspace`, `teardownEphemeralWorkspace`.
- `cronCompoundPromoteHandler` orchestrating `step.run` over the data-flow described above.
- Inngest registration at file bottom.
2.2. Run vitest until every test passes.

### Phase 3 — Wire-up
3.1. Edit `apps/web-platform/app/api/inngest/route.ts` (import + array entry).
3.2. Edit `apps/web-platform/infra/sentry/cron-monitors.tf` (new resource block at the end, after `scheduled_stale_deferred_scope_outs`).
3.3. Edit `.github/workflows/apply-sentry-infra.yml`: append `-target=sentry_cron_monitor.scheduled_stale_deferred_scope_outs \` (missing from PR #4457) AND `-target=sentry_cron_monitor.scheduled_compound_promote \` to the `-target=` list. Insert both after `scheduled_competitive_analysis`, maintaining alphabetical order where practical.
3.4. Delete `.github/workflows/scheduled-compound-promote.yml`.
3.5. Add banner comments to `scripts/compound-promote.sh` and `scripts/compound-promote.test.sh` (1:1 PR-6 cron-strategy-review.ts header convention).

### Phase 4 — Runbook
4.1. Update `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`:
- Replace "weekly GitHub Actions cron (Sunday 00:00 UTC)" with "weekly Inngest cron function (Sunday 00:00 UTC) at `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`".
- Replace `gh workflow run scheduled-compound-promote.yml` with the Inngest manual-trigger curl recipe (see Observability discoverability_test).
- Add a Sharp Edges entry: "ADR-021 reference in `scripts/compound-promote.sh:15` is stale — actual ADR is ADR-027. Out of scope for PR-11; file as follow-up."
- Add a `Related artifacts` entry: `Handler: apps/web-platform/server/inngest/functions/cron-compound-promote.ts`.

### Phase 5 — CI green + multi-agent review
5.1. `bun tsc --noEmit` + `bun vitest run` + lint (per repo standards).
5.2. Push branch, open draft PR with `Refs #3948` in body.
5.3. Multi-agent review per single-user-incident threshold: invoke deepen-plan + plan-review at the appropriate workflow gates (handled by one-shot pipeline).

### Phase 6 — Substrate extraction tracking issue
6.1. `gh issue create --label priority/p3-low,domain/engineering,type/chore --milestone "Post-MVP / Later" --title "tech-debt(cron-substrate): extract shared claude-eval helpers into _cron-claude-eval-substrate.ts"` with body summarizing: 7 handlers duplicate ~165 LoC each (`resolveClaudeBin`, `buildSpawnEnv`, `buildAuthenticatedCloneUrl`, `redactToken`, `mintInstallationToken`, `spawnSimple`, `setupEphemeralWorkspace`, `teardownEphemeralWorkspace`, `spawnClaudeEval`, `postSentryHeartbeat`, the 3 Sentry validator regexes). Proposed extraction file: `apps/web-platform/server/inngest/_cron-claude-eval-substrate.ts`. Estimated saving: ~1000 LoC. Recommendation: extract BEFORE the next TR9 cron migration (whichever cron lands next that uses claude-eval).
6.2. Reference the new issue in the PR body as "Follow-up: tech-debt #<N>".

## Test Scenarios

(All vitest cases inside `cron-compound-promote.test.ts` unless noted.)

| ID  | Scenario | Expected |
|-----|----------|----------|
| TS1 | promotion-config.yml `enabled: false` | handler returns `{ ok: true, status: "disabled" }`, no Anthropic POST, sentry-heartbeat status `ok` |
| TS2 | promotion-config.yml `enabled: true` (unquoted YAML) | extractor coerces to bool `true`; handler proceeds |
| TS3 | promotion-config.yml `enabled: "true"` (quoted YAML) | extractor coerces to bool `true`; handler proceeds (gray-matter trap probe) |
| TS4 | dedup gate: open self-healing/auto issue from 3 days ago | handler returns `{ ok: true, status: "deduped" }` |
| TS5 | dedup gate: no recent issues | handler proceeds |
| TS6 | week-cap: 2 open self-healing/auto PRs | handler returns `{ ok: true, status: "week-cap-reached" }` |
| TS7 | week-cap: 1 open self-healing/auto PR | handler proceeds with REMAINING=1, hard-slices clusters to 1 |
| TS8 | PII pre-pass: corpus contains `jean@example.test` | the file is excluded; handler logs `pii-excluded` breadcrumb (NOT the matched line content) |
| TS9 | PII pre-pass: regex byte-equality | TS_PII_REGEX.source === bash regex string (extracted at test setup via `awk` from compound-promote.sh) |
| TS10 | Retired-rule pre-pass: learning path in retired-rule breadcrumb | file excluded; `retired-excluded` breadcrumb |
| TS11 | Anthropic body shape | model = "claude-sonnet-4-6", max_tokens = 16384, messages[0].role = "user", content includes the prompt + JSON corpus |
| TS12 | Anthropic response stop_reason = "max_tokens" | handler returns `{ ok: true, status: "anthropic-truncated" }` |
| TS13 | Anthropic response malformed (not JSON array) | handler returns `{ ok: false }` with sentry breadcrumb |
| TS14 | Cluster target_path = `apps/web-platform/server/foo.ts` | refused; breadcrumb `target-path-refused` |
| TS15 | Cluster diff exceeds 16384 bytes | refused; breadcrumb |
| TS16 | Cluster diff touches `apps/web-platform/server/foo.ts` (allowlisted target_path but bad +++ b/path) | refused |
| TS17 | Cluster branch name fails shape regex | refused |
| TS18 | Cluster diff valid, applies cleanly, post-apply byte cap respected | PR opened, audit row appended, 7 synthetic checks posted |
| TS19 | Cluster post-apply byte cap exceeded (AGENTS.md + AGENTS.core.md > 18000) | apply reverted, no PR opened, breadcrumb |
| TS20 | Cluster diff removes `[id: hr-foo]` line from AGENTS.core.md | refused (FR10); breadcrumb `agents-core-hr-rule-edit-refused` |
| TS21 | Cluster target_path matches plugins/soleur/skills/foo/SKILL.md AND open PR touches that path | comment posted on existing PR; no new branch (FR11) |
| TS22 | Installation token redaction: error message includes token | redacted before reaching logger / Sentry |
| TS23 | Per-cluster commit trailer matches verbatim shape | TS18 sub-assertion |
| TS24 | Synthetic checks count = 7 per PR, names match the verbatim list | TS18 sub-assertion |
| TS25 | PR body contains "human review required" anchor | TS18 sub-assertion |
| TS26 | Empty corpus after PII + retired pre-pass | handler returns `{ ok: true, status: "empty-corpus" }` |
| TS27 | Wall-clock budget exceeded (synthesized via mock fetch hang) | handler returns `{ ok: false }` with sentry breadcrumb `wall-clock-exceeded` |
| TS28 | Sentry heartbeat: domain/projectId/publicKey unset | handler logs `Sentry env unset — skipping heartbeat` and continues |
| TS29 | Sentry heartbeat: malformed env | handler logs `Sentry env malformed — skipping heartbeat` |

## Risks & Mitigations

1. **Risk: regex drift between shell and TS.** A future shell-script edit to
   the PII regex would not be reflected in the TS port; the shell driver is
   retained for hand-testing per Phase 3.5. **Mitigation:** AC8 unit test
   reads the shell regex at test setup via `awk`/`grep` and asserts byte
   equality against the TS regex string. Any future edit to either side that
   breaks parity fails CI.

2. **Risk: gray-matter YAML 1.1 trap on the config file.** `enabled: true`
   without quotes is a YAML boolean (gray-matter returns `data.enabled ===
   true`), but `enabled: yes` / `enabled: 1` would also coerce. The shell
   driver's awk extractor is forgiving in different ways. **Mitigation:** AC10
   probe test enumerates `true | "true" | yes | 1 | TRUE | "false"` and locks
   the contract. Reuse `coerceFrontmatterDate`-style coercion if needed.

3. **Risk: per-cluster PR open in a loop racing with concurrent
   manual-trigger event.** Two clusters could be opened with the same
   branch name on simultaneous fires. **Mitigation:** `concurrency: [{ scope:
   "fn", limit: 1 }]` enforces single-fire (Inngest precedent). Plus the
   branch-name shape includes the cluster hash (collision-resistant).

4. **Risk: ephemeral-workspace clone leaks the installation token.**
   **Mitigation:** PR-7 `buildAuthenticatedCloneUrl` + `redactToken` ported
   verbatim; AC13 unit test asserts no log emission carries the sentinel.

5. **Risk: Anthropic API model drift (claude-sonnet-4-6 deprecated).**
   **Mitigation:** AC9 locks the model string; on deprecation, this AC will
   flag the upgrade as a deliberate change, not an accident.

6. **Risk: Octokit's `repos.createCheckRun` shape changes the synthetic-check
   semantics.** **Mitigation:** version-pin `@octokit/*` (already in
   package.json); AC18 locks the call shape.

7. **Risk: the dedup gate (FR3) misses because the new label was never
   created.** **Mitigation:** Research-reconciliation flagged this; using
   `self-healing/auto` (which exists) instead of a new `compound-promote`
   label.

8. **Risk: Inngest function ID collision.** The function id
   `"cron-compound-promote"` must be unique across the substrate. Verified
   by reading the existing route.ts function list — no collision.

9. **Risk: Sentry monitor slug collision.** The slug
   `scheduled-compound-promote` must be unique in the Sentry org. Verified by
   reading `cron-monitors.tf` — no existing resource of that name.

10. **Risk: the 7-synthetic-checks list drifts (new required check added to
    the ruleset).** **Mitigation:** the GHA workflow's check list was the
    source of truth; the PR-11 handler copies the SAME list. If the ruleset
    changes, both the GHA-era PRs and Inngest-era PRs would need the new
    check; this PR does not change that dynamic.

## Sharp Edges

- **Stale ADR-021 reference in `scripts/compound-promote.sh:15`.** The
  comment says "see ADR-021"; the actual ADR is at
  `knowledge-base/engineering/architecture/decisions/ADR-027-stateless-self-modifying-cron.md`.
  Out of scope for PR-11 (no edits to the script's logic). File as
  doc-debt follow-up in Phase 6 if substrate-extraction follow-up issue
  has bandwidth.
- **`scripts/compound-promote.sh` retained on disk** — the runtime contract
  is the Inngest handler; the script is operator-local hand-testing only.
  Banner comment in Phase 3.5 enforces this.
- **PR body literal `human review required`** is byte-anchored by AC16. Any
  future refactor that paraphrases it ("manual review required",
  "reviewer-required", etc.) silently fails AC16.
- **`self-healing/auto` label vs. brief-suggested `compound-promote` label.**
  Brief flagged a `compound-promote` label; that label does NOT exist. The
  plan uses `self-healing/auto` (which exists and is semantically equivalent).
  If a future plan wants a separate `compound-promote` label, it's a deliberate
  taxonomy choice — not in scope here.
- **A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  deepen-plan Phase 4.6. Fill it before requesting deepen-plan or `/work`.**
- **Substrate extraction is deferred.** 7 claude-eval handlers duplicate
  ~165 LoC each; the issue is filed in Phase 6 but NOT done here.

## Files to Edit

- `apps/web-platform/app/api/inngest/route.ts` (import + array entry)
- `apps/web-platform/infra/sentry/cron-monitors.tf` (new resource block)
- `.github/workflows/apply-sentry-infra.yml` (append `-target=`)
- `scripts/compound-promote.sh` (banner comment, no logic change)
- `scripts/compound-promote.test.sh` (banner comment)
- `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` (Inngest runtime contract)

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` (~500 LoC)
- `apps/web-platform/test/server/inngest/cron-compound-promote.test.ts`
- `apps/web-platform/test/server/inngest/cron-compound-promote-graymatter.test.ts`

## Files to Delete

- `.github/workflows/scheduled-compound-promote.yml` (TR9 I-13 hygiene; same commit)

## References

- Brief: user-provided ARGUMENTS block (see one-shot pipeline invocation)
- Umbrella: `#3948` (TR9 — agent-loop crons → Inngest)
- Compound-promote v1 plan: `knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md`
- Compound-promote v1 PR: `#2720`
- Compound-promote runbook: `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`
- ADR-027 (stateless self-modifying cron): `knowledge-base/engineering/architecture/decisions/ADR-027-stateless-self-modifying-cron.md`
- ADR-033 (Inngest cron via child_process spawn): `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`
- Reference handler (pure-TS): `apps/web-platform/server/inngest/functions/cron-strategy-review.ts` (TR9 PR-6, closes `#4416`)
- Reference handler (claude-eval): `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` (TR9 PR-7, closes `#4425`)
- gray-matter trap precedent: `apps/web-platform/test/server/cron-strategy-review-graymatter.test.ts` + `knowledge-base/project/learnings/2026-05-25-tr9-pr6-gray-matter-yaml11-date-coercion-trap.md`
- BYOK guard: `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts`
- Sentry cron monitors: `apps/web-platform/infra/sentry/cron-monitors.tf`
- Sentry auto-apply: `.github/workflows/apply-sentry-infra.yml`
- Inngest serve route: `apps/web-platform/app/api/inngest/route.ts`
