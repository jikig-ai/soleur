# Learning: the fourth gh-403 fix was a NETWORK-plane denial — error SHAPE triage beats another credential sweep

## Problem

After three merged token-plane fixes (#4946 repo-owner selection + membership
gate, #5031 self-heal hardening, #5041 clone-consumes-self-healed-install),
the hosted Concierge still failed every `gh` command with:

```text
Post "https://api.github.com/graphql": Forbidden
```

The operator's natural hypothesis (and the task framing) was "yet another
unswept consumer of `effectiveInstallationId`". Research refuted it: the token
plane was fully swept. The actual constraint was one layer down — the SDK
sandbox shipped `network.allowedDomains: []` (born as an explicit "no outbound
network" acceptance criterion in #871, extracted verbatim by #2901, never
widened), so the sandbox proxy denied CONNECT to `api.github.com` for every
in-sandbox process. The credential was never the binding constraint **for
gh**; the network was. All the gh/askpass credential infrastructure shipped
structurally dead.

## Solution

Egress-iff-entitled-token (PR #5090, ADR-051): `buildAgentSandboxConfig`
gains `allowGithubEgress` which widens ONLY `network.allowedDomains` to
exactly `["github.com", "api.github.com"]`; `buildAgentQueryOptions` derives
it from `Boolean(args.ghToken)` so token-without-egress and
egress-without-token are unrepresentable. Legacy path never passes `ghToken`
→ stays fully closed. Verified against the installed
`@anthropic-ai/claude-agent-sdk@0.2.85` bundle (the `Cv8` domain collector's
else-branch reads flag-settings `allowedDomains`; `options.sandbox` rides the
`--settings` payload).

## Key Insight

**Triage the error SHAPE before re-running the last incident's playbook.**
In gh output the three failure planes render differently:

| Shape | Plane | Meaning |
|---|---|---|
| `Post "https://...": Forbidden` (transport-wrapped status text) | network | sandbox/proxy CONNECT denial — no credential change can fix it |
| `HTTP 401: Bad credentials` / `HTTP 403: <message>` | credential | GitHub rejected the token (expired, wrong install, missing permission) |
| `GraphQL: <message>` | authorization | authenticated but the resource/permission denies |

Three PRs of token-plane work could not cure a transport-shaped error. The
2026-06-03 session made the inverse mistake: it read an in-sandbox
`gh auth status` "token invalid" as proof api.github.com was reachable
("Outcome A") — a prod signal settles a capability question only when the
signal's SHAPE is verified against the failure mode it claims to rule out.

## Host-by-subcommand deny map (triage table for the 2-host allowlist)

The allowlist is exactly `github.com` + `api.github.com`. These gh surfaces
hit OTHER hosts and will render the SAME transport-shaped `Forbidden` — that
is a scoping decision (ADR-051), not a regression:

| Subcommand | Blocked host |
|---|---|
| `gh run download`, `gh release download` | `objects.githubusercontent.com`, `*.blob.core.windows.net` |
| `gh api .../tarball`, `git archive` fetches | `codeload.github.com` |
| `gh extension install` | `raw.githubusercontent.com` |
| `gh gist *` | `gist.github.com` |
| `gh release upload` | `uploads.github.com` |
| git-LFS objects (refs push fine; objects fail) | `media.githubusercontent.com`, `github-cloud.s3.amazonaws.com` |

Supported surface: `gh issue/pr view`, `gh api` (REST+GraphQL), raw
`git push/fetch/pull/ls-remote`. Widening for any row above requires its own
security review (each host is exfiltration surface).

## Session Errors

1. **Added a duplicate `vi.mock` for a module the test file already mocked**
   — the new egress-posture-log test wired a hoisted spy into a NEW
   `vi.mock("@/server/logger")` block without grepping the 1,200-line factory
   test for the pre-existing logger mock ~150 lines further down; the
   pre-existing anonymous-`vi.fn()` mock won silently and the spy captured
   zero calls, costing ~4 debug cycles (alias-vs-relative specifier
   hypothesis, dynamic-import probe, scratch repro file, importActual
   hypothesis) before a sequential read of all the file's mocks surfaced the
   duplicate. **Recovery:** wire the spy into the EXISTING mock block; delete
   the duplicate. **Prevention:** before adding `vi.mock("<module>")` to an
   existing test file, run `grep -n 'vi.mock' <file> | grep <module-basename>`
   — vitest registers one mock per resolved module per file and a duplicate
   does not error, it silently picks one.
2. **Plan cited the wrong provenance PR for a load-bearing claim** — "mint
   consumes `effectiveInstallationId` since #5031" when `git blame` proves
   #4946 (#5031 hardened the probe, not the mint). The plan's "line-citation
   audit" verified current line CONTENT, not provenance. **Recovery:**
   review-phase git-history-analyzer blamed the exact hunk; plan corrected.
   **Prevention:** a plan claim of the form "X since #N" is a `git blame`
   /`git log -S` check, not a read-the-current-line check; audit provenance
   claims with history commands at plan time.
3. **Plan premise contradicted a committed learning without reconciling it**
   — `2026-06-03-self-heal-on-brand-path-only-acts-on-safe-symptom.md`
   recorded "api.github.com WAS reachable (Outcome A)"; the new plan's H-B
   (proxy denies api.github.com) is its direct negation, and the plan never
   cited the learning. **Recovery:** review caught it; the learning now
   carries a SUPERSEDED block with the corrected meta-lesson.
   **Prevention:** premise validation in /plan should grep
   `knowledge-base/project/learnings/` for empirical claims about the same
   subsystem (here: `grep -rl "allowedDomains\|api.github.com" learnings/`)
   and either cite-and-agree or explicitly supersede each hit.
4. **CWD slip** — one `grep server/logger.ts` ran from the worktree root
   instead of `apps/web-platform/` (Bash CWD does not persist across calls;
   known class). **Recovery:** immediate re-run with `cd <app> && grep`.
   **Prevention:** existing rule (single-call `cd && cmd` chains) covers
   this; no new rule.

## Tags

category: bug-fixes
module: apps/web-platform/server (cc-dispatcher, agent-runner-sandbox-config, agent-runner-query-options)
refs: PR #5090, ADR-051, #871, #2901, #4946, #5031, #5041
