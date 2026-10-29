---
title: "fix: xtrace refusal for content-publisher.sh + Discord blog webhook fallback verification probe"
type: fix
date: 2026-10-29
slug: fix-xtrace-refusal-fallback-probe
branch: feat-one-shot-11532-xtrace-guard-fallback-probe
issue: 11532
closes: 11532
lane: cross-domain
---

# fix: xtrace refusal for content-publisher.sh + Discord blog webhook fallback verification probe

## Enhancement Summary

**Deepened on:** 2026-10-29
**Sections enhanced:** Probe contract, Encryption Posture, Acceptance Criteria (verified live)

### Key Improvements
1. deepen gates all green in-process: User-Brand Impact (4.6), Observability (4.7 — allowlisted verb, literal `expected_output`, <15s), PAT sweep (4.8 — clean), Encryption Posture (4.10), Guard Contract lint (4.11 — 2 entries), Scope Check (4.12 — 1 unfenced, all rows mapped/justified), Task-Design (4.13 — detection table does not fire: probe rides the existing sweeper).
2. Live-verified prescribed GitHub objects: labels `follow-through` + `meta/machinery` exist; milestone `Post-MVP / Later` exists; issue #11532 OPEN; PR #11543 draft on this branch; commit `347d3812` on main.
3. `at_rest: []` — no persistent store; only in_transit (probe → de.sentry.io, TLS + cert verification on) is declared.

### New Considerations Discovered
- `scripts/content-publisher.sh` is baselined in `lint-shell-trace-credential-refusal.baseline.txt` — the fix must delete its row (drawdown) or the violation stays suppressed.
- The lint's `referenced_credentials` includes `LINKEDIN_TRACKER_REASON_MISSING_TOKEN` (in-file constant) — must appear in the refusal's `${VAR:+x}` limbs for Rule C coverage.
- `scripts/followthroughs/*.test.sh` is not glob-discovered: explicit `run_suite` registration + `regenerate-shard-manifest.py --incremental --write` rows are the registration contract.

Close out the deferred verification + lint follow-ups from the Discord blog→general
webhook fallback feature that merged 2026-10-29 as squash commit `347d3812` (cite the
merge by date/SHA only — never as `#11504`, per operator direction).

