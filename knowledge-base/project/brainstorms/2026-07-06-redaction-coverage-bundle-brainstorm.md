---
date: 2026-07-06
topic: redaction-engine post-MVP coverage bundle
issue: 6045
branch: feat-redaction-coverage-bundle-6045
pr: 6098
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
---

# Brainstorm: Redaction-Engine Post-MVP Coverage Bundle (#6045)

## What We're Building

Scoping (not designing) the residual-coverage follow-up to the fail-closed
redaction engine that shipped in PR #6032 under [ADR-086](../../engineering/architecture/decisions/ADR-086-fail-closed-redaction-engine-contract.md).
The engine (`plugins/soleur/skills/incident/scripts/redact-engine.py`, ~153 lines,
deterministic vendor-prefix/format-anchored patterns) scrubs secrets/PII from
egress artifacts (incident PIRs, `code-to-prd` PRDs, `legal-generate` output).
ADR-086 §"Scope boundary" names 8 items as explicit non-goals; #6045 is the
single tracker for them. This brainstorm decides **which to build, in what order,
and how to split PRs** — it does not design the passes.

## Why This Approach

The 8 items are not one work-stream. They separate on **false-positive risk** and
**consumer**:

- **Near-zero-FP anchored extensions** (#1 whitespace, #6 Cloudflare token, #3
  headerless PEM): drop-in additions to the one Python engine, each guarded by a
  new `redact-sentinel.test.sh` case. Ship first.
- **Bounded-FP decode layer** (#2 base64/hex/percent): a decode-and-rescan
  normalization pass; real coverage for k8s Secret manifests (base64 by
  convention). Ships second.
- **Tuning-heavy outliers** (#4 TR39 skeleton, #5 entropy detector): the ADR
  itself flags these as "separate high-false-positive approaches." #5 is a
  **fail-closed** gate — a false positive blocks the write and traps the operator
  in the unsatisfiable redact loop the sentinel explicitly guards against. Defer
  both until leak telemetry / a labeled corpus exists.
- **Second-consumer gating** (#7 legal-audit): near-nil new egress (findings quote
  *already-committed* docs). Split to its own issue.
- **Cross-redactor sync** (#8): the literal ask (NFKC into the two egress
  redactors) is architecturally impossible — `digest-scrub.sh` is pure-bash and
  bash cannot do NFKC (the reason the engine was ported to Python). The buildable
  residual is an allowlist-aware **class-list drift-guard test**.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| Detection scope | **Pure-win + base64** (#1, #6, #3, #2); defer #4, #5 | Ship the low-FP wins; #4/#5 need a corpus/tuning that doesn't exist |
| PR split | **PR-1:** #1 + #6 + #3 · **PR-2:** #2 decode · **PR-3:** #8 drift-guard | Each PR self-contained + sentinel-guarded; #8 lands after the classes it guards exist |
| #6 Cloudflare | **Must anchor** (`\bcf[-_]…` / context), not bare 40-char | A naked 40-char class collides with 40-hex git SHAs → FP spike (CTO) |
| Item 7 (legal-audit) | **Own fresh p3 issue**, out of this bundle | #6044 closed/converged; near-nil egress (already-public docs); keeps bundle detection-scoped |
| Item 8 (egress sync) | **Class-list drift-guard test**, allowlist-aware; no NFKC port, no ADR amendment | NFKC-in-bash is impossible; digest-scrub's missing Doppler/Slack is a *deliberate* subset that the guard must allowlist, not fail on |
| #4 TR39 + #5 entropy | **Deferred issue** with "needs-evidence" re-eval criteria | Adversarial-evasion / high-FP; residual gap already version-pinned by Test 12 |
| Priority | Relabel #1 (and the PR-1 group) toward **p2**; #8 stays p3 | #1/#3/#6 feed `code-to-prd`/`legal-generate` external egress (buyer/investor) — GDPR Art. 33/34 surface (CPO) |
| Review bar | PR-1/PR-2 → **security-sentinel + gdpr-gate**; PR-3 → standard | External-egress paths raise the bar; the drift-guard is internal-only |

## Open Questions

- **#8 drift-guard shape:** allowlist-aware parity (each deterministic class is
  present OR in a documented divergence allowlist) — final allowlist entries
  depend on PR-1/PR-2's landed class set, so PR-3 sequences last. Resolve at plan time.
- **#2 decode depth:** single-level decode-and-rescan vs. recursive (base64 of
  base64). Recommend single-level for v1 (YAGNI); revisit on evidence.
- **PR-1 vs PR-2 boundary:** #2 could fold into PR-1 if the decode pass is small;
  keep separate by default so the low-FP tranche merges without waiting on decode review.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO)

### Engineering (CTO)

**Summary:** Ranked all 8 by effort×FP; PR-1 = #1+#6+#3, PR-2 = #2 (+#4 only if
pursued). **Reject item 8 as written** — `digest-scrub.sh` is pure-bash `grep -oE`
and ADR-086 decision 1 states bash cannot do NFKC; the class-set half is already
"verbatim from redact-sentinel.sh," so the buildable residual is a class-list
drift-guard. Defer #5 (fail-closed FP traps the operator; no labeled corpus).
Anchor #6 (40-char ↔ git-SHA collision). Flagged the #6044-open premise as stale.

### Product (CPO)

**Summary:** p3-low is wrong for the accidental-leak items — #1 and #7 reach
external egress (`code-to-prd` PRDs → buyer/investor, `legal-generate`), so their
review bar is security-sentinel + gdpr-gate, not standard. Relabel #1 → p2. Strong
YAGNI case to defer #4/#5 (both target *deliberate* adversaries; threat model here
is *accidental* operator leak). #8's redactors are internal-only → standard bar.

### Legal (CLO)

**Summary:** Ranked by GDPR Art. 33/34 breach-surface weight: #1 > #2 (k8s Secrets
base64 by convention) > #6 (live-credential class, zero coverage) > #5 > #3 > #8 >
#7 > #4. Item 7 is low-urgency (findings quote already-committed docs — "redacting
the inline echo un-leaks nothing"). Item 8 **is** a real defensibility gap (three
regex sets will drift; can't claim a *uniform* control in a post-mortem) — at
minimum sync the deterministic high-value classes or document the uneven-control
justification.

## User-Brand Impact

- **Artifact:** the redaction engine's egress-scrub path (`redact-engine.py` +
  `redact-sentinel.sh`) feeding `code-to-prd` PRDs, incident PIRs, and
  `legal-generate` output.
- **Vector:** a real credential/PII secret survives the anchored-pattern scan
  (reflowed across a whitespace boundary, or base64-encoded in a k8s Secret
  manifest) and lands in an external-facing PRD or legal artifact — a GDPR
  Art. 33/34 breach on operator/customer data.
- **Threshold:** single-user incident.

## Session Errors

1. **#6044 open/closed race.** Initial `gh issue list --state open --search redaction`
   listed #6044 as open; two leaders independently found it CLOSED. Direct
   re-verify showed it closed COMPLETED 2026-07-06 13:16Z — closed *during* the
   brainstorm. Corrected item-7 routing (nothing open to coordinate against). Lesson:
   for a load-bearing state fact, `gh issue view <N> --json state,closedAt` beats a
   cached `--search` listing.
2. **Item-8 literal ask was unbuildable.** "Sync NFKC into the two egress redactors"
   presumes both can run NFKC; `digest-scrub.sh` is bash and cannot. The operator's
   first answer (ADR amendment) rested on that false premise; re-put with the CTO's
   architectural finding and the buildable drift-guard alternative.
