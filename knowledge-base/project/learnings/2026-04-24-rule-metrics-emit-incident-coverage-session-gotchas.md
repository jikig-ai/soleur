---
title: rule-metrics emit_incident coverage — session gotchas
date: 2026-04-24
category: best-practices
module: .claude/hooks + scripts/rule-metrics-aggregate.sh
issue: 2866
pr: TBD
tags: [telemetry, flock, schema-evolution, cross-runtime, tdd-test-fixtures]
---

# Learning: rule-metrics emit_incident coverage (hooks + skills)

Closed the telemetry gap that produced `hit_count=0, first_seen=null` for
every AGENTS.md rule. Three silent hooks (`pre-merge-rebase.sh`,
`docs-cli-verification.sh`, `security_reminder_hook.py`) and 8 skill-enforced
rules (9 emission points) now write incident lines; the aggregator adds
`applied_count` / `warn_count` / `fire_count` and gates on
`orphan_rule_ids == []` via exit 5.

This file captures the non-obvious gotchas surfaced during implementation and
review — the things that will bite the next schema-evolution PR on this
telemetry surface.

## Gotcha 1 — Cross-runtime `flock` interlock needs physical-path canonicalization

`emit_incident` exists in two runtimes: bash (`.claude/hooks/lib/incidents.sh`,
all shell hooks) and Python (inlined in `.claude/hooks/security_reminder_hook.py`,
chosen over subprocess-shellout per plan ADR-3 for PreToolUse latency). Both
acquire `LOCK_EX` on the same file via `flock`/`fcntl.flock`. **`flock` locks
are per-inode, not per-path.**

Initial implementation used:

- Bash: `(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)` —
  `pwd` defaults to `pwd -L` (logical, preserves symlinks).
- Python: `os.path.abspath(os.path.join(_HOOK_DIR, "..", ".."))` — abspath
  normalizes `..` segments but does NOT follow symlinks.

If `.claude/` is symlinked into the project (common in plugin installs from
`~/.claude/plugins/soleur/...`), the two emitters compute the root to different
physical paths — so they open different inodes — so their `flock` calls do
not interlock — so concurrent writes interleave and the aggregator's
`jq -R 'fromjson?'` silently drops torn lines as malformed (bad-lines warn
only, no loud failure).

**Fix:** both sides must canonicalize to the physical path.

- Bash: `(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd -P)`.
- Python: `os.path.dirname(os.path.realpath(__file__))` for `_HOOK_DIR`, and
  `os.path.realpath(...)` on the final path.

**Prevention generalized:** when two runtimes share an inode via path-based
locking, the path computation on both sides must canonicalize through
symlinks. `abspath` / logical `pwd` are not sufficient.

## Gotcha 2 — `PIPE_BUF` is a pipe constant, not a regular-file constant

The initial Python emitter comment claimed "JSONL lines are ~200 bytes, well
under PIPE_BUF (4096) so the O_APPEND write is atomic on Linux even without
the lock — the lock is belt-and-suspenders." This is wrong.

`PIPE_BUF` (`<limits.h>`, 4096 on Linux) bounds atomic `write(2)` payloads for
**pipes and FIFOs**. For regular files opened `O_APPEND`, POSIX guarantees
only that the write-cursor is positioned at end-of-file atomically — not that
the `write(2)` payload itself is atomic against concurrent writers. Atomic
append on regular files holds only up to the filesystem's block size and only
when the kernel issues the write as a single syscall.

**Fix:** the flock is load-bearing, not belt-and-suspenders. Added a short-
write-safe loop on the Python side (`memoryview` + loop over `os.write` return
values) and capped `cmd` at 1024 bytes on both sides so a multi-line
`gh pr merge --body "$(cat body.md)"` can't push a line past the block-size
boundary.

**Prevention:** don't generalize POSIX IPC atomicity constants to file I/O.
Any multi-writer append to a regular file needs either `flock` or `O_DIRECT`
discipline — not faith in `PIPE_BUF`.

## Gotcha 3 — Schema field addition silently breaks pre-existing test fixtures

The plan renamed the `rule-prune.sh` predicate from `hit_count == 0` to
`fire_count == 0`. The primary test I wrote for the aggregator passed. The
PR fully passed its new test suite. But an orthogonal pre-existing test —
`tests/commands/test-sync-rule-prune.sh` — regressed silently.

Cause: the fixture hard-coded the v1 shape (`hit_count:0, bypass_count:0, ...`)
with no `fire_count` field. `jq`'s `select(.fire_count == 0)` evaluates
`null == 0` as `false`, so every fixture rule was excluded from the candidate
list. Six of seven sub-tests went red.

This was not caught by the TDD loop on the primary feature — the rename was
a schema addition, not a removal, and the primary test used its own fresh
fixtures. It was caught by the architecture-strategist review agent grepping
`rule-metrics.json`-related accessors across the repo.

**Fix:** regenerate the fixture to include all five counter fields
(`hit_count / bypass_count / applied_count / warn_count / fire_count`) and the
`orphan_rule_ids` summary field. Also updated the `rule-prune.sh` "No prune
candidates" stderr line to say `fire_count=0` for consistency.

