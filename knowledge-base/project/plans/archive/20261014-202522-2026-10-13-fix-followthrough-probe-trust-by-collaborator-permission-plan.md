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

## Enhancement Summary

**Deepened on:** 2026-10-13 (after plan-review and CTO ruling D1b).
**Research agents used:** CTO (D1-D5, D1b), learnings-researcher, plan-review panel (DHH, Kieran, code-simplicity), security-sentinel, test-design-reviewer, git-history-analyzer, pattern-recognition-specialist; live measurements of the sweeper run log, the permission endpoint and the unmodified probe.

### Key improvements
1. Evidence that the lib resolved permissions for `deruelle`, `github-actions` and `soleur-ai` under `GITHUB_TOKEN` in the last sweep (run 38324624468): D4's visibility claim is now observed, not only documented.
2. Design collapsed to one internal core with two views on the lib's existing GraphQL read (no REST route, no bot/null/type machinery); public name `trusted_verdict_comments`.
3. Lib hardening split from the behavior-preserving refactor: login-shape guard and ISO `createdAt` check land as separate commits after the four-suite gate; `createdAt` validation lives only in the marker view.
4. Test design repaired: refusal log so rc-3 rows cannot pass on a refused argv, `run_case_raw`, multi-edit mutants, a lib-symlinked mirrored mutation tree with identity/no-symlink controls, `m-legacy-assoc` as the durable RED proof, a default CONTRIBUTOR-admin activation author so ~40 rows catch an association-consulting mutant.
5. Lint widened beyond the spelling ban: `VERDICT_BRANCH` now includes `S<n>-...` markers (an unfiltered future marker reader fails rule 4), unique `# rule5-*` markers, a regex canary and a non-vacuous counter.
6. Documentation set corrected: `ship/SKILL.md`, the stub template and the runbook all repeated the claim rule 5 falsifies; retroactive-trust and edit-time caveats recorded.

