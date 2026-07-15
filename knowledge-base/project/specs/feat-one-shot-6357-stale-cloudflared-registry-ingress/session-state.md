# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-12-fix-harden-deploy-tunnel-registry-ingress-blast-radius-plan.md
- Status: complete

### Errors
None. (One false-positive during gate verification — an SSH-in-command grep matched prose "without SSH" in the Observability `expected_output`, reworded. Two research sources disagreed on the `connect_timeout` type — resolved: integer form authoritative, `terraform validate` is arbiter.)

### Decisions
- **Premise falsified → re-scoped.** The issue's claim that the `registry.soleur.ai → tcp://10.0.1.30:5000` rule is stale leftover from a registry migration is false: the migration moved the registry region (nbg1→hel1) but kept the private IP `10.0.1.30:5000` unchanged; the rule is the live ADR-096/#6122 registry-push path. Removing it breaks CI push; repointing is a no-op. Re-scoped from *remove* to *correct-the-comment + fail-fast hardening*. Recorded as a User-Challenge in decision-challenges.md.
- **Root cause is elsewhere.** The `dial…canceled` errors were the zot registry transiently DOWN during the #6288 OOM/ForceNew window — tracked in #6288 (registry stability). Deploy-tunnel decoupling tracked in #6178. Neither fixed here.
- **Deliverable is minimal:** single in-place edit to `apps/web-platform/infra/tunnel.tf` — a 2-field `origin_request { connect_timeout = 5; no_happy_eyeballs = true }` on the registry ingress rule (blast-radius fail-fast) plus a comment correcting the "stale" misconception. Auto-applies on merge (resource already in the apply `-target=` allowlist; no workflow edit).
- **Plan-review converged to tighten scope:** DHH + Kieran + code-simplicity cut the deploy-tunnel monitor (deferred to #6178), dropped a comment-string drift-test and prose-testing ACs, fixed `connect_timeout` to an integer.
- **All deepen-plan gates passed:** User-Brand Impact, Observability (no-SSH `deploy-status` probe), PAT-halt (none), UI-wireframe (no UI), network-outage L3→L7 deep-dive, precedent (`origin_request` novel in-repo, v4 schema verified). Citations #6357/#6288/#6178/#6122 verified live-OPEN.

### Components Invoked
soleur:plan, soleur:deepen-plan; research agents framework-docs-researcher, platform-strategist, learnings-researcher, repo-research-analyst; plan-review panel dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer.
