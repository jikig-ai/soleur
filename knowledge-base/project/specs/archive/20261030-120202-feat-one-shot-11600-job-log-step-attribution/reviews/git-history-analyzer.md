# Git History Analysis — PR #11603 (feat-one-shot-11600-job-log-step-attribution)

**Seat:** soleur:engineering:research:git-history-analyzer
**Scope:** `git diff origin/main...HEAD` in the worktree — `scripts/followthroughs/web-first-deploy-10585.sh`
(+94/−20), `web-first-deploy-10585.test.sh` (+143/−2), `knowledge-base/engineering/operations/runbooks/
followthrough-convention.md` (+16), spec artifacts (plan, decision-challenges, session-state, tasks).
**Suite status:** `web-first-deploy-10585.test.sh` — **69 passed, 0 failed** (re-run locally; the new
anti-vacuity floor of 69 equals the exact pass count — zero headroom, which is the intended pin).
**Clone depth:** `git rev-parse --is-shallow-repository` → false; history assertions below are on full history.

## Verdict: SHIP — no blocking findings (P1: 0, P2: 0, P3: 8)

---

## 1. Timeline of File Evolution (git archaeology)

| Commit | Date (UTC) | Event |
|---|---|---|
| `c61497617a` | earlier | #8178 probe born — the origin of the `##[group]Run`/`started_at` region-slice technique for `UNKNOWN STEP` logs |
| `2a7ba6de12` | earlier | review fix bounding the follow-through by the runner's step headers |
| `a19a6df6eb` | earlier | #8262 — `git-data-boot-poll-8178.sh` gains the measured BOM idiom (`//`-global strip, 14/15 BOM'd headers on job 106093730126) |
| `0140dc3fe3` | 2026-10-30 01:00 | #11500 — `web-first-deploy-10585.sh` born, inheriting the field-2 step-name anchor (`index($2, step)`) |
| `a258867538` | 2026-10-30 | RED — UNKNOWN STEP fixtures (same day) |
| `c59b6769ec` | 2026-10-30 10:06 | **this fix** — started_at-keyed region-slice recovery, adapted from 8178 |
| `e69f12b22a` | 2026-10-30 | runbook sharp-edge doctrine |

