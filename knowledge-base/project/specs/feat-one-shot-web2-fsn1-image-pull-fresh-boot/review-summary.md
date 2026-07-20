# Review Summary — PR #6395 (§1A GHCR credential re-fetch-on-failure)

Multi-agent review ran as one-shot Step 4 (2026-07-13). Change class: focused infra
credential-fallback (plan was ≥3-agent architecture-reviewed at plan time), so the
high-signal lenses were run rather than the full 8.

## Agents run
- **security-sentinel** — secret handling (token via `--password-stdin` only, cleared after,
  mock records user-not-token), fail-open integrity, log redaction, `SOLEUR_GHCR_READ_FILE`
  override: **all PASS**, no P1/P2. Two P3 notes (both pre-existing: latent `set -x` xtrace,
  cosmetic user rebind) → no action.
- **architecture-strategist** — parity between the two sites CONFIRMED symmetric; re-fetch-on-
  failure is the right durable layer; ADR-088 amendment correct (no new ordinal); scope deferral
  sound. Two P2s, both **file-a-follow-up** (not inline code): (1) enforce the Phase-2 "Vector
  ships logs" deferral by filing the tracker; (2) pre-existing terminal-serving-block observability
  gap. Both folded into the web-2-boot-observability follow-up (DC-1/DC-2).
- **code-quality-analyst** — shell correctness PASS; §1A test a faithful non-vacuous RED→GREEN;
  budget re-baseline (21,060 measured) necessary + still a ~1.5 KB tripwire; two-site duplication
  justified (pre-bootstrap seed can't share a baked helper). No P1/P2.
- **shellcheck** (deterministic bash gate; semgrep can't parse bash) — EXIT 0, every warning
  pre-existing, none in the added retry block.

## Disposition
- Fixed inline: 0 (no code findings — all lenses ship-ready).
- Filed as scope-out: 0 at review time → the web-2-boot-observability follow-up (Vector +
  terminal-block trap + `pull_failure_event` host_id + C4 edge) is filed at ship (DC-1/DC-2).
- P1 blocking: none.
