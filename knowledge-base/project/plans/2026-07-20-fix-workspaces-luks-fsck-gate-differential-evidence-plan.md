---
title: "fix(infra): make the workspaces-luks git-fsck gate differential and self-reporting"
type: fix
date: 2026-07-20
branch: feat-one-shot-fsck-gate-differential-evidence
lane: cross-domain
issue_ref: "Ref #6733"
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# fix(infra): make the workspaces-luks git-fsck gate differential and self-reporting

> `Ref #6733` — **never `Closes`**. #6733 is closed only by a *completed* cutover, never by a merge.
> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Production cutover run `29725194755` (2026-07-20, `dry_run=false`) reached further than any real
cutover has: the mkfs fix held (`STAGING_TARGET result=ok fs=ext4 mapper=/dev/mapper/workspaces`,
no wrong-device write, no stray), the G4 read-probe fix held (C1's `.d..t...... ./` mtime abort did
not recur), bulk rsync + FREEZE + the G3 manifest all passed. It then safe-aborted at the `git fsck`
gate with `FSCK FAIL` on 8 of 10 workspaces and

```
FATAL: git fsck --full failed in 8 workspace(s) — object corruption on the LUKS copy (C1/AC26)
```

DP-6 auto-rolled back; production is healthy (`app.soleur.ai/health` = HTTP 200).

The gate, at `apps/web-platform/infra/workspaces-cutover.sh` (content anchor — the line
`git -C "$ws" fsck --full >/dev/null 2>&1 || { fsck_fail=$((fsck_fail + 1)); log "FSCK FAIL: $ws"; }`),
has two defects, and they are the *same two defects* the C1 verify had before #6604-followup and the
G4 holder probe had before #6735. This is now a three-instance pattern, not a coincidence:

1. **Evidence discarded.** `>/dev/null 2>&1` throws away the only datum that can distinguish a
   corrupt object from a benign repo condition. The gate reports a path and nothing else, and there
   is no way to diagnose it without SSH — forbidden by `hr-no-ssh-fallback-in-runbooks`.
2. **Wrong property measured.** The gate's job is *"did the copy corrupt anything"*. What it actually
   tests is *"are these repos pristine"*. 8-of-10 is the signature of a systemic pre-existing
   property, not of rsync corruption — and any such property fails identically on the plaintext
   source, meaning the copy was fine and the abort was a false positive.

The fix makes the gate **differential** (fail only on a delta between source and copy) and
**self-reporting** (a monitored `SOLEUR_WORKSPACES_LUKS_FSCK` marker per workspace carrying the
actual fsck evidence). The gate is *not* weakened: a genuine wrong-device or corrupting copy still
aborts, and the differential is computed on the **error-line set**, not on the exit code alone, so
a repo with a pre-existing fault that *also* acquires a new fault on the copy still aborts.

### The blindness trap this plan must not fall into

There is a leading hypothesis (H1 below, **UNKNOWN** — the deciding datum was discarded) that the 8
failures are `fatal: detected dubious ownership in repository at '/mnt/data-luks/workspaces/<uuid>'`.
The cutover runs as **root** on the host; the container runs as **uid 1001** (`apps/web-platform/Dockerfile`
— `useradd --no-log-init --uid 1001 -m soleur` / `USER soleur`), so every workspace repo is owned by
1001 and git ≥ 2.35.2 refuses to operate on it as root with rc 128. That fires *before a single
object is read*.

If H1 is true, then a **naive rc-only differential is a no-op disguised as a fix**: the source fails
identically, every workspace classifies `preexisting`, the gate goes green, and it inspects exactly
zero objects on every future cutover — while the plaintext original is wiped in Phase 5. That is
precisely "weaken the gate into a no-op", arrived at by a route that looks like a correctness fix.

So the plan has two non-negotiable halves:

- **(A) make the probe able to run at all** — invoke fsck so a not-owned-by-root repo is actually
  inspected, and treat an fsck that *could not inspect* (rc 128 / setup-class failure) as its own
  classification (`probe_failed`) that **aborts**, never as `preexisting`; and
- **(B) make the verdict differential** — so a genuine pre-existing object fault does not abort.

Half (A) is what keeps half (B) honest. Shipping (B) alone would close #6733's symptom and blind the
gate permanently.

## Hypotheses

