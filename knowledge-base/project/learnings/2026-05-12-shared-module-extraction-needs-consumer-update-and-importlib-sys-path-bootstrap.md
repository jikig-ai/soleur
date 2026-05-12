---
title: "Shared-module extraction: update consumers in same PR + self-bootstrap sys.path for importlib test harnesses"
date: 2026-05-12
category: best-practices
modules: [scripts, lint-rule-ids, lint-agents-rule-budget, _agents_md_sections]
issue: 3684
pr: 3697
tags: [shared-module, sys-path, importlib, ssot, multi-agent-review]
---

# Learning: shared-module extraction needs consumer update + importlib sys.path bootstrap

## Problem

PR #3697 added `scripts/_agents_md_sections.py` as a single source of truth for the `SECTIONS` constant used by `lint-rule-ids.py` and the new `lint-agents-rule-budget.py`. The initial implementation:

1. Created `_agents_md_sections.py` with the `SECTIONS` constant.
2. Made `lint-agents-rule-budget.py` import from it.
3. Left `lint-rule-ids.py:27` with its own local literal `SECTIONS = {...}`.

The new module's docstring claimed "used by `lint-rule-ids.py` and `lint-agents-rule-budget.py`" — false at merge time. Two writers, one source-of-truth claim: section drift becomes silent once a future rule taxonomy edit touches one definition and not the other.

A second issue surfaced when the consumer was patched: `tests/scripts/test_lint_rule_ids.py` loads the script via `importlib.util.spec_from_file_location`, which does NOT add the script's directory to `sys.path`. The new `from _agents_md_sections import SECTIONS` failed at module-load with `ModuleNotFoundError: No module named '_agents_md_sections'` — even though the file was a sibling on disk.

## Solution

Two changes, both required:

1. **Update the consumer in the same PR.** `lint-rule-ids.py:27` replaced the local literal with `from _agents_md_sections import SECTIONS`. The docstring claim is now true, and a `SECTIONS` edit propagates to both linters.

2. **Self-bootstrap `sys.path` in scripts that import a sibling helper.** Both linters now do:

   ```python
   _SCRIPTS_DIR = str(Path(__file__).parent)
   if _SCRIPTS_DIR not in sys.path:
       sys.path.insert(0, _SCRIPTS_DIR)

   from _agents_md_sections import SECTIONS
   ```

   This makes the import resolve under three load paths: CLI invocation (`python3 scripts/lint-rule-ids.py`, where CWD is the repo root), lefthook invocation (same shape, different CWD), and `importlib.util.spec_from_file_location` (test harness, no CWD-relative resolution).

## Key Insight

**Multi-agent review reliably catches incomplete shared-module migrations.** 4 of 10 agents in PR #3697's review (git-history, architecture, data-integrity, pattern-recognition, code-quality) independently flagged the same gap — the docstring promised SSOT, the consumer wasn't wired. Single-agent review tends to focus on the file under direct edit and miss the cross-file consistency claim. The cross-reconcile triad (see AGENTS.rest.md `rf-*`) inverts to the corroboration direction here: when 3+ agents independently surface the same shape, the fix is well-targeted (≤5 lines) and should land inline, not as a follow-up.

**`importlib.util.spec_from_file_location` does NOT populate `sys.path` from the loaded file's directory.** A script that imports `from <sibling>` works when run as `python3 path/to/script.py` (cwd-relative) but fails under importlib loading. If the codebase has importlib-based tests (or might gain them), every script that imports a sibling helper must self-bootstrap `sys.path.insert(0, str(Path(__file__).parent))` before the import.

## Tags
category: best-practices
module: scripts
related: 2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md, 2026-04-15-multi-agent-review-catches-bugs-tests-miss.md
