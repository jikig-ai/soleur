---
title: "fix: Triage 84 pre-existing CodeQL code scanning alerts"
type: fix
date: 2026-04-10
---

# Triage 84 Pre-Existing CodeQL Code Scanning Alerts

Ref #1894, Ref #1874

## Problem

CodeQL initial scan (extended query suite, `remote_and_local` threat model) surfaced 84 pre-existing alerts when GitHub Security features were enabled in #1874. The `remote_and_local` threat model flags environment variables and CLI arguments as taint sources, producing many false positives in CLI tools that intentionally accept file paths as arguments.

The alerts break down as:

| Rule | Severity | Count | Affected Files |
|------|----------|-------|---------------|
| `js/path-injection` | error | 34 | `workspace.ts` (21), `workspace.test.ts` (8), `workspace-error-handling.test.ts` (3), `project-scanner.ts` (2) |
| `py/path-injection` | error | 26 | `init_skill.py` (11), `package_skill.py` (7), `compose_images.py` (2), `edit_image.py` (2), `multi_turn_chat.py` (2), `quick_validate.py` (2) |
| `js/insecure-temporary-file` | warning | 7 | `workspace-cleanup.test.ts` (3), `canusertool-caching.test.ts` (3), `pencil-mcp-adapter.mjs` (1) |
| `actions/missing-workflow-permissions` | warning | 5 | `ci.yml` (5 jobs) |
| `js/file-system-race` | warning | 3 | `skills.js` (1), `kb-reader.ts` (2) |
| `js/http-to-file-access` | warning | 2 | `workspace.ts` (1), `session-sync.ts` (1) |
| `js/remote-property-injection` | warning | 2 | `pencil-mcp-adapter.mjs` (1), `welcome-hook.test.ts` (1) |
| `js/request-forgery` | error | 2 | `health.ts` (1), `github-resolve/callback/route.ts` (1) |
| `js/code-injection` | error | 1 | `kb-reader.ts` (1) |
| `js/resource-exhaustion` | warning | 1 | `ws-handler.ts` (1) |
| `py/polynomial-redos` | warning | 1 | `backfill-frontmatter.py` (1) |

## Triage Strategy

Categorize each alert into one of four dispositions:

1. **Fix** -- genuine vulnerability, apply code hardening
2. **Dismiss (false positive)** -- CodeQL flags internal/CLI code with no remote attacker path
3. **Dismiss (test code)** -- alert in test file, not exploitable
4. **Dismiss (configuration)** -- adjust CodeQL config to reduce noise

### Priority Order

**P1 -- Fix immediately (genuine risk or easy hardening):**

- `js/code-injection` (1): `kb-reader.ts:72` -- `gray-matter` with custom engines disabled (`engines: {}`). Verify the `engines: {}` config prevents code injection via YAML front matter. If safe, dismiss; if not, add sanitization.
- `js/request-forgery` (2): `health.ts:6` uses `serverUrl()` from env var to build Supabase URL -- SSRF via env manipulation requires server access, making this a false positive in practice. `callback/route.ts:122` stores `userData.login` from GitHub API -- already has format validation regex, not SSRF.
- `actions/missing-workflow-permissions` (5): `ci.yml` lacks top-level `permissions:` block. Add `permissions: contents: read` at workflow level, with per-job overrides where needed.

**P2 -- Review and dismiss (false positives in internal tooling):**

- `js/path-injection` (34): 21 alerts in `workspace.ts` which already validates `userId` against a UUID regex (`UUID_RE`) and constructs paths from validated input via `join()`. The `remote_and_local` threat model flags `process.env.WORKSPACES_ROOT` as tainted, but this is server-controlled config, not user input. 8 alerts in test files. 3 in `workspace-error-handling.test.ts`. 2 in `project-scanner.ts` (file may be deleted -- alerts reference a non-existent file on main).
- `py/path-injection` (26): All in CLI scripts (`init_skill.py`, `package_skill.py`, `quick_validate.py`, `compose_images.py`, `edit_image.py`, `multi_turn_chat.py`). These are developer-facing CLI tools that intentionally accept file paths as arguments. The `remote_and_local` threat model flags `sys.argv` as tainted, but these scripts are not network-exposed.

**P3 -- Track or minor fix:**

