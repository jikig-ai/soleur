---
title: "Sentry alert/saved-search/dashboard rename `extra.text` → `extra.shape` (PR #3127 follow-through)"
type: chore
classification: ops-remediation
issue: 3147
source_pr: 3127
branch: feat-one-shot-3147-sentry-rename
created: 2026-05-04
requires_cpo_signoff: false
---

# Plan: Sentry alert/saved-search/dashboard rename `extra.text` → `extra.shape`

## Enhancement Summary

**Deepened on:** 2026-05-04
**Sections enhanced:** 5 (Overview, Implementation Phase 2 Inventory, Implementation Phase 3 Rewrite, Risks, Sharp Edges)
**Research sources:** Context7 (`/getsentry/sentry-docs`), repo precedent (`apps/web-platform/scripts/configure-sentry-alerts.sh`), institutional learnings (`sentry-api-boolean-search-not-supported-20260406.md`, `2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md`)

### Key Improvements

1. **Sentry tag vs. extra-context distinction.** Confirmed via Context7 (`/getsentry/sentry-docs`): the **alert rule** `TaggedEventFilter` operates on TAGS (set via `setTag`), not on extra context (set via `setExtra`). `extra.text` is stored as event metadata (visible in event detail, queryable in Discover) but is **NOT a tag**. This re-shapes the inventory model: alert-rule matches for `extra.text` as a tag key will return **zero in normal usage** — the only way to land such a rule is via API-direct authoring with a non-standard payload. The script must still inventory the alert-rule namespace for completeness, but the realistic match surface is **saved-searches + discover-saved + dashboard widgets**.
2. **Tag character constraints.** Tag keys are restricted to `[a-zA-Z0-9_.:-]`, max 200 chars. The literal substring `extra.text` is a syntactically valid tag key (no forbidden characters), so the AND-with-`tool-label-scrub` guard remains the only safety filter — there is no Sentry-side schema constraint stopping a hand-authored rule from using this exact string.
3. **Newline-injection guard for query strings.** Tag values cannot contain `\n` (Sentry rejects), but Discover query strings ingested from saved searches CAN contain control characters. When the script substitutes `extra.text` → `extra.shape` via `sed` or `jq`, it must guard against control-character injection in the input (e.g., a malicious operator could craft a saved search whose `query` field contains `\n` to break the substitution). Use `jq`-only string operations (no `sed` shell-escape exposure) for the rewrite.
4. **Match-by-name fail-closed pattern is non-negotiable.** Confirmed via learning `2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md` (Quirk #4): Sentry rule name uniqueness is NOT enforced by the API. Two rules can share a name; a naive `.[0].id` upsert silently picks one and leaves the other drifted. The `match_count > 1` fail-closed guard from `configure-sentry-alerts.sh:upsert_rule` MUST be replicated for the alert-rule rewrite path. (This is already in Phase 3 / Acceptance Criteria — calling out for emphasis.)
5. **Sentry API host probe is the only correct region detection.** No environment variable shortcut exists; the prod workspace currently lives on EU (`de.sentry.io`), but a hard-coded host would silently break on a future region migration. Reuse the precedent script's probe verbatim.

### New Considerations Discovered

- **Realistic match-set is likely smaller than the issue body implies.** Combining (a) the tag/extra distinction, (b) the AND-on-`tool-label-scrub` filter, and (c) the fact that no operator has authored such a Sentry artifact (no commits in the repo reference `extra.text` for this op), the most likely outcome is **zero matches across all four resource classes**. The script's primary value is providing a verifiable closure ("we ran the audit; nothing to rewrite"), not the rewrite itself. This re-frames the script as an **audit-first, rewrite-as-fallback** tool — the dry-run is the primary deliverable, and the `--apply` path is a safety net for the unlikely-but-possible case.
- **Dashboard API requires full-payload PUT.** The Sentry dashboards endpoint does NOT support per-widget PATCH. Mutations must serialize the entire dashboard. This is a known Sentry-API quirk worth a learning file if surfaced during work-phase. The script's dashboard branch must therefore (i) GET the full dashboard, (ii) jq-walk the widget tree, (iii) PUT back the mutated full payload, (iv) re-GET to diff.
- **`jq` is a hard dependency.** The precedent script uses jq throughout; the new script must too. `command -v jq` should be checked at script start with a clear "jq not found — install via apt/brew/etc." error if missing. (The precedent does not currently do this — operator-environment context implies `jq` is always present, but a defensive check is cheap insurance.)

## Overview

PR #3127 merged 2026-05-04T10:10:15Z. The fix tightened the workspace-path
diagnostic capture in `apps/web-platform/server/tool-labels.ts` from
`extra.text: out.slice(0, 200)` (200 chars of post-scrub residual) to
`extra.shape: <SUSPECTED_LEAK_SHAPE match>?.[0].slice(0, 200)` (the matched
leak substring only). The server-side code rename is live; any saved Sentry
**alert rule**, **issue saved search**, **discover saved query**, or
**dashboard widget** that filters or groups on `extra.text` for `op:"tool-label-scrub"`
events will silently stop matching post-deploy.

This plan codifies the follow-through as **automated via the Sentry REST API**,
not as an operator-manual click-through. AGENTS.md `hr-never-label-any-step-as-manual-without`
makes this mandatory: Sentry has a public REST API, the credentials
(`SENTRY_AUTH_TOKEN`, `SENTRY_ORG=jikigai`, `SENTRY_PROJECT=soleur-web-platform`)
are already in Doppler `prd`, and the codebase already has a precedent script
(`apps/web-platform/scripts/configure-sentry-alerts.sh`) that handles region
detection (US `sentry.io` vs EU `de.sentry.io`), idempotency, and fail-closed
duplicate handling.

The deliverable is a new **idempotent audit-and-rewrite script**
`apps/web-platform/scripts/audit-sentry-extra-text-references.sh` that:

1. Inventories all four Sentry resource classes that can carry the stale
   filter string.
2. Reports matches in a deterministic dry-run format (default).
3. Rewrites `extra.text` → `extra.shape` in matched resources when
   invoked with `--apply`.
4. Re-verifies post-rewrite that zero matches remain.

The script is reusable for future Sentry field renames (the `extra.*` capture
contract is unstable and PR #3127 already established the `shape` naming
convention; future rename events are likely).

## Source PR Context

- **PR #3127** (merged): "fix(command-center): widen sandbox-path patterns
  for non-slash terminators (Sentry 1e549c80)"
- **PR body operator note** (verbatim): `op: "tool-label-scrub"` events now
  record `extra.shape` instead of `extra.text`. Any saved Sentry queries,
  dashboards, or alert rules filtering on `extra.text` for this `op` will
  silently stop matching post-deploy.
- **Sentry event class:** `op:"tool-label-scrub"` — fired by
  `reportSilentFallback` in `apps/web-platform/server/tool-labels.ts:75`
  when `SUSPECTED_LEAK_SHAPE` matches post-scrub residual.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body / PR description) | Reality (verified) | Plan response |
