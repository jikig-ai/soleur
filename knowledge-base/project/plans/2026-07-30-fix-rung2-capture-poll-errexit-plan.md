---
title: "fix: the rung-2 rehearsal capture poll cannot poll — GitHub's inherited errexit kills it on attempt 1"
refs: 7025
closes:
lane: cross-domain
status: draft
brand_survival_threshold: none
requires_cpo_signoff: false
---

# Plan: restore the rung-2 capture step's bounded poll

> No `spec.md` exists for branch `feat-one-shot-7025-rung2-capture-poll-errexit` — spec lacks
> valid `lane:`, defaulted to `cross-domain` (TR2 fail-closed).

> **This PR must NOT close #7025.** It *unblocks* it. Use `Ref #7025` in the PR body —
> never `Closes`/`Fixes`. #7025 closes only when a rehearsal actually PASSES and the
> banner is cleared, which is explicitly out of scope here (see **Scope Limits**).

## Enhancement Summary

**Deepened on:** 2026-07-30 · **Reviewers:** dhh, kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer, cto (6-agent panel) + deepen-plan gate sweep.

### Key improvements

1. **A silent-false-PASS hazard was found and guarded (Kieran P0).** `set -e` is a builtin —
   therefore a pipeline — so it **resets `PIPESTATUS`**. Re-arming before the read makes `rc`
   always 0. Measured against the real step body: exit 0, **1 attempt**, `capture_rc=0`, green
   `PASS` summary — on a host that never booted. Strictly worse than the bug being fixed.
   Now pinned by the Phase 1 ordering rule, AC2, and mutation arm 13c.
2. **The fix as first drafted introduced a regression (CTO P1-3, measured).** A `doppler` auth
   failure would burn **all 20 attempts / ~16 min on a paid host** and report the least
   actionable verdict, where pre-fix it died in 4 s. Phase 1.5 adds a wrapper-auth fast-fail
   and a fourth summary class; arm 13e guards it.
3. **A standalone repo-wide lint was cut** (4 of 6 reviewers). Measured over **631** `run:`
   bodies: the drafted rule matches **1** — the bug itself — and **0 of 3** sibling bugs. The
   operator's ask is met instead by arm 13d, scoped to this workflow, in an already-registered
   suite. Recorded as a User-Challenge in `decision-challenges.md`.
4. **The ADR citation was wrong (architecture P1-B).** ADR-149 item 4's poll is the
   **birth-job** poll, not this one — and that poll carries the same defect on the highest-stakes
   path. It is now **fixed inline** rather than deferred, because the operator hits it on the
   very next dispatch after rung 2 passes.
