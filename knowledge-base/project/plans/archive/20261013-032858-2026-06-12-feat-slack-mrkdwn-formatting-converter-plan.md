---
title: "Emit valid Slack mrkdwn in release notifications via a shared markdown→mrkdwn converter"
type: feat
date: 2026-06-12
lane: cross-domain
brand_survival_threshold: none
feature: slack-mrkdwn-formatting
status: draft
deepened: 2026-06-12
---

# Emit valid Slack mrkdwn in release notifications via a shared markdown→mrkdwn converter

## Enhancement Summary

**Deepened on:** 2026-06-12
**Sections enhanced:** Architecture (crux), mapping table, Phase 1 fixtures, Acceptance Criteria, Risks.
**Agents used:** verify-the-negative (Explore), best-practices-researcher, security-sentinel.

### Key Improvements (from deepen-plan)

1. **Code regions are escape-only, NOT verbatim (P1-B, security-sentinel).** Slack renders
   `<!channel>` / `<@U…>` inside backtick code in a `text` payload — they are NOT parse-suppressed
   the way GFM suppresses them. So code spans/fences get `&<>` escaped (Slack un-escapes the 3
   entities for display, so content still reads correctly) while still NOT applying GFM conversion.
   "Verbatim byte-for-byte" was unsafe and is struck.
2. **`|` (pipe) handling is now specified (P1-A).** A raw `|` inside a converted link's url or label
   re-opens the `<url|label>` grammar. Inside minted links: strip/percent-encode `|` in the url and
   escape/strip `|` in the label. Slack's 3-entity escape (`&<>`) does NOT cover `|`.
3. **Keystone output-invariant assertion added (P1-C).** A single fail-closed assertion — the
   converter output contains **zero** `<!`, `<@`, `<#`, `<subteam^` sequences (the only raw `<`
   allowed is one immediately starting a URL scheme inside a minted link) — backstops every
   injection-smuggling path regardless of how it was crafted. Added to AC2 and T7.
4. **Explicit fallback wiring (P2-C).** `BODY=$(node …)` assignment masks the exit code under
   `bash -e`; the step must use `if ! BODY=$(node …); then BODY=$(sed …); echo "::warning::"; fi`,
   never `BODY=$(node … || sed …)`.
5. **Bare URLs are NOT wrapped (best-practices).** Slack auto-links bare URLs; only emit `<url|text>`
   when there is custom link text (a genuine `[text](url)`). Wrapping bare URLs is redundant/noisy.

### New Considerations Discovered

- The fallback is for **availability, not safety** — safety lives in the converter's escape
  correctness + the output invariant. A crafted input that exits 0 with a bad payload would bypass
  the non-zero-exit fallback; the output invariant is the real defense.
- All 6 negative/scope claims (one Slack site, no converter exists, no npm-ci in release job,
  markdown-it unavailable, secret-scan.yml bare-`node` precedent, terraform-drift-is-email-not-Slack)
  were verified true against the codebase by the verify-the-negative pass.

## Overview

