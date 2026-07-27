---
title: "fix: /tmp tmpfs fills because cleanup registration is lost in nested command substitution"
date: 2026-07-27
type: fix
branch: feat-one-shot-tmp-tmpfs-mktemp-leak
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# fix: /tmp tmpfs fills because cleanup registration is lost in nested command substitution

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No
> `knowledge-base/project/specs/feat-one-shot-tmp-tmpfs-mktemp-leak/spec.md` exists.

## Overview

The operator's workstation `/tmp` is a 4 GiB RAM-backed tmpfs that repeatedly fills and
wedges agent sessions — tool output fails to write, and even `du` cannot write its own
output. This plan fixes the leak at its source, closes the two blind spots in the guards
that were *supposed* to catch it, and stops routing bulk temp writes at RAM.

**The single most important finding of the research phase is that two of the six requested
deliverables already exist and are already deployed.** The routing brief asked for a CI
guard (item 3) and a janitor (item 6). Both were built and merged weeks ago:

| Requested | Already exists | Shipped in |
|---|---|---|
| CI guard for `mktemp` without a cleanup trap | `scripts/lint-trap-tempfile-ownership.py` (557 lines, 2 rules, escape hatch, high-water ratchet) | #6734 / ADR-129 |
| Age-and-prefix janitor that spares live sessions | `scripts/tmpfs-guard.sh` (257 lines, ownership + age + size + liveness gates, dry-run seam) | #6789 |

`tmpfs-guard.sh` is not merely present — it is **live in the operator's crontab right now**
(`*/5 * * * *`), and it has been running throughout the entire period the leak accumulated.

So the real question is not "why is there no guard?" It is **"why did two purpose-built
guards, both running, both written for exactly this defect class, fail to stop it?"** This
plan answers that with two measured root causes, and the work is scoped to closing them
rather than rebuilding what exists.

### Root cause 1 — the linter cannot see through a named-function trap

`scripts/lint-trap-tempfile-ownership.py` rule (a) detects precisely this defect: a helper
that appends to a cleanup array while being invoked via command substitution. It did not
fire on the leaking file. Measured, not inferred:

```
$ python3 scripts/lint-trap-tempfile-ownership.py scripts/followthroughs/anthropic-admin-key-6297.test.sh
exit=0                       # ← clean. The guard sees nothing.
```

The reason is `trap_owned_arrays()`. It scans lines matching `trap ... EXIT` and harvests
variable names **from the trap line itself**. The leaking file writes:

```bash
trap cleanup_tmp EXIT INT TERM      # names a FUNCTION, not the array
```

so the harvested set is empty and `TMP_PATHS` is never recognised as a cleanup array.
Confirmed directly against the module:

```
owned set = []
TMP_PATHS in owned? False
```

Rule (a) therefore only fires when the trap body is written **inline**
(`trap 'rm -f "${ARR[@]}"' EXIT`). Every script that factors cleanup into a named function —
the *better* style, and the one this file's own comments defend — is invisible to it.

**But that is not the binding blind spot, and a fix that addresses only it changes nothing.**
There is a second, earlier filter. `ARRAY_APPEND` is anchored at line start:

```python
ARRAY_APPEND = re.compile(r'^\s*(\w+)\+=\(')     # lint-trap-tempfile-ownership.py
```

The leaking helpers are one-liners, so `TMP_PATHS+=(` sits mid-line after a `;`. Measured:

```
line 31: current-anchored match = False | un-anchored search = True
line 32: current-anchored match = False | un-anchored search = True
```

`check_rule_a` discards these lines at the append test — **before** `owned` is ever consulted.
So the two blind spots are sequential, and the anchor is the outer one. A prototype of the
named-function fix alone, run over all 689 tracked `*.sh`, returns **0 findings**. Un-anchoring
the append *and* resolving named-function traps returns **exactly 2 findings — both the real
defect (lines 31, 32), zero false positives**, with the two nearest-miss files
(`.claude/hooks/lib/session-state.test.sh`, `apps/web-platform/infra/cutover-inngest-workflow.test.sh`)
correctly staying silent because their appends are at top level rather than inside a
`$()`-invoked function.

This also corrects the sweep denominator: the true blind-spot population is **12 files, not 10**
— the plan's own derivation missed two for the very same mid-line reason. Both additions are
*sound*; no fix is owed for them, but AC12 must not assert `10/10`.

Rule (c) also cannot help: it is `mktemp`-with-*no*-trap, and this file has a trap. The
routing brief predicted this exactly — "the current design would pass a naive 'a trap
exists' check" — and that prediction is now verified against the real implementation.

### Root cause 2 — the janitor's size floor excludes the entire leak

`tmpfs-guard.sh`'s scratch reaper requires a candidate to clear a **100 MB size floor**
(`SCRATCH_MIN_MB=100`) before anything else is evaluated. That floor was calibrated in
#6789 against a measured incident where *three* trees held 3.1 GiB — a small number of very
large entries. The leak in front of us is the exact inverse: a very large number of very
small entries.

```
$ du -sm /tmp/tmp.* | awk '$1>=100{n++} END{print n+0}'
0                            # ← zero of 11,052 entries reach the floor
```

Accurate apparent-size totals (`du -sk --total`, not the per-entry-rounded `du -sm`):

| Class | Count | Total | Mean/entry |
|---|---|---|---|
| `tmp.*` | 11,052 | 422 MB | ~39 KB |
| `ft6297.*` | 1,883 | 186 MB | ~101 KB |
| `ft.*` | 1,883 | 4.5 MB | ~2.4 KB |

Not one entry is individually reapable. The guard has been executing every five minutes,
correctly, and finding nothing — because a leak measured in *count* is structurally
invisible to a reaper gated on *size*. This is a genuine calibration gap, not a bug.

### Why the leak has the exact shape it does

`scripts/followthroughs/anthropic-admin-key-6297.test.sh` allocates through two helpers:

```bash
mktmp()  { local p; p=$(mktemp "$@");    TMP_PATHS+=("$p"); printf '%s' "$p"; }
mktmpd() { local p; p=$(mktemp -d "$@"); TMP_PATHS+=("$p"); printf '%s' "$p"; }
```

Every call site uses command substitution, so the append mutates a subshell copy and is
discarded. The parent `TMP_PATHS` stays empty and `cleanup_tmp` iterates nothing. The
perfectly matched **1,883 / 1,883** pairing is the signature: one `ft.*` fixture file and
one `ft6297.*` sandbox directory per test case, never removed, accumulated since Jul 20.

**This file violates an accepted ADR in writing.** ADR-129 Decision #2 states: *"Cleanup
arrays are appended in the PARENT scope, never inside `$( )`. Allocate in the helper,
register at the call site."* The rule existed; the enforcement had a hole.

### The nesting detail that changes the fix

The obvious remedy — apply ADR-129 #2 literally and register at each call site — **does not
work here**, and this is the plan's most important design finding. The allocation is nested
**two levels** deep in command substitution:

```bash
make_sandbox() {
  local d
  d=$(mktmpd -t ft6297.XXXXXXXX)     # level 2 subshell
  ...
  echo "$d"
}
...
d=$(make_sandbox "$f")               # level 1 subshell — 20 call sites
```

Registering at the `mktmpd` call site inside `make_sandbox` is *still* inside a subshell,
because `make_sandbox` is itself command-substituted. The append would be lost again — a
fix that looks correct, passes an inline reading, and leaks identically.

A shell array cannot escape a subshell at any nesting depth. **A file write can.** The fix
is therefore a registry *file*: allocation appends one line, the trap reads the file. This
is immune to arbitrary nesting by construction, which is exactly the property the array
lacks. It requires an amendment to ADR-129 (Phase 5) because it extends Decision #2 rather
than following it.

## Premise Validation

Every claim in the routing brief was re-verified. Results:

