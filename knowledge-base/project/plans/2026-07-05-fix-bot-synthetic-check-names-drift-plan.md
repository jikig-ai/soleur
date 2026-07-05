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

## Enhancement Summary (deepen-plan, 2026-07-05)

Reviewed by scoped advisor (fable) + security-sentinel + architecture-strategist + code-simplicity-reviewer.
Verdicts folded in below. Load-bearing corrections (all verified against source):

1. **Tier 2 (real gitleaks) is MANDATORY — Tier 1 rejected.** Security-sentinel: GitHub
   push-protection catches only partner-provider shapes; it does NOT enforce this repo's custom
   `.gitleaks.toml` rules (BYOK `sk-soleur-`, Doppler `dp.st./dp.sa.`, Supabase JWTs, VAPID,
   webhooks, `postgres://`) or the entropy rule — exactly the shapes the accidental stall blocks
   and the learnings-clustering digest is most likely to carry. Tier 1 is a net regression.
2. **Two content gates are fabricated, not one.** `lint fixture content` (emails / prod Supabase
   refs / prod UUIDs) is a distinct gate gitleaks does NOT cover, and its CI scan scope
   (`secret-scan.yml:161,169`) greps only `knowledge-base/project/learnings/*.md` — NOT the digest
   paths. Phase 4 now reproduces BOTH `gitleaks` AND `lint-fixture-content.mjs` over the bot diff.
3. **The "markdown under knowledge-base/" safe-surface allowlist VOIDS the ceiling.**
   `.gitleaks.toml` exempts `knowledge-base/plans/`, `knowledge-base/*/specs/`, and (for
   private-key/db-url rules) `knowledge-base/project/learnings/*.md` — so a path passing "markdown
   under knowledge-base/" could be gitleaks-blind, and it also **breaks the rule-metrics caller**
   (`.json`, not markdown). Allowlist is now an **explicit enumeration** of the two real artifacts
   (`weakness-digest.md`, `rule-metrics.json`), rejecting the gitleaks-blind subtrees.
4. **Parser `#`-truncation (P1).** The reused lint parser's `line="${line%%#*}"` truncates
   `waiver discipline (issue:#NNN trailer)` → the parity test can never pass AND the bot still
   stalls. Fix: change the shared comment rule to **leading-`#`-only**.
5. **`adr-ordinals` breaks a hardcoded count (P1).** `test-audit-ruleset-bypass.sh:634` asserts
   `n == "16"`; `.tf:18` + canonical prose say "16". Phase 1 now bumps all three to 17.
6. **Cut the gitleaks-install *extraction*** (simplicity + architecture: it touches the required
   `secret-scan.yml` jobs). Use a 3rd pinned install + a pin-parity assertion instead. Net: the PR
   does NOT touch `secret-scan.yml`.
7. **Composite→SSOT anti-drift assertion is mandatory** (architecture P2, resolving a reviewer
   split) but implemented minimally (a grep that `action.yml` sources `required-checks.txt`).
8. **`required-checks.txt` auto-fabrication guard** (security P2): a load-bearing header comment +
   @deruelle CODEOWNERS so a future content-scoped required check isn't silently auto-fabricated.


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

**Secret-safety decision (RESOLVED by security-sentinel — Tier 2 mandatory):**
Completing the synthetic set relaxes the accidental stall-defense on the **two** fabricated
content gates — `gitleaks scan` AND `lint fixture content`. The ceiling:

- The action reproduces **both** content gates over its own staged diff before posting: real
  `gitleaks` (pinned v8.24.2 + SHA, repo `.gitleaks.toml`) AND `lint-fixture-content.mjs`. Any
  finding fails loud (no PR, no synthetic). This *earns* both content greens rather than
  fabricating them.
- **Tier 1 (push-protection only) is REJECTED.** GitHub server-side push-protection enforces
  only partner-provider token shapes — NOT this repo's custom `.gitleaks.toml` rules
  (`sk-soleur-`, `dp.st./dp.sa.`, Supabase HS256 JWTs, VAPID, webhook URLs, `postgres://`) nor
  the `generic-api-key` entropy rule, and NOT the `lint fixture content` PII class at all. Those
  are exactly the shapes the learnings-clustering digest is most likely to surface, so Tier 1 is
  a net regression at `single-user incident` threshold.
