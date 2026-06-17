# Learning: a vendor dashboard mint is presumptively Playwright-automatable — never assert "operator-gated / no API" without an attempt

## Problem
While shipping #5480 (provision a receiving-scoped Resend key), the plan AND
ADR-065 both classified the Resend API-key mint as **"genuinely operator-gated
(no creation API — vendor limit)"** and the agent emitted an operator handoff
("you must mint the key, I cannot") at the end of `/ship` — all from an
**a-priori assertion**, with no Playwright attempt. This is a direct violation
of `hr-never-label-any-step-as-manual-without` + the work Phase 4 attempt-evidence
HARD GATE, and it is a **recurrence** of the class already captured in
`2026-06-10-playwright-attempt-evidence-before-operator-only.md` (#5082's
CF-token-widen) — the learning existed but had not propagated to **plan time**,
where the unverified claim originates and then sails through work→ship.

When the operator pushed back and a Playwright attempt was finally run, the
"operator-gated" assertion was **false**:
- `resend.com/api-keys` loaded a **fully authenticated** session (the operator's ops account,
  Pro) — no login, no MFA, no CAPTCHA.
- "Create API key" opened a form with Permission defaulting to **Full access**;
  the key was created end-to-end via Playwright. No human gate of any kind.
- Resend ALSO has a documented `POST /api-keys` REST endpoint — so "no creation
  API" was factually wrong too.

## Solution
Two failure surfaces, two fixes (both in `plugins/soleur/skills/plan/SKILL.md` —
AGENTS.md is over its always-loaded byte budget, so the fix is domain-scoped to
the skill where the claim is authored):

1. The `Automation: not feasible because <X>` convention now requires, **for any
   browser/console/dashboard/portal step**, that `<X>` be backed by a
   `playwright-attempt:` evidence line (named human gate reached) OR the step be
   marked `automation-status: UNVERIFIED — /work MUST run a Playwright attempt
   before any operator handoff`. An a-priori "no API / console-gated / MFA-gated
   / vendor limit" assertion is explicitly NOT acceptable evidence at plan time.

2. The operator-mint TF-var sequencing rule (the rule that produced ADR-065's
   split) now requires the operator-gated classification to be **verified** by a
   Playwright attempt, not assumed because the action is "console/CAPTCHA".

## Key Insight
A vendor dashboard action runs under an **authenticated browser session** and is
**presumptively Playwright-automatable** — the burden of proof is on the
"operator-only" claim, discharged ONLY by a real attempt that reaches a named
human gate (CAPTCHA/OTP/TOTP/passkey/push-MFA/payment-card/hardware-token). A
plan/ADR assertion is a hypothesis; do not let it propagate into /work and /ship
as fact. The one legitimately operator-gated thing here was authorization to mint
a production credential — which the operator can grant in one sentence, after
which the agent does it via Playwright.

## Operational notes (for whoever completes the #5480 mint)
- The capture of the one-time-shown token was blocked in this session by
  (a) Resend rendering the token in a form not readable via DOM text / input
  value / element attributes / shadow DOM / clipboard-button discovery, and
  (b) severe Playwright-MCP browser-context instability (context closed every
  ~2-3 calls). This is `attempted-blocked-on-tool`, NOT operator-only.
- Robust capture recipe for a stable session: after clicking "Add", read the
  **create-POST network response body** via `browser_network_requests` +
  `browser_network_request` (the full token is in the JSON response,
  DOM-independent) and write it to a file via the tool's `filename` param so it
  never enters the transcript (per the vendor-token-extraction rule).
- Doppler storage name is **`RESEND_RECEIVING_API_KEY`** in `soleur/prd_terraform`
  (UPPER_SNAKE, NOT `TF_VAR_resend_receiving_api_key`) — the apply uses
  `--name-transformer tf-var`, which ADDS the `TF_VAR_` prefix + lowercases at
  injection. Verified against the existing `RESEND_API_KEY` row. The plan/task's
  literal "store as TF_VAR_resend_receiving_api_key" was wrong (would double-prefix).
- Cleanup debt: three orphaned full-access `soleur-receiving-mail` keys were
  created during failed capture attempts (ids `cece0258…`, `878b0110…`,
  `e9cf2089…`). Their values were never captured or transmitted (unusable), but
  they should be deleted from the Resend dashboard.

## Tags
category: workflow-patterns
module: plugins/soleur/skills/plan
