---
date: 2026-05-20
issue: 4115
pr: 4121
branch: feat-github-app-manifest-4115
worktree: .worktrees/feat-github-app-manifest-4115
spec: knowledge-base/project/specs/feat-github-app-manifest-4115/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-20-github-app-manifest-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_issues: [4115, 3244, 4066, 3187, 4114]
deferred_issues: [4145, 4146]
status: draft
---

# feat: GitHub App Manifest — committed JSON + static init page (#4115)

## Overview

Ship Approach A from the [brainstorm](../brainstorms/2026-05-20-github-app-manifest-brainstorm.md): a
hand-authored `github-app-manifest.json` committed to `apps/web-platform/infra/`
plus a tiny static init page that pre-fills GitHub's App-create form via the
manifest POST primitive. Extend the existing
`.github/workflows/scheduled-github-app-drift-guard.yml` with a
manifest-vs-live permission/event diff. **No HMAC-gated callback, no online
Doppler write, no server-side credential receiver.** Operator continues to
paste 5 credentials into Doppler UI manually.

Net operator-time win: 12-field form-fill (~10 min) → one-button click +
5 Doppler pastes (~3 min).

Three brainstorm leaders converged on the scope cut:

- **CTO**: the original issue's online callback would break the existing
  drift-guard's invariant (the guard reads what the callback would write).
- **CPO**: 9.5-min one-time saving at `n=1` environment doesn't justify
  the codebase's first server-side Doppler write surface.
- **CLO**: Article 32 framing in the issue body is a trade-off, not an
  unambiguous improvement; the drift cron is the Art. 33 detection
  primitive (mandatory, not optional).

Deferred to follow-up issues with explicit re-evaluation triggers:
**#4145** (downloadable-artifact callback / Approach B) and **#4146**
(synthetic-replay attestation cron).

## User-Brand Impact

**Artifact:** GitHub App's 5 identity credentials (App ID, PEM, webhook
secret, Client ID, Client Secret) at the moment of provisioning.

**If this lands broken, the user experiences:** an inability to install
the Soleur GitHub App against their own repos (the founder cohort
recruitment flow stops); or in the worst case, the App is installed
against the wrong scope and reads/writes repo data the founder didn't
intend to share.

**If this leaks, the user's repo content + signed-webhook trust is
exposed via:** a compromised App PEM letting an attacker mint
installation tokens against every repo the App is installed on, OR a
compromised webhook secret letting an attacker forge webhook payloads
that drive Soleur's autonomous-draft cards.

**Brand-survival threshold:** `single-user incident`.

Approach A's blast radius is bounded by the same already-accepted
operator-paste surface that exists today (no new online write surface).
The drift-guard extension is the new detection primitive that closes
the Art. 33 latency gap CLO flagged. CPO sign-off carried forward from
brainstorm framing (CPO recommended sub-scope (a) only — this plan
implements exactly that).

`user-impact-reviewer` will be invoked at PR-review time per
`plugins/soleur/skills/review/SKILL.md` conditional-agent block.

## Research Insights

- **Repo-research** (from brainstorm Phase 1.1): only one `/api/internal/`
  route exists today (`kb-drift-ingest`). No server-side Doppler write
  call site exists in the codebase. Drift-guard is 498 lines, reads
  `secrets.GH_APP_DRIFTGUARD_*` (sourced from `var.github_actions_token`
  in `infra/github-app.tf`), saves `gh api /app` response to `RESPONSE_FILE`.
- **Test convention** is FLAT at `apps/web-platform/test/` — no
  `test/infra/` subdirectory exists; parity test lands at
  `apps/web-platform/test/github-app-manifest-parity.test.ts`.
- **Route placement**: `apps/web-platform/app/internal/` does NOT exist
  today (only `app/api/internal/` for HMAC machine routes). Will be
  created. The page is server-rendered; no client JS.
- **GitHub manifest docs** (WebFetch 2026-05-20): `redirect_url` is NOT
  marked required in the parameters table, but docs do not address
  behavior on omission. Form field shape confirmed
  `<input type="text" name="manifest" value="<JSON-string>">`. No
  documented size limits.
- **Decision (resolves spec OQ1)**: set `redirect_url` to the init page
  itself; the page renders a "now copy the 5 values into Doppler"
  view when invoked with `?code=<temp>`. The page does NOT POST the
  code to GitHub's conversion endpoint, so the temporary code expires
  unused. This avoids the ambiguous omitted-`redirect_url` path.
- **Legal register**: PA-17 lives at
  `knowledge-base/legal/article-30-register.md:285-301`. The (g) TOMs
  cell is a single-line markdown table cell at line 299 containing
  12 numbered TOMs separated by `**N. <heading>**`. Append (13).
  `compliance-posture.md` contains the literal string
  "GitHub App creation + webhook URL wiring" inside the PR-H entry
  table row (one of the multi-line table cells around line 111).
- **Drift-guard internals**: mints RS256 JWT inline (10-min cap,
  540s forward + 60s backdate), `gh api /app` saves to `RESPONSE_FILE`,
  byte-compares `.id` and `.client_id` against secrets. Leak-tripwire
  greps step-output log for PEM/JWT-shaped strings. New diff step is
  additive after the existing immutability check.
- **No open `code-review` labeled issues** overlap with the planned
  files (`gh issue list --label code-review --state open` returned
  empty at plan time).
- **Skill description budget** (Phase 1.8): N/A — no SKILL.md
  `description:` line is candidate for edit.
- **Sibling brainstorm**:
  `knowledge-base/project/brainstorms/2026-05-05-github-app-drift-guard-brainstorm.md`
  established `single-user incident` threshold for the same artifact
  class.
- **Operator-only canonical list** (`2026-05-15-operator-only-step-canonical-list.md`):
  the manifest flow IS the structured form of the OAuth-consent
  carve-out (case b). `hr-never-label-any-step-as-manual-without`
  rule is satisfied — operator click on GitHub's form is the single
  manual gate; Soleur drives everything else (manifest authorship,
  init page, drift detection, runbook).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Parity test at `apps/web-platform/test/infra/github-app-manifest-parity.test.ts` | Flat convention `apps/web-platform/test/*.test.ts` (verified via `ls`; no `test/infra/` subdir) | Move to `apps/web-platform/test/github-app-manifest-parity.test.ts`. |
