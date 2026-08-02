---
title: "feat(hooks): memory backstop via systemd StartTransientUnit + a shared soleur-agents.slice"
issue: 7166
branch: feat-one-shot-7166-memory-backstop-systemd-slice
date: 2026-08-02
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: feature
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# feat(hooks): memory backstop via systemd StartTransientUnit + a shared soleur-agents.slice

> `lane:` note — no `knowledge-base/project/specs/feat-one-shot-7166-memory-backstop-systemd-slice/spec.md`
> exists, so `lane:` could not be carried forward. Defaulted to `cross-domain` (TR2 fail-closed).
>
> **IaC ack** — Phase 2.8 reviewed. Every `systemctl` in this document is a *read-only verification
> or discoverability* command, never a provisioning step. This plan provisions nothing: the systemd
> units are **transient**, created at runtime by the hook, and self-clean. See
> [§ Infrastructure (IaC)](#infrastructure-iac). There are **zero operator steps**, pre- or post-merge.

## Overview

On 2026-08-01 a one-line regex search against a single 21 kB markdown file reached **9.5 GB RSS in
171 s at 99 % CPU and was still climbing**, driving a 31 GB box to 691 MB free with swap at 88.5 %.
The operator's terminal crashed, killing **six concurrent agent sessions** and their in-flight work.
There is no guard in place today.

A prior attempt (PR #7151, closed unmerged) shipped `memory-cap.sh`, which wrote a **raw cgroup v2
directory** and moved the live `claude` process into it with `memory.max=12 GB`. It was wrong in five
independent ways and — decisively — **never executed once**, because it was committed `100644` while
`settings.json` invokes the hook path directly. Physical residue of that attempt was still on the box
at plan time: an orphaned, systemd-unknown cgroup directory
`…/app.slice/soleur-agent-139954`, **under the wrong parent** — proof the raw-cgroup path had already
silently landed in the wrong place at least once. It was removed during plan-time probing.

This plan replaces that with the **sanctioned systemd API**: adopt the live process tree into a
transient scope via `StartTransientUnit`, under a shared `soleur-agents.slice` that carries the
fleet-wide bound. systemd stays the single writer to the cgroup hierarchy; the cap is visible to
`systemctl --user status`; the scope self-cleans when its last process exits.

Every mechanism below was **measured on the operator's box at plan time** (systemd 259, cgroup v2
unified, no sudo) and is reproduced in
[§ Verified Live-Box Grounding](#verified-live-box-grounding) so `/work` re-runs it as a precondition
rather than re-deriving it.

**What this does NOT do, stated up front:** under a cap the 2026-08-01 blowup dies by **SIGSEGV after
~45 s at 2.7 GB** (measured at a 3 GB cap) — ugrep does not handle allocation failure gracefully. A
cap **bounds damage; it does not prevent ~45 s of 100 % CPU on one core.** What it does prevent is the
memory-and-swap exhaustion that froze the desktop and killed six sessions. That sentence belongs in
the PR body verbatim.

---

## Premise Validation (Phase 0.6)

| Cited reference | Probe | Result |
|---|---|---|
| Issue **#7166** | `gh issue view 7166` | **OPEN**, `type/feature`. Premise holds. |
| **#7151** ("the earlier attempt") | `gh pr view 7151` | **CLOSED** PR `WIP: feat-one-shot-ugrep-oom-guards`, unmerged. Premise holds. |
| `.claude/hooks/memory-cap.sh` | `git show origin/main:…` | **Does not exist on `origin/main`** — this is a *build*, not a *fix*. |
| "`followthrough-exec-bit.test.sh`'s glob does not reach `.claude/hooks/`" | read the file | **Confirmed** — its glob is literally `'scripts/followthroughs/*.sh'`. |
| "both sibling SessionStart hooks are 100755" | `git ls-files -s` | **Confirmed.** |
| Proposed mechanism vs. ADR corpus | grep `decisions/` for cgroup / memory / systemd | **No ADR governs agent-session resource control.** ADR-062 caps a *server-side Docker container* — precedent, not a conflict. No rejected-alternative collision. |
| Sibling findings from the same #7151 review | `gh issue list --search 7151` | **#7164** (guardrails `eval`/`jq @sh` RCE) and **#7165** (`grep`→`command grep` via `updatedInput`) are filed and **out of scope** — see [§ Non-Goals](#non-goals--out-of-scope). |

No stale premises.

---

## Research Reconciliation — Spec vs. Reality

| Claim (issue #7166 / feature description) | Measured reality | Plan response |
|---|---|---|
| AC3: "`claude` is still a **member of the terminal's scope**" | **Physically impossible** alongside a per-session cap — a process is in exactly one cgroup; adoption *moves* it (G2). | **AC3 re-stated to its intent** and satisfied via `BindsTo=`+`After=` — a *unit* dependency instead of *cgroup* co-membership (G3). See [D3](#d3--ac3-the-terminals-kill-switch). |
| AC1 as literally globbed (`.claude/hooks/*.sh`) | **Would go RED on 5 pre-existing files** (`incidents.test.sh`, `lib/freeze-lock.sh`, `lib/freeze-lock.test.sh`, `lib/incidents.sh`, `lib/log-rotation.sh` are all `100644`). | AC1's own narrower wording ships: every hook **named in `settings.json`**. Audited: **33 paths, 0 non-100755** → green on the current tree. |
| "`memory.high` … likely the right primitive for a shared parent" | Correct **at the slice**, but with `MemorySwapMax=0` it degenerates for anon-heavy runaways — reclaim can only drop the cgroup's own file pages and immediately refaults them. | Both levels get `MemoryHigh` **and** `MemoryMax`, and `MemoryHigh` is set **above** the heaviest honest workload. See [D2](#d2--memoryhigh-vs-memorymax). |
| "Consider `oom_score_adj`" | **Unnecessary and partly impossible** — lowering a PID's own score needs `CAP_SYS_RESOURCE` (G10). | Solved by `OOMPolicy=continue` + `memory.oom.group=0`. **Transient scopes default to `OOMPolicy=stop`** (G8), which would have systemd kill the whole scope — including `claude` — on any OOM. See [D4](#d4--oom-victim-selection). |
| "`set-property` … is runtime-only; does NOT survive a restart" | **Backwards.** Without `--runtime` it writes a **persistent** drop-in to `~/.config/systemd/user.control/` (G6). | Use D-Bus `SetUnitProperties(…, runtime=true, …)` — measured to write **only** under `/run/user/<uid>/`. See [D5](#d5--fleet-bound-persistence). |
| "the scope self-cleans (closing the leak)" | True for **scopes**; **slices linger** (G11). | Stated honestly; the plan does not claim "everything self-cleans". A slice holds no processes, so it is harmless. |
| Implicit: the cap bounds a session's **total** RSS | **cgroup v2 does not migrate charge** — `memory.current` reads 0 after adoption. | The cap bounds **growth after adoption**; the ~0.5 GiB already-charged baseline is carried through the [D1](#d1--cap-values) arithmetic. |
| Implicit: adopting the `claude` PID covers the session | **False — MCP servers lose the race.** Measured: `playwright-mcp` (PID 3068389) is a **direct child of `claude`** and sits in the Warp scope. SessionStart and MCP startup are concurrent, so headless Chrome — the single largest memory risk on the box — would stay **uncapped**. | **Adopt the whole process tree.** `PIDs` is an array and multi-PID adoption is verified working (G15). See [D6](#d6--adopt-the-tree-not-just-the-pid). |
| Not mentioned anywhere in the issue | **`systemd-oomd` is active with `ManagedOOMMemoryPressure=kill`** on `user@.service`, and swap is already at **94 %** — past oomd's own 90 % threshold. oomd is a *userspace* killer that SIGKILLs **every PID in the selected cgroup**, and its candidate set is the monitored cgroup's **direct children**. Creating `soleur.slice` would make **the entire fleet a single oomd victim** — strictly worse than today. | **`ManagedOOMPreference=avoid` on the slice** (verified accepted on a `--user` transient scope, reads back `avoid`). See [D7](#d7--systemd-oomd). |
| `awk '{print $4}'` over `/proc/<pid>/stat` for PPid | Confirmed brittle (breaks on any ancestor whose `comm` contains a space). | Replaced by the label-anchored `/proc/<pid>/status` `PPid:` field + a **positive** identity match. Note `readlink /proc/<pid>/exe` returns **empty, not an error**, for an exited process — a walk that treats "no match" as "keep walking" could adopt `warp-terminal` or the login shell. See [D8](#d8--pid-discovery). |
| "documented a `daemon-reload` GC risk that does NOT reproduce on systemd 259" | Confirmed. | Not carried forward. A load-bearing comment describing a risk that is not real is worse than no comment. |

---

## Verified Live-Box Grounding

Host at plan time: **systemd 259 (259.5-0ubuntu3)**, Ubuntu, cgroup v2 unified, **30.4 GiB RAM**,
swap = `/swapfile` **1.9 GiB, 1.8 GiB used (~94 %) at rest**. All probes ran **without sudo**.

| # | Probe | Measured result |
|---|---|---|
| G1 | `StartTransientUnit` adopting a **live** PID | `rc=0`; `Memory: 0B (high: 3G, max: 4G, swap max: 0B)`. `MemoryHigh`/`MemoryMax`/`MemorySwapMax` all settable in **one atomic call**. Unit at `/run/user/1001/systemd/transient/`, `Transient: yes`. |
| G2 | PID cgroup before → after | `…/app.slice/app-gnome-dev.warp.Warp-3591813.scope` → `…/soleur.slice/soleur-agents.slice/<scope>`. **Adoption moves the PID.** All 12 live `claude` PIDs share that one Warp scope. |
| G3 | `BindsTo=`+`After=`, then `stop` the parent scope | Parent PID **dead**, child PID **dead**, child unit **gone**. The kill switch survives adoption. |
| G4 | `Slice=soleur-agents.slice` | Resolves to `…/user@1001.service/**soleur.slice/soleur-agents.slice**/<scope>` — systemd's dash convention **implicitly creates `soleur.slice`**. Both go in the AC7 allowlist. |
| G5 | Fleet bound on the slice | `SetUnitProperties(runtime=true, …)` → `rc=0`; `systemctl show` **and** the raw kernel files both reflect the values. |
| G6 | Where properties get written | `systemctl --user set-property` (no `--runtime`) → **persistent** `~/.config/systemd/user.control/<unit>.d/50-*.conf`. D-Bus `SetUnitProperties(…, runtime=true, …)` → **only** `/run/user/1001/systemd/user.control/` (verified with the persistent dir removed first). |
| G7 | Properties on an **inactive** slice, then a scope created into it | Slice activates **with the properties already applied**. Ordering not load-bearing. |
| G8 | `OOMPolicy` default on a transient scope | **`stop`** — systemd would stop the whole scope, **killing `claude`**, on any OOM. Explicit `OOMPolicy=continue` reads back `continue`. `memory.oom.group=0`. |
| G9 | Duplicate `StartTransientUnit`, same name | `rc=1`, `Unit … was already loaded` — a clean idempotency signal. |
| G10 | `oom_score_adj` writability | Raising to 500 → **OK**; *lowering* below the current value needs `CAP_SYS_RESOURCE`. |
| G11 | Lifecycle | Scopes self-clean on last-process exit. `soleur-agents.slice` and `soleur.slice` stayed `loaded/active` after emptying. |
| G12 | Hook ancestry (real child of `claude`) | `bash($$)` → `claude` → `bash` → `warp` → `warp-terminal` → `gnome-shell`. `readlink /proc/<claude>/exe` = `/home/jean/.local/share/claude/versions/2.1.220` — the same string that made `ps` render the runaway as `2.1.220`. |
| G13 | Fleet RSS at rest | **12 `claude` processes, ~6.0 GiB total, ~0.5 GiB each.** System: 30.4 GiB total, 14.7 GiB used → **non-agent baseline ≈ 8.7 GiB**. |
| G14 | AC1 surface audit | `settings.json` names **33 distinct hook paths** across `SessionStart`/`PreToolUse`/`PostToolUse`; **all 33 are `100755`** → gate green on the current tree, no pre-existing remediation needed. |
| G15 | **Multi-PID adoption** | `PIDs au 2 <A> <B>` → `rc=0`, **both** PIDs moved into the new scope. *(A first probe appeared to fail; the failure was in the probe — `pgrep -n -f "sleep 900"` matched this shell's own command line. Re-tested with `$!`-captured PIDs. Recording the false negative because "a probe returning the same result on every arm is an un-run instrument.")* |
| G16 | **`systemd-oomd`** | `systemd-oomd` **active**. `/usr/lib/systemd/system/user@.service.d/10-oomd-user-service-defaults.conf` sets `ManagedOOMMemoryPressure=kill`, `Limit=50%`. `oomctl`: swap-used limit 90 %, pressure duration 20 s, **swap currently 1.8/1.9 GiB = 94 %**. `oomctl` currently lists **zero** monitored cgroups — armed at the unit level but inert at runtime. That uncertainty is the risk, not a reassurance. |
| G17 | `ManagedOOMPreference=avoid` | **Accepted** on a `--user` transient scope (`rc=0`, reads back `avoid`). |
| G18 | **MCP race** | `playwright-mcp` PID 3068389 has `PPid` = a `claude` PID and sits in `app-gnome-dev.warp.Warp-3591813.scope` — i.e. **outside** any scope the hook would create for its own PID alone. |
| G19 | #7151 residue | `…/app.slice/soleur-agent-139954` — a raw-mkdir cgroup dir, no `.scope` suffix, unknown to systemd, **under the wrong parent**. Removed during probing. |
| G20 | Attribution readings | On a live scope, `memory.events` reads `low high max oom oom_kill oom_group_kill sock_throttled` (**cumulative counters**) and `memory.peak` is present. The slice's own `memory.current` is non-zero with a scope inside it — so AC4's two-session assertion is readable. |

Figures carried from the incident learning
(`knowledge-base/project/learnings/2026-08-02-ps-named-it-2-1-220-so-a-grep-that-ate-the-box-read-as-a-claude-leak.md`):

| Quantity | Value |
|---|---|
| Desktop-freeze point (single runaway) | **9.5 GB RSS**, 691 MB free, swap 88.5 % |
| Heaviest honest workload | `tsc --noEmit` **2.45 GB** |
| Second-heaviest | `vitest` full suite **898 MB** (12 702 tests) |
| `claude` baseline RSS | **~0.5 GiB** per session (G13) |
| Worst realistic single-scope concurrency | `claude 0.50 + tsc 2.45 + vitest 0.90` = **3.85 GiB** |
| Runaway death under a 3 GB cap | **SIGSEGV at 2.7 GB after ~45 s** |

---

## Design Decisions Resolved

### D1 — Cap values

**Per-session scope:** `MemoryHigh = 6 GiB`, `MemoryMax = 7 GiB`, `MemorySwapMax = 0`.

- **Floor.** The worst realistic single-scope concurrency is **3.85 GiB** (`claude` + `tsc` + `vitest`,
  and `scripts/test-all.sh` was observed running on this box during plan-time probing). `MemoryHigh`
  6 GiB is **1.56×** that. An earlier draft used 4 GiB — **rejected**, because 3.85 GiB is 96 % of it
  and the backstop would have throttled a green test run on day one.
- **Ceiling.** The harm point is **9.5 GB**. `MemoryMax` 7 GiB = **7.52 GB**; adding the ~0.5 GiB
  non-migrated baseline gives ≈ **8.0 GB — a real 1.5 GB margin** under 9.5 GB. (The engineering
  review recommended 8 GiB; this plan lands 1 GiB lower specifically to keep that margin after the
  charge-migration correction. 8 GiB remains inside the validated band, so raising it later is a
  one-integer change — see [D10](#d10--test-seams-and-two-sided-cap-validation).)
- The 6→7 GiB band is deliberately a **warning band, not a working region**: a workload sustaining
  6 GiB in one session is already anomalous.

**Fleet slice (`soleur-agents.slice`):** `MemoryHigh = 16 GiB`, `MemoryMax = 20 GiB`,
`MemorySwapMax = 0`, `ManagedOOMPreference = avoid`.

- Measured non-agent baseline ≈ **8.7 GiB** (G13). Honest ceiling ≈ 30.4 − 8.7 − ~3 GiB page-cache /
  desktop reserve ≈ **18.7 GiB**.
- **Sized against real concurrency, not idle RSS.** 12 idle sessions = 6.0 GiB; **three concurrent
  `tsc`** (a normal Tuesday across worktrees) adds 7.35 GiB = **13.35 GiB**; four adds 9.8 GiB =
  **15.8 GiB**. An earlier draft's 12 GiB `MemoryHigh` sat **below routine load** and would have
  converted the fleet brake into a permanent tax. 16 GiB clears the four-`tsc` case.
- **`MemoryMax` 20 GiB is a genuine last resort, not the working control.** Reaching it requires
  **three sessions simultaneously at their 7 GiB ceiling** — three concurrent runaways. 20 + 8.7 =
  28.7 GiB, leaving ~1.7 GiB plus a **fully-reserved 1.9 GiB swapfile** (agents are banned from swap),
  versus 0.67 GiB free and swap at 88.5 % at the freeze.
- **Bystander risk, stated not hidden.** At slice `MemoryMax` the kernel kills the largest task *in
  the slice subtree* — probabilistically the offender, since it is the one that grew, but **not
  guaranteed**. This is why the fleet control is `MemoryHigh` (non-lethal) and the per-session
  `MemoryMax` is the intended killer. Both the engineering and product reviews converged
  independently on this ordering.

### D2 — `MemoryHigh` vs `MemoryMax`

Both, at both levels — the issue's "`high` vs `max`" framing is a false choice.

- `MemoryHigh` throttles and reclaims **without killing**, which is what makes a *shared* slice viable
   — the objection that drove #7151's per-pid design.
- `MemoryHigh` **alone is insufficient**: `memory.high` triggers synchronous reclaim in the allocating
  task's context, and with `MemorySwapMax=0` on anon-dominant node heaps reclaim can only drop the
  cgroup's own file-backed pages and immediately refault them. The kernel caps the stall at ~2 s per
  allocation, so it never hard-freezes, but progress becomes glacial and **reads to the operator as a
  hang**. `MemoryMax` is the control that actually terminates a runaway.
- Crucially, this is also why `MemoryHigh` must be set **above** the heaviest honest workload
  ([D1](#d1--cap-values)) — a `high` below routine load is a permanent tax, not a brake.

### D3 — AC3: the terminal's kill switch

Literal cgroup co-membership is impossible alongside a per-session cap (G2). AC3's *intent* — "for a
non-technical operator, closing the terminal is the only stop mechanism there is" — is satisfied by
`BindsTo=<terminal-scope>` + `After=<terminal-scope>`, verified end-to-end (G3).

**Discovery:** read `/proc/<claude-pid>/cgroup`, take the basename, require a `.scope` suffix. The
name contains dots and dashes (`app-gnome-dev.warp.Warp-3591813.scope`) and must be passed quoted.

**The hole, disclosed:** `BindsTo=` tracks unit **active state**, not "the terminal window is gone".
A scope whose controlling process dies while a stray child survives enters `active (abandoned)` and
stays active indefinitely — one orphaned Warp helper keeps the terminal scope active, `BindsTo` never
fires, and the agent scopes survive with no terminal. Warp is also **one scope for the whole app, not
per-tab** (all 12 sessions share it), so closing a *tab* reaps via tty hangup (a process-level path,
unaffected by adoption) rather than via `BindsTo`.

Mitigation: `BindsTo` is **not** presented as the sole mechanism. The hook's first-apply
`systemMessage` and the README both name an explicit, always-available kill path:
`systemctl --user stop soleur.slice`.

**Assertion (both parts required):**
1. **Unit-level** — `systemctl --user show <scope> -p BindsTo` equals the discovered terminal scope.
2. **Behavioural** — in a synthetic parent/child pair, stopping the parent leaves the child's PID
   **dead** and the child unit **absent**. The unit-level check alone would not have caught #7151's
   escape.

### D4 — OOM victim selection

`OOMPolicy=continue` — **passed explicitly**, because G8 measured the transient-scope default as
`stop`, which makes systemd kill the whole scope (including `claude`) on any OOM — plus
`memory.oom.group=0` (default, **asserted not assumed**).

The kernel then kills the **single largest task** in the cgroup. At `MemoryMax` the runaway *is* the
largest by construction (~7 GiB vs `claude`'s ~0.5 GiB), so **the session survives and the runaway
dies**, without touching `oom_score_adj` at all.

`oom_score_adj` is explicitly **not** used: lowering `claude`'s own score requires `CAP_SYS_RESOURCE`
(G10), and raising future children's scores is unreachable from a hook that runs before they exist.

### D5 — Fleet-bound persistence

D-Bus `SetUnitProperties("soleur-agents.slice", runtime=true, …)`, re-applied idempotently every
SessionStart.

Chosen over `systemctl --user set-property`, which without `--runtime` writes a **persistent** drop-in
into `~/.config/systemd/user.control/` (G6) — a permanent mutation of the operator's own systemd
configuration that this hook has no business making. `runtime=true` writes only under
`/run/user/<uid>/`, so a reboot self-heals via the next SessionStart.

This also enables an AC7 assertion that is otherwise unavailable: a mutant that drops `runtime=true`
is caught by asserting `~/.config/systemd/user.control/` is byte-identical before and after.

*(A static `~/.config/systemd/user/soleur-agents.slice` unit file was considered and rejected: it is a
persistent write into the operator's config, and it cannot ship by merging a PR — it would require an
install step, forfeiting the zero-operator-steps property.)*

### D6 — Adopt the tree, not just the PID

Measured (G18): MCP servers are **direct children of `claude`** and SessionStart runs *concurrently*
with MCP startup. Adopting only `claude`'s PID loses that race, leaving `playwright-mcp` and headless
Chrome — the largest memory risk on the box — **outside the cap**, which most undermines the feature's
purpose.

Fix: collect `claude`'s PID **plus all its descendants** (recursive `PPid` scan over `/proc`) and pass
them all in one `PIDs` array. Multi-PID adoption is verified working (G15). Anything spawned *after*
adoption inherits the cgroup automatically, and re-entry on `resume|clear|compact` re-sweeps for
stragglers.

Bound the descendant scan (max 256 PIDs, single `/proc` pass) so a pathological tree cannot stall
SessionStart.

### D7 — `systemd-oomd`

**The most consequential finding of plan-time probing, and absent from the issue entirely.**

`systemd-oomd` is **active** and `user@.service` carries `ManagedOOMMemoryPressure=kill` with a 50 %
pressure limit; oomd's own swap-used limit is 90 % and swap is **already at 94 %** (G16). Three
consequences:

1. `OOMPolicy=continue` and `memory.oom.group=0` govern the **kernel** memcg OOM path only. oomd is a
   **userspace** killer that SIGKILLs **every PID in the selected cgroup** — our carefully-chosen
   "kill only the largest task" semantics do not apply to it.
2. oomd's candidate set for a monitored cgroup is its **direct children**. The monitored cgroup is
   `user@1001.service`. Once `soleur.slice` exists, the candidate becomes `soleur.slice` — **the
   entire fleet, every session, at once.** Strictly worse than today's failure mode.
3. `MemorySwapMax=0` **raises** memory PSI inside the agent cgroups (reclaim cannot offload anon),
   making `soleur.slice` the *most attractive* oomd victim by construction.

Mitigation (verified, G17): set **`ManagedOOMPreference=avoid` on `soleur-agents.slice`** and leave
per-session scopes at the default — oomd then prefers killing one session over the fleet. `oomctl`
before/after is a required verification step (Phase 0.8, AC15).

Honest caveat: `oomctl` currently lists **zero** monitored cgroups, so the policy is armed at unit
level but inert at runtime. What flips it on was not determined. **That uncertainty is the reason to
set `avoid`, not a reason to skip it.**

### D8 — PID discovery

Walk `PPid:` from `/proc/$$/status` — the **label-anchored** field, never `awk '{print $4}'` over
`/proc/<pid>/stat` (breaks on any ancestor whose `comm` contains a space). Bound the walk to 8 hops.

**Require a *positive* identity match, and adopt nothing on failure.** `readlink /proc/<pid>/exe`
returns **empty, not an error**, when the process has exited (observed during plan-time probing), so a
walk that treats "no match" as "keep walking" and then adopts the last PID examined could put
`warp-terminal` or the login shell under a 7 GiB cap bound to itself. Guards:

- accept on **any** of: `exe` matching `*/claude/versions/*`, `$CLAUDE_CODE_EXECPATH` resolving to the
  candidate, or `/proc/<pid>/comm` == `claude` — and **log which signal matched**, so a non-standard
  install (an npm-global install gives `exe` = `/usr/bin/node`) degrades to a *logged* fail-open
  rather than a silent one;
- reject PID 1, PID 0, the hook's own PID, and the terminal scope's leader;
- on no positive match: `outcome=skipped reason=claude_pid_not_found`, `exit 0`.

### D9 — Idempotency, re-entry, and kill attribution

`SessionStart` fires up to four ways per PID, so re-entry is the normal case.

| State on entry | Behaviour |
|---|---|
| Not adopted; cgroup basename ends in `.scope` | Discover terminal scope → `StartTransientUnit` with the full PID tree and all properties. |
| `StartTransientUnit` returns `rc=1` (`already loaded`, G9) | Fall through to `SetUnitProperties(<our-scope>, runtime=true, …)` to **refresh** caps — this is how a changed cap lands without a session restart — and re-sweep for new descendants. |
| Already in `soleur-agent-<pid>.scope` | **Do not re-derive the terminal scope** (it would resolve to our own scope — a self-binding bug). Read `BindsTo` from the existing unit and preserve it. |
| Cgroup basename is not a `.scope` | Fail open, `outcome=skipped reason=no_terminal_scope`, `exit 0`. |
| **`rc=1` but the PID is *not* in that scope** (PID reuse) | See below — **do not** treat `rc=1` as "already adopted". |

**PID-reuse hole (closed here, not discovered later).** The scope name `soleur-agent-<pid>.scope` is
keyed on a PID, and PIDs are reused. A scope left `active (abandoned)` by a stray child
([D3](#d3--ac3-the-terminals-kill-switch)) can outlive its session; if the OS then reuses that PID
for a new `claude`, `StartTransientUnit` returns `rc=1` and the naive re-entry branch would
"refresh" a scope the new process is **not a member of** — reporting `outcome=applied` while the
session is entirely uncapped. That is the #7151 failure shape (a green signal over an inert guard)
reproduced by a different route.

Mitigation, required: after any `rc=1`, **verify membership** — `/proc/<claude-pid>/cgroup` basename
must equal the scope name. If it does not, disambiguate by appending the process **start time**
(`/proc/<pid>/stat` field 22, monotonic and unique per PID incarnation) to the scope name and retry
once: `soleur-agent-<pid>-<starttime>.scope`. Log `reason=pid_reuse_disambiguated`.

**Kill attribution and near-miss (product requirement).** On re-entry, before refreshing, read the
existing scope's `memory.events` and `memory.peak` in **one pass**. Measured available on a live
scope (G20): `memory.events` exposes `low high max oom oom_kill oom_group_kill sock_throttled`, and
`memory.peak` gives the high-water mark.

| Reading | Message |
|---|---|
| `oom_kill > 0` | **Kill attribution.** Plain-language `systemMessage`: what was stopped, that uncommitted work in that command may be lost, the cap that was hit, `memory.peak`, and the **exact one-line command to raise the cap** plus the full-disable variable. |
| `high > 0`, `oom_kill == 0` | **Near-miss.** "This session crossed its 6 GiB brake N times (peak X GiB) but was not killed" — turns cap-tuning into an evidence-driven change and warns *before* a first kill. |

Without kill attribution, an OOM kill presents as *the very symptom the hook exists to prevent* — a
process vanishing mid-work — now caused by us.

> **Correction to an earlier draft of this plan.** The near-miss signal was initially scoped out on
> the grounds that it "needs a sampling mechanism the hook does not have (it runs once per session
> start, not continuously)". That was wrong: `memory.events` carries **cumulative counters**, so a
> single read on re-entry recovers the whole interval without any sampling. The capability was
> declared unavailable after considering only one mechanism (polling) — the
> *"one blocked mechanism is not a blocked capability"* failure. Reading `memory.events`
> post-scope-*exit* genuinely is impossible (the cgroup is gone); reading it on re-entry, which is
> the case that matters, is free.

### D10 — Test seams and two-sided cap validation

**One master gate.** `SOLEUR_MEMORY_BACKSTOP_TEST_MODE=1`. Every other injection variable is read
**only inside that branch**, so with the flag unset `SOLEUR_MEMORY_BACKSTOP_TARGET_PID` cannot skip
the identity check and `…_BYTES=0` cannot be a one-token session kill (both #7151 defects).

| Variable | Read only when `TEST_MODE=1` |
|---|---|
| `SOLEUR_MEMORY_BACKSTOP_TARGET_PID` | yes |
| `…_SCOPE_HIGH_BYTES` / `…_SCOPE_MAX_BYTES` | yes |
| `…_SLICE` | yes — **defaults to `soleurtest-agents.slice`** so tests never touch the production slice |
| `…_SLICE_HIGH_BYTES` / `…_SLICE_MAX_BYTES` | yes |

**Two-sided range validation, enforced in BOTH modes** (a floor alone does not encode "below the harm
point"):

| Value | Accepted range | Why the bound |
|---|---|---|
| per-session `MemoryMax` | `3 GiB ≤ v ≤ 8 GiB` | floor **3 GiB > 2.45 GB** `tsc` peak; ceiling **8 GiB = 8.59 GB < 9.5 GB** harm point |
| per-session `MemoryHigh` | `5 GiB ≤ v < MemoryMax` | floor clears the **3.85 GiB** honest concurrency peak with ≥ 1.3× headroom. Deliberately **not** 4 GiB — [D1](#d1--cap-values) rejects that value as too tight, so the band must not admit it |
| fleet `MemoryMax` | `10 GiB ≤ v ≤ 24 GiB` | floor ≥ one session's ceiling **plus** the idle fleet (7 + 6.0 ≈ 13, rounded down to a permissive 10); ceiling leaves ≥ 6 GiB for the desktop on a 30.4 GiB box |
| fleet `MemoryHigh` | `14 GiB ≤ v < fleet MemoryMax` | floor clears the **three**-concurrent-`tsc` case (13.35 GiB); the chosen 16 GiB additionally clears the **four**-`tsc` case (15.8 GiB) |

Each floor is set so the band **cannot admit a value this plan's own analysis rejects** — a
validation band that would pass 4 GiB per-session or 8 GiB fleet-high would contradict
[D1](#d1--cap-values) and silently re-introduce the "brake becomes a permanent tax" defect.

Out of range ⇒ **apply nothing**, log `outcome=refused reason=cap_out_of_range value=<v>`, emit a
`systemMessage`, `exit 0`. Refusing is correct: a cap outside the validated band is either useless or
dangerous, and a hook that half-applies is worse than one that declines.

**All four values live in one `readonly` block at the top of the hook**, so raising a cap is a
one-token change, and `SOLEUR_DISABLE_MEMORY_BACKSTOP=1` disables the hook entirely — the repo's
established kill-switch convention (`SOLEUR_DISABLE_AGENT_TOKEN_TEE`, `SOLEUR_DISABLE_SKILL_LOGGER`,
`SOLEUR_DISABLE_CONTEXT_QUERIES`, `SOLEUR_DISABLE_PHASE_HINT`).

### D11 — Pre-existing uncapped sessions; self-only adoption

Honest gap: a session that started before the hook existed is in no scope. **v1 adopts only its own
session tree.**

- **Convergence.** The matcher is `startup|resume|clear|compact`, so any long-lived session is adopted
  the next time it is cleared, compacted, or resumed — which every long session hits.
- **Consequence, stated plainly:** until every session has cycled, **the fleet cap's denominator is
  wrong** — with 12 sessions live today the fleet bound is close to meaningless on first merge. It
  becomes real as sessions cycle.
- **Why not sweep every `claude` PID.** Each PID would have to bind to **its own** terminal scope
  (binding another terminal's session to *this* terminal would make closing this window kill that
  session — strictly worse than the status quo), and it would race with concurrent SessionStarts.
  Deferred with a tracking issue ([§ Non-Goals](#non-goals--out-of-scope)).

### D12 — Blast radius: a documented disagreement

The engineering and product reviews **agree on the facts and disagree on the verdict**, so both are
recorded rather than one being silently adopted.

- **Agreed facts.** `.claude/settings.json` and `.claude/hooks/` are **git-tracked**, so the hook runs
  for anyone running Claude Code inside a clone of this repo — the operator, contributors, CI. The
  *shipped plugin* surface is `plugins/soleur/hooks/hooks.json` (welcome + stop hooks only), which
  this plan **does not touch** — so it does **not** reach downstream Soleur plugin users.
- **Engineering position (blocking):** committing this silently reparents a contributor's `claude`
  into a slice they never asked for and imposes caps they never consented to; it belongs in
  `~/.claude/settings.json` (user-level, untracked).
- **Product position:** repo-local hooks are not a user-distribution surface; blast radius today is
  the operator's machine plus contributor clones, with zero beta users on the roadmap.
- **Resolution adopted:** ship repo-local **with `SOLEUR_DISABLE_MEMORY_BACKSTOP=1`**, which is the
  repo's own existing convention for exactly this consent question — four hooks already in the tree
  are opt-out by the same mechanism. This makes the new hook *no more imposed* than its siblings,
  using precedent rather than inventing policy. The README documents the kill switch alongside them.
- **Escalation trigger, recorded now:** promoting this hook into `plugins/soleur/hooks/hooks.json`
  would change the blast radius to fleet-wide and **requires revalidation of the brand-survival
  threshold**. Explicitly scoped out ([§ Non-Goals](#non-goals--out-of-scope)).

---

## User-Brand Impact

**If this lands broken, the user experiences:** a mis-sized or mis-targeted cap **OOM-kills a live
agent session mid-work**, losing uncommitted work — or, the #7151 failure verbatim, the hook
**silently never applies** while the operator believes they are protected, and the next runaway
freezes the desktop and kills every open session.

**If this leaks, the user's workflow is exposed via:** no data surface. The hook reads `/proc`, calls
the invoking user's own systemd bus over a `SO_PEERCRED`-authenticated unix socket, and appends one
JSON line per session to a gitignored local log. No network egress, no credentials, no third-party
processor. The log records a PID, a scope name and cap integers; **the session id is deliberately not
recorded.**

**Brand-survival threshold:** `single-user incident`.

**Precise sizing (product review):** the enum value is correct, but the failure *unit* is not one
user — it is **every concurrent agent session on one host**, which is exactly the six sessions the
2026-08-01 incident killed. A shared `soleur-agents.slice` makes session B's survival depend on
session A's behaviour. Read the threshold as *single-machine, multi-session*. That sizing is what
forces the plan to answer "who dies when the slice is exhausted" — answered in
[D1](#d1--cap-values) (fleet control is non-lethal `MemoryHigh`; the per-session `MemoryMax` is the
intended killer) and [D7](#d7--systemd-oomd) (`ManagedOOMPreference=avoid` so oomd cannot take the
whole fleet).

`requires_cpo_signoff: true` is set; `user-impact-reviewer` runs at review time.

---

## Architecture Decision (ADR/C4)

Detection fires: a **new substrate pattern** (host-level resource control as a first-class
agent-runtime concern) and a **new lifecycle boundary** (the runtime's lifetime now depends on a
systemd unit dependency, not process ancestry). A competent engineer reading only the existing ADRs
and C4 **would be misled** about how an agent session is bounded and reaped.

### ADR

**Create `ADR-155-memory-backstop-via-systemd-transient-scopes.md`.** Highest existing ordinal at plan
time is **ADR-154**, so **155 is provisional** — `/ship`'s ADR-Ordinal Collision Gate re-verifies
against `origin/main`. **If it renumbers, sweep the whole feature artifact set in the same edit**
(`grep -rn 'ADR-155' knowledge-base/project/{plans,specs}/`): the plan, `tasks.md`, and AC14 all name
the ordinal and would otherwise assert a nonexistent file.

Record the decision *and* — per the engineering review — the **wrapper-vs-adopt choice**, the
**systemd-oomd interaction**, and **why the caps live where they do**. `## Alternatives Considered`
must carry, each with the measurement that refuted it:

| Alternative | Why not |
|---|---|
| Raw cgroup v2 directory writes (#7151) | Single-writer violation, leaked a cgroup per session, escaped the kill switch; residue found on the box under the **wrong parent** (G19). |
| `ulimit -v` | Measured: vitest dies at 97 MB actual RSS under **every** cap up to 32 GB — V8/WASM *reserves* address space, so `-v` counts reservations, not usage. |
| `memory.high` alone | Degenerates into refault thrash once swap is capped ([D2](#d2--memoryhigh-vs-memorymax)). |
| `oom_score_adj` biasing | Lowering requires `CAP_SYS_RESOURCE` (G10); raising children's scores is unreachable from SessionStart. |
| **A `soleur-claude` wrapper** (`systemd-run --user --scope … claude "$@"`) | Genuinely better on two axes — MCP servers are inside the cgroup from PID 0, and the cgroup carries a real charge instead of the `memory.current=0` post-adoption blind spot. **Rejected because** it protects only sessions launched through the alias (it fails exactly when the operator forgets), and it cannot ship by merging a PR — it needs an install step, forfeiting the zero-operator-steps property. [D6](#d6--adopt-the-tree-not-just-the-pid) recovers most of the MCP coverage it would have given. |
| A static `~/.config/systemd/user/soleur-agents.slice` unit file | Persistent write into operator config; same install-step objection. |

### C4 views

All three `.c4` files were **read in full**, not keyword-grepped — a grep for "memory" or "systemd"
returns nothing and would have produced a false "no C4 impact".

| Category | Finding |
|---|---|
| **(a) external human actors** | `founder` ("Founder / Operator") already modelled. No new human actor. |
| **(b) external systems / vendors** | **`systemd` (per-user manager) is NOT modelled and must be added** — an outbound API the Hook Engine calls over D-Bus, in the same class as the modelled `anthropic` / `doppler` / `github`. |
| **(c) containers / data stores** | No new store. `platform.engine.hooks` ("Hook Engine") gains the capability. |
| **(d) actor↔surface access relationships** | **The terminal-close kill switch is unmodelled.** There is no `founder -> claude` edge at all (`founder -> webapp` is the only founder edge into the platform) — yet that relationship is precisely what this change alters the mechanism of. |
| **description falsified** | `platform.engine.hooks`'s description asserts the container "Guards tool calls … AND injects additive context" — an implied-complete enumeration this change makes false by adding **host resource-control enforcement**. |

In-scope `.c4` edits, committed in **this** feature's lifecycle (edited directly on the filesystem —
the `c4-edit` flag gates only the in-browser webapp editor and is not on this path):

1. `model.c4` — add `systemdUser = system "systemd (user manager)" { #external; description "…" }`.
2. `model.c4` — add `hooks -> systemdUser "Adopts the live agent process tree into a memory-capped transient scope under soleur-agents.slice (StartTransientUnit over D-Bus); systemd is the single writer — no raw cgroup directory writes (ADR-155)" { technology "D-Bus (busctl --user)" }`.
3. `model.c4` — add `founder -> claude "Closes the terminal to reap a runaway session — preserved across the memory backstop by BindsTo= on the terminal's own scope; explicit fallback `systemctl --user stop soleur.slice` (ADR-155)"`.
4. `model.c4` — amend the `hooks` container description to include resource-control enforcement.
5. `views.c4` — add `systemdUser` to the `include` list of **both** the `context` (L1) and `containers`
   (L2) views, matching every other external system. A `view … include` naming an undefined element
   fails `c4-code-syntax.test.ts`, **not** `tsc` — run that suite plus `c4-render.test.ts`.

### Sequencing

Not soak-gated. ADR-155 ships `status: accepted` in this PR.

---

## Observability

```yaml
liveness_signal:
  what: one JSON line appended to .claude/.memory-backstop.jsonl per SessionStart, plus a live
        systemd unit `soleur-agent-<pid>.scope` visible to `systemctl --user`
  cadence: every SessionStart (startup|resume|clear|compact)
  alert_target: operator terminal via `systemMessage`, EDGE-TRIGGERED only — (a) once per
        (host, hook-version, limit-set) on first successful apply, stamped so it stays silent
        thereafter; (b) whenever the hook previously succeeded on this host and now fails to apply
        (the silent-no-op regression class); (c) on detected OOM attribution. Never per-session.
  configured_in: .claude/hooks/memory-backstop.sh; .claude/settings.json SessionStart block

error_reporting:
  destination: .claude/.memory-backstop.jsonl (outcome/reason fields) + systemMessage on stdout
  fail_loud: partial by design — the hook NEVER blocks a session (exit 0 unconditionally, mirroring
        supabase-loopback-warn.sh's "NEVER blocks" contract), but every non-applied outcome is
        logged with a machine-readable reason AND surfaced on the edge-triggered channel. Plain
        stderr is NOT the primary sink: .claude/hooks/README.md records that stderr is DISCARDED on
        an exit-0 hook — the "dark tripwire" defect its sibling hook's header documents.

failure_modes:
  - mode: hook never executes (the #7151 defect — committed 100644)
    detection: settings-hook-exec-bit.test.sh asserts `git ls-files -s` == 100755 for every hook
        path named in settings.json; memory-backstop.test.sh invokes the hook via the command
        string reconstructed FROM settings.json, not `bash <hook>`
    alert_route: CI red on scripts/test-all.sh (both suites auto-discovered by `.claude/hooks/*.test.sh`)
  - mode: hook runs but silently applies nothing (no bus / no claude PID / not a .scope)
    detection: `outcome=skipped reason=<enum>` in .claude/.memory-backstop.jsonl; absence of a
        `soleur-agent-*` unit in `systemctl --user list-units`
    alert_route: edge-triggered systemMessage when the hook previously succeeded on this host;
        silent where there is no user bus at all (an expected environment, not a failure)
  - mode: MCP servers spawned before adoption stay uncapped (measured: playwright-mcp is a direct
        child of claude and SessionStart races MCP startup)
    detection: test asserts every descendant PID's /proc/<pid>/cgroup equals the new scope after
        adoption — an observable-effect assertion, not an exit-0 assertion
    alert_route: CI red
  - mode: honest workload OOM-killed by our own cap
    detection: `memory.events` `oom_kill` read on the scope at next SessionStart re-entry
    alert_route: plain-language systemMessage naming what was stopped, the cap that was hit, that
        uncommitted work may be lost, and the one-line command to raise the cap
  - mode: systemd-oomd SIGKILLs the whole soleur.slice (userspace killer; ignores OOMPolicy)
    detection: `oomctl` before/after in Phase 0.8 + AC15; ManagedOOMPreference=avoid read back
    alert_route: CI red on the property assertion; `oomctl` output recorded in the PR body
  - mode: writes land outside the hook's own cgroup (e.g. a mutation capping the parent slice)
    detection: before/after sweep over every memory.{high,max,swap.max,low,min} under the user
        manager's cgroup subtree + byte-identical check on ~/.config/systemd/user.control/
    alert_route: CI red

logs:
  where: .claude/.memory-backstop.jsonl (gitignored; rotated via .claude/hooks/lib/log-rotation.sh
         `rotate_if_needed` at the repo-standard 5 MB / 30-day thresholds, conforming to the
         existing log-rotation.test.sh contract)
  retention: one rotated archive, same policy as .claude/.rule-incidents.jsonl

discoverability_test:
  command: systemctl --user list-units 'soleur-*' --all --no-pager && systemctl --user show soleur-agents.slice -p MemoryHigh -p MemoryMax -p MemorySwapMax -p ManagedOOMPreference && oomctl | head -20 && tail -3 .claude/.memory-backstop.jsonl
  expected_output: at least one `soleur-agent-<pid>.scope`; the slice reporting MemoryHigh=17179869184
        MemoryMax=21474836480 MemorySwapMax=0 ManagedOOMPreference=avoid; oomctl listing no
        soleur cgroup as a kill candidate; a recent log line with `"outcome":"applied"`
```

No `ssh` on any path — the surface is the operator's own host.

---

## Infrastructure (IaC)

**No IaC surface, and no operator steps.** This introduces no server, vendor account, DNS record, TLS
cert, secret, firewall rule, or persistent host service. The systemd units are **transient**, created
at runtime by the hook, and self-clean when their last process exits (G11). Nothing is provisioned;
nothing is written to `/etc`; no `daemon-reload`, no `sudo`, no unit file on disk outside `/run`
(G1, G6).

Every `systemctl` / `oomctl` invocation in this document is **read-only verification or operator
discoverability** — never provisioning. The two state-changing D-Bus calls (`StartTransientUnit`,
`SetUnitProperties`) are made **by the hook itself at runtime**, which is the automation, not a step
handed to a human.

**Merging the PR is the complete deployment.** The hook applies itself on the next SessionStart on
every machine that has the repo checked out. That satisfies
`hr-all-infrastructure-provisioning-servers` by having **no provisioning at all**, rather than by
automating a manual step.

---

## Encryption Posture

Not applicable — no persistent data store and no new cross-component or network connection. The only
new communication is a local D-Bus call to the invoking user's own systemd manager over a unix socket
at `/run/user/<uid>/bus`, authenticated by `SO_PEERCRED` uid matching and reachable only by that uid.
No data leaves the host.

---

## GDPR / Compliance Gate

Skipped — no regulated-data surface. The canonical trigger regex (schemas, migrations, auth flows,
API routes, `.sql`) matches nothing in this diff, and none of the four expansion triggers fire: no
LLM/external-API processing of operator data, no cron/workflow reading `learnings/` or `specs/`, no
new artifact-distribution surface. The local log records a PID, a scope name and cap integers; the
session id is deliberately **not** recorded, so no line ties to a conversation.

---

## Open Code-Review Overlap

**None.** Queried 62 open `code-review` issues against every path in
[§ Files to Create / Edit](#files-to-create--edit). The single textual hit — **#2348** (`vitest:
mock-factory export drift…`) — matched only on the incidental substring `.claude/hooks/` and concerns
no file this plan touches. **Disposition: acknowledge**, no action.

---

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — mandatory at the declared threshold).

### Engineering

**Status:** reviewed
**Assessment:** six findings changed the design and are folded in above, not appended: (1)
**`systemd-oomd` is armed to `kill` and would take the whole `soleur.slice` at once** — mitigated by
`ManagedOOMPreference=avoid` ([D7](#d7--systemd-oomd)); (2) **MCP servers lose the adoption race**,
leaving headless Chrome uncapped — mitigated by tree adoption ([D6](#d6--adopt-the-tree-not-just-the-pid));
(3) the original caps were sized off **idle** RSS and sat below routine load — re-derived against
measured concurrency ([D1](#d1--cap-values)); (4) `OOMPolicy` defaults to `stop`
([D4](#d4--oom-victim-selection)); (5) `readlink /proc/<pid>/exe` returns **empty, not an error**, for
an exited process, enabling wrong-PID adoption ([D8](#d8--pid-discovery)); (6) `busctl` prints the job
object path on stdout, which a SessionStart hook injects into session context — must be redirected.
The blocking architectural objection on blast radius is recorded, with the contradicting product
verification, in [D12](#d12--blast-radius-a-documented-disagreement).

### Product/UX Gate

**Tier:** none
**Decision:** reviewed
**Agents invoked:** cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

The mechanical UI-surface override does **not** fire: no path matches `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx`. CPO was invoked because the threshold is
`single-user incident`, not because a UI surface exists.

#### Findings

Sign-off is **approve with two blocking additions**, both folded in: the **exec-bit CI gate across
all hook entrypoints** (AC1 — #7151 is a *class*, not an instance, and this one gate protects all 33
existing hooks) and **kill attribution with a plain-language post-mortem message**
([D9](#d9--idempotency-re-entry-and-kill-attribution) — without it the operator's mental model becomes
"Soleur randomly kills my work", which is the difference between a guardrail and a defect). Also
adopted: edge-triggered first-apply confirmation, an observable-effect (cgroup-membership) test
assertion rather than exit-0, caps in one config location, a documented one-line override named in
the kill message itself, and a full-disable path. The threshold sizing correction
(*single-machine, multi-session*) is recorded in
[§ User-Brand Impact](#user-brand-impact). The operator-digest proof-of-life line is scoped out with a
tracking issue ([§ Non-Goals](#non-goals--out-of-scope)).

---

## Implementation Phases

Ordering is load-bearing: the **class gate ships before the file it gates**, and the **contract (the
hook) ships before its consumer (`settings.json`)**. Wiring `settings.json` first would arm an
unwritten hook on the operator's very next session.

### Phase 0 — Preconditions (re-verify, do not re-derive)

Each item was measured at plan time and recorded in
[§ Verified Live-Box Grounding](#verified-live-box-grounding). A divergence is a stop-and-replan
signal, not something to work around.

- [ ] 0.1 `systemctl --version` → systemd ≥ 257 (plan measured 259).
- [ ] 0.2 `StartTransientUnit` adopting a throwaway `sleep` PID → `rc=0` (G1). **Never probe with a
      real `claude` PID.** Capture probe PIDs with `$!`, **never `pgrep -f <pattern>`** — the pattern
      matches this shell's own command line and produces false results (the G15 false negative).
- [ ] 0.3 `OOMPolicy` default on a transient scope reads `stop` (G8). If it reads `continue` on the
      host, the explicit override is still correct but the rationale comment must be **corrected**,
      not deleted.
- [ ] 0.4 `SetUnitProperties(runtime=true)` writes only `/run/user/<uid>/systemd/user.control/` and
      leaves `~/.config/systemd/user.control/` untouched (G6). Remove stale `soleur*` drop-ins first.
- [ ] 0.5 `BindsTo=` reap behaviour in a synthetic parent/child pair (G3).
- [ ] 0.6 **Multi-PID adoption** moves every PID passed (G15).
- [ ] 0.7 Record `free -m` and the `claude` fleet RSS total into the PR body — the
      [D1](#d1--cap-values) arithmetic is only defensible against a stated baseline.
- [ ] 0.8 **`oomctl`** — record monitored-cgroup lists and swap-used %, and confirm
      `ManagedOOMPreference=avoid` is accepted on a `--user` transient scope (G16, G17).
- [ ] 0.9 AC1 surface still clean: every hook path named in `settings.json` is `100755` (G14). If a
      non-`100755` hook has landed on `main` since, **fix it in this PR** rather than weakening the gate.
- [ ] 0.10 Sweep for orphaned raw cgroup dirs under `app.slice` (G19) and `rmdir` any found — a leaked
      dir makes the AC7 sweep read dirty.

**Cleanup contract for every probe:** stop each probe unit and remove any `soleur*` drop-in it created
under both `~/.config/systemd/user.control/` and `/run/user/<uid>/systemd/user.control/`.

### Phase 1 — RED/GREEN: the exec-bit class gate (AC1)

- [ ] 1.1 Create `.claude/hooks/settings-hook-exec-bit.test.sh`, mirroring
      `scripts/followthrough-exec-bit.test.sh`'s three structural properties: assert the **index**
      mode via `git ls-files -s` (not `test -x`), **fail loudly on an empty listing**, and carry a
      **minimum-cardinality floor**.
- [ ] 1.2 Derive the list across **all** hook events:
      `jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' .claude/settings.json | sed 's|^"\$CLAUDE_PROJECT_DIR"/||' | sort -u`
      (verified to yield 33 paths). Floor at **25** — loose enough to grow, high enough that a broken
      `jq` filter (which yields 0) fails.
- [ ] 1.3 Assert every derived path is **tracked** and mode `100755`. An untracked path named in
      `settings.json` is also a failure: production would exec a file CI never sees.
- [ ] 1.4 Confirm green on the current tree, then **prove non-vacuity**: flip one hook to `100644` in
      a scratch copy and confirm RED. Restore.
- [ ] 1.5 Do **not** widen `scripts/followthrough-exec-bit.test.sh` — its header pins its scope, and
      five `.claude/hooks/**` files are legitimately `100644`.

### Phase 2 — RED: the backstop suite

- [ ] 2.1 Create `.claude/hooks/memory-backstop.test.sh` against the not-yet-written hook; confirm it
      fails for the right reason (hook absent), not a harness error.
- [ ] 2.2 Establish the **live-arm gate**: probe the user bus once. When absent (CI, Docker, macOS,
      non-systemd Linux) print `SKIP: no user systemd bus — <N> live assertions not run` and run the
      pure-fixture arm. The `RESULT:` line must carry `[live: yes|SKIPPED]` so a permanently-skipped
      live arm is visible rather than silently green.
- [ ] 2.3 All test units live in a namespaced slice (`soleurtest-agents.slice`) with `soleurtest-*`
      scope names, so the suite can never mutate the production slice. `trap`-based teardown stops
      every unit created and removes any `user.control` drop-in produced.

### Phase 3 — GREEN: the hook (contract)

- [ ] 3.1 Create `.claude/hooks/memory-backstop.sh` following `supabase-loopback-warn.sh`'s structure:
      `#!/usr/bin/env bash`, `set -uo pipefail` (**deliberately not `-e`** — the expected `rc=1` from
      the duplicate-unit branch would otherwise abort the hook),
      `PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"`, a
      header recording **why** each choice was made, and `exit 0` on every path.
- [ ] 3.2 Honour `SOLEUR_DISABLE_MEMORY_BACKSTOP=1` as the first statement after the header
      ([D12](#d12--blast-radius-a-documented-disagreement)). Declare all four cap values in one
      `readonly` block immediately below.
- [ ] 3.3 Early silent exits, each with a distinct logged `reason`, no `systemMessage`, `exit 0`:
      `command -v busctl` absent; `[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]` false; bus
      probe fails. **Gate on the socket, not on parsing a `busctl` error string.**
- [ ] 3.4 Discover the `claude` PID per [D8](#d8--pid-discovery) — label-anchored `PPid:`, positive
      identity match across three signals with the matching signal logged, explicit PID guards.
- [ ] 3.5 Collect the full descendant PID set per [D6](#d6--adopt-the-tree-not-just-the-pid) in a
      single bounded `/proc` pass (max 256 PIDs).
- [ ] 3.6 Discover the terminal scope per [D3](#d3--ac3-the-terminals-kill-switch); branch per
      [D9](#d9--idempotency-re-entry-and-kill-attribution).
- [ ] 3.7 Validate all four cap values per [D10](#d10--test-seams-and-two-sided-cap-validation)
      **before** any D-Bus call. Refuse-and-log on out-of-range.
- [ ] 3.8 Apply, in order: `SetUnitProperties(slice, runtime=true, MemoryHigh, MemoryMax,
      MemorySwapMax, **ManagedOOMPreference=avoid**)`, then `StartTransientUnit(scope, …)` with
      `PIDs`(tree), `Slice`, `MemoryHigh`, `MemoryMax`, `MemorySwapMax`, **`OOMPolicy=continue`**,
      `BindsTo`, `After`. (G7 proves order is not load-bearing; slice-first means the fleet bound and
      the oomd preference are live before anything can be charged.)
- [ ] 3.9 **Redirect every `busctl` call's stdout to `/dev/null`** — `busctl call` prints the returned
      job object path on success, and a SessionStart hook's stdout is injected into session context.
- [ ] 3.10 Wrap every external call in the sibling hook's portable `timeout` idiom
      (`TO=(); command -v timeout >/dev/null 2>&1 && TO=(timeout 5)`) — macOS ships no `timeout`, and
      hardcoding it made a sibling hook exit 127 and go silently dark. A wedged D-Bus must not stall
      every SessionStart.
- [ ] 3.11 Append one JSON line to `.claude/.memory-backstop.jsonl`, calling `rotate_if_needed` from
      `.claude/hooks/lib/log-rotation.sh` first (conforming to the existing `log-rotation.test.sh`
      contract). Record `ts, event, pid, tree_size, scope, terminal_scope, slice, scope_high,
      scope_max, slice_high, slice_max, swap_max, identity_signal, outcome, reason`. **Never the
      session id.**
- [ ] 3.12 Emit `systemMessage` only on the three edge-triggered conditions in
      [§ Observability](#observability), using a stamp file keyed on
      (host, hook-version, limit-set) for the first-apply case. The OOM-attribution message must name
      the one-line command to raise the cap **and** the full-disable env var.
- [ ] 3.13 Commit executable with
      **`git update-index --chmod=+x .claude/hooks/memory-backstop.sh`** on that exact path —
      **never a glob** (a glob `chmod` silently flips other tracked modes in a worktree, and five
      `.claude/hooks/**` files are legitimately `100644`). Verify `git ls-files -s` → `100755`.
- [ ] 3.14 `shellcheck` clean.

### Phase 4 — Wire the consumer

> **Self-hosting hazard — read before starting this phase.** Wiring `settings.json` arms the hook on
> the `/work` session's **own** next SessionStart. A defect here does not fail a test; it degrades
> the session doing the work, and on `clear`/`compact` it re-fires. Mitigations, all required:
> (a) do **not** start Phase 4 until 3.14 is green and 4.3's manual exercise has passed;
> (b) `export SOLEUR_DISABLE_MEMORY_BACKSTOP=1` in the `/work` shell for the remainder of the
> session, so the agent's own sessions are unaffected until Phase 7 is green;
> (c) the fail-open design (`exit 0` everywhere, no `set -e`) means the worst case is *no
> protection*, never a blocked session — that property is what makes this phase safe to attempt at
> all, and it is why 3.1 and 3.3 are not optional.

- [ ] 4.1 Add to the existing `SessionStart` block in `.claude/settings.json` (matcher
      `startup|resume|clear|compact`) using the **exact sibling shape**:
      `"command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/memory-backstop.sh"` — bare path, no
      interpreter, no arguments. Append after `supabase-loopback-warn.sh`.
- [ ] 4.2 Re-run the Phase 1 gate: it must now cover **34** paths and stay green.
- [ ] 4.3 Exercise the production invocation once before relying on it — reconstruct the command
      string **from `settings.json`**, substitute `$CLAUDE_PROJECT_DIR`, run it with a SessionStart
      payload on stdin, then read back `systemctl --user status soleur-agent-<pid>.scope` **and**
      `/proc/<mcp-pid>/cgroup` for a live MCP child.

### Phase 5 — AC7 sweep + mutation battery

- [ ] 5.1 Implement the before/after sweep (T7): snapshot `memory.{high,max,swap.max,low,min}` for
      **every** cgroup under `/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/`
      recursively, plus a directory inventory, plus a checksum of `~/.config/systemd/user.control/`.
- [ ] 5.2 Run the mutation battery M1–M9; **every mutant killed by a named assertion**, recorded per
      mutant. A surviving mutant means the assertion is decorative.
- [ ] 5.3 Explicitly verify the mutant the issue names: **capping the parent slice**
      (`SetUnitProperties("app.slice"…)` / `…("user@<uid>.service"…)`) must fail the sweep. This is
      the defeat that beat #7151's single-filename check.

### Phase 6 — ADR + C4 + docs

- [ ] 6.1 Write `ADR-155-…` per [§ Architecture Decision](#architecture-decision-adrc4), including the
      full Alternatives table.
- [ ] 6.2 Apply the five `.c4` edits; run `apps/web-platform/test/c4-code-syntax.test.ts` and
      `c4-render.test.ts`.
- [ ] 6.3 Add the hook's rows to `.claude/hooks/README.md` (SessionStart table, telemetry-sinks list,
      and the kill-switch list alongside `SOLEUR_DISABLE_*` siblings), documenting the
      `systemctl --user stop soleur.slice` fallback kill path from [D3](#d3--ac3-the-terminals-kill-switch).
- [ ] 6.4 Add `.claude/.memory-backstop*` to `.gitignore` — the repo uses a **per-sink wildcard** line
      (`.claude/.rule-incidents*`, `.claude/.skill-invocations*`), so a new sink needs a new line or
      the log becomes a tracked file on first run.

### Phase 7 — Verification

- [ ] 7.1 `bash scripts/test-all.sh` fully green. Both new suites are auto-discovered by the
      `.claude/hooks/*.test.sh` glob — **no `run_suite` line is needed or wanted** (`scripts/*.test.sh`
      is the surface requiring explicit registration; putting these there would create an orphan that
      never gates).
- [ ] 7.2 Record the **live arm** on the operator's box into the PR body: `systemctl --user
      list-units 'soleur-*' --all`, the slice's four properties, `oomctl`, an MCP child's cgroup, and
      the last log line. CI's live arm is SKIPPED by construction; this is the evidence the code path
      ran for real.
- [ ] 7.3 Kill-mechanism proof at **256 MB**, never at the real cap — the incident learning's sharp
      edge: *"verifying that a memory cap kills does not require allocating the cap."*
- [ ] 7.4 PR body states the residual verbatim (~45 s of 100 % CPU under a cap), the
      [D11](#d11--pre-existing-uncapped-sessions-self-only-adoption) gap (**the fleet cap's
      denominator is wrong until every session cycles**), and the
      [D3](#d3--ac3-the-terminals-kill-switch) `active (abandoned)` hole. `Closes #7166`.

---

## Files to Create / Edit

### Files to Create

| Path | Purpose |
|---|---|
| `.claude/hooks/memory-backstop.sh` | The hook. **Must be committed `100755`.** |
| `.claude/hooks/memory-backstop.test.sh` | Behavioural suite + AC7 sweep + mutation battery. Auto-discovered. |
| `.claude/hooks/settings-hook-exec-bit.test.sh` | AC1 class gate over every hook named in `settings.json`. Auto-discovered. |
| `knowledge-base/engineering/architecture/decisions/ADR-155-memory-backstop-via-systemd-transient-scopes.md` | Ordinal provisional; see the collision-sweep note. |

### Files to Edit

| Path | Change |
|---|---|
| `.claude/settings.json` | Append the hook to the existing `SessionStart` block, sibling-exact shape. |
| `.claude/hooks/README.md` | SessionStart row, telemetry-sink row, kill-switch row, fallback kill path. |
| `.gitignore` | Add `.claude/.memory-backstop*` (per-sink wildcard convention). |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | New external `systemdUser`; two new relationships; amend the `hooks` description. |
| `knowledge-base/engineering/architecture/diagrams/views.c4` | Add `systemdUser` to the `context` and `containers` include lists. |

**Not edited, deliberately:** `scripts/test-all.sh` (the `.claude/hooks/*.test.sh` glob already covers
both suites), `scripts/followthrough-exec-bit.test.sh` (scope pinned; widening goes RED on five
pre-existing `100644` files), and `plugins/soleur/hooks/hooks.json` (**the shipped plugin surface** —
touching it changes the blast radius, see [D12](#d12--blast-radius-a-documented-disagreement)).

---

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `git ls-files -s .claude/hooks/memory-backstop.sh` reports **`100755`**, and
      `settings-hook-exec-bit.test.sh` asserts index mode `100755` for **every** hook path parsed out
      of `.claude/settings.json` across all hook events (**34** after this PR), with an empty-listing
      guard and a cardinality floor of 25. Proven non-vacuous by flipping one hook to `100644` in a
      scratch copy and observing RED.
- [ ] **AC2** The suite invokes the hook through the **command string reconstructed from
      `settings.json`** (`$CLAUDE_PROJECT_DIR` substituted, bare path, direct exec) — **not**
      `bash <hook>`. A test asserts that running the hook with the executable bit cleared in a scratch
      copy **fails**, proving the invocation honours the mode bit.
- [ ] **AC3** (a) `systemctl --user show soleur-agent-<pid>.scope -p BindsTo` equals the terminal
      scope discovered from `/proc/<claude-pid>/cgroup`; **and** (b) in a synthetic parent/child pair,
      stopping the parent leaves the child's PID **dead** and the child unit **absent**. Both
      required — (a) alone would not have caught #7151's escape.
- [ ] **AC4** A fleet-wide bound exists on `soleur-agents.slice` (`MemoryHigh=17179869184`,
      `MemoryMax=21474836480`, `MemorySwapMax=0`), read back from the **kernel files** not only
      `systemctl show`, and asserted with **two concurrent synthetic sessions**: with both scopes
      live, the slice's `memory.current` reflects both and its caps are unchanged by the second
      adoption.
- [ ] **AC5** `MemorySwapMax=0` read back from `memory.swap.max` on **both** the scope and the slice.
- [ ] **AC6** With `SOLEUR_MEMORY_BACKSTOP_TEST_MODE` **unset**, setting
      `SOLEUR_MEMORY_BACKSTOP_TARGET_PID` and `…_SCOPE_MAX_BYTES=0` has **no effect** (identity check
      still runs, cap unchanged). With the flag set, values outside the validated bands are
      **refused** — nothing applied, `outcome=refused reason=cap_out_of_range` logged.
- [ ] **AC7** A before/after **filesystem sweep** over every cgroup under
      `/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/` shows
      `memory.{high,max,swap.max,low,min}` changes **only** on the hook's own scope and its own slice
      chain, **no new cgroup directory** outside that chain, and `~/.config/systemd/user.control/`
      **byte-identical** before and after. Mutants "cap `app.slice`", "cap `user@<uid>.service`" and
      "drop `runtime=true`" each turn it RED.
- [ ] **AC8** `OOMPolicy` reads back **`continue`** and `memory.oom.group` **`0`** on the scope. A
      mutant omitting `OOMPolicy` is killed by this (the default is `stop`, which would kill `claude`).
- [ ] **AC9** The hook **fails open** — `exit 0`, one `outcome=skipped` line with a distinct `reason`
      — for each of: `busctl` absent, no bus socket, `claude` PID undiscoverable, cgroup basename not
      a `.scope`, `SOLEUR_DISABLE_MEMORY_BACKSTOP=1`. Each a separate named test.
- [ ] **AC10** Idempotency: three runs for the same PID yield exactly one `soleur-agent-<pid>.scope`
      with caps **refreshed not duplicated**, and the `BindsTo` target **unchanged** on re-entry —
      proving the hook does not re-derive the terminal scope from its own scope.
- [ ] **AC11** **Observable effect, not exit 0:** after adoption, **every** PID in the collected tree
      — including a live MCP child — has `/proc/<pid>/cgroup` equal to the new scope. A mutant that
      adopts only `claude`'s own PID is killed by this.
- [ ] **AC12** `bash scripts/test-all.sh` fully green, its log showing both new suites ran. This runs
      the **suite's own invocation**, not a hand-enumerated subset.
- [ ] **AC13** Mutation battery M1–M9 run, **every mutant killed**, killing assertion named per mutant
      in the PR body.
- [ ] **AC14** `ADR-155-…` exists with `## Decision` and an `## Alternatives Considered` naming
      raw-cgroup writes, `ulimit -v`, `memory.high`-only, `oom_score_adj`, **the `soleur-claude`
      wrapper**, and the static slice unit file — each with the measurement that refuted it. The five
      `.c4` edits applied; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- [ ] **AC15** `ManagedOOMPreference` reads back **`avoid`** on `soleur-agents.slice`, and `oomctl`
      output before/after is recorded in the PR body showing no soleur cgroup as a kill candidate.
- [ ] **AC16** The PR body records: live-arm evidence (7.2), the measured baseline the cap arithmetic
      rests on, the residual (~45 s of 100 % CPU), the D11 denominator gap, and the D3
      `active (abandoned)` hole. `Closes #7166`.

### Post-merge (operator)

**None.** Merging is the complete deployment. See [§ Infrastructure (IaC)](#infrastructure-iac).

---

## Test Scenarios

**Pure-fixture arm (always runs, including CI with no systemd bus)**

| # | Scenario | Assertion |
|---|---|---|
| T1 | `settings.json` parse | 34 paths derived; all tracked; all `100755`; empty-listing guard fires on a mangled filter; floor 25 |
| T2 | Cap range validation | each of four values rejected below floor and above ceiling; accepted inside; refusal applies nothing |
| T3 | Test-mode gating | with the master flag unset, every injection variable is inert (AC6) |
| T4 | PPid walk | a synthetic `/proc` fixture whose ancestor `comm` contains a space parses correctly; the `stat`-field-4 form fails the same fixture |
| T5 | Identity guards | empty `exe` readlink ⇒ **no adoption** (not "keep walking"); PID 1 / PID 0 / self rejected; the matching identity signal is logged |
| T6 | Fail-open branches | five distinct `reason` enums; `exit 0`; no `systemMessage` (AC9) |
| T7 | stdout hygiene | the hook's stdout on the success path contains **no** `busctl` job object path |

**Live arm (requires a user systemd bus; SKIPPED loudly otherwise)**

| # | Scenario | Assertion |
|---|---|---|
| T8 | Adoption | scope exists; `MemoryHigh/MemoryMax/MemorySwapMax/OOMPolicy` read back from **kernel files**; `memory.oom.group=0` (AC5, AC8) |
| T9 | **Tree adoption** | every descendant PID's cgroup equals the new scope (AC11) |
| T10 | **AC7 sweep** | snapshot → run → snapshot; only own-scope + own-slice-chain deltas; no foreign cgroup dir; `user.control` byte-identical |
| T11 | Kill switch | synthetic parent + `BindsTo`-bound child; `stop` parent ⇒ child PID dead, child unit gone (AC3) |
| T12 | Fleet bound, **two sessions** | two synthetic scopes in `soleurtest-agents.slice`; slice caps intact; `memory.current` reflects both (AC4) |
| T13 | `ManagedOOMPreference` | reads back `avoid` on the slice (AC15) |
| T14 | Kill mechanism | a **256 MB** scope; bounded allocator inside; `memory.events` `oom_kill ≥ 1`; the *scope* survives (`OOMPolicy=continue`) while the allocator dies. **Never at the real cap.** |
| T15 | Idempotency | three runs ⇒ one scope, refreshed caps, unchanged `BindsTo` (AC10) |
| T16 | Kill attribution | seed a non-zero `oom_kill` on a synthetic scope; assert the re-entry `systemMessage` names the cap and the raise-command |

**Mutation battery**

| # | Mutation | Must be killed by |
|---|---|---|
| M1 | Commit the hook `100644` | T1 / AC1 index-mode assertion |
| M2 | Drop `OOMPolicy=continue` | T8 / AC8 |
| M3 | Drop `MemorySwapMax` | T8 / AC5 |
| M4 | Drop `BindsTo`/`After` | T11 **behavioural** arm (the unit-level check alone must NOT suffice) |
| M5 | `SetUnitProperties("app.slice", …)` — **cap the parent slice** | T10 sweep (the mutant that defeated #7151's check) |
| M6 | Drop `runtime=true` (persistent drop-in) | T10 `user.control` byte-identical check |
| M7 | Read `…_TARGET_PID` outside the test-mode branch | T3 / AC6 |
| M8 | Adopt only `claude`'s own PID (drop the tree) | T9 / AC11 |
| M9 | Drop `ManagedOOMPreference=avoid` | T13 / AC15 |

---

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | **`systemd-oomd` SIGKILLs the whole `soleur.slice`.** It is a userspace killer that ignores `OOMPolicy`, its candidate set is the monitored cgroup's direct children, and `MemorySwapMax=0` makes our slice the most attractive victim. | `ManagedOOMPreference=avoid` on the slice (G17), asserted by AC15, with `oomctl` before/after in the PR body. Residual uncertainty (what arms oomd's monitoring) is disclosed, not resolved — which is why `avoid` is set rather than skipped. |
| R2 | **The cap kills honest work.** | `MemoryHigh` 6 GiB is 1.56× the measured 3.85 GiB concurrent honest peak and throttles first; `MemoryMax` 7 GiB is ~1.8× it. The kill is attributed to a **named unit with its cap printed**, and [D9](#d9--idempotency-re-entry-and-kill-attribution) surfaces a plain-language post-mortem naming the one-line raise command. Raising is a one-integer change re-applied on the next SessionStart. |
| R3 | **Fleet slice kills a bystander.** At slice `MemoryMax` the kernel kills the largest task in the subtree — probabilistically the offender, **not guaranteed**. | The fleet's working control is non-lethal `MemoryHigh` (16 GiB, above the four-concurrent-`tsc` case); `MemoryMax` 20 GiB requires three simultaneously-maxed sessions and is a genuine last resort. Both reviews converged on this ordering. |
| R4 | **`MemoryHigh` degenerates with swap at 0** into refault thrash that reads as a hang. | Acknowledged in [D2](#d2--memoryhigh-vs-memorymax); `MemoryMax` is the actual backstop, and `high` is set **above** routine load so it is a brake, not a tax. |
| R5 | **`BindsTo` never fires on an `active (abandoned)` terminal scope.** | Disclosed in [D3](#d3--ac3-the-terminals-kill-switch); `BindsTo` is not the sole mechanism — `systemctl --user stop soleur.slice` is documented in the README and named in the first-apply message. |
| R6 | **Charge does not migrate**, so caps under-count by each session's RSS at adoption (~0.5 GiB). | Carried through the [D1](#d1--cap-values) arithmetic; the `< 9.5 GB` inequality survives with a 1.5 GB margin. |
| R7 | **The fleet cap's denominator is wrong until every session cycles** — with 12 sessions live it is close to meaningless on first merge. | Stated plainly in [D11](#d11--pre-existing-uncapped-sessions-self-only-adoption) and required in the PR body (AC16). Convergence via `resume|clear|compact`. |
| R8 | **Slices linger** after their last scope exits. | True (G11), harmless (a slice holds no processes). The plan does not claim "everything self-cleans". |
| R9 | **CI cannot exercise the live arm**, so the assertions that matter most are SKIPPED there. | `RESULT: … [live: SKIPPED]` makes vacuity visible; AC16 requires live-arm evidence from the operator's box. |
| R10 | **The hook itself becomes the incident.** | `exit 0` on every path; no `set -e`; `timeout` on every external call; stdout redirected; five named fail-open branches each with a test; a one-token full disable. It can decline to protect; it cannot block. |
| R11 | **Contributors get caps they never asked for** (the blocking engineering objection). | [D12](#d12--blast-radius-a-documented-disagreement): `SOLEUR_DISABLE_MEMORY_BACKSTOP=1`, the repo's existing convention for four sibling hooks. Promotion to the shipped plugin surface is scoped out and flagged as requiring threshold revalidation. |
| R12 | **ADR-155 ordinal collision** with a sibling PR. | `/ship`'s collision gate; the renumber sweep across plan + tasks + AC14 is named explicitly. |
| R13 | The cap arithmetic rests on a **one-moment** baseline. | Phase 0.7 re-measures and records it in the PR body; a materially different baseline is a replan signal. |

---

## Non-Goals / Out of Scope

Each deferral below needs a **tracking issue** filed with: what was deferred, why, and the
re-evaluation criterion.

- **#7164** — `eval` over `jq @sh` in 10 PreToolUse hooks (a confirmed RCE, pre-existing on `main`,
  surfaced by the same #7151 review). **Already filed.** A security fix across 10 hooks does not
  belong in a memory-backstop PR.
- **#7165** — rewriting `grep` → `command grep` via PreToolUse `updatedInput`. **Already filed.** That
  is the *lexical* layer that prevents the known runaway; this plan is the *resource* layer that
  bounds any runaway, predicted or not. Complements — the backstop must not be gated on it.
- **Sweeping every `claude` PID on the box.** Deferred per
  [D11](#d11--pre-existing-uncapped-sessions-self-only-adoption). *Why:* each PID must bind to its
  **own** terminal scope, and it races concurrent SessionStarts. *Re-evaluate:* after the self-only
  hook has run two weeks with zero `outcome=refused` and zero honest-work kills in
  `.claude/.memory-backstop.jsonl`.
- **Promoting the hook into `plugins/soleur/hooks/hooks.json`** (the shipped plugin surface).
  *Why:* changes the blast radius from contributor clones to every downstream Soleur user and
  **requires revalidation of the brand-survival threshold** ([D12](#d12--blast-radius-a-documented-disagreement)).
  *Re-evaluate:* when beta users exist and the hook has a clean local track record.
- **An `operator-digest` proof-of-life line** ("Memory backstop: active on `<host>`, last applied
  `<date>`, N sessions capped"). *Why:* widens the diff into a skill; the edge-triggered
  `systemMessage` covers the first-apply and regression cases. *Re-evaluate:* if the operator reports
  uncertainty about whether the backstop is live.
  *(Note: the near-miss signal originally listed here has been **un-deferred** and moved into
  [D9](#d9--idempotency-re-entry-and-kill-attribution) — `memory.events` counters are cumulative, so
  no sampling mechanism is needed.)*
- **CPU bounding (`CPUQuota=`).** The residual is ~45 s of 100 % CPU on one core, which does not
  freeze the box — memory and swap exhaustion did. A CPU quota would slow every honest build to buy
  back a symptom nobody reported. **Explicitly rejected, not overlooked.**
- **A `SessionEnd` hook.** Unnecessary: transient scopes self-clean on last-process exit (G11), which
  is the leak #7151 had. No `SessionEnd` event is configured today and this plan does not add one.
- **macOS / non-systemd support.** The hook fails open there by design. A launchd equivalent is a
  different mechanism and a different plan.

---

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6.** It is filled; do not hollow it out.
- **`OOMPolicy` defaults to `stop` on transient scopes.** The single most dangerous default in the
  design: without an explicit `continue`, systemd stops the entire scope on any OOM — killing
  `claude` and losing the session the backstop exists to protect. Measured (G8); AC8 pins it.
- **`systemd-oomd` ignores every containment property you chose.** It is a *userspace* SIGKILL of an
  entire cgroup, and creating `soleur.slice` hands it a single fleet-sized target. `OOMPolicy` and
  `memory.oom.group` do not apply to it. `ManagedOOMPreference=avoid` is the only lever (G16, G17).
- **`systemctl --user set-property` without `--runtime` permanently mutates
  `~/.config/systemd/user.control/`.** The issue body states the opposite. Use D-Bus
  `SetUnitProperties(…, runtime=true, …)` (G6).
- **`readlink /proc/<pid>/exe` returns empty, not an error, for an exited process.** A PID walk that
  treats "no match" as "keep walking" can adopt `warp-terminal` or the login shell under a 7 GiB cap
  bound to itself. Require a **positive** match and adopt nothing on failure.
- **`busctl call` prints the job object path on stdout, and a SessionStart hook's stdout is injected
  into session context.** Redirect it, or every session begins with
  `o "/org/freedesktop/systemd1/job/…"` in its context window.
- **Never use `pgrep -f <pattern>` to capture probe PIDs.** The pattern matches the probing shell's
  own command line and yields a false result — this produced a false "multi-PID adoption doesn't
  work" reading during plan-time probing (G15). Use `$!`.
- **`chmod` the exact path, never a glob.** A glob `chmod` silently flips other tracked modes in a
  worktree, and five `.claude/hooks/**` files are legitimately `100644`. Use
  `git update-index --chmod=+x <exact path>`.
- **Do not put the new suites in `scripts/`.** `scripts/*.test.sh` is **not** auto-globbed by
  `scripts/test-all.sh` — each needs an explicit `run_suite` line, and a missing line makes the suite
  an orphan that never gates. `.claude/hooks/*.test.sh` **is** auto-globbed.
- **Never probe with a live `claude` PID, and never test a 7 GiB cap by allocating 7 GiB.** The kill
  mechanism is provable in a 256 MB scope on the same kernel path with a bounded blast radius.
- **A green suite is not evidence the hook ran.** That is the entire lesson of #7151: 26 green
  assertions, a 7/7 mutation battery, a live kernel readback and 243/243 CI all sat on top of a hook
  that could not execute. Verify through the invocation `settings.json` uses, and assert an
  **observable effect** (cgroup membership), never `exit 0`.