5. **The `|| true` consequence was overstated and is now accurate.** Two downstream layers
   (`if-no-files-found: error`, and the gate's independent hash re-derivation) mean the harm is
   a misleading green summary plus a red upload — not a released interlock. Ban retained.
6. **Operator-journey gaps closed** (spec-flow): the artifact→PR path had no `gh run download`
   command anywhere in the repo, and `capture.log` was discarded on exactly the FAIL/TRANSIENT
   paths where diagnosis is needed.

### Verified during the deepen sweep

- All 4 cited AGENTS rule IDs **active**, none retired.
- All 4 cited issues resolve with matching semantics (#7025 OPEN, #7066 MERGED, #7042 OPEN
  confirms the actionlint backlog claim, #2965 OPEN).
- `deploy-docs.yml` unguarded sites **measured as 4** (`id`, `status`, `code`, `http`);
  `detectors` is already guarded — an earlier read miscounted it as a fifth.
- Gates 4.6/4.7/4.8/4.9/4.10 pass; 4.5 and 4.55 evaluated and recorded as not-applicable with
  reasons (see *Skipped Gates*).

---

## Problem

`.github/workflows/git-data-rung2-rehearsal.yml` line 277 is the **only** step in the file
that writes `set -uo pipefail` instead of `set -euo pipefail`. Omitting `-e` from a `set`
line does **not** remove the `-e` that GitHub's default shell already applied. The run log
for the failing dispatch shows `shell: /usr/bin/bash -e {0}`, and the workflow declares
**zero** `shell:` overrides (measured: `grep -c "shell:"` → `0`).

So errexit is ACTIVE inside that step, and the pipeline

```bash
doppler run … git-data-rung2-evidence-capture.sh … 2>&1 | tee /tmp/rung2/capture.log
```

returns 2 on a TRANSIENT attempt — the *normal* early-attempt outcome, because that is what
"the host is still booting" means. With `pipefail` on, errexit kills the step at that line.

Everything after the pipeline is **dead code on the transient path**: `rc=${PIPESTATUS[0]}`,
the doppler-auth-vs-boot-failure sentinel disambiguation, `sleep 30` and attempts 2..20, the
deadline break, `echo "capture_rc=…" >> "$GITHUB_OUTPUT"`, the three-way
`$GITHUB_STEP_SUMMARY` block, and `exit "$rc"`.

**This is total, not intermittent.** Attempt 1 fires ~4 s after `terraform apply` returns.
Hetzner reports the server created long before cloud-init has mounted LUKS, run `doppler`,
and emitted `stage:boot_complete` — minutes later. `rc=0` is unreachable on attempt 1, so
PASS is unreachable, so `git_data_rung2_rehearsal_gate` can never be released and the
git-data host can never be birthed.

## Measured evidence

### Production (GitHub Actions run 30560266736, `dry_run=false`, 2026-07-30)

- Terraform apply created `soleur-git-data-rehearsal-30560266736` successfully.
- "Capture rung-2 evidence (bounded poll)" printed **exactly one**
  `--- capture attempt 1/20 ---` and exited 2, four seconds after the step started.
- Teardown ran and the Hetzner survivor assertion passed — **no orphan host, no ongoing cost.**
- The upload step evaluated `steps.capture.outputs.capture_rc == '0'` against an **empty
  string**, because `capture_rc` was never written.

### Local reproduction against the REAL workflow file

The capture step's `run:` body was extracted from the live YAML by a python3/`yaml` reader,
then executed under `bash -e` with `doppler` and `sleep` stubbed on `PATH`. The stub returns
TRANSIENT (2) twice, then PASS (0):

| variant | step exit | `--- capture attempt` lines | `capture_rc` | summary |
|---|---|---|---|---|
| **current workflow body** | 2 | **1** | *(empty)* | 0 lines |
| **patched** (`set -euo pipefail` + `set +e` … `rc=` … `set -e`) | 0 | **3** | `capture_rc=0` | PASS |
| **patched but REORDERED** (`set -e` before `rc=`) | **0** | **1** | **`capture_rc=0`** | **PASS** |

The first row reproduces production exactly. **The third row is the trap** — see below.

### THE ORDERING IS LOAD-BEARING (Kieran P0, measured)

`set -e` is a **shell builtin, and therefore a pipeline** — bash resets `PIPESTATUS` after
every pipeline. So placing the re-arm before the read silently zeroes the verdict:

```bash
set +e; ( exit 2 ) | cat; rc=${PIPESTATUS[0]}; set -e   # rc=2  ← CORRECT
set +e; ( exit 2 ) | cat; set -e; rc=${PIPESTATUS[0]}   # rc=0  ← SILENT FALSE PASS
```

Run against the real step body, the reordered form yields `exit 0`, **one** attempt,
`capture_rc=0`, and a green `### Rung-2 rehearsal: PASS` summary — on a host that never
booted. That is **strictly worse than the bug being fixed**, which at least fails loudly.
`rc=${PIPESTATUS[0]}` MUST be the *first command after the pipeline*, with nothing — not
even `set -e` — between them.

### Candidate-fix measurements (why this form, and not the obvious ones)

Measured under `bash -e`, pipeline exits 2, `tee` exits 0:

| form | `rc` | verdict |
|---|---|---|
| `pipeline \|\| true` then `rc=${PIPESTATUS[0]}` | **0** | **DISQUALIFIED.** `true` runs as its own pipeline and resets `PIPESTATUS`. Every TRANSIENT reads as PASS. |
| `pipeline \|\| rc=$?` | 2 here, but **1** when `tee` fails and the script *passes* | **DISQUALIFIED.** Under `pipefail`, `$?` is the rightmost failing stage — so a `tee` failure is reported as "the host reported a fatal", the exact mis-blame the sentinel block exists to prevent. |
| `set +e` … `rc=${PIPESTATUS[0]}` … `set -e` | 2; and **0** on tee-fail/script-passes | **CHOSEN.** Preserves `PIPESTATUS[0]` semantics exactly. |

Also measured: `[[ "$rc" -ne 2 ]] && break` at the loop tail does **not** trip errexit (a
failing non-final `&&` member is exempt), so restoring `-e` needs no collateral change.

### The fix is already the house pattern

`PIPESTATUS` appears in exactly **two** workflows repo-wide: the bug, and
`web-platform-release.yml` step **"Run live-verify harness (report-only)"** — a structural
twin (`set +e` → `doppler run … | … | tee` → `rc=${PIPESTATUS[0]}` → `set -e`). *(Cited by
step name, not line number, per `cq-cite-content-anchor-not-line-number`. Caveat: that step
also carries `continue-on-error: true` and never sets `pipefail`; the bracket pattern is the
same, the surrounding posture is not.)*

There are **42** `set +e` uses across `.github/workflows/`, and five in-repo comments already
state the exact rule this step violates. `git log -L 277,277` shows the line was introduced
by **PR #7066**, the same commit that created the workflow. The author's **intent** (tolerate
a non-zero inside the poll) was right; only the mechanism was wrong.

## Research Reconciliation — spec vs. codebase

| Claim | Reality (measured) | Plan response |
|---|---|---|
| Line 277 is the only `set -uo pipefail` in the file | Confirmed — 9 siblings use `-euo` | Bring 277 into line + scoped `set +e`. |
| GHA default `run:` shell | Run log measured `bash -e {0}`. The existing learning `2026-07-02-…` claims `bash --noprofile --norc -eo pipefail {0}` — that is what `shell: bash` expands to. | **Immaterial**: the step's own first line sets `pipefail` regardless. Correct the stale claim in Phase 4. |
| ADR-149 item 4's "poll that reads it" is this poll | **FALSE (architecture P1-B).** Item 4's poll is the **birth-job** poll, step *"Poll for the git-data boot-completion signal"* in `apply-web-platform-infra.yml`. The rung-2 capture poll is a *different* poll added by #7025. | ADR section rewritten; ADR-149 disposition amended; birth poll named in the tracking issue. |
| The birth-job poll is "safe by construction" | **Partly false.** Its "not yet" is rc=0 so the common path is safe, but `rc=$?` after `out=$(bash scripts/betterstack-query.sh …)` is unreachable on *any* non-zero (e.g. its `exit 64`). Fail-**closed**, not false-PASS — but the same shape on the highest-stakes path. | Named explicitly in the tracking issue, not dismissed. |
| The 43-assertion suite covers the poll | **It does not** — grep for the loop's tokens returns only the suite's own `set -uo pipefail`. | Behavioural arm (Phase 2). |
| A grep guard would catch this | **Falsified**: grep counts for `seq 1 N` / `PIPESTATUS` / `capture_rc` are **identical (1/1/1)** for fixed and buggy bodies. | The guard must EXECUTE. |
| The evidence file satisfies the gate | **Confirmed key-by-key** (spec-flow): cardinality, `PASS` literal, URL regex, shared `git_data_rung2_user_data_sha256`, and `REHEARSAL_DIVERGENCE` byte-identical to the gate's allowlist. | No change needed — the poll is the only mechanical break. |
| `\|\| true` "would release the interlock" | **Overstated (architecture P2).** Two layers catch it: upload is `if-no-files-found: error` and the script writes the file only on PASS; and the gate re-derives the template hash independently. | Restated accurately below. Ban retained. |

## Scope Limits (hard)

- **Do NOT clear the DO-NOT-DISPATCH banner** in `git-data-birth.md`.
- **Do NOT birth the git-data host.** **Do NOT commit** any `git-data-rung2-boot-evidence.env`
  — a PR merges atomically, so evidence committed with the harness would be evidence from a
  rehearsal that never ran.
- After merge, the birth sequence resumes at rung 2 by re-dispatching with `dry_run=false`.

## Files to Edit

| File | Change |
|---|---|
| `.github/workflows/git-data-rung2-rehearsal.yml` | **Primary fix** + upload `capture.log` on non-PASS + next-action text in the FAIL/TRANSIENT summaries. |
| `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` | Behavioural arms 13/13b + in-workflow errexit-posture arm 13d; raise the anti-vacuity floor. |
| `.github/workflows/scheduled-supabase-advisor-scan.yml` | Sibling fix + comment. |
| `.github/workflows/follow-through-closure-guard.yml` | Sibling fix + comment. |
| `.github/workflows/deploy-docs.yml` | Sibling fix — **4 sites**, not 1. |
| `.github/workflows/apply-web-platform-infra.yml` | Birth-job boot-signal poll — same bracket; on the operator's critical path immediately after rung 2 passes. |
| `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md` | `## After a PASS` procedure. |
| `knowledge-base/engineering/architecture/decisions/ADR-149-…md` | One-line `### Disposition — #7025` correction. |
| `knowledge-base/project/learnings/best-practices/2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md` | Append; correct its stale default-shell claim. |

## Implementation Phases

> Phase order is load-bearing: the **contract change (Phase 1) ships before its consumer
> (Phase 2)**.

### Phase 1 — Fix the capture step

1. Line 277: `set -uo pipefail` → `set -euo pipefail`.
2. Bracket **only** the capture pipeline. **The `rc=` read must immediately follow the
   pipeline; the `set -e` re-arm must come after it.**

```bash
            # GitHub runs this step as `bash -e {0}` (measured: run 30560266736; this
            # workflow declares no `shell:` override). Omitting -e from our own `set` line
            # does NOT clear that inherited -e — so without an explicit `set +e` the
            # TRANSIENT rc=2 that this poll EXISTS to retry kills the step on attempt 1.
            # Same bracket as web-platform-release.yml's "Run live-verify harness" step.
            #
            # ORDER IS LOAD-BEARING: `set -e` is a builtin, i.e. a PIPELINE, so it RESETS
            # PIPESTATUS. Re-arming before the read makes rc always 0 — a silent false PASS
            # on a host that never booted (measured). Nothing may sit between the pipeline
            # and the read.
            set +e
            doppler run -p soleur -c prd_terraform -- \
              bash scripts/followthroughs/git-data-rung2-evidence-capture.sh \
                --host-name "$REHEARSAL_HOST" \
                --evidence-url "$url" \
                --divergence "$REHEARSAL_DIVERGENCE" \
                --out /tmp/rung2/git-data-rung2-boot-evidence.env 2>&1 | tee /tmp/rung2/capture.log
            rc=${PIPESTATUS[0]}
            set -e
```

3. Change nothing else in the step. The `tee` stays — `capture.log` is load-bearing for the
   sentinel disambiguation.

> **Scope of the `|| true` ban.** It applies to **any pipeline whose status is later read via
> `${PIPESTATUS[…]}`**. Where no `PIPESTATUS` read follows, `|| true` / `|| echo "<default>"`
> is the correct house form and is exactly what Phase 3 sibling #2 needs. Stated
> unconditionally, Phases 1 and 3 would contradict each other and stall an implementer.

4. **Fail fast on a wrapper auth failure — this fix otherwise introduces a regression
   (CTO P1-3, measured).** The sentinel block correctly *detects* a `doppler` auth/config
   failure (rc=1 with no `RUNG2_CAPTURE_VERDICT=`) and downgrades it to `rc=2` so it is not
   mis-blamed on the host. But 2 means "retry", and an auth failure is **not transient** —
   retrying cannot change it. Measured against the patched body with a stub that always
   exits 1 without the sentinel: **all 20 attempts burned**, `capture_rc=2`, summary
   `### Rung-2 rehearsal: TRANSIENT (no verdict)`.

   Pre-fix, a bad token killed the step in **4 seconds**. Post-fix it spends **~16 minutes on
   a paid Hetzner host** and hands the operator the *least* actionable of the three verdicts —
   whose own text says *"This is NOT evidence the host booted dark."*

   Track consecutive no-sentinel `rc=1` attempts; break after **2**, and emit a distinct
   fourth summary class:
   `### Rung-2 rehearsal: WRAPPER FAILURE (doppler auth/config)` — naming the credential as
   the thing to check, not the host. ~5 lines. Guarded by arm 13e.
5. **Upload the diagnostic on the paths that need it.** The existing upload is gated on
   `capture_rc == '0'`, so `capture.log` is discarded on exactly the FAIL/TRANSIENT paths
   where diagnosis is required. Add a second `upload-artifact` for `/tmp/rung2/capture.log`
   gated on non-PASS (spec-flow P1-2).
6. **Give FAIL and TRANSIENT a next action.** Both summary branches currently end without
   one. Add the named next step and a link to
   `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md`.

### Phase 2 — The behavioural regression guard (the point of this task)

Extend `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` — already registered in
`infra-validation.yml`, so no orphan-suite risk (the class closed in `dc6dd1f70`). Follow the
file's `pass()`/`fail()` idiom. Precedents: `workspaces-luks-cutover-workflow.test.sh`
(extract `run:` bodies then execute) and `scripts/review-reminder-liveness.test.sh` (execute
an extracted body under a specific shell posture with mocked `PATH`).

**Placement (Kieran P1-3):** the arms MUST sit **inside** the existing
`if command -v python3` block — an arm outside it silently skips when python3 is absent, and
the `else` arm's `fail` would not cover it. The extracted body assumes repo root (the step
declares no `working-directory:`), so the arm must `cd "$ROOT"`.

