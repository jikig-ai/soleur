---
title: "drain three deferred follow-ups: an Art. 33(5) breach register, a guard that can block, and a linter that can see tests/"
type: feat
date: 2026-09-03
slug: chore-supabase-followups-art30-register-orphan-linter
branch: feat-one-shot-7716-7717-7718-supabase-followups
issue: 7717
closes: [7717, 7716, 7718, 6489]
priority: p1-high
domain: [legal, engineering]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-09-03 · **Review panel:** 7 agents (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO devex, CPO delta) after 3 domain leaders, 6 research agents and the GDPR gate.

**What the review changed, and it was not polish.** Three of the plan's mechanisms were **deleted** rather than improved, and two of its central claims were **falsified**:

1. **W7 lost its union machinery.** A second producer, a parallel covered-set derivation across five surface extractors, a seventh registration surface, 21 waiver entries and two extra floors — replaced by two non-recursive directory loops, on a measurement (53 files → 1 orphan; 4 → 1) that made every one of those costs structurally unnecessary. Complexity went from days to hours. Both panels fired on the same scope, which is the signal to delete.
2. **The second ADR was cut.** ADR-139 already owns the subject, this repo's convention is to amend, and ADR-139 itself forbids inheriting the intersection derivation from a prior ADR — so minting a citable ordinal would have manufactured the thing it bans.
3. **Guard 2 moved into an existing suite**, and its `action.yml` anchor comment was dropped once review found the general instruction already standing at that exact site.
4. **Falsified: the orphan linter is already merge-blocking.** The plan called it advisory. It is registered inside the required `test` context, which changes W7's blast radius from a nag to a repo-wide freeze.
5. **Falsified: the "independently revertable first commit" mitigation.** `ship` merges with `--squash`, so there is no per-phase commit on `main`. DC-1 now records the coupling as real and unmitigated instead of claiming a mitigation the merge path does not support.

**Verifications run against the tree, not asserted:** all 13 AGENTS.md rule-ID citations are active (none retired or fabricated); all 17 cited issue/PR numbers resolve with titles matching their assigned roles; all 10 prescribed labels exist; the guard-contract lint and the no-human-steps lint are green; and **every acceptance criterion was executed against the untouched tree** — each fails today and would pass after the work, except the three labelled regression guards. That dry-run rewrote six criteria that could not fail, could not pass, or measured a different gate than they claimed.

**One defect was introduced and caught during this pass:** a slice anchored on `## Alternative Approaches Considered` matched a backticked *mention* of that heading earlier in the file and duplicated the entire Technical Approach section. Found by the rule-ID sweep, excised, and worth recording because it is precisely the anchor-matched-a-mention class the plan spends four guards on.

## Overview

