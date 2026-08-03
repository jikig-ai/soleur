# ADR-160: Memory backstop via systemd transient scopes

- **Status:** accepted
- **Date:** 2026-08-02
- **Issue:** #7166
- **Supersedes:** the raw-cgroup approach attempted in the PR closed unmerged on 2026-08-01

## Context

On 2026-08-01 a one-line regex search against a single 21 kB markdown file reached
**9.5 GB RSS in 171 s at 99 % CPU and was still climbing**, driving a 31 GB box to
691 MB free with swap at 88.5 %. The operator's terminal crashed, killing **six
concurrent agent sessions** and their in-flight work. There was no guard of any kind.

Agent sessions are long-lived, numerous (10–14 concurrent worktrees on this host),
and run arbitrary tool commands. Host-level resource control is therefore a
first-class property of the agent runtime, not an operational afterthought — and
nothing in the existing ADR corpus governs it. ADR-062 caps a *server-side Docker
container*; that is precedent, not coverage.

A prior attempt shipped a hook that wrote a **raw cgroup v2 directory** and moved the
live `claude` process into it. It was wrong in five independent ways and, decisively,
**never executed once** — it was committed `100644` while `settings.json` invokes hook
paths directly, so every SessionStart died at `execve` with `EACCES`. Its suite was
26/26 green because the suite ran `bash <hook>`, which ignores the mode bit.

## Decision

Adopt the session's process tree into a **systemd transient scope** created over D-Bus
(`StartTransientUnit`), under a shared `soleur-agents.slice` that carries a fleet-wide
bound. systemd remains the **single writer** to the cgroup hierarchy.

| Level | `MemoryHigh` | `MemoryMax` | `MemorySwapMax` | Other |
|---|---|---|---|---|
| per session (`soleur-agent-<pid>.scope`) | 6 GiB | 7 GiB | 0 | `OOMPolicy=continue`, `Delegate=true`, `BindsTo=`/`After=` the terminal's scope |
| fleet (`soleur-agents.slice`) | 16 GiB | 20 GiB | 0 | `ManagedOOMPreference=avoid` (also set on the parent `soleur.slice`, which is the unit systemd-oomd actually selects among) |

Sizing is bounded on both sides against measurements, not intuition. The floor clears
the heaviest honest workload (`claude` + `tsc` + `vitest` = 3.85 GiB concurrent); the
ceiling stays below the observed 9.5 GB harm point after adding back the ~0.5 GiB that
cgroup v2 leaves billed to the old cgroup (charge does not migrate on adoption). The
hook re-validates all four values against a two-sided band on every run and refuses to
apply anything if one is out of range — a cap outside the band is either useless or
dangerous, and a hook that half-applies is worse than one that declines.

**`MemoryHigh` is the working control; `MemoryMax` is the killer.** `high` throttles and
reclaims without killing, which is what makes a *shared* slice viable at all. It is set
deliberately **above** routine load: a brake below routine load is a permanent tax.

**The terminal's kill switch is preserved as a unit dependency, not cgroup
co-membership.** A process is in exactly one cgroup, so a per-session cap necessarily
moves it out of the terminal's scope; `BindsTo=` + `After=` reproduce the reaping
behaviour, verified behaviourally (stop the parent → child PID dead, child unit gone).

**No production-reachable injection path.** The hook is functions plus a `main` guarded
by `BASH_SOURCE == $0`. Tests source it and call functions with ordinary arguments;
where synthetic state is needed they pass a **path argument** (a fake `/proc` root, a
fake `memory.events`). The prior attempt's `SOLEUR_MEMORY_CAP_PID` (which skipped the
identity check) and `SOLEUR_MEMORY_CAP_BYTES=0` (a one-token session kill) are not
defended against — they are unrepresentable.

