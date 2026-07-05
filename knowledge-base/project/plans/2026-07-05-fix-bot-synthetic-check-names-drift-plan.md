---
title: "fix(ci): reconcile bot synthetic check-runs with the CI Required ruleset (drift-proof the whole chain)"
date: 2026-07-05
issue: 6049
type: fix
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
adr: knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md (amend)
related:
  - ADR-032-github-branch-protection-as-iac.md
  - ADR-054-safe-commit-and-pr-sole-write-path-for-bot-cron-prs.md
---

# fix(ci): bot synthetic check-runs are stale vs the CI Required ruleset — drift-proof the chain 🐛

## Overview

`GITHUB_TOKEN`-created bot PRs (the weekly `rule-metrics-aggregate` and `weakness-miner`
crons) never trigger `pull_request` CI, so `.github/actions/bot-pr-with-synthetic-checks`
posts **synthetic** check-runs (Checks API, integration_id 15368) to satisfy `main`'s
required-check rulesets. Its `CHECK_NAMES` list has drifted: it synthesizes **6** checks
(`test dependency-review e2e "skill-security-scan PR gate" enforce tenant-integration-required`,
plus `cla-check`/`cla-evidence`) but the live **CI Required** ruleset (#14145388) requires
**17** contexts. Result: every synthetic-check bot PR sits at `mergeState=BLOCKED` forever
(zero `ci/`-prefixed bot PRs have ever auto-merged; #6048 was admin-merged as the documented
interim, now `MERGED`).

The root cause is a **three-layer drift**, all of which must reconcile to the live truth
and then be locked so they cannot silently re-drift:

| Layer | File(s) | State on `main` | Live truth |
|---|---|---|---|
| **IaC** (what the ruleset requires) | `infra/github/ruleset-ci-required.tf` + `scripts/ci-required-ruleset-canonical-required-status-checks.json` | 16 contexts | 17 — **`adr-ordinals` is required live but tracked in neither** |
| **Synthetic SSOT** (what the bot posts) | `scripts/required-checks.txt` | 8 names | canonical **filtered to `integration_id == 15368`** + CLA (invariant below) |
| **Action** (posting site) | `.github/actions/bot-pr-with-synthetic-checks/action.yml:168` | 6 hardcoded + 2 CLA | must derive from the SSOT |

Two facts make this more than a list-append:

1. **`adr-ordinals` IaC drift.** The live ruleset requires `adr-ordinals`, but the Terraform
   root and the canonical JSON omit it. The next `apply-github-infra.yml` run would compute
   `adr-ordinals` as unmanaged and **remove** it from the live ruleset — silently un-gating
   ADR-ordinal collisions. The bot also cannot merge past `adr-ordinals` today. Reconciling
   it into the IaC is therefore intrinsic to this fix (no-op `terraform apply`: live already
   has it), and the `.tf`↔canonical lockstep gate (T-rsc-9 in
   `tests/scripts/test-audit-ruleset-bypass.sh`) forces both to move together.

2. **The current stall is accidentally protective.** Because the bot never synthesizes
   `gitleaks scan`, a bot digest carrying a secret-shaped string **stalls** instead of merging.
   The `weakness-miner` clusters *learnings* files — which this repo's own Sharp Edges document
   as frequently containing synthetic-token shapes. Naïvely fabricating a green `gitleaks scan`
   would convert "secret-bearing digest stalls" into "fabricated-green merges." Per the
   defense-relaxation rule, completing the synthetic set **must name a new ceiling** for the
   content-safety gate it fabricates. See "Secret-safety decision" below and Phase 4.

This is **not** a regression of #6037 — `weakness-miner` faithfully cloned the
`rule-metrics-aggregate` pattern; it is the second consumer to hit a pre-existing gap.

The architecture already intends the bot to synthesize **every** integration_id-15368 required
check (see `ruleset-ci-required.tf` `tenant-integration-required` comment: *"bot PRs satisfy it
via the synthetic check-run posted by bot-pr-with-synthetic-checks (CHECK_NAMES) — same as the
other 15368 checks"*); `CodeQL` is the sole GHAS-native (57789) exception, satisfied by its
`neutral` conclusion (documented in `required-checks.txt` and `codeql-bot-coverage.md`). The
issue's "do not blanket-synthesize" caution predates awareness of this ADR-032 intent — so the
fix is to **complete the set faithfully, derive it from a single SSOT, add a real content-scan
ceiling, and make the whole chain un-driftable**, not to invent a bypass actor or aggregator
(both would deviate from the established synthesize-everything design; see Alternatives).

**Secret-safety decision (the plan's central risk decision — routed to the security lens + advisor + CPO):**
Completing the synthetic set relaxes the accidental stall-defense on the fabricated
`gitleaks scan` green. Two ceilings were considered:

- **Tier 2 (recommended, CORE):** the action runs the **real** `gitleaks` (same pinned
  v8.24.2 + SHA as `secret-scan.yml`) over its own staged diff before posting; a hit fails
  loud (no PR, no synthetic). This genuinely *earns* the one content gate that applies to
  markdown. Cost: a gitleaks-version-drift surface (guarded — see Phase 4 + Sharp Edges).
- **Tier 1 (severable fallback):** assert `add-paths` stay inside a markdown/`knowledge-base`
  safe-surface allowlist and rely on GitHub server-side push-protection (already blocks
  provider-shaped tokens at the bot's `git push`) as the interim secret backstop. Weaker on
  custom `.gitleaks.toml` rules + high-entropy strings.

At `single-user incident` threshold the honest default is Tier 2 (it reproduces the gate being
fabricated). deepen-plan's `security-sentinel` and the Phase-4.5 advisor confirm or downgrade.

## Research Reconciliation — Spec vs. Codebase

No spec.md exists for this branch (direct one-shot → plan path). The issue body was validated
against the live repo + GitHub API; divergences found:

| Issue / prior claim | Reality (verified) | Plan response |
|---|---|---|
| "bypass_actors = **none**" on CI Required | Live has `OrganizationAdmin` + `RepositoryRole 5` (both `pull_request` mode); the **bot** is not a bypass actor. Admin-merge works because of these. | Wording is imprecise; the substance (bot cannot bypass) holds. No change to bypass actors. |
| Missing checks are "conditional on changed paths … when their path conditions apply" | All 16 IaC contexts are **always-run gate jobs** (verified: no workflow-level `paths:` filter; ADR-032 contract). Bot PRs trigger **none** of them, so **all** must be synthesized. | Synthesize the full 15368 set; `CodeQL` via native neutral. |
| Add a drift test "asserting CHECK_NAMES ⊇ required-check set" | An SSOT + audit chain already exists: `canonical-required-status-checks.json` (↔ live via the Inngest `cron-ruleset-bypass-audit`), `required-checks.txt`, and `lint-bot-synthetic-completeness.sh`. **But** the lint **exempts composite-action consumers** and never scans `.github/actions/**`, so the action's `CHECK_NAMES` is asserted by **nothing**; and `required-checks.txt` itself is stale. | Add a **file-vs-file** drift test (`required-checks.txt` CI-subset ≡ canonical − `CodeQL`), make the action **read** the SSOT (kill the hardcode), and test-back the composite-action coverage. |
| (new finding) `adr-ordinals` | **Live-required (17th) but absent from `.tf` AND canonical JSON.** Latent IaC-revert bug. | Reconcile into `.tf` + canonical (no-op apply; T-rsc-9 lockstep). |
| (new finding) `scripts/post-bot-statuses.sh` | Legacy Statuses-API path, 2 hardcoded contexts, **zero callers**. | Out of scope; note as dead-code cleanup candidate. Do not modify. |
| (new finding) `cla-evidence` | Synthesized by the action but the **CLA Required** ruleset (#13304872) requires only `cla-check`. | Keep (harmless belt-and-suspenders); the drift test scopes CLA to `cla-check`. |

## User-Brand Impact

**If this lands broken, the user experiences:** weekly self-improvement digests
(`rule-metrics.json`, `weakness-digest.md`) never reach the operator — the compounding loop the
crons exist to drive silently stalls; no user-facing product artifact, but the operator's
comprehension/health surface degrades.

**If this leaks, the user's data is exposed via:** a `weakness-miner` digest that clusters a
learnings file containing a real secret-shaped string, merged to `main` under a **fabricated**
`gitleaks scan` green, then surfaced in the public repo / an Artifact — a secret-exposure
single-user incident. This is the exact vector Phase 4's real-gitleaks ceiling closes.

**Brand-survival threshold:** single-user incident.

(Carried from the subsystem's established threshold — `audit-ruleset-bypass.sh` header, #2719/#3542 R15: a
weakened merge gate on this surface = an installable-skill/secret code-execution class incident.)

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)
- Re-confirm live CI Required contexts (17) via `gh api repos/:owner/:repo/rulesets/14145388`
  and that `origin/main:infra/github/ruleset-ci-required.tf` lacks `adr-ordinals`.
- Read `tests/scripts/test-audit-ruleset-bypass.sh` T-rsc-9 to confirm the `.tf`↔canonical
  lockstep assertion shape (any `.tf` context edit must be mirrored in the canonical JSON).
- Read `.github/workflows/secret-scan.yml:82-104` to lift the exact `GITLEAKS_VERSION`/SHA256
  pin + download+verify form the action will reuse.
- Confirm `CODEOWNERS` gates `infra/github/**` to @deruelle (this PR needs code-owner approval;
  legitimate for a ruleset change — a pre-merge review, not a punted operator action).

### Phase 1 — IaC reconciliation (`adr-ordinals`)
Files to edit: `infra/github/ruleset-ci-required.tf`, `scripts/ci-required-ruleset-canonical-required-status-checks.json`
- Add a `required_check { context = "adr-ordinals"; integration_id = var.actions_integration_id }`
  block (Tier-mirroring the existing entries) to the `.tf`.
- Add `{ "context": "adr-ordinals", "integration_id": 15368 }` to the canonical JSON.
- Verify: `terraform -chdir=infra/github validate`; note that `apply-github-infra.yml` will
  compute a **no-op** plan against live (live already requires it) — this only makes the IaC honest.

### Phase 2 — Complete the synthetic SSOT
File to edit: `scripts/required-checks.txt`
- Add the 10 missing synthesizable contexts, grouped/commented like the existing entries:
  `gitleaks scan`, `lint fixture content`, `allowlist-diff (.gitleaks.toml paths surface)`,
  `rename-guard (allowlist destinations)`, `waiver discipline (issue:#NNN trailer)`,
  `Bash fixture tests for guard scripts`, `lockfile-sync`, `service-role-allowlist-gate`,
  `tc-document-sha-guard`, `adr-ordinals`.
- Preserve the `CodeQL` intentional-omission comment block verbatim.
- **Invariant (per advisor):** the synthesizable set is not "canonical minus a `CodeQL` literal"
  — it is **canonical entries whose `integration_id == 15368`** (the bot, app 15368, can only
  synthesize checks pinned to itself; GHAS-pinned `57789` checks it structurally cannot post).
  `CodeQL` is today the sole `57789` entry, so the set is those 16 contexts. Encoding the
  `15368` filter (not the `CodeQL` literal) means a *future* second GHAS/non-15368 check is
  handled automatically instead of silently breaking the test or making the bot fabricate a
  check it cannot post.
- Result: file's CI-Required subset ≡ the `integration_id == 15368` contexts of the canonical
  JSON (currently 16), plus CLA `cla-check` (+ `cla-evidence`).

### Phase 3 — Action derives CHECK_NAMES from the SSOT (kill the hardcode)
File to edit: `.github/actions/bot-pr-with-synthetic-checks/action.yml`
- Replace the hardcoded `CHECK_NAMES=(...)` (line 168) with a read of `scripts/required-checks.txt`
  (repo is checked out in the consumer job), reusing the **same** comment-strip + multi-word +
  single-quote-strip parser as `lint-bot-synthetic-completeness.sh:42-57` (do NOT re-invent —
  `tr -d '[:space:]'` destroys `skill-security-scan PR gate`; see learning
  `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`).
- Post one Checks-API `check-run` per parsed name. Special-case `cla-check`/`cla-evidence`
  output titles/summaries inside the loop (a small `case`), so the two custom outputs are
  preserved from **one** source with no separate hardcoded blocks and no double-post.
- Update `.github/actions/bot-pr-with-synthetic-checks/CHANGELOG.md` (v3: derives from SSOT + real gitleaks preflight).

### Phase 4 — Secret-safety ceiling (Tier 2, CORE — the named ceiling for the relaxation)
File to edit: `.github/actions/bot-pr-with-synthetic-checks/action.yml`
- Before posting synthetics, run the **real** gitleaks over the action's own staged/committed
  diff, reusing `secret-scan.yml`'s pinned `GITLEAKS_VERSION`/SHA256 (single pinned source) and
  the repo `.gitleaks.toml`. On any finding: fail loud (`--redact`), do **not** create the PR,
  do **not** post synthetics.
- Assert every `add-paths` entry is within a safe-surface allowlist (markdown under
  `knowledge-base/`); a path outside it fails loud (a future caller must not get fabricated
  greens for path-scoped gates that would actually apply).
- **Eliminate the version-drift surface at the source (advisor's third option, preferred):**
  gitleaks `8.24.2`+SHA is **already** pinned in **two** sites (`secret-scan.yml:82-84` and
  `ci.yml` `test-scripts` job `env`, with a "bump both files together" comment). Rather than add
  a **third** independent pin, extract the pinned install (version+SHA+download+verify) to a
  **single shared source** both the required-check workflow and the bot action consume — either a
  small `.github/actions/gitleaks-install` composite or a sourced `scripts/gitleaks-version.env` —
  so the earned green is **provably the same gate** and no assert-equal test is needed. **Blast-radius
  guard:** extract only the INSTALL step; do **not** rename or restructure `secret-scan.yml`'s
  required-check **jobs** (the ADR-032 job-name contract un-requires a check on rename). If the
  shared extraction is judged too invasive at /work time, fall back to a third pin site + a
  cross-site pin-parity assertion in the Phase-5 test. The `test-scripts` shard already installs
  pinned gitleaks, so the tooling exists regardless.
- *(If security-sentinel/advisor downgrade to Tier 1: replace the real-gitleaks step with the
  safe-surface allowlist + a `push-protection is the interim secret backstop` note; the allowlist
  guard stays either way.)*

### Phase 5 — Drift-proof tests (make re-drift impossible)
Files to create/edit: `plugins/soleur/test/required-checks-canonical-parity.test.sh` (new),
`scripts/lint-bot-synthetic-completeness.sh` (extend), `plugins/soleur/test/lint-bot-synthetic-completeness.test.sh` (extend)
- **New parity test** (file-vs-file, deterministic, no API): assert the CI-Required subset of
  `required-checks.txt` **equals** the set of `context`s in `canonical-required-status-checks.json`
  **filtered to `integration_id == 15368`** (compute via `jq`, do NOT special-case the string
  `CodeQL` — future-proof per the Phase-2 invariant). Compare as sets (sorted), multi-word-safe,
  regex-escaped — assert **both** directions (⊆ and ⊇), not `| length` (see learning
  `2026-05-16-prose-contract-vs-executable-check-dimension-drift.md`).
- **Close the composite blind spot:** either extend `lint-bot-synthetic-completeness.sh` to also
  assert `.github/actions/bot-pr-with-synthetic-checks/action.yml` reads `required-checks.txt`
  (so the composite exemption is test-backed), OR rely on the fact that the action now reads the
  SSOT (coverage by construction) + the new parity test — document whichever is chosen. Add a
  regression case to the lint's test asserting the composite action is covered.
- Wire the new `.test.sh` into CI: sibling `plugins/soleur/test/*.test.sh` run via
  `scripts/test-all.sh` in the `ci.yml` `test-scripts` job (which already installs pinned
  gitleaks + likec4) — confirm `test-all.sh`'s glob picks up the new file at /work time.

### Phase 6 — ADR-032 amendment + verification
File to edit: `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md`
- Append an amendment (2026-07-05, #6049) documenting: the closed drift chain
  (`live ≡ canonical ≡ .tf`, `canonical − CodeQL ≡ required-checks.txt ≡ action CHECK_NAMES`),
  the `adr-ordinals` reconciliation, the real-gitleaks content-safety ceiling, and the
  composite-action coverage guarantee. **Amend** (not a new ADR) to avoid an ordinal collision.
- Run the C4 completeness read result (see Architecture Decision section): no C4 impact.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `infra/github/ruleset-ci-required.tf` contains an `adr-ordinals` `required_check`; the
      canonical JSON contains a matching `{context: "adr-ordinals", integration_id: 15368}`;
      `test-audit-ruleset-bypass.sh` T-rsc-9 (`.tf`↔canonical lockstep) passes.
- [ ] `scripts/required-checks.txt` CI-Required subset, as a set, equals the
      `canonical-required-status-checks.json` contexts with `integration_id == 15368` (computed
      via `jq`, NOT a `CodeQL` string literal), verified by the new parity test asserting BOTH ⊆ and ⊇.
- [ ] `action.yml` no longer hardcodes `CHECK_NAMES`; it parses `scripts/required-checks.txt`
      with the multi-word-safe parser and posts one 15368 check-run per name; `cla-check`/
      `cla-evidence` custom outputs preserved; no name double-posted.
- [ ] Phase-4 ceiling present: real gitleaks (pinned == `secret-scan.yml`) runs over the diff and
      fails loud on a finding; `add-paths` safe-surface allowlist enforced. (Or Tier-1 fallback
      with push-protection note, if downgraded — recorded in the plan + ADR.)
- [ ] New `plugins/soleur/test/required-checks-canonical-parity.test.sh` passes and is wired into CI.
- [ ] `lint-bot-synthetic-completeness.sh` + its `.test.sh` updated so composite-action coverage
      is asserted (no silent composite blind spot).
- [ ] `terraform -chdir=infra/github validate` passes; the `.tf` change is a **no-op** plan
      against live (documented, not applied by the author).
- [ ] ADR-032 amended; C4 read performed with "no impact" enumeration cited.
- [ ] `bash scripts/lint-bot-synthetic-completeness.sh` and the full `plugins/soleur/test/*.test.sh`
      suite green; typecheck N/A (no TS in `apps/web-platform` touched — confirm no
      `apps/web-platform` files changed).
- [ ] PR body uses `Closes #6049`. PR is code-owner-gated on `infra/github/**` (@deruelle);
      this is an expected pre-merge review approval, **not** a post-merge operator action.

### Post-merge (operator / automated)
- [ ] `apply-github-infra.yml` fires on merge and applies a **no-op** ruleset plan (verify the
      run shows 0 changes; the daily `cron-ruleset-bypass-audit` goes/stays green now that
      canonical ≡ live incl. `adr-ordinals`). Automatable — verify via the Actions run, not SSH.
- [ ] Next scheduled `weakness-miner` / `rule-metrics-aggregate` bot PR reaches
      `mergeState=CLEAN` and auto-merges (or a `workflow_dispatch` run confirms it pre-emptively).

## Domain Review

**Domains relevant:** none

No cross-domain (business) implications detected — this is an infrastructure/CI-governance and
security-tooling change touching `scripts/`, `.github/`, `infra/github/`, tests, and an ADR. No
UI surface (no `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`), so the Product/UX Gate
does not apply (tier NONE). The substantive review lens is engineering/security, carried by the
`single-user incident` threshold: plan-review escalates to +architecture-strategist +spec-flow,
and deepen-plan runs the security-sentinel + data-integrity + architecture triad (the next
pipeline step). CPO sign-off is required by the threshold rule (frontmatter `requires_cpo_signoff`);
here it is an ack that the CI-governance security tradeoff (Tier 2 vs Tier 1) is acceptable —
the substantive gate is security-sentinel, not product.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- The only infrastructure change is the CI Required ruleset, routed entirely through
     infra/github/ruleset-ci-required.tf (Terraform). No server provisioning, SSH, systemd,
     Doppler mutation, or dashboard step. "install" references are GitHub-Actions CI tool
     installs (gitleaks), not host provisioning. -->

## Infrastructure (IaC)

### Terraform changes
- `infra/github/ruleset-ci-required.tf`: +1 `required_check` (`adr-ordinals`, `integration_id = var.actions_integration_id`).
- Provider: `integrations/github ~> 6.10` (existing). No new provider, backend, or variable.
- Sensitive vars: none added (uses existing `var.gh_repo`, `var.actions_integration_id`).

### Apply path
- (c-adjacent) **no-op reconcile**: `apply-web-platform-infra`-analogue `apply-github-infra.yml`
  auto-applies on merge to `infra/github/**`. Because the live ruleset **already** requires
  `adr-ordinals`, `terraform plan` yields **0 changes** — the apply only aligns state/config
  with reality. Blast radius: nil (idempotent). Downtime: none.

### Distinctness / drift safeguards
- `.tf` ↔ canonical JSON lockstep enforced by T-rsc-9. `canonical ↔ live` enforced by the daily
  Inngest `cron-ruleset-bypass-audit`. This PR removes the current `canonical ≠ live` drift.
- No `lifecycle.ignore_changes` change. Bypass actors untouched (canonical bypass JSON unchanged).

### Vendor-tier reality check
- N/A — GitHub rulesets on an existing paid org; no free-tier resource-creation gate.

## Observability

```yaml
liveness_signal:
  what: "bot PR reaches mergeState=CLEAN and auto-merges within the cron window"
  cadence: "weekly (rule-metrics Sun 00:00 UTC; weakness-miner Sun 06:00 UTC)"
  alert_target: "cleanup-unmerged-bot-branches.yml (flags ci/* branches unmerged > threshold) + notify-ops-email on cron failure"
  configured_in: ".github/workflows/cleanup-unmerged-bot-branches.yml, weakness-miner.yml (failure email)"
error_reporting:
  destination: "GitHub Actions run failure + notify-ops-email; the action fails loud (no silent PR) on gitleaks hit or add-paths escape"
  fail_loud: true
failure_modes:
  - mode: "required-check set re-drifts (new ruleset context not synthesized)"
    detection: "required-checks-canonical-parity.test.sh fails in PR CI (file-vs-file, pre-merge)"
    alert_route: "CI red on the PR that adds the ruleset check without updating the SSOT"
  - mode: ".tf and canonical JSON diverge"
    detection: "T-rsc-9 in test-audit-ruleset-bypass.sh"
    alert_route: "CI red"
  - mode: "canonical vs live ruleset drift (e.g. adr-ordinals recurrence)"
    detection: "cron-ruleset-bypass-audit (Inngest, daily) required_status_checks comparison"
    alert_route: "ci/auth-broken issue + Sentry monitor scheduled-ruleset-bypass-audit"
  - mode: "bot digest carries a secret-shaped string"
    detection: "real gitleaks in the action (Phase 4) + GitHub server-side push-protection at git push"
    alert_route: "action fails loud; no PR; run failure email"
logs:
  where: "GitHub Actions run logs (consumer workflow job); Inngest run logs for the audit cron"
  retention: "GitHub Actions default (90d); Inngest per ADR-033"
discoverability_test:
  command: "gh run list --workflow=weakness-miner.yml --limit 1 --json conclusion && gh pr list --search 'head:ci/ is:merged' --limit 5"
  expected_output: "recent run success + at least one merged ci/ bot PR after this lands"
```

## Architecture Decision (ADR / C4)

This changes a CI **trust-boundary / governance** invariant (how bot PRs satisfy required
checks; a new content-safety ceiling), and reconciles an IaC drift — so the record is a
deliverable of this plan (Phase 6), not a follow-up.

### ADR
- **Amend ADR-032** (GitHub branch-protection as IaC): add the closed drift-chain contract, the
  `adr-ordinals` reconciliation, the SSOT-derived `CHECK_NAMES`, and the real-gitleaks ceiling.
  Amend (not new) — avoids an ordinal collision with in-flight PRs.

### C4 views
- **No C4 impact.** Completeness read performed against all three model files
  (`model.c4`, `views.c4`, `spec.c4`). Enumeration checked and found already-modeled or N/A:
  (a) external human actor — none new (the bot is `github-actions[bot]`, an internal CI identity,
  not a modeled person); (b) external system/vendor — `github = system "GitHub"` (`model.c4:214`,
  "Source control, CI/CD, …") and the `engine -> github "Git operations and CI"` edge
  (`model.c4:267`) already model this; the change is an internal mechanic of that existing edge
  and does not alter its description; (c) container/data-store — none touched; (d) actor↔surface
  access relationship — none (the ruleset governs merges, an internal CI mechanic under the
  existing GitHub system, not a product access relationship). No element description is falsified.

### Sequencing
- Single PR (the `adr-ordinals` IaC reconcile is entangled with the bot fix — the parity test
  cannot pass without it, and the bot cannot merge past `adr-ordinals` without it). No soak gate.

## Alternatives Considered

| Alternative | Why not (default = complete + drift-proof the synthetic set) |
|---|---|
| **(a) Scoped ruleset bypass actor for the bot** | Ruleset bypass actors are actor-scoped, **not** path/branch-scoped; a bot bypass would waive **all** checks on **all** bot PRs (strictly weaker than synthesizing) and fights the daily bypass-audit + canonical bypass JSON. Deviates from ADR-032's synthesize-everything design. |
| **(b) Path-conditional required set** | Rulesets have no native path-conditional required checks; the 16 gates are already always-run for humans. The bot problem is "triggers nothing," not "conditionally required." No lever here. |
| **(c) Single always-green aggregator required check** | Cross-workflow `needs:` is impossible; an aggregator would need an API-polling meta-job — high blast radius, and it still fabricates one green (same trust model, less legible). A bigger governance change than the drift it fixes. |
| **Tier-1-only secret safety (allowlist + push-protection)** | Severable fallback, documented in Phase 4; weaker than reproducing the `gitleaks scan` gate. Kept as the downgrade path if security-sentinel/advisor judge push-protection sufficient. |
| **Split adr-ordinals into its own PR** | Creates a merge-order dependency (parity test needs canonical to carry `adr-ordinals` first) for no gain; both must land and both need the @deruelle code-owner review anyway. |
| **Modify/retire `post-bot-statuses.sh`** | Legacy, zero callers — deferred as a separate dead-code cleanup (tracking issue) to keep this PR scoped. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails
  `deepen-plan` Phase 4.6 — this one is filled (threshold: single-user incident).
- **Multi-word check names:** the action's new parser MUST reuse `lint-bot-synthetic-completeness.sh`'s
  leading/trailing-only trim (never `tr -d '[:space:]'`) and regex-escape names before any grep;
  `skill-security-scan PR gate`, `allowlist-diff (.gitleaks.toml paths surface)`,
  `waiver discipline (issue:#NNN trailer)` all contain spaces and/or parens.
- **New gitleaks-version-drift surface:** the action's gitleaks pin must not diverge from
  `secret-scan.yml` (`GITLEAKS_VERSION=8.24.2` + SHA256) — source both from one file or add an
  equality assertion to the parity test. A silent divergence would scan with a different engine.
- **Set-equality, both directions:** the parity test must assert `required-checks.txt` CI-subset
  both ⊆ and ⊇ (canonical − CodeQL); a one-direction or `| length` check passes on a real drift.
- **`.tf`↔canonical lockstep:** editing `ruleset-ci-required.tf` without the matching canonical
  JSON entry (or vice-versa) fails T-rsc-9; move both in the same commit.
- **CODEOWNERS on `infra/github/**`:** this PR requires @deruelle approval and will **not**
  auto-merge — expected and correct for a branch-protection change (a review, not punted work).
- **Do not** re-run `update-ci-required-ruleset.sh`/`create-ci-required-ruleset.sh` to mutate the
  live ruleset — the ruleset is Terraform-managed (ADR-032); the reconcile goes through the `.tf`.
- **Async boundary (advisor):** the new file-vs-file parity test guarantees only
  `required-checks.txt` matches the canonical JSON. `canonical` matching `live` is a **daily
  async** guarantee (the Inngest `cron-ruleset-bypass-audit`) — which is exactly how
  `adr-ordinals` slipped (added to live, never to canonical/`.tf`). So an unsanctioned live
  ruleset change is caught next-day, not at PR time, and the bot stalls for up to 24h in that
  window. This is acceptable **only because** every sanctioned ruleset change flows through
  `infra/github/` (Terraform), keeping `live` and `canonical` equal by construction. The parity
  test does **not** close the live-drift vector; the Terraform-only mutation discipline does.

## Test Scenarios
1. Parity test: mutate `canonical-required-status-checks.json` (add a fake context) in a fixture
   → parity test FAILS (⊇ violated). Remove a `required-checks.txt` name → FAILS (⊆ violated).
2. Lint regression: composite action stripped of its `required-checks.txt` read → the extended
   lint/test FAILS (composite blind spot closed).
3. Action unit-ish: feed a `required-checks.txt` fixture with a multi-word + parenthesized name →
   the parser yields the exact name (no whitespace collapse), one check-run posted per name.
4. gitleaks ceiling: stage a fixture diff containing a synthetic-token shape → action fails loud,
   no PR, no synthetics (use a non-secret placeholder per `cq-test-fixtures-synthesized-only` /
   the push-protection Sharp Edge; wrap in `<<...>>` so push isn't rejected).
5. `terraform -chdir=infra/github validate` passes; `plan` is a documented no-op vs live.

## Hypotheses
N/A — no network-outage / SSH / connectivity keywords; root cause is fully characterized
(three-layer list drift + one IaC drift, all verified against live state).
