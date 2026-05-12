---
title: feat — tech-debt ledger lifecycle + /soleur:resolve-debt skill
date: 2026-05-12
issue: 2723
brainstorm: knowledge-base/project/brainstorms/2026-05-12-tech-debt-tracker-brainstorm.md
spec: knowledge-base/project/specs/feat-tech-debt-tracker/spec.md
branch: feat-tech-debt-tracker
pr: 3645
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: documentation-only
deferred_sibling: 3650
status: post-review
---

# Plan: Tech-Debt Ledger Lifecycle (Spec A of #2723)

> Plan body rewritten 2026-05-12 after 5-agent review (DHH + Kieran + code-simplicity + architecture-strategist + spec-flow-analyzer). Convergent cuts applied; schema.yaml is CORA-vendored and is NOT edited.

## Overview

Ship the lifecycle prerequisite for `tech-debt-tracker` (#2723). The deferred scanner (#3650) is **out of scope**.

Three deliverables in one PR:

1. **Frontmatter migration.** Inline ~25-line Python+PyYAML snippet (Phase 1) adds `status: open` to the 9 live entries under `knowledge-base/project/learnings/technical-debt/`. Modeled on `scripts/backfill-frontmatter.py:115-309` (parse/serialize helpers, MD5 body-verify). Not a committed script — one-shot migration; the live diff IS the artifact.
2. **`/soleur:resolve-debt` skill** at `plugins/soleur/skills/resolve-debt/SKILL.md` (description ≤30 words). One script: `plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py`. Modes: `--list`, interactive (default), `--no-verify`, `--help`.
3. **`/soleur:compound` integration — template-only.** Patch `plugins/soleur/skills/compound-capture/assets/resolution-template.md` to include `status: open` (with inline comment). Do **NOT** touch `schema.yaml` (CORA-vendored upstream) or `references/yaml-schema.md` (CORA-derived); future compound entries inherit `status: open` from the template when written verbatim.

## Research Reconciliation — Spec vs Codebase

Three load-bearing reconciliations remain (rows that expand FR scope). Two cosmetic ones (ledger count, script precedent) are folded into the spec inline; not repeated here.

| Spec claim | Reality | Plan response |
|---|---|---|
| Compound-capture integration is "one-line edit to the technical-debt write path" (spec FR9). | `compound-capture/schema.yaml` is CORA-vendored (header: `# CORA Documentation Schema`); editing breaks upstream-sync contract. Compound's `<validation_gate blocking="true">` (SKILL.md ~line 185) loads schema.yaml — adding `required` field would block all 13 problem_types. | FR9 scope narrowed: edit `assets/resolution-template.md` only (1 line + comment). Skip schema.yaml + references/yaml-schema.md. |
| Component-count update covers "README.md plugin component counts" (spec TR4). | 5 distinct count surfaces drift per `2026-02-22-skill-count-propagation-locations.md`: `plugins/soleur/README.md:45`, root `README.md`, `knowledge-base/overview/brand-guide.md` (×2), `plugins/soleur/docs/_data/skills.js:11` (stale). `plugin.json` no-op. | TR4 expanded: grep repo-wide for current count, update all 5 surfaces, re-grep to confirm zero hits for old number. |
| `/soleur:compound` integration is "one literal-string addition" (spec TR8). | Template-only after K1: ≤2 lines in `assets/resolution-template.md` (one for `status: open`, one comment line). | TR8 amended to "single template edit + 1 comment line; cumulative diff <5 LOC." |

## User-Brand Impact

**Carry-forward from brainstorm.** Verbatim from `knowledge-base/project/brainstorms/2026-05-12-tech-debt-tracker-brainstorm.md` `## User-Brand Impact`.

**If this lands broken, the user (founder/operator) experiences:** corrupted ledger entries with malformed YAML frontmatter, breaking `learnings-researcher`, `kb-search`, and any downstream skill that parses these files. Recovery is `git revert` on the migration commit.

**If this leaks, the user's [repo internals] is exposed via:** `linked_issue: <int>` echoes into the committed entry's frontmatter (public-on-merge `soleur` repo). The leak vector is bounded by integer-only sanitization at the input boundary (Python `int(input)` + range-check rejects strings, floats, shell metachars by construction; PyYAML serializes ints as ints).

**Brand-survival threshold:** `single-user incident`. A single corrupted entry committed to main triggers user-brand risk because the ledger is operator-facing institutional knowledge — silent corruption of frontmatter is harder to detect than an explicit error.

**`requires_cpo_signoff: documentation-only`** (frontmatter line 11). CPO already signed off via the brainstorm `## Domain Assessments` section at 2026-05-12. There is no mechanical `/soleur:work` gate that reads this field today; the flag is brainstorm-time carry-forward documentation, not an automated gate. `user-impact-reviewer` runs at review-time per `plugins/soleur/skills/review/SKILL.md`.

## Files to Create

| Path | Purpose |
|---|---|
| `plugins/soleur/skills/resolve-debt/SKILL.md` | New skill definition. Description ≤30 words to fit the 41-word headroom (current: 1759/1800). `name: resolve-debt`, third-person description. |
| `plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py` | Main script (interactive + `--list` + `--no-verify` + `--help`). Lifts `parse_frontmatter`/`serialize_frontmatter`/`format_field` from `scripts/backfill-frontmatter.py:115-189` inline (no separate `_frontmatter.py` module). Tempfile + `os.replace` atomic write. |
| `knowledge-base/project/learnings/technical-debt/README.md` | Schema contract documentation: required/optional/forbidden semantics for `status`, `linked_issue`. Names `wont-fix` as the **load-bearing discriminator-of-record** (status carries `wont-fix` info that absence-of-`linked_issue` cannot). |
| `plugins/soleur/test/resolve-debt.test.sh` | Per-skill test. Covers core 8 scenarios (see Test Scenarios). |
| `plugins/soleur/test/fixtures/resolve-debt/` | Synthesized fixtures: 1 entry in each schema shape, 1 malformed-frontmatter entry, 1 fixture for compound round-trip. Per `cq-test-fixtures-synthesized-only`. |

## Files to Edit

| Path | Edit |
|---|---|
| `knowledge-base/project/learnings/technical-debt/*.md` (9 live files; archive/ excluded) | `status: open` added by Phase 1 inline Python snippet. |
| `plugins/soleur/skills/compound-capture/assets/resolution-template.md` (line 12, after `severity:`) | Insert `status: open` line + 1 inline comment `# defaults to open — close via /soleur:resolve-debt`. |
| `plugins/soleur/docs/_data/skills.js` line 11 | Bump `(4 categories, 65 skills)` → `(4 categories, 70 skills)`. |
| `plugins/soleur/docs/_data/skills.js` line 61 | Bump `// Workflow (21)` → `// Workflow (22)`. |
| `plugins/soleur/docs/_data/skills.js` between line 75 and 76 | Insert `"resolve-debt": "Workflow",` alphabetically. |
| `plugins/soleur/README.md` line 45 | Bump skill count `69` → `70`. |
| `README.md` (root) | Bump skill count (grep before commit). |
| `knowledge-base/overview/brand-guide.md` | Bump 2 count occurrences (grep before commit). |
| `knowledge-base/project/specs/feat-tech-debt-tracker/spec.md` FR1 | One-line amendment: "11 existing entries" → "9 live entries (archive excluded)". FR9 + TR8 narrowed to template-only per K1. |

## Implementation Phases

### Phase 1 — Backfill (inline snippet, no committed script)

Run the inline Python (modeled on `scripts/backfill-frontmatter.py:115-309` but scoped to `technical-debt/` non-recursive):

```python
# Phase 1 — backfill status: open on 9 live entries
import os, re, hashlib, yaml
LEDGER = "knowledge-base/project/learnings/technical-debt"
for fn in sorted(os.listdir(LEDGER)):
    if not fn.endswith(".md"): continue
    fp = os.path.join(LEDGER, fn)
    if os.path.isdir(fp): continue           # skip archive/
    content = open(fp).read()
    if not content.startswith("---\n"): continue
    lines = content.split("\n")
    end = next((i for i in range(1, 30) if lines[i].strip() == "---"), None)
    if end is None: continue
    fm = yaml.safe_load("\n".join(lines[1:end]))
    body = "\n".join(lines[end+1:])
    body_hash = hashlib.md5(body.encode()).hexdigest()
    if "status" in fm:
        print(f"SKIP {fn} (already has status: {fm['status']})"); continue
    # idempotent insert
    fm["status"] = "open"
    new_fm = ["---"] + [f"{k}: {v}" if not isinstance(v, list) else f"{k}: [{', '.join(str(x) for x in v)}]" for k,v in fm.items()] + ["---"]
    new_content = "\n".join(new_fm) + "\n" + body
    _, new_body = new_content.split("\n---\n", 1) if "\n---\n" in new_content else ("", body)
    assert hashlib.md5(body.encode()).hexdigest() == body_hash, f"BODY CHANGED for {fn}"
    open(fp, "w").write(new_content)
    print(f"UPDATED {fn}")
```

Important: the snippet above is illustrative; the actual Phase 1 should **import the proven helpers** from `scripts/backfill-frontmatter.py` to inherit broken-YAML fallback, quoted-value preservation, key-order, and inline-array serialization. The simplest invocation:

```bash
# Phase 1 — actual invocation (uses proven helpers via sys.path)
python3 -c "
import sys; sys.path.insert(0, 'scripts')
from backfill_frontmatter import parse_frontmatter, serialize_frontmatter
import os, hashlib
LEDGER = 'knowledge-base/project/learnings/technical-debt'
for fn in sorted(f for f in os.listdir(LEDGER) if f.endswith('.md')):
    fp = os.path.join(LEDGER, fn)
    if os.path.isdir(fp): continue
    c = open(fp).read()
    fm, body, _ = parse_frontmatter(c)
    if fm is None or 'status' in fm:
        print(f'SKIP {fn}'); continue
    bh = hashlib.md5(body.encode()).hexdigest()
    fm['status'] = 'open'
    new = serialize_frontmatter(fm) + '\n' + body
    _, nb, _ = parse_frontmatter(new)
    assert hashlib.md5(nb.encode()).hexdigest() == bh, f'BODY CHANGED {fn}'
    open(fp, 'w').write(new)
    print(f'UPDATED {fn}')
"
```

Note: `scripts/backfill-frontmatter.py` is a standalone script, not a package — the `sys.path` import works because Python imports the module by file basename. Operator verifies behavior by running `git diff knowledge-base/project/learnings/technical-debt/` after the snippet; expects 9 single-line additions, all `status: open`. **Pre-existing-`status:` recovery flow:** if the snippet prints `SKIP <file>` for an entry whose status field was hand-added, operator manually inspects via `grep '^status:' <file>` and decides whether to leave it (idempotent) or change it (manual edit + commit). Commit step: `chore: backfill status:open on tech-debt ledger entries (FR1)`.

### Phase 2 — `/soleur:resolve-debt` SKILL.md scaffold

1. Create `plugins/soleur/skills/resolve-debt/SKILL.md` with:
   - `name: resolve-debt`
   - `description:` ≤30 words, third-person, no `<example>` blocks. Draft: *"This skill should be used when triaging or closing open entries in the technical-debt ledger. Lists open debt, walks the operator through closing one with a linked GitHub issue."* (28 words.)
   - Body: `Commands` section mirroring `plugins/soleur/skills/schedule/SKILL.md` — `list` / `close` / `help`.
2. Pre-verify word budget: run `node -e "..."` (per the existing learnings file). Current 1759 + draft 28 = 1787. Pass.
3. Register at `plugins/soleur/docs/_data/skills.js:75-76` (alphabetical insertion) and bump line 11 + line 61 counts.

### Phase 3 — `resolve-debt.py` main script

1. Write `plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py`. Shebang `#!/usr/bin/env python3`. Inline-import the parse helpers from `scripts/backfill-frontmatter.py` (`sys.path.insert(0, 'scripts')` then `from backfill_frontmatter import parse_frontmatter, serialize_frontmatter`). No separate `_frontmatter.py`.
2. Implement `--list`:
   - Walk `knowledge-base/project/learnings/technical-debt/` (skip `archive/`). For each file: parse frontmatter; if parse fails, emit stderr warning naming the file and continue (do NOT crash).
   - Filter to `status == 'open'`.
   - Sort by `severity` desc (`high > medium > low > unset`), then `date` asc.
   - Print markdown table: `| idx | file | date | severity | component-or-category | title |`.
   - Empty state: `No open debt entries.` exit 0.
3. Implement interactive (default mode):
   - Display the table from `--list`. Prompt: `Select entry (1..N) or q to quit: `. Out-of-range → re-prompt up to 3 attempts then exit 2.
   - Prompt: `Status (resolved | wont-fix): `. Enum-reject → re-prompt.
   - If `resolved`: prompt: `linked_issue (integer, e.g., 2723): `. **Validation: Python `int(input)` (rejects strings/floats/shell-metachars by construction); range-check `1 <= n <= 9_999_999` (bounds shell-metachar injection; digit-count is incidental, not load-bearing — documented inline).** On `ValueError` or range-fail → re-prompt up to 3 attempts.
   - If `--no-verify` not set: `gh issue view <N> --json state,title` with 5-second timeout. **Single failure path: non-zero exit → print stderr `gh issue view failed (<reason>). Re-invoke with --no-verify to skip validation.` exit 1.** No closed-state-warn branch (operator typed it → they meant it).
   - Atomic write: serialize new frontmatter to a tempfile in the same directory; `os.replace` atomically. SIGINT before `os.replace` leaves the original untouched.
   - Print `git diff -- <file>` of the change to stdout.
   - Exit 0 with stderr message: *"Diff above. Review and commit when ready. To undo: `git checkout -- <file>`. No auto-commit by design."*
4. Implement `--help`: exit 0 with usage block enumerating the three modes.

### Phase 4 — README

1. Write `knowledge-base/project/learnings/technical-debt/README.md`:
   - One-paragraph: *"Operator-facing ledger of known tech debt in the Soleur plugin codebase."*
   - Frontmatter contract: `status` (required, enum `open|resolved|wont-fix`), `linked_issue` (required only when `status: resolved`; optional when `status: wont-fix`; forbidden when `status: open`).
   - **Load-bearing-discriminator note:** *"The `status` field is kept distinct from absence-of-`linked_issue` because `wont-fix` is the discriminator-of-record — without `status`, there is no way to express 'we know about this debt and have decided not to fix it.' Future schema simplification must preserve `status` for this reason."*
   - Both legacy and current frontmatter shapes (`module/problem_type` vs `title/category`) preserved as-is; schema unification is a separate follow-up.
   - Link to `/soleur:resolve-debt` skill and deferred Spec B issue #3650.
   - Archive subdirectory note: archive is frozen; `resolve-debt` does not scan it.
   - **Non-Goals (explicit deferrals):** `--undo-close` flag (recovery is `git checkout -- <file>` or `git revert`); schema unification; bulk-resolve; severity-filter flag; JSON output for agent consumption.

### Phase 5 — Compound-capture integration (template-only)

`plugins/soleur/skills/compound-capture/assets/resolution-template.md` line 12 (after `severity:`): insert two lines:

```yaml
status: open  # defaults to open — close via /soleur:resolve-debt
```

Verify: dry-run `/soleur:compound` against a fixture problem (synthesized test, not real session) → confirm a new entry under `learnings/technical-debt/` includes `status: open` at the right slot.

**Schema.yaml + references/yaml-schema.md are intentionally NOT touched.** Schema.yaml is CORA-vendored (`# CORA Documentation Schema`); editing breaks upstream sync. The blocking validation_gate at `compound-capture/SKILL.md:185` would reject all 13 problem_types if `status` became `required`. Template-only is sufficient for new entries written verbatim from the template.

### Phase 6 — Count propagation

1. Grep repo for current skill counts:
   ```bash
   git grep -E '\b(69|65) skills\b' -- ':(exclude).worktrees/' ':(exclude)*.lock'
   ```
   Expected hits: `plugins/soleur/README.md:45`, `plugins/soleur/docs/_data/skills.js:11`, root `README.md`, `knowledge-base/overview/brand-guide.md` (×2).
2. Update each hit to `70`. Reconcile divergence (skills.js stale at 65; bump to actual 70).
3. Re-verify with the same grep — zero hits.

### Phase 7 — Tests + final verification

1. Write `plugins/soleur/test/resolve-debt.test.sh` covering 8 core scenarios (see Test Scenarios).
2. Run `bun test plugins/soleur/test/components.test.ts` (word-budget guardrail) and `bun test plugins/soleur/test/` (full suite).
3. Run docs site build per `plugins/soleur/CLAUDE.md`; confirm `resolve-debt` appears under Workflow.
4. Smoke-test `/soleur:resolve-debt --list` against the real backfilled ledger; confirm 9-row markdown table, all `status: open`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] All 9 live entries under `knowledge-base/project/learnings/technical-debt/*.md` (non-recursive) have `status: open` (FR1). Verify: `grep -c '^status:' knowledge-base/project/learnings/technical-debt/*.md` returns 9 (see Phase 1 inline snippet).
- [ ] `plugins/soleur/skills/resolve-debt/SKILL.md` exists, has `name: resolve-debt`, third-person description ≤30 words, no `<example>` blocks (FR3). Per `plugins/soleur/AGENTS.md` skill-compliance checklist.
- [ ] `bun test plugins/soleur/test/components.test.ts` green (cumulative SKILL description words ≤1800). Current headroom: 41 words; draft is 28 words.
- [ ] `bun test plugins/soleur/test/` full suite green, including `resolve-debt.test.sh`.
- [ ] `/soleur:resolve-debt --list` produces a deterministic severity-sorted (then date-asc) markdown table of 9 rows against the live ledger (FR4, FR6 — see `resolve-debt.py:list_mode`). All 9 rows show `status: open`.
- [ ] `/soleur:resolve-debt --list` on empty-ledger fixture prints `No open debt entries.` exit 0 (see `resolve-debt.py:list_mode`).
- [ ] `/soleur:resolve-debt --help` exits 0 with usage block (FR — see `resolve-debt.py:print_help`).
- [ ] Interactive flow transitions a fixture entry `open` → `resolved` with `linked_issue: 2723`, mutates the file atomically (tempfile + `os.replace`), prints diff with `git checkout -- <file>` undo hint in stderr, exits 0 without calling `git commit` (FR5 — see `resolve-debt.py:interactive_mode`, `mutate_atomic`).
- [ ] Interactive flow rejects non-integer `linked_issue` (string, float, shell-metachar input) via `int()` parse + range-check `1 <= n <= 9_999_999`; re-prompts up to 3x then exits 2 (FR7 — see `resolve-debt.py:prompt_linked_issue`).
- [ ] `gh issue view` non-zero exit (timeout, 404, network error) → stderr message names the failure mode + `Re-invoke with --no-verify` hint + exit 1 (FR7 — see `resolve-debt.py:verify_linked_issue`).
- [ ] `--no-verify` mode skips `gh issue view`; stderr message records the bypass for operator's commit message (FR7).
- [ ] Malformed-frontmatter fixture: stderr warning naming the file; skipped by `--list`; does NOT crash (see `resolve-debt.py:safe_parse_frontmatter`).
- [ ] `/soleur:compound` integration: writing a new entry from `resolution-template.md` produces a file with `status: open` at the right slot (FR9 — see Phase 5 template edit). Verify via fixture round-trip; schema.yaml + references/yaml-schema.md remain unedited.
- [ ] `knowledge-base/project/learnings/technical-debt/README.md` exists, documents the frontmatter contract including the `wont-fix` load-bearing-discriminator note (FR10).
- [ ] `plugins/soleur/docs/_data/skills.js` registers `resolve-debt` under Workflow; line 11 + line 61 counts updated (FR8). Verify: render docs site, confirm appearance in `/skills/` page Workflow category.
- [ ] 5 count surfaces updated. Verify: `git grep -E '\b(65|69) skills\b' -- ':(exclude).worktrees/'` returns zero hits.
- [ ] No file in `plugins/soleur/.claude-plugin/plugin.json` or `plugins/soleur/marketplace.json` is edited (per `plugins/soleur/AGENTS.md` pre-commit checklist).
- [ ] PR body has `## Changelog` section + `semver:minor` label (TR4).
- [ ] PR body closes #2723 on its own body line (`Closes #2723`), not in title.

