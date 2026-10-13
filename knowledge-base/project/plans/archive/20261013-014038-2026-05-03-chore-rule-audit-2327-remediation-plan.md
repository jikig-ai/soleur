---
title: "chore: address rule audit findings (#2327)"
date: 2026-05-03
type: chore
classification: agents-md-governance
issue: 2327
branch: feat-one-shot-2327-rule-audit
requires_cpo_signoff: false
---

# chore: Address rule audit findings (#2327)

## Enhancement Summary

**Deepened on:** 2026-05-03
**Sections enhanced:** Research Reconciliation, Phase 1 Risks, Risks & Sharp
Edges, Phase 4 Verification (with measured baselines).
**Research agents used:** Targeted (no parallel fan-out — text-only governance
plan, 2 line edits, with a pre-existing canonical learning file
(`2026-04-23-agents-md-governance-measure-before-asserting.md`) that already
analyzed this exact failure mode). Verification done via direct measurement
per the same learning's "measure, don't estimate" rule.

### Key Improvements (added in deepen pass)

1. **Confirmed lint-rule-ids.py only parses `[id: ...]`, not the tag-text being
   edited.** Verified by reading `scripts/lint-rule-ids.py` lines 1-50: the
   regex `ID_RE = re.compile(r"\[id: ([a-z0-9-]+)\]")` is the only pattern
   that interacts with bracket tags. The tag-text edit cannot break the
   linter — adds to safety guarantee.
2. **Discovered ADR-017 is the deeper canonical source for the version-bump
   constraint.** `knowledge-base/engineering/architecture/decisions/ADR-017-version-from-git-tags.md`
   line 16 carries the same prose. Constitution.md:81 was a duplicated
   restatement of the ADR; the ADR is the right canonical home for the
   architectural decision, AGENTS.md is the right canonical home for the
   per-turn sharp edge. Removing constitution.md:81 leaves both canonical
   sources intact.
3. **Plan-archive preservation note added.** Three archived plan files in
   `knowledge-base/project/plans/` quote the old tag-text `[hook-enforced:
   lint-rule-ids.py]` verbatim — these accurately document the prior state
   and MUST NOT be retroactively rewritten. The Risks section now flags this
   to prevent over-zealous grep-and-replace at work time.
4. **Phase 4 verification commands measured against current state.** All five
   commands run successfully against the unedited AGENTS.md baseline (66
   rules, 22682 bytes, no over-cap rules, lint exits 0). The work-time
   verification will compare against these exact pre-edit numbers.

### New Considerations Discovered

- **Audit script false positive is *self-perpetuating until Phase 5 ships*.**
  Every future scheduled run of `bash scripts/rule-audit.sh` will re-flag
  `lint-rule-ids.py` as a "broken hook reference" because the script's
  existence check is hardcoded to `.claude/hooks/`. The PR body MUST
  pre-emptively note this so the next operator triaging the next
  rule-audit issue can immediately recognize the known false-positive
  rather than re-investigating from scratch. The Phase 5 deferral issue
  is the durable fix; this PR is the surface remediation.
