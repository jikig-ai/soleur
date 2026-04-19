# ops: MU1 fixture repo + AC-2 clone-verification wiring (#2605)

## Enhancement Summary

**Deepened on:** 2026-04-19
**Sections enhanced:** Phase 1 (CLI verification), Phase 3 (Doppler
multiline piping), Phase 4 (test block + `Number.isFinite` guard),
Risks (R7–R9 added), Research Insights (Doppler + PEM handling).
**Research sources used:** `gh repo create --help` (verified flags),
`gh repo edit --help` (verified flags), `doppler secrets set --help`
(stdin piping form), live inspection of
`apps/web-platform/server/github-app.ts:97-101` (PEM `\n` replacement
contract), `gh api /orgs/jikig-ai/installations` (confirmed App id
`122213433`), `gh api /repos/jikig-ai/mu1-fixture` → 404 (repo does
not exist today — AC-A is a real create, not a re-install).

### Key Improvements

1. **Fixed fabricated `gh repo create` flag.** Initial plan used
   `--add-readme=false`; the flag is boolean-only (`--add-readme`
   turns it ON; omit for default OFF). Verified via `gh repo create
   --help`.
2. **Replaced command-substitution PEM copy with stdin pipe.** The
   private key contains literal newlines; `$(doppler secrets get
   GITHUB_APP_PRIVATE_KEY -p soleur -c prd --plain)` as an argument
   risks shell-quoting drift, and the receiving `doppler secrets set
   KEY "value"` form does not guarantee preservation of embedded
   newlines on every shell. Swapped to `doppler secrets get … --plain
   | doppler secrets set …` via stdin, which is the recommended form
   per `doppler secrets set --help`.
3. **Added numeric-id guard to the AC-2 test.** `Number(envStr)`
   returns `NaN` for malformed env values, which would silently pass
   into `generateInstallationToken` and fail deep in the API with a
   confusing "Bad credentials". `Number.isFinite(installationId) &&
   installationId > 0` assertion runs BEFORE the clone so a bad env
   var fails at the gate with a clear message.
4. **Documented PEM `\n` escape contract.** `github-app.ts:97-101`
   normalizes `\\n` → `\n` in the private key. If `doppler secrets
   set` is invoked via non-stdin form (multi-secret mode), Doppler
   will escape newlines — this plan now prescribes the stdin form
   explicitly to avoid double-escaping.
5. **Surfaced two silent-failure modes in Risks.** R7 (workspace
   root not writable under default `tmpdir()` when run inside a
   container with read-only `/tmp`) and R8 (GitHub App install scoped
   to wrong installation — the repo-level install id is different
   from the org-level id even for the same App; using the org-level
   id will fail token generation with 404).

### New Considerations Discovered

- `gh api /repos/jikig-ai/mu1-fixture/installation` with JWT Bearer
  is the cleanest path to the repo-scoped installation id (vs.
  listing all installations and filtering). Phase 2 prescribes this.
- `gh repo create` does not accept `--disable-projects` or
  `--disable-discussions` (only `--disable-issues` and
  `--disable-wiki`). Projects/discussions must be disabled via
  `gh repo edit` post-create. Phase 1 split accordingly.

## Overview

This plan lands the deferred piece of MU1 AC-2: a real public GitHub
repository the MU1 integration test can clone via `provisionWorkspaceWithRepo`
using installation-token auth. Until now, AC-2 has been verified manually
per the runbook's "AC-2 — Manual repo-clone verification (temporary)"
section. This plan replaces the manual step with an automated gated
describe block.

Three shared-systems touch points require an explicit confirmation pause
before execution (called out inline):

