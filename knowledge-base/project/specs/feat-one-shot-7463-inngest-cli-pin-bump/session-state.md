# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-29-infra-inngest-cli-pin-bump-freshness-plan.md
- Plan artifact: complete (selector=branch)
- Status: complete

### Errors
- iac-plan-write-guard rejected first full-plan write (systemctl tokens in prose) → reworded, no opt-out used.
- deepen-plan Phase 4.7 rejected suite-shaped discoverability command → dedicated sub-second probe script added to Files-to-Create.
- deepen-plan Phase 4.55 halt fired (hcloud_server.inngest -/+ replace) → Downtime & Cutover section added.
- Two stale `Closes #7463` remnants → corrected to `Ref #7463`.

### Decisions
- Two-PR split per UNTRUSTED-CI: PR-A = pin + checksums + provenance sidecar + offline staleness/coherence gate + mutation battery + re-spike evidence + ADR-100 amendment + C4 edits (admin-mergeable); PR-B = rule-audit.yml workflow step + parity-pinned guard suite (normal review-gated merge only).
- Monitor: per-PR offline gate via run-registered-suites.sh glob (rc 0/10/2) + 1st/15th poll filing one idempotent `inngest-pin-drift`+`action-required` issue; thresholds delta>=5 releases OR pin age>=45d; MAX_AGE_DAYS=60 sidecar-age backstop.
- Bump target = latest upstream at implementation time (v1.45.1 measured 2026-09-17 at plan time); both arch checksums from one signed release checksums.txt; delta recomputed via tag-ordered walk (position 33/271 measured; neither disputed figure restated).
- Merge is host-inert but pipeline-active: mint-inngest-bootstrap-tag.yml auto-fires on inngest* pin change → vinngest-v* tag + image + ADR-232 auto-authored cloud-init pin PR; live flip = that auto-PR + operator dispatch in a separate window; shared-Postgres + pre-flip backup preconditions (upstream goose migrations run on start; delta contains destructive cleanup migrations).
- `inngest pause` absent on both v1.19.4 and v1.45.1 → pre-existing dead call, deferred to a micro follow-up issue; all repo-passed flags, --postgres-max-open-conns sentinel, signkey-prod- strip, and MINUTES units verified against real binaries.

### Components Invoked
- soleur:plan (full), soleur:deepen-plan (full, inline sequential-fallback disclosure), lint-guard-contract.py, markdownlint-cli2, cloud-detect.sh, gh api/label verifications, sha256-verified downloads of real v1.19.4 and v1.45.1 binaries.

### Follow-ups prescribed at PR-A merge time
- File the `inngest pause` micro-issue and the `action-required`+`follow-through` apply-window tracker.
