# Decision Challenges — feat-one-shot-6178-nosSH-inngest-quiesce-web

Persisted by `plan` (headless). `ship` Phase 6 renders these into the PR body and files an
`action-required` issue for operator visibility.

## User-Challenge (mechanism): rollback re-enable requires a no-SSH `enable` verb, not "restart"

- **Operator's stated direction (the default):** the request's 4th bullet says the op=rollback
  re-enable should reuse "the existing op=rollback restart path for re-enable."
- **Codebase evidence that challenges it:** a `systemctl restart` never touches the `[Install]`
  `WantedBy` symlink (the workflow's own comments say so — `cutover-inngest.yml:803-806`), which
  is why op=rollback currently prints an operator re-enable SEAM (`:800-802`). The 2.2 quiesce
  *disables* the unit (removes the symlink) on purpose, so a bare restart on rollback brings the
  unit up but DISABLED → it silently drops on the next host reboot.
- **Plan's response:** to honor the request's stated GOAL ("genuinely no-SSH end to end") while
  preserving the safety-load-bearing disable, the plan adds a small scope item the request did
  not enumerate — a no-SSH `enable` verb (`ci-deploy.sh` handler + `INNGEST_ENABLE` pinned
  sudoers grant), wired into op=rollback (enable-fan-out THEN restart-fan-out). Folding enable
  into the shared `restart` handler was considered and REJECTED (it would re-enable the
  deliberately-disabled post-cutover web scheduler on any routine restart → double-fire).
- **Disposition:** surfaced for operator confirmation, not silently applied. If the operator
  prefers to keep the re-enable as an out-of-band step, the plan's `enable` verb can be dropped
  — but the runbook would then retain an operator host-shell step, re-introducing the exact
  `hr-no-ssh-fallback-in-runbooks` violation this feature exists to remove.
