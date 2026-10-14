---
title: "Tasks — egress resolver grace-window IP retention"
plan: knowledge-base/project/plans/2026-06-16-fix-egress-resolve-grace-window-retention-plan.md
lane: single-domain
date: 2026-06-16
---

# Tasks — egress resolver grace-window IP retention

Derived from `2026-06-16-fix-egress-resolve-grace-window-retention-plan.md`.
Test runner: `bash apps/web-platform/infra/cron-egress-firewall.test.sh` (a
`.test.sh`, NOT bun/vitest). `nft` is absent on CI — the behavioral retention
test exercises the logic in isolation against a tmp store + tiny
`GRACE_WINDOW_SECS`. Do NOT trigger prod crons.

## Phase 0 — Preconditions (verify before editing)

- 0.1 Re-read `apps/web-platform/infra/cron-egress-resolve.sh` — confirm the
  DESIRED_ALLOW build ends at L183 with `… | grep -E '^[0-9.]+$' | sort -u || true`,
  fail-safe-on-empty guard at L186, PRUNE flip L235-239, atomic apply L241-247,
  FAILCOUNT idiom L169 (`cat … 2>/dev/null || echo 0`).
- 0.2 Confirm `cron-egress-resolve.service` has NO `StateDirectory=` yet and runs
  as root (`Environment=HOME=/root`).
- 0.3 Confirm `server.tf` folds BOTH `cron-egress-resolve.sh` (L727) and
  `cron-egress-resolve.service` (L732) into `config_hash`, and cloud-init reads
  both via `${cron_egress_resolve_*_b64}` (same source files — no separate edit).
- 0.4 `git diff --stat` baseline: confirm GitHub CIDR files
  (`cron-egress-allowlist-cidr.txt`, `scripts/gen-github-egress-cidr*.sh`,
  `cron-github-cidr-refresh*`) are the untouched set.

## Phase 1 — RED (write failing drift-guards + behavioral test first)

- 1.1 In `cron-egress-firewall.test.sh` `-- resolver safety invariants --` block,
  add source-anchored guards (anchored on executable constructs, NOT comment
  prose — 2026-06-03 false-match class):
  - `GRACE_WINDOW_SECS` + `SEEN_DIR` assignments present.
  - eviction gated on the same `PRUNE`/`FAILED_HOSTS` flag (no-prune suppression).
  - readback re-filter (`^[0-9]+\.…$`) present on the store-union path.
  - strict-mode timestamp guard present (`[[ "$ts" =~ ^[0-9]+$ ]]` or the
    `cat … || echo 0` idiom).
- 1.2 Add `assert_grep "StateDirectory=cron-egress-resolve"` against
  `cron-egress-resolve.service`.
- 1.3 Add a behavioral test (extracted function / env-driven, mirroring the
  CIDR-validator copy pattern at test L243-250) exercising, with a tiny
  `GRACE_WINDOW_SECS`:
  - retention within window (stored-not-re-resolved IP RETAINED);
  - eviction after window (RETAINED → EVICTED + store entry removed);
  - no-prune suppresses eviction (`FAILED_HOSTS>0` → past-window entry kept);
  - no-prune STILL refreshes timestamp + unions (record/union run on every tick);
  - readback re-filter (non-dotted-quad store file never reaches the batch);
  - fail-safe-on-empty unchanged (ZERO current-tick → abort before reading store).
- 1.4 Run the suite; confirm the new asserts FAIL (RED) and the pre-existing
  invariant guards still PASS.

## Phase 2 — GREEN (implement)

- 2.1 `cron-egress-resolve.sh`: add `GRACE_WINDOW_SECS` (default 86400, env-overridable)
  + `SEEN_DIR` (default `/var/lib/cron-egress-resolve/seen`, env-overridable)
  constants; `mkdir -p "$SEEN_DIR"` beside the existing `mkdir -p "$FAILCOUNT_DIR"`.
- 2.2 After the fail-safe-on-empty guard (L186), insert the record-then-retain block:
  - record/refresh each current-tick IP's last-seen = `now` (ALWAYS — every tick);
  - union stored IPs whose last-seen within window into the retained set, re-filtering
    each value through the IPv4 regex on readback (ALWAYS);
  - evict store entries past the window ONLY when `FAILED_HOSTS == 0` (prune tick).
  - All bash strict-mode-safe: `ts="$(cat "$f" 2>/dev/null || echo 0)"; [[ "$ts" =~ ^[0-9]+$ ]] || ts=0`;
    `find "$SEEN_DIR" -type f` (or `nullglob`) for the sweep; `|| true` on union pipes.
- 2.3 Feed the retained set as the `desired` arg to `build_batch "$ALLOW_SET" …`
  (L242 path); leave the DNS-set branch (L243) untouched.
- 2.4 Extend the OK log line (L293) with a `retained=` count.
- 2.5 `cron-egress-resolve.service`: add `StateDirectory=cron-egress-resolve`
  under `[Service]`.
- 2.6 Re-run the suite → GREEN. Reconcile the `RESULT: N passed` count.

## Phase 3 — Runbook + verification

- 3.1 `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`:
  add "Remediation (LB-rotation IP-coverage gap, non-GitHub)" subsection
  (grace-window retention is now automatic; a recurring drop for an
  already-allowlisted LB host means the window is too short OR the store was
  wiped; the OK log carries a new `retained` count). Confirm the sentinel-name
  runbook-parity guard (test L454-475) still passes (no new server.tf sentinels
  → no new runbook rows required).
- 3.2 `bash -n cron-egress-resolve.sh` parses; `bash cron-egress-firewall.test.sh`
  exits 0; `bash apps/web-platform/infra/scripts/gen-github-egress-cidr.test.sh`
  exits 0 (proves CIDR side untouched).
- 3.3 `git diff --stat` shows NO change to the GitHub CIDR file/generator/cron set.

## Phase 4 — Ship

- 4.1 PR body: `Ref` the Sentry `egress-blocked` incident (not `Closes` —
  fix verifies post-apply); record CPO sign-off (threshold = single-user
  incident); `user-impact-reviewer` runs at review-time.
- 4.2 Post-merge (automated): `apply-web-platform-infra.yml` re-applies on the
  `apps/web-platform/infra/**` path filter; post-apply container probes stay green.
- 4.3 Post-merge (verify, no SSH / no dashboard-eyeball): via the incident skill's
  Sentry toolchain, confirm the `104.18.x`/`198.x`/`34.149.x` DST hit-rate trends
  to zero within one grace-window, and the six heavy eval-cron monitors recover
  to OK on their next scheduled fire. Do NOT trigger them.
