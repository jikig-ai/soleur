# Phase 1 — precondition evidence (measured, not argued)

All probes run 2026-08-03 in an **isolated** `claude -p` against a throwaway
`--settings` file in a temp dir. The live session's settings were never touched.

Harness: a PreToolUse `Bash` hook that logs raw stdin and emits `updatedInput`
carrying **only** `.command`; a PostToolUse `Bash` hook that logs the raw stdin
it receives. PostToolUse sees the *effective* `tool_input`, which is what makes
the merge-vs-replace question directly observable rather than inferred.

`claude` 2.1.220. GNU grep 3.12.

| # | Precondition | Result |
|---|---|---|
| 1.1 | `updatedInput` applies with no `permissionDecision` | ✅ applies |
| 1.2 | A sibling `deny` still beats `updatedInput` | ✅ deny wins |
| 1.3 | Does `updatedInput` **merge** or **replace** `tool_input`? | ⚠️ **REPLACES** |
| 1.4 | Is the rewritten command re-submitted to PreToolUse? | ✅ **no** re-entrancy |
| 1.5 | GNU grep accepts the injected flags; still errors on `-G` + `-E` | ✅ both |

## 1.1 — `updatedInput` applies

Hook emitted `updatedInput` with **no** `permissionDecision`; the executed
command was the rewritten one. Confirmed by the PostToolUse `tool_response`:

```json
{"stdout":"REWRITTEN","stderr":"","interrupted":false,...}
```

## 1.3 — `updatedInput` REPLACES `tool_input` wholesale

This is the load-bearing one (Kieran P0-5) and it is confirmed by execution.

Submitted (PreToolUse stdin):

```json
{"tool_input":{"command":"sleep 1; echo ORIGINAL","timeout":45000,
               "description":"probe marker","run_in_background":true}}
```

Hook emitted `updatedInput: {"command":"echo REWRITTEN"}`.

Received (PostToolUse stdin):

```json
{"tool_input":{"command":"echo REWRITTEN"}}
```

`timeout`, `description` and `run_in_background` were **all dropped**. The
command additionally ran in the **foreground** — stdout was returned inline with
no background task ID — independently confirming `run_in_background: true` was
lost rather than merely absent from the log.

**Consequence, binding on the implementation:** the envelope MUST be built from
the whole `tool_input` (`.tool_input | .command = $new`), never from `.command`
alone. Emitting only `.command` silently strips `timeout`,
`run_in_background`, `description` and `sandbox` from every rewritten call.

## 1.4 — no re-entrancy

`wc -l < pre.log` = **1** for one Bash call. The rewritten command is not
re-submitted to PreToolUse, so the idempotency sentinel (AC11) is defense in
depth against a future runtime change, not a live requirement.

## 1.5 — GNU grep flag acceptance

```
$ command grep -I --exclude-dir=.git ... --exclude-dir=.next -rn hello sub
sub/a.txt:1:hello                                                    rc=0
$ printf 'hello\n' | command grep -I --exclude-dir=.git hello
hello                                                                rc=0
$ command grep -I --exclude-dir=.git -G -E hello sub/a.txt
grep: conflicting matchers specified                                 rc=2
```

The injected set is accepted both recursively and on a non-recursive stdin
read, and — because the injected set contains no `-G` — a user's own `-G` + `-E`
still conflicts exactly as it does today.

## D3 re-measurement (the plan's 12.9× claim)

Plan §Research Reconciliation justified shipping the three heavy build-dir
excludes on a measured 423 ms → 5,446 ms → 590 ms sequence (12.9×). Re-derived
on this repo (101,104 files, 87,988 of them under `node_modules`), 5 interleaved
reps, recursive `grep -rl`:

| arm | reps (ms) | steady-state |
|---|---|---|
| shim excludes only | 13829*, 3477, 3737, 3816, 3354 | ~3,600 ms |
| + node_modules, dist, .next | 577, 573, 573, 524, 734 | ~590 ms |

`*` cold page cache; excluded from the steady-state figure.

**~6.0×, not 12.9×.** The ~3,000 ms effect is ~13× the ~230 ms run-to-run
spread, so the comparison is decisively resolved and the sign is physically
correct (strictly less work is faster). The plan's `590 ms` "with excludes"
figure reproduces exactly; only the baseline differs, which is a
repo/machine-state difference. **D3 stands; the decision is unchanged.**

## Divergence probe — `--exclude-dir` vs an explicitly targeted directory

Not in the plan; found while implementing. `--exclude-dir=X` suppresses results
when the explicit target argument's **own basename** is exactly `X`:

| form | result |
|---|---|
| `grep -r PAT node_modules` | ❌ **empty**, rc=1 |
| `grep -r PAT node_modules/` (trailing slash) | ✅ works |
| `grep -r PAT node_modules/pkg` | ✅ works |
| `grep -r PAT node_modules/pkg/deep` | ✅ works |
| `grep PAT node_modules/pkg/a.txt` (file) | ✅ works |
| `grep -r PAT proj` (excluded dir nested below) | ✅ works, excluded subtree skipped |

So the regression is exactly one narrow form: a bare, trailing-slash-less
directory argument whose basename is one of the excluded names. For the six
shim excludes (`.git`, `.svn`, `.hg`, `.bzr`, `.jj`, `.sl`) this is **already
today's behavior** and therefore not a regression. It is new only for the three
build dirs this change adds (`node_modules`, `dist`, `.next`), and the
workaround is a trailing slash. Enumerated as an accepted divergence in ADR-162.
