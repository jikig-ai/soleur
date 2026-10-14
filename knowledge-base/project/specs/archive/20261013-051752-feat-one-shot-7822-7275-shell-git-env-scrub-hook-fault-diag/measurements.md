# Measurements — #7275 classifier, and the #7822/#7835 sweep set

Every number here was re-derived in the implementing session against the rebased
tree. Nothing is inherited from the plan; where a plan figure differs, both are
shown and the difference is explained rather than silently resolved.

Machine of record: bash 5.3.9(1)-release, jq 1.8.1, x86_64 Linux.

---

## Phase 0.1 — `PIPESTATUS` through a command substitution (the #7275 root cause)

The issue reported that jq rc 5 and rc 0 were both labelled `unparseable`. The
mechanism is worse than that: the return code was **never read at all**.

Probe, mirroring the exact shape in `.claude/hooks/lib/hook-input.sh`:

```
raw="$(printf '%s' "$input" | jq -j '.' 2>/dev/null; printf 'X')"
jq_rc=${PIPESTATUS[1]:-0}
```

| reading | value |
|---|---|
| `PIPESTATUS` after the assignment | `(0)` — **length 1** |
| `PIPESTATUS[1]` | unset, so `:-0` fires |
| `jq_rc` as actually read | `0`, unconditionally |

`PIPESTATUS` on that line describes the **assignment**, not the pipeline inside
the substitution. jq's real codes, measured separately on the same inputs:

| input | jq's true rc | pre-fix `jq_rc` | pre-fix reason |
|---|---|---|---|
| malformed document | 5 | 0 | `unparseable` |
| empty stdin | 0 | 0 | `unparseable` |
| our program fails to compile | 3 | 0 | `unparseable` |

So `if (( jq_rc == 3 ))` was **dead code**, and the row the design most wanted
kept separate — *our own hook is broken* — was reported as the model having sent
junk. `hook-input.sh`'s own comment says that collapse "is how a broken gate
hides"; the comment described a discriminator the code never read.

## Phase 0.1b — why the trailing `printf` survives `set -e`

Load-bearing, because the fix depends on a command running **after** a failing
pipeline inside the substitution.

| condition | `$-` inside the substitution | trailing `printf` runs? |
|---|---|---|
| `set -euo pipefail` | no `e` | yes |
| `set -euo pipefail` + `shopt -s inherit_errexit` | `e` present | yes |

Measured both ways. The shipped form still uses `|| _hi_rc=$?` rather than
`; _hi_rc=$?`: as the right operand of `||` the pipeline is exempt from errexit
**by the shell grammar**, which is a language guarantee, where the table above is
an observation about one bash build. Correctness should not be a property of the
caller's shopts.

## Phase 0.2 — strip-before-split, on the candidate design

Candidate: capture jq's rc inside the substitution, emit it after an
unconditional RS, strip it before the `IFS` split.

| payload | fields | rc | classified |
|---|---|---|---|
| happy envelope | 6 | 0 | *(parses)* |
| empty stdin | 0 | 0 | `empty` |
| `garbage {{` | 0 | 5 | `baddoc` |
| `null` root | 6 | 0 | `nonobject` |
| valid envelope + trailing garbage | 6 | 5 | `baddoc` |
| value carrying an RS | 7 | 0 | `separator` |

Two rows are the ones the old code got wrong beyond the issue's own report:

- **`null` root** returned **0** with all five fields empty — a silent total
  disarm, no incident row, no ask, every anchored guard matching an empty
  command.
- **valid envelope + trailing garbage** emitted a complete six-field record
  while jq exited 5. The count-only check accepted it as a clean parse, so the
  hook ran its guards against a document jq had already rejected.

The rejected alternative — append the rc as a further RS-delimited field and
split afterwards — makes the happy path **seven** fields and, because the
appended field is always present, makes the zero-field arm structurally
unreachable. Every payload fault would then be misreported as `internal`: the
exact inverse of the defect being fixed.

## Phase 0.4 — the aggregator absorbs the new reason ids with no code change

`scripts/rule-metrics-aggregate.sh` selects by **prefix**
(`startswith("hook-input-")`), not by an enum roster, so the split needed no
behavioural change there. Run against a **copy** under `INCIDENTS_REPO_ROOT`
(never the real root — it writes before it rejects):

```
AGG_EXIT=0
{"orphans":[],"faults":4,"reasons":{"empty":1,"baddoc":1,"nonobject":1,"internal":1}}
```

`internal` rather than `internal:rc3` confirms `hook_input_report`'s
`${reason%%:*}` keying: the detail rides along without creating a new
aggregation key. The only edits in that file are its comment roster and one test
fixture id — documentation, as the plan specified.

## Phase 0.5 — collision state at implementation time

| ref | state | bearing |
|---|---|---|
| #7822 | OPEN | work target (PR 2) |
| #7835 | OPEN | work target (PR 2) |
| #7275 | OPEN | work target (PR 1) |
| #7849 | OPEN | owns the sweep's exit condition |
| PR #7879 | **OPEN** | edits `scripts/test-all.sh`, `plugins/soleur/test/test-helpers.sh`, `apps/web-platform/infra/workspaces-luks-loopback.test.sh` — all three are do-not-touch here |
| #7942 | OPEN | **out of scope**, operator-authorised; see `session-state.md` |

## Phase 0.3 — the sweep set, and why it is not the plan's number

Predicate as re-derived here: a tracked `*.test.sh` that runs `git init` **and**
a write verb (`git commit` / `git add`), carrying none of a `test-helpers.sh`
source, an `exit 97` tripwire, or a `GIT_`-prefix / `env -i` scrub.

That returns **30** files repo-wide. The plan says the sweep it owes is **five**.
Both are correct and they measure different sets:

- The plan scopes to **#7849's named exit condition**, which is
  `plugins/soleur/test/*.test.sh` reaching full `test-helpers.sh` adoption — 3
  files under this predicate (`gitleaks-merge-commit`, `harvest-debt`,
  `roadmap-reconcile`).
- The plan's other two members (`fixture-dir-operand-assert`, `proc`) do not
  create a committing git fixture at all. They belong to the **vacuity** class
  (a case asserting "this directory is not a repository", which inverts under an
  inherited `GIT_DIR` and passes while proving nothing) — Phase A1, not the
  Phase A2 sweep.
- The remaining 27 are outside #7849's stated condition, and 7 of them sit under
  `.claude/hooks/`, which is where #7822 says the exposure is highest.

**This is unreconciled and PR 2 must reconcile it before editing anything.** It
is recorded rather than resolved here because PR 1 touches none of these files.
The honest statement is that the "five" is a scoped count, the "30" is a
repo-wide count, and neither is wrong — but a sweep that ships against the
smaller number should say which condition it is discharging.