| --- | --- | --- |
| "Operator: search Sentry workspace…" framed as manual | `SENTRY_AUTH_TOKEN`/`SENTRY_ORG`/`SENTRY_PROJECT` exist in Doppler `prd`; `apps/web-platform/scripts/configure-sentry-alerts.sh` is direct precedent for idempotent Sentry REST mutation | Reframe as automated audit+rewrite script — manual handoff would violate AGENTS.md `hr-never-label-any-step-as-manual-without`. |
| "saved queries / alert rules" (two classes) | Sentry has FOUR distinct API resource classes that can store a query string referencing `extra.text`: (1) issue alert rules (`/projects/{o}/{p}/rules/`), (2) issue saved searches (`/organizations/{o}/searches/`), (3) discover saved queries (`/organizations/{o}/discover/saved/`), (4) dashboard widgets (`/organizations/{o}/dashboards/{id}/`) | Script audits all four. Two-class enumeration in issue body is incomplete. |
| Implicit assumption: matches likely exist | Operator never explicitly created any such alert (no Sentry config commits reference `extra.text`); the PR body is precautionary | Default behaviour is dry-run report; "zero matches" is a valid successful outcome that closes the issue. |
| `SENTRY_API_HOST` defaults to `de.sentry.io` (EU) per `oauth-probe-failure.md` runbook | Confirmed: precedent script probes both hosts and picks the responding one | Reuse the same probe pattern; no hard-coded host. |

## User-Brand Impact