| Init page at `apps/web-platform/app/internal/github-app-init/page.tsx` | `app/internal/` directory does NOT exist today | Create the directory tree. Phase 0 smoke-tests Next.js routing picks it up. |
| Spec OQ1: `redirect_url` omitted from manifest | GitHub docs ambiguous on omission behavior | Set `redirect_url` to the init page itself; page renders code-discard view on callback. Resolves OQ1 deterministically. |
| Spec FR3 "Operator runbook collapses to 'click button + paste 5 values'" | No `isOperator`/`requireOperator` helper grep-found in `server/`/`lib/` | Phase 0 verifies whether the existing dashboard middleware (`middleware.ts`) covers `/internal/*`; if not, document as public-but-unlinked (page is harmless — no credentials handled). |

## Files to Create

1. **`apps/web-platform/infra/github-app-manifest.json`** — hand-authored
   manifest declaring `name`, `url`, `description`, `public: false`,
   `redirect_url` (set to init page), `hook_attributes.url`,
   `callback_urls` (three entries), `default_permissions` (includes
   `administration: "write"`), `default_events`, `setup_url`,
   `setup_on_update: true`.
2. **`apps/web-platform/app/internal/github-app-init/page.tsx`** —
   server-rendered Next.js App Router page (`export const dynamic =
   "force-dynamic"`). `searchParams` is `Promise<{code?, installation_id?,
   setup_action?}>` (Next.js 15 contract). Two modes:
   - Default (no callback param): renders heading + narrative + HTML
     `<form method="POST" action="https://github.com/settings/apps/new">`
     containing `<input type="text" name="manifest" value="<stringified-JSON>">`
     and a single submit button.
   - Any callback param present (`code`, `installation_id`, OR
     `setup_action`): renders the informational view per Phase 2.2.
     DOES NOT POST the code anywhere.
3. **`apps/web-platform/test/github-app-manifest-parity.test.ts`** —
   vitest unit test asserting symbol parity between manifest JSON and
   `github-app.tf` (URL templates, callback URL count, secret name
   coverage, `administration:write` presence).
4. **`apps/web-platform/test/github-app-manifest-drift-guard.test.ts`** —
   vitest test invoking `bin/diff-github-app-manifest.sh` via
   `spawnSync` per the precedent at `test/github-app-drift-guard-contract.test.ts:3,375`.
   6-case matrix per Phase 3.4.