- `js/insecure-temporary-file` (7): 6 in test files using `mkdtempSync(join(tmpdir(), "prefix-"))` -- standard Node.js pattern, secure enough for tests. 1 in `pencil-mcp-adapter.mjs` -- uses constructed filename with timestamp, not truly insecure.
- `js/file-system-race` (3): TOCTOU patterns in `skills.js` (stat then read) and `kb-reader.ts` (stat then read). Low risk -- these are build-time and server-side reads of local files, not security-sensitive.
- `js/http-to-file-access` (2): `workspace.ts` and `session-sync.ts` write GitHub tokens to temporary credential helpers. These are designed behavior -- the token is written to a temp file with mode 0o700, used by git, then deleted. Already has cleanup logic.
- `js/remote-property-injection` (2): `pencil-mcp-adapter.mjs:37` processes `process.argv` key-value pairs into `process.env`. `welcome-hook.test.ts:14` copies `process.env` entries. Both are internal tooling with no remote attacker vector.
- `js/resource-exhaustion` (1): `ws-handler.ts:122` parses `process.env.WS_IDLE_TIMEOUT_MS` with `parseInt`. Server-controlled env var, not user input.
- `py/polynomial-redos` (1): `backfill-frontmatter.py:86` regex `^## Tags\s*\n+(.+?)(?:\n\n|\n#|\Z)` with `re.DOTALL`. The `(.+?)` with `re.DOTALL` on untrusted markdown could exhibit polynomial behavior on adversarial input. Low practical risk (offline script), but trivially fixable.

## Implementation Plan

### Phase 1: CI Workflow Permissions (5 alerts)

Add a top-level `permissions` block to `.github/workflows/ci.yml`:

```yaml
permissions:
  contents: read
```

This resolves all 5 `actions/missing-workflow-permissions` alerts. The CI workflow only needs read access to repository contents.

**Files:**

- `.github/workflows/ci.yml` -- add `permissions:` block after `on:` trigger

### Phase 2: Code Injection Assessment (1 alert)

**Alert 33:** `kb-reader.ts:72` -- `matter(raw, { engines: {} })` flags as code injection because `gray-matter` historically allowed JavaScript execution in YAML frontmatter via custom engines. The `{ engines: {} }` option disables all custom engines, which is the recommended mitigation.

**Action:**

1. Check installed `gray-matter` version in `apps/web-platform/package-lock.json` -- the `engines: {}` mitigation was introduced in a specific version and older versions may not honor it.
2. Verify `engines: {}` is sufficient by checking `gray-matter` docs for the installed version.
3. If confirmed safe, dismiss the alert with a comment explaining the mitigation. Add an inline comment to the code for future reference.

**Files:**

- `apps/web-platform/server/kb-reader.ts` -- add explanatory comment at line 72

### Phase 3: Polynomial ReDoS Fix (1 alert)

**Alert 6:** `backfill-frontmatter.py:86` -- regex with `re.DOTALL` and `(.+?)` can exhibit quadratic behavior.

**Fix:** Replace the regex with a more specific pattern that avoids backtracking:

```python
# Before (polynomial):
match = re.search(r"^## Tags\s*\n+(.+?)(?:\n\n|\n#|\Z)", content, re.MULTILINE | re.DOTALL)

# After (linear):
match = re.search(r"^## Tags[ \t]*\n((?:[^\n]|\n(?!\n|#))+)", content, re.MULTILINE)
```

**Files:**

- `scripts/backfill-frontmatter.py` -- fix regex at line 86

### Phase 4: Dismiss False Positives via API (75 alerts)

Dismiss all remaining false positive alerts via the GitHub API. Each dismissal includes a specific comment explaining why the alert is a false positive, providing a self-documenting audit trail. No `codeql-config.yml` path exclusions -- API dismissals are one-time, self-documenting, and avoid a second configuration surface to maintain.

Use `gh api` to dismiss alerts that are confirmed false positives:

```bash
# Dismiss with reason and comment
gh api repos/{owner}/{repo}/code-scanning/alerts/<N> \
  -X PATCH \
  -f state=dismissed \
  -f dismissed_reason=false_positive \
  -f dismissed_comment="<explanation>"
```

**Dismissal groups:**

