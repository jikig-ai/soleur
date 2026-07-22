# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-07-19-fix-inngest-cutover-code-blockers-plan.md`
- Status: complete (revision 2, after deepen-plan)

### Errors
- Gate 4.55 (Downtime & Cutover) **halted** deepen-plan — section missing from revision 1. Closed by adding it; surfaced that web-2 was retired 2026-07-17, so web-1 is the sole web host with no blue-green partner (#6459 OPEN, ADR needed).
- Two `hr-all-infrastructure-provisioning-servers` hook blocks on the Write tool, both **false positives** on descriptive prose (an AC asserting a write count is zero; a quoted `systemctl` token). Resolved via `iac-routing-ack` + rephrasing. Note: the hook matches quoted/negative prose, not just prescriptions.
- No blocking errors. All 15 cited issue numbers, KB citations, and infra paths verified live.

### Decisions
- **Two PRs, split on which host must be replaced** — PR-A (#6500 + #6617a/c, inngest host), PR-B (#6441, web host). Three-PR split rejected: #6500 and #6617 share one `inngest-host-replace`.
- **NIC-wait re-attributed from #6466 to #6441.** #6466's body is host-addressability; ADR-114 §I1 tracks the NIC gate under #6441. Filing against #6466 would close an issue whose actual scope is untouched.
- **Rejected provisioning `INNGEST_HEARTBEAT_URL`** as briefed — that is `op=arm`'s job; doing it early recreates the dual-pusher state #6552 prevents. Quota-waste goal kept via hourly rate-limiting.
- **PR-B redesigned to defer-not-abort** via a systemd precondition. The briefed `|| exit 1` before `cloudflared service install` would have **bricked a fresh web-1**: `cloud-init.yml` runs `runcmd` as one shell, so the abort takes cloudflared, the webhook, and every monitor with it — permanently, since `runcmd` is once-per-instance.
- **A2 gated on verification.** No `cosign verify` exists on the inngest bootstrap path; the sole `cosign` mention is a comment claiming a control that does not exist. A plain-HTTP zot arm on an unverified root-executed payload is a security regression, so A2 requires a digest pin or real cosign first.

### Open blocking dependencies (recorded, NOT absorbed)
- **#6497** — zot has served **zero pulls in 90 days**.
- **ADR-096 5.3** deletes the GHCR fallback entirely, leaving the singleton one registry and no break-glass.

### Components Invoked
`soleur:plan`, `soleur:deepen-plan`, repo-research-analyst, learnings-researcher, architecture-strategist, security-sentinel, observability-coverage-reviewer, spec-flow-analyzer. Gates 4.5 (fired), 4.55 (halted), 4.6, 4.7, 4.8 passed; 4.9 skipped (no UI surface).