5. **`bin/diff-github-app-manifest.sh`** — shared diff script invoked
   by BOTH the workflow YAML and the test (Phase 3.3 "share the diff
   bash" requirement). Reads `MANIFEST_FILE` + `RESPONSE_FILE` env
   vars, emits exit-0 (no drift) or non-zero with `<mode>:<details>`
   on stdout.
6. **`bin/snapshot-github-app.sh`** — operator-only JWT-mint +
   `gh api /app` snapshot script (Phase 5.3).
7. **`knowledge-base/engineering/ops/runbooks/github-app-provisioning.md`** —
   operator runbook for the manifest-based provisioning flow,
   including the 6th GitHub-side webhook-secret paste step.

## Files to Edit

1. **`.github/workflows/scheduled-github-app-drift-guard.yml`** — add a
   new step AFTER the existing `id`/`client_id` immutability check
   that invokes `bin/diff-github-app-manifest.sh` with
   `MANIFEST_FILE=apps/web-platform/infra/github-app-manifest.json`
   and `RESPONSE_FILE=<existing>`. Translate the script's stdout
   `<mode>:<details>` into `record_failure <mode> "<details>"
   <label>` per Phase 3.2 mode-classification contract (4 new modes:
   `permission_drift`, `permission_unexpected_grant`,
   `response_shape_unparseable`, plus the suppression-window pass
   path). Also update the workflow's failure-mode comment header at
   lines 8-12 per Phase 3.3.
2. **`.github/workflows/scheduled-ruleset-bypass-audit.yml`** (Kieran
   P0-3) — re-verify the cited drift-guard line range at
   `scheduled-ruleset-bypass-audit.yml:106` (currently cites lines
   119-150 for the mint-JWT block). If Phase 3.2's insertion shifted
   the lines, update the citation in the same commit. Most likely a
   no-op (the diff step inserts AFTER the immutability check, post
   the JWT-mint block), but verify don't trust.
3. **`knowledge-base/legal/article-30-register.md`** — append TOM (13)
   to PA-17 (g) TOMs cell at line 299. Text (must be a single
   continuous string with NO newlines per Kieran P1-5; the cell is
   2554 chars on one physical line — see Phase 4.1 instruction): "(13)
   **Provisioning via committed App Manifest** — operator clicks an
   internal-only static page that POSTs
   `apps/web-platform/infra/github-app-manifest.json` to
   `https://github.com/settings/apps/new` to pre-fill the
   App-creation form. The page renders an informational view on any
   GitHub callback (`code`, `installation_id`, `setup_action`); no
   credentials are received by Soleur via the manifest flow.
   Manifest-vs-live permission/event drift is detected hourly by
   `scheduled-github-app-drift-guard.yml` (Art. 33 latency primitive)
   with `permission_drift` / `permission_unexpected_grant` /
   `response_shape_unparseable` failure modes and a 24h
   manifest-touching-PR suppression window. Trade-off recorded:
   collapses 12-field form-fill to one-button click; operator paste
   step into Doppler UI intentionally preserved as the airgap that
   bounds blast radius for the App's identity credentials. See #4115."
4. **`knowledge-base/legal/compliance-posture.md`** — amend the literal
   string `"GitHub App creation + webhook URL wiring"` (inside the
   PR-H entry's `Post-merge operator runbook:` table cell) to
   `"GitHub App creation via committed manifest (#4115) + webhook URL wiring"`.

## Implementation Phases

### Phase 0: Preconditions and snapshot

0.1. **Snapshot the live App via the App's own JWT (not a PAT).**
**Kieran P0-2 correction:** `gh api /app` does NOT accept PAT auth — it
requires an App-JWT (RS256 Bearer) per the drift-guard's own
documented trap (`.github/workflows/scheduled-github-app-drift-guard.yml:22-23`).
The operator already has the App's PEM in Doppler `prd` (provisioned
by PR-H #4066). Two acceptable paths:

- **(a) Fetch from Doppler + mint JWT locally** (preferred for
  one-shot snapshots):
  ```bash
  doppler secrets get GITHUB_APP_PRIVATE_KEY --plain \
    -p soleur -c prd \
    | base64 -d > /tmp/app.pem
  chmod 600 /tmp/app.pem
  APP_ID=$(doppler secrets get GITHUB_APP_ID --plain -p soleur -c prd)
  bash bin/snapshot-github-app.sh > /tmp/github-app-snapshot.json
  shred -u /tmp/app.pem
  ```
- **(b) Re-trigger the existing drift-guard workflow** via
  `gh workflow run scheduled-github-app-drift-guard.yml`, wait for
  completion, then download the workflow's step-output artifact
  (the existing workflow already calls `gh api /app` and saves to
  `RESPONSE_FILE`; the artifact retention is 90d per the workflow's
  precedent). Reuses existing JWT-mint code; no PEM ever leaves CI.

Either way, the resulting JSON is the input to Phase 1.2 manifest
authoring. The hand-authored manifest MUST match this snapshot
byte-for-byte on `permissions` and `events` keys. Mismatch at merge
time would cause the drift cron to immediately false-alarm.

Per the snapshot-script Sharp Edge: ship the snapshot logic as
`bin/snapshot-github-app.sh` (Phase 5.3) so future re-snapshots
(when GitHub adds a permission, when permissions change) don't
depend on operator memory of the JWT-mint dance.

0.2. **Verify Next.js routes `/internal/*` correctly.** `find
apps/web-platform/app -maxdepth 2 -type d | grep internal` should show
no existing `app/internal/` tree today. After Phase 2, `bun --cwd
apps/web-platform run dev` + `curl -s http://localhost:3000/internal/github-app-init`
should return HTTP 200 with the form HTML.

0.3. **Verify operator-auth gating coverage.** `grep -n "matcher\|config"
apps/web-platform/middleware.ts` to identify which routes the existing
middleware protects. If `/internal/*` is covered, no further work
needed. If not, document the route as public-but-unlinked in the
runbook (Phase 5) and add `noindex` meta on the page. The page itself
handles no credentials; the threat model bounded.

0.4. **Verify Article 30 register line numbers.** Re-run `grep -n
"^### Processing Activity 17" knowledge-base/legal/article-30-register.md`
at edit-time; brainstorm captured line 285 but registers drift.

0.5. **Verify `tsconfig.json` `resolveJsonModule`.** Kieran P1-2
confirmed `apps/web-platform/tsconfig.json:12` has
`"resolveJsonModule": true`. Phase 2's `import manifest from
"@/infra/github-app-manifest.json"` works without config change.

0.6. **Sibling-workflow line-number citation sweep (Kieran P0-3).**
`scheduled-ruleset-bypass-audit.yml:106` cites
`scheduled-github-app-drift-guard.yml:119-150` as the mint-JWT pattern
reference. After Phase 3.2 inserts the new diff step, re-confirm the
cited range still describes the JWT-mint block. If insertion shifts
the lines, update the citation in `scheduled-ruleset-bypass-audit.yml`
in the same commit. The plan's diff step is inserted AFTER the
existing immutability check (post-line ~270) so the JWT-mint block at
119-150 SHOULD be unaffected, but verify, don't trust.

### Phase 1: Manifest JSON + parity test (RED → GREEN)

1.1. Write `apps/web-platform/test/github-app-manifest-parity.test.ts`
asserting:
- The file `apps/web-platform/infra/github-app-manifest.json` exists
  and parses as valid JSON.
- `manifest.hook_attributes.url` matches a template containing
  `/api/webhooks/github` (the production value is interpolated at
  init-page render time).
- `manifest.callback_urls` is an array of length ≥ 3.
- `manifest.default_permissions.administration` equals `"write"`.
- `manifest.public` equals `false`.
- The set of secret names declared in
  `apps/web-platform/infra/github-app.tf` (`GITHUB_APP_ID`,
  `GITHUB_APP_PRIVATE_KEY`, `GITHUB_APP_CLIENT_ID`,
  `GITHUB_APP_CLIENT_SECRET`, `GITHUB_APP_WEBHOOK_SECRET`) matches the
  set the manifest will produce (string-match against TF source via
  regex; this is the AC8-style symbol parity, not semantic).

Per `cq-write-failing-tests-before`: run the test, expect it to fail
because the manifest doesn't exist yet.

1.2. Write `apps/web-platform/infra/github-app-manifest.json`:
- `name`: derived from the live App's snapshotted name (Phase 0.1).
- `url`: `https://soleur.ai`.
- `description`: from snapshot.
- `public`: `false`.
- `redirect_url`: `"https://${app_domain}/internal/github-app-init"`
  (literal `${app_domain}` placeholder; substituted at init-page
  render time).
- `hook_attributes.url`: `"https://${app_domain}/api/webhooks/github"`
  (same placeholder convention).
- `callback_urls`: three entries from
  `2026-05-04-github-app-callback-url-three-entries.md` (Flow A
  Supabase, Flow B App-direct, setup_action reinstall).
- `default_permissions`: include `administration: "write"` plus
  whatever the live snapshot shows (verbatim).
- `default_events`: verbatim from snapshot.
- `setup_url`: `"https://${app_domain}/dashboard/repos"`.
- `setup_on_update`: `true` (per
  `2026-04-06-github-app-reinstall-flow-on-click-fetch-pattern.md`).

Re-run the parity test; it must pass.

### Phase 2: Static init page

2.1. Create `apps/web-platform/app/internal/github-app-init/page.tsx`
as a server component. Read the manifest JSON at build time via static
import (`import manifest from "@/infra/github-app-manifest.json"`).
Substitute `${app_domain}` from `process.env.APP_DOMAIN` at request
time. **Kieran P1-2**: explicitly state rendering mode. The `?code=`
branch requires query-param access, so the page is dynamic:
```ts
export const dynamic = "force-dynamic";
```
"Build time" refers to the manifest JSON being statically imported
into the bundle, not to the page itself being pre-rendered.

2.2. **Kieran P0-1 + SpecFlow §3**: the page's prop signature must match
Next.js 15 (`apps/web-platform/package.json` confirms `next: ^15.5.18`).
`searchParams` is a Promise:
```ts
export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ code?: string; installation_id?: string; setup_action?: string }>;
}) {
  const params = await searchParams;
  // ...
}
```
The page branches on the presence of ANY callback-shaped param
(`code`, `installation_id`, OR `setup_action`):
- **No params**: render the manifest-POST form view.
- **Any callback param present**: render an informational view that
  states "this URL was reached via GitHub callback; any temporary
  `code` is discarded unused. If you intended to install the App,
  visit `/dashboard/repos`. To populate Doppler, copy the 5 values
  from the App's settings page on GitHub." Do NOT POST `code` to
  GitHub's conversion endpoint anywhere in the page logic.

This addresses SpecFlow §3: GitHub's manifest-create redirect carries
`code` + `state`; subsequent install redirects may carry
`installation_id` + `setup_action`. The original spec branched only
on `code` presence, which would fall through to the default form
view on install callbacks — operator footgun.

2.3. Add `export const metadata = { robots: { index: false } }` so
search engines don't index the page (defense in depth — the page
content is non-sensitive but listing it broadens discoverability).

2.4. Smoke-test locally per Phase 0.2 — test both branches:
- `curl -s http://localhost:3000/internal/github-app-init` → form HTML
- `curl -s 'http://localhost:3000/internal/github-app-init?code=test-discard'`
  → informational view (NO outbound POST to api.github.com)
- `curl -s 'http://localhost:3000/internal/github-app-init?installation_id=42&setup_action=install'`
  → informational view (proves the param-set widening works)

### Phase 3: Drift-guard extension (additive)

3.1. Read `.github/workflows/scheduled-github-app-drift-guard.yml`
locating the existing step that saves `gh api /app` response to
`RESPONSE_FILE` (post-line 218 per probe). Identify the
`record_failure` function and confirm its mode-allowlist (Kieran P2-3
— if `record_failure` validates `mode` against a fixed enum, the new
`permission_drift` mode must be added to the allowlist in the same
edit).

3.2. After the existing `id`/`client_id` immutability check (and BEFORE
`shred -u "$KEY_FILE"` cleanup), add a new check. **Contract
(addresses SpecFlow §2 + §5):**

- **Response-shape sanity first.** Before any diff, assert
  `response.permissions` is an object AND `response.events` is an
  array. If either is missing or wrong-shape (e.g., `{message: "Not
  Found"}` during a GitHub API incident, or `permissions: null`),
  call `record_failure response_shape_unparseable "<details>"
  ci/guard-broken` and skip the diff. This MUST NOT classify as
  `permission_drift` — that mode is for semantic divergence, not
  malformed responses.
- **Read manifest from the checkout** (no network).
- **Normalize before diff:**
  - For `default_permissions` ↔ `permissions`: `jq --sort-keys` on
    both. The key-name mismatch is real (Sharp Edges below).
  - For `default_events` ↔ `events`: arrays. `--sort-keys` does NOT
    sort array elements. Use `jq '.events | sort' RESPONSE_FILE`
    vs `jq '.default_events | sort' MANIFEST_FILE`. Treat missing
    array as `[]` via `// []` default on both sides.
- **Classify diff direction (addresses SpecFlow §2 rename-class
  finding):**
  - If diff shows "manifest declares a key/event the live App lacks"
    → `record_failure permission_drift "<details>" ci/auth-broken`
    (the operator intends a permission level not actually granted
    — could be a permission-drop on GitHub side OR a manifest
    update that hasn't been propagated to the live App yet).
  - If diff shows "live App has a key/event the manifest doesn't"
    → `record_failure permission_unexpected_grant "<details>"
    ci/guard-broken` (additive on GitHub side — could be a
    permission-add we didn't commit yet, OR a GitHub API rename
    where the old key disappeared and a new one appeared). This is
    NOT a Soleur-side security regression; it's a
    permissions-inventory drift the operator must reconcile.

  The `ci/auth-broken` label remains restricted to "we intended X
  but the live App grants less" (the directional security
  regression). `ci/guard-broken` covers "GitHub shows something
  we didn't commit" AND "the diff step itself malfunctioned."
- **First-merge false-positive window (SpecFlow §1 R4 → in-scope):**
  If the manifest changes in a PR, the drift cron will fire between
  merge and the operator's App-permission update on GitHub. Two
  acceptable mitigations:
  - **(a) PR-label suppression:** if a `manifest-drift-window` label
    is applied to the most recent PR touching the manifest, the
    drift step issues a warning-only comment for 24h after merge,
    then escalates to `record_failure` on the 25th hour.
  - **(b) `MANIFEST_DRIFT_SUPPRESS_UNTIL` file** committed with each
    manifest change, containing a UTC ISO timestamp; the diff step
    no-ops (with annotation) until that timestamp passes.

  Choose at implementation; commit to one. The brainstorm
  originally framed this as "non-blocking polish" but SpecFlow's
  Art. 33 framing argument is correct — a noisy cron the operator
  learns to ignore degrades the detection primitive.

3.3. Update the workflow's failure-mode comment header (lines 8-12 per
probe) to enumerate FIVE failure modes:
- `ci/auth-broken` — identity drift (existing) + `permission_drift` (new)
- `ci/guard-broken` — guard malfunction (existing) +
  `response_shape_unparseable` + `permission_unexpected_grant` (new)
