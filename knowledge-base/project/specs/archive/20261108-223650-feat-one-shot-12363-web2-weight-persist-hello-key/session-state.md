# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-08-chore-web2-lb-weight-default-and-proxy-hello-key-mint-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None.

### Decisions
- Release push arm WILL fire on merge (no infra exclusion in web-platform-release.yml; 3 precedents): accept a no-op release, disclose in PR body.
- Generator is random_bytes(32).hex feeding a masked doppler_secret, count-gated on host_proxy_tls_enabled.
- Serve accepts a no-op plan via a hardened wrapper around the unchanged grader; ga_overlay gains explicit -var=web2_lb_weight=0.
- Flip is its own commit.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, CTO x5, review agents.

## Operator Constraints

- constraint: OWNER-GATED, do not run: queue or merge this PR, workflow dispatches, any Doppler write, flip.sh. The owner names the exact merge command.
- constraint: Stop with the PR ready, all required checks read green, review done, and report.
- constraint: Never git stash. No secrets on command lines. Run prepush-secret-scan.sh before every push.
- constraint: Scoped tests only. Floors exact and derived. Mutate each new guard on a sandbox copy.
- constraint: Review is yours. Technical forks go to the CTO, legal to the CLO, never the owner.
