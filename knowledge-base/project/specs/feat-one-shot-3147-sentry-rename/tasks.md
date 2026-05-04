---
title: Tasks for feat-one-shot-3147-sentry-rename
plan: knowledge-base/project/plans/2026-05-04-chore-sentry-extra-text-to-extra-shape-rename-plan.md
issue: 3147
source_pr: 3127
created: 2026-05-04
---

# Tasks: Sentry `extra.text` → `extra.shape` rename audit-and-rewrite script

Plan: `knowledge-base/project/plans/2026-05-04-chore-sentry-extra-text-to-extra-shape-rename-plan.md`

## Phase 1 — Setup and scaffold

- [x] 1.1 Read `apps/web-platform/scripts/configure-sentry-alerts.sh` to absorb
      the precedent's region-detection, env-preamble, jq-guard, and
      fail-closed duplicate-handling patterns.
- [x] 1.2 Verify `bats` absence: `command -v bats` AND
      `find apps/web-platform/scripts -name '*.bats'`. If absent, lock
      "no new test framework" per the plan's Sharp Edge 6.
- [x] 1.3 Create `apps/web-platform/scripts/audit-sentry-extra-text-references.sh`
      with shebang `#!/usr/bin/env bash`, `set -euo pipefail`, and the
      `: "${SENTRY_AUTH_TOKEN:?…}"` env-preamble triplet from the precedent.
- [x] 1.4 Implement argument parsing: default mode (dry-run), `--apply`,
      `--add-or-clause`, `--help`. Make `--add-or-clause` require `--apply`
      (mutation only). Print sanity log line at start: host + org + project
      + mode.
- [x] 1.5 Implement region detection by copy-pasting the precedent's
      `for candidate in sentry.io de.sentry.io` probe block; reuse the same
      `--max-time 10` and 200-status check.
- [x] 1.6 **(deepen-pass addition)** Add `jq` dependency check after
      env-preamble:
      `command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found — install via 'brew install jq' or 'apt-get install jq'" >&2; exit 1; }`.
      Surfaces R7.
- [x] 1.7 **(deepen-pass addition)** Add a script header comment block
      explaining the tag-vs-extra namespace distinction (Sharp Edge 8).
      Operators reading the script must see immediately that the Sentry
      UI's issue-stream search bar will NOT find `extra.text` even when
      matches exist in saved-search/discover/dashboard query strings —
      the script is the only complete audit path.

## Phase 2 — RED tests

- [x] 2.1 RED: `unset SENTRY_AUTH_TOKEN; bash <script>` exits non-zero
      with "SENTRY_AUTH_TOKEN must be set" on stderr.
- [x] 2.2 RED: `SENTRY_AUTH_TOKEN=invalid SENTRY_ORG=jikigai SENTRY_PROJECT=soleur-web-platform bash <script>`
      exits non-zero with "Sentry token not valid against either US or EU
      ingest" on stderr (verifies probe path).
- [x] 2.3 RED: `bash <script> --apply --add-or-clause` without
      `SENTRY_*` env exits non-zero (env-preamble fires before
      arg-validation — confirms ordering).

## Phase 3 — GREEN: inventory phase

- [x] 3.1 Implement `inventory_alert_rules` — GET
      `/api/0/projects/{org}/{project}/rules/`, jq-filter
      `.[] | select((.. | strings? | contains("extra.text")) and (.. | strings? | contains("tool-label-scrub")))`.
      Emit `[issue-alert-rule] id=<id> name="<name>" match=<jsonpath>` per
      hit. `--max-time 10` and `jq -e .` guard.
- [x] 3.2 Implement `inventory_saved_searches` — GET
      `/api/0/organizations/{org}/searches/`, jq-filter on the `query`
      field containing both literals.
- [x] 3.3 Implement `inventory_discover_saved` — GET
      `/api/0/organizations/{org}/discover/saved/`, jq-filter on `query`
      string AND `fields[]` array entries.
- [x] 3.4 Implement `inventory_dashboards` — GET
      `/api/0/organizations/{org}/dashboards/` (list), then sequential
      per-id GET `/api/0/organizations/{org}/dashboards/{id}/`. Match on
      `widgets[*].queries[*].{conditions,fields,aggregates}`. Handle HTTP
      429 with single `sleep 5` retry.
- [x] 3.5 Wire all four into a top-level `inventory_all` that prints the
      4-row table format from the plan, plus a final `Summary: N matches…`
      line. Zero-match path prints the explicit "no follow-through targets"
      message and exits 0.

## Phase 4 — GREEN: rewrite phase (`--apply`)

- [x] 4.1 Implement `rewrite_alert_rule` — fetch full rule body, jq
      string-substitute `extra.text` → `extra.shape` in `filters[*].value`
      and `filters[*].key`, PUT back. Match-by-name fail-closed: refuse
      to mutate if multiple rules share a name (mirrors precedent).
