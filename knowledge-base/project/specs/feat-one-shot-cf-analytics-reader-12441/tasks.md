# Tasks: Cloudflare analytics reader (Ref #12441, Ref #10479, Ref #10205)

Plan: `knowledge-base/project/plans/2026-11-09-feat-cloudflare-analytics-reader-subcommand-plan.md`
Rulings: `knowledge-base/project/specs/feat-one-shot-cf-analytics-reader-12441/decision-challenges.md`
Hard limits: no production write, dispatch, apply, merge, arm or mark-ready; no live run of the branch wrapper before merge without the owner's typed per-command go naming the exact command; `Ref` only, `closingIssuesReferences` must be `[]`; `prepush-secret-scan.sh` before every push; no credential value is minted, read, printed or committed.

## Phase 0: Prerequisites (no repository change)

- [x] 0.1 Re-run the baseline `bash plugins/soleur/test/cloudflare-readonly.test.sh`: expect `1038 passed, 0 failed` and 108 of 108 mutation rows
- [x] 0.2 Real-curl proof (local loopback only, `python3 -I` one-shot listener): the exact config lines `cf_graphql` will build (`data-raw`, backslash then double quote escaped) deliver the body byte-exactly; record a `Checked:` line; on failure fall back to argv `--data-raw` and add a superseding CTO row
  - Checked: 2026-11-09 real `/usr/bin/curl` 8.23.0 against a one-shot `python3 -I` loopback listener (127.0.0.1 only, no Cloudflare traffic): a stdin config with `header` x2 and `data-raw` (backslash then double quote escaped) delivered the 299-byte query body byte-for-byte equal (`cmp`), method POST, Content-Type application/json; no fallback needed