No `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed) rather than being carried forward.

Three follow-ups were deliberately deferred out of the merged Supabase Management API
log-endpoint migration and filed as separate trackers. This plan drains them together
because they share a provenance and a review surface, while keeping their disposition
explicit per part.

- #7716 — a five-part engineering tracker covering a guard promotion, a deprecated
  vendor surface with no successor, a secret-name unification, a missing C4 element,
  and an incident-routing convention that is present in one runbook out of sixty-seven.
- #7717 — statutory register completeness: determination records that exist only inside
  the audit documents that produced them, plus unresolved placeholders in one register
  entry.
- #7718 — a test-suite linter whose directory walk cannot observe one test directory,
  which the filing issue frames as a design question rather than a widening.

Each part is decided explicitly in this plan as in-scope for this PR, monitor-only by
construction, or separately tracked with a reason.

## Research Insights

### Premise Validation (Phase 0.6)

Every artifact the three issues cite by reference was probed. Five premises moved.

| Cited premise | Probe | Verdict |
|---|---|---|
| PR #7706 merged, three issues OPEN | `gh pr view 7706` → `MERGED 2026-09-02T23:10:28Z`; `gh issue view` ×3 → all OPEN | **holds** |
| #7717 cites `…/feat-one-shot-supabase-analytics-logs-endpoint-migration/phase-0-endpoint-evidence.md` for the out-of-scope rationale | `find` over the spec dir + `archive/`; `git log --all --diff-filter=A -- '*phase-0-endpoint-evidence*'` → empty | **STALE — the file was never committed anywhere.** The measured evidence lives in `knowledge-base/engineering/operations/references/supabase-management-api-log-contract.md` and `…/decisions/ADR-197-a-zero-from-a-log-surface-is-not-evidence-of-absence.md`. The plan cites those instead; the scope-out itself is unaffected and stands. |
| #7716 part 1: "adding a content-scoped gate name to `required-checks.txt` makes the composite action post a fabricated green, so reproduce it in the preflight FIRST" | Re-derived the ADR-139 intersection mechanically (see below) | **PARTLY STALE.** The intersection is EMPTY, so the earned-green preflight the issue mandates is not the applicable disposition — the `marketplace-manifest-guard` unreachability argument is. And a cheaper promotion path exists that the issue does not consider (see Property List P1). |
| #7716 part 5: "0 of 67 runbooks carry `triggers:`; `breach-access-log-investigation.md` is the first" | `ls …/runbooks/*.md \| wc -l` → **68**; `grep -l '^triggers:'` → **2** | **drifted, substance holds.** #7706 added `supabase-log-query.md`, whose block is a deliberate `triggers: []` counter-exemplar. Non-empty count is still 1. |
| #7716 part 3: "`SUPABASE_PAT` / `SUPABASE_ACCESS_TOKEN` unification — debt, not a defect" | `gh issue list --search SUPABASE_PAT` → **#6489 OPEN**, "SUPABASE_PAT is stale — HTTP 401 in both soleur/dev and soleur/prd" (verified 2026-07-15) | **UNDERSTATED.** The name split is debt; the token behind one of the names is a live 401. #6489 already prescribes the fix ("delete and standardise on `SUPABASE_ACCESS_TOKEN` — grep first"). This plan folds it in and closes both. |

Adjacent OPEN issues touching the same files, checked for collision:

- **#7670** (P2, `domain/legal`) — edits `article-30-register.md` PA-7/PA-1 transfer-test reasoning. Its own §Boundary forbids rewriting the Supabase transfer assertions as a side effect of another PR. **Acknowledged, not folded in** — a different cell, a different question.
- **#7635** (P3, `type/bug`) — a load-dependent false FAIL in `tests/scripts/test-supabase-advisor-scan.sh`. Same directory as #7718, different concern. **Acknowledged.**
- **#7125 / DEF-2** — the existing tracker for register-vs-code drift guarding. This plan's register gate is a first instalment against it, not its closure.

### Property List (Phase 0.6b — what the ask actually wants, as observable outcomes)

| # | Property |
|---|---|
| P1 | A PR that reintroduces a deprecated Supabase Management API path, or unpins the host span on a PAT-bearing caller, **cannot merge**. |
| P2 | If Supabase publishes a successor to `advisors/*`, or an announced removal date, the repo finds out without anyone remembering to look. |
| P3 | An agent reaching for a Supabase Management API credential finds one name, and it authenticates. |
| P4 | The architecture model shows the Supabase Management API as a dependency rather than omitting it. |
| P5 | `/soleur:incident` routes a symptom to a runbook instead of falling through to ad-hoc response on every incident. |
| P6 | The parseable shape of a `triggers:` block is recoverable from the skill that consumes it. |
| P7 | A supervisory authority shown `article-30-register.md` can find every Art. 33(5) determination the controller has made. |
| P8 | PA-8 and the vendor mapping carry no unresolved placeholder tokens. |
| P9 | A shell suite added under `tests/scripts/` and registered in no runner is detected. |

Explicit **non**-property, per #7717: a retention technical-and-organisational measure for the Supabase log surface. The 2026-08-26 measurement is revocable vendor-side retrievability through an instrument concurrently proven untrustworthy (HTTP 200 + `error: null` over a window that truncates non-monotonically; the documented 24-hour range cap is not enforced). Recording it would claim a control we do not hold.

### Cut List (Phase 0.6b — mechanisms cut before research)

| Mechanism the ask proposes | Property it buys | What already covers it | Disposition |
|---|---|---|---|
| Add `lint-bot-statuses` (or a new extracted job) to `required-checks.txt` + the canonical JSON + `infra/github/ruleset-ci-required.tf` — a new public-ABI status context | P1 | **The `test` required context already blocks merges, and `scripts/test-all.sh` already runs inside it.** `scripts/test-all.sh` registers `scripts/lint-supabase-deprecated-endpoints-unit` at the `run_suite` line whose own committed comment reads: *"this single line IS a promotion path, and it bypasses the #6049 auto-fabrication trap that makes the required-checks.txt route four coupled steps, because it adds no new content-scoped gate NAME."* | **CUT the new context.** P1 is bought by one `-live` `run_suite` line. Full reasoning and the rejected alternative are in §Alternative Approaches Considered. |
| Reproduce the guard in the bot-PR composite action's Phase-4 preflight (issue #7716 step 1) | soundness of the bot-PR synthetic green | ADR-139 says the `ALLOWED_PATHS ∩ SCAN_DIRS` test is re-derived per gate, never inherited. Re-derived here, mechanically, against the guard's own pathspec: `ALLOWED_PATHS = {knowledge-base/project/weakness-digest.md, knowledge-base/project/rule-metrics.json}`; the guard's pathspec is `. :(exclude)*.md :(exclude)*.mdx :(exclude)knowledge-base/**`. Both members are excluded twice over. Command run: `git grep -lI --fixed-strings -e 'https://api.supabase.com' -- . ':(exclude)*.md' ':(exclude)*.mdx' ':(exclude)knowledge-base/**'` and the arm-2 equivalent → **0 `knowledge-base/` files in either assembly; 30 files enumerated total; intersection ∅.** | **CUT the preflight.** The unreachability disposition (`marketplace-manifest-guard` shape) applies. Replaced by a mechanical tripwire — see Guard Contract Guard 2 — because prose is not a control. |
| Backfill `triggers:` into the other 66 runbooks (#7716 part 5) | P5 | Nothing covers P5 today. **Not cut** — but deferred, and the reason is scope shape rather than redundancy. Each runbook needs *curated* symptom phrases, and the committed counter-exemplar shows `triggers: []` is the right answer for tool-documenting runbooks, so this is 66 judgement calls, not a sweep. Bundling that diff under a P1 statutory change buries the statutory change. | **Deferred, tracked.** P6 (the shape pin) **is** in scope — it is cheap, it is the issue's own secondary finding, and it is a precondition for anyone doing the backfill correctly. |
| Migrate the `advisors/*` callers (#7716 part 2) | — | Nothing. The issue is explicit: no replacement path exists in the live spec for either `advisors/security` or `advisors/performance`, and neither carries a sunset date. | **Cut by the issue itself.** Monitor-only. |

### Value-Proposition Measurement (Phase 0.6c)

The Cut List's first row rests on a cost claim, so it is measured rather than asserted.

- **Cost of the cut path (new required context):** four coupled file edits (`required-checks.txt`, `scripts/ci-required-ruleset-canonical-required-status-checks.json`, `infra/github/ruleset-ci-required.tf`, a new `ci.yml` job extracted from `lint-bot-statuses`), plus a permanent public-ABI obligation — `infra/github/ruleset-ci-required.tf` states it in terms: *"the `context` strings below are public ABI for the branch-protection gate. A workflow job rename … silently un-requires the check until this resource is updated in the same PR."* Plus a live ruleset apply: `.github/workflows/apply-github-infra.yml` fires `on: push` to `main` for `infra/github/*.tf`, so the ruleset mutates on merge.
- **Cost of the kept path:** one `run_suite` line in `scripts/test-all.sh`, alongside the `-unit` line already there.
- **Property delta:** none. Both make the guard merge-blocking on human PRs and both leave bot PRs on a synthetic green whose soundness rests on the same (empty) intersection.
- **What the cut path would buy that the kept path does not:** a distinct check name in the PR checks list. Measured against the repo's own precedent, that attribution was worth paying for in #6882 because promoting the *job* would have promoted five unrelated advisory linters with it — a bundling problem the `test-all.sh` route does not have at all.

### Skill Description Budget (Phase 1.8)

Baseline recorded because this plan edits `plugins/soleur/skills/incident/SKILL.md`. That edit touches the skill **body**, not its `description:` frontmatter, so the cumulative `SKILL_DESCRIPTION_WORD_BUDGET` in `plugins/soleur/test/components.test.ts` is not consumed. Re-checked against the final `## Files to Edit`: no `description:` edit is proposed. Gate does not fire.

### Relevant file paths

Guard promotion:

- `scripts/lint-supabase-deprecated-endpoints.sh` — two arms (deprecation denylist, host-pin). Arm 1 is file-scoped, not line-scoped. Arm 2 inverts the quantifier: assembly is keyed on caller shape, membership is the assertion. Green today: `OK — 30 files enumerated, 26 Management API call sites (baseline 26), 3 waived, 0 violations`, exit 0.
- `scripts/lint-supabase-deprecated-endpoints.highwater` — a **coverage floor, direction inverted** relative to the repo's other highwater files. A drop is the failure.
- `scripts/test-all.sh` — the `SUITE_GLOBS` array (nine patterns, none matching `tests/**` or `scripts/*.test.sh`), and the explicit `run_suite` registration block whose comment names #7718 and describes the promotion path.
- `.github/workflows/ci.yml` — job `lint-bot-statuses` (advisory, eleven steps); job `test-scripts` (runs `bash scripts/test-all.sh scripts`); job `test` (aggregator over `test-webplat`, `test-bun`, `test-scripts`, `if: always()`, `needs:` all three) — `test` is the required context.
- `.github/actions/bot-pr-with-synthetic-checks/action.yml` — `ALLOWED_PATHS`, the `CHECK_NAMES` derivation loop, the Phase-4 ceiling.
- `plugins/soleur/test/required-checks-canonical-parity.test.sh` — Tests 1–8; Test 8 is the reproduction-deletion tripwire whose anchors are syntactic, never a bare script name.
- `knowledge-base/engineering/architecture/decisions/ADR-139-earned-green-required-for-reachable-surface-content-gates.md`; `ADR-197-…` §"Non-vacuity of the deprecated-endpoint guard after `advisors/*` migrates".
- `knowledge-base/project/brainstorms/2026-07-23-lint-bot-statuses-required-promotion-brainstorm.md` — the #6882 promotion brainstorm; D1–D7 are the closest precedent to this plan's W1 and the source of the extraction-for-attribution rationale.

Article 30 register:

- `knowledge-base/legal/article-30-register.md` — 35 processing activities, **PA-36 is the next free number**; frontmatter `version: 0.1.0-draft`, `last_reviewed: 2026-07-31` (stale — PA-34/35 are 2026-08-06 and PA-8 carries 2026-08-13 blocks). Amendment contract is **additive-only dated brackets**: `**[YYYY-MM-DD UPDATE (#issue / ADR-nnn): …]**`.
- **`grep -c "33(5)"` on the register → 0.** There is no Art. 33(5) section, no table, no per-event entries. The three existing "no notification warranted" statements sit incidentally inside PA-8 `(d) Recipients` as bracketed update blocks.
- Placeholders: `__TBD_OBSERVED_VOLUME__` ×2 and `__TBD_BETTERSTACK_RETENTION__` in PA-8 §(f); `__TBD_DPA_DATE__` in the `## Vendor / Sub-Processor Mapping` Better Stack row (PA column `8, 31`).
- `knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md` — the canonical fenced record, under the heading *"Art. 33(5) breach-documentation / near-miss record (canonical) — cross-referenced from the Art. 30 register"*. Zero register hits for every distinctive term (`pigsfuxruiopinouvjwy`, `inngest-prd-rls`, `near-miss`, `2026-06-29`). Its `<!-- ADDENDUM-2026-08-26 -->` block states the record above **is not amended**, while reframing its "retained edge/auth logs show zero traffic" sentence as an instrumentation gap rather than evidence.
- `knowledge-base/legal/statutory-response-catalog.md` — points outward to the PIR scaffold and back at the register; carries no determinations index. The three-way pointer loop (catalog → register → determination → register) is broken at the register.
- `knowledge-base/legal/compliance-posture.md` — the Better Stack row carries a **standing directive**, unactioned: *"The AC15 escalation this cell announces has never been filed … **Directed:** file the `compliance/critical` issue AC15 names, and either execute the Vendor DPA or record on that issue the specific published Better Stack terms relied on as the 'other legal act' under Art. 28(3)."* Re-evaluation: on execution, or 2026-11-13.
- `plugins/soleur/skills/ship/references/register-update-pr-pattern.md` — the register-update PR playbook; the register cites file paths inline as Art. 5(2) evidence while the PR body must cite semantic identifiers only (`pr-body-vs-diff` gate).
- `scripts/check-pa-22.sh` — a fail-closed sentinel over the register that is **wired into no workflow** (`grep -rn check-pa-22 .github/` → zero). The register says so about itself at PA-31 §(g) measure (10), tracked as DEF-2 / #7125.
- `scripts/generate-article-30-register.sh` — stale and misleading; targets an archived template and prints a "must NOT be committed" warning that contradicts the live register. Not a validator.
- `.github/workflows/legal-doc-cross-document-gate.yml` — job `enforce`, a required context, triggers on all PRs with no `paths:` filter. Its `surface_patterns` are six DSAR-specific regexes; the register is in neither the surface set nor `required_legal_files`. **Editing the register triggers nothing.**

Orphan-suite linter:

- `scripts/lint-orphan-test-suites.sh` — the producer is `git ls-files '*.test.sh'`, a **suffix**, repo-wide. `EXPECTED_SUITE_ROOTS=".claude apps plugins scripts"` (a superset check; `tests` deliberately absent). Six coverage surfaces, three of which hard-code `\.test\.sh` in their own regexes. A hard-coded `tests/commands/` loop exists at the bottom, with **no waiver mechanism**. `EXCLUSIONS=()` is empty and the header says empty is the goal state.
- The file **contradicts itself**: its header records that the claim "`tests/scripts/` is floored by `.github/scripts/test/run-all.sh`'s own `MIN_SUITES`" is false, and then the trailing `tests/commands/` comment repeats that same false claim. Verified: that runner globs `$DIR/test-*.sh` with `DIR=.github/scripts/test` and never looks at `tests/scripts/`.
- Stale count in the header: it says `tests/scripts/` holds 45 `test-*.sh`; the tree holds **53**.
- Naming conventions inside `tests/` are **three**, not one: `test-<name>.sh` (`tests/scripts/`, `tests/commands/`), `test_<name>.sh` (`tests/hooks/`), `test_<name>.py`. **Zero `*.test.sh` files exist anywhere under `tests/`.**
- `tests/scripts/lib/*.sh` (17 files) are **production gate implementations**, not suites — `source`d from `.github/workflows/apply-web-platform-infra.yml` at 17 sites and executed as `bash …/preapply-entrypoint-gate.sh --gate`. A naive `tests/**/*.sh` walk reports all 17 as orphans.
- Repo-wide: 380 tracked `*.test.sh`; 82 tracked `/test-*.sh` across seven directories. Outside `tests/`, the `test-*.sh` pattern also matches libraries (`scripts/lib/test-relevance-paths.sh`, `scripts/lib/test-contention.sh`, `plugins/soleur/test/test-helpers.sh`) and the runner itself (`scripts/test-all.sh` and five `test-all-*.test.sh` siblings) — which is exactly why the current producer uses a suffix: a suffix is unambiguous, a prefix is not.
- **Live orphans the research surfaced** (the blind spot is not hypothetical): `tests/scripts/test-sentry-brownout-retry.sh` — `git grep` returns zero hits repo-wide, and it gates the brownout retry in `apply-sentry-infra.yml`, which touches production Sentry paging including GDPR Art. 33 alert rules; `tests/hooks/test_drop_sentinel_parity.sh`; `scripts/test-jaccard-duplicates.sh`; `scripts/test-weekly-analytics.sh`.
- `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` is **double-covered** — registered in `scripts/test-all.sh` and executed directly by `.github/workflows/apply-sentry-infra.yml` at two sites. A new producer needs a `DOUBLE_COVERED_ACK` entry for it or it reds on arrival.
- Nothing in `knowledge-base/` documents the `tests/` vs `*/test/` split. The constitution's only test-placement rule (`knowledge-base/project/constitution.md`, *"Test files live in a `test/` sibling directory … named `<module>.test.ts`"*) is TypeScript-only. The convention lives **only** in `EXPECTED_SUITE_ROOTS` and in scattered self-referential comments.
- `ADR-161` records the inverse trick — a mutation battery deliberately **not** named `*.test.sh` so the auto-glob would not pick it up. The suffix is load-bearing as an *opt-in signal*, so a producer widened to `test-*.sh` must not silently capture files whose authors opted out.

C4 model:

- `knowledge-base/engineering/architecture/diagrams/spec.c4` — exactly five element kinds (`actor`, `system`, `container`, `database`, `component`) and two tags (`external`, `selfhosted`).
- `model.c4` — external systems are top-level siblings of `platform`, in one block, shape `id = system "Name" { #external \n description "…" }` (tag first, then description). A `supabase` element exists but it is `platform.infra.supabase`, a `database` **inside** the boundary with no `#external` tag; seven inbound internal relationships. **No element represents the Supabase control plane at `api.supabase.com`.**
- `views.c4` — both endpoints of an edge must appear in a view's include list or the edge does not render; the file records two prior incidents of exactly that (#7332, ADR-182/#7471). A `#external` tag is auto-muted by both views' style blocks.
- `model.likec4.json` is a **committed compiled artifact**. `plugins/soleur/test/c4-model-freshness.test.sh` renders off-tree with pinned `likec4@1.50.0` and byte-diffs it. `lefthook.yml` hook `c4-model-regenerate` runs `scripts/regenerate-c4-model.sh` and stages the result on any `*.c4` commit. Comment-only edits do not require regeneration; body edits do.
- `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` do **not** validate model content — the first tests a CodeMirror highlighter, the second tests a spawn wrapper with `fs` and `child_process` fully mocked. The gate that actually bites is `c4-model-freshness.test.sh`.
- `supabaseMgmtApi` is named in exactly four places, all archived planning docs, as a deferred-and-tracked gap. Zero occurrences in code or the model.

`triggers:` convention:

- `plugins/soleur/skills/incident/SKILL.md` — three passages. Line-22 directory convention claims *"runbooks have `triggers:` frontmatter and are scanned by Phase 3 for routing; PIRs do not and are not scanned."* Phase 3 prescribes an `awk`-scan, a `{slug: [trigger, ...]}` map, literal-substring scoring, top-3 selection, and the fallthrough string `no runbook matches — proceed to ad-hoc response`.
- **Two documented claims in that file are false against the tree.** (a) **102 of 113** post-mortems under `knowledge-base/engineering/operations/post-mortems/` DO carry `triggers:` (an earlier draft of this line said ~19 — off by more than fivefold, and it is the figure an implementer reading top-down meets first) — they are PIRs generated from `templates/pir.md`, which emits the key — so "has `triggers:`" is not the semantic discriminator the skill claims. (b) `knowledge-base/legal/runbooks/dsar-accountless-ex-member.md` is a runbook the Phase-3 directory scope does not reach.
- **The parseable shape is nowhere in the skill.** `plugins/soleur/skills/incident/scripts/dry-run.sh` does not scan runbooks at all — it reads `triggers` from the fixture JSON (`jq -r '.triggers | join(",")'`) and its Phase 3 only checks the runbook directory exists. The shape is recoverable only from the emit side (`triggers_yaml+="  - ${t}"`) and `templates/pir.md` (`triggers:\n{{TRIGGERS_LIST}}`) — a YAML block sequence under a column-0 `triggers:` key, two-space indent, one `- <item>` per line. Not comma-separated, not flow-style.
- Both exemplars must be handled by any scanner: `breach-access-log-investigation.md` carries nine natural-language symptom phrases as a block sequence; `supabase-log-query.md` carries a deliberate inline-flow `triggers: []` with a committed note explaining why an empty list beats an omitted one.
- Phase 4 consumes `triggers[]` further: the substitution table, the secret-leak preamble (`api_key_leaked`, `credentials_exposed`, `token_exposed`, `secret_in_logs` — snake_case tokens, a **different vocabulary** from the prose phrases the sole exemplar uses), and the LLM-trust redaction sentinel.

Credentials:

- `SUPABASE_PAT` is read by exactly one script — `apps/web-platform/scripts/postgrest-reload-schema.sh` — plus its test, one comment in `apps/web-platform/scripts/run-migrations.sh`, and one doc line in `apps/web-platform/docs/migration-rollback.md`. `SUPABASE_ACCESS_TOKEN` is the name every workflow, Terraform resource and Inngest function uses.
- Both names are arm-2 assembly keys in the deprecated-endpoint guard's regex (`/v1/projects|SUPABASE_ACCESS_TOKEN|SUPABASE_PAT`). Unifying the callers must **not** drop `SUPABASE_PAT` from that regex — a resurrected use has to stay catchable.

Deferred spec-diff poller (#7716 part 2's "monitor"):

- The mechanism is fully designed and unbuilt: `knowledge-base/project/plans/archive/20260902-200523-2026-08-26-feat-supabase-analytics-logs-endpoint-migration-plan.md` §"Phase 9 (PR-C) — Deprecation spec-diff, folded in" — one step appended to `.github/workflows/scheduled-supabase-advisor-scan.yml`, which already holds the token, already calls the host, and already carries label-dedupe. Folding in avoids a new cron surface **and** `.claude/hooks/new-scheduled-cron-prefer-inngest.sh`, which denies a new scheduled workflow outright (ADR-033) — including when the trigger token appears inside a comment.
- No issue tracks it. `gh issue list --search "spec-diff poller"` returns only #7716 itself.

### Applicable institutional learnings

| Learning | What it changes here |
|---|---|
| `knowledge-base/project/learnings/2026-07-16-a-gate-that-proves-it-cannot-fail-open-shipped-its-own-proof-unwired.md` | Five documented instances of auto-discovery failure, one of them **`test-all.sh` + `tests/scripts/`** — the exact #7718 shape. An unwired harness is worse than no gate. Mutation-test the promotion. |
| `2026-07-20-an-advisory-gate-is-not-a-weak-gate-it-is-no-gate-and-a-ratio-needs-its-denominator-checked.md` | The framing for W1: advisory is not weak, it is nothing. Cited by the #6882 brainstorm for the same promotion. |
| `2026-03-20-github-required-checks-skip-ci-synthetic-status.md` | A newly-required context with no producer on bot PRs stalls every bot PR pending forever. Load-bearing for rejecting the `integration_id` option and for the kept path (which adds no new context at all). |
| `2026-06-29-required-check-anchors-must-cover-verified-surface-not-inherited-paths.md` | Promoting a changed-files gate makes its diff anchors part of the security contract. The Supabase guard is already full-scan (`git grep` over a pathspec), so its green asserts "the repository is clean". |
| `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md` | Check names are ABI; `tr -d '[:space:]'` collapses internal whitespace. Relevant only to the rejected path — a further argument for not minting a new name. |
| `2026-06-29-c4-source-edit-requires-regenerate-model-json-orphan-suite.md` | `c4-model-freshness.test.sh` is itself discovered only by the full `test-all.sh` run. Regenerate and commit `model.likec4.json` in the same change; do not rely on a touched-file test set. |
| `2026-06-18-c4-impact-requires-reading-all-diagrams-and-enumerating-external-actors.md` | A "no C4 impact" conclusion requires reading all three `.c4` files and enumerating external actors/systems/access edges — never a keyword grep for the feature's own noun. Applied in §Architecture Decision. |
| `2026-06-04-art-30-pa-citation-must-be-grep-validated-against-register.md` | PA-number attributions are hypotheses. Grep the register for the *implementing surface*, never match on a PA's title. PA-36 was derived by enumerating every `## Processing Activity` heading, not by incrementing a remembered number. |
| `2026-05-23-legal-disclosure-prose-must-be-grep-validated-against-actual-migration.md` | Every implementation-detail claim in a register cell is grep-validated against the artifact it names before it lands. |
| `2026-08-06-my-correction-overshot-into-a-new-wrong-claim-in-a-compliance-artifact.md` | A replacement claim inherits none of the original's scrutiny. Directly binding on `__TBD_DPA_DATE__`: the replacement must not be a plausible-looking date. |
| `2026-05-29-legal-doc-triple-lockstep-and-rpc-grants-invoker-before-definer.md` | Editing `docs/legal/*.md` is a three-way lockstep (cross-document gate, SHA pin in `apps/web-platform/lib/legal/legal-doc-shas.ts`, Eleventy mirror date). This plan edits `knowledge-base/legal/**` only and does **not** touch `docs/legal/**`, so the lockstep does not fire — asserted, not assumed. |
| `2026-06-02-fixture-bare-substring-marker-over-slurp-and-orphan-test-infix.md` | A suite whose filename lacks the runner's infix is invisible and RED forever. Any new suite this plan adds uses `*.test.sh` under an existing `SUITE_GLOBS` root. |
| `2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md` | Enumerated CI discovery is a standing orphan generator; backfill orphans found on the way, they are free coverage. |
| `2026-04-14-plan-prescribed-test-framework-not-available.md` | The repo convention is bash `*.test.sh` with `plugins/soleur/test/test-helpers.sh`; no bats. |

### Conventions carried from CLAUDE.md / AGENTS.rules.md / the constitution

- `hr-gdpr-gate-on-regulated-data-surfaces` — the register edit routes through `/soleur:gdpr-gate` at plan Phase 2.7 and again at work Phase 2 exit.
- `hr-verify-repo-capability-claim-before-assert` — every option-bounding claim in this plan carries the command that produced it.
- `hr-no-dashboard-eyeball-pull-data-yourself` — the placeholder resolutions pull their numbers from an API or from committed configuration, never from a dashboard glance.
- `hr-no-ssh-fallback-in-runbooks` — `__TBD_OBSERVED_VOLUME__` must not be resolved by an SSH-measured figure.
- `cq-test-fixtures-synthesized-only`, `cq-assert-anchor-not-bare-token`, `cq-cite-content-anchor-not-line-number` — all bind on the new guard tests.
- `wg-architecture-decision-is-a-plan-deliverable` — the ADR and the C4 edit are tasks in this plan, not follow-ups.
- Register frontmatter is `status: draft-requires-counsel-review`; the custodian is the CLO role; amendments are additive-only dated brackets.
- Shell tests: `set -euo pipefail`, one `TMPROOT` with a single `trap` (ADR-129), `pass`/`fail` counters, `assert_*` helpers from `plugins/soleur/test/test-helpers.sh`.

### Provisional ADR ordinal

`ADR-200`. Derived across **all 69 `origin/*` refs**, not `origin/main` alone: `origin/main` tops out at ADR-197; `ADR-198` is claimed by `origin/feat-one-shot-7460-betterstack-baked-token` and `ADR-199` by `origin/feat-one-shot-7695-merge-b-inngest-luks-recut`. Provisional — re-derive immediately before merge and sweep this plan, `tasks.md` and every AC in the same edit if it moves.

### Functional-overlap check

No community skill or agent is adoptable for any of the five items; each turns on a repo-local invariant (the check-name ABI, the register's PA-row conventions, the LikeC4 DSL, the incident router's frontmatter contract). In-repo reuse: `plugins/soleur/skills/architecture/SKILL.md` for the C4 edit, `plugins/soleur/skills/ship/references/register-update-pr-pattern.md` for the register PR shape, `plugins/soleur/skills/gdpr-gate/SKILL.md` and the `soleur:legal:clo` agent for the determination wording.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned 63 issues; each of this plan's `## Files to Edit` paths was matched against every issue body with `jq --arg path … contains($path)` and no body cites any of them.

Three OPEN issues that are **not** `code-review`-labelled do touch this plan's surfaces; their dispositions are recorded in §Premise Validation above — #7670 acknowledged, #7635 acknowledged, #6489 folded in and closed.

## Problem Statement

Three things are true at once on `main`, and each is a gate that reports nothing while looking like coverage.

**A guard that cannot block.** `scripts/lint-supabase-deprecated-endpoints.sh` enforces two properties over every tracked non-doc file that talks to the Supabase Management API: no call to a vendor-deprecated path except under a dated waiver, and a pinned host span on every caller that carries an account-level personal access token. It runs in `lint-bot-statuses`, which is in neither `scripts/required-checks.txt` nor the branch ruleset, so a PR can merge with it red. The host-pin arm is the security-bearing half: a caller whose `API=` resolves through an env-controlled default sends an account-level token to an attacker-chosen host. That arm is currently enforced by nothing.

**A statutory register that does not contain its own records.** `knowledge-base/legal/article-30-register.md` is the artifact a supervisory authority is shown. It contains zero Art. 33(5) determinations — no section, no table, no entries. The determinations exist: **six** files under `knowledge-base/legal/audits/` carry an express Art. 4(12) / Art. 33 determination, and a seventh lives in a post-mortem outside that directory. Two of the six are already cited by the Art. 30 register, and two more are cited there for other propositions. **Exactly one has zero register footprint** — and it is the one whose own text announces itself as *"cross-referenced from the Art. 30 register"*. The gap is narrower than #7717 filed it and worse in kind: not an omission, but a legal artifact making a false self-referential claim. The canonical 2026-06-29 Inngest record announces itself as *"cross-referenced from the Art. 30 register"* and the register returns zero hits for every distinctive term in it. `knowledge-base/legal/statutory-response-catalog.md` points at the register as the place the accountability record lives; the register has no such place. All three documents assert a link that does not exist. Separately, PA-8 and the vendor mapping carry four unresolved `__TBD_*` placeholder tokens, unenforced by anything, that have sat there since 2026-05-22.

**A linter blind to a directory.** `scripts/lint-orphan-test-suites.sh` exists to catch a suite that no runner executes. Its producer is `git ls-files '*.test.sh'` — a suffix — and nothing under `tests/` uses that suffix. 53 suites live in `tests/scripts/` under a `test-*.sh` convention, registered only by hand-written `run_suite` lines that nothing guards. This is not hypothetical: `tests/scripts/test-sentry-brownout-retry.sh` has **zero references anywhere in the repository** and gates the brownout retry in `apply-sentry-infra.yml`, which touches production Sentry paging including GDPR Art. 33 alert rules. Three more unregistered suites were found alongside it.

The third problem is the shape of the other two. A guard that runs in no runner and a determination that lives in no register are the same failure: a control that exists as an artifact and not as a mechanism.

## Proposed Solution

Six workstreams. Four land in this PR; two are deferred with a named reason and a tracking issue. The `## Alternative Approaches Considered` table records what was cut and why.

| WS | Issue part | Disposition |
|---|---|---|
| W1 | #7716 part 1 — promote the deprecated-endpoint guard | **IN SCOPE.** Promote via the already-required `test` context, not a new one. |
| W2 | #7716 part 2 — `advisors/*` | **MONITOR-ONLY, no code**, as the issue states. The monitor's *mechanism* is designed-but-unbuilt; a tracking issue is filed for it. |
| W3 | #7716 part 3 — credential-name unification | **IN SCOPE.** Also closes #6489. |
| W4 | #7716 part 4 — C4 `supabaseMgmtApi` | **IN SCOPE.** |
| W5 | #7716 part 5 — `triggers:` | **SPLIT.** The shape pin and three factual corrections land; the 66-runbook backfill is deferred and tracked. |
| W6 | #7717 — Art. 33(5) register completeness | **IN SCOPE.** The P1. |
| W7 | #7718 — orphan-suite linter | **IN SCOPE**, as a design decision with the rejected options recorded. |

## Technical Approach

### Architecture

**W1 — the promotion, and the fork it turns on.**

`test` is a required status context. It is an aggregator: `needs: [test-webplat, test-bun, test-scripts]`, `if: always()`, and it exits 1 unless all three shards report `success`. `test-scripts` runs `bash scripts/test-all.sh scripts`. `scripts/test-all.sh` already carries an explicit registration for the guard's **unit** suite. Adding a sibling **live** registration makes the guard itself merge-blocking, through a context that already exists.

**This route is not novel, and an earlier draft framed it as though it were.** The `test` aggregator already carries roughly seventeen live full-repo content scanners registered exactly this way — among them `scripts/lint-orphan-test-suites` itself, `lint-guard-contract-live`, `lint-legal-scope-block-placement-live`, `lint-legal-mirror-drift-baseline-live` and `tenant-dpa-register-guard-live`. The decision here is therefore not whether to open a door but whether to keep walking through an open one, and the honest record of it says so. That matters for what the ADR must carry: the interesting question stops being "may a content gate ride `test`" — it manifestly already may — and becomes "what control replaces the four-file CODEOWNERS-gated review that the one-line route bypasses".

The guard is already full-scan by construction — its assembly is a `git grep` over a pathspec, not a diff — so a green asserts *the repository is clean*, not *this diff is clean*. It is green today: `OK — 30 files enumerated, 26 Management API call sites (baseline 26), 3 waived, 0 violations`, exit 0, and `--check-highwater` likewise. There is no backlog to drain first.

Two consequences follow and both must be handled rather than assumed.

1. **The advisory copies in `lint-bot-statuses` must be removed, not left alongside.** Leaving them duplicates execution and, worse, leaves a committed comment block in `ci.yml` and a header in the guard script that both state, at length and in bold, that this gate does not block. A guard whose own documentation says it is advisory when it is not is the same defect class inverted.
2. **Path B does not escape the #6049 auto-fabrication question — it inherits it through `test`, and an empty per-gate intersection is necessary but NOT sufficient.** The committed comment in `scripts/test-all.sh` says this route *"bypasses the #6049 auto-fabrication trap … because it adds no new content-scoped gate NAME."* That is true about the name and insufficient about the soundness. `test` is itself in `scripts/required-checks.txt`, so `.github/actions/bot-pr-with-synthetic-checks/action.yml` posts an unconditional green for it on every bot PR. Moving a content-scoped scanner behind `test` therefore moves it behind a fabricated green, and ADR-139 requires the `ALLOWED_PATHS ∩ SCAN_DIRS` test to be re-derived per gate rather than inherited. It is re-derived in §Research Insights and it is **empty** for this guard. But ADR-139 is written **per gate**, and every alternative it considers is a mint-your-own-context variant — it does not contemplate an aggregator at all. For the `test` route the sound invariant is not per-gate:

> `ALLOWED_PATHS ∩ (⋃ scan surfaces of every live gate registered in scripts/test-all.sh) = ∅`

Nothing computes that union today, and the margin is thinner than it looks: `lint-guard-contract-live` walks `knowledge-base/project/plans/**.md`, one path segment from `ALLOWED_PATHS`' own `knowledge-base/project/weakness-digest.md`. This plan's **own** `scripts/lint-legal-registers.sh` scans `knowledge-base/legal/**`. So a trigger condition phrased as a path shape — "any path not under `knowledge-base/` and not `*.md`" — would tell the next editor that a `knowledge-base/**/*.md` path is safe to add, which is false today and false by construction for a gate this same plan adds. The drafted plan wrote exactly that condition; it is cut.

The disposition is therefore: the unreachability argument holds for this guard, the **union** is the invariant that makes it sound for the route, and Guard 2 computes the union over the surfaces this PR actually creates rather than a single membership test. ADR-139's amendment carries that invariant as its decision, not as a footnote — because ADR-139's own sharpest paragraph is about precisely this failure, and because the discipline it mandates currently exists **only in prose**: `required-checks-canonical-parity.test.sh` Test 8 is hardcoded to one gate and one script path, and no CI assertion enumerates content-scoped gates anywhere.

Two consequences the amendment must record as accepted rather than discover later. **The recovery lever is asymmetric:** a dedicated context can be temporarily lifted from `infra/github/ruleset-ci-required.tf` in a bounded, reviewable diff; `test` cannot be lifted without un-requiring every unit test in the repository, so the only recovery from a bad merge is revert. Combined with this guard's **inverted** highwater, an ordinary refactor that deletes a Management API call site drops the census below the floor and reds `test` on every open PR until the floor moves in the same commit. **And the cheap path bypasses a real control:** adding a name to `required-checks.txt` is a four-file CODEOWNERS-gated diff a reviewer cannot miss; adding a `run_suite` line is one line in a 2,162-line file. Legitimising the cheap path without replacing that control is a decision to stop having one, so the compensating control ships with the permission.

**W6 — where the determinations land. The CLO ruling reshaped this workstream; what follows is the ruled design, not the drafted one.**

*The determinations do not go in the Article 30 register at all.* Art. 30(1) enumerates a closed list of limbs (a)–(g) and breach documentation is not among them; Art. 33(5) is a separate obligation with a separate verification purpose, and CNIL practice keeps a *registre des violations* distinct from the *registre des traitements*. Putting the index inside the Art. 30 body would invite the reading that Jikigai treats Art. 33(5) documentation as an Art. 30 limb — an error that costs credibility in an Art. 58(1)(a) exchange.

The corpus already carries this exact precedent, which is what settles it: `knowledge-base/legal/article-30-2-register.md` exists as a separate file for Art. 30(2) records, and the Art. 30(1) register says in terms that it is scoped to controller capacity only. So: a new canonical `knowledge-base/legal/breach-register.md`, with a short pointer under `## Register Maintenance` in `article-30-register.md`. **No new PA**; PA-36 stays free. The new register's title and scope must disclaim the collision with **#3686**, which proposes a durable `security_events` runtime table citing the same article — a *runtime event* surface, complementary to this *determination* index, and the corpus must not grow two things called "the Art. 33(5) register".

*An index, not a transcription.* Art. 33(5) requires documentation of the facts, effects and remedial action, and the canonical audits already do that. Duplicating them mints a second copy that drifts, and the repo's gates measure agreement rather than truth — two byte-identical copies of a stale sentence pass everything. An index with stable canonical paths discharges the "enable the supervisory authority to verify" limb. Rows must nonetheless be self-sufficient on notifiability, so the column set is: date · event · PA(s) touched · **awareness anchor (the Art. 33(1) 72-hour clock origin)** · determination · **Art. 33 engaged?** · **Art. 34 engaged?** (two columns — they are different tests) · **evidentiary limbs inconclusive?** · canonical source.

*The inclusion predicate is stated in prose, or "every determination" is unfalsifiable and the gate reds on 101 files.* An event is indexed when a breach-shaped fact pattern — an actual or suspected security event touching personal data — was assessed against Art. 4(12) and a determination recorded. A PIR's `art_33_triggered: false` on an availability-only or credential-only incident is a **screening output, not a determination**, and is excluded. Measured: 114 files repo-wide carry `art_33_triggered` frontmatter, 101 of them post-mortems generated from `templates/pir.md`. Six files under `knowledge-base/legal/audits/` carry an express Art. 4(12) / Art. 33 determination — not four, as this plan first recorded.

*The 2026-06-29 fence is not transcribed.* Two grounds. It is a signed, dated instrument whose integrity comes from being unamended, and copying it mints a second artifact bearing the same signature block without a signature. And a register entry is a live representation to a supervisory authority, not an archival copy — reproducing *"Retained edge/auth logs show zero REST/GraphQL/auth traffic"* under any heading represents that the controller currently believes it. The row is a summary carrying the correction inline and pointing at the unamended canonical.

*And the existing correction is itself incomplete, which this plan must fix rather than inherit.* The fenced record names **"edge/auth logs"**; the 2026-08-26 addendum corrects `edge_logs` only and is silent on `auth_logs`. `knowledge-base/engineering/operations/references/supabase-management-api-log-contract.md` records the instrumented 30-day sources as `supavisor_logs`, `postgres_logs`, `postgrest_logs` and `auth_logs` — with `edge_logs` absent entirely. So `auth_logs` **is** instrumented and its zero retains weak evidentiary value the addendum does not credit. Decisively: **`postgrest_logs` is the instrumented source that records REST traffic on that project, and it was never queried** — `knowledge-base/project/specs/feat-one-shot-inngest-prd-rls-enable/gate-g-escalate-evidence.md` records exactly two sources consulted, `edge_logs` and `auth_logs`, both zero. The determination attributed REST-absence evidence to the one source that does not emit, while the source that does was not consulted and is now unrecoverable for that window. The verdict is unaffected — it rests on the never-published key, and the limb was already INCONCLUSIVE — but it changes what the register may honestly say. A **second annotation-only addendum** is appended to the canonical record and to both siblings the 2026-08-26 addendum names, or the corpus drifts three ways.

*The placeholders resolve to honest prose, and two of them do not resolve to numbers at all.*

- `__TBD_DPA_DATE__` — **and the word "signed" goes with it.** The cell reads "signed `__TBD_DPA_DATE__`" in a DPA-status column beside `SIGNED 2026-03-19` rows, so a reader scanning the column reads Better Stack as covered. Swapping only the token while leaving "signed" is the overshoot failure in pure form. It becomes `NOT EXECUTED — no Art. 28(3) instrument recorded`, citing **#7529** (OPEN, `compliance/critical`), noting that reliance predates the registry emitter by ~3 months and that no vendor snapshot exists under `knowledge-base/legal/data-processing-agreements/` (which holds `anthropic.md` and `flagsmith.md` only), with the 2026-11-13 re-evaluation date. **The plan's earlier instruction to file that issue was wrong: it is already filed.** What is stale is `compliance-posture.md`'s directive sentence, which still says the escalation "has never been filed" — leaving it while adding a cross-reference produces a fresh instance of the exact defect the cell complains about. Narrow the directive to its substantive limb.
- `__TBD_BETTERSTACK_RETENTION__` — **not resolvable to a number, and the plan stops trying.** Retention is a function of plan tier; `knowledge-base/operations/expenses.md` records the account moved off free tier on 2026-08-16, that the tier *name* is explicitly not verified and recorded as unknown rather than guessed, and that the Telemetry API exposes no usage or billing endpoint (`/usage`, `/billing`, `/sources/<id>/usage` all 404). `hr-no-dashboard-eyeball-pull-data-yourself` closes the dashboard and `hr-no-ssh-fallback-in-runbooks` closes the host. The `~3 days` comment in `apps/web-platform/infra/inngest-server-flip-guard.sh` must **not** be used: it is a free-tier figure predating the upgrade. Art. 30(1)(f) says "**where possible**" — an honest `NOT RECORDED`, with the reason and the unblocking condition (`expenses.md` `verify_by=2026-09-16`; #7529), is compliant; a guessed number is not.
- `__TBD_OBSERVED_VOLUME__` — **the cell asks the wrong question.** What (f) needs is the envisaged time limit, and a capacity-bounded ring buffer has none: duration is load-dependent. State the mechanism (30 MB = `max-size=10m × max-file=3`, pinned in `apps/web-platform/infra/cloud-init.yml`), state that duration varies with instantaneous emission rate, and cite the one emission measurement available by API — `expenses.md` records the web container at ~101,000 rows/day of ~135,316 total (2026-08-17, #7577) — with the caveat that those are rows on the journald→Vector→Better Stack plane, a different surface from the container's own json-file buffer, and that rows are not bytes, so it bounds an order of magnitude rather than MB/day. The **second** occurrence is not a measurement: it is the Better Stack sentence's phrase "mirrors the `__TBD_OBSERVED_VOLUME__` pattern", and must be rewritten as a cross-reference or the gate is satisfied by a substitution that leaves the sentence meaningless. The cell's parenthetical "post-merge operator measurement" is an unactioned operator deferral inside a statutory record and is removed, not restated.

*What the register carries instead of the forbidden retention measure.* The non-scope holds, and the 2026-06-29 record's own FOLLOW-UP already reached the same conclusion in terms — so the register must not now contradict it. Two entries land in PA-8, which already claims at §(b)(ii) to anchor the Art. 33 72-hour clock:

1. **A recorded limitation on the Art. 33 evidentiary chain**, in §(g): that on Supabase projects `edge_logs` may be uninstrumented and return zero without that zero being evidence, that the Management API log endpoint returns HTTP 200 with `error: null` over windows it truncates non-monotonically and does not enforce its documented 24-hour cap, and that access-log evidence from this surface is corroborating only and must carry a coverage verdict. Recording a limitation you have measured is what Art. 5(2) looks like when the news is bad, and it is a stronger posture than a technical measure because it is defensible.
2. **The durable-sink remediation, named as open**, citing **#5697** — which is the existing tracker for the 2026-06-29 record's FOLLOW-UP condition, and which this plan had implied was untracked.

*The untranscribed state is an Art. 5(2) deficiency and nothing more.* It is not an Art. 33(5) breach (that article prescribes no register form; per-incident documentation discharges it) and not an Art. 30 gap (the limbs are closed). Accountability means being able to demonstrate, and documentation that cannot be enumerated cannot be demonstrated on request. It is recorded in a dated provenance preamble that remedies it in the same breath, and **not escalated further** — over-recording self-identified housekeeping as a statutory deficiency creates an admission in a document a regulator will read, for zero compliance gain.

**W7 — the design decision.**

The repair is a **second producer keyed on the `test-<name>.sh` basename convention**, which is what `scripts/lint-orphan-test-suites.sh`'s own header prescribes: *"closing it needs a second producer keyed on the `test-*.sh` convention."* It is a second producer rather than a widened walk because the existing producer's suffix is load-bearing as an opt-in signal — ADR-161 records a mutation battery deliberately **not** named `*.test.sh` so the auto-glob would skip it — and because `test-` as a bare prefix is ambiguous in a way the suffix is not.

The ambiguity is the whole design problem, and it is enumerated rather than hand-waved. Repo-wide, 82 tracked paths match `/test-*.sh`, and the non-suites among them are:

- `tests/scripts/lib/*.sh` (17 files) — **production gate implementations**, `source`d from `.github/workflows/apply-web-platform-infra.yml` at 17 sites and executed as `bash …/preapply-entrypoint-gate.sh --gate`. Not tests.
- `scripts/lib/test-relevance-paths.sh`, `scripts/lib/test-contention.sh` — libraries, `source`d.
- `plugins/soleur/test/test-helpers.sh` — the shared helper library.
- `scripts/test-all.sh` and its five `test-all-*.test.sh` siblings — the runner itself, plus suites that already match the first producer.
- `.github/scripts/test/*.sh` (11) — genuinely covered by that directory's own `run-all.sh` glob with `MIN_SUITES=11`; a second surface, not an orphan.

So the second producer is `basename` -prefixed, directory-scoped to `tests/` plus `scripts/` plus `test/helpers/`, and excludes `tests/*/lib/` and `scripts/lib/` structurally rather than by naming individual files — an exclusion keyed on a path segment survives new members; one keyed on filenames does not.

Three defects in the linter are fixed in the same change because they are the reason the gap persisted:

- The trailing `tests/commands/` comment repeats the claim *"the same gap covers `tests/scripts/`, which is floored instead by `.github/scripts/test/run-all.sh`'s own `MIN_SUITES`"* — which the file's own header already records as false. Verified again here: that runner globs `$DIR/test-*.sh` with `DIR=.github/scripts/test` and never looks at `tests/scripts/`.
- The header states `tests/scripts/` holds 45 `test-*.sh`; it holds 53.
- The `tests/commands/` loop has **no waiver mechanism at all** — `EXCLUSIONS` is only consumed against the suffix producer's orphan set. The new producer shares `EXCLUSIONS` and `DOUBLE_COVERED_ACK` rather than inheriting that gap.

### Implementation Phases

**Phase 0 — preconditions (verify, do not assume).**

*Measured at plan time, 2026-09-03, and recorded so /work re-runs them against a moved tree rather than trusting these numbers:* `bash scripts/lint-supabase-deprecated-endpoints.sh` → exit 0, `30 files enumerated, 26 Management API call sites (baseline 26), 3 waived, 0 violations`. `bash tests/scripts/test-lint-supabase-deprecated-endpoints.sh` → exit 0, `45 passed, 0 failed`. `bash scripts/lint-orphan-test-suites.sh` → exit 0, `walked 380 tracked *.test.sh against 6 registration surfaces (s1=87 s2=177 s3=106 s4=1 s5=13 s6=1) — 380 covered, 0 orphaned` — which is the finding, not the reassurance: the linter reports a clean sweep while 53 suites under `tests/scripts/` and four live orphans sit outside its producer entirely. `bash scripts/check-pa-22.sh` → exit 0. `bash plugins/soleur/test/c4-model-freshness.test.sh` → exit 0, 3 passed.

0.1 Re-derive the ADR-139 intersection with the two commands recorded in §Research Insights and paste the output into the PR body. It is a precondition, not a formality: if a `knowledge-base/` path has entered either assembly since this plan was written, W1's disposition changes from unreachability to earned-green.
0.2 Confirm `bash scripts/lint-supabase-deprecated-endpoints.sh` and `--check-highwater` both exit 0 on a clean tree. If either is red, W1 acquires a backlog-drain phase before the promotion.
0.3 Re-derive the next free ADR ordinal across every `origin/*` ref (not `origin/main`). ADR-200 is provisional. Only one ordinal is needed; the promotion-route decision amends ADR-139 in place.
0.4 Re-run the four orphan probes (`git grep -l -F <basename>` for each) — a sibling PR may have registered one.
0.5 Confirm `docs/legal/**` is absent from the working file list, so the three-way legal-doc lockstep (cross-document gate, `apps/web-platform/lib/legal/legal-doc-shas.ts` SHA pin, Eleventy mirror dates) does not fire. If any `docs/legal/**` edit becomes necessary, all three legs land in the same commit.
0.6 `bash scripts/check-pa-22.sh` — confirm it passes today, before it is wired into a runner. Wiring a red sentinel and wiring a green one are different changes.
0.7 **W3 credential precondition (GDPR-Art-32 finding).** Confirm `SUPABASE_ACCESS_TOKEN` is present and authenticating in **both** Doppler configs `postgrest-reload-schema.sh` runs under, and record its account scope. `hr-dev-prd-distinct-supabase-projects` makes this per-project, not once. A dead 401 currently makes this call a no-op; Phase 4 makes it live for the first time. If either config lacks the token, the Doppler deletion (**AC36**, post-merge — not Phase 4.4, which is the census re-run and has no gate to hold) is held until it does. **Record the token's account scope where an AC can read it**: §User-Brand Impact turns on that token not being project-scoped, and a precondition that gates this plan's only S1 user-data vector must leave evidence, not a memory.
0.8 Re-derive the PA ordinal by **enumerating** `^## Processing Activity` headings, never by reading the last one — the headings are out of numeric order (PA-17 precedes PA-16; PA-23–35 follow the Vendor Mapping and TOMs blocks). This plan creates no PA, but the enumeration is what proves it does not need one.

**Phase 1 — W6, the statutory workstream (first, and in its own commit).**

It goes first because it is the P1, and alone because a reviewer must be able to read the statutory diff without the shell diff in the way. The commit boundary is also the mitigation recorded against DC-1: it is what keeps the statutory record independently revertable from the engineering commits.

1.1 Create `knowledge-base/legal/breach-register.md` — a distinct statutory register, matching the shape of the existing `knowledge-base/legal/article-30-2-register.md` precedent. Frontmatter mirrors the Art. 30 register's conventions (`status: draft-requires-counsel-review`, CLO custodian). The title and a scope paragraph disclaim the #3686 collision: this indexes *determinations*, that proposes a *runtime event* table.
1.2 Write the **inclusion predicate** in prose, before any row: an event is indexed when a breach-shaped fact pattern was assessed against Art. 4(12) and a determination recorded; a PIR's `art_33_triggered: false` screening output is not a determination and is excluded. Without this, P7's "every determination" is unfalsifiable and Phase 7's gate has no bounded producer.
1.3 Write the dated **provenance preamble**: the determinations were made and documented at the time of each event in the canonical files cited; until this change they were enumerable only by knowing which incident to look for. Creating the index is an Art. 5(2) accountability improvement and alters, revisits and re-dates nothing. The delay is recorded rather than elided — and not escalated beyond Art. 5(2).
1.4 Index the six determinations under `knowledge-base/legal/audits/` plus the one that lives outside it (`knowledge-base/engineering/operations/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md`). Columns per §Architecture, including the awareness anchor and the split Art. 33 / Art. 34 tests. **Pin the machine-readable form of the canonical-source column here, in Phase 1** — a bare repo-relative path in a fixed column — because Phase 7's parser resolves it against disk. Authoring rows first and writing a regex around whatever they happened to look like is the fork-the-derivation shape `scripts/test-all.sh`'s own header warns against. Every claim in every cell is grep-validated against the file it came from before it lands. Rows are summaries; no fence is transcribed.
1.5 Write the 2026-06-29 row with the coverage correction inline — reachability-only, no Art. 4(12) breach, Art. 33 and Art. 34 not engaged, resting on the absent exploitation precondition; access-log limb INCONCLUSIVE and not certified clean, the `edge_logs` zero being an instrumentation gap rather than evidence.
1.6 Append a **second annotation-only addendum** to `knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md` under the same `<!-- ADDENDUM-… -->` convention, recording that the 2026-08-26 correction addressed `edge_logs` only; that `auth_logs` is instrumented and its zero retains weak value; and that `postgrest_logs` — the instrumented source that records REST traffic — was never queried and is now unrecoverable for that window. Add a **one-line pointer** to the same addendum from both siblings the 2026-08-26 block names (`knowledge-base/project/specs/feat-one-shot-inngest-prd-rls-enable/gate-g-escalate-evidence.md`, `knowledge-base/engineering/operations/post-mortems/inngest-prd-rls-disabled-exposure-postmortem.md`) — a pointer, not a third copy of the text, which is ADR-200's own principle applied to itself. The corpus must not drift three ways, and three transcriptions is how it would. State that the verdict is unaffected.
1.7 Close the pointer chain **in all three legs**, which the drafted plan claimed while editing only two. Add the reciprocal pointer from the canonical 2026-06-29 record to `breach-register.md`; a pointer under `## Register Maintenance` in `article-30-register.md`; **and — the leg that was missing — `knowledge-base/legal/statutory-response-catalog.md`**, both in its accountability-pack step (the list of documents a supervisory authority asks for first, which today names the Art. 30 register and the posture file and would still omit the breach register after this PR) and in its `related:` frontmatter. The catalog is the file the operator opens the day a regulator letter arrives; leaving it pointing where it pointed before is the loop staying open at the leg §Problem Statement calls broken.
1.8 Resolve **five** `__TBD_*` occurrences per §Architecture — two `__TBD_OBSERVED_VOLUME__`, one `__TBD_BETTERSTACK_RETENTION__` and one `__TBD_DPA_DATE__` in `article-30-register.md`, **plus the second `__TBD_DPA_DATE__` in `compliance-posture.md`**, which the drafted four-slot mapping silently omitted even though `## Files to Edit` names that file. Two resolve to honest `NOT RECORDED` prose with reason and unblocking condition, two to `NOT EXECUTED` (dropping the word "signed" in both places), one to a cross-reference. Record the producing source for every figure inline as Art. 5(2) evidence. Also fix `knowledge-base/engineering/operations/runbooks/recover-userid-from-pino-stdout.md`, which carries the same token convention.
1.9 Narrow the stale directive in `knowledge-base/legal/compliance-posture.md`'s Better Stack row: the AC15 escalation **was** filed (#7529). Retain the substantive limb — execute the instrument or record the published terms relied on under Art. 28(3). Add the Art. 33(5) register to that file's source-of-truth pointer list and add an `## Active Compliance Items` row.
1.10 Add the two PA-8 entries the CLO ruled in place of a retention measure: the recorded limitation on the Art. 33 evidentiary chain in §(g), and the durable-sink remediation named as open, citing #5697.
1.11 State the non-scope **in the register**, not only in this plan: the Supabase log surface gets no retention technical-and-organisational measure, with the reason and the citations to `supabase-management-api-log-contract.md` and ADR-197 — and note that the 2026-06-29 record's own FOLLOW-UP already reached this conclusion, so the register is not creating a new judgement.
1.12 Bump the register's `last_reviewed:`; leave `version: 0.1.0-draft` and `status: draft-requires-counsel-review` alone. Add **counsel-review item 12** to the register's numbered list: confirm the instrument choice (separate `registre des violations` vs. co-located index) under CNIL practice, and confirm the inclusion predicate that excludes PIR screening outputs.
1.13 Write the CLO attestation at `knowledge-base/legal/audits/2026-09-03-clo-attestation-7717-art-33-5-register.md` with per-artifact verdicts (the new register; each placeholder resolution; the second 2026-06-29 addendum; the compliance-posture amendment) and a DISCHARGED / BLOCKED disposition, with re-evaluation triggers in frontmatter.

**Phase 2 — W7, the orphan-suite linter (RED first). Measured complexity: hours — the drafted union design was cut in review. Blast radius: merge-blocking on arrival.**

**Read this before the design.** `scripts/lint-orphan-test-suites.sh` is **already inside the required `test` context** — `scripts/test-all.sh` carries `run_suite "scripts/lint-orphan-test-suites" bash scripts/lint-orphan-test-suites.sh` — *and* is double-executed advisorily in `ci.yml`'s `lint-bot-statuses`. An earlier draft of this plan believed it advisory. It is not, and three things follow. Its producer is a repo-wide `git ls-files`, not diff-scoped, so a merged mistake reds `test` on **every open PR at once**, including PRs touching nothing related. W7 therefore lands on the repo's most load-bearing required context, which is the strongest argument for the narrow design below rather than the union one. And the double-execution Phase 3.2 removes for the Supabase guard exists identically here — the same removal is in scope, along with the comment above it, which currently asserts "a PR can merge with it red" over three steps, one of which is this linter.

The drafted design bought P9 with a second producer, a parallel covered-set derivation across four surface extractors that hard-code `\.test\.sh`, a seventh registration surface, 21 `DOUBLE_COVERED_ACK` entries, structural exclusions and a second pair of non-vacuity floors. Both review panels fired on that scope, which is the signal to delete rather than fix. The measurement dissolves it: a **non-recursive** glob `tests/scripts/test-*.sh` covers **53 files, of which exactly 1 is unregistered** (`test-sentry-brownout-retry.sh`), and `tests/hooks/test_*.sh` covers **4, of which exactly 1** (`test_drop_sentinel_parity.sh`). Both were re-measured at plan time.

The plan had rejected *generalising* the existing `tests/commands/` loop to all of `tests/` — soundly. It never considered **instantiating that loop twice, narrowly**, which is what the measurement supports and which is the design this phase now takes.

2.1 Write the failing rows in `scripts/lint-orphan-test-suites.test.sh` from Guard 3's mutation matrix, before touching the linter.
2.2 Clone the existing `tests/commands/` loop twice — once for `tests/scripts/test-*.sh`, once for `tests/hooks/test_*.sh` — each reusing that loop's `run_suite`-command-anchored grep and its `cmd_seen` cardinality floor. Everything the union route needed falls away, and it falls away *structurally* rather than by exclusion:
  - **No exclusion list.** A non-recursive glob cannot reach `tests/scripts/lib/` (17 production gate implementations), `tests/scripts/fixtures/`, `scripts/lib/`, `plugins/soleur/test/test-helpers.sh`, `test/helpers/test-*.sh`, or `scripts/test-all*.sh`. Every class the drafted plan excluded by path segment is unreachable by construction — which is a better guarantee than an exclusion, because it cannot be widened by a later edit.
  - **No seventh surface.** `.github/scripts/test/run-all.sh` auto-globs `"$DIR"/test-*.sh` behind a `MIN_SUITES` floor, so a suite there cannot be an orphan. It was only ever going to be a "surface" because a repo-wide producer would have false-reported it — a cost the union route creates, not a property it buys.
  - **No `DOUBLE_COVERED_ACK` entries.** Double coverage is only a problem inside a union with a disjointness check. A directory loop asking "is there a `run_suite` line for this file?" is an assertion, not a union, so the 21 files registered in both `test-all.sh` and a workflow are simply registered.
  - **No parallel covered-set derivation.** The four surface extractors that hard-code `\.test\.sh` are never consulted, so they never need widening. This was the drafted phase's entire body.
2.3 Give each loop the cardinality floor the `tests/commands/` loop already uses, so a glob that silently matches nothing reds instead of passing.
2.4 Fix the three self-contradictions in the file, which are the reason the gap persisted: the trailing `tests/commands/` comment repeating the `MIN_SUITES` claim the header already records as false; the header's stale `45` (actual 53); and the `DOUBLE_COVERED_ACK` comment asserting "the check fails on any SIXTH", which the code below it contradicts.
2.5 Register the two orphans these loops find, plus the two outside `tests/` that the sweep surfaced (`scripts/test-jaccard-duplicates.sh`, `scripts/test-weekly-analytics.sh`) — read each first. A suite that has never run may be red; a red suite is registered *and* fixed, or excluded with an issue citation under the fail-closed `EXCLUSIONS` contract. It is not left unregistered.
2.6 Fold the three new chokepoint assertions into the **existing `REQUIRED_RUNNERS` array** rather than writing bespoke test rows for them. That array already asserts `run_suite` call shape for named scripts, anchors on the command rather than the label, and carries its own vacuity floor — so `scripts/lint-supabase-deprecated-endpoints.sh`, `scripts/lint-legal-registers.sh` and `scripts/check-pa-22.sh` become three entries and one floor bump, inheriting an already-mutation-tested anchor.

**Phase 3 — W1, the promotion.**

3.1 Add **one** `-live` `run_suite` registration in `scripts/test-all.sh` beside the existing `-unit` line. One line is sufficient: the guard's default `MODE=scan` already runs the ratchet — `--check-highwater` is only an early-exit branch, and the fallthrough path ends by propagating the ratchet's return code. A second line mirroring the `ci.yml` highwater step is not needed. Rewrite that comment block: the paragraph explaining why there is no `-live` line becomes the paragraph explaining why there now is.
3.2 Remove the two Supabase steps from `ci.yml`'s `lint-bot-statuses` job — decided, not left implicit. Keeping them would double-execute and, worse, leave two committed comment blocks asserting an enforcement level that is no longer true. Update the job's comments so no surviving text calls this guard advisory.
3.3 Rewrite the guard script's own `ENFORCEMENT LEVEL IS ADVISORY … NO MERGE-GATING CLAIM IS MADE HERE` header block to state the blocking level, name the context it rides, and carry the ADR-139 per-gate derivation. This repo's recurring failure is a guard whose header restates a condition it has stopped enforcing; both false comments are rewritten in the same commit as the change that falsifies them.
3.4 Add the intersection assertion (Guard 2) as **Test 9 in the existing `plugins/soleur/test/required-checks-canonical-parity.test.sh`**, not as a new file. That suite already owns the bot-PR synthetic-check contract end to end — Test 4 asserts `action.yml` derives `CHECK_NAMES` from the SSOT, and Test 8 is the ADR-139 reproduction tripwire — so the intersection belongs beside them, and putting it there is also what makes the general, parameterised-over-all-four-gates version a later edit rather than a rewrite. A bespoke single-gate file would have been built in the same PR that files an issue to generalise it. **No new anchor comment is written at the `ALLOWED_PATHS=(` site.** The drafted plan proposed one; review established that `action.yml` already carries the general instruction verbatim at that exact site — *"Before adding ANY path here, re-derive the intersection for EVERY content-scoped required check, and note that reachability can also widen without touching this array."* A Supabase-specific restatement of an instruction already standing where the editor will be standing adds nothing and dilutes it. Test 9 makes the general instruction mechanical, which is what was actually missing.
3.5 *(folded into 3.4)*
3.6 Amend ADR-197's promotion paragraph, which currently says promotion "requires reproducing the gate in the bot-PR composite action's preflight … adding the job to `required-checks.txt` and to the ruleset". That sentence is what this plan's re-derivation supersedes; leaving it hands the next reader a route this PR deliberately did not take.
3.7 Note on the merge-gate's newly load-bearing waiver: `advisors/security|WAIVED-2026-08-26` never expires — the waiver field is compared only against the literal `NONE`, and there is no date arithmetic in the script. **No expiry is added**, because a hard expiry would red CI on a date certain and force a migration the vendor has not made possible. The consequence is recorded on the W2 tracking issue instead: the deferred spec-diff poller is now the only mechanism that would ever surface a successor or a sunset for this waiver. Recorded as DC-3.

**Phase 4 — W3, credential unification.**

4.1 Migrate `apps/web-platform/scripts/postgrest-reload-schema.sh` and its `.test.sh` to `SUPABASE_ACCESS_TOKEN`; update the comment in `apps/web-platform/scripts/run-migrations.sh` and the line in `apps/web-platform/docs/migration-rollback.md`.
4.2 Leave `SUPABASE_PAT` in the guard's arm-2 assembly regex. Removing it would make a resurrected use invisible to the guard — the assembly is keyed on caller shape precisely so it enumerates shapes we do not want.
4.3 **Keep `apps/web-platform/scripts/run-migrations.sh` in the assembly.** It is a member *only* because of its `SUPABASE_PAT` comment, and it sits on the arm-2 `ALLOWLIST`. Silently removing the mention drops the file from the union (30→29) and leaves a live allowlist entry matching no file — and `ALLOWLIST-STALE` fires only when `file_sites > 0`, so **there is no check for an orphaned allowlist entry at all**. Rewrite the comment to name `SUPABASE_ACCESS_TOKEN`, which is also an arm-2 key, so membership is preserved by the new name — **and update that file's `ALLOWLIST` entry reason string in the same edit**, since it reads "comment about a missing SUPABASE_PAT never failing the run" while the array's contract is a reason verified by reading the file. Preserved membership with a false reason is the comment-drift class Phase 3.3 exists to fix. **The drafted plan also added an orphaned-allowlist-entry check to the guard; review cut it** — it serves no property in P1–P9, and this phase explicitly preserves membership, so the PR creates no orphan for it to catch. Adding a detector for a condition the same phase prevents is the definition of the scope creep this plan's own Cut List exists to refuse. Recorded in §Alternative Approaches as considered-and-cut.
4.4 Re-run `--census`; it should stay 26, because the census counts call constructs and a variable rename adds and removes none. Confirm the union count too. If either moves, the highwater moves in the same commit with the reason attached — a drop is the failure, per that file's inverted direction.
4.5 **The Doppler deletion is deferred to post-merge and lives solely at AC36 — this step is a placeholder that executes nothing.** The drafted plan put the deletion here with "after 4.1 lands", which reads as *commits*, while AC36 reads as *merges*; only one can be right, and the pre-merge reading breaks `main`: deleting the secret from live `soleur/prd` while `main` still carries a script reading `SUPABASE_PAT` leaves any run on `main` — or a revert of this PR, which §Risk Analysis explicitly contemplates — pointing at a deleted secret. Record the deletion. Do not rotate it: #6489 established it is a stale 401 and the grep in 4.1 establishes nothing reads it. Note that `postgrest-reload-schema.test.sh` asserts on the literal string `SUPABASE_PAT` in its T1 pass condition and sets it in five stub invocations — it changes in the same commit or T1/T2 red.

**Phase 5 — W4, the C4 element.**

5.1 Add `supabaseMgmtApi` to `model.c4` as a top-level `system` sibling of `platform`, `#external` first then `description`, matching the block's existing shape. The existing `platform.infra.supabase` is a `database` **inside** the boundary with no `#external` tag — the data plane. This element is the control plane at `api.supabase.com`, a distinct surface with a distinct credential and distinct callers; the two are not the same vendor edge.
5.2 Add the relationship edges for the real callers — the CI workflows that hold `SUPABASE_ACCESS_TOKEN` and the Inngest cron functions that call the host.
5.3 Add the element to the include lists of **both** views it must render in, and confirm **both endpoints** of every new edge are in the same view's list. `views.c4` records two prior incidents (#7332, ADR-182/#7471) of a node added to one view whose edge endpoints were in another, shipping a disconnected box.
5.4 **Keep numbers out of the new edge descriptions.** `plugins/soleur/test/c4-count-parity.test.sh` guards numeric counts embedded in edge-description prose against live derivations; a count in a description makes it a parity subject and a maintenance liability.
5.5 `bash scripts/regenerate-c4-model.sh` and commit `model.likec4.json` in the same change; `lefthook.yml`'s `c4-model-regenerate` hook stages it, and `plugins/soleur/test/c4-model-freshness.test.sh` byte-diffs it — a suite discovered only by the full `test-all.sh` run, not by any touched-file set. Refresh `c4-model.md` if the rendered page changes.

**Phase 6 — W5, the `triggers:` shape pin and corrections.**

6.1 Pin the parseable block shape in `plugins/soleur/skills/incident/SKILL.md` Phase 3 — **four shapes, not two, and the two the drafted plan missed are the ones the skill's own emitter produces.** Measured across the 102 post-mortems carrying the key: 97 use a column-0 `triggers:` with a two-space block sequence; 1 uses inline-flow `triggers: []`; **3 emit `triggers:` followed by an indented `[]` on the next line**; and one emits `triggers:` followed directly by the next key. The last two shapes come from `plugins/soleur/skills/incident/templates/pir.md`, whose `triggers:\n{{TRIGGERS_LIST}}` renders an empty substitution as a bare key — and the failure 6.1 names for the inline case, a block-sequence scanner falling through into the next key's values, applies verbatim to them. Either pin all four shapes, or fix the emitter to always write `triggers: []` when empty and pin two; the emitter fix is one line in `templates/pir.md` plus its `scripts/dry-run.sh` counterpart, and is the better answer because it shrinks the contract rather than the scanner. **Both emitter files enter `## Files to Edit` either way** — a shape pinned in the skill that its own generator does not satisfy is the artifact-without-mechanism failure this plan is named after.
6.2 Correct the line-22 directory convention. It claims PIRs do not carry `triggers:`; measured, **102 of 113** post-mortems do, because `templates/pir.md` emits the key. The discriminator is the directory, not the key.
6.3 Widen Phase 3's scan scope to include `knowledge-base/legal/runbooks/` — **decided, not left as a fork**, and the widening is only half the work. Measured: the one runbook there, `dsar-accountless-ex-member.md`, carries **no `triggers:` key at all**, so widening the scan alone routes nothing and buys no property. Add a curated `triggers:` block to that runbook in the same change. And widen `plugins/soleur/skills/incident/scripts/dry-run.sh`, which hard-codes the runbook directory — leaving the harness on the narrow scope while the skill moves is how the two silently disagree.
6.4 Fix the fallthrough condition, and the two neighbouring undefined branches while standing there: the selection prompt offers index `0` against a list rendered `1.`/`2.`/`3.`, so `0` refers to nothing; and "top-3" is undefined when one or two runbooks match. Phase 3 currently says *"If 0 runbooks have a `triggers:` frontmatter block"* — a global-zero test, and that condition can no longer fire, since two runbooks carry the key. It does not say what to print when runbooks carry triggers but nothing scores, which is now **every** incident that is not a breach-access-log symptom. That undefined branch, not the 66-file backfill, is the operator-facing hole.
6.5 **Reconcile the three incompatible `triggers` vocabularies, which currently make a security-relevant branch unreachable.** The skill uses one name for three different things: runbook `triggers:` frontmatter holds **natural-language symptom phrases** (the sole exemplar carries nine, e.g. `anon key exposed`); Phase 3 states that selected runbook **slugs** auto-populate Phase 4 `triggers[]`; and Phase 4's secret-leak preamble fires only if `triggers[]` contains one of the **snake_case tokens** `api_key_leaked`, `credentials_exposed`, `token_exposed`, `secret_in_logs`. A runbook slug is never equal to a snake_case token, so **`{{SECRET_LEAK_PREAMBLE}}` cannot fire from Phase-3 routing at all** — and it is the redaction warning that guards a credential-leak incident report. Decide one vocabulary and make the three sites agree, or state the mapping explicitly. Note the same vocabulary question governs how the deferred 66-runbook backfill should be written, which is a further reason the shape work precedes the data work.
6.6 **Point the determination producer at the new register.** `/soleur:incident` writes `art_33_triggered` into post-mortems and contains **zero references to any register** at any line — so a future genuine `art_33_triggered: true` determination would land in `post-mortems/`, which Phase 7.1(c)'s producer deliberately excludes, and nothing would index it. That is this plan's own thesis reproduced one directory over: a control that exists as an artifact and not as a mechanism. Phase 6 is already editing this file, so the fix is a line in the skill instructing a `true` determination to be indexed into `knowledge-base/legal/breach-register.md` — closing the producer→register loop for determinations that do not exist yet, which is the only kind the gate will ever face.
6.7 Update the census figures the skill and #7716 both quote: 68 runbooks, 2 carrying the key, 1 non-empty; 102 of 113 post-mortems carrying it; 1 legal runbook out of scope.

**Phase 7 — register gate, ADRs, deferral issues.**

7.1 Create `scripts/lint-legal-registers.sh` + its `.test.sh`, built to the CLO's ruled design rather than the drafted one:
  - **(a) Assert the token class, not three known names — with a waiver, because the predicate is RED on `main` today.** `__TBD_`, `TBD`, `TODO`, `XXX`, `FIXME` **scoped to the register files, not the whole corpus** — `article-30-register.md`, `article-30-2-register.md`, `breach-register.md`, `compliance-posture.md`. The drafted plan scanned all of `knowledge-base/legal/**`, which is a *working-document* tree: `audits/` holds 41 counsel reviews that legitimately use an unresolved marker for an open counsel question, so a corpus-wide gate would red the required context on every future counsel review. It also contradicted the same script's other half, which deliberately scopes its producer to `audits/**`. One script taking opposite scoping decisions in its two halves is the defect, and narrowing (a) to the registers resolves both. Measured at plan time: **8 matches across 4 files**, not the 5 across 2 the drafted plan assumed. Two live in `knowledge-base/legal/audits/2026-08-counsel-review-7440.md` as `#<TBD>` — and one of them reads `` `#<TBD>` correctly resolved to **#7500** ``, a meta-reference that **cannot be made token-free without falsifying the sentence**; the other is a live marker inside a dated counsel-review artifact, exactly the instrument class W6's own reasoning says must stay unamended. A third lives in `knowledge-base/legal/runbooks/dsar-accountless-ex-member.md`. Under the register scoping, the two counsel-review hits fall out of scope by construction rather than by waiver — which is the right outcome, because one of them is unamendable and the other sits in a signed instrument. The runbook hit is brought into `## Files to Edit` and resolved. Additionally narrow the predicate to **standalone unresolved markers**, excluding backticked and inline-code occurrences, so a register that documents its own convention stays writable; and give the guard a waiver in the repo's **existing** `path | reason citing #NNNN` shape — the same shape as `EXCLUSIONS`, `DENY` and `ALLOWLIST`, not a tenth novel one. Target zero is the goal state, reached by resolution or by a cited waiver, never by a silent narrowing.

  - **(a″) Land the whole of `lint-legal-registers.sh` ADVISORY for one merge cycle, then promote.** It is the **first** corpus-level lint over `knowledge-base/legal/**` — nothing structurally lints that tree today; every wired legal lint targets `docs/legal/` and its Eleventy mirror, and the only KB-legal reach is a six-site explicit list in `apps/web-platform/test/legal-doc-consistency.test.ts` plus the single-file `tenant-dpa-register-guard.sh`. A first-of-its-kind gate whose scope was designed rather than measured should not go straight onto the one required context that cannot be un-required. One cycle advisory measures the scope; promotion is then a one-line change with evidence behind it. Record the promotion as a follow-up with its trigger, not as a hope.
  - **(a′) Put the accepted-resolution shape in the guard's own FAILURE MESSAGE, not in a note somewhere else.** Without it the gate creates pressure to substitute plausible text for an unresolved question — and both of this plan's honest resolutions are prose, not numbers, so the gate would otherwise be the *cause* of the next fabricated date. The drafted plan mitigated this with a committed note in a different file, which the engineer who trips the gate will never read; one extra `echo` line does more than the note ever will, and it reaches the person standing at the failure. A note also cannot live under `knowledge-base/legal/**` while naming the tokens it explains — it would be red on its own gate, which is the self-reference trap. The failure message is outside the scanned scope by construction. The same constraint binds AC8.
  - **(b) Reuse `scripts/tenant-dpa-register-guard.sh` rather than re-deriving it, and mint no fifth highwater file.** A header row with no data satisfies "non-empty", and that script already solves exactly this: it exposes `count-data-rows` (documented as excluding the empty-state placeholder), `assert-populated` / `assert-empty`, resolves its target column **by name from the header row** per `cq-assert-anchor-not-bare-token`, and is fail-closed (exit 2 for "cannot decide", never a vacuous 0). Its own header records the defect the drafted plan was about to reproduce: `grep -c '^|' | test {} -ge 3` is vacuously true on an empty register, because the `| _(none yet)_ |` placeholder is itself a pipe-line. It ships a `.test.sh` and is already registered. Parameterise it (register path, placeholder literal, column name) and call it. **Drop the committed row floor entirely** — assertion (c) reds on any deleted row whose source still exists, so the floor uniquely covers only the single out-of-`audits/` post-mortem row; assert that one path literally instead. What survives from (b) is the assertion worth the most per line: **every row's canonical-source path resolves on disk**, because a determination register whose pointers rot is worse than none.
  - **(c) Invert the coverage assertion.** Do not assert coverage of a *discovered* set: 101 post-mortems carry `art_33_triggered: false` from `templates/pir.md`, and six `audits/` files carry prose determinations with no such frontmatter, so any keyword producer either captures the 101 or misses the prose — the discriminator is semantic and no regex makes a legal judgement. Instead assert integrity of the *declared* set: every `audits/**` file matching the **determination-shaped pattern — pinned literally as `4\(12\)|33\(5\)|Art\. 33`, which measured 6 of 41 files at plan time** — is either cited by the register or listed in a committed `NOT_TRANSCRIBED` waiver with a one-line reason. The pattern is pinned in the plan because its cardinality decides the gate's character: at this regex the waiver list is empty and matches the seven indexed rows exactly; anything looser makes it a 35-entry list nobody budgeted for. in the `EXCLUSIONS` / `DOUBLE_COVERED_ACK` shape this plan already uses for W7, so adding an entry is a diff a reviewer sees. Scope the producer to `knowledge-base/legal/audits/**` only, with `post-mortems/**` **explicitly excluded and the exclusion's reason committed inline**, or the next person widens it and it reds on 101 files.
7.1a **Correct the two artifacts that wiring `check-pa-22.sh` falsifies — and note *why* nothing would have caught it.** `article-30-register.md` PA-31 §(g) measure 10 states the script "is wired into **no** workflow", citing `git grep check-pa-22 .github/` as its evidence. Phase 7.2 wires it into `scripts/test-all.sh`, **not** into `.github/` — so the cited command still returns zero and the sentence stays *literally true* while its claim becomes false. That is this plan's own subject reproduced inside a regulator-facing artifact, and the cheap promotion route is what makes it silent. Update that cell and the same statement in `knowledge-base/legal/audits/2026-07-31-dpia-screening-claude-eval-fleet-and-ci.md`, and re-anchor the evidence on a command that would actually change (a `run_suite` grep over `scripts/test-all.sh`). The DPIA memo sits under Guard 4's producer scope, so its disposition is decided here rather than discovered by the gate.
7.1b **Name the register's maintaining surface in ADR-200, and wire it.** ADR-200 claims to govern every future determination; a claim with no writer is prose. Phase 6.6 points `/soleur:incident` at the register for the `art_33_triggered: true` case. ADR-200 additionally states that the `clo` agent maintains it at ship time, and the pointer is added to `plugins/soleur/skills/ship/references/register-update-pr-pattern.md`, which today names only `article-30-register.md` and would route the next register-update PR to the wrong file.
7.2 Register `scripts/lint-legal-registers.sh`, **its `.test.sh` companion**, and `scripts/check-pa-22.sh` in `scripts/test-all.sh` — **three** `run_suite` lines, not two. `SUITE_GLOBS` contains `scripts/lib/*.test.sh` but not `scripts/*.test.sh`, and the orphan linter's producer is a repo-wide `git ls-files '*.test.sh'`, so an unregistered `scripts/lint-legal-registers.test.sh` is detected as an orphan the moment it is committed and reds the required `test` context **on this PR's own diff**. Follow the repo's unit+live pair convention. taking the same cheap route W1 takes — a `run_suite` line riding the existing required `test` context, minting no new check-name ABI. Mutation-test all three: inject a violation, confirm red, remove. For `check-pa-22.sh` the mutation **must include moving the TOMs row out of the PA-22 block**, because its assertion (iv) uses an awk range whose terminator does not match the heading that actually follows PA-22 in the live register — the range spans past the Vendor Mapping and Cross-Cutting TOMs sections, so "TOMs present *inside* the PA-22 block" is not what the code checks and a naive inject-and-confirm would pass. `check-pa-22.sh` is one of the five documented instances in `2026-07-16-a-gate-that-proves-it-cannot-fail-open-shipped-its-own-proof-unwired.md`, and wiring it without driving it red would reproduce that learning rather than discharge it. This is a first instalment against #7125 — which is specifically about PA-31's 21-module membership snapshot rotting, not sentinel wiring generally — and the PR body must not read as closing it.
7.3 Write **one** ADR and **one** amendment. The drafted plan proposed two ADRs; review cut the second.
  - `ADR-200` — Art. 33(5) documentation is a **distinct statutory register**, not an Art. 30(1) limb, and is discharged by an index with stable canonical pointers rather than by transcription. Governs every future determination.
  - An **amendment paragraph under `ADR-139`'s `## Decision`** — not a new ordinal — recording that a content-scoped gate may ride the already-required `test` aggregator, with the intersection re-derived per gate and the widened `ALLOWED_PATHS` trigger condition stated. See §Architecture Decision for why minting a second ordinal here would have manufactured the inheritable precedent ADR-139 bans.
  The C4 element is a one-line diff and is recorded inside ADR-200's C4 section rather than given an ADR of its own. ADR-200 verified free across all 69 `origin/*` refs, provisional until the pre-merge re-derivation.
7.4 **File three issues, fix one inline, execute one, and label deliberately.** The drafted plan filed six. Post-MVP holds well over a thousand open issues, so filing into it is a write-only queue and six entries is a way of not deciding. Each of the three carries re-evaluation criteria and a milestone; **none carries `action-required`**, because `operator-digest` warns that labelling a non-ask spends the P1 channel's credibility and all three are engineering work. Route the DC items to `decision-challenge` so they land in the digest's informational block.

  - **The spec-diff poller (W2)** — cite the archived §"Phase 9 (PR-C)" design **and** DC-3: with the guard now merge-blocking, this is the only mechanism that would ever surface a successor or a sunset for a waiver that never expires. Milestone Phase 4, not Post-MVP, or DC-3's disclosure is decorative.
  - **The published-disclosure contradiction** — `compliance/critical`, `domain/legal`, Phase 4, and the most severe of the set. `docs/legal/data-protection-disclosure.md` §2.3(m)(i) and `docs/legal/gdpr-policy.md` both state "no off-host log shipping is configured" while the same bullet discloses Better Stack ingestion live since 2026-05-21. Two published legal surfaces state incompatible things about one processing activity, and because they *agree* on the contradiction every mirror, SHA and parity gate is green. It outranks the internal register gap this plan calls its P1. It is filed rather than folded because fixing it fires the three-way `docs/legal/**` lockstep, which is exactly what must not ride inside a statutory chore — the CLO's ruling, and the reason the split is a filing rather than a deferral.
  - **The `triggers:` curation** — titled for the **top ~10 recurring symptom classes**, not "66-runbook backfill". A 66-item issue is never picked up; a 10-item one might be, the operator only benefits on classes that recur, and the tail is likely `triggers: []` anyway. Attach Phase 6's shape spec to it, so the shape lands with its corpus.
  - **Fixed inline, not filed:** the `plugins/soleur/skills/plan/SKILL.md` §2.6 inversion, where `aggregate pattern` — the broader tier — procures *less* sign-off than `single-user incident`, and `user-impact-reviewer` hard-exits on it. It is a one-paragraph edit to a file in a plugin this PR already opens, and `rf-review-finding-default-fix-inline` plus `wg-defer-only-after-inline-triage` both bind. Filing a governance inversion into a four-figure queue is how it survives another quarter.
  - **Executed, not filed:** `gh issue edit 7125 --milestone "Phase 4: Validate + Scale"`. An issue whose entire content is "change another issue's milestone" is a work item to create a work item — and if the register is to carry Art. 33(5) determinations, its drift control stops being a Post-MVP nicety.
  - **Also executed:** add `action-required` to **#7529**. It is the one operator-facing consequence of this work — executing a Vendor DPA, or recording the published terms relied on under Art. 28(3), is something only the founder can do. Phase 1.8 writes `NOT EXECUTED` into the statutory register permanently, citing that issue; without the label the register names a gap the operator's only comprehension surface never mentions.
  - **Not filed at all:** the general `ALLOWED_PATHS ∩ SCAN_DIRS` capability gap. Guard 2 covers the surfaces this PR creates, and filing an issue to generalise a mechanism in the same PR that hand-builds its special case is the shape review cut from Guard 2 itself. Record the count honestly wherever it is next raised: it is not the second such derivation but roughly the eighteenth once `test`'s members are counted.

## Alternative Approaches Considered

| Option | Verdict |
|---|---|
| **W1 via a new required context** — extract a `supabase-endpoint-guard` job from `lint-bot-statuses` and add it to `scripts/required-checks.txt`, `scripts/ci-required-ruleset-canonical-required-status-checks.json`, and `infra/github/ruleset-ci-required.tf`. This is what #7716 prescribes. | **Rejected.** No property delta against the kept path — both make the guard merge-blocking on human PRs and both leave bot PRs on a synthetic green resting on the same empty intersection. It costs a permanent public-ABI obligation (`infra/github/ruleset-ci-required.tf`: *"a workflow job rename … silently un-requires the check until this resource is updated in the same PR"*) and a live ruleset mutation on merge via `apply-github-infra.yml`. The #6882 precedent extracted a job because promoting `lint-bot-statuses` would have promoted five unrelated advisory linters and silently reversed ADR-129 — a bundling problem the `test-all.sh` route does not have. Recorded as a genuine fork; if the panel disagrees, the four-file fan-out is a bounded, well-precedented change and this plan's Phase 3 becomes that instead. |
| **W1 via a non-15368 `integration_id`** (the issue's "exclude from synthesis" option) | **Rejected**, on the #6882 brainstorm's finding: an Actions job always reports as 15368, so requiring the context under any other id leaves no producer on bot PRs and stalls every one of them pending forever. It is a deadlock, not an exclusion. |
| **W1 with the Phase-4 preflight reproduction** (#7716 step 1) | **Rejected on the re-derived intersection**, which is empty — the applicable precedent is `marketplace-manifest-guard`'s unreachability, not `credential-path-guard`'s earned green. Replaced by a mechanical tripwire rather than by prose, because ADR-139's own lesson is that an argument resting on an unwatched invariant is not a control. |
| **The orphaned-allowlist-entry check in the deprecated-endpoint guard** | **Cut.** The CTO surfaced it as a real fail-open — `ALLOWLIST-STALE` fires only when a file has sites, so an entry matching no file is invisible. But it serves no property in P1–P9, and Phase 4.3 explicitly preserves the membership that would create one, so the PR generates nothing for it to catch. Measured: all 11 allowlist members are in the assembly today. Adding a detector for a condition the same phase prevents is the scope creep this plan's Cut List exists to refuse; if it is worth doing it is worth doing where it is the subject. |
| **W7 by generalising the `tests/commands/` loop** | **Rejected.** Smallest diff, but that loop has no waiver mechanism at all and would need per-case exclusions for `tests/scripts/lib/`, `tests/scripts/fixtures/`, `tests/hooks/test_*.sh` and the three `python3 -m unittest` registrations — reproducing the ambiguity problem inside a construct that cannot express an exception. |
| **W7 by renaming `tests/**` to `*.test.sh`** | **Rejected.** Makes the existing producer cover it for free, but touches ~60 files, two workflows, `.github/CODEOWNERS`, and two of five `RELEVANCE_ARRAYS` entries — and collides with ADR-161, which deliberately uses the absence of the suffix as an opt-out signal. A rename would silently opt those files back in. |
| **W7 by adding `tests` to `EXPECTED_SUITE_ROOTS` alone** | **Rejected.** Reds immediately and permanently: that check is derived from the suffix producer, and zero `*.test.sh` files exist anywhere under `tests/`. Only meaningful paired with the second producer, and the second producer makes it redundant. |
| **W5 shipping the 66-runbook backfill in this PR** | **Deferred, tracked.** Each runbook needs curated symptom phrases, and the committed counter-exemplar establishes that `triggers: []` is the correct answer for tool-documenting runbooks — so it is 66 judgement calls, not a sweep. A 66-file diff in the same PR as a P1 statutory amendment makes the statutory amendment unreviewable. The cheap half (P6, the shape pin) ships here and is a precondition for doing the backfill correctly. |
| **W6 landing as its own PR** | **Recommended by two independent reviewers and NOT applied — recorded as DC-1, because splitting operator-requested scope is a User-Challenge this pipeline does not decide on its own.** The plan's original ground for bundling (the review panel is composed by label, so the legal reviewers are in the room either way) is correct and, as the CPO pointed out, is simultaneously the reason bundling buys nothing — the same panel travels to a standalone legal PR. The plan's original *mitigation* — Phase 1 as an independently revertable first commit — is **false and was falsified during review**: `ship` queues `gh pr merge --squash --auto`, and `origin/main` carries no per-PR merge commits, so a squash collapses every phase into one commit and there is no statutory commit to revert independently. The coupling between a statutory record and a CI-guard promotion is therefore real and unmitigated, and the plan says so rather than papering it. Phase 1 stays a separate commit for readability of the statutory diff only. |
| **Adding no gates at all** | **Considered, and it is the frame that makes every cut above the default.** `ADR-131-gate-moratorium-and-meta-work-budget.md` sits on `main` at `status: proposed` and argues that each new gate is a permanent issue generator with an unbounded tail cost against a one-time benefit. It does not bind, but a plan that adds two lint scripts and four guard contracts owes it the argument rather than silence. The answer: three of the four guards make an *existing* silent failure loud rather than adding a new class of work — the promotion, the orphan loops and the register sentinel each replace a control that already exists as an artifact — and the fourth (the intersection tripwire) converts a prose argument that four fabricated bot-PR greens already depend on into an executable one. The moratorium's cost model applies to gates that invent a new obligation; these formalise obligations already claimed. Where it did bind, it won: it is why `lint-legal-registers.sh` lands advisory for a cycle and why the orphaned-allowlist-entry check was cut. |
| **W2 migrating the `advisors/*` callers** | **Rejected by the issue and confirmed here.** No replacement path exists in the live spec for `advisors/security` or `advisors/performance`, and neither carries a sunset date. There is nowhere to migrate to. |

## User-Brand Impact

The threshold is carried by the credential surface, not by the register. That ordering is the CPO's ruling and it is load-bearing: `plugins/soleur/agents/engineering/review/user-impact-reviewer.md` rejects an artifact line that does not name a specific user-facing thing, and "the Art. 30 register" — a regulator-facing record *about* data surfaces — fails that test. The register is why the `compliance/critical` label and the CLO panel apply; it is not why the threshold is what it is.

- **If this leaks, the user's data is exposed via:** `users.email`, `conversations`, `messages`, `api_keys.token` and `workspaces` rows in the `soleur/prd` Supabase project — reachable by an **account-level** `SUPABASE_ACCESS_TOKEN` — a token that is not project-scoped and reaches every project on the account, including the one holding user records. The vector is a future PR that redirects a PAT-bearing caller's host span past a guard that is inert or fabricated-green. `scripts/lint-supabase-deprecated-endpoints.sh` arm 2 exists for exactly this shape, and today nothing blocks a PR that introduces it: the guard runs in `lint-bot-statuses`, which is in neither `scripts/required-checks.txt` nor the ruleset.
- **If this lands broken, the user experiences:** that same merge gate reporting green while enforcing nothing. Two concrete mis-landings: the `-live` registration added while the advisory copies and their committed "this does not block" prose survive, so the repository documents two contradictory enforcement levels and the next author believes the wrong one; or the new orphan-suite producer's exclusions swallowing the very directory the producer was widened to reach. Both restore the exact state these issues were filed about, while looking fixed.
- **If this lands broken, the user experiences (second artifact):** a `knowledge-base/legal/article-30-register.md` that misstates what the controller determined — the single artifact a supervisory authority is shown, over the founder's name. The specific mis-landing to fear is a transcription that reproduces the 2026-06-29 record's *"retained edge/auth logs show zero REST/GraphQL/auth traffic"* sentence without its 2026-08-26 correction, putting an evidentiary claim the corpus has since hollowed out in front of a regulator.
- **If this lands broken, the user experiences (this PR's own change, not a future one):** W3 takes `apps/web-platform/scripts/postgrest-reload-schema.sh` from a dead 401 to a live authenticated call against the **prd** project for the first time. It is a behaviour change, not a rename. The blast radius is bounded — the request body is the fixed literal `{"query":"NOTIFY pgrst, 'reload schema';"}`, not caller-supplied SQL — but a first-time live use of an account-level credential on the migration path is this PR's own exposure, and Phase 0.7 gates it in both Doppler configs before Phase 4 lands.
- **If this leaks, the user's data-protection posture is exposed via:** `__TBD_DPA_DATE__` being replaced with a plausible date rather than the true state. That would assert an executed Art. 28(3) instrument that does not exist, for a processor already receiving journald and host metrics on a live source — converting an open, tracked question into a documented false claim.
- **Brand-survival threshold:** `single-user incident`

`requires_cpo_signoff: true`. `user-impact-reviewer` is invoked at review time per `plugins/soleur/skills/review/SKILL.md`'s conditional-agent block, and must be fed the credential artifact/vector pair above rather than the register. CLO and CPO assessments are in §Domain Review; CLO sign-off is required on Phase 1 before PR-ready.

## GDPR / Compliance Gate (Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

**Why the gate fired.** The canonical `hr-gdpr-gate-on-regulated-data-surfaces` regex does **not** match this plan's file set — `apps/web-platform/scripts/postgrest-reload-schema.sh` is not under `supabase/migrations/`, `lib/auth/`, `server/*auth*`, `app/api/`, and is not `*.sql`. The gate fires on plan Phase 2.7 expansion trigger **(b)**: a brand-survival threshold of `single-user incident` is declared. Recorded because a reader who checks only the regex would conclude the gate was skipped.

**No `Critical` finding.** The Art. 9 special-category check is the only `Critical` in v1 and it matches on new column names; this plan adds no schema. The operator-acknowledgment escalation flow does not apply and nothing is auto-written to `compliance-posture.md`.

### `GDPR-Art-32` — a dead credential is being replaced with a live one on the migration path

**Severity:** Important
**Article:** Art. 32(1)(b) — security of processing / confidentiality
**Location:** plan section `Implementation Phases` Phase 4; `apps/web-platform/scripts/postgrest-reload-schema.sh`
**Pattern matched:** bearer-credential substitution on an existing outbound call, reached from `apps/web-platform/scripts/run-migrations.sh` in `--best-effort` mode
**Why this matters:** #6489 established `SUPABASE_PAT` is a stale 401 in both `soleur/dev` and `soleur/prd`, so this call currently fails closed and the reload no-ops. Substituting a working `SUPABASE_ACCESS_TOKEN` makes it authenticate for the first time. Scoped precisely, against the script rather than the endpoint's general capability: the request body is the fixed literal `{"query":"NOTIFY pgrst, 'reload schema';"}` — not caller-supplied SQL — and only `project_ref` is interpolated, from `NEXT_PUBLIC_SUPABASE_URL`. So this is not an arbitrary-SQL surface. It is nonetheless a first-time live use of an account-level token on the migration path, and `hr-dev-prd-distinct-supabase-projects` means the precondition is per-project, not once.
**What to do:** Phase 0.7 verifies `SUPABASE_ACCESS_TOKEN` is present and authenticating in **both** Doppler configs this script runs under, and records its scope, before Phase 4 lands and before the post-merge Doppler deletion at AC36.

### `GDPR-Chapter-V` (adjacent) — a vendor row asserts an instrument that does not exist

**Severity:** Important
**Article:** Art. 28(3) — processor instrument (not Chapter V proper: Better Stack is CZ → DE `eu-fsn-3`, intra-EU, so no third-country transfer arises)
**Location:** `knowledge-base/legal/article-30-register.md` Vendor / Sub-Processor Mapping, Better Stack row; `knowledge-base/legal/compliance-posture.md` Better Stack row
**Pattern matched:** a vendor mapping cell reading `Better Stack DPA (standard EU-region terms; signed __TBD_DPA_DATE__)` against a posture row reading `PENDING`
**Why this matters:** the register's phrasing already presupposes an executed instrument and leaves only its date open, while the posture file records the instrument as unexecuted and carries a directive — never actioned — to file a `compliance/critical` issue and either execute it or record the published terms relied on as the Art. 28(3) "other legal act". Four emitters now rely on it. Resolving the placeholder to a date would harden a presupposition into an assertion.
**What to do:** Phases **1.8** (the placeholder resolution that drops the word "signed") and **1.9** (the compliance-posture directive) carry this — not 1.5/1.6, which are the Inngest determination row and its addendum. The gate's contribution is the severity and the framing: the correct output is the true state plus a filed issue, and the register cell must stop presupposing execution.

### `GDPR-Art-5e` — retention figures resolved from a revocable instrument

**Severity:** Suggestion
**Article:** Art. 5(1)(e) — storage limitation; Art. 30(1)(f) — time limits for erasure
**Location:** `knowledge-base/legal/article-30-register.md` PA-8 §(f)
**Why this matters:** `__TBD_BETTERSTACK_RETENTION__` becomes the Art. 30(1)(f) envelope for the off-host plane **and** bounds the Art. 17 argument in the same sentence ("the hash is allowed to age out per processor retention"). A measured retrievability figure is not the same thing as a contracted retention limit — the same distinction #7717 draws when it forbids a retention measure for the Supabase log surface.
**What to do:** record the measured figure **as measured**, with its producing command and date, and say plainly whether it is contracted or observed. Do not phrase an observation as a control. This is the same discipline the non-scope enforces one paragraph away, applied to the surface where a number *is* obtainable.

### `TS-05` — fixtures for the new register sentinel

**Severity:** Suggestion
**Article:** Art. 32(1)(a) — pseudonymisation
**Location:** `scripts/lint-legal-registers.test.sh` (to be created)
**What to do:** synthesize every fixture register per `cq-test-fixtures-synthesized-only`; do not copy determination prose wholesale into a fixture tree. The determinations concern infrastructure reachability and carry no data-subject identifiers today, but a fixture that is a copy of a live legal artifact rots into a second, unversioned copy of it.

**Disposition:** four findings, none `Critical`, all folded into the plan's phases rather than deferred. Re-run at `/soleur:work` Phase 2 exit per `hr-gdpr-gate-on-regulated-data-surfaces`.

## Observability

```yaml
liveness_signal:
  what: "the `test` required status context — the Supabase endpoint guard's live arm reports through it via the `test-scripts` shard, and its `--check-highwater` census floor reports alongside"
  cadence: "per pull request, per merge_group entry, and per push to main"
  alert_target: "the PR's own checks list; a red `test` blocks merge, which is the alert"
  configured_in: ".github/workflows/ci.yml jobs `test-scripts` and `test`; scripts/test-all.sh run_suite registrations"

error_reporting:
  destination: "GitHub Actions job logs for `test-scripts`; the suite name is printed by test-all.sh's run_suite wrapper, so a red `test` names which guard failed"
  fail_loud: "non-zero exit from scripts/lint-supabase-deprecated-endpoints.sh prints the finding class (DEPRECATED-NO-WAIVER, UNPINNED-HOST, HOST-SPAN-NOT-PINNED, UNRESOLVABLE-HOST, ALLOWLIST-STALE) with the offending file; the census floor prints measured-vs-baseline"

failure_modes:
  - mode: "the guard goes blind — a pathspec typo, a renamed tree, or a reworded API= assignment makes the extractor match nothing, so it prints 0 violations and looks like a clean repo"
    detection: "the committed coverage floor in scripts/lint-supabase-deprecated-endpoints.highwater — a census DROP fails --check-highwater; the direction is inverted relative to the repo's other highwater files and the header says so"
    alert_route: "red `test` context on the PR that caused the drop"
  - mode: "the promotion is asserted but not effective — the -live registration is added while the advisory copies and their 'this does not block' comments survive, so the repo documents two contradictory enforcement levels"
    detection: "Guard 1 mutation row 2 — deleting the -live run_suite line must red the linter suite; plus an AC asserting zero surviving occurrences of the advisory-claim sentences"
    alert_route: "red `test` context"
  - mode: "the bot-PR fabricated green over `test` becomes unsound because ALLOWED_PATHS gains a path inside the guard's assembly"
    detection: "Guard 2 — a committed suite that recomputes ALLOWED_PATHS ∩ assembly from both files and fails on a non-empty result"
    alert_route: "red `test` context"
  - mode: "a new suite lands under tests/scripts/ or tests/hooks/ with no run_suite line and runs in zero runners"
    detection: "Guard 3 — the two directory loops in scripts/lint-orphan-test-suites.sh"
    alert_route: "red `test` context. The linter is ALREADY merge-blocking: scripts/test-all.sh registers `run_suite \"scripts/lint-orphan-test-suites\" bash scripts/lint-orphan-test-suites.sh`, which is inside the required `test` aggregator. An earlier draft of this section called it advisory; that was wrong, and the correction changes W7's blast radius rather than only a sentence"
  - mode: "a placeholder token, a rotted canonical-source pointer, or an untranscribed determination re-enters the legal registers"
    detection: "Guard 4 — scripts/lint-legal-registers.sh plus the newly-wired scripts/check-pa-22.sh, both registered in scripts/test-all.sh and therefore inside the required `test` context"
    alert_route: "red `test` context"

logs:
  where: "GitHub Actions run logs for the ci.yml `test-scripts` job"
  retention: "90 days, GitHub Actions default for this repository"

discoverability_test:
  command: "bash scripts/lint-supabase-deprecated-endpoints.sh && bash scripts/lint-orphan-test-suites.sh && bash scripts/lint-legal-registers.sh && bash scripts/check-pa-22.sh"
  expected_output: "all four exit 0. The first prints `lint-supabase-deprecated-endpoints: OK — 30 files enumerated, 26 Management API call sites (baseline 26), 3 waived, 0 violations` and propagates its ratchet result on the same invocation (the default scan mode runs it; `--check-highwater` is only an early-exit branch, so no second call is needed). The third prints an OK line naming zero surviving placeholder-class tokens under knowledge-base/legal/, a determination-row count at or above the committed floor, and zero unresolved canonical-source paths."
```

No `credentials_required` — all four probes read tracked files from the repository and reach no network.

## Encryption Posture

Not applicable, and the detection was run rather than assumed. Phase 2.11 fires on `.tf`, `supabase/migrations/*.sql`, `cloud-init*.ya?ml`, and `docker-compose*.ya?ml` in the working file set, and on prose introducing a persistent store or a new cross-component connection. This plan's `## Files to Edit` and `## Files to Create` contain none of those patterns. W3 changes which environment variable supplies the bearer token on an **existing** HTTPS connection to `https://api.supabase.com` — same endpoint, same scheme, same pinned host span, no new connection and no new store. W6 adds text to a tracked Markdown file. Gate skipped.

## Guard Contract

### Guard 1 — Supabase Management API deprecation + host-pin guard, promoted to blocking

**Property.** No commit can reach `main` in which any tracked non-doc file calls a Supabase Management API path on the deprecation denylist without a dated inline waiver, or reaches `https://api.supabase.com`-family endpoints through a host span that is not the bare pinned literal.

**Assembly.** The property quantifies over the union of the guard's two `git grep` assemblies, computed from the repo root with the pathspec `. ':(exclude)*.md' ':(exclude)*.mdx' ':(exclude)knowledge-base/**'` — arm 1 keyed on the host literal, arm 2 keyed on `/v1/projects|SUPABASE_ACCESS_TOKEN|SUPABASE_PAT`. The **chokepoint through which enforcement must flow is the `test` required status context**, and there is exactly one path to it: `scripts/test-all.sh`'s `run_suite` registration → the `test-scripts` job → the `test` aggregator's `needs:` list. Each of those three links is a separate place the enforcement can be severed while the guard script itself stays correct and green in isolation, so the matrix targets all three rather than the script.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Introduce a caller with `API="${SUPABASE_API_HOST:-https://api.supabase.com}"` — benign-looking, and the shape arm 2's inverted quantifier exists to catch | RED |
| 2 | Delete the `-live` `run_suite` registration from `scripts/test-all.sh`, leaving the guard script untouched and the `-unit` line in place | RED |
| 3 | Add a **second** file with an unpinned host span after a first compliant one, to prove the scan does not stop at the first member | RED |
| 4 | Remove `test-scripts` from the `test` aggregator's `needs:` list, or make the aggregator tolerate a non-`success` scripts shard — the chokepoint's third link | RED |
| 5 | **Delete a call site without lowering the floor** — the census falls below the baseline. (An earlier draft wrote this row backwards, as *lowering* the integer; that direction is a **note and exit 0**, because `SITES > allowed` is legitimate growth. The row would have been written expecting RED, watched to pass, and then "fixed" by weakening something.) | RED |
| 5b | Raise the integer without adding a call site — the floor then claims coverage the extractor does not have | RED |
| 6 | Re-run the guard with the repository unchanged | PASS |
| 7 | Add a compliant new Management API caller carrying the bare pinned literal, and raise the highwater in the same change | PASS — a must-PASS that is not the canonical, differing in a way the contract explicitly permits (growth raises the floor) |

**Harness rows:**

| # | Mutation to the SUITE (not the guard) | Expected |
|---|---|---|
| H1 | Replace the body of a mutation case in `tests/scripts/test-lint-supabase-deprecated-endpoints.sh` with a no-op that records a pass | RED — a per-case floor asserts the suite ran the number of cases it claims |
| H2 | Neutralise the suite's own dispatch so it reports `0 checked` and exits 0 | RED |

### Guard 2 — ALLOWED_PATHS ∩ guard-assembly intersection tripwire

**Property.** The set of paths `.github/actions/bot-pr-with-synthetic-checks/action.yml` permits a bot PR to write is disjoint from the set of files `scripts/lint-supabase-deprecated-endpoints.sh` scans — which is what makes the unconditional synthetic green over the `test` context sound for bot PRs.

**Assembly.** `ALLOWED_PATHS` from `action.yml`, intersected against the **union** of the scan surfaces of the live gates this PR adds to or promotes within `scripts/test-all.sh` — the Supabase guard's pathspec, `lint-legal-registers.sh`'s scan root, and `check-pa-22.sh`'s target file. A single-membership test is the shape that would let the next gate through, so the assembly is the union and the chokepoint is the recomputed intersection, which fires on movement in **either** input. Each surface is read **through an accessor, never parsed out of a source file**: the guard gains `--print-pathspec`, mirroring the `--print-suite-globs` precedent that `scripts/lint-orphan-test-suites.sh`'s own header insists on (*"a contract, not a parse"*) — parsing a bash array out of a neighbour is the exact fragility this repo has already ruled against. It lands as Test 9 of `plugins/soleur/test/required-checks-canonical-parity.test.sh`, whose Tests 4 and 8 already quantify over `action.yml`, so the assembly sits beside the tests that would otherwise drift from it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a path outside `knowledge-base/` — e.g. `scripts/rule-metrics.json` — to `ALLOWED_PATHS` | RED |
| 2 | Remove `':(exclude)knowledge-base/**'` from the guard's `PATHSPEC`, widening the scanner rather than the writer | RED |
| 2b | Add a `knowledge-base/legal/*.md` path to `ALLOWED_PATHS` — safe under the drafted path-shape condition, unsafe against the union, and the row that proves the union is what is computed | RED |
| 3 | Stub the intersection computation so it reports `0 files compared` and exits 0 | RED |
| 4 | Add a **second** `ALLOWED_PATHS` member that intersects, after a first that does not | RED |
| 5 | Run against `main` unchanged | PASS |
| 6 | Add a further `knowledge-base/project/*.md` member to `ALLOWED_PATHS` | PASS — permitted by the contract; the exclusion covers it |

**Harness rows:** deleting either file-read from the suite must red it (a suite that silently defaults a missing array to empty proves disjointness vacuously); and a fixture pair with a *known* non-empty intersection must be RED, so the suite is shown to be able to fail.

### Guard 3 — orphan-suite detection over the `test-<name>.sh` convention

**Property.** Every shell test suite tracked under `tests/scripts/` and `tests/hooks/` is executed by at least one runner.

**Assembly.** Two non-recursive directory globs — `tests/scripts/test-*.sh` and `tests/hooks/test_*.sh` — each intersected against `scripts/test-all.sh`'s `run_suite` lines by the same command-anchored grep the existing `tests/commands/` loop uses. The chokepoint is that grep, and the reason the assembly is *structural* rather than a member list is that a non-recursive glob cannot reach the library and fixture directories that sit one level down; membership is decided by the shape of the glob, not by an exclusion list a later edit could widen.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `tests/scripts/test-brand-new-gate.sh` with no `run_suite` line | RED |
| 2 | Delete the `run_suite` line for an existing `tests/scripts/` suite | RED |
| 3 | Add `tests/hooks/test_another_thing.sh` with no `run_suite` line — proving the underscore loop exists and is not the hyphen one | RED |
| 4 | Point either glob at a directory that matches nothing, so the loop iterates zero times and exits 0 | RED — the cardinality floor, and the guard's own dispatch |
| 5 | Add a **second** unregistered suite after a first that is registered | RED |
| 6 | Run against the tree after Phase 2.5 registers the orphans | PASS |
| 7 | Add `tests/scripts/lib/new-gate.sh` — a production gate implementation, not a suite | PASS — unreachable by a non-recursive glob, which is the permitted difference from the canonical |

**Harness rows:** a suite-side edit that stops constructing the fixture tree must RED rather than pass vacuously over an absent directory; and the suite must carry a must-PASS fixture whose only registered suite uses the **underscore** convention, so a harness that only ever exercised the hyphen loop cannot pass.

### Guard 4 — legal-register integrity sentinel

**Property.** No unresolved placeholder token survives under `knowledge-base/legal/**`; the breach register's index exists, carries at least its committed floor of determination rows, and every canonical-source path it cites resolves on disk; and every determination-shaped file under `knowledge-base/legal/audits/` is either cited by that index or carries a committed `NOT_TRANSCRIBED` waiver with a reason.

**Assembly.** Three inputs, and the guard reads each from its defining location: (i) every tracked file under `knowledge-base/legal/**` for the token class; (ii) `knowledge-base/legal/breach-register.md`'s index table, whose cited paths are resolved against the working tree; (iii) the determination-shaped files under `knowledge-base/legal/audits/**` — **scoped there deliberately, with `post-mortems/**` excluded and the reason committed inline**, because 101 post-mortems carry `art_33_triggered: false` as a screening output rather than a determination and any producer that reaches them reds on all of them. The chokepoint is `scripts/test-all.sh`'s `run_suite` registration of `scripts/lint-legal-registers.sh` — the same chokepoint Guards 1 and 3 use, and the same one that has left `scripts/check-pa-22.sh` inert since it was written, which is why that script is registered and mutation-tested in the same change rather than left as the counter-example the register cites against itself at PA-31 §(g).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Reintroduce any member of the token class — `__TBD_X__`, a bare `TBD`, a `TODO`, an `XXX`, a `FIXME` — anywhere under `knowledge-base/legal/` | RED |
| 2 | Delete the breach register's index heading, or reduce the table to a header row with no data | RED — via `tenant-dpa-register-guard.sh`'s `count-data-rows`, which already discounts the placeholder row |
| 3 | Point a determination row at a path that does not exist | RED |
| 4 | Add a determination-shaped file under `audits/` that the index does not cite and no `NOT_TRANSCRIBED` waiver covers | RED |
| 5 | Neutralise the guard's own dispatch so it reports zero files scanned and exits 0 | RED |
| 6 | Add a **second** broken citation after a first that resolves, to prove the walk does not stop at the first row | RED |
| 7 | Widen the producer to `knowledge-base/legal/` without the `post-mortems/**` exclusion | RED — the exclusion is asserted, not merely applied |
| 7b | Remove a waiver entry while its token still stands | RED |
| 7c | Add a waiver entry with no citing issue | RED — same fail-closed contract `EXCLUSIONS` already uses |
| 8 | Run against the corpus as Phase 1 leaves it | PASS |
| 9 | Add a determination row citing a file outside `audits/` — the Sentry post-mortem — which the contract permits | PASS — a must-PASS that is not the canonical and differs in a permitted way |
| 10 | Add an `audits/` file covered by a `NOT_TRANSCRIBED` waiver carrying a reason | PASS |
| 11 | A token inside backticks or an inline-code span — e.g. a document explaining that a marker was resolved | PASS — the predicate is standalone unresolved markers, and a corpus that discusses its own convention must remain writable |

**Harness rows:** a suite-side edit that stops constructing the fixture corpus must RED rather than pass vacuously over an absent tree; and the suite must carry a must-PASS fixture that is **not** a copy of the live register, so a guard that only ever validated the real file cannot pass. Fixtures are synthesized per `cq-test-fixtures-synthesized-only` — a fixture that is a copy of a live legal artifact rots into a second, unversioned copy of it.

## Architecture Decision (ADR/C4)

### ADR

Two decisions, two records. They are in different domains and one inside the other would be lost.

- **ADR-200 — Art. 33(5) documentation is a distinct statutory register, discharged by an index.** Art. 30(1) enumerates a closed list of limbs and breach documentation is not among them; Art. 33(5) is a separate obligation with a separate verification purpose. The decision is a canonical `knowledge-base/legal/breach-register.md` with a pointer from the Art. 30 register, following the `knowledge-base/legal/article-30-2-register.md` precedent already in the corpus, discharged by an index with stable canonical pointers rather than by transcription. Alternatives recorded: a co-located `## Appendix A` inside the Art. 30 register (rejected — invites the reading that Art. 33(5) is an Art. 30 limb); full transcription (rejected — mints a second copy that drifts, and the repo's gates measure agreement rather than truth); indexing inside `statutory-response-catalog.md` (rejected — that file is a forward-looking response playbook, not a record). Governs every future determination, so it is written even though the immediate diff is one file.
- **An amendment to `ADR-139`, not a second ordinal** — a content-scoped gate may ride the already-required `test` aggregator instead of minting a public-ABI status context. The drafted plan minted `ADR-201` for this and review cut it on two grounds. The subject *is* ADR-139's subject, and this repo's convention is to amend: ADR-139 does so itself (*"This ADR **amends, and does not reverse,** ADR-092 and the ADR-031 2026-07-17 amendment"*). And ADR-139 states the intersection *"MUST be re-derived per gate — **never inherited from a prior ADR**"*, so minting a freshly-`accepted` ordinal explicitly as "the precedent a future author needs" would create the citable artifact ADR-139 forbids inheriting. The amendment carries three things the drafted ADR did not: the **aggregator-union invariant** (`ALLOWED_PATHS ∩ ⋃ scan surfaces of every live gate in test-all.sh = ∅`), which is the sound form for this route since ADR-139 contemplates only mint-your-own-context alternatives; the **compensating control** that ships with the permission, because the one-line route bypasses a four-file CODEOWNERS-gated review and legitimising it without a replacement is a decision to stop having a control; and the **accepted consequence** that `test` cannot be temporarily un-required, so a full-scan gate riding it makes a bad merge a repo-wide freeze. It also records that the route is already in use by roughly seventeen live scanners, so the amendment documents practice rather than opening a door.

Both ordinals were derived by enumerating every `origin/*` ref (69 of them), not `origin/main` — `ADR-198` and `ADR-199` are already claimed on unmerged branches and would have collided. Both remain **provisional**: re-derive immediately before merge and after every sync, and if either moves, sweep `grep -rn 'ADR-20[01]' knowledge-base/project/{plans,specs}/` in the same edit so the plan, `tasks.md` and every AC naming the ordinal move with the file.

### C4 views

The enumeration below is the C4 completeness mandate discharged: all three of `model.c4`, `views.c4` and `spec.c4` were read, and the conclusion is **not** derived from grepping the feature's own noun. Grepping `supabaseMgmtApi` returns four hits, all in archived planning docs — which is exactly the false-negative shape the mandate warns about, since the gap is named by the vendor surface rather than by the feature.

- **(a) External human actors.** None added. The Management API is machine-to-machine; no correspondent, reviewer or recipient enters or leaves.
- **(b) External systems / vendors.** **One gap, and it is the change.** `platform.infra.supabase` is modelled as a `database` *inside* the platform boundary with no `#external` tag — the data plane, described as "Users, BYOK-encrypted API keys, conversation sessions". Its siblings `operationalInbox`, `crmStore` and `inngestPostgres` are the same. **Nothing models the Supabase control plane at `api.supabase.com`** — a distinct surface, reached with a distinct account-level credential, by a distinct set of callers. `supabaseMgmtApi` is added as a top-level `#external` `system`.
- **(c) Containers / data stores touched.** None changed. `platform.infra.supabase` keeps its description and its seven inbound edges; the control plane is not that store and must not be drawn as it.
- **(d) Access relationships that change.** New edges from the CI plane and the Inngest plane to the new element, for the workflows and cron functions that hold `SUPABASE_ACCESS_TOKEN` and call the host. No existing edge changes owner or grain, and no element description is falsified by this change — checked specifically, since the mandate requires fixing descriptions the change makes untrue.
- **Rendering.** The element goes in the include lists of both views it must appear in, and both endpoints of every new edge must be in the same view's list. Descriptions carry no numbers, so `c4-count-parity.test.sh` gains no new parity subject. `model.likec4.json` is regenerated and committed in the same change.

### Sequencing

Neither record is contingent on a later slice. ADR-200's decision is true the moment `breach-register.md` exists; the ADR-139 amendment's is true the moment the `run_suite` line lands. Both are written at `status: accepted`, not `adopting`.

## Files to Edit

Every path below was confirmed to exist, and every glob this plan prescribes was expanded against the tree rather than constructed from the plan.

**W6 — statutory (Phase 1):**

- `knowledge-base/legal/article-30-register.md` — the `## Register Maintenance` pointer to the new register; counsel-review item 12; PA-8 §(f) placeholder resolutions; PA-8 §(g) Art. 33 evidentiary-chain limitation and the #5697 durable-sink item; the Vendor Mapping Better Stack cell; `last_reviewed:`.
- `knowledge-base/legal/compliance-posture.md` — narrow the stale AC15 directive (the issue **is** filed, #7529); `__TBD_DPA_DATE__`; source-of-truth pointer list; `## Active Compliance Items` row.
- `knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md` — the second annotation-only addendum, and the reciprocal pointer.
- `knowledge-base/project/specs/feat-one-shot-inngest-prd-rls-enable/gate-g-escalate-evidence.md` — the same addendum.
- `knowledge-base/engineering/operations/post-mortems/inngest-prd-rls-disabled-exposure-postmortem.md` — the same addendum.
- `knowledge-base/engineering/operations/runbooks/recover-userid-from-pino-stdout.md` — the same placeholder-token convention.

**W7 — orphan linter (Phase 2):**

- `scripts/lint-orphan-test-suites.sh`
- `scripts/lint-orphan-test-suites.test.sh`
- `scripts/test-all.sh` — four orphan registrations.

**W1 — promotion (Phase 3):**

- `scripts/test-all.sh` — the `-live` registration and the rewritten comment block.
- `scripts/lint-supabase-deprecated-endpoints.sh` — the enforcement-level header, the ADR-139 derivation, the orphaned-allowlist-entry check.
- `.github/workflows/ci.yml` — remove the two Supabase steps from `lint-bot-statuses`; correct that job's comments.
- `.github/actions/bot-pr-with-synthetic-checks/action.yml` — the tripwire anchor comment at the `ALLOWED_PATHS=(` site.
- `plugins/soleur/test/required-checks-canonical-parity.test.sh` — Test 9, the intersection assertion (Guard 2).
- `knowledge-base/engineering/architecture/decisions/ADR-197-a-zero-from-a-log-surface-is-not-evidence-of-absence.md` — the superseded promotion paragraph.
- `knowledge-base/engineering/architecture/decisions/ADR-139-earned-green-required-for-reachable-surface-content-gates.md` — the amendment paragraph under `## Decision`.

**W3 — credentials (Phase 4):**

- `apps/web-platform/scripts/postgrest-reload-schema.sh`
- `apps/web-platform/scripts/postgrest-reload-schema.test.sh`
- `apps/web-platform/scripts/run-migrations.sh`
- `apps/web-platform/docs/migration-rollback.md`

**W4 — C4 (Phase 5):**

- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/views.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` *(regenerated, not hand-edited)*
- `knowledge-base/engineering/architecture/diagrams/c4-model.md` *(only if the rendered page changes)*

**W5 — incident skill (Phase 6):**

- `plugins/soleur/skills/incident/SKILL.md` — body only; no `description:` frontmatter change, so the cumulative skill-description budget is untouched.

**Phase 7:**

- `scripts/test-all.sh` — registrations for `scripts/lint-legal-registers.sh` and `scripts/check-pa-22.sh`.

## Files to Create

- `knowledge-base/legal/breach-register.md`
- `knowledge-base/legal/audits/2026-09-03-clo-attestation-7717-art-33-5-register.md`
- `scripts/lint-legal-registers.sh`
- `scripts/lint-legal-registers.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-200-*.md` *(provisional ordinal)*
- `knowledge-base/project/learnings/<category>/<topic>.md` *(at ship time; directory and topic only — the date is chosen at write time)*

## Acceptance Criteria

### Pre-merge — W6 (statutory)

- [ ] AC1 — `knowledge-base/legal/breach-register.md` exists, carries frontmatter matching the **`article-30-2-register.md`** shape specifically — `date`, `issue`, `processor`, `related`, `status`, and no `version`/`last_reviewed`/`controller`/`dpo`/`contact`. Phase 1.1 and this criterion previously named two different shapes; they differ materially, and the 30(2) register is the precedent ADR-200 follows. and its scope paragraph names #3686 and states the determination-index / runtime-table distinction.
- [ ] AC2 — the file states an inclusion predicate in prose that expressly excludes PIR `art_33_triggered` screening outputs.
- [ ] AC3 — the file carries a dated provenance preamble framing the gap as Art. 5(2) only, and asserting that no determination is altered, revisited or re-dated.
- [ ] AC4 — the index has a row for each of the seven determinations in scope (**six** under `knowledge-base/legal/audits/` plus the one post-mortem — the same arithmetic as §Problem Statement and Phase 1.4, and no other count of this corpus appears anywhere in the plan), with columns for the awareness anchor and for Art. 33 and Art. 34 as **separate** tests. `grep -c '^|' ` over the table body is at or above the committed floor.
- [ ] AC5 — no fenced determination block is reproduced. `grep -c 'GDPR Art. 33(5) breach-documentation / near-miss record' knowledge-base/legal/breach-register.md` returns **0**; the same string still returns 1 in the canonical audit file.
- [ ] AC6 — the 2026-06-29 row carries the coverage correction inline and does not assert that retained logs show zero REST traffic.
- [ ] AC7 — the second addendum is present in all three sibling files, each naming `auth_logs` and `postgrest_logs`, and each stating that the verdict is unaffected.
- [ ] AC8 — `grep -rEo '(__TBD_[A-Z_]*__|\bTBD\b|\bTODO\b|\bXXX\b|\bFIXME\b)' knowledge-base/legal/` returns **0 matches**.
- [ ] AC9 — the Better Stack vendor-mapping cell no longer contains the word `signed` adjacent to that vendor, cites #7529, and carries the 2026-11-13 re-evaluation date.
- [ ] AC10 — `compliance-posture.md` no longer asserts the AC15 escalation "has never been filed", and retains the substantive execute-or-record limb.
- [ ] AC11 — PA-8 §(g) carries the Art. 33 evidentiary-chain limitation citing both `supabase-management-api-log-contract.md` and ADR-197, and the durable-sink item citing #5697.
- [ ] AC12 — no retention technical-and-organisational measure is recorded for the Supabase log surface; the register states the non-scope and its reason.
- [ ] AC13 — no new Processing Activity is created. `grep -c '^## Processing Activity' knowledge-base/legal/article-30-register.md` is unchanged at **35**.
- [ ] AC14 — the CLO attestation file exists with per-artifact verdicts and a disposition.

### Pre-merge — W1 / W7 / W3 / W4 / W5 (engineering)

- [ ] AC15 — `bash scripts/lint-supabase-deprecated-endpoints.sh` exits 0 and reports 26 call sites against baseline 26.
- [ ] AC16 — exactly one `-live` `run_suite` line for the guard exists in `scripts/test-all.sh`, and `bash scripts/test-all.sh --print-suite-globs` still returns its nine patterns unchanged.
- [ ] AC17 — the guard's own advisory claims are gone, asserted against the **exact committed strings** and scoped so the sibling linter's true advisory claim is not caught in the blast:
  - `git grep -c 'ENFORCEMENT LEVEL: ADVISORY' scripts/lint-supabase-deprecated-endpoints.sh` → **0** (note the colon; the script's string differs from `ci.yml`'s).
  - `git grep -c 'MERGE-GATING CLAIM IS MADE HERE' scripts/lint-supabase-deprecated-endpoints.sh` → **0**.
  - `git grep -c 'ENFORCEMENT LEVEL IS ADVISORY' .github/workflows/ci.yml` → **1**, not 0. Two occurrences exist today; the Supabase one goes with its steps.
  - **The surviving occurrence must be re-scoped, not merely kept.** It heads a block covering *three* steps — the two tempfile-cleanup steps and `Lint orphan test suites` — and asserts "a PR can merge with it red". That is already false for the orphan linter, which `scripts/test-all.sh` registers inside the required `test` context. Certifying the count at 1 without re-scoping the comment would lock in a false enforcement claim about the very linter W7 widens — the identical defect Phase 3.3 exists to fix for the Supabase guard, applied to one gate and waived on its neighbour. Scope the comment to the tempfile steps only.
  - No surviving comment in either file describes *this* guard, or the orphan linter, as non-blocking.
- [ ] AC18 — `.github/actions/bot-pr-with-synthetic-checks/action.yml` carries the tripwire anchor at the `ALLOWED_PATHS=(` site, stating the widened trigger condition (**any** path not under `knowledge-base/` and not `*.md`/`*.mdx`).
- [ ] AC19 — Test 9 asserts the **invariant**, not that the suite ran. `bash plugins/soleur/test/required-checks-canonical-parity.test.sh` exits 0; Test 9 names a non-zero count of paths on both sides; **and the suite carries a must-FAIL fixture pair with a known non-empty intersection which, when run, exits non-zero naming the intersecting path.** Without that fixture a stub that reads both arrays, prints a plausible count and exits 0 satisfies the criterion completely — which is the proxy-for-invariant shape this plan objects to elsewhere.
- [ ] AC20 — ADR-197's promotion paragraph no longer prescribes the `required-checks.txt` + ruleset route as the only path.
- [ ] AC21 — `bash scripts/lint-orphan-test-suites.sh` exits 0 with **zero** orphans, and its output names each directory loop with its enumeration count: `tests/scripts/` ≥ **53** and `tests/hooks/` ≥ **4**. A non-zero count alone is a proxy — a loop that enumerated one file in the wrong directory would satisfy it while the blind spot stayed intact.
- [ ] AC22 — each of the four orphans is **either** registered in `scripts/test-all.sh` **or** present in `EXCLUSIONS` with a citing issue, and the two sets sum to 4. The drafted AC demanded four registrations, which contradicts Phase 2.5's own sanctioned escape hatch for a suite that is red on first run — the likeliest outcome for `tests/scripts/test-sentry-brownout-retry.sh`, which has never executed and gates a live `apply-sentry-infra.yml` path. Note the count is asserted with `grep -c` over a single file, not `git grep -c`, which prints nothing and exits 1 on no match and would abort the check under `set -e`.
- [ ] AC22b — each of the four runs green individually (`bash <path>` exits 0), or its `EXCLUSIONS` entry names the issue tracking its failure. A full battery exiting 0 is not evidence for a suite that has never run.
- [ ] AC23 — the double-coverage decision is implemented and its reason is committed in `scripts/lint-orphan-test-suites.sh`; if the ACK route was taken, all 21 entries are present.
- [ ] AC24 — the three self-contradictions are fixed: the trailing `MIN_SUITES` claim, the `45` count (now 53), and the "fails on any SIXTH" comment.
- [ ] AC25 — `git grep -c SUPABASE_PAT apps/web-platform/scripts/postgrest-reload-schema.sh` returns **0**, while `git grep -c SUPABASE_PAT scripts/lint-supabase-deprecated-endpoints.sh` remains **non-zero** (the assembly key is retained deliberately).
- [ ] AC26 — `apps/web-platform/scripts/run-migrations.sh` is still enumerated by the guard's arm-2 assembly, and the guard now reports an orphaned-allowlist-entry finding class.
- [ ] AC27 — `bash plugins/soleur/test/c4-model-freshness.test.sh` exits 0, and `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0.
- [ ] AC28 — `supabaseMgmtApi` appears in `model.c4` with `#external`, and in every `views.c4` include list where an endpoint of one of its edges appears.
- [ ] AC29 — `plugins/soleur/skills/incident/SKILL.md` states the parseable block shape including the inline-flow `triggers: []` form; corrects the PIR claim against the measured 102-of-113; dispositions `knowledge-base/legal/runbooks/`; defines the behaviour for a non-empty trigger map with no scoring match; and reconciles the three `triggers` vocabularies so that the secret-leak preamble is reachable from Phase-3 routing — asserted by tracing one worked example from a runbook's frontmatter through to `{{SECRET_LEAK_PREAMBLE}}`, not by the presence of prose.
- [ ] AC30 — `bash scripts/lint-legal-registers.sh` and `bash scripts/check-pa-22.sh` both exit 0, **all three** new `run_suite` lines are present (both scripts plus `lint-legal-registers.test.sh`), **and the mutation evidence is recorded**: for each, an injected violation drove it red and was removed. For `check-pa-22.sh` the injected violation is the TOMs row moved outside the PA-22 block. Green-and-wired is precisely the state the cited learning says is indistinguishable from fail-open; the mutation is the evidence, so the AC asserts the mutation.
- [ ] AC30b — Phase 0.7's finding is recorded in the PR body: `SUPABASE_ACCESS_TOKEN` present and authenticating in both Doppler configs, with its account scope named.
- [ ] AC31 — `python3 scripts/lint-guard-contract.py` accepts this plan's `## Guard Contract`. Not `bash` — it is a Python file and `scripts/test-all.sh` invokes it with `python3`. Verified green on this plan today, so it is a regression guard rather than a target.
- [ ] AC32 — `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0 over this PR's changed docs. Run the gate's **own** invocation, not a hand-enumerated path list.
- [ ] AC33 — `bash scripts/test-all.sh` (full battery) exits 0 at the `/ship` Phase 4 checkpoint.
- [ ] AC34 — every `knowledge-base/` path cited in this plan resolves: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'` prints nothing.
- [ ] AC35 — the required `adr-ordinals` check is green. The cross-ref re-derivation is a **Phase 0.3 and pre-merge step, not an acceptance criterion**: its truth turns on what other branches have pushed, so a criterion phrased over it would be flipped by a process this plan never mentions without one line of the diff changing — the shape `cq-ac-must-not-depend-on-concurrent-sessions` forbids. What an AC can assert is the repo's own deterministic collision gate.
- [ ] AC36 — `ADR-139` carries the amendment paragraph, and no new ADR ordinal was minted for the promotion route.

### Post-merge (operator)

- [ ] AC36 — `SUPABASE_PAT` is deleted from Doppler `soleur/dev` and `soleur/prd`.
  *Automation: feasible.* Executed in-session via the Doppler CLI after Phase 4 lands and Phase 0.7's precondition has held; it is listed here only because it is a live-config write that must follow the code merge, not because a human performs it.

## Test Scenarios

### Acceptance tests (RED-phase targets)

- Given a tracked file introducing `API="${SUPABASE_API_HOST:-https://api.supabase.com}"`, when `scripts/test-all.sh scripts` runs, then the guard suite reports `UNPINNED-HOST` and the shard exits non-zero.
- Given the `-live` `run_suite` line deleted while the guard script is untouched, when the linter suite runs, then it reds.
- Given `test-scripts` removed from the `test` aggregator's `needs:` list, when the workflow-shape assertions run, then they red.
- Given a path outside `knowledge-base/` added to `ALLOWED_PATHS`, when the intersection tripwire runs, then it reds and names the intersecting path.
- Given a new `tests/scripts/test-*.sh` with no `run_suite` line, when `lint-orphan-test-suites.sh` runs, then it reports exactly that file as an orphan.
- Given a new `tests/hooks/test_*.sh` with no registration, when the same linter runs, then it reports it — proving the `test[-_]` key, not just the hyphen.
- Given `tests/scripts/lib/new-gate.sh` added, when the linter runs, then it is **not** reported (library exclusion by path segment).
- Given a `TODO` reintroduced anywhere under `knowledge-base/legal/`, when `lint-legal-registers.sh` runs, then it reds — proving the token *class*, not the three known names.
- Given a determination row pointed at a non-existent path, when the same linter runs, then it reds naming the row.
- Given a determination-shaped `audits/` file neither cited nor waived, when the same linter runs, then it reds.

### Regression tests

- Given the tree unchanged, when each of the four discoverability probes runs, then each exits 0 — and none reports a zero-item scan, which would be a vacuous pass.
- Given the `postgrest-reload-schema` suite, when it runs after the credential rename, then T1 and T2 pass against `SUPABASE_ACCESS_TOKEN` rather than the old name.
- Given `model.likec4.json` regenerated, when `c4-model-freshness.test.sh` runs, then the byte-diff is clean.

### Edge cases

- A runbook carrying inline-flow `triggers: []` must be treated as zero items, never as falling through into the next frontmatter key's values.
- A `NOT_TRANSCRIBED` waiver entry with no reason must red, matching the fail-closed contract `EXCLUSIONS` already uses.
- The guard's census must be re-measured after Phase 4, not assumed: a variable rename should move neither the 26 nor the union of 30, and if either moves the highwater moves in the same commit with the reason attached.

## Domain Review

**Domains relevant:** Legal, Engineering, Product

### Legal (CLO)

**Status:** reviewed
**Assessment:** Ruled that Art. 33(5) documentation is **not** an Art. 30 artifact and belongs in a distinct `breach-register.md`, following the existing `article-30-2-register.md` precedent — overturning the drafted co-located-section design. Ruled for an **index with canonical pointers** over transcription, with an explicit inclusion predicate excluding PIR screening outputs (without which the gate reds on 101 post-mortems). Ruled **against** transcribing the 2026-06-29 fence on two grounds — it is a signed instrument whose integrity comes from being unamended, and a register entry is a live representation rather than an archival copy. Surfaced a new finding the plan had no way to reach: the 2026-08-26 addendum corrects `edge_logs` only, is silent on `auth_logs`, and misses that `postgrest_logs` — the instrumented source that records REST traffic — was never queried, so the determination attributed REST-absence evidence to the one source that does not emit. Verdict unaffected; a second annotation-only addendum is required across three files. Corrected the plan's premise from "3 of 4 untranscribed" to "6 determinations exist, exactly 1 has zero register footprint". Ruled `__TBD_BETTERSTACK_RETENTION__` and `__TBD_OBSERVED_VOLUME__` **not resolvable to numbers** and that attempting it is the failure — Art. 30(1)(f)'s "where possible" makes an honest `NOT RECORDED` compliant. Ruled the word "signed" must go with `__TBD_DPA_DATE__`, and corrected the plan's instruction to file #7529, which is already open. Ruled the CI gate's coverage assertion must be **inverted** to declared-set integrity with a committed waiver list. Confirmed no clock starts or reopens, and that the untranscribed state is an Art. 5(2) matter only, not to be over-escalated. Requires a CLO attestation artifact and register counsel-review item 12. Confirmed the `docs/legal/**` lockstep does not fire, and separately surfaced a published-disclosure self-contradiction to be filed rather than folded in.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Endorsed the W1 fork and independently verified the two facts it rests on — `test-scripts` has no `if:` and no path gate, and the `test` aggregator fails on any shard result other than `success`, so there is no fail-open on either link. Confirmed the ADR-139 intersection is empty. Corrected the plan in the cheaper direction: the guard's default scan already propagates the ratchet, so one `run_suite` line suffices rather than two. Identified that the "no property delta" claim is wrong on **discoverability** — the three unreachability precedents hang their ADR-139 argument at their `required-checks.txt` entry and this route has none, so the tripwire must be anchored at the `ALLOWED_PATHS=(` site itself, and its trigger condition stated more widely than the single-file precedent's. Flagged that a never-expiring waiver becomes load-bearing on a required context, which raises the standing of the deferred spec-diff poller. Found a W1/W3 interaction the plan missed: `run-migrations.sh` is in the assembly only via its `SUPABASE_PAT` mention, and there is no check for an allowlist entry matching no file. Found W3 to be a behaviour change rather than a rename, gated on a live-credential precondition in both Doppler configs. Judged W7 **materially under-specified** and raised its complexity from small to medium/days, with six defects — decisively that the covered-set extraction also hard-codes the suffix, so a parallel producer alone would report 67 correctly-registered suites as orphans. Also: 21 double-covered files rather than one; three missing exclusions under `test/helpers/`; `.github/scripts/test/` is a seventh registration surface rather than an exclusion; the key must be `test[-_]` to reach `tests/hooks/`; and producer 2 needs its own non-vacuity floor and roots check. Held that the consequential architecture decision is the promotion-route precedent, not the C4 element. Noted `.github/CODEOWNERS` is `* @deruelle`, so there is no approval delta between the two promotion routes — that argument is dropped.

### Product/UX Gate

**Tier:** none
**Decision:** reviewed
**Agents invoked:** cpo
**Skipped specialists:** none — `spec-flow-analyzer` and `ux-design-lead` are not applicable and this is not a skip: the mechanical UI-surface override did not fire. `## Files to Edit` and `## Files to Create` contain no `components/**/*.tsx`, no `app/**/page.tsx` and no `app/**/layout.tsx`, and no path matches the shared UI-surface term list. `wg-ui-feature-requires-pen-wireframe` does not apply and no `.pen` is required.
**Pencil available:** N/A (no UI surface)

#### Findings

CPO ruled the threshold `single-user incident` with `requires_cpo_signoff: true`, but corrected **what carries it**: the credential surface, not the register. A register is a regulator-facing record *about* data surfaces, and `user-impact-reviewer` rejects an artifact line that does not name a specific user-facing thing — so the section leads with the account-level token pair or the review fails on shape. The register is why the label and the legal panel apply; it is not why the threshold is what it is. CPO recommended **splitting the statutory workstream into its own PR** (recorded as DC-1, not applied, because it changes the operator's stated direction), on four grounds, the strongest being a divergent rollback shape: reverting an engineering failure would silently retract a statutory record. Endorsed deferring the 66-runbook backfill and corrected the plan's justification — `/soleur:incident` scaffolds a report *after* an incident, its blocking Art. 33/34 gate runs before routing and is independent of `triggers:`, and the one runbook carrying non-empty triggers is the breach-investigation one, so routing is narrow on the right thing rather than inert. Identified the genuinely operator-facing hole as Phase 3's **undefined zero-score branch**, which is now the common case and costs one sentence rather than 66 judgement calls. Recommended re-milestoning #7125 out of Post-MVP if the register is to carry determinations, and filing the `plugins/soleur/skills/plan/SKILL.md` §2.6 inversion where the more severe tier procures less sign-off.

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| The promotion lands and the guard's own header still says it does not block, so the next author believes the wrong one. | Phase 3.2/3.3 rewrite both false comments in the same commit; AC17 asserts zero surviving occurrences. This repo's recurring failure mode, and the reason the AC is a count rather than a reading. |
| The unreachability argument silently stops holding because `ALLOWED_PATHS` gains a non-`knowledge-base/` path. | Guard 2 recomputes the intersection from both defining files; the argument is anchored where the editor will be standing, not only in a test file. |
| W7 ships a widened producer without a widened covered set and reports 67 correctly-registered suites as orphans. | Phase 2.2 makes the covered-set derivation the phase's main body; Guard 3 mutation row 5 asserts the exclusions rather than merely applying them; the linter's own suite gets must-PASS rows for the prefix convention. |
| W3 turns a dead credential into a live one on the migration path. | Phase 0.7 verifies presence, authentication and scope in **both** Doppler configs before Phase 4, per `hr-dev-prd-distinct-supabase-projects`. Scoped precisely: the request body is a fixed literal `NOTIFY`, not caller-supplied SQL. |
| A placeholder is resolved to a plausible number under gate pressure. | Both unresolvable placeholders resolve to `NOT RECORDED` prose with a reason and a dated unblocking condition, and Phase 7.1(a′) commits a note that this is an accepted resolution shape — so the gate cannot become the cause of the next fabrication. |
| The 2026-06-29 correction is inherited incomplete and the register repeats a hollowed-out evidentiary claim. | Phase 1.6 appends the second addendum across all three sibling files before the register cites it; AC6 and AC7 assert both halves. |
| A statutory record and an engineering change share a revert boundary. | Phase 1 is a self-contained first commit. The stronger mitigation — a separate PR — is recorded as DC-1 for the operator, not silently applied. |
| The ADR ordinals collide before merge. | Derived across all 69 `origin/*` refs rather than `origin/main`; AC35 re-derives immediately before merge and requires a sweep of the plan, tasks and ACs if either moves. |
| The plan's own census figures drift between planning and work. | Phase 0 re-runs every one of them, and treats a divergence as a scope change rather than a nuisance. |

## Success Metrics

- A PR introducing an unpinned host span on a PAT-bearing caller cannot merge — demonstrated by mutation, not asserted.
- `scripts/lint-orphan-test-suites.sh` reports zero orphans across both naming conventions, with a non-zero enumeration count for each producer.
- `knowledge-base/legal/breach-register.md` answers "what has this controller determined about breaches" in one file, with every pointer resolving.
- Zero placeholder-class tokens under `knowledge-base/legal/`.
- Four previously-unrun test suites run.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one names the credential artifact first, deliberately — `user-impact-reviewer` rejects a register-led artifact line on shape.
- The register's `## Processing Activity` headings are **out of numeric order** (PA-17 precedes PA-16; PA-23–35 follow the Vendor Mapping and TOMs blocks). An ordinal read off the last heading is wrong. Enumerate.
- `scripts/lint-supabase-deprecated-endpoints.highwater` is a **coverage floor with inverted direction** relative to every other highwater file in this repo. A drop is the failure. Do not lower it to make a build pass.
- `tests/scripts/lib/*.sh` are production gate implementations `source`d by a live apply workflow, not test suites. Any walk over `tests/**` that does not exclude them by path segment reports 17 false orphans.
- `apps/web-platform` has no npm workspaces root: `npm run -w apps/web-platform <script>` aborts. Use the in-package binary.
- **If the W1 promotion reds after merge, revert the Phase-3 commit only. Never revert this PR.** Commit 1 is a statutory record, and retracting it is itself a recorded event under the register's amendment contract. This instruction exists because the merge is a squash: there is no per-phase commit on `main` to revert cleanly, so the recovery is a targeted forward fix, not `git revert` of the PR.
- **The breach register creates a standing per-incident duty, enforced by a blocking check, in perpetuity.** Every future determination under `knowledge-base/legal/audits/` must be indexed or waived or the required `test` context reds. That is the right control and it is a permanent obligation on a one-person company — named here so it is approved deliberately rather than discovered the first time an unrelated PR goes red because an audit was written last week.
- **`test` is the one required context that cannot be temporarily un-required.** A dedicated context can be lifted from `infra/github/ruleset-ci-required.tf` in a bounded diff; lifting `test` un-requires every unit test in the repository. A full-scan gate riding it converts a bad merge into a repo-wide freeze whose only exit is a forward fix.
- **`git grep -c` prints nothing and exits 1 when there are no matches** — it never "returns 0". Under a `set -e` runner an AC written that way aborts instead of reporting. Use `grep -c` on a named file, or `! git grep -q`.
- **Every acceptance criterion in this plan was executed against the untouched tree before the plan was approved.** Each one fails today and would pass after the work, except AC5, AC13 and AC31, which are labelled regression guards. That dry-run is the discipline this plan most nearly failed: it derived its design mechanically and its criteria by writing down what it expected to be true, and six criteria that could not fail, could not pass, or measured a different gate than they claimed were found by running them.

## References & Research

### Internal

- Issues: #7716, #7717, #7718 (in scope); #6489 (closed by W3); #7529, #5697, #3686, #7670, #7635, #7125 (cited, not closed).
- `knowledge-base/engineering/architecture/decisions/ADR-139-earned-green-required-for-reachable-surface-content-gates.md`
- `knowledge-base/engineering/architecture/decisions/ADR-197-a-zero-from-a-log-surface-is-not-evidence-of-absence.md`
- `knowledge-base/engineering/operations/references/supabase-management-api-log-contract.md`
- `knowledge-base/legal/article-30-2-register.md` — the separate-register precedent ADR-200 follows.
- `knowledge-base/project/brainstorms/2026-07-23-lint-bot-statuses-required-promotion-brainstorm.md` — the #6882 promotion, D1–D7.
- `knowledge-base/project/plans/archive/20260902-200523-2026-08-26-feat-supabase-analytics-logs-endpoint-migration-plan.md` — §"Phase 9 (PR-C)", the designed-and-unbuilt spec-diff poller.
- `plugins/soleur/skills/ship/references/register-update-pr-pattern.md`
- Learnings: enumerated with their bearing in §Research Insights.

### Decision challenges

`knowledge-base/project/specs/feat-one-shot-7716-7717-7718-supabase-followups/decision-challenges.md` — DC-1 (CPO: split the statutory PR), DC-2 (CTO: the ADR's real subject), DC-3 (the non-expiring waiver on a now-blocking gate).