### Post-merge (operator)

None. Spec A is a pure-in-repo change; merge IS the deliverable. The 60-day re-evaluation clock for #3650 starts at merge timestamp.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | Phase 1 inline snippet against the 9 live entries (idempotent) | 9 files modified on first run; MD5 body verification passes; re-run produces zero changes (`SKIP` on all 9) |
| T2 | `--list` against backfilled ledger | 9-row markdown table, severity-sorted; all rows `status: open` |
| T3 | `--list` empty-ledger fixture | `No open debt entries.` exit 0 |
| T4 | Interactive happy path: `linked_issue: 2723` | Entry mutated atomically; diff printed with undo hint; no auto-commit; exit 0 |
| T5 | Interactive rejection: `linked_issue=foo`, `=12.5`, `=$(rm -rf /)` | All rejected at `int()` parse or range-check; re-prompt; no shell evaluation |
| T6 | `gh issue view` failure (use a non-existent issue number) | stderr message + `--no-verify` hint + exit 1; no fallback |
| T7 | Malformed-frontmatter fixture | stderr warning naming file; skipped in `--list`; no crash |
| T8 | Dual-schema round-trip (legacy `module/problem_type` AND current `title/category` fixtures) | Mutation preserves all other keys + key order; only `status` line added |
| T9 | `/soleur:compound` round-trip with `problem_type: technical_debt` | New entry has `status: open` at the right slot (from template edit) |
| T10 | `--help` | Usage block; exit 0 |
| T11 | Docs site build | `resolve-debt` rendered under Workflow category |
| T12 | Word-budget guard | `bun test plugins/soleur/test/components.test.ts` green |

