---
title: "tasks — fix secret-scan jwt.io colocated lib test allowlist"
lane: single-domain
plan: knowledge-base/project/plans/2026-05-19-fix-secret-scan-jwt-io-colocated-test-allowlist-plan.md
issue: 4099
related_issues: [4090, 4066]
status: ready
created: 2026-05-19
---

# Tasks — secret-scan jwt.io colocated lib test allowlist

Derived from `knowledge-base/project/plans/2026-05-19-fix-secret-scan-jwt-io-colocated-test-allowlist-plan.md`.

## 1. Phase 0 — Preconditions

- [ ] 1.1 — Verify local gitleaks v8.24.2 install (`gitleaks version`).
- [ ] 1.2 — Run baseline scan: `gitleaks git --no-banner --exit-code 0 --redact -v` → confirm 2 findings, both at `apps/web-platform/lib/safety/redaction-allowlist.test.ts:101`, in commits `0def2e2d` and `7cad1fa5`.
- [ ] 1.3 — Count baseline path entries: `grep -c "apps/web-platform/test/\.\*\\\\\\.test\\\\\.(ts|tsx)" .gitleaks.toml` → must equal **16**.
- [ ] 1.4 — Confirm new path NOT present: `grep -c "apps/web-platform/lib/\.\*\\\\\\.test\\\\\.(ts|tsx)" .gitleaks.toml` → must equal **0**.

## 2. Phase 1 — Widen `.gitleaks.toml` allowlists

- [ ] 2.1 — Edit `.gitleaks.toml`. For each of the 16 `[[rules.allowlists]] paths` lists (lines 103, 120, 133, 150, 162, 176, 188, 200, 215, 227, 241, 258, 278, 297, 308, 318), add `'''apps/web-platform/lib/.*\.test\.(ts|tsx)$'''` immediately after the existing `'''apps/web-platform/test/.*\.test\.(ts|tsx)$'''` entry.
- [ ] 2.2 — Verify pairing count: `grep -c "apps/web-platform/lib/\.\*\\\\\\.test\\\\\.(ts|tsx)" .gitleaks.toml` → must equal **16**.
- [ ] 2.3 — Local scan: `gitleaks git --no-banner --exit-code 1 --redact -v 2>&1 | tail -20` → must report `leaks found: 0` and exit 0.

## 3. Phase 2 — Smoke matrix case

- [ ] 3.1 — Edit `.github/workflows/secret-scan.yml`. Add `colocated-lib-test-allowlist` to the `jobs.smoke-tests.strategy.matrix.case` list at line ~267.
- [ ] 3.2 — Add a new `case` branch in the runner script (between the existing cases at lines 318-455) that mirrors `allowlist-positive` with the path swap:
  - `mkdir -p apps/web-platform/lib/safety/__smoke__`
  - `echo "$FAKE_DOPPLER" > apps/web-platform/lib/safety/__smoke__/with-secret.test.ts`
  - `git add apps/web-platform/lib/safety/__smoke__/with-secret.test.ts`
  - `./gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1` (must exit 0)
  - Echo `PASS: colocated lib test path didn't trip`
- [ ] 3.3 — Confirm the `FAKE_DOPPLER_PREFIX`/`FAKE_DOPPLER_BODY` split is REUSED, not re-introduced — the existing env block at lines 312-313 already defines them; no new literal needed (avoids GitHub push-protection block per learning `2026-05-04-gitleaks-secret-scanning-floor-rollout.md` §(b)).

## 4. Phase 3 — Local verification

- [ ] 4.1 — Full-tree scan exits 0: `gitleaks git --no-banner --exit-code 1 --redact -v && echo OK`.
- [ ] 4.2 — Capture output line for PR body (`scanned ~64 MB ... leaks found: 0`).

## 5. Phase 4 — PR creation

- [ ] 5.1 — Commit and push. Commit message MUST include `Allowlist-Widened-By: jean.deruelle@jikigai.com` trailer.
- [ ] 5.2 — Create PR via `gh pr create` with body containing `Closes #4090`, `Closes #4099`, local-scan output paste, 6-commit failure context.
- [ ] 5.3 — Apply label: `gh pr edit <N> --add-label secret-scan-allowlist-ack`.
- [ ] 5.4 — Verify `secret-scan / allowlist-diff` job posts a sticky comment via `gh pr view <N> --comments` listing the new path; comment text mentions the widening.
- [ ] 5.5 — Verify CI smoke matrix returns green for all 10 cases (9 existing + new `colocated-lib-test-allowlist`).
- [ ] 5.6 — Verify all PR checks green: `gh pr checks <N>`.

## 6. Phase 5 — Cross-PR advisory comment (conditional)

- [ ] 6.1 — Check PR #4066 state: `gh pr view 4066 --json state`. If `MERGED`, skip Phase 5.
- [ ] 6.2 — Otherwise post: `gh pr comment 4066 --body-file <comment-path>` recommending inline waiver on `redaction-allowlist.test.ts:101` with shape:
  ```ts
  // gitleaks:allow # issue:#4099 canonical jwt.io HS256 example, signed with published demo secret "your-256-bit-secret"
  ```

## 7. Phase 6 — Post-merge verification

- [ ] 7.1 — `/soleur:ship` Phase 7 watches the merge commit's `secret-scan` workflow; conclusion = `success`. Automated via `gh run watch`.
- [ ] 7.2 — Close issue #4099 explicitly if `Closes` did not fire (it should — this is not ops-remediation).
- [ ] 7.3 — Capture learning at `knowledge-base/project/learnings/bug-fixes/<date-chosen-at-write-time>-secret-scan-colocated-lib-test-allowlist-drift.md`. Topic: colocated-test convention drift between `apps/web-platform/test/` (allowlisted) and `apps/web-platform/lib/<m>/*.test.ts` (not allowlisted). Sharp edge: when adopting colocated tests in any new directory, audit all CI gates scoped to the legacy `test/` root.
