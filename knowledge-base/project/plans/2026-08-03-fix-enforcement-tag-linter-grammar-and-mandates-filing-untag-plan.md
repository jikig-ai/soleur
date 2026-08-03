---
title: "fix: teach the enforcement-tag linter the corpus's real tag grammar, wire it to CI, and untag mandates-filing"
date: 2026-08-03
type: fix
lane: cross-domain
brand_survival_threshold: none
closes: [7174, 7172, 6751, 4622]
branch: feat-one-shot-7174-7172-mandates-filing-and-enforcement-tag-lint
pr: 7194
---

# fix: enforcement-tag linter grammar + CI wiring + mandates-filing untag

> **Lane note.** No `spec.md` exists for this branch, so `lane:` defaulted to
> `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-08-03
**Method note:** this session runs under an operator config that forbids
spawning subagents, so the deepen pass was executed **inline** — every gate and
verification below was run mechanically rather than delegated. The mandated
halts all ran; no research fan-out occurred. Recorded here so a reader does not
mistake the absence of agent output for a skipped phase.

### Gates run

| Gate | Result |
|---|---|
| 4.4 Precedent-diff | **Satisfied.** Sibling precedent found and adopted: `scripts/test-all.sh:277-278` registers `lint-rule-ids` as a `-unit` + `-live` pair; Phase 4 mirrors it exactly. Scheduled-work sub-check N/A (no new job). |
| 4.5 Network-outage | Skipped — no trigger pattern; no SSH-provisioned resource. |
| 4.55 Downtime & cutover | Skipped — no infra reboot/replace, no lock-taking DDL, no deploy/router change. |
| 4.6 User-Brand Impact | **PASS** — heading present, 11 non-blank lines, threshold `none`. Sensitive-path regex run against all 12 Files-to-Edit/Create paths: **zero matches**, so `none` is valid without a scope-out bullet. |
| 4.7 Observability | **PASS** — all 5 fields present with non-placeholder values; `discoverability_test.command` contains no `ssh`. |
| 4.8 PAT-shaped variable | **PASS** — zero matches across all four PAT patterns. |
| 4.9 UI-wireframe | Skipped — zero UI-surface files (no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`). |
| 4.10 Encryption posture | Skipped — zero store-class files (`.tf`, `supabase/migrations/*.sql`, `cloud-init*`, `docker-compose*`); no new store or cross-component connection. |

### Verification checks run

- **Cited rule IDs** — every `\b(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]+\b` token in the plan resolves to an active `[id: …]` in `AGENTS.md`. No fabricated or retired citations.
- **Cited issue/PR numbers** — `#7174`, `#7172`, `#6751`, `#4622` all live-verified **OPEN**; PR `#7194` **OPEN**. No number cited from memory.
- **ADR ordinal** — re-derived after `git fetch origin main`. Highest on **fresh** `origin/main` is ADR-157, so **ADR-158 is free**. Still provisional; `/ship` re-verifies, and a renumber must sweep this plan, `tasks.md`, and AC16.
- **Knowledge-base citations** — every `knowledge-base/…\.md` path in the plan resolves on disk except the three this plan creates.
- **Self-grep scope** — no AC greps a scope containing this plan or its `tasks.md`; AC7/AC8 are scoped to `AGENTS.rules.md`, AC15 reads the plan deliberately.

### Key improvements over the plan's first draft

