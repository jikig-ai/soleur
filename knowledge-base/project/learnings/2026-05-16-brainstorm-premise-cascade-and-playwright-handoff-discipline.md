---
date: 2026-05-16
category: process
module: brainstorm, incident, playwright-mcp, sentry-residency
tags:
  - brainstorm
  - playwright
  - host-verification
  - premise-cascade
  - credential-boundary
  - sentry
  - gdpr
  - pir
  - workflow-gate
related_issues:
  - "#3861"
  - "#3863"
related_prs:
  - "#3863"
related_learnings:
  - 2026-05-15-sentry-dsn-cluster-substring-authoritative-residency
  - 2026-05-15-token-namespace-divergence-across-secret-stores
  - 2026-04-21-concurrent-cleanup-merged-wipes-active-worktree
---

# Learning: brainstorm premise-cascade detection + Playwright credential-handoff discipline

A multi-hour Sentry residency A2 brainstorm halted at Phase 0 prereqs and surfaced a cascade of three premise failures, all from one unverified URL substring in the feature description. The session also exposed three Playwright workflow gaps that compounded the wasted effort. This learning captures both the diagnostic pattern (recognize cascading-anchor failures) and the prevention discipline (curl host before driving anything, probe headless-vs-visible before clicking through credential modals).

## Problem

A2 was scoped as "align tfstate to DE org, rotate token, re-apply against `de.sentry.io`, regenerate §5(2) evidence, close #3861." The feature description prescribed two operator prereqs (A2.P1 billing on `de.sentry.io`, A2.P2 mint DE-scoped token from `de.sentry.io/settings/...`), and a verify probe (`curl https://de.sentry.io/api/0/users/me/` returning 200). Every URL was wrong.

Symptoms encountered, in order:

1. Playwright drove to `https://de.sentry.io/settings/jikigai/billing/` and returned `ERR_HTTP_RESPONSE_CODE_FAILURE` — initially misdiagnosed as CDN bot-detection blocking the MCP browser fingerprint. Wasted time on Cloudflare-mitigation theories.
2. Operator-driven walkthrough emitted in prose with `de.sentry.io` URLs — operator could not resolve the URLs either, surfacing the actual diagnosis: `de.sentry.io` is **ingest-only**. Every `/settings/*` returns 404. The dashboard host is `sentry.io` (org-routed via subdomain: `jikigai.sentry.io` for the US org).
3. After correcting the host, Playwright successfully drove the US `jikigai.sentry.io` billing page — and revealed that the org currently administered by the operator's account is on a Team trial actively burning $5.46 PAYG. Wasn't the residency-target org; it's the US shadow org the original A2 plan intended to tear down.
4. Navigating to `eu.sentry.io` returned an explicit banner: "Your account (`<operator-email>`) is not a member of the eu organization." API probe of `/api/0/organizations/jikigai/` on the EU edge returned `302 → /organizations/eu/ → 401 "Invalid org token"` — Sentry's region-router signal for "no `jikigai` slug exists on this edge."
5. A1's audit script (PR #3863) catches wrong-cluster (DSN host-substring mismatch) but **not** wrong-destination (DSN points to DE cluster but the org at the specified ID is unowned). It greenlit a destination nobody can administer.