- **Safe-surface allowlist = explicit enumeration**, not a directory prefix: the action asserts
  every `add-paths` entry is one of `knowledge-base/project/weakness-digest.md` /
  `knowledge-base/project/rule-metrics.json` (the two real artifacts) and REJECTS `plans/`,
  `specs/`, `references/`, `learnings/` sub-trees — because `.gitleaks.toml` *allowlists* those,
  so a real gitleaks run over them finds nothing and the earned-green would be fabricated after
  all. This also fixes a naive "markdown"-only predicate that would break the rule-metrics
  caller (whose `add-paths` is `.json`).

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
Files to edit: `infra/github/ruleset-ci-required.tf`, `scripts/ci-required-ruleset-canonical-required-status-checks.json`, `tests/scripts/test-audit-ruleset-bypass.sh`
- Add a `required_check { context = "adr-ordinals"; integration_id = var.actions_integration_id }`
  block (Tier-mirroring the existing entries) to the `.tf`. `integration_id` MUST be
  `var.actions_integration_id` (15368) — `adr-ordinals` is a GitHub Actions job (`ci.yml:163`),
  NOT GHAS; using `codeql_integration_id` would silently un-match and break the gate.
- Add `{ "context": "adr-ordinals", "integration_id": 15368 }` to the canonical JSON.
- **Bump the hardcoded count 16→17 in `tests/scripts/test-audit-ruleset-bypass.sh:634`** (T-rsc-7:
  `[[ "$n" == "16" ... ]]`) and its prose comment `:618-621`, AND the `.tf:18` prose ("the 16
  `context` strings below are public ABI" → 17). Same-PR; otherwise T-rsc-7 fails (the exact
  stale-count failure mode #4397 it was written to catch). (T-rsc-9 `.tf`↔canonical lockstep is
  satisfied by the paired `.tf`+JSON edits.)
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
- **Add an auto-fabrication guard comment** (security P2) to the file header: *"Adding a name here
  makes bot PRs fabricate a green for it with no per-check review. A content-scoped gate (secret /
  PII / lockfile / fixture scanning) MUST first be reproduced in the action's preflight
  (Phase 4) or excluded via non-15368 `integration_id` — do not add a content gate here that the
  action cannot actually run over the bot diff."* The file is already `* @deruelle` CODEOWNERS-gated.
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
  (repo is checked out in the consumer job — both current callers run `actions/checkout` and commit
  files; add a **fail-loud guard** if the file is absent so a future non-checkout consumer errors
  instead of posting an empty set). Reuse the `lint-bot-synthetic-completeness.sh:42-57` parser
  (multi-word + single-quote-strip; do NOT `tr -d '[:space:]'` — it destroys
  `skill-security-scan PR gate`; learning `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`)
  — **BUT with the comment rule fixed** (Phase 5): the current `line="${line%%#*}"` inline-comment
  strip truncates `waiver discipline (issue:#NNN trailer)` at the `#`, posting a wrong check-run
  name and leaving that live-required context UNsatisfied. Change to **leading-`#`-only** (a line
  is a comment iff it starts with optional whitespace then `#`) — behavior-preserving for the
  existing full-line comments, and required for the `#`-bearing check name.
- Post one Checks-API `check-run` per parsed name. Special-case `cla-check`/`cla-evidence`
  output titles/summaries inside the loop (a small `case`), so the two custom outputs are
  preserved from **one** source with no separate hardcoded blocks and no double-post.
- Update `.github/actions/bot-pr-with-synthetic-checks/CHANGELOG.md` (v3: derives from SSOT + real gitleaks preflight).

### Phase 4 — Secret-safety ceiling (CORE — the named ceiling; Tier 2, mandatory)
File to edit: `.github/actions/bot-pr-with-synthetic-checks/action.yml`
- Before posting synthetics, reproduce **both** fabricated content gates over the action's own
  staged/committed diff:
  1. **real gitleaks** — same pinned `GITLEAKS_VERSION` (8.24.2) + SHA256 as `secret-scan.yml` and
     the repo `.gitleaks.toml`, `--redact`.
  2. **`node apps/web-platform/scripts/lint-fixture-content.mjs`** over the diff (emails / prod
     Supabase refs / prod UUIDs) — gitleaks does NOT cover this class, and its CI scope
     (`secret-scan.yml:161,169`) greps only `knowledge-base/project/learnings/*.md`, so the digest
     paths are otherwise unscanned by the real gate.
  Any finding from either → fail loud, do **not** create the PR, do **not** post synthetics.
