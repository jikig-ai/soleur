# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-02-feat-memory-backstop-systemd-transient-scope-plan.md
- Status: complete

### Errors
- One IaC-routing hook block on the first plan write (`systemctl` in prose read as manual provisioning). Resolved by reviewing Phase 2.8 and adding the `iac-routing-ack` marker — the plan provisions nothing; all `systemctl` uses are read-only verification.
- One self-inflicted probe failure: `pkill -f "sleep 600"` matched the probing shell's own wrapper and killed it (exit 144). Re-run without the self-matching pattern.
- One false-negative probe result (multi-PID adoption) caused by `pgrep -f` matching the probe's own command line; corrected by re-testing with `$!` and recorded in the plan as G15.

### Decisions
- Caps re-derived against measured concurrency, not idle RSS: per-session `MemoryHigh=6 GiB`/`MemoryMax=7 GiB`, fleet `MemoryHigh=16 GiB`/`MemoryMax=20 GiB`, `MemorySwapMax=0` everywhere (swap exhaustion was the observed harm mechanism).
- AC3 re-stated to its intent: literal cgroup co-membership is physically impossible alongside a per-session cap, so the terminal kill switch is preserved as a `BindsTo=`/`After=` unit dependency, asserted at unit level and behaviourally.
- `OOMPolicy=continue` set explicitly — transient scopes default to `stop`, which would have systemd kill the whole scope including `claude` on any OOM. Resolves the issue's `oom_score_adj` question without needing it (lowering one's own score requires `CAP_SYS_RESOURCE`).
- Test-injection seams deleted rather than gated — a sourced-function + `main` guard makes the predecessor's `TARGET_PID` defect unrepresentable, satisfying AC6 more strongly than a test-mode flag.
- Phase 4 moved to run last — `compact` fires automatically, so wiring `settings.json` mid-implementation self-arms the hook against the session doing the work.
- `Delegate=true` is required on the transient scope: `AttachProcessesToUnit` fails on a non-delegated unit, which would have made the re-entry re-sweep unimplementable.
- `ManagedOOMPreference=avoid` on the slice, because `systemd-oomd` is active with `ManagedOOMMemoryPressure=kill` and selects among a monitored cgroup's direct children — a shared slice would otherwise make the whole fleet one victim. Runtime efficacy recorded as unvalidated.

### Open judgement calls carried into work/review
- The simplicity review recommended dropping the fleet slice's memory caps (~1/3 of the acceptance surface). Rejected: "no aggregate bound" is defect #4 of the five the issue indicts, and AC4 requires a fleet-wide bound asserted with more than one session. The rest of that review was taken, including making the fleet control the non-lethal `MemoryHigh` with `MemoryMax` as an explicit last resort.
- Engineering and product reviews disagreed on blast radius; both positions are recorded in the plan rather than silently resolved. Agreed facts: `.claude/` is git-tracked, so this reaches contributor clones but not downstream plugin users. Resolution uses the repo's existing opt-out convention rather than inventing policy.

### Components Invoked
- Skills: `soleur:plan`, `soleur:deepen-plan`
- Agents: `learnings-researcher`, `repo-research-analyst`, `engineering:cto`, `product:cpo`, `review:code-simplicity-reviewer`, `product:spec-flow-analyzer`
- Live-box probes: `busctl StartTransientUnit` / `SetUnitProperties` / `AttachProcessesToUnit`, `systemctl --user show/set-property`, `oomctl`, `/proc` ancestry + cgroup reads, `memory.events`/`memory.peak`
- Repo verification: `gh issue/pr view`, `git ls-files -s`, `git ls-tree origin/main`, `jq` over `.claude/settings.json`