- **If this lands broken, the user experiences:** no direct user impact —
  `op:"tool-label-scrub"` is a server-internal silent-fallback diagnostic; the
  affected surfaces are Sentry observability config (alert rules, dashboards)
  used by ops to detect regression of the workspace-path scrub. A regression
  would re-introduce ops monitoring loss for one diagnostic field on one op
  tag, NOT user-data exposure. Defence-in-depth (verb-only Bash labels per
  FR1 #2861, client render scrub in `lib/format-assistant-text.ts:88`) remains
  intact and is what protects the rendered surfaces.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A
  — the script reads/writes Sentry alert configuration only; it does not
  ingest, render, or transmit user data. The audit step uses GET-only Sentry
  REST and is safe to run in dry-run as often as desired.
- **Brand-survival threshold:** none.
- threshold: none, reason: this is observability configuration drift cleanup;
  no auth/payments/credentials/user-data path is touched. The diff is scoped
  to a new shell script under `apps/web-platform/scripts/` plus an optional
  runbook update; preflight Check 6 sensitive-path regex does not match
  `apps/web-platform/scripts/audit-*.sh`.

## Hypotheses

This is a follow-through with a single concrete deliverable; no diagnostic
hypothesis space. Skipping `## Hypotheses` per Phase 1.4 trigger non-match
(no SSH/connection-reset/firewall keywords in the issue body, and no
Terraform `provisioner` block).

## Open Code-Review Overlap

None. Issue #3147 is `follow-through`-labeled, not `code-review`. The new
file `apps/web-platform/scripts/audit-sentry-extra-text-references.sh` does
not yet exist, so there are no pre-existing scope-outs against it. The
existing `apps/web-platform/scripts/configure-sentry-alerts.sh` is a
read-and-reuse precedent, not a target of edit.

## Domain Review

**Domains relevant:** Engineering/CTO (observability config — minor
architectural relevance for review correctness).

### Engineering/CTO

**Status:** assessed inline (single-paragraph framing — no structured-leader
spawn required for an ops-remediation script with established precedent).
**Assessment:** This is a small, self-contained shell script (~200 LoC)
following an established pattern (`configure-sentry-alerts.sh`). The
architectural surface is the Sentry-API-mutation-script class. The plan's
correctness load is on (a) match-detection logic — must AND on
`tool-label-scrub` to scope correctly, and (b) idempotency — match-by-name
fail-closed-on-duplicate per the precedent's pattern. Both are addressed
explicitly in the script design below. No new infrastructure, no new
service, no new architectural pattern. Approved for plan-time inline
assessment without a spawned domain-leader Task.

No other domains apply. No CMO/CRO/CFO/COO/CLO/CPO concerns: zero user-facing
content, zero copy, zero pricing, zero compliance surface, zero finance
surface, zero ops-org-chart surface (the script is run by an existing ops
engineer with existing Sentry token), zero product surface.

### Product/UX Gate

**Tier:** none (no Product domain relevance — script-only deliverable; zero
user-facing component changes).

## Implementation Phases

### Phase 1 — Script scaffold and region detection (RED)

Create `apps/web-platform/scripts/audit-sentry-extra-text-references.sh` with:

- Strict mode (`set -euo pipefail`) and required-env preamble matching
  the precedent script:

  ```bash
  : "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"
  : "${SENTRY_ORG:?SENTRY_ORG must be set}"
  : "${SENTRY_PROJECT:?SENTRY_PROJECT must be set}"
  ```

- Region detection identical to
  `apps/web-platform/scripts/configure-sentry-alerts.sh` (probe
  `/users/me/` against `sentry.io` then `de.sentry.io`, pick the 200; fail
  with explicit error if neither).
- Argument parser: default mode is **dry-run**; `--apply` flag enables
  mutation; `--add-or-clause` (mutually exclusive with default replace)
  switches the mutation strategy from
  `extra.text:* → extra.shape:*` (replace) to
  `extra.text:* → (extra.text:* OR extra.shape:*)` (additive deploy-window
  posture); `--help` prints usage.
- Sanity log: print the resolved API host, org, project, and mode at
  start, so operators reading CI logs can see exactly what is about to
  happen before any mutation.

**RED test:** running `bash apps/web-platform/scripts/audit-sentry-extra-text-references.sh`
without exporting the required env should exit non-zero with a clear
"`SENTRY_AUTH_TOKEN must be set`" message. Verify by `unset SENTRY_AUTH_TOKEN; bash <script> 2>&1 | grep -q "SENTRY_AUTH_TOKEN must be set"`.

### Phase 2 — Inventory phase (GET-only)

Implement four GET helpers, each returning a JSON array of
`{id, name, query_string}` tuples for matching purposes:

1. **Issue alert rules** — `GET /api/0/projects/{org}/{project}/rules/`. The
   response is an array; each rule's `filters[]` may contain
   `TaggedEventFilter` entries with `key:"extra.text"`.

   **Research insight (Context7 `/getsentry/sentry-docs`):** Sentry alert
   rules' `TaggedEventFilter` operates on **tags** (key-value pairs set via
   `Sentry.setTag()`), not on **extra context** (key-value pairs set via
   `Sentry.setExtra()`). The `extra.text` value emitted by
   `reportSilentFallback` lives in extra context, NOT in the tag namespace.
   In normal Sentry usage, no `TaggedEventFilter` should reference
   `extra.text` because that key is not a tag. However, an operator can
   author a non-standard rule via API-direct POST that puts the literal
   string `extra.text` in a filter's `key` or `value` field — Sentry's
   tag-key character allowlist (`[a-zA-Z0-9_.:-]`, max 200 chars) does
   permit `extra.text` syntactically.

   Match logic: scan `rules[*].filters[*]` for any object whose `value` or
   `key` field contains the literal substring `extra.text` AND whose
   sibling filter or condition references `tool-label-scrub`. Emit a tuple
   per matching rule. **Realistic expectation: zero matches** — the script
   inventories this surface for completeness, not because matches are
   likely.