- **Safe-surface allowlist = explicit enumeration.** Assert every `add-paths` entry equals one of
  `knowledge-base/project/weakness-digest.md` / `knowledge-base/project/rule-metrics.json`. REJECT
  (fail loud) any path under `knowledge-base/{plans,specs,references}/**` or
  `knowledge-base/project/learnings/**` — `.gitleaks.toml` allowlists those, so the real gitleaks
  run would be blind there and the earned-green would be fabricated. Do NOT use a bare "markdown
  under knowledge-base/" predicate (voids the ceiling AND rejects the `.json` rule-metrics caller).
- **Pin management (simplicity + architecture: do NOT extract).** Do NOT refactor `secret-scan.yml`'s
  install step — it hosts the required `gitleaks scan` / `lint fixture content` jobs and the
  ADR-032 job-name contract makes any restructure of a required-check workflow high blast-radius.
  Instead add the action's own pinned install block (3rd site) and add a **pin-parity assertion**
  to the Phase-5 test: all three sites (`secret-scan.yml:82`, `ci.yml` `test-scripts:448`, the
  action) reference the same `GITLEAKS_VERSION` + SHA256; divergence fails CI. Cheaper and touches
  no required-check workflow.

### Phase 5 — Drift-proof tests (make re-drift impossible)
Files to create/edit: `plugins/soleur/test/required-checks-canonical-parity.test.sh` (new),
`scripts/lint-bot-synthetic-completeness.sh` (fix parser comment rule + minimal composite guard),
`plugins/soleur/test/lint-bot-synthetic-completeness.test.sh` (regression case)
- **Fix the shared parser first** (P1, see Phase 3): change the comment rule in
  `lint-bot-synthetic-completeness.sh` from inline `${line%%#*}` to **leading-`#`-only**, add a
  regression case in its `.test.sh` asserting `waiver discipline (issue:#NNN trailer)` round-trips
  intact. Without this, both the action AND the parity test break on that name.
- **New parity test** (file-vs-file, deterministic, no API): assert the CI-Required subset of
  `required-checks.txt` **equals** the set of `context`s in `canonical-required-status-checks.json`
  **filtered to `integration_id == 15368`** (compute via `jq '.[]|select(.integration_id==15368).context'`,
  NOT a `CodeQL` string literal). Compute the "CI-Required subset" of `required-checks.txt` by
  **excluding an explicitly-named CLA set `{cla-check, cla-evidence}`** — there is no canonical CLA
  JSON (only `create-cla-required-ruleset.sh`), so name the exclusion in the test with a comment
  that a 3rd CLA context requires updating it (deferred hardening: a canonical CLA JSON mirroring
  the RSC one — see Alternatives). Compare as sorted sets, multi-word-safe, regex-escaped — assert
  **both** ⊆ and ⊇, not `| length` (`2026-05-16-prose-contract-vs-executable-check-dimension-drift.md`).
- **Composite→SSOT guard (mandatory, minimal — architecture P2).** The action is exempt from the
  existing lint by construction; a future re-hardcode of `CHECK_NAMES` in `action.yml` would
  silently reintroduce the exact drift this PR fixes. Add a cheap deterministic assertion (in the
  lint or the parity test) that `action.yml` **references** `scripts/required-checks.txt` (a
  `grep -q` on the action body). Do NOT rely on "coverage by construction" alone. This is minimal
  (one grep), so it satisfies both the architecture mandate and the simplicity concern.
- **Pin-parity assertion** (Phase 4): assert `GITLEAKS_VERSION`+SHA256 match across
  `secret-scan.yml`, `ci.yml` `test-scripts`, and the action.
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
- [ ] `infra/github/ruleset-ci-required.tf` contains an `adr-ordinals` `required_check`
      (integration_id `var.actions_integration_id`); the canonical JSON contains a matching
      `{context: "adr-ordinals", integration_id: 15368}`; `test-audit-ruleset-bypass.sh` T-rsc-9
      (`.tf`↔canonical lockstep) passes AND T-rsc-7 count assertion updated 16→17 (with the
      `.tf:18` + `:618-621` prose bumped to 17).
- [ ] `scripts/required-checks.txt` CI-Required subset, as a set, equals the
      `canonical-required-status-checks.json` contexts with `integration_id == 15368` (computed
      via `jq`, NOT a `CodeQL` string literal), verified by the new parity test asserting BOTH ⊆ and ⊇.
- [ ] `action.yml` no longer hardcodes `CHECK_NAMES`; it parses `scripts/required-checks.txt`
      with the multi-word-safe parser (leading-`#`-only comment rule) and posts one 15368 check-run
      per name; `cla-check`/`cla-evidence` custom outputs preserved; no name double-posted; fails
      loud if the file is absent.
