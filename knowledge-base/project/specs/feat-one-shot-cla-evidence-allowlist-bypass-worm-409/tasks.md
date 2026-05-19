---
title: "Tasks — fix(cla-evidence): map R2 Lock Rules ObjectLockedByBucketPolicy to idempotent-duplicate"
lane: single-domain
plan: knowledge-base/project/plans/2026-05-18-fix-cla-evidence-allowlist-bypass-worm-409-plan.md
created: 2026-05-18
deepened: 2026-05-18
---

# Tasks

## Phase 0 — Preconditions

- [ ] 0.1 — Verify CWD is `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-cla-evidence-allowlist-bypass-worm-409` and `git branch --show-current` returns `feat-one-shot-cla-evidence-allowlist-bypass-worm-409`.
- [ ] 0.2 — Baseline grep: `grep -n 'ObjectLockedByBucketPolicy\|worm-duplicate' apps/cla-evidence/scripts/r2-conditional-put.sh` — expect zero matches (the fix has not landed yet).
- [ ] 0.3 — Run `bash apps/cla-evidence/scripts/upload-bypass.test.sh` — expect all existing cases pass (a/b/c/d/e/f/g/h).
- [ ] 0.4 — Run `bash apps/cla-evidence/scripts/upload-evidence.test.sh` — expect all existing cases pass (TS6.a-TS6.e).
- [ ] 0.5 — Verify existing `Bypass.c` (403 fast-fail) does NOT inject a `body_fixture` containing `ObjectLockedByBucketPolicy` — read lines 105-116 of `upload-bypass.test.sh`. If a stray body fixture from a prior test leaks into Bypass.c via `$work/body_fixture`, the new 403-broadening would flip Bypass.c's expected outcome from fast-fail to idempotent. The `Bypass.g` cleanup at line ~154 (`rm -f "$work/body_fixture"`) is the established pattern; verify Bypass.c reaches its `prime_403` without a leaked fixture in scope.

## Phase 1 — RED tests + harness extension

- [ ] 1.1 — In `apps/cla-evidence/scripts/upload-bypass.test.sh`, add new case `Bypass.b2`: 409 + body `<Error><Code>ObjectLockedByBucketPolicy</Code><Message>The object is locked by the bucket policy.</Message></Error>` → expect exit 0 + stdout contains `worm-duplicate-quarter status=409`. Reuse `mk_curl_stub` + `body_fixture` pattern from existing case Bypass.g. End the case with `rm -f "$work/body_fixture"` to avoid state pollution.
- [ ] 1.2 — Add new case `Bypass.b2b`: 403 + same body → expect exit 0 + stdout contains `worm-duplicate-quarter status=403`. Covers the CF-documented status envelope (error code 10069 documented at HTTP 403). End with body-fixture cleanup.
- [ ] 1.3 — Add new case `Bypass.b3`: 409 + body `<Code>SignatureDoesNotMatch</Code>` (a real R2 4xx code unrelated to bucket-policy WORM) → expect exit 2 + `::error::fatal-4xx status=409` AND body excerpt visible in annotation. Specificity guard. (Plan v1 used `ObjectLockedRetention`; deepen-pass found that code is NOT documented for R2 today.)
- [ ] 1.4 — Add new case `Bypass.b4`: 409 + empty body → expect exit 2 + `::error::fatal-4xx status=409` + `body=(empty body)`. Defensive fail-closed.
- [ ] 1.5 — **Extend `mk_curl_stub` in `apps/cla-evidence/scripts/upload-evidence.test.sh`** to honor `-o <file>`: copy the body-fixture mechanism from `upload-bypass.test.sh` lines 32-56 (6-line addition to the heredoc). This is a Phase 1 prerequisite — without it, TS6.f cannot exercise body-fixture injection.
- [ ] 1.6 — Add new case `TS6.f` to `upload-evidence.test.sh`: 409 + body `<Error><Code>ObjectLockedByBucketPolicy</Code><Message>The object is locked by the bucket policy.</Message></Error>` → expect exit 0 + stdout contains `worm-duplicate status=409`. Use the extended stub from 1.5.
- [ ] 1.7 — Run both test scripts. Expect Bypass.b2 + Bypass.b2b + TS6.f FAIL (current 4xx → fatal-4xx; expected exit 0). Bypass.b3 + b4 PASS (current behavior matches expected fatal-4xx). Commit as a single RED checkpoint with message naming the four failing cases.

## Phase 2 — GREEN implementation

- [ ] 2.1 — Edit `apps/cla-evidence/scripts/r2-conditional-put.sh`. Insert new classification arm between the existing 412 arm (lines 129-132) and the existing 5xx/429 retry arm (lines 134-143). The new arm:
  ```bash
  # 409 or 403 + ObjectLockedByBucketPolicy: R2 Lock Rules (bucket-wide WORM)
  # refused an overwrite of a key that already exists within the
  # maxAgeSeconds floor. Production observed status 409 (run 26042357131);
  # Cloudflare docs document error code 10069 at status 403. Both are
  # handled here — the body code is the stable identifier; the 4xx envelope
  # may shift between R2 implementation paths.
  #
  # Semantically equivalent to 412 PreconditionFailed in a non-WORM bucket —
  # the canonical record exists and is sealed by first-writer-wins. The body
  # match is intentionally specific to ObjectLockedByBucketPolicy: any other
  # 4xx body (e.g., SignatureDoesNotMatch, AccessDenied, or a future
  # object-key-lock code) falls through to the existing fatal-4xx arm and
  # surfaces in the operator annotation.
  if (( code == 409 || code == 403 )) && body_excerpt | grep -q -F '<Code>ObjectLockedByBucketPolicy</Code>'; then
    echo "worm-${dup_label} status=$code key=$key attempt=$attempt (worm-idempotent)"
    exit 0
  fi
  ```
