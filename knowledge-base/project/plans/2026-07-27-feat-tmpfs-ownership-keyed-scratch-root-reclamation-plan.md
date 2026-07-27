---
title: "feat: reclaim count-shaped /tmp leaks by declared ownership, via per-run scratch roots"
date: 2026-07-27
issue: 7004
type: feat
branch: feat-one-shot-7004-tmpfs-reclaim-scratch-roots
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# feat: reclaim count-shaped /tmp leaks by declared ownership, via per-run scratch roots

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No
> `knowledge-base/project/specs/feat-one-shot-7004-tmpfs-reclaim-scratch-roots/spec.md` exists.
>
> **All live-host figures below are `as-measured 2026-07-27T18:2xZ`.** `/tmp` is volatile and
> grew during authoring (19,931 → 20,582). Every figure carries its re-derivation command;
> re-run rather than trust.

## Enhancement Summary

**Deepened:** 2026-07-27 · **Reviewers:** DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, CTO (devex), plus a strong-model consult at plan Step 4.5.

### What review changed, and why each change was accepted

1. **The schema went from five fields to one** (`soleur-run.<pid>.XXXXXXXX`). Both the
   simplification and correctness panels fired on the same scope, which the plan-review contract
   says means *delete, don't fix*. Each cut dissolved a defect rather than defending one — the
   `starttime` cut alone removed the `/proc` field-22 misparse (17 of 573 live processes), the
   unfalsifiable AC that guarded it, and a cross-file helper that `tmpfs-guard.sh` could not source.
2. **Primary liveness became a held fd, not a sampled seam.** Measured: `export` after `execve`
   does not rewrite `/proc/<pid>/environ`, so a *forked subshell* is invisible to all five seams.
   An inherited `exec 9>` holder fd survives `fork` **and** `execve` and is held continuously — it
   removes the sampling race instead of adding a sixth sampler, and the existing `_INUSE_TOP` fd
   walk already sees it with no new code.
3. **Quarantine was adopted after being rejected.** The rejection ("a rename frees no tmpfs space")
   was the wrong frame: an `rm -rf` trap is indistinguishable from correct cleanup to the residue
   probe, so without quarantine the plan's own guards are blind to its stated worst case.
4. **Five defects found in the code *around* the new arm**, none visible from the new code alone —
   most seriously that Reaper 2 has no name filter and would delete the roots Reaper 3 spares,
   which falsified the central safety claim outright (Phase 2X).
5. **Three premises of mine were proven false** and corrected in place: ADR-129 was never amended
   by #6986; `scratch-root.test.sh` *is* already runner-covered; the census ratchet cannot move.
6. **One advisory claim was refuted by my own measurement** and not adopted — the backlog is
   677 MB allocated (34% of in-use), not the "3.1 MB / 2.6%" reported.

### Gate results (deepen-plan Phases 4.5–4.10)

