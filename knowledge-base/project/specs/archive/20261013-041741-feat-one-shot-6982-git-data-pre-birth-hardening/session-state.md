# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-07-27-chore-git-data-pre-birth-hardening-plan.md`
- Status: complete
- Draft PR: #7015
- Base: `ddbb70703`

### Errors
None. Two non-fatal interruptions handled inline:
- `iac-plan-write-guard` blocked two writes on `systemctl` prose — legitimately quoted cloud-init
  template content, not operator steps. Resolved with the `iac-routing-ack: plan-phase-2-8-reviewed`
  opt-out plus an explicit IaC-routing note in both artifacts (git-data has no `remote-exec`
  provisioner and no human SSH path, so an operator step is structurally impossible there).
- Deepen-plan gate 4.8 halted on `var.betterstack_logs_token`. Adjudicated a false positive
  (`hr-github-app-auth-not-pat` governs GitHub writes; this is a Better Stack ingest token) and
  recorded rather than silently dismissed.

### Decisions
- Authoritative scope is ADR-149's 7-item interlock-release checklist, not the issue body. It carries
  two items the issue never mentions — `GIT_DATA_SSH_HOST` (whose absence makes every account
  deletion file a false "Art. 17 erasure failed" event from the first birth) and the
  firewall-entailment correction (verified already discharged on `main`). The panel added a
  present-tense Art. 30 LUKS claim that becomes false at birth, and a `doppler run --config prd`
  invocation whose token is scoped to `prd_git_data`.
- Two headline premises were falsified and corrected rather than shipped. "Post-birth sizing is
  uncorrectable" is false — `git-data-host-replace` exists; the argument that holds is that the
  replace is *destructive*. The first draft's heartbeat design was withdrawn on three grounds, the
  sharpest being that a TCP connect to `:22` succeeds on a host whose LUKS never mounted, so arming
  it would install a green light over the exact failure the interlock exists to catch.
- The ADR-068 D1 vs. brainstorm contradiction resolves by construction, not by picking a side: D1 is
  true of steady state, the brainstorm of the burst — and the burst exists only because
  `receive.autogc` is default-ON with unlimited `pack.windowMemory`. The gc/pack tuning *is* the
  correction; `cpx22` stays.
- Four P0 review findings changed the design: Sentry fatals matched no alert rule (write-only),
  `STAGE=luks_open` had no producer (runs in a child bash), the `trap` fired on exit 0 (every healthy
  boot would emit `fatal`), and a follow-through probe named a credential that does not exist.
  Recorded as R1–R38 with dispositions.
- CPO signed off APPROVED WITH CONDITIONS at `single-user incident`; C1/C2 blocking, folded in. The
  birth dispatch stays out of scope (production write, separate authorisation).

### Components Invoked
`soleur:plan` · `soleur:deepen-plan` · 5 Explore research agents · `soleur:engineering:cto` ·
`soleur:legal:clo` · `soleur:operations:coo` · `soleur:product:cpo` (sign-off) ·
`soleur:engineering:discovery:functional-discovery` · `soleur:engineering:review:kieran-rails-reviewer` ·
`soleur:engineering:review:architecture-strategist` · `soleur:product:spec-flow-analyzer` ·
`soleur:engineering:review:code-simplicity-reviewer` · scoped Fable advisor consult (ADR-083) ·
deepen-plan halt gates 4.5/4.55/4.6/4.7/4.8/4.9/4.10