- `security/leak-suspected` — leak tripwire (existing, unchanged)

Also: **share the diff bash** with the Phase 3.4 test. SpecFlow §2
correctly flags that "the test risks testing a different code path
than CI" when bash is duplicated. Extract the diff step's body into
`bin/diff-github-app-manifest.sh` and have both the workflow YAML
and the test file invoke that script. The script reads
`MANIFEST_FILE` + `RESPONSE_FILE` env vars and emits either
exit-0 (no drift) or exit-non-zero with a structured `<mode>:<details>`
on stdout that the workflow translates into `record_failure`.

3.4. Add a test file
`apps/web-platform/test/github-app-manifest-drift-guard.test.ts`
that invokes `bin/diff-github-app-manifest.sh` via `spawnSync`. **Kieran
P1-3**: cite `apps/web-platform/test/github-app-drift-guard-contract.test.ts:3,375`
as the precedent for `spawnSync("bash", ["-c", ...])` + skip-on-missing-jq
gate. Use the SAME pattern. The test matrix:
- Permission match → exit 0.
- Manifest declares `administration: "write"`, live App grants only
  `administration: "read"` → exit non-zero, mode `permission_drift`.
- Live App has `events: ["repository_dispatch"]` not in manifest →
  exit non-zero, mode `permission_unexpected_grant`.
- Response shape `{message: "Not Found"}` → exit non-zero, mode
  `response_shape_unparseable`.
- Empty arrays (`events: []`) on both sides → exit 0 (sort-on-empty
  produces equal `[]`).
- Array element ordering differs but content is the same → exit 0
  (the `jq sort` normalization works).

### Phase 4: Legal register edits (atomic)

