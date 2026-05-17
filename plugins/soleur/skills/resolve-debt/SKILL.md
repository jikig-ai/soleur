---
name: resolve-debt
description: "This skill should be used when triaging or closing open entries in the technical-debt ledger. Lists open debt, walks the operator through closing one with a linked GitHub issue."
---

# Resolve Tech-Debt Ledger Entries

Operator-facing surface for the `knowledge-base/project/learnings/technical-debt/` ledger. The ledger is populated reactively by `/soleur:compound`; this skill is the read + close half of the loop.

Four modes:

- **`--list`** — print a deterministic markdown table of open entries (severity desc, then date asc). Stdout only, no prompts. Pair with `--json` for agent / `/loop` composition.
- **`--close N --status S [--linked-issue N]`** — non-interactive close. Bypasses prompts. Reuses the same validation surface as interactive mode (status enum, linked-issue range, fixture-path refusal, `gh issue view`, atomic mutation, body MD5 check). Index `N` follows the `--list` ordering.
- **interactive (default)** — list, prompt for entry selection, prompt for new status + `linked_issue`, mutate the entry's frontmatter atomically, print the diff. Does NOT auto-commit; the operator commits on whatever branch they are on.
- **`--no-verify`** — modifier on interactive / `--close`: skip the `gh issue view <N>` round-trip. Use offline or when `gh` is unavailable.

The skill never calls `git commit` or `git push`. Recovery from a wrong close is `git checkout -- <file>` (pre-commit) or `git revert` (post-commit).

## Commands

### `list`

```bash
python3 plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py --list
```

Walks `knowledge-base/project/learnings/technical-debt/` (skips `archive/`). For each `.md` file, parses frontmatter via the `parse_frontmatter` helper from the repo-root `scripts/` directory (file: `frontmatter_lib.py`). Files with parse failures emit a stderr warning naming the file and are skipped — `--list` does not crash on malformed frontmatter.

Filters to `status == open`. Sorts by `severity` desc (`high > medium > low > unset`), then `date` asc (oldest first).

Output columns: `idx | file | date | severity | component-or-category | title`.

Empty state: `No open debt entries.` exit 0.

### `close` (interactive default)

```bash
python3 plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py
```

1. Display the same table as `--list`.
2. Prompt: `Select entry (1..N) or q to quit:`. Out-of-range or non-numeric → re-prompt up to 3 attempts, then exit 2.
3. Prompt: `Status (resolved | wont-fix):`. Enum reject → re-prompt.
4. If `resolved`: prompt `linked_issue (integer, e.g., 2723):`. Validated by `int()` parse (rejects strings, floats, shell metachars by construction) + range-check `1 <= n <= 9_999_999`. The bounds reject shell-metachar injection; the digit-count cap is incidental, not load-bearing.
5. Unless `--no-verify`: `gh issue view <N> --json state,title` with 5-second timeout. Non-zero exit prints `gh issue view failed (<reason>). Re-invoke with --no-verify to skip validation.` to stderr and exits 1. There is no closed-state warning branch — if the operator typed the number, they meant it.
6. Mutate atomically: serialize the new frontmatter to a tempfile in the same directory, then `os.replace`. SIGINT before `os.replace` leaves the original file untouched.
7. Print `git diff -- <file>` to stdout. Print `Diff above. Review and commit when ready. To undo: git checkout -- <file>. No auto-commit by design.` to stderr. Exit 0.

### `help`

```bash
python3 plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py --help
```

Prints a usage block enumerating the three modes; exit 0.

## Frontmatter Contract

- `status`: required, enum `open | resolved | wont-fix`. Default `open` for new entries (set by `/soleur:compound`'s `resolution-template.md`).
- `linked_issue`: required when `status: resolved`; optional when `status: wont-fix`; forbidden when `status: open`. Stored as a YAML integer, no `#` prefix.

Why `status` instead of "absence-of-`linked_issue`": `wont-fix` is the load-bearing discriminator of record. Without `status`, there is no way to express "we know about this debt and have decided not to fix it." Future schema simplification must preserve `status` for this reason.

See [knowledge-base/project/learnings/technical-debt/README.md](../../../../knowledge-base/project/learnings/technical-debt/README.md) for the full contract.

## Sharp Edges

- **Frontmatter parsing goes through the shared `parse_frontmatter` helper in the repo-root `scripts/` directory** (file: `frontmatter_lib.py`), imported via `sys.path.insert`. The `backfill-frontmatter.py` one-shot migration in the same directory imports the same module — single source of truth. Do not re-implement YAML mutation in shell — `sed` range patterns match all `---` blocks and ledger bodies may contain horizontal-rule `---`.
- **No auto-commit by design.** The skill prints the diff and stops. Ledger commits land on whatever branch the operator is on; auto-commit would risk wrong-branch writes.
- **Archive is frozen.** The walker skips `knowledge-base/project/learnings/technical-debt/archive/`. Closed-out historical entries live there and are not re-surfaced.
- **`gh issue view` failure is a hard stop.** No silent fallback to skip validation. The error message names the failure mode and points at `--no-verify` for the operator to opt in explicitly.
- **Two schema shapes coexist.** Legacy entries use `module / problem_type / component / tags / severity`; current entries use `title / category / tags / severity`. The skill preserves whichever shape it finds. Schema unification is a separate follow-up.

## Non-Goals

- `--undo-close` flag — recovery is `git checkout -- <file>` (pre-commit) or `git revert` (post-commit).
- Bulk-resolve.
- Severity filter (`--severity high`).
- Scheduled scanner / re-surfacing of stale open entries — deferred to issue #3650 (Spec B).