2. **Issue saved searches** — `GET /api/0/organizations/{org}/searches/`.
   Each search has a `query` field (free-text Sentry search syntax). Match
   when `query` contains both `extra.text` and `tool-label-scrub` (per
   learning `sentry-api-boolean-search-not-supported-20260406.md`, do this
   client-side via `jq`, not as a Sentry-API boolean search — the Sentry
   search syntax does not support `AND`/`OR` and would 400 on a boolean
   query).
3. **Discover saved queries** — `GET /api/0/organizations/{org}/discover/saved/`.
   Each query has a `query` field plus `fields[]`. Match when either the
   `query` string contains both literals OR any entry in `fields[]` is the
   literal `extra.text`. (A Discover query that aggregates by `extra.text`
   for `tool-label-scrub` events would have `extra.text` in `fields` and
   `op:tool-label-scrub` in `query`.)
4. **Dashboard widgets** — `GET /api/0/organizations/{org}/dashboards/`
   returns a flat list of dashboards. For each dashboard, GET
   `/api/0/organizations/{org}/dashboards/{id}/` to retrieve `widgets[]`.
   Each widget has `queries[]` with `conditions` (string), `fields[]`, and
   `aggregates[]`. Match when any of those three fields contains the
   `extra.text` literal AND a sibling field references `tool-label-scrub`.
   Note: this is the only resource class that requires a per-id GET
   round-trip; cap concurrency at 1 (sequential) to stay under
   Sentry's per-organization rate limit on the dashboards endpoint.

Each helper MUST use `--max-time 10` on `curl` (per learning
`oauth-probe-failure.md` and AGENTS.md sharp-edge: unbounded network calls
inherit resolver/socket defaults). Each helper MUST run `jq -e .` on the
response before further parsing — Sentry returns JSON-shaped error bodies
on 4xx and the `--max-time` exit on a hung connection, both of which produce
non-array responses.

**Output format (dry-run):** human-readable table to stdout, one match per
line, plus a summary at the end:

```
[issue-alert-rule]   id=12345 name="extra-text-burst"        match=filters[0].value
[saved-search]       id=98765 name="tool-label-scrub leaks"  match=query
[discover-saved]     id=#3147   name="scrub residual breakdown" match=fields[3]
[dashboard-widget]   dashboard=42 widget=2 name="Tool label scrub" match=queries[0].conditions

Summary: 4 matches across 4 resource classes. Run with --apply to rewrite, --add-or-clause to add OR clause.
```

If zero matches, print `No matches found. extra.text → extra.shape rename has no follow-through targets in this Sentry project.` and exit 0.

### Phase 3 — Rewrite phase (`--apply`)

For each match, implement an upsert that replaces `extra.text` with
`extra.shape` (or, with `--add-or-clause`, augments rather than replaces).

The rewrite is per-resource-class:

1. **Issue alert rules** — PUT `/projects/{org}/{project}/rules/{id}/` with
   the full rule payload, where any `filters[]` entry whose `value` or
   `key` contains `extra.text` has been rewritten in-place. Match-by-name
   idempotency follows the precedent's fail-closed pattern (refuse to
   mutate if multiple rules share the same name — this should be a hard
   error, not a "pick first" silent recovery).