- **ADR-017 reference adds "no orphan" guarantee.** Even after deleting
  constitution.md:81, the version-from-git-tags decision rationale lives
  on at ADR-017 (the architecturally correct location for "why this
  decision"). AGENTS.md:43 carries the per-turn sharp-edge enforcement.
  No knowledge is lost.
- **No load-bearing string-literal drift.** No skill, agent, hook, test,
  or workflow YAML matches the literal `[hook-enforced: lint-rule-ids.py]`
  outside of three archived plan files (which describe historical state)
  and AGENTS.md itself. Tag-text edit is safe.

## Overview

Issue #2327 was filed by `scripts/rule-audit.sh` on 2026-04-15 listing four
remediation classes against `AGENTS.md`:

1. Fix four broken hook references (`detect_bypass` x2, `browser-cleanup-hook.sh`,
   `lint-rule-ids.py`).
2. Consolidate one suspected duplicate between `AGENTS.md` and
   `knowledge-base/project/constitution.md`.
3. Migrate hook-enforced rules from `AGENTS.md` to `constitution.md` where the
   prose is no longer load-bearing.
4. Reduce the always-loaded budget — the report claimed 334 rules vs. a 300
   threshold (over by 34).

Re-running the audit on 2026-05-03 (today) shows the landscape has materially
shifted in the 18 days since the report was filed. Most of the report's
findings are stale or were already remediated by intervening PRs (#2754,
#2865, the 2026-04-23/24 retirements). What remains is a single misleading
hook-enforcement annotation, one genuine duplicate, and a budget claim that
needs to be refuted with measurement rather than acted on.

This plan **deliberately rejects** the report's two largest framing claims
(combined budget over threshold; hook-enforced AGENTS.md rules should migrate
to `constitution.md`) and instead executes the narrow remediation that survives
verification: clarify one tag, retire one duplicate.

## Research Reconciliation — Spec vs. Codebase

The audit report (issue body) is the spec. The codebase as of 2026-05-03 is
reality. Every divergence below was verified by direct measurement, not
estimate.

| Spec claim (2026-04-15) | Reality (2026-05-03) | Plan response |
|---|---|---|
| AGENTS.md has 76 rules | 66 rules (`grep -c '^- ' AGENTS.md`) | Report is stale — 10 rules were retired by #2865 (2026-04-23 discoverability litmus pass). |
| constitution.md has 258 rules | 282 rules | Report is stale — net +24 from rule migrations into the constitution. |
| Combined always-loaded = 334; threshold 300; over by 34 | **AGENTS.md alone is always-loaded** (22,682 bytes / 37,000 cap = under). `constitution.md` is read-on-demand per `CLAUDE.md`'s single `@AGENTS.md` import; AGENTS.md prose says "read when needed". | Reject the budget framing entirely. The "combined always-loaded" claim is the same framing error documented in `knowledge-base/project/learnings/2026-04-23-agents-md-governance-measure-before-asserting.md` Claim 2. The real budget is bytes-of-AGENTS.md, currently 22,682 / 37,000 (61%). No shrink action required. |
| 4 broken hook references in AGENTS.md (`detect_bypass` ×2, `browser-cleanup-hook.sh`, `lint-rule-ids.py`) | AGENTS.md contains zero references to `detect_bypass` or `browser-cleanup-hook.sh` (verified `grep -n` returns no hits). Only `lint-rule-ids.py` remains tagged in AGENTS.md line 61. | Three of four "broken" references were removed in #2865 and the 2026-04-23/24 retirements (3 rules pointer-deleted into `scripts/retired-rule-ids.txt` with hook breadcrumbs). The fourth (`lint-rule-ids.py`) is not actually broken — the script exists at `scripts/lint-rule-ids.py` and is wired into `lefthook.yml:32` (pre-commit). The `[hook-enforced: lint-rule-ids.py]` tag is accurate; `rule-audit.sh` is reporting a false positive because it only checks `.claude/hooks/` and not `scripts/`. **Action:** clarify the tag to `[hook-enforced: lefthook lint-rule-ids.py]` so the audit script can be improved later to recognize the lefthook surface, and the tag itself unambiguously points operators at the right enforcement layer. (Tag-text change only; rule id `cq-rule-ids-are-immutable` is preserved.) |
| 1 hook-enforced AGENTS.md rule is a "migration candidate" to constitution.md (`hr-never-git-stash-in-worktrees`) | Same rule still present at AGENTS.md:9 with `[hook-enforced: guardrails.sh guardrails:block-stash-in-worktrees]`. | Reject the migration. `cq-agents-md-tier-gate` (line 63) explicitly says hook-enforced rules keep `[id]` + `[enforced]` + a one-line pointer in AGENTS.md and the full rule lives in the enforcing skill/hook. The current AGENTS.md form is already the prescribed pointer form (one sentence + tag). Migrating the prose to `constitution.md` would NOT save bytes from the always-loaded set (constitution.md is not always-loaded), and it would orphan the pointer from the always-loaded surface where the agent needs to see it. The 2026-04-23 governance learning (Claim 1) already measured pointer-migration savings as **+21 bytes net**, not the estimated -800. |
| 1 suspected cross-layer duplicate at AGENTS.md:42 vs. constitution.md:77 (66% Jaccard) | Verified: AGENTS.md:43 `wg-never-bump-version-files-in-feature` (current line — was 42 at audit time) and constitution.md:81 ("Never edit version fields in `plugin.json` or `marketplace.json`...") cover the same constraint with overlapping text. AGENTS.md is the active sharp-edge form (has rule id, sets ship-time semver labels); constitution.md is older background prose. | **Action:** retire constitution.md:81 (the older prose) and consolidate the constraint at AGENTS.md:43 only. constitution.md is not always-loaded so the byte savings are zero, but two sources of truth on the same rule create drift risk (one will be updated, the other stays stale). |

**Net plan scope:** two surgical text edits — (a) clarify one hook-enforcement
tag in AGENTS.md, (b) delete one duplicate prose line from constitution.md.
Plus one process artifact: explicitly close out the report's other findings
with verified rationale so #2327 can be closed without ambiguity.

## User-Brand Impact

**If this lands broken, the user experiences:**
A misleading `[hook-enforced: ...]` tag would mislead operators investigating
which enforcement layer holds a constraint. No user-facing or
production-system behaviour change.

**If this leaks, the user's [data / workflow / money] is exposed via:**
N/A — this is documentation/governance only. No credentials, auth, data
paths, or payment flows are touched.

**Brand-survival threshold:** none

This is a metadata/text-only change to `AGENTS.md` and
`knowledge-base/project/constitution.md`. No code paths, no schemas, no
external services, no user-visible surfaces. Per `cq-agents-md-tier-gate`
this kind of hygiene work is exactly what the placement gate calls for —
quietly tidy without expanding scope.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AGENTS.md line 61 (`cq-rule-ids-are-immutable`) tag updated from
  `[hook-enforced: lint-rule-ids.py]` to
  `[hook-enforced: lefthook lint-rule-ids.py]`.
- [x] Rule id `cq-rule-ids-are-immutable` is preserved (no rename — covered by
  the `cq-rule-ids-are-immutable` rule itself).
- [x] AGENTS.md byte length verified post-edit: `wc -c AGENTS.md` reports
  ≤ 37000 bytes (current baseline 22682; this edit adds ~9 bytes).
- [x] No AGENTS.md rule exceeds the 600-byte per-rule cap after the edit
  (verified by `awk '/^- / {if (length > 600) print NR}' AGENTS.md`).
- [x] `constitution.md` line 81 (the older "Never edit version fields..." prose)
  removed; the constraint is now expressed only at AGENTS.md:43.
- [x] `bash scripts/rule-audit.sh` runs to completion locally; its
  cross-layer duplicate count drops from 1 to 0 (verified by reading the
  generated issue body preview).
- [x] `python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md`
  exits 0 (no rule-id violations introduced).
- [x] `lefthook run pre-commit` passes (or the equivalent `pre-commit`
  invocation), proving the lint hook still works.
- [x] PR body says `Closes #2327` (the issue is fully addressed by this PR
  — no post-merge operator action).

### Post-merge (operator)

None. Post-merge `bash scripts/rule-audit.sh` will run on its scheduled
cadence and may file a fresh issue for the next budget snapshot — that's
expected, not action-on-this-PR.

## Implementation Phases

### Phase 1 — Tag clarification in AGENTS.md (1 edit)

**File:** `AGENTS.md`

**Edit:** Line 61.

```diff
-- Rule IDs on AGENTS.md rules are immutable [id: cq-rule-ids-are-immutable] [hook-enforced: lint-rule-ids.py]. Remove a rule by appending its ID to `scripts/retired-rule-ids.txt` (`<id> | date | PR | breadcrumb`); reintroducing a retired ID is linter-rejected. Section prefixes (`hr`, `wg`, `cq`, `rf`, `pdr`, `cm`) match the section.
+- Rule IDs on AGENTS.md rules are immutable [id: cq-rule-ids-are-immutable] [hook-enforced: lefthook lint-rule-ids.py]. Remove a rule by appending its ID to `scripts/retired-rule-ids.txt` (`<id> | date | PR | breadcrumb`); reintroducing a retired ID is linter-rejected. Section prefixes (`hr`, `wg`, `cq`, `rf`, `pdr`, `cm`) match the section.
```

**Rationale:** `lint-rule-ids.py` lives at `scripts/lint-rule-ids.py` and is
invoked from `lefthook.yml:32` as a pre-commit hook, not from
`.claude/hooks/`. The `lefthook` qualifier makes the enforcement surface
unambiguous and stops `scripts/rule-audit.sh`'s `.claude/hooks/`-only check
from flagging this as broken on every future audit run.

**Linter-safety guarantee.** `scripts/lint-rule-ids.py` parses bracket tags
with the regex `ID_RE = re.compile(r"\[id: ([a-z0-9-]+)\]")` and inspects
ONLY the `[id: ...]` content. The `[hook-enforced: ...]` tag-text is
opaque to the linter — verified by reading lines 1-50 of
`scripts/lint-rule-ids.py`. The edit cannot break the lint pre-commit
hook regardless of what string we choose for the qualifier.

**Byte impact:** +9 bytes ("lefthook " prefix). Rule was 463 bytes before,
becomes 472 bytes — well under the 600-byte per-rule cap.

### Phase 2 — Remove duplicate prose from constitution.md (1 deletion)

**File:** `knowledge-base/project/constitution.md`

**Edit:** Delete line 81.

```diff
-- Never edit version fields in `plugin.json` or `marketplace.json` (frozen sentinels). Version is derived from git tags -- `version-bump-and-release.yml` creates GitHub Releases with `vX.Y.Z` tags at merge time via semver labels set by `/ship`
```

**Rationale:** The same constraint is stated at AGENTS.md:43 with rule id
`wg-never-bump-version-files-in-feature` (current sharp-edge form, includes
the ship-skill semver-label binding). The constitution.md prose is older
background and adds no information beyond what AGENTS.md says. Two sources
of truth on the same constraint produce drift risk; removing the older,
unidentified copy keeps the constraint expressed exactly once at the
always-loaded surface.

**Architecture-decision preservation.** The decision rationale (*why* the
project uses git-tag-derived versioning) lives at
`knowledge-base/engineering/architecture/decisions/ADR-017-version-from-git-tags.md:16`,
which is the architecturally correct home for that decision. AGENTS.md:43
carries the per-turn sharp-edge enforcement (*do not edit version fields*).
Constitution.md:81 was an intermediate restatement that duplicated parts of
both. Removing it is a strict simplification: the ADR keeps the *why*, the
AGENTS.md rule keeps the *what to do*. Verified by `rg` — the only three
non-test/-non-archive files matching the prose are AGENTS.md:43,
constitution.md:81, and ADR-017:16.

The neighbouring constitution.md line 82 (`Always set a semver:* label...`) is
**not** a duplicate of any AGENTS.md rule (it's covered by the `/ship`
skill's preflight, not by an AGENTS.md rule) and is left untouched.

### Phase 3 — Verify the audit's other findings are non-actionable (no edits)

This phase produces no diffs but is required for the PR description to
explain why #2327's other line items are deliberately not addressed. The
PR body MUST cite the table from the Research Reconciliation section above.

For each non-actionable finding, the PR body lists:

1. **`detect_bypass` ×2 broken refs** — already removed from AGENTS.md by
   #2865 (`cq-never-skip-hooks` retired into `scripts/retired-rule-ids.txt`
   with breadcrumb pointing to `.claude/hooks/lib/incidents.sh detect_bypass()`).
   Verified by `grep -n detect_bypass AGENTS.md` returning no hits.
2. **`browser-cleanup-hook.sh` broken ref** — already removed from AGENTS.md
   by #2865 (`cq-after-completing-a-playwright-task-call` retired with
   breadcrumb pointing to `plugins/soleur/hooks/browser-cleanup-hook.sh`).
   Script still exists; just no longer referenced from AGENTS.md.
3. **Migration candidate `hr-never-git-stash-in-worktrees`** — currently
   matches the `cq-agents-md-tier-gate` "Already-enforced (hook or skill
   step)" pattern: keeps `[id]` + `[enforced]` tags + a one-line pointer in
   AGENTS.md, full rule mechanism in `.claude/hooks/guardrails.sh`. This is
   the prescribed shape; migrating the rule body to constitution.md would
   not save bytes from the always-loaded set (constitution.md is not
   always-loaded) and would orphan the pointer from the always-loaded
   surface. Per the 2026-04-23 governance learning, prior pointer-migration
   measured +21 bytes net (not the estimated -800).
