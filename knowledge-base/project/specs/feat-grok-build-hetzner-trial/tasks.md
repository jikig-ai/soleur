---
lane: cross-domain
branch: feat-grok-build-hetzner-trial
issue: 6545
plan: knowledge-base/project/plans/2026-07-16-feat-headless-grok-build-hetzner-trial-plan.md
---

# Tasks — Headless Grok Build Hetzner trial

## Phase 0 — Gates

- [x] 0.1 Live Hetzner inventory: free server slots vs account limit
- [x] 0.2 Confirm `cx33` (or ≥8 GB EU equivalent) stock in hel1
- [ ] 0.3 Decide Doppler config for `XAI_API_KEY` (operator-only)
- [ ] 0.4 Confirm soft API ceiling ($100/mo default unless operator overrides)

## Phase 1 — Terraform

- [x] 1.1 Add `enable_grok_dogfood` + server type/location variables
- [x] 1.2 Author `grok-dogfood.tf` (server, labels, cloud-init, firewall SSH)
- [x] 1.3 Outputs (IP, server id)
- [x] 1.4 `terraform validate` + plan with flag false (zero create)
- [ ] 1.5 Wire apply path / `-target` if required by root allowlist

## Phase 2 — Bootstrap

- [x] 2.1 Cloud-init or bootstrap: install pinned `grok` binary
- [ ] 2.2 Clone Soleur (no tenant git; no prd secrets)
- [x] 2.3 `config.toml` with Grok 4.5 default + placeholder local model block
- [ ] 2.4 Secret injection (0600 file / Doppler)

## Phase 3 — Measurement

- [x] 3.1 `grok-measure.sh` (streaming-json → TTFT, tok/s, cost fields)
- [x] 3.2 Three prompt classes (read / scoped edit / multi-tool)
- [x] 3.3 Parser test against fixture NDJSON
- [x] 3.4 Runbook with method + sample table template

## Phase 4 — Guards

- [x] 4.1 Default max-turns + deny rules documented
- [x] 4.2 No git push credentials by default
- [x] 4.3 Kill criteria in runbook

## Phase 5 — Trajectory docs + ledger

- [x] 5.1 Phase 2 open-model swap section (#6546)
- [x] 5.2 Product ACP trajectory (Claude SDK → Grok Build later epic)
- [ ] 5.3 Expense ledger row when host retained

## Phase 6 — Post-merge live trial

- [ ] 6.1 Enable flag + apply when slot free
- [ ] 6.2 Run measure suite; comment results on #6545
- [ ] 6.3 xAI billing alert (Playwright-attempt or verified console)
