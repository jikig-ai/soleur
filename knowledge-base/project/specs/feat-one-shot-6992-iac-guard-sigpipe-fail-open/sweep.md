# `| grep -q` sweep — #6992 (AC-A3)

Measured 2026-07-27 on the target host: bash 5.3.9, GNU grep 3.12, default pipe
capacity 64 KiB (`/proc/sys/fs/pipe-max-size` = 1048576, but the *default*
per-pipe buffer is 65536, and that is the number that matters).

## The mechanism, stated correctly

Under `set -o pipefail`, `<producer> | grep -q P` reports **failure on a
successful match** whenever the producer still holds unwritten data at the
moment `grep -q` exits:

1. `grep -q` finds the match and exits immediately, closing the read end.
2. The producer's next (or blocked) `write()` gets `EPIPE` → `SIGPIPE` → 141.
3. `pipefail` propagates 141 as the **pipeline's** status.

So the pipeline says "no match" when the match is exactly what happened. It is
worse the *earlier* the match appears, because an early match is what makes
`grep -q` exit while the producer is still writing.

## The discriminating axis is capacity, not producer class

The plan this work started from asserted that bash builtins "never raise the
race" and that external producers "race at every size including 1 KB". **Both
halves are refuted by measurement**, and the corrected axis is simply *does the
producer still have data to write when the reader goes away*:

| Producer | Input | False failures |
|---|---|---|
| builtin `echo "$var"` | 4–64 KB | 0/30 |
| builtin `echo "$var"` | 65 KB | 1/30 |
| builtin `echo "$var"` | 66 KB | 10/30 |
| builtin `echo "$var"` | 72 KB | 23/30 |
| builtin `echo "$var"` | 96 KB | 25/30 |
| builtin `echo "$var"` | ≥128 KB | **30/30** |
| `cat <file>` | 1 KB – 512 KB | 0/30 |
| `yes` (unbounded) | ∞ | 3/3 |

A builtin `echo` writes the whole string in one `write()`. Below the 64 KiB
pipe buffer that write completes into the buffer and the producer exits before
`grep` ever closes anything — hence 0/30. Above it the write blocks, `grep -q`
exits on the match, and the blocked write returns `EPIPE`. The onset at exactly
65 KB is the pipe buffer, not a coincidence.

`cat` never raced here in ~250 trials at any size. That is a timing property of
how `cat` and `grep` interleave, not a guarantee — so command producers were
still converted, using `grep -c` rather than a herestring.

## End-to-end effect on the guard the issue names

`.claude/hooks/iac-plan-write-guard.sh`, real hook, real payload, body whose
first line is `ssh root@example.com`:

| body | pre-fix DENY/30 | post-fix DENY/30 |
|---|---|---|
| 4 KB | 30 | 30 |
| 50 KB | 22 | 30 |
| 64 KB | 17 | 30 |
| 72 KB | 12 | 30 |
| 128 KB | **0** | 30 |
| 512 KB | **0** | 30 |
| 2048 KB | **0** | 30 |

At ≥128 KB the guard **never** blocked a plan containing an operator-SSH step.
38 of the repo's 1754 plan files currently exceed 64 KiB, including three
written this month at 93–113 KB.

The same race hit the ack check in the opposite direction: a **valid** acked
50 KB plan was denied 22/30. That is the reported 9-deny/3-allow symptom, and
it is the SIGPIPE race — not, as the plan concluded, the Edit-scope issue.
Edit-scope blindness is a real second defect (confirmed: ack on disk + violation
in `new_string` → deny) but it is deterministic and cannot produce a ratio.

## Direction taxonomy

The third shape is the one that hides, and it is common in this repo:

| Shape | On race | Direction |
|---|---|---|
| `X \| grep -q P && deny` | `deny` skipped | **FAILS OPEN** |
| `if X \| grep -q P; then allow` | bypass skipped | fails closed |
| `if ! X \| grep -q P; then <early-exit>` | `!` inverts the false negative, the early exit fires, **the gate skips its own check** | **FAILS OPEN** |

## Disposition

### Fixed in this PR — `.claude/hooks/` (51 sites, 21 files)

Zero `| grep -q` remain in non-test hook code. Variable producers became
herestrings; command producers became `grep -c … -gt 0`. All 34 hook suites
pass byte-identically to the pre-conversion baseline.

The five sites that needed hand conversion, with direction:

| Site | Direction | Consequence of the race |
|---|---|---|
| `skill-context-queries.sh:77` | **FAILS OPEN** | `awk … \| grep -q … \|\| exit 0` — silently disables `context_queries` for the skills that declare them |
| `pre-merge-rebase.sh:153` | **FAILS OPEN** | an open `code-review` todo reads as absent |
| `guardrails.sh:341` | fails closed | denies a `gh issue create` that *did* carry `--milestone` |
| `skill-security-scan.sh:46` | fails closed | denies a HIGH-RISK skill whose override artifact **is** staged |
| `brand-hex-commit-gate.sh:159` | fails closed | a CSS file that does define a token reads as not defining one |

`ship-soak-followthrough-gate.sh` has no test suite of its own; its two sites
were verified by `bash -n` and by reading the surrounding control flow.

### Sweep-pattern footnote — the first pattern under-counted

The obvious pattern `\| *grep +-q` (the one the issue proposes) matches only a
`-q` written immediately after the dash. It **misses** `-Eq`, `-iq`, `-Fq`, and
every other cluster where `q` is not the first flag letter. Two live sites in
`background-poll-prefer-monitor.sh` survived the first conversion pass because
of this and were caught only by the drift guard, which uses
`\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q`.

Anyone re-running this sweep should use the wide form. The narrow form
under-reports by roughly 2% in `.claude/hooks/` and by 1 and 5 sites in
`scripts/` and `plugins/` respectively.

### Not fixed here — tracked

| Scope | Non-test sites | Why deferred |
|---|---|---|
| `scripts/**/*.sh` | 51 | Mostly one-shot follow-through scripts and operator tooling. Real but lower consequence than a policy gate, and each needs its own reading. |
| `plugins/**/*.sh` | 64 | Same. |
| test files (all trees) | 160 | A racing assertion in a **test** is its own hazard — a negative assertion (`! … \| grep -q …`) passes vacuously — but converting test harnesses wholesale in a bug-fix PR risks masking real failures. |

A tracking issue is filed at ship time covering all three rows.

## Vacuity warning for anyone re-running these measurements

In a Claude Code agent Bash session, `grep` resolves to a **ugrep shim shell
function**, and ugrep's `-q` drains its input. The race is therefore invisible
to anyone testing by hand in an agent session — it measures 0/N and looks
refuted. That is very likely how this defect class survived earlier review, and
it is why the plan's own measurements came back wrong.

Re-run anything here under a pinned binary:

```bash
env -i PATH=/usr/bin:/bin bash --noprofile --norc <script>
```

`.claude/hooks/iac-plan-write-guard.test.sh` asserts this as T5 and fails loudly
rather than passing vacuously.