Per the Sharp Edge on hypothesis honesty: **the deciding datum (each repo's fsck stderr) was
discarded at the source by the very defect this plan fixes.** No verdict below may read CONFIRMED or
REFUTED. All are UNKNOWN; the plan's primary deliverable is the probe that decides them on the next
run, and the plan must be correct under *every* one of them.

| # | Hypothesis | Verdict | Discriminating field in the new marker |
|---|---|---|---|
| H1 | `detected dubious ownership` (root fsck-ing uid-1001 repos) — rc 128, zero objects read | **UNKNOWN** (strongest prior; the ownership asymmetry is verified in the Dockerfile, the *failure* is not) | `dst_rc=128` + `first="fatal: detected dubious ownership…"` → `probe_failed` |
| H2 | `objects/info/alternates` holding absolute paths that do not resolve at the `/mnt/data-luks/...` prefix | **UNKNOWN** | `first="fatal: bad object …"` / `broken link` present on dst, absent on src → a *true* `copy_corruption` (the prefix genuinely changed) |
| H3 | Partial/blobless clones (`promisor` objects) that `fsck --full` reports as missing | **UNKNOWN** | identical error-line set on src and dst → `preexisting` |
| H4 | Worktree gitdir pointers | **UNKNOWN — and probably unreachable**: the loop's `[ -d "$ws/.git" ] || continue` skips worktrees (`.git` is a *file* there), so a worktree workspace is never fsck'd at all | new `classification=skipped reason=no_git_dir` row makes the coverage hole visible |
| H5 | Genuine object corruption introduced by the copy | **UNKNOWN** — but *disfavoured*: C1's `rsync -aHAXi --checksum --delete --dry-run` verify passed with **0** differences immediately before this gate, and a `du --apparent-size` byte match passed. A copy that corrupted 8 of 10 repos' objects while passing a full-tree checksum verify is close to physically impossible | error lines present on dst and absent on src → `copy_corruption` → **abort** |

Note the count arithmetic that H1/H4 jointly explain and that no single-cause hypothesis explains as
cleanly: 10 workspace directories, 8 fsck failures ⇒ 2 directories had no `.git` **directory** and
were `continue`d. Under H1 the 8 that *were* probed failed **100%**, which is a systemic-cause
signature, not a corruption signature. This is a prior, not a proof.

## Research Reconciliation — Spec vs. Codebase

| Claim (task framing) | Codebase reality | Plan response |
|---|---|---|
| "Current code, line 1621" | Line numbers drift; the gate is inside the `if [ "$DRY_RUN" != "1" ]` G3 block, after `verify_byte_identity` and the `du` byte assert. Cite the **content anchor** (`git -C "$ws" fsck --full >/dev/null 2>&1`) per `cq-cite-content-anchor-not-line-number` | All ACs anchor on content, never on a line number |
| "the corresponding plaintext source workspace" | Source root is `$MOUNT/workspaces/<id>`; copy root is `$STAGING/workspaces/<id>` (`$MOUNT` becomes the mapper only *after* the repoint, which is later) | Pair by basename `<id>`; a dst id with no src counterpart is its own classification (`dst_only`) and **aborts** (a workspace that exists only on the copy is unexplained) |
| "follow existing `SOLEUR_WORKSPACES_LUKS_*` marker conventions" | Verified: summary row then per-item rows; every field `_vscrub`'d; `echo` **and** `logger -t "$LUKS_LOG_TAG"`; `feature=workspaces-luks op=workspaces-luks-<kebab>`; a cap constant (`VERIFY_DIFF_CAP`, default 40) | New `FSCK_MARKER_CAP` / `FSCK_OUT_CAP` follow the same shape |
| "emit a monitored marker" — does this need infra work? | **No.** `luks-monitor` is already allowlisted in `apps/web-platform/infra/vector.toml` (exact-value tag match). No Terraform, no vector change | `## Infrastructure (IaC)` — skipped, no new infra surface |
| "add cases to the loopback harness" | `workspaces-luks-loopback.test.sh` drives the cutover by `source`ing it (sourced-detection guard) and calling a **function** (`prepare_staging_target`, `verify_byte_identity`). The fsck gate is **inline in the main body** — not callable, therefore not testable | The gate must be **extracted into a function** (`verify_git_fsck_differential`) first. This is a prerequisite of the test, not a refactor for taste |
| "10 passing cases incl. L5b/L5c" | Verified: L1, L1b, L2, L3, L3b, L5a, L5b, L5b-control, L5c, L5d = 10 pass/fail cases (L4 is advisory and deliberately does not touch the counters) | New cases append as L6*; the harness's `executed`-count-zero guard and `unavailable()` fail-closed shape are untouched |
| "the source-side fsck can be hoisted out of the frozen window" | Confirmed feasible: the bulk rsync step (`writers live, no --delete`) runs **before** `freeze_writers`, and `$MOUNT` is readable there | Hoist — see Ordering below. With an explicit inline fallback for ids that have no baseline |

## Ordering — where each half of the differential runs, and why

```
  bulk rsync (writers live)
      │
      ├── NEW: fsck_baseline_source()        ← SOURCE fsck, OUTSIDE the freeze
      │        writes $FSCK_BASELINE_DIR/<id>.{rc,out}
      │        runs in BOTH the dry-run and real arms
      │
  FREEZE ─ quiesce ─ pass-2 delta ─ drop_caches ─ C1 verify ─ du assert
      │
      └── verify_git_fsck_differential()     ← DST fsck only, INSIDE the freeze
               reads the baseline; classifies; emits; aborts on delta
```

**Why the source side hoists cleanly.** A pre-existing repo condition on the plaintext source does
not change during the freeze *in the direction that matters*. Writers are live during the baseline,
so a repo can gain objects between baseline and gate — but that can only make the source baseline
**stale-optimistic** (baseline passed, source now has a fault). That direction is the *conservative*
one: it yields `copy_corruption` and **aborts**. It cannot produce a false green. The dangerous
direction (baseline records a fault the source does not have) requires the source to *heal* itself
during the freeze, which no writer does.

**Freeze-budget cost.** The measured fsck pass was ~4.5 min over 10 repos, held entirely inside the
freeze. Running both sides naively would roughly double that to ~9 min against a ≤20 min budget —
unacceptably close. Hoisting the source side keeps the **in-freeze** cost at ~4.5 min, i.e. *no
regression* on the frozen window, while paying ~4.5 min of unfrozen wall-clock before the freeze,
where writers are still live and users are unaffected. The PR body must state this explicitly.

**Missing baseline.** A workspace present on the copy but absent from the baseline (created between
the bulk rsync and the freeze) gets its source fsck run **inline** at gate time and is marked
`baseline=inline` in the marker. Correctness over freeze budget; this is bounded by the number of
workspaces created inside a ~10-minute window, i.e. normally zero.

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) another aborted cutover — the encryption-
at-rest migration slips again and every user's workspace stays on a plaintext volume; or, far worse,
(b) a cutover that *completes* with a blinded gate, wiping the plaintext original in Phase 5 while a
corrupt object on the LUKS copy goes uncaught — a user opens their workspace and their git history
is unreadable, with no source to restore from.

