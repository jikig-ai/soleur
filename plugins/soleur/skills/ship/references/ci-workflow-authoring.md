# CI Workflow Authoring

Rules governing GitHub Actions workflow edits and shell snippets inside CI. Load this reference whenever editing `.github/workflows/*.yml`, `.github/actions/**`, or any shell step that runs in CI.

These rules were migrated out of AGENTS.md because they only fire when CI-adjacent files are edited — keeping them in AGENTS.md wasted per-turn tokens on sessions that never touch CI. Retired IDs are preserved as breadcrumbs; the authoritative constraint lives here.

## Hard

- In GitHub Actions `run:` blocks, never use heredocs or multi-line shell strings that drop below the YAML literal block's base indentation. Column-0 heredoc terminators and multi-line `--body` / `--comment` args break YAML parsing (zero jobs run). Use `{ echo "..."; } > file` for multi-line content and `$'\n'` for CLI args. (ex-`hr-in-github-actions-run-blocks-never-use`; #974 indented heredoc → `<pre>`; #1358 broke YAML parser entirely)
- GitHub Actions workflow notifications must use email via `.github/actions/notify-ops-email`, not chat webhooks. One carve-out: the release announcement posts to Slack via the inline "Post to Slack (release)" step in `reusable-release.yml` (#5079) — internal team channel, redundant with the email-to-ops signal. Discord is for community content only. For custom bodies, construct HTML in a preceding step and pass as the `body` input. (ex-`hr-github-actions-workflow-notifications`)

## Code Quality

- CI steps polling JSON endpoints under `bash -e` must precede every `jq -r` call with a `jq -e . >/dev/null 2>&1` guard that `continue`s on non-JSON bodies. Without it, plaintext 404s, HTML 503s, or connection errors kill the step before the retry loop reacts. Do NOT use `jq empty` (passes `null` through) or drop `-e` (silences real failures). (ex-`cq-ci-steps-polling-json-endpoints-under`; #2214; `knowledge-base/project/learnings/bug-fixes/2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md`)
- When a PR changes `--model <name>` in `.github/workflows/*.yml`, verify every `anthropics/claude-code-action` pin in the modified files is within ~3 weeks of release tip. SDK lags the API by days — old pins send deprecated `thinking.type.enabled` and fail 4xx. Audit pin age via `gh api repos/anthropics/claude-code-action/releases`. When bumping the pin, check release notes for default-model flips. (ex-`cq-claude-code-action-pin-freshness`; #2540 v1.0.75 pin + opus-4-6 → 4-7 bump failed 4 workflow runs)
- When extending a GitHub Actions workflow by duplicating an existing job's pattern, scan the source for known-buggy idioms before duplicating. Common: piped `| while` loops swallow counter updates (subshell scope), missing `set -uo pipefail`, unguarded `gh api` calls. Fix in BOTH the new and source jobs per `wg-when-fixing-a-workflow-gates-detection`. (ex-`cq-workflow-pattern-duplication-bug-propagation`; PR #2631 propagated the `check-alerts` subshell-counter bug into `close-orphans`)
- Doppler service tokens are per-config — use config-specific GitHub secret names (`DOPPLER_TOKEN_PRD`, `DOPPLER_TOKEN_CI`), never bare `DOPPLER_TOKEN`. The `-c` flag is silently ignored with service tokens. (ex-`cq-doppler-service-tokens-are-per-config`; `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`)
- When a CI step disables `set -e` to capture an exit code (typical pattern: `set -uo pipefail` + `rc=$?` from `terraform plan`, `gh api`, etc.), the `-e` re-enable window MUST close before any `[[ "$VAR" -gt|-lt|-eq|-ne N ]]` arithmetic test where `$VAR` is assigned from a piped command. Bash arithmetic coerces empty-string → 0 silently, so a failed `jq` or upstream pipe produces an empty `$VAR` and bypasses the guard (e.g., a destroy-guard that lets destructive plans through). Either re-enable `set -e` immediately after the rc-capture window closes, OR add an explicit `[[ ! "$VAR" =~ ^[0-9]+$ ]]` validation before the arithmetic test. Belt-and-braces (both) is preferred for destroy/blast-radius guards. (PR #3903 review; `knowledge-base/project/learnings/2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md`)
- When a PR adds a `permissions:` scope (e.g. `id-token: write` for cosign/OIDC) to a **reusable** workflow (`on: workflow_call`), EVERY caller MUST grant that scope — a reusable workflow can only USE permissions its caller passes down. `actionlint`/CI does NOT catch this; it surfaces only **post-merge at dispatch as a `startup_failure`** ("This run likely failed because of a workflow file issue"), silently breaking the release/deploy pipeline for future merges. After merging such a change, at `/ship` Phase 7 (post-merge verify) confirm each caller — `git grep -l 'uses:.*<reusable-basename>\.yml' .github/workflows/` — grants the scope; scope it to the calling **job** (least privilege), not workflow-wide (a job-level `permissions:` block REPLACES inherited perms, so re-declare the ones the reusable workflow still needs). This class is only reliably caught by **live validation** (`gh workflow run` + watch for `startup_failure`), not by tests — drive the real dispatch. (PR #5977 added `id-token: write` to `reusable-release.yml` for cosign signing; `web-platform-release.yml` granted only contents+packages → `startup_failure` broke releases; fixed #5981. `knowledge-base/project/learnings/2026-07-04-reusable-workflow-permission-needs-caller-grant.md`)

## Slack mrkdwn formatting

Slack messages do **not** render GitHub-flavored Markdown. Slack uses "mrkdwn", a different syntax. Posting raw GFM (PR-body changelogs, `CHANGELOG.md` text) to a Slack webhook renders the markers as **literal characters** (`**bold**`, `## heading`, `[text](url)` all show verbatim). Any CI step that composes a message for a Slack webhook MUST convert GFM → mrkdwn first.

**Use the shared converter, never re-derive a sed pipeline.** `scripts/md-to-mrkdwn.mjs` (self-contained, zero-dependency Node ESM; runs under stock ubuntu-latest `node`, no `setup-node`) is the canonical transform. Invoke it from the `run:` block: `node scripts/md-to-mrkdwn.mjs --max 3000 < "$NOTES_FILE"`. It exports `toSlackMrkdwn(md)` + `truncateMrkdwn(text, max)` for reuse. Precedent wiring: the "Post to Slack (release)" step in `reusable-release.yml`.

### GFM → mrkdwn mapping (the converter's contract)

| GFM input | Slack mrkdwn output | Notes |
|---|---|---|
| `**bold**` / `__bold__` | `*bold*` | single asterisk |
| `*italic*` / `_italic_` | `_italic_` | single underscore |
| `~~strike~~` | `~strike~` | single tilde |
| `` `code` `` / ` ```fence``` ` | same | escape `&<>` inside, NO GFM convert |
| `[text](url)` / `[text][ref]` | `<url\|text>` | delimiters raw; url+label sub-escaped (incl. `\|`) |
| `<https://x>` autolink / bare url | `https://x` | Slack auto-links bare URLs; do NOT wrap |
| `![alt](url)` image | `<url\|alt>` | no inline image → degrade to link |
| `# H1` … `###### H6`, Setext | `*H1*` | no headings in mrkdwn |
| `- `/`* `/`+ ` bullet | `• item` | canonical Slack bullet |
| `1.` ordered | `1.` | Slack renders ordered lists |
| `- [ ]` / `- [x]` task | `• ☐ ` / `• ☑ ` | no native checkbox |
| `> quote` | `> quote` | same as GFM |
| GFM pipe table | wrap in ` ``` ` | no table support; monospace degrade |
| `---` / `***` thematic break | blank line | no HR in mrkdwn |
| raw `<!channel>` / `<@U…>` in prose | `&lt;!channel&gt;` etc. | escaped → inert (injection safety) |

### Escape-vs-emit ordering invariant (security-critical)

The transform is **one context-aware tokenizing pass**, not two string passes. Slack has **no** API-level mention suppression (unlike Discord's `allowed_mentions`), so escaping `&`, `<`, `>` is the only defense against a changelog author's `<!channel>` mass-ping or `<url|label>` disguised link:

- **Text nodes** (prose, including any author-typed mention): escape `&<>`. This keeps injection inert.
- **Converter-minted link syntax** (`<`, `>`, `|` of a `<url|label>` from a genuine `[text](url)`): the delimiters are raw, but the url + label segments are sub-escaped, and `|` is stripped (label) / percent-encoded (url) — a raw `|` would re-open the grammar, and Slack's 3-entity escape does NOT cover `|`. Only `http(s)`/`mailto` URLs are minted (never `javascript:`).
- **Code spans / fences**: **escape-only** (`&<>`), no GFM convert — but **not verbatim**: Slack renders `<!channel>`/`<@U…>` inside backticks in a `text` payload, so a verbatim copy would be a live mass-ping hole.
- **Keystone fail-closed invariant**: the converter output contains **zero** `<!`, `<@`, `<#`, `<subteam^` sequences (the only raw `<` begins a URL scheme inside a minted link). This single assertion backstops every smuggling path and is enforced in both `scripts/md-to-mrkdwn.test.mjs` and the `plugins/soleur/test/reusable-release-idempotency.test.sh` T7 contract test.
- **Truncate AFTER conversion** at a token boundary (no dangling `<url|`, close any open fence) — `truncateMrkdwn` / the `--max` flag does this. Truncating raw GFM first would sever tokens the converter then mangles.

When wiring the converter, guard the call so a non-zero exit cannot fail the release: `if ! BODY=$(node scripts/md-to-mrkdwn.mjs --max 3000 < "$F"); then …sed-escape fallback…; fi`. The `if !` form is load-bearing — a bare `BODY=$(node …)` assignment masks the exit code under `bash -e`. The fallback is for **availability**, not safety (safety lives in the converter's escaping + the keystone invariant).

## When to Load This File

- Editing any `.github/workflows/*.yml`
- Editing any `.github/actions/**`
- Adding or modifying CI shell steps in `bash -e` / `set -euo pipefail` mode
- Changing `anthropics/claude-code-action` pins or model strings
- Adding new Doppler secrets consumed by CI
- Composing any message for a Slack webhook in CI (use `scripts/md-to-mrkdwn.mjs`, never raw GFM)