| Claim from brief | Verdict | Evidence |
|---|---|---|
| `/tmp` is tmpfs, `size=4G` | **HOLDS** | `findmnt`: `size=4194304k` |
| `/etc/fstab` pins `size=4G` | **HOLDS** | `/etc/fstab:13` verbatim as quoted |
| Host RAM 30 GiB | **HOLDS** | `free -g`: total 30 |
| `/tmp` now ~1.1G used / 3.0G avail | **HOLDS** | `df -h /tmp`: 1.1G used, 3.0G avail, 26% |
| `tmp.*` ≈ 11,037 entries | **HOLDS** (11,052 now) | count drifted up during the session — still leaking |
| `ft.*` 1,883 + `ft6297.*` 1,883 | **HOLDS exactly** | confirms the per-test-case pairing hypothesis |
| oldest `ft.*` is Jul 20 | **HOLDS** | `/tmp/ft.GFw0N75v`, Jul 20 10:59 |
| `tmpfiles.d` ages `/tmp` at 10d | **HOLDS** | `/usr/lib/tmpfiles.d/tmp.conf:11` — `q /tmp 1777 root root 10d`; no `/etc/tmpfiles.d` override |
| Subshell bug at lines 31-32 | **HOLDS** | read verbatim; nesting is worse than described (2 levels) |
| `sudo -n` is not passwordless | **HOLDS** (not re-probed) | accepted from brief; Phase 4 does not depend on it |
| "191M total" for `ft` classes | **HOLDS** | 4.5 MB + 186 MB = 190.5 MB |
| **"No open GitHub issue targets this"** | **STALE** | **#6760 is open** and tracks a sibling leak class (below) |
| **Item 3: a CI guard must be built** | **STALE** | `lint-trap-tempfile-ownership.py` exists (#6734/ADR-129) |
| **Item 6: a janitor must be built** | **STALE** | `tmpfs-guard.sh` exists (#6789) and is live on a `*/5` cron |

**Open issue #6760** — *"skill-security-scan leaks one runtime dir per invocation (7,603
observed) — needs a retention policy, not a trap"* — is already filed, labelled
`priority/p2-medium`, and is explicitly **not** a missing-trap defect (the script's trap
deliberately spares a durable output the caller reads after exit). It is a *retention*
problem, a genuinely different fix. See "Open Code-Review Overlap" for disposition.

**Prior art check (`hr-verify-repo-capability-claim-before-assert`):** ADR-129 and ADR-133
were both read before asserting any capability bound. ADR-133 (`test-all` tmpfs contention,
managed resource + advisory lock) and `scripts/lib/test-contention.sh` already establish
that `${TMPDIR:-/tmp}` is the repo's tmpfs-observation seam — which is why Phase 3 extends
that lib rather than inventing a new one.

## Hypotheses — the 2.3 GiB `/tmp/tmp.iDFle9tyKl` producer

**Disposition: UNKNOWN. This is deliberate and must not be "resolved" by reasoning.**

The brief notes the directory was removed by hand before this pipeline started. That
directory *was* the deciding datum. With it gone there is no observation that can
discriminate between candidate producers, and any verdict below CONFIRMED would be
reasoning dressed as evidence. Per the plan-skill Sharp Edge on refuting a hypothesis while
its discriminator is invisible, all rows stay UNKNOWN.

| # | Candidate | Shape match | Status |
|---|---|---|---|
| H1 | `constraint-scaffold/scripts/constraint-scaffold.sh:104` — `WT="$(mktemp -d)"` (bare, so `tmp.XXXXXXXX` class) + `git worktree add --detach` (full tree ⇒ contains both `apps/web-platform` and `apps/cla-evidence`) + `ln -s` to real `node_modules`. Trap is `EXIT` **only** — no `INT TERM HUP`, so a ^C or harness kill orphans it. | Strong on name class, tree contents, and kill-path leak. **Weak on size**: it *symlinks* `node_modules` rather than hydrating it, so the tree is ~231 MB unless measured with `du -L`. | UNKNOWN |
| H2 | `constraint-scaffold/test/boundary.test.sh:200` — bare `mktemp -d` + real `npm install` at :215, trap `EXIT` only. | Right *shape* (bare mktemp + real install), wrong *contents* — installs dependency-cruiser + typescript (tens of MB), never `next-swc`/`@napi-rs/canvas`/`claude-agent-sdk`. | UNKNOWN |
| H3 | An uncommitted / ad-hoc invocation, or a since-changed script. | Cannot be excluded from the repo alone. | UNKNOWN |

**Why this does not block the work.** The fix is class-scoped, not instance-scoped. Phase 2
brings *every* bare-`mktemp -d` + incomplete-trap site up to the `EXIT INT TERM` bar,
which covers H1 and H2 whether or not either produced that specific directory. Phase 6
adds the count-based reaper that reclaims the class regardless of producer. Identifying the
individual producer would be satisfying; it is not load-bearing for any deliverable.

**Standing probe (Phase 6).** The new count-based reaper logs the top-level entry name and
size of everything it reaps via `logger -t tmpfs-guard`. If a multi-GB bare-`mktemp -d`
tree recurs, the journal will name it at reap time — turning the next occurrence from an
un-attributable post-mortem into a labelled observation. This is the in-surface probe the
current setup lacks.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| "Add a CI guard so this cannot regress" | Guard exists (#6734), is wired into CI, has an escape hatch and a high-water ratchet at 100 (live census: 98) | **Re-scoped**: fix rule (a)'s named-function blind spot + add a fixture proving the nested case fires. Do not build a second guard. |
| "Reclaim stale artifacts safely: a janitor…" | Janitor exists (#6789), deployed on `*/5` cron, already has ownership + recursive-age + `/proc` cwd+fd liveness + dry-run | **Re-scoped**: add a count-based reap arm for the small-entry class the 100 MB floor excludes. Reuse every existing safety gate. |
| "append the path to a registry FILE" | ADR-129 Decision #2 mandates the *opposite* (parent-scope array registration) | **Adopt the registry file, and amend ADR-129** — parent-scope registration is provably insufficient at 2-level nesting (see Overview). Divergence is deliberate and recorded. |
| "Known-good examples… all four already trap correctly" | Verified: all four use inline-body traps, which is why rule (a) sees them | Model the *ownership*, not the inline style — the named-function style is better and must be made detectable rather than avoided. |
| "No open GitHub issue targets this yet" | #6760 open (sibling class); #6713, #6734, #6789 closed (direct lineage) | File one new tracking issue for *this* defect; cross-ref #6760, do not duplicate it. |
| `du -sm` totals in the brief (2.7G for `tmp.*`) | `du -sm` rounds every entry up to ≥1 MB; across 11,052 entries that inflates by ~10× | Use `du -sk --total`. Real figure: **422 MB**. The brief's 2.7G conflated this with the since-deleted 2.3G tree. |

## User-Brand Impact

**If this lands broken, the user experiences:** the janitor's new count-based arm deletes a
directory an in-flight agent session is actively using — the session loses its scratchpad
mid-run and fails with a confusing ENOENT rather than an obvious cause. This is the same
"a leak of this shape does not announce itself, it corrupts the next thing that needs
space" failure mode #6760 describes, inverted into an over-eager reap.

**If this leaks, the user's workflow is exposed via:** nothing is *exposed* — `/tmp` entries
are uid-scoped and the reaper never widens permissions. The exposure axis here is
availability, not confidentiality: the operator is a solo founder whose entire workday runs
through these agent sessions, and a wedged `/tmp` costs a full session's context.

**Brand-survival threshold:** `single-user incident`

Justification: the deliverable includes an **unattended, recurring, destructive delete** on
the operator's own machine, running as a `*/5` cron with no human in the loop. A
mis-scoped predicate does not degrade gracefully — it removes live work. That blast radius
warrants CPO sign-off at plan time and `user-impact-reviewer` at PR time, and it is why
every safety gate in Phase 6 is additive to (never a relaxation of) the existing ones.

## Implementation Phases

### Phase 0 — Preconditions (verify before writing code)

0.1 Re-run the falsifying measurements so the fix is built against current state, not
against this document:
```bash
python3 scripts/lint-trap-tempfile-ownership.py scripts/followthroughs/anthropic-admin-key-6297.test.sh; echo "exit=$?"   # expect exit=0 (the false negative)
python3 scripts/lint-trap-tempfile-ownership.py --census                                                                  # expect 98
du -sm /tmp/tmp.* 2>/dev/null | awk '$1>=100{n++} END{print n+0}'                                                         # expect 0
```
0.2 Confirm the test runner: this repo's shell suites are plain `*.test.sh` executed
directly (no bats — `command -v bats` returns nothing). Do **not** introduce a framework.
0.3 Confirm `scripts/lint-trap-tempfile-ownership.test.sh` (161 lines) is the fixture
harness to extend, and read its fixture-naming convention before adding cases.

### Phase 1 — RED: prove the leak and prove the guard is blind

Two failing tests, written before any fix (`cq-write-failing-tests-before`):

1.1 **On-disk absence regression.** In a new
`scripts/followthroughs/anthropic-admin-key-6297-cleanup.test.sh`: drive the helper
**through command substitution at the real nesting depth** (a `$(outer)` that internally
does `$(mktmpd)`), capture the returned path, let the script exit, then assert the path is
**gone from disk**. Asserting "a trap is registered" is explicitly forbidden — that check
passes today against a script that leaks 3,766 entries. The assertion must be
`[[ ! -e "$path" ]]` after process exit.

1.2 **Linter blind-spot fixture.** Add a fixture to
`scripts/lint-trap-tempfile-ownership.test.sh` that reproduces the named-function
indirection (`trap cleanup_tmp EXIT` + `TMP_PATHS+=(...)` inside a `$()`-invoked helper) and
assert the linter **exits 1**. It currently exits 0; this test must fail first.

### Phase 2 — GREEN: fix the leak site and sweep the class

2.1 Convert `anthropic-admin-key-6297.test.sh` to a **registry file**: `mktmp`/`mktmpd`
append the allocated path to `$TMP_REGISTRY` (itself a `mktemp` allocated before the trap is
installed); `cleanup_tmp` reads the registry line-by-line and removes each path, then the
registry. A file write escapes every subshell, so this is correct at any nesting depth.
Carry the existing header comment's reasoning forward and extend it to name the nesting.

2.2 **Sweep, do not spot-fix** (`hr-write-boundary-sentinel-sweep-all-write-sites`). Audit
these 10 files — every tracked `*.sh` pairing a named-function EXIT trap with an array
append, i.e. the exact rule-(a) blind spot — and classify each as *defective* (helper
invoked via `$()`) or *sound* (registration already in the parent scope):

```
.claude/hooks/pre-merge-auto-close-scan.test.sh
apps/web-platform/infra/canary-bundle-claim-check.test.sh
apps/web-platform/infra/workspaces-cutover.sh
apps/web-platform/infra/workspaces-luks-loopback.test.sh
plugins/soleur/skills/code-to-prd/scripts/code-to-prd.sh
plugins/soleur/skills/community/scripts/github-community.sh
plugins/soleur/skills/provision-cloudflare/scripts/provision-cloudflare.sh
plugins/soleur/skills/provision-doppler/scripts/provision-doppler.sh
plugins/soleur/skills/provision-github/scripts/provision-github.sh
scripts/domain-model-drift.sh
```

Record the verdict for each in the PR body. Fix the defective ones; leave the sound ones
untouched (a sweep that "fixes" correct code is how a gate loses trust).

2.3 Fix the **incomplete-signal** traps found in the H1/H2 candidates —
`constraint-scaffold.sh:105` and `constraint-scaffold/test/boundary.test.sh:201` both use
`trap ... EXIT` with no `INT TERM`. Bring both to `EXIT INT TERM` (matching the
`credential-persist-home-guard.test.sh:62` precedent, which uses `EXIT INT TERM HUP`).
`constraint-scaffold.sh` additionally leaves a `git worktree` administrative entry on the
kill path — its cleanup already calls `worktree remove --force`, so extending the signal
list is sufficient; verify no `git worktree prune` is separately required.

### Phase 3 — Route bulk temp writes off RAM

3.1 Extend `scripts/lib/test-contention.sh` — already the repo's `${TMPDIR:-/tmp}`
observation seam per ADR-133 — with a `soleur_default_tmpdir()` that resolves a **disk-backed**
scratch root (`${XDG_CACHE_HOME:-$HOME/.cache}/soleur/tmp`), creates it `0700`, and exports
`TMPDIR` only when the caller has not already set one. Never override an explicit `TMPDIR`.

3.2 Apply it at the high-volume sites specifically: `constraint-scaffold.sh` and
`constraint-scaffold/test/boundary.test.sh` (the repo-copy + install class, where a single
run can be GB-scale against a 4 GiB mount). A leak there then costs disk (hundreds of GB
available) instead of wedging the machine.

3.3 Document the env default in the repo's shell-conventions surface so new scripts inherit
it, and add the one-line rationale: tmpfs is RAM; a leak on RAM is an outage, a leak on disk
is a chore.

**Guard rail:** `workspaces-cutover.sh:1989-2001` hard-aborts when `$TMPDIR` resolves under
its mount (#6733). Verify the new default cannot land inside any path that script certifies
— `$HOME/.cache` is outside every such mount, but assert it rather than assume it.

### Phase 4 — Raise the tmpfs ceiling, without a prose checklist

Per `hr-never-label-any-step-as-manual-without` and `hr-exhaust-all-automated-options-before`:
ship an executable, **not** a checklist.

4.1 New `scripts/raise-tmp-tmpfs-ceiling.sh` — idempotent and re-runnable:
- Detect the current `size=` in `/etc/fstab`; **no-op with exit 0** if already at or above
  target (the idempotency guard).
- Back up `/etc/fstab` to a timestamped sibling before any write.
- Rewrite only the `/tmp` tmpfs line's `size=` field (`8G` proposed — 27% of 30 GiB RAM,
  still far under systemd's 50% default, so the downward pin's original intent is preserved
  rather than discarded).
- Install `/etc/tmpfiles.d/tmp.conf` as a drop-in overriding the 10d age to **2d** for
  `/tmp` only. `/etc/tmpfiles.d` shadows `/usr/lib/tmpfiles.d` by filename, and the
  directory already exists (holds `screen-cleanup.conf`), so this is the supported
  mechanism, not a workaround.
- `--dry-run` prints every intended mutation and writes nothing.
- Validate the resulting fstab (`findmnt --verify --tab-file`) **before** exiting non-zero
  on failure, and restore the backup if validation fails. A broken `/etc/fstab` is a
  boot-time failure on the operator's only machine — this rollback is not optional.
- Print the single privileged invocation that applies it, plus the
  `mount -o remount /tmp` that avoids a reboot.

4.2 `scripts/raise-tmp-tmpfs-ceiling.test.sh` — drives the script against a **fixture**
fstab via an injected path seam (mirroring `TMPFS_GUARD_TMP` in `tmpfs-guard.sh`), never
against the real `/etc/fstab`. Cases: already-applied ⇒ no-op; unapplied ⇒ rewritten +
backup exists; malformed ⇒ restored + non-zero; `--dry-run` ⇒ zero writes.

**This step is root-gated, not judgement-gated.** The script makes 100% of the decisions; the
only human contribution is the `sudo` credential, which cannot be automated (`sudo -n` is not
passwordless on this host). That is the irreducible residue.

### Phase 5 — Close the guard's blind spot

5.1 Extend `trap_owned_arrays()` to **resolve one level of function indirection**: when a
`trap` line names a bare identifier that `find_functions()` knows to be a function, harvest
variable names from that function's *body* as well as from the trap line. `find_functions()`
already returns the needed `(start, end)` spans, so this reuses existing machinery.

5.2 Extend rule (a)'s call-site detection to treat a helper as command-substituted when it is
invoked via `$()` **transitively** — i.e. `mktmpd` called inside `make_sandbox`, where
`make_sandbox` is itself `$()`-invoked. Bound this to a single transitive hop; unbounded
call-graph analysis is out of scope and would risk the fires-on-correct-code failure ADR-129
warns about repeatedly.

5.3 Preserve every existing property: the `# lint-trap-ownership: ok <reason>` escape hatch
(with its non-empty-reason requirement), the added-line scoping for rule (c), the fail-open
behaviour on an unresolvable merge base, and the high-water ratchet.

5.4 Re-run `--census`. The count should not *rise*; if the Phase 2 fixes lower it, lower
`scripts/lint-trap-tempfile-ownership.highwater` in the same PR to ratchet the accept.

### Phase 6 — Reclaim the small-entry class

6.1 Add a **count-based** reap arm to `tmpfs-guard.sh`'s `reap_scratch_entries`, alongside
(never replacing) the size-based arm. A candidate qualifies when it matches a **known leak
prefix** *and* clears every existing gate. Prefixes are an explicit allowlist —
`tmp.`, `ft.`, `ft6297.`, `ft-mut.`, `ft-mut2.`, `skill-security-scan-` — not a wildcard.

6.2 **Every existing safety gate applies unchanged**, and this is the load-bearing
constraint of the whole phase:
- own-uid only (`-user "$uid"`)
- the protected-path `case` list (`claude-*`, `soleur-session-state*`, `node-compile-cache`,
  the `.X11-unix` family, `systemd-*`, `snap*`) — this is what spares
  `/tmp/claude-1001/...`, the operator's live session scratchpad
- **recursive** age check, not top-level mtime (a directory's own mtime does not change when
  a nested file is written)
- `_INUSE_TOP` liveness via the single `/proc` pass over both **cwd and open fds**, plus
  `fuser` for file candidates
- never follow a symlink out of the scratch root
- `find "$e" -delete`, never `rm -rf` — a candidate can be an abandoned repo clone, and the
  constitution's `guardrails:block-recursive-delete` rule forbids `rm -rf` on such a target.
  The cron context means the PreToolUse hook does not fire, so honouring the idiom is what
  keeps this inside the guardrail.

6.3 Use a **shorter age floor** for the count arm — `TMPFS_GUARD_PREFIX_AGE_MIN`, default
120 minutes. Rationale: these are per-test-case artifacts whose useful life ends when the
suite exits, unlike the 24 h floor calibrated for large scratch trees that a long session
may still want. The floor is an env seam so it can be tuned without a code change.

6.4 Honour the existing `TMPFS_GUARD_DRY_RUN` seam so the arm is dry-run-able before it ever
deletes, and extend `scripts/tmpfs-guard.test.sh` (282 lines) with: prefix match reaps;
non-matching prefix spared; protected path spared **even when the prefix matches**; live
(open-fd) entry spared; fresh entry spared; dry-run deletes nothing.

6.5 Performance: the existing batched `du --files0-from` exists because per-candidate `du`
does not finish inside a 5-minute window on a full `/tmp`. The count arm must **not**
reintroduce a per-candidate tree walk — it is prefix + age + liveness gated, none of which
requires sizing. Skip `du` entirely on this arm.

### Phase 7 — Track and record

7.1 File the tracking issue (none exists for this defect — #6760 is a sibling class, not
this one). Cross-reference #6734, #6789, #6713, #6760 and ADR-129. Close it from the PR body
with `Closes #<N>`.
7.2 File a **separate** issue for the in-session discovery below (do not fold in — different
file, different root cause, and it gates every plan write in the repo):
`.claude/hooks/iac-plan-write-guard.sh` line 118's escape-hatch check is a **race**. Measured
this session: identical 50 KB input, 12 runs → **9 deny / 3 allow**. The documented opt-out is
a coin flip for any plan above roughly 30 KB, which is precisely the size of a thorough plan.
See Sharp Edges for the mechanism and the proposed fix.
7.3 Amend ADR-129 per the Architecture Decision section below.
7.4 Capture the session learning: *a guard that fires on the inline form of an idiom and not
its named-function form encourages the worse style, and its silence is indistinguishable
from correctness.*

## Files to Edit

| File | Change |
|---|---|
| `scripts/followthroughs/anthropic-admin-key-6297.test.sh` | Registry-file cleanup replacing the subshell-lost array (2.1) |
| `scripts/lint-trap-tempfile-ownership.py` | Resolve named-function trap indirection; one-hop transitive `$()` detection (5.1-5.2) |
| `scripts/lint-trap-tempfile-ownership.test.sh` | Blind-spot fixture asserting exit 1 (1.2) |
| `scripts/lint-trap-tempfile-ownership.highwater` | Ratchet down if the census falls (5.4) |
| `scripts/tmpfs-guard.sh` | Count-based prefix reap arm reusing all existing gates (6.1-6.5) |
| `scripts/tmpfs-guard.test.sh` | Six new cases incl. protected-path-wins-over-prefix (6.4) |
| `scripts/lib/test-contention.sh` | `soleur_default_tmpdir()` disk-backed resolver (3.1) |
| `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` | `EXIT INT TERM` trap; disk-backed TMPDIR (2.3, 3.2) |
| `plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh` | `EXIT INT TERM` trap; disk-backed TMPDIR (2.3, 3.2) |
| *(0-10 of the Phase 2.2 sweep list)* | Only those the audit classifies as defective |
| `knowledge-base/engineering/architecture/decisions/ADR-129-jq-argv-ceiling-and-shell-cleanup-ownership.md` | Amend Decision #2 (nesting-depth caveat) |

## Files to Create

| File | Purpose |
|---|---|
| `scripts/followthroughs/anthropic-admin-key-6297-cleanup.test.sh` | On-disk-absence regression at real nesting depth (1.1) |
| `scripts/raise-tmp-tmpfs-ceiling.sh` | Idempotent fstab + tmpfiles.d drop-in applier (4.1) |
| `scripts/raise-tmp-tmpfs-ceiling.test.sh` | Fixture-driven tests for the applier (4.2) |
| `knowledge-base/project/learnings/2026-07-27-guard-blind-to-named-function-trap-indirection.md` | Session learning (7.4) |

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `scripts/followthroughs/anthropic-admin-key-6297-cleanup.test.sh` exits 0, and
  its assertion is on-disk absence (`[[ ! -e "$path" ]]` after process exit), **not** trap
  presence. Verify by inspection: `grep -c 'trap' <test>` in an assertion position is 0.
- **AC2** — The full `anthropic-admin-key-6297.test.sh` suite still passes, and a run leaves
  **zero** new `/tmp/ft.*` or `/tmp/ft6297.*` entries. Measure with a before/after count:
  `n0=$(ls -d /tmp/ft.* /tmp/ft6297.* 2>/dev/null | wc -l)`, run the suite, re-count, assert
  equality.
- **AC3** — `python3 scripts/lint-trap-tempfile-ownership.py scripts/followthroughs/anthropic-admin-key-6297.test.sh`
  exits 0 **for the right reason** — i.e. the pre-fix version of the file now exits 1. Both
  arms asserted; a one-sided check cannot distinguish a fix from a still-blind linter.
- **AC4** — The new linter fixture exits 1 before the Phase 5 change and 0 after removal of
  the defect, proving the rule is not vacuous (the ADR-129 fixture-adequacy convention).
- **AC5** — `python3 scripts/lint-trap-tempfile-ownership.py` (full scan) exits 0 on the
  branch; `--check-highwater` exits 0.
- **AC6** — `bash scripts/lint-trap-tempfile-ownership.test.sh` and
  `bash scripts/tmpfs-guard.test.sh` both exit 0.
- **AC7** — `TMPFS_GUARD_DRY_RUN=1` with a synthetic `TMPFS_GUARD_TMP` fixture containing a
  protected `claude-<uid>` dir whose name *also* matches a leak prefix reports **zero**
  would-reap lines for it. Protected-path precedence over prefix match is asserted directly.
- **AC8** — A fixture entry with an open file descriptor held by a live process is **not**
  reaped by the count arm (liveness gate still binds on the new path).
- **AC9** — `bash scripts/raise-tmp-tmpfs-ceiling.sh --dry-run` against the fixture fstab
  writes zero bytes (assert via checksum before/after) and exits 0.
- **AC10** — Running the applier twice against the fixture yields an identical file after
  run 2 (idempotency), and a backup exists after run 1.
- **AC11** — Applying against a malformed fixture fstab restores the backup and exits
  non-zero.
- **AC12** — Every Phase 2.2 sweep file is classified *defective* or *sound* in the PR body,
  with 10/10 accounted for. No file silently omitted.
- **AC13** — `soleur_default_tmpdir()` resolves outside every mount `workspaces-cutover.sh`
  certifies: `bash -c 'source scripts/lib/test-contention.sh; soleur_default_tmpdir'` returns
  a path under `$HOME`, and the L3 gate at `workspaces-cutover.sh:1989` is unaffected.
- **AC14** — ADR-129 carries the amendment; `grep -c 'nesting' <ADR-129>` ≥ 1.
- **AC15** — PR body contains `Closes #<N>` for the new tracking issue, references #6760 as
  related-but-distinct, and references the Phase 7.2 hook-race issue.

### Post-merge (privileged, one keystroke)

- **AC16** — `sudo bash scripts/raise-tmp-tmpfs-ceiling.sh` then `sudo mount -o remount /tmp`;
  `findmnt /tmp` reports `size=8388608k`.
  *Automation: not feasible because the fstab write requires root and `sudo -n` on this host
  returns "interactive authentication is required" — the credential is the only
  non-automatable element. The script performs every decision, edit, backup, validation and
  rollback; a single command applies it. No checklist is emitted.*
- **AC17** — 48 h after merge, `ls /tmp/ft.* /tmp/ft6297.* 2>/dev/null | wc -l` returns 0 and
  `journalctl -t tmpfs-guard --since '48 hours ago' | grep -c reaping` is > 0 — proving the
  count arm fired and the leak class is gone. Automated via the follow-through convention
  (see Observability §soak).

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-129** (accepted, 2026-07-20) — do not open a new ADR. This work extends an
existing Decision rather than making an independent one.

Decision #2 currently reads: *"Cleanup arrays are appended in the PARENT scope, never inside
`$( )`. Allocate in the helper, register at the call site."* That is correct for **one** level
of command substitution and **silently insufficient** beyond it: when the allocating helper
is itself `$()`-invoked, the "parent scope" is still a subshell and the registration is lost
again — by a fix that reads as correct.

Amendment to add:

> **2a. Registration must escape every enclosing subshell, not merely the innermost one.**
> When the allocating helper is itself invoked via command substitution (nesting depth ≥ 2),
> parent-scope array registration is insufficient — the "parent" is another subshell. Use an
> append-only **registry file** allocated before the trap is installed; the cleanup function
> reads it. A file write escapes every subshell by construction, which is the property a
> shell array cannot have at any depth. Reference implementation:
> `scripts/followthroughs/anthropic-admin-key-6297.test.sh`.
>
> **4a. Ownership detection must resolve named-function traps.** A `trap cleanup_fn EXIT`
> names a function, so the cleanup array appears nowhere on the trap line. Enforcement that
> reads only the trap line is blind to the *better-factored* form of the idiom and its
> silence is indistinguishable from correctness — the #6734 gate passed the exact file whose
> defect motivated it.

The ordinal is not at issue (this is an amendment). Should a new ADR be preferred at review,
the next free ordinal is **ADR-149** — provisional per the plan-skill Sharp Edge; `/ship`
re-verifies against `origin/main` before merge, and any renumber must sweep this plan,
`tasks.md`, and AC14 in the same edit.

### C4 views

**No C4 impact.** Per the C4 completeness mandate this is not a keyword grep — all three
model files were read (`model.c4` 558 lines, `views.c4` 62, `spec.c4` 54) and the enumeration
checked:

- **(a) External human actors** — `founder`, `emailSender`, `betaContact`, `contributor`. This
  work introduces no new correspondent, reviewer or recipient. The `founder` actor exists, but
  their *local workstation filesystem* is not and never has been a modeled element.
- **(b) External systems / vendors** — `anthropic`, `github`, `cloudflare`, `doppler`,
  `discord`, `stripe`, `plausible`, `resend`, `pushService`, `ghcr`, `zotRegistry`,
  `betterstack`, `sentry`, `sigstore`, `letsencrypt`, `publicResolvers`. No inbound webhook,
  outbound API or third-party store is added — the change touches no network boundary at all.
- **(c) Containers / data stores** — the L2 view models `webapp`, `engine`, `plugin`, `infra`
  and their children (`supabase`, `hetzner`, `gitDataStore`, `sessionStore`,
  `workspacesVolume`, `inngest*`, `tunnel`, …). The operator's `/tmp` tmpfs, their user
  crontab, and repo-local shell linters are **developer tooling on a personal machine**, not
  product containers. No new store; no existing store changes shape.
- **(d) Access relationships** — no actor↔surface edge changes. Nothing moves between
  single-owner and shared; no new trust boundary is crossed.

The test: would a competent engineer reading only the ADRs + C4 be *misled* about the system
after this ships? No — the system diagram is unchanged; only the workstation's temp-file
hygiene and two repo-local guards change. The decision *is* recorded, in the ADR-129
amendment, which is the correct home for it.

## Observability

```yaml
liveness_signal:
  what: "tmpfs-guard cron run — reap counts and /tmp usage %"
  cadence: "*/5 * * * * (existing user crontab entry, unchanged)"
  alert_target: "notify-send desktop notification + syslog tag tmpfs-guard"
  configured_in: "crontab -l; scripts/tmpfs-guard.sh main()"

error_reporting:
  destination: "logger -t tmpfs-guard (journald) + notify-send for operator-visible events"
  fail_loud: true   # the >=70% usage warning already fires when BOTH reapers find nothing,
                    # which is precisely the 'something else is filling /tmp' case. The count
                    # arm adds its own per-reap log line so a silent reap is impossible.

failure_modes:
  - mode: "count arm reaps a live session's scratch dir"
    detection: "journalctl -t tmpfs-guard names every reaped path and size at reap time"
    alert_route: "notify-send (immediate, desktop) + journal for post-hoc attribution"
  - mode: "count arm reaps nothing while /tmp keeps filling (new leak prefix not on allowlist)"
    detection: "existing >=70% usage warning fires when both reapers return 0"
    alert_route: "notify-send critical + logger"
  - mode: "linter regresses to blind (rule (a) stops firing on the named-function form)"
    detection: "the Phase 1.2 fixture asserts exit 1; CI fails if the rule goes quiet"
    alert_route: "CI red on the test-scripts job"
  - mode: "class-b population grows silently"
    detection: "--check-highwater compares live census against the ratchet file"
    alert_route: "CI red"
  - mode: "fstab applier corrupts /etc/fstab"
    detection: "findmnt --verify --tab-file runs BEFORE the script exits; backup restored on failure"
    alert_route: "non-zero exit + restored backup printed to stderr"

logs:
  where: "journald (syslog tag tmpfs-guard); CI job logs for the linter"
  retention: "journald default on the workstation; GitHub Actions default for CI"

discoverability_test:
  command: "journalctl -t tmpfs-guard --since '1 hour ago' --no-pager | tail -20"
  expected_output: "one line per cron run; 'reaping <path> (<N> MB)' for each reclaimed entry"
```

Every surface above is the operator's own machine or CI, both directly inspectable, so no
remote-shell fallback appears in any command (`hr-no-ssh-fallback-in-runbooks` satisfied by
construction).

**Soak follow-through enrollment (2.9.1).** AC17 is a time-gated close criterion (48 h
post-merge), so it must be automated rather than remembered:

- Script: `scripts/followthroughs/tmp-tmpfs-leak-<issue>.sh` — exit 0 when
  `ls /tmp/ft.* /tmp/ft6297.* | wc -l` is 0 **and** the journal shows ≥1 reap since merge;
  exit 1 while still soaking.
- Tracker directive:
  `<!-- soleur:followthrough script=scripts/followthroughs/tmp-tmpfs-leak-<issue>.sh earliest=<merge+2d> -->`
  plus the `follow-through` label.
- No new `secrets=` required — the probe is entirely local.

## Infrastructure (IaC)

**Phase 2.8 assessed; Terraform routing does not apply.** The `hr-all-infrastructure-provisioning-servers`
rule governs *provisioned infrastructure* — Hetzner hosts, Cloudflare records, secret-manager
entries, service units on fleet hosts — all of which live in `apps/*/infra/*.tf`. The
`/etc/fstab` edit here targets **the operator's personal laptop**, which is not represented in
any Terraform root, is not a fleet host, and has no cloud-init path. There is nothing to
import and no provider that manages it.

The correct shape for a root-owned change on an unmanaged personal machine is exactly what
Phase 4 ships: an idempotent, re-runnable, backed-up, validated, rollback-capable,
dry-run-able script invoked in one keystroke — which is the
`hr-multi-step-post-merge-bootstrap-script` pattern, not a prose checklist. This plan
prescribes no remote-shell step, no vendor-dashboard click-through, no secret-manager write,
and no hand-run service command anywhere in its phases.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Pure developer-tooling and workstation-hygiene change. Three engineering
concerns dominate and are addressed in-plan: (1) the destructive-delete blast radius of the
new reaper arm, mitigated by reusing every existing gate additively and by dry-run coverage
in AC7/AC8; (2) the risk of a guard that fires on correct code — ADR-129 documents this as
the failure mode that gets gates switched off, so Phase 5 bounds transitive detection to a
single hop and preserves the escape hatch; (3) scope discipline — the largest engineering
risk was rebuilding two existing systems, which premise validation caught before any code
was written.

### Product/UX Gate

Not applicable. The mechanical UI-surface override was evaluated against `## Files to Edit`
and `## Files to Create`: zero paths match `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx`, or any UI-surface glob. Every file is a shell script, a Python linter, a
test, or a knowledge-base document. Product tier: **NONE**.

**Domains assessed and found not relevant:** Marketing, Sales, Finance, Legal, Operations,
Support, Product — no customer-facing surface, no pricing/contract/vendor change, no
regulated data, no recurring expense.

## GDPR / Compliance Gate

**Skipped — no regulated-data surface.** Assessed against the `hr-gdpr-gate-on-regulated-data-surfaces`
canonical regex (schemas, migrations, auth flows, API routes, `.sql`): zero matches. The four
expansion triggers were also checked: (a) no LLM/external-API processing of operator data is
added; (b) the `single-user incident` threshold here is an *availability* judgement about
destructive deletes, not a personal-data one; (c) no new cron reads from
`knowledge-base/project/learnings/` or `specs/`; (d) no new artifact-distribution surface. The
reaper deletes uid-scoped temp files on a personal machine and transmits nothing.

## Encryption Posture

**Skipped — Phase 2.11 detection does not fire.** No `.tf`, no `supabase/migrations/*.sql`,
no `cloud-init*.yml`, no `docker-compose*.yml` in the file lists; no persistent store and no
new cross-component connection is introduced. `$HOME/.cache/soleur/tmp` is a local scratch
directory created `0700`, not a data store.

## Open Code-Review Overlap

One open issue overlaps this plan's surface:

- **#6760** — *skill-security-scan leaks one runtime dir per invocation (7,603 observed)*
  (`priority/p2-medium`, `type/chore`, `domain/engineering`). Touches
  `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh`, which is **not** in this
  plan's Files to Edit.

  **Disposition: acknowledge.** The issue body is explicit that this is *not* a missing-trap
  defect — `run-scan.sh` registers a correct trap that deliberately spares `$meta_dir`
  because the scan prints that path to stdout for a caller to read *after* the process exits
  (`plugins/soleur/test/skill-security-scan.test.ts` matches
  `/scan-meta\.json written to: (\S+)/` and then reads it). Adding it to the trap would break
  every consumer. The fix is a *retention policy* — a design decision with at least three
  viable shapes — and folding it in would mean making that decision inside a PR scoped to a
  different root cause.

  It is nonetheless the same *family*, and Phase 6's count-based reaper materially reduces
  its harm without touching its contract: `skill-security-scan-*` directories become reapable
  by age once the prefix is added to the allowlist (done — see Phase 6.1). **Action:** post a
  comment on #6760 noting the harm reduction, so the retention-policy decision is made on its
  merits rather than under disk pressure. The issue stays open.

No other open `code-review`-labelled issue touches any path in Files to Edit or Files to
Create.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The count-based reaper deletes live work.** The single largest risk in this plan; it is why the threshold is `single-user incident`. | Every existing gate applies unchanged and additively: own-uid, protected-path `case` (spares `/tmp/claude-<uid>`), **recursive** age, `/proc` cwd **and** open-fd liveness, no-symlink-follow, `find -delete` not `rm -rf`. AC7 asserts protected-path precedence *over* a matching prefix; AC8 asserts an open-fd entry survives. Dry-run seam exists and is exercised first. |
| Prefix allowlist grows stale as new leak classes appear. | The existing ≥70% usage warning fires precisely when both reapers find nothing — the "new prefix not covered" signal. Documented as a named failure mode in Observability. |
| Linter change fires on correct code and gets switched off — ADR-129's stated worst outcome. | Transitive detection bounded to one hop; the escape hatch with its non-empty-reason requirement is preserved; full-scan must exit 0 on the branch before merge (AC5). |
| Registry-file approach diverges from ADR-129 Decision #2. | Deliberate and recorded as amendment 2a with the falsifying nesting case. Not a silent divergence. |
| The fstab applier corrupts `/etc/fstab` and the machine will not boot. | Timestamped backup before any write; `findmnt --verify --tab-file` validation **before** exit; automatic restore on validation failure; `--dry-run` default-verifiable; fixture-driven tests never touch the real file (AC9-AC11). |
| Raising tmpfs to 8G defeats the original purpose of the downward pin (a runaway cannot eat all RAM). | 8G is 27% of 30 GiB — still well under systemd's 50% default, so the pin's intent is preserved rather than discarded. The ceiling is also the *least* important fix here: Phases 2, 3 and 6 remove the pressure, and the ceiling only buys headroom. |
| Disk-backed TMPDIR lands inside a path `workspaces-cutover.sh` certifies, tripping its L3 abort (#6733). | AC13 asserts the resolved path is under `$HOME`, outside every certified mount. Asserted, not assumed. |
| The 2.3 GiB producer is never identified and recurs. | Accepted and recorded as UNKNOWN. Class-scoped fixes cover both candidates; the Phase 6 reaper logs the name and size of anything it reaps, so a recurrence is labelled at reap time rather than reconstructed after the fact. |
| Phase 2.2 sweep "fixes" already-correct files. | Each of the 10 files is classified *defective* or *sound* with the verdict recorded in the PR body (AC12); sound files are left untouched. |

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **Build a new CI guard as the brief requested** | One exists (#6734/ADR-129) with an escape hatch, added-line scoping, and a high-water ratchet. A second guard would duplicate coverage, double the false-positive surface, and leave the *actual* blind spot open. Fixing the existing rule is strictly better. |
| **Build a new janitor as the brief requested** | One exists (#6789) and is deployed on a `*/5` cron with ownership, recursive-age, and `/proc` cwd+fd liveness gates that took real incidents to calibrate. Rebuilding would discard that safety work and risk re-learning it destructively. |
| **Parent-scope array registration (literal ADR-129 #2)** | Provably insufficient at this file's 2-level nesting — `make_sandbox` is itself `$()`-invoked, so the "parent" is another subshell. Would look correct and leak identically. |
| **Refactor `make_sandbox` to a nameref/global instead of `$()`** | Touches ~20 call sites, churns a suite whose contamination arms are load-bearing, and fixes only this one file. The registry file is smaller, local, and correct at any depth. |
| **Lower `systemd-tmpfiles` `/tmp` age alone** | Even at 2d it cannot outpace a leak that added ~3,766 entries in a week, and it does not touch the root cause. Kept as one line inside the Phase 4 script, never as the fix. |
| **Raise tmpfs to 15G (systemd's 50% default)** | Restores the exact failure the 4G pin was added to prevent — a runaway consuming half of RAM. 8G keeps the pin's intent. |
| **Drop the size floor in `tmpfs-guard.sh` instead of adding a count arm** | The floor is a *safety* gate for the large-tree class it was calibrated against. Removing it widens the destructive blast radius across all entries. Adding a narrower, prefix-allowlisted, shorter-age arm is additive rather than a relaxation (`2026-05-05-defense-relaxation-must-name-new-ceiling`). |
| **`rm -rf` in the reaper (simpler than `find -delete`)** | Forbidden by the constitution's `guardrails:block-recursive-delete` for `.git`-bearing targets, and a size-survivor can be an abandoned repo clone. The cron context means the PreToolUse hook would not fire, so the idiom must be honoured in code. |

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | Allocate via `$(mktmpd)` nested inside `$(make_sandbox)`, exit the script | Path absent from disk |
| T2 | Run the full 6297 suite; count `ft.*`/`ft6297.*` before and after | Counts equal |
| T3 | Lint the pre-fix file | exit 1 (blind spot closed) |
| T4 | Lint the post-fix file | exit 0 |
| T5 | Lint a file with a *correct* named-function trap and parent-scope registration | exit 0 (no false positive) |
| T6 | Lint a file whose defect carries `# lint-trap-ownership: ok <reason>` | exit 0 (escape hatch intact) |
| T7 | Lint a file with a bare `# lint-trap-ownership: ok` | exit 1 (reason required) |
| T8 | Reaper vs. entry matching a leak prefix, older than the floor, unheld | reaped |
| T9 | Reaper vs. `claude-<uid>` whose name also matches a prefix | **spared** (protected wins) |
| T10 | Reaper vs. prefix-matching entry with a live open fd | spared |
| T11 | Reaper vs. prefix-matching entry younger than the floor | spared |
| T12 | Reaper vs. entry not on the prefix allowlist | spared |
| T13 | Reaper with `TMPFS_GUARD_DRY_RUN=1` | reports, deletes nothing |
| T14 | Reaper vs. symlink pointing outside the scratch root | not followed |
| T15 | fstab applier on an already-applied fixture | no-op, exit 0 |
| T16 | fstab applier on an unapplied fixture | rewritten, backup exists |
| T17 | fstab applier on a malformed fixture | backup restored, exit non-zero |
| T18 | fstab applier `--dry-run` | zero bytes written (checksum unchanged) |
| T19 | fstab applier run twice | identical result (idempotent) |
| T20 | `soleur_default_tmpdir()` with `TMPDIR` already set | caller's value preserved |
| T21 | `soleur_default_tmpdir()` unset | resolves under `$HOME/.cache`, mode 0700 |

## Plan Review Revisions (v2 — supersedes the phases it names)

Six of seven review agents reported (dhh, kieran, architecture-strategist, cto, cpo, plus the
eng-panel baseline; code-simplicity and spec-flow-analyzer were still running at write time and
their findings must be folded in before `/work` begins). Findings converged so strongly that the
plan's **strategy**, not just its details, is revised. Every claim below was re-verified locally.

### R1 — The root-cause diagnosis was incomplete (kieran P0-1). **Corrected in Root cause 1 above.**

The binding blind spot is the line-start anchor on `ARRAY_APPEND`, not the named-function trap.
Fixing `trap_owned_arrays()` alone yields **0 findings across 689 files**. Both fixes together
yield **exactly 2, zero false positives**. Sweep denominator is **12 files, not 10**; AC12's
"10/10" is wrong.

### R2 — The registry file is unnecessary (dhh P0-1). **Phase 2.1 is replaced.**

Verified locally: `mktemp -t` resolves against `$TMPDIR`, including at 2-level command-substitution
nesting, and one `rm -rf` of the root reclaims everything. So the fix is a **single scratch root**,
which is already the house style in 15 sibling files:

```bash
TMP_ROOT=$(mktemp -d -t ft6297-run.XXXXXXXX)
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM
export TMPDIR="$TMP_ROOT"
```

Nothing has to escape a subshell, so nesting depth becomes irrelevant. **ADR-129 amendment 2a is
withdrawn** — Decision #2 was never wrong; this file simply went off-menu, and inventing a second
idiom to bless the deviation would be doctrine that outlives the plan. Verify the `env -i` in
`run_probe` does not strip `TMPDIR` from the child before declaring the 1,883/1,883 pairing closed.

### R3 — Phase 6 (count-based reaper) is **cut from this PR** and deferred to its own issue.

Unanimous across dhh (P0-2), cpo (C1), cto (E3), architecture (P0-1/P0-2). Both the simplification
and correctness panels fired on the same scope, which per the consolidation rule means *delete, not
fix*. The specific defects:

- **`tmp.` is the GNU `mktemp` default template, not a leak signature.** Verified: **576 bare
  `mktemp -d` sites in this repo alone**. The protected-path `case` matches by *name* and is
  **disjoint** from `tmp.*` by construction — there is nothing to add, because the defining
  property of the default template is that it carries no name. This makes AC7 and T9 **vacuous by
  construction** (kieran P1-2, architecture P1-1): no string satisfies both predicates.
- **The reaper targets a class Phase 2 eliminates at source**, in the same PR.
- **Phases 6.2 and 6.5 are mutually exclusive** (architecture P0-1). `du` is the loop's *iteration
  source*, the cost bound for the recursive-age gate, and the sole source of the `<N> MB` probe
  value. Dropping it forces a second candidate reader, and any key-normalization difference against
  `_INUSE_TOP` makes the liveness gate **fail open, toward deletion, silently**.
- **It silences its own safety net.** The ≥70% warning is suppressed whenever `reaped != 0`, so the
  documented detector for "a new leak prefix is not on the allowlist" is disarmed by the arm that
  depends on it. Phase 4 would push the trigger a further ~13× out.
- **ADR-129 Decision #4's upgrade trigger has already fired** (architecture P0-2). The `tmp.*` pile
  *is* the accepted class-b population, now on a long-lived host — the ADR's stated criterion (a).
  The consistent response is to re-evaluate the accept via a ratcheted sweep of the bare-`mktemp`
  sites, not to hide it behind a deleter. Phase 6 would make the debt permanently invisible.
- **AP-009 "never delete user data"** was never cited and must be, given the population is largely
  operator-originated.

### R4 — Phase 4 (fstab applier) is **cut**; its tmpfiles arm is **cut as unsafe**.

dhh P1-1, cpo C6, cto E7 concur the fstab raise is the plan's own least-important fix carrying its
only unbootable-machine risk. `/tmp` is at 26%; post-Phase-2 accrual goes to zero.

The `/etc/tmpfiles.d` 2d drop-in is **also cut, and this is not a scope call but a safety one**:
`systemd-tmpfiles` age-cleans by timestamp with **no protected-path concept and no liveness gate**.
Measured: **11 files under `/tmp/claude-1001` are older than 2 days** — it would unlink the
operator's live session scratchpad. A change introduced as a safety improvement was itself a
destructive-delete regression.

### R5 — Phase 5: keep the widened 5.1, **cut 5.2**.

`mktmpd` is *directly* `$()`-invoked, so the existing call-site regex already matches; 5.2 buys zero
detection on the motivating defect while adding the call-graph false-positive surface ADR-129 argues
against at length (kieran P0-2, dhh P1-3, cto E6). **Rule (a) has no accept mechanism** — unlike
rule (c) it is not line-scoped and has no highwater — so widening it repo-wide in one step must ship
with added-line scoping or its own ratchet in the same PR (architecture P1-4b).

### R6 — Phase 3: move the resolver out of `test-contention.sh`.

That lib declares "This module only OBSERVES. It creates no files… deletes nothing"; a `mkdir` +
`export TMPDIR` breaks both clauses and the `tc_` namespace (kieran P1-4). Worse, `TC_TMPDIR` is
bound **at source time**, so exporting `TMPDIR` can silently repoint ADR-133's tmpfs instrumentation
at the wrong filesystem (architecture P1-5). Use a separate `scripts/lib/scratch-root.sh`, call-time
only. Also: Phase 3 relocates the leak to `$HOME/.cache/soleur/tmp`, which has **no janitor and no
age policy** — assign that chore or do not claim it is handled.

### R7 — The strategic finding (cto E1). **Highest leverage in the whole review.**

An outcome-based detector already exists and is dormant. `run_suite()` in `scripts/test-all.sh`
measures a per-suite `/tmp` entry delta as `tmp_delta=<N>`, gated on `TEST_TIMING_LOG`, which is
unset on a default run. Verified: the leaking suite **is** registered through it (line 257),
**95 suites** funnel through it, and `tmp_delta` has **zero consumers** — it has reported to
`/dev/null` since #6789.

This is the third guard, and the only one without a blind spot: it measures the filesystem rather
than the source, so nesting depth, `$()` vs `( )` vs pipeline, named-function vs inline trap, and
shell vs the **65 non-shell temp allocators** are all invisible to it. Calibration surface: zero.

**Added to scope, replacing Phase 6's role:** ungate `tmp_delta`, fail a suite on non-zero delta,
and give `run_suite()` a per-suite private scratch root reaped unconditionally. One file, ~25 lines,
covering 95 suites — versus a prefix allowlist, a size floor, and an age floor that were each
already miscalibrated once.

### R8 — Verification defects to fix before `/work`

- **AC2/AC17 go vacuous the moment Phase 3 lands** (kieran P1-1): they count `/tmp/ft.*`, but
  `TMPDIR` moves those artifacts out of `/tmp` entirely, so both pass whether or not the leak is
  fixed. Anchor on the resolved scratch root.
- **AC17 can never pass** regardless: it greps the journal for `reaping`, but that line goes to
  **stdout** and is captured into `reaped="$(…)"`. Measured: **0** occurrences of `reaping` vs
  **346** of `Reaped`. The `discoverability_test` expected output is false today for the same
  reason, and `[[ "${reaped:-0}" -eq 0 ]]` does arithmetic on a multi-line capture.
- **`skill-security-scan-` is a dead allowlist entry**: 0 matches. Real prefixes are
  `skill-scan-input-` (45) and `skill-scan-results-` (4) — so the claimed harm reduction for #6760
  was false and is withdrawn.
- AC1 is not a runnable command; AC3 is unrunnable post-Phase-2 and vacuous besides; AC4's wording
  is inverted; AC13 inherits the caller's `TMPDIR` (pin `env -u TMPDIR`); AC14 greps a common
  English word instead of a content anchor.
- `find_functions()` desyncs on braces in heredocs and misses `cleanup` in the two largest scripts,
  so 5.1 **fails toward silence** there — state it rather than imply coverage.

### R9 — Revised scope

**Ships here:** single-root fix (R2) · `EXIT INT TERM` completion · widened rule (a) + non-vacuous
fixture + 12-file sweep with per-file verdicts (R1/R5) · `run_suite` private roots + `tmp_delta`
gate (R7) · the 2-line stdout→`logger` fix in `tmpfs-guard.sh` (R8) · ADR.

**Deferred to their own issues:** the count-based reaper (R3) · the fstab raise (R4) · the
ADR-129 D#4 accept re-evaluation across the bare-`mktemp` population (R3) · the
`iac-plan-write-guard.sh` race, whose sibling *pattern* checks fail **open** (higher priority than
this plan).

**ADR:** withdraw 2a; re-file the named-function finding under Decision #2 / "Enforcement, stated
honestly" rather than #4 (architecture P2-1); open a new ADR for the real decision — *per-run
private scratch roots reaped unconditionally, over shared `/tmp` reaping gated on conjunctive
evidence*. Ordinal provisional; `/ship` re-verifies.

**Phase order becomes:** 1 (RED, incl. reaper tests if it ever returns) → 5 (widen) → derive the
defective set from tool output → 2 (fix) → 3 → ADR → 7.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above.
- **A default name template is not a leak signature.** The single root error behind every P0 in
  this review was treating `tmp.` — GNU `mktemp`'s default — as if it identified a producer. Name-
  based protection cannot exist for a class whose defining property is that it carries no name.
- **An outcome detector beats a source-shape detector, and this repo already had one.** Three
  generations of guard inferred leakage from source shape (#6734) or artifact properties (#6789);
  each generation's blind spot was found by the next incident. `tmp_delta` measures the outcome and
  has been switched off the whole time.
- **`du -sm` rounds every entry up to at least 1 MB.** Across 11,052 entries that overstates
  occupancy by roughly an order of magnitude and was the source of the brief's "2.7G" figure.
  Use `du -sk --total` for any count-heavy directory.
- **The `tmp.*` name class cannot be produced by a prefixed `mktemp -t`.** Bare `mktemp -d`
  yields `tmp.XXXXXXXX`; `mktemp -d -t foo.XXXXXXXX` yields `foo.XXXXXXXX`. This is the only
  reliable way to narrow producer candidates from a name alone, and it is what excludes the
  Inngest cron handlers (which prefix with `soleur-${cronName}-`).
- **`worktree-manager.sh`'s `cleanup_stale_sandbox_tmp` cannot match the `tmp.*` class.** Its
  name filter is `-regex "$tmp_root/[A-Za-z0-9_-]{15,}"` — `tmp.XXXXXXXX` is 12 characters and
  `.` is not in the class. The two reapers were designed to cooperate; verify the assumed
  division of labour rather than inheriting it.
- **A prohibition sentence containing the forbidden literal trips the gate that enforces it.**
  Writing this plan was denied three times by `iac-plan-write-guard.sh`, and never for a real
  IaC violation: first because the Infrastructure section said "no `<remote-shell>`, no
  `<secret-write>` appears anywhere" — the negative claim contains the very tokens the hook
  scans for — and finally because a *reproduction snippet documenting the hook's own bug*
  embedded a matching phrase as test data. Write prohibitions descriptively, and keep matched
  literals out of illustrative code. Same class as the AC self-reference grep trap in the
  plan-skill Sharp Edges.
- **`iac-plan-write-guard.sh`'s documented escape hatch is size-dependent and
  non-deterministic — file it, do not work around it silently.** The ack check at line 118 is
  `echo "$content" | grep -qF '<marker>'` under `set -euo pipefail`. `grep -q` exits at the
  first match and closes the pipe; whether `echo` has finished writing decides the pipeline's
  exit status, so the `if` is a race rather than a test. Measured this session on identical
  50 KB input, **12 runs → 9 deny / 3 allow**; below ~25 KB it passed every time. The opt-out
  is therefore a coin flip for exactly the large, thorough plans most likely to need it.
  Proposed fix: replace the pipeline with a pure-bash `case "$content" in *"$marker"*)` (no
  subprocess, no pipe, no race), and audit the sibling `echo … | grep -q` pattern checks in
  the same file for the same defect — a *pattern* check that loses this race fails **open**,
  which is the worse direction. Tracked by Phase 7.2. **This plan does not depend on the
  ack** — it avoids the matched phrasing outright, which is why it writes deterministically.
- **The plan-time ADR ordinal is provisional.** This plan amends ADR-129 (no ordinal needed),
  but if review prefers a new ADR, ADR-149 is the next free slot as of 2026-07-27 and `/ship`
  re-verifies against `origin/main`. Any renumber must sweep this plan, `tasks.md`, and AC14
  in the same edit.