- [ ] Parser round-trips `waiver discipline (issue:#NNN trailer)` intact (regression test) — no
      `#`-truncation.
- [ ] Phase-4 ceiling present: real gitleaks AND `lint-fixture-content.mjs` run over the diff and
      fail loud on a finding; `add-paths` allowlist is the explicit `{weakness-digest.md,
      rule-metrics.json}` enumeration and REJECTS `plans/`/`specs/`/`references/`/`learnings/`
      sub-trees; pin-parity assertion covers all 3 gitleaks pin sites. `secret-scan.yml` untouched.
- [ ] New `plugins/soleur/test/required-checks-canonical-parity.test.sh` passes (both ⊆/⊇ via
      `jq integration_id==15368`, CLA `{cla-check,cla-evidence}` excluded) and is wired into CI.
- [ ] A deterministic guard asserts `action.yml` references `scripts/required-checks.txt` (future
      re-hardcode caught).
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
| **Tier-1-only secret safety (allowlist + push-protection)** | **REJECTED** by security-sentinel: push-protection covers only partner shapes, missing this repo's custom `.gitleaks.toml` rules + entropy + the entire `lint fixture content` PII class — a net regression on the digest's highest-risk shapes. Tier 2 (reproduce both content gates) is mandatory. |
| **Shared gitleaks-install composite** | Cut per simplicity + architecture — it touches `secret-scan.yml`'s required-check jobs (ADR-032 job-name contract, high blast-radius). Replaced by a 3rd pinned install + pin-parity assertion. |
| **Canonical CLA JSON (mirror the RSC one)** | Deferred hardening — would let the parity test derive the CLA exclusion structurally instead of a named `{cla-check,cla-evidence}` set. Low-drift (CLA rarely changes); a follow-up, not this PR. |
| **Split adr-ordinals into its own PR** | Creates a merge-order dependency (parity test needs canonical to carry `adr-ordinals` first) for no gain; both must land and both need the @deruelle code-owner review anyway. |
| **Modify/retire `post-bot-statuses.sh`** | Legacy, zero callers — deferred as a separate dead-code cleanup (tracking issue) to keep this PR scoped. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails
  `deepen-plan` Phase 4.6 — this one is filled (threshold: single-user incident).
- **Multi-word check names:** the action's new parser MUST reuse `lint-bot-synthetic-completeness.sh`'s
  leading/trailing-only trim (never `tr -d '[:space:]'`) and regex-escape names before any grep;
  `skill-security-scan PR gate`, `allowlist-diff (.gitleaks.toml paths surface)`,
  `waiver discipline (issue:#NNN trailer)` all contain spaces and/or parens.
- **`#`-in-name truncation (P1, verified):** the current parser strips comments via inline
  `${line%%#*}`, which truncates `waiver discipline (issue:#NNN trailer)` → `waiver discipline (issue:`.
  This breaks the parity test AND makes the bot post a wrong name (still stalling on the real
  context). Fix the comment rule to **leading-`#`-only** before reusing the parser. Verify:
  `line='waiver discipline (issue:#NNN trailer)'; [[ "${line%%#*}" == "$line" ]]` must be made true.
- **Safe-surface allowlist vs `.gitleaks.toml` allowlist (P1):** a "markdown under knowledge-base/"
  predicate is NOT safe — `.gitleaks.toml` exempts `knowledge-base/{plans,specs}/**` and (for
  private-key/db-url rules) `learnings/**`, so the real gitleaks run is blind there and the
  earned-green becomes a fabrication. Enumerate the two real artifacts; reject those sub-trees.
- **T-rsc-7 hardcoded count (P1):** adding `adr-ordinals` bumps the canonical set 16→17; the
  audit test `test-audit-ruleset-bypass.sh:634` hardcodes `"16"` and `.tf:18` prose says "16" —
  update both (and the `:618-621` comment) in the same PR or CI fails.
- **Auto-fabrication (P2):** once the action derives from `required-checks.txt`, adding any
  `integration_id==15368` context there auto-fabricates a green for bot PRs. A future
  content-scoped required check MUST first be reproduced in Phase-4 preflight (or excluded via
  non-15368 id) — the header guard comment + @deruelle CODEOWNERS enforce this.
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
  `infra/github/` (Terraform) — convention + daily *detection* (the Inngest audit), NOT a
  technical *prevention* gate (a console/API edit can still cross it, which is how `adr-ordinals`
  slipped). The parity
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