- [ ] 2.2 — Update the header docstring (lines 8-16) to add the new classification row: `- 409/403 + ObjectLockedByBucketPolicy body → worm-${dup_label} label, exit 0 (Lock-Rules-enforced first-writer-wins; same audit property as 412 in non-WORM buckets).`
- [ ] 2.3 — Run `bash -n apps/cla-evidence/scripts/r2-conditional-put.sh` — expect exit 0 (shell syntax).
- [ ] 2.4 — Run `bash apps/cla-evidence/scripts/upload-bypass.test.sh` — all cases pass (a/b/c/d/e/f/g/h + b2/b2b/b3/b4).
- [ ] 2.5 — Run `bash apps/cla-evidence/scripts/upload-evidence.test.sh` — all cases pass (TS6.a-TS6.e + TS6.f).
- [ ] 2.6 — `shellcheck apps/cla-evidence/scripts/r2-conditional-put.sh` if available; non-blocking.

## Phase 3 — Learning + documentation

- [ ] 3.1 — Append a new `## 13. ` section to `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md` titled "R2 Lock Rules block duplicate canonical writes via ObjectLockedByBucketPolicy — the WORM-bucket idempotent-duplicate signal (not 412)". Cover: pre-WORM design comment, post-WORM behavior, the WORM-vs-412 distinction, the 409-vs-403 status-envelope discrepancy (production observed 409; CF docs document 403 for error code 10069), specificity caveat (only `ObjectLockedByBucketPolicy` is documented at R2 today), the chain-of-prior-PRs that exposed this gap (#3201 → #3920 → #3965 → #3969 → THIS).
- [ ] 3.2 — Add `[Updated 2026-05-18 — see §13]` markers at the end of §4 and §5 prose. Do NOT delete existing prose (historical record).
- [ ] 3.3 — Verify with `grep -nE '^## 13\.' knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md` — exactly 1 match. Also verify `awk '/^## 13\./{flag=1; next} /^## /{flag=0} flag' <file> | grep -c -E 'ObjectLockedByBucketPolicy|409|403'` returns ≥3.

## Phase 4 — Verification

- [ ] 4.1 — `bash apps/cla-evidence/scripts/upload-bypass.test.sh && bash apps/cla-evidence/scripts/upload-evidence.test.sh` — exit 0.
- [ ] 4.2 — `git grep -n 'fatal-4xx\|ObjectLockedByBucketPolicy\|worm-duplicate' apps/cla-evidence/` — verify new tokens land in r2-conditional-put.sh + both test files; no unintended call sites.
- [ ] 4.3 — `git diff --stat` — expect 4 files changed (r2-conditional-put.sh + upload-bypass.test.sh + upload-evidence.test.sh + learning .md), <250 LoC.
- [ ] 4.4 — `git diff main -- apps/cla-evidence/infra/ docs/legal/ plugins/soleur/docs/pages/legal/ apps/web-platform/scripts/cla-evidence/schema.ts` — empty (no infra, legal, or schema edits).
- [ ] 4.5 — AC1 jq object-shape check (three-dimension contract):
  ```bash
  jq -n \
    --arg has_body "$(grep -c 'ObjectLockedByBucketPolicy' apps/cla-evidence/scripts/r2-conditional-put.sh)" \
    --arg has_status "$(grep -c 'code == 409 || code == 403' apps/cla-evidence/scripts/r2-conditional-put.sh)" \
    --arg has_label "$(grep -c 'worm-${dup_label}' apps/cla-evidence/scripts/r2-conditional-put.sh)" \
    '{has_body: ($has_body|tonumber), has_status: ($has_status|tonumber), has_label: ($has_label|tonumber)}'
  ```
  Expect each value ≥1.
- [ ] 4.6 — AC11 stub-extension check: `grep -c "if \[\[ -n \"\\\$out_path\" && -f \"\$work/body_fixture\" \]\]" apps/cla-evidence/scripts/upload-evidence.test.sh` returns 1.

## Phase 5 — PR + post-merge

- [ ] 5.1 — Commit, push, open PR. Title: `fix(cla-evidence): map R2 Lock Rules ObjectLockedByBucketPolicy to idempotent-duplicate`. Body: `Ref #4009` (or whatever issue number is filed), reference run 26042357131, the prior-PR chain, the canonical-per-quarter WORM design property preserved.
- [ ] 5.2 — Post-merge: within 24h of merge, run `gh run list --workflow cla-evidence.yml --limit 5 --json conclusion,headBranch,createdAt,databaseId` and verify ≥1 row has `conclusion: success` AND `createdAt` > merge timestamp. Then `gh run view <databaseId> --log | grep -E 'worm-duplicate-quarter status=(409|403)'` returns ≥1 match in the "Record allowlist-bypass" step. If no natural bypass PR fires within 24h, push an empty commit to an existing open bypass PR (e.g., feat-pr-g-cohort-onboarding from the failing run) to retrigger.

## Quality gates

- AGENTS.md `cq-write-failing-tests-before` — Phase 1 satisfies RED-before-GREEN (commit isolated as RED checkpoint per task 1.7).
- AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to` — Task 5.1 uses `Ref #N` in body, not title.
- AGENTS.md `hr-write-boundary-sentinel-sweep-all-write-sites` — N/A (no DB writes).
- AGENTS.md `hr-no-dashboard-eyeball-pull-data-yourself` — Task 5.2 uses `gh run list --json` + `gh run view --log`, not dashboard-eyeball.
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` — N/A (success is logged to stdout as `worm-duplicate-*`; not a fallback).
- AGENTS.md `hr-when-in-a-worktree-never-read-from-bare` — Phase 0.1 verifies worktree CWD.