## Open Code-Review Overlap

None. Phase 1.7.5 grep against 80 open `code-review`-labeled issues for each planned file path returned zero matches:

- `plugins/soleur/skills/compound-capture` → no hits
- `plugins/soleur/docs/_data/skills.js` → no hits
- `plugins/soleur/README.md` → no hits
- `knowledge-base/project/learnings/technical-debt` → no hits
- `knowledge-base/overview/brand-guide.md` → no hits

No fold-in / acknowledge / defer decisions needed.

## Domain Review

**Domains relevant:** Product, Engineering, Legal (carried forward from brainstorm `## Domain Assessments`).

**Brainstorm carry-forward:** all three triad leaders signed off on lifecycle-first sequencing at brainstorm time (2026-05-12). No fresh assessment needed at plan time. CLO carry-forward constraints (path denylist, NOTICE attribution, aggregate-only PR bodies, 2-cycle dry-run) apply to deferred #3650 ONLY — Spec A does not touch infra paths or commit scan output.

### Product (CPO)

**Status:** reviewed (carry-forward). **Assessment:** Spec A is the lifecycle prerequisite the CPO requested; founder-outcome gate is satisfied as "evidence-gathering for the deferred scanner re-evaluation criteria." Sign-off granted at brainstorm time; this plan implements the agreed scope.