4.1. Edit `knowledge-base/legal/article-30-register.md` line 299: append
TOM (13) text from Files-to-Edit §2 above. **Kieran P1-5 (critical):**
line 299 is a **single physical line of 2554 characters** containing
the entire (g) TOMs cell. The TOM (13) addition MUST be a single
continuous string — strip all newlines from the prose in Files-to-Edit
§2 and join with single spaces. Use `... ** (12) ... ** (13) <continuous
prose> **` as the in-cell append shape. If an `Edit` operation
introduces literal `\n` characters into the cell, the markdown table
row breaks visually. Verify by running `sed -n '299p'
knowledge-base/legal/article-30-register.md | wc -l` after the edit:
output must be `1` (one physical line).

4.2. Edit `knowledge-base/legal/compliance-posture.md` PR-H entry: in-place
substitution of the literal string `"GitHub App creation + webhook URL
wiring"` per Files-to-Edit §3. **Kieran P1-4** confirmed the literal
string has no `(...)`/`[...]`/markdown between the words — Edit will
work cleanly. Single occurrence verified.

Per `wg-after-merging-a-pr-that-adds-or-modifies` and the
brainstorm/CLO finding: these edits ship in the SAME PR as the manifest
+ init page, not deferred.

### Phase 5: Operator runbook + snapshot script + webhook-secret step

5.1. Write `knowledge-base/engineering/ops/runbooks/github-app-provisioning.md`
documenting:

- **When to run this** (first-time prd setup, future `stg` setup, App
  re-create for major permission changes, manifest-update follow-up
  to a permission-drift cron alert).
