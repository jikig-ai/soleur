# Data-Integrity Review — PR #11603 (feat-one-shot-11600-job-log-step-attribution)

Seat: `soleur:engineering:review:data-integrity-guardian`
Diff reviewed: `git diff origin/main...HEAD` in the worktree (7 files, +608/−20).
Data surface: **no DB/migration surface**. The only mutable state the diff builds is the
probe's in-memory obligation map (`BOOT_EPOCH`/`BOOT_ISO`/`RUN_URL`) derived from GitHub
job logs in `scripts/followthroughs/web-first-deploy-10585.sh`. The review therefore
grades whether the new recovered-region path can **fabricate** an obligation (a host
that was never proven fresh-booted enters the owed set) or **lose** one (a proven boot
silently leaves the set), per the brief's four named axes: ts parse, supersession by
newest boot, `jstart` `-` handling, conclusion-agnostic enrollment.

Verdict: **PASS WITH FINDINGS** — no P1. One P2 (a silent-obligation-loss channel on
degraded/partial attribution), four P3s.

## Verified sound (no findings)

- **Region derivation is byte-identical to the proven 8178 form.** The awk at
  `web-first-deploy-10585.sh:307-310` is `git-data-boot-poll-8178.sh:204-207`
  verbatim (only `poll_start` → `jstart` renamed), including the two-tab field
  strip, `substr(line,1,19)` second-precision ts, the `ts >= ps` string compare
  (chronologically correct for ISO-8601 at equal precision), `started`/`exit`
  bounds, and EOF close. The global CR + BOM strips (`:290-291`) run once for
  both consumers — required for the header regex's `^[0-9]` anchor, and they
  additionally fix a latent named-path BOM edge (documented inline).
- **`emit_rows` is the single emitted-vs-echoed chokepoint** (`:222-227`): both
  paths feed `"<ts> <content>"` lines through the same ANSI-ESC drop and
  `ts<TAB>content` reshape, so the #9905 echoed-source trap cannot drift between
  copies. Region lines arrive in the same `<ts> <content>` shape the named path's
  `$3` produces. Verified end-to-end: suite 69/69 pass, including the
  ANSI-echoed-ready-inside-region arm (case 18) and cross-mode supersession
  (case 21).
- **Fabrication requires pattern content that only the trail step emits.** A
  mis-bounded region (adjacent step, `::group::` title beginning "Run ",
  started_at/header skew) yields lines that fail the
  `web-host-(replace|create) web-[0-9]+ — fresh-host Sentry pointer` /
  `fresh-host boot reached fresh_boot_ready` gate → `trail=""` → loud
  CANNOT ESTABLISH on success jobs, no-enrollment on failure jobs. Adjacent
  steps (`Dispatch summary` emits `## web-host-create — birth of …`, not the
  pointer shape) cannot contribute either anchor. The blast radius of every
  mis-slice is **loss-bounded, never fabrication** — the stated residual is
  accurate. Checked the emitter `fresh-host-boot-trail.sh`: 73 `echo` sites,
  zero `##[group]`-shaped output lines (see P3-1 for the unpinned residual).
- **`jstart` `-` handling cannot lose a real obligation.** `-` is emitted only
  when the jobs-API step entry is absent or `started_at` is null — both imply
  the trail step never ran, so no trail content exists to recover. On success
  jobs the arm still lands at CANNOT ESTABLISH via the post-recovery tripwire
  (suite case 20); on failure jobs nothing is owed because nothing was emitted.
  The `^[0-9]{4}-…` regex is prefix-only, but `${jstart:0:19}` re-slices to a
  well-formed `YYYY-MM-DDTHH:MM:SS` for both the `ps` compare and the echoed
  `recovery_cause`, so API-side tail garbage can neither skew the bound nor
  inject into the verdict line.
- **Supersession is order-independent and conclusion-agnostic.** `-gt` epoch
  compare keeps the newest proven boot per key regardless of run-iteration
  order and regardless of which attribution mode supplied it (case 21).
  Enrollment runs for every non-skipped job conclusion — a failure job whose
  host emitted pointer+ready then died later still enrolls (case 17c), which is
  the correct over-owing posture; `skipped` (plan_only) remains the designed
  absence.
- **ts parse failures are loud, never silent.** A ready-line timestamp that
  fails `ts_to_epoch` exits 3 (`:341-345`); malformed region lines that reach a
  pattern match carry garbage ts fields that fail the same parse → CANNOT
  ESTABLISH. Marker-vs-boot staleness (`dt >= toDateTime64(...,'UTC')`),
  roster gate, verdict ordering and precedence are untouched and retested green.

## Findings

### P2-1 — Recovery trigger and success tripwire key on trail *emptiness*, not trail *content*: a nonempty-but-patternless named trail silently loses the obligation on a success job

