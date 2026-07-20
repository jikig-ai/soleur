---
title: "fix(infra): make the workspaces-luks git-fsck gate differential and self-reporting"
type: fix
date: 2026-07-20
branch: feat-one-shot-fsck-gate-differential-evidence
lane: cross-domain
issue_ref: "Ref #6733"
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
deepened: 2026-07-20
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# fix(infra): make the workspaces-luks git-fsck gate differential and self-reporting

> `Ref #6733` — **never `Closes`**. #6733 is closed only by a *completed* cutover, never by a merge.
> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-07-20
**Agents used:** empirical `git fsck` semantics research (git 2.53.0, measured), architecture-strategist,
code-simplicity-reviewer, spec-flow-analyzer.

The deepen pass **measured** `git fsck` rather than reasoning about it, and the measurements falsified
four load-bearing assumptions in v1. The design changed materially:

1. **The source fsck no longer hoists out of the freeze — both sides run CONCURRENTLY inside it.**
   v1's staleness argument ("no writer heals a repo") is false: `git gc --auto`, `repack`, `prune` and
   reflog expiry heal repos constantly, and a repo mid-`repack` at baseline time emits transient
   `missing blob <sha>` lines that vanish — the exact forbidden direction, character-identical to a
   genuine copy loss of the same sha. v1 rejected in-freeze-both-sides on a ~9 min serial estimate;
   the two sides are on **different devices** (plaintext volume vs dm-crypt mapper) and run in
   parallel: `max(4.5, 4.5) ≈ 5 min`. This deletes the staleness question, the baseline directory,
   the `baseline=hoisted|inline|missing` field and its fallback path — a *smaller* diff than the hoist.
2. **`rc == 0` does not mean clean.** Measured: broken `objects/info/alternates` → `error:` lines with
   **rc 0**; a junk file in `objects/` → `bad sha1 file:` with **rc 0**. v1's table short-circuited on
   "both rc 0 → ok" *before* comparing sets, so a copy that acquires a new error line at rc 0 would
   have classified `ok`. The set differential is now computed **unconditionally**; rc only escalates.
3. **fsck reports across BOTH streams.** Measured: a missing object referenced by a commit → **rc 2
   with completely empty stderr** (`missing blob` on stdout). v1 diffed stderr only and would have
   missed it. Both streams are now captured and merged for comparison.
4. **Linked worktrees fsck the wrong filesystem.** Measured: a linked worktree's `.git` is a *file*
   containing `gitdir: <absolute path>`; fsck'ing the copy follows that pointer **back across the
   mount to the source**, reporting source corruption as though it were the copy's (and hiding the
   copy's own). Same hazard for `objects/info/alternates` holding an absolute path — which is
   hypothesis H2. These are now detected and classified explicitly rather than silently mismeasured.

Also folded in: `--no-optional-locks` (the file's own uniform invariant — a bare `git -C` can rewrite
`.git/index` on `$STAGING` *immediately after* C1 certified it byte-identical); a **total** classifier
with a fail-closed default; per-classification abort text; a pre-freeze advisory probe that lets a
rehearsal answer H1 without burning a freeze approval; and the removal of the `dst_only`
classification (the `du` byte assert and the G3 manifest already own that state).

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
G4 holder probe had before #6735. Three instances is a pattern, not a coincidence:

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
aborts, the differential is on the **error-line set** (not the exit code) so a pre-existing fault
cannot mask a new one, and the classifier is **total** with a fail-closed default.

### The blindness trap this plan must not fall into

There is a leading hypothesis (H1 below, **UNKNOWN** — the deciding datum was discarded) that the 8
failures are `fatal: detected dubious ownership in repository at '/mnt/data-luks/workspaces/<uuid>'`.
The cutover runs as **root** on the host; the container runs as **uid 1001**
(`apps/web-platform/Dockerfile` — `useradd --no-log-init --uid 1001 -m soleur` / `USER soleur`), so
every workspace repo is owned by 1001 and git refuses to operate on it as root with **rc 128**
(measured; exact text in the Measured Semantics section). That fires *before a single object is read*.

If H1 is true, then a **naive rc-only differential is a no-op disguised as a fix**: the source fails
identically, every workspace classifies `preexisting`, the gate goes green, and it inspects exactly
zero objects on every future cutover — while the plaintext original is wiped in Phase 5. That is
precisely "weaken the gate into a no-op", arrived at by a route that looks like a correctness fix.

So the plan has two non-negotiable halves:

- **(A) make the probe able to run at all** — invoke fsck so a not-owned-by-root repo is actually
  inspected, and treat an fsck that *could not inspect* as its own classification (`probe_failed`)
  that **aborts**, never as `preexisting`; and
- **(B) make the verdict differential** — so a genuine pre-existing object fault does not abort.

Half (A) is what keeps half (B) honest. Shipping (B) alone would close #6733's symptom and blind the
gate permanently.

## Measured `git fsck` Semantics (git 2.53.0 — the foundation of every design choice below)

Measured empirically during the deepen pass. **Nothing in this section is inferred.** Anything that
could not be measured is marked UNVERIFIED and is not relied upon.

### Exit code is a BITMASK, not 0/1

| Scenario | rc | where the report lands |
|---|---|---|
| clean repo | **0** | no output at all |
| dangling objects only | **0** | `dangling blob <sha>` on **stdout** |
| truncated loose object | **3** | `error:` ×3 on **stderr** + `missing blob` on **stdout** |
| missing object referenced by a commit | **2** | `missing blob` on **stdout**, **stderr EMPTY** |
| broken `objects/info/alternates` | **0** | `error: unable to normalize alternate object path: …` on stderr |
| junk file in `objects/ab/` | **0** | `bad sha1 file: …` |
| dubious ownership | **128** | `fatal: …` on stderr |

`rc = ERROR_OBJECT 1 | ERROR_REACHABLE 2 | ERROR_PACK 4 | ERROR_REFS 8 | …`. Three consequences the
design depends on:

- **`rc == 0` is not "clean".** Two real defect classes exit 0. The set comparison must run
  unconditionally.
- **`rc != 0` is not "has error lines".** A missing object is rc 2 with empty stderr. Both streams
  must be captured; and a non-zero rc with an *empty* merged set is a probe anomaly, not a pass.
- **Nothing may key on `rc == 1`** — real corruption measured at rc 3. v1's Phase 0.2 predicted rc 1.

### `safe.directory` — exact requirements (measured)

Text at rc 128: `fatal: detected dubious ownership in repository at '<abs worktree path>'`.

| form | result |
|---|---|
| `safe.directory=<abs worktree path>` | **works** — real rc and real output returned |
| `safe.directory=<abs>/.git` | **FAILS**, still rc 128 |
| relative (`corrupt`, `../corrupt`) | **rejected** — `warning: safe.directory 'corrupt' not absolute`, rc 128 |
| `*` / `<parent>/*` | works — but forbidden here (too broad) |

So: **absolute worktree path, per repo, via `-c` (command scope, which git honours as protected
configuration).** Never `.git`, never relative, never a wildcard, never a `--global` write.

Note for a root-run script: `git-config(1)` documents that under `sudo` git also accepts `SUDO_UID`.
So behaviour differs between an interactive `sudo` test and a systemd/CI root context — which is
exactly why `safe.directory` is set explicitly rather than depended upon implicitly.

### Sources of spurious src-vs-dst difference (the set differential's real risk)

