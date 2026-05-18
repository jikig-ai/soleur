---
title: "fix(cla-evidence): map R2 Lock Rules ObjectLockedByBucketPolicy to idempotent-duplicate (canonical-per-quarter)"
issue: 4009
related_issues: []
related_prs: [3201, 3920, 3924, 3939, 3965, 3966, 3967, 3969]
branch: feat-one-shot-cla-evidence-allowlist-bypass-worm-409
lane: single-domain
type: bug
classification: standard
created: 2026-05-18
deepened: 2026-05-18
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-05-18
**Sections enhanced:** 5 (Overview/Why, Research Insights, Files to Edit, Acceptance Criteria, Sharp Edges)
**Verification done in deepen-pass:**

- All cited PRs verified live MERGED via `gh pr view`: #3201, #3920, #3924, #3939, #3965, #3966, #3967, #3969.
- Failing run id 26042357131 verified live: `{conclusion: failure, workflowName: cla-evidence, headBranch: feat-pr-g-cohort-onboarding, createdAt: 2026-05-18T15:13:04Z}` — TODAY's run, confirms ongoing failure.
- Exact line numbers in `r2-conditional-put.sh` re-verified: 412 arm at 129-132, 5xx/429 at 134-143, 4xx fatal at 145-153.
- All cited AGENTS.md rule IDs verified active (`cq-write-failing-tests-before`, `wg-use-closes-n-in-pr-body-not-title-to`, `hr-write-boundary-sentinel-sweep-all-write-sites`, `hr-when-in-a-worktree-never-read-from-bare`, `hr-when-a-plan-specifies-relative-paths-e-g`, `hr-no-dashboard-eyeball-pull-data-yourself`, `cq-silent-fallback-must-mirror-to-sentry`).
- All cited labels verified exist (`cla-evidence`, `type/bug`, `domain/engineering`, `priority/p2-medium`).
- Empirical bash verification of the prescribed `(( code == 409 || code == 403 )) && body_excerpt | grep -q -F '<Code>ObjectLockedByBucketPolicy</Code>'` form under `set -euo pipefail` — all four expected cases (match, non-match, empty body, status-short-circuit) pass.

### Key Improvements vs. plan v1

1. **Status code broadened from `409` to `409 OR 403`.** Cloudflare's documented error code 10069 (`ObjectLockedByBucketPolicy`) is documented at HTTP status 403, but production run 26042357131 surfaced it at status 409. The empirical observation is authoritative for "fix the failing PRs today"; the documented status is also covered for robustness against future CF behavior changes within the documented range. The body code remains the stable identifier; the status code is just the 4xx envelope.
2. **Specificity claim corrected.** Plan v1 cited `ObjectLockedRetention` and `ObjectLockedLegalHold` as "object-key-level locks the bucket does not use." Live CF docs scan confirms ONLY `ObjectLockedByBucketPolicy` (error code 10069) is documented in R2's S3-API error table today. Updated test fixture in Bypass.b3 uses `<Code>SignatureDoesNotMatch</Code>` (a real R2 4xx code) as the realistic non-match counterexample. The specificity defense is preserved: any other body still fast-fails.
3. **`upload-evidence.test.sh` labeling + stub gap closed.** Plan v1 prescribed adding case `Evidence.b2` to upload-evidence.test.sh; the file actually uses `TS6.X` labels (TS6.a..TS6.e) AND its `mk_curl_stub` does NOT honor `-o <body_fixture>`. Renamed to `TS6.f`. Plan v2 prescribes extending the upload-evidence.test.sh stub with the body-fixture mechanism from upload-bypass.test.sh (lines 32-56) as a Phase 1 prerequisite for TS6.f to be testable.
4. **Empirical pipe-form verification added to Research Insights.** A 10-line test repro confirms `(( code == 409 || code == 403 )) && body_excerpt | grep -q -F '<Code>ObjectLockedByBucketPolicy</Code>'` behaves correctly under `set -euo pipefail` across all four expected cases. Pins the runtime contract so the implementer does not re-derive shell semantics at /work time.

# fix(cla-evidence): map R2 Lock Rules 409 ObjectLockedByBucketPolicy to idempotent-duplicate

Ref the run-26042357131 fast-fail surfaced by PR #3965. Failure mode:

```
upload-bypass: fatal-4xx status=409 key=allowlist/deruelle/2026-q2.json
body=<Error><Code>ObjectLockedByBucketPolicy</Code><Message>The object is locked by the bucket policy.</Message></Error>
```

Every allowlist-bypass PR from actor `deruelle` in 2026-Q2 retries the same canonical key (`allowlist/deruelle/2026-q2.json`) and hits R2 Lock Rules (WORM). Result: cla-evidence "Record allowlist-bypass" step exits 2 on every PR run, spamming failed-check notifications across all open PRs.

## Overview

### What

In `apps/cla-evidence/scripts/r2-conditional-put.sh` — the shared upload primitive consumed by `upload-evidence.sh` AND `upload-bypass.sh` — add an arm that maps `HTTP 409 OR 403` with body containing `<Code>ObjectLockedByBucketPolicy</Code>` to the same idempotent-success exit (exit 0) as the existing 412 arm. Surface the result with a distinct log token (`worm-duplicate` / `worm-${DUP_LABEL}`) so the two cases are distinguishable in operator logs.

The status-code disjunction (409 OR 403) covers both the production-observed status (run 26042357131 surfaced status 409) AND Cloudflare's documented status for error code 10069 (`developers.cloudflare.com/r2/api/error-codes/` documents `ObjectLockedByBucketPolicy` at HTTP 403). The body code `ObjectLockedByBucketPolicy` is the stable identifier; the 4xx envelope may shift between 409 and 403 depending on R2 implementation path. The disjunction is robust to either.

This is a one-file behavior change (~18 lines) plus tests. No infrastructure change, no Doppler write, no schema bump, no legal-doc edit.

### Why

R2's Lock Rules (10-year `maxAgeSeconds` floor, bucket-wide `prefix:""`) override the S3 conditional-PUT semantic when the object already exists within the retention window. Once `allowlist/<principal>/<quarter>.json` has been written, R2 refuses every subsequent overwrite with `<Code>ObjectLockedByBucketPolicy</Code>` (HTTP 409 in production today; HTTP 403 per CF docs) BEFORE the `If-None-Match: *` precondition can evaluate to 412. The design comment in `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md` §4 ("two concurrent workflow runs may both detect the same bypass event, but only one can win the write, and the loser exits cleanly without an error") was written against the pre-WORM build (PR #3201). PR #3920 (CF Lock Rules adoption) introduced the WORM floor; PR #3969 (creds fix) made authentication actually work for the first time; the 409/403 has been surfaced cleanly by PR #3965 (response-body capture). The remaining gap is the classification arm.