The Soleur release pipeline posts release announcements to an internal Slack channel via an
inline shell step in `.github/workflows/reusable-release.yml` (lines 655-714, shipped by
`feat-slack-release-notify` ~2026-06-10, issue #5079). That step already does two correct things:
it writes a `*single-asterisk*` bold **header** (valid mrkdwn) and entity-escapes `&`/`<`/`>` in the
untrusted changelog **body** to neutralize mass-ping (`<!channel>`) and disguised-link injection.

But the changelog **body** itself is raw GitHub-flavored Markdown lifted from the PR body /
`CHANGELOG.md`. Slack does **not** render GFM. So `**bold**`, `## headings`, `[text](url)`,
`~~strike~~`, and `_italic_`/`*italic*` all render as **literal characters** in the Slack message.
This is exactly the gap the prior spec deferred as **NG4** ("Block Kit rich formatting / plain
`text` for v1; later enhancement").

This feature closes that gap: introduce a **markdown→Slack-mrkdwn converter**, wire it into the one
existing Slack-sending step, and **document the convention** (a GFM→mrkdwn mapping table + the
escape-vs-emit ordering invariant) so the next workflow that posts to Slack reuses the converter
instead of re-deriving a broken sed pipeline.

## Problem Statement / Motivation

Release notes authored in GFM render with formatting markers visible to the team:

```
*Web Platform v1.2.3 released!*          ← header: correct (single-asterisk bold)

Some fixes in **bold** and a [link](https://x)    ← body: BROKEN
## Breaking changes                                ← renders literal "## Breaking changes"
- item one                                         ← renders as "- item one" (not a Slack bullet)
~~removed~~ feature                                ← renders literal "~~removed~~"
```

Beyond the cosmetic defect, the body is **untrusted** (any PR author writes the changelog), so the
converter must remain compatible with the existing injection-safety guarantee: a raw `<!channel>`,
`<@U123>`, or `<https://evil|Click here>` typed into the changelog must still render **inert**, never
fire a ping, and never become a disguised link.

## Proposed Solution

1. Build a **markdown→mrkdwn converter** as a self-contained Node ESM script
   (`scripts/md-to-mrkdwn.mjs`) that reads markdown on stdin and writes Slack mrkdwn on stdout.
   It exports a pure `toSlackMrkdwn(md: string): string` function plus a thin stdin/stdout CLI so it
   is unit-testable with `node --test`.
2. **Wire it into** the "Post to Slack (release)" step in `reusable-release.yml`, replacing the
   body's `sed`-only escape with `node scripts/md-to-mrkdwn.mjs < "$RELEASE_NOTES_FILE"`. The header
   and release-notes-link assembly stay in shell; only the body transform moves to the script.
3. **Preserve all non-formatting behavior**: the empty-webhook skip, `unfurl_links: false`,
   `continue-on-error: true`, the `|| echo 000` curl guard, the HTTP-2xx `::warning::` path, and the
   length cap. Add a **converter-failure fallback**: if the script exits non-zero, fall back to the
   current `sed`-escaped plain body and emit a `::warning::` — never fail the release.
4. **Update the existing contract test** (`plugins/soleur/test/reusable-release-idempotency.test.sh`
   T7) to assert the converted output (GFM `**bold**` → `*bold*`, `[t](u)` → `<u|t>`) AND that the
   injection-safety assertions still hold.
5. **Document the convention** in `plugins/soleur/skills/ship/references/ci-workflow-authoring.md`
   (the canonical Slack-notification convention file) with the GFM→mrkdwn mapping table, the
   escape-vs-emit ordering invariant, and a pointer to the shared converter.

## Research Reconciliation — Premise vs. Codebase

The task premise asserts Slack messages "render with broken/literal markdown characters" across the
codebase. Verified against `origin/main` — the premise is **partially stale and the scope is much
narrower than stated**:

| Premise claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "Bold is `**double**` and renders broken" | The release **header** already uses `*single*` bold (`reusable-release.yml:692-694`). | No change to header. The live defect is only the **body**. |
| "Every place that sends to Slack composes GFM" | There is exactly **ONE** active Slack-sending site (`reusable-release.yml`). `git grep hooks.slack.com\|SLACK_*_WEBHOOK` returns only that file. No server/cron/TS Slack POST exists. | Scope = one site + converter + convention doc. No broad sweep. |
| "Links/strike/headings render broken" | **True** for the changelog body — only `&`/`<`/`>` are escaped today; no GFM→mrkdwn conversion happens. | This is the real fix. |
| (SpecFlow agent claimed) `scheduled-terraform-drift.yml` is a 2nd Slack consumer | **False.** That workflow's `&<>` sed escape feeds `notify-ops-email` (HTML email body), not Slack (`:226`). | The shared-converter justification rests on regression-prevention + future adoption, NOT a current 2nd site. Recorded in Alternatives. |
| (SpecFlow agent assumed) markdown-it usable in the release job | `markdown-it@^14.1.1` is a **root devDependency** but the release job runs **no `setup-node`/`npm ci`** (only `actions/checkout` at `:77`). `node node_modules/markdown-it` would throw `MODULE_NOT_FOUND` in CI. | Forces the implementation-shape decision (see Architecture / Alternatives). Established CI precedent (`secret-scan.yml:130`) is bare `node <script>.mjs` with **zero deps**. |

**Premise Validation note:** No cited issue/PR was found stale in a blocking way. The
`feat-slack-release-notify` work (#5079) is merged and is the direct predecessor; this feature is its
NG4 fast-follow. No external blocker is open against this scope.

## Technical Approach

### Architecture

**Implementation shape — RESOLVED to a zero-dependency Node ESM script.** This is the central design
decision; the evidence:

- **Pure bash/sed/awk is unsafe** for this transform. It cannot (a) preserve code fences / inline
  code byte-for-byte (a `**` or `[x](y)` inside a code sample would be mangled), (b) distinguish a
  `*`-bullet from a `*`-bold delimiter, (c) tell an author-typed `<` (data → escape) from a
  converter-emitted `<` for a link (syntax → keep) in a single pass, or (d) resolve reference-style
  links. These are the silent-corruption classes the original `&<>` escape was added to prevent.
- **markdown-it (the root devDependency) is NOT available in the release job** (no `npm ci`). Adding
  `setup-node` + a scoped install to the release **critical path** is a cold-start + dependency cost
  on every release, and `node_modules` resolution from a workflow `run:` block at repo root is
  fragile.
- **Established CI precedent is a bare `node <script>.mjs` with zero external deps**
  (`secret-scan.yml:130` runs `node apps/web-platform/scripts/lint-fixture-content.mjs` with no
  setup-node). The runner's stock Node (≥20) ships a robust stdlib.

→ **Decision:** `scripts/md-to-mrkdwn.mjs` is a **self-contained** ESM script using only Node stdlib
(no `import` of markdown-it or any dependency). It implements a small, fence-aware line/inline
tokenizer scoped to exactly the GFM subset that appears in changelogs. `node` is invoked directly in
the workflow `run:` block; no `setup-node`, no `npm ci`, no `node_modules` dependency. The root
`package.json` already declares `"type": "module"`, so `.mjs` runs natively. **deepen-plan / the
implementer must `node --version`-probe the runner and confirm the stock Node major satisfies the
stdlib APIs used; if a dependency genuinely cannot be avoided, escalate to the setup-node fork rather
than silently adding an install to the release critical path.**

### The crux: escape-vs-emit ordering (single-pass, context-aware)

The transform is **one tokenizing pass**, not two string passes. Per-context rules:

- **Text nodes** (literal prose, including any raw `<!channel>` / `<@U…>` / `<url|evil>` the author
  typed): escape `&`→`&amp;`, `<`→`&lt;`, `>`→`&gt;`. This is what keeps injection inert.
- **Converter-emitted structural syntax** (the `<`, `>`, `|` of a `<url|label>` link the converter
  mints from a genuine `[text](url)`): the two `<` `>` delimiters and the one `|` delimiter are
  written **raw**. But the **url** and **label** segments are sub-escaped: `&<>` → entities, AND any
  raw `|` is stripped/percent-encoded in the url and stripped/escaped in the label (a raw `|` in
  either segment would re-open the `<url|label>` grammar — Slack's 3-entity escape does not cover
  `|`). [P1-A]
- **Code spans / fenced code blocks**: **escape-only** — escape `&`→`&amp;`, `<`→`&lt;`,
  `>`→`&gt;`, and do NOT apply GFM conversion (no `**`→`*`, links stay literal). Content still reads
  correctly because Slack un-escapes the 3 entities for display inside backticks. **Not** verbatim:
  Slack renders `<!channel>`/`<@U…>` inside backtick code in a `text` payload, so a verbatim copy
  would be a live mass-ping hole. [P1-B]
- **Bare URLs** (`https://x` appearing in prose, and GFM autolinks `<https://x>`): emit the bare URL
  unwrapped — Slack auto-links it. Only emit `<url|label>` for a genuine `[label](url)` with custom
  text. [best-practices]
- **Keystone output invariant (fail-closed backstop):** regardless of the above, the converter's
  final output MUST contain **zero** `<!`, `<@`, `<#`, or `<subteam^` sequences. The only raw `<` in
  output is one that immediately begins a URL scheme (`http`/`https`/`mailto`) inside a minted link.
  This single assertion catches every smuggled-mention path. [P1-C]
- **Truncation happens AFTER conversion** (current code truncates before there is any conversion;
  that ordering breaks once conversion is inserted because cutting raw GFM mid-`[text](` would
  produce a broken `<url|`). Truncate the *rendered mrkdwn* at a token boundary, append `…`, and if
  an unclosed fence remains, append a closing ` ``` `.

### GFM → mrkdwn mapping (the converter's contract)

| GFM input | Slack mrkdwn output | Notes |
|---|---|---|
| `**bold**` / `__bold__` | `*bold*` | single asterisk |
| `*italic*` / `_italic_` | `_italic_` | single underscore |
| `~~strike~~` | `~strike~` | single tilde |
| `` `code` `` | `` `code` `` | escape `&<>` inside, NO convert (Slack renders mentions in backticks) [P1-B] |
| ` ```fence``` ` | ` ```fence``` ` | escape `&<>` inside, NO convert [P1-B] |
| `[text](url)` | `<url\|text>` | delimiters `<` `>` `\|` raw; url+label sub-escaped incl. `\|` [P1-A] |
| `[text][ref]` + `[ref]: url` | `<url\|text>` | resolve reference links |
| `<https://x>` (autolink) / bare url | `https://x` (unwrapped) | Slack auto-links bare URLs; do NOT wrap |
| `![alt](url)` (image) | `<url\|alt>` | no inline image in mrkdwn → degrade to link |
| `# H1` … `###### H6`, Setext | `*H1*` (bold line) | no headings in mrkdwn |
| `- ` / `* ` / `+ ` bullet | `• item` | canonical Slack bullet |
| `1.` ordered | `1.` | Slack renders ordered lists |
| `- [ ]` / `- [x]` task | `• ☐ ` / `• ☑ ` | no native checkbox |
| `> quote` | `> quote` | same as GFM |
| GFM pipe table | wrap in ` ``` ` code block | no table support; monospace degrade |
| `---` / `***` thematic break | blank line | no HR in mrkdwn |
| raw `<!channel>` / `<@U…>` in prose | `&lt;!channel&gt;` etc. | escaped → inert (injection safety) |

### Implementation Phases

#### Phase 1: Converter script + tests (RED → GREEN)

- Create `scripts/md-to-mrkdwn.mjs`: `export function toSlackMrkdwn(md)` + a CLI guard
  (`if (import.meta.url === ...) { read stdin → toSlackMrkdwn → stdout }`).
- Create `scripts/md-to-mrkdwn.test.mjs` (`node --test`) covering every mapping-table row PLUS the
  edge cases below. Write the failing tests first.
- Wire the new `node --test` file into `scripts/test-all.sh` if it is not already swept by an
  existing glob (verify: the script greps for `*.test.mjs` discovery; if not, add the file
  explicitly so the orphan-suite exit gate runs it).

Edge-case fixtures (each a test):
- code fence containing `**stars**` and `[x](y)` → `**stars**`/`[x](y)` NOT converted (literal),
  AND any `&<>` inside is escaped (escape-only, not verbatim) [P1-B]
- inline code `` `**x**` `` mid-sentence → inner not converted
- inline code `` `<@U123>` `` and fence containing `<!channel>` → escaped to `&lt;@U123&gt;` /
  `&lt;!channel&gt;`, never live mention [P1-B]
- unclosed/unbalanced fence → runs to EOF as code (GFM behavior), output stays valid
- nested emphasis `**_x_**` → `*_x_*`; `**<!channel>**` and `_<@U1>_` → mention escaped inert [P1-C]
- reference-style link resolved; orphan `[ref]: url` line consumed
- image `![alt](url)` → `<url|alt>`
- raw `<!channel>`, `<@U123>`, `<https://evil|Bank>` typed in prose → all escaped, inert
- **minted-link smuggling** [P1-A]: `[<!channel>](https://x)` → `<https://x|&lt;!channel&gt;>` (no raw
  `<!channel`); `[Click](https://x|<!channel>)` → url's `|`/`<>` neutralized; `[a|b](https://x)` →
  label `|` escaped/stripped; `[a](https://x>y)` → url `>` escaped; `[](https://x)` / `[x]()` →
  no degenerate `<|x>` / `<>`
- **malformed/nested links** [P1-C]: `[a[b](c)](d)`, `[text](url with > inside` (unclosed),
  `[a)(b]` unbalanced → degrade to escaped literal text, never leak unescaped `<>|`
- bare URL in prose / `<https://x>` autolink → emitted unwrapped (no `<url|>` wrapping)
- empty body / whitespace-only body → empty/clean output
- all-code-fence body → fence preserved (escaped) including closing ` ``` `
- truncation mid-link and mid-fence → structure-aware cut, no broken `<url|` or unclosed fence
- **keystone invariant** [P1-C]: a property-style test asserting for a corpus of adversarial inputs
  that the output contains zero `<!` / `<@` / `<#` / `<subteam^` — the fail-closed backstop

#### Phase 2: Wire converter into the workflow step

- Edit `.github/workflows/reusable-release.yml` "Post to Slack (release)" step (655-714):
  replace the body `sed` escape with the converter, using the **explicit `if !` form** (NOT
  `BODY=$(node … || sed …)` — a `BODY=$(cmd)` assignment masks the exit code under `bash -e`, so the
  fallback would never trigger) [P2-C]:

  ```bash
  if ! BODY=$(node scripts/md-to-mrkdwn.mjs < "$RELEASE_NOTES_FILE"); then
    echo "::warning::md-to-mrkdwn failed; sent plain escaped body"
    BODY=$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$RELEASE_NOTES_FILE")
  fi
  ```

  The fallback is for **availability, not safety** — safety lives in the converter's escape
  correctness + the keystone output invariant, not in the non-zero-exit guard (a crafted input that
  exits 0 with a bad payload would bypass the fallback; the invariant test is the real defense).
- Keep truncation AFTER conversion; re-check the body cap so header + release URL appended after the
  body keep the total under Slack's ~4k display fold (current 3000 cap + ~80 char header may be
  re-tuned).
- Keep `unfurl_links: false`, `--max-time 15`, `|| echo 000`, the 2xx `::warning::` branch.

#### Phase 3: Update the contract test + document the convention

- Update `plugins/soleur/test/reusable-release-idempotency.test.sh` T7: extend the fixture notes to
  contain `**bold**` and `[text](url)`, assert the payload `.text` contains `*bold*` and `<url|text>`
  (converted), AND keep the existing assertions that `<!channel>` is escaped to `&lt;!channel&gt;`
  and no raw mass-ping reaches the payload. Note: the test executes the real run-block under a curl
  stub, so it will invoke `node scripts/md-to-mrkdwn.mjs` — ensure the stub harness has `node` on
  PATH (it does; the harness only stubs `curl`/`gh`).
- Update `plugins/soleur/skills/ship/references/ci-workflow-authoring.md`: add a "Slack mrkdwn
  formatting" subsection with the GFM→mrkdwn mapping table, the escape-vs-emit ordering invariant,
  and a pointer to `scripts/md-to-mrkdwn.mjs` as the shared converter to reuse for any future
  Slack-posting workflow.
- Optionally add a one-line pointer in `plugins/soleur/skills/release-announce/SKILL.md` manual-post
  guidance (line 47) noting that CI auto-converts GFM→mrkdwn; a manual Slack post should run the
  changelog through `scripts/md-to-mrkdwn.mjs` for parity.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Pure bash/sed/awk converter (inline, no Node) | Cannot preserve code fences, cannot disambiguate `*`-bullet vs `*`-bold, cannot do single-pass context-aware escape-vs-emit. The exact silent-corruption class the escape was added to prevent. |
| markdown-it (root devDependency) + add `setup-node`/`npm ci` to release job | Adds a cold-start + dependency install to the release **critical path** on every release; `node_modules` resolution from a repo-root `run:` block is fragile. The robust-parser benefit doesn't outweigh putting an install in the release path. Self-contained stdlib script gets fence-correctness without the dep. **Re-open only if a stdlib-only converter proves infeasible.** |
| Block Kit `blocks` payload instead of `text` + mrkdwn | Prior spec NG4 deferred Block Kit; `text` + mrkdwn is the lower-risk uplift and section-block 3000-char limit doesn't apply to top-level `text`. Block Kit is a separate later enhancement; not needed to fix the literal-markdown defect. |
| Build the converter as a TS module in `apps/web-platform/lib/` | The only consumer is a CI shell workflow at repo root, not the web-platform app. `markdown-it` lives in the **root** `package.json`; a repo-root `scripts/*.mjs` co-locates with its natural home and matches the `secret-scan.yml` `node <script>.mjs` precedent. A web-platform module would need a build/bundling step to run in the release job. |
| Convert at authoring time (in `release-announce` skill) instead of in CI | The CI step receives the PR-body changelog of CI-driven releases; the skill only handles manual releases (which get no Slack post). The transform must live where the Slack POST is, i.e., the workflow. |

**Deferred (tracking):** Block Kit rich formatting remains deferred (was NG4). No new deferral issue
needed — it stays out of scope as before; note it in the PR body as explicitly out of scope.

## User-Brand Impact

- **If this lands broken, the user experiences:** the **internal team** sees a malformed Slack
  release message (broken converter output, a missing release link, or — worst case — a converter
  bug that lets a raw `<!channel>` slip through and mass-pings the channel). The end **customer** is
  not exposed; release notes are public and the Slack channel is team-internal.
- **If this leaks, the user's data is exposed via:** N/A — no customer data, auth, or cross-tenant
  surface is touched. The only sensitive value (the webhook URL) is already masked (`::add-mask::`)
  and caught by the `soleur-slack-webhook-url` gitleaks rule; this feature does not change secret
  handling.
- **Brand-survival threshold:** `none` — internal team channel, public release notes, no
  customer-facing surface, no regulated data. (Inherits the `feat-slack-release-notify` spec's
  refined `none` threshold for the same reasons.) Webhook-leak is a security concern handled by the
  existing gitleaks rule + `::add-mask::`, not a customer-brand vector. The one residual risk —
  injection mass-ping — is a team-annoyance, not a brand-survival event, and is explicitly tested.

*Scope-out override (sensitive path touched: `.github/workflows/reusable-release.yml` matches the preflight Check-6 release pattern):* `threshold: none, reason: the workflow edit only changes how the changelog body is formatted for an internal team Slack channel — it touches no customer data, auth, secret-handling, or cross-tenant surface, and the webhook secret's masking/gitleaks protection is unchanged.`

## Observability

```yaml
liveness_signal:
  what: "GitHub Actions step 'Post to Slack (release)' log line 'Slack notification sent (HTTP 2xx)'; the Slack message itself is the end-to-end liveness artifact"
  cadence: "per-release (every CI-driven release of a component)"
  alert_target: "operator email via the existing 'Email notification (release)' step (reusable-release.yml:639) — redundant signal independent of Slack"
  configured_in: ".github/workflows/reusable-release.yml:655-714 (Slack step), :639 (email step)"

error_reporting:
  destination: "GitHub Actions run annotations (::warning::) — surfaced in the workflow run UI and the Actions API"
  fail_loud: "::warning::Slack notification failed (HTTP <code>) on non-2xx; ::warning::md-to-mrkdwn failed; sent plain escaped body on converter non-zero exit"

failure_modes:
  - mode: "Converter (md-to-mrkdwn.mjs) crashes or emits invalid output"
    detection: "node non-zero exit caught in the step; ::warning:: emitted; falls back to sed-escaped plain body"
    alert_route: "GitHub Actions run annotation + the email-to-ops release signal still fires"
  - mode: "Converter regression lets raw <!channel> reach the payload (injection)"
    detection: "plugins/soleur/test/reusable-release-idempotency.test.sh T7 asserts no raw mass-ping in payload; runs in scripts/test-all.sh (CI gate, blocks merge)"
    alert_route: "CI red on PR — never reaches production"
  - mode: "Slack POST fails (bad webhook, timeout, DNS)"
    detection: "curl --max-time 15 || echo 000; HTTP code checked; non-2xx → ::warning::"
    alert_route: "GitHub Actions annotation; release stays green (continue-on-error); email-to-ops unaffected"

logs:
  where: "GitHub Actions run logs for the reusable-release workflow (the Slack step's stdout)"
  retention: "GitHub Actions default log retention (90 days)"

discoverability_test:
  command: "node scripts/md-to-mrkdwn.mjs <<< '**bold** and [link](https://x) and <!channel>'"
  expected_output: "*bold* and <https://x|link> and &lt;!channel&gt;  (bold converted, link converted, mass-ping escaped inert)"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `scripts/md-to-mrkdwn.mjs` exists, exports `toSlackMrkdwn`, and runs as a stdin→stdout CLI
  with bare `node` (no `setup-node`/`npm ci`/external import). Verify:
  `node scripts/md-to-mrkdwn.mjs <<< '**b** [t](https://u)'` prints `*b* <https://u|t>`.
- [ ] AC2: `node --test scripts/md-to-mrkdwn.test.mjs` passes, including every edge-case fixture
  (code-fence escape-only, nested emphasis, reference links, image-degrade, injection-escape,
  minted-link smuggling, malformed/nested links, empty body, all-fence body, structure-aware
  truncation) AND the keystone invariant: for the adversarial corpus, output contains zero `<!` /
  `<@` / `<#` / `<subteam^` sequences. [P1-A/B/C]
- [ ] AC3: `reusable-release.yml` "Post to Slack (release)" step pipes the body through
  `scripts/md-to-mrkdwn.mjs` with a non-zero-exit fallback to the sed-escaped body + `::warning::`.
  `actionlint .github/workflows/reusable-release.yml` is clean; the embedded `run:` shell is
  `bash -c`-valid (extract + `bash -n` the snippet).
- [ ] AC4: `plugins/soleur/test/reusable-release-idempotency.test.sh` passes and its T7 block now
  asserts (a) GFM `**bold**`→`*bold*` and `[t](u)`→`<u|t>` in the payload `.text`, (b) the existing
  injection assertions (`<!channel>`→`&lt;!channel&gt;`, no raw mass-ping in payload), AND (c) the
  keystone invariant on the full payload `.text` — zero `<!` / `<@` / `<#` / `<subteam^` sequences. [P1-C]
- [ ] AC5: A simulated converter crash (e.g., temporarily aliasing `node` to fail in the test
  harness, or a unit test of the fallback branch) keeps the release step on the `::warning::` path
  with a plain-escaped body — release job stays green.
- [ ] AC6: `bash scripts/test-all.sh` is green (orphan-suite exit gate runs the new `.mjs` test and
  the updated `.test.sh`).
- [ ] AC7: `ci-workflow-authoring.md` contains the GFM→mrkdwn mapping table, the escape-vs-emit
  ordering invariant, and a pointer to `scripts/md-to-mrkdwn.mjs`. Verify:
  `grep -c 'md-to-mrkdwn' plugins/soleur/skills/ship/references/ci-workflow-authoring.md` ≥ 1.

### Post-merge (operator)

- [ ] AC8: On the next CI-driven release, confirm the Slack message renders converted formatting
  (bold/links/bullets, no literal `**`/`[]()`/`##`). Automation: not feasible to assert the rendered
  Slack DOM without the channel; the per-release liveness log line + the T7 payload-shape test cover
  the machine-checkable half. Operator visually confirms the next real release post.

## Test Scenarios

### Acceptance Tests (RED targets)

- Given a changelog `**bold** and [link](https://x)`, when `toSlackMrkdwn` runs, then output is
  `*bold* and <https://x|link>`.
- Given a changelog containing a fenced code block with `**stars**` inside, when converted, then the
  `**stars**` inside the fence is preserved byte-for-byte (not converted).
- Given a changelog line `Ping <!channel> now`, when converted, then output contains
  `&lt;!channel&gt;` and never a raw `<!channel>`.
- Given a `[Click](https://evil)` disguised-link and a raw `<https://evil|Bank>` in prose, when
  converted, then the genuine `[Click](url)` becomes `<url|Click>` and the raw `<…|Bank>` is escaped
  inert.

### Regression Tests

- Given an empty / missing `RELEASE_NOTES_FILE`, when the step runs, then `BODY=""` and only the
  header + release link are posted (current behavior preserved).
- Given `unfurl_links` is set, when the payload is built, then it is `false` (unchanged).

### Edge Cases

- Given a body that exceeds the display budget, when truncated, then the cut is at a token boundary,
  no `<url|` is left dangling, and any open fence is closed with ` ``` `.
- Given a GFM pipe table, when converted, then it is wrapped in a code block (monospace degrade), not
  emitted as broken pipes.

### Integration Verification (for /soleur:qa)

- **Local converter:** `node scripts/md-to-mrkdwn.mjs <<< '## H\n- a\n~~x~~'` expects
  `*H*` line, `• a`, `~x~`.
- **Contract test:** `bash plugins/soleur/test/reusable-release-idempotency.test.sh` expects all T7
  assertions pass.

## Files to Edit

- `.github/workflows/reusable-release.yml` — pipe body through converter + fallback (Phase 2).
- `plugins/soleur/test/reusable-release-idempotency.test.sh` — extend T7 assertions (Phase 3).
- `plugins/soleur/skills/ship/references/ci-workflow-authoring.md` — document the convention (Phase 3).
- `plugins/soleur/skills/release-announce/SKILL.md` — optional one-line manual-post parity note (Phase 3).
- `scripts/test-all.sh` — add the new `.test.mjs` to the suite IF not auto-discovered (Phase 1).

## Files to Create

- `scripts/md-to-mrkdwn.mjs` — the self-contained converter (function + CLI).
- `scripts/md-to-mrkdwn.test.mjs` — `node --test` unit tests.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (63 open) — none reference
`reusable-release.yml`, `md-to-mrkdwn`, `ci-workflow-authoring`, or
`reusable-release-idempotency`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/infra/tooling change. No UI surface (no
`components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files to Create/Edit), so the
Product/UX Gate does not fire (mechanical UI-surface scan: no match). No regulated-data surface
(no schema/migration/auth/API-route/`.sql`), so the GDPR/Compliance gate (Phase 2.7) is skipped.
No new infrastructure (no server/secret/vendor/cron/DNS/TLS), so the IaC routing gate (Phase 2.8)
is skipped — the change edits an existing workflow step and adds a repo-root script.

## Dependencies & Risks

- **Risk — Node availability/version in the release job.** Mitigation: the converter uses only Node
  stdlib (no external import) and the established `secret-scan.yml` precedent runs bare
  `node <script>.mjs`. The implementer MUST `node --version`-probe the runner and confirm the stock
  major satisfies the stdlib APIs used; if a dep proves unavoidable, escalate to the setup-node fork
  (do NOT silently add `npm ci` to the release critical path).
- **Risk — injection regression (mass-ping) [P1, security-sentinel].** The converter must escape
  `&<>` in all text nodes AND inside code regions AND inside minted-link url/label segments
  (plus `|` handling in url/label); the only raw `<>|` are converter-minted link delimiters. The
  **keystone output invariant** (zero `<!`/`<@`/`<#`/`<subteam^` in output) is the fail-closed
  backstop, asserted in both the unit test and T7. This is the single security-critical invariant.
- **Risk — code-span mention rendering [RESOLVED to escape-only].** Slack DOES render `<!channel>` /
  `<@U…>` inside backtick code in a `text` payload (code styling is visual, not parse-suppressing).
  Therefore code regions are escape-only (escape `&<>`, no GFM convert) — NOT verbatim. Resolved in
  the design; no implementation-time confirmation needed.
- **Risk — `|` re-opening link grammar [P1-A].** A raw `|` inside a minted `<url|label>` url or
  label re-opens the grammar. Slack's 3-entity escape does not cover `|`; the converter must
  strip/percent-encode `|` in urls and escape/strip `|` in labels.
- **Risk — truncation/conversion ordering.** Truncating before conversion would sever GFM tokens the
  converter then mangles. Truncate the rendered mrkdwn at a token boundary; close any open fence.
- **Risk — fallback must not fail the release.** The `node` call must be guarded so a non-zero exit
  (or `bash -e`) cannot abort the step; fall back to the sed-escaped body + `::warning::`.

## References & Research

### Internal References

- `.github/workflows/reusable-release.yml:655-714` — the one Slack-sending step (target).
- `plugins/soleur/test/reusable-release-idempotency.test.sh:254-332` — existing T7 payload contract.
- `plugins/soleur/skills/ship/references/ci-workflow-authoring.md:10` — Slack-notification convention (carve-out).
- `plugins/soleur/skills/release-announce/SKILL.md:10,47` — manual-release-gets-no-Slack note.
- `knowledge-base/project/specs/feat-slack-release-notify/spec.md` — predecessor spec (NG4 deferred Block Kit/rich formatting).
- `knowledge-base/project/plans/2026-06-09-feat-move-release-notifications-discord-to-slack-plan.md` — as-built inline-step design.
- `.github/workflows/secret-scan.yml:130` — precedent: bare `node <script>.mjs` in CI, zero deps, no setup-node.
- `package.json:2` — `"type": "module"` (`.mjs`/ESM runs natively).

### External References

- Slack mrkdwn formatting (canonical, fetched 2026-06-12): https://docs.slack.dev/messaging/formatting-message-text
  — bold `*x*`, italic `_x_`, strike `~x~`, links `<url|text>`, no headings/tables/images, escape only `&`/`<`/`>`.
- Slack section block 3000-char limit (top-level `text` is separate, ~40k hard / ~4k display): https://docs.slack.dev/reference/block-kit/blocks/section-block

### Internal Learnings

- `knowledge-base/project/learnings/2026-04-17-grep-lib-before-writing-format-helpers.md` — grep for
  existing helpers first (done: no converter exists); test identity/edge values first (empty body is
  the first fixture).
- `knowledge-base/project/learnings/2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md`
  — Slack has NO API-level mention suppression; escaping `&<>` is the only defense (load-bearing for
  the converter's text-node rule).
- `knowledge-base/project/learnings/2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md`
  — preserve caller intent 1:1; no silent default that masks a missing input.
- `knowledge-base/project/learnings/2026-06-09-no-test-asserts-X-must-grep-workflow-step-names-in-ci-test-sh.md`
  — workflow-step correctness is validated by `*.test.sh` parsing step names; T7 is that gate here.
- `knowledge-base/project/learnings/2026-05-11-tr-does-not-interpret-hex-escapes.md` — if any shell
  escaping remains, use octal not `\xHH` (the converter is Node, so largely N/A).

### Related Work

- Predecessor: `feat-slack-release-notify` (#5079, merged ~2026-06-10) — moved release notifications
  Discord→Slack, deferred rich formatting as NG4. This feature is its fast-follow.
