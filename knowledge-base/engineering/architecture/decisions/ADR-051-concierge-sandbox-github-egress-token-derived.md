# ADR-051: Concierge sandbox GitHub egress derived from entitled-token presence

- **Status:** Accepted
- **Date:** 2026-06-10
- **Deciders:** Jean (operator), security-sentinel + user-impact-reviewer + architecture-strategist (PR #5090 review)
- **Relates to:** PR #5090 (this change), PR #871 (zero-egress origin), PR #2901 (helper extraction), PRs #4946/#5031/#5041 (token-plane incident arc)

## Context

The agent SDK sandbox has shipped `network.allowedDomains: []` since PR #871,
where "no outbound network" was an explicit acceptance criterion for the
multi-tenant hosted environment. PR #2901 extracted the literal into
`buildAgentSandboxConfig` unchanged.

Subsequent product direction made the Concierge drive GitHub via in-sandbox
`gh` and raw `git` (GH_TOKEN mint, GIT_ASKPASS plumbing, gh prompt directives,
gh in the Docker image — #4946/#5031/#5041). All of that credential
infrastructure was structurally dead: with an empty allowlist the SDK's
sandbox proxy denies CONNECT to every host, surfacing as the transport-shaped
`Post "https://api.github.com/graphql": Forbidden` that three token-plane
fixes could not cure.

## Decision

Widen the sandbox network allowlist to exactly `["github.com",
"api.github.com"]` **if and only if** an entitled GitHub App installation
token was minted for the dispatch. The egress flag is **derived** from token
presence (`allowGithubEgress: Boolean(args.ghToken)` inside
`buildAgentQueryOptions`) — never threaded as an independent flag — so the
two half-wired states (token without egress, egress without token) are
unrepresentable. The legacy domain-leader path never passes `ghToken`, so its
sandbox remains fully closed (the #871 posture is preserved where it was
written).

This is the first deliberate widening of the zero-egress sandbox policy. It
supersedes the #871 "no outbound network" acceptance criterion for the
entitled-token Concierge case only.

## Consequences

- Restores the flagship Concierge gh/git capability for entitled sessions;
  fail-closed everywhere else (no-repo, mint-failure, empty-string token,
  legacy path — all test-pinned).
- Accepted residual risk (documented in the PR #5090 plan §User-Brand
  Impact): prompt-injection exfil bounded to the user's own GitHub tenancy,
  and token-value self-exfiltration bounded by the short-lived,
  installation-scoped App token.
- Any future host added to `GITHUB_EGRESS_DOMAINS` (gist/upload/CDN/LFS
  hosts) is new exfiltration surface and requires its own security review.
- Blocked-host failures for unsupported gh subcommands (`gh run download`,
  `gh gist`, LFS objects) render with the same transport-shaped `Forbidden`
  as the original incident — triage via the host-by-subcommand deny map in
  the PR #5090 learning, not re-diagnosis.