The canonical-per-quarter design property is **first-PR-of-quarter wins, byte-content sealed under WORM for 10 years**. R2 Lock Rules enforce exactly that. The current fast-fail-on-409 is therefore a *misclassification* of the WORM-bucket-policy duplicate as a config error.

### Why not the alternatives

- **(a) HEAD/GET before PUT** — adds a round-trip on every bypass PR (~99% of which are duplicates within a quarter), needs a content-comparison policy ("does this PUT byte-match the existing object?"), introduces a race window between HEAD and PUT, and still has to handle 409 from the PUT loser. Net: more code, same outcome, weaker correctness.
- **(b) Per-run keys with a mutable canonical pointer** — breaks the WORM property at the layer where it is legally load-bearing (`docs/legal/gdpr-policy.md` §3.4 balancing test claims a 10-year WORM-protected archive of the canonical bypass record). Any mutable pointer is a new attack surface the §3.4 prose would have to be reworded around. Not viable.
- **(c) Map `409 OR 403` + `ObjectLockedByBucketPolicy` to idempotent-duplicate** — this plan. Preserves WORM verbatim. The semantic of "the canonical record already exists and is sealed" is the same property the conditional-PUT path was trying to expose via 412. R2 happens to expose it via 409/403 because the Lock Rules layer evaluates first.

Option (c) is strictly the smallest change that closes the bug without weakening the legal claim.

### Research Insights