| Gate | Result |
|---|---|
| 4.5 network-outage | **Skip** — 4 keyword hits, all `ssh` as a TMPDIR-inheritance boundary or the plan's own "no ssh in any verification path". No connectivity symptom is diagnosed |
| 4.55 downtime/cutover | **Skip** — no serving surface, no host reboot, no lock-taking DDL, no router change |
| 4.6 user-brand impact | **PASS** — section present, 26 body lines, threshold `single-user incident`, no placeholders |
| 4.7 observability | **PASS** — all 5 fields present and non-empty; `discoverability_test` is ssh-free |
| 4.8 PAT-shaped variable | **PASS** — no matches |
| 4.9 UI wireframe | **Skip** — 0 UI-surface paths in Files to Create/Edit |
| 4.10 encryption posture | **Skip** — no `.tf`, migration, cloud-init, or compose file; no persistent store or cross-component connection (the capped breadcrumb log sits beside the existing alarm file on the operator's own machine) |

## Overview

`scripts/tmpfs-guard.sh` detects a count-shaped `/tmp` leak every five minutes and reclaims
none of it. This plan ships the reclamation half, without the heuristic that #6991 measured
and removed.

**One substitution: stop *inferring* which entries are garbage; make the producer *declare*
it.** A run allocates one scratch root named `soleur-run.<pid>.XXXXXXXX`, points `TMPDIR` at
it so every allocation in that process and its children lands inside, and moves exactly that
root to quarantine on exit. The reaper reclaims a root only when `/proc/<pid>` is gone and no
liveness evidence remains. Age, size, and prefix never enter the decision.

**Day one, the operator sees exactly one thing: the every-five-minutes alarm stops.** The
677 MB of legacy `/tmp` is reclaimed by the next reboot, not by this PR. The benefit is
measured at day 7 by the soak probe, not at merge. That is the honest framing.

### Measured, not proposed

| Question | Measurement | Re-derive |
|---|---|---|
| Does bare `mktemp` follow `TMPDIR`? | **Yes** — `TMPDIR=X mktemp` → `X/tmp.XXXXXXXXXX`; `-d`, `-t` likewise | `TMPDIR="$d" bash -c 'mktemp; mktemp -d'` |
| Ownership key vs the real `/tmp` | **reap=6, spared_live=1, non_candidates=19957** | prototype dry run |
| Full pass inside the 5-min cron? | **0.046 s** schema-scoped (budget 300 s); rejected tier was >600 s | `time find /tmp -maxdepth 1 -name 'soleur-run.*'` |
| `/tmp` state | 20,582 entries, 49% blocks, **10%** inodes | `find /tmp -mindepth 1 -maxdepth 1 \| wc -l`; `df -i /tmp` |
| Backlog cost | `tmp.*` = 13,849 entries, **677 MB allocated** / 140 MB apparent = **34%** of 1.96 GB in use | `du -sk[--apparent-size] --total --files0-from=-` |
| Quarantine rename | atomic, same-filesystem, **0.003 s** | `time mv "$a" "$quar/"` |

### The one hard problem: proving nothing is still using the root

The ownership key answers *"who was supposed to clean this up"*. It does **not** answer
*"is anyone still using it"* — and the second question is the one that can destroy live data.
Three measurements bound it:

**1. `/proc/<pid>` absence is a safe primary gate.** Present ⇒ spare (fail **open**: the leak
persists, bounded by reboot). Absent ⇒ the allocator is gone. The dangerous direction —
`/proc/<pid>` absent while the owner lives — is impossible.

**2. The existing liveness map is not sufficient.** `_INUSE_TOP` covers cwd, fds, `map_files`,
and `/proc/net/unix`, but samples instantaneous state every 5 minutes. Measured: a descendant
doing `echo x > "$TMPDIR/f"` between commands is invisible to it (`fd-seam = 0`), and with the
owner dead the root would be **reaped while live data was being written**.

**3. `/proc/<pid>/environ` closes it — but is exec-time, not live.** This is load-bearing and
was measured in both directions:

```
TMPDIR exported BEFORE the descendant execs  -> environ seam sees it = 1   (the real design)
TMPDIR set by the descendant AFTER it execs  -> environ seam sees it = 0
```

Because `soleur_scratch_session_begin` exports `TMPDIR` *before* any child execs, descendants
carry it. But **the allocating shell never appears in its own `environ`** — `export` after
exec does not rewrite it. That is precisely why `<pid>` stays in the name: it covers the window
where a runner sits between two child invocations, publishing nothing. Both gates are
mandatory conjuncts; either one sparing spares the root.

**And the trap does not fire on `SIGKILL`** — which is exactly what tmpfs pressure produces
(ADR-133). Under the condition this feature exists to relieve, the reaper is the *only* line
of defence, not a redundancy.

### The schema is one field, after cutting four

The first draft encoded `uid`, `boot8`, `nsino`, `pid`, `starttime`. Review plus measurement
cut four. Recorded because each cut dissolved a defect rather than defending one:

| Field | Cut because | Evidence |
|---|---|---|
| `uid` | `find -user "$uid"` is authoritative; a name is an unauthenticated claim. Cross-checking the two is not a safety property | — |
| `boot8` | Provably inert on `/tmp` (tmpfs is wiped at boot). After a reboot a recycled pid is either absent ⇒ reaped, or present ⇒ spared, which fails **safe** | `/tmp` is tmpfs |
| `nsino` | **Zero reachable instances**: 0 bwrap invocations bind host `/tmp`; all 36 containerized surfaces declare their own `--tmpfs /tmp`. It also converts a containerized run from "wrong delete" into "never reclaimed, silently" | `git grep -cE 'bwrap.*--bind.*/tmp'` → 0 |
| `starttime` | Bought only a rare fail-**open** → reap, and cost the **entire** `/proc` field-22 misparse defect (17 of 573 live processes; `comm` is paren-wrapped and may contain spaces). It also forced a helper shared across two files — and `scripts/tmpfs-guard.sh` **sources nothing** and runs `set -euo pipefail`, so sharing meant a new source line plus an option-interaction hazard. Both review panels fired on this same scope ⇒ delete, don't fix | naive `$22` vs slice-after-last-`)` |

**Survives: `soleur-run.<pid>.XXXXXXXX`.** The measured result is unchanged, because it was
produced by the `-name` glob and the liveness seams, not by the fields: `non_candidates=19957`
is the glob; `spared_live=1` was spared by liveness.

### What already exists — do not rebuild

| Component | Disposition |
|---|---|
| `scripts/lib/scratch-root.sh` — `soleur_scratch_root()` | **Extend.** Its header defers the trap and `TMPDIR` decision to the caller; this issue *is* that decision. Contract stays byte-identical |
| `scripts/tmpfs-guard.sh` | **Add Reaper 3 inside it**, under the same flock, reusing `_INUSE_TOP`, `DRY_RUN`, `guard_log`, `alarm_record` |
| `scripts/followthroughs/anthropic-admin-key-6297.test.sh` | **The precedent** (merged #6986): one root + `TMPDIR` + trap, replacing a 1,883-file leak |
| `.claude/hooks/lib/session-state.sh` — `sweep_orphan_leases` | **Do NOT "lift" anything.** Its identity check is two lines (`kill -0` + hostname) over a sidecar `.lease` file in a different process. Coupling across the hook-lib boundary is not reuse. The earlier draft promised a lift with no corresponding `Files to Edit` entry — promise deleted |
| `worktree-manager.sh` — `cleanup_stale_sandbox_tmp` | **The genuine overlap** (same `/tmp`, same uid, same `-maxdepth 1`, same age gate). Right follow-up is deleting it *into* this mechanism — a separate issue, not an abstraction built now |

## Premise Validation

| Claim | Verdict | Evidence |
|---|---|---|
| #7004 open, unresolved | **HOLDS** | `gh issue view 7004` → OPEN |
| Detection shipped, reclamation deferred | **HOLDS** | guard: `"reporting, not reaping"` |
| `df -i` is the wrong trigger | **HOLDS** | 49% blocks vs 10% inodes |
| `tmp.` is mktemp's default, not a signature | **HOLDS** | 13,849 of 20,582 entries |
| "856 of 1013 sites are bare ⇒ migration means touching call sites" | **STALE** | `TMPDIR` is inherited by a process **and its children**. Migration touches *entry points*; runner-invoked suites inherit for **zero** author action |
| `TMPDIR` redirection would fix it | **REFUTED** | `test-all.sh:16` already does it; `/var/tmp` holds **1,538** leaked `tmp.*`. Redirection relocates, it does not reclaim |
| Backlog is unbounded | **STALE** | `tmp.*` mtimes span a rolling **8 days**; **0** entries survive 10d (mtime or atime). `systemd-tmpfiles-clean.timer` active at 10d `/tmp`, 30d `/var/tmp`. It is draining |
| **"#6986 amended ADR-129 to permit a registry file"** | **FALSE** | ADR-129 has one commit (#6743). `git show --stat a5160b29a` → 15 files, none under `decisions/`. `grep -ciE 'registry\|amendment'` → 0. The panel killed the registry design |
| **"`scratch-root.test.sh` runs in no runner"** | **FALSE — my own error** | `scripts/test-all.sh:474` globs `scripts/lib/*.test.sh`, which matches it. `bash scripts/lint-orphan-test-suites.sh` → `orphan test suites: none`. **No registration is needed**; adding one would double-register |
| "the census ratchet is the migration's metric" | **FALSE** | `lint-trap-tempfile-ownership.py` computes class-b per file, requiring a literal `trap … EXIT` **in that file**. The idiom puts the trap in the library, so a migrated file stays class-b. Census cannot move. `test-all.sh` has no `mktemp` at all and is not even in the population |
| "three reapers share `/tmp`" | **UNDERSTATED** | **Five** delete under `/tmp` today (`reap_output_files`, `reap_scratch_entries`, `cleanup_claude_tmp`, `cleanup_stale_sandbox_tmp`, `sweep_orphan_leases`) across three files and three lifecycles. Reaper 3 makes **six** |
| `run-registered-suites.sh` covers 87 suites | **WRONG → 76** | Replicating the script's own derivation over `infra-validation.yml` yields 76 |
| CTO advisory: backlog is "3.1 MB, not a capacity threat" | **REFUTED** | 677 MB **allocated**; the apparent-vs-allocated gap *is* the issue's thesis |

## User-Brand Impact

**If this lands broken, the user experiences:** the reaper deletes a scratch root a live
process is still writing into — the session loses its working directory mid-run and fails with
a confusing `ENOENT` whose cause is a different process entirely.

**If this leaks, the user's data is exposed via:** no new surface. Roots are `mktemp -d`
(0700), own-uid; the reaper reads directory names and `/proc`, never file contents.

**Brand-survival threshold:** `single-user incident` — an over-eager `rm -rf` on a RAM-backed
filesystem is terminal (no trash, no snapshot). (`requires_cpo_signoff: true` follows from this
threshold, **not** from the Product tier, which is correctly NONE — the two are independent.)

**The plan takes BOTH branches of the issue's AC4, and the second was a late reversal.**

*Provably scoped* holds mechanically: the candidate set is `find -maxdepth 1 -name
'soleur-run.*'`, so an entry not named to the schema is never enumerated. Measured: 19,957
non-candidates, 0 false positives.

*Reversible* was initially rejected — "on tmpfs a rename frees no space." **That reasoning was
wrong**, and the Step 4.5 consult caught why:

> A deliverable wrongly placed inside a root is destroyed by the trap — and the residue probe
> then observes *absence*, which is a **pass**. Destroyed deliverable and correctly-cleaned
> scratch are indistinguishable to every guard the plan proposes.

So the EXIT trap **renames the root into quarantine** (atomic, 0.003 s) and the reaper deletes
quarantined roots after a TTL. This is not the rejected inference: TTL deletion applies only to
roots whose ownership was declared and whose owner already exited — never to the shared
namespace. It converts the scratch-only rule from *"must never be violated"* into *"violations
are observable and recoverable for one cron interval"*, gives the SIGKILL asymmetry a second
chance, and makes cleanup cheap on a full tmpfs where `rm -rf` is least likely to complete.

**The asymmetry that justifies shipping:** a root holds *only* scratch from a run in progress.
Authored work lives outside any root where the glob cannot see it. The pressure tier's worst
case was terminal loss of authored work; this design's worst case is *re-run the suite*.

## Reach — what this mechanism can and cannot touch (state it before shipping)

Both runners **already** export `TMPDIR=/var/tmp`, which is why the plan's own evidence finds 1,538
leaked `tmp.*` there. It follows that entries landing in **`/tmp`** are, by construction, produced by
paths that do **not** inherit the runners' `TMPDIR`: the Claude Code Bash sandbox (documented in
`worktree-manager.sh` as unrelocatable — *"no settings.json/env lever exists to relocate or
auto-clean it"*), agent-invoked scripts run directly, hooks, `env -i` sites, and hardcoded literals.

So Phase 3.1 converts **`/var/tmp`** leaks into self-reaping roots — real value, but a `/var/tmp`
leak costs **disk**, not the RAM this issue is about. **PR 2 must attribute the `/tmp` growth to
named producers and state what fraction of the 20.7k the mechanism can actually reach**, rather than
implying the runner migration addresses it. This is the single most important honesty item in the plan.

> **Do not misread the backlog histogram.** 3,836 of the entries are `ft6297.*` + `ft.*` with mtime
> 13:13 CEST today; #6986 merged at 13:43 CEST. They **predate the fix by 30 minutes** and do not
> falsify the precedent. A reviewer running the histogram will see that file's name on ~19% of the
> backlog and reasonably conclude the opposite — say so in the PR body.

## Legacy Backlog — not cleared, and that is correct

The 20,582 existing entries declare no ownership, so the reaper **cannot and must not** reclaim
them; doing so needs exactly the heuristic #6991 removed.

They are not trivial (677 MB allocated, 34% of in-use) but they are **verifiably draining**:
mtimes span a rolling 8-day window and **zero** entries survive the 10d `tmpfiles.d` age, so
nothing is refreshing their timestamps. A reboot clears `/tmp` entirely at any time. The
operator's complaint therefore resolves passively within ≤10 days — the scope-out lets an
already-verified mechanism finish rather than leaving the complaint unsolved.

Explicitly **not** adopted: shortening the `tmpfiles.d` age below 10d. That is age-based
inference — #6991 wearing a systemd hat — and a root-owned system config change besides.

### The alarm must be rebaselined — as a re-floored watermark (PR 0)

`COUNT_TRIGGER=5000` against 20,582 entries means **the guard already alarms every five minutes,
forever, today** — before any of this. The reaper neither causes nor worsens it, which is why
this ships **first and alone**.

Two failure modes a naive fix hits, both of which the watermark must survive:

- **A frozen ship-time baseline goes blind while the legacy drains** — a new leak of thousands
  reads as "below baseline" for the whole drain window, i.e. this feature's own validation period.
- **A frozen baseline is permanently disarmed by a reboot** — `/tmp` is tmpfs, so after a reboot
  a stored ~20,500 sits against an actual ~0 and the alarm cannot fire until a new leak regrows
  past 20,500. That is the exact inverse of the bug, and invisible because the surface is silence.

**Fix:** count only entries that do **not** parse as the schema, and hold a **downward-ratcheting
watermark** re-floored every run (`min(stored, current)`). It follows the drain down, survives a
reboot to ~0, and alarms on growth above the current floor.

## Architecture Decision (ADR/C4)

### ADR-150 — *Declared-ownership scratch roots for tmpfs reclamation*

Ordinal: highest on `origin/main` is **ADR-149**; the 144 gap is claimed by unmerged sibling
PR #6778; no `ADR-150+` file has ever been created on any ref. Provisional — `/ship` re-verifies,
and any renumber sweeps plan + tasks + ACs in one edit.

Records:

1. **Decision** — one root per run named `soleur-run.<pid>.XXXXXXXX`, `TMPDIR` repointed, trap
   quarantines it, reclamation gated on **owner-dead + liveness**, quarantine drained on a TTL.
2. **Amends ADR-133 Decision #2**, which mandates reaping "gated on age **and** size **and**
   ownership **and** liveness". Reaper 3 replaces *age + size* with *declared ownership*; the
   existing size-gated arm is untouched. ADR-133's rejected alternative *"reap the many small
   /tmp entries (by count)"* is superseded — its stated reason (bytes live in large trees) is
   answered by the allocated-vs-apparent measurement.
3. **Does NOT amend ADR-129**, with the nuance review demanded: D2's *array* clause is not
   engaged (one root, no array), but D2's remedy sentence — *"Allocate in the helper, register at
   the call site"* — **is** substituted, by the `BASHPID` guard rather than call-site
   registration. Say that, rather than "D2 is not engaged." D3 (one owning trap) is satisfied.
4. **Coordination as a mechanical partition, not a comment.** A comment records a treaty; it cannot
   detect a breach — and the current split holds **by accident**: `cleanup_stale_sandbox_tmp` gates
   on `-regex "$tmp_root/[A-Za-z0-9_-]{15,}"`, and dots are simply not in that character class, so
   any future widening silently claims the schema with nothing failing. Extract
   `scripts/lib/tmp-reaper-scope.sh` exporting one predicate
   `soleur_tmp_reaper_owner <path> → {output|scratch|sandbox|schema|none}`, source it from all
   call sites, and add a **partition test**: no path classifies to two owners, and a `soleur-run.*`
   fixture classifies only to `schema`. Also have `worktree-manager.sh` take the same flock — today
   its SessionStart sweep does not participate in it at all.
5. **Cite `AP-009 "Never delete user data"`** from `knowledge-base/engineering/architecture/principles-register.md`
   by ID, and record the scoping argument as its compliance case. This is the repo's **second**
   automated `rm -rf` on a filesystem with no undo, and the register should not be silent about it.
   A secondary line against `AP-010` (convention over configuration for paths) is warranted for the
   new `TMPFS_GUARD_SCRATCH_BASES` seam.
5. **Rejected alternatives, each with its measurement** — including the build-vs-buy probes,
   which are the strongest evidence in the document:

   | Alternative | Result |
   |---|---|
   | Pressure tier (drop the size floor) | 12,240 candidates, ~1,500 authored, >600 s |
   | `df -i` trigger | 10% inodes vs 49% blocks |
   | `tmp.` prefix signature | mktemp's default template |
   | `systemd-run --user --scope -p PrivateTmp=yes` | **`Unknown assignment`** — scopes cannot carry exec sandboxing. Structurally impossible |
   | `systemd-run --user --pipe -p PrivateTmp=yes` | **Accepted, exit 0, and did nothing.** The file landed in the shared host `/tmp`; `ns/mnt` identical to host. `kernel.apparmor_restrict_unprivileged_userns=1` makes it **fail open, silently** — the buy option would have shipped looking correct |
   | `XDG_RUNTIME_DIR` | Relocation, already refuted for `/var/tmp`; and a *smaller* RAM budget (3.1 G) than `/tmp`'s 4 GiB, so it worsens the pressure |
   | Shorter `tmpfiles.d` age | Age inference — #6991 in a systemd hat |
   | ~~Quarantine~~ | **Adopted** after the Step 4.5 reversal — the only backstop for the scratch-only rule |

### C4 views

**No C4 impact — by structural absence.** All three of `model.c4` / `views.c4` / `spec.c4` read
in full. Enumerated: 4 actors (`founder`, `emailSender`, `betaContact`, `contributor`), 18
containers/data stores, 17 external systems, 5 element kinds. **The model has no
developer-workstation tier at any level** — `founder` is a product Owner reaching the platform
over HTTPS, not a machine that runs `mktemp`; the 13 `cron` matches are all *hosted* crons, not
the operator's local `*/5` crontab; `spec.c4` defines no kind capable of expressing a local mount.
Checked and unchanged: (a) external human actor, (b) external system/vendor, (c) container/data
store, (d) actor↔surface relationship. Precedent: ADR-133 shipped this class with no C4 delta.

## Scope — three PRs, deliberately

Both review panels converged that this is not one change. The split is safety-motivated: 25
`env -i` judgement calls against the highest-consequence rule do not belong in the same PR as a
destructive reaper.

| PR | Contents | Why separable |
|---|---|---|
| **PR 0 — alarm rebaseline** | Phase A only | The alarm is red *today*, independent of the reaper. ~40 lines, highest operator value, ships first and alone |
| **PR 1 — the feature (this plan's core)** | Phases 1–2, 3.1, 4, 5 | Allocator + Reaper 3 (**`/tmp` only**) + one runner + ADR + discovery. Coherent and testable |
| **PR 2+ — adoption tail** | Phases 6.x | Measurement-ranked entry points, `/var/tmp` coverage with the second runner, Tier-3 `env -i`, soak probe |

## Implementation Phases

### Phase A — Alarm rebaseline (PR 0, ships first)

A.1 Count only entries not matching the schema; persist a watermark beside the heartbeat,
    re-floored every run to `min(stored, current)`.
A.2 Alarm on growth above the floor, never on absolute count.

### Phase 0 — Preconditions (PR 1)

0.1 Re-run the Overview measurements; paste output into the PR body. (That is the whole phase —
    the earlier draft's `bash`-version, `boot_id`, and census preconditions guarded things now cut.)

### Phase 1 — The allocator (`scripts/lib/scratch-root.sh`)

1.1 Add `soleur_scratch_session_begin [base]` with an explicit, published contract:

    > **Prints nothing.** After it returns, `$TMPDIR` **is** the root; callers use bare `mktemp`.
    > If a path variable is genuinely needed, read `$SOLEUR_SCRATCH_SESSION_ROOT`. **Never** call
    > it as `root=$(soleur_scratch_session_begin)`.

    The contract is load-bearing for discoverability: the sibling `soleur_scratch_root()` in the
    same file *is* a print-and-capture API, so the obvious call form is the banned one. A function
    that prints nothing is not something people wrap in `$( )`.

1.2 Enforce the contract — this is the #6986 defect as a guard:

    ```bash
    if [[ "$BASHPID" != "$$" ]]; then
      echo "scratch-root: soleur_scratch_session_begin must NOT be called in a subshell" >&2
      return 1
    fi
    ```

1.3 Allocate in one primitive: `mktemp -d "$base/soleur-run.$$.XXXXXXXX"`, then guard —
    `|| { echo FATAL >&2; return 1; }`, `: "${root:?}"`,
    `[[ "$root" == /* && -d "$root" && ! -L "$root" ]]`. An unguarded failure would leave
    `TMPDIR=""` and send everything back to `/tmp`, most likely *exactly when `/tmp` is full*.

    **State the real option invariant:** this library carries no `set` line and inherits the
    caller's options — `test-all.sh` is `-euo pipefail`, `tmpfs-guard.sh` is `-euo pipefail`, the
    precedent script is `-uo` with no `-e`. Every guard must hold under **both** `-e` and `+e`.

1.4 `export TMPDIR="$root"`; set `SOLEUR_SCRATCH_SESSION_ROOT`; install **one** trap (ADR-129 D3)
    whose body is **expanded at set time**, not late-bound:

    ```bash
    trap "mv -- '$root' '$quar/' 2>/dev/null || rm -rf -- '$root'" EXIT INT TERM
    ```

    `$quar` is `<base>/soleur-quarantine.<uid>/` (0700, same filesystem ⇒ atomic). The `|| rm -rf`
    fallback preserves old behaviour if quarantine cannot be created, so this never fails closed
    into a leak. **Do not copy the precedent's `readonly`**: it is script-global there, but here a
    `local -r` is out of scope when the trap fires and a late-bound body would expand to
    `rm -rf -- ""` — the exact catastrophe the guard exists to prevent. Expanding at set time
    removes the need for `readonly` entirely.

1.5 Keep `soleur_scratch_root()` byte-identical. Compose as two statements, never one line —
    the earlier one-liner mixed both conventions and is the line people would copy.

**Tests:** contract (prints nothing; `$TMPDIR` inside the root); subshell guard returns non-zero
and leaves no root; `mktemp` failure never yields empty `TMPDIR`; trap quarantines on EXIT, INT,
TERM; fallback `rm -rf` when quarantine cannot be created; guards hold under `-e` and `+e`.

### Phase 2 — Reaper 3 (`scripts/tmpfs-guard.sh`; PR 1 scans `/tmp` only)

> **Seam-vs-scope reconciliation (self-audit finding).** `TMPFS_GUARD_SCRATCH_BASES` is
> **introduced in PR 1 but defaults to `/tmp` alone**; PR 2 only changes what the default
> contains. The seam therefore *exists* in PR 1, which is why Phase 2.7 must list it in the
> header seam list and AC14 must pin it under test. That pinning is not bookkeeping: AC2
> mandates a **non-dry-run** reap, so a seam that exists but is unpinned would let the suite
> reach the operator's real `/var/tmp`. Introducing the seam late — after tests were written
> against a hardcoded `/tmp` — is exactly how that gap would ship unnoticed.

2.1 `reap_orphan_scratch_roots()`. Candidates:
    `find /tmp -mindepth 1 -maxdepth 1 -name 'soleur-run.*' -type d -user "$uid" -print0`.
    Schema-scoped at the `find` — the mechanical basis of the provably-scoped claim. Skip symlinks.

2.2 Parse `<pid>`. Reap iff `/proc/<pid>` is **absent**. Present ⇒ spare (fail open). Unparseable
    ⇒ non-candidate, skipped silently. Default direction is "leave it alone".

2.3 Liveness — **both mandatory conjuncts**: the existing `_INUSE_TOP` map **and** a new
    `/proc/<pid>/environ` `TMPDIR` pass. Comment inline that `environ` is **exec-time, not live**,
    and that this is exactly why `<pid>` is in the name — it is the unstated invariant a future
    simplification would otherwise delete.

2.4 Reap = `mv` into `<base>/soleur-quarantine.<uid>/`. Drain quarantine each pass, deleting
    entries older than `TMPFS_GUARD_QUARANTINE_TTL_MIN` (default one interval) with `rm -rf --`;
    TTL floors to zero under block pressure so reclamation is not delayed when it matters most.

2.5 Reuse `DRY_RUN`, `guard_log`, `alarm_record`, and the existing flock. Log the reaped root
    basename **and** append it to a capped `tmpfs-guard-reaped.log` beside the alarm file (reusing
    `alarm_record`'s size-cap logic). Do **not** route reaps through `alarm_record` — a healthy
    reaper reaps constantly, and that is the alarm-fatigue failure this plan already fixes for the
    count alarm. The journal is a forensic record; the breadcrumb file is first contact.

2.6 `_build_inuse_top` is currently called **inside** `reap_scratch_entries`. Reaper 3 needs the
    same map, so hoist the build into `main` and have both arms read it — an explicit refactor,
    not the one-line ordering change the earlier draft implied.

2.7 Replace the two negotiated-split comments with a pointer to ADR-150's six-reaper table, and
    add every new seam (`TMPFS_GUARD_SCRATCH_BASES`, `TMPFS_GUARD_QUARANTINE_TTL_MIN`) to the
    header's **seam list** — that header states the list is exact, because *"a seam that is
    documented but unimplemented produces a test that sets it, observes no effect, and passes for
    the wrong reason."*

### Phase 2X — Five defects review found in the reaper's neighbourhood (all PR 1, all blocking)

These are not polish. Each one silently deletes live data or silently disables a gate, and none
was visible from the new code alone — they live in the code *around* it.

2X.1 **Reaper 2 deletes the roots Reaper 3 spares. This breaks the plan's central safety claim.**
     `reap_scratch_entries` builds candidates with **no name filter**
     (`find … -user "$uid" -mmin "+${age_min}"`) and its protected-path `case` does **not** list
     `soleur-run.*`. A root ≥100 MB whose tree has been idle 24 h clears size, age, and the
     protected list and is deleted with `find -delete` — **without** the environ seam, i.e. without
     the one gate proven to see a descendant holding nothing open. Ordering makes it worse: Reaper 3
     spares the root, Reaper 2 deletes it in the same run, and the log names Reaper 2's rationale.
     **Fix: add `soleur-run.*|soleur-quarantine.*` to that `case`, with an AC.**

2X.2 **`_INUSE_TOP` has no built-sentinel, and its failure direction is deletion.** Its sibling
     `_FRESH_TOP` carries `_FRESH_TOP["__built__"]=1` with a comment stating the map must fail
     closed for exactly this reason. `_INUSE_TOP` has none — an unbuilt map and a genuinely idle
     system are indistinguishable, so hoisting it (2.6) to serve two consumers turns a silent
     no-build into a silent mass-delete. **Add the sentinel and make Reaper 3 abort if it is absent.**

2X.3 **The environ seam must PREFIX-match, not exact-match — nested roots are the normal case
     after Phase 3.** Once `test-all.sh` allocates a root, `TMPDIR` *is* that root, so any suite
     that also calls `soleur_scratch_session_begin` allocates at `<outer>/soleur-run.…`. SIGKILL the
     outer runner: the reaper enumerates the outer root at `-maxdepth 1`, its pid is gone, and the
     nested child's `TMPDIR` is `<outer>/soleur-run.…` — which an **exact** comparison misses. The
     outer root is `rm -rf`'d with a live run inside. Match `"$root"` **or** `"$root"/*`.

2X.4 **Exclude the guard's own pid and ancestors from the environ pass.** If the guard is ever
     invoked as a descendant of a run whose owner was SIGKILLed, its own environ carries
     `TMPDIR=<that dead run's root>` and it spares the very root it was invoked to reclaim.

2X.5b **PRIMARY LIVENESS IS A HELD FD, NOT A SAMPLED SEAM — this supersedes the environ design.**
     Measured: `export` after `execve` does **not** rewrite the `mm->env_start..env_end` region
     `/proc/<pid>/environ` exposes (glibc moves the environment to the heap). So a **forked subshell**
     `( … ) &` or a **background shell function** — which never re-execs — is invisible to *all five*
     seams including environ:

     ```
     forked-subshell ( … ) &   environ TMPDIR: NOT VISIBLE   cwd/fd: 0
     bg-function     worker &  environ TMPDIR: NOT VISIBLE   cwd/fd: 0
     the allocator itself      environ TMPDIR: NOT VISIBLE
     ```

     This matters more than it first reads, because **the OOM killer selects by RSS, not by root
     ownership** — so under the tmpfs exhaustion this feature exists for, "owner dead, descendant
     alive" is the **common** shape, not the rare one.

     **Remedy (measured, and it removes complexity):** the allocator holds an inherited,
     non-`CLOEXEC` sentinel fd inside the root — `exec 9>"$root/.soleur-run.holder"`. File
     descriptors survive **both `fork` and `execve`**, and the fd is held **continuously** rather
     than sampled, so this does not add a sixth sampler — **it dissolves the sampling race that
     produced defect 3.** The existing `_INUSE_TOP` fd walk already sees it with **no new code**:

     ```
     forked-subshell  inherited holder fd visible in /proc/<pid>/fd: 1
     exec-d-bash      inherited holder fd visible in /proc/<pid>/fd: 1
     ```

     Make the holder fd the **primary** liveness proof; keep the environ pass as corroboration only.

2X.5c **`_INUSE_TOP` is structurally scoped to `/tmp` and answers "not in use" for every other base.**
     `_mark_inuse` only matches `case "$target" in "$TMP_ROOT"/*)`. For any root on `/var/tmp` or
     `$XDG_CACHE_HOME`, the map is permanently unset — **fail-open toward deletion**, on precisely
     the base where both runners already point `TMPDIR`. Make `_mark_inuse` iterate the base list,
     and run AC4's live-fd spare **and its blinding half** on a disk-backed base, not `/tmp`.

2X.5d **Reaper 3 must be allocation-free on any base it reclaims.** `reap_scratch_entries` allocates
     `cand_file`/`sized_file` via `mktemp` **on the filesystem it is reclaiming** and `return 0`s if
     that fails; the flock `exec 9>` degrades to unserialised on ENOSPC. So the guard's ability to
     reclaim is weakest exactly when reclamation is needed — and per 2X.5b the reaper is the *only*
     defence there. Stream the candidate list; no temp files. Exercise it with a full-base simulation.

2X.5e **Pin an anchored, fixed-arity parse.** The safety claim rests on the name, but only the glob
     is specified — a split-on-dot parse would accept extra fields. Pin
     `^soleur-run\.[0-9]+\.[A-Za-z0-9]{8}$` in ADR-150 and in a near-miss fixture table (extra field,
     missing field, non-numeric pid, trailing dot, embedded newline, `..` component) each asserted
     non-candidate. Reaper 2 already learned the newline lesson the expensive way — Reaper 3 inherits
     the exposure. Use `rm -rf --one-file-system`: neither `rm -rf` nor `find -delete` respects mount
     boundaries, so a bind mount inside a root would otherwise be descended into.

2X.5f **Zombie owner:** `/proc/<pid>` still exists, so a zombie classifies **live** and its root is
     spared forever. Fail-safe but it defeats reclamation — treat `state == Z` as dead, but only
     *after* the liveness pass.

2X.5 **The guard's lockfile relocates under a migrated shell, so `flock` stops serialising.**
     `_lockfile="${TMPFS_GUARD_LOCKFILE:-${TMPDIR:-/tmp}/.tmpfs-guard-$(id -u).lock}"`. Under cron
     `TMPDIR` is unset ⇒ `/tmp/…`; invoked from a migrated `test-all.sh` ⇒ a *different* lockfile
     inside that root. Two guards then take different locks and **run concurrently, racing each
     other's deletes** — the exact condition the lock exists to prevent. Latent today; Phase 3 makes
     it live. **Pin the lockfile to a `TMPDIR`-independent path.**

**Tests:** orphan reaped; live-owner root spared; foreign-uid root a non-candidate; unparseable
name a non-candidate; **authored-work fixture (`pr-body-*.md`, `review-bak.*`, bare
`tmp.XXXXXXXX`) untouched by a non-dry-run pass**; live-fd root spared **and blinding
`_INUSE_TOP` deletes it**; environ-only descendant spared **and blinding the environ seam deletes
it**; quarantine round-trip (lands intact, survives before TTL, deleted after, TTL floors under
pressure); `DRY_RUN=1` neither deletes nor quarantines.

### Phase 3 — One runner (PR 1)

> **Inheritance decision rule — state this at the top, it collapses the migration.**
> If `scripts/test-all.sh` or `apps/web-platform/infra/run-registered-suites.sh` runs you, you
> **inherit the root and do nothing**. Act only if you are `env -i`, `sudo`, cron, `ssh`, or
> `docker run`.

3.0 **Per-entry-point pre-flight — three disqualifiers, all invisible to a `mktemp` grep.** Run
    this on every candidate before migrating it; it is the same class of insight as Tier 3.
    - **Pre-existing `trap … EXIT`** — `trap` **replaces**, it does not compose, so whichever
      registration runs second silently wins. 35 files under `scripts/*.sh` carry one, and the
      named Tier-2 target `run-registered-suites.sh` has `trap 'rm -f "$LOG"' EXIT` immediately
      after its `mktemp` — installing the root trap first means that trap overwrites it and **every
      run of that runner leaks a whole root**. Extend the existing cleanup function; never register
      a second trap (ADR-129 D3 — the migration is what would violate it).
    - **`&`, `nohup`, `setsid`, `disown`** — the parent's EXIT trap quarantines the root while a
      backgrounded child still holds `TMPDIR=<root>`, producing the plan's own User-Brand Impact
      failure *via the trap rather than the reaper*. The scratch-only rule does not cover this: it
      is a path held by a **process** that outlives the parent, not an artifact read by the operator.
    - **`exec "$0"`** — re-exec does **not** run the EXIT trap; the old root is orphaned, and since
      `exec` preserves the pid it matches a live process and is spared for the script's whole life.
      A retry wrapper accumulates one root per attempt.

3.0b **Sourced entry points are out of scope, and the guard must say so.** When a file is
    `source`d, `BASHPID == $$`, so the subshell guard **passes** — the trap then lands on the
    *interactive shell's* EXIT, `TMPDIR` is exported for the rest of that shell's life, and every
    later unrelated command allocates inside a root named for a forgotten session. `.claude/hooks/`
    sources libraries this way. Detect and refuse (`[[ "${BASH_SOURCE[0]}" != "$0" ]]`).

3.1 `scripts/test-all.sh` — allocate one per-run root under the existing `/var/tmp` default,
    covering **234** suite invocations (98 static `run_suite` + 136 glob-expanded; record that
    derivation inline so a future reader does not "correct" it to 98). Preserve "respects an
    explicit caller value" **and** the independent `TC_TMPDIR=/tmp` pin — blinding the ADR-133
    contention instrumentation is a regression that already happened once.

3.2 Quantify and record the coverage fraction: what share of `mktemp` allocations now occur under
    a runner-provided root? If >90%, declare the tail an accepted steady state, exactly as ADR-129
    accepted its class-b population. Left unquantified, the tail reads unbounded and every future
    reader reopens it.

### Phase 4 — Discovery and adoption metric (PR 1)

4.1 **Add one Code Quality rule line to `AGENTS.rest.md`** (new immutable id) naming the idiom.
    Measured: `git grep 'scratch-root\|TMPDIR'` over `AGENTS*.md`, `plugins/soleur/AGENTS.md`, and
    `knowledge-base/overview/*.md` returns **zero** — there is no discovery path today, and this is
    the only channel that reaches an agent writing a *new* file. Verify loader-class fit before
    placing (`grep -n 'DOCS_RE=' -A 25 .claude/hooks/session-rules-loader.sh`) and check
    `lint-agents-rule-budget.py` headroom against the 23000-byte always-loaded cap before adding
    the index pointer.

4.2 **Adoption floor, not the census ratchet.** The census cannot move (Premise Validation): it
    requires a literal `trap … EXIT` in the scanned file, and the idiom puts the trap in the
    library. Record `git grep -l 'soleur_scratch_session_begin' | wc -l` in a `.floor` file; CI
    asserts it never *drops*. Same idiom as `.highwater`, inverse sense, no per-file judgement, no
    escape hatch. Delete the earlier draft's false claim that rule (c) accepts a migrated file for
    free — a future reader would trust it.

4.3 **Residue probe** — run a migrated target with `TMPDIR` at an empty sentinel and assert on-disk
    absence, copying the precedent's `SOLEUR_FT6297_SELFTEST` shape. Note its known blind spot: it
    cannot distinguish correct cleanup from a destroyed deliverable — that is what quarantine
    covers.

4.4 **Do NOT** add a static "entry points must root their temps" lint, and **do not** register
    `scripts/lib/scratch-root.test.sh` (already covered by the `scripts/lib/*.test.sh` glob;
    registering would double-register). ADR-129 rejected the lint class as incoherent.

### Phase 5 — ADR + record correction (PR 1)

5.1 Author ADR-150 per above.
5.2 One-line correction to the merged #6986 plan, whose Premise Validation still directs "adopt the
    registry file and amend ADR-129" — contradicted by its own merged code.

### Phase 6 — Adoption tail (PR 2+, not this PR)

6.1 Rank entry points — but **not with `tmp_delta`, which measures the wrong mount.** `run_suite`
    computes it from `tc_tmp_entry_count`, which reads `$TC_TMPDIR` (pinned to `/tmp`), while every
    suite's allocation lands in `/var/tmp` via `TMPDIR`. A suite leaking 1,883 files — the #6986
    shape — reports `tmp_delta=0`. The residual `/tmp` delta it *does* see is contaminated by every
    other process on the box (measured: +615 entries in 40 minutes from unrelated sources), so it is
    not attributable either. **Rank with the Phase 4.3 residue probe instead**, which measures the
    right thing by construction. **Run it before opening PR 2** so the file list is named, not TBD.
6.2 `run-registered-suites.sh` (**76** suites, not 87) + `/var/tmp` coverage via
    `TMPFS_GUARD_SCRATCH_BASES` — these belong together, because that runner is where roots land on
    a disk-backed base.
6.3 Tier 3 environment boundaries: `env -i` (75 occurrences / 28 files **scoped to `*.sh`**; 176/76
    repo-wide — state the scope), `sudo` (22 files), cron, `ssh`, `docker run`.
6.4 The ~12 absolute `/tmp/<literal>` templates (derivation command required; independent patterns
    give 14 and 5, so the precise figure is not yet reproducible). Each must first be checked
    against the scratch-only rule — several are deliberate authored outputs.
6.5 Soak probe + follow-through enrollment (near-vacuous before adoption, so it ships here).

> **Migration hazard rule — highest-consequence rule in this plan.**
> **A root is scratch-only.** Anything the operator or a later process reads *after exit* stays
> outside it. `gh pr create --body-file /tmp/pr-body.md` must not be "tidied" into a root — that
> converts a surviving deliverable into one the trap destroys, i.e. the pressure tier's failure
> mode re-entering with a trap instead of a `find -delete`. Quarantine is its backstop; bounding
> the edit set (6.1 naming files before the PR) is its real control.

## Observability

```yaml
liveness_signal:
  what: tmpfs-guard heartbeat, overwritten every completed run
  cadence: every 5 min (existing user cron */5)
  alert_target: SessionStart hook renders alarm + stale-heartbeat
  configured_in: scripts/tmpfs-guard.sh (HEARTBEAT_FILE), .claude/hooks/session-rules-loader.sh

error_reporting:
  destination: $HOME/.local/state/soleur/tmpfs-guard-alarms.log, surfaced at SessionStart
  fail_loud: true — alarm_record logs ALARM-DROP when it cannot persist

failure_modes:
  - mode: reaper deletes a root whose owner is dead but whose descendant is live
    detection: both liveness seams asserted non-vacuously (blinding either deletes its fixture);
      reaped basenames land in the capped breadcrumb file, so a developer hitting ENOENT has a
      one-grep answer rather than a journal hunt
    alert_route: guard_log + tmpfs-guard-reaped.log
  - mode: allocator naming schema drifts out of sync with the reaper glob (silent no-op reaper)
    detection: candidates-found AND reaped counters logged every run. found=0 for N consecutive
      runs while the adoption floor is non-zero is the distinguishable signature — the earlier
      draft's "found>0, reaped=0" check could NOT see this, which is the #6992 class reappearing
      in the detector written to prevent it
    alert_route: alarm_record -> SessionStart
  - mode: quarantine stops draining and becomes a second leak
    detection: quarantine count + oldest age logged each run; surviving two passes past TTL
    alert_route: guard_log + alarm_record
  - mode: alarm watermark disarms (frozen high after a reboot, or blind during the drain)
    detection: watermark logged beside the live non-schema count; watermark above live count for
      two consecutive runs is the signature
    alert_route: alarm_record -> SessionStart
  - mode: allocator called in a subshell (the #6986 defect)
    detection: BASHPID guard returns non-zero at call time; unit-tested
    alert_route: caller's non-zero exit
  - mode: cron stops firing
    detection: heartbeat mtime older than cadence (existing)
    alert_route: SessionStart stale-heartbeat block

logs:
  where: journal via `logger -t tmpfs-guard`; capped breadcrumb at
    $HOME/.local/state/soleur/tmpfs-guard-reaped.log; tests use TMPFS_GUARD_LOG_SINK
  retention: journal default; alarm + breadcrumb files capped at 200 lines

discoverability_test:
  command: >
    TMPFS_GUARD_DRY_RUN=1 bash scripts/tmpfs-guard.sh &&
    cat "$HOME/.local/state/soleur/tmpfs-guard-last-run" &&
    tail -20 "$HOME/.local/state/soleur/tmpfs-guard-reaped.log"
  expected_output: heartbeat updated; dry-run lines name candidate roots and their owner pid;
    nothing deleted, nothing quarantined
```

No `ssh` in any verification path. The cron worker is a blind execution surface, so every
`detection` names a probe emitted **from** that process, and the log line's fields (owner pid,
seam that spared it, quarantine age) discriminate the competing causes in one event.

## Infrastructure (IaC)

**Not applicable.** The guard is already on the operator's user crontab at `*/5 * * * *`; this
adds a function to the script cron already runs. No server, service, unit, secret, DNS record,
vendor account, or firewall rule; no Terraform root touched. `systemd-tmpfiles` is **read** for
the backlog bound and deliberately not modified.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Six reviewers (DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, CTO-devex) plus a strong-model consult. Findings that reshaped the plan:
the four-field schema cut (both simplification and correctness panels fired on the same scope);
quarantine adopted after the consult proved the residue probe cannot distinguish a destroyed
deliverable from clean scratch; the census ratchet proven vacuous and replaced with an adoption
floor; the `scratch-root.test.sh` "unregistered" premise proven **false**; the reaper count
corrected 3 → 6; the build-vs-buy "buy" option measured to be a **silent no-op**. One advisory
claim was **refuted by measurement** and not adopted (backlog "3.1 MB / 2.6%"; actual 677 MB / 34%).

### Product/UX Gate

Not applicable. Independent mechanical UI-surface scan of `## Files to Create` / `## Files to
Edit`: every path is `scripts/**`, `AGENTS.rest.md`, or `knowledge-base/**`. No
`components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`. Product tier = **NONE**.

**Assessed and not relevant:** Marketing, Sales, Finance (no spend), Legal, Operations (no
provisioning or vendor account — local developer tooling), Support.

## GDPR / Compliance Gate

Canonical regulated-data regex does not match: no schema, migration, auth flow, API route, or
`.sql`. Of the four expansion triggers only (b) fires (threshold = `single-user incident`).
Assessed: reads no file contents, transmits nothing off-host, adds no processing activity, touches
no personal data — inputs are directory names it created and `/proc`. **No Article 30 entry, no
lawful-basis question, no disclosure change.**

## Acceptance Criteria

**Nineteen** (`AC-A1`, `AC1`–`AC15`, with `AC4` split into `AC4`/`AC4b`/`AC4c`/`AC4d`), across
three PRs. The count moved twice and the direction matters: an earlier draft's twenty were cut to
ten after review removed ceremony that restated phase instructions, asserted the status quo, or —
in two cases — was **unfalsifiable**. The five-defects sweep (Phase 2X) then *added* nine, because
each defect it found is one the plan's safety argument depends on and none was covered by an
existing criterion. Fewer ACs is not the goal; every AC here fails on a real defect.

### PR 0

- [ ] **AC-A1 — Watermark silences the legacy and still catches growth.** (a) legacy present +
  zero orphans ⇒ **no** alarm; (b) simulate the drain ⇒ the persisted watermark **decreases**;
  (c) growth above the *new* watermark ⇒ **alarms**; (d) simulate a `/tmp` reset to ~0 ⇒ the
  watermark re-floors and does **not** disarm. (c) and (d) are the two a frozen baseline fails.

### PR 1 — Pre-merge

- [ ] **AC1 — Zero non-leak candidates against a real `/tmp` carrying the leak.** Re-derive the
  live count, create N orphaned roots plus one live-owner root, run `TMPFS_GUARD_DRY_RUN=1`:
  reports exactly the N orphans and spares the live root.
- [ ] **AC2 — Authored work survives a NON-dry-run.** A fixture of `pr-body-*.md`, `review-bak.*`,
  a bare `tmp.XXXXXXXX` tree, **and a foreign-uid `soleur-run.*`** is untouched after a real reap.
  (The foreign-uid arm is the non-tautological half — the rest is guarded by the glob.)
- [ ] **AC3 — Full pass fits the interval, bound recorded.** `time` the dry run **with the environ
  pass enabled** (it is O(own-uid pids), not O(candidates), so the 0.046 s prototype figure does
  not bound the shipped thing). Re-measure and set the threshold within ~3× of the new number;
  record it in the PR body. This AC is retained because it is an operator-stated criterion in #7004.
- [ ] **AC4 — The holder fd is the primary liveness proof, and it covers the shapes environ cannot.**
  Three arms, each run **on a disk-backed base** (not `/tmp`, per 2X.5c): (a) a root whose only
  survivor is a **forked subshell** `( … ) &` is spared — this shape is invisible to environ and to
  every other sampled seam; (b) a root whose only survivor is an **exec'd** child is spared;
  (c) removing the holder fd from the allocator causes (a) to be **deleted** (non-vacuity).
- [ ] **AC4b — `_INUSE_TOP` is base-aware.** A live-fd root on `/var/tmp` is spared. With the
  pre-fix `_mark_inuse` (scoped to `$TMP_ROOT` only) the same fixture is **deleted** — the fail-open
  this AC exists to pin.
- [ ] **AC4c — The name parse is anchored and fixed-arity.** A near-miss fixture table (extra field,
  missing field, non-numeric pid, trailing dot, embedded newline, `..` component) is entirely
  classified non-candidate.
- [ ] **AC4d — The reaper is allocation-free on the base it reclaims.** With the base simulated
  full, Reaper 3 still enumerates and reclaims; it allocates no temp file on that base.
- [ ] **AC5 — Owner-present fails open.** A root whose `/proc/<pid>` exists is spared even with no
  other liveness evidence.
- [ ] **AC6 — The subshell guard fires.** `soleur_scratch_session_begin` invoked as `$( )` returns
  non-zero and leaves no root; and a forced `mktemp -d` failure never leaves `TMPDIR` empty.
- [ ] **AC7 — Reap is reversible for one interval.** A reaped root is found in quarantine with
  contents intact, survives a pass before the TTL, is deleted after it, and the TTL floors to zero
  under simulated block pressure.
- [ ] **AC8 — `TC_TMPDIR` independence preserved.** After Phase 3.1, `TC_TMPDIR` still resolves to
  `/tmp` and `tc_tmp_entry_count` observes `/tmp`.
- [ ] **AC9 — Discovery + adoption floor exist.** The `AGENTS.rest.md` rule is present and passes
  `lint-rule-ids.py` + `lint-agents-rule-budget.py`; the `.floor` file records a non-zero count and
  CI fails when it drops.
- [ ] **AC10 — Reaper 2 cannot delete a scratch root (2X.1).** A `soleur-run.*` root that is
  ≥`SCRATCH_MIN_MB` and older than `SCRATCH_AGE_MIN` — i.e. clears every one of Reaper 2's gates —
  survives a full non-dry-run guard pass. Assert the same for `soleur-quarantine.*`. **Without this
  AC the plan's central safety claim is false**, because Reaper 2 has no name filter and no environ seam.
- [ ] **AC11 — `_INUSE_TOP` fails closed (2X.2).** With the map's built-sentinel absent, Reaper 3
  **aborts and reaps nothing** rather than treating an unbuilt map as "nothing is in use".
- [ ] **AC12 — The environ seam prefix-matches (2X.3).** A nested root
  (`<outer>/soleur-run.…`) held by a live descendant causes the **outer** root to be spared after
  the outer owner is killed. An exact-match implementation fails this.
- [ ] **AC13 — An entry point is actually migrated.** `scripts/test-all.sh` allocates a root: a real
  suite run produces exactly one `soleur-run.*` under the base and zero loose `tmp.*` attributable
  to it. **Every other AC could pass with Phase 3 unimplemented** — this is the one that gates the
  feature's value rather than its machinery.
- [ ] **AC14 — Tests cannot touch the operator's real filesystem.** The suite pins **both**
  `TMPFS_GUARD_TMP` **and** `TMPFS_GUARD_SCRATCH_BASES`; a guard invoked with the new seam unset
  under test defaults fail-closed rather than scanning real `/var/tmp`. (AC2 mandates a non-dry-run
  reap, so an unpinned second seam would delete real roots.)
- [ ] **AC15 — Full suite green.** `bash scripts/test-all.sh` passes.

### Post-merge (operator)

None. The guard is already on cron; the merge is the deployment.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-150-declared-ownership-scratch-roots-for-tmpfs-reclamation.md`
- `scripts/soleur-scratch-adoption.floor`

## Files to Edit

- `scripts/lib/scratch-root.sh` — `soleur_scratch_session_begin`, contract, subshell guard
- `scripts/lib/scratch-root.test.sh` — new assertions (already runner-covered by the glob)
- `scripts/tmpfs-guard.sh` — Phase A watermark; Reaper 3; environ seam; `_build_inuse_top` hoist; quarantine; breadcrumb; header pointer
- `scripts/tmpfs-guard.test.sh` — classification, both-seam non-vacuity, authored-work fixture, quarantine, watermark
- `scripts/test-all.sh` — one per-run root; preserve the `TC_TMPDIR` pin
- `AGENTS.rest.md` — one Code Quality rule (new immutable id) + `AGENTS.md` index pointer
- `knowledge-base/project/plans/2026-07-27-fix-tmp-tmpfs-mktemp-cleanup-leak-plan.md` — stale-directive correction

## Open Code-Review Overlap

**None.** All 61 open `code-review` issues queried against every path above; zero matches.

- **#6760** (`skill-security-scan` leaks 7,603 dirs) — **acknowledge, do not fold in.** A
  *retention* problem: its trap deliberately spares a durable output the caller reads after exit.
  Adopting a root there would delete the artifact the caller needs — it is the migration hazard
  rule in issue form. It is also the larger measured leak, which is another reason to keep PR 1 small.
- **#7005** (`pipefail` + `grep -q` sweep) — **acknowledge.** `tmpfs-guard.sh` is in that scope;
  this plan adds no new `| grep -q` shape.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Dead owner, live descendant ⇒ deleting live data | Both liveness seams mandatory, both asserted non-vacuously (AC4). Measured: `_INUSE_TOP` alone is blind |
| `environ` is exec-time, so a runner between child invocations publishes nothing | `<pid>` retained precisely for this window; documented inline so it is not "simplified" away |
| Trap does not fire on SIGKILL — and tmpfs pressure produces SIGKILLs | Accepted and explicit: the reaper is the *only* defence under that condition, not a redundancy |
| Migration moves an authored artifact inside a root | Scratch-only rule + quarantine backstop (AC7) + bounding the edit set by naming files before PR 2 |
| Quarantine becomes a second leak or delays reclamation | TTL drain each pass; floors to zero under pressure (AC7) |
| Alarm disarms after a reboot, or goes blind during the drain | Re-floored watermark; AC-A1(c)+(d) |
| Silent no-op reaper if the schema drifts from the glob | found-count telemetry + adoption floor cross-check (Observability mode 2) |
| Six reapers racing over `/tmp` | Reaper 3 shares `tmpfs-guard.sh`'s flock with Reaper 2; one authoritative ADR-150 table with pointers replaces three partial comments |
| `/proc` unreadable (`hidepid`) | Owner reads as absent ⇒ would reap; liveness seams also go blind. **Detect and skip the arm entirely** rather than reap on degraded evidence |

## Test Scenarios

Shell suites, repo convention (`<script>.test.sh`, pass/fail counters, loud failures,
fixture-scoped roots, synthesized fixtures per `cq-test-fixtures-synthesized-only`).

1. **Allocator** — contract (prints nothing, `$TMPDIR` inside root), subshell guard, `mktemp`-failure
   safety, trap on EXIT/INT/TERM, quarantine fallback, guards under `-e` and `+e`.
2. **Classification** — orphan reaped; live owner spared; foreign uid, unparseable name non-candidates.
3. **Safety (both directions)** — authored-work fixture untouched by a non-dry-run; live-fd spared
   and blinding `_INUSE_TOP` deletes it; environ-only descendant spared and blinding environ deletes it.
4. **Quarantine** — lands intact, survives before TTL, deleted after, floors under pressure, `DRY_RUN` inert.
5. **Watermark** (PR 0) — silence, drain-decrease, growth-catch, reboot-reset non-disarm.
6. **Integration** — allocate under a fixture base, kill the owner, run the guard, assert reclamation.
