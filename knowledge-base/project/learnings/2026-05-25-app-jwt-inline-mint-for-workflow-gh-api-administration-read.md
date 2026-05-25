---
date: 2026-05-25
tags: [workflow, github-app, security, infrastructure, terraform]
source_pr: 4384
related:
  - 2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md
---

# App-JWT inline-mint pattern for workflow `gh api` calls requiring `Administration:Read`

## Problem

PR #4384 migrated `infra/github/` from PAT auth (`GH_RULESET_PAT` in Doppler `prd_terraform`) to App-installation auth (`soleur-ai` App id `3261325`, installation `122213433`) per `hr-github-app-auth-not-pat`. The migration was mechanically straightforward for the `provider "github"` block — the sibling `apps/web-platform/infra/main.tf:72-79` is a 1:1 reference pattern. The hard part was the post-apply verify step at `.github/workflows/apply-github-infra.yml`: it called `gh api .../rulesets/14145388` with `GH_TOKEN: ${{ env.GITHUB_TOKEN_PAT }}` (the deleted PAT). The default `secrets.GITHUB_TOKEN` does NOT carry `Administration:Read` scope — the App installation does.

The naive options each had a sharp edge:

- **Use `actions/create-github-app-token`**: a new external action; SHA-pin governance friction.
- **Skip the verify and use `terraform output`**: regression — the probe's purpose is detecting drift between Terraform's bookkeeping and live GitHub state.
- **Inline JWT mint**: the `.github/workflows/scheduled-ruleset-bypass-audit.yml:104-269` precedent is ~165 lines with full failure-mode taxonomy. Over-engineered for a single post-apply probe.

## Solution

A ~50-line inline JWT-mint + installation-token exchange chain in the verify step, with four defensive properties carried forward from the drift-guard precedent and the multi-agent review:

```yaml
- name: Fetch GitHub App credentials from Doppler
  env:
    DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
    DOPPLER_PROJECT: soleur
    DOPPLER_CONFIG: prd_terraform
  run: |
    set -euo pipefail
    APP_ID=$(doppler secrets get GITHUB_APP_ID --plain)
    PEM=$(doppler secrets get GITHUB_APP_PRIVATE_KEY --plain)
    printf '::add-mask::%s\n' "$APP_ID"
    # P1: per-line ::add-mask:: for every PEM line BEFORE the heredoc write.
    # $GITHUB_ENV does NOT auto-mask multi-line values; downstream TF_LOG=DEBUG
    # or set -x would otherwise leak the PEM.
    while IFS= read -r pem_line; do
      [[ -n "$pem_line" ]] && printf '::add-mask::%s\n' "$pem_line"
    done <<< "$PEM"
    printf 'TF_VAR_github_app_id=%s\n' "$APP_ID" >> "$GITHUB_ENV"
    {
      echo 'TF_VAR_github_app_private_key<<__SOLEUR_PEM_EOF__'
      printf '%s\n' "$PEM"
      echo '__SOLEUR_PEM_EOF__'
    } >> "$GITHUB_ENV"
    umask 077
    APP_PEM_FILE=$(mktemp -p "$RUNNER_TEMP" soleur-ai-app-pem.XXXXXX)
    printf '%s\n' "$PEM" > "$APP_PEM_FILE"
    chmod 600 "$APP_PEM_FILE"
    # P2: openssl rsa -check pre-flight catches a corrupted PEM in Doppler
    # (literal \n instead of newlines, BOM, partial paste) HERE with a
    # routable error, instead of later at `openssl dgst -sign` with a
    # generic "unable to load Private Key".
    if ! openssl rsa -in "$APP_PEM_FILE" -check -noout 2>/dev/null; then
      echo "::error::GITHUB_APP_PRIVATE_KEY in Doppler is not a valid RSA PEM. Recover from password manager or App admin UI."
      exit 1
    fi
    printf 'APP_PEM_FILE=%s\n' "$APP_PEM_FILE" >> "$GITHUB_ENV"

- name: Post-apply verify (mint App-JWT, exchange for installation-token, call gh api)
  env:
    APP_ID: ${{ env.APP_ID }}
    APP_PEM_FILE: ${{ env.APP_PEM_FILE }}
    INSTALLATION_ID: "122213433"
  run: |
    set -euo pipefail
    # P3: trap-based cleanup so the PEM file is shredded on BOTH success and
    # any failure exit (openssl/jq/curl/gh failures, set -e trips). The
    # `|| true` keeps the trap idempotent.
    trap 'rm -f "${APP_PEM_FILE:-}" 2>/dev/null || true' EXIT

    b64url() { base64 -w 0 | tr '+/' '-_' | tr -d '=\n'; }

    now=$(date +%s)
    header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)
    payload=$(jq -nc \
      --argjson iss "$APP_ID" \
      --argjson iat "$((now - 60))" \
      --argjson exp "$((now + 540))" \
      '{iss: $iss, iat: $iat, exp: $exp}' | b64url)
    unsigned="${header}.${payload}"
    signature=$(printf '%s' "$unsigned" | \
      openssl dgst -sha256 -sign "$APP_PEM_FILE" -binary | b64url)
    JWT="${unsigned}.${signature}"
    echo "::add-mask::$JWT"

    INSTALL_TOKEN=$(curl -sS -X POST \
      -H "Authorization: Bearer $JWT" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens" \
      | jq -r '.token // empty')
    echo "::add-mask::$INSTALL_TOKEN"

    GH_TOKEN="$INSTALL_TOKEN" gh api "repos/${GITHUB_REPOSITORY}/rulesets/14145388" \
      | jq '.rules[0].parameters.required_status_checks | length'
```

## Key Insight

