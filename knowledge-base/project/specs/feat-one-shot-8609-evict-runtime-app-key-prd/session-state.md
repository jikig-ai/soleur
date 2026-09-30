# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-30-security-evict-runtime-app-key-from-prd-reachability-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- A PreToolUse hook blocked two Bash calls that contained `doppler secrets set/delete` without `>/dev/null`. The work switched to the Write tool, and every Doppler set/delete command in the plan now ends with `>/dev/null`.
- The Playwright MCP server was unavailable. The four App-settings UI steps are marked `automation-status: UNVERIFIED` and carry a manual fallback.
- deepen-plan Phase 4.8's PAT check flagged the Doppler service-token variables. This was a false positive and is recorded in the plan.

### Decisions
- **Where the key lives.** It moves to a new Doppler project, `soleur-github-app`, and is rotated in the move. The new key is minted directly there, and the old key is deleted at GitHub last.
- **Read token.** It is minted by hand into `soleur-infra-privileged`. web-1 gets it through the existing Terraform-declared push (one conditional line in the existing credential file). web-2 is replaced from main and its host key re-pinned (R5b).
- **Deploy overlay.** The overlay covers only `GITHUB_APP_PRIVATE_KEY`, only for images whose signature verified, and runs in the parent shell. Before any swap, a canary calls `GET /app` and must see slug `soleur-ai` and the expected App ID. A failed fetch falls back to the `prd` key until R6.
- **Gating.** The R1 mint is gated on #8209 O10/O13. There are two PRs: PR-A (code, ADR-241 D10 amendment, runbook; `Ref #8609`) and PR-B (flip D2 to accepted; `Closes #8609`) after R7 and R8.
- **Legal (CLO).** The reachability-only dated assessment creates no notification duty. The courtesy notice is logged as DC-1.
- **Work-phase obligations.** AC13: bump `BASELINE_DECLARED_PROBES` by 1. PR-A touches workflows, so it merges through UNTRUSTED-CI auto-merge only.

### Components Invoked
- Skills: soleur:plan, soleur:plan-review, soleur:deepen-plan.
- Agents:
  - CTO (x2), CLO, CPO.
  - Plan review: DHH, Kieran, simplicity, architecture, spec-flow.
  - Deepen: security-sentinel, deployment-verification, observability-coverage, user-impact, test-design.
  - Research: repo-research, learnings-research, functional-discovery.