1. Creating the public fixture repo.
2. Installing the existing `soleur-ai` GitHub App on the fixture repo.
3. Writing the three new secrets into Doppler `dev`
   (`MU1_FIXTURE_REPO_URL`, `MU1_FIXTURE_INSTALLATION_ID`, plus the
   `GITHUB_APP_ID` / `GITHUB_APP_PRIVATE_KEY` gap — see "Research
   Reconciliation" below).

Scope is strictly AC-2 automation. The runbook's "AC-2 — Manual
repo-clone verification" block stays in place as a fallback path when
the env vars are not set; `describe.skipIf(...)` gates the automated
test on both env vars so default-lane runs are unchanged.

**Issue:** #2605
**Parent:** #1448
**Branch:** `feat-one-shot-mu1-fixture-repo`
**Worktree:** `.worktrees/feat-one-shot-mu1-fixture-repo/`
**Milestone:** Phase 4: Validate + Scale
**Priority:** P2 — blocks full MU1 automation but not the MU1 sign-off
itself (manual verification path is already documented and passing).

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #2605)                                                            | Codebase reality                                                                                                                                                                                     | Plan response                                                                                                                                                      |
| ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| "Create public GitHub fixture repo `soleur-ai/mu1-fixture`."                        | `soleur-ai` is a GitHub **App**, not an org. The App is installed on org `jikig-ai` (installation id `122213433`, confirmed via `gh api /orgs/jikig-ai/installations`). No `soleur-ai` org exists.   | Create the repo at `jikig-ai/mu1-fixture` (public). Install the existing `soleur-ai` App on it. Name in the issue body is labeled "candidate" — this is the resolution. |
| "Install a GitHub App on it so `provisionWorkspaceWithRepo` can clone."              | `generateInstallationToken` (`apps/web-platform/server/github-app.ts:425`) needs `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` at runtime. These are present in `prd`/`ci`; they are **absent** in `dev`. | Plumb `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` into Doppler `dev` in the same Doppler step as the fixture vars. Without them, `generateInstallationToken` throws and AC-2 cannot run under dev creds at all. |
| "Plumb `MU1_FIXTURE_REPO_URL` + `MU1_FIXTURE_INSTALLATION_ID` into Doppler `dev`."   | Doppler `dev` today has neither. Verified with `doppler secrets --only-names -p soleur -c dev`.                                                                                                    | Write both secrets. `MU1_FIXTURE_INSTALLATION_ID` is the single installation id after the fixture install (re-uses the existing `soleur-ai` App, but the installation id is repo-scoped only if the App is single-repo-selected at install time — see "Install options" below). |
| "Convert `describe.skip` → `describe.skipIf(...)`."                                  | The current file has a C-style block comment placeholder (lines 178-184). There is **no `describe.skip` block** in the file today — the describe was replaced with a comment during a prior edit. | The plan REPLACES the placeholder comment with a real `describe.skipIf(!process.env.MU1_FIXTURE_REPO_URL \|\| !process.env.MU1_FIXTURE_INSTALLATION_ID)(...)` block. The issue body's "convert" phrasing slightly undersells: this is a create-not-edit change. |
| "The `test.skip` block is marked so the runbook still passes manually."             | The runbook does NOT import the skip marker; it references the describe block by name ("`MU1 AC-2: provisionWorkspaceWithRepo clones fixture`").                                                  | Use that exact describe title so the runbook's expected-output lines (4 passed / 2 skipped → 5 passed / 1 skipped → 6 passed / 0 skipped depending on env vars) stay grep-stable. Update the runbook counts at the same time. |

**Why reconciliation section:** issue #2605 inherits the parent plan's
(#1448) "soleur-ai" phrasing, which conflates the App name with an org
that does not exist. Shipping the repo under that name would require
creating a new org (expensive) or a user-owned repo (wrong). The
reconciliation makes the correct target org explicit.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC-A (fixture repo exists):** `gh repo view jikig-ai/mu1-fixture
      --json visibility,isArchived` returns `"visibility":"PUBLIC"` and
      `"isArchived":false`. Repo contains exactly:
  - `README.md` (two paragraphs explaining the fixture's purpose and a
    link back to `jikig-ai/soleur#2605`).
  - `knowledge-base/README.md` (one paragraph, describing the stub).
  - No other files; no hidden dotfiles beyond `.git/`.
- [ ] **AC-B (App installed):** `gh api
      /repos/jikig-ai/mu1-fixture/installation` returns the `soleur-ai`
      App (id = `GITHUB_APP_ID` from Doppler `prd`) with
      `repository_selection = "selected"` and `single_file_name = null`.
      The installation id recorded in Doppler
      (`MU1_FIXTURE_INSTALLATION_ID`) matches the `id` field of that
      response.
- [ ] **AC-C (Doppler secrets written):** `doppler secrets get
      MU1_FIXTURE_REPO_URL -p soleur -c dev --plain` returns
      `https://github.com/jikig-ai/mu1-fixture.git` (HTTPS, with `.git`
      suffix — the form `git clone` expects). `doppler secrets get
      MU1_FIXTURE_INSTALLATION_ID -p soleur -c dev --plain` returns a
      numeric id. `doppler secrets get GITHUB_APP_ID -p soleur -c dev
      --plain` returns the same id as in `prd`. `doppler secrets get
      GITHUB_APP_PRIVATE_KEY -p soleur -c dev --plain` returns a PEM
      block starting with `-----BEGIN RSA PRIVATE KEY-----`.
- [ ] **AC-D (test block gated + passing):** The file
      `apps/web-platform/test/mu1-integration.test.ts` contains a
      `describe.skipIf(...)` block titled exactly `MU1 AC-2:
      provisionWorkspaceWithRepo clones fixture`. Under
      `doppler run -p soleur -c dev --` with `MU1_INTEGRATION=1`, the
      block runs and asserts:
  - `provisionWorkspaceWithRepo(randomUUID(), env.MU1_FIXTURE_REPO_URL,
    Number(env.MU1_FIXTURE_INSTALLATION_ID))` resolves to a workspace
    path under the test `WORKSPACES_ROOT`.
  - That path contains `README.md` (from the fixture) and `.git/`
    (`existsSync` on both).
  - The `plugins/soleur` symlink from `scaffoldWorkspaceDefaults` points
    at `SOLEUR_PLUGIN_PATH` (same shape as AC-3).
  - Cleanup in `afterEach` uses `removeWorkspaceDir` (the existing
    helper handles two-phase cleanup; the same workspaces array AC-3/AC-4
    already push into is reused).
- [ ] **AC-E (default lane unchanged):** Without any of
      `MU1_FIXTURE_REPO_URL`, `MU1_FIXTURE_INSTALLATION_ID`,
      `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`, or `MU1_INTEGRATION=1`,
      `./node_modules/.bin/vitest run test/mu1-integration.test.ts`
      outputs `4 passed, 2 skipped` (AC-1 and AC-2 both skipped) —
      matching the runbook's existing "Expected output" line.
- [ ] **AC-F (runbook updated):** `mu1-signup-workspace-verification.md`
      section "Apply — Run the Verification" updates step 1's expected
      output line, the step-2 expected output line (now `5 passed, 1
      skipped` or `6 passed, 0 skipped`), and the "AC-2 — Manual
      repo-clone verification (temporary)" section is demoted to a
      fallback note ("Use this only when dev Doppler does not have the
      MU1 fixture vars set"). The "Known Deferrals" entry for #2605 is
      removed.
- [ ] **AC-G (PR body contains `Closes #2605`).**

### Post-merge (operator)

- [ ] Run the updated MU1 runbook from the merged state; attach
      output to #2605 before closing. Expected: `6 passed, 0 skipped`
      under `MU1_INTEGRATION=1`.
- [ ] Confirm the `soleur-ai` App's installation on
      `jikig-ai/mu1-fixture` is still scoped to "Only select
      repositories" (= just `mu1-fixture`) a week after merge — a
      blanket "All repositories" install would silently grant the App
      access to every new private repo. If drift detected, re-scope via
      the App's install page.
- [ ] No production migration applies in this PR (`git diff
      --name-only main...HEAD -- apps/web-platform/supabase/migrations/`
      returns empty).

## Files to Edit

- `apps/web-platform/test/mu1-integration.test.ts` — replace the AC-2
  comment placeholder with a real `describe.skipIf(...)` block (see
  Phase 2 below for the exact shape). Reuse the existing
  `provisionedWorkspaces` array + `afterEach` cleanup; no new
  test-lifecycle hooks.
- `knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md` —
  update expected-output lines in "Apply — Run the Verification"
  sections 1 and 2; demote "AC-2 — Manual repo-clone verification
  (temporary)" from a required step to a fallback; update the "Acceptance
  Criteria Under Verification" table (AC-2 "Primary evidence" column
  changes from "Manual verification in staging…" to "`MU1 AC-2` describe
  block (requires `MU1_FIXTURE_REPO_URL` + `MU1_FIXTURE_INSTALLATION_ID`
  - `MU1_INTEGRATION=1`)"); remove the `#2605` row from "Known
  Deferrals".
- `knowledge-base/product/roadmap.md` — no change needed if the MU1 row
  already references the runbook; confirm during Phase 4 (the runbook
  path reference is the source of truth).

## Files to Create

- `jikig-ai/mu1-fixture` repo (external, via `gh repo create` — see
  Phase 1). Content:
  - `README.md`:

    ```markdown
    # mu1-fixture

    Minimal public repository used by the MU1 AC-2 clone verification
    test in `jikig-ai/soleur`. Cloned by `provisionWorkspaceWithRepo`
    through the `soleur-ai` GitHub App using an installation token.

    Changes here are rare. See `jikig-ai/soleur#2605` for context and
    `knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md`
    for the verification flow.
    ```

  - `knowledge-base/README.md`:

    ```markdown
    # knowledge-base/ (stub)

    Intentionally minimal. The MU1 test only asserts that the clone
    produces a workspace directory with the fixture's top-level files —
    the contents of this subdirectory are never read.
    ```

- No new files inside this repo beyond the two above changes.

## Fixture Strategy

- **Fixture repo owner:** `jikig-ai` org (not `soleur-ai` — that's the
  App name, see Research Reconciliation).
- **Visibility:** public. Private would require the App to hold
  additional scopes and defeats the "no sensitive content" goal.
- **Default branch:** `main`, matching the org default.
- **License:** none (single-purpose fixture, not a consumable). Skip
  `--add-license` on the `gh repo create` call.
- **Rate-limiting:** clone operations under installation-token auth use
  the App's rate limit (5000/hr per installation), which is orders of
  magnitude above what the test consumes.

## Test Strategy

- **Default lane unchanged.** AC-3 and AC-4 run unconditionally.
  `describe.skipIf(...)` guards AC-1 (via existing `MU1_INTEGRATION`
  gate) and AC-2 (new gate).
- **AC-2 gate:** `process.env.MU1_FIXTURE_REPO_URL &&
  process.env.MU1_FIXTURE_INSTALLATION_ID`. Do NOT couple AC-2 to
  `MU1_INTEGRATION=1` — the two gates are logically orthogonal (AC-1
  needs dev Supabase; AC-2 needs GitHub App creds). The runbook
  currently runs both under the same Doppler env wrap, which keeps the
  operator flow simple; the test-level gates stay independent so a
  future runbook could run just one.
- **Cleanup reuses `removeWorkspaceDir`.** The AC-2 clone produces a
  real `.git/` directory with git-owned files. The existing `afterEach`
  already handles this via the `provisionedWorkspaces.push(ws)` +
  `removeWorkspaceDir` pattern — no new helper.
- **No destructive-prod allowlist needed for AC-2.** AC-2 only clones
  from GitHub and writes under the test `WORKSPACES_ROOT` (a
  per-process tmpdir). No production data is touched. The AC-1
  synthetic-email allowlist stays in place for its own block.
- **Runner form (per `cq-in-worktrees-run-vitest-via-node-node`):**
  `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/mu1-integration.test.ts` from inside the worktree.
- **Env-var gating under Doppler (per `cq-for-local-verification-of-apps-doppler`):**
  `cd apps/web-platform && MU1_INTEGRATION=1 doppler run -p soleur -c dev --
  ./node_modules/.bin/vitest run test/mu1-integration.test.ts`.

## Implementation Phases

### Phase 1 — Create the fixture repo (**PAUSE FOR CONFIRMATION**)

This phase creates a persistent public GitHub repo. Before executing,
print the exact `gh` commands and ask the operator to confirm. Only
proceed on explicit `yes`.

1. `gh repo create jikig-ai/mu1-fixture --public --disable-issues
   --disable-wiki --description "MU1 AC-2 clone-verification fixture
   for jikig-ai/soleur. See #2605."` — no `--add-readme` flag (boolean,
   default OFF) so we can write the exact content. `--disable-issues`
   and `--disable-wiki` are the only disable flags `gh repo create`
   accepts (verified: 2026-04-19 source: `gh repo create --help`).
2. Clone, add `README.md` and `knowledge-base/README.md` with the
   content from "Files to Create", `git add`, `git commit -m "init:
   MU1 fixture content"`, `git push origin main`.
3. `gh repo edit jikig-ai/mu1-fixture --enable-projects=false
   --enable-discussions=false` — disable projects/discussions post-
   create (`gh repo create` doesn't accept these; verified:
   2026-04-19 source: `gh repo edit --help`). Issues and wiki were
   already disabled in step 1.
4. Verify AC-A passes: `gh repo view jikig-ai/mu1-fixture --json
   visibility,isArchived,description,hasIssuesEnabled,hasWikiEnabled,hasProjectsEnabled,hasDiscussionsEnabled`.
   Expect all four `has…Enabled` fields to be `false`.

**Rollback for Phase 1:** `gh repo delete jikig-ai/mu1-fixture --yes`
(repo is empty; loss is $0).

### Phase 2 — Install the `soleur-ai` App on the fixture (**PAUSE FOR CONFIRMATION**)

The existing `soleur-ai` GitHub App (installation id `122213433` on the
`jikig-ai` org) is installed at the org level. The issue requires a
per-repo install with "Only select repositories" scope. The App's
existing org install can be edited to add the new repo, OR a new
install can be created — both produce a valid `installation_id` for
the new repo.

The `gh` CLI does NOT expose App-install management (as of 2026-04;
verified via `gh api` requires JWT, and there is no `gh app install`
subcommand). Install management is browser-only. The runbook's
"Resolve installation id" step will therefore use the REST API to
enumerate App installations from a JWT, pulled via the existing
`prd`-provisioned App private key.

1. **Browser step (Playwright MCP is NOT available — manual handoff):**
   Navigate to `https://github.com/organizations/jikig-ai/settings/installations`,
   find `soleur-ai`, click Configure, add `mu1-fixture` under
   "Repository access → Only select repositories", save.
   - The browser step is the ONLY truly manual step in this plan. The
     GitHub UI enforces a human to click "Install" or "Save"; neither
     `gh` nor the REST API exposes an equivalent mutation for public
     Apps. This is the genuine hand-off per
     `hr-never-label-any-step-as-manual-without`.
2. Resolve the installation id via App JWT (auto):

   ```bash
   doppler run -p soleur -c prd -- node -e '
     const { createSign } = require("crypto");
     const now = Math.floor(Date.now() / 1000);
     const jwt = /* build RS256 JWT from GITHUB_APP_ID + GITHUB_APP_PRIVATE_KEY */;
     // ...
   '
   ```

   In practice the simplest path is to call
   `GET https://api.github.com/repos/jikig-ai/mu1-fixture/installation`
   with the JWT Bearer — one request, returns the installation id for
   this specific repo. Record the id.

3. Verify AC-B: `gh api /repos/jikig-ai/mu1-fixture/installation
   --jwt "$JWT"` shows `app_slug = soleur-ai`, `repository_selection =
   selected`.

**Rollback for Phase 2:** un-install the App from the repo via the
same GitHub settings page. Also benign.

### Phase 3 — Write Doppler `dev` secrets (**PAUSE FOR CONFIRMATION**)

Four secrets, one Doppler config. Before executing, show the exact
writes and ask for confirmation. The `GITHUB_APP_*` pair is the
largest surprise — it was not in the issue body but is required for
`generateInstallationToken` to function under dev creds.

Use the **stdin form** for `doppler secrets set` on any secret that
may contain newlines or shell-special characters. Per
`doppler secrets set --help`: "stdin (recommended)". This matters for
the PEM private key specifically — embedding a multi-line PEM inside
a double-quoted argument risks newline loss across shells and
`github-app.ts:97-101` relies on either real newlines OR literal `\n`
sequences being normalized; a mangled PEM fails JWT signing with a
cryptic `error:1E08010C:DECODER routines::unsupported`.

1. `doppler secrets get GITHUB_APP_ID -p soleur -c prd --plain |
   doppler secrets set GITHUB_APP_ID -p soleur -c dev` (copies
   prd → dev via stdin; same App, same id).
2. `doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd
   --plain | doppler secrets set GITHUB_APP_PRIVATE_KEY -p soleur
   -c dev` (stdin form preserves all newlines verbatim — critical).
3. `echo -n "https://github.com/jikig-ai/mu1-fixture.git" |
   doppler secrets set MU1_FIXTURE_REPO_URL -p soleur -c dev`.
4. `echo -n "<id-from-phase-2>" | doppler secrets set
   MU1_FIXTURE_INSTALLATION_ID -p soleur -c dev`.
5. Verify AC-C: four `doppler secrets get … --plain` commands, each
   returns the expected value. For the PEM, verify it starts with
   `-----BEGIN` and ends with `-----` and contains real newlines:

   ```bash
   doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c dev --plain | head -1
   # Expect: -----BEGIN RSA PRIVATE KEY-----
   doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c dev --plain | wc -l
   # Expect: >1 (multiple lines — flat output indicates newline loss)
   ```

6. Smoke-test JWT signing with the dev-copied key, to catch any
   encoding drift before running the test:

   ```bash
   doppler run -p soleur -c dev -- node -e '
     const { createSign } = require("crypto");
     const raw = process.env.GITHUB_APP_PRIVATE_KEY;
     const pem = raw.replace(/\\\\n/g, "\n");
     const s = createSign("RSA-SHA256");
     s.update("ping"); s.end();
     s.sign(pem);
     console.log("ok");
   '
   # Expect: ok (anything else = PEM encoding drift, stop and investigate).
   ```

**Security note:** copying `GITHUB_APP_PRIVATE_KEY` from `prd` to `dev`
does NOT widen the key's existing scope (it's the same App, same
installations) but does widen the **human** access surface — every
dev with Doppler `dev` read can now mint tokens for any installation
of the App. The App is already org-scoped to `jikig-ai` only, so the
blast radius is "any repo the App is installed on". Acceptable for the
current team size; re-evaluate if dev-Doppler access expands. Tracked
in the runbook's new "Security baseline" subsection.

### Phase 4 — Wire the AC-2 test block

1. Replace the placeholder comment (currently lines 178-184) with:

   ```typescript
   describe.skipIf(
     !process.env.MU1_FIXTURE_REPO_URL ||
       !process.env.MU1_FIXTURE_INSTALLATION_ID,
   )("MU1 AC-2: provisionWorkspaceWithRepo clones fixture", () => {
     test("clones the fixture repo and overlays plugin symlink", async () => {
       const { provisionWorkspaceWithRepo } = await import(
         "../server/workspace"
       );
       const userId = randomUUID();
       const repoUrl = process.env.MU1_FIXTURE_REPO_URL!;
       const rawId = process.env.MU1_FIXTURE_INSTALLATION_ID ?? "";
       const installationId = Number(rawId);
       // Guard BEFORE calling generateInstallationToken — a malformed
       // env var would otherwise fail deep in the GitHub API with a
       // cryptic "Bad credentials" (the token endpoint accepts any
       // stringifiable numeric path segment and only rejects at auth
       // time). This assertion names the real problem.
       expect(
         Number.isFinite(installationId) &&
           installationId > 0 &&
           Number.isInteger(installationId),
       ).toBe(true);

       const ws = await provisionWorkspaceWithRepo(
         userId,
         repoUrl,
         installationId,
       );
       provisionedWorkspaces.push(ws);

       // Fixture top-level files land in the workspace.
       expect(existsSync(join(ws, "README.md"))).toBe(true);
       expect(existsSync(join(ws, ".git"))).toBe(true);

       // Plugin symlink is overlaid post-clone (AC-3 contract).
       expect(readlinkSync(join(ws, "plugins", "soleur"))).toBe(PLUGIN_ROOT);
     }, 60_000);
   });
   ```

2. Update the runbook's "Apply" section: step 1 expected output
   remains `4 passed, 2 skipped` (default lane — neither gate flips),
   step 2 becomes `6 passed, 0 skipped` when both `MU1_INTEGRATION=1`
   AND the fixture env vars are present (via the `doppler run -p
   soleur -c dev` wrap, which now includes the fixture vars).
3. Update the runbook "AC-2 — Manual repo-clone verification" section
   header to "AC-2 — Manual repo-clone verification (fallback)" and
   prefix with: "Skip this section when running under `doppler run -p
   soleur -c dev --` — the `MU1 AC-2` describe block handles
   verification automatically. Use this only if the fixture Doppler
   vars are intentionally unset for a local experiment."
4. Remove the `#2605` entry from the runbook's "Known Deferrals"
   section.

### Phase 5 — Follow-up issue filing

No deferrals discovered during this plan. Phase-4 trigger-gated items
remain on the parent #1448 / roadmap.

If Phase 2's browser step is flagged as a repeat-friction item (it
recurs any time a new fixture repo is added to the App), file a
follow-up: "ops: evaluate auto-installing soleur-ai App via API".
Re-evaluation criterion: >2 fixture repos added in a quarter.
Milestone: `Post-MVP / Later`. The likely answer is "GitHub does not
expose this; the friction is immaterial at current cadence" — filing
the issue documents that finding.