Three deliverables, one PR (#11543, draft, this branch):

1. **#11532** — `scripts/content-publisher.sh` binds live credentials but lacks the
   `case "$-" in *x*) ... exit 78` xtrace refusal; the advisory
   `lint-bot-statuses`/`lint-shell-trace-credential-refusal` check flags it on any PR
   touching the file (`--changed` bypasses the baseline).
2. **Verification probe** — new generic-named followthrough probe
   `scripts/followthroughs/discord-blog-webhook-fallback.sh` (precedent for a
   number-free probe name: `scripts/followthroughs/post-deploy-incident-soak.sh`,
   ADR-298) that proves the first post-secret publish emitted no
   `SOLEUR_PUBLISHER_FALLBACK` marker / no Sentry `op=discord-blog-webhook-fallback`
   event, plus its `.test.sh` harness and runner registration.
3. **Tracker issue** — `gh issue create --label follow-through --label meta/machinery
   --milestone "Post-MVP / Later"` carrying the column-0 `soleur:followthrough`
   directive; the PR body references it as `Ref #N` (never `Closes`).

## Research Insights

**Premise Validation (Phase 0.6, run 2026-10-29).** Held: issue #11532 is OPEN,
title `fix(scripts): content-publisher.sh binds live credentials without xtrace
refusal (#7797 pattern)`; PR #11543 is OPEN/draft on this branch; squash commit
`347d3812` exists on main; `scripts/content-publisher.sh:36` carries
`set -euo pipefail` and no `case "$-"` block (grep confirms absent);
`scripts/followthroughs/cron-machinery-soak-9272.sh:33-46` is the verbatim idiom
source; `scripts/lint-shell-trace-credential-refusal.py` is the flagging lint and
`scripts/content-publisher.sh` sits in its `lint-shell-trace-credential-refusal.baseline.txt`
(drawdown contract: "any PR that edits a listed script must remediate it");
`scripts/sweep-followthroughs.sh` runs probes under `env -i` from a checkout of
main; `.claude/hooks/follow-through-directive-gate.sh` resolves `script=` under
`$HOOK_CWD` (the Bash call's `.cwd`, so `gh issue create` run FROM THIS WORKTREE
resolves inside the worktree — the convention doc's "main checkout" caveat applies
only to sessions whose CWD is the main checkout); both `GH_TOKEN` and
`SENTRY_ACTIONS_RO_TOKEN` are already wired in
`.github/workflows/scheduled-followthrough-sweeper.yml:110,124` (no workflow edit
needed); `knowledge-base/marketing/distribution-content/2026-11-03-first-property-test-found-real-bug.md`
exists with `status: scheduled`, `publish_date: 2026-11-03`, `channels: x, bluesky,
discord, linkedin-personal`; the Sentry event shape is `feature: "cron-content-publisher"`,
`op: "discord-blog-webhook-fallback"`, message
`"DISCORD_BLOG_WEBHOOK_URL unset in publisher env — …"` at
`apps/web-platform/server/inngest/functions/cron-content-publisher.ts:736-742`.
Stale: none. Collision precheck: PR #11543 names #11532 — it is this pipeline's own
draft, not a duplicate. Foreign `test-all.sh` processes in other worktrees are
unrelated load.

**Property List (Phase 0.6b).** (a) No live credential bound by
`scripts/content-publisher.sh` can be traced into logs under `set -x` — the property
the lint exists to assert, closed by adding the refusal. (b) A verifiable,
time-gated close criterion exists for "the blog-webhook secret is actually live in
the publisher env" — closed by probe + tracker enrollment on the existing sweeper
substrate. (c) The sweeper can reach the probe — closed by file + executable bit +
directive `script=` + registration.

**Cut List (Phase 0.6b).** Nothing proposed: every mechanism named in the ask is an
existing repo mechanism (xtrace-refusal preamble, followthrough probe convention,
sweeper directive). No new machinery invented; nothing to cut.

**Mechanism/ADR check (Phase 0.6 item 4).** Proposed mechanisms already have ADR
backing rather than rejection: ADR-031 (`SENTRY_ACTIONS_RO_TOKEN` org-level RO
integration), ADR-202 (Rule D destination pinning + carried self-refusal), ADR-298
(generic-named soak probes), ADR-214 (destination pins never env-declared). The
probe is read-only (GET events) — no write surface.

**Relevant paths.** `scripts/content-publisher.sh` (`set` at :36, refusal belongs
immediately after; `get_frontmatter_field` at :103 is the frontmatter idiom the
probe mirrors). `scripts/followthroughs/cron-machinery-soak-9272.sh` — copy
verbatim: xtrace refusal (:35-46), `_bearer_ok` (:53), `_sentry_get` (:57-60,
`curl --disable --noproxy '*'` + bearer via stdin `--config -`), org/host pin +
refusal (:63-70), URL allowlist `case "$URL" in` (:89-92), TRANSIENT mapping.
`scripts/followthroughs/post-deploy-incident-soak.sh` — generic-name precedent,
header shape (exit contract, liveness gate, RETIREMENT line :64-67, TLS-subversion
prologue :91-96). `scripts/followthroughs/post-deploy-incident-soak.test.sh` — the
harness idiom: `env -i` + PATH-shimmed `curl`/`gh` stubs + `run_case` rc
assertions + instrument self-test. `scripts/test-all.sh` — `run_suite` explicit
registration (`scripts/followthroughs/*.test.sh` is NOT in SUITE_GLOBS).
`scripts/lint-followthrough-varq-ban.sh` — rules 1-5: no `${VAR:?}`, no
`SENTRY_AUTH_TOKEN` anywhere (retired name, banned in comments too),
repo-relative paths must exist tracked, trusted-verdict obligations, no
`author_association` on executable lines. `scripts/lib/test-affected-paths.sh` —
name-stem derivation `<x>.test.sh → <x>.sh` classifies a new suite without an
`AFFECTED_*_PATHS` array (post-deploy-incident-soak has none).
`scripts/regenerate-shard-manifest.py --incremental --write` adds the shard row.

**Applicable learnings.** `followthrough-convention.md` §Author workflow (exit-code
vocabulary: 0 PASS / 1 FAIL / 2 NOT YET / 3 CANNOT ESTABLISH / 78 xtrace; liveness
marker required before a zero-count PASS; CREDENTIAL POSTURE + RETIREMENT headers;
unfenced column-0 directive). `2026-04-22-passive-sentry-signal-closes-followthrough-verification.md`
(passive Sentry read beats an active trigger). `2026-09-25-a-fixture-suite-cannot-see-that-the-probe-can-no-longer-take-its-reading.md`
(dry-run the real sweeper on the branch before shipping the probe change).
Sharp edge applied (CTO ruling, 2026-10-29): newest-first is the observed default
but NOT a documented contract (`get_orderby` returns None when `sort` is absent),
so the events URL pins `&sort=-timestamp`; with it, `per_page=10` provably
suffices because any `timestamp >= cutoff` event ranks within the newest 10.

**CLI-verification gate.** `gh issue create` flags (`--label`, `--milestone`,
`--body-file`) and `gh issue list`/`gh pr view` are standard documented forms; the
Sentry events URL mirrors the live, in-repo `cron-machinery-soak-9272.sh:87` call
verbatim. `python3 scripts/regenerate-shard-manifest.py --incremental --write` is
the header-documented invocation in `scripts/suite-shard-legs.tsv`.

**Skill Description Budget (Phase 1.8).** No SKILL.md `description:` edits —
skipped.

## Research Reconciliation — Spec vs. Codebase

No spec exists for this branch (one-shot entered at plan). Premise validation above
covered every cited artifact; nothing inherited.

## Open Code-Review Overlap

Six open code-review issues contain `scripts/followthroughs/` or sibling paths —
all **acknowledged, no action**: #11312 (monitor_sig hook residue — different
files), #10464/#10463/#10462 (zot fill-rate probe — different probe),
#8800 (census sandbox fixture — unrelated mechanism), #8435 (gsc-indexing probe —
different probe), #7942 (`*.mutation.sh` registration — different file class),
#8881 (shard-rebalance review — our incremental row-add is exactly its prescribed
mechanism), #3649 (content scheduling — unrelated). None touches
`scripts/content-publisher.sh`, `lint-shell-trace-credential-refusal.baseline.txt`,
or the files this plan creates.