### New considerations discovered
- S3's probe projection had no failure check (a jq failure would reproduce this exact false FAIL).
- #9808/#9885 merged with zero reviews and no code-owner enforcement exists; AC9 is advisory.
- Five out-of-scope sibling gaps are listed under Deferred with tracking-issue obligations.

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
| Under the sweeper's Actions token private members read as CONTRIBUTOR (bot comments show CONTRIBUTOR) | The bot-comment observation is about the bot, not the operator. The operator claim is measured elsewhere: sweeper run 35470503032 (2026-09-19) printed `observed authorAssociation=CONTRIBUTOR for verdict author deruelle (token=GITHUB_TOKEN)`; `public_members/deruelle` is 404; same comment shows `MEMBER` under the operator token. New measurement this session: the UNMODIFIED S2 probe run locally under the operator token returns `NOT YET: 82 elided run(s) over 1 day(s)` (activated=2026-10-11T09:48:17Z, mean 8.08 job-min, adr_status=adopting) while the sweeper-token run FAILs - same code, same repo state, different token. LIVE observation under `GITHUB_TOKEN` (sweeper run 38324624468, 2026-10-12T23:55Z, runner image ubuntu-24.04 20261002.596): the three lib-consuming probes ran to their "no verdict yet" arms (cpx22 on #7437: `TRANSIENT: no member-authored, anchored RESULT: line`; concierge on #5733: `no RESULT: PASS/FAIL verdict`), not the lib's resolution-failure arm, on threads whose authors are `deruelle`, `github-actions` and `soleur-ai` - i.e. the permission endpoint resolved all three under that token (a 403 would have returned rc 2); inferred from the probes' output arms, since the sweeper does not log the request | Evidence bar met without any setting change (D4); the post-fix expected sweeper verdict is `NOT YET` (age < 7 days), NOT PASS |
| "bot/unknown author => untrusted" | The lib's GraphQL read (`gh issue view --json comments`) reports the sweeper bot as `github-actions`; the permission endpoint answers 404 "not a user" and the lib maps 404 to `none`; author-less comments are dropped by `select((.author.login // "") != "")` (CTO D1b measured the bot login and 404 on #9777) | No new bot/null/login-shape mechanism is needed; rows pin the existing behavior on the new view |
| (implied) author_association appears only in the two probes | `git grep` over `scripts/followthroughs/*.sh` + `scripts/lib/*.sh` (non-test, non-comment lines): exactly two live filters, `ci-push-dedupe-soak-9512.sh:101` and `ci-draft-light-soak-9728.sh:111`. Lint rule 4 stayed green over both: it fires only on a probe that reads comments AND branches on `RESULT:` | Lint rule 5 (D3) |
| (implied) a larger thread needs REST `--paginate` | Measured by CTO on gh 2.102.0: `gh issue view --json comments` returns ALL pages (212/212 on #9777, 102/102 on #7312, 1720/1720 on #7607) | GraphQL read kept; a fixture row serves more than 100 comments through the GraphQL shape |

## Research Insights

**Premise validation.** #9818 is OPEN (label `follow-through`, directive `script=scripts/followthroughs/ci-push-dedupe-soak-9512.sh
earliest=2026-10-09T10:08:48Z secrets=GH_TOKEN`); #9512 (the S2 PR's issue) is CLOSED and PR #9808 is merged, as the probe
expects; #9728 (S3) is OPEN. Cited files exist on this branch; filter lines are 101 (S2) and 111 (S3), matching "~100/~111".
ADR corpus grep for the mechanism (`trusted-verdict`, `author_association`): ADR-100 cites the lib; ADR-142 E8 specifies an
`author_association` attestation requirement with no implementing script (spec-only sibling of the same class; not touched). No ADR
rejects the permission-endpoint mechanism; #8389 chose it. Attributions (git-history-analyzer, verified against `origin/main`): the lib and lint rule 4 landed in 71e7585eae (#8389, squash; the PR-branch review commits are not on main); #7448 was closed by 2e71c04d66 (#7451), not by a lib change; the S2 filter arrived in 32b2fe2abb (#9808) and the S3 filter in 3ef5aa6e12 (#9885), both merged with zero formal reviews and no mention of the lib (so "review noted the lib" is not claimed); the `5470503032`-style numbers in this plan are sweeper run or comment ids, not commits. Census of association-based trust beyond `scripts/followthroughs` (pattern-recognition-specialist): `plugins/soleur/skills/community/scripts/github-community.sh:620-645` tallies "external" commenters by association under an App installation token (a metric only, gates no close; out of scope, listed in the deferred section); `.github/workflows/claude-code-review.yml:41` is a commented example; no `.yml`/`.ts`/`.py` file trusts a comment author by association.

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

- D1 / D1b (public name `trusted_verdict_comments`, renamed from the ruled `trusted_marker_comments` at deepen-plan to match the lib's `trusted_verdict_*` prefix; a mechanical rename, rulings otherwise binding): one internal core in `scripts/lib/trusted-verdict.sh` (GraphQL `gh issue view --json comments` read, resolve-all-logins first, memo, `admin|maintain|write`, fence strip) with two views: `trusted_verdict_bodies` (`.b`, unchanged contract) and new `trusted_verdict_comments <issue> [repo]` (`{t,b}` JSON per trusted comment). `_trusted_verdict_is_trusted_perm` and `_trusted_verdict_strip_fences` are extracted in this PR as a strictly behavior-preserving refactor. Both probes use the new view.
- D2: S3 is fixed in the same PR (S3 live; do not alter S3 soak state).
- D3: lint rule 5 in this PR (own counter and floor, no per-line opt-out).
- D4: existing measurement suffices; pre-merge read-only replay; post-merge the next scheduled sweep.
- D5: probe headers, runbook, learning; no tracker body edit, no tracker comment, no new ADR.

## Implementation Phases

RED before GREEN (`cq-write-failing-tests-before`): each phase's tests land in the same phase and are run RED against the
unmodified code first. Phase order follows dependency direction: lib (contract) before consumers.

### Phase 0 - Reproduce (RED) before touching any probe

0.1. In `ci-push-dedupe-soak-9512.test.sh` add fixture knob `privact`: the activation comment is authored by `{login:"priv-op"}`
with `authorAssociation:"CONTRIBUTOR"` (and `author_association` on the REST shape) and the fake `gh` answers
`collaborators/priv-op/permission` = `admin`. Row `r_privmember` (the same name in S2, S3 and the Guard Contract):
`build_fx ... 10 15 510 2568 privact` expects rc 0 `PASS`. COMMIT ORDER (durable RED): commit 1 = the dual-route fake (serves the OLD REST comments
route for the unmodified probe AND the new `issue view` route) + the RED row; run it against the UNMODIFIED probe and require BOTH
`FAIL: 10 push run(s) were elided with no activation on record` (rc 1, the sweeper's exact observed output) AND a `requests.log` line proving the old REST route
was actually hit (a RED caused by a missing route would be vacuous). Commit 2 (Phase 2) removes the REST arm. The in-suite, durable form of this RED proof is
the mutant `m-legacy-assoc` (Phase 2.3). Keep the commit-1 output for the PR body.
0.2. Same `r_privmember` in `ci-draft-light-soak-9728.test.sh` (S3-CONFIRMED + S3-ACTIVATED by a CONTRIBUTOR-association admin); unmodified probe: RED
(`light run(s) observed with no activation on record`) plus the REST-route `requests.log` line.

### Phase 1 - the lib: one core, two views, behavior-preserving first

1.1. Refactor `scripts/lib/trusted-verdict.sh` WITHOUT adding behavior (own commit). Acceptance gate for this step, run unchanged before any new row counts: `scripts/lib/trusted-verdict.test.sh`, `scripts/followthroughs/concierge-strand-754ee124-5733.test.sh`, `scripts/followthroughs/cpx22-invoice-reconcile-7431.test.sh`, `scripts/followthroughs/inngest-zot-client-authz-6500.test.sh` all pass as before.
- Extract `_trusted_verdict_is_trusted_perm <perm>` (`admin|maintain|write` -> rc 0) and `_trusted_verdict_strip_fences` (the awk, moved byte-for-byte; fix only the mis-indented comment). Each now occurs once in the file, which is what makes the lib mutation anchors unique. Keep the existing `if ! _trusted_verdict_permission "$login" "$repo" >/dev/null; then` line verbatim and 4-space-indented inside the core: the existing row-9 `sed` mutation keys on that exact text.
- Extract the internal core `_trusted_verdict_core <issue> <repo>`: one `gh issue view <issue> --repo <repo> --json comments` read (all pages, measured), drop author-less comments, resolve every distinct login via `_trusted_verdict_permission "$login" "$repo" >/dev/null` (a redirect, NEVER `$(...)`, so the memo survives; any rc 2 -> `return 2` BEFORE any output), then emit one record per trusted comment as `{t: (.createdAt // ""), b: <fence-stripped body>}` JSON, accumulating into a variable and printing once at the end (so rc 2 never leaves partial output). The core does NOT validate `createdAt` (the existing lib fixtures and the three live-consumer suites carry none; validating in the core breaks this gate). Keep: rc 2 = transient (never untrusted), the empty-memo guard, the bash >= 4 associative-array refusal.
- `trusted_verdict_bodies` becomes the `.b` view of the core with identical stdout/rc.
1.2. Add `trusted_verdict_comments <issue> [repo]` (own commit; renamed from the CTO-named `trusted_verdict_comments` at deepen-plan to keep the lib's `trusted_verdict_*` public prefix, so `LIB_CALL` becomes `trusted_verdict_(bodies|comments)` and covers future views) = the `{t,b}` view: one compact JSON object per trusted comment (emitted with `jq -c --arg`, never string-built), API order, `t` = `createdAt`. Validation lives ONLY here: every emitted `t` must match `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$` (S3 sorts `t` lexicographically and feeds it to `date -d`, which accepts natural language); a missing or non-matching `createdAt` -> rc 2 with empty stdout, never a default timestamp. Add the view's own rc/usage comment and update the lib header spots that mention only `trusted_verdict_bodies` (the memo sentence "WITHIN ONE `trusted_verdict_bodies` INVOCATION" and the `Usage:` block), stating the rc mapping (the probes map rc 2 to exit 3 via `fail_api`; concierge maps it to exit 2).
1.3. Hardening that is NEW behavior (own commit, after the 1.1 gate is green): in the core, a login that does not match `^[A-Za-z0-9][A-Za-z0-9_-]{0,38}$` is untrusted WITHOUT a permission request (the login is interpolated into a URL path; a bad one must also not become a permanent rc 2 for the whole thread). Rows: `a/../b`, `x?y`, a newline, a leading `-` each make zero permission requests and drop only that author.
1.4. `scripts/lib/trusted-verdict.test.sh` (new matrix; the existing rows already own bot/author-less/404/403/fence/memo for the bodies view):
- harness repairs first: (a) the stub appends `REFUSED <argv>` to a refused-log before `exit 64` and `run_case` fails any row when it is non-empty (the lib sends `gh issue view` stderr to `/dev/null` and `gh api` stderr to a tmpfile, so today a refusal is indistinguishable from a transient failure); (b) `run_case_raw` records rc and stdout independently (today stdout is discarded when rc is nonzero); (c) the permission arm serves `{"permission":"<p>"}` JSON, applies the supplied `--jq`, refuses a call with no `--jq`, and logs every permission request; the `issue view` arm logs every call; (d) a `mutant_lib` helper (anchor count must be exactly 1; supports multi-edit mutants) and a floor `MUT_RUN == MUT_CAUGHT && MUT_RUN >= N`.
- rows (each negative row has a positive control on the same input, differing only in the stubbed permission): M-H1 (the repro) a CONTRIBUTOR-association admin author counts in the `{t,b}` view; M-H2 OWNER-association author with permission `read` does not; M-H3 `triage` does not, `maintain` and `write` do (one row each); M-H4 parity: for one fixture the bodies view equals the `.b` projection of the `{t,b}` view, plus an ABSOLUTE row that a fenced marker (both spellings) is absent from the `{t,b}` output; M-H5 `t` equals the fixture `createdAt` byte-for-byte, a missing or non-ISO `createdAt` (`yesterday`, `+02:00` offset) -> rc 2 with empty stdout in the `{t,b}` view, and the bodies view still returns rc 0 on a `createdAt`-less fixture; M-H6 permission 403/5xx on the LAST of several distinct authors -> rc 2 with EMPTY stdout (via `run_case_raw`); M-H7 404 drops that author only, a second trusted author still comes through; M-H8 two comments by one author -> one permission request (memo; a request-log assertion); M-H9 more than 100 comments through the GraphQL shape are all returned (teeth: the mutant below); M-H10 one `issue view` call per `{t,b}` view invocation (request-log assertion); the 1.3 login-shape rows.
- lib mutants (anchors unique after 1.1): `triage` added to `_trusted_verdict_is_trusted_perm` (M-H3); `maintain` removed, `write` removed (M-H3 positive arms); predicate always true (`admin|maintain|write)` -> `*)`) (M-H2, M-H3); a jq pre-filter on `.authorAssociation` at the `select((.author.login // "") != "")` anchor (M-H1); `_trusted_verdict_strip_fences` body emptied (the ABSOLUTE fenced row, not parity); resolver called under `$(...)` (M-H1 positive control); two-edit mutant loop-1 `return 2` -> `continue` AND a per-record `printf` in loop 2 (M-H6); memo guard `if false` AND `sort -u` -> `cat` together (M-H8: each single edit is an equivalent survivor, because `sort -u` and the memo each independently guarantee one request - label the singles EQUIVALENT in the suite); `.comments[]` -> `.comments[0:100][]` (M-H9); `t` replaced by `""` (M-H5); the `{t,b}` view re-reading comments itself (M-H10); `--jq` dropped from the permission call (M-H1 via the refusing stub); the login-shape guard removed (1.3 rows); validation moved into the core (Phase 1.1 gate rows redden). Raise `MIN_ASSERTIONS` to the measured real count minus the self-test.

### Phase 2 - S2 probe on the `{t,b}` view

2.1. `ci-push-dedupe-soak-9512.sh`: `source` the lib the way `concierge-strand-754ee124-5733.sh` does
(`source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/trusted-verdict.sh"`, after the xtrace refusal and the tool
checks; lint rule 3 accepts that line, verified identical to concierge's); extend the tool-check loop (`for need in gh jq`) with `base64 awk mktemp sort` so a missing tool reads `CANNOT ESTABLISH: <tool> is not installed`, not a misleading 127 from the helper; replace lines 100-103 with
`trusted_json="$(trusted_verdict_comments "$tracker" "$REPO")" || fail_api "tracker $tracker comments (trusted-author resolution)"`
then `trusted="$(jq -r '.b' <<<"$trusted_json" | tr -d '\r')" || fail_api "tracker $tracker comments (projection)"`. Everything downstream (TS_RE, `last_on`, `census_marked`) is unchanged.
Behavior changes to state in the PR body and the runbook: fence stripping now applies to S2/S3 markers (a marker inside a fenced block counted before and is ignored now); trust narrows from `OWNER/MEMBER/COLLABORATOR` to permission `admin/maintain/write` (a `read`/`triage` collaborator stops counting).
2.2. Header lines 21-31 (and the `(d)` clause): say trust comes from the comment author's repository permission (admin/maintain/write, resolved at read time through the shared lib), not `author_association` (computed against the reading token's visibility; private members read as CONTRIBUTOR under `GITHUB_TOKEN`, #6617/#8389). Runtime message strings that say "owner, member or collaborator" change in ONE mechanical sweep to "a repository admin, maintainer or writer" - first `grep -n "owner, member or collaborator" scripts/followthroughs/*.test.sh` must be empty (the plan-review found no row asserts it).
2.3. `ci-push-dedupe-soak-9512.test.sh` (probe WIRING only; trust-matrix properties are the lib suite's):
- fake `gh`: restructure the top-level `[ "$1" = "api" ] || exit 64` so `issue` is handled; add an `issue view <N> --repo <r> --json comments [--jq ...]` arm (argv-strict) serving `$FX/comments-<N>.json` as `{"comments":[{author:{login},authorAssociation,createdAt,body}]}` and a `repos/*/collaborators/*/permission` arm reading `$FX/perms.tsv` (`login<TAB>perm|403|404`; stderr texts mirror the real `gh` - `(HTTP 404)` / `(HTTP 403)` - because the lib's 404 detection keys on that text; JSON `{"permission":...}` with the supplied `--jq` applied). Every arm logs to `requests.log`; every refusal appends `REFUSED <argv>` to `$FX/refused.log` before `exit 64`, and `expect` fails any row whose `refused.log` is non-empty (otherwise a refusal surfaces as the lib's rc 2 -> exit 3 and the rc-3 rows pass for the wrong reason). The old REST comments arm is removed in this commit (the RED commit of Phase 0 had both).
- fixtures: every comment carries a valid ISO `createdAt` (S2 never used the field; the new view requires it). The old association argument maps to a stable login + perms row (OWNER->`owner-op` admin, MEMBER->`member-op` write, COLLABORATOR->`collab-op` write, CONTRIBUTOR->`contrib-op` read, NONE->`none-op` 404) while every comment KEEPS its `authorAssociation` as a DECOY. The DEFAULT activation comment is authored by a CONTRIBUTOR-association admin (`priv-op`) so that roughly 40 existing rows, not two, would redden under an association-consulting mutant.
- new rows (appended to `ALL_ROWS`, so the always-PASS harness and the mutants can address them): `r_privmember` (repro), `r_assocowner` (association OWNER, permission `read` -> not trusted), `r_permfail` (403 on the activation author -> rc 3 `CANNOT ESTABLISH`; paired with `r_privmember` - identical argv, only the `perms.tsv` row differs), `r_badjq` (helper output not parseable by the projection -> rc 3), plus a `requests.log` assertion that the probe issued `issue view 4242 --repo jikig-ai/soleur --json comments` exactly once and one permission request per distinct human author. No `r_manycomments`: the fake serves any N, so nothing in the code could fail it; pagination evidence is the lib suite's `M-H9` mutant and the Phase 6.2 parity check.
- mutation tree: `mutant()` currently writes a lone `$TMP/mut-<name>.sh`, so the probe's relative `source` would resolve to nothing, the helper call would return 127 and `|| fail_api` would turn EVERY mutant "caught" for the wrong reason. Add `mk_tree <name>` building `$R/scripts/followthroughs/` with `$R/scripts/lib` a symlink to the real lib (probe-only mutants; lib mutants live in the lib suite). Port S3's crash detection (`MUT_CRASHED`, `note_crash`, and its three harness controls) into S2. Instrument controls: an identity copy must show zero reds across the full row set, and a copy with the symlink removed must red at least one row (the identity-green check subsumes any "No such file" text assertion, which `core_rows_quiet`'s `/dev/null` could not observe anyway). The shape-mutant loop (`$TMP/shape.sh`) uses the same tree; its comments-route pair (`api --paginate "repos/$REPO/issues/$tracker/comments`) no longer exists in the probe and is dropped (the `requests.log` assertion replaces it); the other pairs stay.
- re-anchor and retire: `m-trusted` -> delete the helper call's `|| fail_api ...` (reds `r_commentsfail`/`r_permfail`); `m-crlf` -> the new `tr -d '\r'` line; `m-no-collab`/`m-contrib` are retired (their anchor `IN("OWNER", "MEMBER", "COLLABORATOR")` is gone; the lib suite owns the equivalents); add `m-legacy-assoc` (replace the helper call with a raw `gh issue view ... --jq 'select(.authorAssociation|IN(...))'` through the same fake arm: reds `r_privmember` and `r_assocowner` - the durable form of the Phase 0 RED proof), `m-project-raw` (credited ONLY to the negative rows `r_assocowner`/`r_untrusted_*`/`r_contrib`: an over-trusting mutant cannot redden a positive control) and `m-empty-helper` (helper call replaced by `""`: every activation row reds).
- floors: `_FLOOR` and the harness floors are set to the MEASURED post-change counts; the mutant-count floor (baseline `-ge 50`) may drop only by the three retirements above, each paired with its replacement; the always-PASS harness count is recomputed with the new rows in `ALL_ROWS` (`r_privmember` expects PASS, so it is not red under an always-PASS probe).

### Phase 3 - S3 probe on the same view

3.1. `ci-draft-light-soak-9728.sh` lines 109-113: `comments="$(trusted_verdict_comments "$TRACKER" "$REPO")" || fail_api "tracker $TRACKER comments (trusted-author resolution)"`; the S3 projection (`trusted="$(jq -r '.b' <<<"$comments" 2>/dev/null | tr -d '\r')"`, line 113) currently has NO failure check - an empty projection after a jq failure erases ACTIVATED/DEACTIVATED/CONFIRMED and reproduces the very false FAIL this plan fixes - so add `|| fail_api "tracker $TRACKER comments (projection)"` to it and to the `conf_iso` jq (line 121), with a row feeding malformed helper output expecting exit 3. The downstream `jq -r '.b'` greps and the `S3-CONFIRMED` jq over `.t`/`.b` are otherwise unchanged (same `{t,b}` shape; `t` is now an ISO `createdAt`). Header lines 20 and 35-37, the tool-check loop and the message strings as in 2.1/2.2.
3.2. `ci-draft-light-soak-9728.test.sh`: the same wiring-only harness migration (its `addc` already writes a time field; it now writes `createdAt` and `author`; its `mutant_probe`, shape loop and the hard-coded `$TMP/mut-c-crash-rt.sh` `bash -n` check move to the mirrored tree TOGETHER), same decoy rule, same default-activation-by-CONTRIBUTOR-admin, same `REFUSED` log, same mutation tree and instrument controls. New rows only: `r_privmember` (private-member admin posts CONFIRMED then ACTIVATED -> the canonical PASS shape), `r_late_conf_private` (CONFIRMED after ACTIVATED by a private-member admin still FAILs: ordering uses the preserved `t`), `r_assocowner`, `r_permfail`, `r_badjq`; re-anchor/retire mutants as in 2.3 (S3 has 64 mutants, floor 45: the same retire-and-replace rule); recompute `_FLOOR` (baseline 162). If the migrated harness still prints the pre-existing `requests.log: No such file` stderr line, it goes in the deferred list below; do not investigate it here.
3.3. HARD CONSTRAINT: the S3 work posts no marker, sets no variable, and leaves PR #9707 and `ci.yml` alone.

### Phase 4 - lint: rule 5, the rule-4 denominator and the rule-4 branch anchor (D3)

4.1. `scripts/lint-followthrough-varq-ban.sh`: add RULE 5 - over every non-test `*.sh` in the target dir, comment-stripped exactly as rule 4 strips (`sed -E 's/^[[:space:]]*#.*$//'`: WHOLE-LINE comments only; a trailing `# why` mention on an executable line DOES fire, a documented limitation - a quote-aware strip is more mechanism than a spelling ban deserves), any line matching `author_?[aA]ssociation` case-insensitively (`grep -qiE`) is a violation citing file:line with a `rule 5:` prefix, naming the permission lib and the #6617/#8389 measurement; no per-line opt-out. Unique markers on every mutable line (rule 4 already contains the same strip and `! -name '*.test.sh'` text, so text anchors would occur twice): `# rule5-grep`, `# rule5-strip`, `# rule5-walk`, `# rule5-exempt`, `# rule5-loop`, `# rule5-count`. Counter and floor: `scanned_rule5` must NOT be a bare `find | wc -l` (byte-identical to rules 1 and 3, whose `MIN_PROBES` `exit 2` fires first, so its floor would be unreachable - the failure rule 4's own header records); count the probes whose comment-stripped code rule 5's predicate actually examined AND add a regex canary run before the walk (`grep -qiE "$RULE5_RE"` must match both `.author_association` and `.authorAssociation`, else `exit 2` naming rule 5), so a neutered regex trips something a file count cannot. The floor is derived from the measured walk at work time, with a test-only override env var named after what is counted, in the sibling style (`VARQ_BAN_MIN_RULE5_FILES`, like `VARQ_BAN_MIN_COMMENT_READERS`). Update the header ("Four rules"), the `FAILED:` summary line, the clean-line counters, and rewrite the rule-4 header paragraphs that argue a bare-word ban "cannot be documented" and that printing an observed value "is not banned", so they describe rule 5 accurately (rule 5 bans the executable-line spelling; rule 4 owns the obligation).
4.2. Widen `LIB_CALL` to `trusted_verdict_(bodies|comments)`. After the migration S2/S3 have no raw `issues/N/comments` read, so without the widening they leave rule 4's denominator and `scanned_rule4` falls 8 -> 6 (the "floor that punishes compliance" the lint's own header names). Also widen `VERDICT_BRANCH` from `RESULT:` to `RESULT:|S[0-9]+-(ACTIVATED|DEACTIVATED|CONFIRMED|EXIT-CENSUS)`: a future marker probe (an `S4-...`) that reads `issues/N/comments` directly and branches on a marker, with NO author filter at all, has no `RESULT:` line and no `author_association` spelling, so it passes rules 4 and 5 today (the security-sentinel's exploit); after this widening it fires rule 4. Pre-check at work time that no existing direct reader matches the widened anchor (measured at plan time: only S2/S3, which no longer read directly after Phase 2-3). The marker-name convention `S<n>-...` is brittle by nature: record it in the rule-4 header as the convention the anchor encodes.
4.3. `scripts/lint-followthrough-varq-ban.test.sh` rows (each mutates by marker, `sed '/# rule5-.../d'`, asserting the mutation landed per marker): R5-M1 a probe that sources the lib (precondition satisfied) AND reintroduces an inline `select(.author_association ...)` -> exit 1 at TRUE line with `rule 5:`; R5-M2 camelCase `.authorAssociation` -> exit 1 with `rule 5:`; R5-M3 must-PASS: the word only in a WHOLE-LINE header comment; R5-M4 CHARACTERIZATION row (labelled as such): a trailing `# why` mention on an executable line -> exit 1 (pins the documented false positive; breaks on purpose if the limitation is ever fixed); R5-M5 must-PASS: the word in a `.test.sh` fixture (exempt); R5-M6 second probe after a compliant first is also cited (walk does not stop); R5-M7 DISPATCH: guard COPY with the `# rule5-grep` line deleted -> exit 0 on the M1 fixture; R5-M8 guard COPY with the counter forced to 0 -> production-mode run exits 2 naming rule 5 and rule 1's "expected the full set" did NOT fire; R5-M9 guard COPY with the regex canary line deleted AND the regex neutered -> exit 2 or the M1 fixture still reddens (the canary is not dead code); R5-M10 an unfiltered marker reader (reads `issues/N/comments`, branches on `S4-ACTIVATED`, no author filter, no lib call) -> exit 1 with `rule 4:` (the 4.2 widening); R5-H1 must-PASS non-canonical: a compliant probe with different variable names that sources the lib and calls only `trusted_verdict_comments`, counted as `checked 1 comment-reading probe(s)` in a hermetic sandbox (kills the `LIB_CALL`-revert mutant without pinning the live corpus count); R5-H2 live tree: 0 rule-5 hits. Existing R4-M2c (an inline `.authorAssociation` filter) gains a `grep -q 'rule 4:'` assertion, since rule 5 now ALSO fires on that fixture and a dead rule 4 would otherwise stay green. Set the suite floor (baseline 89, floor 80) to the measured count.

### Phase 5 - documentation (D5), no issue-body edits

5.1. `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`: add to the operator-confirmed-probe section (a) marker probes use `trusted_verdict_comments`, the `{t,b}` shape; (b) the semantics, as four sentences: trust is resolved at READ time, so a demoted commenter's older markers stop counting (an old ACTIVATED can become live again if its DEACTIVATED author is demoted) and a later-promoted user retroactively legitimizes their earlier markers; `write` is enough to close a tracker, which is broader than the issue text's "owner/member/collaborator"; `createdAt` is creation time, not edit time (gh exposes no `updatedAt`), so S3's CONFIRMED-before-ACTIVATED check guards operator mistakes, not tampering by a writer; a seated bot must never relay raw issue text at line start; (c) the behavior changes (fence stripping now applies; `read`/`triage` collaborators stop counting); (d) REST `author_association` and GraphQL `authorAssociation` are the same defect, rule 5 bans both spellings on executable lines, and the "an inline `authorAssociation` select is subsumed by rule 4" sentences (runbook lines ~179-211) are reworded: rule 5 bans the spelling, rule 4 owns the obligation.
5.2. `plugins/soleur/skills/ship/SKILL.md` (lines ~2799-2801) and `plugins/soleur/skills/ship/references/followthrough-stub-template.sh` (lines ~50-66): both repeat "call `trusted_verdict_bodies`" and the "subsumed by rule 4" sentence; name `trusted_verdict_comments` for marker probes and rule 5, so new probes copy the right form.
5.3. Amend `knowledge-base/project/learnings/2026-10-09-a-cost-lever-must-not-be-able-to-redden-the-run-it-saves.md` Solution bullet ("filtered to `author_association` OWNER/MEMBER/COLLABORATOR") to point at the helper (append a dated correction; do not rewrite history).
5.4. ONE new learning under `knowledge-base/project/learnings/` (author picks the date; topic: rule 4's `RESULT:` anchor let marker probes stay green over the defect it claims to ban, and the S3 sibling was live but masked; the two-tokens-same-code measurement method; the soak PRs #9808 / #9885 merged with zero reviews and the lib unmentioned). Directory + topic only in tasks.
5.5. Do NOT edit the #9818 / #9728 bodies, post tracker comments, add an ADR, or touch `ci.yml`, Actions settings, `CI_PUSH_DEDUPE`, `CI_DRAFT_LIGHT`.

### Phase 6 - verification (read-only)

6.1. Run each directly (never a hand-enumerated subset): `bash scripts/lib/trusted-verdict.test.sh`, the three live-consumer suites named in 1.1, `bash scripts/lint-followthrough-varq-ban.test.sh`, `bash scripts/lint-followthrough-varq-ban.sh`, `bash scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh`, `bash scripts/followthroughs/ci-draft-light-soak-9728.test.sh`; then the ratchets that read tracked files: `bash plugins/soleur/test/fixture-relative-assert.test.sh`, `bash scripts/test-affected-kb-consumers.test.sh` (both keep `*.baseline.txt` files: regenerate with the suites' documented command, never by hand), `python3 scripts/lint-guard-contract.py <this plan>`, `python3 scripts/lint-infra-no-human-steps.py <this plan>`, `shellcheck` on the edited scripts. Expect rebase conflicts: #9788 (e7c64c42dc) and #9554 (ed6a77b868) already touched the lib and lint test files on main; rebase on `origin/main` before measuring floors.
6.2. Pre-merge real-comment replay (read-only, operator token; a manual check, not a committed fixture per `cq-test-fixtures-synthesized-only`), run after Phase 1: `GH_TOKEN="$(gh auth token)" bash -c 'source scripts/lib/trusted-verdict.sh; trusted_verdict_comments 9818 | jq -r .b | tr -d "\r" | grep -c "^S2-ACTIVATED: 2026-10-11T09:48:17Z$"'` expects `1`; the same for `9728` with `grep -c -e "^S3-ACTIVATED: 2026-10-11T09:43:31Z$" -e "^S3-CONFIRMED: "` expects `2`; the negative control pair: `gh issue view 9818 --repo jikig-ai/soleur --json comments --jq '[.comments[].body | select(startswith("### Sweeper run"))] | length'` is greater than 0 while `trusted_verdict_comments 9818 | jq -r .b | grep -c "### Sweeper run"` is `0` (the control proves the zero is the filter, not an empty read); and the pagination parity check: `gh issue view 9777 --repo jikig-ai/soleur --json comments --jq '.comments | length'` equals `gh api --paginate repos/jikig-ai/soleur/issues/9777/comments --jq 'length' | jq -s add` (212 at plan time; gh 2.102.0 on this host, and the sweeper runner image ubuntu-24.04 20261002.596 lists GitHub CLI 2.102.0 in the runner-images readme).

## Files to Edit

- `scripts/lib/trusted-verdict.sh` (core + two views + extracted predicates; header memo sentence, `Usage:` block and per-function rc comments)
- `scripts/lib/trusted-verdict.test.sh` (stub + rows + `mutant_lib` + floor)
- `scripts/followthroughs/ci-push-dedupe-soak-9512.sh`
- `scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh`
- `scripts/followthroughs/ci-draft-light-soak-9728.sh`
- `scripts/followthroughs/ci-draft-light-soak-9728.test.sh`
- `scripts/lint-followthrough-varq-ban.sh`
- `scripts/lint-followthrough-varq-ban.test.sh`
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
- `plugins/soleur/skills/ship/SKILL.md` (lines ~2799-2801: names `trusted_verdict_bodies` only and repeats the "subsumed by rule 4" claim)
- `plugins/soleur/skills/ship/references/followthrough-stub-template.sh` (lines ~50-66, same)
- `knowledge-base/project/learnings/2026-10-09-a-cost-lever-must-not-be-able-to-redden-the-run-it-saves.md` (appended correction)

## Files to Create

- `knowledge-base/project/learnings/<date>-<topic>.md` (one learning; directory + topic only, author picks the date)

No new `*.test.sh` is created, so no `scripts/suite-shard-legs.tsv` / `scripts/suite-durations.tsv` / `test-all.sh` registration row is added
(grepped: both probe suites are registered at `scripts/test-all.sh` lines ~6289/6300 and the lib suite by the `scripts/lib/*.test.sh` glob). The
three live consumers of the lib (concierge, cpx22, inngest-zot) are NOT edited but must stay green (Phase 1.1 gate). Both probe files are
CODEOWNERS-bound to `@deruelle` (`.github/CODEOWNERS` lines 29-32): no active ruleset sets `require_code_owner_review` (git-history check: rulesets 14145388, 13304872, 13044280), the owner is also the PR author, and #9808 / #9885 merged with zero reviews, so request the owner's review as advisory and do not describe the PR as independently approved.
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
| Lib core + `trusted_verdict_comments` view | "recommend same PR if the shared logic is a trivial helper" (asks 2, 5) | asked |
| Extraction of `_trusted_verdict_is_trusted_perm` / `_trusted_verdict_strip_fences` (behavior-preserving) | — | inferred — justification: CTO D1b; without it the new view duplicates the trust predicate and fence strip (drift) and the lib mutants cannot anchor uniquely |
| S3 probe + harness migration | "Decide whether the sibling S3 script gets the same fix in this PR" (ask 5) | asked |
| Lint rule 5 + `LIB_CALL` widening | — | inferred — justification: CTO D3; rule 4's anchor (`RESULT:`) left both probes green over the defect, and without the widening the migration shrinks rule 4's denominator 8 -> 6 |
| Runbook sentence, learning, amended 2026-10-09 learning | — | inferred — justification: CTO D5; the 2026-10-09 learning prescribes the defective filter and is the copy-paste source |
| Harness mutation tree (mirrored dirs, lib symlink, identity row) | "reproduce with a failing test" (ask 1) | inferred — justification: the probes now source the lib by relative path; the existing lone-file copy breaks every mutant |
| Login-shape guard, ISO `createdAt` regex (marker view only), `|| fail_api` on the S3 projection | — | inferred — justification: the security review measured that the login is interpolated into a URL path and that S3 sorts `t` lexicographically and passes it to `date -d` (natural language accepted); an unchecked jq projection reproduces this very false FAIL |
| `VERDICT_BRANCH` widening to the `S<n>-...` markers | — | inferred — justification: a future marker probe with no author filter and no `author_association` spelling passes rules 4 and 5 today; this is the "absence of the right mechanism" the lint header says it must catch |
| ship `SKILL.md` and `followthrough-stub-template.sh` edits | — | inferred — justification: both repeat "call `trusted_verdict_bodies`" and the "subsumed by rule 4" sentence that rule 5 falsifies; new probes copy these |
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

Three guards ship: the lib core/views, the probes' use of them, and the lint. The class to defeat for each: a trust decision whose window, chokepoint or identifier set is narrower than the property. Each matrix was derived from the design before the code and then corrected by the test-design review (every row below was checked for whether a single mutant can actually redden it).

### Guard 1 - the trusted-verdict core and its two views

**Property.** A comment's text reaches a probe only if its author's effective repository permission (resolved at read time against the reading token's real access) is admin, maintain or write, and any unreadable resolution yields rc 2 with no output, identically for the bodies view and the `{t,b}` view.

**Assembly.** Every path from "a comment exists on the tracker" to "its text reaches a probe's marker grep": the single `gh issue view --json comments` read (all pages, measured), the author-less drop, the login-shape guard, the distinct-login resolution loop, the memo table, `_trusted_verdict_is_trusted_perm`, `_trusted_verdict_strip_fences`, the accumulate-then-print emit, both public views, and BOTH probe call sites. The chokepoint is the core; a second read or emit path (an early print inside the loop, a view that bypasses the core, a probe that calls `gh issue view --json comments` itself) is the defect. Members drift (new probes, new marker names); the structural invariant is "probes receive bodies only through a view of the core", enforced by lint rule 4 (widened) and rule 5.

**Mutation matrix.**

| # | Edit (mutated COPY of the lib; multi-edit where stated) | Must redden |
|---|---|---|
| 1 | add `triage` to `_trusted_verdict_is_trusted_perm`; separately remove `maintain`; separately remove `write` | M-H3 (negative arm, then each positive arm) |
| 2 | predicate always true (`admin|maintain|write)` -> `*)`) | M-H2, M-H3 |
| 3 | jq pre-filter on `.authorAssociation` at the `select((.author.login // "") != "")` anchor | M-H1 (positive control) |
| 4 | empty `_trusted_verdict_strip_fences` | the ABSOLUTE fenced-marker row (not the parity row, which stays green when both views share the emptied function) |
| 5 | call `_trusted_verdict_permission` under `$(...)` (memo lost) | M-H1 (positive control), M-H8 |
| 6 | TWO edits: loop-1 `return 2` -> `continue` AND a per-record `printf` in loop 2 | M-H6 (last author fails -> partial output, observed via `run_case_raw`) |
| 7 | TWO edits: memo guard `if false` AND `sort -u` -> `cat` (each single edit is an equivalent survivor and is labelled EQUIVALENT in the suite) | M-H8 (request-log count) |
| 8 | `.comments[]` -> `.comments[0:100][]` | M-H9 (more than 100 comments) |
| 9 | replace `t` with `""`; separately move ISO validation into the core | M-H5; the Phase 1.1 gate rows |
| 10 | the `{t,b}` view re-reads comments itself (a second read path) | M-H10 (request-log: one `issue view` per call) |
| 11 | drop `--jq` from the permission call | M-H1 via the refusing stub |
| 12 | remove the login-shape guard | the 1.3 rows (zero-request assertions) |

**Harness rows.** Suite edits that must go RED: neuter the stub so the permission endpoint always answers `admin` (M-H2, M-H3, M-H7 must red, proving the rows can fail); a stub refusal (`REFUSED` log non-empty) must red the row that provoked it; must-PASS non-canonical inputs: a trusted author whose login has digits and interior hyphens with CRLF line endings in the body; a second trusted author after a compliant first; a `createdAt`-less fixture through the bodies view (rc 0).

**Anchor.** No stored value is compared (a live API answer decides), so no stored-value anchor applies; the stored values are suite floors, anchored by the set-to-measured rule in 2.3/3.2/1.4 and by `MUT_RUN == MUT_CAUGHT` with a floor in the lib suite.

### Guard 2 - the probes' consumption of the view (S2 and S3)

**Property.** A probe's `active`/`census`/`confirmed` state is derived only from `trusted_verdict_comments` output, an unreadable trust decision or an unparseable projection is exit 3 (never "no marker", never PASS), and S3's ordering of CONFIRMED before ACTIVATED uses the preserved comment time.

**Assembly.** For each of the two probes: the `trusted_verdict_comments` call and its `|| fail_api`, the `jq -r .b` projection and its `|| fail_api` (S3's was unchecked), every grep that reads `$trusted` (`last_on`, `last_off`, `census_marked`, S3 `first_on`, `conf_iso`), and the sweeper's exit-code contract (0/1/2/3/78). A probe that sources the lib and then reads comments directly is the "both endpoints pinned, wire unpinned" shape; rule 4 already forbids it.

**Mutation matrix.**

| # | Edit (mutated COPY of the probe in the mirrored tree, lib symlinked) | Must redden |
|---|---|---|
| 1 | delete `|| fail_api "tracker ... comments (trusted-author resolution)"` | `r_commentsfail`, `r_permfail` |
| 2 | replace the helper call with a raw `gh issue view ... --jq 'select(.authorAssociation|IN(...))'` (`m-legacy-assoc`) | `r_privmember`, `r_assocowner` (the durable RED proof) |
| 3 | project `.b` from an over-trusting source (`m-project-raw`) | the NEGATIVE rows `r_assocowner`, `r_untrusted_*`, `r_contrib` only (an over-trusting mutant cannot redden a positive control) |
| 4 | delete the projection's `|| fail_api` (both probes) | `r_badjq` |
| 5 | drop the `tr -d '\r'` | `r_crlf` |
| 6 | S3: take `conf_iso` from the latest instead of the earliest | `r_conf2`, `r_late_conf_private` |
| 7 | helper call replaced with a literal empty string (`m-empty-helper`) | every activation row |
| 8 | second probe left on the old filter after the first migrated | its own `r_privmember` (stays RED until Phase 3) |

**Harness rows.** `build_fx` edit that must RED: the decoy `authorAssociation` flipped so OWNER carries permission `read` (`r_assocowner`); must-PASS non-canonical: activation by a `COLLABORATOR`-association author with `write`, and by a `NONE`-association author with `maintain` (the contract permits both); instrument controls: an identity copy through the mirrored tree must show zero reds, and a copy with the lib symlink removed must red at least one row (proves the tree, not the mutant, is sound); each rc-3 row has a same-argv success twin differing only in the `perms.tsv` row.

**Anchor.** Post-change suite floors are set to measured counts (2.3, 3.2); the real-comment replay (6.2) is the external anchor that the live markers survive the real helper.

### Guard 3 - lint rule 5 and the widened rule-4 anchors (no probe filters on author association; no marker reader skips the lib)

**Property.** No non-test probe under `scripts/followthroughs/` contains an executable (whole-line-comment-stripped) reference to `author_association` or `authorAssociation`, in any case, with or without the underscore, and no probe that reads issue comments and branches on a `RESULT:` or `S<n>-...` marker does so without calling the trusted lib.

**Assembly.** The target-dir walk (`find "$TARGET_DIR" -type f -name '*.sh' ! -name '*.test.sh'`), the comment strip, the grep, the violation emit, the counter and its floor and regex canary; rule 4's `LIB_CALL` (denominator the migration must not shrink) and `VERDICT_BRANCH` (the obligation's trigger). Chokepoint: the single grep line plus the rule-4 obligation; a second spelling (`author-association`, a runtime-built field name `K=author_association; .[$K]`) is out of rule 5's reach - recorded as a known residual, mitigated by rule 4's positive obligation (call the lib).

**Mutation matrix.** (each by unique marker, `sed '/# rule5-.../d'`, asserting the mutation landed)

| # | Edit (mutated COPY of the guard, or fixture) | Must redden |
|---|---|---|
| 1 | delete the `# rule5-grep` line (DISPATCH) | R5-M7 (M1 fixture exits 0) |
| 2 | force `scanned_rule5` to 0 | R5-M8 (production-mode exit 2 naming rule 5; rule 1's message did not fire) |
| 3 | grep case-sensitive (`-i` removed) | R5-M2 (camelCase) |
| 4 | stop at the first violating file (`# rule5-loop`) | R5-M6 |
| 5 | comment strip removed (`# rule5-strip`; whole-line comments now fire) | R5-M3 |
| 6 | `.test.sh` exemption removed (`# rule5-exempt`) | R5-M5 |
| 7 | `LIB_CALL` reverted to `trusted_verdict_bodies` only | R5-H1 (hermetic denominator row) |
| 8 | `VERDICT_BRANCH` reverted to `RESULT:` | R5-M10 (an unfiltered `S4-ACTIVATED` direct reader) |
| 9 | regex canary line deleted AND the regex neutered | R5-M9 |

**Harness rows.** Suite edit that must RED: an always-exit-0 guard stub must redden every R5 must-FAIL row; must-PASS non-canonical: a compliant probe with different variable names that sources the lib and mentions the word only in a whole-line `# why` comment. Precondition-satisfied-yet-property-fails row: a probe that sources the lib (precondition) AND filters inline on `.author_association` (property violated) must still FAIL (R5-M1 builds exactly this). R5-M4 is a labelled characterization row (the documented trailing-comment false positive).

**Anchor.** The rule is validated against the tree its own remediation produces: after Phases 2-3 the live tree has zero hits and the denominator keeps counting the migrated probes (R5-H1, R5-H2); the remediation's own text (the lib header, the probe headers) mentions the word only in whole-line comments, which the strip must pass (R5-M3). Rule 4's R4-M2c gains a `rule 4:` message assertion because rule 5 now also fires on its fixture.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 RED proof: Phase 0 rows `r_privmember` (S2 and S3) fail against the UNMODIFIED probes with the sweeper's own FAIL text and pass after Phases 2-3 (evidence pasted in the PR body).
- [x] AC2 `git grep -niE 'author_?association' -- 'scripts/followthroughs/*.sh' ':!scripts/followthroughs/*.test.sh' | grep -vE ':[0-9]+:[[:space:]]*#'` prints nothing (lint rule 5 enforces it; paste the lint's own clean line).
- [x] AC3 All of Phase 6.1 exit 0, every mutant caught, floors SET to the measured counts (baselines 13/89/121/162; mutant-count floors may drop only by the listed retirements, each paired with its replacement; every new row is a function in `ALL_ROWS`), and the three live-consumer suites (concierge, cpx22, inngest-zot) pass unchanged against the refactored lib (Phase 1.1 gate, separate commit).
- [x] AC4 Real-comment replay (Phase 6.2) prints `1`, `2`, `0` (with the greater-than-zero control) and the GraphQL/REST comment-count parity on #9777 matches (212 at plan time).
- [x] AC5 Fail-closed rows exist and are GREEN: permission 403/5xx -> `CANNOT ESTABLISH` rc 3 (S2 and S3), 404 drops that author only, last-author failure leaves no partial output.
- [x] AC6 `git diff --quiet origin/main...HEAD -- .github/workflows/ci.yml .github/workflows/scheduled-followthrough-sweeper.yml` exits 0 (merge-base form), and the diff contains no `gh variable`, `gh workflow run`, or marker-posting command.
- [ ] AC7 PR body: `Ref #9818` only; no `Closes|Fixes|Resolves`; no sentence citing ADR-270 as accepted canary evidence; no "canary closed" phrasing; no operator checklist (this PR has no operator step).
- [x] AC8 `python3 scripts/lint-guard-contract.py` and `python3 scripts/lint-infra-no-human-steps.py` pass over this plan; `fixture-relative-assert` and `test-affected-kb-consumers` ratchets run directly and pass; `shellcheck` clean on the edited scripts.
- [ ] AC9 Review by `@deruelle` requested as advisory (CODEOWNERS binds both probe files, but no ruleset enforces code-owner review and the owner authors the PR); the PR body says so.
- [x] AC9b Lint: `VERDICT_BRANCH` widening kills an unfiltered `S4-ACTIVATED` direct reader (R5-M10) and the live tree stays clean; rule-4 denominator row R5-H1 is hermetic.

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
10. Lint: reintroduced filter in either spelling -> exit 1 `rule 5:`; whole-line comment mention -> exit 0; trailing mention -> exit 1; hermetic denominator counts a `trusted_verdict_comments`-only probe.
11. Real-comment replay on #9818/#9728 (read-only, operator token).

## Risks

- The lib refactor touches code three live probes depend on: the Phase 1.1 gate (four suites unchanged) must pass BEFORE any new row is added, and the refactor must be a separate commit from the new view so a revert is clean.
- Harness rewrite: the fake `gh` must grow the `issue view` and permission arms without loosening its exit-64 strictness (an answer-anything stub puts the fixture above the code under test).
- Mutation tree: probe copies must resolve their `source` (lib symlink) or every new mutant is "caught" for the wrong reason; the identity-copy row and the `No such file` assertion are the guard.
- Permission is resolved at read time: a commenter demoted later un-trusts earlier markers (consistent with the existing lib; documented). `createdAt` is creation time, not edit time.
- A real marker comment inside a fenced block would be dropped by the strip; Phase 6.2 checks the live markers.
- Sweeper token rate: one permission request per distinct human commenter per probe per sweep (#9818 and #9728 each have one human author); negligible against ~1000/hour.
- The sweeper launches probes through `FT_LAUNCHER` (`scripts/sweep-followthroughs.sh`, not a bare `env -i` any more) with `PATH`, `HOME`, the forwarded secrets and `SOLEUR_FT_EARLIEST`; no `TMPDIR`, so `mktemp` falls back to `/tmp` (fine). The tool-check loop names `base64 awk mktemp sort` so a missing tool reads as such.
- Pagination of `gh issue view --json comments` is measured on gh 2.102.0 (212/212, 102/102, 1720/1720); the sweeper runner image's readme lists the same version. A silently truncated read would drop the newest comments (where a DEACTIVATED marker lives); the Phase 6.2 parity check and M-H9's `[0:100]` mutant are the guards, and a gh downgrade on the runner image is the residual.
- The fence strip toggles on any fence line without matching the closer to the opener (not CommonMark): a nested/mixed fence can leave quoted marker text live. Only a trusted writer can produce it (an accident risk, not a forgery path) and the refactor is byte-for-byte by CTO ruling; deferred below.
- Rebase conflicts: #9788 and #9554 already changed the lib test and the lint on main; rebase before measuring floors.
- Rule 5 is a spelling ban (CTO-ruled) with a whole-line-comment strip; a runtime-built field name evades it - rule 4's widened positive obligation is the backstop.

## Deferred (tracking issues to file at ship; each cites re-evaluation criteria; milestone `Post-MVP / Later` unless the roadmap says otherwise)

- Fence strip is not CommonMark (track opener character/length, close only on the same): re-evaluate when any trusted-marker body is observed inside a nested fence, or at the next lib change. Deviating would break the byte-for-byte refactor gate.
- Unfiltered sentinel readers outside `scripts/followthroughs/`: `scripts/watch-live-verify-pass.sh:49` and `.github/workflows/codeql-1537-revisit-watch.yml:92` grep comments for a record-once sentinel with no author filter (a forged sentinel suppresses the watcher). Re-evaluate: when either gates anything beyond a nag.
- `plugins/soleur/skills/community/scripts/github-community.sh:620-645` tallies external commenters by association (private members miscount as external; metric only). Re-evaluate: when the count feeds a decision.
- The S3 suite's pre-existing `requests.log: No such file` stderr line (only if it survives the harness migration).
- Sweeper directive validator accepting a `script=` path that ends `.test.sh` (exempt from every rule): re-evaluate with the next sweeper change.

## Observability

```yaml
liveness_signal:
  what: the daily sweeper comment on #9818 (and #9728) is produced by the migrated probes and no longer reports a trust-dropped marker
  cadence: daily at 18:00 UTC (scheduled-followthrough-sweeper)
  alert_target: the sweeper's own tracker comment and its red run on a probe failure
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml
error_reporting:
  destination: the probe's exit code (3 CANNOT ESTABLISH on any unreadable trust decision) rendered by the sweeper as a tracker comment
  fail_loud: yes, rc 2 from the lib maps to exit 3 and a visible comment; never to "no marker"
failure_modes:
  - mode: permission endpoint unreadable under GITHUB_TOKEN (403/5xx)
    detection: probe exit 3 and a CANNOT ESTABLISH sweeper comment naming the trusted-author resolution
    alert_route: sweeper comment on the tracker
  - mode: the trust filter regresses to association again
    detection: lint-followthrough-varq-ban rule 5 (and rule 4 widened) in test-all
    alert_route: red CI on the PR
  - mode: truncated comment read drops a DEACTIVATED marker
    detection: pagination parity check (Phase 6.2) and the lib mutant on the 100-comment slice
    alert_route: red lib suite
logs:
  where: the sweeper job log and the tracker comment (last 4 KB of probe output)
  retention: GitHub Actions default log retention
discoverability_test:
  command: bash scripts/lint-followthrough-varq-ban.sh
  expected_output: followthrough-varq-ban: clean
```

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this plan fills it (`none`, with the scope-out line).
- Never wrap `_trusted_verdict_permission` in `$(...)` inside the core (memo loss, learning 2026-09-19); the views are called under `$(...)` by the probes, which is fine because the memo is only needed within one call.
- Do not rename the `S2-*`/`S3-*` markers or change `TS_RE`: both are asserted by existing rows and by live tracker comments.
- Do not run `gh variable set/delete`, post any `S2-*`/`S3-*` marker, or comment on #9818/#9728 while verifying.
- Path literals were verified with `git ls-files` at plan time (`scripts/lib/trusted-verdict.{sh,test.sh}`, `scripts/lint-followthrough-varq-ban.{sh,test.sh}`, `.github/CODEOWNERS`, `plugins/soleur/test/fixture-relative-assert.test.sh`, `scripts/test-affected-kb-consumers.test.sh`).
- Diff-scope ACs must name the files the pipeline also writes: `knowledge-base/INDEX.md` (if regenerated) and `knowledge-base/project/specs/feat-one-shot-sweeper-probe-activation-lookup/` (tasks.md, decision-challenges.md, session-state.md).