2. **Issue saved searches** — PUT `/organizations/{org}/searches/{id}/` with
   the body `{query: <rewritten query string>}`. Use **`jq`-only** string
   substitution (`jq -n --arg q "$old_query" '$q | gsub("extra\\.text"; "extra.shape")'`)
   — NOT `sed` over a shell string. **Research insight:** Sentry tag values
   reject `\n`, but the `query` field on saved searches is a free-text
   Sentry search string and may contain control characters. A
   `sed "s/extra.text/extra.shape/g" <<< "$query"` substitution is
   shell-injection-adjacent on adversarial inputs (newlines, NUL,
   quote-escaped metacharacters); `jq -n --arg`'s `--arg` binding
   safely encodes the input as a JSON string. Verify post-write by
   GET-and-diff (compare jq-canonicalized JSON of pre/post to confirm
   only the targeted substring changed).
3. **Discover saved queries** — PUT `/organizations/{org}/discover/saved/{id}/`.
   Rewrite both the `query` string and any `fields[]`/`yAxis[]` entry that
   equals `extra.text`.
4. **Dashboard widgets** — POST/PUT to
   `/organizations/{org}/dashboards/{id}/` with the full dashboard body
   (Sentry dashboards API does not support per-widget mutation; the whole
   dashboard payload must be sent back). Within `widgets[*].queries[*]`,
   rewrite `conditions`, `fields[]`, and `aggregates[]` entries that
   contain `extra.text`. Re-fetch post-write to confirm.

For every PUT/POST, capture the response code via `-w '%{http_code}' -o "$resp_file"`
exactly as the precedent does. On non-2xx, echo the response body to stderr
and exit non-zero — never silently continue.

**`--add-or-clause` mode:** for query strings only (not for `fields[]`
arrays), wrap the existing clause in an OR clause:

- `extra.text:foo` → `(extra.text:foo OR extra.shape:foo)`

The mode's purpose is the deploy-window posture from the PR body operator
note. Default behaviour remains the simpler replace because (a) the deploy
already lands today, so no in-flight events from a pre-deploy build will use
`extra.text`, and (b) field-level rewrites in `fields[]` arrays cannot be
"OR'd" — they must be replaced. Document this asymmetry in the script
header.

### Phase 4 — Re-verify and exit

After `--apply` writes complete, re-run the inventory phase silently. If any
matches remain, exit non-zero with a list of unrewritten resources. If zero
matches, print `Verified: 0 references to extra.text remain on op:tool-label-scrub`
and exit 0.

This is the ops-remediation closure criterion. The post-merge step
`gh issue close 3147 --comment "<verification output>"` should be run only
after this exit-zero verification.

### Phase 5 — Runbook augmentation

Add a short runbook section to
`knowledge-base/engineering/ops/runbooks/` documenting the script's purpose,
invocation, and expected zero-match outcome going forward. Either:

- Extend `oauth-probe-failure.md` with a "Sentry config drift cleanup" sibling
  section (preferred — same operator surface as the existing
  `configure-sentry-alerts.sh` invocation), OR
- Create a standalone `sentry-extra-field-rename.md` runbook if the new
  content exceeds ~30 lines.

Decision deferred to work-phase based on the actual content size; either is
acceptable.

## Files to Edit

- `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` —
  add a "Sentry config drift cleanup" subsection pointing to the new audit
  script (or split to a sibling runbook if length warrants).

## Files to Create

- `apps/web-platform/scripts/audit-sentry-extra-text-references.sh` —
  the audit-and-rewrite script described above.
- `apps/web-platform/scripts/__tests__/audit-sentry-extra-text-references.bats`
  — IF the codebase already has `bats` installed for Bash unit tests
  (verify via `command -v bats` and `find apps/web-platform/scripts/ -name '*.bats'`).
  If absent, prefer integration verification (Phase 4 self-verify run on the
  real Sentry project in dry-run) over introducing a new test framework
  dependency. AGENTS.md sharp edge: never prescribe a new test framework
  without an explicit "Add `<framework>` dependency" task. The work skill
  must verify framework presence before writing the test file.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/scripts/audit-sentry-extra-text-references.sh`
      exists, is executable, follows `set -euo pipefail`, and matches the
      argument-parsing surface in Phase 1 (`--apply`, `--add-or-clause`,
      `--help`).
- [ ] Region detection probes `sentry.io` then `de.sentry.io` and exits
      non-zero with a clear error if neither responds 200 — verified by
      `bash <script> --help` (which exercises the early sanity-check path)
      AND by a smoke run with a deliberately invalid token producing the
      expected "token not valid" exit.
- [ ] All four inventory helpers respect `--max-time 10` on `curl` and
      `jq -e .` guard the parsed response (grep for `--max-time` count == 4
      `curl` invocations against Sentry hostnames).
- [ ] Inventory helpers AND on `tool-label-scrub` — verified by reading the
      script: a hit on `extra.text` alone (no `tool-label-scrub`) MUST NOT
      appear in the output. (Required to avoid mutating unrelated saved
      searches that happen to mention `extra.text` for a different `op`.)
- [ ] Match-by-name idempotency for alert rules: if two rules share a name,
      the script exits non-zero rather than picking one (mirrors precedent
      `configure-sentry-alerts.sh:upsert_rule`).
- [ ] PR body uses `Ref #3147` (NOT `Closes #3147`) — per AGENTS.md sharp
      edge for `ops-remediation` classification, the actual remediation
      runs post-merge; auto-closing on merge would mark the issue resolved
      before the rewrite has been verified. The operator manually closes
      the issue after the script's exit-zero verification.
