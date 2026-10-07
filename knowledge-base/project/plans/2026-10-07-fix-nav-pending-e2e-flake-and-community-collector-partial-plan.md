---
title: "fix: nav-pending e2e flake (root causes) and full collector output for the community-monitor digest"
type: fix
date: 2026-10-07
slug: fix-nav-pending-e2e-flake-and-community-collector-partial
branch: feat-one-shot-9666-nav-pending-flake-collector-partial
issue: 9666
closes: [9666]
refs: [9678, 9679, 7124]
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# fix: nav-pending e2e flake (root causes) and full collector output for the community-monitor digest

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No spec.md exists for this one-shot branch.

## Overview

Two independent fixes ship in one branch (draft PR #9676).

1. **#9666 — the nav-pending e2e flake.** The required `e2e` check goes red intermittently on
   `nav-states-nav-pending.e2e.ts` (the "NavLink click" test, and on main the "never commits" test).
   Local reproduction on an idle 16-core box found **three independent causes**, each observed in
   captured evidence (not inferred), one of them a real (small) product race. Fix all three
   deterministically: no retries, no timeout bumps.
2. **Community-monitor `partial` digest rows (#9678, filed from this plan).** The spawned agent has
   no file tools (ADR-273), so any collector output past the Bash tool's inline limit (30,000
   characters by default) is truncated and unreadable; the prompt then forces `partial` /
   `output-too-large`. The 2026-10-06 digest shows Discord and GitHub both `partial` for that
   reason. Fix it at the collectors with a handler-controlled compact projection, leaving the
   closed schema, the containment hook, the spawn credentials and the publication path untouched.

## Research Insights

### Premise Validation (Phase 0.6)

- **#9666** open, no closing PR, labels `flaky`, `priority/p2-medium`; PR #9676 is an empty draft.
  The cited test exists on `origin/main` (`apps/web-platform/e2e/nav-states-nav-pending.e2e.ts`,
  the "NavLink click" test and the "never commits" test).
- The "schema-constrained handler-side publication change" is #9596 (`ed6083309f`), ADR-273.
  Its Spike S3 paragraph and the runbook ("A Discord day that shows `partial` with cause
  `output-too-large`") **explicitly accepted** the inline-limit partial for a Discord listing.
  The premise "now also GitHub" is confirmed by `knowledge-base/support/community/2026-10-06-digest.md`.
- **No open or closed issue tracked the partial gap** (searched "partial", "output-too-large",
  "inline limit", "collector"). #7124 (collector-side input minimisation before Anthropic egress)
  is the nearest relative but is a privacy objective; this change narrows the same input without
  closing it. Filed **#9678**.
- **Correction to the ask:** the GitHub row cannot become fully `collected` by this PR. The ADR-273
  addendum (2026-10-06) makes the handler force github to `partial` / `auth` on every run while the
  read-only spawn token cannot list stargazers. This PR removes the `output-too-large` cause; the
  `auth` label is a separate, accepted residual, now tracked as **#9679** (previously untracked).
- ADR corpus check: the proposed mechanism (a compact collector mode) is not in any ADR's rejected
  alternatives; ADR-273's only recorded alternative for large output was the `read-root` file-read
  fallback, which Spike S3 declined to build.

### Root cause of #9666, with evidence

Experiments ran against the real dev servers through a scratch Playwright config kept outside the
repo (scratchpad), on the unmodified spec. Baseline: 2 of the first 8 "NavLink click" runs red at
`--repeat-each=8` (same signature as CI: `toBeVisible` times out at 5000 ms, element not found); in
instrumented runs of the unmodified flow, 1 of 16 and 3 of 40 red. In-page event logs (`click`, `BAR+`/`BAR-`, `pushState`) and
`document` request logs, captured only for failing runs, separate three causes:

| # | Cause | Evidence in the failing run | Class |
|---|-------|------------------------------|-------|
| RC1 | The test clicks the rail link right after `domcontentloaded`, before React hydrated the `<a>`. The click is a normal anchor navigation (full document load), not a soft nav, so no episode and no bar. | `docsAfterClick` contained `/dashboard/settings` as a `document` request; the log restarted (`load`) with no `click` event in the new document. | test harness |
| RC2 | `await expect(BAR).toHaveCount(0)` directly after `link.click()` asserts "nothing shows under the 150 ms entry delay", but `click()` returns late on a busy box (observed 188 ms after the DOM click event). The bar is already up, so `toHaveCount(0)` blocks until the 1500 ms held fetch commits and the bar is gone; the next `toBeVisible` then times out. | `rel.clickEnd` 1081 ms vs `BAR+` at +1103 ms; `count0End` 3335 ms (it waited for the bar to leave); `pushState` at +2.6 s. | test harness (wall-clock claim made in the wrong place) |
| RC3 | **Product race.** `NavPendingLocationWatcher` calls `stopNavPending()` unconditionally in the effect that runs at its own mount. The watcher sits in a `Suspense` boundary that hydrates after the rail links. A click between link hydration and watcher mount starts an episode that the watcher's first effect run immediately cancels. | With RC1 and RC2 removed (gate on hydration, held fetch released by the test), 3 of 42 runs (2 of 12, 1 of 30) were still red, and **0 of 60** were red with the proposed watcher change applied temporarily to the working tree (then reverted): `nav_duration_ms` telemetry `nav:link:dashboard:lt400ms` emitted ~90 ms after the click (an episode stopped before the 150 ms entry delay), no `BAR+`, fetch still held, no `pushState`. | production (rare on real devices; frequent under a dev server, where hydration is slow) |

The readiness probe in RC1's fix was measured too: with every `/_next/static/**/*.js` request held, the rail link carried no React props key (`hasOnClick: false`); after release it carried one with an `onClick` function (`hasOnClick: true`).

The failing run on main also flaked `:220` ("never commits"), which has the same shape as RC1/RC3
(click right after `gotoDash`, then `toBeVisible`) and no RC2 line.

### Institutional learnings applied

- `2026-06-29-playwright-tohaveclass-auto-retries-poll-swap-is-noop.md` and the 2026-06-29 rail-toggle
  plan: "hydration-before-interaction" is a known e2e trap; the existing remedy in
  `nav-states-shell.e2e.ts` is a blind `waitForTimeout(1500)`. This plan replaces that pattern for the
  affected spec with a deterministic readiness probe (the ask forbids blind timeouts).
- `2026-06-03-shared-hook-fetch-coalescing-and-e2e-flake-isolation.md`: isolate by verifying the failing set
  changes across reruns; used (the three causes were found by comparing failing and passing runs).
- Claude Code truncates Bash output at 30,000 characters by default (output past it is saved to a
  file and the agent gets a preview and a path). The agent has no file tools, so the truncated part is
  unreadable by design (ADR-273 Spike S3).
- `cq-test-fixtures-synthesized-only`: all collector fixtures are generated by `jq -n`/`gen_*` helpers.

### Property List (Phase 0.6b)

1. A bar assertion runs only after the click became an in-page soft navigation whose fetch is held.
2. No e2e outcome depends on wall-clock time between `click()` returning and the 150 ms entry delay.
3. A navigation episode started after link hydration but before the watcher mounts is not cancelled
   (product behavior).
4. The Discord and GitHub collector output the agent reads fits the Bash inline limit with a
   deterministic margin on worst-case inputs.
5. Every field the prompt reads is present in the compact output, and the prompt names the compact
   field it reads (no silent shape drift).
6. Publication guarantees are unchanged: closed schema, no new agent capability or credential, no
   new file tool; default (interactive) collector output is byte-identical.

### Cut List

| Mechanism | Property it would buy | Disposition |
|-----------|----------------------|-------------|
| Playwright `retries` / larger `timeout` for the spec | none (hides RC1-RC3) | cut: the ask forbids it, and CI already has `retries: 1` (which failed both attempts in run 37489979327) |
| `waitForTimeout(1500)` hydration settle (house style) | 1 | cut: blind sleep; replaced by a React-props readiness probe |
| File/handoff of full collector output to the agent | 4 | cut: needs `Read`/`Glob`, which ADR-273 removed (the `read-root` fallback was declined in Spike S3); a handler-side collector run would move credentials |
| Raising the Bash output cap (`bashOutputMaxChars` / `BASH_MAX_OUTPUT_LENGTH`) | 4 | cut: a bump with a clamped ceiling, not a bound; also feeds more third-party text to the model |
| Handler computes the metrics from raw collector output | 4 | cut: larger rewrite, moves metric authorship; not needed for the property |
| A new ADR | 6 | cut: ADR-273 gets an addendum (decision is an extension of its Spike S3 result) |

## Research Reconciliation: Spec vs. Codebase

| Claim in the ask | Reality | Plan response |
|------------------|---------|---------------|
| "The Discord and GitHub collector outputs exceed the inline limit, so the digest labels them partial." | True (2026-10-06 digest); the label comes from the prompt's own rule (`output-too-large`), not from the handler. | Shrink the collector output the agent reads; keep the prompt rule as the residual fallback. |
| "so those sections are no longer partial" | Discord can become `collected`. GitHub stays `partial` / `auth` by design (ADR-273 addendum, stargazers 403 under the read-only token). | Success criterion for GitHub is "cause is no longer `output-too-large` and the previously truncated values (PRs touched, commits, interactions) are measured"; residual tracked in #9679. |
| "the nav-pending bar test reddens the required e2e check ... root cause of the flake" | Three causes, one in production code (RC3). | Fix all three; production change is minimal and unit-tested. |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Find the root cause of the flake, fix it deterministically (no blind retries/timeouts bumps)" | Phase 1 (RC1-RC3) | mapped |
| 2 | "close #9666 via \"Closes #9666\" in the PR body" | Phase 6 (PR body) | mapped |
| 3 | "Make the handler/collector path carry the full collector output (e.g. via file/handoff instead of inline, or paginate/trim deterministically) so those sections are no longer partial" | Phase 3 (collector compact mode), Phase 4 (handler flag, prompt) | mapped |
| 4 | "without weakening the schema-constrained publication guarantees or moving posting credentials" | Phase 4 (one non-secret env key; schema, hook and credentials untouched), Guard 1 | mapped |
| 5 | "Check first whether an open issue already tracks this; if none, file one and reference it." | Done in planning: none existed; filed #9678 (and #9679 for the GitHub `auth` residual); Phase 6 references both | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Test restructure (`clickNavLink` helper: hydration probe, gated hold; drop racy assertion) | "fix it deterministically (no blind retries/timeouts bumps)" | asked |
| Watcher mount race fix in `nav-pending-island.tsx` / `nav-pending-store.ts` | "Find the root cause of the flake" | asked (RC3 is a root cause) |
| Compact mode in two collector scripts, env flag in the handler, prompt update | "paginate/trim deterministically" | asked |
| ADR-273 addendum + runbook paragraph update | "without weakening the schema-constrained publication guarantees" | asked (documented decision must not contradict shipped behavior) |
| Soak follow-through script for #9678 | — | inferred — justification: plan Phase 2.9.1 requires enrolling a post-deploy soak so the tracker closes itself; the effect (rows stop being `output-too-large`) is only observable after the next scheduled run |
| #9679 filing | "accepted residual" (ask) | inferred — justification: wg-defer-only-after-inline-triage / deferral tracking: the GitHub `auth` label is an untracked residual that the ask's wording ("no longer partial") cannot be met on |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `plugins/soleur`, `scripts`, `knowledge-base`
- Planned files: 14 (12 edits, 2 creates) | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR, despite meeting the root threshold. The operator named one branch and draft PR (#9676) for both items, each is small, and the only shared artifact is the PR itself. The panel's suggestion to split (the cron prompt change is higher-stakes than the e2e fix, so a revert of one drags the other) is recorded as a Taste item in `decision-challenges.md`.

## User-Brand Impact

- **If this lands broken, the user experiences:** (e2e) a red required check or an over-eager skip that hides a real regression; (production) the thin route-progress bar fails to appear on a link click or sticks for the 30 s stall timeout; (digest) a public community digest row that shows wrong or `failed` Discord/GitHub numbers.
- **If this leaks, the user's data is exposed via:** nothing new. The compact projection strictly reduces what reaches the model (message bodies, comment snippets, logins and URLs are dropped; only counts, ids of channels, and capped titles remain). No credential, env allowlist entry or publication surface is added; the one new spawn env key is a non-secret flag.
- **Brand-survival threshold:** aggregate pattern
- **Threshold decision (challengeable):** a systematic mis-projection would publish a wrong number to a public digest every day (a pattern), but no single-user exposure exists, so not `single-user incident`.

## Implementation Phases

### Phase 1 — #9666: tests first, then the fixes (RED before GREEN)

Files: `apps/web-platform/test/nav-pending-island.test.tsx`, `apps/web-platform/test/nav-pending-store.test.tsx`,
`apps/web-platform/components/nav/nav-pending-island.tsx`, `apps/web-platform/lib/nav-pending-store.ts`,
`apps/web-platform/e2e/nav-states-nav-pending.e2e.ts`.

1.1 **Unit tests first (RC3).** In `nav-pending-island.test.tsx` add, using the existing `nav` mock and
`setLocation`:

- RED on `main`: "mounting the watcher mid-episode does not cancel the episode": `startNavPending("link")`
  before `render(<NavPendingIsland />)`, location unchanged; after render the snapshot is still
  `pending: true`, and after `PENDING_ENTRY_DELAY_MS` the bar is visible.
- RED on `main`: the same inside `<React.StrictMode>` (dev double-invokes effects; a "skip the first
  run" ref would fail here, a key comparison does not).
- GREEN guard (passes on `main` too, kept so the fix cannot regress the other direction): "a commit
  that landed before the watcher mounted still ends the episode": start an episode,
  `window.history.pushState({}, "", "/inbox")` without calling `noteNavLocation`, then render with
  `nav.pathname = "/inbox"`; the episode stops (no 30 s stall).

In `nav-pending-store.test.tsx` add one case: `noteNavLocation()` returns `true` after the location
changed and `false` on a repeat call.

1.2 **GREEN (production, RC3).** In `nav-pending-store.ts` make `noteNavLocation()` return `boolean`
(true iff the current `pathname+search` differs from the previously noted location; it still
updates `lastLocation`). In `nav-pending-island.tsx` the commit-watcher effect becomes
`const moved = noteNavLocation(); const first = prevKey.current === null; const changed = first ? moved : prevKey.current !== key; prevKey.current = key; if (changed) stopNavPending();`
where `key = pathname + "?" + searchParams.toString()` and `prevKey` is a `useRef<string | null>(null)`.
Put the invariant in a comment next to the effect: the first run compares against the store's
last noted location (a commit that landed before mount still stops the episode), later runs compare
the hook values with the previous key (the existing island tests move the mocked hooks, not
`window.location`), and a "skip the first run" flag is wrong because StrictMode double-invokes
effects. This was measured with the change applied temporarily to the working tree: 0 of 60 red
(see Research Insights).

1.3 **e2e restructure (RC1, RC2).** In `nav-states-nav-pending.e2e.ts`:

- add `holdNavFetch(page, pattern)` returning `{ requested, release }`: same prefetch-abort and
  non-RSC `fallback()` rules as `delayRoute`, but the nav fetch is held on a gate the test
  releases, and `requested` resolves when the held fetch arrives. Reuse it for the "never
  commits" test (it already hand-rolls a gate) so there is one hold mechanism for bar tests.
- add ONE helper, `clickNavLink(page, link, hold)`, that every bar test uses: (1) wait until the
  React props key (`__reactProps$…`) on `link`'s element carries an `onClick` function
  (`page.waitForFunction`; the timeout message says "React props key not found: the hydration
  probe may need updating for this React version"), (2) `link.click()`, (3) `await hold.requested`.
  The probe is deterministic: React attaches the internal props key to a DOM node only when it
  hydrates it (measured: no key with all JS held, key with `onClick` after release), and
  `next/link` puts `onClick` there. A pre-hydration click would never request the fetch, so a
  future edit that bypasses the helper fails loudly instead of flaking. No blind sleep.
- "NavLink click" test: install the hold before `gotoDash`; `clickNavLink`; then
  `await expect(BAR).toBeVisible()`, the `LIVE` assertion, `hold.release()`, and the URL and
  `toHaveCount(0)` assertions as today. **Delete** the post-click `await expect(BAR).toHaveCount(0)`
  (RC2). The "no bar under the entry delay" claim is covered deterministically at unit level
  (`nav-pending-store.test.tsx`: "opens pending at start() but stays invisible through the entry
  delay" and "a commit inside the entry delay produces no visible flash"); say so in a comment.
- "never commits" test: same `holdNavFetch` and `clickNavLink`.
- `delayRoute` stays for the back-nav test that still uses it (do not widen scope).
- Add the stress recipe as a header comment in the spec (`--repeat-each=30 --retries=0`, and
  `taskset -c 2,3` plus busy loops) so a future flake investigation does not rediscover it.

1.4 **Verify (PR-body evidence, not an acceptance criterion: it is not reproducible in CI).** From
`apps/web-platform`: `npx playwright test e2e/nav-states-nav-pending.e2e.ts --project=authenticated --retries=0 --repeat-each=30`
reports 0 failures on an idle box and under CPU contention (`taskset -c 2,3` plus three busy
loops); record the counts next to the baseline rates above.

### Phase 2 — Issue tracking (done during planning)

- #9678 filed (the collector partial gap; closes via the soak follow-through, not at merge).
- #9679 filed (GitHub `partial`/`auth` residual).
- No open `code-review` issue touches any planned file (checked, see Open Code-Review Overlap).

### Phase 3 — Collector compact mode (plugins/soleur/skills/community/scripts)

Contract: when `SOLEUR_COLLECTOR_COMPACT=1`, each command prints ONE line of compact JSON built by
a projection of its normal output; unset or any other value leaves output byte-identical. Failure
semantics are unchanged (the projection runs inside the same pipeline; a `jq` failure is a non-zero
exit, recorded by the GitHub sidecar).

Add a small `_emit_compact <jq-filter>` helper in each script (stdin to stdout; `jq -c` when
`${SOLEUR_COLLECTOR_COMPACT:-}` is `1`, `cat` otherwise; both scripts run under `set -u`; a non-empty
value other than `1` prints one stderr warning and leaves output unchanged, so a typo is visible).
Pipe each command's final output through it, including the discussions "not enabled" early
`echo` return. Caps are constants at the top of each script (`COMPACT_MAX_ITEMS=40`,
`COMPACT_TITLE_MAX=60`) passed to `jq` with `--argjson`.

| Command | Compact output (fields the prompt reads, nothing else) |
|---------|--------------------------------------------------------|
| `discord guild-info` | `{"approximate_member_count":N}` |
| `discord members` | `{"count":N}` (not called by the prompt, which a test pins; unbounded today, so it is projected for safety) |
| `discord channels` | `{"count":N,"channel_ids":[first 40 ids]}` (count stays exact so ">40 channels" is still detectable) |
| `discord messages <id> 50` | `{"count":N}` (bodies, authors, attachments dropped) |
| `github repo-stats` | `{"stargazers_count","forks_count","subscribers_count","new_stargazers_count","stargazers_unavailable"}` (no `new_stargazers` login list) |
| `github activity` | `{"issues":{"count":N,"titles":[<=40 titles, each <=60 chars]},"pull_requests":{...same}}`; items are sorted by `updated_at` descending inside the filter before the slice, so "newest" does not depend on API ordering |
| `github contributors` | `{"commit_total":N}` (sum of the existing `commit_authors[].commits`; logins dropped) |
| `github discussions` | `{"titles":[<=40 titles, each <=60 chars]}` (not-enabled case: `{"titles":[]}`) |
| `github fetch-interactions` | `{"external_contributors":M,"interactions_count":N}` (M = distinct `user`, N = list length; computed in the collector, no logins reach the model) |

Worst-case budget (measured with synthetic fixtures): `activity` at 100 issues + 100 PRs with
256-character titles is 77,599 bytes compact / 93,456 pretty today (over the 30,000 limit on its
own); the projection is 5,959 bytes. The GitHub chain's worst case sums to roughly 9 KB (work
records the measured figure and pins the test ceiling about 25% above it, never a rounder
guess), Discord calls are under 1 KB each (a 60-channel guild's `channels` output is 41,932 bytes today and 219 bytes
compact). Topic counts are therefore computed over the newest 40 titles per list; `count` fields
stay exact.

### Phase 4 — Handler flag and prompt (apps/web-platform/server/inngest/functions/cron-community-monitor.ts)

4.1 Add `SOLEUR_COLLECTOR_COMPACT: "1"` to the existing `buildSpawnEnv` wrapper next to
`SOLEUR_COLLECTOR_STATUS_DIR` (the wrapper stays an additive, non-secret, non-`process.env`
extension). The agent cannot set it itself: the containment hook denies `NAME=value` prefixes.
4.2 Update `COMMUNITY_MONITOR_PROMPT` text where it names collector fields: Discord (`channels` is
`count`, ids in `channel_ids`; `messages` is the sum of each call's `count`), GitHub
(`commits` is `commit_total`; `externalContributors` is `external_contributors`;
`externalInteractions` is `interactions_count`; topics classify only the listed titles, newest
40 per list). Field names that did not change (`approximate_member_count`,
`stargazers_count`, `forks_count`, `subscribers_count`, `new_stargazers_count`,
`stargazers_unavailable`, `issues.count`, `pull_requests.count`) stay. **Keep** the
"truncated or exceeds the inline limit ... output-too-large" rule as the residual fallback (the
existing prompt test asserting it stays green). No `bash ...` span changes, so the hook's
exact-literal allowlist and `cron-community-monitor-prompt-grammar.test.ts` are untouched.
4.3 Tests updated/added in `apps/web-platform/test/server/inngest/`: in `cron-community-monitor.test.ts`,
the wrapper test asserts the literal `SOLEUR_COLLECTOR_COMPACT: "1"` inside the matched wrapper (a
bare key-presence check would pass for `"0"`), the "defines the GitHub external counts" test is
rewritten to the new sentences (`external_contributors`, `interactions_count`, `commit_total`), and
the `output-too-large` rule stays asserted. A new `cron-community-monitor-compact-parity.test.ts`
(Guard 1) runs both collectors, GitHub through the existing `gh` stub shape and Discord through a
PATH-shim `curl`, so no new bash suite or shard-table row is needed for Discord.

### Phase 5 — Documentation (architecture decision, in this PR)

- ADR-273: append `## Addendum (2026-10-07): compact collector mode` stating the decision (collectors project to
  prompt-read fields under a handler-set flag; no file tools, no schema change), updating the Spike S3
  paragraph's "accepted" wording, and recording the Alternatives (file handoff, raised cap, handler-side
  metrics) with why each was cut. Status line unchanged.
- Runbook `cloud-scheduled-tasks.md` paragraph "A Discord day that shows `partial` with cause
  `output-too-large`": rewrite to the new reality (now only a genuine collector overrun; where to
  look; the follow-through probe).

### Phase 6 — Follow-through and PR

- `scripts/followthroughs/community-collectors-collected-9678.sh` (soak probe, exit 0 PASS / 1 FAIL /
  other TRANSIENT). It derives its own cut-off from the date of the commit on `origin/main` that
  introduced `SOLEUR_COLLECTOR_COMPACT` in `cron-community-monitor.ts` (`git log -S`), so nobody
  edits a directive after deploy; the directive's `earliest=` is the filing date, per
  `followthrough-convention.md`. It reads the newest `knowledge-base/support/community/*-digest.md`
  dated after the cut-off; TRANSIENT when none exists (liveness control: a digest must exist after
  the deploy). FAIL only when the Discord or GitHub row carries `output-too-large`; a Discord row
  that is `partial` for another cause, or any quiet-day oddity, is TRANSIENT, not FAIL, so one
  unrelated bad day cannot file a false regression. PASS needs two consecutive digests with Discord
  `collected` and no `output-too-large` on either row. A `--status-line` arm (always exit 0; prints
  `discord=<status> github=<cause-or-status>`) exists because preflight Check 10 treats a non-zero
  exit as a failed probe, and the real arm exits 1 before the deploy. Add the
  `<!-- soleur:followthrough script=... earliest=<filing date> -->` directive and the
  `follow-through` label to #9678 per the Soak row. No separate `.test.sh`: the script is a
  two-row grep; its PASS/FAIL/TRANSIENT arms are exercised once against two synthetic digests
  inside the compact parity test.
- PR body: `Closes #9666`, `Ref #9678` (the sweeper closes it after the soak), `Ref #9679`, and the
  Phase 1.4 before/after counts. A `Closes #9678` would close the tracker before the effect is
  observable, which `wg-use-closes-n-in-pr-body-not-title-to` carves out.

## Files to Edit

- `apps/web-platform/e2e/nav-states-nav-pending.e2e.ts`
- `apps/web-platform/components/nav/nav-pending-island.tsx`
- `apps/web-platform/lib/nav-pending-store.ts`
- `apps/web-platform/test/nav-pending-island.test.tsx`
- `apps/web-platform/test/nav-pending-store.test.tsx`
- `plugins/soleur/skills/community/scripts/github-community.sh`
- `plugins/soleur/skills/community/scripts/discord-community.sh`
- `plugins/soleur/skills/community/test/github-community.test.sh`
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`
- `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-273-schema-constrained-handler-side-publication.md`
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` (rewrite the `output-too-large` paragraph; add how to see what the agent saw: `SOLEUR_COLLECTOR_COMPACT=1 bash plugins/soleur/skills/community/scripts/<platform>-community.sh <command>`)

## Files to Create

- `apps/web-platform/test/server/inngest/cron-community-monitor-compact-parity.test.ts`
- `scripts/followthroughs/community-collectors-collected-9678.sh`

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` (200 issues) against every path in the two lists above; no body names any of them.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-273** with an addendum (not a new ADR): the decision is the compact collector mode and the
reversal of its Spike S3 "accepted partial" wording. Task: Phase 5.

### C4 views

No C4 impact. Checked against all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`:
external human actors (Discord and GitHub community members whose content the collectors read) are
unchanged; external systems Discord (`discord`), GitHub (`github`) and Anthropic (`anthropic`) are
already modeled and no edge is added (collectors still read the same sources; the model still
receives collector output through the same agent call); the data store touched is the ephemeral
workspace / KB digest path already covered by the `api -> kb` edge ("committed bytes are
handler-rendered from a validated closed-schema draft"); no actor-to-surface access relationship
changes. `plugins/soleur/test/c4-count-parity.test.sh` passes (13/13) on the unmodified tree and no
derived count (workflows, monitors, heartbeat slugs) changes here.

### Sequencing

The ADR addendum describes shipped behavior and lands in this PR.

## Observability

```yaml
liveness_signal:
  what:            the published digest row for Discord and GitHub (status and failureCause), plus the existing scheduled-community-monitor Sentry cron check-in
  cadence:         daily (the cron's schedule)
  alert_target:    #9678 follow-through tracker comment on FAIL; existing Sentry cron monitor for run liveness
  configured_in:   scripts/followthroughs/community-collectors-collected-9678.sh; apps/web-platform/infra/sentry/cron-monitors.tf (unchanged)
error_reporting:
  destination:     existing Sentry project via reportSilentFallback (op collector-status-failed for a github projection failure)
  fail_loud:       a projection (jq) failure is a non-zero collector exit; the GitHub sidecar records it and the handler pages; the Discord surface has no sidecar (pre-existing), so its failure shows as a `failed` row
failure_modes:
  - mode:          compact output still exceeds the inline limit (a caps regression)
    detection:     digest row cause output-too-large; follow-through probe FAIL; CI worst-case budget test fails first
    alert_route:   tracker comment on #9678; CI
  - mode:          the flag is not propagated into the spawn env (full pretty output again)
    detection:     handler test pins the wrapper keys; digest row output-too-large; follow-through FAIL
    alert_route:   CI; tracker comment
  - mode:          prompt and collector field names drift (model reads a missing field and reports 0)
    detection:     parity test (Guard 1) in CI; a collected platform whose every value is 0 is already shown as unverified by the handler
    alert_route:   CI
logs:
  where:           Better Stack (SOLEUR_COMMUNITY_DIGEST_FILE marker: verdict, present, writer) and the committed digest file
  retention:       digest files are permanent in git; Better Stack per the existing plan
discoverability_test:
  command:         bash scripts/followthroughs/community-collectors-collected-9678.sh --status-line
  expected_output: discord=
```

Surface note (blind cron worker, plan 2.9.2): the discriminating in-surface signal is the agent's own
per-platform status and cause as rendered by the handler (one row distinguishes "cap exceeded"
from "collector failed" from "auth"); a sidecar size field was considered and cut because output is
bounded by construction and by the CI worst-case test.

## Guard Contract

### Guard 1 — compact projection budget and prompt/collector parity

**Property.** In compact mode, the GitHub chain (the five commands run in ONE Bash call, so the limit applies to their concatenated output) and every Discord call stay well under the 30,000-character inline limit on worst-case inputs, and every compact field name the prompt reads exists in the collector projection (and vice versa).

**Assembly.** The projection filters in `github-community.sh` (5 commands) and `discord-community.sh` (4 commands, nine in total) are the only producers; the prompt in `cron-community-monitor.ts` is the only consumer; the spawn env wrapper is the only place the flag is set. Chokepoint: `_emit_compact` in each script. The budget test derives the command list from each script's dispatch `case`, not a hand-written list, and exempts nothing silently (`members` is projected too).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Raise `COMPACT_MAX_ITEMS` to 100 and `COMPACT_TITLE_MAX` to 256 | worst-case budget test RED (concatenated chain above the pinned ceiling) |
| 2 | Remove the `_emit_compact` pipe from one command (e.g. `discussions`, or the early not-enabled return) | budget/shape test RED for that command (it asserts every dispatched command emits a compact one-line object) |
| 3 | Add a tenth command to a dispatch `case` with no projection | the derived-from-source command list picks it up and the shape test is RED |
| 4 | Rename `commit_total` (or any field) in the script only, or in the prompt only | parity test RED (every compact field the prompt names must appear in the scripts, and the numeric caps 40 and 60 must match the prompt text) |
| 5 | Set the handler flag to `"0"`, or remove it | handler test RED (it asserts the literal `SOLEUR_COLLECTOR_COMPACT: "1"` inside the wrapper) |
| 6 | Must-PASS row (differs from the worst-case fixture): titles shorter than the caps and counts below 40 | passes, with every `count` equal to the default-mode count (the projection does not reject small inputs and does not alter counts) |
| 7 | Sort-order row: feed `activity` items in ascending order | the first 40 titles are the newest by `updated_at` (selection does not depend on API order) |

## Acceptance Criteria

### Functional Requirements

- [ ] The two RED island tests fail on `main` and pass after Phase 1.2 (RED then GREEN recorded in the work log); the GREEN-guard test and the new store case pass on both sides.
- [ ] `nav-states-nav-pending.e2e.ts` passes on the authenticated project in CI, with no `retries`, `timeout` or blind-sleep change anywhere in the diff (no new `waitForTimeout`), and the bar tests reach the click only through `clickNavLink`.
- [ ] Default-mode collector output is byte-identical to `main` for all nine commands (existing `github-community.test.sh` assertions pass unchanged; the parity test adds a golden comparison for the four Discord commands).
- [ ] With `SOLEUR_COLLECTOR_COMPACT=1`, worst-case synthetic fixtures (100 issues + 100 PRs with 256-character titles, 50 discussions, 100 external comments, 60 channels, 50 messages of 400 characters) produce single-line JSON; the concatenated GitHub chain is at most 1.25 times the measured figure recorded in the test (roughly 9 KB expected), far below 30,000; every Discord call is under 1,000 bytes; every `count` field equals the default-mode count.
- [ ] Compact output contains no login, message body, comment snippet or URL from the fixtures (assert absence of the fixture login prefix and body marker).
- [ ] `cron-community-monitor.test.ts`: the spawn wrapper contains the literal `SOLEUR_COLLECTOR_COMPACT: "1"` and `SOLEUR_COLLECTOR_STATUS_DIR`, no `process.env`, no credential; the prompt names every compact field it reads; the `output-too-large` fallback sentence is retained.
- [ ] `cron-community-monitor-allowlist.test.ts` and `cron-community-monitor-prompt-grammar.test.ts` pass unchanged (no allowlisted command changed).
- [ ] After the first scheduled run following the deploy, the Discord row is `collected` and neither row carries `output-too-large` (verified by the follow-through probe, which closes #9678).

### Non-Functional Requirements

- [ ] Posting credentials, the `buildSpawnEnv` allowlist, the containment hook, `--allowedTools`/`--disallowedTools`, the closed schema and the publication module are untouched: `git diff origin/main...HEAD --stat` shows no change under `_cron-community-publication.ts` or `_cron-claude-eval-substrate.ts`, and the only `cron-community-monitor.ts` hunks are the one env key and prompt text.
- [ ] No new Sentry noise: a clean compact run adds no event.
- [ ] NFR register assessment run (`soleur:architecture assess`) for the ADR-273 addendum.

### Quality Gates

- [ ] `bash plugins/soleur/skills/community/test/github-community.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh`, vitest for the touched and new `apps/web-platform/test/**` files, `./node_modules/.bin/tsc --noEmit` from `apps/web-platform`, and `markdownlint-cli2` on the plan, tasks and ADR all green.
- [ ] No new bash suite is added, so no `scripts/suite-durations.tsv` / `scripts/suite-shard-legs.tsv` change is needed; if work adds one anyway, register it under both key forms (full path for `plugins/**/test/*.test.sh`, stem for `scripts/followthroughs/*`) and run `lint-orphan-test-suites.sh` once the file is tracked.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a link click lands after hydration but before the watcher mounts, when the island mounts, then the episode is still pending and the bar appears after the entry delay.
- Given an episode started under React StrictMode, when effects double-invoke at mount, then the episode is not cancelled.
- Given a held nav fetch and a hydrated link, when `clickNavLink` runs, then `hold.requested` resolves and the bar is visible until `release()`.
- Given worst-case fixtures and `SOLEUR_COLLECTOR_COMPACT=1`, when each collector command runs, then output is one JSON line within budget with exact counts.

### Regression Tests

- Given a commit landed before the watcher mounted, when it mounts, then the episode stops (GREEN guard).
- Given the flag unset, when any collector runs, then output equals the pre-change golden bytes.
- Given two synthetic digests, when the follow-through probe runs, then PASS needs two consecutive digests without `output-too-large`, FAIL names `output-too-large`, and a digest-less checkout is TRANSIENT.

### Edge Cases

- Discord guild with more than 40 channels: `count` reports the true number, `channel_ids` holds 40, the prompt's existing "more than 40 channels" partial/timeout rule still triggers.
- GitHub discussions not enabled: compact `{"titles":[]}`.
- A fetch failure in compact mode keeps the existing exit code and sidecar record.
- Titles containing multi-byte characters: truncation is character-based (`jq` string slicing), not byte-based.
- Flag set to a value other than `1` (a typo): one stderr warning, output unchanged.

### Integration Verification (for `soleur:qa`)

- **e2e:** `cd apps/web-platform && npx playwright test e2e/nav-states-nav-pending.e2e.ts --project=authenticated --retries=0 --repeat-each=30` expects `30 passed` per test.
- **Collector (hermetic, no network):** the compact cases added to `github-community.test.sh` (PATH-shim `gh`) and the parity test (PATH-shim `curl`).
- **Post-deploy:** `bash scripts/followthroughs/community-collectors-collected-9678.sh --status-line` prints `discord=collected github=...` without `output-too-large`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI test determinism, a small client-island fix and internal data plumbing for an existing cron. The digest's reader-facing format does not change (same table, same labels); the GitHub `auth` label is unchanged and tracked in #9679. GDPR gate not invoked: the change narrows an existing processing activity (less third-party text reaches the model) and adds no data class, store, schema or API route (#7124 stays open).

## Dependencies & Risks

- **RC3 fix touches client code on the critical path of every navigation.** Mitigation: three unit tests, existing island suite unchanged, the first-run rule falls back to the old behavior whenever the location actually moved.
- **`__reactProps$` is React-internal.** The probe depends on a long-lived internal key prefix (present in React 18 and 19, which `next@16` bundles); it is isolated in `clickNavLink`, and a React upgrade that renames it makes the helper time out with a message naming the probe, instead of passing vacuously. Re-check it when `react` is bumped.
- **Topic counts are over the newest 40 titles per list.** Documented in the prompt; `count` fields stay exact; the schema's topic counts were never exact measurements (they are model classifications).
- **GitHub stays `partial` / `auth`** until #9679 is resolved; the soak probe is written to not conflate the two.
- **Handler wording:** the handler forces the GitHub row to `partial` / `auth` only when the model reports GitHub as `collected` (the `githubOverride` branch), so a model-reported `partial` / `output-too-large` row survives and the soak probe stays meaningful.
- **The e2e dev server dies mid-run in some local environments** (observed: `ERR_CONNECTION_REFUSED` after several tests on one local session); that is a local environment effect, not part of #9666, noted so the verification runs are read correctly.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this plan fills it.
- No `waitForTimeout` is added anywhere; readiness is the React props probe and `hold.requested`.
- The projection runs in the same pipeline as the command; do not `|| true` it, or a projection failure becomes a quiet empty output (the exact silent-zero class the sidecar exists to prevent).
- When the prompt text changes, update `cron-community-monitor.test.ts` assertions that match old field sentences (`DISTINCT \`user\` values`, commit-sum sentence) in the same commit.
- Any new `*.test.sh` suite must be registered in both suite tables or the shard check fails (this plan adds none).

## References

- Issues: #9666, #9678 (filed here), #9679 (filed here), #7124, #9606 (sibling generalization, out of scope)
- PRs: #9676 (this draft), #9596 / `ed6083309f` (publication change), #9652 (read-only stargazer degradation)
- ADR-273, ADR-255 (nav-pending channels), `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
- Code: `apps/web-platform/components/nav/nav-pending-island.tsx`, `apps/web-platform/lib/nav-pending-store.ts`, `apps/web-platform/e2e/nav-states-nav-pending.e2e.ts`, `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`, `plugins/soleur/skills/community/scripts/{github,discord}-community.sh`