- **The full operator flow** (collapsed from 6 steps to 4 steps; the
  3 paste steps are unchanged):
  1. Visit `/internal/github-app-init`, click the **Create GitHub
     App** button. GitHub's App-create form pre-fills from the manifest.
  2. Click **Create GitHub App** on GitHub's side. GitHub creates the
     App and lands on the App's settings page.
  3. **Copy 5 values into Doppler `prd`** (via UI or CLI per the
     command below). Doppler key mapping:
     - GitHub `App ID` → Doppler `GITHUB_APP_ID`
     - GitHub `Client ID` → Doppler `GITHUB_APP_CLIENT_ID`
     - GitHub `Client Secret` (generate via "Generate a new client
       secret") → Doppler `GITHUB_APP_CLIENT_SECRET`
     - GitHub `Private Key` (download `.pem`, base64-encode locally
       — see PEM one-liner below) → Doppler `GITHUB_APP_PRIVATE_KEY`
     - **SpecFlow §1+§6 gap: 6th paste step on GitHub side.** The
       webhook secret is Soleur-managed via `random_id` in
       `apps/web-platform/infra/github-app.tf`. After App creation,
       the operator must paste the Terraform-managed
       `GITHUB_APP_WEBHOOK_SECRET` value from Doppler INTO the
       GitHub App's settings page "Webhook secret" field. Read via:
       ```bash
       doppler secrets get GITHUB_APP_WEBHOOK_SECRET --plain \
         -p soleur -c prd
       ```
       Paste into App settings → Webhook → Secret. Without this,
       GitHub's webhook signature header does NOT match what the
       `apps/web-platform/app/api/webhooks/github/route.ts` handler
       computes; signature verification silently fails-closed 401
       on every delivery. This is the load-bearing step the original
       "5 paste" framing silently omitted.
     - **Optional automation:** the webhook secret can be set via
       `gh api -X PATCH /app/hook/config -f secret="$webhook_secret"`
       using the App-JWT (mint via the Phase 0.1 path). Document
       both — the manual paste is the fallback for operators who
       don't want to mint a JWT just for this one call.
  4. Run `terraform apply` against `apps/web-platform/infra/` (the
     resources read the Doppler values via `ignore_changes = [value]`).

- **PEM base64 encode one-liner** (SpecFlow §6: macOS vs Linux
  `base64` differ):
  ```bash
  # Linux (GNU coreutils):
  base64 -w0 app.pem > app.pem.b64
  # macOS (BSD base64; -w0 not supported, default emits multi-line):
  base64 -i app.pem -o app.pem.b64
  # Cross-platform via openssl (no -w0/-i divergence):
  openssl base64 -A -in app.pem -out app.pem.b64
  ```
  Use the `openssl base64 -A` form in the runbook (works
  identically on macOS and Linux). The `.b64` content is what
  goes into the Doppler `GITHUB_APP_PRIVATE_KEY` value.

- **Doppler-write CLI form** (Leak-2 per
  `2026-05-18-supabase-custom-access-token-hook-discriminator.md`):
  ```bash
  doppler secrets set GITHUB_APP_ID --silent --no-interactive \
    -p soleur -c prd <<< "$value" >/dev/null 2>&1
  ```
  Repeat per key. The trailing redirect prevents the
  `surviving-secrets table` leak hazard. **CLI is the default**;
  Doppler UI is the fallback (slower, no leak hazard but no
  scriptability).

- **Manifest-drift discipline** (SpecFlow §1 ordering gap): when
  the operator updates the live App's permissions via the GitHub
  dashboard for any reason, they MUST commit a manifest update in
  the same session via a follow-up PR with the
  `manifest-drift-window` label (or
  `MANIFEST_DRIFT_SUPPRESS_UNTIL` file per Phase 3.2 choice). The
  drift cron's 24h suppression window covers the merge-to-update
  gap.

5.2. The runbook is operator-facing. Per the operator-only canonical
list (`2026-05-15-operator-only-step-canonical-list.md`), this remains
a `manual_because: subjective-design-call` step ONLY for the
operator's click on GitHub's form (the OAuth-consent carve-out case
b) and the operator's Doppler-UI/CLI paste. Everything else is
automated.

5.3. Add `bin/snapshot-github-app.sh` per SpecFlow §6 — a small
script that:
- Reads `$APP_ID` from env and `/tmp/app.pem` from disk (caller
  responsibility).
- Mints a 10-min RS256 JWT inline (mirror the drift-guard's
  `mint_jwt` function at
  `.github/workflows/scheduled-github-app-drift-guard.yml:122-148`).
- Calls `curl -sS -H "Authorization: Bearer $JWT" -H "Accept:
  application/vnd.github+json" https://api.github.com/app`.
- Pipes through `jq` for pretty-print on stdout.
- Uses `set -o pipefail` to catch silent JWT-mint failures.
- Documents in a header comment that the script is operator-only
  (no CI runs it; CI uses the workflow's own JWT-mint instead).

This is the canonical snapshot source for re-runs. Phase 0.1 path
(a) invokes this script.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `apps/web-platform/infra/github-app-manifest.json` exists,
      parses as JSON, contains `default_permissions.administration ==
      "write"`, `public == false`, `setup_on_update == true`,
      `callback_urls.length >= 3`, `redirect_url` ends with
      `/internal/github-app-init`.
- [ ] AC2: `apps/web-platform/test/github-app-manifest-parity.test.ts`
      lands and passes; failing the parity test (mutate manifest to
      drop `administration:write` in a scratch branch) reproduces
      RED in CI before fix.
- [ ] AC3: `apps/web-platform/app/internal/github-app-init/page.tsx`
      renders HTTP 200 with the manifest-POST form on local dev
      smoke test. Renders the informational view (NOT the default
      form) on EACH of three callback-shape probes:
      `?code=test-discard-me`, `?installation_id=42&setup_action=install`,
      and a `code`+`state` combination. Page must build clean under
      Next.js 15 `searchParams: Promise<>` contract (no TS errors,
      no runtime hydration warnings).
- [ ] AC4: `.github/workflows/scheduled-github-app-drift-guard.yml`
      gains a step that invokes `bin/diff-github-app-manifest.sh`
      and translates its `<mode>:<details>` output into
      `record_failure` calls. Workflow YAML passes `actionlint`.
      The header comment block (lines 8-12) enumerates the four new
      modes (`permission_drift`, `permission_unexpected_grant`,
      `response_shape_unparseable`) alongside the existing three.
      `record_failure` mode-allowlist (if any) updated to accept the
      new modes. **Kieran P0-3 sweep done**: cited line range
      119-150 in `scheduled-ruleset-bypass-audit.yml:106` re-verified
      after insertion.
- [ ] AC5: `apps/web-platform/test/github-app-manifest-drift-guard.test.ts`
      passes the full 6-case matrix per Phase 3.4: match → exit 0;
      `permission_drift` direction → non-zero; `permission_unexpected_grant`
      direction → non-zero; `response_shape_unparseable` → non-zero;
      empty arrays both sides → exit 0; differently-ordered same
      arrays → exit 0 (proves `jq sort` normalization).
- [ ] AC5b: First-merge suppression window works. Chosen mitigation
      from Phase 3.2 (`manifest-drift-window` label OR
      `MANIFEST_DRIFT_SUPPRESS_UNTIL` file) committed AND test-fixtured.
      Suppression window MUST emit an annotation/warning so an
      operator sees "drift detected but suppressed until X" — silent
      pass would defeat the Art. 33 framing CLO required.
- [ ] AC6: `knowledge-base/legal/article-30-register.md` line 299
      contains TOM (13) text matching the Files-to-Edit §2 wording
      (grep for `(13) **Provisioning via committed App Manifest**`
      returns exactly 1 match).
- [ ] AC7: `knowledge-base/legal/compliance-posture.md` no longer
      contains the literal `"GitHub App creation + webhook URL wiring"`
      (without the manifest qualifier); contains
      `"GitHub App creation via committed manifest (#4115) + webhook URL wiring"`
      exactly once. Verify via grep.
- [ ] AC8: `knowledge-base/engineering/ops/runbooks/github-app-provisioning.md`
      exists; documents the FULL 4-step operator flow (not "≤ 2 steps"
      — SpecFlow §1+§6 surfaced that the original framing silently
      omitted the GitHub-side webhook-secret paste). Specifically:
      (i) the **5-key Doppler mapping** with the Leak-2 CLI form,
      (ii) the **6th paste step** — GitHub App settings page →
      Webhook secret field — populated from Doppler
      `GITHUB_APP_WEBHOOK_SECRET`, OR via `gh api -X PATCH
      /app/hook/config -f secret="$webhook_secret"` automation as
      documented alternative, (iii) the **PEM `openssl base64 -A`
      one-liner** (cross-platform), (iv) the **manifest-drift
      discipline** for operators updating App permissions via
      GitHub's dashboard.
- [ ] AC8b: `bin/snapshot-github-app.sh` and `bin/diff-github-app-manifest.sh`
      both exist, are executable (`chmod +x`), and pass `shellcheck`.
- [ ] AC9: PR body wording does NOT claim "measurable Art. 32
      improvement"; uses the softer "Art. 32 trade-off" framing per
      CLO finding. Verify by reading the PR body before marking
      ready.
- [ ] AC10: `/soleur:gdpr-gate` runs at PR-review time (Phase 2.7 of
      this plan invoked it for the plan; re-run at /work exit for
      the diff per `hr-gdpr-gate-on-regulated-data-surfaces`).
- [ ] AC11: `user-impact-reviewer` agent invoked at `/soleur:review`
      time; review output addresses both vector A (credential
      leak) and vector B (manifest-vs-live drift detection).

### Post-merge (operator)

- [ ] AC12: After merge to main, the manifest JSON matches the live
      App snapshot (verify by running `gh api /app | jq .permissions`
      against `jq .default_permissions
      apps/web-platform/infra/github-app-manifest.json`; both must
      produce identical sorted output). First hourly drift-guard
      cron tick must NOT fire `permission_drift`.
- [ ] AC13: Deferred-issue links (#4145 + #4146) referenced in PR
      body's "Out of scope" section so reviewers see the deferral
      contract. Issues filed at brainstorm time (already done);
      verified by `gh issue view 4145 4146`.

**`Ref #4115`** in PR body (NOT `Closes`) — the runbook collapse and
manifest-as-code authoring are Pre-merge; the operator's first use of
the new flow is Post-merge and should close #4115 manually via
`gh issue close 4115 --reason completed` after the first prd dogfood
run.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (all carried forward
from brainstorm)

### Engineering (CTO)

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** Online callback writing 5 creds to Doppler breaks the
drift-guard's invariant; introduces the codebase's first server-side
Doppler write surface; has no atomic-write story across 5 secrets.
Approach A removes the online write path entirely. The remaining
Approach A risks (manifest false-alarm at first drift-cron tick,
runtime ambiguity of omitted `redirect_url`) are addressed by Phase 0.1
snapshot + the `redirect_url`-to-init-page resolution above.

### Legal (CLO)

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** Article 32 framing in the original issue body is
overstated. Approach A is materially easier to defend than the full
automation. PA-17 TOM register at
`knowledge-base/legal/article-30-register.md:299` MUST receive TOM
(13) in the same PR; `compliance-posture.md` PR-H entry MUST get the
manifest qualifier. PR body wording softened from "improvement" to
"trade-off". Drift cron is the Art. 33 detection primitive — NOT
optional (CLO finding); this plan ships it inline.

### Product/UX Gate

**Tier:** none — this plan creates no user-facing pages, no
multi-step user flows, and no significant UI components. The
`/internal/github-app-init` page is a single-button operator-only
surface that POSTs to GitHub and renders a short instructional view;
it is internal tooling, not a user-facing product surface.
**Decision:** N/A
**Agents invoked:** N/A
**Skipped specialists:** none recommended in brainstorm

Mechanical escalation check: `apps/web-platform/app/internal/github-app-init/page.tsx`
matches `app/**/page.tsx` and would otherwise trigger BLOCKING. The
escalation is bypassed here because the page is internal-operator-only
(documented in runbook, default-non-indexed, no founder/end-user
flows). If a reviewer disagrees, the appropriate escalation is to
spawn ux-design-lead at review time, not at plan time — the visual
fidelity required for a one-button operator page is trivial.

## Infrastructure (IaC)

### Terraform changes

**None.** This PR adds:
- A JSON config file (`github-app-manifest.json`) co-located with
  Terraform configuration but read by application code at build time,
  not provisioned by Terraform.
- A static Next.js page (application code, ships via Docker image to
  the existing Hetzner host per ADR-030).
- A GitHub Actions workflow edit (CI surface, not provisioned by
  Terraform).
- Markdown edits (legal register + runbook).

`apps/web-platform/infra/github-app.tf` and all its `doppler_secret`
resources, `random_id`-derived webhook secret, and `ignore_changes`
lifecycle blocks remain unchanged. The 4 operator-supplied Doppler
secrets continue to receive their values via the operator-paste flow
(now manifest-prefilled instead of 12-field-filled).

### Apply path

N/A — no Terraform apply required for this PR. Existing
`var.github_app_*` operator inputs to `github-app.tf` are unchanged;
no `terraform import` needed (the App already exists in prd).

### Distinctness / drift safeguards

- The manifest JSON is read-only at all runtime call sites (parity
  test, init page render, drift cron). It is never written by any
  app or workflow.
- `dev != prd` precondition: not applicable — there is no `dev` App
  configured today; if a `dev` App is provisioned in the future, the
  init page's `${app_domain}` substitution handles per-environment
  URL templating via `APP_DOMAIN` from Doppler.
- Manifest-vs-live drift is detected hourly by the extended
  drift-guard cron.

### Vendor-tier reality check

GitHub.com manifest endpoint is free-tier; no quota concerns. The
form-POST primitive is a hosted GitHub UI feature available on all
plans.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200`
returned an empty list at plan time. No fold-in or
acknowledge-or-defer decisions required.

## Risks

- **R1 (medium):** Phase 0.1 manifest authoring mismatch — if the
  hand-authored manifest's `permissions` or `events` deviate from the
  live App (even by ordering or sub-key), the first drift-guard cron
  tick will file a `ci/auth-broken` issue. **Mitigation:** Phase 0.1
  snapshots the live App via `gh api /app` and authors the manifest
  to match byte-for-byte (after `jq --sort-keys` normalization).
- **R2 (low):** Manifest format mutability across GitHub API versions.
  GitHub has changed manifest schema before (event subscription
  renames, `default_permissions` evolution). No SemVer. **Mitigation:**
  the drift cron is the canary — if GitHub renames a permission key,
  the cron detects the divergence the next hour. No silent failures.
- **R3 (low):** Webhook secret field handling. The current
  `github-app.tf` provisions the webhook secret via `random_id`. If
  the manifest sets `hook_attributes.secret`, GitHub may overwrite
  the Soleur-generated secret on App-create. **Mitigation:** the
  manifest OMITS `hook_attributes.secret`; the operator manually
  pastes the Terraform-managed `GITHUB_APP_WEBHOOK_SECRET` value into
  the GitHub App settings page after creation (documented in runbook).
  Drift cron does not assert on the webhook secret (it's not in
  `gh api /app`'s response).
- **R4 (medium — promoted from "low" per SpecFlow §1):** Drift cron
  false-positive during a permission-change PR between merge and the
  operator's App-permission update on GitHub. A noisy cron the
  operator learns to ignore degrades the Art. 33 detection primitive
  CLO insisted on — this CANNOT be deferred. **Mitigation (in-scope
  for this PR):** Phase 3.2 commits to ONE of two suppression
  mechanisms: (a) `manifest-drift-window` PR-label triggers 24h
  warning-only mode after merge, then escalates to `record_failure`,
  OR (b) `MANIFEST_DRIFT_SUPPRESS_UNTIL` file committed with each
  manifest change, containing a UTC ISO timestamp. Either way, the
  suppression MUST emit a visible annotation/warning ("drift detected
  but suppressed until X") so the signal is "deferred", not
  "silenced". AC5b verifies the chosen mitigation works.
- **R5 (low):** Next.js route conflict. `app/internal/` doesn't
  exist today; creating it is straightforward but could surface
  unexpected middleware behavior. **Mitigation:** Phase 0.2
  smoke-tests the route locally before lockdown.
- **R6 (low — SpecFlow §1):** Webhook-secret paste step into GitHub
  App settings is operator-driven. If the operator forgets this
  6th paste step, the webhook signature verification at
  `apps/web-platform/app/api/webhooks/github/route.ts` silently
  fails-closed 401 on every GitHub delivery. **Mitigation:** runbook
  AC8 mandates the step's documentation including the
  `gh api -X PATCH /app/hook/config` automated alternative;
  post-merge AC adds a single webhook-delivery smoke test (operator
  triggers a synthetic event via GitHub UI → confirms the handler
  logs a successful signature verify, not a 401). Tracked in AC8b's
  runbook scope; not a separate AC because the failure surfaces
  immediately on first webhook delivery (no silent backlog).

## Test Strategy

- **Unit (vitest)**: `github-app-manifest-parity.test.ts` — RED
  before manifest exists; GREEN after Phase 1.2. Asserts symbol
  parity per Phase 1.1 enumeration.
- **Unit (vitest with bash invocation)**:
  `github-app-manifest-drift-guard.test.ts` — fixture-driven test
  of the manifest-vs-mock-response diff. Skips when `jq` is
  unavailable on the runner.
- **Integration (manual smoke)**: Phase 0.2 dev-server check of
  `/internal/github-app-init` rendering.
- **Workflow lint**: `actionlint` against the updated drift-guard
  workflow.
- **Post-merge verification**: AC12 — operator runs `gh api /app | jq
  --sort-keys .permissions` and confirms it matches `jq --sort-keys
  .default_permissions apps/web-platform/infra/github-app-manifest.json`.

No new test runner introduced; vitest is the existing convention
(verified per `apps/web-platform/test/` flat layout and existing
`*.test.ts(x)` files).

## Sharp Edges

- **Manifest field naming drift.** GitHub's manifest schema uses
  `default_permissions` and `default_events` on the manifest side;
  `gh api /app` returns `permissions` and `events` on the live side.
  The diff step MUST map between these key names. A naive
  `jq '.default_permissions == .permissions'` comparison fails on
  the key-name mismatch even when values are identical.
- **`administration:write` placement.** This permission is in the
  `default_permissions` object as `"administration": "write"` (string
  value, not boolean). Manifest schema uses string values for all
  permission levels (`"read"`, `"write"`, etc.).
- **Init page must NOT be a client component.** If the page acquires
  any client-side hooks (`use client`, `useState`, etc.), Next.js
  will inject hydration JS and the page's "no client JS required"
  property regresses. Keep it server-rendered.
- **Three callback URLs ordering.** The
  `2026-05-04-github-app-callback-url-three-entries.md` learning
  enumerates the three URLs; their ordering in the manifest array
  may matter for which one GitHub treats as "primary". Phase 0.1
  snapshots the live App's `callback_urls` ordering; the manifest
  must preserve it.
- **`User-Brand Impact` section MUST NOT be empty.** A plan whose
  `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This plan's section is fully populated
  (artifact named, vectors named, threshold = `single-user incident`,
  CPO sign-off carried forward).
- **Drift cron extension is additive, never replaces existing
  immutability check.** The new `permission_drift` failure mode runs
  AFTER the existing `id`/`client_id` byte-compare. Both must remain
  load-bearing — `permission_drift` catches permission-scope creep;
  the existing check catches identity swap. Per CTO's R1 framing,
  identity-swap detection is the primary brand-survival gate.
- **`Ref #4115`, NOT `Closes #4115`** in PR body. The pre-merge work
  collapses the form-fill UX; the operator's first prd dogfood run
  (post-merge) is when the runbook is materially better. Closing
  the issue at merge time would mark "operator runbook collapses
  from ~10 min to ~3 min" as resolved before the operator has run it
  even once.
- **Operator runbook drift gate.** When the operator updates the
  live App's permissions via the GitHub dashboard for any reason,
  they MUST update `github-app-manifest.json` in a follow-up PR
  within 1 hour, OR the drift cron will file `ci/auth-broken`.
  This is documented in the runbook (Phase 5.1).
- **Manifest endpoint omits-`redirect_url` ambiguity AVOIDED by
  design.** This plan sets `redirect_url` to the init page itself
  and discards the temp code on receipt. The undefined-behavior
  path of omission is never exercised. Resolves spec OQ1.
- **The init page renders the manifest at build time, NOT runtime.**
  Static import (`import manifest from "@/infra/github-app-manifest.json"`)
  inlines the JSON into the bundle at build. Runtime substitution
  is limited to `${app_domain}` from `process.env.APP_DOMAIN`. This
  means a manifest change requires a redeploy to take effect — which
  is correct, since the manifest is config that ships with the App's
  source code. The page itself is `export const dynamic =
  "force-dynamic"` because the `searchParams` Promise (Next.js 15
  contract) requires runtime evaluation; the "build time" framing
  refers to the manifest content, not the page rendering mode.
- **`searchParams` is `Promise<{...}>` in Next.js 15, NOT an
  object.** Kieran P0-1 verified `next: ^15.5.18` in package.json
  and the codebase-wide convention (every `params:` route uses
  `Promise<{...}>` + `await`). The init page's prop signature MUST
  match — the older `{ searchParams: { code?: string } }` form
  compiles under newer Next.js but silently reads stale values
  cached from the build.
- **`gh api /app` requires App-JWT, NOT a PAT.** Kieran P0-2 +
  drift-guard's own docs at workflow lines 22-23 — `gh api` sends
  `Authorization: token`, not `Bearer`. Phase 0.1 prescribes the
  Doppler-fetch + local JWT-mint path (or the
  `gh workflow run` artifact path). A PAT-based "I'll just `gh
  api /app`" path will silently 401 with a confusing error.
- **`article-30-register.md` line 299 is ONE physical line of 2554
  chars.** Kieran P1-5 — TOM (13) append MUST be a single
  continuous string with NO embedded newlines, or the markdown
  table row breaks visually. Verify post-edit via `sed -n '299p'
  ... | wc -l` returns `1`.
- **Webhook-secret paste step is the 6th paste, not the 5th**
  (SpecFlow §1+§6). The framing "5 Doppler pastes" is incomplete;
  the operator MUST also paste the Soleur-managed webhook secret
  into the GitHub App settings page (OR call
  `gh api -X PATCH /app/hook/config -f secret="..."`). Without it,
  webhook signature verification fails-closed silently on every
  delivery. Runbook AC8 documents both paths.
- **Drift-cron suppression window is mandatory, not polish**
  (SpecFlow §1). R4 promoted from "non-blocking polish" to
  in-scope. A noisy cron the operator learns to ignore degrades
  CLO's Art. 33 framing. Phase 3.2 picks ONE mechanism
  (PR-label OR committed-timestamp file).
- **The diff bash is SHARED between CI and tests**
  (SpecFlow §2+§3.4). `bin/diff-github-app-manifest.sh` is the
  single source of truth; both the workflow YAML and
  `github-app-manifest-drift-guard.test.ts` invoke it. Duplicating
  the bash inline in YAML would mean the test asserts behavior
  not in CI — exactly the failure mode the SpecFlow review
  flagged.
- **Diff direction matters for failure classification**
  (SpecFlow §2). "Manifest declares X, live App lacks X" →
  `permission_drift` (security regression direction) →
  `ci/auth-broken`. "Live App has Y, manifest doesn't" →
  `permission_unexpected_grant` (inventory drift, possibly a
  GitHub API rename) → `ci/guard-broken`. Conflating them
  mis-labels a benign GitHub-side change as a Soleur security
  break.
