# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-07-fix-inngest-bootstrap-pin-and-guard-hardening-plan.md
- Status: complete (revised in place from the inherited 1209-line draft; deepen-plan run constrained)
- Plan artifact: complete (selector=branch)
- Worktree reused per operator brief; rebased onto 0ae1a39d2, 0 behind main.

### Errors

- deepen-plan did not run in the first planning turn (two plan reviews consumed it); run in the second turn, constrained to thin sections with explicit no-refanout.
- Phase 4 boundary-derivation shipped pre-review in the first turn; rewritten in the second.
- AC12 shipped incoherent in the first turn (asserted a merits verdict impossible at merge by construction); corrected to expect a `boundary_underivable` token.
- Length regressed 1209 -> 1255 lines against the "substantially shorter" instruction. Scope cut is large (six workstreams removed) but correctness material outgrew prose trimming. Instruction not met; recorded rather than reframed.

### Decisions

- #7761 premise INVERTED and corrected: its fix merged in PR #7768 (2026-09-03, closes=[] prose ref); the pin was set 2026-08-20, two weeks earlier. Re-pinning is the remediation, not a new exposure. Measured live: 4,204 inngest-cutover-flip rows in 48h, ZERO carrying the `guard` field -> production scheduler is running pre-fix code.
- Guard A redesigned hermetic and git-only (`git show <pinned tag>:<path>` vs HEAD over the cp-derived carrier set). Resolves BOTH P0s at once: no crane in deploy-script-tests, and authorship-before-consumption by construction.
- Guard B's live arm moved off PR-gating CI to the apply path (which already holds GHCR credentials), following the repo's own zot-image-staleness.test.sh NO-NETWORK-BY-DESIGN precedent.
- Phase 4 resolved by PROVENANCE, not override: supplied boundary keeps the committed header's FAIL arm verbatim; derived boundary is capped PASS-or-TRANSIENT. T6 is the control proving the split is by provenance, not a weakened rule.
- Digest-only substring matching is mandatory: the live host reports a zot-prefixed image_ref while the pin literal is GHCR, so whole-ref comparison would be a permanent silent no-op.
- Gate 4.55 (new): editing cloud-init-inngest.yml ARMS a force-replace of hcloud_server.inngest (no ignore_changes on user_data). Merging does not fire it (`target=hcloud_server` count 0 in the apply workflow). That armed replace IS the Step 2 delivery vehicle.
- Semver-max drift check KEPT (reverses the prior draft's R14; its claimed permanent-red window on main does not exist).

### Components Invoked

- Skill: soleur:plan, Skill: soleur:deepen-plan
- Agent: general-purpose x2; code-simplicity-reviewer; architecture-strategist
- scripts/betterstack-query.sh (control-paired queries throughout)
- scripts/lint-guard-contract.py, scripts/lint-infra-no-human-steps.py (both green)
- apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh (baseline 129/129)

## Preflight measured by pipeline runner (pre-work)

- Live probe row: no `probe_schema` AND no `redis_keys` field; image_ref v1.1.25@sha256:f23a2a0d...;
  server_active=inactive, redis_active=active, uptime_s=1620603, cutover_flag=aborted, instance_id=hetzner-162809678.

- probe_schema=3 (Merge A #7778 / 000fa4715) ALREADY emits redis_keys via INFO keyspace summed across all dbs
  (deliberately not DBSIZE, which reads db0 only while FLUSHALL spans all). No extra emitter work needed.

- INNGEST_REDIS_PASSWORD present in soleur-inngest/prd -> the cloud-init:1009 fail-closed
  `redis_keys=__UNREADABLE__` trap will NOT fire on replace. INNGEST_REDIS_LUKS_KEY present (Step 4).

- inngest-cutover environment required reviewers = [deruelle] (NON-EMPTY; no auto-approve).
- No secret name in soleur-inngest/prd collides with a CUTOVER_* fixture seam -> #7761 latent, not active.
- ci.yml on main last 3 runs 2332s/2143s/2438s (under the 3000s await-ci ceiling; today's peak 3366s).
