---
title: "feat: launch-check PR-B, severity-ranked epic with sub-issues"
date: 2026-11-03
slug: launch-check-severity-ranked-epic-sub-issues
branch: feat-one-shot-launch-check-pr-b-epic-issues
issue: 11910
type: feat
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
parent_plan: knowledge-base/project/plans/archive/20261102-220428-2026-11-02-feat-customer-repo-readiness-gap-analysis-plan.md
---

## Overview

Second change for the `launch-check` skill (tracking issue #11910, which stays open: the PR body says "Refs #11910", never "Closes"). The first change (PR #11867, merged 2026-11-03) shipped the read-only scan, the baseline derived from `guards.tsv`, the living report, the redaction gate and ADR-314. This change adds the only part that writes to a customer's tracker: from a saved preview plan, create one epic and severity-ranked, domain-labelled sub-issues in the customer's OWN repository with the customer's own `gh` credentials, behind the same redaction chokepoint, idempotent on re-run.

Running the skill on a customer repo stays out of scope and gated (roadmap 4.12, executed Art. 28(3) instrument). After this change merges and 4.12 is done, the first customer run is the operator's call, and closing #11910 follows it. The launch-check blog post and feature tweet stay held (content-strategy.md held row) until a real run exists and this change has shipped. The red `affected-index-ratchet` on main is not this change's; leave it unless it blocks.

Everything below is scoped to `plugins/soleur/skills/launch-check/` plus the registry, ADR and C4 bookkeeping those files force.

## Research Reconciliation — Spec vs. Codebase

| Brief / parent-plan claim | Reality (verified in this worktree) | Plan response |
|---|---|---|
| Parent plan Guard 2: "`--dry-run` and any headless/no-TTY invocation make `gh_write` return without calling `gh`" | The shipped refusal rule is `is_headless` in `launch-check.sh` = `CI` set or `LAUNCH_CHECK_HEADLESS=1` only. An agent's Bash tool has no TTY, so a no-TTY rule would block the intended flow (skill asks the customer, then runs `--create`). The brief says "CI or LAUNCH_CHECK_HEADLESS=1". | Follow the brief and the shipped rule. Headless `--create` is REFUSED (abort `headless-write-refused`, exit 2, zero `gh` calls); `--dry-run` returns without a write. `is_headless` moves to `common.sh` as `lc_is_headless` so `gh_write` enforces it too (defence in depth). |
| Parent plan: labels via `gh label create`; issues via `gh issue create` | A repo hook refuses the literal `gh issue create` string in the Bash tool, and `gh issue list --json parent` fails on older customer `gh` versions ("Unknown JSON field"). `gh api` exists on every `gh` and the REST create call returns `.id` and `.number` in one request (the `sub_issue_id` needs the database id; no second lookup). | Every read and write goes through `gh api` (REST) except `gh auth status` and `gh repo view --json nameWithOwner,isFork` (repo resolution). One allowlisted write wrapper; a source-scan test asserts no `gh issue`, `gh label` or `gh pr` verb anywhere in the skill. |
| Parent plan: "`gh repo view --json hasIssuesEnabled,isArchived,viewerPermission,visibility`" | Those fields exist on 2.103.3 but older `gh` rejects unknown `--json` fields. REST `GET repos/{o}/{r}` returns `.visibility`, `.archived`, `.has_issues`, `.fork`, `.permissions.push` on every version. | Resolve the slug with `gh repo view --json nameWithOwner,isFork`, then read the rest through REST. |
| Parent plan: "the state block is not consulted for issue numbers" | True and kept; orphan handling needs a live fact. `GET repos/{o}/{r}/issues/{epic}/sub_issues` returned 200 on a real repo today (jikig-ai/soleur #11910) and lists children. | Orphan re-link: a marked issue that exists but is not in the epic's live `sub_issues` list is re-linked, not skipped (CTO risk R1). |
| Parent plan: "a re-run lists the epic's live issues (label `lc:` plus marker)" | `lc:` is a prefix, not a queryable label. | Add one scope label `lc:launch-check` (epic also `lc:epic`) so one REST listing (`labels=lc:launch-check&state=all`) is the idempotency lookup (CTO T2). |
| ADR-314 decision 6: "no network call"; `model.c4` `launchcheck` component: "no network, no telemetry" | Both become false the moment `issues --create` exists: it makes confirm-gated HTTPS calls to the customer's own GitHub. | Amend ADR-314 decisions 6 and 7 in place; rewrite the component description; add the `plugin -> github` edge (CTO T8). |
| Parent plan AC: "one end-to-end run against a throwaway repo confirms the real sub-issue endpoint" | The token here has `repo` scope but no `delete_repo`, so every live run leaves a repo behind; the two org scratch candidates (`test-new-project`, `mu1-fixture`) are public, and a sub-issue write there is a visible mutation. | CTO re-ruling D8 (plan review): stub-only in this PR, stated as "stub-only" in the PR body, plus a tracked follow-up issue to run the live check with the exact commands against a private repo the operator creates. No repository is minted by this work. |
| Plan-review finding (Kieran): `gh api` signals HTTP status only on stderr (`gh: ... (HTTP 404)`) and field flags flip a call to POST | The link fallback keys on 403/404/410/422 and a "read" that carries `-f`/`-F` would silently POST. | `lc__gh_exec` captures stderr and parses `HTTP [0-9]{3}`; the read helper always injects `-X GET`; the stub emits the real `gh:` line format and a test fails if a read reaches it without `-X GET` (CTO D2). |
| Brief: "SKILL.md body-byte ceiling" ratchet | `plugins/soleur/test/skill-body-budget.json` has no `launch-check` entry (grep count 0); the ceilings cover the lifecycle set only. | No ceiling applies to launch-check's SKILL.md. Do not edit any lifecycle SKILL.md; run `python3 scripts/lint-skill-body-budget.py` to prove nothing moved. |
| Brief: "skill description word budget (2454)" | The description is unchanged by this work (18 words, headroom 21 on main). | No `description:` edit, so no budget edit. `bun test plugins/soleur/test/components.test.ts` re-confirms. |
| Brief: "grep-q pipe guard PJ_TRIPLES (316 on main; re-check)" | `.claude/hooks/grep-q-pipe-guard.test.sh` pins `PJ_TRIPLES=316`. It counts distinct (test file, verb, producer file) triples: a test stubs a verb and a non-test file it names pipes text into that verb. A repo-wide search found no non-test file that pipes into `gh`. | Expect no bump; do not pipe into `gh` in `issues.sh`; run the guard once after the suite lands and record the recount. |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #11910 OPEN (tracking issue, stays open); PR #11867 MERGED 2026-11-03T02:58:38Z; draft PR #11949 already exists for this branch (title "WIP: feat-one-shot-launch-check-pr-b-epic-issues"); roadmap rows 4.12 (Art. 28(3) instrument, P1) and 4.14 (this feature, "PR-B: severity-ranked epic with sub-issues") exist in `knowledge-base/product/roadmap.md`; ADR-314 exists on main with decision 7 marked "planned". ADR corpus grep for the proposed mechanism (saved-plan issue writes, sub-issues, epic) found no ADR rejecting it; ADR-314 decision 7 is the operative record. Collision pre-check: no open PR names #11910 beyond this branch's draft; four foreign `test-all.sh` processes belong to another worktree (`/tmp/soleur-gitignore-probe`) and are unrelated to launch-check, reported and not acted on. Every file path in this plan was read in this worktree (SKILL.md, `launch-check.sh`, `lib/{common,render,redact-gate,checks,baseline,safe-walk}.sh`, `references/*`, `test/{lib,render,redact-gate,wording}.test.sh`).

**Property List (Phase 0.6b).**
1. A customer who has read the report can turn its open gaps into ranked, labelled issues in their own tracker without hand-copying.
2. Nothing is written to the tracker that the customer did not see in a preview and confirm.
3. Running it twice never files the same gap twice, and a run that failed half-way resumes cleanly.
4. No secret, secret location or personal-data string reaches an issue title, body, label, plan file or stdout marker.
5. A customer's own text in the epic and their close/label decisions survive every re-run.
6. When the tracker cannot be written (no auth, no permission, issues off), the customer is told why and nothing is half-created.

**Cut List (Phase 0.6b).** Mechanism, property, what already covers it.
- Per-gap issue without a preview stays cut (parent Cut List); the saved plan buys properties 1 and 2.
- A confirm-hash token and `--confirm <hash>` stays cut; the in-place-validated saved plan plus the skill's `AskUserQuestion` buys property 2.
- Closing resolved issues from the tool stays cut (create-only; the customer closes).
- Storing issue numbers in the report state block stays cut; GitHub is the record (property 3).
- A `verify-plan` subcommand: cut as a separate command; the validation `--create` already runs is exposed as the `--check-plan` flag (parse-only), which also serves as the discoverability probe.
- A second wording-lint harness for issue bodies: cut; `wording.test.sh` gains the new template and `issues.sh` in its lint list.
- A second epic template file: cut; epic prose lives in `references/phrases.txt` (already linted).
- `gh label create` and `gh issue create` verbs: cut in favour of REST via `gh api` (one write-shape family, portable across `gh` versions, no hook-blocked string).
- A no-TTY refusal: cut (blocks the intended agent flow); the shipped CI/`LAUNCH_CHECK_HEADLESS` rule stays.
- (Plan review, CTO re-ruling 2026-11-03) Rate-limit retry/backoff and its `LAUNCH_CHECK_SLEEP` seam: cut; the first failed write aborts `issues-incomplete` naming the rate limit, the marker-idempotent re-run is the retry; only a fixed 1 s pause between writes stays.
- Read-side allowlist (`lc_gh_read`): cut; the read helper always injects `-X GET`, the write helper keeps the allowlist.
- Listing sanity limit (`listing-truncated`, 1000 rows): cut; the listing is label-scoped and `--paginate`d.
- Per-item 422 fallback: cut; any link failure latches the whole run to the task list (one rule, no per-status branch).
- Snapshot copy of the plan directory before scan and send: cut; validate in place, with closed vocabularies for every `plan.tsv` field, `@file` operands confined (realpath) inside the validated plan directory, and a field-key allowlist on writes. Same-user processes are outside the threat model (Encryption Posture).
- Preview `mode=report-only reason=epic-closed` variant: cut; preview prints a plain warning line, `--create` aborts `epic-closed` with a fix message.
- 24-hour plan max age (spec-flow suggestion): rejected; the report-hash `report-stale` check proves staleness better than a clock and adds no second abort path.
- A live endpoint check that mints a throwaway repository: cut from this PR (stub-only plus a tracked follow-up).

**Dissent recorded, not applied (operator-direction items):** DHH and code-simplicity would drop `--exclude-domain`/`--exclude-class` (they are in the referenced parent plan Phase 5, so cutting them drops specified scope) and `--confirm-public` (CTO T4 and D7 keep it, gated on LIVE visibility); DHH would make the epic task list the always-written source of truth with a best-effort link, which reshapes the operator's "sub-issues API, with a task-list fallback" (kept as asked). See decision-challenges.md.

**Value-proposition measurement (Phase 0.6c).** Not applicable: a new capability, not a saving.

**Functional overlap (Phase 1.5b).** Registry sweep (claude-plugins.dev, claudepluginhub.com, Anthropic marketplace): no skill combines severity ranking, domain labels, body-marker idempotency, preview-then-confirm, redaction-scanned bodies and a plain `gh` helper. The nearest (`az-cost-optimize`, a Copilot prompt: findings to issues plus an epic) is Azure-specific with no idempotency or redaction. Decision: build.

**Community discovery (Phase 1.5).** Stack is bash and markdown, covered by built-in agents. No gap.

**Repo research (Phase 1).**
- Stub-`gh` precedents to copy: `plugins/soleur/test/codeql-main-alert-gate.test.sh` with `plugins/soleur/test/fixtures/codeql-main-alert-gate/shim/gh` (append argv to `calls.log`, truncate per case, a harness row that fails when a green run recorded zero calls, file-operand `grep -cF` counts); `plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh` (heredoc stub, positional `case` router, unrouted calls exit 64); `plugins/soleur/test/sync-pr-behind.test.sh` (counter stub).
- No code in the repo writes sub-issues; `plugins/soleur/skills/ship/references/epic-close-sweep.md` only reads `gh issue view --json subIssues` / `parent`. There is no existing 403/404/410/422 handling to reuse.
- `scripts/test-all.sh` auto-globs `plugins/soleur/skills/*/test/*.test.sh` (SUITE_GLOBS). A suite with no `suite-durations.tsv` / `suite-shard-legs.tsv` row still runs (hash fallback) but `plugins/soleur/test/scripts-shard-manifest.test.sh` (durations keys equal manifest keys) and `scripts-shard-totality.test.sh` go red.
- The affected-index audit's accept rows are keyed by (suite, path, content anchor, ordinal), anchor = sha256 of the whitespace-normalised, comment-stripped line (12 hex). Existing launch-check suites each carry 8 rows for the `lib.sh` fixture strings (lines naming `package.json`, `.github/workflows/ci.yml`, `.nvmrc`, `CLAUDE.md`, `README.md`, `package-lock.json`). Editing other lines of `lib.sh` does not move anchors; changing a path-naming line or duplicating one does.
- Open `code-review` issues touching the planned files: none (97 open scanned).
- No `proc.sh` use is needed: the launch-check test directory spawns no background processes.

**Institutional learnings applied.**
- `2026-09-25-gh-stub-must-mirror-real-cli-flags.md`: the stub whitelists real `gh api` flags (`-X`, `-f`, `-F`, `--jq`, `--paginate`) and exits 64 on anything else.
- `test-failures/2026-04-22-path-prefix-gh-stub-signal-drift-resistance.md`: the recorder touches its sentinel inside the matched dispatch branch, never before the `case`; the catch-all exits without recording.
- `2026-10-14-my-stubs-checked-the-shape-of-argv-and-never-the-value-...md`: the stub refuses contract violations (exit 64 plus a REFUSE log line) and the suite asserts values (title, labels, body bytes, `sub_issue_id`), not just that `gh` ran.
- `2026-10-25-a-test-engine-that-resets-its-own-failure-list-...md`: every verdict-owning helper gets a control that must fail and a counter that must move.
- `2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`: no `--arg` inside `gh --jq`; numeric ids are digit-validated before interpolation.
- `2026-03-24-gh-api-paginate-concatenated-arrays.md`: listings use `--paginate` with `--jq` emitting one TSV row per item; a test forces pagination with a small `per_page`.
- `2026-05-15-fail-closed-redaction-enables-committed-default-output.md`: scan the exact bytes that get sent, before sending; the blob plus a per-file scan in send order closes the gap between scan and send.
- `2026-06-29-c4-source-edit-requires-regenerate-model-json-orphan-suite.md`: after any `.c4` edit run `bash scripts/regenerate-c4-model.sh`, commit `model.likec4.json`, and run `c4-model-freshness.test.sh` by name (it runs only from `test-all.sh`).
- `test-failures/2026-10-30-audit-accept-rows-need-every-boundary-line-...md`: build accept rows from `audit --all-refs`, not from the ratchet report; do not re-price incumbent durations in a feature PR.
- `2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`: read `SKILL_DESCRIPTION_WORD_BUDGET` from `components.test.ts`, never a remembered number.
- `2026-05-06-plan-prescribed-labels-must-be-verified.md`: a missing label fails creation; the labels step lists before creating.

**Capability verification (CLI-verification gate).** Verified here against `gh` 2.103.3: `gh api --help` documents `-X/--method`, `-f/--raw-field` (string), `-F/--field` (typed; `@file` reads the value from a file), `--jq`, `--paginate`, and that field flags switch the method to POST unless `-X GET` is given; `gh repo view --json` lists `nameWithOwner`, `isFork`, `isArchived`, `visibility`; `gh api repos/jikig-ai/soleur/issues/11910/sub_issues` returned 200; `gh api -X GET repos/jikig-ai/soleur/issues -f labels=... -f state=all -f per_page=2 --paginate --jq '...@tsv'` returned rows; a gojq `scan()` expression ran without error; `gh issue edit --add-sub-issue` exists on 2.103 but is NOT used (older customer `gh`). Not yet verified (work-phase item T7): a POST to `.../sub_issues` with `-F sub_issue_id=<int>` and the 403/404/410/422 behaviours.

**Conventions.** Shell suites source `plugins/soleur/skills/launch-check/test/lib.sh` and use the `gitq`/`lc` constructed-environment helpers (no inherited `GIT_*`); fixtures are synthesized (`cq-test-fixtures-synthesized-only`); no `grep -q` after a pipe (use here-strings); no `pgrep -f`; no `rm -rf` on a variable (cleanup uses the `${var:?}` pattern already in `launch-check.sh`).

## Open Code-Review Overlap

None. The open `code-review` issues (97) were filtered against `plugins/soleur/skills/launch-check/`, `knowledge-base/engineering/architecture/diagrams/model.c4`, `apps/web-platform/test/git-lock-marker-telemetry.test.ts`, `scripts/suite-durations.tsv` and `plugins/soleur/test/fixture-relative-assert.baseline.txt` with no match. The work phase re-runs the same filter at start.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Build PR-B: the severity-ranked epic with sub-issues." | Phases 1-4 | mapped |
| 2 | "scripts/lib/issues.sh: preview, 30-issue cap, gh_write create from a saved plan only, refused when headless (CI or LAUNCH_CHECK_HEADLESS=1)." | Phase 2 (`issues.sh`), Phase 3, Guard 1 | mapped |
| 3 | "lc: labels created only if absent." | Phase 3 labels step, Guard 3 | mapped |
| 4 | "Sub-issues API, with a task-list fallback." | Phase 3 link step + epic marked section | mapped |
| 5 | "Idempotency by label plus a <!-- launch-check:gap=<id> --> marker." | Phase 2 live lookup, Guard 3 | mapped |
| 6 | "test/issues.test.sh." | Phase 0 / Files to Create | mapped |
| 7 | "plugin -> github C4 edge in model.c4 (regenerate the JSON)." | Phase 5 | mapped |
| 8 | "SKILL.md accept/epic flow." | Phase 5 | mapped |
| 9 | "Issue bodies go through the lc_emit_checked redaction chokepoint. Secret findings are counts only." | Guard 2, Phases 2-3 | mapped |
| 10 | "Ratchets to expect: skill description word budget (2454), SKILL.md body-byte ceiling, affected-index accept rows (anchor-keyed), grep-q pipe guard PJ_TRIPLES (316 on main; re-check), telemetry marker drift guard, suite-durations.tsv, fixture-relative baseline." | Phase 6 ratchet table | mapped |
| 11 | "Run the full ship pipeline (review, then CI as the full-suite gate; do not hold the local session on the whole battery)." | Phase 7, Acceptance Criteria (targeted local suites only) | mapped |
| 12 | "do NOT run launch-check against any customer repo" | Non-Goals; the Phase 7 live check uses a throwaway repo, never a customer repo | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `issues.sh`, preview, cap 30, saved-plan create, headless refusal | "preview, 30-issue cap, gh_write create from a saved plan only, refused when headless" | asked |
| `lc:` labels if absent | "lc: labels created only if absent" | asked |
| Sub-issues API plus task-list fallback | "Sub-issues API, with a task-list fallback" | asked |
| Label plus marker idempotency | "Idempotency by label plus a <!-- launch-check:gap=<id> --> marker" | asked |
| `test/issues.test.sh`, stub `gh` | "test/issues.test.sh" | asked |
| C4 edge plus JSON regen | "plugin -> github C4 edge in model.c4 (regenerate the JSON)" | asked |
| SKILL.md flow | "SKILL.md accept/epic flow" | asked |
| Ratchet bookkeeping (accept rows, durations, shard legs, fixture baseline, PJ_TRIPLES) | "Ratchets to expect: ..." | asked |
| `--exclude-domain` / `--exclude-class` | "Read first: archived plan Phase 5 at knowledge-base/project/plans/archive/20261102-220428-2026-11-02-feat-customer-repo-readiness-gap-analysis-plan.md" (Phase 5 specifies both flags) | asked (via the referenced plan) |
| Report-hash `report-stale` re-check at create, live-visibility gate, fresh epic GET before the splice, `epic-ambiguous` | — | inferred — justification: plan review (spec-flow P0, architecture P1): a customer decision after the preview (accepting a finding), a repo that turned public, a customer edit during the run, or a planted marker must not be overridden |
| Closed-set validation of every `plan.tsv` field, `@file` confinement, write field-key allowlist | — | inferred — justification: plan review (Kieran, architecture): a hand-edited plan is the only input that reaches `gh` unscanned for structure; the redaction gate checks secrets, not labels or file operands |
| Scope label `lc:launch-check` (and `lc:epic`) | — | inferred — justification: "label plus marker" needs a queryable label; the `lc:` prefix is not one; one scope label makes the live lookup a single bounded REST listing (CTO T2) |
| `--check-plan` parse-only flag and the committed `plan-sample` fixture | — | inferred — justification: the Observability discoverability probe must run in a 15 s sandbox with no network or scanner; the flag reuses the validation `--create` already performs |
| `lc_compute_gaps` extraction from `render.sh` | — | inferred — justification: issues and report must agree on the open/accepted set; a second copy of the partition would drift (CTO T1) |
| `--confirm-public` | — | inferred — justification: issues on a public repo publish unfixed gaps (the banner says to keep the report private); the parent plan's warning is advisory only, and consent for that is the customer's, so the script requires an explicit flag bound to the plan's repo (CTO T4) |
| Orphan re-link, closed-epic abort, damaged-marker skip | — | inferred — justification: CTO risks R1/R2 and T6; each is a state a crash or a customer edit produces |
| `test/gh-stub.sh` (stateful fake `gh api`) | — | inferred — justification: partial-failure resume, orphan and fallback tests need a fake that keeps state; `lib.sh` stays untouched so existing affected-index anchors do not move |
| ADR-314 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` (decisions 6 and 7 become false) |

### Split Assessment

- Subsystems touched: 4 — `plugins/soleur`, `knowledge-base`, `scripts`, `.claude/hooks` (only if the PJ_TRIPLES recount moves)
- Planned files: ~22 | Estimated changed lines: ~1700 (issues.sh ~450, stub ~150, suite ~650, template/phrases ~40, SKILL.md/ADR/C4 ~150, registry rows ~250)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. This change IS the split half (parent plan: PR-A then PR-B). The only code that writes to a customer's tracker must land with its stub-`gh` suite and its Guard tests; the registry rows are mechanical bookkeeping that cannot be separated from the new suite without leaving CI red. The lines estimate is dominated by tests and ratchet rows.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Marketing

Carried forward from the parent plan's domain assessments (brainstorm 2026-11-02, archived with the parent specs); PR-B adds no domain surface beyond the issue-writing path those assessments already scoped.

### Engineering (CTO)

**Status:** reviewed (parent carry-forward + fresh ruling 2026-11-03)
**Assessment:** The CTO ruled the design forks T1-T10 and three risks, then re-ruled eight items after the plan-review panel (decision-challenges.md). Headline: single source for the gap set, scope label for idempotency, plan validated in place with closed vocabularies (no snapshot copy), no retry ladder (the idempotent re-run is the retry), `--confirm-public` gated on live visibility, markers from `scripts/lib/` (outside the drift guard's walk, like `_ABORT`), report-only exit 0 on preview for environment causes and abort on create, any link failure latches to the task list, live endpoint check stub-only with a tracked follow-up, ADR stays `adopting` until the first real run.

### Product (CPO)

**Status:** reviewed (parent carry-forward)
**Assessment:** n=1 hypothesis; the Phase 4 checkpoint (#8981) remains the validation hook. No UI surface. The parent plan's validation bar is unchanged (validated if the tester acts on at least 3 filed issues or names a gap they had not seen).

### Legal (CLO)

**Status:** reviewed (parent carry-forward)
**Assessment:** Local CLI on the customer's key is supplier posture; no Jikigai-hosted sink, no telemetry. Issue creation goes from the customer's machine to the customer's own GitHub. A hosted variant and any Jikigai-keyed run on tester content stay gated on an executed Art. 28(3) instrument (C1). Public-repository publication of gaps is handled by the plan's visibility field and `--confirm-public`.

### Marketing (CMO)

**Status:** reviewed (parent carry-forward)
**Assessment:** No quantitative claims at n=1; the blog post and feature tweet stay held until a real run exists and this change has shipped. No wording change to the skill description.

### Product/UX Gate

**Tier:** none
**Decision:** not applicable (no `components/**/*.tsx`, `app/**/page.tsx` or layout file in Files to Create or Edit; output is CLI text, markdown and GitHub issues)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** not applicable (no UI surface)

**Brainstorm-recommended specialists:** none named by a leader.

## User-Brand Impact

- **If this lands broken, the user experiences:** a flood of wrong, duplicated or half-created issues in their own tracker (an epic that links to nothing, the same gap filed twice after a retry, a closed issue that comes back) that they must clean up by hand, or issues created in a repository they did not intend (a fork resolving to its upstream).
- **If this leaks, the user's data is exposed via:** an issue title or body that carries a secret value, a secret-class location or a personal-data string into a tracker (possibly public), or the gap list itself published on a public repository without the customer's explicit consent; or a plan file or stdout marker carrying the same.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one leaked credential or one unconsented public listing of unfixed weaknesses in a customer's repo is a Soleur-caused incident for that user; the per-user tier from the parent plan applies unchanged.

`requires_cpo_signoff: true` carries from the parent plan (CPO assessed at the brainstorm). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## GDPR Gate (advisory, plan Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Invoked on trigger (b) (threshold `single-user incident`); no canonical regulated-data path is touched (no migration, `.sql`, auth or API-route file).

- `GDPR-Chapter-V`: not triggered. Issue text travels from the customer's machine to the customer's own GitHub with the customer's credentials; Soleur operates no server-side path, receives nothing, and adds no telemetry. A hosted variant would trigger it and stays a non-goal.
- `GDPR-Art-5c` / `Art-32` (suggestion): issue bodies carry only catalog titles and remedies, check ids, severities, and sanitized evidence (bare `path`, `path:line` or fixed count phrases); personal-data and secret classes are scanned by `lc_emit_checked` on the exact bytes sent. Secret-class findings are counts only in titles, bodies, plan files and markers.
- Suggestion: a public repository makes the gap list world-readable. The plan records visibility and `--create` needs `--confirm-public` on PUBLIC or UNKNOWN visibility (CTO T4); the skill must name the repo and visibility in the question.
- Suggestion: the live issue listing reads other people's issue bodies. Only the marker substring is kept (gojq `scan`); nothing else from those bodies is stored or printed.
- Result: no `Critical` finding, so no `compliance-posture.md` write is proposed. The work phase re-runs the gate on the actual diff (AC).

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-314** (not a new ADR) via `soleur:architecture`, as a dated "Amendment" block rather than a silent rewrite: decision 6 ("no network call") becomes "no network call except the confirm-gated `gh` writes to the customer's own repository, from a saved plan, never headless", and states that the Art. 28(3) posture is unchanged because Soleur still receives nothing; decision 7 moves from "planned" to the built contract (saved-plan directory validated in place against closed vocabularies; one write wrapper with an allowlist of four REST shapes, a field-key allowlist and confined `@file` operands; `lc:launch-check` scope label plus body marker as the idempotency key; sub-issue API with a probe-and-latch task-list fallback; `--confirm-public` gated on live visibility; markers emitted from `scripts/lib/issues.sh`, deliberately unmirrored because they carry the customer's repository slug). Add one row to Alternatives Considered: `gh issue create` / `gh label create` verbs (rejected: hook-blocked string, version-dependent flags). Status stays `adopting` until the first real customer run (CTO T8). The plan's per-item rows are derived from the catalog, consistent with ADR-193 ("derived, never listed").

### C4 views

Read all three files under `knowledge-base/engineering/architecture/diagrams/` (`model.c4`, `views.c4`, `spec.c4`). Enumeration:
- External human actors: the founder/customer, already modeled as `founder` with edges through the harnesses to `platform.plugin`. Already-modeled.
- External systems: `github`. The existing `plugin -> github` edge ("Opt-in release lookup ...") covers Jikigai's own public repo and ADR-289 per-user reads. The customer's tracker is the same vendor but a different data owner and a write direction; ADD a second `plugin -> github` edge for launch-check's confirm-gated writes (technology "HTTPS (GitHub REST API via gh)"). The brief names this edge literally. Anthropic reach is through the harness, already modeled.
- Containers/data stores: the plan directory is a temp directory on the customer's machine; no Soleur-hosted store.
- Access relationship changes: none for Soleur-hosted systems. The `launchcheck` component description ("Writes only that report ... no network, no telemetry") is falsified by this change; REWRITE it: the report is the only analysis write, issue writes are confirm-gated and go through one wrapper to the customer's own repository, no Jikigai-hosted sink and no telemetry.
- Views: `launchcheck` is in no `views.c4` include list today; the `plugin` container and `github` are both in the containers view, so the new edge renders there with no `views.c4` edit.
- Counts: the skill count (106) is unchanged and the existing `plugin -> github` edge prose cardinalities are untouched. `plugins/soleur/test/c4-count-parity.test.sh` (green on main today) must stay green.

Tasks: edit `model.c4` (edge plus component description), run `bash scripts/regenerate-c4-model.sh` and commit `model.likec4.json`, run `cd apps/web-platform && npx vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`, `bash plugins/soleur/test/c4-count-parity.test.sh` and `bash plugins/soleur/test/c4-model-freshness.test.sh`.

### Sequencing

The ADR amendment and C4 edit ship in this PR (not a follow-up issue). Status `adopting` remains until the first real customer run.

## Guard Contract

### Guard 1 — Saved-plan-only gh writes

**Property.** No `gh` write (label create, issue create, sub-issue link, issue-body edit) runs except by executing a validated saved plan of the repository the plan names, never under `--dry-run`, never when headless, and never with a shape, field key or file operand outside the four allowlisted REST forms.

**Assembly.** One executor, `lc__gh_exec`, is the only place the word `gh` is invoked as a command in any skill script. Reads go through `lc_gh_read`, which always injects `-X GET` for `gh api` (a field flag otherwise flips the call to POST) and refuses any argv without it. Writes go through `lc_gh_write`, which (a) aborts `headless-write-refused` when `lc_is_headless`, (b) returns without calling `gh` when `LC_DRY=1`, (c) accepts only `api -X POST repos/<slug>/labels`, `api -X POST repos/<slug>/issues`, `api -X POST repos/<slug>/issues/<n>/sub_issues` and `api -X PATCH repos/<slug>/issues/<n>`, where `<slug>` equals the plan-bound repo and `<n>` is digits, (d) accepts only the field keys `title`, `body`, `labels[]`, `sub_issue_id`, `name`, `color` and `description` (so a PATCH can never carry `state`), and (e) accepts a `@file` operand only when its realpath is inside the validated plan directory (or the scratch file the tool itself built for the epic section); any other argv aborts `write-shape-refused`. `--create` also refuses at argument parse when headless (before any `gh` call, reads included) and with no `--plan`. Every call site of `lc_gh_write` is in `issues.sh`; a source-scan test enumerates them.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Run `--create` with no `--plan` | RED (abort `usage`, zero recorded calls) |
| 2 | Run `--create --dry-run` under the recording stub (a dry-run that records one write is vacuous) | RED if any write call is recorded; reads allowed |
| 3 | Run `--create` with `CI=1`, then with `LAUNCH_CHECK_HEADLESS=1` | RED (rc 2, `headless-write-refused`, zero recorded calls of any kind) |
| 4 | Source `issues.sh` in the suite and call `lc_gh_write` directly under `CI=1`, then under `LC_DRY=1` (separate rows from the argument-parse refusal, so deleting the wrapper's own check is visible) | RED (nothing reaches the stub) |
| 5 | Add a second `gh api -X POST` call outside `lc_gh_write` after a compliant first (sandbox copy of `issues.sh`) | RED (source-scan test) |
| 6 | Hand-edit the plan's `repo=` to another repository, and separately execute the plan from a checkout whose resolved repo differs | RED (`plan-repo-mismatch`, zero writes) |
| 7 | Call `lc_gh_write` with `-X DELETE`, a `labels` PATCH, a different slug, `-f state=closed` on the PATCH shape, and `-F body=@/etc/hostname` | RED (`write-shape-refused`, nothing recorded) |
| 8 | Call `lc_gh_read` for an `api` path with `-f` and no `-X GET` | RED (refused; the stub never sees a read without `-X GET`) |

**Harness rows.** Edit the suite's stub so it records nothing: the suite must go RED (a recorder that cannot record proves nothing; the suite fires a canary write at the stub directly and asserts the log line). Edit the suite to drop the CI=1 case: the canary-count floor must fail. Must-PASS rows that differ from the canonical: a plan whose rows are in a different order from a regenerated preview is still executed as saved; a plan for a PRIVATE repo runs without `--confirm-public`.

**Anchor.** The independent witness is the stub's append-only call log (a file the code under test cannot rewrite) plus the allowlist shapes and field keys pinned in the test file by literal; weakening the wrapper means editing both `issues.sh` and the test's lists. The plan directory is the single source of what runs.

### Guard 2 — Authored bytes are scanned bytes; counts only for secret classes

**Property.** Every byte this tool authors into a tracker (issue titles, issue bodies, the rebuilt epic section, label names and descriptions) passed `lc_emit_checked` before the first write, and no secret value, secret-class location or personal-data string appears in an issue, a plan file or an `ISSUES` marker.

**Assembly.** The chokepoint is `lc_emit_checked <file> "" 1` (scan-only mode). `--create` validates the plan directory in place (refusing symlinks, files outside `plan.tsv`, `epic.md` and `issues/<ID>.md`, files over 64 KiB; every `plan.tsv` field checked against a closed vocabulary: ids `^[A-Z]+-[A-Za-z0-9-]+$`, severity and domain enums, class enum, action enum, title length-bounded with no control characters, repo `^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$`; each body carries exactly its own marker). Then it builds one scan blob in send order (title line then body for every item, the epic body, label names and descriptions) and, before the first write, scans the blob and ALSO each file that will be sent, so a file that differs from the blob cannot slip through. The rebuilt epic section is scanned again before its PATCH. Same-user tampering between scan and send is outside the threat model (Encryption Posture); the point of the in-place validation is that a stale or hand-edited plan cannot reach `gh` with an unknown label, file operand or id. Preview reuses the same validate-and-clean path as render (`lc_prepare_inputs`: `lc_build_catalog`, `lc_clean_facts`, `lc_validate_judged`), so a raw facts file written with `--show-secrets` cannot put a location into a body. Secret-class findings render the fixed count phrase (the `lc_clean_facts` grammar), never a path. Evidence is rendered inside a code span so `@scope/pkg` shapes cannot mention anyone. Bodies are built by an awk splice that takes values through `ENVIRON` (never `awk -v`, which interprets backslashes) using `index()`/`substr()` (never `gsub`, never `${var//pat/repl}`: `&` in a replacement is special in bash 5.2 and awk, and the domain label "Tests & CI/CD" contains one). A source scan bans `${...//...}` substitution in `issues.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Tamper one plan body with a synthesized secret-shaped string (assembled from fragments at run time) before `--create` | RED (rc 1, `redaction-hit`, zero writes recorded) |
| 2 | Remove the gate call from a sandbox copy of the create path | RED (the tamper row now records writes) |
| 3 | Plant a pattern only gitleaks matches (not the sentinel) and make `gitleaks` a stub that exits 0 printing nothing | RED (the tamper row passes through, so the suite must catch the stub; with the real gitleaks the row aborts rc 1) |
| 4 | Make the sentinel exit 2 | RED (rc 2 and zero writes) |
| 5 | Add a second authored field to a body (a free-text note) | RED (template/marker validation; the scan blob must equal the concatenation of the sent files in send order) |
| 6 | Render a SEC-01 item's evidence as a path; and feed `issues --preview` a hostile facts file that carries a secret path | RED (body must contain only the count phrase; the planted path never appears in any recorded argv, body or plan file) |
| 7 | Introduce `${var//pat/repl}` into `issues.sh` | RED (source scan; plus a direct splice test with the `Tests & CI/CD` label, which is portable to bash 3.2) |
| 8 | Evidence `node_modules/@types/node/index.d.ts` rendered outside a code span | RED (no `@` mention outside a code span) |
| 9 | Hand-edit `plan.tsv` with an unknown label-bearing severity, a newline in a title, an id with `../`, or a symlink in `issues/` | RED (`plan-invalid`, zero writes) |

**Harness rows.** Replace the planted secret in the suite with a clean string: the tamper row must flip to success (a suite with no plant asserts nothing). Must-PASS: an evidence path containing the word "secret" but no value is sent; an evidence path with `@types` is sent inside a code span.

**Anchor.** The stub stores received body bytes independently, so the test compares the received bytes to the scanned blob in send order; editing the send path without editing the scan path is visible. `lc_emit_checked` itself is pinned by `redact-gate.test.sh`.

### Guard 3 — Idempotency and resume

**Property.** A gap id is filed at most once per repository (open or closed counts as filed), a run that stopped half-way, for any reason including a kill during linking, resumes by creating exactly the missing issues, and an issue that exists without a parent link is re-linked rather than recreated or skipped.

**Assembly.** The live identity is the pair (label `lc:launch-check`, body marker `<!-- launch-check:gap=<ID> -->` or `<!-- launch-check:epic -->`), read through one paginated REST listing (`labels=lc:launch-check`, `state=all`, `--paginate`, `--jq` keeping only number, state, PR flag and the marker substring, anchored to the id grammar). `lc_issues_live` is the only producer of "what exists"; both `--preview` and `--create` use it, and `--create` re-lists immediately before the first write and again after creating the epic (a second epic marker aborts `epic-ambiguous`). Extracted values are used only as set keys, never in a path or argv. Issues whose body has zero markers or more than one distinct marker are ignored and counted; duplicates of the same id resolve to the lowest number. The epic is accepted only when it is not a PR, carries `lc:epic` and has exactly one begin/end pair; a second candidate aborts `epic-ambiguous`. The epic's live `sub_issues` list decides orphans. Label creation treats a 422 `already_exists` as success and only names absent from a fresh `labels` listing are posted (no update path exists in the allowlist). A write whose outcome is unknown (timeout) is never retried blindly; the re-list on the next run decides. At create, every `create` row must still be `open` in the current report: the plan records the report's state-block hash, and a mismatch aborts `report-stale`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fail the 4th create (stub), re-run the same plan | RED unless the re-run creates exactly the remaining issues and the fake tracker holds 1 epic plus every item once |
| 2 | Kill the run between a create and its link (stub exits the script's process group after the create response), re-run | RED unless no duplicate is created and the orphan is linked exactly once |
| 3 | Pre-seed a CLOSED marked issue for a gap | RED if it is recreated; it is reported as closed-by-customer and skipped |
| 4 | Pre-seed a marked issue with no parent link, API available | RED unless exactly one link call and zero create calls are recorded for it |
| 5 | Remove the live re-list from `--create` (sandbox copy) and re-run after a partial failure | RED (duplicates appear) |
| 6 | Pre-seed a label `lc:severity-high` with a custom colour | RED if any label write is recorded for it or its colour changes |
| 7 | Add a second issue carrying the same marker, plus a body with two distinct markers | RED unless duplicates resolve to the lowest number and the multi-marker body is ignored and counted |
| 8 | Closed epic; and a second labelled epic-marker candidate | RED unless `--create` aborts `epic-closed` (with the reopen-or-unlabel message) or `epic-ambiguous` with zero writes, and preview prints a warning line |
| 9 | Stub the sub-issue endpoint to 404, then separately to 422, on the first link | RED unless the whole run latches to the task list in both cases, no further link call is recorded, and the epic section lists every item as `- [ ] #N` |
| 10 | Accept a finding in the report after the preview, then `--create` | RED unless the run aborts `report-stale` with zero writes |

**Harness rows.** Edit the suite so the stub fails nothing: the partial-failure row must go RED (it asserts `failed>0` on the first run). Must-PASS: a re-run of an already complete plan records zero writes (no PATCH when the section is byte-identical).

**Anchor.** GitHub's state, as held by the stub's state files, is the independent record; the test reads the fake tracker's contents, not the script's own counters.

### Guard 4 — Epic edits are confined to the marked section

**Property.** The only part of the epic body this tool ever changes is the text between the first `<!-- launch-check:begin -->` and the matching `<!-- launch-check:end -->`; everything outside is carried byte-for-byte (CRLF and trailing-newline differences included), and damaged markers stop the edit rather than widening it.

**Assembly.** One function, `lc_epic_splice <old-body-file> <new-section-file>`, is the only producer of an epic PATCH body. It is called with the epic body fetched by a GET immediately before the splice (never the body read at the first listing, which is minutes old by then). It requires exactly one begin and one end marker in order, tolerating a trailing `\r`; otherwise it returns `markers-damaged`, no PATCH is sent and the summary says `epic-section=markers-damaged`. The body is written to a file and compared to the spliced result with the single trailing newline `--jq` adds normalised. The initial epic body (create) is the plan's `epic.md`. The new section is built at create time from live numbers and plan rows and scanned before the PATCH; the gate scans the bytes the tool authors (the section), while customer-owned bytes outside the markers are carried unchanged and are not re-judged. A PATCH failure is `issues-incomplete`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Customer text before and after the markers, then a re-run | RED unless text outside the markers is byte-identical (cmp) |
| 2 | The stub rewrites the epic body between the first listing and the PATCH (the customer edits during the run) | RED unless the customer's new text survives (the GET-before-splice rule) |
| 3 | Delete the end marker in the live epic | RED unless no PATCH is recorded |
| 4 | Duplicate the begin marker | RED unless no PATCH is recorded |
| 5 | Epic body stored with CRLF line endings | RED unless the section is found and the CRLF bytes outside it are preserved |
| 6 | Make the splice replace the whole body (sandbox copy) | RED (customer text lost) |
| 7 | Re-run with nothing changed | RED if a PATCH is recorded (an unchanged section is not rewritten) |
| 8 | Section content containing a synthesized secret-shaped string | RED (rc 1, no PATCH) |

**Harness rows.** Edit the suite to put no customer text in the epic: row 1 must go RED on its own floor. Must-PASS: customer text containing the words begin and end (without the marker syntax) survives.

**Anchor.** The test compares the stub's stored epic body outside the markers to a copy taken before the run.

## Observability

Surface: code under `plugins/soleur/skills/launch-check/` that executes on a customer's own machine (observability layer 7, `cli-stdout-artifact`). No Soleur-side sink is added (ADR-314 decision 6: no phone-home). The markers carry the owner/name slug and counts, are emitted from `scripts/lib/issues.sh` (outside the telemetry drift guard's `skills/*/scripts/*.sh` walk, like `_ABORT`), and are read only in the customer's own tool result.

```yaml
liveness_signal:
  what: "SOLEUR_LAUNCH_CHECK_ISSUES_PLAN (preview: repo, visibility, counts) and SOLEUR_LAUNCH_CHECK_ISSUES (create: created, linked, skipped, failed, fallback, epic) stdout markers, plus the epic and sub-issues in the customer's own tracker"
  cadence: "per run (invoked by the operator or the customer)"
  alert_target: "the customer's in-session tool-result stdout; no Soleur-hosted alert target by design"
  configured_in: "plugins/soleur/skills/launch-check/scripts/lib/issues.sh (marker emission) and scripts/launch-check.sh (subcommand wiring)"

error_reporting:
  destination: "stdout/stderr tool result in the customer's session; the exit-code table in the launch-check.sh header lists every reason: 0 ok (including preview report-only for an environment cause), 1 redaction hit or a verify failure, 2 usage, preflight, stale/invalid input or partial failure"
  fail_loud: "SOLEUR_LAUNCH_CHECK_ABORT reason=<headless-write-refused|report-missing|report-stale|plan-missing|plan-invalid|plan-repo-mismatch|confirm-public-required|redaction-hit|epic-closed|epic-ambiguous|issues-unavailable|write-shape-refused|issues-incomplete> and a non-zero exit; no further write after the first abort; a partial run prints the ISSUES summary (created, skipped, failed ids, the rate-limit hint when the stderr said so, and the fixed line 'run the same command again; the plan is kept') first and stays resumable"

failure_modes:
  - mode: "gh missing, unauthenticated, no remote, repo unresolved (including a fork that resolved to its upstream), issues disabled, archived, or no push permission"
    detection: "preview prints SOLEUR_LAUNCH_CHECK_ISSUES mode=report-only reason=<named cause>, writes no plan, exits 0; create aborts reason=issues-unavailable detail=<cause>, exit 2"
    alert_route: "layer 7: tool-result stdout in the customer session"
  - mode: "redaction hit in a title, body, label or epic section"
    detection: "lc_emit_checked aborts reason=redaction-hit layer=<sentinel|gitleaks> (class only, never the value) before the first write; zero writes recorded"
    alert_route: "layer 7: stdout marker"
  - mode: "sub-issue API unavailable or rejecting links (any of 403, 404, 410, 422)"
    detection: "ISSUES summary prints fallback=task-list (the whole run latches on the first failed link) and the epic section carries the task list"
    alert_route: "layer 7: stdout marker and the epic body itself"
  - mode: "partial creation (network, secondary rate limit, a failed PATCH, or a killed run)"
    detection: "the first failed write stops the run: ISSUES summary created=N skipped=M failed=<ids> then ABORT reason=issues-incomplete exit 2; re-running the same plan resumes by live marker lookup and re-links orphans"
    alert_route: "layer 7: stdout marker plus the epic's marked section"
  - mode: "stale report (facts rescanned after render, or a finding accepted after the preview) or a plan from an older catalog; plan directory gone (new session)"
    detection: "preview and create abort reason=report-stale (report state-block hash or catalog hash differs, or a create row is no longer open); a missing plan directory aborts reason=plan-missing with the recovery sentence from SKILL.md"
    alert_route: "layer 7: stdout marker"
  - mode: "damaged epic markers, a customer-edited marker, a closed epic, or two epic candidates"
    detection: "ISSUES summary epic-section=markers-damaged with no PATCH; a closed epic aborts reason=epic-closed (reopen it or remove its lc:epic label); two candidates abort reason=epic-ambiguous"
    alert_route: "layer 7: stdout marker"

logs:
  where: "the customer's terminal/tool result; the epic and sub-issues in their own GitHub repository are the durable artifact"
  retention: "stdout markers last for the session; issues live in the customer's tracker"

discoverability_test:
  command: bash plugins/soleur/skills/launch-check/scripts/launch-check.sh issues --check-plan --plan plugins/soleur/skills/launch-check/test/fixtures/plan-sample
  expected_output: SOLEUR_LAUNCH_CHECK_PLAN_OK
```

`--check-plan` is parse-only: it validates the plan directory (header, repo slug shape, ids, one marker per body, no symlinks, size bounds) with no network, no credentials, no `gitleaks` and no repository walk, so it finishes well under preflight Check 10's 15-second cap. On a customer machine the equivalent is `bash "${CLAUDE_PLUGIN_ROOT}/skills/launch-check/scripts/launch-check.sh" issues --check-plan --plan <dir>`. The fixture `plan-sample/` is committed in this PR and is synthesized.

## Encryption Posture

```yaml
at_rest:
  - store: "saved plan directory (plan.tsv, epic.md, issues/<ID>.md) under the customer's $TMPDIR (or the directory passed as --plan-out)"
    mechanism: "no encryption layer is added; the directory is created with mktemp -d (mode 0700) and holds only catalog text, ids, severities and sanitized evidence"
    evidence: "scripts/lib/issues.sh creates the directory with mktemp -d; the suite asserts mode 700 with ls -ld (not stat -c, which differs on macOS)"
    defends_against: "other local users reading the plan on a shared machine (filesystem permission)"
    does_not_defend: "a process running as the same user, a stolen unlocked disk, and backups of the temp directory; the content is the same information that goes to the customer's tracker after confirmation"
    disclosed_as: "SKILL.md states the plan is a local temp artifact the customer can read and delete; ADR-314 decision 7"
    live_verification: "issues.test.sh asserts directory mode 700 and that the plan directory survives the run (it is the resume handle) while no other temp file is left behind"
in_transit:
  - connection: "gh api to the customer's GitHub (api.github.com, or the customer's configured GH_HOST) using the customer's own gh authentication"
    tls: "HTTPS, enforced by the gh CLI"
    cert_verification: on
    does_not_defend: "a compromised customer machine or token; GitHub itself sees the issue text (that is the purpose); public visibility publishes it"
    disclosed_as: "C4 edge plugin -> github, ADR-314 decision 6, and the preview line that names repo and visibility before the customer confirms"
```

No `exception` block: neither plaintext storage nor disabled certificate verification is introduced.

## Implementation Phases

### Phase 0 — Failing tests and fixtures first (RED)

Write before any `issues.sh` code (`cq-write-failing-tests-before`):
- `plugins/soleur/skills/launch-check/test/gh-stub.sh`: a stateful fake `gh` installed on `PATH` for the suite. The state directory holds `repo.json`, `labels.json`, `issues.json`, `calls.log`. It implements only real flags: `auth status`, `repo view --json nameWithOwner,isFork [--jq]`, `api [-X GET|POST|PATCH] <path> [-f k=v] [-F k=v|k=@file] [--jq expr] [--paginate]`; an unknown flag exits 64 with a REFUSE log line, and a read that reaches it without `-X GET` is logged as a violation the suite asserts is empty. Failures print the real `gh: <message> (HTTP <code>)` stderr line. `--jq` is applied by running real `jq -r` over the canned JSON; the shipped expressions stay inside the subset common to jq and gojq (`scan`, `//`, `@tsv`), and the T7 follow-up (live run) is where gojq itself is exercised. jq is a hard requirement of the suite, like gitleaks. Failure injection by env: `GH_STUB_AUTH`, `GH_STUB_FAIL_AFTER=<n>`, `GH_STUB_KILL_AFTER_CREATE=<n>`, `GH_STUB_SUBISSUE=ok|403|404|410|422`, `GH_STUB_PER_PAGE` (forces pagination), `GH_STUB_EDIT_EPIC_BETWEEN` (a customer edit mid-run), `GH_STUB_CRLF`. The recorder appends to `calls.log` inside the matched dispatch branch only; writes are logged with the full argv and the stored body bytes. Model the structure on `codeql-main-alert-gate.test.sh`'s shim.
- `plugins/soleur/skills/launch-check/test/issues.test.sh`: the cases in Test Scenarios, a small sandbox-copy mutation battery (headless check removed from the wrapper, gate call removed, live re-list removed, splice replacing the whole body, `${...//...}` introduced, a second write site), an exact assertion floor, a recorder canary and the instrument self-test (`selftest`). It sources `lib.sh` unchanged and builds repos with the existing `fx_*` helpers. Mode assertions use `ls -ld | cut -c1-10`.
- `plugins/soleur/skills/launch-check/test/fixtures/plan-sample/` (`plan.tsv`, `epic.md`, `issues/CI-01.md`): committed, synthesized, valid.
- Extend `test/wording.test.sh`: lint `issues.sh` and the new template; assert `issues.sh` has no sentence-length prose literal (same regex as `render.sh`).
- Characterization of the render partition: capture `render --dry-run` output for `fx_minimal`, `fx_healthy`, `fx_python` before Phase 1 so the extraction can be diffed.

### Phase 1 — Small refactors the writer depends on

1. `scripts/lib/common.sh`: add `lc_is_headless` (`CI` set or `LAUNCH_CHECK_HEADLESS=1`); `launch-check.sh` `is_headless()` calls it. Behaviour unchanged.
2. `scripts/lib/render.sh`: (a) add `lc_prepare_inputs` holding what `cmd_render` does before `lc_render` (`STACK` from the facts header, `lc_build_catalog`, `lc_clean_facts`, `lc_validate_judged`), called by both `cmd_render` and `cmd_issues`, so preview can never read an unsanitized facts file; (b) extract the block from the `lc_prev_state` call through the `open.ids` / `accepted.ids` / `new.ids` partition into `lc_compute_gaps`, which leaves `prev`, `has_prev`, `judged_in`, `gaps.tsv`, `open.ids`, `accepted.ids` as `$WORK` files or documented globals because `lc_render` reads them afterwards (the closed loop, Not-assessed list and state block). No bash 4 features (`declare -A`, `mapfile`) anywhere: the script runs on customer macOS bash 3.2, so array expansions under `set -u` use `${a[@]+"${a[@]}"}` or delimited strings. Run `render.test.sh`, `identity.test.sh`, `wording.test.sh` before and after; the dry-run output for the three fixtures must be byte-identical.

### Phase 2 — `scripts/lib/issues.sh`: wrappers, preflight, live lookup, preview

- `lc__gh_exec` (captures stderr, exposes the parsed `HTTP nnn` status; rate-limit text is recognised before any 403 is treated as a link failure), `lc_gh_read` (always `-X GET` for `api`), `lc_gh_write` (Guard 1: headless, dry-run, four shapes, field-key allowlist, `@file` realpath confinement) and a fixed 1 s pause between writes, skipped under `LAUNCH_CHECK_TEST=1` with a `LAUNCH_CHECK_PAUSE=0` seam. No retry ladder: the first failed write stops the run.
- `lc_issues_preflight`: run from `cd "$TARGET"`; `command -v gh`, `gh auth status`, `gh repo view --json nameWithOwner,isFork --jq` (non-interactive: a `gh` that needs a default-repo choice with no TTY fails and maps to `repo-unresolved` with the sentence "set a default with gh repo set-default"), REST `GET repos/<slug>` for `visibility`, `archived`, `has_issues`, `permissions.push`; sets `ISSUES_MODE=ready|report-only` and `ISSUES_REASON` from {`gh-missing`, `gh-unauthenticated`, `repo-unresolved`, `issues-disabled`, `repo-archived`, `no-write-permission`}. `GH_REPO` is unset for the run and every call carries the explicit slug. A fork is flagged in the preview line and the SKILL.md question.
- `lc_issues_live`: one paginated REST listing into `$WORK/live.tsv` (number, state, marker). Marker extraction via `--jq` with `scan` anchored to the id grammar (no `--arg`); pull-request rows excluded; extracted values are used only as set keys.
- `lc_issues_preview`: runs `lc_prepare_inputs` then `lc_compute_gaps`; requires the written report (`report-missing`); refuses when a gap that would be filed is not `open` in the report's state block or the catalog hash differs (`report-stale`); applies `--exclude-domain` and `--exclude-class` (repeatable, validated against the closed vocabularies; stored as delimited strings); partitions each gap into `create | exists | closed | accepted | excluded | capped` (cap 30 on `create` per run, ordered by severity rank then id); renders bodies from `references/issue-body.template` by an awk splice via `ENVIRON` (marker first; severity, domain label, check id, title, evidence in a code span, remedy, command for baseline rows; a closing sentence tells the customer to close, not unlabel, an issue that does not apply); writes the plan directory (mode 700) with `plan.tsv` header lines `repo`, `visibility`, `catalog_hash`, `report_hash`, `created` and one row per item; scans the would-be blob through `lc_emit_checked ... 1`; prints a static-phrase summary and `SOLEUR_LAUNCH_CHECK_ISSUES_PLAN ...`. Summary contents: repo and visibility, the fork flag, counts by severity, "to file / already filed / closed by you / accepted / capped / excluded", informational lines "filed, gap now resolved: #N (close it yourself)" and "closed by you, gap still open: #N", a closed-epic warning line, the cap rule ("at most 30 per run; N remain; run again to file them"), and the exact `--create` command line including `--confirm-public` when visibility is PUBLIC or UNKNOWN.
- New static prose goes to `references/phrases.txt` and `references/issue-body.template`; no sentence-length literal in `issues.sh`.

### Phase 3 — `--create`

`lc_issues_create`, in this order: reject headless and a missing `--plan` (`plan-missing` with the recovery sentence when the directory is gone); validate the plan in place (Guard 2 assembly) and stop here for `--check-plan`; resolve the repo and compare to the plan's `repo=`; re-read LIVE visibility and require `--confirm-public` when it is PUBLIC or UNKNOWN (never the plan's recorded value); re-run `lc_prepare_inputs`/`lc_compute_gaps` and abort `report-stale` when the report hash differs or any `create` row is no longer open; scan the blob and each sent file (zero writes before this passes); re-list live state; handle the epic (`epic-closed`, `epic-ambiguous`); create absent labels (fresh `labels` listing; 422 `already_exists` counts as success; fixed colours); create the epic if absent (labels `lc:launch-check`, `lc:epic`; body from `epic.md`), then re-list once more and abort on a second epic marker; for each `create` row not already live (severity order): REST create (`-f title`, `-F body=@<plan file>`, `-f 'labels[]=...'`, `--jq '[.number,.id]|@tsv'`, digit-validated), then link with `-F sub_issue_id=<id>` (the first failed link, any of 403/404/410/422, latches the whole run to the task list); stop at the first failed write; re-link live marked issues missing from the epic's live `sub_issues` (skipped in task-list mode); GET the epic body, rebuild the marked section from live state (task list in fallback mode, the capped remainder from plan rows still without an issue) through `lc_epic_splice`, scan the section (a hit is caught in a subshell so the summary still prints, then the run exits 1), PATCH only if the result differs; print `SOLEUR_LAUNCH_CHECK_ISSUES created= linked= skipped= failed=<ids> fallback= epic=#N epic-section=`; exit 0 when nothing failed, else `issues-incomplete` exit 2. `--dry-run` runs everything except the writes and prints what would run. The `--plan` directory is never deleted by the tool (it is the resume handle); scratch files live under `$WORK` and the existing EXIT trap removes them.

### Phase 4 — CLI wiring

`launch-check.sh`: add `issues` to the header comment and `main`, plus an abort-reason to exit-code table in the header; `cmd_issues` parses `--preview | --create | --check-plan`, `--target`, `--facts`, `--judged`, `--plan`, `--plan-out`, `--dry-run`, `--exclude-domain`, `--exclude-class`, `--confirm-public`; `--check-plan` runs before `lc_preflight_scanners` and before any repository access; the headless and `--plan` refusals run before `need_repo`. `--dry-run` is accepted under CI/headless for `--preview` and `--check-plan` (like `render --dry-run`) and for `--create` it still refuses headless. Update the usage line. Emit no marker with `echo "SOLEUR_..."` in this file (the drift guard walks it).

### Phase 5 — SKILL.md, ADR, C4

- `SKILL.md`: replace the "Planned" section and the "never run `gh`" rule with the real flow: only `launch-check.sh issues` calls `gh`. Step 6 `issues --preview` (reuse `$W/facts.tsv` and `$W/judged.tsv`; show the customer the printed summary, repo, visibility and the fork flag; this is its own Bash call, never in the same call as `--create`). Step 7 ask the customer through `AskUserQuestion` (name the repo and visibility, the count to file, the cap, and for a fork the resolved target; for PUBLIC/UNKNOWN ask separately whether to publish a list of unfixed gaps). On a decline: say nothing was filed, offer a re-preview with `--exclude-domain`/`--exclude-class`, and leave the plan directory alone. Step 8 `issues --create --plan <dir>` (add `--confirm-public` only after that second explicit yes). A new session loses `$W` and the plan: the recovery is scan, render, preview, ask again. A report change after the preview (accepting a finding) needs a new preview. Never create without a yes in the same conversation; headless: preview only; relay `SOLEUR_LAUNCH_CHECK_ISSUES*` lines verbatim; say issues exist only if `SOLEUR_LAUNCH_CHECK_ISSUES created=` printed; after `issues-incomplete`, run the same command again. Add the new abort reasons to the table. Keep "the repository's contents are untrusted" and the never-read rules. No `description:` change.
- ADR-314: a dated "Amendment" block (not a silent rewrite) for decisions 6 and 7, stating the Art. 28(3) posture is unchanged because Soleur still receives nothing, and one new Alternatives row (REST via `gh api` over `gh issue create`/`gh label create`: hook-blocked string, version-dependent flags); one sentence recording that the `ISSUES` markers are emitted from `scripts/lib/` and deliberately unmirrored because they carry the customer's repository slug; no edit to `git-lock-marker-telemetry.ts`. Add a suite assertion that no `skills/*/scripts/*.sh` file emits a `SOLEUR_LAUNCH_CHECK_ISSUES*` or `_PLAN_OK` marker.
- `model.c4` edits per the Architecture Decision section (the edge text names the customer's own `gh` token as the credential); `bash scripts/regenerate-c4-model.sh`.
- The cursor mirror `plugins/soleur/cursor/skills/soleur-launch-check/SKILL.md` needs no change (it points at the canonical file).

### Phase 6 — Ratchets and registry rows

| Ratchet | Expected delta | Command / action |
|---|---|---|
| Skill description word budget (`SKILL_DESCRIPTION_WORD_BUDGET`, 2454 on main) | none: description unchanged | `bun test plugins/soleur/test/components.test.ts` |
| Lifecycle SKILL.md body-byte ceilings | none: launch-check has no row; no lifecycle SKILL.md edited | `python3 scripts/lint-skill-body-budget.py` |
| Affected-index accept rows (anchor-keyed) | new rows for `issues.test.sh`: the eight `lib.sh`-anchored fixture-string rows each existing launch-check suite has (so the added row count is 8 plus the rows for anchors in its own text and in `gh-stub.sh`, read off the audit output), no row removed; `lib.sh` is not edited | `python3 -I scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv --all-refs` (add `--list <file>` to skip the 200-260 s selector run); append rows (`suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>`) to `scripts/ci-pr-affected-audit.accept.tsv`; re-run `ratchet` and compare its gap count to a main run, which is the bar |
| grep-q pipe guard `PJ_TRIPLES` (316 on main) | expected unchanged (nothing in `issues.sh` pipes into the stubbed verb; the stub's own `jq` is the real one); recount | run `.claude/hooks/grep-q-pipe-guard.test.sh` once; if the count moves, edit `PJ_TRIPLES` with a note and add `PRODUCER_JOIN` rows in the existing vocabulary |
| Telemetry marker drift guard | none expected: all new markers are emitted from `scripts/lib/issues.sh`, outside the `skills/*/scripts/*.sh` walk, and SKILL.md sentinels are filtered by the git/worktree domain regex; the suite assertion in Phase 5 keeps a marker from drifting into the walk | `cd apps/web-platform && npx vitest run test/git-lock-marker-telemetry.test.ts` |
| `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` | one row each for `issues.test.sh` | `python3 scripts/regenerate-shard-manifest.py --incremental --write` (floor rows), then set the measured duration from one run; enforced by `scripts-shard-manifest.test.sh` and `scripts-shard-totality.test.sh` |
| `plugins/soleur/test/fixture-relative-assert.baseline.txt` | rows for `issues.sh`, `issues.test.sh`, `gh-stub.sh`; `render.sh` count re-checked after the extraction | `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline` in the same commit as the source edits, then the plain check |
| C4 (`model.likec4.json` freshness, `c4-count-parity`, syntax, render) | JSON regenerated; counts unchanged | commands in the Architecture Decision section |
| Orphan-suite lint | none (auto-globbed) | `bash scripts/lint-orphan-test-suites.sh` |

### Phase 7 — Follow-up issue, review, ship

- Live endpoint check (D8): stub-only in this PR; the tracked follow-up issue #11956 (filed at plan time, milestone Phase 4, `Mandated-By: wg-when-deferring-a-capability-create-a`) is titled for the live run of `issues --create` against a private repository the operator creates, with the exact commands, what to confirm (`sub_issue_id` semantics, the 201 shape, which of 403/404/410/422 a plan without the feature returns, gojq behaviour of the shipped `--jq` expressions) and the re-evaluation trigger (before the first customer run). The PR body states "live endpoint check: stub-only, tracked in #11956". Re-run the open code-review overlap filter at work start.
- Review: full `soleur:review` panel including `user-impact-reviewer` and `observability-coverage-reviewer`; PR-A needed 60 triaged findings, so budget a fix round. CI is the full-suite gate; run locally only the `issues`, `render`, `wording`, `redact-gate` and `identity` suites, the C4 set, `components.test.ts`, the guard-contract lint and the telemetry test.
- Ship: the PR body carries `Refs #11910` (never Closes), a `## Changelog` section, the GDPR advisory output, the live-check line above (follow-up #11956), and the draft-requires-counsel note unchanged from PR-A. The existing draft PR #11949 is re-titled.

## Files to Create

- `plugins/soleur/skills/launch-check/scripts/lib/issues.sh`
- `plugins/soleur/skills/launch-check/references/issue-body.template`
- `plugins/soleur/skills/launch-check/test/issues.test.sh`
- `plugins/soleur/skills/launch-check/test/gh-stub.sh`
- `plugins/soleur/skills/launch-check/test/fixtures/plan-sample/plan.tsv`
- `plugins/soleur/skills/launch-check/test/fixtures/plan-sample/epic.md`
- `plugins/soleur/skills/launch-check/test/fixtures/plan-sample/issues/CI-01.md`
- `knowledge-base/project/specs/feat-one-shot-launch-check-pr-b-epic-issues/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-launch-check-pr-b-epic-issues/decision-challenges.md` (created by this plan)

## Files to Edit

- `plugins/soleur/skills/launch-check/scripts/launch-check.sh` (`issues` subcommand, header comment and exit-code table, `is_headless` delegate)
- `plugins/soleur/skills/launch-check/scripts/lib/common.sh` (`lc_is_headless`)
- `plugins/soleur/skills/launch-check/scripts/lib/render.sh` (`lc_prepare_inputs`, `lc_compute_gaps`)
- `plugins/soleur/skills/launch-check/references/phrases.txt` (epic and preview prose)
- `plugins/soleur/skills/launch-check/SKILL.md` (accept/epic flow, hard rules, abort table; no `description:` change)
- `plugins/soleur/skills/launch-check/test/wording.test.sh` (lint `issues.sh` and the template; prose-literal check)
- `knowledge-base/engineering/architecture/decisions/ADR-314-launch-check-baseline-manifest-and-finding-contract.md` (dated amendment of decisions 6 and 7, one alternatives row)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (second `plugin -> github` edge; `launchcheck` description)
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated)
- `scripts/ci-pr-affected-audit.accept.tsv`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`
- `plugins/soleur/test/fixture-relative-assert.baseline.txt`
- `.claude/hooks/grep-q-pipe-guard.test.sh` (only if the recount moves `PJ_TRIPLES`)

Not edited by design: `plugins/soleur/test/components.test.ts`, `apps/web-platform/server/git-lock-marker-telemetry.ts`, `plugins/soleur/test/skill-body-budget.json`, `test/lib.sh`, `knowledge-base/marketing/content-strategy.md` (the held row stays held), and the roadmap row 4.14 text (it already names PR-B).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `issues --preview` makes no `gh` write (stub log has zero write records); it refuses with `report-missing` when no report exists and `report-stale` when a to-be-filed gap is not `open` in the report; it prints the repo, visibility, fork flag, the cap rule and the exact `--create` command, and warns on PUBLIC/UNKNOWN.
- [ ] `issues --create` refuses with no `--plan`, refuses under `CI=1` and `LAUNCH_CHECK_HEADLESS=1` with zero `gh` calls of any kind, and records zero writes under `--dry-run` (Guard 1); calling `lc_gh_write` directly under `CI=1` or `LC_DRY=1` also reaches nothing.
- [ ] Preflight failures (`gh` absent, unauthenticated, repo unresolved, issues disabled, archived, no push permission) each yield preview `mode=report-only reason=<cause>` with exit 0 and no plan, and create `issues-unavailable` exit 2. A closed epic prints a warning in preview and aborts `epic-closed` on create; two epic candidates abort `epic-ambiguous`.
- [ ] With 35 open gaps the preview plans 30 and lists 5 as capped by severity then id; the epic's marked section lists the remainder; excluded domains and classes are omitted.
- [ ] Labels: only absent `lc:` labels are created; a pre-existing label is untouched; no label write is recorded for it.
- [ ] Sub-issue linking: success links every item; a 404, 403, 410 or 422 on the first link latches the run to the task list (no further link calls) with `fallback=task-list` and `- [ ] #N` lines in the epic section.
- [ ] A run that failed after 3 of 7 creates, and a run killed between a create and its link, both resume: re-running the same plan creates only the missing issues, links the orphan once, and the fake tracker holds one epic and each id once; a closed marked issue is not recreated.
- [ ] Epic edits touch only the marked section; the epic body is re-read just before the splice (a customer edit made mid-run survives); customer text outside the markers is byte-identical, including with CRLF; damaged markers produce no PATCH and `epic-section=markers-damaged`.
- [ ] Redaction: a tampered plan body with a synthesized secret aborts rc 1 before any write; every sent file was scanned; SEC-01/SEC-02 issues carry only the count phrase and a hostile facts file with a secret path never reaches a body, a plan file or a recorded argv; `@scope/pkg` evidence is inside a code span; the `&` in "Tests & CI/CD" renders intact; `issues.sh` contains no `${...//...}` substitution.
- [ ] A hand-edited plan (unknown label, newline in a title, `../` in an id, symlink, oversized file, `@file` operand outside the plan directory, `state` field on a PATCH) aborts `plan-invalid` or `write-shape-refused` with zero writes.
- [ ] PUBLIC or UNKNOWN LIVE visibility requires `--confirm-public` (a plan recorded as PRIVATE does not waive it); a plan executed against a different resolved repo aborts `plan-repo-mismatch`; accepting a finding in the report after the preview makes `--create` abort `report-stale`.
- [ ] `issues --check-plan --plan test/fixtures/plan-sample` prints `SOLEUR_LAUNCH_CHECK_PLAN_OK` with no network or scanner.
- [ ] A rate-limit failure stops the run with `issues-incomplete`, names the rate limit and the re-run line, and the re-run completes.
- [ ] `render --dry-run` output is byte-identical before and after the `lc_prepare_inputs`/`lc_compute_gaps` extraction for the three reference fixtures; the `render`, `identity`, `wording` and `redact-gate` suites are green.
- [ ] The guard-contract lint on this plan passes: `python3 scripts/lint-guard-contract.py`.
- [ ] Ratchets: `components.test.ts` green with no budget edit; `lint-skill-body-budget.py` green; accept rows added so the `ci-pr-affected-replay.py ratchet` gap count is not above a run on main (main's red `affected-index-ratchet` is not this change's); `PJ_TRIPLES` recounted and either unchanged or updated with a note; the telemetry drift test green without edits to `git-lock-marker-telemetry.ts`; duration, shard-leg and fixture-baseline rows present for the new suite.
- [ ] ADR-314 carries a dated amendment (decisions 6 and 7 true to the built behaviour), status still `adopting`; `model.c4` edge added and the `launchcheck` description rewritten; `model.likec4.json` regenerated; `c4-code-syntax`, `c4-render`, `c4-count-parity` and `c4-model-freshness` green.
- [ ] `gdpr-gate` re-run on the actual diff; advisory output in the PR body.
- [ ] PR body: `Refs #11910`, no `Closes`; "live endpoint check: stub-only, tracked in #11956" with the follow-up issue filed.
- [ ] No run of launch-check against any customer repo; no repository created; the content-strategy held row is unchanged.

### Post-merge

- [ ] None required for the merge. The live endpoint check (follow-up issue), the first customer run (after roadmap 4.12's executed instrument) and closing #11910 stay with the operator.

## Test Scenarios

- Given a rendered report with 3 open gaps, when `issues --preview` runs against a PRIVATE stub repo, then a plan directory exists (mode 700) with 3 `create` rows, zero write records, and the ISSUES_PLAN marker shows `create=3`.
- Given the report is missing, when preview runs, then abort `report-missing`; given facts rescanned after the report was rendered, then abort `report-stale`.
- Given `CI=1`, when `--create` runs, then rc 2 `headless-write-refused` and the stub log is empty (not even reads).
- Given `--create --dry-run`, then zero write records.
- Given a PUBLIC stub repo, when preview runs, then the warning and the `--confirm-public` command line are printed; when `--create` runs without the flag, then abort `confirm-public-required`; given a plan recorded PRIVATE but a live PUBLIC repo, the same abort.
- Given 35 gaps, then 30 `create` rows and 5 `capped`, the capped ids in the epic section and the cap line in the preview.
- Given the sub-issue endpoint returns 404 (then, separately, 422) on the first link, then no later link call is recorded and the epic section lists `- [ ] #N` for every created item.
- Given the stub fails the 4th create, then the run ends `issues-incomplete` with `created=3`; re-running the same plan creates the remaining items and the tracker holds each id once. Given the stub kills the run after a create and before its link, the re-run links the orphan and creates nothing twice.
- Given a closed marked issue, then it is reported closed-by-customer and not recreated; given a marked issue with no parent link, then exactly one link call and no create; given a filed issue whose gap is now resolved, the preview says so.
- Given a pre-existing `lc:severity-high` label with a custom colour, then no label write is recorded for it.
- Given customer text above and below the epic markers (also CRLF), then a re-run leaves it byte-identical; given a customer edit between the listing and the PATCH, the edit survives; given a deleted end marker, then no PATCH.
- Given a tampered body with a synthesized secret, then rc 1 and zero writes; given the sentinel exiting 2, then rc 2 and zero writes.
- Given SEC-01 gaps on a repo with a planted secret, and a hostile facts file carrying a secret path, then the issue body holds only the count phrase and the path appears nowhere in recorded argv, bodies or the plan directory.
- Given a finding accepted in the report after the preview, then `--create` aborts `report-stale` with zero writes.
- Given the plan directory is gone, then `plan-missing` with the recovery sentence.
- Given a rate-limit failure on a create, then `issues-incomplete` naming the rate limit and the re-run line, and the re-run completes.
- Given the stub is invoked with an unknown flag, or a read without `-X GET`, then exit 64 or a recorded violation (harness rows).
- Given a fork, then the preview line names the resolved `owner/name` and the fork flag.

## Risks and Sharp Edges

- **Consent is not script-enforced.** `--create` executes a saved plan, refuses headless, and for public repos needs `--confirm-public`, but an agent can still call it; the guard is the SKILL.md instruction (separate Bash call, separate question) plus the harness permission prompt, recorded in ADR-314.
- **Repository resolution.** `gh` resolves the base repo from remotes; a fork may resolve to its upstream, and with several remotes and no TTY it fails instead of prompting. The slug is resolved once, shown in the preview with the fork flag, bound into the plan, and every call carries `repos/<slug>` explicitly. `GH_REPO` is unset for the run.
- **Removing the scope label refiles.** If a customer removes `lc:launch-check` from an issue, the next run does not see it and files the gap again (CTO T2); the issue template's closing sentence says to close, not unlabel.
- **A collaborator can plant a labelled marker** to suppress a filing, or a lower-numbered epic marker. Mitigated: the lookup keeps only number, state, PR flag and an anchored marker; an epic needs `lc:epic`, no PR flag and exactly one marker pair or the run aborts `epic-ambiguous`; the preview lists filed ids with their issue numbers.
- **Sub-issue API behaviour is unverified for plans and limits.** The REST page is silent on permission and the per-parent maximum; GitHub's documented cap (100 sub-issues per parent, 8 levels) is far above 30. The task-list fallback covers it and the live check is the tracked follow-up (stub-only here).
- **The stub uses real `jq`, customers run `gh`'s gojq.** `scan` and `@tsv` on null can differ; the expressions stay inside the common subset and the follow-up live run is where gojq is exercised.
- **Bash 3.2 on macOS.** No `declare -A`, no `mapfile`, no `${a[@]}` of an empty array under `set -u`, no `${...//...}` with `&`, no `awk -v` for text with backslashes, no `stat -c`. A source scan covers the substitution rule; the suite runs on the CI bash.
- **`-f` versus `-F` in `gh api`:** `-F` converts `true/false/null/integers` and reads `@file`; `sub_issue_id` must be sent with `-F` (integer), titles with `-f` (raw string, no magic), bodies with `-F body=@file`. A `@file` operand must resolve inside the plan directory.
- **`gh api` reports status only on stderr** (`gh: ... (HTTP 404)`); a 403 may be a secondary rate limit, which is recognised first by its text.
- **`gh --jq` cannot take `--arg`.** Interpolated numbers are digit-validated before use.
- **`grep -q` after a pipe under `pipefail`** can read a match as a miss (#9217); use here-strings everywhere in the new files. `PJ_TRIPLES` counts stub-verb producers; do not pipe into the stub.
- **The recorder canary.** A stub that does not record is the classic vacuous harness: the suite fires a direct canary write and asserts the log line before trusting any "zero writes" row.
- **Accept rows are anchor-keyed** (content hash plus ordinal), so changing a path-naming line of `lib.sh` or of an existing suite moves anchors. Touch neither.
- **The hook that blocks the literal issue-create command string** applies to Bash tool calls in this repo, not to shipped scripts or stub files; the scripts use `gh api` anyway.
- **Plan edits.** Keep each guard heading in the exact `### Guard <n> — <name>` form for `lint-guard-contract.py`.

## Non-Goals

- Running launch-check against any customer repo (gated on roadmap 4.12); the blog post and feature tweet (held).
- Creating any GitHub repository, or a live endpoint run, in this PR (tracked follow-up).
- A hosted variant, telemetry, or any share-back path.
- Closing, reopening, relabelling or editing a customer's issues (the tool is create-only; the epic's marked section is the only edit).
- Writing issue numbers into the report state block; auto-remediation; a readiness score or certification wording.
- Retry/backoff machinery, a plan expiry clock, a per-item sub-issue fallback, an `--exclude-id` flag, a `--new-epic` flag.
- Changing the skill `description:`, the cursor mirror, `commands/sync.md`, or the onboarding runbook.
- Fixing the red `affected-index-ratchet` on main unless it blocks this change.