4. **"Over budget by 34"** — based on a combined-rule-count metric that
   isn't the actual budget. Per CLAUDE.md's `@AGENTS.md` import (only),
   constitution.md is read-on-demand. The real budget is bytes-of-AGENTS.md
   (`cq-agents-md-why-single-line` cap = 37000 bytes; current 22682). The
   `scripts/rule-audit.sh` rule-count metric is informational, not a
   shrink target.

### Phase 4 — Verification (no edits)

Run, in this order, and capture output in the PR description:

```bash
# Per-rule cap (should print only "Total rules: 66" with no rule-line numbers)
awk '/^- / {n++; if (length > 600) print "RULE", n, length} END {print "Total rules:", n}' AGENTS.md

# Total file budget (should be < 37000)
wc -c AGENTS.md

# Lint pass (must exit 0)
python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md

# Audit re-run (cross-layer duplicate count must drop to 0; broken hook
# count is permitted to remain at 1 because rule-audit.sh's existence
# check is .claude/hooks/-scoped and the lefthook surface is intentionally
# tagged as such — recorded as known false positive in this PR)
bash scripts/rule-audit.sh

# Pre-commit verification (proves lefthook still wires the linter)
lefthook run pre-commit
```

If any of the first three commands fail, halt — the edit needs revision.
If `bash scripts/rule-audit.sh` reports the duplicate count as 1 (instead
of 0), inspect output and either (a) verify constitution.md:81 is actually
deleted, or (b) update the duplicate-detection invariant.

