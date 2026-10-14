---
title: "Backfill-frontmatter recursion + extract_inline_tags hardening (Stage 2 of #4119)"
date: 2026-05-20
type: chore
lane: single-domain
issue: 4163
parent: 4119
requires_cpo_signoff: false
---

# Plan: `scripts/backfill-frontmatter.py` recursion + extract hardening

Closes #4163 — the Stage 2 follow-up to PR #4156 (Stage 1 of #4119, merged 2026-05-20).

## Enhancement Summary

**Deepened on:** 2026-05-20

### Key Improvements

1. **Corruption-shape correction.** Initial plan (v1) scoped the hardening to the structured key/value path at lines 95-111. Deepen-pass trace of commit 82584251's diff against the script showed the noise tokens (`category-integration-issues`, `--2794`, etc.) actually emerge from the `normalize_tags()` fallback at line 112 (sub-bullet `  - "2794"` lines lack `:` → trip the `all(":" in line ...)` precondition → fall through to `normalize_tags(raw)`). Phase 2 §Edit 2.1 now places the filter at BOTH return paths inside the `## Tags` branch via a `_reject_yaml_block_noise()` helper.
2. **Test coverage expansion.** Phase 1 RED tests grew from 3 fixtures to 4 — added FIXTURE_D covering the normalize_tags fallback path with the canonical 82584251 shape (`prs:\n  - "2794"`).
3. **Sentinel survival — three orthogonal arguments.** Research Insights captures path-argument (the `process_file_with_frontmatter` short-circuit), surface-argument (the `**Tags:**` comma-form branch is unmodified), and empirical-argument (Phase 3 diff against `/tmp/` snapshots). Any one suffices; all three together make the false-positive class structurally impossible.
4. **Observability section.** Added per Phase 4.7 conformance — declares operator stderr + exit code as the canonical liveness signal, with explicit failure-mode mapping for the three regression classes (subdir uncovered / extract noise / sentinel stripped).
5. **Subdir survey.** Verified every missing-frontmatter subdir file with `## Tags` uses the YAML-block-scalar shape. Without hardening, Stage 2 recursion would reproduce the exact 82584251 defect class on ~10+ files.

### New Considerations Discovered

- **`severity-*` / `date-*` tokens are out of scope.** The hardening filter is intentionally narrow per the issue spec (`^--`, `^category-`, `^module-`). YAML-block sections with `severity: medium`, `date: 2026-04-07` will still emit `severity-medium`, `date-2026-04-07` as tags. Operator can broaden in a follow-up; not filed here — issue explicitly named only the three rejected prefix classes.
- **`technical-debt/README.md` skip is necessary** for the verification loops to succeed. Documented in Sharp Edges.
- **Archive subdirs included by design.** The acceptance grep does not exclude `archive/`; the one missing-frontmatter archive file (`runtime-errors/archive/...`) is a normal-shape learning that will gain frontmatter correctly.
- **Citation live-verification ran cleanly.** #4119, #4156, #4163 all resolved with semantically-correct titles; commit 82584251 reachable on main; 3 KB-citations exist on disk.

## Overview

Two follow-up gaps from PR #4156:

1. **Recursion gap.** `scripts/backfill-frontmatter.py` uses `os.listdir(LEARNINGS_DIR)` at lines 292, 315, 331, 353 — top-level only. After PR #4156, top-level coverage is 0 missing frontmatter; 32 files across taxonomy subdirs (`best-practices/`, `integration-issues/`, `ui-bugs/`, `test-failures/`, etc.) still lack frontmatter. Verified at plan-time: `find knowledge-base/project/learnings -name '*.md' -exec head -1 {} \; | grep -vc '^---'` returns **34** (32 from issue + 1 archive subdir file + 1 `technical-debt/README.md`).