**If this leaks, the user's data is exposed via:** the new marker is written to stdout, to the run
log, and to Better Stack via `logger -t luks-monitor`. It carries a workspace **UUID** (pseudonymous)
and a bounded prefix of `git fsck` output. `git fsck` output is object-id-shaped by default; it
becomes **path-bearing** if `--name-objects` is passed. The plan therefore forbids `--name-objects`,
`_vscrub`s every field, and truncates output to `FSCK_OUT_CAP` bytes.

**Brand-survival threshold:** `single-user incident` — one user with an unreadable repo and no
plaintext fallback is a brand-ending event. CPO sign-off required at plan time; `user-impact-reviewer`
runs at review time.

## Implementation Phases

### Phase 0 — Preconditions (verify before writing code)

0.1 Re-read the gate's content anchor on `origin/main` and confirm it is unchanged since this plan:
`git show origin/main:apps/web-platform/infra/workspaces-cutover.sh | grep -n 'fsck --full'`.

0.2 Establish the **local** exit-code semantics of every fsck invocation form this plan relies on —
do not infer them (Sharp Edge: exit-code semantics must be read, not assumed). Build a throwaway
repo, `chown` it to a different uid, and record, as pasted evidence in the PR body:
- `git -C <repo> fsck --full` as root on a foreign-uid repo → expected rc **128** + `dubious ownership`
- `git -c safe.directory=<repo> -C <repo> fsck --full` as root on the same repo → expected rc **0**
- `git fsck --full` on a repo with a genuinely corrupted loose object → expected rc **non-zero (1)**
  with error lines on **stderr**
- a repo with only *dangling* objects → expected rc **0** (dangling is a notice, not an error)

The last one is load-bearing: it establishes that "rc 0" is the correct pass and that dangling
objects will not be misread as faults.

0.3 Confirm `luks-monitor` is allowlisted in `apps/web-platform/infra/vector.toml` (it is — exact-value
tag match) so the new marker needs **no** infra change.

0.4 Grep the harness for the case-id namespace so the new cases do not collide:
`grep -nE '^\s*(ok|no) "L' apps/web-platform/infra/workspaces-luks-loopback.test.sh`.

### Phase 1 — RED: failing tests first (`cq-write-failing-tests-before`)

