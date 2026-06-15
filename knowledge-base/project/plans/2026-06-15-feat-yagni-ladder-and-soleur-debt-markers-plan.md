---
title: "feat: YAGNI minimalism-ladder principle + SOLEUR-DEBT inline-marker harvest skill"
type: feat
date: 2026-06-15
lane: cross-domain
semver: minor
requires_cpo_signoff: false
---

# feat: YAGNI minimalism-ladder principle + SOLEUR-DEBT inline-marker harvest skill

Two-part engineering-quality change in ONE worktree/PR. PR A of a two-PR effort; the
promptfoo eval harness is a SEPARATE later PR and is explicitly NOT in scope here. Both
items adapt patterns from the ponytail Claude Code plugin (github.com/DietrichGebert/ponytail, MIT).

- **ITEM ONE** — add a concise YAGNI "minimalism ladder" generation-bias principle to the
  constitution Code Style section, with the mandatory trust-boundary carve-out, plus a tight
  one-line pointer in the AGENTS sidecar. Cross-reference the existing `code-simplicity-reviewer`
  agent (post-hoc) — this principle biases generation *up front*.
- **ITEM TWO** — establish an inline `SOLEUR-DEBT:` deferral-marker comment convention (ceiling +
  upgrade trigger), and a new `harvest-debt` skill that greps the repo for these markers, harvests
  them into a ledger grouped by file, and flags any marker with NO upgrade trigger as `no-trigger`.
  It COMPLEMENTS (does not duplicate) the existing `technical-debt/` ledger and `resolve-debt` skill:
  harvest surfaces inline markers; resolve-debt closes them. Wire the two together, document the
  convention where the other debt conventions live, and connect it to the `wg-when-deferring-a-capability`
  deferral gate.

## Enhancement Summary

**Deepened on:** 2026-06-15
**Passes run:** code-simplicity review + repo-claim verification (Explore), plus all deepen-plan hard
gates (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shape, 4.9 UI-wireframe) — all PASS.

### Key corrections folded in
1. **Dropped `plugin.json` edit** — verified plugin.json description has NO skill count and
   `sync-readme-counts.sh` never touches it; the "89→90" step was wrong.
2. **Cut the `--json` flag** from `harvest-debt.sh` (YAGNI — no concrete consumer; the cited
   resolve-debt "deferred --json" precedent was factually wrong, but resolve-debt's own Non-Goal
   "defer --json until a downstream skill needs it" is the real lesson, so defer).
3. **Cut the `code-simplicity-reviewer.md` body cross-reference edit + its AC** — the
   constitution body and the cq-rule already name the agent; a third pointer is redundant.
4. **Respecified `harvest-debt.sh` as a single grep+awk pipeline** (not a phased multi-mode CLI) —
   it is read-only text munging, not the ledger-mutating complexity that justifies `resolve-debt.py`.
5. **Tightened the cq-rule one-liner** to stay ≤600 bytes (exact `PER_RULE_CAP`), not re-enumerating
   the five carve-out concerns (the constitution body carries them).

### Confirmed (no change needed)
- Budget at 2197/2197 zero headroom → bump `SKILL_DESCRIPTION_WORD_BUDGET` by exact new-description word count.
- README skill counts ARE hardcoded and `sync-readme-counts.sh` edits them (step kept).
- `docs/_data/skills.js` `SKILL_CATEGORIES` needs the manual entry (step kept).
- Linters: `lint-rule-ids.py` requires cq-prefix in a `## Code Quality` section; `lint-agents-rule-budget.py` caps at 600 bytes.

## Premise Validation

Checked before research; no external GitHub-issue/PR premises (these are internal "Item N" labels, not issue refs).

- **Constitution path drift (corrected).** The task brief named `knowledge-base/overview/constitution.md`.
  That path does NOT exist. The canonical constitution is `knowledge-base/project/constitution.md`
  (verified via `find`). All ITEM ONE edits target the real path. The Code Style section is at the
  top of that file (`## Code Style` → `### Always`).
