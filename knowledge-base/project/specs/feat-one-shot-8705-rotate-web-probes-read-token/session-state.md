# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-24-security-rotate-web-probes-read-doppler-token-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- `gh issue create --body-file` blocked by hook when the body file was written in the same command; re-run after a separate write.
- terraform-architect subagent returned an empty report twice; provider `name` ForceNew (v1.21.2) and `create_before_destroy` propagation verified directly.
- `preflight-discoverability-test` G1 expects 24 declared probes, sees 25 — tasks.md 1.1 bumps the ratchet first.

### Decisions
- Single PR: rename to `web-probes-read-2026-09-24` + `create_before_destroy`, merged with `[ack-destroy]`; web-1 re-delivery via the four token-hash-triggered installers in the same apply.
- web-2 re-seeded by the reviewer-gated `web-host-replace` dispatch (plan_only rehearsal first); no new SSH channel.
- Sweep: only other qualifying token (`workspaces-luks-boot`) already rotated; value exposure filed as #8734; transitive GHCR minter tokens filed as #8737 (must precede #8734).
- Verifier keys on the retired slug and requires positive evidence to print ROTATED.
- PR body uses `Ref` for #8705/#8734/#8737; pre-merge idle-queue check; post-merge head_sha run check with recovery commit.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; research, CTO/CLO/CPO, plan-review and deepen panels (see plan).
