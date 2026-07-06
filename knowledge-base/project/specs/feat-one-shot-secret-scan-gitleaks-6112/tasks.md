# Tasks — fix(security): secret-scan gitleaks allowlist false positives (#6112)

Plan: `knowledge-base/project/plans/2026-07-06-fix-secret-scan-gitleaks-allowlist-false-positives-plan.md`
Lane: single-domain

## Phase 0 — Preconditions
- [ ] 0.1 Reproduce: `gitleaks git --redact --no-banner --report-path /tmp/gl.json --exit-code 1`; confirm 2 rule/file pairs (`generic-api-key`→`.claude/rule-body-hashes.json`, `stripe-access-token`→`plugins/soleur/skills/incident/test/redact-sentinel.test.sh`).
- [ ] 0.2 Confirm `grep -c stripe-access-token .gitleaks.toml` == 0 (default-pack ⇒ top-level `[allowlist]` only).
- [ ] 0.3 Confirm `generic-api-key` same-id override exists (`.gitleaks.toml:319-328`).

## Phase 1 — Edit `.gitleaks.toml`
- [ ] 1.1 Append to top-level `[allowlist].paths` (`.gitleaks.toml:80-90`): `'''plugins/soleur/skills/.*/test/.*\.test\.sh$'''` with the skill-test-runner comment. issue:#6112
- [ ] 1.2 Append to top-level `[allowlist].paths`: `'''^\.claude/rule-body-hashes\.json$'''` with the generated-manifest comment. issue:#6112
- [ ] 1.3 (Decision already made in plan: both entries in top-level all-rules block; narrower single-file alternative for 1.1 documented if review requests it.)

## Phase 2 — Acknowledge + verify green
- [ ] 2.1 Re-run `gitleaks git --redact --no-banner --exit-code 1` → exit 0, "no leaks found."
- [ ] 2.2 Commit `.gitleaks.toml` with an `Allowlist-Widened-By: <name>` trailer (case-sensitive) so the `allowlist-diff` required check passes.
- [ ] 2.3 Verify no file other than `.gitleaks.toml` (+ `knowledge-base/**` artifacts) is in the fix diff.

## Phase 3 — Optional hardening note (no ruleset edit)
- [ ] 3.1 Confirm (read-only) that `gitleaks scan` is already a live required check (`infra/github/ruleset-ci-required.tf` Tier-1) — no `.tf` change. Record in PR body that action #4 is moot (post-merge full-tree scan is non-gateable).
- [ ] 3.2 (Optional) File a `type/security` follow-up issue: investigate why the required PR-diff `gitleaks scan` passed while the full-tree scan failed on the same lines. Do NOT block this PR.

## Acceptance Criteria (see plan for full list)
- [ ] Pre-merge: both allowlist entries present; `gitleaks git … --exit-code 1` exits 0; ack trailer present; required checks green; `Ref #6112` in PR body; only `.gitleaks.toml` changed.
- [ ] Post-merge: `push:main secret-scan` run green (`gh run list --workflow=secret-scan.yml --branch=main --limit 1`); `gh issue close 6112` after green confirmed.