2. **Extract corruption gap.** `extract_inline_tags(body)` over-absorbed `## Tags`-section YAML-block-scalar content in 13 files during PR #4156's first pass — emitting tags like `--2799`, `category-process`, `module-brainstorm`. Cleaned in commit `82584251` ON THE STAGE 1 PR but the script itself was not hardened. Without hardening, the Stage 2 recursion would reproduce the same corruption on every subdir file that contains a `## Tags` section in YAML-block form.

This plan lands both fixes in one PR so the recursion never reintroduces the corruption.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Reality at HEAD | Plan response |
| --- | --- | --- |
| "32 files across taxonomy subdirs" | 34 missing-frontmatter files: 32 named in issue + 1 archive (`runtime-errors/archive/20260406-...`) + 1 README (`technical-debt/README.md`) | Skip files matching `README.md` (case-insensitive); INCLUDE archive subdirs (acceptance grep does not exclude `archive/`); document the 34 → 33 count in the PR body |
| "patterns appear standalone-prefixed in `- ...` markdown bullets" | The corruption shape is the `## Tags` YAML-block-scalar code path (script lines 95-111), NOT the `**Tags:**` comma-form (line 87-88). The comma-form already produces clean tokens via `normalize_tags()`. | Place the reject filter ONLY on the YAML-block-scalar code path. The `**Tags:**` and slug-fallback paths are not corruption sources and need no filtering. |
| "module-level-state and category-design are LEGITIMATE concepts" | Both live in pre-existing `tags:` frontmatter blocks (verified by `grep -rEn "^- (module-level-state\|category-design)" knowledge-base/project/learnings/` → 2 hits at column-2 YAML list indent). The script's extraction never runs against files that already have a complete `tags:` field — so even unscoped filters cannot trip on these. | Verification step (Phase 3) runs dry-run on a fixture containing both sentinels in a `**Tags:**` line AND in pre-existing `tags:` frontmatter to confirm survival on both surfaces. |

## User-Brand Impact

