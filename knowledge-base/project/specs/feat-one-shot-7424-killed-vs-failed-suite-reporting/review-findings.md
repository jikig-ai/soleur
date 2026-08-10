# Review findings ledger — #7424

Two panels ran against this plan: a 5-reviewer plan-review panel (DHH, Kieran, code-simplicity,
CTO devex, strong-model advisor) and a 5-agent deepen-plan panel (architecture-strategist,
test-design-reviewer, spec-flow-analyzer, security-sentinel, git-history-analyzer).

Every finding below was **independently verified by measurement** before being accepted — several
agent claims were themselves wrong and are marked as such. Applied findings are folded into the
plan; the two that touch operator-stated scope live in `decision-challenges.md`.

## Verified and applied — P0

| # | Source | Finding | Measurement that confirmed it |
| --- | --- | --- | --- |
| P0-a | kieran | `kill -l` is not a validity oracle: `kill -l 0`→`EXIT`, `kill -l 32`/`33`→rc 0 with **empty** output, `kill -l 143`→`TERM` (masks >64). rc 128/160/161 would have classified `killed`, the latter rendering a blank `SIG`. | ran all of `kill -l {0,15,31,32,33,34,64,65,143}` |
| P0-b | kieran | The classification `case` had no `ok)`/`*)` arm → an unrecognized class incremented neither counter and counted as **passed**. | executed the case with `status=killed` and the arm removed |
| P0-c | architecture | The classifier fails **open** on a non-numeric rc: `(( rc == 0 ))` with `""` or `" "` evaluates **true** → returns `ok`. The one class that increments no counter and emits no warning. | `sec ""` → `ok`; `sec " "` → `ok` |
| P0-d | dhh | The sandbox suite does `cp "$TARGET" "$out"` — a **single-file** copy — so a sourced `scripts/lib/` classifier would be absent under test and the degradation stub would silently defeat every KILLED assertion. | read `test-all-infra-coverage-notice.test.sh` |
| P0-e | architecture | `tc_siblings [mode]` **cannot express** the requirement: 4.3's cancellation is cross-bucket, so a mode parameter forces either two non-atomic `/proc` walks (the defect 4.3 forbids) or a third return-shape mode. | logic + the 22 zero-arg call sites in the existing suite |
| P0-f | test-design | Mutation arm A7 was mis-specified: removing the `killed)` arm makes the class fall to `*)` → counted FAILED → exit **1**, not 0. The arm reds for a reason it does not describe, so AC7 was not a proof. | executed the mutated case |
| P0-g | spec-flow | `test-fix-loop`'s **iteration arithmetic** is non-monotonic under KILLED: a suite that FAILED then is KILLED lowers the parsed count (reads as improvement); when it completes again the count jumps → **Regression** → `git reset --hard HEAD` **discards real fixes**. Four call sites, not one. | read `test-fix-loop/SKILL.md` lines 54, 71-75, 102-105 |
| P0-h | spec-flow | The monitor's `### Actions required` block is **hardcoded across all arms** — the operator gets an issue titled "terminated" whose only actionable text says "identify the commit … revert the breaking change". | read `main-health-monitor.yml` |
| P0-i | security | The monitor's greps run over a `tee`'d file containing arbitrary suite stdout, and **the new suite's own diagnostic dump re-emits `[KILLED]` at column 0** into that capture — self-inflicting, not merely adversarial. | read the `tee` invocations + the precedent suite's dump idiom |
| P0-j | cto | `test-fix-loop` terminates on **parsed output**, so a killed-only run made it report success — an agent-level **false green** the plan wrongly called "unreachable by construction". | read its termination table |

## Verified and applied — P1

