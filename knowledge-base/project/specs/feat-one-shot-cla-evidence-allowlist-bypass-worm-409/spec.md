---
title: "fix(cla-evidence): map R2 Lock Rules ObjectLockedByBucketPolicy to idempotent-duplicate"
lane: single-domain
type: bug
classification: standard
created: 2026-05-18
deepened: 2026-05-18
---

# Spec — Allowlist-bypass WORM 409 misclassification

## Problem

The cla-evidence workflow's "Record allowlist-bypass (per-quarter canonical)" step exits 2 with `::error::upload-bypass: fatal-4xx status=409 key=allowlist/<actor>/<quarter>.json body=<Error><Code>ObjectLockedByBucketPolicy</Code><Message>The object is locked by the bucket policy.</Message></Error>` on every allowlist-bypass PR after the first PR-of-quarter from each actor. This spams failed-check notifications across all open PRs.

Run id 26042357131 (workflow cla-evidence, branch feat-pr-g-cohort-onboarding, conclusion failure) is the canonical reproduction.

## Root cause

R2 Lock Rules (PR #3920: `maxAgeSeconds=315360000`, `prefix:""`) enforce a 10-year WORM floor bucket-wide. When the canonical-per-quarter key already exists, R2 returns `409 ObjectLockedByBucketPolicy` BEFORE the `If-None-Match: *` conditional-PUT precondition can fire 412. The current `r2-conditional-put.sh` classification arm at lines 145-153 treats 409 as a fast-fail config bug.

The canonical-per-quarter design property is "first-PR-of-quarter wins, byte-content sealed for 10 years" — which is exactly what R2 Lock Rules enforce. The misclassification is the bug; the data behavior is correct.

## Functional requirements

- **FR1** — `r2-conditional-put.sh` MUST map `(HTTP 409 OR HTTP 403) + body containing <Code>ObjectLockedByBucketPolicy</Code>` to the same idempotent-success arm as 412: stdout `worm-${dup_label} status=$code key=$key attempt=$attempt (worm-idempotent)`, exit 0. The status disjunction covers both the production-observed envelope (409, run 26042357131) and the CF-documented envelope (403, error code 10069).
- **FR2** — Any 409 or 403 body that does NOT contain `<Code>ObjectLockedByBucketPolicy</Code>` (e.g., `<Code>SignatureDoesNotMatch</Code>`, `<Code>AccessDenied</Code>`, empty body, any future object-key-lock code) MUST remain fast-fail with the existing `::error::fatal-4xx status=$code` annotation. Body match must be specific to `<Code>ObjectLockedByBucketPolicy</Code>`.
- **FR3** — The fix MUST live at the shared primitive layer (`r2-conditional-put.sh`) so both `upload-bypass.sh` (deterministic-per-quarter key) AND `upload-evidence.sh` (content-addressed key) inherit it. Both paths are subject to the bucket-wide Lock Rules.
- **FR4** — The new log token MUST be parameterized via `${DUP_LABEL}` (= `worm-duplicate-quarter` for bypass, `worm-duplicate` for evidence) so the two paths remain distinguishable in workflow logs.
- **FR5** — Classification arm order MUST be: 200/201 → 412 → WORM-bucket (409 or 403 + matching body) → 429/5xx → 4xx fatal → unexpected. The new arm sits between 412 and 5xx/429 to preserve symmetry with 412 and to fire before the generic 4xx catch.
- **FR6** — Existing test cases MUST continue to pass without modification. In particular, `Bypass.c` (existing 403 fast-fail) MUST remain green — its body fixture is verified NOT to contain `ObjectLockedByBucketPolicy` in Phase 0.
- **FR7** — `apps/cla-evidence/scripts/upload-evidence.test.sh`'s `mk_curl_stub` MUST be extended to honor `-o <file>` for body-fixture injection (mirror the upload-bypass.test.sh form at lines 32-56). This is a Phase 1 prerequisite for testing the new WORM-duplicate arm via the upload-evidence path.

## Non-functional requirements

- **NFR1** — No schema bump. The payload shape is unchanged.
- **NFR2** — No infrastructure change. The R2 bucket, Lock Rules, Doppler secrets, and Terraform remain unchanged.
- **NFR3** — No legal-document edit. The GDPR §3.4 balancing test text remains accurate (WORM via Lock Rules is preserved).
- **NFR4** — No `workflow_dispatch` added to `cla-evidence.yml`. Post-merge smoke uses push-to-existing-bypass-PR or next-natural-bypass-PR.
- **NFR5** — Body-match uses fixed-string `grep -q -F` against the existing `body_excerpt` helper output (preserving the 512-char cap from line 105).

## Acceptance criteria

See `knowledge-base/project/plans/2026-05-18-fix-cla-evidence-allowlist-bypass-worm-409-plan.md` ## Acceptance Criteria (AC1-AC10). Pre-merge ACs are verifiable by grep + test run; post-merge AC is verifiable via `gh run list --json`.

## Out of scope

- HEAD/GET-before-PUT idempotency (option (a) — rejected: adds round-trip, race window, weaker correctness).
- Per-run keys with mutable canonical pointer (option (b) — rejected: breaks WORM property in §3.4 balancing test).
- Object-key-level Lock Rule adoption (the bucket uses bucket-wide policy only; object-key locks are a separate feature surface).
- Re-architecting `upload-bypass.sh` or `upload-evidence.sh`. Fix is at the shared primitive layer only.
- Bumping `SCHEMA_VERSION` or modifying any consumer that asserts it.

## References

- Plan: `knowledge-base/project/plans/2026-05-18-fix-cla-evidence-allowlist-bypass-worm-409-plan.md`
- Design learning: `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md` §4 (412 design comment) + §5 (4xx classification table) + §13 (new — this fix's learning).
- Prior PRs in the failure chain: #3201, #3920, #3924, #3939, #3965, #3966, #3967, #3969.
- Failing run: 26042357131 (workflow cla-evidence, branch feat-pr-g-cohort-onboarding).
