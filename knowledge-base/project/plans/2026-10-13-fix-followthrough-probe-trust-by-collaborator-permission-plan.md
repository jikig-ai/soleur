---
title: "fix: follow-through marker probes decide author trust by collaborator permission, not author_association"
date: 2026-10-13
type: fix
slug: followthrough-probe-trust-by-collaborator-permission
branch: feat-one-shot-sweeper-probe-activation-lookup
issue: 9818
lane: cross-domain
priority: p2-medium
domain: engineering
---

# fix: follow-through marker probes decide author trust by collaborator permission, not author_association

Tracker reference only: `Ref #9818` (no close keywords anywhere in PR text; no "canary closed" comment; no citation of
ADR-270 as accepted canary evidence). Spec lacks a valid `lane:` (no spec.md for this branch), so `lane:` defaulted to
`cross-domain` (fail-closed); the domain sweep below was done by hand and found Engineering only.

## Overview

The daily follow-through sweeper reports a false FAIL on the ADR-276 S2 push-dedupe tracker (#9818) every day since
2026-10-11: "10 push run(s) were elided with no activation on record". The operator's activation comment
(`S2-ACTIVATED: 2026-10-11T09:48:17Z`, comment 6107736592) is dropped by the probe's trust filter
(`scripts/followthroughs/ci-push-dedupe-soak-9512.sh` line 101, `author_association IN (OWNER, MEMBER, COLLABORATOR)`)
because the operator's org membership is private and GitHub computes `author_association` against the READING token.
The repo already fixed this exact defect once for `RESULT:` verdict probes (#8389, `scripts/lib/trusted-verdict.sh`,
resolving trust from `GET repos/{repo}/collaborators/{login}/permission`); the S2 and S3 marker probes were written
afterwards, used the snake_case REST spelling, and slipped past that lint.

Plan: write failing fixtures first (a private-member activation comment whose `author_association` is `CONTRIBUTOR` but
whose permission is `admin`), refactor the trust lib to one internal core with two views (bodies, and `{t,b}` pairs),
migrate BOTH the S2 and the S3 probe onto the `{t,b}` view (S3 is live, see Research Reconciliation), and extend the lint
so the spelling cannot return.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (measured 2026-10-13) | Plan response |
|---|---|---|
| Fix by deciding trust from collaborator permission "e.g. `gh api repos/$REPO/collaborators/<login>/permission`" as a new mechanism | That mechanism already exists and is the repo's mandated chokepoint: `scripts/lib/trusted-verdict.sh` (`_trusted_verdict_permission`, admin/maintain/write trusted, 404 = untrusted, other failure = rc 2), runbook `followthrough-convention.md` "An operator-confirmed probe filters verdicts through ...", used by 3 live probes under the sweeper token | Reuse, do not re-invent: one internal core, a second view (D1/D1b) |
| Sibling S3 filter (line ~111) is "latent: its S3 markers" | S3 is LIVE and masked: `CI_DRAFT_LIGHT=on` since 2026-10-11T09:43:31Z, `S3-CONFIRMED` (09:43:23Z) and `S3-ACTIVATED` (09:43:31Z) by `deruelle`; its sweeper comments 6113863166 / 6134932186 FAIL on a stalled PR (#9707) which fires BEFORE the marker-dependent FAILs. When the stall clears it reports the same false "no activation on record" | Same PR (D2); do not touch #9707 or S3 soak state |
| Under the sweeper's Actions token private members read as CONTRIBUTOR (bot comments show CONTRIBUTOR) | The bot-comment observation is about the bot, not the operator. The operator claim is measured elsewhere: sweeper run 35470503032 (2026-09-19) printed `observed authorAssociation=CONTRIBUTOR for verdict author deruelle (token=GITHUB_TOKEN)`; `public_members/deruelle` is 404; same comment shows `MEMBER` under the operator token. New measurement this session: the UNMODIFIED S2 probe run locally under the operator token returns `NOT YET: 82 elided run(s) over 1 day(s)` (activated=2026-10-11T09:48:17Z, mean 8.08 job-min, adr_status=adopting) while the sweeper-token run FAILs - same code, same repo state, different token | Evidence bar met without any setting change (D4); the post-fix expected sweeper verdict is `NOT YET` (age < 7 days), NOT PASS |
| "bot/unknown author => untrusted" | The lib's GraphQL read (`gh issue view --json comments`) reports the sweeper bot as `github-actions`; the permission endpoint answers 404 "not a user" and the lib maps 404 to `none`; author-less comments are dropped by `select((.author.login // "") != "")` (CTO D1b measured the bot login and 404 on #9777) | No new bot/null/login-shape mechanism is needed; rows pin the existing behavior on the new view |
| (implied) author_association appears only in the two probes | `git grep` over `scripts/followthroughs/*.sh` + `scripts/lib/*.sh` (non-test, non-comment lines): exactly two live filters, `ci-push-dedupe-soak-9512.sh:101` and `ci-draft-light-soak-9728.sh:111`. Lint rule 4 stayed green over both: it fires only on a probe that reads comments AND branches on `RESULT:` | Lint rule 5 (D3) |
| (implied) a larger thread needs REST `--paginate` | Measured by CTO on gh 2.102.0: `gh issue view --json comments` returns ALL pages (212/212 on #9777, 102/102 on #7312, 1720/1720 on #7607) | GraphQL read kept; a fixture row serves more than 100 comments through the GraphQL shape |

## Research Insights

**Premise validation.** #9818 is OPEN (label `follow-through`, directive `script=scripts/followthroughs/ci-push-dedupe-soak-9512.sh
earliest=2026-10-09T10:08:48Z secrets=GH_TOKEN`); #9512 (the S2 PR's issue) is CLOSED and PR #9808 is merged, as the probe
expects; #9728 (S3) is OPEN. Cited files exist on this branch; filter lines are 101 (S2) and 111 (S3), matching "~100/~111".
ADR corpus grep for the mechanism (`trusted-verdict`, `author_association`): ADR-100 cites the lib; ADR-142 E8 specifies an
`author_association` attestation requirement with no implementing script (spec-only sibling of the same class; not touched). No ADR
rejects the permission-endpoint mechanism; #8389 chose it.

**Property List** (what the change must buy):
1. P1 - a marker comment by a repository admin/maintainer/writer counts under the sweeper's `GITHUB_TOKEN` regardless of org-membership visibility.
2. P2 - a comment by anyone without admin/maintain/write (drive-by, bot, ghost, triage/read) never arms, ends, or closes a soak.
3. P3 - an unreadable trust decision is `CANNOT ESTABLISH` (exit 3), never "untrusted" and never "trusted".
4. P4 - the same defect cannot re-enter a probe under `scripts/followthroughs/` through either spelling.
5. P5 - S3 keeps `created_at`/`createdAt` per comment (S3-CONFIRMED must precede S3-ACTIVATED).

**Cut List** (mechanisms considered and removed):
- New permission-lookup code per probe -> covered by `_trusted_verdict_permission` already on main (grepped `scripts/lib/trusted-verdict.sh`, the authority, not a consumer).
- A repository-variable read for activation -> already rejected by the S2 probe header (sweeper token gets 403 on Actions variables).
- CODEOWNERS-based fallback -> the runbook records it was held in reserve and not needed (endpoint answers 200 under GITHUB_TOKEN).
- Editing the #9818/#9728 issue bodies -> out of plan scope; "owner/member/collaborator" remains approximately true as a description (D5).
- A new ADR -> reuses the #8389 decision (no architectural change).
- A fresh in-Actions `workflow_dispatch` (dry run) -> existing measurement suffices (D4); dropped at plan-review as it is not a gate.
- A parallel REST-based function with a bot/null/login-shape guard -> dropped at plan-review (D1b): the existing GraphQL read already gives bot = 404 -> none, author-less drop, `createdAt`.
- Per-probe copies of the bot/null/triage/fence/memo/404 matrix -> those are lib properties and live in the lib suite only; probe suites prove wiring.
- Message-string rewrites in every row -> headers change; runtime strings change in one mechanical sweep only if no row asserts them (none does, checked by the plan-review).
- Investigating the pre-existing `grep: .../z2/requests.log: No such file` stderr line of the S3 suite -> answers no ask; if the migrated harness still reproduces it, file a `deferred-scope-out` issue instead.

**Institutional learnings applied** (verified paths exist):
- `knowledge-base/project/learnings/2026-09-19-every-fix-for-a-silent-drop-was-itself-a-silent-drop.md` - the memo table dies inside `$(...)`: call the resolver WITHOUT command substitution inside the core; positive fixtures are mandatory (negative-only fixtures cannot see a dropped memo); 404 definitive vs 403/5xx transient.
- `knowledge-base/project/learnings/2026-10-09-a-cost-lever-must-not-be-able-to-redden-the-run-it-saves.md` - its Solution bullet prescribes the defective `author_association` filter; amend it so it stops being copy-pasted.
- `knowledge-base/project/learnings/2026-10-04-a-new-suite-is-invisible-to-repo-ratchets-until-tracked-and-my-fix-moved-the-event-behind-a-hang.md` and the 2026-10-09 learning's Session Errors - run `fixture-relative-assert.test.sh` and `test-affected-kb-consumers.test.sh` directly before pushing; ratchets read `git ls-files`.
- `knowledge-base/project/learnings/2026-09-25-a-fixture-suite-cannot-see-that-the-probe-can-no-longer-take-its-reading.md` - fixtures certify logic, not host capability; the real-comment replay and the next scheduled sweep are the capability check.
- `knowledge-base/project/learnings/2026-09-18-every-instrument-i-built-to-check-the-guards-needed-checking.md` - run each new mutant against its row before trusting the row; a positive control is mandatory.
- `knowledge-base/project/learnings/2026-09-24-followthrough-retirement-headers-underenumerate-touch-points.md` - the probes keep their RETIREMENT headers; no new suite file is created, so no TSV rows are added, but assertion floors move.

**Baselines (measured this session, `bash <suite>` on the branch tip):** `scripts/lib/trusted-verdict.test.sh` 13 passed (floor `MIN_ASSERTIONS=12` real); `scripts/lint-followthrough-varq-ban.test.sh` 89 passed (floor 80); `ci-push-dedupe-soak-9512.test.sh` 121 passed (`_FLOOR=121`, mutants floor 50, always-PASS harness floor 49 reds); `ci-draft-light-soak-9728.test.sh` 162 passed (`_FLOOR=162`, mutants floor 45, harness 71 reds). Lint production run: rule 4 denominator = 8 comment-reading probes (`MIN_COMMENT_READERS=3`).

**Value-proposition measurement (0.6c).** No cost saving is claimed; skipped.

**Open Code-Review Overlap:** None (`gh issue list --label code-review --state open`, bodies searched for the four edited script paths: zero matches).

**Domain Review:** Domains relevant: Engineering only (CTO consulted: rulings D1, D1b, D2-D5 recorded in
`knowledge-base/project/specs/feat-one-shot-sweeper-probe-activation-lookup/decision-challenges.md`). Product/UX: NONE (no UI
surface; no file matches the UI-surface term list). Legal/GDPR: no new data processing (GitHub logins already public in the
comments being read; `gdpr-gate` triggers (a)-(d) do not fire). Marketing, Sales, Finance, Operations, Support: no implications.
No infrastructure (Phase 2.8), no persistent store or new connection (Phase 2.11), no architectural decision (Phase 2.10: the
ADR/C4 update is not needed; the lib's #8389 decision is reused and no recorded architecture is misled). Plan-review ran with the
engineering panel (DHH, Kieran, code-simplicity); the named CEO/design panel was not relevant and the CTO had already ruled on this plan.

## Decisions (CTO rulings, 2026-10-13; full text in decision-challenges.md)

- D1 / D1b: one internal core in `scripts/lib/trusted-verdict.sh` (GraphQL `gh issue view --json comments` read, resolve-all-logins first, memo, `admin|maintain|write`, fence strip) with two views: `trusted_verdict_bodies` (`.b`, unchanged contract) and new `trusted_marker_comments <issue> [repo]` (`{t,b}` JSON per trusted comment). `_trusted_verdict_is_trusted_perm` and `_trusted_verdict_strip_fences` are extracted in this PR as a strictly behavior-preserving refactor. Both probes use the new view.
- D2: S3 is fixed in the same PR (S3 live; do not alter S3 soak state).
- D3: lint rule 5 in this PR (own counter and floor, no per-line opt-out).
- D4: existing measurement suffices; pre-merge read-only replay; post-merge the next scheduled sweep.
- D5: probe headers, runbook, learning; no tracker body edit, no tracker comment, no new ADR.

## Implementation Phases

RED before GREEN (`cq-write-failing-tests-before`): each phase's tests land in the same phase and are run RED against the
unmodified code first. Phase order follows dependency direction: lib (contract) before consumers.

### Phase 0 - Reproduce (RED) before touching any probe

0.1. In `ci-push-dedupe-soak-9512.test.sh` add fixture knob `privact`: the activation comment is authored by `{login:"priv-op"}`
with `authorAssociation:"CONTRIBUTOR"` and the fake `gh` answers `collaborators/priv-op/permission` = `admin`. Row `r_privmember`
(the same name in S2, S3 and the Guard Contract): `build_fx ... 10 15 510 2568 privact` expects rc 0 `PASS`. Run it against the
UNMODIFIED probe: it must be RED with `FAIL: 10 push run(s) were elided with no activation on record` (rc 1) - the sweeper's exact
observed output. Keep that output for the PR body. The fake `gh` of this phase serves the OLD REST route for the unmodified probe
and the new `issue view` route for the migrated one; build the fixture with both so the RED run is honest (a RED caused by a
missing route would be vacuous - assert the failure text above).
0.2. Same `r_privmember` in `ci-draft-light-soak-9728.test.sh` (S3-CONFIRMED + S3-ACTIVATED by a CONTRIBUTOR-association admin);
unmodified probe: RED (`light run(s) observed with no activation on record`).

### Phase 1 - the lib: one core, two views, behavior-preserving first

1.1. Refactor `scripts/lib/trusted-verdict.sh` WITHOUT adding behavior. Acceptance gate for this step, run unchanged before any new row counts: `scripts/lib/trusted-verdict.test.sh`, `scripts/followthroughs/concierge-strand-754ee124-5733.test.sh`, `scripts/followthroughs/cpx22-invoice-reconcile-7431.test.sh`, `scripts/followthroughs/inngest-zot-client-authz-6500.test.sh` all pass byte-for-byte as before.
- Extract `_trusted_verdict_is_trusted_perm <perm>` (`admin|maintain|write` -> rc 0) and `_trusted_verdict_strip_fences` (the awk, both ``` and ~~~; fix the mis-indented comment while moving it). Each now occurs once in the file, which is what makes the lib mutation anchors unique.
- Extract the internal core `_trusted_verdict_core <issue> <repo>`: one `gh issue view <issue> --repo <repo> --json comments` read (all pages, measured), drop author-less comments, resolve every distinct login via `_trusted_verdict_permission "$login" "$repo" >/dev/null` (a redirect, NEVER `$(...)`, so the memo survives; any rc 2 -> `return 2` BEFORE any output), then emit one record per trusted comment (author in the trusted arm) as `{t: createdAt, b: <fence-stripped body>}` JSON, accumulating into a variable and printing once at the end (so rc 2 never leaves partial output). Keep: rc 2 = transient (never untrusted), the empty-memo guard, the bash >= 4 associative-array refusal.
- `trusted_verdict_bodies` becomes the `.b` view of the core with identical stdout/rc.
1.2. Add `trusted_marker_comments <issue> [repo]` = the `{t,b}` view (one compact JSON object per trusted comment, API order, `t` = `createdAt` unchanged). Fail closed on a missing or non-ISO-8601 `createdAt` (rc 2, never a default timestamp). Note for the runbook: `createdAt` is the comment's creation time and does not reflect later edits to its body.
1.3. `scripts/lib/trusted-verdict.test.sh`: add a `mutant_lib` helper modelled on the probe suite's (anchor count must be exactly 1, else the mutation did not land and the row fails). Rows for the `{t,b}` view and parity (the existing rows already own bot/author-less/404/403/fence/memo for the bodies view): M-H1 (the repro) a CONTRIBUTOR-association admin author counts in the `{t,b}` view; M-H2 OWNER-association author with permission `read` does not; M-H3 `triage` does not, `maintain` and `write` do; M-H4 parity: for one fixture, `trusted_verdict_bodies` output equals the `.b` projection of `trusted_marker_comments` (same trust set, same fence stripping, both spellings); M-H5 `t` equals the fixture `createdAt` byte-for-byte, and a missing or non-ISO `createdAt` -> rc 2 with empty stdout; M-H6 permission 403/5xx on the LAST of several distinct authors -> rc 2 with EMPTY stdout (no partial output); M-H7 404 drops that author only, a second trusted author still comes through; M-H8 two comments by one author -> exactly one permission request (memo); M-H9 more than 100 comments through the GraphQL shape are all returned; M-H10 harness integrity: a fixture comment with no `author` key must be dropped like an author-less comment while an `author` with an empty login is also dropped (and the stub refuses any argv it was not built for, exit 64). Positive control for each negative row on the same input.
Lib mutants (mutated COPIES, anchors unique after 1.1): `triage` added to `_trusted_verdict_is_trusted_perm` (M-H3); the strip function body emptied (M-H4); the resolver called under `$(...)` (M-H1 positive control, M-H8); the core emitting inside the resolve loop (M-H6); `authorAssociation` consulted instead of the permission (M-H1, M-H2); `t` replaced by `""` (M-H5); the `createdAt` validity check removed (M-H5). Raise `MIN_ASSERTIONS` to the measured real count minus the self-test.

### Phase 2 - S2 probe on the `{t,b}` view

2.1. `ci-push-dedupe-soak-9512.sh`: `source` the lib the way `concierge-strand-754ee124-5733.sh` does
(`source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/trusted-verdict.sh"`, after the xtrace refusal and the tool
checks; lint rule 3 accepts that line, verified identical to concierge's); replace lines 100-103 with
`trusted_json="$(trusted_marker_comments "$tracker" "$REPO")" || fail_api "tracker $tracker comments (trusted-author resolution)"`
then `trusted="$(jq -r '.b' <<<"$trusted_json" | tr -d '\r')"` (jq failure -> `fail_api`). Everything downstream (TS_RE, `last_on`, `census_marked`) is unchanged.
2.2. Header lines 21-31 (and the `(d)` clause): say trust comes from the comment author's repository permission (admin/maintain/write, resolved at read time through the shared lib), not `author_association` (computed against the reading token's visibility; private members read as CONTRIBUTOR under `GITHUB_TOKEN`, #6617/#8389). Runtime message strings that say "owner, member or collaborator" change in ONE mechanical sweep to "a repository admin, maintainer or writer" - first `grep -n "owner, member or collaborator" scripts/followthroughs/*.test.sh` must be empty (the plan-review found no row asserts it).
2.3. `ci-push-dedupe-soak-9512.test.sh` (probe WIRING only; trust-matrix properties are the lib suite's):
- fake `gh`: add an `issue view <N> --repo <r> --json comments [--jq ...]` arm (argv-strict, exit 64 otherwise) serving `$FX/comments-<N>.json` as `{"comments":[{author:{login},authorAssociation,createdAt,body}]}` (applying `--jq` with real jq; more than 100 comments supported) and a `repos/*/collaborators/*/permission` arm reading `$FX/perms.tsv` (`login<TAB>perm|403|404`; the 404/403 stderr texts mirror the real `gh`: `(HTTP 404)` / `(HTTP 403)`, because the lib's 404 detection keys on that text), both logging to `requests.log`. The old REST comments arm is removed.
- fixtures: the old association argument maps to a stable login + perms row (OWNER->`owner-op` admin, MEMBER->`member-op` write, COLLABORATOR->`collab-op` write, CONTRIBUTOR->`contrib-op` read, NONE->`none-op` 404) while every comment KEEPS its `authorAssociation` as a DECOY so no row can pass by consulting it.
- new rows only: `r_privmember` (repro), `r_assocowner` (association OWNER, permission `read` -> not trusted), `r_permfail` (403 on the activation author -> rc 3 `CANNOT ESTABLISH`), `r_manycomments` (more than 100 comments, the DEACTIVATED marker beyond the first 100 -> read; replaces the REST `page2` row, whose mechanism no longer exists), plus a `requests.log` assertion that the probe issued `issue view 4242 --repo jikig-ai/soleur --json comments` exactly once and made one permission request per distinct human author.
- mutation tree: `mutant()` currently writes a lone `$TMP/mut-<name>.sh`, so the probe's relative `source` would resolve to nothing, `source` would fail, the helper call would return 127 and `|| fail_api` would turn EVERY mutant "caught" for the wrong reason. Build `$R/scripts/followthroughs/<mutant>.sh` with `$R/scripts/lib` a symlink to the real lib (probe-only mutants; lib mutants live in the lib suite), run an IDENTITY copy through the full row set first and require it green, and assert no row's output contains `No such file`. The shape-mutant loop (`$TMP/shape.sh`) uses the same tree; its comments-route pair (`api --paginate "repos/$REPO/issues/$tracker/comments`) no longer exists in the probe and is dropped (the `requests.log` assertion replaces it); the other pairs stay.
- re-anchor: `m-trusted` -> delete the helper call's `|| fail_api ...` (reds `r_commentsfail`/`r_permfail`); `m-crlf` -> the new `tr -d '\r'` line; `m-no-collab`/`m-contrib` are retired (their anchor `IN("OWNER", "MEMBER", "COLLABORATOR")` is gone; the lib suite owns the equivalents); add `m-project-raw` (project `.b` from an unfiltered source: `r_assocowner`/`r_privmember` red) and `m-empty-helper` (helper call replaced by `""`: every activation row reds).
- recompute `_FLOOR`, the mutant floor (`-ge 50`) and the always-PASS harness reds (`-ge 49`) from the MEASURED post-change counts (a floor below the measured count is a silent under-count).

### Phase 3 - S3 probe on the same view

3.1. `ci-draft-light-soak-9728.sh` lines 109-113: `comments="$(trusted_marker_comments "$TRACKER" "$REPO")" || fail_api "tracker $TRACKER comments (trusted-author resolution)"`; the downstream `jq -r '.b'` and the `S3-CONFIRMED` jq over `.t`/`.b` are unchanged (same `{t,b}` shape; `t` is now an ISO `createdAt`, same as `created_at`). Header lines 20 and 35-37 and the message strings as in 2.2.
3.2. `ci-draft-light-soak-9728.test.sh`: the same wiring-only harness migration (its `addc` already writes a time field; it now writes `createdAt` and `author`), same decoy rule, same mutation tree. New rows only: `r_privmember` (private-member admin posts CONFIRMED then ACTIVATED -> the canonical PASS shape), `r_late_conf_private` (CONFIRMED after ACTIVATED by a private-member admin still FAILs: ordering uses the preserved `t`), `r_assocowner`, `r_permfail`; re-anchor/retire mutants as in 2.3; recompute `_FLOOR` (baseline 162) and the mutant floors. If the migrated harness still prints the pre-existing `requests.log: No such file` stderr line, file a `deferred-scope-out` issue; do not investigate it here.
3.3. HARD CONSTRAINT: the S3 work posts no marker, sets no variable, and leaves PR #9707 and `ci.yml` alone.

### Phase 4 - lint rule 5 and the rule-4 denominator (D3)

4.1. `scripts/lint-followthrough-varq-ban.sh`: add RULE 5 - over every non-test `*.sh` in the target dir, comment-stripped exactly as rule 4 strips (`sed -E 's/^[[:space:]]*#.*$//'`: WHOLE-LINE comments only; a trailing `# why` mention on an executable line DOES fire, a documented limitation - a quote-aware strip is more mechanism than a spelling ban deserves), any line matching `author_?[aA]ssociation` case-insensitively (`grep -qiE`) is a violation citing file:line with a `rule 5:` prefix, naming the permission lib and the #6617/#8389 measurement; no per-line opt-out. Mark the lines `# rule5-grep` and `# rule5-count` (the test's `sed` anchors, like `# rule2-grep`/`# rule4-count`). Own counter `scanned_rule5` and own floor keyed on it (production run only, exit 2 naming rule 5), the floor derived from the measured walk at work time (not a guessed `MIN_PROBES`), with a test-only override env var (e.g. `VARQ_BAN_MIN_RULE5`) so a row can drive it. Update the header ("Four rules"), the `FAILED:` summary line, the clean-line counters, and the rule-4 header sentence that says printing an observed value "is not banned" so it no longer contradicts rule 5.
4.2. Widen `LIB_CALL` to `trusted_verdict_bodies|trusted_marker_comments`. After the migration S2/S3 have no raw `issues/N/comments` read, so without the widening they leave rule 4's denominator and `scanned_rule4` falls 8 -> 6 (the "floor that punishes compliance" the lint's own header names).
4.3. `scripts/lint-followthrough-varq-ban.test.sh` rows: R5-M1 a probe that sources the lib (precondition satisfied) AND reintroduces an inline `select(.author_association ...)` -> exit 1 at TRUE line with `rule 5:`; R5-M2 camelCase `.authorAssociation` -> exit 1 with `rule 5:`; R5-M3 must-PASS: the word only in a WHOLE-LINE header comment; R5-M4 trailing `# why` mention on an executable line -> exit 1 (pins the documented limitation); R5-M5 must-PASS: the word in a `.test.sh` fixture (exempt); R5-M6 second probe after a compliant first is also cited (walk does not stop); R5-M7 DISPATCH: guard COPY with the `# rule5-grep` line deleted -> exit 0 on the M1 fixture; R5-M8 guard COPY with `scanned_rule5` forced to 0 -> production-mode run exits 2 naming rule 5; R5-H1 must-PASS non-canonical: a compliant probe with different variable names that sources the lib and calls only `trusted_marker_comments`, and is counted as `checked 1 comment-reading probe(s)` in a hermetic sandbox (kills the `LIB_CALL`-revert mutant without pinning the live corpus count); R5-H2 live tree: 0 rule-5 hits. Existing R4-M2c (an inline `.authorAssociation` filter) gains a `grep -q 'rule 4:'` assertion, since rule 5 now ALSO fires on that fixture and a dead rule 4 would otherwise stay green. Raise the suite floor (baseline 89, floor 80) to the measured count.

### Phase 5 - documentation (D5), no issue-body edits

5.1. `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`: one added sentence in the operator-confirmed-probe section (marker probes use `trusted_marker_comments`, `{t,b}`, read-time permission, `createdAt` is creation time not edit time) plus a pointer to rule 5; REST `author_association` and GraphQL `authorAssociation` are the same defect.
5.2. Amend `knowledge-base/project/learnings/2026-10-09-a-cost-lever-must-not-be-able-to-redden-the-run-it-saves.md` Solution bullet ("filtered to `author_association` OWNER/MEMBER/COLLABORATOR") to point at the helper (append a dated correction; do not rewrite history).
5.3. ONE new learning under `knowledge-base/project/learnings/` (author picks the date; topic: rule 4's `RESULT:` anchor let marker probes stay green over the defect it claims to ban, and the S3 sibling was live but masked; cite the two-tokens-same-code measurement method). Directory + topic only in tasks.
5.4. Do NOT edit the #9818 / #9728 bodies, post tracker comments, add an ADR, or touch `ci.yml`, Actions settings, `CI_PUSH_DEDUPE`, `CI_DRAFT_LIGHT`.

### Phase 6 - verification (read-only)

6.1. Run each directly (never a hand-enumerated subset): `bash scripts/lib/trusted-verdict.test.sh`, the three live-consumer suites named in 1.1, `bash scripts/lint-followthrough-varq-ban.test.sh`, `bash scripts/lint-followthrough-varq-ban.sh`, `bash scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh`, `bash scripts/followthroughs/ci-draft-light-soak-9728.test.sh`; then the ratchets that read tracked files: `bash plugins/soleur/test/fixture-relative-assert.test.sh`, `bash scripts/test-affected-kb-consumers.test.sh` (both keep `*.baseline.txt` files: regenerate with the suites' documented command, never by hand), `python3 scripts/lint-guard-contract.py <this plan>`, `python3 scripts/lint-infra-no-human-steps.py <this plan>`, `shellcheck` on the edited scripts.
6.2. Pre-merge real-comment replay (read-only, operator token; a manual check, not a committed fixture per `cq-test-fixtures-synthesized-only`), run after Phase 1: `GH_TOKEN="$(gh auth token)" bash -c 'source scripts/lib/trusted-verdict.sh; trusted_marker_comments 9818 | jq -r .b | tr -d "\r" | grep -c "^S2-ACTIVATED: 2026-10-11T09:48:17Z$"'` expects `1`; the same for `9728` with `grep -c -e "^S3-ACTIVATED: 2026-10-11T09:43:31Z$" -e "^S3-CONFIRMED: "` expects `2`; and the negative control pair: `gh issue view 9818 --repo jikig-ai/soleur --json comments --jq '[.comments[].body | select(startswith("### Sweeper run"))] | length'` is greater than 0 while `trusted_marker_comments 9818 | jq -r .b | grep -c "### Sweeper run"` is `0` (the control proves the zero is the filter, not an empty read). Confirms the live markers survive fence stripping and trust resolution.

## Files to Edit

- `scripts/lib/trusted-verdict.sh` (core + two views + extracted predicates)
- `scripts/lib/trusted-verdict.test.sh` (stub + rows + `mutant_lib` + floor)
- `scripts/followthroughs/ci-push-dedupe-soak-9512.sh`
- `scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh`
- `scripts/followthroughs/ci-draft-light-soak-9728.sh`
- `scripts/followthroughs/ci-draft-light-soak-9728.test.sh`
- `scripts/lint-followthrough-varq-ban.sh`
- `scripts/lint-followthrough-varq-ban.test.sh`
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
- `knowledge-base/project/learnings/2026-10-09-a-cost-lever-must-not-be-able-to-redden-the-run-it-saves.md` (appended correction)

## Files to Create

- `knowledge-base/project/learnings/<date>-<topic>.md` (one learning; directory + topic only, author picks the date)

No new `*.test.sh` is created, so no `scripts/suite-shard-legs.tsv` / `scripts/suite-durations.tsv` / `test-all.sh` registration row is added
(grepped: both probe suites are registered at `scripts/test-all.sh` lines ~6289/6300 and the lib suite by the `scripts/lib/*.test.sh` glob). The
three live consumers of the lib (concierge, cpx22, inngest-zot) are NOT edited but must stay green (Phase 1.1 gate). Both probe files are
CODEOWNERS-bound to `@deruelle` (`.github/CODEOWNERS` lines 29-32): the PR needs the owner's review and must not be described as self-approving.
Re-run `git grep -n 'author_association\|authorAssociation' scripts .github` at work time in case another marker probe has appeared.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "reproduce with a failing test in ci-push-dedupe-soak-9512.test.sh (a private-member activation comment whose author_association is CONTRIBUTOR)" | Phase 0.1, Phase 2.3 | mapped |
| 2 | "fix by deciding trust from the repository collaborator permission of the comment author login" | Phase 1, Phase 2.1 | mapped |
| 3 | "keeping fail-closed behavior (API failure => CANNOT ESTABLISH exit 3; bot/unknown author => untrusted)" | Phase 1.2/1.3 (rc 2, M-H6, M-H7), Phase 2.1, `r_permfail` | mapped |
| 4 | "Verify the Actions-token visibility claim as far as possible without changing any setting" | Research Reconciliation row 3, Phase 6.2 | mapped |
| 5 | "Decide whether the sibling S3 script gets the same fix in this PR or a filed follow-up" | Decisions D2, Phase 3 | mapped |
| 6 | "do not alter S3 soak state" | Phase 3.3, Phase 5.4 | mapped |
| 7 | "do not touch ci.yml, GitHub Actions settings, or the CI_PUSH_DEDUPE / CI_DRAFT_LIGHT variables" | Phase 5.4, AC6 | mapped |
| 8 | "no PR text may cite ADR-270 accepted as canary evidence; no \"canary closed\" comment; no close keywords (Ref #9818 only)" | Header, AC7 | mapped |
| 9 | "Plan only; write only under knowledge-base/project/{plans,specs}/" | this plan phase writes only the plan, tasks.md, decision-challenges.md | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Lib core + `trusted_marker_comments` view | "recommend same PR if the shared logic is a trivial helper" (asks 2, 5) | asked |
| Extraction of `_trusted_verdict_is_trusted_perm` / `_trusted_verdict_strip_fences` (behavior-preserving) | — | inferred — justification: CTO D1b; without it the new view duplicates the trust predicate and fence strip (drift) and the lib mutants cannot anchor uniquely |
| S3 probe + harness migration | "Decide whether the sibling S3 script gets the same fix in this PR" (ask 5) | asked |
| Lint rule 5 + `LIB_CALL` widening | — | inferred — justification: CTO D3; rule 4's anchor (`RESULT:`) left both probes green over the defect, and without the widening the migration shrinks rule 4's denominator 8 -> 6 |
| Runbook sentence, learning, amended 2026-10-09 learning | — | inferred — justification: CTO D5; the 2026-10-09 learning prescribes the defective filter and is the copy-paste source |
| Harness mutation tree (mirrored dirs, lib symlink, identity row) | "reproduce with a failing test" (ask 1) | inferred — justification: the probes now source the lib by relative path; the existing lone-file copy breaks every mutant |
| Pre-merge real-comment replay | "Verify the Actions-token visibility claim as far as possible" (ask 4) | asked |

### Split Assessment

- Subsystems touched: 3 - `scripts/lib`, `scripts/followthroughs`, `scripts/` (lint) (+ `knowledge-base/` docs)
- Planned files: 11 | Estimated changed lines: ~500-700 (probe suites trimmed to wiring rows at plan-review; lib refactor and lib rows are the new bulk)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (the lib view, both consumers and the lint share one contract; splitting leaves S3 on the defective filter and the lint red over the migrated probes). If the estimate crosses 800 at work time, the only clean boundary is lint rule 5 as a second PR AFTER the migration (never before: it would redden main).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing; the operator keeps reading a false daily FAIL (or, if the fix fails open, a drive-by commenter could arm, end or close a CI-cost soak tracker).
- **If this leaks, the user's workflow is exposed via:** a trust filter that fails open on this PUBLIC repo (any authenticated GitHub user posting `S2-EXIT-CENSUS: https://github.com/...` closes the S2 tracker through the sweeper's exit-0 close); no customer data is read or written.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`: the blast radius is the maintainers' own CI cost levers and their trackers, no user data or user-facing path is touched, and the design is fail-closed by construction (rc 2 -> exit 3).

threshold: none, reason: the touched paths (scripts/lib, scripts/followthroughs, lint, runbook) are internal CI verification machinery outside the preflight sensitive-path set (verified against the canonical `SENSITIVE_PATH_RE`: no match for any planned file), and the only authority they gate is closing a maintainer-owned follow-through tracker.

## Guard Contract

Three guards ship: the lib core/views, the probes' use of them, and the lint. The class to defeat for each: a trust decision whose window, chokepoint or identifier set is narrower than the property.

### Guard 1 - the trusted-verdict core and its two views

**Property.** A comment's text reaches a probe only if its author's effective repository permission (resolved at read time against the reading token's real access) is admin, maintain or write, and any unreadable resolution yields rc 2 with no output, identically for the bodies view and the `{t,b}` view.

**Assembly.** Every path from "a comment exists on the tracker" to "its text reaches a probe's marker grep": the single `gh issue view --json comments` read (all pages, measured), the author-less drop, the distinct-login resolution loop, the memo table, `_trusted_verdict_is_trusted_perm`, `_trusted_verdict_strip_fences`, the accumulate-then-print emit, both public views, and BOTH probe call sites. The chokepoint is the core; a second read or emit path (an early print inside the loop, a view that bypasses the core, a probe that calls `gh issue view --json comments` itself) is the defect. Members drift (new probes, new marker names); the structural invariant is "probes receive bodies only through a view of the core", enforced by lint rule 4 (widened) and rule 5.

**Mutation matrix.**

| # | Edit (mutated COPY of the lib) | Must redden |
|---|---|---|
| 1 | add `triage` to `_trusted_verdict_is_trusted_perm` | M-H3 |
| 2 | empty `_trusted_verdict_strip_fences` | M-H4 (parity, both fence spellings) |
| 3 | call `_trusted_verdict_permission` under `$(...)` (memo lost) | M-H1 (positive control), M-H8 |
| 4 | emit each record inside the resolve loop instead of after it | M-H6 (last author fails -> partial output) |
| 5 | consult `authorAssociation` instead of the permission | M-H1, M-H2 |
| 6 | replace `t` with `""` | M-H5 and S3 `r_late_conf_private` |
| 7 | remove the `createdAt` validity check | M-H5 |
| 8 | map a permission 403 to "untrusted" (continue) instead of rc 2 | M-H6 |
| 9 | make the `{t,b}` view re-read comments itself (a second read path) | M-H4 parity (request-count assertion: one `issue view` per call) |

**Harness rows.** Suite edit that must go RED: neuter the stub so the permission endpoint always answers `admin` (M-H2, M-H3, M-H7 must red, proving the rows can fail); must-PASS non-canonical inputs: a trusted author whose login has digits and interior hyphens with CRLF line endings in the body; a second trusted author after a compliant first.

**Anchor.** No stored value is compared (a live API answer decides), so no stored-value anchor applies; the stored values are suite floors, anchored by the recompute-from-measurement rule in 1.3/2.3/3.2.

### Guard 2 - the probes' consumption of the view (S2 and S3)

**Property.** A probe's `active`/`census`/`confirmed` state is derived only from `trusted_marker_comments` output, an unreadable trust decision is exit 3 (never "no marker", never PASS), and S3's ordering of CONFIRMED before ACTIVATED uses the preserved comment time.

**Assembly.** For each of the two probes: the `trusted_marker_comments` call and its `|| fail_api`, the `jq -r .b` projection, every grep that reads `$trusted` (`last_on`, `last_off`, `census_marked`, S3 `first_on`, `conf_iso`), and the sweeper's exit-code contract (0/1/2/3/78). A probe that sources the lib and then reads comments directly is the "both endpoints pinned, wire unpinned" shape; rule 4 already forbids it.

**Mutation matrix.**

| # | Edit (mutated COPY of the probe, lib symlinked) | Must redden |
|---|---|---|
| 1 | delete `|| fail_api "tracker ... comments (trusted-author resolution)"` | `r_permfail`, `r_commentsfail` |
| 2 | project `.b` from a raw unfiltered read instead of the helper output | `r_privmember`/`r_assocowner` |
| 3 | drop the `tr -d '\r'` | `r_crlf` |
| 4 | S3: take `conf_iso` from the latest instead of the earliest | `r_conf2`, `r_late_conf_private` |
| 5 | helper call replaced with a literal empty string | every activation row |
| 6 | second probe left on the old filter after the first migrated | its own `r_privmember` (stays RED until Phase 3) |

**Harness rows.** `build_fx` edit that must RED: the decoy `authorAssociation` flipped so OWNER carries permission `read` (`r_assocowner`); must-PASS non-canonical: activation by a `COLLABORATOR`-association author with `write`, and by a `NONE`-association author with `maintain` (the contract permits both); an identity copy through the mirrored tree must be fully green (proves the tree, not the mutant, is sound).

**Anchor.** Post-change suite floors are anchored to measured counts (2.3, 3.2); the real-comment replay (6.2) is the external anchor that the live markers survive the real helper.

### Guard 3 - lint rule 5 (no probe filters on author association)

**Property.** No non-test probe under `scripts/followthroughs/` contains an executable (whole-line-comment-stripped) reference to `author_association` or `authorAssociation`, in any case, with or without the underscore.

**Assembly.** The target-dir walk (`find "$TARGET_DIR" -type f -name '*.sh' ! -name '*.test.sh'`), the comment strip, the grep, the violation emit, the counter and its floor; plus rule 4's `LIB_CALL` regex (the denominator the migration must not shrink). Chokepoint: the single grep line; a second spelling (`author-association`, a runtime-built field name `K=author_association; .[$K]`) is out of the regex's reach - recorded as a known residual, mitigated by rule 4's positive obligation (call the lib).

**Mutation matrix.**

| # | Edit (mutated COPY of the guard, or fixture) | Must redden |
|---|---|---|
| 1 | delete the `# rule5-grep` line (DISPATCH) | R5-M7 (M1 fixture exits 0) |
| 2 | force `scanned_rule5` to 0 | R5-M8 (production-mode exit 2) |
| 3 | grep case-sensitive (`-i` removed) | R5-M2 (camelCase) |
| 4 | stop at the first violating file | R5-M6 |
| 5 | comment strip removed (whole-line comments now fire) | R5-M3 |
| 6 | `.test.sh` exemption removed | R5-M5 |
| 7 | `LIB_CALL` reverted to `trusted_verdict_bodies` only | R5-H1 (hermetic denominator row) |

**Harness rows.** Suite edit that must RED: an always-exit-0 guard stub must redden every R5 must-FAIL row; must-PASS non-canonical: a compliant probe with different variable names that sources the lib and mentions the word only in a whole-line `# why` comment. Precondition-satisfied-yet-property-fails row: a probe that sources the lib (precondition) AND filters inline on `.author_association` (property violated) must still FAIL (R5-M1 builds exactly this).

**Anchor.** The rule is validated against the tree its own remediation produces: after Phases 2-3 the live tree has zero hits and the denominator keeps counting the migrated probes (R5-H1, R5-H2); the remediation's own text (the lib header, the probe headers) mentions the word only in whole-line comments, which the strip must pass (R5-M3). Rule 4's R4-M2c gains a `rule 4:` message assertion because rule 5 now also fires on its fixture.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 RED proof: Phase 0 rows `r_privmember` (S2 and S3) fail against the UNMODIFIED probes with the sweeper's own FAIL text and pass after Phases 2-3 (evidence pasted in the PR body).
- [ ] AC2 `git grep -niE 'author_?association' -- 'scripts/followthroughs/*.sh' ':!scripts/followthroughs/*.test.sh' | grep -vE ':[0-9]+:[[:space:]]*#'` prints nothing (lint rule 5 enforces it; paste the lint's own clean line).
- [ ] AC3 All of Phase 6.1 exit 0, every mutant caught, floors raised to measured counts (baselines 13/89/121/162 only grow), and the three live-consumer suites (concierge, cpx22, inngest-zot) pass unchanged against the refactored lib.
- [ ] AC4 Real-comment replay (Phase 6.2) prints `1`, `2`, `0` (with the greater-than-zero control) as specified.
- [ ] AC5 Fail-closed rows exist and are GREEN: permission 403/5xx -> `CANNOT ESTABLISH` rc 3 (S2 and S3), 404 drops that author only, last-author failure leaves no partial output.
- [ ] AC6 `git diff --quiet origin/main...HEAD -- .github/workflows/ci.yml .github/workflows/scheduled-followthrough-sweeper.yml` exits 0 (merge-base form), and the diff contains no `gh variable`, `gh workflow run`, or marker-posting command.
- [ ] AC7 PR body: `Ref #9818` only; no `Closes|Fixes|Resolves`; no sentence citing ADR-270 as accepted canary evidence; no "canary closed" phrasing; no operator checklist (this PR has no operator step).
- [ ] AC8 `python3 scripts/lint-guard-contract.py` and `python3 scripts/lint-infra-no-human-steps.py` pass over this plan; `fixture-relative-assert` and `test-affected-kb-consumers` ratchets run directly and pass; `shellcheck` clean on the edited scripts.
- [ ] AC9 CODEOWNERS review by `@deruelle` requested (both probe files are owned).

### Post-merge (verifiable by the next scheduled sweep; no operator step)

- [ ] AC10 The next scheduled sweeper comment on #9818 no longer contains `elided with no activation on record`; it reads `NOT YET: <n> elided run(s) over <d> day(s) (need >= 10 over >= 7 days)` with `activated=2026-10-11T09:48:17Z` until 2026-10-18T09:48:17Z, then moves on the count/census criteria (an `S2-EXIT-CENSUS` comment is still required for exit 0). Automation: `gh issue view 9818 --repo jikig-ai/soleur --json comments --jq '.comments[-1].body'` after the 18:00 UTC sweep (a read; the ship agent's postmerge step, not an operator action).
- [ ] AC11 S3 on #9728 is covered pre-merge by the AC4 replay; once PR #9707's stall clears, its comment must not report `no activation on record`. Re-check on the first sweep after the stall clears (read only; if the stall persists the replay is the only evidence).

## Test Scenarios

1. Private-member admin (association CONTRIBUTOR) posts the activation -> S2 reads it (repro row).
2. Drive-by (permission none/404) posts `S2-EXIT-CENSUS` -> not counted (existing rows preserved through the permission table).
3. OWNER-association author whose permission is `read` -> not trusted (decoy proof the association is ignored).
4. `github-actions` comment -> 404 -> none (lib suite).
5. Permission read 403/5xx -> exit 3 on both probes; 404 -> that author dropped only.
6. Marker inside a fenced block -> ignored in both views (lib parity row); same marker as a plain line -> counted.
7. Three comments by one author -> one permission request (memo).
8. More than 100 comments through the GraphQL shape -> the DEACTIVATED marker past the first 100 is read.
9. S3: CONFIRMED after ACTIVATED by a private-member admin -> FAIL (ordering preserved); CONFIRMED before -> PASS shape.
10. Lint: reintroduced filter in either spelling -> exit 1 `rule 5:`; whole-line comment mention -> exit 0; trailing mention -> exit 1; hermetic denominator counts a `trusted_marker_comments`-only probe.
11. Real-comment replay on #9818/#9728 (read-only, operator token).

## Risks

- The lib refactor touches code three live probes depend on: the Phase 1.1 gate (four suites unchanged) must pass BEFORE any new row is added, and the refactor must be a separate commit from the new view so a revert is clean.
- Harness rewrite: the fake `gh` must grow the `issue view` and permission arms without loosening its exit-64 strictness (an answer-anything stub puts the fixture above the code under test).
- Mutation tree: probe copies must resolve their `source` (lib symlink) or every new mutant is "caught" for the wrong reason; the identity-copy row and the `No such file` assertion are the guard.
- Permission is resolved at read time: a commenter demoted later un-trusts earlier markers (consistent with the existing lib; documented). `createdAt` is creation time, not edit time.
- A real marker comment inside a fenced block would be dropped by the strip; Phase 6.2 checks the live markers.
- Sweeper token rate: one permission request per distinct human commenter per probe per sweep (#9818 and #9728 each have one human author); negligible against ~1000/hour.
- The sweeper runs probes under `env -i` with `GH_TOKEN`: confirm `PATH` carries `jq`, `base64`, `awk`, `mktemp` (the lib already needs them for the three live consumers).
- Rule 5 is a spelling ban (CTO-ruled) with a whole-line-comment strip; a runtime-built field name evades it - rule 4's widened positive obligation is the backstop.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this plan fills it (`none`, with the scope-out line).
- Never wrap `_trusted_verdict_permission` in `$(...)` inside the core (memo loss, learning 2026-09-19); the views are called under `$(...)` by the probes, which is fine because the memo is only needed within one call.
- Do not rename the `S2-*`/`S3-*` markers or change `TS_RE`: both are asserted by existing rows and by live tracker comments.
- Do not run `gh variable set/delete`, post any `S2-*`/`S3-*` marker, or comment on #9818/#9728 while verifying.
- Path literals were verified with `git ls-files` at plan time (`scripts/lib/trusted-verdict.{sh,test.sh}`, `scripts/lint-followthrough-varq-ban.{sh,test.sh}`, `.github/CODEOWNERS`, `plugins/soleur/test/fixture-relative-assert.test.sh`, `scripts/test-affected-kb-consumers.test.sh`).
- Diff-scope ACs must name the files the pipeline also writes: `knowledge-base/INDEX.md` (if regenerated) and `knowledge-base/project/specs/feat-one-shot-sweeper-probe-activation-lookup/` (tasks.md, decision-challenges.md, session-state.md).
