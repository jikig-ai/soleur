---
feature: operator-weekly-digest
lane: cross-domain
brand_survival_threshold: single-user incident
tracking_issue: 5085
status: draft
decision: build-scheduled-skill-private-gh-issue-focused4
created: 2026-06-11
brainstorm: knowledge-base/project/brainstorms/2026-06-11-operator-weekly-digest-brainstorm.md
closes: 5085
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# Spec: Operator-Facing Weekly Comprehension Digest

## Problem Statement

Soleur's autonomous loops ship features, move money, publish content, and resolve incidents
faster than a solo **non-technical** operator can track what their company is actually doing —
**business comprehension debt** (Addy Osmani, *Loop Engineering*, June 2026). Soleur has
fragments (changelog, community digest, post-mortems, resume prompts) but **no unified,
operator-private artifact** that answers, in plain language, *"what did my company do this week?"*

The recently-shipped community release digest (#5080) is the inverse surface: public, brand-voiced,
and deliberately closed to published release notes only. The operator's comprehension need is
private and spans the internal business data that digest excludes (PRs, expenses, incidents, open
decisions). The brand-critical risk therefore inverts: not "private content leaking into a public
post," but **the operator's aggregated private business data reaching the wrong channel**.

## Goals

- Deliver a weekly, plain-language, **operator-private** digest of business-relevant activity.
- Reuse existing sources of truth (no re-derivation): expense ledger, post-mortems, `gh` PR/issue
  data, distribution-content frontmatter.
- Make the failure mode observable (never a silently-blank or silently-stopped week).
- Stay a *thin synthesizer* — gate any section expansion on a measured read/acted-on signal.

## Non-Goals

- **Not** a public/community artifact (that is #5080). No Discord/public channel in V1.
- **Not** a decision-routing system. The "Action needed" section *recaps and links* open
  `action-required` items; the operator inbox (#5103) remains the owner of low-latency decisions.
- **Not** a "content published" section in V1 (deferred — `campaign-calendar` already surfaces it).
- **Not** an Inngest/web-platform cron (the input KB files are not in that container image).
- **Not** email/Discord delivery in V1 (third-party processors; deferred behind an explicit ack + DPA).

## Functional Requirements

- **FR1 — Schedule & substrate.** A scheduled **skill** (e.g. `soleur:operator-digest`) invoked
  weekly (Friday, aligned to the release-digest window) via `soleur:schedule` (GitHub Actions, repo
  checked out). Manual-trigger path supported for testing.
- **FR2 — Section: What your company built.** Enumerate PRs merged in the window (`gh pr list
  --state merged --search merged:>=<date>`); Claude rewrites each into a business consequence — no
  PR numbers, file paths, branch names, or jargon.
- **FR3 — Section: Money & vendors.** Surface *this week's* expense/vendor changes by git-diffing
  `knowledge-base/operations/expenses.md` over the window (the ledger is a snapshot; "changes" = diff).
  Plain-language deltas in dollars.
- **FR4 — Section: What broke & whether it's fixed.** One line per **resolved, post-redaction**
  post-mortem (`knowledge-base/engineering/operations/post-mortems/*.md`, `status: resolved`).
  Summaries + links; never raw incident state.
- **FR5 — Section: Action needed from you.** Weekly recap (summary + count + links) of open issues
  labelled `action-required` ("Manual action needed from the CEO"). Reads the same signal the
  operator inbox (#5103) uses; does not mutate or route.
- **FR6 — Synthesis + deterministic fallback.** Claude synthesizes the digest in a calm
  chief-of-staff register. If synthesis fails, a deterministic fallback renders each section as
  operator-readable bullets (titles/links), never raw tags/IDs. Fallback output is verified for
  content quality, not just that it posts.
- **FR7 — Delivery.** Post the digest as a **private GitHub issue** in the operator's repo
  (`gh issue create`), deduped/labelled for findability. No fallback to any public channel.
- **FR8 — Editorial rule.** Every digest line states a business consequence or a required action,
  or it is cut (anti-vanity-report rule).

## Technical Requirements

- **TR1 — Secret/PII gate.** Run `plugins/soleur/skills/incident/scripts/redact-sentinel.sh`
  (or equivalent) on the fully-rendered digest **before** posting; **block** on non-zero exit
  (do not warn-and-continue).
- **TR2 — Input sanitation order.** Scrub secrets/PII from any LLM input **before** truncation and
  **before** any quantified regex (slice-before-regex; O(n²) stall guard — release-digest review-catch).
- **TR3 — LLM JSON parsing.** If the skill parses model JSON, fence-strip via `extractModelJson`
  (`apps/web-platform/server/model-json.ts`).
- **TR4 — Liveness/failure detection.** The Actions substrate lacks the Inngest Sentry heartbeat —
  define and implement a minimum "digest silently stopped" detector (Action-failure notification +
  optional lightweight heartbeat). [Open: exact mechanism — see brainstorm Open Question #2.]
- **TR5 — Read-signal instrumentation.** Define a falsifiable read/acted-on signal (issue reaction /
  reply / follow-up action) and gate future section expansion (content-published, etc.) on it.
- **TR6 — No public-channel coupling.** The delivery code path must not share a webhook/post helper
  with the community release digest; assert the destination is the private-repo issue API at call time.

## Acceptance Criteria

- A manual trigger produces a private GitHub issue containing the four V1 sections in plain language.
- Forcing an LLM failure still produces a usable, content-quality-verified fallback digest (positive
  happy-path test asserts `fallback: false` on the success path so a broken LLM call can't hide).
- A planted secret/PII token in source data causes the redaction gate to block the post (non-zero exit).
- No PR numbers, file paths, or branch names appear in the rendered operator-facing text.
- The "Action needed" section links to open `action-required` issues without mutating them.

## Open Questions (carried from brainstorm)

1. Exact read/consumption signal (TR5).
2. Liveness detector for the Actions substrate (TR4).
3. `expenses.md` git-diff window/format (FR3).
4. Confirm action-needed ↔ inbox (#5103) read the same signal (FR5).