**Isolation (Kieran P1-2):** the body hardcodes `/tmp/rung2` for `mkdir`, the `tee`, the
sentinel `grep -q`, and `--out`. Neither `mktemp -d` nor the suite's `TMPDIR` reaches those.
`rm -rf /tmp/rung2` before **each** arm, and note in the header that these arms cannot run
concurrently.

**Arm 13 — the poll actually polls.**

1. Extract the `run:` body **keyed on `id: capture`, NOT the step name** (CTO P2-1). The name
   is free text with zero consumers, so keying on it makes the guard a cosmetic rename away
   from a spurious red — the recurring tax this guard must avoid. The `id` is load-bearing:
   the upload step gates on `steps.capture.outputs.capture_rc`, so renaming it breaks the
   workflow visibly and independently of the test. **An empty extraction must FAIL with a
   message naming `id: capture` — never skip** (asserted, not left to the Risks table).
2. Fixture with stub `doppler` and `sleep` on `PATH`; `doppler` exits 2 on attempts 1–2, then
   prints `RUNG2_CAPTURE_VERDICT=PASS` and exits 0. **Assert the stub was actually invoked**
   (counter > 0) — otherwise a future edit that drops `doppler run` leaves the stub unused and
   the arm passes for reasons unrelated to the poll.
   **Derive the environment from the parsed YAML** (`workflow env | job env | step env`),
   substituting a fixture placeholder for any `${{ … }}`, rather than hardcoding names
   (CTO P2-2). The seven values come from three different places — `REHEARSAL_HOST` from the
   step `env:`, `REHEARSAL_DIVERGENCE` from the **workflow-level** `env:`, the rest from the
   runner — so a single added `env:` reference would otherwise fail the arm under `set -u`
   with a message pointing at the wrong thing.
   **Assert the `sleep` stub resolves** (`command -v sleep` inside the fixture `bin/`) — the
   real body sleeps 30 s, so an un-stubbed `sleep` makes this a 60-second test that still
   passes and nobody notices until CI wall-time drifts.
   **Execute (`bash -e "$extracted"`), never `source`** — `deadline=$(( SECONDS + 16 * 60 ))`
   reads the shell's own `SECONDS`; sourcing would leak the suite's elapsed time and could
   fire the deadline immediately.
