---
title: Plan-time Python imports and hyphenated module names — verify before /work, prefer lib-extract over importlib
date: 2026-05-12
category: best-practices
tags: [plan, work, python, imports, frontmatter, hyphens, sharp-edges]
severity: medium
status: open
---

# Plan-time Python imports and hyphenated module names

## Problem

The post-review plan for feat-tech-debt-tracker (#3645) prescribed loading helpers from `scripts/backfill-frontmatter.py` via:

```python
import sys
sys.path.insert(0, 'scripts')
from backfill_frontmatter import parse_frontmatter, serialize_frontmatter
```

This fails at runtime with `ModuleNotFoundError: No module named 'backfill_frontmatter'` — the source filename contains a hyphen and Python identifiers cannot contain hyphens. `sys.path.insert` lets Python *find* the file, but `import backfill_frontmatter` still won't resolve to it.

The plan even noted (verbatim): *"scripts/backfill-frontmatter.py is a standalone script, not a package — the sys.path import works because Python imports the module by file basename."* That assertion is incorrect: Python imports by *identifier*, and `backfill-frontmatter` is not a valid identifier.

The plan was reviewed by 5 agents at plan time; none caught the import bug. /work started with the bug and discovered it at the first `python3 -c` invocation in Phase 1.

## Solution

Two patches landed in sequence:

1. **Phase 3 quick-fix** — `resolve-debt.py` switched from the plan's prescribed `sys.path + import` to `importlib.util.spec_from_file_location`:

   ```python
   spec = importlib.util.spec_from_file_location("_bff", src)
   mod = importlib.util.module_from_spec(spec)
   spec.loader.exec_module(mod)
   parse_frontmatter = mod.parse_frontmatter
   ```

   This works, but a layering smell: a plugin skill reaching into a one-shot migration script via `importlib.util` is more machinery than the problem deserves.

2. **Review fix-inline (after code-simplicity-reviewer dissent on a proposed scope-out)** — extracted the helpers to a sibling `scripts/frontmatter_lib.py`. Both `backfill-frontmatter.py` (the migration script keeps its filename and existing contract) and the new `resolve-debt.py` now do:

   ```python
   import sys, os
   sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
   from frontmatter_lib import parse_frontmatter, serialize_frontmatter
   ```

   Single source of truth. No `importlib.util`. Re-export pattern not needed — both callers fix their own import path.

The dissent (rejecting the scope-out claim of "cross-cutting refactor") was correct: the speculated `scripts/content-publisher.sh` consumer didn't actually import these helpers (a 30-second `grep` would have shown that), so the touch surface was 3 small files in one commit, not a cross-cutting cycle.

## Key Insight

**Plan-quoted import statements are preconditions to verify at /work start, not facts to trust.** The same way plan-quoted measurements (`wc -c < AGENTS.md`, "cumulative ~Y words; ~Z headroom") get re-measured because parallel branches may have moved them, plan-quoted Python imports must be tested in a one-line probe before linking the plan's approach as the recommended path. The cost is one `python3 -c "import sys; sys.path.insert(0,'…'); from … import …"` invocation. The cost of skipping is a code commit on a broken precondition that surfaces only at runtime.

Generalization: any plan that quotes a *transport mechanism* (import, fetch URL, shell-out, MCP tool call, npm script name) for connecting two parts of a system should be probed at /work start. The plan-author and the runtime see different worlds.

## Why This Works

Python's import machinery resolves identifiers, not filenames. The mental model "import is just `cp` from disk" is wrong:

- `sys.path.insert(0, 'scripts')` adds `scripts/` to the search path.
- `import foo` makes Python look for `foo.py` or `foo/__init__.py` on the path.
- `foo` must be a valid Python identifier (`[A-Za-z_][A-Za-z0-9_]*`).
- `import backfill-frontmatter` is a syntax error in any code path Python would parse.
- `importlib.util.spec_from_file_location("name", "/path/with-hyphens.py")` is the documented workaround.

The cleaner option — and the one code-simplicity-reviewer recommended — is to make the filename a valid identifier (rename or extract a sibling), eliminating the import-machinery dance entirely.

## Prevention

For the `/soleur:plan` skill: when the plan body quotes a Python import that targets a path with non-identifier characters (hyphens, dots beyond the suffix, leading digits), flag it as a precondition error at plan-review time. A regex audit on the plan body (`import\s+[a-zA-Z0-9_.]*-`) catches this class.

For the `/soleur:work` skill: add to the Phase 1 "Read Plan and Clarify" step — when the plan quotes a Python import, run a one-liner probe before depending on it:

```bash
python3 -c "import sys; sys.path.insert(0, '<dir>'); from <module> import <name>" 2>&1
```

If the probe fails, treat as a precondition error and fix the plan (or the import strategy) before starting implementation.

For both skills: when a Python helper module needs to be shared across the repo, prefer **filename-is-identifier** over `importlib.util` workarounds. Either rename to underscores from the start, or extract helpers to a sibling lib module. The path-with-hyphens convention is fine for *one-shot scripts that are never imported* — but the moment a second caller needs the symbols, rename or extract.

## Session Errors

**Plan-quoted import was wrong but not caught at plan-review.** — Recovery: switched to `importlib.util` in Phase 3, then extracted to `scripts/frontmatter_lib.py` in review. Prevention: probe Python imports at /work Phase 1; flag hyphenated filenames at plan-review. (Captured above as primary insight.)

**First Phase 1 backfill reordered frontmatter keys.** Routing 9 ledger entries through `serialize_frontmatter` (which sorts keys per its required/optional ordering) produced 5-7-line diffs per file instead of the spec's "9 single-line additions" target. — Recovery: reverted and switched to surgical line-insert (find the closing `---`, insert `status: open` before it, write back). MD5-verify the body. — Prevention: for "add one frontmatter field" migrations, use surgical line-insert. The full parse → mutate dict → serialize → write loop reorders keys whenever the dict's iteration order differs from the source file's line order. Mass-migrations that want to *also* normalize key order should declare that as an explicit goal in the spec; ledger backfills that promise "single-line addition" must use surgical insert.

**SKILL.md failed `components.test.ts` backtick-refs regex twice.** Used `` `scripts/backfill-frontmatter.py` `` in inline code spans; the regex `` `(?:references|assets|scripts)/[^`]+` `` is unconditional — it catches any backticked path with those prefixes regardless of whether the path is skill-relative. — Recovery: rephrased to use the file's name without backticks around the full path. — Prevention: in any SKILL.md prose referencing a repo-root path that starts with `scripts/`, `references/`, or `assets/`, drop the backticks around the path *or* use a markdown link. The regex was designed to enforce skill-internal link conventions but the literal pattern matches any path with those prefixes.

**`--list --json` raised `TypeError: Object of type date is not JSON serializable`.** PyYAML coerces ISO date strings to `datetime.date` objects; the default JSON encoder doesn't handle them. — Recovery: added a `_safe()` coerce-to-`str` helper in `render_json` for non-JSON-primitive values. — Prevention: any Python skill that emits JSON from PyYAML-parsed frontmatter must coerce non-primitive values (dates, datetimes, custom YAML tags) at the JSON boundary. Test coverage: assert `json.loads(render_json(entries))` parses without raising.

**Background `bash scripts/test-all.sh 2>&1 | tail -3` truncated the suite summary line.** When chained after `bun test plugins/soleur/test/`, the combined output exceeded the buffer and the test-all summary line landed after the captured tail window. — Recovery: re-ran `test-all.sh` separately and used a Monitor + grep for "suites passed" to detect completion. — Prevention: for long pipeline runs whose summary lives in the last line, use `tail -20` not `tail -3`, or write the output to a file and grep for the suite-completion sentinel.

## Related Issues

- Plan file: `knowledge-base/project/plans/2026-05-12-feat-tech-debt-ledger-lifecycle-plan.md` (Sharp Edges section, line ~316: "Import parse helpers from `scripts/backfill-frontmatter.py:115-189` via `sys.path` insert.")
- Plan-precondition learning prior art: `knowledge-base/project/learnings/2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`
- Compound's `mutate_entry` body-MD5 assertion (review fix-inline, commit 51ba53dc) — addresses the surgical-mutation tradeoff above.
- PR #3645: feat-tech-debt-ledger-lifecycle
- Parent issue: #2723
