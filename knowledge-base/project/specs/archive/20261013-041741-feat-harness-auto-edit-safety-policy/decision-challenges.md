# Decision Challenges & Architecture Rulings — feat-harness-auto-edit-safety-policy

## CTO ruling 2026-07-06 — `rule-body-lint` required-context wiring (security-model fork)

**Question (routed to `soleur:engineering:cto`):** How to wire the new `rule-body-lint`
gate as a merge-blocker given that any `integration_id==15368` canonical required
context is forced (by `required-checks-canonical-parity.test.sh` Test 1) into
`scripts/required-checks.txt`, which the bot-PR composite action FABRICATES a green
check-run for (no per-check review, #6049) — a Goodhart bypass for exactly the
#6038 auto-proposer bot PRs the gate exists to guard.

**Ruling: Option (A)** — standalone `rule-body-lint` required context NOW
(canonical JSON + `infra/github/ruleset-ci-required.tf` + `required-checks.txt` +
drift-guard enrollment); defer the bot-preflight reproduction to #6038.

**Rationale:** Today the entire population of AGENTS-body writers is human PRs, and
(A) is a genuine non-deletable merge-blocker against them with the strongest
anti-deletion property (`.tf` "public ABI" + parity test + drift-guard). The bot
fabricated-green is a residual over a NULL SET: the bot action's `ALLOWED_PATHS`
= {weakness-digest.md, rule-metrics.json} makes AGENTS bodies physically unreachable
by every bot today. The only future bot that gains AGENTS write — #6038's auto-proposer
— cannot add `AGENTS.core.md` to `ALLOWED_PATHS` without tripping the #6049 Phase-4
guard, which structurally forces it to reproduce a content-scoped gate at that time.
(B) reproduce-now = premature surface on a load-bearing shared security action (YAGNI).
(C) fold-into-`test` = same bot residual, but fails AC9's letter and trades away the
ABI/anti-deletion strength — dominated for a single-user-incident guardrail.

**HARD IMPLEMENTATION CONSTRAINT (mandatory):** `rule-body-lint` MUST be an
**always-run** job (NO `paths:` filter) that concludes **green on the no-op path**
(no AGENTS body changed → `--check` passes), exactly like `enforce` /
`tenant-integration-required`. A path-gated required 15368 context never posts on
unrelated PRs → permanent `pending` → wedges every human PR. Short-circuit the WORK
internally (cheap `git diff --quiet`) but ALWAYS emit the context as success.

**Residuals recorded (per ruling):**
1. ADR-092 alternatives-considered + residual paragraph (fabrication residual; safe
   while ALLOWED_PATHS excludes AGENTS bodies; goes live only when #6038 extends it,
   which #6049 blocks until reproduction).
2. CODEOWNERS-gated comment on the `rule-body-lint` line in `required-checks.txt`:
   fabricated-not-earned for bot PRs; safe only while ALLOWED_PATHS excludes AGENTS;
   xref #6038 + action.yml preflight-TODO.
3. Preflight-TODO in `action.yml` Phase-4 ceiling: "#6038 MUST reproduce
   `rule-body-lint --check` over the bot diff BEFORE adding any AGENTS.{core,docs,rest}.md
   path to ALLOWED_PATHS."

**Two CTO verification asks (satisfied):**
- The new job posts as `integration_id 15368` (github-actions[bot], same as every
  other ci.yml job) — confirmed; the non-15368 exclusion escape is unavailable, so
  (A)'s calculus holds.
- Parity/anti-deletion enforced end-to-end: `rule-body-lint` in canonical JSON without
  the wired always-run ci.yml job must fail CI (lean on parity Test 1 +
  `lint-bot-synthetic-completeness.sh`; add coverage if a gap remains).

## Phase-0 verification (task 0.5, AC10) — live enforcement path

**CODEOWNERS-review is NOT enforced on `main`.** Live rulesets: "CI Required"
(status checks), "CLA Required", "Force Push Prevention" — none requires
pull_request reviews or code-owner review; no classic branch protection
(`branches/main/protection` → 404). The CODEOWNERS file header itself states branch
protection requiring CODEOWNERS review is a "separate operator follow-up (requires
repo-admin scope)".

**Therefore the ack's live control path = the required CI check `rule-body-lint` +
deliberate per-change ack authoring** (tamper-evidence + a conscious, reasoned,
hash-bound WORM entry), NOT a second-reviewer gate. CODEOWNERS rows on the new
load-bearing files are cheap belt-and-suspenders that become teeth the day branch
protection is enabled (already-tracked operator follow-up). ADR-092 + PR state this
honestly — no overclaim of "CODEOWNERS-gated human review" as a LIVE control.