Net effect: the runtime `SENTRY_DSN` had been POSTing user envelopes to a destination at org ID `4511123328466944` on `o4511...ingest.de.sentry.io` for ~49 days (since PR #1235 introduced Sentry observability on 2026-03-28), and the destination is either a phantom org, an orphaned org, or owned by a third party — we cannot enumerate it. §5(2) accountability gap.

A separate Playwright workflow failure compounded the time loss: when the password-confirmation modal appeared during US Team plan cancellation, the operator was told to repeat the navigation in their own Chrome — a 6-step prose dump instead of a single-keystroke credential handoff. Root cause: `@playwright/mcp@0.0.75` was running `--headless` despite its `--help` claiming "headed by default." No `pgrep --headless` probe was done before driving the cancellation flow.

## Solution

Seven discrete corrections from this session, ordered by leverage:

### 1. Verify hosts before driving Playwright (curl-I as Phase-0 reflex)

```bash
# Before any Playwright navigation, before any operator walkthrough, before any agent prompt:
curl -sS -o /dev/null -w "http=%{http_code} final=%{url_effective}\n" -L --max-time 5 "<target-url>"
```

A `404` from `curl -I` means the URL is wrong, not that Playwright is blocked. A 4xx that propagates to Playwright as `ERR_HTTP_RESPONSE_CODE_FAILURE` is indistinguishable from CDN/bot-detection if you don't probe with curl first. Five seconds at session start beats hours of mis-diagnosis.

Applies to: every brainstorm with external-UI prereqs; every plan with operator walkthroughs; every ADR that cites a vendor dashboard URL.

### 2. Probe Playwright headed-vs-headless BEFORE driving credential flows

```bash
# After first browser_navigate, before any flow that will hit a password / MFA / card iframe:
pgrep -fa chromium 2>/dev/null | grep -- --headless
```

If the line returns, Playwright is headless. Driving a flow that opens a credential modal mid-sequence is wasted work — the operator can't type into a window they can't see, and repeating the navigation in their own Chrome forfeits the entire Playwright drive.

`@playwright/mcp@0.0.75` ignores the documented "headed by default" and spawns `--headless`. Override via `--config <path>` to a JSON file `{"browser":{"launchOptions":{"headless":false}}}` AND reload the MCP server (`/mcp` slash → reconnect, or full Claude Code restart for some MCP-config changes).

### 3. Credential-boundary handoff is a question, asked BEFORE the trigger click

When a Playwright drive will reach a password modal / MFA prompt / Stripe iframe, ask "where do you complete this — visible Playwright window, or your own Chrome?" **before** clicking the button that opens the modal, not after. Operator's answer determines the smallest possible handoff:

- **Visible Playwright + operator at keyboard:** drive everything; hand off only the keystroke.
- **Headless Playwright + operator's own Chrome:** narrate the flow as a 3-click recipe from the start; don't pretend to drive.
- **Operator wants to take over earlier:** they say so; you yield.

The wrong pattern (this session): drive halfway, modal appears, dump 6-step prose re-walkthrough on operator who must repeat everything in their own Chrome.

### 4. Cascading-anchor recognition: 2+ wrong premises → STOP and restart

When two or more named premises in a feature description prove wrong (this session: `de.sentry.io` is dashboard ❌; A2.P1 prereq is "add payment to existing DE org" ❌; A2.P2 verify probe URL exists ❌), do NOT patch forward. Re-scope the brainstorm with the corrected premise. Every minute spent designing on top of a wrong premise compounds; every minute spent patching individual premises produces an inconsistent design.

Pattern observed: the bot-fix Stage-N issue, the issue-body option enumeration ("Recommended: Option B"), the cited flag name, and the cited host URL are all classes of premise that decay between issue-write time and brainstorm time. Adding `curl -I host` to Phase 1.0.5 (premise validation) is the cheapest catch.

### 5. Audit-script gap: enumeration ≠ controllability

The A1 audit script (`apps/web-platform/scripts/sentry-monitors-audit.sh`) validates DSN host substring against expected cluster. It does NOT validate whether the destination org is admin-controllable. Sentry's ingest endpoint returns 200 on any well-formed envelope POST regardless of destination-org accessibility — a phantom DSN ingests indistinguishably from a real one. Audit scripts pretending to confirm "residency" need an explicit `curl -H "Bearer $SENTRY_AUTH_TOKEN" /api/0/organizations/$SENTRY_ORG/ → 2xx` probe to confirm controllability.

This goes into A2 Branch C's PR as a new audit gate: `audit_destination_admin_controllable`.

### 6. PIR classification override under "no external users" — keep procedural gate, downgrade severity

Sentry SDK had been posting user-telemetry-shaped events to a phantom destination for 49 days. Worst-case framing: aggregate-pattern + medium risk + Art 33 trigger fires.

Reality framing (load-bearing context the operator provided): "we didn't onboard any external users yet." Subjects are internal team only, fully self-aware of the breach via this very brainstorm. Brand_survival_threshold dropped from `aggregate pattern` to `none` with explicit `classification_override: { advisory, chosen, reason }` block in PIR frontmatter. Art 33 still fires (risk ≠ none, data_categories non-empty) — procedural CNIL deadline documented even though the practical filing question is moot pending forensics on org ID 4511...

Pattern: "no external users" is a load-bearing premise check that should be asked **before** affixing brand_survival_threshold during user-impact framing (brainstorm Phase 0.1). If no external users existed during the window, the framing question's preset options (data exposure, credential leak, billing surprise) all collapse to `none` — but the procedural gates may still apply.

### 7. Skill tool cannot change session CWD; main-branch gates must be respected

Compound's hard-rule branch-safety check ("cannot run on main/master") runs `git branch --show-current` from the session CWD, not from any Bash `cd` chain. A `cd .worktrees/feat-X` inside a Bash command is subprocess-scoped — the session CWD is unchanged. If compound is needed mid-session and the user is on main, the only path is: (a) create the worktree via worktree-manager.sh, (b) write the learning file manually using compound's format (`knowledge-base/project/learnings/YYYY-MM-DD-<topic>.md`), (c) commit + push from the worktree via explicit-cd Bash chains, (d) skip the formal compound machinery (constitution-promotion gate, route-to-definition, deviation analyst) — those need a fresh session with the worktree as CWD.

This learning was captured under exactly that workflow; the formal `/soleur:compound` will need to re-run when a fresh session is rooted in this worktree.

## Key insight

**Wrong premises don't stay localized — they cascade.** One unverified URL substring in a feature description (`de.sentry.io`) produced three downstream wrong conclusions (operator-driven walkthrough URLs are 404; Playwright CDN-blocked diagnosis; A2.P1/P2 prereqs as scoped). Patching individual wrong premises in a brainstorm forward is a trap; the right move is to STOP at the second confirmed wrong-premise and restart the brainstorm with the corrected one.

**The cheapest gate that prevents the cascade is `curl -I host` at Phase 1.0.5.** Five seconds at session start beats hours of mis-diagnosis. Adding this to soleur:brainstorm's Phase 1.0.5 (premise validation) — currently scoped to "named numerical claims" — extends it to "named URL substrings." Every brainstorm with external-UI references benefits.

**Playwright MCP is a tool, not a magic-do-everything substrate.** Three workflow nuances unique to Playwright MCP that compound the cost of skipping the upfront probes: (a) `ERR_HTTP_RESPONSE_CODE_FAILURE` looks like CDN block but is usually a 4xx; (b) `--headless` is the silent default despite docs claiming otherwise; (c) credential modals are operator-keystroke boundaries no matter how cleverly Playwright drives the surrounding navigation. Treat Playwright as a navigation assistant with credential-blind spots, not as a "fully autonomous browser."

## Session Errors

1. **Misdiagnosed Playwright `ERR_HTTP_RESPONSE_CODE_FAILURE` as CDN bot-detection block.** Recovery: tried Playwright against `sentry.io/welcome/` (worked) then `sentry.io/settings/jikigai/billing/` (worked — auto-redirected to `jikigai.sentry.io`); confirmed the failure was a 404 on the wrong host. Prevention: curl -I host BEFORE Playwright navigation; treat the 4xx and the bot-block as distinguishable only via independent probe.

2. **Drove the cancellation flow through password-modal-trigger without asking operator where they'd complete credentials.** Recovery: dumped a 6-step prose re-walkthrough on the operator. Prevention: ask "visible Playwright window vs your own Chrome?" at the radio-selection step, NOT at the modal-already-open step. Add to Playwright handoff discipline rule.

3. **Failed to verify Playwright was headed vs headless before driving credential flows.** Recovery: ran `pgrep -fa chromium | grep -- --headless` after operator said "I don't see any chrome window"; confirmed headless. Edited `.mcp.json` with `--config` flag pointing at a headed-mode JSON; user reverted; we proceeded headless. Prevention: probe headed-vs-headless at first Playwright invocation, surface to operator before driving anything that will hit a modal.

4. **Treated A1's audit script as authoritative for "DE residency" claims.** Recovery: independently probed the destination org via eu.sentry.io; surfaced the membership-banner finding. Prevention: extend audit script with destination-controllability probe (`/api/0/organizations/$SENTRY_ORG/ → 2xx`). New audit gate `audit_destination_admin_controllable` goes into A2 Branch C PR.

5. **Did not verify host substring (`de.sentry.io`) before propagating it through walkthrough prose to operator.** Recovery: operator caught the URL didn't resolve for them either. Prevention: every URL in a brainstorm prose walkthrough should be `curl -I`-probed; every URL in an ADR or feature description should be probed at brainstorm Phase 1.0.5.

6. **Tried to run /soleur:compound on main branch.** Recovery: skill correctly halted on the branch-safety hard rule; we created the worktree first, then wrote the learning file manually. Prevention: when /soleur:brainstorm halts at Phase 0 prereqs and the session needs to capture learnings before /clear, create the worktree explicitly as part of the prereq-resolution path — don't wait for the brainstorm-restart to create it.

7. **Wasted ~1500 tokens fighting Playwright's CDN-block hypothesis before testing the host.** Recovery: simpler probe (curl bare host vs path) revealed the host was ingest-only. Prevention: when a tool returns an opaque error, generate three competing hypotheses (tool blocked / wrong URL / wrong auth) and probe the cheapest one (URL) first.

## Workflow proposals for follow-up bundle (deferred per task #10)

These are advisory edits to skills/agents/AGENTS.md, captured here as draft text for the follow-up issue:

### Proposal W1 — `hr-prereq-playwright-first-then-credential-handoff` (new hard rule, AGENTS.core.md)

```
[id: hr-prereq-playwright-first-then-credential-handoff]
Before driving any external-UI flow via Playwright MCP:
(1) curl -I --max-time 5 the target URL. A 404 means the URL is WRONG,
    not that Playwright is blocked. Fix the URL first.
(2) After first browser_navigate succeeds, run `pgrep -fa chromium |
    grep -- --headless` to confirm visible vs headless. If headless, do NOT
    drive a flow that will hit a password/MFA/card-iframe modal — narrate
    a click recipe from the start instead.
(3) At credential boundaries, ask "where do you complete this?" BEFORE
    clicking the trigger that opens the credential modal, not after.
(4) If 2+ premises in feature description prove wrong, STOP and restart
    brainstorm; do not patch individual premises forward.
**Why:** 2026-05-16 Sentry A2 brainstorm — three cascading anchor failures
from one unverified host claim (de.sentry.io is ingest-only, not dashboard).
**How to apply:** brainstorm Phase 1.0.5 (extend to named URL substrings,
not just numerical claims); plan operator-runbook sections; any skill that
emits a "go do X in the UI" instruction; ux-audit + agent-browser + feature-
video skills directly.
```

### Proposal W2 — extend `soleur:brainstorm` Phase 1.0.5 premise check to URL substrings

Current text triggers premise check on "named external systems, prior issues, prior brainstorms, or numerical claims (caps, counts, byte budgets)." Add: "named URL substrings (vendor dashboards, API endpoints, login pages, settings paths)." Verify via `curl -I --max-time 5` before launching Phase 0.5 research agents.

### Proposal W3 — extend `apps/web-platform/scripts/sentry-monitors-audit.sh` with destination-controllability gate

```bash
# In addition to DSN-host-substring check, verify destination admin-controllability:
audit_destination_admin_controllable() {
  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
    "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/")
  if [[ "$code" -ge 200 && "$code" -lt 300 ]]; then
    echo "PASS: destination org $SENTRY_ORG controllable (HTTP $code)"
    return 0
  else
    echo "FAIL: destination org $SENTRY_ORG returned HTTP $code — likely orphan/phantom"
    return 1
  fi
}
```

### Proposal W4 — `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` headed-Playwright propagation

When `feature` command creates a new worktree, optionally copy a `--config=/path/to/playwright-headed.json` arg into the worktree's `.mcp.json` so future Playwright drives inherit headed mode without per-worktree manual config. Gated on `SOLEUR_PLAYWRIGHT_HEADED=1` env var to preserve default behavior for headless-CI use cases.

### Proposal W5 — `/soleur:compound` should fail-friendly when on main, with worktree-create option

Current behavior: hard abort with "Error: compound cannot run on main/master. Checkout a feature branch first." Proposed: present the operator with a single-line offer: "Compound requires a feature branch. Create worktree `feat-compound-<topic>-<date>` and continue? [y/N]" so the workflow doesn't dead-end on the gate.

## Tags

category: process
module: brainstorm, incident, playwright-mcp, sentry-residency, gdpr