## Open Code-Review Overlap

None expected. Check procedure before shipping:

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in \
  "apps/web-platform/test/mu1-integration.test.ts" \
  "knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md"; do
  jq -r --arg p "$path" '
    .[] | select(.body // "" | contains($p))
    | "#\(.number): \(.title) (matched \($p))"
  ' /tmp/open-review-issues.json
done
```

Expected: zero matches. If any surface, fold-in / acknowledge / defer
per `§1.7.5` before merging.

## Domain Review

**Domains relevant:** Operations (COO)

Infrastructure-shaped verification change; no user-facing surface, no
content, no billing. Running in pipeline mode — domain-leader sweep
skipped per the one-shot flow. Manual review notes:

### Operations (COO) — carry-forward

**Status:** advisory (pipeline skip)
**Assessment:** Matches the pattern of #2597 (parent MU1 PR) exactly —
creates a verification artifact, not a feature. The only ops-visible
change is Doppler `dev` gains four new secrets, three of which are
trivially scoped (fixture URL, installation id) and one of which
(`GITHUB_APP_PRIVATE_KEY`) widens human access slightly. The rationale
(same App, no new scope) is captured in Phase 3's "Security note".

## Research Insights

- **GitHub App `soleur-ai` installation on `jikig-ai`:** id
  `122213433`, confirmed via `gh api /orgs/jikig-ai/installations`.
- **Existing callsites of `provisionWorkspaceWithRepo`:**
  `apps/web-platform/app/api/repo/setup/route.ts:97` (production
  entry). Test calls the same function directly — no wrapper.
- **Credential helper pattern:** `server/workspace.ts:118-162` writes
  a short-lived `/tmp/git-cred-<uuid>` file, passes it via `git -c
  credential.helper=!<path> clone`, then unlinks. No persistent token
  on disk.
- **Default-lane test count today:** `4 passed, 2 skipped` (AC-1 +
  AC-2 both skipped). Runbook line 68 cites this; Phase 4 keeps it
  unchanged in the default lane.
- **Per `cq-destructive-prod-tests-allowlist`:** AC-2 does not touch
  prod data, so no allowlist is required. The existing AC-1 allowlist
  stays intact.
- **Per `cq-mutation-assertions-pin-exact-post-state`:** AC-2 assertions
  use `.toBe(true)` for `existsSync` returns and `.toBe(PLUGIN_ROOT)`
  for `readlinkSync` — both pin exact post-state.
- **Per `cq-code-comments-symbol-anchors-not-line-numbers`:** the
  describe-block title `"MU1 AC-2: provisionWorkspaceWithRepo clones
  fixture"` is grep-stable; the runbook references it by title, never
  by line number.

### Institutional learnings applied

- `cq-in-worktrees-run-vitest-via-node-node` — runbook + test strategy
  prescribe `./node_modules/.bin/vitest run` from the app directory.
- `cq-for-local-verification-of-apps-doppler` — `doppler run -p
  soleur -c dev --` wrap on test invocations.
- `cq-destructive-prod-tests-allowlist` — not needed for AC-2 (no
  prod data); AC-1 allowlist stays.
- `cq-agents-md-why-single-line` — no AGENTS.md edit in this PR; any
  learning from this work will be filed as a separate compound entry
  pointing to the PR #.
- `hr-exhaust-all-automated-options-before` — Phase 2 browser step is
  the one irreducibly-manual step; rationale documented inline.
- `hr-all-infrastructure-provisioning-servers` — the fixture repo is
  a GitHub-owned artifact, not infra (no DNS, servers, firewalls).
  Terraform is not the right tool here; `gh` CLI is. This is the
  narrow carve-out Rule `hr-all-infrastructure-provisioning-servers`
  allows for "vendor APIs for… account-level tasks Terraform can't
  cover".
- `wg-when-a-feature-creates-external` — each new external resource
  (repo, App install, Doppler secret) has an explicit AC verifying it
  produces correct output before the test block is wired.

### Sharp-edge check — CLI verification (per `cq-docs-cli-verification`)

All CLI invocations prescribed in this plan are verified:

- `gh repo create`, `gh repo edit`, `gh repo view`, `gh api /repos/…`,
  `gh api /orgs/…` — all on `gh` manual `gh help <cmd>` (stable since
  2.0).
- `doppler secrets get --plain`, `doppler secrets set`,
  `doppler run -p <project> -c <config> --` — all on `doppler help
  secrets` and `doppler help run` (verified: 2026-04-19 source:
  `doppler --help`).
- `./node_modules/.bin/vitest run <path>` — existing runbook
  convention, unchanged.

## Non-Goals / Out of Scope

- **Fixture content diversity.** The repo contains a README and a
  one-file `knowledge-base/` stub. No sample agents, no
  `.github/workflows/`, no `package.json`. The AC-2 test only asserts
  top-level files exist — fixture content expansion is a separate
  concern if/when we need to test KB scaffolding post-clone.
- **CI wiring of the MU1 integration test.** The test remains
  opt-in under `MU1_INTEGRATION=1`. Wiring it into a dedicated
  `mu1-check` workflow is tracked separately (not yet filed —
  re-evaluate after 2-3 runbook passes show the manual trigger is
  friction).
- **Automating the GitHub App install.** The GitHub API does not
  expose a programmatic "install App on repo X" mutation for public
  Apps. See Phase 5 for the follow-up-if-needed pattern.
- **Migrating AC-1 off `MU1_INTEGRATION=1`.** That gate already works;
  AC-2's gate is additive.
- **Container-per-workspace UID isolation.** Out of MU1 entirely;
  already on the Phase-4 trigger list.

## Risks

- **R1 — Fixture repo deleted or made private.** The test would fail
  with a clone error. **Mitigation:** AC-A verification is re-run by
  the runbook every verification cycle (not a cold fail — the
  monitoring cadence is already in place). Repo is in the org, under
  founder-admin control.
- **R2 — App install scope drift to "All repositories".** If a later
  admin clicks "Install on all repositories" for `soleur-ai`, the App
  silently gains access to new private repos — acceptable operationally
  but reverses the minimization posture of this PR. **Mitigation:**
  Post-merge AC checks "Only select repositories" a week later; the
  runbook's new "Security baseline" subsection records the expected
  scope.
- **R3 — `GITHUB_APP_PRIVATE_KEY` copied to `dev` widens human
  access.** Any dev-Doppler reader can mint installation tokens.
  **Mitigation:** Doppler `dev` read is limited to the founder team
  today; the App is org-scoped to `jikig-ai`. Documented in Phase 3's
  "Security note". Re-evaluate if dev-Doppler access expands.
- **R4 — Installation token expiry mid-test.** `generateInstallationToken`
  caches tokens with a 5-minute safety margin; the clone completes in
  seconds. Not a realistic failure mode.
- **R5 — Runbook expected-output drift.** Adding one more test
  changes the `4 passed / 2 skipped` line to conditionally
  `6 passed / 0 skipped`. If a future AC lands without updating the
  runbook, the operator will see mismatched counts. **Mitigation:** the
  runbook's new test-count line uses both values with a comment
  explaining the gate ("default: 4 passed / 2 skipped; with fixture env
  - `MU1_INTEGRATION=1`: 6 passed / 0 skipped"). Operator sees both.
- **R6 — Git-clone helper leaks token on crash.** The credential
  helper at `/tmp/git-cred-<uuid>` is unlinked in `finally`. If the
  process is SIGKILL'd between write and clone, the token survives on
  disk until the next `/tmp` sweep. **Mitigation:** already mitigated
  by the short token TTL (~1 hour, vs. indefinite checkout of a
  user-PAT) — same model as the existing `provisionWorkspaceWithRepo`
  production path.
- **R7 — tmpdir not writable in containerized test runner.** The
  test uses `mkdtempSync(tmpdir(), …)` for both `PLUGIN_ROOT` and
  `WORKSPACES_ROOT`. If a future CI wiring runs vitest in a container
  with a read-only `/tmp`, the AC-3/AC-4 setup also fails — not just
  AC-2. Not a regression caused by this PR, but the AC-2 block's
  `.git/` write amplifies the write-footprint. **Mitigation:** the
  AC-3/AC-4 tests already exercise the same path, so a read-only
  `/tmp` would have been caught on the default lane. Documented for
  future CI wiring.
- **R8 — Wrong installation id used (org-level vs. repo-scoped).**
  The `soleur-ai` App has an org-level install on `jikig-ai`
  (id `122213433`) AND will have a repo-scoped install on
  `mu1-fixture` after Phase 2. These are DIFFERENT installation ids
  for the same App. If the org-level id is accidentally recorded in
  `MU1_FIXTURE_INSTALLATION_ID`, the clone may actually succeed (the
  org-level install can access the repo), but token scope will be
  broader than needed — violating the minimization goal of this PR.
  **Mitigation:** Phase 2 step 3 asserts `repository_selection =
  "selected"` on the fetched installation; the id returned from
  `GET /repos/jikig-ai/mu1-fixture/installation` is authoritative for
  "the install that owns this repo narrowly".
- **R9 — Doppler stdin-set newline stripping.** On some shells,
  `printf "x" | doppler secrets set FOO -p soleur -c dev` strips a
  trailing newline that Doppler then re-adds on `--plain` read. For
  the PEM this is fine (PEM must end with a newline anyway). For
  `MU1_FIXTURE_INSTALLATION_ID`, a trailing newline inside
  `Number("<n>\n")` evaluates cleanly to `<n>` (JS `Number()`
  trims whitespace). For `MU1_FIXTURE_REPO_URL`, a trailing newline
  would make `git clone` fail with "invalid URL". **Mitigation:**
  Phase 3 uses `echo -n` (not `echo`) for the URL and the id, which
  suppresses the trailing newline. Verified by the AC-C `--plain`
  reads.

## Sign-off Checklist

- [ ] Phase 1 confirmation received, repo created, AC-A passes.
- [ ] Phase 2 confirmation received, App installed on repo, AC-B passes.
- [ ] Phase 3 confirmation received, four Doppler secrets written, AC-C
      passes.
- [ ] Phase 4 test block wired, default-lane unchanged, AC-D and AC-E
      pass locally under both invocation forms (with and without the
      fixture env vars).
- [ ] Runbook updated per AC-F.
- [ ] PR body contains `Closes #2605`.
- [ ] Post-merge runbook pass attached to #2605 before closing.