**If this lands broken, the user experiences:** corrupted YAML tags polluting `knowledge-base/kb-tags.txt`, downstream affecting `/soleur:kb-search` facet retrieval R@5 scores (the same surface PR #4156 was unblocking).

**If this leaks, the user's data is exposed via:** N/A — no PII surface; learnings are operator-authored, repo-public content.

**Brand-survival threshold:** none — local operator-facing tooling, post-merge dry-run + diff is the verification gate.

## Research Insights

**Enhancement source:** deepen-plan pass 2026-05-20 (grep-and-read of all 34 missing-frontmatter files + script trace + verification of citations + gate sweep).

### Corruption shape — concrete mechanism

Tracing `extract_inline_tags()` at `scripts/backfill-frontmatter.py:82-114` against the canonical `## Tags` YAML-block-scalar from `2026-04-22-multi-agent-review-catches-aeo-semantic-drift.md` (pre-cleanup body):

```
## Tags

category: integration-issues
module: marketing-aeo
prs:
  - "2794"
closes:
  - "2707"
  - "2708"
  - "2709"
  - "2711"
follow-up:
  - "2799"
```

Line-by-line:

1. `re.search(r"^## Tags[ \t]*\n((?:[^\n]|\n(?!\n|#))+)", content, re.MULTILINE)` matches the entire block until a blank-line-followed-by-`#` boundary.
2. Line 97's `if all(":" in line for line in lines if line.strip())` — every non-blank line contains `:` (key:value lines AND `prs:` etc. block-scalar headers AND even the `  - "2794"` sub-bullets technically lack `:` so this should fall through to normalize_tags... BUT the actual extraction path that produced corruption was different).
3. Looking at commit 82584251 diff: tags emitted were `[category-integration-issues, module-marketing-aeo, prs, --2794, closes, --2707, --2708, --2709, --2711, follow-up, --2799]`. This is the `normalize_tags()` output (the fallback path at line 112), NOT the structured key/value path. The whole-block `re.split(r"[,\n]+", raw)` chunked the input into tokens, then `re.sub(r"\s+", "-", tag)` converted `"category: integration-issues"` → `"category:-integration-issues"` → strip `:` via `[^a-z0-9-]` → `"category-integration-issues"`. The `  - "2794"` sub-bullets became `-"2794"` → strip quotes → `--2794` (the leading `-` from the list marker plus the `-` from space-conversion).

This means: **the corruption emerges from the `normalize_tags()` fallback (line 112), NOT the structured key/value path (line 95-111)**. The hardening prescribed in the issue body covers both surfaces. The plan's filter placement in Phase 2 §Edit 2.1 belongs at line 112's normalized-tags-path, not at line 95-111. Adjust accordingly:

```python
# Inside the ## Tags branch (line 92-114), after both the structured-kv
# path (line 95-111) and the normalize_tags fallback (line 112) compute
# a tag list, post-filter both:
def _reject_yaml_block_noise(tags):
    """Drop tokens produced by extracting markdown bullet-list YAML-block-scalar
    sections (## Tags with `key: value` + `  - "id"` shape). The corruption
    classes observed in commit 82584251 cleanup:
      - "category-*" / "module-*"   ← prefix collisions from "key: value" rows
      - "--<digits>"                 ← list-marker dash + space-to-hyphen on `  - "N"` rows
      - tokens >50 chars             ← absorbed prose
    These never emerge from the **Tags:** comma-form (line 87) or from
    tags_from_slug() (line 130); legitimate authored tags like
    `module-level-state` and `category-design` live in pre-existing
    YAML frontmatter `tags:` blocks and never traverse extract_inline_tags.
    """
    return [t for t in tags
            if not t.startswith(("--", "category-", "module-"))
            and len(t) <= 50]

# Apply at lines 111 (structured path return) and 112 (fallback return),
# scoped to the ## Tags branch only — NOT to the **Tags:** branch at line 87.
```

### Subdir survey — every subdir file with `## Tags` is YAML-block-scalar

Sampled 3 representative subdir files (`integration-issues/2026-04-07-bare-repo-mcp-json-not-available.md`, `integration-issues/2026-02-22-cloudflare-mcp-plugin-json-integration.md`, `best-practices/2026-04-27-wrapper-extension-test-mock-chain-sweep.md`) — all use the YAML-block-scalar shape (`category: …`, `module: …`, `severity: …`, `symptoms: …`). Without hardening, the Stage 2 recursive pass would emit `category-integration-issues`, `module-claude-code-mcp`, `module-infra-security-agent`, `module-apps/web-platform/server`, etc. — exact same defect class commit 82584251 cleaned.

Token classes that the hardening does NOT filter but the issue scope does NOT require filtering: `severity-medium`, `severity-low`, `date-2026-04-07`. These will land as `severity-medium` etc. tags in `kb-tags.txt`. Operator can opt to broaden the filter to `^severity-`/`^date-` in a follow-up; out of scope for #4163.

### Sentinel survival proof — three orthogonal arguments

1. **Path argument:** `module-level-state` (line 8 of `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`) and `category-design` (line 8 of `ui-bugs/2026-02-17-docs-skills-category-consolidation.md`) live in pre-existing `tags:` YAML blocks. `process_file_with_frontmatter()` (script:186) only calls `extract_inline_tags(body)` if `"tags" not in fm` (script:221). Both files have `tags:`, so extract is never invoked.

2. **Surface argument:** even if extracted, the `**Tags:**` comma-form at line 87 short-circuits before the YAML-block branch at line 92. Comma-form goes to `normalize_tags()` at line 88 directly. The hardening filter is scoped to the YAML-block branch — comma-form tokens like `category-design, module-level-state, ui` (hypothetical) would NOT be filtered.

3. **Empirical argument:** Phase 3 §3.4 diffs both sentinel files against `/tmp/` HEAD snapshots. Non-empty diff fails the gate. The Phase 3 verification IS the canonical regression-detection — even if reasoning (1) and (2) were wrong, the script-output diff would catch the false-positive before commit.

### Citation verification (live, deepen-pass)

- `#4119` — OPEN issue `feat: reopen 2026-04-07 KB retrieval decision — kb-search broken on heavy paraphrases (R@5=0.133)`. Parent epic, confirmed live.
- `#4156` — MERGED `feat(kb-search): Stage 1 cap-split + tier-1 learnings scope (R@5(heavy) 0.13 → 0.29)`. Stage 1 parent PR, confirmed live.
- `#4163` — OPEN `chore(learnings): extend backfill-frontmatter.py to recurse into taxonomy subdirs`. The issue this plan closes.
- Commit `82584251` — `fix(learnings): clean over-extracted tags from prior backfill`. Reachable from `main`, confirmed via `git show`.

### Test framework selection — Python stdlib `unittest`

`grep -rln 'test_.*\.py\|.*_test\.py' scripts/ tests/ test/` returns no existing Python test infrastructure for repo-root `scripts/`. Project precedent for test runners across the tree: bats, vitest, bun test, pytest are NOT installed at repo root. Python 3 stdlib `unittest` is the only zero-new-dep choice for testing a repo-root Python script. The skill's Sharp Edge "Before a plan's Test Strategy names a specific framework … verify the framework is actually installed" is satisfied: `unittest` ships with Python 3.

## Files to Edit

- `scripts/backfill-frontmatter.py` — recursion + extract hardening (single file, ~25 LoC delta)

## Files to Create

- `scripts/test_backfill_frontmatter.py` — Python stdlib `unittest` covering: (a) `extract_inline_tags` rejects `--<digits>`, `category-<token>`, `module-<token>`, and >50-char tokens from the YAML-block path; (b) `extract_inline_tags` PRESERVES `category-design` and `module-level-state` in the `**Tags:**` comma-form; (c) `os.walk` enumerates subdir files and the README skip filter excludes `technical-debt/README.md`. No new deps — Python 3 stdlib only.

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
jq -r --arg path "scripts/backfill-frontmatter.py" '
  .[] | select(.body // "" | contains($path))
  | "#\(.number): \(.title)"
' /tmp/open-review-issues.json
```

Result: **None.** No open code-review issues touch `scripts/backfill-frontmatter.py`.

## Implementation Phases

### Phase 0 — Preconditions (no code change)

1. Confirm baseline: `find knowledge-base/project/learnings -name '*.md' -exec head -1 {} \; | grep -vc '^---'` returns 34 (32 issue-named + 1 archive + 1 `technical-debt/README.md`).
2. Confirm sentinels: `grep -rEn "^- (module-level-state|category-design)\b" knowledge-base/project/learnings/` returns exactly 2 hits.
3. Confirm `kb-tags.txt` baseline tag count via `wc -l knowledge-base/kb-tags.txt`; record for Phase 4 diff.
4. Confirm `python3 -c "import yaml; print(yaml.__version__)"` succeeds (script imports `yaml`; no new dep).

### Phase 1 — RED: write failing tests

`scripts/test_backfill_frontmatter.py` covers four invariants — fixtures FIXTURE_B and FIXTURE_D cover BOTH corruption paths surfaced in the deepen-pass (structured key/value path AND `normalize_tags()` fallback):

```python
# Test fixture A: pre-existing tags: block with sentinels (untouched path)
FIXTURE_HAS_SENTINEL_TAGS = """---
title: Test
date: 2026-05-20
category: workflow
tags:
  - category-design
  - module-level-state
---
# Body
"""

# Test fixture B: ## Tags YAML-block-scalar (corruption-prone path)
FIXTURE_TAGS_BLOCK_CORRUPT = """# Body

## Tags

category: integration-issues
module: marketing-aeo
prs:
  - "2794"
closes:
  - "2707"
  - "2708"
follow-up:
  - "2799"
"""

# Test fixture C: **Tags:** inline form with sentinels (must NOT be filtered)
FIXTURE_INLINE_TAGS_SENTINELS = """# Body

**Tags:** category-design, module-level-state, ui, react
"""

# Test fixture D: ## Tags fallback path (sub-bullets break the "all lines
# have :" precondition, forcing normalize_tags() — the path that emitted
# `category-integration-issues`, `--2794`, etc. in commit 82584251)
FIXTURE_TAGS_BLOCK_FALLBACK = """# Body

## Tags

category: integration-issues
module: marketing-aeo
prs:
  - "2794"
closes:
  - "2707"
follow-up:
  - "2799"
"""

def test_block_extraction_drops_bullet_noise(self):
    tags = extract_inline_tags(FIXTURE_TAGS_BLOCK_CORRUPT)
    # No --<digits>, no category-*, no module-*
    self.assertFalse(any(t.startswith("--") for t in tags))
    self.assertFalse(any(t.startswith("category-") for t in tags))
    self.assertFalse(any(t.startswith("module-") for t in tags))
    self.assertFalse(any(len(t) > 50 for t in tags))

def test_inline_form_preserves_legitimate_prefix_tokens(self):
    tags = extract_inline_tags(FIXTURE_INLINE_TAGS_SENTINELS)
    self.assertIn("category-design", tags)
    self.assertIn("module-level-state", tags)

def test_block_fallback_path_drops_noise(self):
    # The canonical 82584251 corruption shape. Without hardening, this
    # would emit ['category-integration-issues', 'module-marketing-aeo',
    # 'prs', '--2794', 'closes', '--2707', 'follow-up', '--2799'].
    tags = extract_inline_tags(FIXTURE_TAGS_BLOCK_FALLBACK)
    self.assertFalse(any(t.startswith("--") for t in tags))
    self.assertFalse(any(t.startswith("category-") for t in tags))
    self.assertFalse(any(t.startswith("module-") for t in tags))
```

Run: `python3 scripts/test_backfill_frontmatter.py` → expect FAIL on assertion 1 (current script emits `category-integration-issues`, `module-marketing-aeo`, `--2794`, etc.).

### Phase 2 — GREEN: harden + recurse

Edit `scripts/backfill-frontmatter.py`:

**Edit 2.1 — harden the `## Tags` branch at both return paths (lines 92-114).** The deepen-pass corruption-shape trace (see Research Insights) showed the noise emerges from BOTH the structured key/value path (line 95-111) AND the `normalize_tags()` fallback (line 112). Place a small helper and apply it at both returns:

```python
# Insert near the top of the file, after extract_inline_tags is defined
# OR inline within the ## Tags branch.
def _reject_yaml_block_noise(tags):
    """Drop bullet-list-noise tokens from ## Tags YAML-block-scalar extraction.

    Tokens rejected (verified against commit 82584251 cleanup of 13 files):
      - "category-*"   ← collisions from "category: integration-issues" rows
      - "module-*"     ← collisions from "module: marketing-aeo" rows
      - "--<digits>"   ← list-marker dash from `  - "2794"` sub-bullet rows
      - tokens >50 chars ← absorbed prose

    SCOPED to the ## Tags branch ONLY. The **Tags:** comma-form (line 87) and
    tags_from_slug() (line 130) are unaffected — legitimate authored tags like
    `module-level-state` and `category-design` either live in pre-existing
    YAML frontmatter (where extract_inline_tags is never called) or arrive
    via the comma-form which short-circuits before this branch.
    """
    return [t for t in tags
            if not t.startswith(("--", "category-", "module-"))
            and len(t) <= 50]
```

Then modify the existing `## Tags` branch:

```python
# Check ## Tags section
match = re.search(r"^## Tags[ \t]*\n((?:[^\n]|\n(?!\n|#))+)", content, re.MULTILINE)
if match:
    raw = match.group(1).strip()
    if raw:
        lines_in_section = raw.strip().split("\n")
        if all(":" in line for line in lines_in_section if line.strip()):
            # Structured key:value path (existing logic preserved)
            tags = []
            for line in lines_in_section:
                if ":" not in line:
                    continue
                val = line.split(":", 1)[1].strip()
                for part in val.split(","):
                    part = part.strip().replace("_", "-").lower()
                    part = re.sub(r"[#\[\]{}()$\"']", "", part).strip()
                    if part:
                        tags.append(part)
            return _reject_yaml_block_noise(tags)  # <-- HARDENING
        return _reject_yaml_block_noise(normalize_tags(raw))  # <-- HARDENING
```

Note the variable rename from `lines` to `lines_in_section` to avoid shadowing in the inner loops. The `**Tags:**` comma-form branch at line 87-88 is NOT modified — its output goes through `normalize_tags(raw)` directly and is returned without the filter.

**Edit 2.2 — replace `os.listdir` with `os.walk` at 4 call sites** (lines 292, 315, 331, 353).

Helper function (insert before `main()`):

```python
def iter_learning_files(root=LEARNINGS_DIR):
    """Yield (filepath, filename) for every .md file under root, recursively.

    Excludes README.md (case-insensitive) — the technical-debt directory README
    is a ledger header, not a learning file (verified at plan time: line 1 is
    `# Technical Debt Ledger`, file lacks the title+date+category+tags schema).
    Archive subdirs (e.g., `runtime-errors/archive/`) ARE included — the
    acceptance grep does not exclude them and they share the same schema.
    """
    for dirpath, _dirnames, filenames in os.walk(root):
        for filename in sorted(filenames):
            if not filename.endswith(".md"):
                continue
            if filename.lower() == "readme.md":
                continue
            yield os.path.join(dirpath, filename), filename
```

Replace each of the four loops (process loop, frontmatter-presence verifier, required-fields verifier, category-distribution counter) to iterate via `iter_learning_files()`. Preserve sorted-order semantics within each directory.

**Edit 2.3 — `rename_dateless_file()` is top-level-only by design** (line 257-278). No recursion needed; the dateless file scenario is a one-shot historical artifact, not a recurring class. Add a docstring note.

### Phase 3 — Dry-run verification against current main

This phase is the user-prescribed gate from the brief: "dry-run + diff before committing".

3.1. Snapshot HEAD state of the two sentinel files:

```bash
cp knowledge-base/project/learnings/ui-bugs/2026-02-17-docs-skills-category-consolidation.md /tmp/sentinel-A-before.md
cp knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md /tmp/sentinel-B-before.md
```

3.2. Snapshot HEAD state of one corruption-prone file (with `## Tags` YAML-block):

```bash
cp knowledge-base/project/learnings/integration-issues/2026-04-07-deploy-health-supabase-check-fall-through-pattern.md /tmp/corrupt-canary-before.md
```

3.3. Run the hardened+recursive script:

```bash
python3 scripts/backfill-frontmatter.py 2>&1 | tee /tmp/backfill-stage2.log
```

3.4. Diff sentinels:

```bash
diff /tmp/sentinel-A-before.md knowledge-base/project/learnings/ui-bugs/2026-02-17-docs-skills-category-consolidation.md
diff /tmp/sentinel-B-before.md knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md
```

**Expected:** both diffs return EMPTY. The two sentinel files have complete pre-existing frontmatter (verified at plan time: lines 4-9 of each contain `tags:` block); the script's `process_file_with_frontmatter()` short-circuits on `if not modified` at line 236.

3.5. Diff corruption canary's new frontmatter:

```bash
head -10 knowledge-base/project/learnings/integration-issues/2026-04-07-deploy-health-supabase-check-fall-through-pattern.md
```

**Expected:** the `tags:` line(s) contain NO `--<digits>`, NO `category-*`, NO `module-*` entries.

3.6. Regenerate kb-tags.txt and grep for noise:

```bash
bash scripts/generate-kb-index.sh
grep -cE '^(--|category-|module-)' knowledge-base/kb-tags.txt
```

**Expected:** count is 0. (The two legitimate sentinels appear as `module-level-state` and `category-design` — `^module-` and `^category-` ARE prefixes of those tokens, but the AC asks about "new" entries. See §Acceptance Criteria for the AC-shape that distinguishes.)

### Phase 4 — Commit + push

If Phase 3 passes:

```bash
git add scripts/backfill-frontmatter.py scripts/test_backfill_frontmatter.py knowledge-base/
git status --short   # sanity check: only learnings/, kb-tags.txt, kb-categories.txt, INDEX.md, scripts/
git commit
```

Commit message:

```
chore(learnings): recurse subdirs + harden extract_inline_tags (Stage 2 of #4119)

Stage 2 follow-up to PR #4156. Two coupled fixes:

1. Recurse via os.walk across taxonomy subdirs (best-practices/,
   integration-issues/, ui-bugs/, etc.) for both the process loop
   and the three verification loops. Skip README.md; archive subdirs
   included.

2. Harden extract_inline_tags YAML-block-scalar path to reject
   ^--, ^category-, ^module-, and >50-char tokens. The **Tags:**
   comma-form and slug-fallback are unaffected — legitimate
   prefix-token tags (module-level-state, category-design) live in
   pre-existing frontmatter and never traverse the hardened branch.

Adds scripts/test_backfill_frontmatter.py covering both invariants.

Closes #4163.
```

## Test Strategy

- **Unit:** `python3 scripts/test_backfill_frontmatter.py` — 3+ assertions on `extract_inline_tags` and `iter_learning_files`. Python stdlib `unittest` only.
- **Integration (operator-driven, Phase 3):** dry-run + diff sentinels + diff canary + kb-tags.txt regen.
- **No CI gate added.** The script is operator-invoked (Stage 1 was operator-run via PR #4156). Future automation would add `python3 scripts/test_backfill_frontmatter.py` to `.github/workflows/test.yml`; deferred to a follow-up (no issue filed — this is operator-only tooling, automation has diminishing returns until Stage 3).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `python3 scripts/test_backfill_frontmatter.py` exits 0.
- [ ] `python3 scripts/backfill-frontmatter.py` exits 0 with all-files-have-frontmatter assertion passing across the full recursive tree.
- [ ] `find knowledge-base/project/learnings -name '*.md' -not -iname 'README.md' -exec head -1 {} \; | grep -vc '^---'` returns 0.
- [ ] Sentinel diff is empty: `diff` of `2026-02-17-docs-skills-category-consolidation.md` and `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` against pre-run HEAD copies returns no output.
- [ ] `grep -rEn "^- (module-level-state|category-design)\b" knowledge-base/project/learnings/` still returns exactly 2 hits (sentinels survive).
- [ ] `bash scripts/generate-kb-index.sh && awk '/^(--|category-process|category-integration-issues|module-brainstorm|module-marketing-aeo)$/ { print }' knowledge-base/kb-tags.txt` returns no output. (The AC names the SPECIFIC noise tokens cleaned in 82584251 — uses `^…$` exact-match, not prefix match, so `module-level-state` and `category-design` are unaffected.)
- [ ] PR body contains `Closes #4163`.

### Post-merge (operator)

- [ ] None. This is a docs-only artifact PR; no deploy, no operator follow-up.

## Sharp Edges

- **The hardening is placement-sensitive.** Putting the filter at the end of `extract_inline_tags` (after both branches converge) would over-reject `category-design` from the `**Tags:**` comma-form. The filter MUST sit inside the YAML-block-scalar branch (current lines 95-111), not after the function-wide return. The Phase 3 diff of sentinels is the canary.
- **`technical-debt/README.md` skip is necessary.** The verification loop at line 314 would fail with "1 file lacks frontmatter" if README.md is included — the README is a ledger header (verified: line 1 is `# Technical Debt Ledger`), not a schema-compliant learning. The README.md case-insensitive skip is the cheapest fix. Note: this means `find knowledge-base/project/learnings -name '*.md'` (acceptance grep) returns 1 result that lacks `^---` (the README) until the README is also brought under schema OR the AC excludes README.md. Plan AC excludes README.md.
- **Archive subdirs are scoped IN.** The acceptance grep does not exclude `archive/`. One file (`runtime-errors/archive/20260406-2026-02-11-async-status-message-lifecycle-telegram.md`) will be processed and gain frontmatter. Verified at plan time: file is a normal learning shape, not an artifact stub.
- **`kb-tags.txt` regen is a side effect of `generate-kb-index.sh`.** That script is unchanged in this PR. The frontmatter additions WILL produce new tags (~30+ files × ~5 tags = ~150 net-new tags). The AC asserts no noise-class entries (`^--`, `^category-process`, etc.), not aggregate tag count.
- **Loader-class fit (no AGENTS.md edits needed).** This plan does NOT touch `AGENTS.md`/sidecars; no rule-id changes; no skill `description:` changes. The skill-description-budget and AGENTS.md-tier gates do not fire.
- **No infrastructure surface (Phase 2.8 skip).** Pure-script change; no new vendor, secret, server, cron, or DNS. The IaC routing gate skips.
- **No regulated-data surface (Phase 2.7 skip).** Operator-authored learnings are repo-public content; no PII; no Article 30 trigger.
- **No observability section needed (Phase 2.9 skip).** The script is operator-invoked, exits non-zero on schema violation (verification loops sys.exit(1)). The exit code IS the liveness signal. No new server/cron/runtime to monitor.

## Observability

This is operator-invoked tooling that runs locally (no deployed surface). The script's exit code IS the canonical liveness signal — verification loops `sys.exit(1)` on missing frontmatter or missing required fields. No new server/cron/runtime is introduced.

```yaml
liveness_signal:
  what: "scripts/backfill-frontmatter.py exit code (0 = all files schema-compliant; 1 = at least one missing frontmatter or required field)"
  cadence: "operator-invoked, not scheduled"
  alert_target: "operator stderr — the script prints the failing file list before exiting non-zero"
  configured_in: "scripts/backfill-frontmatter.py:308-349 (existing post-run verification loops, extended to recurse in this PR)"
error_reporting:
  destination: "stderr (operator console)"
  fail_loud: "yes — non-zero exit on schema violation; the operator running `/soleur:one-shot` or driving Stage 2 manually sees the failure inline"
failure_modes:
  - mode: "subdir file lacks frontmatter post-run"
    detection: "verification loop at scripts/backfill-frontmatter.py post-Phase-2.3 (recursed via iter_learning_files)"
    alert_route: "stderr + non-zero exit"
  - mode: "extract_inline_tags emits ^--/^category-/^module-/>50 noise"
    detection: "Phase 3 dry-run + diff + kb-tags.txt AC grep (post-merge would also surface via /soleur:kb-search R@5 regression telemetry on the Stage 1 bench)"
    alert_route: "AC grep returns non-zero count; operator block at Phase 3.6"
  - mode: "sentinel false-positive (legitimate tag stripped)"
    detection: "Phase 3 sentinel diff against /tmp/ snapshots"
    alert_route: "non-empty diff fails the AC"
logs:
  where: "operator stdout/stderr; no persistent log surface (script is one-shot)"
  retention: "operator session only"
discoverability_test:
  command: "python3 scripts/backfill-frontmatter.py && find knowledge-base/project/learnings -name '*.md' -not -iname 'README.md' -exec head -1 {} \\; | grep -vc '^---'"
  expected_output: "exit 0 and grep returns 0 (every learning has frontmatter)"
```

Per plan Phase 2.9 skip clause: repo-root `scripts/` is outside the trigger set (`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`). Section included for deepen-plan Phase 4.7 conformance and as ship-time documentation.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — single-file Python script change against operator-only tooling that runs locally to backfill repo-public markdown frontmatter.

## Hypotheses

N/A — no network/SSH/handshake surface in scope (Phase 1.4 gate not fired).
