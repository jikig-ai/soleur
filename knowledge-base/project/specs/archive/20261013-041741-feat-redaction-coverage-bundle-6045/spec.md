---
feature: redaction-engine post-MVP coverage bundle
issue: 6045
branch: feat-redaction-coverage-bundle-6045
pr: 6098
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
created: 2026-07-06
brainstorm: knowledge-base/project/brainstorms/2026-07-06-redaction-coverage-bundle-brainstorm.md
adr: ADR-086
---

# Spec: Redaction-Engine Post-MVP Coverage Bundle

## Problem Statement

The fail-closed redaction engine (`plugins/soleur/skills/incident/scripts/redact-engine.py`,
shipped PR #6032 under ADR-086) defeats compatibility-char / invisible / bidi /
control / prefix-homoglyph evasion, but ADR-086 §"Scope boundary" names 8 residual
coverage gaps. The highest-weight gap is the **highest-probability *accidental*
leak**: a real secret reflowed across a whitespace/newline boundary by a
markdown/PDF renderer survives the anchored-pattern scan and can land in an
external-facing artifact (`code-to-prd` PRD, `legal-generate` output) — a GDPR
Art. 33/34 breach surface. This bundle closes the deterministic, low-false-positive
subset now and defers the tuning-heavy and separate-consumer items.

## Goals

- **G1** — Catch secrets split by meaningful whitespace/newline (collapse-and-rescan a
  high-entropy candidate run). *(Item 1 — highest breach-surface weight.)*
- **G2** — Add an **anchored** Cloudflare token class (`\bcf[-_]…` / context prefix, NOT
  a bare 40-char class — that collides with 40-hex git SHAs). *(Item 6.)*
- **G3** — Detect a headerless PEM key body via a long-base64-run heuristic. *(Item 3.)*
- **G4** — Decode reversibly-encoded blobs (base64/hex/percent, incl. k8s Secret
  manifests) and re-run the prefix classes. *(Item 2.)*
- **G5** — Add an allowlist-aware **class-list drift-guard** across the three redactors
  (`redact-engine.py`, `digest-scrub.sh`, `redact-linear-urls.sh`) so a class added to
  one but deliberately absent from another is asserted-in-allowlist, not silently drifted.
  *(Item 8 — buildable residual; NO NFKC port, NO ADR amendment.)*
- **G6** — Preserve the fail-closed contract and ERE↔`re` parity; every new class/pass
  ships with a synthesized `redact-sentinel.test.sh` case.

## Non-Goals

- **NG1** — Full cross-script TR39 homoglyph skeleton (#4). Adversarial-evasion only;
  residual gap already version-pinned by `redact-sentinel.test.sh` Test 12. **Deferred**
  to its own issue with needs-evidence re-eval.
- **NG2** — Unprefixed/high-entropy entropy detector (#5). High false-positive; a
  fail-closed FP traps the operator in the unsatisfiable redact loop the sentinel guards.
  **Deferred** until leak telemetry + a labeled corpus exist.
- **NG3** — `legal-audit` multi-surface redaction gating (#7, UC2). Near-nil new egress
  (quotes already-committed docs). **Split to its own p3 issue.**
- **NG4** — Porting `digest-scrub.sh` to Python for true NFKC parity. Reintroduces the
  `code-to-prd` python3-availability regression ADR-086 called out.
- **NG5** — Recursive/multi-level decode for #2 (base64-of-base64). Single-level v1 (YAGNI).

## Functional Requirements

- **FR1** — Whitespace/newline re-scan pass inserted after the strip→NFKC→strip→confusable
  pipeline (`redact-engine.py` ~line 129), before output: collapse whitespace inside a
  high-entropy candidate run, re-run `scan()`, report on the original offset.
- **FR2** — Anchored Cloudflare token class added to the `PATTERNS` registry (lines 78–103,
  after the Supabase group), with a prefix/context anchor to avoid the git-SHA collision.
- **FR3** — Headerless-PEM long-base64-run class in the same registry.
- **FR4** — Decode-and-rescan pass for base64/hex/percent candidate blobs (single-level),
  re-running the prefix classes on the decoded bytes.
- **FR5** — Drift-guard test enumerating each redactor's deterministic class list and
  asserting parity-or-allowlisted-divergence (digest-scrub's missing Doppler/Slack is a
  documented allowlist entry, not a failure).
- **FR6** — Each of FR1–FR4 adds a `redact-sentinel.test.sh` case: fixtures synthesized via
  `python3 -c … chr(0xXXXX)` (no committed literal invisibles; `cq-test-fixtures-synthesized-only`),
  `assert_exit` + `assert_grep` pairs, and an old↔new parity baseline (Test 9 pattern).

## Technical Requirements

- **TR1** — Preserve the fail-closed contract: green→red only on genuine detection, never
  a new availability regression on the python3-less runner path.
- **TR2** — Maintain ERE↔`re` golden parity (`redact-sentinel.test.sh` Test 9); the sentinel
  and engine must not diverge.
- **TR3** — All new patterns declared `re.ASCII` with explicit `\b` anchors + low-entropy
  lookahead markers, consistent with the existing registry.
- **TR4** — Review bar: PR-1 (FR1–FR3) and PR-2 (FR4) touch external-egress paths → run
  `security-sentinel` + `gdpr-gate`. PR-3 (FR5) is internal-only → standard bar.

## PR Split

1. **PR-1 (p2):** FR1 (whitespace) + FR2 (Cloudflare, anchored) + FR3 (headerless PEM).
2. **PR-2 (p3):** FR4 (base64/hex/percent decode-and-rescan).
3. **PR-3 (p3):** FR5 (allowlist-aware class-list drift-guard) — sequences last so its
   allowlist references the final landed class set.

## Deferred (tracked separately)

- #4 TR39 skeleton + #5 entropy detector → one "needs-evidence" deferred issue.
- #7 legal-audit gating → own p3 issue.
