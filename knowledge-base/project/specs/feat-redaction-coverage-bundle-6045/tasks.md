---
feature: redaction-engine coverage — detection passes
issue: 6045
branch: feat-redaction-coverage-bundle-6045
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-06-feat-redaction-coverage-detection-passes-plan.md
status: ready
---

# Tasks: Redaction-Engine Coverage (#6045)

Drift-guard first, then detection tranches. TDD every PR: failing evasion test → implement → GREEN.
Shared invariants (dedup `seen` keyed on `(class,value)`; new emit paths route through `_emit`→`_meta_redact`;
fan-out caps with inline rationale; tag suffix starts with `` ( ``) apply across all PRs — see plan.

## PR-A — item 8: drift-guard + digest-scrub sync

- [x] 1.1 Sync `digest-scrub.sh`: add `doppler_token` + `slack_token`; widen `env_var` vendors (+HETZNER/FLAGSMITH/RESEND/TAILSCALE), `pem` qualifier (`[A-Z0-9 ]*PRIVATE KEY`), `UUID` (`[0-9A-Fa-f]`); correct the header comment.
- [x] 1.2 Create `operator-digest/test/redact-class-parity.test.sh`: parse engine `PATTERNS` names; class-count self-test (`parsed == len(PATTERNS)`); assert each secret class present-in-digest OR in `DIVERGENCE_ALLOWLIST` (one-word rationale); `linear-urls.sh` out-of-set comment.
- [x] 1.3 GREEN + negative controls: guard passes synced; FAILs on a locally-unsynced class AND on a dropped `PATTERNS` entry.

## PR-B — item 1 (whitespace reflow) + item 6 (Cloudflare)

- [ ] 2.1 (RED) Reflow tests: two-engine (old MISSES / new CATCHES); distinct newline + space positives; no-FP on an INCLUDED prefix (`dp.st.`+prose); Test 4b on a reflow finding.
- [ ] 2.2 (RED) Cloudflare tests: upper+digit positive; git-SHA + kebab-prose negatives; add `cloudflare_token` to Test 2 loop + `positive-corpus.md`.
- [ ] 2.3 Implement item 6: `cloudflare_token` with lookaround boundaries + inline uppercase-AND-digit predicate; update guard allowlist (`cloudflare_token=not-in-digest`).
- [ ] 2.4 Implement item 1: `seen`/`_emit` dedup; `_scan_reflow` from a `reflow=True` `PATTERNS` marker; real-boundary guard; `REFLOW_WINDOW=512`; `_MAX_REFLOW_CANDIDATES`.
- [ ] 2.5 Trim item-1/item-6 lines from `redact-sentinel.sh` header (this PR). GREEN + Test 9 parity.

## PR-C — item 2 (decode) + item 3 (private-key DER)

- [ ] 3.1 (RED) Decode positives: base64 / base64url / hex / percent of a known secret; wrapped-base64 block. No-FP: data-URI image, `sha512-` SRI, git SHA/sha256, JWT→JSON-with-email, percent-encoded URL.
- [ ] 3.2 (RED) DER positives: headerless RSA + EC P-256 + Ed25519. DER no-FP: public X.509 cert, PNG/JPEG, `0x30 0x81` non-key. Add `pem_key_body` to Test 2 + corpus.
- [ ] 3.3 (RED) Behavioral fan-out bound test; Test 4b on a decode finding.
- [ ] 3.4 Implement `_scan_text` (anchored secret classes only — exclude IPv4/UUID/email).
- [ ] 3.5 Implement `_scan_encoded`: base64 candidate assembly (join wrapped lines) + per-candidate `try/except/continue`; hex (even-length); percent (`unquote` once); caps with rationale.
- [ ] 3.6 Implement item 3 DER discriminator: short+long-form length; inner `INTEGER` (private) → emit, inner `SEQUENCE` (cert) → reject. Update guard allowlist (`pem_key_body=not-in-digest`).
- [ ] 3.7 GREEN + Test 8 no-FP + parity.

## Phase Z — ADR + docs (in PR-C)

- [ ] 4.1 Amend `ADR-086-fail-closed-redaction-engine-contract` additively/dated: items 1/2/3/6 covered; residual gaps (encrypted-PKCS#8 headerless) recorded; 4/5/7 remain non-goals (#6104/#6105); full slug; note #6054 ordinal collision.
- [ ] 4.2 `redact-sentinel.sh` header matches final coverage.

## Ship

- [ ] Per PR: security-sentinel + gdpr-gate (PR-B/PR-C external-egress bar); `user-impact-reviewer` at review (single-user-incident); `Ref #6045` in PR bodies (close #6045 only after all three merge).