**Prevention:** when renaming or adding a field to a shared-artifact schema,
grep for existing fixtures on the old shape — not just the reader code. A
`select(.missing == 0)` expression over a null field is a silent-failure mode;
no exception, no warning, just zero rows. Candidate AGENTS.md addition after
this file plus #2866 ships:

> When evolving a schema consumed by a `jq select(...)` predicate, grep for
> every test/CI fixture using the old field set — `null == <number>` is
> false and silently drops rows.

(Not proposed as a rule yet — one data point; file an issue-in-compound if
it recurs.)

## Gotcha 4 — Hard-coded rule-text prefixes drift from AGENTS.md

ADR-2 prescribed snippet form:

```bash
source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && \
  emit_incident <rule-id> applied "<first-50-chars-of-rule-text>"
```

Two of the nine snippets (compound Step 8, ship Phase 5.5 entry) shipped
with prefixes that dropped the backticks present in the AGENTS.md rule text
(`` `**Why:**` ``, `` `/ship` ``). The aggregator joins on `rule_id`, so the
counts were correct — but the forensic `rule_text_prefix` in raw incident
lines diverged from the aggregated `rule_text_prefix` in `rule-metrics.json`.

Caught by `code-quality-analyst` doing a character-exact cross-reference
against the awk prefix extraction at `scripts/rule-metrics-aggregate.sh:57-65`.

**Fix:** switched the two mismatched snippets to single-quoted bash strings
so the backticks survive verbatim. Confirmed with the aggregator's parsing
rule — take the bullet text AFTER stripping `- ` prefix and `[id: ...]`
suffix, then first 50 codepoints.

**Prevention candidate:** the snippet form in ADR-2 could include a sentence
reminding authors that backticks, underscores, and other markdown in AGENTS.md
bullet text count toward the 50-char prefix. Whether to cement this as a
skill instruction depends on whether it recurs; for now, the inline comment
in the 9 snippets documents the convention.

## Gotcha 5 — `grep '^[[:space:]]*source.*emit_incident' ...` does not match
   multi-line snippets

ADR-4's acceptance-criterion grep was:

```bash
grep -c '^[[:space:]]*source.*emit_incident' \
  plugins/soleur/skills/{brainstorm,ship,plan,deepen-plan,work,compound}/SKILL.md
# Expect: total 9
```

My implementation used the ADR-2 two-line snippet form (`source ... && \` on
line 1, `emit_incident ...` on line 2). The `source.*emit_incident` pattern
requires both tokens on the same physical line. The grep returned 0 across
all 6 files.

**Fix:** verified the count with `grep -c 'emit_incident .* applied'` instead
(which matches the second line of each snippet, once per snippet, 9 total).

**Prevention:** when a plan prescribes an acceptance-criterion grep, either
(a) adjust the grep to the snippet form, or (b) collapse the snippet to a
single line. I chose (a) because the snippet form is the thing that affects
agent execution reliability, and a single-line emit_incident call with a
full `$(...)` substitution is 150+ characters and harder to read.

## Session errors inventory (for the record)

| # | Error | Recovery | Prevention |
|---|---|---|---|
| 1 | `INCIDENTS_REPO_ROOT="$incidents" printf ... \| "$HOOK"` — env-var attached to `printf`, not `$HOOK` | Move env-var to immediately precede `$HOOK` on right side of pipe | Visible at first test run; learning only |
| 2 | `wc -l < "$jsonl"` failed when file did not exist yet | Guard reads with `[[ -f "$jsonl" ]]` | Visible error; learning only |
| 3 | ADR-4 grep pattern returned 0 across all 6 files | Swap to `'emit_incident .* applied'` pattern | See Gotcha 5 |
| 4 | 2/9 SKILL.md snippet prefixes dropped backticks | Switch to single-quoted bash strings | See Gotcha 4 |
| 5 | P1 regression in `test-sync-rule-prune.sh` fixture | Add `fire_count` + sibling counters to fixture | See Gotcha 3 — candidate rule |
| 6 | Python/bash `flock` inode divergence under symlinks | `realpath` / `pwd -P` on both sides | See Gotcha 1 |
| 7 | PIPE_BUF claim in comment was wrong for regular files | Remove claim, cap cmd at 1024B, short-write loop | See Gotcha 2 |

None of the seven warranted a new AGENTS.md rule at this point — five were
self-discoverable at runtime (visible test failures or grep returns), and
two (Gotchas 1 and 3) are narrow enough that a single recurrence would be
the signal to promote.

## References

- Plan: `knowledge-base/project/plans/2026-04-24-chore-rule-metrics-emit-incident-coverage-plan.md`
- Spec: `knowledge-base/project/specs/feat-one-shot-2866-rule-metrics-emit-incident-coverage/spec.md`
- Prior learning: `knowledge-base/project/learnings/2026-04-15-rule-metrics-aggregator-pr-pattern-session-gotchas.md`
- Aggregator: `scripts/rule-metrics-aggregate.sh:109-160, :211-225`
- Emitter library: `.claude/hooks/lib/incidents.sh:16-28`
- Python emitter: `.claude/hooks/security_reminder_hook.py:35-90`
- Test: `scripts/rule-metrics-aggregate.test.sh`, `.claude/hooks/pre-merge-rebase.test.sh`
- Review agents consulted: `security-sentinel` (P2), `code-quality-analyst` (High + Medium), `architecture-strategist` (P1)