Ranked, all measured unless noted:

1. **`git -C <repo>` prints loose-object paths RELATIVE to the gitdir** (`.git/objects/ce/0136…`),
   whereas `git --git-dir=<abs>` prints the absolute path. → **always `-C`, never `--git-dir`.**
   Without this, every error line differs between the two prefixes and the set-diff explodes.
2. **`-C` is not sufficient.** Paths reached through an *absolute pointer* (alternates, a linked
   worktree's `gitdir:`) stay absolute regardless. → prefix normalization is still required.
3. **Linked worktrees fsck the WRONG filesystem.** Measured: a linked worktree copied to a new prefix,
   with an object corrupted **only in the source**, reported that corruption when fsck'd at the
   *destination* path — it followed the absolute `gitdir:` pointer back across the mount. Since
   `/mnt/data` still exists while `/mnt/data-luks` is scanned, any linked worktree yields results
   that are **not about the copy** — false positives *and* false negatives.
4. **Reflogs / dangling churn.** `--no-reflogs` flipped a repo from 1 to 2 `dangling` lines. Dangling
   and unreachable are notices, not faults. → drop `dangling`/`unreachable` lines from the set.
5. **The alternates error line repeats** (measured 4× identically, stable across runs but a function
   of how often the ODB is re-prepared). → `sort -u`.
6. **readdir order.** fsck enumerates loose objects via `readdir` of `objects/XX/`; ext4 `dir_index`
   order depends on a per-filesystem hash seed set at mkfs time, so two different filesystems can
   enumerate identically-named files in different orders (UNVERIFIED — needs two ext4 images and
   root). Free mitigation: the comparison is a **sorted set**, which is order-immune anyway.

### `--name-objects` (confirmed privacy finding)

Measured output with the flag: `missing blob 1269488f… (:clients/acme-corp/salary-2024.csv)` — it
appends the in-repo **path**. It adds no integrity signal and leaks user filenames into Better Stack.
**Forbidden** (AC2).

### `--no-progress`

Exists for fsck. Progress is auto-suppressed when stderr is not a tty (measured: zero bytes when
piped). Passed anyway as belt-and-braces against a future tty/`GIT_PROGRESS_DELAY` surprise.

### Not measured

- Real root-vs-`SUDO_UID` ownership behaviour (passwordless sudo unavailable in the research
  environment; simulated via `GIT_TEST_ASSUME_DIFFERENT_OWNER=1`, which drives the identical code
  path). **This is the H1 datum, and the pre-freeze advisory probe (Phase 2.6) is what measures it
  on web-1.**
- A genuine never-fetched promisor blob in a large blobless clone. What *was* measured: a repo with
  partial-clone extensions set and a genuinely absent object still reports `missing blob` at rc 2 —
  promisor tolerance covers only objects referenced from a `.promisor` pack, not arbitrary holes.
- Cross-filesystem readdir ordering divergence (see 6 above).

## Hypotheses

Per the Sharp Edge on hypothesis honesty: **the deciding datum (each repo's fsck output) was
discarded at the source by the very defect this plan fixes.** No verdict below may read CONFIRMED or
REFUTED. All are UNKNOWN; the plan's primary deliverable is the probe that decides them, and the
design must be correct under *every* one of them.

| # | Hypothesis | Verdict | How the new marker decides it |
|---|---|---|---|
| H1 | `detected dubious ownership` (root fsck-ing uid-1001 repos) — rc 128, zero objects read | **UNKNOWN** (strongest prior; the ownership asymmetry is verified in the Dockerfile, the *failure* is not) | `rc=128` + `first=fatal: detected dubious ownership…` → `probe_failed` → **abort**. Decided by the **pre-freeze advisory probe**, i.e. by a rehearsal, without a freeze approval |
| H2 | `objects/info/alternates` holding absolute paths that do not resolve at the `/mnt/data-luks/...` prefix | **UNKNOWN** — and v1's discriminator was **wrong**: measured, this emits `error: unable to normalize alternate object path: …` at **rc 0**, not `fatal: bad object` at non-zero. v1's rc-first table would have classified it `ok` | `alternates_escape` detection (Phase 2.2) + the unconditional set comparison |
| H3 | Partial/blobless clones reporting missing promisor objects | **UNKNOWN** | identical normalized error-set on both sides → `preexisting` |
| H4 | Worktree gitdir pointers | **UNKNOWN — and now known to be actively dangerous rather than merely unreachable.** v1 said the `-d "$ws/.git"` guard skips them. It does — but measurement shows that had they *not* been skipped, the copy's fsck would have read the **source** filesystem | `skipped reason=worktree_pointer`, counted on the summary row |
| H5 | Genuine object corruption introduced by the copy | **UNKNOWN** — *disfavoured*: C1's `rsync -aHAXi --checksum --delete --dry-run` verify passed with **0** differences immediately before this gate, and a `du --apparent-size` byte match passed | dst-only lines in the normalized set → `copy_corruption` → **abort** |

Count arithmetic that H1/H4 jointly explain and no single-cause hypothesis explains as cleanly: 10
workspace directories, 8 fsck failures ⇒ 2 had no `.git` **directory** and were `continue`d. Under H1
the 8 that *were* probed failed **100%** — a systemic-cause signature, not a corruption signature.
This is a prior, not a proof.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| "Current code, line 1621" | Line numbers drift; the gate is inside the `if [ "$DRY_RUN" != "1" ]` G3 block, after `verify_byte_identity` and the `du` byte assert | Cite the **content anchor** per `cq-cite-content-anchor-not-line-number`; no AC uses a line number |
| "fsck errors land on stderr" (v1 Sharp Edge) | **False in part** — a missing object is rc 2 with `missing blob` on **stdout** and empty stderr | Capture both streams separately, merge for the set |
| "the corresponding plaintext source workspace" | Source root `$MOUNT/workspaces/<id>`, copy `$STAGING/workspaces/<id>` (`$MOUNT` becomes the mapper only after the repoint) | Pair by basename; the dst-driven loop plus a src-side count reconciliation |
| "hoist the source fsck out of the freeze" | Feasible, but **unsound**: `git gc --auto`/`repack`/`prune`/reflog expiry heal repos while writers are live, producing a stale baseline whose transient `missing blob <sha>` is character-identical to a genuine copy loss of the same sha | **Rejected.** Both sides run concurrently *inside* the freeze — `max(4.5,4.5) ≈ 5 min`, no staleness, less state |
| marker conventions | Verified: summary row then per-item rows, `_vscrub` on every field, `echo` + `logger -t "$LUKS_LOG_TAG"`, `feature=workspaces-luks op=workspaces-luks-<kebab>`, a cap constant (`VERIFY_DIFF_CAP`, 40) | `FSCK_MARKER_CAP` / `FSCK_OUT_CAP` mirror it |
| infra needed for the marker? | **No** — `luks-monitor` already allowlisted in `apps/web-platform/infra/vector.toml` (exact-value tag match) | `## Infrastructure (IaC)` skipped |
| harness can test the gate | Only via **functions** — it `source`s the cutover (sourced-detection guard) and calls `prepare_staging_target` / `verify_byte_identity` | Extraction into a function is a **prerequisite of the test**, not a refactor for taste. New functions must be defined **above** the sourced-detection guard |
| `--no-optional-locks` | `manifest_of` applies it **uniformly** to all three git invocations and documents why: a rewritten `.git/index` on `$STAGING` "mutates the destination tree immediately after the proof that it matched, silently invalidating that proof" | v1 prescribed a bare `git -C` in the same post-C1 window. **Fixed** — `--no-optional-locks` on every new invocation, pinned by an AC |
| "10 passing harness cases" | Verified: L1, L1b, L2, L3, L3b, L5a, L5b, L5b-control, L5c, L5d (L4 is advisory and deliberately does not touch the counters) | New cases append as L6*; `unavailable()` fail-closed shape and the zero-`executed` guard untouched |

## Ordering — where each probe runs, and why

```
  bulk rsync (writers live)              [real arm only]
      │
      ├── NEW: fsck_advisory_probe "$MOUNT"     ← PRE-FREEZE, BOTH arms
      │        SOURCE side only. Evidence, NEVER the gate's comparand.
      │        Emits SOLEUR_WORKSPACES_LUKS_FSCK rows with phase=advisory.
      │        ABORTS PRE-FREEZE (no freeze held, no rollback needed) iff
      │        every probed source repo returns probe_failed — under H1 that
      │        is the whole point: fail before the outage, not after it.
      │
  FREEZE ─ quiesce ─ pass-2 delta ─ drop_caches ─ C1 verify ─ du assert
      │
      └── verify_git_fsck_differential "$MOUNT" "$STAGING"   [real arm only]
               BOTH sides fsck'd CONCURRENTLY (& … & wait), ~5 min not ~9.
               Comparand is src-at-gate-time. Classifies; emits; aborts.
```

**Why both sides run inside the freeze.** v1 hoisted the source side and argued staleness could only
run conservatively. That argument is false. Git repositories self-heal routinely: `git gc --auto`
fires on ordinary write commands (default 6700 loose objects), and `repack`/`prune`/reflog expiry
delete the referents of fsck error lines. A repo mid-`repack` at baseline time emits transient
`missing blob <sha>` lines that are gone once the repack lands — the forbidden direction. Worse, it
is *positively correlated* with the copy's most likely real corruption mode: bulk-rsyncing a repo
mid-repack is the classic way to lose exactly those objects, and fsck names them **by sha**, so the
stale baseline's transient line and the copy's genuine-loss line are character-identical:

- `src@T0` mid-gc → baseline records `missing blob <sha>`
- gc completes → `src@T1` clean
- the copy loses that same blob → dst emits the identical line
- dst set ⊆ src set → `preexisting` → **no abort**, and Phase 5 wipes the plaintext original.

Freezing both sides makes the comparand `src@T1` and deletes the failure mode outright.

**Why the budget is fine.** The two sides sit on **different devices** — the plaintext volume and the
dm-crypt mapper — so they are I/O-independent. Run them concurrently:

```
_fsck_side "$src_root" "$src_out" &
_fsck_side "$dst_root" "$dst_out" &
wait
```

In-freeze wall clock is `max(4.5, 4.5) ≈ 5 min`, not 9 — roughly a 30 s regression against the ~4.5
min the gate already costs, inside a ≤20 min budget. Compare v1's hoist: ~4.5 min in-freeze *plus*
~4.5 min pre-freeze *plus* a baseline directory, a three-valued `baseline=` field, an inline fallback
whose worst case puts the 4.5 min straight back into the freeze, and an unsound comparand.

**Why the pre-freeze advisory probe survives anyway.** It is the single highest-value, lowest-cost
item in the plan and it is *not* the comparand — it is evidence. It runs in **both** arms, so a
`dry_run=true` rehearsal answers H1 outright without spending a freeze approval. And per the script's
own established discipline (`escrow_probe` runs in both arms "so the rehearsal proves the escrow path
is usable BEFORE any irreversible freeze"; `ensure_lsof` is hoisted because "an apt-get inside the
freeze window … would burn an irreversible-freeze approval"), it **aborts pre-freeze** when every
source repo is un-inspectable — the state that would otherwise freeze the platform, take the outage,
run the delta rsync and C1, and abort at exactly the point run 29725194755 aborted.

Cost note: the advisory probe is ~4.5 min of read I/O and root git processes against the live
plaintext volume with users on it. Run it under `ionice -c3 nice -n 10`. Stated in the PR body.

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) another aborted cutover — the encryption-
at-rest migration slips again and every user's workspace stays on a plaintext volume; or, far worse,
(b) a cutover that *completes* with a blinded gate, wiping the plaintext original in Phase 5 while a
corrupt object on the LUKS copy goes uncaught — a user opens their workspace and their git history is
unreadable, with no source to restore from.

**If this leaks, the user's data is exposed via:** the marker is written to stdout, the run log, and
Better Stack via `logger -t luks-monitor`. It carries a workspace **UUID** (pseudonymous) and a
bounded prefix of fsck output. fsck output is object-id-shaped by default; `--name-objects` makes it
**path-bearing** (measured: `(:clients/acme-corp/salary-2024.csv)`). Forbidden by AC2; every field
`_vscrub`'d; `first=` truncated to `FSCK_OUT_CAP`.

- **Brand-survival threshold:** `single-user incident` — one user with an unreadable repo and no
  plaintext fallback is a brand-ending event. CPO sign-off required at plan time;
  `user-impact-reviewer` runs at review time.

## Implementation Phases

### Phase 0 — Preconditions

0.1 Re-read the gate's content anchor on `origin/main`:
`git show origin/main:apps/web-platform/infra/workspaces-cutover.sh | grep -n 'fsck --full'`.

0.2 **Local** exit-code/stream evidence. The Measured Semantics section above already carries this
from the deepen pass (git 2.53.0). Re-run it only if the local git major version differs, and note in
the PR body that this is **local** evidence — the authoritative measurement on web-1's git, its
uid-1001 repos and its mount options is the **pre-freeze advisory probe**, which is why that probe
exists and runs in the rehearsal arm.

0.3 Confirm `luks-monitor` is allowlisted in `apps/web-platform/infra/vector.toml`.

0.4 `grep -nE '^\s*(ok|no) "L' apps/web-platform/infra/workspaces-luks-loopback.test.sh` — confirm the
existing 10 case ids and that `L6*` is free.

0.5 Locate the sourced-detection guard
(`if [ "${BASH_SOURCE[0]:-$0}" != "$0" ]; then return 0 …; fi`, after `clean_stray`, before
`trap cleanup EXIT`). All four new **functions** go above it; only the two **call sites** go below.

### Phase 1 — RED: failing tests first (`cq-write-failing-tests-before`)

New Session D in `apps/web-platform/infra/workspaces-luks-loopback.test.sh`, on the existing
`new_session` helper (real loopback + dm-crypt; this suite never stubs the block layer). Cases drive
the real functions via `source` + `bash -c` with `die`/`logger`/`emit_drift` stubbed, exactly as
L3/L3b drive `verify_byte_identity`. Every assertion greps a **file** directly — never a pipe (the
harness's SIGPIPE rule is load-bearing).

**Fixture discipline (load-bearing).** Build real repos with `git init` + one commit, then
`chown -R 1001:1001` **both sides** by default. Production repos are uid 1001 and the harness runs as
root; a root-owned fixture never exercises `safe.directory` on the happy path, so L6a–L6d would go
green for a reason that cannot hold in production. Include one workspace id containing a **space** so
the emitter's `ws=`-last convention and any `read` loop are proven against it.

| Case | Scenario | Must assert |
|---|---|---|
| **L6a** | clean repos both sides (uid 1001), plus one non-repo directory, plus one linked worktree | rc 0, per-ws rows `classification=ok src_rc=0 dst_rc=0`, and summary carries `skipped=2` with the worktree distinguished (`reason=worktree_pointer` vs `reason=no_git_dir`) |
| **L6b** | **copy corruption still aborts** — corrupt a loose object under `$STAGING/…/.git/objects/` only | rc ≠ 0, `classification=copy_corruption`, `first=` carries a real fsck error string, abort text is the `copy_corruption` variant |
| **L6c** | **both-fail does not abort** — corrupt on src, then rsync so both sides match | rc **0**, `classification=preexisting`, log says pre-existing repo condition |
| **L6d** | **both-fail-plus-new-fault aborts**, and **path normalization holds** — a shared fault plus a dst-only fault, with repo paths differing between the two roots | rc ≠ 0, `classification=copy_corruption`, and **no** spurious dst-only line arises purely from the `$MOUNT` vs `$STAGING` prefix |
| **L6e** | **probe-failed aborts** (the H1 trap). Root-proof mechanism (see below) | rc ≠ 0, `classification=probe_failed`, abort text is the `probe_failed` variant |
| **L6f** | **rc-0-with-errors** — broken `objects/info/alternates` on the copy only (measured: rc 0 + `error:` lines) | rc ≠ 0 from the **gate**, `classification=copy_corruption`. Proves rc 0 does not short-circuit the set comparison |
| **L6g** | **non-zero rc with an empty error set** — e.g. a killed/failed probe | rc ≠ 0, `classification=unclassified`, abort. Proves the classifier is total and fails closed |
| **L6h** | **truncation** — a repo emitting many error lines (many broken alternates entries is the cheap fixture; no giant repo needed), with the dst-only line placed **beyond** `FSCK_MARKER_CAP`/`FSCK_OUT_CAP` | rows ≤ cap, `truncated=1` present, **and the run still aborts** — proving caps apply to *emission* only, never to comparison |
| **L6i** | **mutation control** (L5d discipline) — `sed` the abort predicate in a copy of the cutover into a vacuous `true`, re-run L6b; it MUST flip green | proves L6b's abort is load-bearing. Assert the `sed` landed before trusting the result |
| **L6j** | **advisory probe** — run `fsck_advisory_probe` alone against a source with an un-inspectable repo | emits `phase=advisory` rows; aborts pre-freeze when **all** source repos are `probe_failed`; does **not** abort when only some are |

**L6e's mechanism must be root-proof.** The harness self-elevates to root, so neither a foreign uid
(which `safe.directory` is designed to defeat — the SUT would pass) nor `chmod 000` (no-op under
CAP_DAC_OVERRIDE) produces `probe_failed`. Use one of: replace `.git/objects` with a **dangling
symlink**, corrupt `.git/config`/`HEAD` into a `fatal:` rc-128 shape, or drive the probe under
`setpriv --reuid=1001`. Name the chosen mechanism in the case comment.

Run the suite; **L6a–L6j must fail** before Phase 2. Record the red output for the PR body.

### Phase 2 — GREEN

**2.1 Extract**, above the sourced-detection guard:

```
fsck_advisory_probe <src_root>                        # pre-freeze, both arms, evidence
verify_git_fsck_differential <src_root> <dst_root>    # in-freeze gate, real arm
_fsck_side <root> <out_dir>                           # probe every workspace under a root
_fsck_one <repo> <rc_file> <raw_out> <raw_err>        # one probe; NEVER calls die
emit_fsck_row <fields…>                               # marker emitter
```

`verify_git_fsck_differential` and `fsck_advisory_probe` are called **directly** in the main body —
never in `$(…)`, a pipe, or a subshell — so `die`'s `exit 1` reaches the EXIT trap and rollback,
matching `verify_byte_identity`'s documented discipline. **`_fsck_one` and `_fsck_side` never call
`die`**; they return and write results to files. State this as an invariant in the function comment:
an implementer reaching for `rc=$(_fsck_one …)` puts a `die` in a subshell where, under
`set -uo pipefail` with **no `-e`**, it becomes a silent exit and execution continues past it.

`fsck_advisory_probe` runs **before** `FREEZE_HELD=1; persist_state FREEZE_HELD 1; arm_dead_man`, so a
`die` there reaches `cleanup()` with both flags 0 → no rollback, which is correct. Say so in an inline
comment so the next editor does not "fix" it into a rollback, and use the script's existing pre-freeze
die language ("no freeze was held; NO rollback is needed and ROLLBACK=1 must NOT be run").

**2.2 The probe (`_fsck_one`)** — half (A):

```
git --no-optional-locks -c safe.directory="<ABSOLUTE worktree path>" -C "<repo>" \
    fsck --full --no-progress --no-dangling --no-reflogs \
    >"$raw_out" 2>"$raw_err"; rc=$?
```

Every element is load-bearing and measured:

- **`--no-optional-locks`** — the file's uniform invariant. A bare `git -C` can rewrite `.git/index`
  on `$STAGING` *immediately after* `verify_byte_identity` certified DST == SRC byte-for-byte,
  silently invalidating that proof. `manifest_of` applies it to all three of its invocations
  deliberately so the property is statically checkable ("no bare `git -C` here"). AC pins it.
- **`-C`, never `--git-dir=<abs>`** — measured: `-C` prints loose-object paths relative to the gitdir;
  `--git-dir` prints them absolute, which would make every error line differ between the two roots.
- **`-c safe.directory="<absolute worktree path>"`** — measured: the `.git` form and relative forms
  both still return rc 128. Per repo, never a wildcard, never `--global`.
- **no `--name-objects`** — measured to append in-repo file paths. Privacy.
- **`--no-dangling --no-reflogs`** — dangling/unreachable are notices, not faults, and reflog state
  differs benignly. Applied to **both** sides symmetrically.
- **separate `$raw_out` and `$raw_err`** — measured: a missing object is rc 2 with the report on
  stdout and stderr empty. Both are needed; keeping them separate is the C1 verify's defect-(1)
  lesson (folded streams let benign noise contaminate the signal).
- **files, never shell variables** — a pathological repo can emit megabytes. Bound what lands on disk
  too (the root disk is the one the stray-copy incident filled): cap the raw capture with an explicit
  `truncate`/`head -c` **after** the write, not a pipe (a `git … | head -c N` under `set -o pipefail`
  yields rc 141 — a SIGPIPE that would land in `unclassified`).

**2.2b Cross-filesystem escape detection** — measured to be a real mismeasurement, not a theoretical
one. Before probing a dst repo, classify it:

- `.git` is a **file** (linked worktree) → `skipped reason=worktree_pointer`. Measured: fsck'ing the
  copy follows the absolute `gitdir:` pointer **back to the source filesystem** and reports the
  source's state. Never probe it; count it.
- `objects/info/alternates` exists and contains an **absolute path outside the root being probed**
  → `skipped reason=alternates_escape`, counted. This is H2's actual shape, and it is why H2's v1
  discriminator was wrong.

Both are **counted on the summary row**, not emitted as per-workspace rows (they would burn
`FSCK_MARKER_CAP` budget to say "not a probeable repo"). If either count is > 0, log it loudly — it is
a genuine coverage hole in the gate, made visible rather than silent. Widening the gate to *cover*
worktrees is deliberately out of scope (it changes gate coverage in a verdict-logic PR); if the next
run's marker shows a non-zero count, file a follow-up.

**2.3 Normalization, then classification** — half (B).

Normalize each side's report identically:

```
cat "$raw_out" "$raw_err" \
  | sed "s|$root/||g; s|/mnt/data-luks/workspaces/|<WS>/|g; s|/mnt/data/workspaces/|<WS>/|g" \
  | grep -vE '^(dangling|unreachable) ' \
  | sort -u
```

Both mount prefixes are stripped on **both** sides so a path that survives via an absolute pointer
cannot become a spurious dst-only line. `sort -u` handles the measured repeat of the alternates line
and any readdir-order divergence.

Classification — evaluated **in this order**, and the order is load-bearing:

| # | Condition | `classification` | Abort? |
|---|---|---|---|
| 1 | `.git` absent / worktree pointer / alternates escape | `skipped` (+ `reason=`) | no (counted) |
| 2 | a **setup** `fatal:` on either side (`_FSCK_SETUP_FATAL_RE`) | `probe_failed` | **yes** |
| 2b | a `fatal:` matching neither the setup nor the content taxonomy | `unclassified` | **yes** |
| 3 | either side `rc != 0` **and** that side's normalized set is **empty** | `unclassified` | **yes** |
| 4 | src workspace directory absent at gate time | `probe_failed` (`reason=src_absent`) | **yes** |
| 5 | dst set ⊄ src set (≥1 dst-only line) | `copy_corruption` | **yes** |
| 6 | both sets non-empty, dst ⊆ src | `preexisting` | no (logged) |
| 7 | src set non-empty, dst set empty | `src_only` | no (logged) |
| 8 | both sets empty **and** both rc 0 | `ok` | no |
| 9 | **anything else** | `unclassified` | **yes** |

Five changes, each closing a measured hole. **The first was measured at /work time and falsifies the
deepen pass's own row 2** — recorded here because the plan is authoritative for intent, never for a
literal that measurement contradicts:

- **Row 2 may NOT key on `rc == 128` or on "has a `fatal:` line".** Measured (git 2.53.0): a corrupt
  loose object exits **rc 128** with
  `fatal: loose object <sha> (stored in .git/objects/xx/…) is corrupt`, which is indistinguishable by
  rc, and by the presence of a `fatal:`, from the setup failure
  `fatal: bad config line 1 in file .git/config`. The deepen-pass discriminator is therefore wrong in
  **both** directions: it labels genuine corruption "nothing was verified", and — decisively — it
  makes a corrupt object present on **BOTH** sides classify `probe_failed` and **abort**, which is
  exactly the false positive this change exists to remove, reintroduced under a new name. Driven
  locally, the deepen-pass table produced `probe_failed` for the both-sides case; the shipped code
  produces `preexisting` + rc 0. Discrimination is on the **kind** of fatal (`_FSCK_SETUP_FATAL_RE`
  vs `_FSCK_CONTENT_FATAL_RE`), with row 2b failing **closed** on any unrecognised fatal so an
  un-enumerated setup failure can never fall through to the differential and blind the gate.
- **Row 2 must precede row 5.** Under H1 the `fatal: dubious ownership` line embeds the differing
  path prefix; if the set comparison ran first it would produce a dst-only line on **100%** of
  workspaces → `copy_corruption` on all 8 → the same abort with a wronger label.
- **Row 8 requires an empty set, not just rc 0.** Measured: broken alternates and junk objects both
  exit 0 with error lines. v1's "both rc 0 → ok" short-circuited past the comparison — a state where
  the new gate would have been **weaker than today's**.
- **Rows 3 and 9 exist at all.** v1's table was not total: `src_rc=0, dst_rc≠0, dst set empty` (an
  OOM-killed or SIGPIPE'd probe) matched no row, and the natural shell shape (`classification=ok`
  initialized, overwritten by matching branches) would have defaulted it to green — again weaker than
  today's rc-only gate, which aborts on it.
- **`dst_only` is gone.** A workspace present on the copy with no source counterpart is already caught
  twice on the path here: the `du --apparent-size -sb` equality assert runs *immediately before* this
  gate, and the G3 manifest workspace-count comparison runs *immediately after*. A third detector for
  a condition two adjacent gates own is scope creep. The genuinely dangerous inverse — a source
  workspace **missing** from the copy — is likewise G3's; this gate reports it as a summary count
  (`src_missing_on_dst`) so the marker is complete, and does not abort on it.

**Abort text is per-classification.** A single string is wrong for three of the four aborting states,
and under H1 — the most likely next-run outcome — a generic "the copy regressed" message asserts
corruption that did not happen. Given SSH is forbidden, the die line is the operator's loudest
artifact:

- `copy_corruption` → `git fsck regressed on N workspace(s) between the plaintext source and the LUKS copy — see the SOLEUR_WORKSPACES_LUKS_FSCK marker for the workspace id(s) and the fsck output`
- `probe_failed` → `git fsck could NOT INSPECT N workspace(s) — nothing was verified, so the copy is uncertified; see the marker for rc and the fatal: line`
- `unclassified` → `git fsck returned a state this gate cannot classify on N workspace(s) (non-zero rc with no error output) — failing closed; see the marker`

**Summary invariant:** the per-classification counts must sum to `total`, and `total + skipped` is
cross-checked against `G2_COUNT`. `total=0` while `G2_COUNT > 0` is **instrument failure, not
emptiness** — abort. This mirrors `clean_stray`'s own stated discipline and the DP-9 F10 rule that
floors are derived from the observed count, never hardcoded.

**2.4 The marker** — mirror `emit_verify_diff`. Emit **before** any cleanup and **before** `die`
(defect (2) of the C1 verify was literally "rm before log"). Register the capture tempdir with the
existing EXIT trap rather than `rm`-ing inline, so the emit-before-cleanup ordering is structural
rather than a source-order convention.

Summary row:
```
SOLEUR_WORKSPACES_LUKS_FSCK feature=workspaces-luks op=workspaces-luks-fsck phase=<gate|advisory> \
  total=<n> ok=<n> preexisting=<n> src_only=<n> copy_corruption=<n> probe_failed=<n> \
  unclassified=<n> skipped=<n> skipped_worktree=<n> skipped_alternates=<n> \
  src_missing_on_dst=<n> inspected_objects=<yes|no> host=<hostname>
```

Per-workspace row (`ws=` **last**, per the `path=`-last convention, so a spaced id is captured whole):
```
SOLEUR_WORKSPACES_LUKS_FSCK feature=workspaces-luks op=workspaces-luks-fsck phase=<gate|advisory> \
  idx=<k> classification=<ok|preexisting|src_only|copy_corruption|probe_failed|unclassified|skipped> \
  reason=<…> src_rc=<n> dst_rc=<n> truncated=<0|1> first=<…> ws=<id>
```

`first=` is defined **per classification** — under H1 this field *is* the run's entire output value:

| classification | `first=` holds |
|---|---|
| `copy_corruption` | the first **dst-only** line (not dst's first line — that is often shared with src and useless) |
| `probe_failed` | the `fatal:` line from whichever side failed, prefixed `src:`/`dst:` |
| `unclassified` | `rc=<n> with empty output on <side>` |
| `preexisting` | the first shared line |
| `src_only` | the first src line |
| `skipped` | the reason token |
| `ok` | empty |

Every field `_vscrub`'d. `echo` **and** `logger -t "$LUKS_LOG_TAG"`. `emit_drift
workspaces_luks_fsck_<classification>` fires **once per distinct aborting classification per run**
(not per workspace — `emit_verify_diff` fires exactly once at its tail; per-workspace firing could
produce up to `FSCK_MARKER_CAP` Sentry events for one abort).

**2.5 Bounds.** `FSCK_MARKER_CAP="${WORKSPACES_FSCK_MARKER_CAP:-40}"` (rows) and
`FSCK_OUT_CAP="${WORKSPACES_FSCK_OUT_CAP:-256}"` bytes per `first=` — 256 chosen to hold the longest
line the five hypotheses can produce (measured: the `fatal: detected dubious ownership in repository
at '<uuid path>'` line is ~90 chars; `error: unable to normalize alternate object path: <abs>` is
similar; 256 leaves headroom without inviting a log flood). **Invariant: caps apply to EMISSION only.
Comparison always consumes the full capture.** A dst-only error line beyond the cap must still abort
(L6h asserts exactly this). Aborting rows are emitted **first** so the cap can never truncate away
the row that explains the abort; log `… +N more` as `emit_verify_diff` does.

**2.6 The pre-freeze advisory probe.** `fsck_advisory_probe "$MOUNT"` immediately after the bulk rsync
step, **outside** the `DRY_RUN` gate so it runs in both arms. Source side only, `phase=advisory`,
under `ionice -c3 nice -n 10`. It is **never** the gate's comparand. Its one aborting condition:
every probed source repo returns `probe_failed` → abort **pre-freeze**, before `FREEZE_HELD=1`, with
its own `emit_drift`. Under H1 that is the whole point — fail before the outage rather than after it,
and let a `dry_run=true` rehearsal decide H1 for free.

**2.7 Dry-run honesty.** No short-circuit.
- The advisory probe runs in the dry-run arm and emits its rows — the rehearsal reports the real
  pre-existing-condition landscape, the exact evidence that would have pre-empted this abort.
- The differential gate stays inside `if [ "$DRY_RUN" != "1" ]` because there is no copy to fsck. The
  dry-run log must say so in as many words: `(dry-run) source fsck advisory probe only; the
  differential gate does NOT run in this arm` — mirroring the advisory-holder-probe wording the
  dry-run G4 arm already uses. A rehearsal must never read as if the gate passed. Asserted from
  **captured dry-run output** (L6j), not by grepping the script for the string.

### Phase 3 — Verify

- Loopback suite green: 10 pre-existing + 14 new = **24** pass/fail cases, 0 failures.
  (14, not 10: review added L6h2 byte-ceiling fail-closed, L6h3 object-count floor, L6h4 instrument
  failure — three abort classes unreachable from any fixture as written — plus L6k, which instantiates
  H1 itself: `detected dubious ownership` aborts as probe_failed with safe.directory suppressed, and
  the SAME repo classifies ok through the real prober, proving the per-repo `-c safe.directory=` is
  what makes half (A) work rather than an untested assertion.)
- `bash -n` on both edited files.
- `shellcheck` only if `.github/workflows/infra-validation.yml` already runs it on these files —
  verify before asserting.
- Walk every Pre-merge AC, recording command + output.

### Phase 4 — Learning

`knowledge-base/project/learnings/<topic>.md` (author picks the date at write time). Two learnings,
both earned by measurement rather than reasoning:

1. **The three-instance pattern.** C1 verify, G4 holder probe, and now the fsck gate all shipped as
   fail-closed gates that discarded the evidence needed to answer the question they raised; each cost
   an irreversible-freeze approval to discover. Generalizable rule (AGENTS.md only if `B_ALWAYS =
   wc -c AGENTS.md + AGENTS.core.md` permits against the 23000-byte cap; otherwise the constitution):

   > A fail-closed gate must emit the evidence that discriminates its own verdict, on a durable
   > channel, before it aborts. A gate that can only say *that* it failed forces an SSH diagnosis
   > that `hr-no-ssh-fallback-in-runbooks` forbids — so it is not merely inconvenient, it is
   > unresolvable. Corollary: a gate whose probe can fail *for setup reasons* must classify that
   > separately from a genuine finding, or a differential fix silently converts it into a no-op.

2. **`git fsck` semantics that every integrity gate gets wrong.** rc is a bitmask (corruption is rc 3,
   not 1); rc 0 does **not** mean clean (broken alternates, junk objects); the report is split across
   both streams (a missing object is rc 2 with empty stderr); `--name-objects` leaks in-repo paths;
   and a linked worktree fsck'd at a copied path follows its absolute `gitdir:` pointer **back to the
   original filesystem**. The last is the one that silently measures the wrong volume.

## Files to Edit

- `apps/web-platform/infra/workspaces-cutover.sh` — add `fsck_advisory_probe`,
  `verify_git_fsck_differential`, `_fsck_side`, `_fsck_one`, `emit_fsck_row` (all **above** the
  sourced-detection guard); add `FSCK_MARKER_CAP` / `FSCK_OUT_CAP` beside `VERIFY_DIFF_CAP`; replace
  the inline fsck loop with the gate call; insert the advisory-probe call after the bulk rsync,
  outside the `DRY_RUN` gate.
- `apps/web-platform/infra/workspaces-luks-loopback.test.sh` — Session D, cases L6a–L6j.

## Files to Create

- `knowledge-base/project/learnings/<topic>.md` (Phase 4).

No Terraform, no workflow, no `vector.toml` change (`luks-monitor` already allowlisted).

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` filtered on
`workspaces-cutover` returned zero matches.

## Acceptance Criteria

Deepen-pass note: v1 carried 13 ACs, of which six were ceremony — token greps satisfiable by a
comment, restatements of "run the suite", and "a paragraph exists in the PR body". Those are cut or
converted to behavioural assertions in the harness. What remains are checkable post-conditions.

### Pre-merge (PR)

1. The old anchor is gone **and** the new form is present — absence alone would pass for `&>/dev/null`
   or a re-folded `>"$out" 2>&1`, which is the defect the plan forbids by name. Both greps below
   EXCLUDE comment lines (`grep -v '^[[:space:]]*#'`): the new code quotes both forbidden strings
   verbatim in its explanatory comments, so the bare greps return 1 against correct code and the
   privacy gate stops being a mechanical check:
   - `grep -v '^[[:space:]]*#' <script> | grep -c 'fsck --full >/dev/null 2>&1'` → `0`
   - the new probe redirects to **separate** files: a `>"$…" 2>"$…"` form on the fsck invocation.
2. `grep -v '^[[:space:]]*#' <script> | grep -c -- '--name-objects'` → `0`.
3. **No bare `git -C` in the new functions** — every git invocation inside them carries
   `--no-optional-locks`, mirroring the statically-checkable property `manifest_of` was written to
   have. Assert over the function bodies, not the whole file.
4. `safe.directory` usage is scoped and absolute: every occurrence is `-c safe.directory=` bound to a
   per-repo absolute path variable; **no** wildcard in any quoting form and no `--global` write.
   `grep -nE 'safe\.directory' <script>` — inspect every hit; assert none matches
   `safe\.directory=["']?\*` and none is preceded by `config --global`.
5. The loopback suite: `sudo bash apps/web-platform/infra/workspaces-luks-loopback.test.sh` → exit 0,
   output matches `workspaces-luks-loopback: 24 passed, 0 failed`. This subsumes the behavioural
   proof of every classification — including **L6e** (`probe_failed` aborts: the anti-no-op proof),
   **L6f** (rc 0 with errors still aborts), **L6g** (the classifier is total and fails closed),
   **L6h** (a dst-only line beyond the cap still aborts), and **L6i** (L6b's abort is load-bearing,
   not decorative).
6. The dry-run arm's **captured output** contains `(dry-run) source fsck advisory probe only` and does
   **not** contain any `phase=gate` row (asserted from L6j's output file, not by grepping the script).
7. The per-classification counts on the summary row sum to `total`; `total=0` with `G2_COUNT > 0`
   aborts. Asserted behaviourally in L6a.
8. `bash -n` passes on both edited files.
9. PR body says `Ref #6733` and does **not** contain `Closes #6733`:
   `gh pr view <N> --json body -q .body | grep -c 'Closes #6733'` → `0`.

### PR-body content (conventions, not acceptance criteria)

The PR body must also carry, for the reviewer rather than for a checker: the Measured Semantics
transcript with its git version and the explicit note that it is **local** evidence (the
authoritative measurement on web-1 is the advisory probe); the freeze-budget statement (in-freeze
fsck goes from ~4.5 min serial-one-side to ~5 min concurrent-two-sides against a ≤20 min budget, and
why the v1 hoist was rejected as unsound); and the advisory probe's ~4.5 min of pre-freeze read I/O
against the live volume, run under `ionice`.

### Post-merge

10. **None.** The next cutover run is approved separately (an irreversible freeze —
    `hr-menu-option-ack-not-prod-write-auth`), and #6733 stays open until a cutover completes. This
    PR merges with no post-merge step of any kind.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_WORKSPACES_LUKS_FSCK summary row — phase=advisory in both arms, phase=gate in the real arm
  cadence: per cutover run (approved, irreversible-freeze workflow)
  alert_target: Better Stack via `logger -t luks-monitor` (tag already allowlisted in vector.toml);
                Sentry via emit_drift on any aborting classification
  configured_in: apps/web-platform/infra/workspaces-cutover.sh (emitter);
                 apps/web-platform/infra/vector.toml (tag allowlist, unchanged)
error_reporting:
  destination: Sentry (emit_drift op=workspaces-luks-drift,
               reason=workspaces_luks_fsck_<classification>, once per distinct classification per run)
               + Better Stack + the GitHub Actions run log (echo)
  fail_loud: true — copy_corruption / probe_failed / unclassified abort and roll back via the EXIT trap
failure_modes:
  - mode: copy corrupted an object
    detection: normalized dst error-line set not a subset of the normalized src set
    alert_route: abort (copy_corruption abort text) + marker + emit_drift
  - mode: probe could not inspect (dubious ownership, fatal setup error, src dir absent)
    detection: rc 128 or a fatal: line on either side
    alert_route: abort (probe_failed abort text) + emit_drift — never silently green.
                 Also detected PRE-FREEZE by the advisory probe when it affects every source repo
  - mode: probe returned non-zero with no output (OOM-kill, SIGKILL, SIGPIPE)
    detection: rc != 0 with an empty normalized set
    alert_route: abort (unclassified abort text) + emit_drift — fail closed
  - mode: rc 0 but the copy has new error lines (broken alternates, junk objects)
    detection: set comparison runs unconditionally; rc never short-circuits it
    alert_route: abort as copy_corruption
  - mode: pre-existing repo condition (partial clone, alternates, historical fault)
    detection: identical normalized error sets on both sides
    alert_route: logged, classification=preexisting, NO abort
  - mode: workspace not probeable (no .git dir, linked worktree, alternates escape)
    detection: .git absent / .git is a file / absolute alternates outside the root
    alert_route: summary counters skipped, skipped_worktree, skipped_alternates — coverage hole
                 visible, not silent
  - mode: instrument failure (zero workspaces enumerated)
    detection: total=0 while G2_COUNT > 0
    alert_route: abort — an empty enumeration is instrument failure, not emptiness
  - mode: pathological fsck output
    detection: capture exceeds FSCK_OUT_CAP / FSCK_MARKER_CAP
    alert_route: truncated=1 + "… +N more"; comparison still consumes the full capture
logs:
  where: GitHub Actions run log (echo) + Better Stack (logger -t luks-monitor)
  retention: Better Stack default retention for the luks-monitor tag
discoverability_test:
  kind: run-log
  marker: SOLEUR_WORKSPACES_LUKS_FSCK
  command: gh run view <run-id> --log | grep SOLEUR_WORKSPACES_LUKS_FSCK
  expected_output: "a phase=advisory summary row (both arms) and, in the real arm, a phase=gate summary row with the per-classification counts, plus one row per workspace carrying classification=, reason=, src_rc=, dst_rc= and a first= excerpt of the actual fsck output — sufficient to decide H1..H5 without any shell on the host, and sufficient to decide H1 from a REHEARSAL alone"
```

No `ssh` appears in the discoverability test — the point of this change is that the next cutover, and
indeed the next rehearsal, self-reports.

### Affected-surface observability

The cutover host is an operator-blind surface (`hr-no-ssh-fallback-in-runbooks`). The marker is the
in-surface probe, and its fields discriminate **all five** hypotheses in a single event: `rc=128` +
a `dubious ownership` excerpt decides H1 (and the advisory probe decides it in a rehearsal, before any
freeze); `skipped_alternates > 0` or a normalized `unable to normalize alternate object path` line
decides H2; identical normalized sets decide H3; `skipped_worktree > 0` decides H4; a dst-only line
with `src_rc=0` decides H5. One event decides the root cause — the property the current gate lacks.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure change to a production cutover script, deepened with empirical
measurement and three review agents. The decisive corrections: the source-fsck hoist was unsound (git
self-heals via `gc`/`repack`/reflog expiry, so a stale baseline can mask a genuine copy loss of the
same sha) and is replaced by concurrent in-freeze probing on two independent devices; `rc == 0` is not
"clean" so the set comparison must be unconditional; the report spans both streams; linked worktrees
and absolute alternates silently fsck the wrong filesystem; and `--no-optional-locks` is required
because the gate runs against `$STAGING` in the window immediately after C1 certified it
byte-identical. No Product/UX surface (no file in `## Files to Edit` matches any UI-surface glob) —
Product gate **NONE**.

## Architecture Decision (ADR/C4)

**Skipped** — no architectural decision. A bug fix to an existing gate on an existing surface: no
ownership/tenancy boundary moves, no new substrate, no resolver/trust boundary change, no divergence
from an existing ADR. C4 completeness check: all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` are to be reviewed at
/work time for external human actors (none new), external systems/vendors (none new — the marker
rides the already-modeled `luks-monitor` → vector → Better Stack path; Sentry already modeled),
containers/data stores (none new — `$MOUNT`/`$STAGING` are the same already-modeled volumes), and
actor↔surface access relationships (unchanged). If any of those four enumerations turns up an
unmodeled element at /work time, the `.c4` edit is in scope for this PR, not a follow-up.

## Infrastructure (IaC)

**Skipped** — no new infrastructure surface. No server, service, cron, vendor account, DNS record,
TLS cert, secret, firewall rule, or monitoring webhook. The marker rides the `luks-monitor` syslog tag
already allowlisted in `apps/web-platform/infra/vector.toml`. Phase 2.8 reviewed; see the
`iac-routing-ack` marker at the top of this file.

## GDPR / Compliance Gate

The canonical regulated-data regex does not match. Trigger (b) fires
(`brand_survival_threshold: single-user incident`), so the gate is invoked. One substantive finding,
now backed by measurement rather than suspicion: `--name-objects` makes fsck output **path-bearing**
(observed form `missing blob <sha> (:clients/acme-corp/salary-2024.csv)`), and file paths inside a
user's workspace are personal data once they reach Better Stack. AC2 forbids the flag; `_vscrub` +
`FSCK_OUT_CAP` bound what can be emitted; workspace UUIDs (pseudonymous, already emitted by sibling
markers) are the only identifier. No new processing activity, no Article 30 entry required.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The differential silently blinds the gate** (H1): source fails identically, everything classifies `preexisting`, zero objects ever inspected | `probe_failed` is a separate, **aborting** classification evaluated **before** the set comparison; per-repo absolute `safe.directory` makes the probe able to run; the advisory probe catches the all-source case **pre-freeze**; L6e asserts it. The single most important property in the plan |
| Stale source baseline masks a genuine copy loss of the same sha | **Design changed.** Both sides fsck concurrently inside the freeze; the comparand is src-at-gate-time. No baseline exists to go stale |
| rc 0 treated as clean, hiding broken alternates / junk objects | Set comparison is **unconditional**; `ok` requires an empty set *and* rc 0 on both sides. L6f asserts |
| Non-zero rc with empty output falls off the table and defaults green | Rows 3 and 9 (`unclassified` → abort). The classifier is total. L6g asserts |
| Linked worktree / absolute alternates make the copy's fsck read the **source** filesystem | Detected before probing; `skipped reason=worktree_pointer` / `alternates_escape`, counted on the summary. Measured hazard, not theoretical |
| Path-prefix asymmetry creates spurious dst-only lines | `-C` (not `--git-dir`) keeps loose-object paths relative; both mount prefixes stripped on both sides; `sort -u`. L6d asserts |
| Dangling/reflog churn enters the set as noise | `--no-dangling --no-reflogs` symmetrically, plus a `dangling|unreachable` filter |
| Gate mutates `$STAGING` after C1 certified it byte-identical | `--no-optional-locks` on every new git invocation; AC3 pins "no bare `git -C`" over the new function bodies |
| Freeze-budget regression | Concurrent probing on two independent devices: `max(4.5,4.5) ≈ 5 min` vs the ~4.5 min the gate already costs, against ≤20 min. The v1 hoist's worst case (all-inline fallback) put the full second pass *back* inside the freeze |
| Caps hide the line that explains the abort | Caps apply to **emission** only; comparison consumes the full capture; aborting rows emitted first. L6h asserts a beyond-cap dst-only line still aborts |
| A `die` inside a subshell is silently swallowed (`set -uo pipefail`, no `-e`) | Invariant: `_fsck_one`/`_fsck_side` never call `die`; the two entry points are called directly in the main body |
| Unbounded capture fills the root disk | Raw captures bounded after write (never via a pipe — `| head -c` yields rc 141 under `pipefail`); the capture tempdir is registered with the existing EXIT trap |
| Empty enumeration reads as success | `total=0` with `G2_COUNT > 0` aborts — instrument failure, not emptiness |
| Rehearsal reads as green where the real arm would abort | Gate stays inside `DRY_RUN != 1`; the dry-run log states the differential gate did not run; asserted from captured output (L6j), not a script grep |
| Advisory probe adds read I/O to the live volume with users on it | ~4.5 min under `ionice -c3 nice -n 10`, pre-freeze, writers live. Stated in the PR body |
| Approach stops scaling with workspace count | At ~10 workspaces the in-freeze concurrent pass is ~5 min. At ~50 it is ~22 min against a ≤20 min budget and the design breaks. Recorded here as the known ceiling; revisit before the workspace count triples |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Drop the fsck gate | The plaintext original is wiped in Phase 5 — this is the last chance to catch a corrupting copy |
| Narrow the gate (allowlist "benign" fsck errors) | Same failure shape as narrowing C1: a guess about which corruption matters, made in advance and without evidence |
| rc-only differential (as literally specified) | Measured to be unsound in both directions: rc 0 hides real defects (alternates, junk objects) and rc ≠ 0 with empty output hides a failed probe. Adopted as the baseline, then strengthened to normalized-error-set membership with a total classifier |
| **Hoist the source fsck out of the freeze (v1's design)** | **Rejected at deepen.** Git self-heals (`gc --auto`, `repack`, `prune`, reflog expiry), so a stale baseline can record a transient `missing blob <sha>` that is character-identical to a genuine copy loss of the same sha → `preexisting` → no abort → Phase 5 wipes the original. Also carried a baseline dir, a 3-valued `baseline=` field, and an inline fallback whose worst case returned the full cost to the freeze |
| Run both passes serially inside the freeze | ~9 min against ≤20. The two sides are on independent devices; concurrency makes it ~5 |
| Snapshot the source and fsck the snapshot | Removes staleness, but needs LVM/btrfs snapshot support on the volume being migrated *away from*. Concurrency achieves the same for free |
| `dst_only` as its own classification | Cut. The `du --apparent-size` assert (immediately before) and the G3 manifest count (immediately after) already own that state. Reported as a summary count only |
| Per-workspace `skipped` rows | Cut. They burn `FSCK_MARKER_CAP` budget to say "not a probeable repo". Summary counters carry the same information |
| Widen `-d "$ws/.git"` to cover worktrees now | Changes gate *coverage* in a verdict-logic PR — and measurement shows a naive widening would read the **wrong filesystem**. Made visible via `skipped_worktree`; follow-up if the next run shows a non-zero count |

## Test Scenarios

L6a–L6j above, on real loopback + dm-crypt (this suite never stubs the block layer), with fixtures
`chown`ed to uid 1001 on both sides so `safe.directory` is exercised on the happy path, and one
workspace id containing a space. The suite's fail-closed properties are preserved untouched:
`unavailable()` exits non-zero with the literal `LOOPBACK_UNAVAILABLE` token (never a silent skip),
and a zero `executed` count exits 3.

## Sharp Edges

- **Do not let the differential become the fix.** If the advisory probe confirms rc 128 / dubious
  ownership, the temptation is to stop at "the source fails too, so it's fine" — that is a
  permanently blind gate with a green checkmark. `probe_failed` and L6e exist to make that
  unshippable.
- **`rc == 0` is not "clean" and `rc != 0` is not "has errors."** Both were measured. Any code that
  branches on rc before comparing sets reintroduces the hole.
- **Never `git --git-dir=<abs>`; always `git -C <repo>`.** Measured: the former prints absolute
  loose-object paths and every error line then differs between the two roots.
- **A linked worktree fsck'd at a copied path reads the ORIGINAL filesystem.** Measured. Detect
  `.git`-as-file before probing; the same applies to an absolute `objects/info/alternates`.
- **Never pipe the fsck capture through `head`.** Under `set -o pipefail` that yields rc 141, which
  lands in `unclassified` and aborts a healthy run. Bound the file after writing it.
- A plan whose `## User-Brand Impact` section is empty, placeholder, or missing its threshold fails
  `deepen-plan` Phase 4.6. It is filled above.
