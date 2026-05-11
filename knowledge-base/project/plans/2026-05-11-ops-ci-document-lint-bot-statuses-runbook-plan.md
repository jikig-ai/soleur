---
title: "ops(ci): document lint-bot-statuses runbook"
type: ops-docs
date: 2026-05-11
issue: 3546
parent_pr: 3543
parent_issue: 2719
classification: docs-only
requires_cpo_signoff: false
---

# Plan: Document `lint-bot-statuses` Runbook (R15 follow-up D3)

Closes #3546. Documentation-only follow-up to PR #3543 (R15 mitigation for #2719). Adds a runbook entry under `knowledge-base/engineering/ops/runbooks/` describing the `lint-bot-statuses` CI gate's enforcement footprint: what it guards, what it skips, how to diagnose a failure, how to extend it.

## Overview

The `lint-bot-statuses` CI job runs two shell scripts on every PR:

1. `scripts/lint-bot-synthetic-statuses.sh` — rejects `[skip ci]` in any `scheduled-*.yml` workflow that runs `gh pr create` (refs #826, #827, #842, #1014).
2. `scripts/lint-bot-synthetic-completeness.sh` — verifies every `scheduled-*.yml` workflow whose shell `run:` block calls `gh pr create` also posts synthetic check-runs (`-f name=…` or `-f context=…`) for every entry in `scripts/required-checks.txt` (refs #826, #1468).

These guards exist because bot PRs created via `GITHUB_TOKEN` do not re-trigger CI (GitHub prevents infinite loops). Without a complete set of synthetic check-runs, the "CI Required" ruleset (#14145388) blocks auto-merge indefinitely. The lint catches the missing-synthetic case at PR time, before the bot PR has shipped a deadlock-shaped artifact.

The lint exists, is wired into CI, and is load-bearing — but its enforcement footprint is not documented. A failure mode (which we already hit once at PR #3543 — see learning `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`) currently requires reading the bash to understand what failed and how to fix it. This plan adds the runbook so the next failure routes to documentation, not source.

## Research Reconciliation — Spec vs. Codebase

The issue body summarized the surface accurately. One precision callout:

| Spec claim | Reality | Plan response |
|---|---|---|
| "lint-bot-statuses workflow" | The check is a **job** named `lint-bot-statuses` inside `.github/workflows/ci.yml` (lines 20-27), not a standalone workflow file. The GitHub-side check name surfaces as `lint-bot-statuses` (the job ID), which is what shows in the PR's "Checks" tab. | Runbook calls this the `lint-bot-statuses` CI job; cross-references `.github/workflows/ci.yml`. |
| "scripts/lint-bot-synthetic-completeness.sh" wired into the check | Two scripts are wired: `lint-bot-synthetic-completeness.sh` AND `lint-bot-synthetic-statuses.sh`. Documenting only the completeness script would leave the sibling lint undocumented at the same audience. | Runbook covers both scripts under one `lint-bot-statuses` runbook (the failure surface is the same job; operator-debugging differs by which step failed). |

## User-Brand Impact

**If this lands broken, the user experiences:** Nothing user-facing. This is operator documentation. Worst-case is operator confusion at the next lint failure (10-30 min extra debugging time reading bash source), identical to the status quo.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A. The runbook contains no secrets, no PII, no credentials — it documents a public CI gate against a public ruleset. The script names, required-check names, and ruleset ID are already public in `scripts/`, `.github/workflows/`, and `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md` on `main`.

**Brand-survival threshold:** none. Docs-only follow-up to a closed brand-survival-critical incident (#2719). The threshold for the underlying gate is `single-user incident` (per #3543), but this plan only documents it — does not change enforcement.

`threshold: none, reason: docs-only addition under knowledge-base/engineering/ops/runbooks/; no behavior change, no regulated-data surface, no consumer of the lint contract is added or removed by this PR.`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] New file: `knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md`. YAML frontmatter matches sibling runbooks (`audience: operator`, `on_page_for:`, `issues:`, `threshold:`, `last_updated:`).
- [ ] Runbook documents both scripts under the `lint-bot-statuses` job: `scripts/lint-bot-synthetic-completeness.sh` AND `scripts/lint-bot-synthetic-statuses.sh`.
- [ ] Runbook includes these sections:
  - **Trigger** — when an operator should read it (CI failure, before adding a new required check, before adding a new bot workflow).
  - **What this lint is (and isn't)** — bot-PR auto-merge guard, not a code-quality lint.
  - **The as-built behavior** — completeness check semantics; statuses check semantics; the App-token escape hatch (`gh pr create` only in `prompt:` blocks).
  - **Required-checks config** — pointer to `scripts/required-checks.txt`; the `CodeQL` and `bypass_actors` cross-references already documented in the file's comment block; the rule that adding a new required check requires updating BOTH `scripts/required-checks.txt` AND `.github/actions/bot-pr-with-synthetic-checks/action.yml` (the composite action's `CHECK_NAMES` array).
  - **Drift triage** — failure mode taxonomy: (a) `[skip ci]` present (statuses script), (b) missing synthetic for a known check (completeness script), (c) config-parser regression (e.g., the strip-all-whitespace bug from #3543), (d) new bot workflow with shell `gh pr create` but no synthetics, (e) false-positive from a `prompt:`-only `gh pr create` mis-detected as shell.
  - **How to extend** — adding a new required check (3 edits: `required-checks.txt`, composite action, runbook cross-ref); adding a new bot workflow (use the composite action, or post synthetics inline matching the test fixture in `plugins/soleur/test/lint-bot-synthetic-statuses.test.sh`); checking your new workflow locally (`bash scripts/lint-bot-synthetic-completeness.sh`).
  - **Cross-references** — sibling runbooks: `skill-security-scan-required-check.md`, `codeql-bot-coverage.md`, `ruleset-bypass-drift.md`. The composite action file. The test fixture.
- [ ] Runbook cross-links bidirectional with existing runbooks:
  - `skill-security-scan-required-check.md` lines 22-30 already reference `lint-bot-statuses` — verify the link points to the new runbook path.
  - `codeql-bot-coverage.md` § Cross-references — add a row pointing to the new runbook.
  - `ruleset-bypass-drift.md` § Cross-references — add a row pointing to the new runbook.
- [ ] Re-evaluation criterion captured in runbook frontmatter or trailing comment, per #3546 issue body: "Re-evaluate after the 2nd lint failure that required reading the source to understand."
- [ ] Markdown lints pass (`bun run lint:md` if wired; otherwise no markdownlint warnings on the new file under default config).
- [ ] PR body uses `Closes #3546` on its own line (per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] PR body uses `Ref #3542` and `Ref #2719` for upstream R15 lineage.

### Post-merge (operator)

- [ ] Verify the new runbook URL renders on the docs site (if `knowledge-base/engineering/ops/runbooks/` is published) — N/A for this plan if the directory is not part of the Eleventy build. Document the verification command if it applies; otherwise close as "internal-only operator doc, no site rebuild required."

## Implementation Phases

### Phase 1 — Author the runbook

**File to create:**

- `knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md`

**Reference templates (read before writing):**

- `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md` — parent R15 runbook, sets the frontmatter convention.
- `knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md` — sibling bot-related runbook, sets the "what this is/isn't" + "as-built behavior" + "drift triage" section pattern.
- `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md` — sibling audit runbook, sets the failure-mode table pattern.

**Frontmatter template:**

```yaml
---
title: lint-bot-statuses CI gate
audience: operator
on_page_for: scripts/lint-bot-synthetic-completeness.sh
issues: [3546, 3542, 2719]
threshold: none
last_updated: 2026-05-11
---
```

**Section skeleton (drop into the new file):**

```markdown
# lint-bot-statuses CI gate

## Trigger

Read this runbook when:

- The `lint-bot-statuses` CI job on a PR fails.
- You are adding a new required status check to the "CI Required" ruleset (#14145388).
- You are adding a new `scheduled-*.yml` workflow that creates PRs via GITHUB_TOKEN.
- You are debugging a bot PR that opened but never auto-merged.

## What this lint is (and isn't)

**Is:** ...

**Is not:** ...

## The as-built behavior

### `scripts/lint-bot-synthetic-statuses.sh`
...

### `scripts/lint-bot-synthetic-completeness.sh`
...

### App-token escape hatch
...

## Required-checks config
...

## Drift triage
...

## How to extend
...

## Cross-references
...

## Re-evaluation
...
```

**Filled content notes for the author at /work time:**

- The "What this lint is (and isn't)" section MUST explicitly state: it is a PR-time pre-commit-shaped guard against bot-PR auto-merge deadlock, NOT a code-quality lint and NOT a runtime check on the bot's actual PR — those run later, in the bot workflow itself.
- The "as-built behavior" subsection for completeness must call out: the parser preserves internal whitespace (multi-word check names like `"skill-security-scan PR gate"` are one check, not three), it strips a single matching pair of surrounding double quotes from config entries, and it strips trailing `#`-comments. Reference the learning file `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md` as the cautionary tale.
- The "as-built behavior" subsection for the App-token escape hatch must explain the `has_shell_pr_create` heuristic: `gh pr create` inside a YAML `run:` block triggers the synthetic-check requirement; `gh pr create` inside a `prompt:` block (claude-code-action) is exempt because the App token re-triggers real CI.
- The "Drift triage" section must enumerate the five failure modes named in the acceptance criterion above, each with: error-message shape, root-cause guess, fix path.
- The "How to extend" section must include the three-step recipe for adding a new required check (with exact commands using `grep -F` for verification, no shell substitution in the doc per project convention).

### Phase 2 — Bidirectional cross-references

**Files to edit:**

- `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md` — verify line 30-ish reference (`lint-bot-statuses is green on main`) and ensure it links to the new runbook path.
- `knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md` — add row in `## Cross-references` pointing to the new runbook.
- `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md` — add row in cross-references section pointing to the new runbook.

These three edits are mechanical link additions, ~1-3 lines each.

### Phase 3 — Verification

**Local verification commands (run before pushing):**

```bash
# 1. The new file exists and parses as markdown with frontmatter.
test -f knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md
head -10 knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md | grep -F '---'

# 2. All three cross-referenced runbooks now mention the new file.
grep -l 'lint-bot-statuses.md' knowledge-base/engineering/ops/runbooks/*.md | wc -l
# Expect: ≥ 3 (skill-security-scan-required-check, codeql-bot-coverage, ruleset-bypass-drift)

# 3. The runbook itself links to its `on_page_for` script and the sibling lint.
grep -F 'scripts/lint-bot-synthetic-completeness.sh' knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md
grep -F 'scripts/lint-bot-synthetic-statuses.sh' knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md
grep -F 'scripts/required-checks.txt' knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md
grep -F '.github/actions/bot-pr-with-synthetic-checks/action.yml' knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md

# 4. CI lint still passes (sanity — this PR does not touch the lint or any
# scheduled workflow, but verify nothing accidentally got included).
bash scripts/lint-bot-synthetic-statuses.sh
bash scripts/lint-bot-synthetic-completeness.sh
```

No new tests required — this is documentation only, and the lint behavior being documented is already covered by `plugins/soleur/test/lint-bot-synthetic-statuses.test.sh`.

## Files to Edit

- `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md` — verify/normalize the existing cross-reference to `lint-bot-statuses` so it links to the new runbook path.
- `knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md` — add cross-reference row.
- `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md` — add cross-reference row.

## Files to Create

- `knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md` — the runbook itself.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --json number,title,body --limit 200` and grepped for each planned file path. Hits:

- `scripts/lint-bot-synthetic-completeness.sh` — 0 open scope-outs touch this file.
- `scripts/required-checks.txt` — 0 open scope-outs.
- `knowledge-base/engineering/ops/runbooks` — 0 open scope-outs name this directory.

Disposition: **None** — no overlap to fold-in / acknowledge / defer.

## Domain Review

**Domains relevant:** Engineering (CTO advisory only — documentation of an existing gate, no new architecture).

### Engineering (CTO)

**Status:** auto-advisory (no spawn required)
**Assessment:** Documentation-only PR. The lint exists and is load-bearing; the runbook codifies operator behavior that today lives in two ~150-line shell scripts plus one learning file. No production code path, no infra, no secrets surface — the only CTO-shape risk is documentation drift (the runbook becoming stale relative to the scripts). Mitigation: pin the `on_page_for:` frontmatter to `scripts/lint-bot-synthetic-completeness.sh` so any operator editing the script sees the documented runbook in the same `rg`-able surface.

No Product/UX gate — no user-facing surface. No CMO gate — no marketing surface. No CLO gate — no regulated-data surface, no compliance contract changed by this PR.

## GDPR / Compliance Gate

Per `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex (schemas, migrations, auth flows, API routes, `.sql` files): this PR touches none of those surfaces. Files are `knowledge-base/engineering/ops/runbooks/*.md` only. Skip `/soleur:gdpr-gate` per the conditional in plan Phase 2.7. Recorded for audit completeness.

## Risks

- **Documentation drift.** The runbook restates behavior that lives in two shell scripts. If the scripts diverge from the runbook in a future PR, the runbook becomes a stale source. **Mitigation:** `on_page_for: scripts/lint-bot-synthetic-completeness.sh` frontmatter makes the runbook discoverable from the script via `rg`. The runbook does not duplicate the parser regex or the exact exit codes — those live in the script. The runbook describes the contract (what the script gates, why) at a level less brittle to refactor.
- **The runbook claims behavior that is not literally true if the parser regresses.** The strip-all-whitespace bug from #3543 (now fixed) is the canonical example. **Mitigation:** the runbook treats the parser's whitespace-preservation rule as documented invariant and cross-references the learning file. A future regression that violates the invariant will fail `plugins/soleur/test/lint-bot-synthetic-statuses.test.sh` (or its sibling that should exist for completeness — see Test Strategy below).
- **Cross-reference completeness.** Three sibling runbooks need updating; missing one leaves the new runbook orphaned in one direction. **Mitigation:** Phase 3 verification grep counts mentioning files ≥ 3.

## Test Strategy

No new tests. The lint behavior is already covered by `plugins/soleur/test/lint-bot-synthetic-statuses.test.sh` (the statuses-script sibling). A test for the completeness script does not currently exist — that is OUT OF SCOPE for this docs-only PR. Filing a follow-up issue is OPTIONAL; the learning file `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md` already captures the regression class.

If the runbook author finds during writing that the script's documented behavior is unclear or possibly buggy, surface that as inline review comments (or a follow-up issue) — do not silently fix the script in this PR. The brand-survival threshold for the underlying gate is `single-user incident`; touching the script requires a separate code-change PR with `requires_cpo_signoff: true`.

## Non-Goals

- Add a test suite for `lint-bot-synthetic-completeness.sh`. (Tracked separately if needed.)
- Refactor the lint script. (Out of scope — docs-only.)
- Document the "CI Required" ruleset itself. (Already documented at `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md` and `ruleset-bypass-drift.md`.)
- Document the composite action `.github/actions/bot-pr-with-synthetic-checks/action.yml` in depth. (Reference it; do not duplicate its inputs/outputs.)
- Publish the runbook to the public docs site. (Internal operator surface; `knowledge-base/engineering/ops/runbooks/` is not currently in the Eleventy build.)

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Inline the docs as a comment block at the top of `scripts/lint-bot-synthetic-completeness.sh`. | Already partially present; doesn't solve the "operator hits failure, needs a runbook URL" path. The runbook lives in the same surface as sibling runbooks (`skill-security-scan-required-check.md`, `codeql-bot-coverage.md`) so failure-to-runbook routing is consistent. |
| Add a `## Lint behavior` section to `skill-security-scan-required-check.md` instead. | The lint covers four required checks today, not just `skill-security-scan PR gate`. Embedding it under one specific check's runbook creates a discoverability cliff for the other three. Standalone runbook avoids this. |
| Document only the completeness script (issue body's focus); leave the statuses sibling undocumented. | The two scripts share a CI job, share an audience, and fail through the same surface (`lint-bot-statuses` job red). Documenting one leaves the other as a "why is this also red?" surprise. Documenting both is ~30 extra lines, much less than a future operator's debug cost. |

## Sharp Edges

1. The composite action `.github/actions/bot-pr-with-synthetic-checks/action.yml` hard-codes the synthetic check-run names in a bash array (`CHECK_NAMES=(test dependency-review e2e "skill-security-scan PR gate")`). The lint config `scripts/required-checks.txt` is the canonical source. When extending the runbook's "How to extend" section, call out that adding a new check requires editing BOTH — there is no single source of truth today, and the duplication is the bug class that `lint-bot-synthetic-completeness.sh` catches at PR time (a workflow missing a synthetic for a check that's in `required-checks.txt`). Recommend wording: "Always edit `scripts/required-checks.txt` AND `.github/actions/bot-pr-with-synthetic-checks/action.yml` together. The lint catches drift at PR time; a future operator who edits only one will see CI red on the next bot PR."

2. The runbook must not embed the literal lint exit-code semantics (`exit 0` / `exit 1`) — those are implementation details that may change. Describe instead the operator-observable signal: "the `lint-bot-statuses` job is red" or "green".

3. The frontmatter convention varies slightly across sibling runbooks (`title:` is present in some, derived from H1 in others; `threshold:` uses dash-separated values in some, snake-case in others). Pick the most recent sibling (`codeql-bot-coverage.md`, last_updated 2026-05-11) as the canonical template — its convention is the latest reviewed.

4. The runbook adds operator surface; it does not change enforcement. Avoid wording in the runbook that implies the runbook is a gate ("MUST be followed", "MUST update", etc.) — write "operator should" / "the lint enforces" / "the contract is" instead. The gate is `lint-bot-statuses`; the runbook is its documentation.

5. Avoid prescribing exact line numbers when cross-referencing the lint scripts (`scripts/lint-bot-synthetic-completeness.sh:32`). Per constitution §Code Style "Code comments referencing other code MUST use grep-stable symbol anchors", use symbol-stable references — e.g., "the config-line parser in `lint-bot-synthetic-completeness.sh` (the `while IFS= read -r line` loop)".

6. A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. The threshold for this plan is `none`; the docs-only justification is recorded inline. Do not leave the section blank.

## References

- Issue: #3546 (this plan)
- Parent: #3542 (R15 mitigation issue), PR #3543 (R15 mitigation landed)
- Brand-survival origin: #2719
- Lint scripts:
  - `scripts/lint-bot-synthetic-statuses.sh`
  - `scripts/lint-bot-synthetic-completeness.sh`
- Config: `scripts/required-checks.txt`
- Composite action: `.github/actions/bot-pr-with-synthetic-checks/action.yml`
- CI wiring: `.github/workflows/ci.yml` job `lint-bot-statuses`
- Sibling runbooks:
  - `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md`
  - `knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md`
  - `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`
- Existing test (statuses sibling): `plugins/soleur/test/lint-bot-synthetic-statuses.test.sh`
- Cautionary tale: `knowledge-base/project/learnings/2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`
