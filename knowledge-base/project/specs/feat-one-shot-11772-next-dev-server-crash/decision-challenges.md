# Decision Challenges — feat-one-shot-11772-next-dev-server-crash

Plan: `knowledge-base/project/plans/2026-11-01-fix-next-16-4-1-e2e-dev-server-crash-plan.md`

Technical rows carry `pending - assumed:` rulings because this harness (Devin CLI
subagent) has no agent-spawn tool; the CTO-ruling path could not be invoked.
Each pending row names the assumed default implemented by the plan; `soleur:ship`
renders these for operator review per the ADR-084 channel.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Classifier signature scope — exact pair (`message === "aborted"` + `code === "ECONNRESET"`, i.e. Node's inbound `connResetException`) vs. any `ECONNRESET`-coded error | technical | pending - assumed: exact-pair only; outbound ECONNRESET ("socket hang up") keeps the fatal path — a broader exemption would mask real fatals |
| Classifier applies in prod as well as dev/e2e (same `installCrashHandlers` in both bundles) vs. dev-only gate | technical | pending - assumed: prod-wide; the upstream abort reaches `uncaughtException` in prod too, so a dev-only gate leaves the unauthenticated restart-DoS surface live |
| Non-fatal sink is `warnSilentFallback` (existing warn-level mirror) vs. bespoke `Sentry.captureException(level:"warning")` | taste | pending - assumed: `warnSilentFallback` — repo-canonical mirror per `cq-silent-fallback-must-mirror-to-sentry`, gets redaction + pino mirror free |
| CPO sign-off for the `single-user incident` brand threshold (`requires_cpo_signoff: true` in plan frontmatter) | operator (brand) | pending - no CPO agent on this harness; the plan declares the requirement and `soleur:work`/review must surface it |
| Whether the `/api/team-names` 500s warrant a `team_names` mock-supabase route in this PR | taste | pending - assumed: out of scope — the 500s are pre-existing mock-coverage noise (catch-all 404 → `namesResult.error`), not the crash precursor; a mock row is noise-reduction for a separate PR |
| Upstream-fix adoption when a stable next release fixes `body-streams` (tracked in #11783): revert classifier or keep as defense-in-depth | technical | pending - assumed: deferred to the #11783 re-evaluation; default keep-as-defense-in-depth unless review prefers the stricter fatal contract |