**The load-bearing historical fact:** the probe's `POPULATION_WINDOW_S` (30 days) reaches
~1–2 weeks *past* GitHub's ~2–3-week attribution-expiry horizon on its very first sweep. The probe
was born at 01:00 UTC and was reading attribution-expired logs within hours — the defect was latent
from birth in #11500, not introduced by any intermediate change. The field-2 anchor was reasonable
when written (the expiry behavior was undocumented in this codebase until 8178's measured run).

## 2. Verbatim-reuse verification (the PR's core claim)

- The recovery awk at `web-first-deploy-10585.sh:307-310` is **byte-identical** to
  `git-data-boot-poll-8178.sh:204-207` modulo indentation and `poll_start`→`jstart` — verified by
  diff of normalized extracts. Copying the corrected form (including the `//`-global BOM strip that
  8178's comment documents as a hard-won fix) is correct.
- `log=${log//$'\r'/}; log=${log//$'\357\273\277'/}` at `:290-291` matches 8178's `:202-203` exactly.
- **Independent mutation verification:** I re-ran the probe against a 17a-shaped fixture with the
  BOM strip mutated `//`→`/` — the probe exited 3 (`no ##[group]Run header at or after …`) instead
  of 2. The fixture's second BOM'd section genuinely pins the global strip, as designed.

## 3. Exposure sweep — deferral completeness

`grep` across `scripts/followthroughs/*.sh` for `--log` consumers anchoring on field 2
(`index($2,…)` / `-v step=`) returns **exactly three** files: the one this PR fixes plus the two
named siblings `web-fresh-boot-zot-8651.sh` (`:58`) and `git-data-rehearsal-evidence.sh` (`:196,:200`).
The deferral list in #11607 is **complete** — no fourth step-anchored probe exists. (Note:
`git-data-rehearsal-evidence.sh` already carries a per-field `gsub(/\357\273\277/,…)` BOM strip, so
its #11607 port needs the region slice, not the strip idiom.)

## 4. Findings

### P3-1 — Recovery gated on EMPTY named trail: partial attribution would quiet-miss
`[[ -z "$trail" ]]` at `:305` is the only recovery trigger. If GitHub ever expires attribution
per-line/per-step rather than per-log (e.g., pointer attributed, `fresh_boot_ready` under
`UNKNOWN STEP`), a non-empty partial trail suppresses recovery → `ready_ts` empty → quiet 2 over a
proven boot. Observed expiry is all-or-nothing per job today, so theoretical — the architecture seat
found this independently (their P3-1); corroborated, same severity. A one-line comment pinning the
all-or-nothing assumption suffices.

### P3-2 — `emit_rows` emits a bare `\t` row for an empty `$3`/space-less line
A step-matched line with an empty third field yields `ts=""`, `content=""` → a `\t` row → `trail`
non-empty → suppresses BOTH recovery and the success tripwire. **Pre-existing** (carried verbatim
from the old inline awk); also corroborates the architecture seat's P3-2. Recorded so any future
hardening lands in the shared chokepoint once, not per-caller.

### P3-3 — Residual (4) overstates "loud on a success job" for a PARTIAL false bound
The header doc's claim — "a `::group::` title literally beginning `Run ` could false-bound … loud on
a success job (empty region still tripwires)" — is only loud when the false bound truncates the
region to empty. A `##[group]Run ` line appearing *after* the emitted pointer but *before*
`fresh_boot_ready` yields a pointer-only trail → the pattern-grep passes, `ready_ts` is empty →
**quiet 2**, silently dropping the obligation. Currently unreachable (`fresh-host-boot-trail.sh`
contains zero `::group::` uses — verified), but nothing in the emitter-parity drift guard (test 0b)
pins that absence. Suggest either tightening the residual wording or adding a `! grep '::group::'`
assertion to the parity guard.

### P3-4 — Runbook citation `(#8262)` is misplaced
`followthrough-convention.md` new bullet: "already proven in `git-data-boot-poll-8178.sh` and
adapted in `web-first-deploy-10585.sh` (#8262)". Git history: #8262 is the 8178-poll PR; the probe
shipped in **#11500** and gains this adaptation in **#11603** (issue #11600). The parenthetical
grammatically attaches to `web-first-deploy-10585.sh` and misattributes it. Move `(#8262)` beside
`git-data-boot-poll-8178.sh`, or cite #11600 for the adaptation.

### P3-5 — Tripwire message renders `trail.;` double punctuation
`printf … "…unmeasured trail.%s\n" … "$recovery_cause"` at `:334` with `recovery_cause` strings all
beginning `"; "` produces `…unmeasured trail.; no ##[group]Run header…`. Confirmed live in my
mutation run's stderr. Cosmetic; drop the literal `.` before `%s` or the `; ` prefix.

### P3-6 — `jstart` regex is a prefix match, weaker parity than 8178's anchored `ts_re`
`^[0-9]{4}-…T[0-9]{2}:[0-9]{2}:[0-9]{2}` at `:306` accepts `+05:00`-style offsets or trailing junk
(`jstart:0:19` slices whatever follows). 8178 anchors `^…(\.[0-9]+)?Z$`. Failure is still loud
(wrong bound → patternless region → tripwire on success jobs), so exposure is bounded — but
anchoring on `Z` would match the source idiom's strictness.

### P3-7 — `usrc()` helper is dead code
Defined at `.test.sh:157` with a usage comment; never invoked — test 18 inlines the ANSI-echoed
payload via `$'\033[36;1m…'` inside `ulog` instead. Either route 18 through `usrc` (clearer intent)
or delete the helper.

### P3-8 — `job()` fixture sets `completed_at` equal to `started_at`
`.test.sh:138` emits `"started_at":%s,"completed_at":%s` with `$st_json` twice — a completed job
whose `completed_at == started_at` is impossible in production. Unread by the probe; harmless, but
cheap to fix with `post`-style arithmetic while touching the builder.

## 5. Positive checks (verified, not assumed)

- **Named-path equivalence:** `index($2, step) == 1 { print $3 } | emit_rows` is output-identical to
  the prior inline awk (same ts/line derivation, same ANSI-ESC drop). The single-chokepoint
  extraction removes the two-copies drift class that #9905 was.
- **BOM/CR hoist is a real fix, not hygiene:** previously a section-head line could feed a
  BOM-prefixed timestamp into `ts_to_epoch` on the named path.
- **AC coverage:** AC-1 (17a/17b), AC-2 (fixture shape + BOM pins), AC-3 (19/20), AC-4 (18), AC-5
  (17c), AC-6 (21), AC-8 (floor 30→69, SEEN_RCS sweep extended), AC-9 (runbook + #11607 filed) —
  AC-7 is post-merge observational by design.
- **Exit-code vocabulary:** every new path lands in {5,2,3,78}; the trap/xtrace ordering pins pass.
- **Conclusion-agnostic recovery** is consistent with the probe's pre-existing semantics (job
  conclusion was never the boot verdict — #6995 note in the header).
- **Strictness asymmetry is intentional and correct:** the recovery path pattern-gates a non-empty
  region (a mis-bound adjacent step's chatter tripwires); the named path cannot mis-bind. Do not
  symmetrize — corroborates the architecture seat's P3-3.

## 6. Contributor/ownership note

Single-author history on this file (one-shot pipeline, #11500 → #11603 same-day). The technique's
provenance chain is 8178 → #8262 → this PR → #11607 (siblings) — the runbook section is the right
doctrine registry per the followthrough convention.