When migrating a workflow from PAT auth to App-installation auth, the `provider "github"` block migration is the easy half. The hard half is every `gh api` / `curl api.github.com` call elsewhere in the workflow that relied on the PAT's `Administration:Read` / `Secrets:Read` / `Issues:Write` scope. Each one needs an installation-token mint. Five defensive properties make the inline mint cheap to maintain:

1. **Per-line `::add-mask::` for multi-line secrets BEFORE the heredoc write to `$GITHUB_ENV`.** Heredoc-form env vars are NOT auto-masked.
2. **`openssl rsa -in <pem> -check -noout` PEM-shape pre-flight.** A corrupted PEM in Doppler is a recoverable operator error; the pre-flight makes the error message actionable.
3. **`trap 'rm -f "$APP_PEM_FILE"' EXIT` for one-shot PEM file cleanup.** Covers both success and any failure path (`set -e` trips on openssl/jq/curl/gh errors).
4. **JWT lifetime constants from the drift-guard precedent**: backdate `iat` by 60s for clock-skew tolerance; cap `exp` at 540s (under GitHub's 600s max).
5. **`b64url()` helper following RFC 7515**: `base64 -w 0 | tr '+/' '-_' | tr -d '=\n'`.

If a third place in the codebase needs this (i.e., a third workflow with a Terraform-managed root that needs `gh api` with elevated scope), extract a composite action `.github/actions/mint-app-installation-token/`. Until then, inline is cheaper than the indirection.

## Session Errors

- **PreToolUse `security_reminder_hook.py` blocked first-attempt Edits on 4 workflow YAML files** — Recovery: retry the Edit verbatim; the hook is advisory and lets the second attempt through. **Prevention:** When editing `.github/workflows/*.yml` or `.github/actions/*.yml`, expect the security advisory hook to fire on the first Edit attempt per file. Retry is the canonical path; do not rewrite the edit to "work around" the warning.
- **Bash CWD drift** — after `cd infra/github && terraform validate`, the next Bash call ran `git add ...` with CWD = `infra/github/`, causing `pathspec ... did not match` on worktree-root paths. Recovery: explicit `cd <worktree-abs-path> && git add ...` in a single Bash call. **Prevention:** When chaining a long-running command after a `cd` into a subdirectory, the next git/staging command MUST re-anchor with an explicit `cd <worktree-abs-path>` prefix. Bash CWD persistence behavior varies by harness.
- **Plan/comment referenced #3913/#3914/#4144/#4150 as PRs but they are GitHub Issues** — actual merged PRs are #4161/#4165. Recovery: post-commit clarification in PR body; no source edit needed since the precedent (App-auth on `apps/web-platform/infra/main.tf`) is verified via code grep, not the issue number. **Prevention:** Before commit-titling "`#NNNN` precedent", run `gh issue view NNNN --json state,closedByPullRequestsReferences --jq '.closedByPullRequestsReferences[].number'` to surface the PR. The merged-PR number is what should be cited.
- **Plan-quoted line numbers drifted** — `surface_hit=false` short-circuit reference cited `lines 85-88`; an inline comment-cleanup edit shifted the actual range to `lines 82-85`. Recovery: post-fix `grep -rn 'lines 85-88'` sweep. **Prevention:** When the plan or a comment quotes a line range from a file the same PR also edits, the line range is a precondition to re-verify at every commit. The cheapest gate is a post-edit grep on the literal `lines N-M` form across the worktree.
- **`code-quality-analyst` agent hallucinated a 2500-line `cron-bug-fixer.ts` deletion** not present in this PR's diff. Recovery: verified with `git diff --name-only origin/main...HEAD`. **Prevention:** When an agent's finding references a file that the spawn prompt did NOT enumerate, verify the file is actually in the diff before accepting the finding. Agents occasionally describe scope from a sibling worktree or recent main commits.
- **Initial implementation missed 4 defensive properties caught at review** (PEM line-mask, EXIT trap, PEM-shape pre-flight, README/ADR present-tense sweep). Recovery: all fixed inline at review per cost-of-filing gate (≤30 lines / ≤2 files). **Prevention:** When introducing a NEW inline JWT mint or NEW secret-handling step, the canonical defensive properties to budget for at first-write are (1) per-line `::add-mask::` for multi-line secrets, (2) trap-based file cleanup, (3) shape/format pre-flight on operator-supplied secrets, (4) sweep the rest of the artifact set for orphan prose about the predecessor. Tracked here so a future inline-mint can budget the defenses at first-write instead of at review.

## Workflow-feedback proposals

Two proposals derived from the session errors above (Phase 1.5 routing):

### Proposal 1: Add to `soleur:work` skill — "When editing `.github/workflows/*.yml`, expect retry-on-first-attempt"

- **Rule violated:** None (advisory hook behavior)
- **Evidence:** 4 first-attempt Edit failures on workflow YAML
- **Existing enforcement:** None (the hook itself IS the enforcement, but the model retries inefficiently)
- **Proposed enforcement:** Skill instruction in `soleur:work` Phase 2 / `soleur:one-shot` Phase 4 — single bullet noting that `.github/workflows/*.yml` Edits should be retried verbatim on first-attempt failure with the security advisory hook.

### Proposal 2: Add to `soleur:work` skill — "When introducing new inline JWT mint, budget the 4 canonical defenses at first-write"

- **Rule violated:** None (gap between first-write and review-finding)
- **Evidence:** Multi-agent review caught 4 defensive gaps in inline JWT mint (PEM mask, trap, PEM-shape pre-flight, prose sweep)
- **Existing enforcement:** Multi-agent review (works but expensive)
- **Proposed enforcement:** Skill instruction in `soleur:work` referencing this learning's "Key Insight" §1-5 as the budget-at-first-write checklist when introducing a NEW inline JWT mint.