- [ ] `apps/web-platform/lib/sandbox-path-patterns.ts`,
      `apps/web-platform/server/tool-labels.ts`, and
      `apps/web-platform/lib/format-assistant-text.ts` are NOT modified —
      this PR is scoped to the operator-side follow-through, not source
      changes.
- [ ] **`jq` dependency check** at script start
      (`command -v jq >/dev/null 2>&1 || { echo "jq not found …"; exit 1; }`)
      — verified by reading the script. Surfaces R7 (jq not installed).
- [ ] **`jq -n --arg` for all mutation payloads** — `grep -E 'sed.*"\$' apps/web-platform/scripts/audit-sentry-extra-text-references.sh`
      returns zero hits over Sentry payloads (R6 mitigation). The
      precedent script's `jq -n --arg name "$name" --argjson conditions "$conditions" …`
      pattern is the canonical form.
- [ ] **Tag-vs-extra distinction documented** in the script header
      comment block, mirroring Sharp Edge 8. Operators reading the script
      for the first time should see immediately that the Sentry UI's
      search bar will NOT find `extra.text` even when matches exist in
      saved-search/discover/dashboard query strings.

### Post-merge (operator)

- [ ] Operator runs the script in dry-run mode against prod Sentry:
      ```bash
      doppler run -p soleur -c prd -- bash apps/web-platform/scripts/audit-sentry-extra-text-references.sh
      ```
      If zero matches, the operator runs `gh issue close 3147 --comment "$(<dry-run output>)"` and the issue closes.
- [ ] If non-zero matches, the operator decides between `--apply` (replace,
      default) and `--apply --add-or-clause` (additive — only relevant if
      the matched resource is a paging alert and the operator wants
      defence-in-depth across the deploy window). After the rewrite, the
      script auto-verifies; on exit-zero the operator closes the issue
      with the post-rewrite output.
- [ ] (If applicable) the operator documents any non-trivial dashboard
      mutation in the project's ops journal, since dashboard widget
      rewrites send the full dashboard payload back and benefit from a
      paper trail.

## Test Strategy

- **Unit-test framework:** none introduced. `bats` is NOT currently in the
  repo (verified at plan time by `find apps/web-platform/scripts/ -name '*.bats'`
  returning empty). Plan defers tests to integration verification: the
  script's dry-run mode is itself the test harness — running it produces a
  deterministic match list, and re-running after `--apply` produces zero
  matches.
- **Integration verification path:** run dry-run via `doppler run -p soleur
  -c prd -- bash <script>` from a developer workstation (this requires the
  same `SENTRY_AUTH_TOKEN` the precedent script uses). The dry-run does NOT
  mutate state and is safe to invoke at PR-review time.
- **CI hookup:** none. The script is operator-invoked, not CI-invoked.
  Wiring it into CI would require a Sentry token in GitHub Actions secrets,
  which is unnecessary scope for this PR; the existing
  `configure-sentry-alerts.sh` precedent is also operator-invoked.

## Risks

- **R1 — Sentry API rate limits.** The dashboards endpoint requires a
  per-id GET to retrieve widgets. With ≥10 dashboards in the project, the
  inventory pass could brush rate limits. Mitigation: sequential GETs (no
  concurrency), `--max-time 10` per call, and explicit handling of HTTP 429
  with a single retry after `sleep 5`.
- **R2 — Match-set is empty (most likely outcome).** No Sentry config in
  the repo references `extra.text`, and the operator never explicitly
  created such an alert. The PR body's note is precautionary. If
  zero-match is the outcome, the script exits 0 with an explicit "no
  follow-through targets" message, the issue closes, and the script
  remains a reusable artifact for future field renames. This is a feature,
  not a defect.