- 0.3 PR body asks the owner to diff both query templates against the query they ran (the proven query text was not found in #12441, #10479 or PR 12434)

## Phase 1: Tests first (RED) in `plugins/soleur/test/cloudflare-readonly.test.sh`

- [x] 1.1 Take RED evidence from `CF_RO_GROUPS=<groups>` runs (the pristine control fails while RED and voids the battery); mutation rows are authored in RED and first validated after GREEN; run the instrument control once per distinct group-set
- [x] 1.2 Stub: compute `url` first; `-X GET` refused for the GraphQL URL; `-X POST` only for it; POST stdin has exactly Authorization, Content-Type and `data-raw` lines
- [x] 1.3 Wire: parameterise `check_wire` by vector (`EXP` / `EXP_POST`); controls (duplicated `-X`, glued `-XPOST`, no URL); keep the one-line-stdin row on the GET subcommands only
- [x] 1.4 `env -i` on every `"$CURL"` site: per-site census equals site count; `env[analytics]` row
- [x] 1.5 Body rows: fixed prefix, single line, zone equals env, stamps match `STAMP_RE`, `end` on the hour, `end - start` equals H*3600, masked body equals the constant, H=1 and H=216 only, hostile zone id refused, static no-`mutation`/`subscription`/`__schema` row; templates duplicated once in one marked block
- [x] 1.6 Clock: fakedate seam, `10#$t`, `[ -x /usr/bin/date ]` preflight exit 14, bad stamp exit 64
- [x] 1.7 Token binding rows (only old tokens set, only analytics token set, planted `CF_API_TOKEN`, 401/403 mirrors)
- [x] 1.8 Grammar rows (0, 217, -1, 07, 1.5, empty, extra, missing, unicode digit, `5` plus newline, old subcommand with a second argument, analytics with one) and the arity message text row
- [x] 1.9 Group loops: second array for the two analytics names in token, env, status, shape and tools groups (including `nodate` and `fakedate_*` variants); `SUBS` stays the four GET names
- [x] 1.10 Projection rows: 200 with errors, bounded message accept/refuse (newline, escape, 161 chars, credential words, live token, dotted quad, colon-hex), 400, `zones: []` to `no-zone-access`, two-element zones, wrong-typed or out-of-range fields, `data: null`, empty body, null duration passes, ascending order, `by_status` sums, `truncated` at 1000 (edge-errors only)
- [x] 1.11 Re-pin floors and censuses to exact new values (`-ge 108`, `-ge 400`, `PROJ_FLOOR=46`, `EXERCISED -ge 12`, refuse floor, `LEAK_NEEDLES` 13 to 14, `== 5` to 7 arm terminators, one curl site to two, `LIMIT=50` literal and `--argjson limit` text, token-variable lists, G1.4/G1.4b/G1.7/W6.9 expect-strings, non-unique mutation anchors, W4.16)
- [x] 1.12 Mutation rows from the Guard Contract (both guards)

## Phase 2: Wrapper (GREEN) in `plugins/soleur/scripts/cloudflare-readonly.sh`

- [x] 2.1 `GQL_URL`, `cf_graphql` (own call site, `/usr/bin/env -i "$CURL"`, closed POST vector, three stdin config lines), fixed-prefix and control-character pre-flight
- [x] 2.2 Two compiled-in templates (query 2 `datetimeHour_DESC`), epoch-arithmetic window, `guard_gql`, projections, `no-zone-access`, bounded `graphql:` message (token-copy check in bash)
- [x] 2.3 Arity and hours grammar through one shared `need_hours "$@"` called by each analytics arm, written with `if` or `case "$1"` (not a second `case "$SUB"`); `cf_graphql` calls `preflight()`; six `SUBCOMMANDS`; two dispatcher arms; `CF_API_TOKEN_ANALYTICS_READ` in the xtrace list; `--list`
- [x] 2.4 `project()` takes a per-query limit through its own `--argjson` name
- [x] 2.5 Header: subcommands, token binding, POST exception paragraph, message departure, unverified list (status dimension, range operators, `_DESC`), Records F and G with the reason-to-next-action table, expiry 2027-02-07, terse
- [x] 2.6 Run the suite to green; sweep `anchor matched 2 times`; scoped census `git grep -n -i -w -E 'four|4' -- <the five subject files>` (classify every hit; exempt the ADR-289 historical addenda); confirm `cto.md` does not enumerate subcommands

## Phase 3: Doc parity and records

- [x] 3.1 `standing-delegation.md` section 9: apply the CLO text from `knowledge-base/project/specs/feat-one-shot-cf-analytics-reader-12441/clo-ruling-text.md` (sections A, B, C) without re-wording
- [x] 3.2 `components.test.ts`: six-name slice, five-token set equality, PAIRS rows, REQUIRED and clause `GET only` markers, new pins, `VENDOR_SENTENCE`, `hostTokens` host set, polarity test re-run
- [x] 3.3 ADR-289 addendum `## Addendum 2026-11-09 (Ref #12441, #10479, #10205)` (CLO text from `clo-ruling-text.md`, with the CLO message sentence); append 12441 to `related:`; no pointer key
- [x] 3.4 `bun test plugins/soleur/test/components.test.ts`, the cloudflare suite, `bash plugins/soleur/test/c4-count-parity.test.sh`

## Phase 4: Runbook addendum (append-only)

- 4.1 Insert the addendum before `#### What was NOT run before the flip`; first line "Read this first" naming the superseded paragraph and row by anchor text; owner-supplied figures labelled; no cause claimed
- 4.2 5xx row `not yet read; first sanctioned read after merge` with the exact command; caveats; median jq one-liner with named input and `--arg lo/hi`; handoff block and reason-to-action table; evidence path `knowledge-base/engineering/operations/runbooks/evidence/<UTC date>-analytics-health-216h.json` (committed only post-merge)
- 4.3 Live-verify: one bounded CI-log re-derivation attempt (20 runs, `timeout 60`, `grep -a -m1`, `cut -c1-260`); record `Checked:` with run id or the owner-supplied wording with the count searched
- 4.4 WebSocket 101: both timestamps, neither reconciled, not a signed-in check
- 4.5 Verify `git diff --stat` shows additions only in the runbook

## Phase 5: Learning and Playwright guidance

- 5.1 New learning under `knowledge-base/project/learnings/` (top level; the author dates the filename) on the Playwright zip-extractor stall under Node 26 and the Bun install
- 5.2 One-line note in `plugins/soleur/skills/agent-browser/SKILL.md` and in `plugins/soleur/skills/qa/references/browser-preflight.md`

## Phase 6: Verify and open the PR (stop there)

- 6.1 Run the suites, markdown lint, `technical-ruling-gate.sh` on `decision-challenges.md`
- 6.2 `prepush-secret-scan.sh`, push, update the draft PR #12515 body (`Ref` only; `closingIssuesReferences` is `[]`; four owner-review items; descoped 5xx histogram first; justification lines for any filed issue, none expected)
- 6.3 Comment on #12441 with the expiry date 2027-02-07 and the post-merge handoff
- 6.4 After GREEN measure the suite wall time and update `scripts/suite-durations.tsv` through `scripts/regenerate-shard-manifest.py` (`--allow-growth` if needed)
- 6.5 Run the review panel; do NOT mark ready, arm auto-merge or merge

## Post-merge (after the owner's typed go on the merge; tracked by #12441)

- P.1 From a fresh checkout with `git diff origin/main -- plugins/soleur/scripts/cloudflare-readonly.sh` empty, run both subcommands at 216 hours; record `Checked:`/`Unverified:`; append a SECOND dated addendum with the 5xx histogram (never edit the first addendum's `not yet read` row); commit the evidence files only on exit 0, line 2 only (line 1 must equal `cloudflare-readonly: <sub> ok`, line 2 must parse with `jq -e .`, no stderr); at most two fix PRs in total across both queries
