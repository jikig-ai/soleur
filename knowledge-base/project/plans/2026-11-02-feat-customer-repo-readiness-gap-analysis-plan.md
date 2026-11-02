---
title: "feat: customer-repo production-readiness and Soleur best-practice gap analysis skill (launch-check)"
date: 2026-11-02
slug: customer-repo-readiness-gap-analysis
branch: feat-prod-readiness-gap-analysis
issue: 11867
type: feat
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
spec: knowledge-base/project/specs/feat-prod-readiness-gap-analysis/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-11-02-prod-readiness-gap-analysis-brainstorm.md
---

## Overview

Add one new skill, `launch-check`, that a customer runs in their own Claude Code session against their existing GitHub repo. It produces (1) production-readiness findings across four domains and (2) a gap report of Soleur engineering practices the repo lacks, writes both into one living markdown file, and, after a preview and an explicit confirm, files an epic with severity-ranked, domain-labeled sub-issues in the customer's own repo. The analysis writes only the report file; the only other write is the confirm-gated issue creation. It is NOT a `/soleur:sync` area (sync is a write path the web platform runs headless on every clone, `apps/web-platform/server/auto-sync-trigger.ts:84`, and `sync.md` carries known customer-repo defects, #7452).

Skill name `launch-check` follows the CMO naming lean ("Launch Check"); the words audit, score, certified, compliant and passed are banned in its output.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality (verified) | Plan response |
|---|---|---|
| "Extend the `guards.tsv` precedent for the baseline manifest" (FR3) | `guards.tsv` has 4 v1 rows and 1 v2 row (`block-rm-rf`); it covers guards only. The audit file `guardrail-audit.md` classifies hooks 0 generic / 10 generic-after-extraction / 48 soleur-coupled and lints 9 / 8 / 30. | The portable Soleur baseline is small. Baseline checks for guards are **generated at runtime from `guards.tsv`** (no second list). Non-guard baseline items (conventions, ADR dir, constraint gate) are a short catalog in `checks.tsv`. v2 and still-`generic-after-extraction` items are shown as "not installable yet", not as gaps. |
| "Reuse the code-to-prd walker" (TR1) | The walker lives inside `code-to-prd.sh` (`git ls-files -c -o --exclude-standard`, `is_excluded()` at ~line 141, realpath symlink rejection, Layer 1-3 redaction); it is not a library. `is_excluded()` covers only six patterns: `.env*`, `secrets.*`, `*.pem`/`*.key`, `credentials.*`, `master.key`, `.git/*`. The CLO's extra never-read classes (tfstate/tfvars, DB dumps, CSV, fixture data) are NOT in it. | Do not refactor `code-to-prd` in this PR. `safe-walk.sh` carries those six patterns (pinned as a superset of `code-to-prd`'s by a parity test) PLUS launch-check's own additions (tfstate, tfvars, `*.sql` dumps, `*.csv`, `*.sqlite*`, fixture/seed data), covered by their own positive tests. |
| "Pin the baseline in `guards.tsv`" | `guards.tsv` rows are `name verdict surfaces templates default_mode deps source_files emits tier`; `tier` is the LAST column. An `emits` artifact existing does not mean the guard is active (installs are advisory-first and the hook may be unregistered in `settings.json`). | Baseline guard checks report "artifact present, advisory/unverified" (never "satisfied") and read `tier` by header name, not position. |
| Harness mirror path | The `verification-scaffold` precedent mirrors at `plugins/soleur/cursor/skills/soleur-verification-scaffold/SKILL.md`; there is no `plugins/soleur/skills/soleur-*` directory. | Mirror goes at `plugins/soleur/cursor/skills/soleur-launch-check/SKILL.md`. |
| "Quote output through redact-sentinel + gitleaks" (TR2) | `code-to-prd` requires `gitleaks` on PATH and exits 2 (preflight failed, nothing written) when it is absent; it reuses `incident/scripts/redact-sentinel.sh`. | Same contract: missing or non-runnable `gitleaks` is a preflight failure with a remedy line, never a silent skip. |
| "Epic with sub-issues" (FR6) | GitHub REST: `POST /repos/{o}/{r}/issues/{n}/sub_issues` takes `sub_issue_id` (the issue's database `id`, not its number); permission, per-parent maximum and nesting depth are undocumented on the REST page. | Use the endpoint, take `.id` from the create response, and fall back to a task list (`- [ ] #N`) in the epic body when the call returns 403/404/410/422. Verify against a real throwaway repo in the work phase (TR4). |
| "Add to `/soleur:sync`?" (operator) | Only `go`, `sync`, `help`, `version` may be commands (`plugins/soleur/AGENTS.md`); workflow capability is a skill. | New skill; `sync` gets a one-line pointer in its closing summary only. |
| "`kb-blueprint.json` / ADR-171 manifest" (repo research) | `plugins/soleur/kb-blueprint.json` does not exist; ADR-171 is still adopting. | Not a dependency. The report path is a constant in the skill; no manifest read. |

## Research Insights

**Premise Validation (Phase 0.6).** Cited items checked: #7452 OPEN (sync customer-repo follow-ups), #7442 CLOSED (script paths cwd-relative; two scripts outside the payload), #7331 CLOSED, #8981 OPEN (Skouer checkpoint, overdue since 2026-08-20), PR #11867 draft. ADR corpus grepped for "readiness", "gap analysis", "customer repo": hits were unrelated infra ADRs; no ADR rejects this mechanism. No prior plan, issue or ADR covers a customer-repo launch check. The brainstorm's own research was re-read and its cited paths re-verified: `guards.tsv`, `guardrail-audit.md`, `code-to-prd.sh:124-194`, `redact-sentinel.sh`, `harvest-debt.sh`, `auto-sync-trigger.ts:84`.

**Property List (Phase 0.6b).**
1. A customer can learn, from one file, what stands between their repo and opening to users.
2. A customer can learn which Soleur practices their repo lacks and the command that adds each.
3. Re-running tells the customer what closed and what is new.
4. Gaps are trackable as ranked, labeled issues without hand-copying.
5. Running it can never leak a secret or personal data into a report, an issue, or Soleur.
6. Nothing in the customer's repo changes except the report file and issues the customer confirmed.

**Cut List (Phase 0.6b).** Mechanism → property it would buy → what already covers it.
- New `/sync` area → property 1 → the new skill buys it without sync's headless write path.
- Per-gap auto-issues without preview → property 4 → cut; the confirm-gated preview buys the same with property 6 intact.
- A new hand-listed Soleur-baseline inventory → property 2 → `guards.tsv` already is the guard list; derive from it.
- A readiness score → property 1 → a findings list ordered by severity buys it without certification wording (CLO/CMO).
- Hosted variant → property 1 → the local skill covers it; hosted needs an Art. 28(3) instrument (non-goal).
- Auto-remediation → property 2 → `verification-scaffold` and `constraint-scaffold` already install; findings only name them.
- (Plan review, 2026-11-02) Closing resolved issues from the tool → property 4 → cut; ask 4 is create-only, the report lists "Closed since last run", the customer closes issues.
- Confirm-hash token and `--confirm <hash>` → property 6 → cut; `--create` executes exactly the saved preview plan, and the skill asks the customer before invoking it.
- `gh repo view` visibility branch and `fingerprint` identity key → property 5 → cut; secret-class locations are never written to any file or issue, whatever the visibility.
- Runtime wording lint → property 5/6 → cut; all prose is static (catalog, templates, banner), so a test lints the sources; judged findings carry no free text.
- `promote_after` column, `--self-check` → no property → cut.
- `/soleur:sync` pointer and onboarding-runbook step → none of the six properties → cut (revisit after the first customer run).
- Free-text LLM findings → property 5 → cut; judged items use a closed schema (status, severity enum, evidence ids; title and remedy come from `checks.tsv`).

**Value-proposition measurement (Phase 0.6c).** Not applicable: the justification is a new capability, not a cost or performance saving.

**Repo state.** `verification-scaffold` PR #10744 is the closest addition precedent; its 41-file touch list (README counts, `docs/_data/skills.js`, a harness-mirror SKILL.md, `model.c4`/`views.c4`/`model.likec4.json`, `components.test.ts`, `scripts/lib/test-affected-paths.sh`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, `fixture-relative-assert.baseline.txt`) is the registration checklist. `gh` is 2.103.3.

**Institutional learnings applied.** #7442 learnings: anchor producers to plugin identity, presence-guard each producer invocation, content must ship inside `plugins/soleur/` (`2026-09-18-a-plan-can-specify-a-mechanism-the-packaging-boundary-forbids.md`). `2026-06-30-constraint-scaffold-verify-every-assumed-capability...`: verify every capability the emitted output depends on and label unbuilt pieces "planned". `2026-07-16-advisory-first-precedent...`: advisory phases need a machine-enforced expiry. `2026-05-15-fail-closed-redaction...`: build redaction before choosing the output path. `2026-05-12-...write-mostly-artifact...`: a ledger needs a closure mechanic, which the re-run diff provides. `2026-10-08-...session-start-mcp-overwrite`: never touch a customer's `.mcp.json`.

**Conventions.** Skills are flat under `plugins/soleur/skills/<name>/` (`plugins/soleur/AGENTS.md`); test fixtures are synthesized only (`cq-test-fixtures-synthesized-only`); tests that spawn `git` use the constructed environment helpers; any test suite is auto-globbed from `plugins/soleur/test/*.test.sh` or the skill's own `test/`.

## Open Code-Review Overlap

None. Checked the open `code-review` issues against `plugins/soleur/README.md`, `plugins/soleur/docs/_data/skills.js`, `plugins/soleur/commands/sync.md`, `plugins/soleur/skills/verification-scaffold`, `model.c4` and `components.test.ts`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "They should be able to create a production readiness checklist and have a gap analysis report for them to go production when they want to open up to their own customers" [brief] | Phase 1 scanner + Phase 2 render, readiness checks in `checks.tsv` | mapped |
| 2 | "a gap analysis on Engineering best practices used in Soleur missing from their repository that should be added" [brief] | Phase 2 baseline derivation from `guards.tsv` + baseline catalog rows | mapped |
| 3 | "How can we implement this and where should it live? In the /sync command?" [brief] | ADR-314 + `## Architecture Decision` (answer: new skill, not a sync area) | mapped |
| 4 | "1 + Epic creation with sub issues to track all with a severity ranking and a domain labeling (security, tech debt, performance, redundancy, ...)" [dialogue] | Phase 5 issues preview/create + severity rubric + labels | mapped |
| 5 | "Both reports in v1" [dialogue] | Phases 1-2 deliver both reports in the same release | mapped |
| 6 | "We should also test it against this very repo" [dialogue] | Phase 3 self-test (dry-run) on jikig-ai/soleur | mapped |
| 7 | "Security & secrets, Tests & CI/CD, Tech debt & architecture, Reliability, performance & ops" [dialogue] | `checks.tsv` domain column, four label values | mapped |
| 8 | "New read-only skill (Recommended)" [dialogue] | Whole plan | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `launch-check` SKILL.md + `scripts/launch-check.sh` | "New read-only skill (Recommended)" | asked |
| `checks.tsv` readiness catalog (four domains) | asks 1, 7 | asked |
| Baseline checks derived from `guards.tsv` | ask 2 | asked |
| Living report file with re-run diff | "1 + Epic creation..." (the "1" was the living-file option) | asked |
| Issue epic, severity ranks, domain labels | ask 4 | asked |
| Self-test dry-run on this repo | ask 6 | asked |
| `safe-walk.sh` + parity test with `code-to-prd` | — | inferred — justification: the never-read list is the leak control for a tool run on customer repos; a copy without a pinning test drifts (three divergent git-env copies preceded the shared helper) |
| Redaction gate on report and issue bodies | — | inferred — justification: `single-user incident` threshold; a leaked secret in a committed report or public issue is a Soleur-caused incident |
| Banner + banned-word lint | — | inferred — justification: CLO/CMO conditions; a readiness verdict can be read as assurance |
| Roadmap row 4.14 + tracking issue | — | inferred — justification: `wg-every-feature-listed-in-a-roadmap-phase` requires an issue for a roadmap feature |
| Registration mirrors (README, docs data, harness mirror, test registries, C4) | — | inferred — justification: the harness-parity, component-count and c4-count-parity gates fail without them |
| ADR-314 | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` (a new baseline-source contract) |
| Stack detection + `unsupported-stack` status | — | inferred — justification: Node-centric detectors would file false gaps as real issues on Python/Rails/Go repos |
| `accepted` state + closed-marked-issue-is-accepted | — | inferred — justification: without a suppression path a false positive is re-filed on every run and the tool is abandoned |
| `retired-checks.tsv` + `schema_version` | — | inferred — justification: a renamed or removed check id would render as a false "closed" plus "new" after a plugin update |
| Issue cap per run | — | inferred — justification: a path-keyed check on a monorepo could otherwise file hundreds of issues in one confirm |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur`, `knowledge-base`, `scripts`
- Planned files: ~38 | Estimated changed lines: ~2300 (scripts ~800, tests ~800, references ~300, registration/docs ~250, `model.likec4.json` regen not counted)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — PR-A (Phases 0-4: scanner, baseline, render, registration, ADR/C4, self-test) then PR-B (Phase 5: issue epic creation, which is the only code that writes to a customer's tracker, so it gets its own review and its own stub-`gh` test surface). Both land before the first customer run, so v1 scope is unchanged. If the operator prefers one PR, the plan runs unchanged in order.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Marketing

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** New skill with a deterministic scanner, a baseline derived from `guards.tsv` and shipped inside the plugin payload, and confirm-gated writes; sync is a write path and is the wrong home. Medium complexity.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** The need is a hypothesis from one tester (n=1) and must not displace live Phase 4 protocol work (#8981, tester #2 terms). Operator chose the larger v1 over the CPO's smaller probe; the plan keeps the usefulness question at the cohort checkpoint as the validation hook. No UI surface.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Local CLI on the customer's key is supplier posture; hosted needs an Art. 28(3) instrument first. Redaction, disclaimer banner, no telemetry, no Jikigai-keyed runs on tester content (C1). Open counsel items: BUSL-1.1 footer wording and T&C coverage of CLI outputs.

### Marketing (CMO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Name "Launch Check"; findings list, not a score; no quantitative claims at n=1; a Skouer case study needs the testimonial opt-in and tester terms first.

### Product/UX Gate

**Tier:** none
**Decision:** not applicable (no `components/**/*.tsx`, `app/**/page.tsx` or layout files in Files to Create/Edit; output is CLI text, markdown and GitHub issues)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** not applicable (no UI surface)

**Brainstorm-recommended specialists:** none named by a leader.

## User-Brand Impact

- **If this lands broken, the user experiences:** a readiness report that misses a real gap or invents one, and an epic of wrong issues in their own tracker that they must clean up.
- **If this leaks, the user's data is exposed via:** a secret or personal-data string quoted into the committed report file or into a public issue body, or a file outside the never-read list read into the LLM step.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one leaked credential in a customer's committed report is a Soleur-caused breach for that user, so the per-user tier applies, not the aggregate one.

`requires_cpo_signoff: true` is set. CPO sign-off is carried from the brainstorm (CPO assessed at Phase 0.5); `soleur:engineering:review:user-impact-reviewer` runs at review time.

## GDPR Gate (advisory, plan Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Invoked on trigger (b) (brand-survival threshold `single-user incident`) although no canonical regulated-data path is touched: the plan adds no migration, `.sql`, auth or API-route file.

- `GDPR-Art-6`, `GDPR-Art-5e`, `GDPR-Art-17`, `GDPR-Art-17-caller`, `GDPR-Art-9`: not triggered; the plan adds no schema column or table and no Soleur-held personal data.
- `GDPR-Chapter-V`: not triggered for Soleur. The LLM step runs in the customer's own Claude session under the customer's own Anthropic terms; Soleur operates no server-side path and receives no data (no telemetry, Guard 1 and the observability block). A hosted variant would trigger it and is a non-goal.
- Suggestion: the report quotes only `path:line`, never content, and the redaction gate covers personal-data classes as well as secrets, which is the Art. 32 / Art. 5(1)(c) minimisation posture for third-party code the tool reads. Guard 1 and Guard 4 are the enforcement.
- Suggestion: the tool reads a customer's repository, which can contain end-user personal data (the Skouer determination records officer data). The work phase re-runs this gate on the actual diff, and the Art. 28(3) instrument (condition C1) must exist before any Jikigai-keyed run on tester content.
- Result: no `Critical` finding, so no `compliance-posture.md` write is proposed.

## Architecture Decision (ADR/C4)

### ADR

Create **ADR-314 "Baseline manifest and finding contract for customer-repo launch check"** via `soleur:architecture create`. Decision: (a) the skill is a read-only skill, not a sync area; (b) the Soleur-baseline portion of the report is derived at runtime from `verification-scaffold/references/guards.tsv`, never hand-listed, with `checks.tsv` carrying only non-guard rows; (c) findings use a stable id and a state block so re-runs diff; (d) writes are limited to the report file and issues created from a saved preview plan after the customer's confirmation; (e) packaging constraint: every file the skill reads at run time ships inside `plugins/soleur/` (identity-resolved plugin root, fail closed when `guards.tsv` or `redact-sentinel.sh` is missing); (f) redaction trust boundary: judged findings use a closed schema, secret-class locations are never written anywhere, consent for issue creation is skill-enforced plus the harness permission prompt (the script cannot prove human approval). Alternatives considered: sync area (rejected: headless write path on every clone), `verification-scaffold --audit` (rejected: four guards cannot express production readiness), hand-listed inventory (rejected: ADR-193 "derived, never listed"). The ordinal is provisional; `soleur:ship` re-verifies against `origin/main` (current highest is ADR-313).

### C4 views

Read all three files under `knowledge-base/engineering/architecture/diagrams/` (`model.c4` 1067 lines, `views.c4` 148, `spec.c4` 54). Enumeration:
- External human actors: the founder/customer, already modeled as `founder` with edges to each harness and to `platform.plugin` through them. Already-modeled.
- External systems: GitHub (`github` system, with `plugin -> github` at `model.c4:701` for the opt-in release lookup). The customer's own repo is the same vendor but a different data owner; a second edge is added, not a new element. Anthropic is reached through the harness, already modeled.
- Containers/data stores: the customer's local repo files and `knowledge-base/`; no new store, no Soleur-hosted sink.
- Access relationship changes: none for Soleur-hosted systems.
- Counts: `model.c4:198` says "105 workflow skills" and is mirrored four times in `model.likec4.json`; the new skill moves it to 106 (same-length swap, mirrored by hand at all five sites, or regenerated with `scripts/regenerate-c4-model.sh`). `c4-count-parity.test.sh` must stay green.

Tasks: add a `launchCheck` component under `platform.plugin` next to the `verification-scaffold` component (`model.c4:284`), add edge `plugin -> github "launch-check: files the customer's epic and sub-issues in the customer's OWN repository through gh with the customer's credentials, confirm-gated; no Jikigai-hosted sink" { technology "HTTPS (GitHub REST API via gh)" }`, include the component in the plugin component view in `views.c4`, bump the skill count, regenerate `model.likec4.json`, run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

The ADR and C4 changes ship in PR-A; nothing about them waits on PR-B (the issue-writing edge is documented as part of the target state, status "adopting" until PR-B merges).

## Guard Contract

### Guard 1 — Redaction write-boundary gate

**Property.** No byte matching a secret or personal-data class, and no secret-class location, reaches the report file or any issue body.

**Assembly.** Every write flows through one chokepoint, `emit_checked()` in `scripts/lib/redact-gate.sh`: the report write in `render` and each issue body in `issues`. It writes the exact bytes to a temp file in the destination directory, runs `redact-sentinel.sh` (Layer 2) and `gitleaks detect --no-git --source <tempfile>` (Layer 3) with `|| rc=$?` capture (a finding is rc 1, a scan that did not run is rc 2, neither is allowed to trip `set -e` silently), then renames; a `trap` removes the temp file on any abort so an aborted run leaves no file. There is no other redirect to the report path and no `gh issue create` or `gh api` write outside `emit_checked`/`gh_write`; a source-scan test enumerates every write call in the skill's scripts. Judged findings use a closed schema (status, severity enum, evidence ids; title and remedy are looked up from `checks.tsv`): an extra string field is rejected before rendering, so the LLM cannot carry free text past the scanner. Secret-class locations are never written anywhere (count only; locations go to stdout under `--show-secrets`), and state-block ids are `check-id + 8-char path hash`, never a gitleaks fingerprint.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Plant a synthesized secret-shaped string in a fixture file and remove the sentinel call from `emit_checked` | RED |
| 2 | Make `gitleaks` resolve to a stub that exits 0 printing nothing for every input (a gate reporting "0 findings" on a planted secret) | RED |
| 3 | Add a second write site (a debug dump to `$OUT.debug`) after a compliant first | RED |
| 4 | Make `redact-sentinel.sh` exit 2 (scan did not complete) | RED (no file left behind; exit 2, not a finding) |
| 5 | Add an extra free-text string field to a judged finding | RED (schema reject) |
| 6 | Render a secret-class finding's `path:line` into the report | RED |

**Harness rows.** Edit the suite so the planted-secret string is replaced by a clean one: the suite must go RED (a suite with no planted secret asserts nothing). Must-PASS: a report whose evidence cites a path containing the word "secret" but no secret value is written.

**Anchor.** The `gitleaks` pin is a constant shared with `code-to-prd` and compared to it by the parity test; weakening it means editing a file the test also reads.

### Guard 2 — Saved-plan-only issue writes

**Property.** No `gh` write (issue create, label create, sub-issue add, issue body edit) runs except by executing a saved preview plan, and none runs under `--dry-run`.

**Assembly.** Every `gh` write goes through `gh_write()` in `scripts/lib/issues.sh`. `issues --preview` writes the plan file and prints its path; `issues --create --plan <file>` executes exactly that file and refuses without one; `--dry-run` and any headless/no-TTY invocation make `gh_write` return without calling `gh`. Epic edits touch only the text between `<!-- launch-check:begin -->` and `<!-- launch-check:end -->`. A source-scan test greps the skill for `gh issue create`, `gh issue edit`, `gh api -X`, `gh label create` outside `gh_write`. Consent is skill-enforced (SKILL.md requires the customer's confirmation via `AskUserQuestion` before `--create`) plus the harness's own permission prompt on that command; the script alone cannot prove human approval, and the plan records that residual.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Call `--create` with no plan file | RED |
| 2 | Run `--create` with `--dry-run` while a stub `gh` records invocations (a dry-run that calls `gh` once is vacuous) | RED if any write call is recorded |
| 3 | Add a second `gh issue create` outside `gh_write` after a compliant first | RED |
| 4 | Make the fallback rewrite the whole epic body instead of the marked section | RED (customer text outside the markers must survive) |
| 5 | Run `--create` with no TTY (headless) | RED (refused) |

**Harness rows.** Edit the suite so the stub `gh` records nothing: it must go RED (a recorder that cannot record proves nothing). Must-PASS: a plan file whose findings are in a different order from a re-generated preview is still executed as saved.

**Anchor.** The plan file is the single source of what runs; the stub-`gh` recorder in the test is the independent witness of what `gh` was actually called with.

### Guard 3 — Baseline derived from the guard manifest

**Property.** The Soleur-baseline guard checks the scanner emits are exactly the `tier=v1` rows of `verification-scaffold/references/guards.tsv`, and an unreadable or empty manifest is a hard failure, not "zero baseline checks".

**Assembly.** One chokepoint, `scripts/lib/baseline.sh`, reads `guards.tsv` at runtime (column positions resolved by header name) and emits one `BASE-<guard>` check per `tier=v1` row; `checks.tsv` carries no row for those guards, only the non-guard baseline rows (agent-conventions file, ADR directory, the Next.js import-boundary gate). The test derives the expected name set from `guards.tsv` with `awk` and compares by name identity, never by count.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Hard-code a fifth guard name in `baseline.sh` that is not in `guards.tsv` | RED |
| 2 | Point the scanner at an empty `guards.tsv` (a guard reporting "0 baseline checks" and exiting 0) | RED (exit 2, `reason=baseline-source-empty`) |
| 3 | Scanner stops after the first v1 row when a second is added | RED |
| 4 | Duplicate `secret-scan` as a `checks.tsv` baseline row (double count) | RED |

**Harness rows.** Edit the suite to compare counts instead of names: it must go RED against a swapped-name mutation. Must-PASS: a temp copy of `guards.tsv` with its columns reordered still yields the same set, and a `tier=v2` row is not emitted as a gap.

**Anchor.** Set identity against `guards.tsv`, which is itself pinned by `verification-scaffold/test/manifest.test.sh`.

### Guard 4 — Never-read path filter

**Property.** The skill never reads a path `code-to-prd` refuses to read, nor tfstate, tfvars, SQL dumps, CSV, SQLite files or fixture/seed data, nor a symlink.

**Assembly.** One predicate `safe_path()` in `scripts/lib/safe-walk.sh`, called by the walker and by every file read in the detectors (a detector never opens a path itself; a source-scan test fails on a direct `cat`/`grep`/redirect of a variable path). The parity test extracts the case patterns from the body of `is_excluded()` in `code-to-prd.sh` (by function name, not by line number) and asserts `safe_path()` contains all of them; launch-check's additions are asserted from a fixed list in the test.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `*.pem` from `safe_path` | RED |
| 2 | Add a detector that opens `$f` directly instead of via the walker | RED (source-scan test) |
| 3 | Add a new deny pattern to `code-to-prd.sh`'s `is_excluded()` without updating `safe-walk.sh` | RED (superset breaks) |
| 4 | Plant a symlink to a file outside the target | RED (must be excluded and counted) |
| 5 | Remove `*.tfstate` from the launch-check additions | RED |

**Harness rows.** Edit the parity test so its extractor returns zero patterns: it must go RED (an extractor that finds nothing passes any superset check). Must-PASS: `docs/environment.md` (contains "env" but is not `.env*`) is read.

**Anchor.** `code-to-prd.sh`'s `is_excluded()` is the independent side; the fixed addition list lives in the test file, which a weakening change must also edit.

### Guard 5 — Static wording lint

**Property.** No banned assurance word appears in any static prose source that reaches a write site, and every rendered report carries the standing banner.

**Assembly.** All prose in the report and issue bodies originates in three sources: `checks.tsv` (titles, remedies), `references/*.template` and `references/banner.txt`; evidence fields are paths and counts only. A test lints those sources against `references/banned-words.txt` (certified, certification, compliant, production-ready, passed; case-insensitive, whole word, so "non-compliant" is also caught) and a source-scan asserts the render code appends no literal prose beyond them. Judged findings carry no free text (Guard 1), so there is no runtime lint.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Put "production-ready" in a `checks.tsv` title | RED |
| 2 | Delete the banner from the render template | RED |
| 3 | Add literal prose containing "compliant" to `render.sh` (a second source) | RED |
| 4 | Empty `banned-words.txt` (a lint with "0 words" that exits 0) | RED |

**Harness rows.** Edit the suite to lint only `checks.tsv`: it must go RED on mutation 3. Must-PASS: a remedy that says `npm audit` is accepted (audit is not a banned word), and the banner text itself passes the lint.

**Anchor.** `banned-words.txt` and `banner.txt` ship in the plugin payload; the test hashes `banned-words.txt` into its expected value so weakening it is visible in the diff.

## Observability

Surface: code under `plugins/soleur/skills/launch-check/` that executes on a customer's own machine (observability layer 7, `cli-stdout-artifact`). There is no Soleur-side sink and none is added (CLO: no phone-home).

```yaml
liveness_signal:
  what: "SOLEUR_LAUNCH_CHECK_RUN stdout marker with counts (checks, findings, write path, issues created/skipped/failed) plus the committed report file"
  cadence: "per run (operator-invoked)"
  alert_target: "the customer's in-session tool-result stdout; no Soleur-hosted alert target by design"
  configured_in: "plugins/soleur/skills/launch-check/scripts/launch-check.sh (marker emission) and scripts/lib/render.sh (artifact)"

error_reporting:
  destination: "stdout/stderr tool result in the customer's session; exit code distinguishes success (0), redaction hit (1), preflight failure (2)"
  fail_loud: "SOLEUR_LAUNCH_CHECK_ABORT reason=<redaction-hit|scanner-missing|scanner-failed|plugin-root-unresolved|baseline-source-empty|walker-escape> and a non-zero exit; no report is written on abort"

failure_modes:
  - mode: "gitleaks missing or not runnable"
    detection: "preflight prints SOLEUR_LAUNCH_CHECK_ABORT reason=scanner-missing with an OS-specific install line and exits 2 before any read"
    alert_route: "layer 7: tool-result stdout in the customer session"
  - mode: "plugin root cannot be resolved, or guards.tsv / redact-sentinel.sh is missing or empty"
    detection: "reason=plugin-root-unresolved or baseline-source-empty, exit 2, nothing read or written"
    alert_route: "layer 7: stdout marker"
  - mode: "redaction hit in rendered report or issue body"
    detection: "emit_checked aborts, prints reason=redaction-hit with the class name (never the match), exits 1, and removes the temp file; the report is not created or updated"
    alert_route: "layer 7: stdout marker; report file absence/age is the durable signal"
  - mode: "gh unauthenticated, no remote, issues disabled, archived repo or no label permission"
    detection: "issues --preview prints SOLEUR_LAUNCH_CHECK_ISSUES mode=report-only reason=<named cause> and creates nothing"
    alert_route: "layer 7: stdout marker"
  - mode: "sub-issue API unavailable on the customer's plan"
    detection: "issues --create prints SOLEUR_LAUNCH_CHECK_ISSUES fallback=task-list"
    alert_route: "layer 7: stdout marker and the epic body itself"
  - mode: "partial issue creation (network or secondary rate limit mid-run)"
    detection: "SOLEUR_LAUNCH_CHECK_ISSUES created=N skipped=M failed=K after bounded backoff; a re-run matches live issues by label and marker and resumes"
    alert_route: "layer 7: stdout marker plus the epic's marked section"
  - mode: "stale or hand-edited report state block, or a catalog change since the last run"
    detection: "verify-report prints SOLEUR_LAUNCH_CHECK_REPORT_INVALID reason=<field>, or render prints SOLEUR_LAUNCH_CHECK_CATALOG_CHANGED retired=N"
    alert_route: "layer 7: stdout of verify-report / render"

logs:
  where: "the customer's terminal/tool result and the committed report file under knowledge-base/engineering/readiness/"
  retention: "the report is committed by the customer and lives in their git history; stdout markers last for the session"

discoverability_test:
  command: bash plugins/soleur/skills/launch-check/scripts/launch-check.sh verify-report --file plugins/soleur/skills/launch-check/test/fixtures/report-sample.md
  expected_output: LAUNCH_CHECK_REPORT_OK
```

`verify-report` is parse-only: it validates the fenced state block (`schema_version`, ids, statuses) with no network, no credentials and no `gitleaks`, so it finishes in well under preflight Check 10's 15-second sandbox cap. On a customer machine the same check is `bash "${CLAUDE_PLUGIN_ROOT}/skills/launch-check/scripts/launch-check.sh" verify-report --file knowledge-base/engineering/readiness/launch-check.md`; the repo-relative path above exists only in this repository and is what preflight executes. The fixture is committed in this PR.

## Implementation Phases

### Phase 0 — Tests and fixtures first (RED)

Write the failing suites before any script (`cq-write-failing-tests-before`): `test/scan.test.sh`, `test/baseline.test.sh`, `test/render.test.sh`, `test/redact-gate.test.sh`, `test/safe-walk-parity.test.sh`, `test/identity.test.sh`, `test/wording.test.sh`. Fixture repos are **built at test time** under a scratch dir (nested `.git` directories cannot be committed, and a committed secret-shaped string would trip this repo's own gitleaks CI; the planted secret is assembled from fragments at runtime): `repo-minimal` (no tests, no CI), `repo-nextjs-healthy`, `repo-python` (unsupported stack), `repo-with-planted-secret`, `repo-with-symlink-escape`, `repo-renamed-file` (same finding before and after a rename and a line shift), `repo-multi-hit`. Committed fixtures: `report-sample.md` (valid state block). Fixture git runs under `env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_OBJECT_DIRECTORY -u GIT_COMMON_DIR` with a pinned identity, and the suites source `plugins/soleur/test/test-helpers.sh` (shell tripwire prelude). A suite iterates `checks.tsv` and fails on any detector row lacking one positive and one negative fixture case.

**Finding identity (pinned before any code).** Each `checks.tsv` row declares `key`: `path` (id = check id + 8-char hash of the repo-relative path) or `repo` (id = check id only, for absence checks such as "no CI"). A moved file under a `path` key is one closed plus one new finding; that is the documented, tested behavior (`identity.test.sh`: rename, line shift, multiple hits, absence). Several hits in one file collapse to one finding with a hit count. Secret-class findings have no id and no location; they appear as a count.

### Phase 1 — Skill skeleton, safe walker, scanner

`SKILL.md` (frontmatter `disable-model-invocation: true`, as the skills moved in #8290, so the description does not count against the model-visible cap; the skill files issues, so it must be operator-invoked). SKILL.md rules: only the scripts write the report or call `gh`; the agent never writes the report or runs `gh` itself; `AskUserQuestion` to the customer before `issues --create`; headless runs are preview-only. `scripts/launch-check.sh` subcommands: `scan`, `render`, `issues`, `verify-report`, with `--target`, `--dry-run`, `--show-secrets`. Plugin-root resolution by identity (the script's own real path, verified by `.claude-plugin/plugin.json` naming `soleur`), failing closed with `reason=plugin-root-unresolved` if `guards.tsv` or `redact-sentinel.sh` is absent or empty. `scripts/lib/safe-walk.sh` (walker + `safe_path`, detects the repo stack: node, python, ruby, go, other).

`references/checks.tsv` columns: `id domain class kind title key severity stacks glob regex expect closing_command remedy`. `kind` is `presence` (data-driven: glob and optional regex, one engine), `detector` (a named function in `lib/checks.sh`) or `judged`. Statuses: `found`, `not-identified`, `not-applicable`, `unsupported-stack`. A negative is worded "not identified in the files read". Severity is fixed per row; only deterministic rows may be `critical`.

Deterministic rows (17):
- Security & secrets: SEC-01 secret-shaped content in tracked files (detector, gitleaks, count only, critical); SEC-02 `.env` tracked or not git-ignored (critical); SEC-03 lockfile present; SEC-04 dependency-update config (Dependabot/Renovate) present.
- Tests & CI/CD: CI-01 CI workflow present; CI-02 tests present with test-to-source ratio (detector); CI-03 CI runs the test command (regex over workflow files); CI-04 release or rollback path present.
- Tech debt & architecture: DEBT-01 debt-marker count (the four conventional comment tags, plus `SOLEUR-DEBT:` markers using `harvest-debt` semantics); DEBT-02 pinned runtime version file; DEBT-03 architecture docs or ADR directory (baseline); DEBT-04 agent-conventions file `CLAUDE.md`/`AGENTS.md` (baseline); DEBT-05 client/server import-boundary gate for Next.js (baseline, stack-gated, closes with `constraint-scaffold`).
- Reliability, performance & ops: REL-01 error-tracking SDK in dependency manifests; REL-02 health endpoint; REL-03 backup or restore mention in docs/IaC; REL-04 runbook or ops docs directory.

Judged rows (4), driven by SKILL.md: JDG-AUTH (auth model), JDG-DATA (data-layer risk), JDG-SCALE (scaling hot spots), JDG-OBS (observability adequacy, including rate limiting and logging). The agent reads only paths listed in `facts.json` and writes `findings-judged.json` in the closed schema of Guard 1.

### Phase 2 — Baseline derivation, render, state, diff

`scripts/lib/baseline.sh` per Guard 3: one `BASE-<guard>` check per `tier=v1` row, status "artifact present, advisory/unverified" or `not-identified` (an installed-but-unregistered hook is not distinguishable without reading `settings.json`; the check reads `.claude/settings.json` for the hook entry and reports "present, unregistered" when the file exists but the entry does not). `tier=v2` and still-`generic-after-extraction` items render as "not installable yet", never as gaps.

`scripts/lib/render.sh` writes `knowledge-base/engineering/readiness/launch-check.md`: frontmatter (run date, `schema_version`, `checks.tsv` hash), the standing banner (`references/banner.txt`) with two fixed lines added to it: "this scan covers the working tree, not git history; a secret removed from the current tree may still be live in history — rotate it" and, for non-Node repos, "coverage for this stack is partial", summary counts by domain × severity (no score), a findings table, "Closed since last run" / "New since last run" / "Accepted" / "Retired checks" sections, and a fenced JSON state block (`schema_version`, `catalog_hash`, findings `{id, status: open|closed|accepted, reason?, date?}`; no issue numbers). An id missing from the catalog but listed in `references/retired-checks.tsv` is "retired", not "closed". An `accepted` entry is skipped by `issues`. If a prior report exists but its `schema_version` or `catalog_hash` differs, `render` prints `SOLEUR_LAUNCH_CHECK_CATALOG_CHANGED`. Footer attribution comes from `references/footer.txt` (CLO wording, flagged draft-requires-counsel-review in the PR body). Writes go through `emit_checked()`.

### Phase 3 — Self-test (dry-run) and triage

Run `scan` and `render --dry-run` against (a) this repo and (b) one public non-Soleur Node/TS repository cloned to a scratch directory (this repo is public, uses Soleur conventions and would pass by construction, so a second sample is required). The living report is NOT written into either repo. Record in `knowledge-base/project/specs/feat-prod-readiness-gap-analysis/self-test.md` every gap with a disposition: (a) real gap, (b) detector false positive (fix the detector or the `checks.tsv` row), (c) expected non-applicability. Runs BEFORE registration because triage changes ids and wording. Acceptance: every reported gap has a recorded disposition and evidence line; the sample (b) run produces a plausible, non-empty report.

### Phase 4 — Registration, ADR, C4

Harness mirror at `plugins/soleur/cursor/skills/soleur-launch-check/SKILL.md`, `plugins/soleur/README.md` counts, `plugins/soleur/docs/_data/skills.js`, test registries (`scripts/lib/test-affected-paths.sh`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, `plugins/soleur/test/fixture-relative-assert.baseline.txt` if new fixtures trigger it), `components.test.ts` only if a derived count moves, ADR-314, C4 edits and `model.likec4.json` regen. Diff the touch list against `git show 93583f8d27 --stat`. No change to `commands/sync.md` or the onboarding runbook in this PR (revisit after the first customer run).

### Phase 5 — Issue epic (PR-B)

`scripts/lib/issues.sh`. **Preflight** (`gh auth status`, a remote exists, `gh repo view --json hasIssuesEnabled,isArchived,viewerPermission,visibility`): any failure puts the run in `mode=report-only` with the named cause; unknown visibility is reported as unknown, never silently treated as private. **Preview**: writes the plan file (epic + sub-issues, labels to create, issues that already exist, issues skipped as accepted) and prints it with the repo visibility; a public or unknown repository gets a warning that issues are public, and `--exclude-domain security` and `--exclude-class baseline` let the customer drop items. **Cap**: at most 30 sub-issues per run by severity, the remainder listed in the epic's marked section. **Create**: `--create --plan <file>` runs `gh_write` per item: labels first, only if absent (listed, never `--force`), prefixed `lc:` (`lc:severity-critical|high|medium|low`, `lc:domain-security|tests-ci|tech-debt|reliability-ops`) with bounded retry and backoff on secondary rate limits (403/429); then the epic (title `Launch readiness: <repo> (launch-check)`); then each sub-issue with the `<!-- launch-check:gap=<stable-id> -->` marker, evidence `path:line`, the remedy and the banner line, linked with `POST .../issues/{epic}/sub_issues` (`sub_issue_id` = the created issue's database `.id`); on 403/404/410/422, fall back to a `- [ ] #N` task list inside the epic's marked section. **Idempotency**: GitHub is the record. A re-run lists the epic's live issues (label `lc:` plus marker) and matches findings against them; the state block is not consulted for issue numbers. An existing marked issue, open or closed, is never recreated; a marked issue the customer closed counts as `accepted`. The tool never closes issues. Tests use a stub `gh` on PATH that records every invocation.

### Phase 6 — Roadmap and tracking issue

Add roadmap Phase 4 row 4.14 (P2, "Customer-repo launch check: readiness + best-practice gap analysis for existing-repo customers", dependency on row 4.12) and file the tracking issue under the Phase 4 milestone in the same action with a `Mandated-By: wg-every-feature-listed-in-a-roadmap-phase` line; then rewrite this plan's `issue:` frontmatter from the draft-PR number to the new issue number. Run `roadmap-reconcile.sh validate` after.

## Files to Create

- `plugins/soleur/skills/launch-check/SKILL.md`
- `plugins/soleur/skills/launch-check/scripts/launch-check.sh`
- `plugins/soleur/skills/launch-check/scripts/lib/safe-walk.sh`
- `plugins/soleur/skills/launch-check/scripts/lib/checks.sh`
- `plugins/soleur/skills/launch-check/scripts/lib/baseline.sh`
- `plugins/soleur/skills/launch-check/scripts/lib/render.sh`
- `plugins/soleur/skills/launch-check/scripts/lib/redact-gate.sh`
- `plugins/soleur/skills/launch-check/scripts/lib/issues.sh` (PR-B)
- `plugins/soleur/skills/launch-check/references/checks.tsv`
- `plugins/soleur/skills/launch-check/references/retired-checks.tsv`
- `plugins/soleur/skills/launch-check/references/severity-rubric.md`
- `plugins/soleur/skills/launch-check/references/banner.txt`
- `plugins/soleur/skills/launch-check/references/footer.txt`
- `plugins/soleur/skills/launch-check/references/banned-words.txt`
- `plugins/soleur/skills/launch-check/references/issue-body.template` (PR-B)
- `plugins/soleur/skills/launch-check/test/scan.test.sh`
- `plugins/soleur/skills/launch-check/test/baseline.test.sh`
- `plugins/soleur/skills/launch-check/test/render.test.sh`
- `plugins/soleur/skills/launch-check/test/redact-gate.test.sh`
- `plugins/soleur/skills/launch-check/test/safe-walk-parity.test.sh`
- `plugins/soleur/skills/launch-check/test/identity.test.sh`
- `plugins/soleur/skills/launch-check/test/wording.test.sh`
- `plugins/soleur/skills/launch-check/test/issues.test.sh` (PR-B)
- `plugins/soleur/skills/launch-check/test/fixtures/report-sample.md` (the repo fixtures are built at test time)
- `plugins/soleur/cursor/skills/soleur-launch-check/SKILL.md` (harness mirror)
- `knowledge-base/engineering/architecture/decisions/ADR-314-launch-check-baseline-manifest-and-finding-contract.md`
- `knowledge-base/project/specs/feat-prod-readiness-gap-analysis/self-test.md`

## Files to Edit

- `plugins/soleur/README.md` (skill count)
- `plugins/soleur/docs/_data/skills.js`
- `plugins/soleur/test/components.test.ts` (only if a derived count moves)
- `scripts/lib/test-affected-paths.sh`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, `model.likec4.json`
- `knowledge-base/product/roadmap.md` (row 4.14)

## Acceptance Criteria

### Pre-merge (PR-A)

- [ ] `scan` on `repo-minimal` reports tests and CI as not-identified, and on `repo-nextjs-healthy` reports them found, with evidence as `path:line` and never file content; on `repo-python` stack-gated checks report `unsupported-stack` and the banner says coverage is partial.
- [ ] The planted-secret fixture aborts `render` with `reason=redaction-hit`, exit 1, and no report file or temp file exists afterward; a secret-class finding appears only as a count in the report, and its location never appears in any file.
- [ ] Missing `gitleaks` aborts with `reason=scanner-missing`, exit 2, before any file is read; an unresolvable plugin root or empty `guards.tsv` aborts with its named reason.
- [ ] Baseline guard checks equal the `tier=v1` rows of `guards.tsv` by name (Guard 3 suite green, including the empty-manifest and double-count mutations).
- [ ] `safe-walk-parity.test.sh` is green and goes RED when a pattern is removed (Guard 4); tfstate, tfvars, SQL, CSV and SQLite paths are excluded.
- [ ] Re-running after fixing one gap lists it under "Closed since last run" with other ids unchanged; an `accepted` entry stays out of "New"; a removed-and-retired check id is listed as retired, not closed.
- [ ] No banned word in any static prose source and the banner is present (Guard 5); judged findings reject an extra string field (Guard 1).
- [ ] Self-test (Phase 3) ran in dry-run on this repo and on one public non-Soleur Node/TS repo; every reported gap has a recorded disposition in `self-test.md`.
- [ ] `bun test plugins/soleur/test/components.test.ts`, the new suites, `c4-count-parity.test.sh`, the `c4-code-syntax`/`c4-render` tests and `python3 scripts/lint-guard-contract.py` on this plan are green.
- [ ] ADR-314 exists, records the packaging constraint and the redaction trust boundary, and its ordinal was re-verified against `origin/main` at ship.
- [ ] `gdpr-gate` was re-run on the actual diff (advisory output recorded in the PR body).

### Pre-merge (PR-B)

- [ ] `issues --preview` makes no `gh` write; `--create` refuses without a saved plan and refuses headless; the stub-`gh` suite records zero writes under `--dry-run` (Guard 2).
- [ ] Preflight failures (unauthenticated `gh`, no remote, issues disabled, archived repo, no label permission) each yield `mode=report-only` with a named reason.
- [ ] Sub-issue success and each fallback status (403/404/410/422) yield a linked or task-listed epic; epic edits touch only the marked section and leave customer text outside it intact.
- [ ] A re-run after a partial failure (3 of 7 created) creates the remaining 4 and skips 3, matching by label and marker with an empty state block; a marked issue the customer closed is not recreated.
- [ ] Labels are created only when absent and are `lc:`-prefixed; an existing customer label is untouched; the 30-issue cap lists the remainder in the epic.
- [ ] One end-to-end run against a throwaway repo confirms the real sub-issue endpoint behavior (permission, `sub_issue_id` semantics, per-parent limit); the result is recorded in the PR body.

### Post-merge

- [ ] None required for the merge. The first customer run (Skouer, on the tester's own key, after an executed Art. 28(3) instrument exists) is the next validation step, owned by the operator and reviewed at the Phase 4 checkpoint (#8981).

## Test Scenarios

- Given a repo with no CI and no tests, when `scan` runs, then both are reported not-identified in files read, and no assurance wording appears.
- Given a repo whose tracked file contains a synthesized secret, when `render` runs, then no report is written, exit is 1, stdout names the class and never the value or location.
- Given a Next.js repo without a dependency-cruiser gate, when `scan` runs, then a baseline gap names `constraint-scaffold`; given a non-Next.js repo, it is `not-applicable`.
- Given `guards.tsv` gains a v1 guard, when `scan` runs with no code change, then the new guard appears as a baseline check.
- Given a symlink in the target pointing outside it, when the walker runs, then the file is excluded and counted.
- Given the same repo scanned twice with one fix and one `accepted` entry between, when `render` runs the second time, then the fix is closed, the accepted one is not new, and other ids are unchanged.
- Given `--dry-run`, when `issues --create` runs, then a recording stub `gh` sees zero write calls.
- Given the sub-issue endpoint returns 404, when `--create` runs, then the epic's marked section carries a task list and stdout reports `fallback=task-list`.
- Given a partial failure after 3 of 7 issues, when `--create` is re-run, then 4 are created and 3 skipped.
- Given a public repository, when `issues --preview` runs, then it warns that issues are public and `--exclude-domain security` removes those items.
- Given a plugin update that retires a check id, when `render` runs against the old report, then the id is listed as retired and `SOLEUR_LAUNCH_CHECK_CATALOG_CHANGED` is printed.

## Risks and Sharp Edges

- **Priority and displacement.** This is P2 and large next to unfinished P1 Phase 4 work (#8981 overdue since 2026-08-20; tester #2 prerequisites #7331 and the C9 re-run). Operator decision 2026-11-02: start implementation now, with PR-B (epic creation) kept in v1 as specified; the displacement risk is accepted and the overdue checkpoint stays open in parallel.
- **Validation bar.** The Skouer run counts as validated if the tester acts on at least 3 of the filed issues or names at least one gap they had not seen; otherwise shrink or stop at the next Phase 4 review. Owner: the operator.
- **Art. 28(3) status.** The determination exists (#7331 closed) but an executed instrument is not established in this repo; treat it as absent, so the Skouer run stays gated.
- **Baseline is small and may over-report.** Only 4 v1 guards plus three non-guard rows are portable; Phase 3's two-repo self-test calibrates false positives before any customer sees it. A baseline gap in a repo that does not use the guard's stack must be `not-applicable`, not a gap.
- **Detectors are heuristics.** Presence and regex checks miss custom implementations; every negative reads "not identified in the files read" and the banner says absence of findings is not assurance (CLO).
- **Git history is not scanned.** A fixed secret stays live in history; the banner and the SEC-01 remedy say to rotate it, and the tool cannot show it as closed.
- **gitleaks is a hard dependency** (same as `code-to-prd`); the preflight names an OS-specific install line. A customer without it gets a refusal, not a degraded run.
- **Consent is not script-enforced.** `--create` executes a saved plan and refuses headless, but an agent can still call it; the guard is the SKILL.md instruction plus the harness's permission prompt, recorded in ADR-314.
- **Sub-issue API behavior is unverified for plans and limits** (the REST page is silent); the fallback and a real-repo check are acceptance criteria.
- **Report path.** `knowledge-base/engineering/readiness/launch-check.md` must be checked against the customer KB layout that `sync` writes (ADR-171 is still adopting) and that headless `sync` does not ingest it; on a conflict use `knowledge-base/project/readiness/`.
- **Legal footer** wording and T&C/Disclaimer coverage of CLI outputs need counsel; v1 ships the CLO-agent wording flagged draft-requires-counsel-review.
- **Plan edits.** Keep each guard heading in the exact `### Guard <n> — <name>` form for `lint-guard-contract.py`.

## Non-Goals

- Hosted variant (gated on the Art. 28(3) instrument, gdpr-gate, C5 #7347). Documented here, not filed (`wg-when-deferring-a-capability-create-a`).
- Auto-remediation (findings name `verification-scaffold`/`constraint-scaffold` commands only) and closing issues from the tool.
- Readiness score, benchmarking, certification wording, compliance verdicts.
- Any telemetry or share-back path to Jikigai.
- A `/soleur:sync` area, a `/soleur:sync` pointer, an onboarding-runbook step, a new command, or a change to `code-to-prd` (revisit the pointer and runbook after the first customer run).
- Detectors for Python, Ruby and Go stacks (v1 reports `unsupported-stack` there).
- Technical-versus-non-technical founder register (v1 targets technical founders).
