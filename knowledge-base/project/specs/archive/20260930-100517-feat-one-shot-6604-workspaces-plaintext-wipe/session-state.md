# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-28-feat-workspaces-plaintext-volume-wipe-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None

### Decisions
- Two PRs around one gated dispatch. PR A (this branch) builds the wipe mode, with no `.tf` change and no ADR-119 status change, because the sweeper closes #6604 on `accepted`. PR B, after the wipe, narrows the web-1 `for_each` entries, flips ADR-119 to `accepted`, re-scopes the ledger row and sweeps the legal registers. Terraform forces the order (reproduced on 1.10.5).
- One gated `wipe` job (`environment: workspaces-luks-cutover`) runs its checks before touching web-1:
  - Tier-B credential loader;
  - write-token probe;
  - proof the Hetzner project is visible;
  - both apply workflows paused with nothing queued;
  - a same-day green `workspaces-luks-verify.yml` run.

  It then runs the host-side wipe mode and does the API detach and delete. The rehearsal (`dry_run=true`) runs the same host checks, ungated.
- The Terraform state removal runs in its own `workspaces-plaintext-forget.yml` (same concurrency group as the apply workflows), which PR B deletes.
- The gap between the delete and PR B is covered by pausing both apply workflows, not by a new destroy-guard check (which would reverse #6919). Recorded in decision-challenges.md.
- Host wipe checks: header ID vs the stored `CANARY_OK`, passphrase test, off-host header proven restorable, device identity, no dependent units, no armed rollback timer. Then `blkdiscard -z` with disk speed capped, full direct-IO read-back, resumable arms, and rollback refused permanently after the wipe. No reboot.

### Components Invoked
- soleur:plan, soleur:plan-review, soleur:deepen-plan, plus 17 review/research agents (see the plan's Enhancement Summary).

### Operator constraints (2026-09-28)
- No SSH, no dashboard. Doppler `prd_terraform`.
- web-1 stays up as it is until web-2 is pooled (#9123 deferred). Routine container releases on merge are normal operation, and the go-ahead request names them.
- The wipe dispatch needs an explicit per-command operator go-ahead after PR A merges.
