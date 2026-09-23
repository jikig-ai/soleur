# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-23-fix-web-host-fresh-boot-zot-primary-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None. Two scripted plan edits missed their text anchor on the first pass and were re-applied cleanly.

### Decisions
- Stated cause ("3 s probe loses to a cold NIC") was wrong; measured cause is the tokenless early Doppler read (#6985) — reproduced locally; Sentry 90d: 0 app_zot, 0 app_ghcr_fallback, 3 app_ghcr_served post-cutover. NIC race is real but secondary; fixed in the same change.
- Bake ZOT URL + pull credentials into user_data (inngest-host shape) instead of exporting the Doppler token earlier; remove all 11 pre-token Doppler calls; drop the /v2/ probe; zot-rewrite only digest-pinned refs.
- GHCR attempted only after a successful GHCR login; fatal detail leads with state fields (nic, zot login/attempts/cause, ghcr outcome) to survive the 200-char cap. No host-script changes (replace job's image check stays green).
- Verify via gated web-host-replace of web-2 (default pin). Refs only for 8651/6985/6500/6122/6438/8539; follow-through probe closes #8651 on observed evidence. Soak blocker arm untouched.
- Amend ADR-096 (premise correction), cross-ref ADR-114/ADR-123, fix 3 C4 statements. NIC-wait cut and close-criterion wording logged in decision-challenges.md; operator direction kept.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; repo-research-analyst, learnings-researcher, functional-discovery, cto x2, dhh/kieran/simplicity reviewers, security-sentinel, architecture-strategist, observability-coverage-reviewer, test-design-reviewer, spec-flow-analyzer, verify-negatives pass.