### Engineering (CTO)

**Status:** reviewed (carry-forward). **Assessment:** Skill-not-agent (✓), markdown-extension (✓), reuses `code-quality-analyst` adjacency without scope creep. Plan honors all 5 capability gaps the CTO identified.

### Legal (CLO)

**Status:** reviewed (carry-forward). **Assessment:** Spec A's residual leak surface is `linked_issue` echo. Plan mitigates via integer-parse + range-check at the input boundary (Python `int()` rejects strings/floats/shell-metachars by construction). No MIT-lift in Spec A scope (NOTICE attribution carries forward to #3650 when references are lifted from `alirezarezvani/claude-skills`).

### Product/UX Gate

**Tier:** NONE. No files created under `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Skill is operator-terminal-only.

### Brainstorm-recommended specialists

None named. Plan invoked `spec-flow-analyzer` for operator-terminal flow analysis (7 critical AC gaps surfaced + 4 minor — all folded into ACs).

## GDPR / Compliance Gate

Trigger (b) from plan Phase 2.7 fired: `brand_survival_threshold: single-user incident` is declared. Per the rule, `/soleur:gdpr-gate` would be invoked.

**Assessment (inline, advisory-only):**

- **Regulated data surfaces touched:** None. Plan operates exclusively on Soleur plugin internal-tooling artifacts (ledger entries, skill configuration, docs-site data). No customer PII, no Supabase tables, no auth flows, no API routes, no `.sql` files, no Doppler/Cloudflare secret surfaces.
- **External-API processing:** None. Only `gh issue view <N>` (public repo metadata).
- **Compound-capture adjacency note:** the `/soleur:compound` template edit could theoretically capture operator-session-derived content into the ledger if a future session contains regulated content. The leak vector is pre-existing in `/soleur:compound`, not introduced by Spec A. Re-invoke the gate if Spec B (#3650) extends the surface.

**Conclusion:** Gate fires by trigger (b); no regulated-data surface is touched in Spec A. No `compliance-posture.md` Active Item; no `compliance/critical` issue filed. **Disclaimer:** advisory assessment, not legal opinion.

## Risks

| # | Risk | Likelihood | Severity | Mitigation |
|---|---|---|---|---|
| R1 | Inline backfill snippet corrupts a ledger entry's YAML (silent body change) | Low | High (brand-survival single-user incident) | Inline snippet imports proven `parse_frontmatter`/`serialize_frontmatter` helpers from `scripts/backfill-frontmatter.py`; MD5 body-verify asserted; operator inspects `git diff` before committing |
| R2 | `linked_issue` sanitization bypass | Very low | High | Python `int()` parse + range-check; no regex needed (rejects strings/floats/shell-metachars by construction); PyYAML serializes ints as ints |
| R3 | `gh issue view` failure silently bypasses validation | Low | Medium | Single failure path: non-zero exit → loud stderr + `--no-verify` hint + exit 1. No auto-fallback |
| R4 | Word-budget overflow forces SKILL.md trim | Medium | Low | 41-word headroom, draft is 28 words; CI gate at `components.test.ts` fails loud |
| R5 | Compound template edit breaks existing flows for non-tech-debt categories | Very low | Medium | Template-only edit (no schema change); the new `status: open` line is generic-safe. Schema.yaml unedited (CORA-vendored) |
| R6 | Skill never invoked (orphaned per `2026-02-09-plugin-staleness-audit-patterns.md`) | Medium | Medium (Spec A's hypothesis fails — but that's correct outcome) | This IS the falsifiable test: no closures in 60d → #3650 gets killed (correct outcome). Lifecycle field becomes low-cost no-op rather than active bug surface |
| R7 | Two frontmatter schemas drift further | Medium | Low | Schema unification is a separate tracked follow-up; not blocked by Spec A; plan documents this in Non-Goals |
| R8 | Foundations-PR contract-declaring (#3650 hasn't shipped) | Low | Medium | `/soleur:resolve-debt` is the immediate consumer; brainstorm-explicit R7 falsifiability framing IS the deferred-consumer gate. README.md names the binding |

## Sharp Edges (for `/work` phase)

- **Import parse helpers from `scripts/backfill-frontmatter.py:115-189` via `sys.path` insert.** Do NOT re-implement YAML mutation. No separate `_frontmatter.py` module — both Phase 1's inline snippet and `resolve-debt.py` import the proven helpers directly.
- **Awk frontmatter range pattern** (per `2026-03-05-awk-scoping-yaml-frontmatter-shell.md`): if shell parsing is ever needed for a sanity check, use `awk '/^---$/{c++; next} c==1'`. `sed` range patterns match ALL `---` blocks; ledger entry bodies may contain horizontal-rule `---`.
- **`gh issue view` must NOT live in a `!` code fence** (per `2026-02-22-skill-code-fence-permission-flow.md`). Place in narrative shell steps so Bash-tool permission prompts work.
- **Skill description budget is at 1759/1800 (41 words headroom).** Plan-time draft is 28 words. Re-measure after writing SKILL.md and BEFORE running `bun test`. If overflow, trim a sibling skill (NOT this one) per `2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`.
- **Spec FR1 amendment.** Spec.md says "11 existing entries"; reality is 9 live + 2 archived. Phase 1 commit includes a single-line amendment to spec.md FR1.
- **Spec FR9 + TR8 amendment.** Spec narrows to template-only edit (schema.yaml + references/yaml-schema.md unchanged); record this in the spec amendment commit.
- **Do NOT edit `compound-capture/schema.yaml`.** It is CORA-vendored (`# CORA Documentation Schema`). Adding any `required` field would trigger the blocking validation_gate (SKILL.md:185) for all 13 problem_types. Template-only is sufficient.
- **`requires_cpo_signoff: documentation-only`** is brainstorm-time carry-forward documentation, not a `/soleur:work` mechanical gate (no such gate exists today). Do NOT treat as enforceable.

## References

- Spec: `knowledge-base/project/specs/feat-tech-debt-tracker/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-12-tech-debt-tracker-brainstorm.md`
- Migration helper source: `scripts/backfill-frontmatter.py:115-189`
- Compound template anchor: `plugins/soleur/skills/compound-capture/assets/resolution-template.md`
- SKILL.md template precedent: `plugins/soleur/skills/schedule/SKILL.md`
- Word-budget guard: `plugins/soleur/test/components.test.ts` (`SKILL_DESCRIPTION_WORD_BUDGET = 1800`)
- Count-propagation rule: `knowledge-base/project/learnings/2026-02-22-skill-count-propagation-locations.md`
- YAML mutation rules: `knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`, `knowledge-base/project/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md`
- Defense-relaxation rule: `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md`
- Foundations-PR rule: `knowledge-base/project/learnings/2026-05-07-foundations-pr-must-not-declare-downstream-contracts.md`
- Deferred Spec B: #3650