**The hook verifies rather than assumes.** After applying, it reads back cgroup
membership and logs `outcome=failed reason=adoption_unverified` if the process is not
in the scope it just requested. This is not defensive padding: during implementation a
missing trailing argument made every `StartTransientUnit` call fail silently (stdout
and stderr are both redirected, because `busctl` prints the job object path and a
SessionStart hook's stdout is injected into session context) while the hook reported
`outcome=applied`. That is the prior attempt's failure shape reproduced by a different
route, caught only by this check.

Membership alone is not sufficient, and on the re-entry path it is not even a real
check: that branch is reached only when the process is already in the scope, so
asserting membership there re-asserts the branch's own entry condition. Every `/clear`
and every resume takes that path. So the hook reads back the **properties** at both
levels and logs what was *observed* (`scope_max_after`, `slice_max_after`, …) beside
what was intended, with distinct `scope_caps_unverified` / `fleet_caps_unverified`
outcomes. This matters because `SetUnitProperties` is all-or-nothing: on systemd older
than 247 the unsupported `ManagedOOMPreference` fails the whole call, dropping the
fleet `MemoryMax` **and** `MemorySwapMax=0` with it — silently restoring the
swap-exhaustion half of the incident. A zero exit code does not help either: the call
returns rc=0 for a unit that does not exist yet.

## Consequences

- Merging is the complete deployment. The units are **transient**, created at runtime,
  and self-clean when their last process exits. Nothing is provisioned, nothing is
  written to `/etc`, no `daemon-reload`, no `sudo`, no operator step.
- Slice properties are applied with `runtime=true`, so they land only under
  `/run/user/<uid>/` and a reboot self-heals. `systemctl --user set-property` **without**
  `--runtime` would permanently mutate `~/.config/systemd/user.control/`, which this
  hook has no business doing. A mutant dropping `runtime=true` is caught by a
  byte-identical check on that directory.
- The hook **never blocks a session**: `exit 0` on every path, no `set -e`, `timeout` on
  every external call, eight named fail-open reasons. It can decline to protect; it
  cannot block.
- `.claude/settings.json` and `.claude/hooks/` are git-tracked, so this runs for anyone
  running Claude Code inside a clone of this repo — the operator, contributors, CI. It
  does **not** reach downstream plugin users; the shipped plugin surface
  (`plugins/soleur/hooks/hooks.json`) is untouched. Opt-out is
  `SOLEUR_DISABLE_MEMORY_BACKSTOP=1`, the same mechanism four sibling hooks already use.
  Promoting this hook to the plugin surface would change the blast radius to fleet-wide
  and requires revalidating the brand-survival threshold.

### Known limits, stated rather than smoothed over

- **A cap bounds damage; it does not prevent the CPU burn.** Under a cap the 2026-08-01
  runaway dies by SIGSEGV after ~45 s at 2.7 GB (measured at a 3 GB cap) — `ugrep` does
  not handle allocation failure gracefully. What the cap prevents is the memory-and-swap
  exhaustion that froze the desktop and killed six sessions. CPU bounding (`CPUQuota=`)
  is explicitly rejected: it would slow every honest build to buy back a symptom nobody
  reported.
- **`ManagedOOMPreference=avoid` is armed but its runtime efficacy is UNVALIDATED.**
  `systemd-oomd` is active with `ManagedOOMMemoryPressure=kill` on `user@.service`, and
  its candidate set is the monitored cgroup's *direct children* — so the existence of
  `soleur.slice` hands it a single fleet-sized target, and `MemorySwapMax=0` raises the
  memory PSI that makes our slice an attractive victim. The property is accepted and
  reads back `avoid`, but `oomctl` currently lists **zero** monitored cgroups, so the
  readback proves a string was transmitted, not that behaviour changed. That uncertainty
  is the reason to set it, not a reason to skip it. It must not be presented as verified.
  It is set on **both** `soleur.slice` and `soleur-agents.slice`. Setting it only on the
  latter — as a first cut did — arms it on a unit oomd never consults: the monitored
  cgroup is `user@<uid>.service`, whose direct child is `soleur.slice`. That was a
  targeting error, distinct from the efficacy caveat above.
- **The fleet `MemoryMax` can kill a bystander.** The kernel picks the largest task in the slice subtree, which is usually the one that grew — but not necessarily. A session sitting honestly at 6.9 GiB is the largest task in the slice, so *another* session's growth pushing the fleet to 20 GiB kills the honest session's biggest process. This is why the fleet's working control is the non-lethal `MemoryHigh` and `MemoryMax` is a last resort, and why the attribution message says what happened rather than who caused it.
- **`BindsTo=` does not fire on an `active (abandoned)` terminal scope.** One orphaned
  helper keeps the terminal scope active and the agent scopes survive with no terminal.
  `BindsTo` is therefore not presented as the only mechanism; the README and the
  first-apply message both name `systemctl --user stop soleur.slice` as the explicit
  fallback — with its consequence (it stops **every** agent session) stated.
- **The fleet cap's denominator is wrong until every session cycles.** v1 adopts only its
  own session tree; sessions that started before the hook existed are in no scope.
  Convergence happens via the `startup|resume|clear|compact` matcher, which every
  long-lived session eventually hits, but on first merge the fleet bound is close to
  meaningless.
- **CI runners are in the blast radius, silently.** Repo-local means this runs on CI too, where the absence of a per-user systemd bus makes it inert today — but nothing asserts that. If a runner image ever gains a user bus, CI jobs acquire a 7 GiB cap and share one fleet cap across every concurrent job on that runner.
- **The slice's drop-ins are shared mutable state.** Scopes self-clean; the slice does not, and `runtime=true` writes four property files under `/run/user/<uid>/systemd/user.control/soleur-agents.slice.d/`. Those four files *are* the fleet cap, and every checkout rewrites them on every SessionStart with no arbitration — so the fleet bound is owned by whichever worktree most recently started a session. Reboot-scoped, but "nothing is provisioned" would be too strong.
- **A session's cap under-counts by whatever it had already allocated**, because cgroup v2
  does not migrate charge. Carried through the sizing arithmetic above.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **Raw cgroup v2 directory writes** (the prior attempt) | Violates systemd's single-writer invariant; leaked a cgroup per session; and because the new cgroup was a *sibling* of the terminal's scope, the process stopped being a scope member and closing the terminal no longer reaped a runaway. Physical residue was still on the box at plan time — an orphaned, systemd-unknown cgroup directory under the **wrong parent**, proving the raw path had already silently landed in the wrong place at least once. |
| **`ulimit -v`** | Measured: `vitest` dies at 97 MB *actual* RSS under **every** cap up to 32 GB. V8 and WASM *reserve* address space, so `-v` counts reservations rather than usage. Unusable for this workload. |
| **`memory.high` alone** | Degenerates into refault thrash once swap is capped. Measured directly: a 512 MB allocator under `high=200 MB` / `max=256 MB` / `swap=0` never OOMed and never finished — reclaim can only drop file pages and immediately refaults them. It reads to the operator as a hang. `MemoryMax` is the control that actually terminates a runaway. |
| **`oom_score_adj` biasing** | Unnecessary and partly impossible: lowering a process's own score requires `CAP_SYS_RESOURCE`, and raising future children's scores is unreachable from a hook that runs before they exist. `OOMPolicy=continue` plus `memory.oom.group=0` already yields "kill the largest task", which at `MemoryMax` is the runaway by construction (~7 GiB vs `claude`'s ~0.5 GiB). |
| **A `soleur-claude` wrapper** (`systemd-run --user --scope … claude "$@"`) | Genuinely better on two axes: MCP servers would be inside the cgroup from PID 0, and the cgroup would carry a real charge instead of the post-adoption `memory.current=0` blind spot. **Rejected because** it protects only sessions launched through the alias — it fails exactly when the operator forgets — and it cannot ship by merging a PR, forfeiting the zero-operator-steps property. Adopting the whole process tree recovers most of the MCP coverage it would have given. |
| **A static `~/.config/systemd/user/soleur-agents.slice` unit file** | A persistent write into the operator's own systemd configuration, and it cannot ship by merging a PR — it needs an install step. |
| **`CPUQuota=`** | See known limits: buys back a symptom nobody reported at the cost of slowing every honest build. |
| **A `SessionEnd` cleanup hook** | Unnecessary. Transient scopes self-clean when their last process exits, which is precisely the leak the prior attempt had. (Slices do linger, but a slice holds no processes and is harmless.) |

## Verification

- `.claude/hooks/settings-hook-exec-bit.test.sh` — asserts the **index** mode (`git ls-files -s`) *and* the on-disk bit for every hook path parsed out of `settings.json`, with cardinality pinned three ways. Guards the class, so the `100644` defect cannot recur for any hook. Non-vacuity proven by a 6-mutant battery.
- `.claude/hooks/memory-backstop.test.sh` — 51 assertions with a live user bus; 34 pure-fixture with the live arm SKIPPED loudly and its skipped count asserted against the number of live tests declared, so a deleted live test cannot masquerade as a skipped one.
- `.claude/hooks/memory-backstop-mutation-battery.sh` — 10 mutants, all killed, each naming the assertion that kills it. Run by hand (needs a live bus); deliberately not `*.test.sh` so CI's auto-glob does not pick it up.