3. Assert: `--- capture attempt 2/20` **appears**; terminal PASS exits **0**; `capture_rc=0`
   is written; the PASS line reaches `$GITHUB_STEP_SUMMARY`.

**Arm 13b — mutation / non-vacuity (mandatory).** Re-run with the `set +e` **stripped**;
assert collapse to one attempt, non-zero exit, empty `capture_rc`. This discharges the first
obligation in
`learnings/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`
— *"First prove the check can fail; then care that it didn't."*

**Arm 13c — the ordering trap.** Re-run with `set -e` moved **before** the `rc=` read; assert
the arm goes RED. Without this, the single most dangerous regression (silent false PASS) is
unguarded. *(This replaces the speculative `continue-on-error` assertion the review cut;
retain only the check that the upload step still gates on `capture_rc == '0'`, since that
coupling did fail in production.)*

**Arm 13e — a wrapper auth failure stops fast.** Stub `doppler` to always exit 1 without the
sentinel; assert the loop stops at attempt **2** (not 20) and the summary carries the
`WRAPPER FAILURE` class. Without this arm, Phase 1.4's fast-fail is unguarded and the
16-minute paid burn silently returns.

**Arm 13d — in-workflow errexit posture (the operator's "pin the class" ask, scoped).**
Text-level, over **this workflow only**: for every `run:` body, if it reads `${PIPESTATUS[…]}`
then the nearest preceding `set +e`/`set -e` toggle must be `set +e`, and no command may sit
between the pipeline and the read. ~15 lines in an already-registered suite, zero new files,
zero waivers. See *Decision Challenges* for why this replaced a standalone repo-wide lint.

**Raise the anti-vacuity floor** from 43 — **keep `-lt`**. The suite's own comment explicitly
rejects `-eq` ("developer-incremented, so `-eq` would redden the suite on every legitimately
added arm"). The literal `43` appears at **three** lines (the `-lt` test, the FAIL message,
the ok message); update all three plus the `RAISED 28 -> 39 -> 43` header note.

### Phase 3 — Sibling steps carrying the same latent assumption

Measured and load-bearing; each fails toward silence. Per `rf-review-finding-default-fix-inline`.

1. **`scheduled-supabase-advisor-scan.yml`** — `out="$(… supabase-advisor-scan.sh …)"; rc=$?`.
   Errexit kills the step at the first failing ref. **The real harm (Kieran P2) is
   misclassification, not just an aborted loop:** `issue_class` is never written, so the
   `if: failure()` filer falls back to `|| 'B'` — a genuine RLS violation (class A,
   `type/security`, p1-high) is filed as class B *"the scan itself could not be trusted"*.
   The step's comment asserts *"a non-zero from one ref must NOT abort the loop"*. Fix both.
2. **`follow-through-closure-guard.yml`** — `run_id=$(grep -oE 'actions/runs/[0-9]+' … | head -1 | sed …)`.
   `grep` exits 1 when the comment has no run URL — **the exact case the guard exists to
   catch** — so the reopen path never runs. Correct fix here is `|| true` / `|| echo ""`,
   **not** a `set +e` bracket (no `PIPESTATUS` read).
3. **`deploy-docs.yml`** — **four** unguarded sites across two steps, not one (architecture
   P1-A). The job sets `defaults.run.shell: bash`, so the body runs as
   `bash --noprofile --norc -eo pipefail {0}` — `-e` *and* `pipefail` both active (verified).

   **Measured, guard exactly these four** (named by variable, per
   `cq-cite-content-anchor-not-line-number`):

   | assignment | step | consequence if it fails |
   |---|---|---|
   | `id=$(jq -r … <<<"$detectors" …)` | pause | step dies before the monitor id is recorded |
   | `status=$(curl … -X PUT …)` | pause | monitor **paused and unrecorded** → the resume step reads an empty id and exits 0 "nothing to resume" — the stranded-paged-off outcome |
   | `code=$(curl … '%{http_code}' …)` | probe | resume block below never runs |
   | `http=$(curl … -X PUT …)` | **resume** | the `::error::… may remain paused` fail-loud is itself unreachable |

   **`detectors=$(curl …)` is ALREADY guarded — do not touch it.** (Verified by balancing
   parens across the multi-line substitutions and checking each for a `||` guard; an earlier
   read of this plan miscounted it as a fifth site.)

   House form here is `|| status="000"` — both steps already branch on the code — not a
   `set +e` bracket. Both steps' comments currently assert best-effort semantics
   (*"a transient Sentry API blip must NEVER block a docs deploy"*, *"the resume runs
   regardless"*) that errexit falsifies; re-derive both.

**Comment correctness (architecture P1-A).** Fixing one site and "correcting the comment"
would produce a *new* false statement. AC requires each **named site** guarded and the comment
**re-derived from the guarded code**.

4. **`apply-web-platform-infra.yml` — the birth-job poll. FIX INLINE, do not defer.** Step
   *"Poll for the git-data boot-completion signal"*, under `set -uo pipefail`:
   `out=$(bash scripts/betterstack-query.sh "…" 2>/dev/null); rc=$?`. The empty-result path
   is rc=0, so the *common* path polls fine — which is why the first draft of this plan
   wrongly called it "safe by construction". The entire `rc != 0` path is dead: the `rc=$?`
   capture, the `[[ $rc -eq 0 ]]` guard, and the `poll ${i}/20: rc=${rc}` diagnostic. One
   transient Better Stack error (rate limit, 5xx, credential blip) kills the **birth job**
   mid-poll with no annotation instead of retrying.
   **Both architecture and CTO converged on fixing this inline**, and the sequencing argument
   is decisive: the operator's path is fix rung 2 → dispatch rung 2 → dispatch the birth →
   hit this. Deferring it ships the identical failure on the very next dispatch. Same ~3-line
   `set +e` bracket.
5. **`git-data-rung2-rehearsal.yml` — the `teardown_only` / `dry_run` survivor gate. FIX
   INLINE.** The recovery arm is gated on `inputs.teardown_only`, but both teardown-verification
   steps are gated on `always() && !inputs.dry_run` — and `dry_run` defaults to **true**. So a
   `teardown_only=true` dispatch that leaves the default runs the destroy but **skips the
   Hetzner survivor assertion** — on the step whose entire purpose is proving no paid box
   survived. The operator is about to enter a re-dispatch loop on a workflow that spends real
   hosts, which is exactly when they reach for `teardown_only=true`. One-line `if:` change
   (`always() && (inputs.teardown_only || !inputs.dry_run)`).

**File a tracking issue** for the remaining `set`-omits-`-e` audit. Measured over **631**
`run:` bodies in `.github/workflows/`: the `set`-omits-`-e`-with-no-`set +e` rule matches
**56**; a `PIPESTATUS`-or-bare-`var=$?` rule matches **16**; the `PIPESTATUS`-only rule
matches **1**. *(An earlier draft cited "17" — that was a third, narrower rule and the number
was not comparable. Corrected here so the deferral rests on the real figures.)* Many of the 56
are safe by construction (`until` conditions are errexit-exempt).

The issue must explicitly name: (a) the **~10 `Terraform plan` steps** across the `apply-*`
family — e.g. `apply-github-infra.yml` carries a comment reading *"`-e` is intentionally
omitted so we can capture terraform plan's exit code in `$rc`"* directly above code where
`rc=$?` and its `::error::terraform plan failed` branch are both unreachable. Ten copies of a
comment asserting the opposite of the code is the strongest available evidence that comments
are not a working control here; and (b) the standalone repo-wide lint deferred from this PR.
Labels `code-review` + `domain/engineering` (both verified to exist).

**Do NOT bulk-flip `set -uo` → `set -euo` across the 56.** On a body that genuinely needs
errexit off, the token flip preserves the broken runtime behaviour while making the code look
deliberate — converting a detectable bug into an invisible one.

### Phase 4 — Docs + ADR + learning

1. **`## After a PASS` in the rehearsal runbook (spec-flow P0-1).** Today the entire procedure
   is one clause: *"Open a PR with it yourself"*. The destination path *is* named in
   `git-data-birth.md`, but the retrieval step exists nowhere: there is **no `gh run download`
   command anywhere in the repo** for this artifact. Add the literal
   `gh run download <id> -n git-data-rung2-boot-evidence` → `git checkout -b` → `gh pr create`
   sequence, and echo it into `$GITHUB_STEP_SUMMARY` on the PASS branch so the operator reads
   it where they already are. Add one line on the staleness race: any merge touching
   `cloud-init-git-data.yml` or its nine payloads between the rehearsal and the evidence PR
   invalidates the evidence (`infra-validation.yml` catches it, but the remedy is a full
   re-rehearsal).
2. **ADR-149 `### Disposition — #7025` correction (architecture P1-B).** The disposition says
   #7025 shipped "the route"; the route's capture step could not execute past attempt 1, so
   item 8's precondition stayed unproducible. One line, in the same register as the ADR's five
   existing in-line corrections. No change to `## Decision` or the alternatives table.
3. **Append to the existing learning — do NOT create a fifth file.** The repo already carries
   four learnings on this rule (`2026-03-03-set-euo-pipefail-upgrade-pitfalls`,
   `2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail`,
   `2026-04-29-canary-layer3-mount-and-pipefail-traps`, and the 2026-07-02 one) plus five
   in-workflow comments — and it still recurred. Append to
   `best-practices/2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md`:
   the `|| true` and `|| rc=$?` disqualifications, the **`set -e`-resets-`PIPESTATUS` ordering
   trap**, and a **correction to that file's own claim** that the default `run:` shell is
   `bash --noprofile --norc -eo pipefail {0}` (that is `shell: bash`; the measured plain-`run:`
   default is `bash -e {0}`).

## Acceptance Criteria

### Pre-merge (PR)

1. `! grep -q 'set -uo pipefail' .github/workflows/git-data-rung2-rehearsal.yml`.
   *(Use `! grep -q`, not `grep -c … == 0` — `grep -c` exits 1 on zero matches and would turn
   a passing AC red under a `set -e` runner.)*
2. In the capture step's **extracted body** (not the file — `|| true` legitimately appears in
   two unrelated steps), matched with anchors `^[[:space:]]*set [-+]e$` (an unanchored
   `set -e` also matches every `set -euo pipefail` line): exactly one `set +e` and one `set -e`;
   `set +e` precedes the pipeline; `rc=${PIPESTATUS[0]}` **immediately follows** the pipeline;
   `set -e` follows the read. No `|| true` and no `|| rc=$?` on that pipeline.
3. The step still pipes to `tee /tmp/rung2/capture.log` and ends `exit "$rc"`.
4. `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` passes, reports **> 43**
   assertions, and its `-lt` floor equals the new total at all three literal sites.
5. Arm 13 asserts `--- capture attempt 2/20`, `capture_rc=0`, and the PASS summary line.
6. **Arms 13b and 13c both go RED against their mutations** — `set +e` stripped, and `set -e`
   moved before the read. A guard that cannot go red is not a guard.
7. Arm 13d passes and reports a non-zero count of `run:` bodies scanned (not a vacuous
   zero-scan pass). Arm 13e asserts a no-sentinel `rc=1` stops at attempt **2**, not 20, and
   yields the `WRAPPER FAILURE` summary class.
8. Extraction is keyed on `id: capture`; a missing id **FAILs** with a message naming it. The
   arm's env is derived from the parsed workflow/job/step `env:` maps, not hardcoded. The
   `doppler` stub's invocation counter is asserted > 0.
9. All Phase-3 sites guarded: 1 in `scheduled-supabase-advisor-scan.yml`, 1 in
   `follow-through-closure-guard.yml`, **4** in `deploy-docs.yml`, the birth-job poll in
   `apply-web-platform-infra.yml`, and the `teardown_only`/`dry_run` survivor gate — each with
   its comment **re-derived from the guarded code** (fixing one site and "correcting" the
   comment would only produce a new false statement). Tracking issue filed, naming the ~10
   `Terraform plan` steps and the deferred lint, linked in the PR body.
10. The rehearsal runbook has an `## After a PASS` section containing a literal
    `gh run download` command; the PASS summary branch echoes the same sequence.
11. ADR-149's `### Disposition — #7025` carries the correction; `## Decision` is unchanged.
12. The 2026-07-02 learning is appended to and its default-shell claim corrected; **no new
    learning file** is created. The append records the measured actionlint/shellcheck result
    (`SC2034` only) so the build-vs-buy question is not re-litigated.
13. Named gates green: the four suites above, plus
    `bash apps/web-platform/infra/run-registered-suites.sh`,
    `bash scripts/check-adr-ordinals.sh`, `bash scripts/test-all.sh`.
    *(Baseline measured: 43 / 58 / 30 / 101 assertions, all green — and green against the
    broken poll. That is the point, which is why AC6 carries the real weight here.)*
14. `git diff` shows **no** change to `git-data-birth.md` and **no**
    `git-data-rung2-boot-evidence.env` anywhere.
15. PR body says `Ref #7025`, with no `Closes`/`Fixes` keyword, and discloses the two
    behaviour changes the sibling fixes arm: the next advisor scan may file a legitimate
    p1-high security issue previously masked as class B, and the closure guard will begin
    reopening incompletely-closed issues. Both are correct outcomes, not regressions.

### Post-merge (operator)

15. **Precondition, costs nothing, run first:** a `--verify-only` probe against the live
    Better Stack source. The source-liveness anchor gates **every** PASS and has never been
    exercised against live data — every test arm stubs the transport, and the one production
    run died before the anchor ran. It fails toward TRANSIENT, so an untested anchor turns a
    €-costing dispatch into a no-verdict. Retire that risk before spending a host.
16. Re-dispatch `git-data-rung2-rehearsal.yml` with `dry_run=false`,
    `confirm=REHEARSE-GIT-DATA`.
    *Automation: `gh workflow run`-able; the `environment: web-platform-infra-apply` reviewer
    gate is pre-existing and intentional per ADR-149. This plan adds no new manual step.*
17. **Split on outcome** — a TRANSIENT must not read as success:
    - **PASS** → artifact downloadable; validate it *before* committing
      (`source tests/scripts/lib/git-data-birth-readiness-gate.sh && git_data_rung2_rehearsal_gate apps/web-platform/infra/cloud-init-git-data.yml <downloaded>`);
      then open the evidence PR promptly (staleness race).
    - **FAIL / TRANSIENT** → `capture.log` artifact exists, the summary names the next action,
      and an issue is filed. **#7025 stays open and the banner stays up.**
18. Teardown verification ("Assert no rehearsal host survives") passes.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — `soleur-git-data` has never
existed and no user workspace depends on it. The cost is that the host stays unbornable, and
each attempt spends a real Hetzner host for ~4 seconds of useful work.

**If this leaks, the user's data / workflow / money is exposed via:** no new exposure surface.
`DOPPLER_TOKEN` handling is unchanged. The one money-shaped risk is the *existing* one this
reduces: a rehearsal that dies at attempt 1 still provisions and tears down a paid host.

**Brand-survival threshold:** `none` — no user-facing surface, no regulated data, no persistent
store.

- `threshold: none, reason: the diff changes only shell-flag posture inside existing `run:`
  blocks — it adds no resource, no secret, no route, and no data path, so the three
  sensitive-path files it touches (`deploy-docs.yml`, `apply-web-platform-infra.yml`,
  `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`) gain guards rather than
  capabilities.`

Sensitive-path scope-out detail, per file:

- **`git-data-rung2-rehearsal.yml`** — `workflow_dispatch`-only behind an approving
  environment; creates only prefix-scoped throwaway resources in a separate Terraform root;
  teardown verified independently against the Hetzner API.
- **`apply-web-platform-infra.yml`** — the edit is confined to a `run:` body in the
  birth job's boot-signal poll. **No Terraform resource, `-target=` list, or destroy-guard
  input changes**, so the merge-triggered apply's plan is unaffected.
- **`deploy-docs.yml`** — the only `push: main` file in the diff. The edit adds failure
  guards to two Sentry-monitor steps; it changes no deploy step and no Pages output. Net
  effect is *fewer* aborted deploys, not more.
- **`git-data-rung2-rehearsal.test.sh`** — test-only; adds assertions.

**The genuine hazard is inside this plan**, which is why the ordering rule and the `|| true`
ban carry measurements: a fix that let `PIPESTATUS` read 0 on a TRANSIENT would print a green
PASS over a host that never booted. Accurately scoped (architecture P2): two downstream layers
still catch it — the upload is `if-no-files-found: error` and the script writes the evidence
file only on PASS, and the gate independently re-derives the template hash. So the harm is **an
operator misled by a job summary plus a red upload**, not a released interlock. Guarded by
arms 13b and 13c.

## Observability

```yaml
liveness_signal:
  what: "The `--- capture attempt N/20` progression and the three-way $GITHUB_STEP_SUMMARY verdict (PASS / FAIL / TRANSIENT)."
  cadence: "Per manual dispatch (workflow_dispatch only)."
  alert_target: "The dispatching operator, via the Actions run page and job summary."
  configured_in: ".github/workflows/git-data-rung2-rehearsal.yml, step 'Capture rung-2 evidence (bounded poll)'."

error_reporting:
  destination: "Actions run log + $GITHUB_STEP_SUMMARY; ::error:: annotations for the doppler-auth-vs-boot disambiguation; capture.log uploaded as an artifact on non-PASS (added by this PR)."
  fail_loud: true

failure_modes:
  - mode: "The poll cannot poll — errexit kills the step on the first TRANSIENT (THIS BUG)."
    detection: "Arm 13/13b execute the real extracted step body under `bash -e` and assert attempt 2 is reached."
    alert_route: "CI red on the PR (infra-validation.yml)."
  - mode: "Silent false PASS — `set -e` re-armed before the PIPESTATUS read zeroes the verdict."
    detection: "Arm 13c mutates the ordering and requires the suite to go RED."
    alert_route: "CI red on the PR."

logs:
  where: "Actions run log; /tmp/rung2/capture.log uploaded on non-PASS; evidence artifact (retention 90d) on PASS."
  retention: "90 days."

discoverability_test:
  command: "gh run list --workflow=git-data-rung2-rehearsal.yml --limit 5 --json databaseId,conclusion && gh run view <id> --log | grep -c -- '--- capture attempt'"
  expected_output: "A count > 1 proves the poll polled. A count of exactly 1 alongside a failed conclusion is this bug's signature."
```

## Architecture Decision (ADR/C4)

**No new ADR; ADR-149 amended by one line** (see Phase 4.2). The plan's earlier claim that
ADR-149 item 4 already records *this* poll was **wrong** — item 4's poll is the birth-job poll
in `apply-web-platform-infra.yml`. Nothing in `## Decision` or the alternatives table changes,
and the interlock's contract is untouched; the correction is to a factual disposition claim,
the house form for this ADR.

**C4:** no impact — no new external actor, external system, container/data store, or
actor↔surface access relationship. A shell-flag fix inside an existing step moves no element
and no edge.

## Skipped Gates

- **Network-Outage Deep-Dive (deepen-plan 4.5) — evaluated, not applicable.** The keyword scan
  fires on `unreachable` (×5) and `firewall` (×1), but both are false positives: `unreachable`
  is used throughout in the **code-reachability** sense (*"`rc=0` is unreachable on attempt 1"*,
  *"the `::error::` branch is unreachable"*), and the single `firewall` hit is the IaC line
  below stating the plan introduces **no** firewall rule. There is no connectivity symptom
  here — the root cause was measured and reproduced locally, not inferred from a failed
  connection — and the rehearsal Terraform root contains no `provisioner "file"`,
  `provisioner "remote-exec"`, or `connection { type = "ssh" }` block (verified), so the
  resource-shape trigger does not fire either. No `hr-ssh-diagnosis-verify-firewall`
  telemetry is emitted: recording this as an application of that rule would misreport a
  keyword collision as a real SSH triage.
- **Downtime & Cutover (deepen-plan 4.55)** — no reboot/replace class (no Terraform resource
  changes at all), no database-lock class (no migrations), no deploy/router class. The
  `deploy-docs.yml` change makes deploys *less* likely to abort, not more.

- **Encryption Posture** — no `.tf`, no `supabase/migrations/*.sql`, no `cloud-init*.yml`, no
  `docker-compose*.yml`; no persistent store, no new cross-component connection.
- **Infrastructure (IaC)** — no new server, service, cron, vendor, DNS, cert, secret, or
  firewall rule. The rehearsal host comes from pre-existing, untouched Terraform.
- **GDPR** — no schema, migration, auth flow, API route, or `.sql`; no LLM processing of
  operator data; threshold `none`.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (60 open) against every
path in **Files to Edit**. One match: **#2965** *"evaluate build-time critical-CSS extractor
for Eleventy docs"* on `deploy-docs.yml`. **Disposition: Acknowledge** — unrelated concern
(CSS build pipeline vs. an errexit guard in the monitor steps). #2965 stays open.

## Domain Review

**Domains relevant:** Engineering only. **Product/UX Gate:** not applicable — no
`## Files to Edit` path matches any UI-surface glob. Tier NONE.

**Engineering assessment:** the risk is not the three-line change but the guard. The existing
43-assertion suite is fully green against a poll that cannot poll — a measured demonstration
that text-grep guards do not cover control flow. The plan's centre of gravity is arms 13/13b/13c.

## Decision Challenges (surfaced, not auto-applied)

Per ADR-084 these are **User-Challenge / Taste** — they alter operator-stated scope, so they are
recorded rather than silently applied. `ship` renders these into the PR body and files an
`action-required` issue.

1. **A standalone repo-wide errexit lint was CUT.** The task asked to *"consider pinning that
   no `run:` step in this workflow relies on an errexit posture its own `set` line
   contradicts."* It was considered and measured, and four of six reviewers rejected the
   standalone-lint form:
   - Measured over **631** `run:` bodies: its rule matches **1** — the bug itself. **0 of the
     3** sibling bugs this PR fixes read `PIPESTATUS` at all, so it would have caught none of
     them. A `PIPESTATUS`-or-`var=$?` rule matches 16; the `set`-omits-`-e` rule matches 56.
   - As specified it **certifies the false-PASS shape** (Kieran P0): `set +e` → pipeline →
     `set -e` → read satisfies the rule and always yields rc=0.
   - It also bans two *correct* forms (`if pipeline; then … else rc=${PIPESTATUS[0]}` and
     `pipeline || rc=${PIPESTATUS[0]}`, both errexit-exempt).
   - Comparable in-repo lint pairs cost 234–793 LOC, and `lint-workflows.sh` already exists as
     a workflow-body scanner. **Build-vs-buy was measured, not assumed:** actionlint (with
     shellcheck) against a synthesized workflow carrying this exact shape returns only
     `SC2034 … i appears unused` — nothing about errexit, `PIPESTATUS`, or the dead retry.
     That is structural: shellcheck lints each `run:` body as a standalone script and cannot
     know GitHub invokes it as `bash -e {0}`; the `-e` lives in the *invocation*, outside the
     artifact shellcheck sees. So a bespoke lint **is** warranted eventually — which argues
     for a well-shaped one, not this one. ("Make actionlint blocking" is a separate ~93-finding
     remediation project, tracked in #7042; correctly out of scope here.)
   **Instead:** arm 13d pins exactly what was asked — *this workflow*, in an already-registered
   suite, ~15 lines, zero waivers — and the repo-wide lint is deferred to the tracking issue,
   to be shaped *after* the 17-step audit determines the real rule.
2. **Operator-journey scope was added** beyond the stated ask: the `## After a PASS` runbook
   procedure and the non-PASS `capture.log` upload (Phase 1.4/4.1). Rationale: spec-flow found
   the artifact→PR path is otherwise a dead end for a non-technical operator
   (`hr-weigh-every-decision-against-target-user-impact`), and on the two paths where diagnosis
   is needed the diagnostic file is currently discarded. Both are docs/config, neither fires
   the rehearsal, so the Scope Limits hold.
3. **A `capture_only: <run_id>` recovery input was considered and NOT added.** spec-flow
   correctly notes the capture script does not need the host (Better Stack rows outlive
   teardown by weeks), so a re-query would be a free retry instead of another host. It is real
   value and ~15 lines, but it is a new feature on a workflow this PR is trying to make
   *correct*, and the 16-minute deadline it hedges is unmeasured. Deferred to the tracking
   issue; AC15's live-anchor probe reduces the same risk at zero cost.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **`set -e` re-armed before the read → silent false PASS** (measured: exit 0, 1 attempt, `capture_rc=0`, green PASS summary). | The ordering rule is stated in the Phase 1 comment, AC2, and arm 13c, which requires the suite to go RED on the mutation. |
| `\|\| true` regression → TRANSIENT reads as PASS. | Banned with the measurement; AC2 greps the extracted body; the arm-13 stub only PASSes on attempt 3. |
| Restoring `-e` breaks something else in the step. | Measured exempt: `[[ … ]] && break` (non-final `&&`), `(( … ))` and `grep -q` (if-conditions). Arm 13 executes the whole body, so collateral breakage is a red arm, not a production dispatch. |
| The guard tests a drifting copy. | Extraction is by **`id: capture`** from the live YAML (NOT the step name — see Phase 2 arm 13.1; this row said "name" in an earlier draft and was corrected at implementation); a missing id yields nothing and FAILs the arm with a message naming it. |
| Arms 13/13b/13c interfere via hardcoded `/tmp/rung2`. | `rm -rf /tmp/rung2` before each arm; header notes they cannot run concurrently. |
| Arm silently skipped when python3 is absent. | Arms placed **inside** the existing `if command -v python3` block, whose `else` already fails. |
| `deploy-docs.yml` is the only production-path file in the diff (`push: main`, mutates live Sentry monitor state). | All four named sites guarded; each already branches on an HTTP code, so `\|\| status="000"` is the house form and preserves existing control flow. |
| Sibling fixes arm dormant automations. | Disclosed in the PR body: the next advisor scan may file a legitimate p1-high security issue previously masked as class B, and the closure guard will begin reopening issues. Expected, not a regression. |
| Anti-vacuity floor left stale. | AC4 requires the `-lt` floor to equal the new total at all three sites. |

## Sharp Edges

- **`set -e` is a builtin, therefore a pipeline, therefore it RESETS `PIPESTATUS`.** Any
  `rc=${PIPESTATUS[0]}` must be the first command after its pipeline. This is the single most
  dangerous edit anyone can make to the fixed step, and it fails silently toward PASS.
- **`grep -c 'set -uo pipefail'` is not a sufficient AC for this class.** Buggy and fixed
  bodies have *identical* grep counts (1/1/1) for `seq 1 N`, `PIPESTATUS`, `capture_rc`.
- **An unanchored `grep 'set -e'` also matches every `set -euo pipefail` line** (9 hits in this
  file). Anchor with `^[[:space:]]*set [-+]e$`.
- **`grep -c` exits 1 when the count is 0**, so an AC asserting "count is 0" goes red under a
  `set -e` runner. Use `! grep -q`.
- **`|| true` already appears twice in this workflow** in unrelated steps — any `|| true` AC
  must scope to the extracted capture body, not the file.
- **`set +e` is not scope-aware by position alone.** A body with an unrelated earlier
  `set +e`, a `set -e` re-arm, and *then* a `PIPESTATUS` read satisfies "contains `set +e`
  before the read" while being exactly the bug. Any future rule must key on the **nearest
  preceding toggle**, not mere presence.
- **Do not bulk-flip `set -uo` → `set -euo`.** On a body that needs errexit off, the flip
  preserves broken runtime behaviour while making the code look deliberate.
- `apps/web-platform/infra/*.test.sh` is registered by a **single-line**
  `run: bash …` step in `infra-validation.yml`; a multi-line `run: |` block runs in CI but is
  invisible to `run-registered-suites.sh`, and the extraction class excludes `/`, so suites
  must sit at the infra root.