- [x] 4.2 Implement `rewrite_saved_search` — PUT
      `/organizations/{org}/searches/{id}/` with `{query: <new>}`.
      Default mode replaces `extra.text` → `extra.shape`;
      `--add-or-clause` rewrites to
      `(extra.text:foo OR extra.shape:foo)` per Sentry search syntax.
      **(deepen-pass addition)** Use `jq -n --arg q "$old"
      '$q | gsub("extra\\.text"; "extra.shape")'` for the substitution —
      NOT `sed` over a shell-quoted string (R6 mitigation, Sharp Edge 6).
      Verify post-write by GET-and-diff (compare jq-canonicalized JSON).
- [x] 4.3 Implement `rewrite_discover_saved` — PUT
      `/organizations/{org}/discover/saved/{id}/`. Rewrite both `query`
      string and `fields[]`/`yAxis[]` array entries. **`fields[]` always
      replaces** even in `--add-or-clause` mode (R3 in the plan); log the
      asymmetry.
- [x] 4.4 Implement `rewrite_dashboard` — fetch full dashboard, mutate
      `widgets[*].queries[*]`, PUT back full payload. Sequential, no
      concurrency. Re-fetch and diff post-write.
- [x] 4.5 On any non-2xx response, print the response body to stderr and
      exit non-zero. Never silently continue.

## Phase 5 — GREEN: re-verify and exit

- [x] 5.1 After all rewrites, silently re-run `inventory_all`. If matches
      remain, print "FAILED: <N> references still present:" + the table,
      and exit non-zero.
- [x] 5.2 If zero remaining, print
      `Verified: 0 references to extra.text remain on op:tool-label-scrub`
      and exit 0.

## Phase 6 — Runbook

- [x] 6.1 Decide between extending `oauth-probe-failure.md` vs creating
      `sentry-extra-field-rename.md`. Default to extension if the new
      content fits in ≤30 lines.
- [x] 6.2 Add a "Sentry config drift cleanup" section with:
      one-line purpose, the dry-run invocation
      (`doppler run -p soleur -c prd -- bash apps/web-platform/scripts/audit-sentry-extra-text-references.sh`),
      the `--apply` invocation, and a "if zero matches, close #3147" note.
- [x] 6.3 Add a learning file
      `knowledge-base/project/learnings/<topic>.md` IF a non-trivial
      Sentry-API quirk surfaces during work-phase (e.g., the dashboards API
      requiring full-payload PUTs). Otherwise skip — the plan's references
      already cover the known quirks.

## Phase 7 — Pre-merge verification

- [x] 7.1 `chmod +x apps/web-platform/scripts/audit-sentry-extra-text-references.sh`.
- [x] 7.2 Run `shellcheck apps/web-platform/scripts/audit-sentry-extra-text-references.sh`
      and resolve all warnings (the precedent passes shellcheck cleanly;
      maintain parity).
- [x] 7.3 Smoke test against prod Sentry in dry-run mode (no mutation):
      `doppler run -p soleur -c prd -- bash apps/web-platform/scripts/audit-sentry-extra-text-references.sh`.
      Capture the output for the PR body.
- [x] 7.4 Verify `wc -c apps/web-platform/scripts/audit-sentry-extra-text-references.sh`
      is in the same order of magnitude as the precedent (~7 KB);
      if drastically larger, audit for unnecessary code.
- [x] 7.5 Compound (`/soleur:compound`) before commit per AGENTS.md
      `wg-before-every-commit-run-compound-skill`.

## Phase 8 — PR and merge

- [ ] 8.1 Push branch and open PR with title
      `chore(observability): audit-sentry-extra-text-references.sh — follow-through for PR #3127 field rename`.
- [ ] 8.2 PR body includes the dry-run smoke output from 7.3 verbatim
      (showing zero-or-N matches), the User-Brand Impact section's
      threshold/reason line, and `Ref #3147` (NOT `Closes #3147`).
- [ ] 8.3 Run review pipeline; fix-inline per
      `rf-review-finding-default-fix-inline`.
- [ ] 8.4 `gh pr merge <num> --squash --auto`; poll until MERGED;
      `cleanup-merged`.

## Phase 9 — Post-merge operator action

- [ ] 9.1 Operator runs the script in dry-run via Doppler-prod against
      live Sentry.
- [ ] 9.2 If zero matches: `gh issue close 3147 --comment "Verified zero references to extra.text on op:tool-label-scrub via audit script (dry-run output: …)"`.
- [ ] 9.3 If non-zero matches: operator chooses replace vs. add-or-clause,
      runs `--apply` (or `--apply --add-or-clause`), confirms exit-zero
      verification, then closes #3147 with the verification output.
- [ ] 9.4 Verify deploy/release workflows succeeded post-merge per
      `wg-after-a-pr-merges-to-main-verify-all`.
