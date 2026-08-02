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

## Enhancement Summary

**Deepened on:** 2026-08-02
**Panel:** `cto`, `cpo`, `code-simplicity-reviewer`, `spec-flow-analyzer`
**Live-box probes run at plan time:** 21 (G1–G21), all on systemd 259, no sudo

### Key improvements

1. **A blocking gap was found and closed before `/work`:** `AttachProcessesToUnit` — the only
   sanctioned way to move a live PID into an *existing* unit — **fails on a non-delegated scope**
   (`Process migration not available on non-delegated units`). The re-entry re-sweep that D6 and D9
   both promise was therefore **unimplementable as originally specified**, and the only other route
   is #7151's single-writer violation. `Delegate=true` verified as the fix (G21).
2. **A design-changing external interaction was found that the issue never mentions:**
   `systemd-oomd` is active with `ManagedOOMMemoryPressure=kill`, swap is already at 94 %, and its
   candidate set is the monitored cgroup's *direct children* — so creating `soleur.slice` would make
   **the whole fleet a single oomd victim**. `ManagedOOMPreference=avoid` verified as accepted (G17),
   with its runtime efficacy honestly recorded as **unvalidated** ([D7](#d7--systemd-oomd)).
3. **A self-hosting hazard was closed:** `compact` fires *automatically*, so wiring `settings.json`
   mid-implementation self-arms the hook against the `/work` session. Phase 4 now runs **last**, and
   the previously-proposed mitigation is documented as a **no-op** (an `export` from a Bash tool call
   never reaches a hook).
4. **Caps were re-derived against measured concurrency** rather than idle RSS — per-session
   4→6 GiB high / 6→7 GiB max, fleet 12→16 GiB high / 16→20 GiB max — after the engineering review
   showed the originals sat *below* routine load (`claude` + `tsc` + `vitest` = 3.85 GiB in one scope).
5. **The test-injection seam was deleted rather than defended.** A sourced-function + `main` guard
   makes #7151's `TARGET_PID` defect **unrepresentable**, and removes an AC/scenario/mutant triple.
6. **AC17 was added** — nothing in the plan asserted that the *real Claude Code runtime* ever invoked
   the hook. AC1/AC2/AC12 and the live-arm evidence were jointly satisfiable with the runtime never
   running it once: #7151 verbatim, one layer up.

### New considerations discovered

- `memory.events` counters are **cumulative and never reset**, so attribution must fire on *increase*
  — a non-zero test re-emits the same post-mortem forever. It also makes the near-miss signal free,
  which reversed an earlier deferral in this plan.
- `T14` as first written was **self-defeating** (the scope self-cleans before `memory.events` can be
  read) and `T16` was **impossible** (`memory.events` is read-only kernel state).
- `AC11` was **self-referential** — collection and assertion shared one source of truth, so a
  partial-collection mutant would have survived the entire battery.
- 14 active worktrees on this box means mixed hook versions will **flap the shared slice** once caps
  are tuned; the log must record `slice_*_before` for that to be detectable at all.

---

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
| G21 | **Re-entry re-sweep — a blocking gap, found and closed at plan review** | `AttachProcessesToUnit` (the only sanctioned way to move a live PID into an **existing** unit) **fails** on a default transient scope: `Call failed: Process migration not available on non-delegated units.` (rc=1, PID unmoved). Adding **`Delegate=true`** to the `StartTransientUnit` property list fixes it: `attach rc=0`, the PID moves into the scope, `Delegate=yes`, and `MemoryMax` still enforces at the kernel (`memory.max=7516192768`). Without this, [D6](#d6--adopt-the-tree-not-just-the-pid)'s and [D9](#d9--idempotency-re-entry-and-kill-attribution)'s promised re-sweep is **unimplementable** — `StartTransientUnit` refuses an existing unit (G9) and a raw `cgroup.procs` write is #7151's single-writer violation. |

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

> **Rejected at plan review: "drop the fleet slice's memory properties entirely."** The simplicity
> review argued the fleet caps are unreachable in practice (three simultaneous runaways), admittedly
> weak on first merge ([D11](#d11--pre-existing-uncapped-sessions-self-only-adoption)), and the
> source of the oomd exposure — and that cutting them would remove ~1/3 of the acceptance surface.
> The engineering trade is real, but **the aggregate bound is a hard requirement, not an
> optimisation**: "no aggregate bound" is *defect #4 of five* in the issue's own indictment of
> #7151 ("per-pid keying means N sessions × 12 GB on a 31 GB box; two honest 11 GB sessions pass and
> reproduce the freeze"), and issue **AC4** requires a fleet-wide bound *asserted with more than one
> session*. Cutting it would ship the exact defect this issue exists to fix, and would fail AC4 on
> its face. The oomd half of the argument is separately answered in [D7](#d7--systemd-oomd): the
> exposure comes from the slice's existence, not its caps.
>
> What *was* taken from that review: the fleet's working control is the non-lethal `MemoryHigh`,
> `MemoryMax` is an explicit last resort, and AC15's vacuous `oomctl` clause is cut.

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

**The re-sweep needs `Delegate=true` — this was a blocking gap (G21).** On re-entry the scope already
exists, so `StartTransientUnit` refuses it (G9) and new descendants must be moved with
`AttachProcessesToUnit`. That call **fails on a non-delegated unit**
(`Process migration not available on non-delegated units`), which made the re-sweep that both this
decision and [D9](#d9--idempotency-re-entry-and-kill-attribution) promise **unimplementable as
originally specified** — and the only other route, writing `cgroup.procs` directly, is exactly
#7151's single-writer violation. Adding `Delegate=true` to the `StartTransientUnit` property list
makes `AttachProcessesToUnit` succeed while the kernel still enforces `MemoryMax` (measured).

This matters beyond tidiness: the re-sweep is what [D11](#d11--pre-existing-uncapped-sessions-self-only-adoption)
relies on for convergence and what this decision relies on to close the MCP race on `resume|clear|compact`.
A mutant that drops the re-sweep would otherwise survive the entire battery, because AC10's three
back-to-back runs use a **static** tree — see M8 in the revised battery.

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

**Not circular — the exposure comes from the slice's *existence*, not from its caps.** Plan review
proposed dropping the slice's memory properties on the grounds that they are "the sole cause of the
plan's most dangerous finding". That reasoning does not survive: the per-session scopes must live in
*some* cgroup, and placing them under `soleur-agents.slice` is what makes the documented
`systemctl --user stop soleur.slice` kill path work and keeps them out of `app.slice` (where #7151's
residue was found, G19). The slice therefore exists either way, and oomd's candidate set is the same
either way. The caps only *worsen* the exposure marginally, via the PSI that `MemorySwapMax=0`
raises. So `ManagedOOMPreference=avoid` is required **regardless** of whether caps are set — it is
not an unverifiable mitigation for a self-inflicted risk.

**Honest caveat, carried into the ADR rather than papered over:** `oomctl` currently lists **zero**
monitored cgroups, so the policy is armed at unit level but inert at runtime, and what flips it on
was not determined. **The `avoid` property readback therefore proves a string was transmitted, not
that behaviour changed** — by this plan's own G15 standard that is a partially un-run instrument.
That uncertainty is the reason to set `avoid`, not a reason to skip it, but the limitation must be
stated plainly in ADR-155 and **must not be dressed up as a verified mitigation.** Accordingly the
`oomctl`-before/after PR-body clause is cut from AC15: with zero monitored cgroups it returns the
same result on every arm.

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
| `oom_kill` **increased** since the last recorded value | **Kill attribution.** Plain-language `systemMessage`: what was stopped, that uncommitted work in that command may be lost, the cap that was hit, `memory.peak`, and the remedies in R9 order (narrow first). |
| `high` **increased**, `oom_kill` unchanged | **Near-miss.** "This session crossed its 6 GiB brake N times (peak X GiB) but was not killed" — turns cap-tuning into an evidence-driven change and warns *before* a first kill. |

**On *increase*, not on non-zero — these counters never reset.** `oom_kill` and `high` are
**monotonic** for the life of the cgroup. A non-zero test would re-emit the *same* post-mortem on
every subsequent SessionStart forever, for a kill the operator already saw — flatly contradicting the
Observability block's `EDGE-TRIGGERED only … Never per-session`. Persist the last-seen counts in the
jsonl line and compare. T17 pins this by running re-entry twice against an unchanged counter and
asserting **exactly one** message.

**The attribution message must not claim causation.** At slice `MemoryMax` (R3's bystander case) the
victim can sit in *another* session's scope, so a message may be delivered to a session that did not
cause the kill. One sentence in the PR body, and message wording that says what happened, not who
did it.

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

### D10 — No test seams at all; two-sided cap validation

**Revised at plan review.** An earlier draft gated six test-injection variables behind a
`SOLEUR_MEMORY_BACKSTOP_TEST_MODE=1` master flag, and then needed **three artifacts** (an AC, a test
scenario and a mutant) to prove the master gate held. That defends against #7151's
`SOLEUR_MEMORY_CAP_PID` defect; it does not eliminate it.

**Adopted instead: the hook has no production-reachable injection path whatsoever.** Split the file
into functions plus a `main`, guarded by the standard idiom:

```sh
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
```

Tests **source** the hook and call `validate_caps`, `discover_claude_pid`, `collect_descendants`
directly with ordinary arguments. Production **execs** it, so `main` runs and nothing is injectable —
`TARGET_PID` and `BYTES=0` become **unrepresentable rather than defended-against**. `set -uo pipefail`
moves inside `main` so sourcing does not leak shell options into the test harness.

This **strengthens** issue AC6 rather than skipping it: "test-injection seams are gated behind an
explicit test-mode flag" is satisfied *a fortiori* by having no seams to gate. Cap floor-validation
(below) is unchanged and is now directly unit-testable by calling `validate_caps` with out-of-range
arguments — no environment manipulation at all.

**The one env var that remains** is `SOLEUR_DISABLE_MEMORY_BACKSTOP=1` — a user-facing kill switch
matching four sibling hooks ([D12](#d12--blast-radius-a-documented-disagreement)), not a test seam.

**Test split:** source-and-call for every pure-function assertion (cap validation, PPid walk,
identity guards, stdout hygiene); **one** end-to-end exec through the reconstructed `settings.json`
command string for AC2/AC11. Neither path needs an injection variable.

*(This also resolved a live contradiction the review surfaced: AC4 asserted the **production** slice
byte constants while the seam design routed tests to `soleurtest-agents.slice` with **injected**
values — AC4 was unsatisfiable alongside the seam. See AC4's revised split.)*

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

## Research Insights — Precedent Diff (deepen-plan Phase 4.4)

Every pattern-bound behaviour this plan prescribes has an in-repo precedent. Each was `git grep`-ed
and read; **none is novel**, which is the desired outcome — a novel pattern here would need
scrutiny the plan does not budget for.

| Prescribed behaviour | Canonical precedent | Adopt verbatim |
|---|---|---|
| **`flock` around the apply (R2)** | `.claude/hooks/agent-token-tee.sh` — `flock -w 5 -x 9` with an explicit **drop sentinel** on timeout (`_emit_drop_sentinel … "flock_timeout"`) and the comment *"never blocks tool dispatch"*. Its header also records that callers must canonicalize the repo root via `cd -P` + `pwd -P` so a symlinked path does not produce **two disjoint flock inodes**. | Yes — including the timeout value, the drop-sentinel-on-timeout shape (a silent drop is what the plan is trying to avoid everywhere else), and the `cd -P`/`pwd -P` canonicalization. This is a **stronger precedent than `skill-invocation-logger.sh`**, which appends under `flock` but has no timeout/drop path. |
| **Operator-visible message channel** | `.claude/hooks/supabase-loopback-warn.sh` — `jq -n --arg m "$msg" '{systemMessage:$m}'` on **stdout**, with a header stating plain stderr is DISCARDED on an exit-0 hook. | Yes. |
| **`jq`-absent fallback (R8)** | Same file — deliberately `exit 1` when `jq` is missing, *"because exiting 0 here would write the warning to the one sink documented not to work."* | Yes — this is the precedent that makes R8 a correction rather than a preference. |
| **Log rotation** | `.claude/hooks/lib/log-rotation.sh` — `rotate_if_needed`, 5 MB / 30-day defaults, `LOG_ROTATION_DISABLE=1` kill switch, and **exit 0 for both no-op and successful rotation** (fire-and-forget safe). | Yes. |
| **Portable `timeout` guard** | `.claude/hooks/supabase-loopback-warn.sh` — `TO=(); command -v timeout >/dev/null 2>&1 && TO=(timeout 10)`, with a header recording that hardcoding `timeout` made the hook exit 127 on macOS and go **silently dark**. | Yes, at 5 s. |
| **Index-mode exec-bit gate** | `scripts/followthrough-exec-bit.test.sh` — `git ls-files -s`, empty-listing guard, cardinality floor. | Structure yes; **cardinality mechanism no** — replaced with the three-way check in AC1, because a floor cannot catch a filter that drops one hook event. |
| **cgroup / OOM telemetry reads** | `scripts/followthroughs/zot-restart-plateau-6288.sh` reads `memory.max` and `memory.events`; `scripts/zot-restart-loop-alarm.sh` parses cgroup OOM signals. | Yes — `memory.events` as an OOM-attribution source is established practice in this repo. |

**ADR ordinal re-derived from freshly-fetched `origin/main`** (not the branch base, which is the
stale-pick failure mode): highest is **ADR-154**, so **ADR-155 is free**. Still provisional —
`/ship`'s collision gate re-verifies at merge.

**Verified live at deepen time:** every cited issue resolves and carries the state the plan claims
(#7151 CLOSED, #7164/#7165/#7166 OPEN, #2348 OPEN); the single AGENTS rule ID cited
(`hr-all-infrastructure-provisioning-servers`) is ACTIVE in `AGENTS.md`; all five `## Observability`
fields are populated and no `discoverability_test.command` uses `ssh`.

---

## Plan Review Revisions (R1–R12) — binding on `/work`

The findings below came from the plan-review panel and are **requirements, not commentary**. The
larger ones are already folded into the sections they affect (G21, D6, D7, D9, D10, D1, Phase 4,
AC1/AC2/AC4/AC6/AC11/AC12/AC15/AC17/AC18, T14/T16–T19, M1–M7). These are the remainder, each with the
reachable state or defect that motivates it.

| # | Requirement | Motivating defect |
|---|---|---|
| **R1** | **`Delegate=true` on the per-session scope.** | Without it `AttachProcessesToUnit` refuses and the re-entry re-sweep is unimplementable (G21). **Blocking.** |
| **R2** | **Take a per-PID `flock` around discover→apply→log**, non-blocking with a short timeout; on failure log reason `concurrent_apply` and `exit 0`. | No mutual exclusion exists. `startup` then a fast `/clear`, or overlapping `resume`+`compact`, has both invocations reach `SetUnitProperties`, re-sweep different trees, and possibly double-emit the first-apply message; the stamp write is itself racy. Precedent: `.claude/hooks/skill-invocation-logger.sh` appends under `flock` for exactly this reason. |
| **R3** | **D9 row 2 must verify the existing scope is *ours*** before refreshing: its `cgroup.procs` contains our PID **and** its `BindsTo` matches the terminal scope just discovered. Key the scope name on **PID + start time**. | Scopes self-clean only when the **last** process exits (G11), so one orphaned MCP grandchild keeps a stale scope alive; a new `claude` on the recycled PID then refreshes caps on — and adopts its tree into — a dead session's scope, `BindsTo`-bound to the wrong window. |
| **R4** | **Reading start time: split `/proc/<pid>/stat` on the *last* `)` and index from there.** `comm` is the only field that can contain the delimiter. | [D8](#d8--pid-discovery)'s rule "never `awk '{print $4}'` over `stat`" reads as "never touch `stat`" and will otherwise push the implementer to a worse key. |
| **R5** | **New D9 row — stale-but-present `BindsTo`.** On re-entry, if the preserved `BindsTo` target is `not-found` or `inactive`, do **not** preserve it. Prefer the `terminal_scope` recorded in the jsonl at first apply, validated as still-loaded. | `claude` can outlive its terminal scope (tty close, tmux, `nohup`); cgroup membership does not change on re-parenting, so `/proc/<pid>/cgroup` still names the dead scope. Preserving that `BindsTo` with `After=` makes the scope liable to be stopped. |
| **R6** | **New D9 row — unit exists ∧ our PID is not in it.** Re-adopt via `AttachProcessesToUnit`; never merely refresh. | Distinct from R3. Reachable when another worktree's copy of this hook, or an agent's own `systemd-run`, moves the PID. Falling to the refresh branch reports `outcome=applied` while **nothing is capped** — the silent-no-op class this feature exists to eliminate. |
| **R7** | **Log `slice_high_before` / `slice_max_before`** alongside the written values. | **14 active worktrees** on this box, `.claude/hooks/` is per-checkout, and [D5](#d5--fleet-bound-persistence) re-applies slice properties every SessionStart. The moment caps are tuned, old- and new-version sessions flap the **shared** slice. Today the log records only what was written, making the flap invisible. |
| **R8** | **Reconcile the `jq`-absent path with the sibling hook.** Add `no_jq` as a named fail-open reason, and either mirror `supabase-loopback-warn.sh`'s deliberate `exit 1` or emit the JSON via `printf` with manual escaping. | That sibling `exit 1`s when `jq` is absent *precisely because* "stderr is DISCARDED on an exit-0 hook". This plan mandates `exit 0` unconditionally and omits `jq` from AC9's reasons — so on a host without `jq` the OOM post-mortem (the CPO's blocking requirement) is written to a documented-dead sink while the hook reports success. |
| **R9** | **Message ordering: narrow remedy first, fleet-wide last, consequence stated.** The per-session escape is `systemctl --user stop soleur-agent-<pid>.scope`; the raise path is `systemctl --user set-property --runtime soleur-agent-<pid>.scope MemoryHigh=infinity MemoryMax=infinity`. **`--runtime` is mandatory.** | `systemctl --user stop soleur.slice` — named in D3, the first-apply message and the README — **kills every agent session on the box**. A non-technical operator with one bad session runs the documented remedy and loses all twelve. And omitting `--runtime` on the raise path commits the exact persistent-config mutation [D5](#d5--fleet-bound-persistence) rejects (G6). |
| **R10** | **Refusal message must name the variable, the value, the accepted band, and `git checkout -- .claude/hooks/memory-backstop.sh`.** Refusal **always** messages. | The caps are `readonly` constants in a tracked file, so `cap_out_of_range` can essentially only fire after an operator edit. The Observability stamp is keyed on the *limit-set*, so an operator who just changed it gets a **new key with no prior-success stamp** → the regression channel reads false → **silent refusal on exactly the recovery path.** Resolve the contradiction in favour of always-message, and key the regression channel on `last_outcome != applied` from the jsonl, not on a limit-set-inclusive stamp. |
| **R11** | **Add a fourth edge-trigger: never-worked.** On the first SessionStart where the hook is present, a **user bus exists**, and the outcome is `skipped` — emit one message. | The regression channel is defined as "previously succeeded and now fails", so on a machine where it **never** succeeded there is no "previously" and it never fires. A non-standard install (npm-global → `exe` = `/usr/bin/node`) logs `skipped` forever while the operator believes they are protected. The detector is structurally blind to #7151's own class. |
| **R12** | **`SOLEUR_DISABLE_MEMORY_BACKSTOP` must be rendered by the `discoverability_test`,** and the README row must state literally: *if set, you are unprotected and nothing will tell you.* | "No bus" is an environment fact; "disabled" is a decision that ages out of memory. Set once in a shell profile, it leaves the operator permanently unprotected with nothing ever saying so. (This is also the strongest argument for reconsidering the deferred operator-digest proof-of-life line.) |

Two smaller items folded directly: **AC1 also asserts `test -x` on every derived path** (the index and
the on-disk mode diverge under `core.fileMode=false`, on a `noexec` mount, or when a fix lands in the
index but not on disk — and the runtime execs the **on-disk** file); and **AC12 splits into 12a (CI:
green **and** `[live: SKIPPED]` **and** the skipped-count equals the number of live tests, so a
deleted live test is distinguishable from a skipped one) and 12b (operator box: green with
`[live: yes]`, pasted verbatim)**.

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
- [ ] 0.3 Record `free -m` and the `claude` fleet RSS total into the PR body — the
      [D1](#d1--cap-values) arithmetic is only defensible against a stated baseline (this is what
      R13 guards).
- [ ] 0.4 Sweep for orphaned raw cgroup dirs under `app.slice` (G19) and `rmdir` any found — a leaked
      dir makes the AC7 sweep read dirty, so this is a genuine precondition, not a re-measurement.

> **Phase 0 was collapsed from ten probes to four at plan review, and the reason matters.** The
> dropped items (`OOMPolicy` default, `runtime=true` write location, `BindsTo` reap, multi-PID
> adoption, `oomctl`, the AC1 surface audit) each re-verify a G-number measured **the same day on the
> same box**, and each is then verified a *third* time by the live test arm — through the real hook,
> which is strictly better evidence. Re-probing them by hand invites the precise #7151 error of
> **treating a green probe as evidence the hook works**. What survives is only what the live arm
> cannot supply: an environment gate (0.1), a smoke test that the whole approach is viable before
> ~200 lines are written (0.2), the baseline numbers D1's arithmetic depends on (0.3), and a clean
> tree for the AC7 sweep (0.4).

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

### Phase 4 — Wire the consumer — **EXECUTES LAST, after Phase 7** (kept here for diff-ordering readability)

> **Self-hosting hazard — this phase MOVES to after Phase 7. Read why.**
>
> Wiring `settings.json` arms the hook on the `/work` session's **own** next SessionStart, and
> `compact` is **not operator-initiated** — it fires automatically when context fills, which on a
> long `/work` run is near-certain. So the hook self-arms mid-implementation without anyone choosing
> to, against **real** `claude` PIDs with **production** caps, in the window before the AC7 sweep
> (5.1), the mutation battery (5.2) and full verification (7.1) have run. A defect in D8's identity
> walk in that window adopts `warp-terminal` or the login shell under a 7 GiB cap bound to itself —
> the precise catastrophe D8 exists to prevent. It is also self-concealing: if the armed hook kills
> the `/work` session's own tree, **the session that dies is the one holding the uncommitted
> implementation.**
>
> **Resolution: execute this phase after Phase 7.1.** Checked the dependency — 4.2 is the only step
> that needs `settings.json` wired, and it is a **pure static check** (`git ls-files -s` over a
> parsed list) that never arms anything. Nothing forces 4.1 early, so moving it closes the window at
> **zero cost**. Run 4.3 immediately after the moved 4.1.
>
> **A mitigation that does NOT work, recorded so it is not re-attempted:** an earlier draft said
> "`export SOLEUR_DISABLE_MEMORY_BACKSTOP=1` in the `/work` shell". **That is a no-op.** Hooks
> inherit the *Claude Code process* environment, not a Bash-tool subshell's — an `export` from a tool
> call never reaches the hook. If a kill switch is wanted during the window, the only working
> mechanism is the **`env` block already present in `.claude/settings.json`**
> (`{"CLAUDE_CODE_EFFORT_LEVEL": "high"}`), set in the same edit as 4.1 and removed in 7.2.
>
> Also required regardless: **commit Phases 1–3 before arming**, so a self-inflicted session death
> costs nothing. The fail-open design (`exit 0` everywhere, no `set -e`) bounds the worst case to
> *no protection* rather than a blocked session — that is why 3.1 and 3.3 are not optional.

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

- [ ] 5.1 Implement the before/after sweep (T10): snapshot `memory.{high,max,swap.max,low,min}` for
      **every** cgroup under `/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/`
      recursively, plus a directory inventory, plus a checksum of `~/.config/systemd/user.control/`.
- [ ] 5.2 Run the mutation battery M1–M7; **every mutant killed by a named assertion**, recorded per
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
      of `.claude/settings.json` across all hook events. **Cardinality is asserted three ways, not by
      a loose floor** — a floor of 25 against 34 paths would still pass a `jq` filter that silently
      dropped an entire hook event: (a) the listing is non-empty; (b) **every** top-level key under
      `.hooks` contributes ≥ 1 path (so dropping `PostToolUse` fails); (c) the derived count equals
      the count of `"type": "command"` entries in the file — a **self-consistent** check that needs no
      hand-maintained magic number.
- [ ] **AC2** The suite invokes the hook through the **command string reconstructed from
      `settings.json`** (`$CLAUDE_PROJECT_DIR` substituted, bare path, direct exec) — **not**
      `bash <hook>`. A second assertion clears the executable bit on a scratch copy and confirms that
      same invocation **fails**. *This guards the test, not the kernel*: `execve` on a `0644` file
      returning `EACCES` is a POSIX guarantee, but a test harness that silently fell back to
      `bash <hook>` would swallow it — and that fallback is precisely how #7151's 26 green assertions
      sat on a hook that could not run.
- [ ] **AC3** (a) `systemctl --user show soleur-agent-<pid>.scope -p BindsTo` equals the terminal
      scope discovered from `/proc/<claude-pid>/cgroup`; **and** (b) in a synthetic parent/child pair,
      stopping the parent leaves the child's PID **dead** and the child unit **absent**. Both
      required — (a) alone would not have caught #7151's escape.
- [ ] **AC4** A fleet-wide bound exists on `soleur-agents.slice`, asserted in **two separate arms**
      because one arm cannot carry both claims (a contradiction plan review caught in the earlier
      draft):
      **(a) values** — from the single end-to-end exec of the real hook, the **production** slice
      reads `MemoryHigh=17179869184`, `MemoryMax=21474836480`, `MemorySwapMax=0` from the **kernel
      files**, not only `systemctl show`;
      **(b) more than one session** — in the namespaced test slice, two concurrent synthetic scopes
      **each allocate a deterministic fixed amount** before the assertion (never a timing-dependent
      read, since `memory.current` starts at 0 after adoption and only grows with new allocations),
      and the assertion is the **relationship**: the slice's `memory.current` ≥ the sum of both
      allocations, and its caps are unchanged by the second adoption.
- [ ] **AC5** *(merged — `MemorySwapMax=0` is asserted on the slice by AC4(a) and on the scope by
      AC8's readback loop. Retained as a number so downstream references do not shift.)*
- [ ] **AC6** The hook has **no production-reachable injection path at all**
      ([D10](#d10--no-test-seams-at-all-two-sided-cap-validation)): a grep asserts the only
      environment variable it reads is `SOLEUR_DISABLE_MEMORY_BACKSTOP`, and the `main` guard means
      sourcing exposes functions while exec runs `main`. Cap validation is asserted by calling
      `validate_caps` directly with out-of-range arguments — each of the four values rejected below
      floor and above ceiling, accepted inside, and a refusal applying **nothing** with
      `outcome=refused reason=cap_out_of_range` logged.
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
- [ ] **AC11** **Observable effect, not exit 0** — and **not self-referential.** An earlier draft
      asserted "every PID *in the collected tree* is in the scope", where the collection and the
      assertion shared one source of truth: a mutant that collects a *smaller* tree (depth-1 only, or
      an early return at 8 PIDs) satisfies it trivially, so **a partial-collection mutant would have
      survived the whole battery.** Revised: after adoption the test **re-walks `/proc`
      independently** for descendants of the claude PID and asserts (a) that set ⊆ the scope's
      `cgroup.procs`, **and** (b) `|cgroup.procs| == |independently-derived tree|`.
      The test must also **spawn a synthetic grandchild** (`sleep` under `bash` under the target) so
      tree size ≥ 3 **by construction** — the earlier "including a live MCP child" wording made the
      whole D6/G18 headline risk contingent on `playwright-mcp` happening to be running, and passed
      on a tree of size 1 when it was not.
- [ ] **AC12** `scripts/test-all.sh`'s **own log** shows both new suites ran by name
      (`.claude/hooks/memory-backstop.test.sh`, `.claude/hooks/settings-hook-exec-bit.test.sh`).
      Scoped to the **registration** claim — that the `.claude/hooks/*.test.sh` glob actually reaches
      them and neither is an orphan. "Full suite green" is the repo's standing merge gate, not an
      acceptance criterion of this feature.
- [ ] **AC13** *(cut at plan review — a meta-AC asserting that other ACs were asserted. Every mutant
      already names its killing AC in the battery table; that table is the artifact.)*
- [ ] **AC14** `ADR-155-…` exists at the resolved ordinal with `## Decision` and
      `## Alternatives Considered` sections, and the five `.c4` edits are applied with
      `c4-code-syntax.test.ts` + `c4-render.test.ts` passing. *(The six-alternative table with its
      refuting measurements is an authoring instruction in Phase 6.1.1 — no command can check "each
      with the measurement that refuted it", so it is not an AC.)*
- [ ] **AC15** `ManagedOOMPreference` reads back **`avoid`** on `soleur-agents.slice`. *(The
      `oomctl`-before/after clause is **cut**: with zero monitored cgroups it returns the same result
      on every arm — an un-run instrument by this plan's own G15 standard. The limitation is recorded
      in ADR-155 instead; see [D7](#d7--systemd-oomd).)*
- [ ] **AC16** *(cut at plan review — a verbatim restatement of Phase 7.4, checkable by no command.
      The PR-body content requirement lives at 7.4 where it belongs, and 7.4 now requires the
      live-arm evidence be pasted **verbatim as command-plus-output**, not summarised.)*
- [ ] **AC17** **The real Claude Code runtime invoked the hook — not the test harness, not a hand-run.**
      After the (moved) Phase 4.1 wiring, trigger a genuine SessionStart (fresh `claude` launch, or
      `/clear` in a live session) and assert a **new** line in `.claude/.memory-backstop.jsonl` whose
      `pid` is a `claude` PID **not spawned by the test harness or by Phase 4.3**, with `ts`
      postdating the wiring commit.
      **Why this AC exists and why it is the most important one here:** AC1, AC2, AC12 and the
      Phase 7.2 live-arm evidence are *jointly satisfiable in a world where the SessionStart runtime
      never invoked the hook once* — AC2 proves the **test harness's** executor honours the mode bit,
      Phase 4.3 *reconstructs* the command string and runs it **by hand**, and 7.2's
      `systemctl --user list-units` output is produced by whichever exec created the scope, including
      that hand-run. That is #7151 verbatim, one layer up: every green light, and the runtime never
      ran it. AC17 is the only check in the plan that reads the actual invariant.
- [ ] **AC18** **Re-entry re-sweep works** ([D6](#d6--adopt-the-tree-not-just-the-pid), G21). Spawn a
      child **after** first adoption, re-run the hook, and assert the new child's
      `/proc/<pid>/cgroup` equals the scope — proving `Delegate=true` +
      `AttachProcessesToUnit` are wired. AC10's three back-to-back runs use a **static** tree and
      pass against a hook that never re-sweeps, so without AC18 the re-sweep is entirely untested
      while `resume|clear|compact` convergence depends on it.

### Post-merge (operator)

**None.** Merging is the complete deployment. See [§ Infrastructure (IaC)](#infrastructure-iac).

---

## Test Scenarios

**Pure-fixture arm (always runs, including CI with no systemd bus)**

| # | Scenario | Assertion |
|---|---|---|
| T1 | `settings.json` parse | 34 paths derived; all tracked; all `100755`; empty-listing guard fires on a mangled filter; floor 25 |
| T2 | Cap range validation | each of four values rejected below floor and above ceiling; accepted inside; refusal applies nothing |
| T3 | **No injection path** | grep asserts `SOLEUR_DISABLE_MEMORY_BACKSTOP` is the only env var the hook reads; sourcing exposes functions without executing `main` (AC6) |
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
| T14 | Kill mechanism — **rewritten; the original was self-defeating** | Scope at `MemoryHigh=200MB, MemoryMax=256MB, MemorySwapMax=0`. Put a **sentinel `sleep` in the scope first** (standing in for `claude`), *then* the bounded allocator. Assert the **triple**: allocator PID **dead**, sentinel PID **alive**, `oom_kill ≥ 1` read from the **still-live** cgroup. *Why the sentinel:* with the allocator alone the scope empties on its death and **self-cleans (G11)** — the cgroup is gone before `memory.events` can be read, so the original spec could never pass. *Why swap 0:* without it the allocator swaps instead of OOMing. *Why high≠max:* exercises the high→max transition ([D2](#d2--memoryhigh-vs-memorymax)) for free. **This is the only place [D4](#d4--oom-victim-selection)'s behaviour is tested** — AC8 reads properties only. **Never at the real cap.** |
| T15 | Idempotency | three runs ⇒ one scope, refreshed caps, unchanged `BindsTo` (AC10) |
| T16 | Kill attribution — **re-scoped; the original was impossible** | `memory.events` is a **read-only kernel file** and `oom_kill` is a kernel-maintained counter, so "seed a non-zero `oom_kill`" cannot be done. Two arms instead: **(a) live** — chain onto T14, which has already produced a real `oom_kill ≥ 1` with a surviving sentinel; re-run the hook against that scope and assert the `systemMessage`. **(b) fixture (runs in CI)** — the attribution function takes the `memory.events` **path as a function argument**, so a sourced test points it at a temp file containing `oom_kill 3`. *(A path argument, deliberately **not** an env var — [D10](#d10--no-test-seams-at-all-two-sided-cap-validation) removed the injection surface and this must not re-introduce it.)* |
| T17 | **Attribution fires on increase, not on non-zero** | Run re-entry **twice** against an unchanged counter; assert **exactly one** message. `oom_kill` is monotonic and never resets, so a non-zero test re-emits the same post-mortem on every SessionStart forever — contradicting the Observability block's `EDGE-TRIGGERED only … Never per-session`. |
| T18 | **The documented kill path actually reaps** | `systemctl --user stop soleurtest-agents.slice`; assert every scope beneath it is gone and its PIDs dead. Without this the one command a non-technical operator is told to use is untested — and if a scope lands off the expected slice chain it silently does nothing. |
| T19 | **`systemMessage` is well-formed** | On the message path, `jq -e .systemMessage` succeeds against the hook's **stdout**; on the non-message path stdout is **zero bytes**. A malformed message is operationally indistinguishable from "no OOM happened". |

**Mutation battery**

Restructured at plan review. The earlier M2/M3/M9 were **three instances of one mutant shape** —
"a property string was omitted from an array passed to a D-Bus call, and a readback fires" — killed
by the same instrument. They collapse into a single parameterised mutant, and the freed slot goes to
a genuinely uncovered defect (the self-binding bug), which nothing previously mutated.

| # | Mutation | Must be killed by |
|---|---|---|
| M1 | Commit the hook `100644` | T1 / AC1 index-mode assertion |
| M2 | **Omit one declared property** from either D-Bus array — run once per property over `{OOMPolicy, MemorySwapMax, ManagedOOMPreference, MemoryHigh, MemoryMax}` | one readback loop over every declared property: T8 / T13 / AC8, AC4(a), AC15 |
| M3 | Drop `BindsTo`/`After` | T11 **behavioural** arm (the unit-level check alone must NOT suffice) |
| M4 | `SetUnitProperties("app.slice", …)` — **cap the parent slice** | T10 sweep (the mutant that defeated #7151's check) |
| M5 | Drop `runtime=true` (persistent drop-in) | T10 `user.control` byte-identical check — a *different instrument* from M4's subtree-delta check |
| M6 | Adopt only `claude`'s own PID (drop the tree) | T9 / AC11 |
| M7 | **Re-derive the terminal scope on re-entry** (the [D9](#d9--idempotency-re-entry-and-kill-attribution) self-binding bug: the scope binds to *itself*, silently destroying the kill switch) | T15 / AC10 `BindsTo`-unchanged assertion |

*(The former M7 — "read `…_TARGET_PID` outside the test-mode branch" — is **deleted, not moved**:
under [D10](#d10--no-test-seams-at-all-two-sided-cap-validation) there is no test-mode branch and no
injection variable to leak, so the mutant is unrepresentable.)*

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
