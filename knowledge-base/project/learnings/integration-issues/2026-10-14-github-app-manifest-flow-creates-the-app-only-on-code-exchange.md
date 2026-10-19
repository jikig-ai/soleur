---
title: GitHub App manifest flow creates the App only when the one-time code is exchanged
date: 2026-10-14
category: integration-issues
tags: [github-app, manifest-flow, operator-bootstrap, staged-scripts, archive-kb, playwright]
related_issues: ["#10058", "#9995", "PR #10273"]
---

# Learning: the manifest flow's "Create GitHub App" click does not create the App

## Problem

The staged `bootstrap.sh` for #10058 told the founder to click **Create GitHub App** and then
**Generate a private key**. Run live it failed three ways, in order:

1. GitHub refused the manifest: `"redirect_url" wasn't supplied` (the plan had omitted the field).
2. After adding `redirect_url`, clicking Create redirected to
   `/organizations/jikig-ai/settings/apps/soleur-ci-fixture?code=…` which returned **404**, and the
   App was **absent from the org's app list** (checked twice).
3. `verify` then failed with `No such file or directory` because it located the repo root with a
   fixed `../../../..` that was one level too shallow once `archive-kb` moved the spec directory.

## Solution

- `redirect_url` is **required** in an App manifest. A private CI fixture points it at its own GitHub
  settings page rather than the production web-platform handler the sibling manifests use, because the
  redirect carries a credential-bearing code.
- The App exists only after `POST https://api.github.com/app-manifests/<code>/conversions` (no auth
  needed; single-use, ~1h). Measured 2026-10-14: HTTP 201 with `id`, `slug`, `pem`, `client_secret`,
  `webhook_secret`; the App page and the list entry appeared only after that call. The human path
  "click Create, then Generate a private key" is therefore a dead end. Keep the whole response off
  stdout, write only the `pem` to a 0600 file on tmpfs, and shred the rest.
- Resolve a staged script's repo root with `git -C "$SCRIPT_DIR" rev-parse --show-toplevel` (run
  without inherited `GIT_*`), and refuse a root whose credentialed probe is not a tracked,
  non-symlink file whose blob hash equals `HEAD:<path>` (`git update-index --assume-unchanged` hides
  an edit from `git diff HEAD`, a hash compare does not).
- A browser-automation agent cannot open the launcher over `file://` (Playwright MCP blocks it):
  serve a COPY of the page from a `mktemp -d` over `127.0.0.1`, never the script directory, which
  holds `.env`.

## Key Insight

A vendor flow's documented happy path is a hypothesis until the vendor's own state confirms each step.
Here one observation (404 plus absent from the list) refuted a review seat's confident statement that
the click creates the App; measure before accepting a verdict that contradicts an observation.

Cost note: `apps/[^/]+/infra/` matches `SENSITIVE_PATH_RE`, so a 5-line CI-fixture manifest edit
resolved the `single-user incident` tier by clamp and a full 18-seat review (user-impact found no
user-facing artifact). Declare `threshold: none, reason: <…>` at plan time for private CI fixtures.

## Session Errors

1. **`bypassPermissions` mode made the staged-apply approval hook refuse `create-app`** — Recovery:
   switched to normal permission mode. **Prevention:** stage runs need the normal mode; the skill
   already says so, so check the mode before the first `--apply`.
2. **The apply hook rejected a piped apply command** — Recovery: re-issued as one simple command.
   **Prevention:** run `--apply` as a single `bash <script> --stage <s> --apply --plan-digest <d>`;
   never add a pipe, redirect or substitution.
3. **Manifest lacked the required `redirect_url`** — Recovery: added it to JSON and launcher.
   **Prevention:** `apps/web-platform/test/github-ci-fixture-app-manifest.test.ts` now pins it.
4. **Assumed the Create click creates the App** — Recovery: exchanged the code. **Prevention:** the
   script's printed steps now state the measured flow; the manifest flow is documented here.
5. **Project Playwright MCP could not find Chrome; `file://` blocked** — Recovery: the plugin-scoped
   server plus a localhost copy of the page. **Prevention:** printed hint in `apply_create_app`.
6. **`sleep 45` and `pkill -f` were hook-blocked** — Recovery: `ss` + `kill <pid>`. **Prevention:**
   already hook-enforced (`pkill-self-match-guard.sh`).
7. **`verify` used a fixed `../` repo root that broke after archival** — Recovery: `git rev-parse`.
   **Prevention:** `operator-bootstrap/SKILL.md` §3 rule and the generated-script guard.
8. **Playwright wrote screenshots into the repo root** — Recovery: deleted. **Prevention:** save
   screenshots with an absolute scratchpad path.
9. **Worktree base was a stale detached commit without the probe script** — Recovery: branched from
   `origin/main`. **Prevention:** `git fetch` and check the base before running a script that reads
   repo files.
10. **A review seat's claim contradicted a live measurement** — Recovery: rejected it with the
    measurement in the disposition. **Prevention:** re-measure contested, cheap, load-bearing claims.
11. **The clamp produced an 18-seat review for a 5-line diff** — Recovery: ran it as the tier
    requires and recorded the mismatch. **Prevention:** declare the tier at plan time (see above).
12. **A "Paused" line was flagged as handing delivery back** — Recovery: continued in-turn.
    **Prevention:** phrase a wait on an in-flight run as that, and keep working on independent steps.
13. **A long suite hit my 150 s cap and a background run lost its output handle** — Recovery:
    re-ran in the background with a longer bound. **Prevention:** use `run_in_background` and read
    the task output file.