- The 412 idempotent-loser arm at `r2-conditional-put.sh:129-132` is the design template for the new WORM-duplicate arm: both signal "object already exists at this key with sealed bytes from a prior write."
- Both upload paths (`signatures/<sha>.json` content-addressed AND `allowlist/<principal>/<quarter>.json` deterministic-per-quarter) sit behind the same `r2-conditional-put.sh` primitive. Fixing at the shared primitive layer covers both the active bypass-canonical bug AND the dormant edit-without-change evidence case (a contributor edits their sign-comment to byte-identical text → identical sha → same key → Lock Rules block from R2). Per the existing learning Section 5 ("Kieran F7 single source of truth"), keeping all retry/classification in `r2-conditional-put.sh` is the established convention.
- R2's `<Code>ObjectLockedByBucketPolicy</Code>` body shape is the verbatim XML surfaced in run 26042357131's annotation. Matching against `<Code>ObjectLockedByBucketPolicy</Code>` (with the `<Code>` tags as anchors) is the stable identifier.
- **Status code envelope is 409 (observed) OR 403 (CF-documented).** Run 26042357131's annotation shows `status=409 ... body=<Error><Code>ObjectLockedByBucketPolicy</Code><Message>The object is locked by the bucket policy.</Message></Error>`. CF's [R2 Error Codes](https://developers.cloudflare.com/r2/api/error-codes/) page documents `ObjectLockedByBucketPolicy` (CF error code 10069) at HTTP status 403. The discrepancy is benign — the body code is the stable identifier, the 4xx envelope may shift between R2 implementation paths. Plan handles both.
- Body excerpting at `r2-conditional-put.sh:100-106` already strips newlines to a 512-char single line; the body-match check operates on that single line, so a simple `grep -q -F` works.
- **`ObjectLockedRetention` and `ObjectLockedLegalHold` are NOT documented R2 error codes today.** Live scan of `developers.cloudflare.com/r2/api/error-codes/` confirms only `ObjectLockedByBucketPolicy` (10069) is in R2's S3-API error table. The specificity defense in the test fixture uses `<Code>SignatureDoesNotMatch</Code>` instead — a real R2 error code, ensures any non-WORM-bucket-policy body still fast-fails. If CF later adds object-key-level lock codes, they will fall through to the existing fatal-4xx arm with the body visible in the annotation (operator-actionable, no silent regression).
- The 2026-05-04 learning Section 5 table already lists "4xx ≠ 412 | Config bug (stale token, missing perms, bucket lock violation)" — the existing prose treats "bucket lock violation" as a config bug. Post-fix the prose needs updating to distinguish "bucket-policy-locks-duplicate-canonical" (idempotent success) from "bucket-policy-locks-misconfigured-write" (config bug — won't happen in normal flow but kept fast-fail for defense in depth).
- **Empirical bash-form verification (deepen-pass):** the form `if (( code == 409 || code == 403 )) && body_excerpt | grep -q -F '<Code>ObjectLockedByBucketPolicy</Code>'; then ... fi` was tested under `set -euo pipefail` against four input cases: (a) 409 + matching body → enters branch; (b) 409 + non-matching body → does not enter branch; (c) 409 + empty body → does not enter branch (because `body_excerpt` prints `(empty body)`, which lacks the substring); (d) 412 + matching body → does not enter branch (status short-circuit). All four pass. The form is correct.

## Research Reconciliation — Spec vs. Codebase

| Issue/runbook claim | Codebase reality (verified 2026-05-18) | Plan response |
|---|---|---|
| "Every allowlist-bypass PR from actor `deruelle` in 2026-Q2 retries the same canonical key" | Confirmed via `apps/web-platform/scripts/cla-evidence/allowlist-bypass.ts::bypassRecordKey(principal, quarter)` — deterministic, no per-PR component. | This is the design; canonical-per-quarter is load-bearing for the audit property. Do NOT change key derivation. |
| "Root cause appears to be in `apps/cla-evidence/scripts/upload-bypass.sh`" | Partially correct: `upload-bypass.sh` computes the key and delegates classification to `r2-conditional-put.sh`. The misclassification (409 → fast-fail instead of idempotent success) lives in the shared primitive, lines 145-153. | Fix at `r2-conditional-put.sh` so both upload paths inherit the fix. `upload-bypass.sh` is unchanged. |
| "Maybe HEAD/GET first to skip if existing record covers same hash" | Adds round-trip + content-comparison policy + race window. R2 Lock Rules already enforce the desired semantic at the PUT boundary (the LATER write cannot displace the earlier). HEAD/GET would be belt-and-suspenders without strengthening the audit property. | Reject option (a) per "Why not the alternatives." |
| "Per-run keys + canonical pointer that's allowed to mutate" | Breaks GDPR §3.4 balancing test sub-bullet (1) ("write-once-read-many semantics via Cloudflare R2 Lock Rules") — a mutable pointer is by definition not WORM. | Reject option (b) per "Why not the alternatives." |
| "Prior fixes #3939/#3920/#3965/#3966/#3967/#3969 have NOT resolved this" | Confirmed: #3920 introduced WORM, #3965 made the failure legible (response body in annotation), #3969 made auth succeed (so the failure now reproduces every run instead of failing earlier with InvalidArgument/SignatureDoesNotMatch). The 409-classification gap was masked by the cred-shape gap until #3969 landed. | This plan is the immediate-next fix after #3969. The chain order: bad creds → wrong-shape secret → auth succeeds → first PUT lands → second PUT trips Lock Rules → 409 misclassified as config bug. |
| "Note: `.worktrees/fix-cla-evidence-bootstrap-r2-derivation` is on a merged branch with stale staged deletes" | Confirmed — that worktree corresponds to PR #3969 (merged), do not reuse. | Working in the fresh `feat-one-shot-cla-evidence-allowlist-bypass-worm-409` worktree. |
| Failing run id 26042357131 on branch `feat-pr-g-cohort-onboarding` | Confirmed: `gh run view 26042357131 --json conclusion,workflowName,headBranch` → `{conclusion: failure, workflowName: cla-evidence, headBranch: feat-pr-g-cohort-onboarding}`. | Smoke-test target post-merge: re-trigger the cla-evidence workflow on an open allowlist-bypass PR and assert exit 0 with `worm-duplicate-quarter status=409`. |

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in apps/cla-evidence/scripts/r2-conditional-put.sh apps/cla-evidence/scripts/upload-bypass.sh apps/cla-evidence/scripts/upload-evidence.sh apps/cla-evidence/scripts/upload-bypass.test.sh apps/cla-evidence/scripts/upload-evidence.test.sh apps/web-platform/scripts/cla-evidence/build-bypass.ts; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Result: **None.** No open code-review issues touch any of the files in this plan's edit scope.

## User-Brand Impact

**If this lands broken, the user experiences:** continued red `cla-evidence` checks on every allowlist-bypass PR for the rest of 2026-Q2 (and every quarter thereafter, once a quarter's first bypass PR lands), with the cla-evidence step exiting 2 and posting a failed check-run to every PR's status surface. Operators see persistent red-X notifications across all open PRs and learn to ignore the check, eroding the audit-signal value of the layer that justifies the 10-year WORM archive in `docs/legal/gdpr-policy.md` §3.4.

**If this leaks, the user's data is exposed via:** N/A. The fix is a status-code-to-exit-code mapping inside a CI workflow primitive; no data path is altered. The R2 bucket contents, the canonical-per-quarter audit property, the WORM floor, and the GDPR §3.4 balancing test are all preserved verbatim. No new processing, no widened data category, no change to lawful basis.

**Brand-survival threshold:** `none` — internal CI hygiene fix; the WORM property (the legally load-bearing one) is preserved.

**threshold: none, reason:** no sensitive path touched. The diff is `apps/cla-evidence/scripts/r2-conditional-put.sh` + its test + a one-paragraph append to `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md`. None match the canonical sensitive-path regex (no schema, no auth, no API route, no SQL, no migration, no `doppler*.{yml,yaml,sh}`, no infra Terraform, no .env, no secrets). Preflight Check 6 should record this scope-out unmodified.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO).

### Engineering (CTO)

**Status:** reviewed (inline analysis below — no separate domain-leader spawn needed for a single-file shell primitive change with established precedent at lines 129-132).
**Assessment:** Fix is at the shared primitive layer per the Kieran F7 single-source-of-truth convention established in PR #3201. The classification arm being added mirrors the 412 arm in exit shape and log format, with a status disjunction `(409 || 403)` to cover both the production-observed (run 26042357131: 409) and CF-documented (error code 10069: 403) envelopes. The body-substring match against `<Code>ObjectLockedByBucketPolicy</Code>` is the load-bearing identifier; the disjunction is the envelope filter. As of 2026-05-18, only `ObjectLockedByBucketPolicy` (10069) is documented in R2's S3-API error table; any future object-key-level lock codes (if R2 adds them) will fall through to the existing fatal-4xx arm and surface in the operator annotation, NOT be silently swallowed. The fix is strictly additive: any 4xx not bearing the WORM-bucket-policy body still falls through.

### Legal (CLO)

**Status:** reviewed (inline analysis — no domain-leader spawn).
**Assessment:** The 10-year WORM retention floor in `docs/legal/gdpr-policy.md` §3.4 sub-bullet (1) is preserved verbatim. The canonical-per-quarter audit record's byte content is still sealed by R2 Lock Rules from first-write through the 10-year window; this fix only changes the CI workflow's interpretation of the duplicate-overwrite-attempt status code, NOT the underlying object's protection. No Article 30 register update needed. No `compliance/critical` label needed. No prose edit to legal docs needed (the §3.4 prose names "WORM semantics via Cloudflare R2 Lock Rules (age-based retention floor, 10 years)" — still accurate).

### Product/UX Gate

**Tier:** none — no user-facing surface. CI-internal status-code classification change.

## GDPR / Compliance Gate (Phase 2.7)

`/soleur:gdpr-gate` canonical regex: does NOT trigger (no schema, no migration, no auth flow, no API route, no `.sql` file). Cross-controller (a)-(d) trigger expansions also do NOT fire: (a) no LLM/external-API processing of operator data, (b) brand-survival threshold is `none`, (c) no cron/workflow that READS from `knowledge-base/`, (d) no new artifact distribution surface. **Skip silently.**

## Infrastructure-as-Code Routing Gate (Phase 2.8)

Plan introduces no new infrastructure — pure shell-primitive behavior change. No `ssh root@`, no `doppler secrets set`, no `systemctl`, no vendor dashboard click-through, no new resource. **Skip silently.**

## Files to Edit

- **`apps/cla-evidence/scripts/r2-conditional-put.sh`** — add a new classification arm BEFORE the `(( code >= 400 && code < 500 ))` fast-fail arm at lines 145-153 (line numbers re-verified live in deepen-pass). The new arm:
  - Condition: `(code == 409 OR code == 403) AND body_excerpt contains '<Code>ObjectLockedByBucketPolicy</Code>'`. The disjunction covers both production-observed (run 26042357131: status 409) AND CF-documented (error code 10069: HTTP 403) envelopes.
  - Action: emit `worm-${dup_label} status=$code key=$key attempt=$attempt (worm-idempotent)` to stdout; `exit 0`. The `$code` echo preserves whichever 4xx envelope R2 used so operators can correlate to the actual run log.
  - Rationale comment block explaining why a Lock-Rules-blocked overwrite is the WORM-bucket equivalent of 412 PreconditionFailed: the canonical-per-quarter design property is "first-PR-of-quarter wins, byte-content sealed for 10 years"; Lock Rules enforce that property at the bucket layer BEFORE the conditional-PUT precondition can fire 412; the loser of the duplicate-write race exits cleanly with exit 0.
  - Verbatim body-match string: `'<Code>ObjectLockedByBucketPolicy</Code>'` (with the `<Code>` tags). Match via `grep -q -F` (fixed-string, no regex metacharacters) against the existing `body_excerpt` output. The body has already been newline-stripped by `body_excerpt()` at lines 100-106; the substring is robust to surrounding whitespace.
  - Use `body_excerpt | grep -q -F '<Code>ObjectLockedByBucketPolicy</Code>'`, NOT inlining the body file read, so the 512-char cap from the helper is preserved (prevents a future malicious-bucket-redirect from blowing up the classification logic with megabytes of HTML).
  - Update the header docstring comment block (lines 8-16) to add the new classification: `- 409/403 + ObjectLockedByBucketPolicy body → worm-${dup_label} label, exit 0 (Lock-Rules-enforced first-writer-wins; same audit property as 412 in non-WORM buckets).` Keep the existing rows.

- **`apps/cla-evidence/scripts/upload-bypass.test.sh`** — add THREE new test cases after `Bypass.b` (the existing 412 idempotent case), preserving the existing test alphabet:
  - **`Bypass.b2`**: 409 + body `<Error><Code>ObjectLockedByBucketPolicy</Code><Message>The object is locked by the bucket policy.</Message></Error>` → exit 0 + stdout contains `worm-duplicate-quarter status=409` AND does NOT contain `::error::`. This is the verbatim regression case from run 26042357131. Use the existing `mk_curl_stub` + `body_fixture` pattern (lines 32-56 + 150-152 — already exercised by Bypass.g).
  - **`Bypass.b2b`**: 403 + same body → exit 0 + stdout contains `worm-duplicate-quarter status=403`. Covers the CF-documented status envelope (error code 10069: HTTP 403). Same fixture, different code prime.
  - **`Bypass.b3`**: 409 + body containing `<Code>SignatureDoesNotMatch</Code>` (a real R2 4xx code unrelated to bucket-policy) → fast-fail with `::error::fatal-4xx status=409` AND body excerpt visible in annotation. Defends the specificity of the match: only `ObjectLockedByBucketPolicy` body is idempotent; any other 4xx body still fast-fails. (Plan v1 used `ObjectLockedRetention` here; deepen-pass found that code is NOT documented for R2 today — `SignatureDoesNotMatch` is a real R2 code, more realistic counterexample.)
  - **`Bypass.b4`**: 409 + empty body (defensive: R2 hypothetically returns 409 without a body) → fast-fail with `::error::fatal-4xx status=409`. Empty body cannot prove idempotency; fail closed because `body_excerpt` emits `(empty body)`, which lacks the substring.
  - Place the new cases between Bypass.b (412) and Bypass.c (403 fast-fail) to keep the test file's status-code-ascending order. (Note: Bypass.c remains a fast-fail case because its body is presumed not to contain `ObjectLockedByBucketPolicy` — the existing `prime_403` block emits no body fixture. Verify in Phase 0.)

- **`apps/cla-evidence/scripts/upload-evidence.test.sh`** — extend the test harness AND add ONE new test case:
  - **Stub extension (Phase 1 prerequisite for TS6.f).** The existing `mk_curl_stub` (lines ~27-39, scoped to upload-evidence) does NOT honor `-o <file>` (unlike upload-bypass.test.sh's stub at lines 32-56). Port the body-fixture mechanism from upload-bypass.test.sh: detect `-o <out_path>` in argv, and if `$work/body_fixture` exists, copy it to the out path. This is a 6-line addition to the stub heredoc; mirror the upload-bypass.test.sh form verbatim for parity.
  - **`TS6.f`** (next free slot — existing labels are TS6.a..TS6.e): 409 + body `<Error><Code>ObjectLockedByBucketPolicy</Code><Message>The object is locked by the bucket policy.</Message></Error>` → exit 0 + stdout contains `worm-duplicate status=409`. Covers the dormant edit-without-change evidence-record case (a contributor edits their sign-comment to byte-identical text → identical sha → same key → Lock Rules block from R2). The fix at the shared primitive makes this automatically work; the test pins the contract so a future refactor cannot regress it. (Note label: `TS6.f`, not `Evidence.b2` — the file uses `TS6.X` convention.)

- **`knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md`** — append a new Section 13 entitled "R2 Lock Rules block duplicate canonical writes via ObjectLockedByBucketPolicy — the WORM-bucket idempotent-duplicate signal (not 412)". Body covers:
  - The 412 design comment in §4 was written against the pre-WORM build (PR #3201). After PR #3920 introduced bucket-wide Lock Rules with `maxAgeSeconds:315360000`, the Lock Rules layer evaluates BEFORE the conditional-PUT precondition. The loser of a duplicate write therefore gets `<Code>ObjectLockedByBucketPolicy</Code>` (HTTP 409 in production, HTTP 403 per CF docs at error code 10069), not 412 PreconditionFailed.
  - The behavior is correct (the audit property "first-PR-of-quarter wins, sealed for 10 years" is preserved); the bug was in the CI primitive treating the 4xx as a config error.
  - The §5 4xx table is updated to add a new row: `409 or 403 + <Code>ObjectLockedByBucketPolicy</Code> body | WORM-bucket duplicate (first-writer-wins) | exit 0 — log as 'worm-duplicate status=$code'`. Distinct from the existing "4xx ≠ 412" row which now reads "4xx ≠ 412 AND NOT a WORM-bucket-policy duplicate" for the config-bug fast-fail case.
  - The specificity caveat: as of 2026-05-18, only `ObjectLockedByBucketPolicy` (CF error code 10069) is documented in R2's S3-API error table. Object-key-level locks (`ObjectLockedRetention` / `ObjectLockedLegalHold` in standard S3 vocabulary) are NOT documented for R2. The match string MUST stay specific to `<Code>ObjectLockedByBucketPolicy</Code>` so any future addition of object-key lock codes does NOT silently swallow them at the idempotent-duplicate arm — they will fall through to fatal-4xx with the body visible in the annotation.
  - The status-envelope discrepancy: production run 26042357131 (2026-05-18T15:13:04Z) emitted status 409; CF docs document error code 10069 at status 403. The plan handles both. The body code is the stable identifier.
  - Cross-reference §4 + §5 with a `[Updated 2026-05-18 — see §13]` pointer; do NOT delete the existing prose (historical record, still accurate against the pre-WORM build).
  - Note that PR #3969 made authentication actually succeed for the first time (prior 4xx failures were `InvalidArgument`/`SignatureDoesNotMatch` from the cred-shape bug); this fix is the immediate-next layer's gap exposed once auth started working.

## Files to Create

None.

## Implementation Phases

### Phase 0 — Preconditions (`/work` Phase 0)

- Confirm CWD is `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-cla-evidence-allowlist-bypass-worm-409` and the worktree's `git branch --show-current` equals `feat-one-shot-cla-evidence-allowlist-bypass-worm-409`. Per AGENTS.md `hr-when-in-a-worktree-never-read-from-bare`.
- `grep -n 'ObjectLockedByBucketPolicy\|worm-duplicate' apps/cla-evidence/scripts/r2-conditional-put.sh` — expect no matches (verifies the fix has not landed yet; baseline for the RED phase).
- `bash apps/cla-evidence/scripts/upload-bypass.test.sh` — expect all existing cases to pass (verifies no pre-existing regression at the test entry point).
- `bash apps/cla-evidence/scripts/upload-evidence.test.sh` — expect all existing cases to pass.

### Phase 1 — RED tests

Add the four new cases to `apps/cla-evidence/scripts/upload-bypass.test.sh` (`Bypass.b2`, `Bypass.b2b`, `Bypass.b3`, `Bypass.b4`); extend `mk_curl_stub` in `apps/cla-evidence/scripts/upload-evidence.test.sh` to honor `-o <file>` body fixtures (mirror upload-bypass.test.sh lines 32-56); add the `TS6.f` case. Commit as a single RED checkpoint.

- Run `bash apps/cla-evidence/scripts/upload-bypass.test.sh` — Bypass.b2 + Bypass.b2b fail (current behavior: 4xx → fatal-4xx exit 2, expected: exit 0). Bypass.b3 + b4 already pass (current fatal-4xx behavior matches the expected fatal-4xx for these defensive cases — they exercise the test's NEW assertion shape, not new SUT behavior, but pinning them now prevents a future regression that broadens the match too far). Document this in the commit message.
- Run `bash apps/cla-evidence/scripts/upload-evidence.test.sh` — TS6.f fails (same reason as Bypass.b2 — Lock Rules block, current treats as fatal-4xx).
- Per AGENTS.md `cq-write-failing-tests-before`, the failing test must exist as a separate commit (or co-located in a single commit with a clear RED-then-GREEN message structure) before the implementation lands. Single-commit RED+GREEN is acceptable per the rule's body; checkpoint isolation is preferred.

### Phase 2 — GREEN implementation

Edit `apps/cla-evidence/scripts/r2-conditional-put.sh`:

1. Add the new arm between the existing 412 arm (currently lines 129-132) and the existing 5xx/429 retry arm (currently lines 134-143). Placement matters: classification ordering is "200/201 → 412 → WORM-bucket-policy (409 or 403) → 429/5xx → 4xx → unexpected." This ordering keeps the new arm symmetric with 412 (both are "object already exists; exit 0 idempotent") and ensures the WORM-bucket case is checked BEFORE the generic 4xx fast-fail catches it.
2. The arm shape:
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
   Note `body_excerpt` is a function (lines 100-106); the call form `body_excerpt | grep` is correct — `body_excerpt` writes to stdout via `printf`/`tr`/`head -c`. Empirically verified in deepen-pass under `set -euo pipefail` for all four expected cases (match, non-match, empty body, status short-circuit).
3. Update the header docstring (lines 8-16) to add the new row.
4. Run `bash apps/cla-evidence/scripts/upload-bypass.test.sh` — all cases pass, including Bypass.b2/b2b/b3/b4.
5. Run `bash apps/cla-evidence/scripts/upload-evidence.test.sh` — all cases pass, including TS6.f.
6. Run `bash -n apps/cla-evidence/scripts/r2-conditional-put.sh` — no syntax errors.
7. Run `shellcheck apps/cla-evidence/scripts/r2-conditional-put.sh` if shellcheck is on PATH; otherwise note as nice-to-have, not blocking.

### Phase 3 — Learning + doc append

- Append Section 13 to `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md` per the "Files to Edit" spec above.
- Add `[Updated 2026-05-18 — see §13]` markers at the end of §4 and §5 prose (NOT deleting the existing text).
- `bash plugins/soleur/test/components.test.ts` style budget gate does NOT apply (this is a learning file, not a SKILL.md description).

### Phase 4 — Verification (local)

- Re-run both test scripts: `bash apps/cla-evidence/scripts/upload-bypass.test.sh && bash apps/cla-evidence/scripts/upload-evidence.test.sh` — exit 0.
- `git grep -n 'fatal-4xx\|ObjectLockedByBucketPolicy\|worm-duplicate' apps/cla-evidence/` — verify the new tokens land in `r2-conditional-put.sh` and both test files, and that no other call sites are accidentally affected.
- `git diff --stat` — expect 4 files changed (`r2-conditional-put.sh`, `upload-bypass.test.sh`, `upload-evidence.test.sh`, learning .md), small diff (<200 LoC).

### Phase 5 — Post-merge smoke (operator-runnable, not a manual step)

After merge, re-trigger the cla-evidence workflow on an open allowlist-bypass PR within 2026-Q2 (e.g., the failing run 26042357131's PR `feat-pr-g-cohort-onboarding`):

```bash
gh workflow run cla-evidence.yml --ref main  # if workflow_dispatch is wired
# OR push an empty commit to one of the open bypass PRs to retrigger pull_request_target
```

Then `gh run list --workflow cla-evidence.yml --limit 3` and verify the "Record allowlist-bypass (per-quarter canonical)" step exits 0 with stdout `worm-duplicate-quarter status=409 key=allowlist/<actor>/2026-q2.json attempt=1 (worm-idempotent)`. This is the canonical confirmation that the fix landed in CI.

If the workflow does NOT have `workflow_dispatch`, the smoke is "next allowlist-bypass PR opened after merge transitions from red to green." Either confirmation closes the verification gate.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — `apps/cla-evidence/scripts/r2-conditional-put.sh` contains the new classification arm with body-match `<Code>ObjectLockedByBucketPolicy</Code>` AND status disjunction `code == 409 || code == 403` placed between the existing 412 arm and the existing 5xx/429 arm. Verify (object-shape, multi-dimension contract):
  ```bash
  jq -n \
    --arg has_body "$(grep -c 'ObjectLockedByBucketPolicy' apps/cla-evidence/scripts/r2-conditional-put.sh)" \
    --arg has_status "$(grep -c 'code == 409 || code == 403' apps/cla-evidence/scripts/r2-conditional-put.sh)" \
    --arg has_label "$(grep -c 'worm-${dup_label}' apps/cla-evidence/scripts/r2-conditional-put.sh)" \
    '{has_body: ($has_body|tonumber), has_status: ($has_status|tonumber), has_label: ($has_label|tonumber)}'
  ```
  Expect `{has_body >=1, has_status >=1, has_label >=1}`. The three-dimensional check matches the three-dimensional contract (body match, status disjunction, log token) — single-grep would false-pass on partial implementation.
- [ ] **AC2** — `bash apps/cla-evidence/scripts/upload-bypass.test.sh` exits 0 with all cases passing (existing a/b/c/d/e/f/g/h + new b2/b2b/b3/b4).
- [ ] **AC3** — `bash apps/cla-evidence/scripts/upload-evidence.test.sh` exits 0 with all cases passing (existing TS6.a-TS6.e + new TS6.f).
- [ ] **AC4** — `bash -n apps/cla-evidence/scripts/r2-conditional-put.sh` exits 0 (shell syntax).
- [ ] **AC5** — `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md` contains a new `## 13. ` section whose body names `ObjectLockedByBucketPolicy`, the WORM-bucket-vs-412 distinction, AND the 409/403 status-envelope discrepancy. Verify:
  ```bash
  grep -nE '^## 13\.' knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md  # exactly 1 match
  awk '/^## 13\./{flag=1; next} /^## /{flag=0} flag' knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md | grep -c -E 'ObjectLockedByBucketPolicy|409|403'  # >=3
  ```
- [ ] **AC6** — The change is strictly additive: existing test cases continue to pass without modification. Verify (corrected per AGENTS.md sharp-edge on `awk` self-match and `git diff` semantics): for each of `upload-bypass.test.sh` and `upload-evidence.test.sh`, run `git diff main -- <file>` and confirm any `-` line is part of a hunk that adds the new cases (no removal of existing `PASS:` literal strings). A simple smoke: `git show main:apps/cla-evidence/scripts/upload-bypass.test.sh | grep -E 'PASS: (Bypass|TS6)\.' | sort > /tmp/pre.txt; grep -E 'PASS: (Bypass|TS6)\.' apps/cla-evidence/scripts/upload-bypass.test.sh | sort > /tmp/post.txt; comm -23 /tmp/pre.txt /tmp/post.txt` must be empty (no pre-existing PASS strings deleted).
- [ ] **AC7** — PR body uses `Ref #N` (or `Closes #N` if a tracking issue is filed), NOT in the title, per `wg-use-closes-n-in-pr-body-not-title-to`. If no tracking issue is created, omit the cross-link entirely.
- [ ] **AC8** — No new infrastructure resource added. Verify: `git diff main -- apps/cla-evidence/infra/` is empty.
- [ ] **AC9** — No legal-doc edits. Verify: `git diff main -- docs/legal/ plugins/soleur/docs/pages/legal/` is empty. (The WORM property and the §3.4 balancing test are preserved verbatim; this fix is a CI-classification change.)
- [ ] **AC11** — `upload-evidence.test.sh`'s `mk_curl_stub` honors `-o <file>` for body-fixture injection. Verify: `grep -c "if \[\[ -n \"\\\$out_path\" && -f \"\$work/body_fixture\" \]\]" apps/cla-evidence/scripts/upload-evidence.test.sh` returns 1 (mirrors the upload-bypass.test.sh form at line ~46-48).

### Post-merge (operator)

- [ ] **AC10** — Within 24 hours of merge, the cla-evidence workflow exits 0 on at least one allowlist-bypass PR run (either by re-triggering an existing PR or by the next allowlist-bypass PR opened). Verify via `gh run list --workflow cla-evidence.yml --limit 5 --json conclusion,headBranch,createdAt,databaseId` — at least one row has `conclusion: success` AND `createdAt` after the merge timestamp. Then `gh run view <databaseId> --log | grep -E 'worm-duplicate-quarter status=(409|403)'` returns ≥1 match in the "Record allowlist-bypass" step. Automation feasibility: a single `gh run list` + `gh run view --log` is automatable; bake into `/soleur:ship` Phase 5.5 if not already covered.

## Test Scenarios

| ID | Setup | Action | Expected |
|---|---|---|---|
| T1 | First-write happy path (200) | `upload-bypass.sh` with well-formed payload, R2 returns 200 | exit 0, stdout `ok status=200 ...`. Regression check — existing case Bypass.a. |
| T2 | Pre-WORM duplicate (412) | Second `upload-bypass.sh` for same quarter pre-WORM, R2 returns 412 | exit 0, stdout `duplicate-quarter status=412 ...`. Existing case Bypass.b. Kept to ensure 412 path is not regressed by the new arm's placement. |
| T3 | WORM-bucket duplicate (409 + ObjectLockedByBucketPolicy) | Second `upload-bypass.sh` for same quarter under R2 Lock Rules, R2 returns 409 with the verbatim body from run 26042357131 | exit 0, stdout `worm-duplicate-quarter status=409 ... (worm-idempotent)`, NO `::error::` annotation. New case Bypass.b2 — the regression case for the production-observed envelope. |
| T3b | WORM-bucket duplicate (403 + ObjectLockedByBucketPolicy) | R2 returns 403 + body bearing `<Code>ObjectLockedByBucketPolicy</Code>` (CF-documented envelope) | exit 0, stdout `worm-duplicate-quarter status=403 ... (worm-idempotent)`. New case Bypass.b2b — covers the CF-documented status path. |
| T4 | 409 + non-WORM-bucket 4xx body (specificity guard) | R2 returns 409 with `<Code>SignatureDoesNotMatch</Code>` body (a real R2 4xx code, NOT a WORM duplicate) | exit 2, stdout `::error::fatal-4xx status=409 ... body=<Error><Code>SignatureDoesNotMatch</Code>...`. New case Bypass.b3 — defends specificity: any non-`ObjectLockedByBucketPolicy` body still fast-fails. (Plan v1 used `ObjectLockedRetention` here; deepen-pass found that code is NOT documented for R2 today.) |
| T5 | 409 with empty body | R2 returns 409 with no body (defensive) | exit 2, stdout `::error::fatal-4xx status=409 ... body=(empty body)`. New case Bypass.b4 — fail-closed when idempotency cannot be proven. |
| T6 | Evidence-record duplicate under WORM | Edit-without-change re-sign produces identical sha → identical key → R2 returns 409 with `<Code>ObjectLockedByBucketPolicy</Code>` under Lock Rules | exit 0, stdout `worm-duplicate status=409 ... (worm-idempotent)`. New case TS6.f — covers the dormant evidence path that the shared primitive fix unblocks for free. |
| T7 | 5xx retry exhausted | R2 returns 503 three times | exit 2 after 3 attempts. Existing case Bypass.d. Verifies retry classification is not affected by the new arm. |
| T8 | 403 fast-fail (non-WORM) | R2 returns 403 with a non-`ObjectLockedByBucketPolicy` body (stale token) | exit 2, fatal-4xx annotation. Existing case Bypass.c. Verifies 403 fast-fail is preserved for non-WORM bodies (the new arm broadens 403 to idempotent ONLY when body matches). |
| T9 | 400 + body capture | R2 returns 400 with `<Code>InvalidRequest</Code>` body | exit 2, body excerpt in annotation. Existing case Bypass.g. |
| T10 | 53-char bearer-token preflight | Doppler still holds bearer-token-shaped key | exit 2 at preflight (before any curl). Existing case Bypass.h. |
| T11 | Trust boundary | Adversarial payload with `[bot]` in `principal_safe` field | exit 0 with key re-derived to `-bot`. Existing case Bypass.e. |
| T12 | Missing principal | Payload lacks `principal` field | exit 64. Existing case Bypass.f. |

**T8 regression risk (deepen-pass note):** The existing `Bypass.c` 403 case tests the current behavior "403 → fast-fail." After this PR, 403 + `ObjectLockedByBucketPolicy` body becomes idempotent-success. Verify in Phase 0 that `Bypass.c`'s current code-prime does NOT also inject a `body_fixture` with `ObjectLockedByBucketPolicy` — `prime_403` (or equivalent) MUST be paired with either no body fixture OR a non-WORM-bucket body. If the existing setup happens to leak a matching body fixture from a prior test (state pollution between cases via `$work/body_fixture`), Bypass.c's expected outcome flips. Audit: each test case that primes a body fixture MUST `rm -f "$work/body_fixture"` at its END (the existing Bypass.g already does this at line ~154 — confirm and propagate the pattern to the new b2/b2b cases).

## Risks

- **Risk: the body-substring match is too narrow and R2 surfaces a different body shape in some edge condition.** Mitigation: the verbatim XML from run 26042357131 is `<Error><Code>ObjectLockedByBucketPolicy</Code><Message>The object is locked by the bucket policy.</Message></Error>`. The match string `<Code>ObjectLockedByBucketPolicy</Code>` is the stable S3 ErrorCode token (S3-compat convention; not specific to R2's wrapper prose). If R2 ever changes wrapper prose (e.g., adds an Outer element), the `<Code>...</Code>` tag remains. If R2 ever changes the ErrorCode itself, the classification falls through to fatal-4xx and surfaces the new body in the annotation — operator-actionable, no silent regression.
- **Risk: the status-code disjunction `(409 || 403)` is too narrow and R2 emits a different 4xx envelope.** Mitigation: the body match is the load-bearing identifier; the status disjunction is the envelope-shape filter. If CF later moves the response to a different 4xx code (e.g., 423 Locked, which is the standard WebDAV/HTTP code for this semantic), the classification falls through to fatal-4xx — the body is still visible in the annotation, and the operator can update the disjunction. The risk is bounded by "we'd see a single workflow failure with the new code visible, fix the arm, move on." It is NOT an unbounded silent regression because the body code itself is unchanged.
- **Risk: the new arm is invoked on a NON-duplicate first-write (false-positive idempotent).** Why this cannot happen: a first PUT to a non-existent key returns 200/201 (caught by the existing 200/201 arm BEFORE 409/403 can be returned). R2 only returns 409/403 + `ObjectLockedByBucketPolicy` when an object exists at the key AND the Lock Rule blocks the overwrite. The arm is therefore reachable only after a prior successful write.
- **Risk: the 403 broadening swallows a legitimate stale-token 403.** Mitigation: a stale-token 403 returns a different body (`<Code>InvalidAccessKeyId</Code>` or `<Code>SignatureDoesNotMatch</Code>`), NOT `ObjectLockedByBucketPolicy`. The body match is the discriminator. The existing test `Bypass.c` (403 fast-fail) is preserved as a regression check; its body fixture is verified NOT to contain `ObjectLockedByBucketPolicy` in Phase 0.
- **Risk: a future bucket-policy change (e.g., adding `narrow-prefix` rules via `gdpr-override.sh --shape=narrow-prefix`) introduces a different 4xx body that should still be fast-fail.** Mitigation: the body match is exact — only `<Code>ObjectLockedByBucketPolicy</Code>` is mapped to idempotent. Any other body falls through. The `gdpr-override.sh` flow uses temporary rule modifications via Bearer-auth on the management API, which does NOT route through `r2-conditional-put.sh` at all — the two paths are isolated.
- **Risk: the `body_excerpt | grep -q -F` form is fragile under `set -euo pipefail`.** Mitigation: empirically verified in deepen-pass — `body_excerpt` is a defined function (lines 100-106) that emits to stdout via `printf`/`tr`/`head -c`. The form `if (( cond )) && fn | grep -q -F '...'; then` is standard bash and operator-precedence-safe (binds as `(cond) && (fn | grep)`). All four expected cases (match, non-match, empty body, status short-circuit) verified to behave correctly. The `-F` flag forces fixed-string match so the angle brackets in `<Code>...</Code>` are not regex metacharacters.
- **Risk: the test stub in `upload-evidence.test.sh` does not honor `-o <file>` for body-fixture injection.** Mitigation: deepen-pass identified this as a Phase 1 prerequisite. The stub MUST be extended (mirroring upload-bypass.test.sh lines 32-56) in the same commit as the TS6.f case. Plan tasks include this explicit step (1.5 below). Without the extension, TS6.f passes vacuously (no body → no match → fast-fail expected) AND fails to exercise the actual GREEN behavior — silent test gap.

## Sharp Edges

- **The body-match string MUST stay exactly `<Code>ObjectLockedByBucketPolicy</Code>`.** Loosening to `ObjectLocked` or `BucketPolicy` would catch unrelated 4xx codes and silently swallow real config bugs. As of 2026-05-18 deepen-pass, ONLY `ObjectLockedByBucketPolicy` (CF error code 10069) is documented in R2's S3-API error table; if CF later adds object-key lock codes (`ObjectLockedRetention`/`ObjectLockedLegalHold`), the specific match ensures they fall through to the existing fatal-4xx arm and surface in the operator annotation rather than being silently swallowed.
- **Do NOT add `case` globs for status-code classification.** The existing primitive uses integer comparisons (per the comment at lines 14-21: "`case` globs are ordering-coupled and fragile"). Stay with `(( code == 409 || code == 403 ))`.
- **Do NOT pre-load the body file content into a variable.** The `body_excerpt` function caps output at 512 chars to defend against a malicious-bucket-redirect dumping HTML; bypassing it with `body_content=$(cat "$body_tmp")` defeats that defense.
- **Do NOT modify `upload-bypass.sh` or `upload-evidence.sh`.** The fix is at `r2-conditional-put.sh` only; the wrappers are intentionally thin per Kieran F7.
- **Do NOT bump `SCHEMA_VERSION` in `schema.ts`.** The payload shape is unchanged; this is a CI-side classification fix only. A schema bump would cascade into backfill/inspect/sidecar consumer assertions and is unjustified.
- **Do NOT touch `docs/legal/gdpr-policy.md` §3.4 prose.** The WORM property is preserved verbatim; the prose remains accurate. Editing it without a substantive change is noise (and may trigger the legal-doc consistency CI guard).
- **Do NOT add `workflow_dispatch` to `cla-evidence.yml` "just to make the smoke test easier."** That's a workflow-architecture change with its own blast radius (manual triggers on `pull_request_target` workflows have specific security envelope considerations). The post-merge smoke is automatable via push-an-empty-commit-to-an-existing-bypass-PR, which is what the next bypass PR does naturally anyway.
- **When labeling the new log token, use `worm-${dup_label}` (= `worm-duplicate-quarter` for upload-bypass, `worm-duplicate` for upload-evidence) NOT a hardcoded `worm-duplicate`.** The wrappers set `DUP_LABEL` via the existing parameter; preserving the parameterization keeps the bypass-vs-evidence distinguishability in logs and matches the existing convention at lines 47 + 129-132.
- **Phase ordering is load-bearing: classification arm placement is between 412 and 5xx/429, NOT after the generic 4xx.** Putting it after the generic 4xx arm would never fire because the generic arm catches all 4xx first. The plan explicitly prescribes the placement per §2 step 1 above.
- **The status-code disjunction `(code == 409 || code == 403)` is load-bearing — do NOT narrow to `409` alone.** Run 26042357131 emitted 409; CF docs document the same error code 10069 at 403. Either is reachable depending on R2's internal request path. Narrowing to 409 alone would silently regress if CF moved the response to the documented 403. The body code is the stable identifier.
- **The 403 broadening intersects with the existing `Bypass.c` test (403 fast-fail) — verify the existing test's body fixture does NOT contain `ObjectLockedByBucketPolicy`** (see T8 regression risk in Test Scenarios). State pollution between test cases via `$work/body_fixture` is the failure mode; the existing Bypass.g already handles cleanup at line ~154 (`rm -f "$work/body_fixture"`). Propagate the same cleanup to the new b2/b2b cases.
- **The `mk_curl_stub` extension in `upload-evidence.test.sh` is a Phase 1 prerequisite, not a Phase 2 nice-to-have.** Without it, TS6.f cannot exercise body-fixture injection (the existing stub only emits HTTP codes; it does not honor `-o`). The extension MUST land in the same commit as the TS6.f case or TS6.f will pass vacuously (no body returned → `body_excerpt` prints `(empty body)` → match returns false → fast-fail → fails the new test → forces a follow-up fix). Verify in Phase 1 by running TS6.f against the extended stub BEFORE landing the GREEN implementation in Phase 2.

## Rollback

- Revert the single PR commit (`git revert <merge-sha>`). The fix is additive; revert returns the classification to the pre-fix fatal-4xx behavior for 409.
- No infrastructure rollback required (no infra changes).
- No Doppler rollback required (no secret writes).
- No legal-doc rollback required (no §3.4 edits).
- Affected PRs whose cla-evidence step was red post-revert can be re-triggered by pushing an empty commit; the step will fast-fail again with the same `fatal-4xx status=409` annotation — visible, not silent.

## Cross-references

- Prior PRs in the chain that did NOT resolve this bug (but established the surfaces the fix depends on):
  - **#3201** — cla-evidence sidecar introduction. Established the `If-None-Match: *` conditional-PUT primitive and the canonical-per-quarter design.
  - **#3920** — adopted CF Lock Rules with `maxAgeSeconds:315360000` bucket-wide. Introduced the WORM constraint that 409s under.
  - **#3924/#3939** — GDPR Art. 17 admin-override driver (`gdpr-override.sh`). Established the pattern of working WITHIN Lock Rules via temporary rule modifications. Reaffirms that bypassing the lock is reserved for Art. 17 and NOT the right tool here.
  - **#3965** — captured R2 response body in fast-fail annotations. Surfaced the 409 + ObjectLockedByBucketPolicy body cleanly for the first time.
  - **#3966** — diagnose + repair allowlist-bypass R2 write. Addressed earlier-layer failures (cred shape) that masked the 409 classification gap.
  - **#3967** — trigger workflow after Doppler `prd_cla` HMAC rotation. Operational change; not the fix.
  - **#3969** — bootstrap.sh requires real R2 S3 creds + probe-PUT before Doppler. Made auth succeed for the first time, exposing the 409 classification gap as the now-dominant failure mode.

- Learning carry-forward target: `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md` §13 (new). Cross-references §4 (the 412 design comment) and §5 (the 4xx classification table).

- Hard rules consulted:
  - `cq-silent-fallback-must-mirror-to-sentry` — N/A (no fallback; success-by-classification is logged to stdout as `worm-duplicate-*`, visible in workflow log).
  - `hr-write-boundary-sentinel-sweep-all-write-sites` — N/A (no DB write; CI-only).
  - `hr-when-a-plan-specifies-relative-paths-e-g` — All paths in this plan verified via `ls`/`git ls-files`.
  - `hr-no-dashboard-eyeball-pull-data-yourself` — Post-merge AC10 is API-driven (`gh run list --json`), not dashboard-eyeball.
  - `wg-use-closes-n-in-pr-body-not-title-to` — Honored in AC7.

## Plan Quality Pre-Submission Checklist

- [x] Title under 70 chars, conventional `fix(cla-evidence): ...` form.
- [x] Issue number referenced (the worktree branch number 409 will be filed as a tracking issue if not already done; AC7 governs).
- [x] `## User-Brand Impact` populated with threshold `none` + reason ("no sensitive path touched").
- [x] `## Domain Review` populated (Engineering + Legal, inline analysis).
- [x] `## Research Reconciliation` populated (6 rows).
- [x] `## Open Code-Review Overlap` populated (None — query shown).
- [x] `## Files to Edit` enumerates every path with reason + line-range pointer.
- [x] `## Acceptance Criteria` split Pre-merge / Post-merge with verification commands per row.
- [x] `## Test Scenarios` covers the regression case (T3) AND defensive cases (T4, T5).
- [x] `## Sharp Edges` enumerates the do-NOTs (body-match specificity, no schema bump, no legal-doc edit, no workflow_dispatch).
- [x] `## Rollback` is a single `git revert`.
- [x] Phase-by-phase RED/GREEN/REFACTOR structure aligned with `cq-write-failing-tests-before`.
- [x] No `manual` step in any phase; AC10 is automation-feasible via `gh run list`/`gh workflow run`.