| # | Source | Finding |
| --- | --- | --- |
| P1-a | architecture | The breakdown line **displaces the terminal marker** as the last `===` line, contradicting `work/SKILL.md`'s measured "match the runner's LAST emitted line" rule (#6750). Fix: emit the breakdown **before** the marker. |
| P1-b | kieran | `killed=0` initialization and the `exit 3` arm were never actually written; under `set -u` an uninitialized `killed` aborts **after** the marker and **before** the exit arm → exit 0 on a failing run. |
| P1-c | kieran / security | `[KILLED]` lines never reached the issue **body** — the existing grep feeds both `HAS_FAIL_MARKER` and `SUMMARY`, so a killed-only run named no suite (reproducing #7374, whose body carries **zero** marker lines — measured). |
| P1-d | kieran | The "six banned constructions" list was an incomplete paraphrase of the live `CLAIM` regex (missing 5 phrases, 2 verbs, 3 adjectives, and the fact that the adjective group is optional). Scope also corrected: `DIRS` covers `.github/workflows`, so AC10 gates the workflow LEDE too. |
| P1-e | kieran | R4 understated the limit: **any** wrapper that outlives its killed child absorbs the signal — including the **webplat** `npm run test:ci` registration, the most plausible OOM victim. |
| P1-f | architecture | `work/SKILL.md` **§663** — the primary agent-facing statement of the runner's exit semantics, carrying a *second* closed banner enumeration — was not in Files to Edit. |
| P1-g | test-design | `make_fake_proc` hardcodes ppid=0/pgrp=0; the ancestry arms need those parameterised. And there was **no over-cancellation control** — an implementation dropping *every* suite match whenever *any* run match exists passes every arm listed. |
| P1-h | security | Redaction **ordering** is unasserted (a later edit appending after the redactor ships raw and still passes AC14), and `head -20` bounds line count but not line length — a 100 KB line breaks GitHub's 65536-char body limit and the monitor files **nothing**. |
| P1-i | spec-flow / architecture | `grok-pre-push-gate.sh`'s `run_step` is R1's defect verbatim (`if "$@"`), re-labelling exit 3 as `[FAIL]` on the local pre-push surface — the plan applied one standard to the runner and waived it in the wrapper. |
| P1-j | spec-flow | The `[KILLED]` line is 100% negative space with **no next action**, against a runner whose house style ends every NOTE with a literal command. |

## Verified — agent claims that were WRONG (recorded so they are not re-raised)

| Claim | Source | Measurement that refuted it |
| --- | --- | --- |
| "Every new marker must be registered in `git-lock-marker-telemetry.ts`'s `MARKER_RE`" | learnings-researcher | That guard scans exactly two git-worktree scripts for `SOLEUR_*` sentinels. Neither target file is in scope. |
| "`kill -l` is the decode AND the bounds check" | **my own plan v1** | Refuted by P0-a. |
| "No false green is reachable by construction" | **my own plan v1** | Refuted by P0-c, P0-g, P0-j. |
| "`<= 192` is a load-bearing guard" | **my own plan v2** | test-design F4: the code passes `kill -l $((rc-128))`, so for rc>192 the operand is 65..127 which `kill -l` rejects — the non-empty guard already excludes it. **No reachable rc discriminates it.** Verified over rc 193/200/255. Retained with an honest comment, not claimed as pinned. |
| "The `<= 192` bound is needed because `kill -l` masks >64" | **my own plan v2** | The masking applies to `kill -l "$rc"`, which is not what is written. |
| "`/proc` scan discloses other users' cwd" | (my own concern) | security-sentinel measured EACCES on cross-uid `readlink /proc/<pid>/cwd` → renders `<unreadable>`. The real widening is **same-uid cross-project**. |
| "#7374's body contains a suite list" | git-history-analyzer summary | Measured: **zero** `^\[FAIL\]`/`^RED ` lines in its body. The plan's "names no suite" characterization was right. |

## Deferred to the Phase-7.2 tracking issue (triple test passed)

- Signal classification in the wrapper surfaces (`run-registered-suites.sh` — blocked on #7376/PR #7423; `.github/scripts/test/run-all.sh`; the webplat `npm run test:ci` registration).
- **Scope constraint that must appear in the issue body:** the wrapper must NOT return 3. rc=3 through
  `run_suite` classifies as a plain FAIL (measured), so nested KILLED must surface as a **marker line
  the parent promotes**, never as exit-code propagation. Without this the deferral as scoped
  instructs the violation.

## Deferred as P2 (recorded, not applied — no tracking issue per the triple test)

- Monitor redactor holes beyond the new channel (JWT/AWS/Cloudflare/npm/Slack/Sentry-DSN patterns; PEM
  body vs header-only strip). Pre-existing, wider than this PR's surface.
- Workflow-command fencing (`::stop-commands::`) around the suite steps — pre-existing exposure of all
  suite stdout to the Actions log parser; precedent exists at `reusable-release.yml`.
- Issue-title staleness when a tracker's arm changes between runs (pre-existing across all 3 arms).
- `run-registered-suites.sh`'s own `exit 2` (FATAL) — evidence for the "exit codes are runner-local"
  framing, recorded in ADR-175 Consequences rather than changed.