1. The reconciliation table now carries the measurement that **inverts the issue's prescribed remedy** — 9 of 12 failures are parser-grammar limits, not corpus errors.
2. Ack-row budget corrected from the issue's "three or more" to **one**, because no rule body is factually wrong.
3. Two sibling issues (**#6751**, **#4622**) folded in — they are the same defect and would otherwise rot as stale trackers.

### New consideration discovered during the deepen pass

The `AGENTS.rules.md:8` legend false positive was introduced by the *same PR*
that filed these issues, and it is the **sole** cause of both
`lint-agents-enforcement-tags.test.sh` T1 failures. That makes Phase 1.2 a
higher-leverage single edit than its size suggests: it converts the suite from
7/9 to 9/9 and unlocks the Phase 4 de-orphaning.

## Overview

Two operator-facing work items that must ship together because both touch
`AGENTS.rules.md`, `.claude/rule-body-hashes.txt`, and the ADR-092 ack ledger —
splitting them into parallel worktrees would collide on the manifest.

**Item A (#7174)** — a decision-challenge the operator has now answered. Remove
` [mandates-filing]` from `wg-when-deferring-a-capability-create-a`; keep it on
`wg-block-pr-ready-on-undeferred-operator-steps`.

**Item B (#7172)** — the enforcement-tag linter. The issue frames this as "the
linter lints zero tags because its argparse default is `["AGENTS.md"]`, and the
12 resulting failures are wording drift to be fixed by aligning tags to
headings." **Measurement falsified most of that framing.** The corrected
diagnosis, and the fix it implies, are in the reconciliation table below.

Because the corrected diagnosis requires **zero** `AGENTS.rules.md` body edits
for Item B, this plan needs **one** ack row, not the "three or more" the issue
budgeted.

Net issue flow: **closes 4, files 0.**

## Research Reconciliation — Spec vs. Codebase

Every row was measured in the worktree at `68996d3ed`. The first four rows
change what gets built.

| Issue #7172 claim | Reality | Plan response |
|---|---|---|
| "The linter's default invocation reports zero checks, so nothing is validated." | Half true. The **default** is vacuous, but `lefthook.yml:87` already runs `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.rules.md` — both files, explicitly. The lefthook invocation lints 12 hook + 32 skill tags and **fails with 13 errors**. | The real defect is **wiring, not the default**: the linter is lefthook-only and appears in **zero** `.github/workflows/` files. Main drifted because pre-commit never fired on it. Fix the default *and* register it in `scripts/test-all.sh`. |
| "FAIL: 12 unresolved enforcement tag(s)." | **13** live. The 13th is `AGENTS.rules.md:8` — the **tag legend blockquote** `[hook-enforced: …]`, matched by `HOOK_TAG_RE` as if it were a real tag. `git log -L 8,8` attributes that line to PR #7161 — the same PR that filed this issue. | Skip non-body lines. This is also the sole cause of both `lint-agents-enforcement-tags.test.sh` T1 failures, so fixing it turns that suite 9/9 green. |
| "Ten are anchor-wording drift … align tag ↔ heading; decide per case which side is authoritative." | **Only two of twelve are wording drift** (both on line 126). Nine are **grammar** mismatches: the corpus uses `/` for multi-skill (`plan/work/ship`), `+` for multi-enforcer (`Phase 2.8 + iac-plan-write-guard.sh`), and `§` for sections — none of which the linter's one-skill-one-anchor grammar can parse. `resolve_anchor` hard-rejects any anchor containing `/` (`:118`), so five tags can **never** resolve. | Extend the **linter's** grammar to the vocabulary the corpus actually uses. Do not rewrite nine accurate rule bodies to satisfy a deficient parser. |
| "Two point at skills that do not exist on disk … retire the rule or repoint the tag." | Neither is a missing skill. `[skill-enforced: components.test.ts AUTONOMOUS_LOOP_SKILLS]` names `plugins/soleur/test/components.test.ts` (exists; symbol present, 2 hits). `[skill-enforced: workflow-fidelity.ts]` names `plugins/soleur/lib/workflow-fidelity.ts` (exists). `SKILL_TAG_RE` captures the leading `[a-z][a-z0-9-]*` and mistakes `components` / `workflow-fidelity` for skill slugs. | Both tags are **already correct**. Teach the grammar file-form enforcers. No rule body changes, no ack rows, no retirements. |
| "Keep `AGENTS.md` in the list — pointer lines may legitimately carry tags per `POINTER_LINE_RE`." | `AGENTS.md` currently carries **0** enforcement tags, and `POINTER_LINE_RE` is defined in `lint-rule-ids.py:160` / `lint-rule-bodies.py:102` — **not** in this linter. | Keep `AGENTS.md` anyway (harmless, future-proof), but the vacuity floor is asserted over the **sum** across files so a 0-tag `AGENTS.md` alone still trips it. |

**The load-bearing finding:** every enforcer named by all 12 tags **exists and
actually enforces** — all 7 skills, both hook scripts, both file-form targets,
and every phase anchor (`plan ### 2.8 / ### 1.8 / ### 2.9 / ### 2.5`,
`brainstorm Phase 3.55`, `deepen-plan Phase 4.9`, `brainstorm budget
checkpoint`). Not one tag is factually wrong. Following the issue's prescription
would have **destroyed accurate documentation to satisfy a deficient parser**.

## Premise Validation

- **#7174 OPEN, #7172 OPEN** — `gh issue view`, no closing PRs. Both premises live.
- **#7174 premise holds** — `AGENTS.rules.md:85` and `:94` both still carry `[mandates-filing]`; `:10` is header prose.
- **#7172 premise partly stale** — `default=["AGENTS.md"]` confirmed at `:303`, but see reconciliation row 1.
- **Sibling issues found, same defect family, both OPEN:** **#4622** ("10 pre-existing unresolved enforcement-tags; fails on main") and **#6751** ("test.sh fails on main (2 of 9), excluded from the orphan-suite gate"). Both are resolved by this work; folding them in is correct rather than leaving two stale trackers.
- **Cited-but-merged context** — the mandated-filing exemption shipped 2026-08-02 (ADR-155). Cited as prose, never as an issue ref.
- **`silent-failure-hunter`** — not a repo file; it is the installed `pr-review-toolkit:silent-failure-hunter` plugin agent. The grammar must treat a `review-agent <name>` segment as descriptive, not as a repo-path assertion.

## User-Brand Impact

**If this lands broken, the user experiences:** a red required check on every
subsequent PR that touches `AGENTS.md` / `AGENTS.rules.md` — the corpus becomes
un-editable until someone reverts. Or, if the grammar is made too permissive,
the opposite: a green gate that validates nothing, which is the exact failure
this work exists to close.

**If this leaks, the user's data/workflow/money is exposed via:** no exposure
vector. This changes a repo-local lint script, a corpus marker, and a test
registration. No user data, no network surface, no credentials.

**Brand-survival threshold:** `none` — reason: internal developer tooling with
no user-facing surface, no persistent store, and no regulated data. The diff
touches no sensitive path.

## Architecture Decision (ADR/C4)

### ADR

**Create ADR-158** (ordinal provisional — highest on disk is ADR-157; `/ship`
re-verifies against `origin/main` before merge, and a renumber must sweep this
plan, `tasks.md`, and every AC that names the ordinal).

**Decision:** *The rule corpus's enforcement-tag vocabulary is authoritative; the
linter conforms to the corpus, not the reverse.* When a tag and the linter
disagree, the default remediation is to extend the parser — rewriting a rule body
is reserved for tags that are **factually wrong** about their enforcer. Rationale:
tag bodies are ADR-092-gated human-reviewed security-tagged text whose edits cost
an ack row each; the parser is ungated code. Optimising the cheap side is correct.
Records the three grammar extensions (`/`-joined skills, `+`-joined enforcer
segments, file-form enforcers) as the supported vocabulary so the next rule author
knows what is expressible.

**Alternatives considered** (must be recorded): (a) normalise all tags to the
one-skill-one-anchor grammar — rejected: 9 ack rows, information loss, and it
encodes the parser's limits into the corpus; (b) delete the anchor-parity check —
rejected: it is the only thing tying a rule to a live enforcer.

Neighbours to cross-reference: ADR-151 (corpus split created the drift),
ADR-092 (why body edits are expensive), ADR-155 (the `[mandates-filing]` marker
Item A edits).

### C4 views

**No C4 impact.** Checked all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`
for the enumeration the completeness mandate requires: **external human actors** —
none added or changed (this is a repo-local lint script; the only actor is the
already-modelled founder/agent); **external systems/vendors** — none (no network
call, no vendor API, GitHub Actions is the existing CI runner already modelled);
**containers/data stores** — none (no new store; the ack ledger and hash manifest
are existing committed files, not modelled containers); **actor↔surface access
relationships** — unchanged (no new permission, role, or sharing boundary). No
element description is falsified by this change.

### Sequencing

The decision is true on merge. Nothing is soak-gated.

## Observability

```yaml
liveness_signal:
  what: scripts/test-all.sh runs `lint-agents-enforcement-tags-live` and `-unit`
  cadence: every CI run (per-PR) and every local `test-all.sh`
  alert_target: red required check on the PR
  configured_in: scripts/test-all.sh (registration), lefthook.yml:87 (pre-commit)
error_reporting:
  destination: CI job log + non-zero exit; per-tag ERROR lines on stderr naming file:line
  fail_loud: true — vacuity floor makes "scanned nothing" an ERROR, not a pass
failure_modes:
  - mode: corpus moves again (a future ADR-151-class split)
    detection: vacuity floor trips — "0 enforcement tags across N file(s)"
    alert_route: red check, message names the scanned paths
  - mode: a tag names an enforcer that is deleted
    detection: existing per-tag resolution ERROR
    alert_route: red check naming file:line and the unresolved token
  - mode: grammar extension made too permissive (silent always-pass)
    detection: T2 negative case + the resolved-pair count assertion in the floor
    alert_route: red check
logs:
  where: GitHub Actions job log for the test-all job; local stderr
  retention: GitHub default (90d)
discoverability_test:
  command: python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.rules.md; echo "EXIT=$?"
  expected_output: "OK: all 12 hook + 32 skill + N anchor parity check(s) resolve" with EXIT=0
```

No `ssh` anywhere in the verification path.

## Implementation Phases

Phase order is load-bearing: the contract change (grammar) must precede the
consumers (default flip, CI registration, floor), or the intermediate states are
red for reasons the later phases fix.

### Phase 0 — Preconditions (verify, do not assume)

1. Re-run the baseline and pin it: `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.rules.md 2>&1 | tail -3` → expect `FAIL: 13`.
2. `bash scripts/lint-agents-enforcement-tags.test.sh` → expect `Total: 9 Pass: 7 Fail: 2`, both failures on T1.
3. Confirm the ADR-158 ordinal is still free against `origin/main`.

### Phase 1 — Linter grammar (TDD: failing tests first, per `cq-write-failing-tests-before`)

Write the RED cases in `scripts/lint-agents-enforcement-tags.test.sh` before
touching the script. Add to `scripts/lint-agents-enforcement-tags.py`:

1. **Skip non-body lines.** Only lines that are real rule bodies carry tags. Reuse
   the discipline `lint-rule-bodies.py` already encodes: a body line starts with
   `- ` at column 0. Skip blockquote (`> `) and other prose. Fixes the `:8` legend
   false positive without editing the legend.
2. **`/`-joined skill lists.** Split the leading token on `/` into a skill list
   (`plan/work/ship gates` → skills `[plan, work, ship]`, anchor `gates`). Require
   **every** named skill to exist; require the anchor to resolve in **at least
   one** (a cross-skill gate legitimately has its heading in one of them). Widen
   `SKILL_TAG_RE` accordingly, and narrow the `/`-rejection in `resolve_anchor`
   to the *anchor*, keeping the `..` path-traversal rejection intact.
3. **`+`-joined enforcer segments.** Split the anchor on ` + ` and resolve each
   segment independently against the right resolver: a `Phase X.Y` / heading
   segment against the skill's SKILL.md; a `*.sh` / `*.py` segment against
   `HOOK_SEARCH_DIRS`; a `review-agent <name>` / `hook <script>` segment against
   its own namespace. All segments must resolve.
4. **File-form enforcers.** When the token carries a file extension
   (`components.test.ts`, `workflow-fidelity.ts`), resolve it as a repo file
   (search `plugins/soleur/{test,lib}`, `scripts/`) instead of a skill dir. If a
   trailing symbol is given (`AUTONOMOUS_LOOP_SKILLS`), require it to appear in
   that file.
5. **`§X.Y` → `### X.Y` normalization**, mirroring the existing `Phase X.Y`
   variant. Fixes `plan §1.8`.
6. **`brainstorm Phase 2 budget checkpoint`** — the one genuine wording drift the
   variants still miss. Resolve by tightening the tag to the anchor that exists
   (`budget checkpoint` is present in `brainstorm/SKILL.md`, 2 hits). **This is
   the only tag whose text may change**, and only if a grammar variant cannot
   reach it — decide with a measurement, not a preference. If it does change,
   it needs its own ack row (see Phase 3).

Exit condition: `FAIL: 13` → `OK`, with **no** `AGENTS.rules.md` edit yet.

### Phase 2 — Vacuity floor + default (the consumers of Phase 1)

1. **Vacuity floor in the script.** After the scan, if `total_hook_tags +
   total_skill_tags == 0`, print an ERROR naming the scanned paths and exit 1.
   The failure class is "the gate silently checked nothing", and only a
   cardinality floor catches it. Precedent: the `MIN_ASSERTIONS` floor in
   `plugins/soleur/test/net-issue-flow.test.sh`.
2. **Flip the argparse default** to `["AGENTS.md", "AGENTS.rules.md"]` so a bare
   invocation is not vacuous. Note the deliberate consequence: `... .py AGENTS.md`
   alone now **fails** the floor (0 tags), which is correct — that is the vacuity
   signal, not a regression.
3. Add a test asserting the floor fires on a tag-free fixture.

### Phase 3 — `[mandates-filing]` untag (#7174)

1. Remove ` [mandates-filing]` from the `wg-when-deferring-a-capability-create-a`
   body in `AGENTS.rules.md`. **One-line edit.** Do not touch the rule's mandate text.
2. Check the ADR-155 header prose (`AGENTS.rules.md:10-17`) — it describes the
   marker generically and does not enumerate rules, so it likely needs no change.
   Correct it **only** if it asserts a count or names both rules.
3. Sweep for prose that now over-states the tagged set: `.claude/hooks/ship-net-issue-flow-gate.sh`,
   `plugins/soleur/skills/ship/scripts/net-issue-flow.sh`, ADR-155, and the two
   test files. Any that says "two rules" must become one. Comments that name only
   `wg-block-pr-ready-on-undeferred-operator-steps` are already correct.
4. `python3 scripts/lint-rule-bodies.py --write` to regenerate `.claude/rule-body-hashes.txt`.
5. Append the ack row to `.claude/rule-weakening-acks.txt` in the
   `<id>|<sha256>|<date>|<PR>|<reason>` format. The reason must record the
   **decisive** evidence (nothing writes the claim), not the refuted one — see
   Decision Record below. The existing 2026-08-02 ack for this rule already
   anticipates this: *"Untagging is a one-line corpus edit under this same gate."*
6. Update `knowledge-base/project/specs/feat-one-shot-net-issue-flow-mandated-filing-exemption/decision-challenges.md`
   (DC-1 → resolved, with the disposition) and `discovered-defects.md` (DD-1 →
   resolved, **and correct DD-1's own diagnosis** per the reconciliation table).

### Phase 4 — Wiring (close #6751 and #4622)

1. Register both suites in `scripts/test-all.sh`, mirroring the existing
   `lint-rule-ids` pattern at `:277-278`:
   - `run_suite "scripts/lint-agents-enforcement-tags-unit" bash scripts/lint-agents-enforcement-tags.test.sh`
   - `run_suite "scripts/lint-agents-enforcement-tags-live" python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.rules.md`
2. **Remove** the allowlist entry at `scripts/lint-orphan-test-suites.sh:24` — the
   suite is no longer orphaned or failing. Leaving it would re-hide the next
   regression.
3. Leave `lefthook.yml:87` unchanged — it already passes both files correctly.

### Phase 5 — ADR + learning

1. Write `ADR-158-enforcement-tag-grammar-conforms-to-the-corpus.md`.
2. Write a learning capturing the two transferable findings: (a) *an issue's
   diagnosis is a hypothesis — measure the failure set before adopting its
   prescribed remedy*, and (b) *when a gate and its corpus disagree, fix the
   ungated side*. Include the #7174 measurement (below) so it is preserved in a
   durable artifact, per the issue's explicit ask.

## Decision Record — #7174 (operator-answered; do not re-litigate)

**A1 — DECIDED: remove the marker from `wg-when-deferring-a-capability-create-a`;
keep it on `wg-block-pr-ready-on-undeferred-operator-steps`.**

The deciding evidence is **not** "the gate becomes advisory" — a measurement
taken 2026-08-03 refuted that framing and must be recorded honestly:

> Over the 30 days to 2026-08-03: 442 merged PRs, 729 issues filed. Of 256 merged
> PRs with any closing-or-filing activity, **138 would block** at NET>0.
> Simulating the exemption: tagging **both** rules flips 8 blocked PRs (5.8%)
> under strict label-only classification and 32 (23.2%) under a deliberately
> over-inclusive keyword proxy; tagging **only the first** flips 2 (1.4%) / 10
> (7.2%). So **77–94% of blocked PRs still block either way.** The gate does not
> become advisory, and the ">half" bar the decision-challenge issue itself set
> was **not** met.
>
> Method, stated honestly: classification used the `deferred-scope-out` /
> `deferred-automation` labels plus a keyword proxy; **178 of 256** deferral
> classifications came from the keyword proxy rather than the label, which is why
> the result is a bounded range and not a point estimate.

The **decisive** point instead: **nothing writes the claim.** Every writer emits
the *first* rule id literally — `plugins/soleur/skills/ship/SKILL.md` (Phase 5.5
issue-creation snippet, ~`:1175`) and `plugins/soleur/skills/work/SKILL.md`
(operator-only deferral table row, ~`:897`). **No writer anywhere emits
`Mandated-By: wg-when-deferring-a-capability-create-a`.** An agent citing it
would be hand-authoring the string — precisely the free-form-reason shape the
closed vocabulary exists to prevent. Secondary: that rule's default is
document-in-place; filing is one conditional branch gated on a triple test the
gate cannot observe.

**A2 — DECIDED: no change.** Keep the corpus-marker mechanism. Do **not** revert
to a free-form `reason=` token. The self-serve constraint is unchanged. ADR-155
already records honestly that the mechanism buys a closed vocabulary and
per-rule attribution rather than tamper-evidence — leave that framing intact.

## Acceptance Criteria

### Pre-merge (PR)

1. `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.rules.md; echo EXIT=$?` → `EXIT=0` and an `OK: all …` line. *(This is the exact lefthook invocation — the AC runs the gate's own command, per `cq-assert-anchor-not-bare-token`'s input-side twin.)*
2. `python3 scripts/lint-agents-enforcement-tags.py; echo EXIT=$?` (bare, default args) → `EXIT=0`, and the OK line reports **non-zero** hook and skill counts.
3. The OK line reports `12 hook + 32 skill` tags — asserting the **expected** counts, not merely "> 0".
4. `bash scripts/lint-agents-enforcement-tags.test.sh` → `Fail: 0`, and total cases **increased** (new floor + grammar cases).
5. Vacuity floor fires: running the linter against a tag-free fixture exits 1 with a message naming the scanned paths.
6. Negative case preserved: a fixture with a genuinely unresolvable anchor still exits 1. *(Guards against the grammar becoming a silent always-pass.)*
7. `grep -c '\[mandates-filing\]' AGENTS.rules.md` → `2` (the header-prose mention at `:10` plus the single surviving body tag).
8. `grep -n 'mandates-filing' AGENTS.rules.md | grep -c 'wg-when-deferring-a-capability-create-a'` → `0`.
9. `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"` → exit 0 (ack row present and hash-matched).
10. `bash .claude/hooks/ship-net-issue-flow-gate.test.sh` and `bash plugins/soleur/test/net-issue-flow.test.sh` → green. Any hard-coded two-tagged-rules set updated **deliberately**, called out in the PR body.
11. `bash scripts/lint-orphan-test-suites.sh` → green with the allowlist entry **removed**.
12. `bash scripts/test-all.sh` → green, and the two new `run_suite` registrations appear in its output.
13. `git diff --stat AGENTS.rules.md` → exactly **one** body line changed (the untag), unless AC14 applies.
14. If the `brainstorm Phase 2 budget checkpoint` tag text changed, a second ack row exists for `cq-skill-description-budget-headroom` and AC13's count is 2.
15. Every `knowledge-base/` path cited in this plan resolves: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN: {}'` → no output.
16. `ADR-158-*.md` exists on disk and its ordinal is still free against `origin/main` at ship time.
17. PR body carries `Closes #7174`, `Closes #7172`, `Closes #6751`, `Closes #4622`.

### Post-merge (operator)

None. Every step above is automatable in-session; there is no vendor console,
no credential mint, and no infrastructure apply in this change.

## Domain Review

**Domains relevant:** engineering.

### Engineering

**Status:** reviewed
**Assessment:** Repo-local developer tooling. The one architectural call (corpus
authoritative over parser) is recorded as ADR-158. Risk is concentrated in
grammar permissiveness, mitigated by AC6's preserved negative case and AC3's
exact-count assertion. No runtime, user, or data surface.

### Product/UX Gate

Not applicable — Product domain not relevant. No path in `## Files to Edit`
matches a UI-surface term or glob (no `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx`); the mechanical UI-surface override does not fire.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open` returned no issue body
containing any path in this plan's edit set.

## Files to Edit

- `scripts/lint-agents-enforcement-tags.py` — grammar extensions, body-line skip, vacuity floor, default flip
- `scripts/lint-agents-enforcement-tags.test.sh` — RED cases first, then floor + grammar cases
- `scripts/test-all.sh` — two `run_suite` registrations
- `scripts/lint-orphan-test-suites.sh` — remove the allowlist entry
- `AGENTS.rules.md` — **one** body line (the untag)
- `.claude/rule-body-hashes.txt` — regenerated via `--write`
- `.claude/rule-weakening-acks.txt` — one appended ack row
- `knowledge-base/project/specs/feat-one-shot-net-issue-flow-mandated-filing-exemption/decision-challenges.md` — DC-1 disposition
- `knowledge-base/project/specs/feat-one-shot-net-issue-flow-mandated-filing-exemption/discovered-defects.md` — DD-1 disposition **and diagnosis correction**
- Possibly: `net-issue-flow.sh`, `ship-net-issue-flow-gate.sh`, ADR-155 — only where prose over-states the tagged set

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-158-enforcement-tag-grammar-conforms-to-the-corpus.md`
- `knowledge-base/project/learnings/2026-08-03-an-issues-diagnosis-is-a-hypothesis-measure-the-failure-set-first.md`
- `knowledge-base/project/specs/feat-one-shot-7174-7172-mandates-filing-and-enforcement-tag-lint/tasks.md`

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Grammar becomes a silent always-pass** — the exact class this work closes. Widening a matcher is the natural way to reintroduce it. | AC6 keeps a negative case; AC3 asserts **exact** tag counts, not `> 0`; the floor asserts non-vacuity. Each grammar variant gets its own positive **and** negative test. |
| `/`-anchor rejection is a path-traversal defense (`:118`). Loosening it could allow `../` escapes into `rglob`. | Narrow the loosening to the **skill-list** token only. Keep `..` rejected unconditionally, and keep the anchor's own `/` rejection. Add a test asserting a `../` anchor is still refused. |
| The default flip makes `... .py AGENTS.md` fail for anyone invoking it narrowly. | Deliberate — that is the vacuity signal. Documented in the docstring and the ADR. lefthook and test-all both pass explicit paths. |
| Un-allowlisting the orphan suite turns `test-all.sh` red if any case still fails. | AC4 requires `Fail: 0` **before** Phase 4 removes the entry. Phase order enforces it. |
| ADR-158 ordinal collides with a sibling PR merging first. | `/ship` re-verifies against `origin/main`; on renumber, sweep this plan + `tasks.md` + AC16 in the same edit. |
| The untag prose sweep misses a site claiming "two rules". | AC7/AC8 pin the corpus; the Phase 3.3 sweep is explicit; review re-greps `mandates-filing` repo-wide. |

## Non-Goals

- **Reverting the corpus-marker mechanism to a `reason=` token** — operator-decided A2, no change.
- **Re-litigating either #7174 decision.**
- **Normalising the corpus tags to the parser's old grammar** — explicitly rejected in ADR-158's alternatives.
- **Adding a dedicated `.github/workflows/` job** — `scripts/test-all.sh` is the established home for corpus linters (`:277-284`); a new job would duplicate coverage.

## Test Scenarios

1. **Real-tree pass** — linter against the live corpus exits 0 with exact counts (AC1–AC3).
2. **Legend immunity** — a blockquote containing `[hook-enforced: …]` is not treated as a tag.
3. **Grammar positives** — one fixture per variant: `/`-joined skills, `+`-joined segments, file-form enforcer with symbol, `§X.Y`.
4. **Grammar negatives** — for each variant: a nonexistent skill in a `/` list, an unresolvable `+` segment, a missing file-form target, a missing symbol → all exit 1.
5. **Path-traversal** — `../` in an anchor still refused.
6. **Vacuity floor** — tag-free fixture exits 1.
7. **Ack gate** — `lint-rule-bodies.py --check` passes with the new ack, and **fails** if the ack row is removed (proves the ack is load-bearing, not decorative).

## Sharp Edges

- **An issue's diagnosis is a hypothesis, not a finding.** #7172 was authored by a competent agent from a real measurement and was still wrong about 9 of 12 failures and about the root cause. Re-measure the failure set before adopting a prescribed remedy — especially when the remedy is "edit N human-gated files."
- **A gate that names its own tag syntax in prose will lint its own documentation.** Any linter whose regex matches a legend must skip non-body lines, or the docs become a permanent false positive. Introduced here by the very PR that discovered the vacuity.
- **`argparse` `default=` on `nargs="*"` hides wiring, it does not create it.** The default was vacuous *and* the real invocation was correct — reading only the default would have produced the wrong fix. Always grep the invocation sites (`lefthook.yml`, `test-all.sh`, `.github/`) before diagnosing a gate as unwired.
- **A plan whose `## User-Brand Impact` is empty or `TBD` fails `deepen-plan` Phase 4.6.** Filled above.