- **Skill description budget is at the cap.** Verified: cumulative skill `description:` word count is
  **2197 / 2197 — ZERO headroom** (`SKILL_DESCRIPTION_WORD_BUDGET = 2197` in
  `plugins/soleur/test/components.test.ts`). The established pattern (read from the constant's bump
  history comment) is: every new skill bumps the constant by EXACTLY the new description's word count
  against a zero-headroom baseline. The new `harvest-debt` description WILL require a budget bump.
  This is load-bearing, not optional. See Sharp Edges + AC.
- **Ledger + resolve-debt verified as complementary, not duplicative.** `resolve-debt` walks the
  `knowledge-base/project/learnings/technical-debt/` ledger DIR (`status: open` entries) and closes
  one interactively with a linked GitHub issue; it never greps source. The new skill greps SOURCE
  for inline markers — a distinct surface. No overlap; the wiring is harvest→(promote)→resolve-debt.
- **`SOLEUR-DEBT:` marker is a clean slate.** `grep -rn "SOLEUR-DEBT"` returns zero hits repo-wide.
  No collision with the `soleur:` skill-reference prefix (e.g. `soleur:go`) because the marker is
  ALL-CAPS-hyphenated `SOLEUR-DEBT:`, not bare `soleur:`.
- **AGENTS tier gate constrains ITEM ONE placement.** `cq-agents-md-tier-gate` (AGENTS.docs.md) is
  explicit: AGENTS.md is for cross-cutting session invariants with no single-file trigger; everything
  else keeps an `[id]` + tag + one-line pointer with the full body in the enforcing artifact. A
  generation-bias style principle is a **Code Quality (`cq-*`)** rule, not a blast-radius `hr-*`.
  See ITEM ONE design decision.
- **Self-capability claims verified (`hr-verify-repo-capability-claim-before-assert`).** `resolve-debt`
  modes, ledger frontmatter contract, the two linters (`scripts/lint-rule-ids.py`,
  `scripts/lint-agents-rule-budget.py`), and `code-simplicity-reviewer` description all read directly
  from source — no claims from memory.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|-------------|---------|---------------|