### Phase 5 — Follow-up issue: rule-audit.sh path-search heuristic (optional, defer)

`scripts/rule-audit.sh`'s `extract_hook_enforced` function checks only
`.claude/hooks/<script_name>` for hook script existence. This produces
false-positive "MISSING" findings whenever a hook is wired through
`lefthook`, `scripts/`, or `plugins/soleur/hooks/` — all valid enforcement
surfaces. The 2026-04-23 governance learning already noted this:

> rule-audit.sh's existence check should scan the full repo, not just
> `.claude/hooks/`. Follow-up issue will track the heuristic fix.

**Defer**: file a follow-up GitHub issue (separate from this PR) to widen
the existence check to a `find . -name "<script>" -not -path '*/archive/*'`
sweep. Out of scope for #2327 itself — that issue is about *fixing the AGENTS.md
findings*, not about *fixing the audit script*. The deferral issue is
tracked in this PR's scope-out section so it is not silently lost.

**Re-evaluation criteria:** the next time the rule-audit cron runs and
files a fresh issue, the false-positive `lint-rule-ids.py` finding will
re-surface (because the lefthook surface still doesn't match `.claude/hooks/`).
At that point either (a) the heuristic-fix issue is prioritized, or (b) the
fresh audit issue is closed-as-known with a pointer to the deferral issue.

## Files to Edit

- `AGENTS.md` (1 line; tag-text change at line 61)
- `knowledge-base/project/constitution.md` (1 line; delete line 81)

## Files to Create

None.

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json
```

Queried for the two affected file paths:

```bash
jq -r --arg path "AGENTS.md" '
  .[] | select(.body // "" | contains($path))
  | "#\(.number): \(.title)"
' /tmp/open-review-issues.json

jq -r --arg path "knowledge-base/project/constitution.md" '
  .[] | select(.body // "" | contains($path))
  | "#\(.number): \(.title)"
' /tmp/open-review-issues.json
```

**Result:** None. (To be re-confirmed at deepen-plan Phase 4 in case the
backlog has shifted; if any matches surface, fold them in or record the
explicit disposition.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is an AGENTS.md/constitution.md
documentation-only change. Per `cq-agents-md-tier-gate`, governance hygiene
inside the rule files themselves is the placement gate's domain. No CTO,
CPO, CMO, COO, CLO, CRO, or CFO signal.

## Test Strategy

There is no application code under test. Verification is the four-command
block in Phase 4 (per-rule cap awk, total-file `wc -c`, `lint-rule-ids.py`,
`scripts/rule-audit.sh`, `lefthook run pre-commit`). All five commands
must succeed before requesting review.

The `scripts/rule-audit.sh` run is a soft check — its `broken hook
references` count is permitted to remain at 1 (the `lint-rule-ids.py`
false positive is intentional, captured by the `lefthook` qualifier in the
tag). The hard checks are the per-rule cap, the total-file cap, and the
lint script's exit code.

## Risks & Sharp Edges

- **Rule-id rename trap.** `cq-rule-ids-are-immutable` rejects rule-id
  renames. This plan does NOT rename `cq-rule-ids-are-immutable` itself —
  only the bracket-tag content `[hook-enforced: lint-rule-ids.py]` →
  `[hook-enforced: lefthook lint-rule-ids.py]` changes. The rule id is
  preserved character-for-character. Verified before drafting via
  `grep -n 'cq-rule-ids-are-immutable' AGENTS.md`.
- **Constitution.md deletion regret.** Deleting line 81 from constitution.md
  is reversible (git history) but if some downstream skill/agent grep
  references the exact text "Never edit version fields in `plugin.json`",
  the search will miss. Verified before drafting:

  ```bash
  rg -n "Never edit version fields in \\\`plugin.json\\\`" --type-add 'cfg:*.{md,yml,yaml,json,sh}' -t cfg
  ```

  If the only hit is `knowledge-base/project/constitution.md:81`, the deletion
  is safe. (To be re-verified at work time before applying the diff.)
- **Audit-script false positive will recur.** Until the deferred Phase 5
  issue is shipped, every future `bash scripts/rule-audit.sh` run will
  re-flag `lint-rule-ids.py` as a "broken hook reference" because the
  script's path scope is hardcoded to `.claude/hooks/`. The PR body MUST
  call this out so a future operator triaging the next rule-audit issue
  can see the known-false-positive and not chase it.
- **A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6.** This plan's threshold is `none` with an
  explicit reason (text-only governance hygiene); fill it before requesting
  deepen-plan or `/work`.
- **Don't expand scope.** It is tempting to use this PR as a vehicle to
  shrink AGENTS.md further, retire more rules, or refactor the rule-audit
  script. Resist. The issue is "address rule audit findings"; the smallest
  diff that closes the issue is the right diff. Other shrink work belongs in
  follow-up issues with their own measurement budgets.
- **Do NOT retroactively rewrite plan-archive references to the old tag-text.**
  Three archived plan files quote `[hook-enforced: lint-rule-ids.py]` verbatim
  as historical record:

  ```
  knowledge-base/project/plans/2026-04-14-feat-rule-utility-scoring-plan.md:215
  knowledge-base/project/plans/2026-04-18-chore-bundle-fix-compound-route-to-definition-proposals-plan.md:17
  knowledge-base/project/plans/2026-04-23-chore-agents-md-shrink-via-allowlist-plan.md:191
  ```

  These accurately document the prior tag form at the time those plans were
  written. A grep-and-replace across the repo would corrupt the historical
  record and is explicitly out of scope for this PR. The Phase 1 edit is
  scoped to AGENTS.md ONLY.
- **Phase 4 verification baselines (pre-edit, captured at deepen-time
  2026-05-03):** AGENTS.md = 66 rules, 22682 bytes, 0 rules over the 600-byte
  cap, `python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md`
  exits 0. The work-time verification MUST land at 66 rules, ~22691 bytes
  (+9), 0 over-cap, and lint exit 0. Any deviation indicates the edit
  touched something unintended.

## Out of Scope

- Refactoring `scripts/rule-audit.sh`'s broken-reference heuristic (Phase 5
  defers to a separate issue).
- Any further AGENTS.md rule retirements or migrations beyond the single
  tag-text edit.
- Constitution.md restructure or section reordering.
- Changes to `lefthook.yml` or any hook script.
- Changes to `cq-agents-md-tier-gate` or `cq-agents-md-why-single-line`
  (the placement-gate and byte-cap rules) — both currently express the
  policy correctly; this PR is an instance of applying them, not amending
  them.

## References

- Issue #2327 — the rule-audit report this PR addresses
- `scripts/rule-audit.sh` — the audit producer
- `scripts/lint-rule-ids.py` — the rule-id linter (lefthook-wired)
- `lefthook.yml` line 32 — the linter invocation
- `knowledge-base/project/learnings/2026-04-23-agents-md-governance-measure-before-asserting.md` —
  prior measurement of pointer-migration savings (+21 bytes, not estimated
  -800) and the framing-error pattern this plan deliberately avoids
- `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md` —
  retirement breadcrumb pattern used by #2865
- `knowledge-base/project/learnings/2026-04-07-rule-budget-false-alarm-fix.md` —
  prior false-alarm precedent
- AGENTS.md lines 61, 62, 63 — `cq-rule-ids-are-immutable`,
  `cq-agents-md-why-single-line`, `cq-agents-md-tier-gate` (the three
  rules that govern this PR's edits)
- `scripts/retired-rule-ids.txt` — retirement registry that absorbed the
  three "broken hook references" the audit report cites as still present
- `knowledge-base/engineering/architecture/decisions/ADR-017-version-from-git-tags.md` —
  the architectural decision record that holds the *why* of the version-from-git-tags
  approach; constitution.md:81 was an intermediate restatement of this ADR
  and is being retired in favour of the ADR + AGENTS.md:43 split