| Alert Numbers | Rule | Reason |
|--------------|------|--------|
| 38-55, 69 | `js/path-injection` | `workspace.ts`: userId validated by UUID regex, paths built from server env vars |
| 56-64, 65-68 | `js/path-injection` | Test files: not exploitable |
| 36-37 | `js/path-injection` | `project-scanner.ts`: file deleted from main -- check if alerts auto-closed before dismissing manually |
| 7-32 | `py/path-injection` | CLI scripts: intentionally accept file paths, not network-exposed |
| 71-76 | `js/insecure-temporary-file` | Test files or standard `mkdtempSync` pattern |
| 77 | `js/insecure-temporary-file` | `pencil-mcp-adapter.mjs`: constructed filename with timestamp, in screenshot dir |
| 82-84 | `js/file-system-race` | Build-time/server-side file reads, TOCTOU not exploitable |
| 80-81 | `js/http-to-file-access` | Designed behavior: credential helper written with 0o700 mode, cleaned up after use |
| 78-79 | `js/remote-property-injection` | Internal tooling: argv/env processing, no remote attacker vector |
| 34-35 | `js/request-forgery` | Server-controlled env vars (Supabase URL), GitHub API response with format validation |
| 70 | `js/resource-exhaustion` | Server-controlled env var parsed with `parseInt` |

### Phase 5: Verification

**Alert tally (all 84 accounted for):**

- Alerts 1-5: Phase 1 (CI permissions fix)
- Alert 6: Phase 3 (ReDoS regex fix)
- Alert 33: Phase 2 (code injection assessment + dismissal)
- Alerts 7-32, 34-35, 36-84: Phase 4 (API dismissals -- 75 alerts total)

**Verification steps:**

1. Trigger a CodeQL re-scan to confirm alert count drops
2. Verify the CI workflow permissions fix passes the CodeQL check
3. Document the triage decisions in the PR description for audit trail
4. Confirm each dismissal comment was written based on actual code inspection, not copy-pasted from plan summary

## Acceptance Criteria

- [x] `ci.yml` has a top-level `permissions:` block resolving 5 workflow permission alerts
- [x] `backfill-frontmatter.py` regex fixed to prevent polynomial ReDoS
- [x] `kb-reader.ts` has inline comment explaining `engines: {}` mitigation
- [x] Test file alerts dismissed as "test code, not exploitable"
- [x] CLI script path-injection alerts dismissed as "false positive: CLI tool accepting file path arguments"
- [x] Production code false positives dismissed with specific explanations
- [x] Alert count verified post-triage (target: 0 open alerts or only intentionally-tracked alerts)

## Test Scenarios

- Given `ci.yml` with `permissions: contents: read`, when CodeQL scans, then no `actions/missing-workflow-permissions` alerts fire
- Given `backfill-frontmatter.py` with fixed regex, when processing a markdown file with a `## Tags` section, then frontmatter tags are extracted correctly
- Given a dismissed alert, when CodeQL re-scans, then the alert remains dismissed and does not reappear
- Given all 84 alerts triaged, when checking `gh api repos/{owner}/{repo}/code-scanning/alerts --jq '[.[] | select(.state=="open")] | length'`, then the count is 0

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Pure security tooling triage -- no architectural decisions required. The fixes are configuration-level (CI permissions, CodeQL config) and one-line code changes (regex fix, inline comment). No new services, no infrastructure changes, no API surface changes. CTO review not needed beyond standard PR review.

No Product/UX Gate needed -- this is an infrastructure/tooling change with zero user-facing impact.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Downgrade to `default` query suite | Fewer alerts, higher precision | Misses quality queries | Deferred -- evaluate after initial triage |
| `remote` threat model only | Eliminates CLI/env false positives | Misses local privilege escalation | Evaluate after path exclusions |
| Inline `// lgtm` suppression | Per-line precision | 75+ comments polluting codebase | Rejected |
| Fix all path-injection with sanitization | Most thorough | Unnecessary hardening for CLI tools and UUID-validated paths | Rejected -- overengineering |

## References

- [CodeQL threat models](https://docs.github.com/en/code-security/code-scanning/creating-an-advanced-setup-for-code-scanning/customizing-your-advanced-setup-for-code-scanning#extending-codeql-coverage-with-threat-models)
- [CodeQL alert dismissal API](https://docs.github.com/en/rest/code-scanning/code-scanning#update-a-code-scanning-alert)
- [gray-matter code injection CVE](https://github.com/jonschlinkert/gray-matter/issues/99)
- Issue #1874 (CodeQL setup)
- Issue #1894 (this triage)
