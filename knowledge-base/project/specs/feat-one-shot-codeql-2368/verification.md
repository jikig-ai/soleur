# Verification — CodeQL issue #2368

**Date:** 2026-04-19
**Branch:** `feat-one-shot-codeql-2368`
**Issue:** [#2368](https://github.com/jikig-ai/soleur/issues/2368)
**Plan:** `knowledge-base/project/plans/2026-04-19-fix-verify-and-close-codeql-issue-2368-plan.md`
**Snapshot:** `web-platform-alerts.json` (filtered to `apps/web-platform/*`).
The raw paginated API dump (~685KB) is recreatable on demand via the snapshot
command in `tasks.md` 2.1 and is intentionally not committed.

## Result

**PASS — issue is resolved by prior remediation.** All 9 alerts named in #2368 are
currently `state == "dismissed"` with reasons compliant with AGENTS.md
`hr-github-api-endpoints-with-enum`. Zero open `high` or `critical` CodeQL alerts
exist in `apps/web-platform/*` on `main`. No production code change is required.

## Phase 1 — Hard Assertion (Snapshot 2026-04-19)

```text
# 1. Snapshot (recreatable; not committed):
gh api '/repos/jikig-ai/soleur/code-scanning/alerts?per_page=100' --paginate \
  > /tmp/alerts-snapshot.json

# 2. Hard assertion (executed against the snapshot):
open_high_critical=$(jq '[.[]
  | select(.most_recent_instance.location.path | startswith("apps/web-platform/"))
  | select(.state == "open")
  | select(.rule.security_severity_level == "high"
           or .rule.security_severity_level == "critical")] | length' \
  /tmp/alerts-snapshot.json)
# Result: 0  → ASSERTION PASSED
```

## Phase 1 — Alert-State Table

| # | Alert | Rule | Severity | File:line | State | Reason | Defense (from `dismissed_comment`) |
|---|---|---|---|---|---|---|---|
| 1 | #89  | `js/http-to-file-access` | medium   | `app/api/kb/upload/route.ts:205` | dismissed | false positive | `sanitizeFilename()` + `isPathInWorkspace()` + extension allowlist + 20MB cap |
| 2 | #92  | `js/request-forgery`     | critical | `server/github-api.ts:64`        | dismissed | false positive | Hardcoded base URL; server-side callers only; DELETE rejected for cloud agents |
| 3 | #100 | `js/file-system-race`    | high     | `server/kb-reader.ts:405`        | dismissed | false positive | Symlink guards at `isDirectory`/`isFile`; bubblewrap atomicity |
| 4 | #96  | `js/http-to-file-access` | medium   | `server/kb-route-helpers.ts:258` | dismissed | false positive | `randomCredentialPath()` mode 0o700; token via heredoc; `finally` cleanup |
| 5 | #93  | `js/path-injection`      | high     | `server/sandbox.ts:66`           | dismissed | false positive | `realpathSync` + symlink resolution + ELOOP/EACCES + bubblewrap |
| 6 | #88  | `js/resource-exhaustion` | high     | `server/ws-handler.ts:180`       | dismissed | false positive | 3-layer rate limit (IP + unauth cap + per-user); periodic pruning |
| 7 | #95  | `js/resource-exhaustion` | high     | `server/ws-handler.ts:259`       | dismissed | false positive | Bounded timer with `.unref()`; teardown clears; 30min idle |
| 8 | #90  | `js/request-forgery`     | critical | `test/fixtures/qa-auth.ts:42`    | dismissed | used in tests  | Test fixture; URL from env var |
| 9a | #102 | `js/path-injection`     | high     | `test/workspace.test.ts:41`      | dismissed | used in tests  | Controlled test fixture paths |
| 9b | #103 | `js/path-injection`     | high     | `test/workspace.test.ts:38`      | dismissed | used in tests  | Controlled test fixture paths |

(Issue #2368 named 9 logical alerts; `test/workspace.test.ts` produced two alert
numbers (#102, #103) for two different lines in the same file.)

## Phase 2 — Code-Drift Spot Check

`git log --since=2026-04-16 --oneline` over the 9 named source files returned
the following commits. None removed the specific defense cited in the
corresponding `dismissed_comment` (verified indirectly: the Phase 1 hard
assertion is zero — CodeQL would have re-fired on any of these commits if a
defense had been stripped, opening a new alert).

```text
0e1aff84 test(chat-sidebar): drain review backlog #2386 + #2391 (#2574)
61cb52f6 refactor(kb): shared serve-binary + dispatch + isMarkdownExt helpers (#2517)
0c7ebedb refactor(kb-share-route): helper extraction (#2520)
d40061bb refactor(kb-chat): sidebar cleanup bundle (#2500)
08d524f5 refactor(kb-upload): extract prepareUploadPayload helper (#2502)
98774e2a refactor(kb): extract workspace helper + shared test mocks + ETag (#2486)
efb7afed perf(kb): disable PDF.js streaming so range-only transport (#2480)
5b9b644d perf(kb): linearize PDFs on upload via qpdf (#2457)
4787a92a fix(kb): bind share links to content hash (#2463)
2b3bc1cf fix(kb-chat): PR #2347 follow-ups (#2446)
711d033f fix(kb-chat): relax resumeByContextPath validation (#2420)
```

**Conclusion:** No defensive regression observed. Phase 2 is a secondary safety
net behind Phase 1's CodeQL re-scan on the verification PR.

## References

- **Bulk dismissal PR:** [#2416](https://github.com/jikig-ai/soleur/pull/2416)
  (mergeCommit `dd36190573e0ae84c62b1dcb100c19eab29868a3`, merged 2026-04-16T11:14:55Z)
- **Threat-model switch follow-up:** [#2421](https://github.com/jikig-ai/soleur/pull/2421)
  (merged 2026-04-16T11:42:50Z) — switched CodeQL `threat_model` from
  `remote_and_local` to `remote` to reduce false-positive volume.
- **Brainstorm + CTO assessment:**
  `knowledge-base/project/brainstorms/2026-04-16-security-scanning-alerts-brainstorm.md`

## Workflow Gap

Issue #2368 was filed at 2026-04-15T17:22:29Z (2 minutes before PR #2346 merged
and ~18 hours before the bulk-dismiss PR #2416). It became an orphan when PR
\#2416 dismissed all 9 alerts. The remediation in this PR adds an automated
**post-dismissal sweep** to `.github/workflows/codeql-to-issues.yml` that, after
every workflow run, scans open `type/security` issues for referenced alert
numbers and auto-closes any whose alerts are all `state == "dismissed"`. See
`knowledge-base/project/learnings/best-practices/2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md`.

## Disposition

This PR closes #2368 via `Closes #2368` in the PR body. The ten alert numbers
remain `dismissed` in GitHub Code Scanning. No re-dismissal needed.
