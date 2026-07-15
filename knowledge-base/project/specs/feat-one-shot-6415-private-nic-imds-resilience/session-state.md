# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-07-15-fix-private-nic-boot-convergence-plan.md`
- Status: complete
- Scope verified: `git diff <base>..HEAD --name-only` against base `a9016a9978860b77c122133bb8f62ea20dc996d5`
  returned only `plans/` + `specs/` paths — the plan-only mandate held. Verified on disk rather than
  taken from the Session Summary narrative (the #3937 drift class).

### Errors
Three self-inflicted issues, all caught and corrected in-session by the planning subagent:

1. **`hr-verify-repo-capability-claim-before-assert` violation (plan author).** Plan v1 asserted
   `apply-web-platform-infra.yml` "already names the web-host-driven private-net probe … this follows
   it." The file says the opposite (`:2198-2206`: the probe cron is *"unbuilt"*). That fabricated
   "the remaining work is small" was the **sole basis** for elevating L3 to required-for-close — and
   both CPO's and DHH's "keep" verdicts rested on it. Caught by `spec-flow-analyzer`, verified against
   the file, L3 deferred.
2. **IaC-routing hook blocked the plan write twice.** The `iac-routing-ack` comment itself contained
   the trigger token. Resolved by removing the literal while keeping the ack.
3. **Two bad tool calls** (a wait-condition that proved nothing; a glob that expanded across every plan
   file). Neither corrupted state — `git status` confirmed scope stayed clean.

### Decisions
- **Root cause reframed against the issue body.** The "transient IMDS blip" (H1) is likely a
  misdiagnosis of a known structural race (H2): `hcloud_server_network` is an additive *online attach*
  that cannot be ordered before the guest's network stage, and
  `learnings/2026-07-07-immutable-redeploy.md` Sharp edge 2 documents this exact symptom on this exact
  host (#6122). Both held as competing; the design is correct under either, and the emitted
  `imds_rc`/`imds_nets`/`uptime_s` fields discriminate them in one event (AC15).
- **Scope cut from the issue's ask (registry + git-data + inngest) to registry-only, on safety.** A
  reboot primitive on git-data would silently unmount the LUKS store (`luksOpen` lives in `runcmd`,
  which is per-instance and does not re-run on reboot; no `crypttab` repo-wide; fstab carries
  `nofail`). Recorded as a normative blocker inside ADR-113, since the ADR outlives this plan.
- **Netplan converge path deleted; a guarded reboot is the sole primitive.** Both review panels fired
  on it; its trigger was a strict subset of the reboot's, and it had no budget (would re-apply every
  5 min, bouncing public egress invisibly — #6400's own signature, self-inflicted).
- **L3 (off-host probe) deferred; L1+L2 ship.** Its `paused` flip is a Terraform no-op
  (`ignore_changes=[paused]`), so L3 would have shipped inert behind a green AC — reproducing #6400's
  failure shape inside its own fix.
- **Threshold kept at `single-user incident`, re-grounded.** The original rationale was falsifiable
  (beta users = 0); re-grounded on ADR-103 precedent + Phase 4 being the founder-recruitment phase.

### Components Invoked
- **Skills:** `soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`
- **Research:** `Explore`, `learnings-researcher`, `soleur:engineering:cto`
- **Review panel (5-agent escalation + named panel):** `dhh-rails-reviewer`, `kieran-rails-reviewer`,
  `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, `cpo`
- **deepen-plan Phase 4.45:** verify-the-negative sweep (`sonnet` per ADR-053) — 12/12 CONFIRMS, one
  citation drift fixed
- **Gates:** 4.5 network-outage (fired), 4.55 downtime/cutover (fired — real gap), 4.6/4.7/4.8 (pass),
  4.9 (skipped — no UI surface)

## Open Operator-Facing Items (carried to ship)
- **UC-1** — L3 deferred vs required-for-close. Resolved in-plan toward the issue's own stated ask
  (self-heal + loud marker); L3 is greenfield on a different host. Surfaced for overrule at ship.
- **UC-2** — #6415 tracking metadata (`Post-MVP`/`p2-medium`/`type/chore`) contradicts the plan's
  threshold. Automatable via `gh issue edit`; must not be left as a manual operator step.