Add to `apps/web-platform/infra/workspaces-luks-loopback.test.sh`, in a new Session D built on the
existing `new_session` helper (real loopback + dm-crypt — this suite never stubs the block layer).
All cases drive the **real** `verify_git_fsck_differential` by `source`ing the cutover, exactly as
L3/L3b drive `verify_byte_identity`. Every assertion greps a **file** directly (never a pipe — the
harness's SIGPIPE rule is load-bearing).

Fixture: build real git repos in `$SRC_DIR/workspaces/` (`git init`, one commit) and rsync them onto
the mapper, mirroring L3's copy step.

| Case | Scenario | Must assert |
|---|---|---|
| **L6a** | clean repos both sides | rc 0, no abort, marker row per ws with `classification=ok`, `src_rc=0 dst_rc=0` |
| **L6b** | **copy corruption still aborts** (positive control) — truncate/overwrite a loose object under `$STAGING/workspaces/<id>/.git/objects/` only | rc ≠ 0, `DIE:` mentions the gate, marker `classification=copy_corruption` naming that `<id>`, and `first=` carries a real fsck error string |
| **L6c** | **both-fail does not abort** — corrupt the *same* object on **both** sides (corrupt on src, then rsync) | rc **0**, marker `classification=preexisting`, log line explicitly says pre-existing repo condition |
| **L6d** | **both-fail-plus-new-fault still aborts** — a pre-existing fault on both sides **and** an additional fault only on the copy | rc ≠ 0, `classification=copy_corruption`. This is the case that proves the differential is on the **error-line set**, not on rc |
| **L6e** | **probe-failed aborts** (the H1 trap) — make the copy's repo unreadable to the probe (foreign uid / unreadable `objects/`) so fsck cannot inspect | rc ≠ 0, `classification=probe_failed`. Proves a gate that *cannot see* never reports green |
| **L6f** | `src_only` — fault on the source, clean copy | rc **0**, `classification=src_only`, and it is logged (surprising, worth seeing) |
| **L6g** | `dst_only` — a workspace on the copy with no source counterpart | rc ≠ 0, `classification=dst_only` |
| **L6h** | **truncation** — a repo whose fsck output is pathologically large | total emitted marker bytes bounded; `first=` ≤ `FSCK_OUT_CAP`; row count ≤ `FSCK_MARKER_CAP`; a `truncated=1` field present |
| **L6i** | **mutation / load-bearing control** (the L5d discipline) — copy the cutover, `sed` the abort predicate into a vacuous `true`, re-run **L6b**; it MUST flip green | proves L6b's abort is not decorative. Assert the `sed` landed before trusting the result |
| **L6j** | `no_git_dir` coverage row — a workspace directory with no `.git` **directory** | `classification=skipped reason=no_git_dir` emitted (H4's coverage hole becomes visible rather than silent) |

Run the suite; **L6a–L6j must fail** before Phase 2 (the function does not exist yet). Record the
red output in the PR body.

### Phase 2 — GREEN: extract and rewrite the gate

**2.1 Extract** the inline loop into a function beside `verify_byte_identity`, with the same calling
discipline (called **directly** in the main body — never in `$(…)`, a pipe, or a subshell — so
`die`'s `exit 1` reaches the EXIT trap and rollback):

```
verify_git_fsck_differential <src_root> <dst_root>     # e.g. "$MOUNT" "$STAGING"
fsck_baseline_source <src_root>                        # hoisted, pre-FREEZE
_fsck_one <repo> <rc-file> <out-file>                  # single probe, bounded capture
```

**2.2 The probe (`_fsck_one`)** — half (A), the part that makes the gate able to see:

- `git -c safe.directory=<repo> -C <repo> fsck --full --no-progress` — `safe.directory` scoped to the
  single repo being probed, never a global `*`, and never a persisted config write.
- **Do not** pass `--name-objects` (it makes output path-bearing → user-data leak into Better Stack).
- Redirect stdout and stderr to **separate** files (the exact lesson from the C1 verify's defect (1):
  folding streams lets benign noise contaminate the signal). fsck errors land on stderr.
- Capture to `mktemp` files, never to a shell variable — a pathological repo can emit megabytes.
- Record rc.

**2.3 Classification** — half (B). Normalize each side's error lines (sort; prefer raw line-set
equality — the simplest thing that works), then:

| Condition | `classification` | Abort? |
|---|---|---|
| probe could not inspect (rc = 128, or a `fatal:` setup-class line) on either side | `probe_failed` | **yes** |
| dst id has no src counterpart | `dst_only` | **yes** |
| dst error-line set contains ≥1 line absent from src's set | `copy_corruption` | **yes** |
| `dst_rc != 0` and `src_rc != 0` and dst's error set ⊆ src's set | `preexisting` | no (logged as a pre-existing repo condition) |
| `src_rc != 0`, `dst_rc = 0` | `src_only` | no (logged — surprising) |
| both rc 0 | `ok` | no |
| no `.git` directory | `skipped` (`reason=no_git_dir`) | no (logged; coverage hole made visible) |

The abort message must name the count **and** point at the marker, mirroring the C1 verify's
message shape:

> `git fsck --full regressed on N workspace(s) between the plaintext source and the LUKS copy — see the SOLEUR_WORKSPACES_LUKS_FSCK marker for the workspace id(s) and the fsck output`

`preexisting` / `src_only` / `skipped` counts are logged and carried on the summary row but do
**not** contribute to the abort count.

**2.4 The marker** — follow `emit_verify_diff`'s shape exactly. Emit **before** any `rm` of the temp
files and **before** `die` (defect (2) in the C1 verify was literally "rm before log"):

Summary row:
```
SOLEUR_WORKSPACES_LUKS_FSCK feature=workspaces-luks op=workspaces-luks-fsck \
  total=<n> ok=<n> preexisting=<n> src_only=<n> copy_corruption=<n> probe_failed=<n> \
  dst_only=<n> skipped=<n> host=<hostname>
```

Per-workspace row (one per workspace, `ws=` **last** so a spaced value is captured whole — the
convention `emit_verify_diff` uses for `path=`):
```
SOLEUR_WORKSPACES_LUKS_FSCK feature=workspaces-luks op=workspaces-luks-fsck idx=<k> \
  classification=<ok|preexisting|src_only|copy_corruption|probe_failed|dst_only|skipped> \
  src_rc=<n> dst_rc=<n> baseline=<hoisted|inline|missing> truncated=<0|1> \
  first=<_vscrub'd, FSCK_OUT_CAP-truncated first line of the discriminating fsck output> ws=<id>
```

`first=` is the **discriminating** line: for `copy_corruption`, the first dst-only error line (not
merely dst's first line — the first line is often shared with src and would be useless). Every field
`_vscrub`'d. `echo` **and** `logger -t "$LUKS_LOG_TAG"`, per convention. On any aborting
classification, also `emit_drift workspaces_luks_fsck_<classification>` so Sentry pages with a
discriminating reason, mirroring `emit_verify_diff`'s tail.

**2.5 Bounds.** `FSCK_MARKER_CAP="${WORKSPACES_FSCK_MARKER_CAP:-40}"` (rows) and
`FSCK_OUT_CAP="${WORKSPACES_FSCK_OUT_CAP:-200}"` (bytes per `first=`), mirroring `VERIFY_DIFF_CAP`.
When rows are capped, log `… +N more` exactly as `emit_verify_diff` does. Aborting classifications
are emitted **first** so the cap can never truncate away the row that explains the abort.

**2.6 Hoist the source side.** Insert `fsck_baseline_source "$MOUNT"` immediately after the bulk
rsync step, writing `<id>.rc` / `<id>.out` into a run-scoped `mktemp -d`. It runs in **both** arms;
its failures are **never fatal** on their own (a source-side fault is not an abort condition — that
is the whole point), but a baseline that could not be produced for an id yields `baseline=missing`
and forces the inline path at gate time.

**2.7 Dry-run honesty.** No short-circuit. Specifically:
- The **source baseline runs in the dry-run arm too** and emits its rows. A rehearsal therefore
  reports the real pre-existing-condition landscape — the exact evidence that would have pre-empted
  this abort. This makes the rehearsal *more* informative; it does not make the real arm's gate
  weaker.
- The **dst side stays inside `if [ "$DRY_RUN" != "1" ]`**, unchanged, because there is no copy to
  fsck in a rehearsal. The dry-run log must say so in as many words — `(dry-run) source fsck baseline
  only; the differential gate does NOT run in this arm` — mirroring the advisory-holder-probe wording
  the dry-run G4 arm already uses. A rehearsal must never read as if the gate passed.

### Phase 3 — Verify

- Loopback suite: L6a–L6j green, all 10 pre-existing cases still green (20 pass/fail cases total).
- `bash -n` on the cutover and on the harness.
- `shellcheck` if the repo already runs it on this file (check `.github/workflows/infra-validation.yml`
  before asserting).
- Full `infra-validation.yml` job locally where feasible.

### Phase 4 — Learning

Write `knowledge-base/project/learnings/<topic>.md` (author picks the date at write time — never a
plan-prescribed dated filename). The learning is the **three-instance pattern**: C1 verify, G4 holder
probe, and now the fsck gate all shipped as fail-closed gates that discarded the evidence needed to
answer the question they raised. Each one cost an irreversible-freeze approval to discover. The
generalizable rule — candidate for AGENTS.md only if the always-loaded budget permits (measure
`B_ALWAYS = wc -c AGENTS.md + AGENTS.core.md` against the 23000-byte cap first; if at cap, the
constitution is the right home):

> **A fail-closed gate must emit the evidence that discriminates its own verdict, on a durable
> channel, before it aborts.** A gate that can only say *that* it failed forces an SSH diagnosis that
> `hr-no-ssh-fallback-in-runbooks` forbids — so it is not merely inconvenient, it is unresolvable.
> Corollary: a gate whose probe can fail *for setup reasons* must classify that separately from a
> genuine finding, or a differential fix will silently convert it into a no-op.

## Files to Edit

- `apps/web-platform/infra/workspaces-cutover.sh` — extract + rewrite the gate; add
  `fsck_baseline_source`, `verify_git_fsck_differential`, `_fsck_one`, `emit_fsck_row`;
  add `FSCK_MARKER_CAP` / `FSCK_OUT_CAP`; insert the hoisted baseline call after the bulk rsync.
- `apps/web-platform/infra/workspaces-luks-loopback.test.sh` — Session D, cases L6a–L6j.

## Files to Create

- `knowledge-base/project/learnings/<topic>.md` (Phase 4).

No Terraform, no workflow, no vector.toml change (`luks-monitor` already allowlisted).

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` filtered on
`workspaces-cutover` returned zero matches.

## Acceptance Criteria

### Pre-merge (PR)

1. The content anchor `git -C "$ws" fsck --full >/dev/null 2>&1` no longer exists in
   `workspaces-cutover.sh`:
   `grep -c 'fsck --full >/dev/null 2>&1' apps/web-platform/infra/workspaces-cutover.sh` → `0`.
2. `grep -c -- '--name-objects' apps/web-platform/infra/workspaces-cutover.sh` → `0` (no path-bearing
   fsck output can reach Better Stack).
3. `grep -c 'safe.directory' apps/web-platform/infra/workspaces-cutover.sh` → ≥ 1, and every
   occurrence is `-c safe.directory=` scoped to a single repo path — **no** wildcard value and no
   `git config --global` write:
   `grep -cE "safe\.directory='?\*|config --global" …` → `0`.
4. The seven classification tokens each appear in the script:
   `for c in ok preexisting src_only copy_corruption probe_failed dst_only skipped; do grep -q "classification=$c" … || exit 1; done`.
5. The loopback suite reports **20** pass/fail cases with **0** failures:
   `sudo bash apps/web-platform/infra/workspaces-luks-loopback.test.sh` → exit 0, output matches
   `workspaces-luks-loopback: 20 passed, 0 failed`.
6. **L6i (mutation) is green** — neutering the abort predicate flips L6b to green. Without this,
   L6b's abort assertion could be vacuous.
7. **L6e is green** — an un-inspectable copy classifies `probe_failed` and **aborts**. This is the AC
   that proves the fix is not a no-op under H1.
8. The dry-run arm emits the source baseline rows **and** an explicit statement that the differential
   gate did not run:
   `grep -c '(dry-run) source fsck baseline only' apps/web-platform/infra/workspaces-cutover.sh` → ≥ 1.
9. Phase 0.2's four measured fsck exit codes are pasted into the PR body (not asserted from memory).
10. The freeze-budget cost is stated in the PR body: in-freeze fsck cost unchanged at ~4.5 min
    (dst only); ~4.5 min added **before** the freeze (src baseline, writers live); the source-hoist
    ordering and its staleness argument explained.
11. PR body says `Ref #6733` and **does not** contain `Closes #6733`:
    `gh pr view <N> --json body -q .body | grep -c 'Closes #6733'` → `0`.
12. `bash -n` passes on both edited files.
13. Marker emission precedes cleanup: in `verify_git_fsck_differential`, every `rm -f` of the capture
    tempfiles occurs **after** the emit call — asserted by a source-order check, mirroring the C1
    verify's own defect-2 guard.

### Post-merge

14. **None.** The next cutover run is approved separately (an irreversible freeze —
    `hr-menu-option-ack-not-prod-write-auth`), and #6733 stays open until a cutover completes. This
    PR merges with no post-merge step of any kind.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_WORKSPACES_LUKS_FSCK summary row (one per cutover run, both arms for the src baseline)
  cadence: per cutover run (approved, irreversible-freeze workflow)
  alert_target: Better Stack via `logger -t luks-monitor` (tag already allowlisted in vector.toml);
                Sentry via emit_drift on any aborting classification
  configured_in: apps/web-platform/infra/workspaces-cutover.sh (emitter);
                 apps/web-platform/infra/vector.toml (tag allowlist, unchanged)
error_reporting:
  destination: Sentry (emit_drift op=workspaces-luks-drift, reason=workspaces_luks_fsck_<classification>)
               + Better Stack + the GitHub Actions run log (echo)
  fail_loud: true — copy_corruption / probe_failed / dst_only abort the run and roll back via the EXIT trap
failure_modes:
  - mode: copy corrupted an object
    detection: dst error-line set not a subset of src error-line set
    alert_route: abort + marker classification=copy_corruption + emit_drift
  - mode: probe could not inspect the repo (dubious ownership, unreadable objects)
    detection: rc 128 or a fatal: setup-class first line
    alert_route: abort + classification=probe_failed + emit_drift — never silently green
  - mode: pre-existing repo condition (partial clone, alternates, dangling)
    detection: identical error-line set on both sides
    alert_route: logged, marker classification=preexisting, NO abort
  - mode: workspace on the copy with no source counterpart
    detection: basename set difference
    alert_route: abort + classification=dst_only
  - mode: workspace never inspected (no .git directory)
    detection: -d "$ws/.git" false
    alert_route: marker classification=skipped reason=no_git_dir — coverage hole visible, not silent
  - mode: pathological fsck output
    detection: capture exceeds FSCK_OUT_CAP / FSCK_MARKER_CAP
    alert_route: truncated=1 on the row + "… +N more" in the log
logs:
  where: GitHub Actions run log (echo) + Better Stack (logger -t luks-monitor)
  retention: Better Stack default retention for the luks-monitor tag
discoverability_test:
  command: gh run view <run-id> --log | grep SOLEUR_WORKSPACES_LUKS_FSCK
  expected_output: >-
    one summary row with the seven counts, plus one row per workspace carrying
    classification=, src_rc=, dst_rc=, baseline=, and a first= excerpt of the actual fsck output —
    sufficient to decide H1..H5 without any shell on the host
```

No `ssh` appears in the discoverability test — the entire point of this change is that the next
cutover self-reports.

### Affected-surface observability

The cutover host is an operator-blind surface (`hr-no-ssh-fallback-in-runbooks`). The `first=` field
is the in-surface probe, and its fields discriminate **all five** competing hypotheses in a single
event: `dst_rc=128` + a `dubious ownership` excerpt decides H1; a `bad object` / `broken link`
excerpt with dst-only membership decides H2; identical error sets decide H3; the
`skipped reason=no_git_dir` rows decide H4; a dst-only error set with `src_rc=0` decides H5. This
satisfies the "one event decides the root cause" requirement — the exact property the current gate
lacks.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure/tooling change to a production cutover script. Three concerns, all
folded into the plan body: (1) the gate must be extracted to a function before it is testable — the
harness can only drive functions; (2) an rc-only differential is a no-op under H1, so the
`probe_failed` classification and the `safe.directory` scoping are load-bearing, not polish; (3) the
source-side hoist must preserve the freeze budget and its staleness direction must be argued, not
assumed. No Product/UX surface (no file in `## Files to Edit` matches any UI-surface glob) — Product
gate **NONE**.

## Architecture Decision (ADR/C4)

**Skipped** — no architectural decision. This is a bug fix to an existing gate on an existing
surface: no ownership/tenancy boundary moves, no new substrate, no resolver/trust boundary change,
no divergence from an existing ADR. A competent engineer reading the current ADRs + C4 would not be
misled about the system after this ships. C4 completeness check: all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` are to be reviewed at
/work time for this change's external human actors (none new — the cutover has no external
correspondent), external systems/vendors (none new — the marker rides the already-modeled
`luks-monitor` → vector → Better Stack path, and Sentry is already modeled), containers/data stores
(none new — `$MOUNT` / `$STAGING` are the same already-modeled volumes), and actor↔surface access
relationships (unchanged). If any of those four enumerations turns up an unmodeled element at /work
time, the `.c4` edit is in scope for this PR, not a follow-up.

## Infrastructure (IaC)

**Skipped** — no new infrastructure surface. No server, service, cron, vendor account, DNS record,
TLS cert, secret, firewall rule, or monitoring webhook is introduced. The new marker rides the
`luks-monitor` syslog tag already allowlisted in `apps/web-platform/infra/vector.toml`. Phase 2.8
reviewed; see the `iac-routing-ack` marker at the top of this file.

## GDPR / Compliance Gate

The canonical regulated-data regex does not match (no schema, migration, auth flow, API route, or
`.sql` file). Trigger (b) *does* fire — `brand_survival_threshold: single-user incident` — so the gate
is invoked. The one substantive finding is folded in above: `git fsck` output becomes **path-bearing**
under `--name-objects`, and file paths inside a user's workspace are personal data once they reach
Better Stack. AC2 forbids `--name-objects`; `_vscrub` + `FSCK_OUT_CAP` bound what can be emitted;
workspace **UUIDs** (pseudonymous, already emitted by sibling markers) are the only identifier. No
new processing activity, no Article 30 entry required.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The differential silently blinds the gate** (H1): source fails identically, everything classifies `preexisting`, zero objects ever inspected | `probe_failed` is a **separate, aborting** classification; `safe.directory` scoping makes the probe able to run; **L6e** asserts it. This is the single most important AC in the plan |
| A pre-existing fault masks a co-located new fault | Differential is on the **error-line set**, not on rc — a new dst-only line aborts even when both sides fail. **L6d** asserts exactly this |
| Source baseline is stale (writers live during the baseline) | Staleness can only run in the conservative direction (baseline passed, source later faults ⇒ `copy_corruption` ⇒ abort). A false green requires the source to heal itself mid-freeze, which no writer does. Argued in Ordering above |
| Workspace created between baseline and gate | `baseline=missing` → inline source fsck at gate time, `baseline=inline` on the row. Never treated as `ok` by default |
| Freeze budget regression | Only the dst side stays in the freeze — in-freeze cost is **unchanged** at ~4.5 min against ≤20 min. Stated in the PR body per AC10 |
| Pathological repo blows up the log | `FSCK_OUT_CAP` (bytes) + `FSCK_MARKER_CAP` (rows), capture to tempfiles not variables, aborting rows emitted first so the cap cannot hide the explanation. **L6h** asserts it |
| Rehearsal reads as green where the real arm would abort | Dst side stays inside the `DRY_RUN != 1` gate; dry-run log states in as many words that the differential gate did not run. **AC8** |
| Extraction changes gate behaviour beyond the intended fix | The function is called **directly** in the main body (never in `$(…)`/a pipe/a subshell) so `die`'s `exit 1` reaches the EXIT trap → rollback, matching `verify_byte_identity`'s documented discipline |
| Worktree-shaped workspaces are never fsck'd (H4) | Deliberately **not** changed in this PR — widening `-d "$ws/.git"` would change gate *coverage* in a PR whose job is to change gate *verdict logic*. Instead the hole is made visible via `classification=skipped reason=no_git_dir` (**L6j**); if the next run's marker shows skipped > 0, file a follow-up |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Drop the fsck gate | Forbidden by the task and correct to forbid: the plaintext original is wiped in Phase 5, so this is the last chance to catch a corrupting copy |
| Narrow the gate (ignore certain fsck error classes) | The same failure shape as narrowing C1 — an allowlist of "benign" errors is a guess about which corruption matters, made in advance and without evidence |
| rc-only differential (as literally specified) | Adopted as the *baseline*, then strengthened to error-line-set membership so a pre-existing fault cannot mask a new one (L6d), and split so an un-inspectable probe aborts (L6e). Both are strict strengthenings; neither weakens any specified behaviour |
| Run both fsck passes inside the freeze | ~9 min inside a ≤20 min budget. Hoisting the source side costs nothing in correctness (staleness runs conservative) and keeps the in-freeze cost flat |
| Snapshot the source and fsck the snapshot | Removes the staleness question entirely, but needs LVM/btrfs snapshot support on the volume being migrated *away from*. Disproportionate; the staleness direction is already conservative |
| Widen `-d "$ws/.git"` to cover worktrees now | Changes gate coverage in a verdict-logic PR. Made visible via `skipped` rows instead; follow-up if the next run shows any |

## Test Scenarios

Covered by L6a–L6j above (real loopback + dm-crypt, no stubbed block layer). The suite's existing
fail-closed properties are preserved untouched: `unavailable()` exits non-zero with the literal
`LOOPBACK_UNAVAILABLE` token (never a silent skip), and a zero `executed` count exits 3.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above.
- **Do not let the differential become the fix.** If Phase 0.2 confirms rc 128 / dubious ownership,
  the temptation is to stop at "source fails too, so it's fine" — that is a permanently blind gate
  with a green checkmark. AC7 exists to make that impossible to ship.
- `git fsck` reports **dangling** objects as notices with rc 0. Do not treat any non-empty output as
  a fault; the rc and the error-line set are the signals, and Phase 0.2 measures both.
- fsck errors land on **stderr**, not stdout. Capturing them into one stream is defect (1) of the C1
  verify, repeated.