`web-first-deploy-10585.sh:305` fires recovery only `if [[ -z "$trail" ]]`, and
`:333` tripwires only `jcon == "success" && -z "$trail"`. Any log that returns
**at least one named-attributed line** under the trail step — while the
pointer/ready lines sit unrecovered — yields a nonempty `trail`, so recovery
never runs and the tripwire never trips. Reproduced end-to-end against the PR's
own probe: a log with one named diagnostic line plus pointer+ready under
`UNKNOWN STEP` (partial attribution) and a boot >2d old returned `rc=2,
owed=0` — a proven overdue host read as quiet, the exact "unmeasured reads as a
quiet population of 0" class the probe's doctrine exists to refuse. The same
shape arises from a truncated named section or any gh-shape drift that leaves a
named row (a two-field line even produces a `\t`-only trail row that passes
`-z`). Notably, the diff itself proves the fix exists and applies it
asymmetrically: the *recovered* path is graded with a pattern-content gate
(`:317`, `grep -qE 'web-host-(replace|create) … |fresh-host boot reached
fresh_boot_ready'`) while the *named* path is graded on non-emptiness alone.
Suggested fix — fire recovery whenever the named trail lacks pattern lines, not
only when it is empty, e.g.
`if [[ -z "$trail" ]] || ! grep -qE '<the two anchors>' <<<"$trail"`; on
legitimate patternless trails (failure job whose step emitted diagnostics only)
recovery returns same-or-empty and behavior is unchanged, while partial
attribution / truncated sections recover the evidence instead of quietly
dropping it. Alternatively (weaker — makes the channel loud but still loses the
obligation) upgrade the success tripwire to `success && no trail-pattern
lines`.
File: `scripts/followthroughs/web-first-deploy-10585.sh:305,317,333`.

### P3-1 — Unpinned residual: an emitted line shaped like `##[group]Run` inside the trail step would early-bound the region into a pointer-only quiet read

The region exits at the *next* line matching
`^[0-9][0-9TZ:.-]* ##\[group\]Run `, which includes any emitted line whose
content begins `##[group]Run `. Today's emitter cannot produce one (verified:
no `##[group]`/`::group` output in `fresh-host-boot-trail.sh`), but nothing
pins that: a future `echo` of a literal `##[group]Run …` between the pointer
and ready lines would truncate the region to pointer-only → the OR-alternation
gate passes → `ready_ts` empty → silent non-enrollment **even on a success
job** (a real proven boot reads as a dark boot). Same stated-residual family as
the `::group::` title collision, but one step more dangerous because the
surviving fragment satisfies the pattern gate. Suggest pinning the emitter
(e.g., an emitter-parity grep like the existing `'— fresh-host Sentry
pointer'` guard asserting no emitted `##[group]Run` literal).
File: `scripts/followthroughs/web-first-deploy-10585.sh:309`.

### P3-2 — `recovery_cause` is computed on every empty-trail path but consumed only by the success tripwire

On failure/unknown-conclusion jobs the variable is assigned and discarded —
harmless, but the diagnostic value (why recovery failed) is dropped on exactly
the paths where it could inform the NOT YET/verdict trail. Cosmetic; no data
effect.
File: `scripts/followthroughs/web-first-deploy-10585.sh:304-327`.

### P3-3 — `usrc()` fixture helper is defined but never used

`web-first-deploy-10585.test.sh:152` defines the ANSI-echo UNKNOWN-STEP helper;
case 18 inlines its own `\033[36;1m` line instead. Dead fixture code — drop it
or use it so the helper can't drift from the shape it models.
File: `scripts/followthroughs/web-first-deploy-10585.test.sh:152`.

### P3-4 — Runbook cites `(#8262)` after the 10585 adaptation; the adaptation is #11600/this PR

`followthrough-convention.md` new bullet: "already proven in
`git-data-boot-poll-8178.sh` and adapted in `web-first-deploy-10585.sh`
(#8262)" — #8262 is the 8178 precedent; the 10585 adaptation is this PR
(#11600/#11603). Mis-citation in a doc whose purpose is citation.
File: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` (new "Sharp edges" bullet).

## Notes (non-findings)

- Named path slices `$3` (truncates at an embedded tab); region path keeps the
  full post-two-field remainder. Divergence is upstream of `emit_rows` and can
  only differ on content containing tabs, which neither anchor line carries —
  immaterial.
- The pattern gate's OR alternation is *correct*: pointer-only is the
  legitimate dark-boot read on a success job (must not tripwire); only
  ready-without-pointer is anomalous, and it is benign (enrolls nothing because
  no pointer key parses).
- `recovery_cause` interpolates `${jstart:0:19}` — the 19-char slice is
  regex-constrained to `[0-9T:-]`; no injection surface.
- `gh run view --job --log` reads the latest attempt only — pre-existing stated
  residual, unchanged by this diff.

## Verification performed

- `bash scripts/followthroughs/web-first-deploy-10585.test.sh` — **69 passed,
  0 failed**, floor at 69, property sweep holds {5,2,3,78}.
- Byte-compared the region awk against `git-data-boot-poll-8178.sh:204-207` —
  identical modulo the variable name.
- Reproduced P2-1 end-to-end with a stub-`gh` harness in scratch: partial
  attribution → `rc=2, owed=0` instead of enrolling/recovering.
- Grepped `fresh-host-boot-trail.sh` (73 echo sites) for `##[group]`/`::group`
  output — none today (P3-1 is latent, not live).
- Confirmed both workflow trail-step sites (`apply-web-platform-infra.yml:5056`,
  `:5474`) emit one runner `##[group]Run` header each and are followed by a
  `run:` step (`Dispatch summary`) that bounds the region.