- **R3 — Field-level rewrite asymmetry in `--add-or-clause` mode.** OR
  semantics apply to query strings (`conditions`, `query`) but not to
  `fields[]` / `aggregates[]` arrays — there's no syntactic way to express
  "either field A or field B" in a Discover `fields[]` array. The script
  must replace (not OR-augment) `fields[]` entries even in
  `--add-or-clause` mode, and must log this asymmetry per match. Document
  in the script header and in the runbook.
- **R4 — Sentry API region drift.** The prod Sentry workspace is currently
  on EU (`de.sentry.io` per `oauth-probe-failure.md` runbook). The probe
  pattern handles this transparently, but if the workspace migrates between
  regions during this PR's review window, the cached api_host could drift.
  Mitigation: the probe runs every invocation; no caching.
- **R5 — `extra.text` references outside the `tool-label-scrub` op.** A
  Sentry-savvy operator might have a global `extra.text` filter on
  unrelated ops (e.g., a different feature's silent-fallback diagnostic).
  The AND-with-`tool-label-scrub` guard is load-bearing — without it, the
  script would mutate unrelated alerts. The Acceptance Criterion that
  matches AND on both literals is the safety net.
- **R6 — Shell-injection-adjacent substitution.** Per the deepen-pass
  research insight on saved-search rewriting, a `sed` substitution over a
  shell variable holding adversarial input (newlines, NUL, quote-escaped
  metacharacters) is unsafe. The script uses `jq -n --arg` for ALL string
  substitutions in mutation payloads. Mitigation: a static grep against
  the script in CI confirming zero `sed.*"\$.*"` patterns on Sentry
  payloads.
- **R7 — `jq` not installed.** The precedent script implicitly assumes
  `jq` is on the operator's PATH. The new script makes the dependency
  explicit: `command -v jq >/dev/null 2>&1 || { echo "jq not found — install via 'brew install jq' or 'apt-get install jq'"; exit 1; }`
  immediately after the env-preamble. Cheap, defensive, prevents a
  cryptic `jq: command not found` mid-pipeline failure.
- **R8 — Tag-vs-extra namespace confusion (operator-side).** If an
  operator reads only the issue body and tries to "search Sentry for
  `extra.text`" via the issue stream search bar, they will get
  zero results — because `extra.text` is not a tag, the issue stream's
  search syntax does not index it. They might wrongly conclude the
  follow-through is complete. Mitigation: the runbook (Phase 5) MUST
  explicitly state that the issue-stream search bar does NOT cover all
  artifact classes; only the audit script does. This is a documentation-
  not-code mitigation, but it's the failure mode most likely to land
  if the operator skips running the script.

## Sharp Edges

- **Sharp Edge 1 — `## User-Brand Impact` section validation.** Per
  AGENTS.md `hr-weigh-every-decision-against-target-user-impact` and the
  plan-skill Phase 2.6 enforcement: `deepen-plan` Phase 4.6 will halt if
  the section is empty, contains placeholder text, or omits the threshold.
  This plan declares `threshold: none, reason: …` per the canonical
  scope-out path because no sensitive surface is touched.
- **Sharp Edge 2 — Sentry search API does not support boolean operators.**
  Per learning `sentry-api-boolean-search-not-supported-20260406.md`, do
  NOT attempt to inventory matches with a Sentry-side query like
  `extra.text:* AND op:tool-label-scrub` — Sentry returns 400. All
  AND-filtering happens client-side via `jq` after retrieving the full
  resource list. The Phase 2 inventory helpers are written this way.
- **Sharp Edge 3 — `--max-time` on every `curl`.** Per
  AGENTS.md sharp edge ("when a plan prescribes `dig`, `nslookup`, `curl`,
  or any network call inside a CI step, pin a timeout"). The script
  prescribes `--max-time 10` on all four inventory helpers and all
  rewrite PUT/POSTs.
- **Sharp Edge 4 — `jq -e .` on every response.** Sentry returns
  JSON-shaped 4xx error bodies (`{"detail": "…"}`) that look like valid
  JSON to a naive `jq 'length'`. Per the same boolean-search learning,
  the script must `jq -e . <<<"$resp"` to assert "is JSON AND not null"
  before parsing — and on array endpoints, follow with
  `jq 'if type == "array" then length else error end'` to catch the
  error-object-as-singleton trap.
- **Sharp Edge 5 — Issue close timing.** The script ships in this PR; the
  apply runs post-merge. Per AGENTS.md sharp edge for `ops-only-prod-write`
  classification, the PR body uses `Ref #3147`, NOT `Closes #3147`. The
  operator manually runs `gh issue close 3147` after the script's
  exit-zero verification. Pre-merge automatic closure would mark the
  issue resolved before the actual remediation runs.
- **Sharp Edge 6 — Test framework reconciliation.** Plan does NOT prescribe
  `bats` because it is not installed (`find apps/web-platform/scripts/ -name '*.bats'`
  returned empty at plan time). If the work-skill author considers adding
  `bats` for unit tests, AGENTS.md sharp edge requires (a) explicit "add
  bats dependency" task AND (b) reconciliation with this plan's "no new
  dependencies" stance. Default path is integration verification only.
- **Sharp Edge 7 — Plan AC external-state verification.** Per AGENTS.md
  sharp edge ("plan AC claims about external-service config must be
  API-verified"): this plan does NOT claim any specific number of matches
  in the prod Sentry workspace. It claims only that the script will
  enumerate them and that zero-match is a valid outcome. This avoids the
  PR #2769 trap of asserting external state from a code-grep.
- **Sharp Edge 8 — Tag-namespace vs. extra-namespace.** Discovered in
  deepen-pass via Context7. The Sentry issue-stream search bar and
  alert-rule `TaggedEventFilter` operate on the **tag** namespace
  (`Sentry.setTag()`), not on the **extra** namespace (`Sentry.setExtra()`).
  Therefore an operator searching the Sentry UI for `extra.text` will get
  zero results in the issue stream regardless of how many extra-context
  fields exist. The script's match logic accounts for this: the alert-rule
  branch matches `extra.text` literally in `filters[*].key/value` strings
  (which is structurally non-canonical but syntactically permitted), and
  the substantive matches are expected from saved-searches (free-text
  Sentry search) and Discover/dashboards (which DO index extra context).
- **Sharp Edge 9 — Dashboard mutation requires full-payload PUT.** The
  Sentry dashboards API does NOT support per-widget PATCH. Any widget
  mutation must serialize the entire dashboard back. The script must
  GET → jq-walk → PUT-full-dashboard, and re-fetch to confirm. A
  partial-payload PUT will silently nuke widgets the script didn't echo
  back. If this surfaces as a quirk during work-phase, file a learning
  file under `knowledge-base/project/learnings/integration-issues/`.

## Out of Scope / Non-Goals

- **No source-code changes.** PR #3127 already shipped the server-side
  rename. This plan is pure operator-side cleanup.
- **No CI integration.** The script is operator-invoked. Wiring into a
  GitHub Actions cron would require a workflow-scoped `SENTRY_AUTH_TOKEN`
  secret and a cadence justification — neither warranted by a one-time
  field rename.
- **No retroactive Sentry event mutation.** Existing events still tagged
  `extra.text` remain in Sentry's event store; we do not (and cannot via
  a public API) rewrite event tags. Only saved queries / dashboards / alert
  rules are mutated.
- **No client-side scrub change.** `lib/format-assistant-text.ts:88` is
  out of scope; PR #3127 left it intentionally on the matched-leak
  capture pattern. Issue #3147 is exclusively about Sentry config, not
  application code.

## References

- **Source PR:** #3127 (`fix(command-center): widen sandbox-path patterns
  for non-slash terminators`)
- **Tracking issue:** #3147 (`follow-through: Sentry alert rule rename
  extra.text → extra.shape (PR #3127)`)
- **Precedent script:** `apps/web-platform/scripts/configure-sentry-alerts.sh`
  (idempotent Sentry alert configurator, region detection, fail-closed
  duplicate handling)
- **Learnings:**
  - `knowledge-base/project/learnings/integration-issues/sentry-api-boolean-search-not-supported-20260406.md`
    — Sentry search API does not support boolean operators; AND filtering
    must be client-side via `jq`.
  - `knowledge-base/project/learnings/integration-issues/2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md`
    — Sentry rule API quirks (interval enumeration, NotifyEmailAction
    target shapes).
- **Runbook:** `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md`
  (Sentry API host detection, `SENTRY_API_HOST` env, configurator
  invocation pattern).
- **AGENTS.md rules:**
  - `hr-exhaust-all-automated-options-before` — drives the plan's
    "automate via REST API" framing instead of operator-manual handoff.
  - `hr-never-label-any-step-as-manual-without` — same.
  - `hr-weigh-every-decision-against-target-user-impact` — drives the
    `## User-Brand Impact` declaration.
  - `wg-use-closes-n-in-pr-body-not-title-to` + the
    ops-remediation `Ref #N` sharp edge — drives the PR body's `Ref #3147`.
