# CI Workflow Authoring

Rules governing GitHub Actions workflow edits and shell snippets inside CI. Load this reference whenever editing `.github/workflows/*.yml`, `.github/actions/**`, or any shell step that runs in CI.

These rules were migrated out of AGENTS.md because they only fire when CI-adjacent files are edited — keeping them in AGENTS.md wasted per-turn tokens on sessions that never touch CI. Retired IDs are preserved as breadcrumbs; the authoritative constraint lives here.

## Hard

- In GitHub Actions `run:` blocks, never use heredocs or multi-line shell strings that drop below the YAML literal block's base indentation. Column-0 heredoc terminators and multi-line `--body` / `--comment` args break YAML parsing (zero jobs run). Use `{ echo "..."; } > file` for multi-line content and `$'\n'` for CLI args. (ex-`hr-in-github-actions-run-blocks-never-use`; #974 indented heredoc → `<pre>`; #1358 broke YAML parser entirely)
- GitHub Actions workflow notifications must use email via `.github/actions/notify-ops-email`, not Discord webhooks. Discord is for community content only. For custom bodies, construct HTML in a preceding step and pass as the `body` input. (ex-`hr-github-actions-workflow-notifications`)

## Code Quality

- CI steps polling JSON endpoints under `bash -e` must precede every `jq -r` call with a `jq -e . >/dev/null 2>&1` guard that `continue`s on non-JSON bodies. Without it, plaintext 404s, HTML 503s, or connection errors kill the step before the retry loop reacts. Do NOT use `jq empty` (passes `null` through) or drop `-e` (silences real failures). (ex-`cq-ci-steps-polling-json-endpoints-under`; #2214; `knowledge-base/project/learnings/bug-fixes/2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md`)
- When a PR changes `--model <name>` in `.github/workflows/*.yml`, verify every `anthropics/claude-code-action` pin in the modified files is within ~3 weeks of release tip. SDK lags the API by days — old pins send deprecated `thinking.type.enabled` and fail 4xx. Audit pin age via `gh api repos/anthropics/claude-code-action/releases`. When bumping the pin, check release notes for default-model flips. (ex-`cq-claude-code-action-pin-freshness`; #2540 v1.0.75 pin + opus-4-6 → 4-7 bump failed 4 workflow runs)
- When extending a GitHub Actions workflow by duplicating an existing job's pattern, scan the source for known-buggy idioms before duplicating. Common: piped `| while` loops swallow counter updates (subshell scope), missing `set -uo pipefail`, unguarded `gh api` calls. Fix in BOTH the new and source jobs per the retroactive-gate-application workflow rule. (ex-`cq-workflow-pattern-duplication-bug-propagation`; PR #2631 propagated the `check-alerts` subshell-counter bug into `close-orphans`)
- Doppler service tokens are per-config — use config-specific GitHub secret names (`DOPPLER_TOKEN_PRD`, `DOPPLER_TOKEN_CI`), never bare `DOPPLER_TOKEN`. The `-c` flag is silently ignored with service tokens. (ex-`cq-doppler-service-tokens-are-per-config`; `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`)

## When to Load This File

- Editing any `.github/workflows/*.yml`
- Editing any `.github/actions/**`
- Adding or modifying CI shell steps in `bash -e` / `set -euo pipefail` mode
- Changing `anthropics/claude-code-action` pins or model strings
- Adding new Doppler secrets consumed by CI