| Edit `knowledge-base/overview/constitution.md` | File does not exist; canonical path is `knowledge-base/project/constitution.md` | Target the real path |
| "Hard Rule pointer in AGENTS.md core if that matches the established pattern" | Established pattern: `hr-*` = blast-radius invariants (one-liner, hook/skill-enforced); generation-bias style → `cq-*` Code Quality rule per `cq-agents-md-tier-gate`. Code Quality rules live in `AGENTS.docs.md` (docs-only class), pointer in `AGENTS.md` | Add a one-line `cq-*` rule in `AGENTS.docs.md` + index pointer in `AGENTS.md`; document the `hr-*`-vs-`cq-*` decision (the brief's conditional "if that matches" is satisfied by choosing the tier that matches) |
| Update `plugin.json`/README counts "per release-docs if a component is added" | `release-docs` runs `scripts/sync-readme-counts.sh` (auto-updates both READMEs); plugin.json description carries counts and is updated manually; `plugin.json` version field is a frozen sentinel — do NOT touch | One component (skill) added → run `sync-readme-counts.sh`, update plugin.json description counts, register in `docs/_data/skills.js` |
| Skill description ≤ ~30 words, budget headroom available | Budget is 2197/2197 = 0 headroom | Bump `SKILL_DESCRIPTION_WORD_BUDGET` by the new description's exact word count; keep description ≤ ~15 words to minimise the bump |

---

## ITEM ONE — YAGNI Minimalism Ladder Principle

### Design decision: constitution body + `cq-*` pointer (NOT `hr-*`)

The ladder is a multi-rung principle with a carve-out — it does not fit the one-line `hr-*` shape.
Per `cq-agents-md-tier-gate`, the full body lives in the **enforcing/owning artifact** (the
constitution Code Style section, where comparable multi-line principles already live, e.g. the
progressive-rendering and git-askpass rules), and AGENTS carries a tight one-line pointer. Because
the principle is a *code-quality generation bias* (not a blast-radius session invariant), the pointer
is a **`cq-*`** rule placed in `AGENTS.docs.md` under `## Code Quality`, with an index entry in
`AGENTS.md`. This satisfies the brief's "if that matches the established pattern" condition by
selecting the tier that DOES match. (An `hr-*` placement would fail the tier gate: there is no
single-file trigger, no silent-failure/blast-radius axis, and it is advisory generation guidance,
not a hard invariant.)

### Files to Edit

1. **`knowledge-base/project/constitution.md`** — add the ladder principle to `## Code Style` →
   `### Always` (append as a new bullet near the existing simplicity/dependency bullets — place this
   one in Code Style since it governs code shape). Draft body (tight, itself a YAGNI artifact — no essay):

   > **Minimalism ladder (stop at the first rung that holds):** (1) Does it need to exist at all? (YAGNI — delete the requirement.) (2) Does the stdlib do it? (3) Does a native platform feature cover it? (4) Does an already-installed dependency solve it? (5) Can it be one line? (6) Only then, write the minimum code that works. **Carve-out — never simplify away:** input validation at trust boundaries, error handling that prevents data loss, security measures, accessibility basics, or anything the user explicitly requested. This biases generation up front; the `code-simplicity-reviewer` agent is the post-hoc check.

2. **`AGENTS.docs.md`** — add ONE `cq-*` rule under `## Code Quality` (matching the existing
   one-line format with `[id: cq-...]`). The body MUST be ≤ 600 bytes (exact cap enforced by
   `scripts/lint-agents-rule-budget.py:51 PER_RULE_CAP = 600`). Do NOT re-enumerate all five carve-out
   concerns here — the constitution body carries the enumeration; the pointer just names the boundary.
   Draft:

   > - Generate to the minimalism ladder: stop at the first rung that holds — (1) need it at all (YAGNI) (2) stdlib (3) native platform feature (4) installed dependency (5) one line (6) minimum code [id: cq-minimalism-ladder-generation-bias]. Carve-out at trust boundaries (validation, data-loss error handling, security, a11y, explicit requests). Full body: `knowledge-base/project/constitution.md` Code Style; post-hoc check: `code-simplicity-reviewer`.

3. **`AGENTS.md`** — add the index pointer line under `## Code Quality`:
   `- [id: cq-minimalism-ladder-generation-bias] → docs-only`

   (CUT — deepen-plan review finding: a body cross-reference edit to
   `code-simplicity-reviewer.md` is redundant. The constitution body already names the
   `code-simplicity-reviewer` agent as the post-hoc check, and the cq-rule pointer repeats it. A third
   back-pointer in the agent body earns nothing — the cross-reference graph is complete in two places.
   The agent's `description:` frontmatter stays untouched regardless, preserving the agent token budget.)

### ITEM ONE acceptance

- `grep -n "Minimalism ladder" knowledge-base/project/constitution.md` returns 1 hit in `## Code Style`.
- The carve-out clause in the CONSTITUTION body names all five protected concerns verbatim (input
  validation at trust boundaries, data-loss error handling, security, accessibility basics, explicit requests).
- `grep -n "cq-minimalism-ladder-generation-bias" AGENTS.docs.md AGENTS.md` returns exactly 2 hits
  (one rule body in docs under `## Code Quality`, one index pointer in `AGENTS.md` under `## Code Quality`).
- `python3 scripts/lint-rule-ids.py` and `python3 scripts/lint-agents-rule-budget.py` both pass
  (new rule has matching section prefix `cq-` under a `## Code Quality` section; body ≤ 600 bytes —
  verify the drafted line's UTF-8 byte length before committing).

---

## ITEM TWO — SOLEUR-DEBT Inline-Marker Convention + harvest-debt Skill

### The marker convention

Format (inline code comment, language-appropriate comment leader):

```text
// SOLEUR-DEBT: <ceiling/shortcut>; <upgrade trigger>
```

- Distinctive ALL-CAPS marker `SOLEUR-DEBT:` — deliberately NOT bare `soleur:` (which collides with
  skill references like `soleur:go` throughout the docs).
- After the marker: the **ceiling** (what shortcut was taken / what the current design tops out at),
  then a `;` separator, then the **upgrade trigger** (the observable signal that says "do the real
  thing now").
- Example: `// SOLEUR-DEBT: global lock; switch to per-account locks if throughput matters`.
- A marker with NO `;`-delimited trigger (or an empty trigger) is the rot-prone case → the harvest
  skill flags it `no-trigger`.

### How it complements (not duplicates) the existing debt system

| Surface | Owner | Role |
|---------|-------|------|
| Inline `SOLEUR-DEBT:` markers in source | **harvest-debt (new)** | SURFACE deliberate shortcuts where they live, in code |
| `knowledge-base/project/learnings/technical-debt/` ledger (`.md` entries) | `compound` (write) + `resolve-debt` (close) | TRACK + CLOSE consolidated debt with `status` + `linked_issue` |

harvest-debt does NOT write ledger entries automatically and does NOT close anything — that would
duplicate compound/resolve-debt. It produces a read-only grouped report; promotion of a worth-tracking
marker into the ledger remains the operator's deliberate act (then `resolve-debt` closes it). The
wiring is a pointer in both directions (harvest report → "promote with compound, close with
resolve-debt"; resolve-debt/README "see harvest-debt for inline markers").

### Connection to the deferral gate (`wg-when-deferring-a-capability`)

The deferral gate already says: default to **documenting a deferral in-place** (plan, ADR, or **code
comment**), and file a GitHub issue only when the triple test passes. `SOLEUR-DEBT:` IS the canonical
shape of that "code comment" in-place documentation — it makes the in-place deferral
**grep-discoverable** and trigger-bearing. harvest-debt is the read surface that makes those in-place
deferrals visible without converting every one into phantom backlog. Document this linkage in the
convention doc and reference the gate by id.

### Files to Create

1. **`plugins/soleur/skills/harvest-debt/SKILL.md`** — frontmatter + body.
   - Frontmatter (third-person, `This skill should be used when...`, ≤ ~15 words to minimise budget bump):
     `name: harvest-debt`
     `description: "This skill should be used when harvesting inline SOLEUR-DEBT: markers from the codebase into a ledger grouped by file, flagging markers with no upgrade trigger."`
     (Count this exact string's words at /work time; bump the budget constant by that count — see AC.)
   - Body: numbered phases — (Phase 1) run the harvest script, (Phase 2) present the grouped report,
     (Phase 3) point the operator at `compound` (to promote a marker into the ledger) and
     `resolve-debt` (to close it). Reference the convention doc + `wg-when-deferring-a-capability`.
     Note the path-denylist self-exclusion limitation. All `scripts/` refs as markdown links
     (compliance checklist). Imperative voice, no second person.

2. **`plugins/soleur/skills/harvest-debt/scripts/harvest-debt.sh`** — a SINGLE grep+awk pipeline
   (NOT a phased multi-mode CLI — this is read-only text munging, not the ledger-mutating complexity
   that justifies `resolve-debt.py`'s heft).
   - `#!/usr/bin/env bash`, `set -euo pipefail`, snake_case functions, SCREAMING_SNAKE constants,
     `[[ ]]` tests, stderr for diagnostics, stdout for the operator-facing report (per the constitution
     "operator-protection signal → stdout" rule).
   - Behavior: `git grep -n` (tracked files only — fast, no `.gitignore` noise) for `SOLEUR-DEBT:`,
     excluding `node_modules`, `.git`, build output (`_site`, `dist`, `*.min.*`), AND the skill's own
     dir + the convention doc (`technical-debt/README.md`) via git-grep pathspec exclusions, so the
     marker *definition* is never self-reported as debt. One `awk` pass: group by file, and for each
     hit split the text after `SOLEUR-DEBT:` on the FIRST `;` → left = ceiling, right = trigger; empty/
     absent right side → `no-trigger` flag. Emit a markdown report grouped by file with a trailing
     `no-trigger` count summary line.
   - `--help` prints usage (exit 0); empty state prints `No SOLEUR-DEBT markers found.` (exit 0). No
     other flags.
   - **NO `--json` flag** (deepen-plan YAGNI finding): no concrete downstream consumer exists today
     (`/loop` is hypothetical). The cited "resolve-debt deferred its --json" precedent was wrong —
     resolve-debt actually SHIPS `--json` — but the *real* lesson there is "add `--json` only when a
     consumer exists" (its own Non-Goals: "JSON output … defer until at least one downstream skill
     needs it"). Mirror that: defer `--json` until a real caller appears.
   - Idempotent, read-only — never writes files, never commits.
   - **Self-exclusion is a path denylist, not a semantic check** (acknowledged proxy): the true
     invariant is "marker is in an actual code comment," but the script excludes by path. A future doc
     that quotes `SOLEUR-DEBT:` outside the excluded paths will self-report; document this lossiness in
     the SKILL.md so it is a known limitation, not a surprise.

### Files to Edit (ITEM TWO)

3. **`knowledge-base/project/learnings/technical-debt/README.md`** — add a `## Inline Markers
   (SOLEUR-DEBT)` section documenting the marker format, the grep scope, the `no-trigger` flag, the
   harvest→promote→close flow, and the link to `wg-when-deferring-a-capability`. This is where the
   other debt-tracking conventions already live (frontmatter contract, two-schema, archive). Add
   harvest-debt to the `## Related` list.

4. **`plugins/soleur/skills/resolve-debt/SKILL.md`** — add a one-line cross-reference in the intro
   (and/or `## Related`-style note) pointing to `harvest-debt` as the inline-marker surface that
   complements the ledger: "harvest surfaces inline `SOLEUR-DEBT:` markers; this skill closes ledger
   entries." Keep `description:` frontmatter UNCHANGED (no skill-budget impact from this edit).

5. **`plugins/soleur/.claude-plugin/plugin.json`** — NO EDIT (deepen-plan correction). Verified: the
   plugin.json `description` is a generic sentence containing NO numeric skill count, and
   `sync-readme-counts.sh` never touches plugin.json. Do NOT edit plugin.json for this feature
   (the `version` field is also a frozen `0.0.0-dev` sentinel — untouched either way).

6. **`plugins/soleur/docs/_data/skills.js`** — register `harvest-debt` in `SKILL_CATEGORIES`
   (skill discovery does not recurse; unregistered skills are silently omitted from the docs site —
   per constitution Architecture rule).

7. **`README.md` + `plugins/soleur/README.md`** — counts updated mechanically by
   `bash plugins/soleur/skills/release-docs/scripts/sync-readme-counts.sh` (skills 89 → 90). Do not
   hand-edit counts.

8. **`plugins/soleur/test/components.test.ts`** — bump `SKILL_DESCRIPTION_WORD_BUDGET` from 2197 by
   EXACTLY the new `harvest-debt` description word count (zero-headroom baseline), with a trailing
   comment matching the existing bump-history format (`bumped +N for <this PR/feat> (harvest-debt
   skill description, N words, against a 2197/2197 zero-headroom baseline)`).

### Test Scenarios (Given/When/Then)

- **Given** a source file containing `// SOLEUR-DEBT: global lock; per-account locks if throughput matters`
  **When** `harvest-debt.sh` runs **Then** the report groups it under that file with ceiling
  `global lock` and trigger `per-account locks if throughput matters`, NOT flagged `no-trigger`.
- **Given** a marker `// SOLEUR-DEBT: hardcoded list` (no `;` trigger) **When** the script runs
  **Then** it is flagged `no-trigger` and counted in the summary.
- **Given** a `SOLEUR-DEBT:` string inside `node_modules/`, `.git/`, build output, or the convention
  doc itself **When** the script runs **Then** it is excluded from the report.
- **Given** no markers anywhere **When** the script runs **Then** `No SOLEUR-DEBT markers found.` exit 0.
- A skill test file (`plugins/soleur/test/...` per the `<module>.test.ts` convention, in `test/`)
  exercises the four cases above against synthesized fixtures (constitution: "test files live in a
  `test/` sibling directory", `cq-test-fixtures-synthesized-only`). RED before GREEN.

---

## Plugin Compliance Checklist (run before PR ready)

- [ ] `harvest-debt/SKILL.md` frontmatter: `name: harvest-debt` (matches dir), `description:` third
      person starting `This skill should be used when`.
- [ ] `bun test plugins/soleur/test/components.test.ts` PASSES (budget bumped; new skill has
      name+description+non-empty body; description < 1024 chars; starts with "This skill").
- [ ] All `scripts/` refs in SKILL.md are markdown links, not bare backticks.
- [ ] Imperative voice; no second person.
- [ ] Skill registered in `plugins/soleur/docs/_data/skills.js` `SKILL_CATEGORIES` (else the docs
      site classifies it "Uncategorized"); update the `Last verified` count comment.
- [ ] `bash plugins/soleur/skills/release-docs/scripts/sync-readme-counts.sh` run; both README
      hardcoded skill counts reflect 90 (root `README.md` line ~14 + `plugins/soleur/README.md` table).
- [ ] `plugin.json` NOT edited (no count in description; version field is a frozen sentinel).
- [ ] PR has `semver:minor` label (new skill) + `## Changelog` section.
- [ ] `npx @11ty/eleventy` build verifies (run `npm install` first in worktree) — skills catalog
      shows harvest-debt.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 (ITEM ONE): constitution Code Style contains the minimalism ladder (6 rungs) + 5-concern carve-out.
- [~] AC2 (ITEM ONE): **DESCOPED at /work** — `cq-minimalism-ladder-generation-bias` was NOT added.
      The always-loaded AGENTS payload was at 22994/23000 bytes (6 bytes slack); a new index pointer
      (`lint_union` couples pointer↔body 1:1, so the docs body needs the always-loaded pointer) would
      have tipped B_ALWAYS over the 23000 critical cap, forcing an unrelated core-rule demotion — out
      of scope, and the brief made the pointer conditional ("if that matches the established pattern").
      ITEM ONE ships as the constitution body only (AC1); the body no longer references the rule id.
- [ ] AC3 (ITEM TWO): `harvest-debt.sh` correctly groups by file and flags `no-trigger` markers
      (all four Test Scenarios green); script is read-only and idempotent; the convention-doc/skill-dir
      self-exclusion holds.
- [ ] AC4 (ITEM TWO): marker convention documented in `technical-debt/README.md` with the
      harvest→compound→resolve-debt flow and a reference to `wg-when-deferring-a-capability`.
- [ ] AC5 (ITEM TWO): `resolve-debt/SKILL.md` cross-references harvest-debt (complement, not duplicate).
- [ ] AC6 (plugin): `SKILL_DESCRIPTION_WORD_BUDGET` bumped by EXACTLY the new description word count;
      `bun test plugins/soleur/test/components.test.ts` passes; both READMEs synced; skill registered in
      `docs/_data/skills.js`; plugin.json NOT edited.
- [ ] AC7: standard QA (`soleur:qa`) + review (`soleur:review`) run before PR marked ready.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a no-op or false report from `harvest-debt` (e.g.
missed markers or a crash on malformed comments) — an internal dev-tooling annoyance, not a
user-facing product failure. The constitution/AGENTS edits are documentation; a wrong rule biases
agent generation but is advisory and caught by review.

**If this leaks, the user's data is exposed via:** N/A — no user data, no PII, no auth, no schema, no
network surface is touched. The skill greps tracked source and emits a local report.

**Brand-survival threshold:** none — internal engineering-quality tooling and documentation only.
threshold: none, reason: pure dev-tooling + docs change; no user-data, auth, schema, or prod surface touched.

## Domain Review

**Domains relevant:** engineering (CTO — architectural/tooling). Product/UX: NONE — no user-facing
page/component/flow; no file under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`. The new
skill and docs are operator/agent-facing infrastructure (per `hr-new-skills-agents-or-user-facing`
the CMO carve-out applies: operator-facing dev tooling, CMO omittable with rationale; CPO advisory
only — threshold is `none`).

No cross-domain product/legal/finance implications detected — engineering-quality tooling + docs.

## Observability

Skip — pure-docs + a read-only local dev-tooling skill (no code under `apps/*/server`, `apps/*/src`,
`apps/*/infra`; no new infrastructure surface). The harvest script's own success signal is its
stdout report + exit code; no liveness/alerting surface is introduced.

## Infrastructure (IaC)

Skip — no new infrastructure (no server, service, cron, secret, vendor, DNS, or persistent runtime
process). Pure code/docs change against the existing repo.

## Non-Goals (deferred, documented in-place per `wg-when-deferring-a-capability`)

- **promptfoo eval harness** — explicitly a SEPARATE later PR (PR B). Not built here.
- **Auto-promotion of markers into the ledger** — harvest is read-only by design; promotion stays a
  deliberate `compound` act so the ledger doesn't fill with un-triaged noise (mirrors resolve-debt's
  "no auto-commit" stance).
- **Scheduled marker scanner / time-series dashboard** — same class as the ledger's deferred #3650
  scanner; defer until close-loop activity justifies it. (Triple-test fails: no concrete trigger yet.)
- **CI gate that fails on `no-trigger` markers** — defer; would need grandfathering of any existing
  markers and is enforcement, not the harvest read-surface this PR delivers.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` not consulted at plan-write (no network
dependency assumed); the files touched (constitution, AGENTS sidecars, a new skill dir, technical-debt
README, resolve-debt SKILL, plugin.json, docs data, components.test) are documentation/tooling with
low overlap probability. /work Phase 0 should run the overlap query against the final file list.

## Sharp Edges

- **Budget is at the cap (2197/2197).** The single most likely failure: forgetting to bump
  `SKILL_DESCRIPTION_WORD_BUDGET` by the new description's exact word count → `components.test.ts`
  fails immediately. Keep the description ≤ ~15 words to minimise the bump; count the EXACT final
  string at /work time (not an estimate) and match the bump comment format.
- **`plugin.json` has no skill count and must not be edited** (deepen-plan correction) — its
  `description` is a generic sentence; `sync-readme-counts.sh` only edits the two READMEs' hardcoded
  counts. The `version` field is a frozen `0.0.0-dev` sentinel regardless.
- **Skill discovery does not recurse** — register `harvest-debt` in
  `plugins/soleur/docs/_data/skills.js` `SKILL_CATEGORIES` or the docs site classifies it
  "Uncategorized" / omits it.
- **Marker scope must exclude the convention doc + the skill's own files** — otherwise the harvest
  report self-reports the format definition as a debt marker. Exclude `_site`/`dist`/`*.min.*`/
  `node_modules`/`.git` AND the skill dir + technical-debt README.
- **Do NOT make harvest-debt write or close anything** — that duplicates compound/resolve-debt and
  re-creates the exact overlap the brief forbids. Read-only report + cross-pointers only.
- **AGENTS rule placement is tier-gated** — the YAGNI pointer is a `cq-*` rule in `AGENTS.docs.md`
  (docs-only class), NOT an `hr-*` in core; `lint-rule-ids.py` rejects a section/prefix mismatch.

## Component (new skill)

- **harvest-debt** — read-only grep harvester for inline `SOLEUR-DEBT:` deferral markers; groups by
  file, flags `no-trigger` markers; complements the technical-debt ledger (compound writes,
  resolve-debt closes). Entry point: Skill tool `soleur:harvest-debt`.
