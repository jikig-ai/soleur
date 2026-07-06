---
title: "fix(security): secret-scan RED on main — allowlist two synthesized false positives (#6112)"
type: fix
issue: 6112
branch: feat-one-shot-secret-scan-gitleaks-6112
lane: single-domain
brand_survival_threshold: aggregate pattern
created: 2026-07-06
---

# fix(security): secret-scan (gitleaks full-tree) RED on main — allowlist two synthesized false positives 🐛

Closes #6112 (via `Ref #6112` — see Sharp Edges on close semantics).

## Enhancement Summary

**Deepened on:** 2026-07-06
**Sections enhanced:** Observability (5-field schema), Research Insights (precedent-diff + verify-the-negative evidence).
**Passes run:** deepen gates 4.4 (precedent-diff), 4.6 (User-Brand Impact — PASS), 4.7 (Observability schema — reformatted to pass), 4.8 (PAT-shaped — PASS, none), 4.9 (UI-wireframe — PASS, no UI); verify-the-negative on all load-bearing negative claims.

### Key Improvements
1. **Verify-the-negative on "hash-only" claim (entry #1):** `git show f17f7a02:.claude/rule-body-hashes.json` confirms the file is `{"schema":1,"hashes":{"<rule-id>":"<64-hex SHA-256>"}}`. Line 18 is literally `"hr-github-app-auth-not-pat": "87b13f93…db8"` — the `generic-api-key` regex fires on the `auth"` substring inside the rule-id key followed by its SHA-256. Provably a hash, never a credential. This validates the top-level all-rules home for entry #1 (robust if the regenerated manifest adds more `auth`/`token`/`secret`-substring rule-ids).
2. **Precedent-diff (gate 4.4):** the new `plugins/soleur/skills/.*/test/.*\.test\.sh$` top-level entry mirrors the existing `apps/web-platform/(?:infra|test)/.*\.test\.(?:sh|ts)$` entry (`.gitleaks.toml:81`) — same class (integration test-runners crafting synthesized token corpora), same all-rules scope, same 3 compensating controls. Not a novel pattern.
3. **Confirmed the double-premise correction** (Sentry-DSN false; secret-scan-not-required false) against live gitleaks JSON + live ruleset API — see Research Reconciliation.

### New Considerations Discovered
- The irony worth noting in the PR body: the specific value that trips the scanner is the SHA-256 hash of the `hr-github-app-auth-not-pat` rule body — a hash of a *rule about not committing secrets*, not a secret.

## Overview

The `secret-scan` workflow's **`push:main` full-history** job (`./gitleaks git --redact --no-banner --exit-code 1`, `.github/workflows/secret-scan.yml:131-135`) is RED on `main`, failing on every push since `560168055` (2026-07-06 14:45Z). A local `gitleaks git --redact --no-banner` run in this worktree reproduces the failure and pins the exact findings.

**Both findings are false positives — synthesized/generated content, NOT real credentials. No rotation, no history rewrite.** The fix is two scoped `.gitleaks.toml` allowlist additions plus the `allowlist-diff` acknowledgement trailer.

### The two findings (verified locally, redacted)

| # | Rule | File | Introduced by | What it actually is |
|---|------|------|---------------|---------------------|
| 1 | `generic-api-key` (our same-id override, `.gitleaks.toml:319-328`) | `.claude/rule-body-hashes.json:18` | commit `f17f7a02` (#6103 "hard-rule body-weakening gate + baseline manifest") | A **machine-generated SHA-hash manifest**. The regex `(?i)(...|auth|...)[\s'"]*[:=][\s'"]*([A-Za-z0-9_\-]{16,})` fires on a hash value under an `"auth"`-shaped key. Structurally hash-only; never credential-bearing. The file is **absent from HEAD** (relocated/gitignored after #6103) — this is a **history-only** finding the full-tree scan surfaces. |
| 2 | `stripe-access-token` (**default-pack**, no override in our toml) | `plugins/soleur/skills/incident/test/redact-sentinel.test.sh:519` | commits `be90914d`/`a41accaa` (#6045 redaction-coverage bundle) | A **synthesized redaction-test sentinel corpus** — deliberately secret-shaped strings the `/soleur:incident` redaction test must catch (`cq-test-fixtures-synthesized-only`). Line 519 no longer exists at HEAD (file is 306 lines now) — also effectively history-only. |

Local full-history scan reports **3** hits (findings #1 + #2 once per each of the two #6045 branch-tip commits reachable in this shared-object-DB worktree); CI on `main`'s first-parent history reports **2** (#6045 squash-landed once). The path-based allowlist is **commit-independent**, so it covers all occurrences regardless of the 2-vs-3 count.

## Research Reconciliation — Issue Premise vs. Codebase Reality

The issue (#6112, title *"secret-scan RED on main — 2 leaks from #6092 baked-DSN"*) carries **two false premises**, both refuted by direct investigation. Building the fix on either would target the wrong artifact.

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| The 2 leaks are the **baked Sentry client DSN** from #6092 (`560168055`). | The gitleaks JSON report contains **zero** findings in any infra/Sentry file. A client DSN (`https://<key>@…ingest.sentry.io/…`) matches **no** rule in the pack (our `sentry-auth-token` rule only matches `sntrys_`/`sntryu_` prefixes). The real findings are #6103's manifest + #6045's test sentinel. | Fix targets `.claude/rule-body-hashes.json` + `redact-sentinel.test.sh`, **not** any Sentry/infra file. |
| #6092 (`560168055`) **introduced** the leak (it is the first RED push). | `560168055` is the first push that **ran** the scan after #6103 (`f17f7a02`) and #6045 (`be90914d`/`a41accaa`) merged into history (commit dates 14:14–14:27Z, just before 560168055's 14:45Z push). Red-**surfacing** ≠ red-**introducing**. | Diagnose from the gitleaks report, not the push-event bracket. |
| secret-scan **is not a required status check**, so auto-merge did not block. | The **`gitleaks scan`** context **IS** a live required check on the CI Required ruleset (id 14145388; `infra/github/ruleset-ci-required.tf` Tier-1). The RED job is the **`push:main` full-tree scan**, which runs **post-merge** and is **structurally non-gateable** (a push-triggered job cannot block the merge that triggers it). | Action #4 ("promote to required") is largely moot — reframed in Phase 3 as an accurate, optional hardening note, not a ruleset edit. |

## User-Brand Impact

**If this lands broken, the user experiences:** `secret-scan` stays RED on every push to `main`, so the repo's secret-leak gate is dark — a *real* future credential could merge to a public repo unnoticed while the noise-floor failure is ignored. (The immediate blast radius is the operator/maintainer, not an end user of the product.)

**If this leaks (the allowlist is drawn too broad), the exposure vector is:** a genuinely-leaked secret in a skill test-runner `.sh` file or the `.claude/` manifest path would be masked by the new allowlist entry. Mitigated by three independent compensating controls that still fire on these paths: (1) `lint-fixture-content.mjs` (real-email / prod-UUID / project-ref scanner), (2) GitHub server-side push protection (Doppler/AWS/Stripe/GitHub-PAT shapes, ignores our allowlist), (3) CODEOWNERS on `.gitleaks.toml` (2nd-reviewer approval). The two allowlisted paths are provably synthetic: `.claude/rule-body-hashes.json` is SHA-hash-only by construction; `*/test/*.test.sh` runners craft synthesized corpora by design (`cq-test-fixtures-synthesized-only`).

**Brand-survival threshold:** `aggregate pattern` — the risk is a *class* of masked secrets accumulating over time if the allowlist is over-broad, not a single-user data exposure. Reason for not `single-user incident`: no product-user data flows through these paths, and three compensating controls remain live. `threshold: aggregate pattern, reason: security-gate allowlist widening on provably-synthetic paths with 3 live compensating controls; no product-user data surface touched.`

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)
1. Confirm both findings reproduce: `gitleaks git --redact --no-banner --report-path /tmp/gl.json --exit-code 1` → 2 rule/file pairs (`generic-api-key`→`.claude/rule-body-hashes.json`, `stripe-access-token`→`redact-sentinel.test.sh`). (Already captured; re-confirm at work time.)
2. Confirm `stripe-access-token` is **not** a custom rule in `.gitleaks.toml` (`grep -c stripe-access-token .gitleaks.toml` → `0`) ⇒ only the **top-level `[allowlist]`** can suppress it (per-rule `[[rules.allowlists]]` blocks do not attach to default-pack rules; header lines 9-13).
3. Confirm `generic-api-key` **is** a same-id override with a per-rule allowlist (`.gitleaks.toml:319-328`).

### Phase 1 — Add the two allowlist entries to the top-level `[allowlist]` block (`.gitleaks.toml`)
Both findings are on paths that are **provably never credential-bearing**, so both land in the top-level `[allowlist]` (silences ALL rules for the path — the only mechanism that works for the default-pack `stripe-access-token`, and the more robust choice for the generated manifest). Append to the `paths = [ … ]` array (`.gitleaks.toml:80-90`), each with a dedicated comment:

```toml
  # Skill test-runner scripts (*.test.sh) craft synthesized secret-shaped corpora to
  # exercise redaction/scrubber gates — e.g. incident/test/redact-sentinel.test.sh's
  # Stripe/JWT/Supabase/PEM positive corpus (cq-test-fixtures-synthesized-only).
  # Mirrors the apps/web-platform/(infra|test)/*.test.(sh|ts) entry above; default-pack
  # rules (stripe-access-token) are ONLY suppressible from this top-level block. issue:#6112
  '''plugins/soleur/skills/.*/test/.*\.test\.sh$''',
  # Generated SHA-hash manifest from the #6103 body-weakening baseline gate. Structurally
  # hash-only (no credential can appear); the generic-api-key regex trips on a hash under
  # an "auth"-shaped key. History-only finding (file absent from HEAD). issue:#6112
  '''^\.claude/rule-body-hashes\.json$''',
```

**Scoping decisions (both deliberately narrow, alternatives noted):**
- Entry #2 uses the **`*/test/*.test.sh` class glob** (not just the single redact-sentinel file) to complete the documented intent at `.gitleaks.toml:59-63` and mirror the existing web-platform test-runner precedent. *Narrower alternative if reviewers prefer minimal scope:* `'''^plugins/soleur/skills/incident/test/redact-sentinel\.test\.sh$'''`.
- Entry #1 could alternatively go in the `generic-api-key` per-rule allowlist (`.gitleaks.toml:328`) to scope to the single firing rule. Chosen the top-level (all-rules) home because the file is structurally hash-only and this is future-proof against the manifest tripping other rules on regeneration; it also keeps both #6112 entries in one review location.

### Phase 2 — Acknowledge the allowlist widening + verify green
1. The commit that edits `.gitleaks.toml` **MUST** carry the trailer `Allowlist-Widened-By: <name>` (case-sensitive; `apps/web-platform/scripts/allowlist-diff.sh:41`) OR the PR must get the `secret-scan-allowlist-ack` label. The **trailer is preferred** (works headlessly; no label round-trip). Without it, the required `allowlist-diff (.gitleaks.toml paths surface)` check fails.
2. Re-run `gitleaks git --redact --no-banner --exit-code 1` locally → **exit 0, "no leaks found."** This is the load-bearing success gate (it replays exactly what `push:main` runs).
3. `.gitleaks.toml` is CODEOWNERS-protected — the PR needs owner approval before merge (normal review flow).

### Phase 3 — (Optional / advisory) durable-prevention note; NO ruleset edit
Action #4 from the issue ("promote secret-scan to a required check") is **already satisfied for the gateable path**: `gitleaks scan` (PR-diff) is a live required check (`infra/github/ruleset-ci-required.tf` Tier-1). The RED job (`push:main` full-tree) is **post-merge and cannot be a merge gate** by construction. Therefore **no `.tf` ruleset change is prescribed** — adding a post-merge context to `required_status_checks` is impossible.

Residual (small) gap for an **optional follow-up issue** (do not block this PR): *why did #6045/#6103's required PR-diff `gitleaks scan` pass while the full-tree scan fails on the same lines?* The PR-diff scan covers only `--no-merges BASE..HEAD`; the full-history scan covers all commit diffs. If a synthesized fixture can enter history via a diff-scan-clean path, the weekly `schedule` cron (`.github/workflows/secret-scan.yml:75-76`, already present) is the backstop that catches it retroactively — as it did here. File the investigation as a `type/security`-labelled issue if desired; it is out of scope for restoring green.

## Files to Edit
- `/.gitleaks.toml` — append 2 anchored path entries (+ comments) to the top-level `[allowlist].paths` array (Phase 1). **No other file.**

## Files to Create
- None. (Plan + tasks artifacts under `knowledge-base/` are lifecycle records, not feature files.)

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `grep -c 'rule-body-hashes' .gitleaks.toml` ≥ 1 **and** `grep -c 'skills/.\*/test/.\*\\.test\\.sh' .gitleaks.toml` ≥ 1 (both entries present; verify with the exact anchored regexes, not the loose grep).
- [ ] `gitleaks git --redact --no-banner --exit-code 1` exits **0** with "no leaks found" (run in this worktree after the edit — replays the `push:main` command verbatim).
- [ ] The `.gitleaks.toml`-editing commit carries an `Allowlist-Widened-By: <name>` trailer: `git log -1 --format='%(trailers:key=Allowlist-Widened-By,valueonly)' | grep -q .` returns success.
- [ ] Required PR checks green: `gitleaks scan`, `lint fixture content`, `allowlist-diff (.gitleaks.toml paths surface)`, `rename-guard (allowlist destinations)`, `waiver discipline (issue:#NNN trailer)`.
- [ ] PR body uses `Ref #6112` (not `Closes`) — see Post-merge close step.
- [ ] No file other than `.gitleaks.toml` is modified in the fix commit (`git diff --name-only <base>..HEAD` = `.gitleaks.toml` + `knowledge-base/**` artifacts only).

### Post-merge (operator/automated)
- [ ] After merge, the `push:main` `secret-scan / gitleaks scan` run is **green** (verify: `gh run list --workflow=secret-scan.yml --branch=main --limit 1 --json conclusion` → `success`). Automatable via `gh` — `/soleur:ship` post-merge verification should assert this.
- [ ] `gh issue close 6112` once the post-merge `push:main` scan is confirmed green (the fix is only "done" after main is green; `Ref` + explicit close avoids a premature auto-close).

## Observability
The change is a CI-config edit (`.gitleaks.toml`), not production runtime code — but the `secret-scan` workflow **is itself** the observability surface this PR restores from a stuck-RED (dark) state to actionable-green. Schema filled truthfully:

```yaml
liveness_signal:
  what: secret-scan `gitleaks scan` (PR-diff, required) + full-tree scan (push:main) + weekly retroactive cron
  cadence: every PR, every push to main, weekly (Mon 06:00 UTC)
  alert_target: red required-check on PRs / red run on main in the GitHub Checks UI
  configured_in: .github/workflows/secret-scan.yml
error_reporting:
  destination: GitHub Actions run log + Checks API (red status); content redacted via --redact
  fail_loud: yes — `--exit-code 1` fails the job; the `gitleaks scan` required check blocks PR merge
failure_modes:
  - mode: real secret enters via a PR diff
    detection: required `gitleaks scan` PR-diff job (--no-merges BASE..HEAD)
    alert_route: red required check blocks the merge
  - mode: secret already in history the PR-diff scan did not cover
    detection: push:main full-tree scan + weekly schedule full-history cron
    alert_route: red run on main (THIS issue's class) — surfaced at /ship post-merge verification
  - mode: over-broad allowlist masks a genuine secret on the allowlisted paths
    detection: lint-fixture-content.mjs + GitHub server-side push protection (both ignore .gitleaks.toml)
    alert_route: separate red check / server-side push rejection
logs:
  where: GitHub Actions run logs for the secret-scan workflow (redacted)
  retention: GitHub default (~90 days)
discoverability_test:
  command: gh run list --workflow=secret-scan.yml --branch=main --limit 1 --json conclusion
  expected_output: conclusion == "success" once this fix merges to main
```

## Infrastructure (IaC)
No IaC change. The CI Required ruleset is Terraform-managed (`infra/github/ruleset-ci-required.tf`), but the `gitleaks scan` context is **already** a `required_check` there (Tier-1) — nothing to add. The failing `push:main` full-tree job is post-merge and non-gateable, so it cannot be added to `required_status_checks`. No server, secret, vendor, DNS, or runtime process is introduced.

## Domain Review

**Domains relevant:** none — single-domain engineering / CI-tooling config change.

No cross-domain implications (no product/UI surface, no legal/finance/marketing/ops/sales/support impact). Product/UX Gate: **NONE** — no UI-surface file in Files to Edit (`.gitleaks.toml` only); mechanical UI-surface override does not fire.

## Architecture Decision (ADR/C4)
No architectural decision. This follows the established false-positive allowlist pattern (top-level `[allowlist]` historical-triage precedent #3194; per-rule override precedent throughout `.gitleaks.toml`; `allowlist-diff` ack gate #3323). No new invariant, ownership boundary, substrate, or trust-boundary change. **No C4 impact:** the secret-scan gate is CI tooling, not modeled as a C4 actor/system/container/data-store — checked `model.c4`/`views.c4`/`spec.c4` conceptually: no external human actor, external system/vendor, container, or access relationship is added or changed by an allowlist edit.

## Risks & Mitigations
- **Allowlist too broad masks a real secret.** Mitigated: both paths provably synthetic; 3 live compensating controls (lint-fixture-content, GitHub push protection, CODEOWNERS). Narrower single-file alternative documented for entry #2 if review prefers.
- **`allowlist-diff` gate blocks the PR** if the ack trailer is forgotten. Mitigated: Phase 2 step 1 makes the `Allowlist-Widened-By:` trailer a hard step + a pre-merge AC.
- **Count drift (2 vs 3 findings)** between CI and local worktree. Immaterial: path allowlists are commit-independent; the success gate is `exit 0`, not a count.
- **Manifest regenerates and trips a *different* rule.** Low (hash-only content); the top-level all-rules entry #1 already covers any rule for that exact path, so no follow-up needed unless the manifest path changes.

## Sharp Edges
- **Use `Ref #6112`, not `Closes #6112`.** The fix is only complete once the **post-merge** `push:main` scan is green; `Closes` auto-closes at merge (before that verification). Close explicitly via `gh issue close 6112` after confirming green (extends `wg-use-closes-n-in-pr-body-not-title-to` for the verify-after-merge class).
- **Default-pack rules cannot be allowlisted per-rule in v8.24.2.** `stripe-access-token` has no same-id override in our toml, so its only suppression path is the top-level `[allowlist]`. Do not try to add a `[[rules.allowlists]]` under a non-existent `stripe-access-token` rule — it would be a no-op (or you'd have to add a full same-id override rule, which is heavier than the top-level path).
- **The issue title is diagnostically wrong** (blames #6092 baked-DSN). Do not "fix" any Sentry/infra file — the DSN matches no rule and produces no finding. The evidence is the `gitleaks git --report-path` JSON, not the push-event bracket.
- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails `deepen-plan` Phase 4.6. This one is filled (threshold `aggregate pattern` with reason).

## Alternative Approaches Considered
| Approach | Why not chosen |
|---|---|
| Rotate the "secret" + purge history (issue action #3) | N/A — neither finding is a real credential (SHA-hash manifest / synthesized test sentinel). History rewrite is heavy and unjustified for false positives. |
| `git filter-repo` to strip the historical lines | Rejected — destructive history rewrite for provably-synthetic content; allowlist is the canonical, reviewable, reversible fix (matches #3194 precedent). |
| Per-rule `generic-api-key` allowlist for entry #1 | Viable and narrower (single rule) but semantically mismatched (the per-rule list is described as "synthesized fixtures/test files/docs", not a generated manifest) and not future-proof if the manifest trips other rules. Kept as documented alternative. |
| `commitAllowlist` (SHA-scoped) | Fragile: SHAs are already on `main`; a rebase/re-tag would break it, and it doesn't express *why* the content is safe. Path-based is stable and self-documenting. |
| Edit `infra/github/ruleset-ci-required.tf` to make the full-tree scan required | Impossible — `push:main` full-tree scan is post-merge; a push-triggered context cannot gate its own triggering merge. |