## User-Brand Impact

- **If this lands broken, the user experiences:** a missed or misrouted social
  post — the xtrace refusal can only ABORT the publisher under `set -x` (a
  debugging-only mode the cron never enables); the probe is read-only and cannot
  affect publishing.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the
  refusal exists precisely so a live credential is never traced into logs — the
  change reduces exposure; the probe queries Sentry event metadata only.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI/ops machinery; no
  user-facing artifact is created, and the publish path's behavior is unchanged on
  every non-traced invocation.
- **Scope-out override:** `threshold: none, reason: the touched credential-binding
  script is operator/CI machinery — the refusal is additive-only and cannot alter
  any non-traced execution path.`

## Files to Create

- `scripts/followthroughs/discord-blog-webhook-fallback.sh` — the probe
  (`chmod +x`); contract below.
- `scripts/followthroughs/discord-blog-webhook-fallback.test.sh` — exit-code
  harness in the `post-deploy-incident-soak.test.sh` idiom.

## Files to Edit

- `scripts/content-publisher.sh` — insert the xtrace refusal as the first thing
  after `set -euo pipefail` (:36), before `SCRIPT_DIR=` (:38). Conditional form
  (the script binds inherited env credentials; it does NOT acquire at runtime —
  `unconditional_reason` returns null, verified against the lint's own regexes).
  The `${VAR:+x}` predicate must cover EVERY name the lint's
  `referenced_credentials` reports (measured: `BSKY_APP_PASSWORD`,
  `LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_ORG_ACCESS_TOKEN`,
  `LINKEDIN_TRACKER_REASON_MISSING_TOKEN`, `X_ACCESS_TOKEN`,
  `X_ACCESS_TOKEN_SECRET`, `X_API_KEY`, `X_API_SECRET`), plus
  `DISCORD_BLOG_WEBHOOK_URL`, `DISCORD_WEBHOOK_URL`, `GH_TOKEN` — real credentials
  the lint's name regex does not match (`_URL`) or that appear only in comments;
  extra limbs are always legal under Rule C (`missing = referenced − guarded`).
  Model the block verbatim on `cron-machinery-soak-9272.sh:35-46` with a
  concatenated single-test predicate (the `post-deploy-incident-soak.sh:85`
  `${A:+x}${B:+x}` form).
- `scripts/lint-shell-trace-credential-refusal.baseline.txt` — delete the
  `scripts/content-publisher.sh` row (the file's own drawdown contract: a
  remediated file must leave the baseline or future regressions stay suppressed).
- `scripts/test-all.sh` — add, beside the other followthroughs registrations:
  `run_suite "scripts/followthroughs/discord-blog-webhook-fallback" bash scripts/followthroughs/discord-blog-webhook-fallback.test.sh`
  with the one-line rationale comment the sibling registrations carry
  (explicit registration; `scripts/followthroughs/*.test.sh` is not in SUITE_GLOBS).
- `scripts/suite-shard-legs.tsv` + `scripts/suite-durations.tsv` — regenerated by
  `python3 scripts/regenerate-shard-manifest.py --incremental --write` (one new
  row each; never hand-edited — header rule at `test-all.sh:5703`).

## Non-Goals

- No `.github/workflows/scheduled-followthrough-sweeper.yml` edit — both declared
  secrets are already in its env block.
- No `AFFECTED_*_PATHS` array unless `scripts/lint-orphan-test-suites.sh` reports
  the new registration UNCLASSIFIED (name-stem derivation covers it — verified
  against the post-deploy-incident-soak precedent, which declares none).
- No changes to the publisher's post routing, marker text, or the cron's Sentry
  mirror — verification only.
- The affected-index-ratchet stale-baseline line — already closed by an earlier
  merge; explicitly out of scope.

## Probe contract (canonical, pins the deliverable)

Header: name rationale (generic, number-free — one copy per enrollment, per
`post-deploy-incident-soak.sh`), what it proves, LIVENESS-FIRST ordering,
exit-contract table, CREDENTIAL POSTURE (`SENTRY_ACTIONS_RO_TOKEN` — org-level
read-only `actions-read-prd` integration, ADR-031; `GH_TOKEN` — declared per the
directive so `gh` MAY be used; the probe does not call `gh`), RETIREMENT line
listing back-references (this `.test.sh`, the `run_suite` row in
`scripts/test-all.sh`, `scripts/suite-shard-legs.tsv` + `scripts/suite-durations.tsv`
rows, the tracker directive `script=` body, `scripts/lib/test-affected-paths.sh`
if an edge array lands). Never the retired Sentry credential name — banned in
code AND comments by varq-ban rule 2.

Body, in order:

1. `set -uo pipefail` (no `-e` — explicit verdict exits throughout).
2. xtrace refusal (verbatim soak idiom) covering `SENTRY_ACTIONS_RO_TOKEN` +
   `GH_TOKEN` → `exit 78`.
3. TLS-subversion prologue (`unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE
   SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS`), `export LC_ALL=C`,
   `TMPDIR` default.
4. Prereqs: `command -v curl jq` else CANNOT ESTABLISH (3); `_bearer_ok` on
   `SENTRY_ACTIONS_RO_TOKEN` else CANNOT ESTABLISH (3); `ORG`/`API_HOST` pinned to
   `jikigai-eu`/`de.sentry.io` with override refusal → CANNOT ESTABLISH (3).
   NEVER `${VAR:?}` word-expansion (varq-ban rule 1).
5. **LIVENESS (runs before any credentialed read):** scan
   `knowledge-base/marketing/distribution-content/*.md` (repo-root relative — the
   sweeper runs probes from the repo root; resolve `CONTENT_DIR` from
   `BASH_SOURCE/../..` for manual runs, with a `*_CONTENT_DIR` env seam for the
   harness). Mirror `get_frontmatter_field` (`awk '/^---$/{c++; next} c==1'`,
   `grep "^<field>:"`, strip quotes). A file qualifies when `status: published`
   AND `publish_date >= 2026-10-30` (string compare is valid for ISO dates) AND
   `channels:` contains the `discord` token (word match inside the CSV value).
   Zero qualifying files → `NOT YET` → `exit 2`.
6. **Sentry:** `QUERY='feature:"cron-content-publisher" "DISCORD_BLOG_WEBHOOK_URL unset in publisher env"'`;
   `QUERY_ENC=$(printf '%s' "$QUERY" | jq -sRr @uri)`;
   `URL="https://${API_HOST}/api/0/organizations/${ORG}/events/?query=${QUERY_ENC}&statsPeriod=30d&per_page=10&field=title&field=timestamp&sort=-timestamp"`;
   pinned-URL `case` gate; `_sentry_get -w '\nHTTP_STATUS:%{http_code}' -H
   "Accept: application/json" "$URL"`; non-200 or unparseable `.data` → CANNOT
   ESTABLISH (3). Any event with `timestamp` (`fromdateiso8601`) `>=` the
   `2026-10-29T17:00:00Z` cutoff epoch → `FAIL` (1), printing title+timestamp of
   each offender. Zero → `PASS` (0).
7. Verdict emit lines in the sibling probes' shape (e.g. `PASS: <what held>`).

Harness cases (each in the post-deploy idiom — `env -i`, PATH-shim `curl`,
synthesized fixtures): no qualifying file → 2; qualifying + zero events → 0;
qualifying + in-window event → 1; qualifying + only pre-cutoff events → 0; event
at exactly 2026-10-29T17:00:00Z → 1 (inclusive bound); HTTP 500 → 3; non-JSON
body → 3; missing/bad-shaped token → 3; `SENTRY_ORG`/`SENTRY_API_HOST` override →
3; xtrace with creds → 78; stdin-config bearer asserted + never in argv;
`SUT_ARGV`/`_CONTENT_DIR` seam exercised; instrument self-test first.

## Tracker issue (deliverable 3)

Filed AFTER the probe exists+is executable on this branch, via `gh issue create`
run from the worktree (the directive gate resolves `script=` under the call's
`.cwd`). Labels `follow-through` + `meta/machinery`, milestone `Post-MVP / Later`.
Body: context paragraph (feature merged 2026-10-29 as `347d3812`;
`DISCORD_BLOG_WEBHOOK_URL` written to soleur/prd 2026-10-29T17:17:19Z; live
container env-file re-downloaded by the deploy at 17:21Z; next scheduled publish
`2026-11-03` at 14:00Z), close-criteria (the next post-secret publish emits no
`SOLEUR_PUBLISHER_FALLBACK` marker and no Sentry event for
`op=discord-blog-webhook-fallback`), and the UNFENCED column-0 directive:

```text
<!-- soleur:followthrough
  script=scripts/followthroughs/discord-blog-webhook-fallback.sh
  earliest=2026-11-03T15:30:00Z
  secrets=GH_TOKEN,SENTRY_ACTIONS_RO_TOKEN
-->
```

`earliest` = publish cron (14:00Z) + ~1.5h for the status-flip commit to land on
main — the first sweep can only run after evidence could exist.

## Observability

```yaml
liveness_signal:
  what: the probe's own verdict — sweeper posts it to the tracker issue + run log
  cadence: daily (scheduled-followthrough-sweeper, 14:00Z-class cron)
  alert_target: tracker issue comment (FAIL → comment, stays open; PASS → closes)
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml
error_reporting:
  destination: tracker issue via sweep-followthroughs.sh captured output (last 4 KB)
  fail_loud: exit 1 FAIL line naming each offending event (title+timestamp)
failure_modes:
  - mode: probe cannot measure (Sentry read/auth/parse failure)
    detection: exit 3 CANNOT ESTABLISH — sweeper retries next sweep
    alert_route: daily sweep comment on failure class
  - mode: marker still fires post-secret
    detection: Sentry events API row with timestamp >= 2026-10-29T17:00:00Z → exit 1
    alert_route: tracker issue FAIL comment
logs:
  where: sweeper workflow run log + tracker issue comments
  retention: Actions retention + issue history
discoverability_test:
  command: bash scripts/followthroughs/discord-blog-webhook-fallback.sh
  expected_output: "NOT YET CANNOT ESTABLISH TRANSIENT PASS FAIL"
```

(`expected_output` is token-matched — the probe's own verdict vocabulary covers
every arm; the command needs no credentials because LIVENESS runs before the
credentialed read, and no qualifying file exists until 2026-11-03.)

## Encryption Posture

```yaml
at_rest: []  # no persistent store introduced — the probe persists no data
  # (read-only GETs; tmp files in mktemp are deleted by the EXIT trap)
in_transit:
  - connection: probe -> de.sentry.io (GET /api/0/organizations/jikigai-eu/events/)
    enforced_at: scripts/followthroughs/discord-blog-webhook-fallback.sh — _sentry_get + pinned-URL case gate
    tls: https only, curl --proto '=https' implied by literal https:// URL; cert verification on (curl default; --disable --noproxy '*' strips ~/.curlrc and proxy redirection)
    does_not_defend: a compromised runner image or a token store elsewhere on the host
    disclosed_as: not-publicly-claimed
```

## Task Design

Not emitted — the detection table does not fire: no new `.github/workflows/*.yml`,
no Inngest `.ts`, no `CHECK_REGISTRY` key, no `cron.schedule(`, no host
`cron.d`/`.timer`, no `setInterval` daemon, no TF `github_repository_file`. The
probe is data for the EXISTING scheduled-followthrough-sweeper task surface, not a
new task.

## Guard Contract

### Guard 1 — xtrace refusal in `scripts/content-publisher.sh`

**Property.** No credential the script binds can be echoed into a trace, because
any invocation with `xtrace` already on exits 78 before the first command.

**Assembly.** Every bash invocation of the file: the preamble sits in the
prologue (Rule A — nothing but `set`/`shopt`/`readonly -x` may precede it) and
its `${VAR:+x}` predicate covers every credential name the file references
(Rule C — the lint's own `referenced_credentials`/`guarded_credentials` census).
Enforced by `scripts/lint-shell-trace-credential-refusal.py` (Rules A, B, C) run
`--changed` on the PR and repo-wide post-merge; the baseline row must drop so the
suppression dies with the violation.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete the `case "$-"` block | RED — Rule A: no xtrace refusal |
| 2 | Move the block below `SCRIPT_DIR=` | RED — Rule A: refusal not in prologue |
| 3 | Drop the `${X_API_SECRET:+x}` limb | RED — Rule C: refusal narrower than referenced set |
| 4 | Re-add `scripts/content-publisher.sh` to the baseline | the file is guarded either way — baseline coverage is verified by `--changed` ignoring it |
| 5 | Change a limb to `${X_API_SECRET:+}` (empty alternate) | RED — Rule C empty-alternate predicate can never fire |
| 6 | Suite mutation: point the lint's own `.test.sh` fixture set at a no-op copy | RED — `lint-shell-trace-credential-refusal.test.sh` pins the remedy text |
| 7 | Must-PASS: run the lint on the remediated file under `bash` with xtrace off | PASS — refusal never fires without `-x` |

### Guard 2 — probe PASS authority

**Property.** The sweeper closes the tracker only when BOTH a qualifying
post-secret publish exists AND zero in-window Sentry events were measured — a
probe that skips liveness or misreads the API must never emit 0.

**Assembly.** The probe's two ordered arms (liveness scan of
`knowledge-base/marketing/distribution-content/*.md` → Sentry events read) and
the harness's `run_case` assertions that drive every arm under `env -i`, the same
way `sweep-followthroughs.sh` invokes it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Reorder: Sentry read before the liveness scan | RED — a no-qualifying-file case must still exit 2, never reach the read |
| 2 | `exit 0` on a missing/empty Sentry `.data` | RED — unparseable body is CANNOT ESTABLISH, not PASS |
| 3 | Cutoff off-by-one (`>` instead of `>=`) | RED — the exactly-at-cutoff case must FAIL |
| 4 | Hardcode a qualifying published fixture file unconditionally | RED — the no-qualifying-file case must exit 2 |
| 5 | Drop the pinned-URL `case` | RED — varq-ban/rule-D class: credentialed call to unpinned destination |
| 6 | Suite mutation: stub `curl` to always serve an empty page | RED — the PASS case then never exercises the event-parse arm; asserted by the harness's in-window-event case going red |
| 7 | Must-PASS: a second fixture file `status: scheduled` beside the qualifying published one | PASS — scheduled files are not liveness evidence |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Fix open issue #11532 — `scripts/content-publisher.sh` binds live credentials … Fix = add the refusal as the first thing after the `set` line, modeled on the exact pattern in `scripts/followthroughs/cron-machinery-soak-9272.sh`" | Files-to-Edit entry 1 (xtrace refusal) | mapped |
| 2 | "New followthrough probe `scripts/followthroughs/discord-blog-webhook-fallback.sh` … LIVENESS first … Then Sentry … exit 2 / exit 1 / exit 0" | Files-to-Create entry 1 (probe) | mapped |
| 3 | "Idioms to copy verbatim … xtrace refusal covering SENTRY_ACTIONS_RO_TOKEN and GH_TOKEN; `_bearer_ok`; `_sentry_get`; org `jikigai-eu` / host `de.sentry.io` pinning; TRANSIENT exit 2 / CANNOT ESTABLISH exit 3; NEVER `${VAR:?msg}`; never name the retired vendor Sentry credential env-var; CREDENTIAL POSTURE and a RETIREMENT: line" | Probe contract (canonical) §Body 2-7, header | mapped |
| 4 | "Check whether sibling probes carry a `.test.sh` and whether `scripts/test-all.sh` or a manifest … registers them; match the repo's own registration pattern" | Files-to-Create entry 2 + Files-to-Edit (test-all.sh, suite-shard-legs.tsv) | mapped |
| 5 | "file the follow-through tracker issue … `gh issue create --label follow-through --label meta/machinery --milestone \"Post-MVP / Later\"` … UNFENCED, column-0 directive" | Tracker issue (deliverable 3) | mapped |
| 6 | "secrets=GH_TOKEN,SENTRY_ACTIONS_RO_TOKEN … declare only what it uses: `GH_TOKEN` is needed ONLY if the probe calls `gh`; the liveness check reads the checked-out tree so it may not need it — decide in the plan, but the directive below declares both so the probe MAY use gh if needed" | Probe CREDENTIAL POSTURE + directive secrets= (Decisions D2) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| xtrace refusal in content-publisher.sh | "add the refusal as the first thing after the `set` line" | asked |
| baseline row deletion | "the advisory `lint-bot-statuses` check (`lint-shell-trace-credential-refusal`) flags it on any PR touching the file" | inferred — justification: the file's baseline header mandates drawdown on remediation ("any PR that edits a listed script must remediate it"), and a stale row would suppress future regressions of the same file |
| probe + .test.sh | "New followthrough probe … include a `.test.sh` if that is the established pattern" | asked |
| run_suite registration + shard rows | "whether `scripts/test-all.sh` or a manifest (e.g. `suite-shard-legs.tsv`) registers them; match the repo's own registration pattern" | asked |
| tracker issue + directive | "file the follow-through tracker issue … Body close-criteria … include the context paragraph" | asked |
| Observability / Encryption Posture / Guard Contract sections | — | inferred — justification: plan-skill gates 2.9/2.11/2.12 require them for a change that adds a credentialed-HTTP probe and a refusal control; content is honest, not ceremonial |

### Split Assessment

- Subsystems touched: 1 — `scripts/` (plus knowledge-base plan artifacts)
- Planned files: 6 | Estimated changed lines: ~420 (probe ~180, suite ~180, refusal ~12, registration ~4, baseline −1, manifest rows +2)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Implementation Phases

### Phase 1 — the refusal (closes #11532)

1. Insert the xtrace-refusal block in `scripts/content-publisher.sh` immediately
   after `set -euo pipefail` (:36), covering the 8 lint-referenced names +
   `DISCORD_BLOG_WEBHOOK_URL` + `DISCORD_WEBHOOK_URL` + `GH_TOKEN`.
2. Delete the `scripts/content-publisher.sh` row from
   `lint-shell-trace-credential-refusal.baseline.txt`.
3. Verify: `python3 scripts/lint-shell-trace-credential-refusal.py scripts/content-publisher.sh`
   → clean; `python3 scripts/lint-shell-trace-credential-refusal.py --changed` →
   clean; run the affected selection (`bash scripts/test-all.sh --affected`).

### Phase 2 — the probe + harness + registration

1. Write `scripts/followthroughs/discord-blog-webhook-fallback.sh` per the
   contract above; `chmod +x`.
2. Write `scripts/followthroughs/discord-blog-webhook-fallback.test.sh` per the
   case list; run it → all assertions green.
3. Register `run_suite "scripts/followthroughs/discord-blog-webhook-fallback" …`
   in `scripts/test-all.sh` beside the other followthroughs entries; run
   `python3 scripts/regenerate-shard-manifest.py --incremental --write` and commit
   the `suite-shard-legs.tsv` + `suite-durations.tsv` rows.
4. Run `scripts/lint-followthrough-varq-ban.sh` and
   `scripts/lint-orphan-test-suites.sh` → clean (declare an
   `AFFECTED_SCRIPTS_FOLLOWTHROUGHS_DISCORD_BLOG_WEBHOOK_FALLBACK_PATHS` edge only
   if the census reports the registration unclassified).
5. Optional pre-merge verification per convention: `gh workflow run
   scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true` is
   read-only; read the tracker's `exit=` line in the run log if run.

### Phase 3 — the tracker issue

1. `gh issue create` from the worktree with the body above (directive unfenced,
   column 0). Record the issue number.
2. PR #11543 body: `Closes #11532` on its own line + `Ref #<tracker>`.

## Acceptance Criteria

- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py scripts/content-publisher.sh` exits 0.
- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py --changed` exits 0 on this branch.
- [ ] `scripts/content-publisher.sh` no longer appears in `lint-shell-trace-credential-refusal.baseline.txt`.
- [ ] `scripts/followthroughs/discord-blog-webhook-fallback.sh` exists, is executable, and carries the contract's header block (exit vocabulary, CREDENTIAL POSTURE, RETIREMENT).
- [ ] `bash scripts/followthroughs/discord-blog-webhook-fallback.test.sh` exits 0 with every assertion green, including the xtrace→78 and bearer-never-in-argv cases.
- [ ] `grep -c 'SENTRY_AUTH_TOKEN' scripts/followthroughs/discord-blog-webhook-fallback.sh scripts/followthroughs/discord-blog-webhook-fallback.test.sh` prints 0 (retired-name ban, comments included).
- [ ] `bash scripts/lint-followthrough-varq-ban.sh` exits 0.
- [ ] `bash scripts/lint-orphan-test-suites.sh` exits 0 with the new suite classified.
- [ ] `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` carry a `scripts/followthroughs/discord-blog-webhook-fallback` row produced by the regen tool.
- [ ] The tracker issue exists with labels `follow-through` + `meta/machinery`, milestone `Post-MVP / Later`, and an unfenced column-0 `soleur:followthrough` directive whose `script=` resolves to an executable in this worktree.
- [ ] PR #11543 body carries `Closes #11532` on its own line and `Ref #<tracker>`.
- [ ] Plan/PR artifacts cite the merged feature by date + SHA `347d3812` only — the token `#11504` appears nowhere in the diff or PR body.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal verification/lint machinery.

## Test Scenarios

- Given a `set -x` invocation of `scripts/content-publisher.sh` with any bound
  credential, when it starts, then it prints the refusal to stderr and exits 78
  before any command runs (`unit` — exercised via the lint's own suite shape +
  manual `bash -x` smoke).
- Given no `status: published` + `discord` + `publish_date >= 2026-10-30` file in
  the content dir, when the probe runs, then it exits 2 NOT YET without a network
  call (`unit` — harness case).
- Given a qualifying published file and a Sentry events page with a
  `timestamp >= 2026-10-29T17:00:00Z` row, when the probe runs, then it exits 1
  FAIL and names the event (`unit` — harness case).
- Given a qualifying published file and only pre-cutoff events, when the probe
  runs, then it exits 0 PASS (`unit` — harness case).
- Given a non-200 or unparseable Sentry response, when the probe runs, then it
  exits 3 CANNOT ESTABLISH (`unit` — harness case).

## Context

- Merged feature: Discord blog→general webhook fallback warning, squash commit
  `347d3812` (2026-10-29). Verified context (do not re-verify): prod secret
  `DISCORD_BLOG_WEBHOOK_URL` exists in soleur/prd (121 bytes, well-formed); live
  container env-file re-downloaded 2026-10-29T17:21Z after the secret write;
  `buildPublisherEnv` forwards it; the marker fires only on a post attempt with
  the key absent.
- The publisher flips `status: scheduled` → `published` via `sed -i` and commits
  through `safeCommitAndPr` (mergeMode "direct") — the `published` file on main
  IS the liveness evidence the probe reads.
- PR #11543 (draft) is this pipeline's PR.

## References

- Issue #11532; issue body cites the lint's emitted remedy.
- `scripts/followthroughs/cron-machinery-soak-9272.sh` (idiom source).
- `scripts/followthroughs/post-deploy-incident-soak{,.test}.sh` (generic-name +
  harness precedent).
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`.
- `.claude/hooks/follow-through-directive-gate.sh`.
- ADR-031 (Sentry RO token), ADR-202 (Rule D pinning), ADR-298 (generic soak),
  ADR-214 (no env-declared destination pins).
