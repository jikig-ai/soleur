---
title: "security: runbook 6894 destroy read-back sends the read-only Hetzner token on stdin, pinned by the sole-copy suite"
type: fix
date: 2026-11-11
slug: security-runbook-6894-destroy-readback-stdin-header
branch: feat-one-shot-12616-6894-readback-stdin-header
issue: 12616
closes: 12616
priority: p3-low
domain: engineering
brand_survival_threshold: none
---

# security: runbook 6894 destroy read-back sends the read-only Hetzner token on stdin

## Enhancement Summary

**Deepened on:** 2026-11-11.

**Agents used:** security-sentinel, test-design-reviewer, a verify-the-negative sweep (general-purpose), and the CTO
agent for four new technical rulings (8a-8d in `decision-challenges.md`). This was a targeted subset, not the full
review roster, because the plan-review panel (DHH, Kieran, code-simplicity, the CTO) had already run.

**Key improvements:**

1. **Observability section** added, with a discoverability test that prints `0` before the fix and `2` after.
2. **Precedent diff** against `scripts/lib/bearer-curl.sh` (deepen-plan 4.4).
3. **The census gains p3** (`curl` plus `api.hetzner.cloud`; widened at review to `api.hetzner.cloud` on any line, ruling 9b) and Guard 1 row 10, closing the variable-staged bearer
   (ruling 8a). On today's files p3 flags the same three lines.
4. **H18 checks why a row went red, not just that it did.** `n3b` messages carry fixed tags, each row names the tag
   it needs, mutations are confined to their section and checked to have landed there, and the slot check returns
   early so H-b is no longer vacuous.
5. **The Phase 4 stub run can now show a leak.** A per-call log replaces the word-and-exit check, which could not tell
   a refusal from a 401. The run covers `jq`, `sed` and `tail` as well as curl, under both bash and dash (ruling 8c).
6. **Declared residuals:** the Doppler fallback file and the environment channel (rulings 8b, 8d), plus a re-checkable
   AC2 and a `git fetch` before the `origin/main` comparisons.
7. **Corrections:** the lefthook claim (its pre-commit glob does not select `.sh` suites) and the log-retention
   wording. The verify-the-negative sweep confirmed all 9 negative claims.

## Overview

The "Read-backs after `destroy`" command in the Inngest LUKS cutover runbook (6894, section 5b) passes the read-only
Hetzner bearer on curl's argument list, where `ps` and `/proc/<pid>/cmdline` show it to any other local user while the
request runs. Every other read-only Hetzner read-back in runbooks 6894 and 6604 already sends the header as a curl config
on stdin.

This plan:

1. Replaces that command with the exact runbook-6604 retired-volume GET form, with only the volume id changed to
   106261946.
2. Moves the section 5c one-liner in runbook 6894, and its byte-identical copy in `plugins/soleur/skills/postmerge/SKILL.md`
   Phase 5.7, to the same confined curl form (`--disable --noproxy "*"` first, `--max-time 30`), still byte-identical.
3. Corrects the 5c testing paragraph. The 2026-10-15 real-API run was of the earlier form. The new form is re-checked
   against stubs only.
4. Extends `plugins/soleur/test/sole-copy-drift-check.test.sh`:
   - N1 exempts expect-404 GETs and rejects an expect-404 GET that names the pin.
   - A new exact-text row, N3b, covers every Hetzner-bearer line in runbook 6894 and the postmerge skill.
   - A new self-test row, H18, proves N1 and N3b each go red on mutant copies.

The change touches docs, one skill body and one test. No host, infra or workflow changes. Merging does ship a patch plugin
release (`version-bump-and-release.yml` delivers the new `SKILL.md` to plugin users) and a docs-site rebuild (`deploy-docs.yml`).

Ref #9927. Operator holds for that epic stay on #12272 and are not discharged here. #12608 is left untouched.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (checked 2026-11-11) | Plan response |
| --- | --- | --- |
| The destroy read-back is "line 357" and lacks `--only-secrets` | True: `inngest-luks-cutover-6894.md:357`, in the first fence under `` ### Read-backs after `destroy` (read-only; re-runnable) `` (heading at :354) | Replace that one line; the heading text is unchanged (N3b anchors on it) |
| "Every other read-only read-back in runbooks 6894 and 6604 already sends the header on stdin (`curl --disable --noproxy "*" -sS --config - --max-time 30`)" | Partly false for 6894. The 5c one-liner (:408) and the postmerge copy (:506) send it on stdin, but as `curl -sS --config - -w ...`, without `--disable --noproxy "*"` and without `--max-time 30`. Only runbook 6604 uses the full confined form | CTO ruling 5: move 5c and its skill copy to the confined form in this PR |
| N1 reds when the destroy line gains `--only-secrets` | Confirmed by simulation (repo-research): `_rb` names both `v1/volumes/106261946` and `v1/volumes/106903269`, not `v1/volumes/106903269` alone | CTO ruling 3: N1 skips expect-404 lines and gains a clause rejecting an expect-404 line that names the pin |
| No suite row reds an argv header on a runbook-6894 read-only line | True. N3 / `rb_cmdline_ok` pins runbook **6604** only. No exact-text pin covers 6894 or the skill line. Only `apps/web-platform/infra/inngest-luks-sole-copy.test.sh` H2 checks that the two 5c copies are byte-equal to each other | New row N3b (CTO ruling 4) |
| The 5c line was "confirmed against the real API" | True of the earlier form only (2026-10-15, ADR-282 Addendum 2026-10-15). The new form adds three curl flags, so that run does not cover it | Correct the paragraph; stub re-run recorded in the PR body; no real-API claim (CTO ruling 5) |

## Research Insights

### Premise Validation

- **#12616:** OPEN, no closing PR. The only open change naming it is this branch's draft PR #12645 (`collision-precheck.sh 12616`).
  The pre-check also reported a foreign `test-all.sh` process (pid 3004114) owned by the
  `feat-one-shot-changed-path-readers-remainder` worktree. That is an unrelated suite run, not a duplicate of this work.
- **#9927:** OPEN (the epic; this plan uses `Ref`, never `Closes`).
- **#12608:** OPEN and out of scope by ruling 1. Not touched.
- **Cited paths** (all present on this branch, cut from `origin/main` at 408ad9c0e1):
  - `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` (948 lines)
  - `plugins/soleur/skills/postmerge/SKILL.md` (648 lines, 47853 bytes)
  - `plugins/soleur/test/sole-copy-drift-check.test.sh` (2571 lines; baseline run `284/284 passed`, rc 0, about 1m53s)
  - `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md:362`: the template line, indented 5
    spaces inside a list fence.
- **Mechanism vs. ADRs:**
  - ADR-282 cites the 5c read-back "by section and not reprinted here" (Addendum 2026-10-15). Its claim is a dated event
    (`protected` on 2026-10-15), so it stays true and needs no edit.
  - No ADR rejects the stdin-config form. `scripts/lib/bearer-curl.sh` is the repo precedent for `--disable --noproxy '*'` first.

### Property List (Phase 0.6b)

- **P1.** While a runbook-6894 read-only command runs, the Hetzner read-only bearer never appears on any process's
  argument list.
- **P2.** That command can only use the read-only token. If the token is absent it stops with `missing-token` (exit 3) and
  never falls back to the read/write `HCLOUD_TOKEN`.
- **P3.** curl in those commands reads no `.curlrc`, honours no proxy variable, and is bounded in time.
- **P4.** The section 5c read-back in runbook 6894 and the copy the postmerge skill runs stay byte-identical.
- **P5.** A future edit that puts a Hetzner bearer on argv in runbook 6894 or the postmerge skill, or drops the
  confinement, turns a CI suite red.
- **P6.** N1's statement stays true and stays guarded after the retired id appears on a read-only line. N1's statement:
  every non-404 read-only volume GET in runbook 6894 names the live Inngest pin, and no expect-404 GET names it.
- **P7.** The runbook does not claim a real-API verification for a command text that was never run against the real API.

### Cut List (Phase 0.6b)

- **A token-shape guard before curl.** It would refuse a token with a newline or quote, which would otherwise inject
  curlrc directives (learning 2026-10-06). Property: P1/P3 hardening. Cut, because ruling 2 fixes the exact 6604 form,
  and the 6604 lines, the 5c line and `bearer-curl.sh` callers share this residual. Changing it is a cross-runbook
  design change, not this fix. Recorded under Non-Goals.
- **Process substitution (`< <(printf ...)`) instead of a pipe.** Learning 2026-10-06 found exit 141 under `pipefail`
  with a pipe. That does not apply here: the command runs under `sh -c` (POSIX sh, no `pipefail`), and curl drains a
  one-line config. In `r=$(printf ... | curl ...)` the status is curl's. Ruling 2 also fixes the pipe form. Cut.
- **A committed fake-tool harness.** P7 needs the stub results recorded, not a new committed suite. Ruling 5 says to
  record them in the PR body. The harness lives in the scratchpad. N3b pins the text that the harness exercised.
- **Hard-coding 106261946 in N1.** Ruling 3. The exemption is structural, so N1 holds no second literal that could drift.
- **Cut at plan review (CTO rulings 7a, 7b, 7c, 7f, 2026-11-11):**
  - the `SOLE_COPY_DRIFT_RUNBOOK` / `SOLE_COPY_DRIFT_SKILL` overrides and the full-suite mutant runs;
  - the awk fixed-copy generator for H18;
  - N3b's section checks for the 5c and skill fences;
  - Guard 1 row 9 and Guard 2 row 3, which duplicate other rows;
  - the destroy-line stub run.

  H18 already proves the mutants on copies, and the multiset plus the destroy-fence check cover what the cut checks did.
  See the `decision-challenges.md` rows 7a-7g.

### Relevant files (with anchors)

- **`sole-copy-drift-check.test.sh`:**
  - Constants: `RUNBOOK=` / `SKILL=` / `RB6604=` (`:94-98`), `FLOOR=284` (`:55`), `TABLE_ROWS=149` (`:58`).
  - Header comment naming the counts and the H-row ranges (`:27-30`).
  - N1 inline block: the `_rb=$(grep -F -e '--only-secrets HCLOUD_TOKEN_READONLY' "$RUNBOOK" ...` line and the
    `pass "N1 the inngest row's volume_id` line.
  - `n1c()` and its expect-404 exemption: the `grep -vE "v1/volumes/[0-9]+'[[:space:]]+# expect 404\$"` line, plus the
    `_g=` clause. This is the shape N1 copies.
  - `RB_WRAP=` / `RB_HDR=` / `rb_expected()` / `fence1()` / `rb_blocks()` / `rb_cmdline_ok()` (the N3 exact-text pin of
    runbook 6604).
  - H14 (`n1c_mut`, `mut_lit`) and H15 (`_rb_mark`, `rb_mut`, `rb_put`, `_rb_judge` with the `cmp -s` did-not-land check):
    the mutant-on-a-copy idiom N3b's self-test reuses.
- **`apps/web-platform/infra/inngest-luks-sole-copy.test.sh`** H2 (`readback_of`: the first fenced block containing
  `protection.delete` must be byte-identical between SKILL and runbook). It stays green when both 5c copies change
  identically. Run it in the work phase.
- **`tests/scripts/test-argv-bearer-sweep.sh`** S7 scans `plugins/**/*.md` for argv bearers. The planned 5c line hits
  neither its V nor its Q regex (repo-research applied both). Run it in the work phase.
- **`plugins/soleur/test/skill-body-budget.json`:** `"postmerge": 48000`, enforced by
  `scripts/lint-skill-body-budget.py --base origin/main` (lefthook). The file is 47853 bytes, so headroom is 147. The 5c
  edit adds 38 bytes (`--disable --noproxy "*"` plus a space is 24, `--max-time 30` plus a space is 14), leaving 109. **No prose is added to the
  skill.**
- **`scripts/lib/test-affected-paths.sh`:** `AFFECTED_PLUGINS_SOLEUR_TEST_SOLE_COPY_DRIFT_CHECK_TEST_SH_PATHS` already
  lists both the 6894 runbook and `postmerge/SKILL.md`, so edits to either already select this suite. No selection-list
  edit is needed.
- **Lints on the touched text** (all clean on a candidate copy, per repo-research):
  - `lint-infra-no-human-steps.py` (scans the runbooks dir)
  - `lint-credential-path-literals.py`
  - markdownlint (MD013 off)
  - `lint-hcloud-token-readonly-no-fallback.sh` excludes `*.md`.

### Line census (the population N3b quantifies over)

`grep -n curl <f> | grep -iE 'hcloud_token|authorization'`, together with `grep -n HCLOUD_TOKEN <f> | grep -i authorization`
and `grep -n curl <f> | grep -i 'api\.hetzner\.cloud'` (p3, added at deepen-plan), gives exactly the lines below. Each
of the three predicates fires on each of the three lines, so p3 adds no noise (checked 2026-11-11; the CTO agent re-ran
it independently):

| File | Lines |
| --- | --- |
| runbook 6894 | 357, 408 |
| postmerge SKILL.md | 506 |

No other line in either file matches. The postmerge Sentry block (`:165-172`) splits `curl` (`:170`) and `Authorization`
(`:172`) across lines, and neither of those lines names `HCLOUD_TOKEN` or `api.hetzner.cloud`, so it is outside all three
predicates.

### CLI verification (gate #2566)

- `doppler run --help` (local, 2026-11-11) shows both flags:
  - `--only-secrets strings   only include the specified secrets`
  - `--no-exit-on-missing-only-secrets   do not exit on missing secrets via --only-secrets`
- `curl --help all` (local) shows all four flags used:
  - `-q, --disable   Disable .curlrc`
  - `--noproxy <no-proxy-list>`
  - `-m, --max-time <seconds>`
  - `-K, --config <file>`
- curl applies `--disable` only as the **first** argument, which is why the pinned form puts it first.
- Every token in the new lines already appears verbatim in runbook 6604 `:362`. The 5c transform was checked mechanically:
  6894 `:408`, with `curl -sS --config - -w` replaced by
  `curl --disable --noproxy "*" -sS --config - --max-time 30 -w`, equals 6604 `:1228` (fence indentation stripped, id
  106443278 to 106903269) byte for byte.

### Institutional learnings applied

- `2026-11-10-a-closed-allow-list-that-pins-names-leaves-the-deny-list-one-level-down.md` (the #12563 / #10432 review):
  pin exact text, not spellings. That is why N3b is an exact-text equality plus a census, not a list of banned `-H`
  spellings.
- `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md`: the
  pipe and token-shape points. Both are dispositioned in the Cut List.
- `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-...md` and
  `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`: the matrix includes rows the CTO did not name (a second
  member, the skill copy, vacuity, a split-line header). It also includes a must-PASS non-canonical copy.
- `2026-08-10-my-verification-was-narrower-than-the-claim-it-certified.md`: the testing paragraph must say what was run,
  on which text.
- `2026-10-10-a-log-scraping-probe-matched-the-script-it-echoed-and-the-inline-copies-dropped-the-trim-the-library-had.md`:
  the inline-copy drift risk between runbook and skill. N3b pins both copies to one generated text.

### Conventions

- `cq-cite-content-anchor-not-line-number`: the suite anchors on headings and fences, never line numbers.
- `cq-test-fixtures-synthesized-only`: stub tokens are synthetic.
- `hr-never-run-commands-with-unbounded-output`: the suite run is piped to a log, then tailed.
- `wg-use-closes-n-in-pr-body-not-title-to`.
- `semver:patch` per `plugins/soleur/AGENTS.md`.

## Proposed Solution

### The two pinned texts

Both pinned texts are built from the suite's existing `RB_WRAP` / `RB_HDR` (shown here unescaped).

- **D (destroy read-back, runbook 6894 section 5b).** This is the 6604 retired-volume GET with only the id swapped.
  `RB_WRAP RB_HDR` followed by `-o /dev/null -w "%{http_code}\n" https://api.hetzner.cloud/v1/volumes/106261946'   # expect 404`.
  Expanded:

  ```text
  doppler run -p soleur -c prd_terraform --only-secrets HCLOUD_TOKEN_READONLY --no-exit-on-missing-only-secrets -- sh -c '[ -n "$HCLOUD_TOKEN_READONLY" ] || { echo missing-token; exit 3; }; printf "header = \"Authorization: Bearer %s\"\n" "$HCLOUD_TOKEN_READONLY" | curl --disable --noproxy "*" -sS --config - --max-time 30 -o /dev/null -w "%{http_code}\n" https://api.hetzner.cloud/v1/volumes/106261946'   # expect 404
  ```

- **R(pin) (section 5c read-back).** This is the existing `rb_expected` read-back line, the one runbook 6604 carries for
  the web-1 pin, with the Inngest pin 106903269 read from the workflow row (`_pin`). It differs from today's 6894 `:408`
  only by `--disable --noproxy "*"` inserted after `curl` and `--max-time 30` inserted after `--config -`. Kieran
  checked this byte for byte against the suite's own builders.

The trailing comment falls outside the single-quoted `sh -c` script, as it already does on runbook 6604's lines. Where the
pasting shell does not treat `#` as a comment, the words reach `sh -c` as `$0..$2`, and the script never reads them.

### Suite changes

**Commit A: helper extraction (equivalence refactor, its own commit).** Split `rb_expected` into two line builders:

- `rb_line_readback <id>`
- `rb_line_get404 <id>`

`rb_expected` calls them. Prove the refactor is a no-op before adding anything: dump `rb_expected "$_wpin"` before and
after, `cmp` the two dumps, and the suite must still print `284/284`, with N3 and H15 green. N3b calls the same builders,
so "the 6894 form is the 6604 form" holds by construction.

**N1 as `n1_rb <runbook> <pin>`.** The function prints one line per disagreement, in the same shape as `n1c`. It begins
with a readable-file check: a missing or unreadable file prints a disagreement. Both clauses share one exemption regex
variable, `RE404='v1/volumes/[0-9]+'"'"'[[:space:]]+# expect 404$'`.

- **Set clause.** The ids of every `--only-secrets HCLOUD_TOKEN_READONLY` line that does **not** match `RE404` must be
  exactly `{pin}`. This is N1's current check, with the exemption. An empty set never equals `{pin}`, so a broken regex
  (`grep` rc 2, empty output) or a deleted line reds this clause. This is the fail-closed backstop.
- **Pin clause (new).** The count of `RE404` lines naming `v1/volumes/<pin>'` must be 0. Take the count from
  `grep -c` without a `|| _g=0` fallback: `grep -c` prints `0` on no match. Because the file is checked first and the
  set clause backstops, a masked error cannot pass both clauses.
- **Comment in `n1_rb`.** State that the comment-keyed exemption is safe only because N3b's exact multiset reds any other
  expect-404 bearer line (ruling 7g). Neither check may be removed without the other.

The N1 assertion keeps its other conjuncts (the ADR-282 `Hetzner id`, the skill containing the pin, the suite's Inngest
id) and its single pass/fail line. The pass label adds "and no expect-404 read-only GET names it".

**N3b: `n3b <runbook-6894> <skill> <pin> <retired>`.** The function prints one line per disagreement and runs beside N3.
Every disagreement line starts with a fixed tag, so H18 can tell which check fired (test-design review finding 2):
`slot:`, `destroy-fence:`, `unclassified p1:` / `unclassified p2:` / `unclassified p3:`, and `count <D|R> <file>: want <n> got <m>`.

0. **Slots.** `[[ -n $pin && -n $retired && $pin != $retired ]]`, otherwise print `slot: ...` and **return at once**.
   Without the early return, an empty or equal pin makes `R(pin)` match no line, so the census reports anyway and the
   slot check is never what turns the row red (test-design review finding 3).
1. **Destroy fence.** The first fenced block under the heading
   `` ### Read-backs after `destroy` (read-only; re-runnable) `` is exactly the one line `D(retired)`. The heading is
   matched by awk string equality (`$0 == "..."`), never by a regex: the heading contains backticks, parentheses and
   `;`. The section ends at the next line matching `^##`. The block is extracted with the existing `fence1`.
2. **Census.** One awk pass over **every line** of each file (ruling 4, upheld in 7d), with `l = tolower($0)` applied to
   every term. A line is a **bearer line** if either holds:
   - (p1) it contains `curl` and also `hcloud_token` or `authorization` — the CTO predicate;
   - (p2) it contains both `hcloud_token` and `authorization` — a strict superset, ruled keep in item 7.1. It catches an
     argv header on a continuation line;
   - (p3) it contains `api.hetzner.cloud` (review ruling 9b dropped the `curl` requirement) — ruled keep in item 8a. It catches a bearer staged through a
     variable on an earlier line (`T=$HCLOUD_TOKEN_READONLY`, then `curl --oauth2-bearer "$T" https://api.hetzner.cloud/...`),
     where the curl line names neither the token nor `Authorization`.

   Each bearer line, with leading whitespace stripped, must equal `D(retired)` or `R(pin)`. The multiset must be exact:
   runbook `{D:1, R:1}`, skill `{R:1}`. This compares counts, so a deleted line is red. Any other bearer line is reported
   as **unclassified**, with its file, the first predicate that fired (`p1`/`p2`/`p3`) and its first 120 characters. A comment by
   the predicate says that it reads prose too.

Check 1 together with the multiset catches D and R trading places, which N1 cannot see (ruling 7c). The 5c and skill
fences are covered by the multiset: each must hold `R` exactly once, and nothing else may carry a bearer.

`INNGEST_RETIRED_ID=106261946` is a suite literal beside the N3b block, with a comment saying it is the oracle and is
deliberately not read from the runbook. N3b passes when `n3b` prints nothing.

**H18 (self-test, one aggregated pass/fail, the same shape as H14/H15).** Mutants are copies of the **real, fixed**
documents under `$TMP/n3b/` (ruling 7b). A copy that is `cmp -s`-identical to its source is reported as
`(did-not-land)`, never as caught.

- **Scoped edits (test-design review finding 1).** After the fix, `--disable` and the `D`/`R` texts each occur on more
  than one line of runbook 6894, so a file-wide first-match edit can land on the wrong line and still go red for the
  wrong reason. Rows 1, 2, 3, 4 and 9 edit only inside their named section (the destroy section, or the section from
  `^## 5c\.` to the next level-2 heading), and after the edit H18 checks that the changed line is the intended one: `diff` of
  source and copy shows exactly the intended changed lines (one, or one per section for row 9), each inside its section. Otherwise the row is `(misplaced)`, never caught.
- **Tag check (test-design review finding 2).** Each row names the tag its mutation must produce (Guard Contract,
  "Expected"). A row counts as caught only if `n3b`'s output contains that tag. Row 9 must also print no `count` line,
  which proves the destroy-fence check and not the multiset caught the swap. Failures are listed as `uncaught:<label>`
  and `spurious:<label>:<first output line>`, as H14 does. The rows are listed in the Guard Contract. H18 runs `n3b` and `n1_rb` directly on the
copies; it never repoints `RUNBOOK` or `SKILL`.

**Counts.**

- FLOOR is set to the count the finished run prints. Expected 286 (+N3b, +H18; N1 stays one line). TABLE_ROWS stays 149
  (no `end_row`).
- Header comment `:27-30` changes:
  - "H11-H17" becomes "H11-H18";
  - the negative-control list adds "N1's expect-404 exemption and the N3b runbook-6894/postmerge exact-text pin";
  - the counts become 286 assertions;
  - the "Edits to ... select this suite too" sentence adds runbook 6894 and the postmerge skill (read by N1 and N3b).

### Runbook prose (6894)

- **Under the destroy fence.** Replace the paragraph from "Expect `404`." onwards with the following. Keep it to lines
  that never carry `curl` beside a token name, `Authorization` or `api.hetzner.cloud`, and never a token name beside
  `Authorization`.
  - "Expect `404`."
  - `missing-token` (exit 3) means `HCLOUD_TOKEN_READONLY` is absent from `prd_terraform`. Minting it is step **O5** in
    `infra-credential-tiers-8209.md`. The command never falls back to the read/write token.
  - The line is the runbook-6604 retired-volume GET with only the id changed, and the drift suite pins it (row N3b).
  - Keep the existing `GET /v1/servers/169426216` and probe-row sentences.
- **Section 5c testing paragraph.**
  - Add after "The token never reaches argv": "`--disable --noproxy "*"` come first, as in `scripts/lib/bearer-curl.sh`,
    so curl reads no `.curlrc` and honours no proxy variable; `--max-time 30` bounds the request."
  - Replace the two stub and real-API sentences ("The command was exercised against a stubbed ..." and "It was then run
    once against the real API, ...") with:
    - "The current form (`--disable --noproxy "*"` first and `--max-time 30`, #12616) was exercised on <work date>
      against a stubbed `doppler` and `curl`, with a fake token and no network. It covered protected, not-protected,
      HTTP 401, HTTP 404, network failure, non-JSON, a missing field, a missing token, an empty token and a failing
      `doppler` (no word)."
    - "The one run against the real API, on 2026-10-15 (`protected`, exit 0; ADR-282, Addendum 2026-10-15), was of the
      earlier form without those three flags. The current form has not been run against the real API."
- **No other runbook text changes.**

### Skill (postmerge Phase 5.7)

Only the one line at `:506` changes, to `R(106903269)`, byte-identical to the runbook. Add no prose.

## Implementation Phases

### Phase 1: refactor, then RED

1. **Commit A.** Extract the helpers, `cmp` the `rb_expected` output before and after, and run the suite (`284/284`).
   Commit.
2. **Add the guards.** Add `n1_rb` (switch N1 to it), `INNGEST_RETIRED_ID`, `n3b`, the N3b row and H18. H18 is built on
   copies of the real documents. FLOOR stays 284 for now.
3. **RED run on the unfixed documents.** Do not commit it. lefthook's pre-commit affected-test hook (`bun-test`) has the
   glob `*.{ts,tsx,js,jsx}`, so it does not select this `.sh` suite. Expect:
   - N3b FAILs, naming runbook `:357` (`D` missing from the destroy fence, plus unclassified `p1`) and both 5c lines as
     unclassified;
   - H18 FAILs too, because its mutants need the fixed text and come out `did-not-land` or uncaught.

   Record both FAIL lines for the PR body.

### Phase 2: GREEN (docs and skill)

4. **Destroy line.** Runbook 6894 `:357` becomes `D(106261946)`, unindented, matching the existing fence. Copy without
   6604's 5-space list indentation.
5. **5c lines.** Runbook 6894 `:408` and postmerge SKILL.md `:506` both become `R(106903269)`, with the identical edit in
   both.
6. **Prose.** Edit the paragraph under the destroy fence and the 5c testing paragraph, as specified above.
7. **FLOOR.** Run the suite, set FLOOR to the realized total, and update the header comment. Commit B.
8. **Run the suites.**
   - `bash plugins/soleur/test/sole-copy-drift-check.test.sh > "$SCRATCH/sc.log" 2>&1; echo rc=$?; tail -3 "$SCRATCH/sc.log"`.
     Expect all passed, rc 0.
   - `bash apps/web-platform/infra/inngest-luks-sole-copy.test.sh` (H2 byte-identity).
   - `bash tests/scripts/test-argv-bearer-sweep.sh` (S7).
   - `python3 scripts/lint-skill-body-budget.py --base origin/main`.
   - `python3 scripts/lint-infra-no-human-steps.py`.
   - `npx markdownlint-cli2` on the two documents.

### Phase 3: the four CTO mutants as whole-suite FAIL lines (ruling 7a)

9. **One mutant at a time.** Apply the mutant to the worktree file, run the suite to a log, and capture the N3b FAIL line
   (and the N1 FAIL line for mutants 3 and 4). Then `git checkout -- <file>`, and confirm with `git diff --quiet -- <file>`
   before any commit. Record the four results in the PR body. H18 is the standing proof; this step is evidence only.

### Phase 4: stub re-run of the 5c line (ruling 5)

10. **Stub harness** (scratchpad, never committed): a stub `doppler` and a stub `curl` on `PATH`, driven by `FAKE_CASE`,
    plus argv-checking pass-through stubs for `jq`, `sed` and `tail` (ruling 8c). A working prototype of the `doppler`
    and `curl` stubs exists at
    `/tmp/claude-1000/-data-git-repositories-jikig-ai-soleur/6781a196-45c3-43ad-bc32-fdb6045164ab/scratchpad/stubproto/bin/`.
    Re-create it in the work session's scratchpad.
    - **Stub `doppler`.** Its argv must be exactly
      `run -p soleur -c prd_terraform --only-secrets HCLOUD_TOKEN_READONLY --no-exit-on-missing-only-secrets -- ...`,
      otherwise it exits 64. It then `exec`s the command under `env -i`, with only `PATH` plus the fake read-only token;
      branch explicitly for the unset and empty cases, never with a `${X+VAR=...}` prefix. `FAKE_DOPPLER_FAIL=1` makes
      it exit 1 first.
    - **Stub `curl`.** It refuses (exit 64):
      - an argv not starting `--disable --noproxy *`;
      - an argv without `--max-time 30`;
      - any argv containing the fake token;
      - stdin other than `header = "Authorization: Bearer <fake>"`.

      Otherwise it honours `-o /dev/null` and expands `-w` with `printf '%b'`, never `printf "$w"`. Per case it returns:
      200 with a JSON body (delete true, delete false, a missing field, non-JSON), 401, 404, or a network failure
      (`000`, exit 7). It reads all of stdin (`cfg=$(cat)`) and compares the whole of it, so a second config line such
      as an injected `proxy =` is refused too; keep that check as it is in the prototype.
    - **Call log (security review F1).** The word and exit cannot show a leak: a refusal (exit 64) inside
      `r=$(...) || { echo read-failed; exit 2; }` prints `read-failed`/2, the same result the 401, network, non-JSON and
      missing-field rows expect. So the stub `curl` appends one line per call to `$FAKE_LOG`, either `accepted` or
      `refused:<reason>`. The harness truncates the log before each case and checks it after: exactly one `accepted`
      line, and no `refused` line, for each of the seven cases that reach curl; an empty log for the three that do not.
    - **Every external command (security review F3, ruling 8c).** Read in full, the 5c line runs `printf`, `curl`,
      `tail`, `sed` and `jq`. Attack Surface item 3 and property P1 are about every process, not only curl. The stub
      `jq`, `sed` and `tail` each check their own argv: if it holds the fake token they append
      `refused:token-on-argv` to `$FAKE_LOG` and exit 64; otherwise they `exec` the real tool (resolved by absolute path
      before `PATH` is changed). `printf` cannot be stubbed this way because it must be a builtin, so the harness asserts
      that `command -V printf` reports a builtin in each shell.
    - **Two shells.** Run all ten cases twice: once with `sh` resolving to the host's `sh` (bash), once with a stub-bin
      `sh` symlinked to dash (`/home/jean/.local/bin/dash` on the planning host; resolve with `command -v dash`), which
      matches the Debian and Ubuntu `/bin/sh`. strace and busybox are not installed on the planning host, so execve
      tracing is not part of the run; the PR body says so. Other `/bin/sh` implementations (for example macOS bash 3.2
      in POSIX mode) stay untested, as the CTO's dissent on 8c records.
11. **Run the 5c line, extracted from the fixed runbook fence (not retyped), through `bash -c`, in each of the two shell
    set-ups.** The ten cases, with the
    word and exit each expects:

    | Case | Word | Exit |
    | --- | --- | --- |
    | protected | `protected` | 0 |
    | not-protected | `not-protected` | 1 |
    | 401 | `read-failed` | 2 |
    | 404 | `volume-gone` | 4 |
    | network | `read-failed` | 2 |
    | non-JSON | `read-failed` | 2 |
    | missing field | `read-failed` | 2 |
    | missing token | `missing-token` | 3 |
    | empty token | `missing-token` | 3 |
    | failing doppler | no word | 1 |

    The prototype produced exactly these on 2026-11-11. As a control, it refused today's unconfined `:408` form (exit 64,
    then `read-failed`).
12. **Record** in the PR body a table of case, word, exit, and the call-log column, built from `$FAKE_LOG` rather than
    typed: `accepted` for the seven cases that reach curl, and `n/a, curl not run` for missing token, empty token and
    failing doppler (security review F2), one table per shell. The claim it supports is "the fake token was absent from
    the argv of every external command the 5c line invokes, under bash and dash"; also record that strace was not
    available. State that no real-API run was made. Do not cite a destroy-line stub run
    (ruling 7f).

### Phase 5: Ship

13. Write the PR body with:
    - `Closes #12616` and `Ref #9927`;
    - a `## Changelog` section (patch: the runbook-6894 destroy read-back and the 5c read-back send the read-only token
      on stdin with curl confined; the drift suite pins every Hetzner-bearer line in runbook 6894 and the postmerge skill);
    - the RED-before lines from Phase 1, the four mutant FAIL lines from Phase 3, and the stub table from Phase 4.

    Label `semver:patch`. Normal `soleur:ship` and auto-merge. No post-merge operator step.

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`:
  - the destroy read-back line and its paragraph (section 5b);
  - the 5c one-liner and the testing paragraph (section 5c).
- `plugins/soleur/skills/postmerge/SKILL.md`: the Phase 5.7 one-liner only (+38 bytes; ceiling 48000, current 47853).
- `plugins/soleur/test/sole-copy-drift-check.test.sh`: the helper extraction, `n1_rb`, `INNGEST_RETIRED_ID`, `n3b`, the
  N3b row, H18, FLOOR and the header comment.

## Files to Create

None in the repo. The stub harness and the Phase 3 evidence runs use the session scratchpad and a restored worktree.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` was searched for the three file paths and for
`inngest-luks-cutover-6894`, `sole-copy-drift-check` and `postmerge/SKILL.md`. Other open issues that name these files
cover different concerns and are acknowledged:

- #10430 (the Sentry monitor for the job);
- #10431 (a shared Doppler CLI install step);
- #12608 (the web-1 detach probe, out of scope by ruling 1).

## Non-Goals

- **A token-shape guard before curl, and process substitution instead of the pipe.** See the Cut List. The same residual
  applies to every runbook-6604 read-only line and to the shared `bearer-curl.sh`, so changing it is a cross-runbook
  change and not part of this fix.
- **`--no-fallback` and the environment channel (`env -u SSLKEYLOGFILE`).** Attack Surface items 7 and 8, rulings 8b and
  8d. Both are the same cross-runbook hardening as the token-shape guard: each would change every runbook-6604
  read-only line, N3's shared builders and the 5c line together. They are recorded here, with the token-shape residual,
  rather than in a GitHub issue: no deferral issue exists for that residual, and per
  `wg-when-deferring-a-capability-create-a` this Non-Goals list is the documentation until a cross-runbook change has a
  concrete trigger. The CTO's dissent stands: until that change lands, the read-only token may sit in an encrypted
  Doppler cache and in inherited environments.
- **A real-API re-run of the new 5c form.** Ruling 5 claims none. The next `soleur:postmerge` Phase 5.7 run triggered by
  an `inngest-redis-luks.tf` merge exercises the new form in its normal course.
- **ADR-282 and the legal destruction record.** They cite the read-back by section, and their dated claims stay true.
  Review added append-only addenda to ADR-282 (the cited location now holds the new form) and to ADR-280 (this
  read-back's carve-out from the 2026-10-13 no-`--noproxy` rule), rulings 9a and 9e.
- **#12608 and every standing operator hold on #12272.**

## Alternative Approaches Considered

| Approach | Why not |
| --- | --- |
| Leave `--only-secrets` off the destroy line so N1 never sees it | Loses P2 (Doppler-enforced no fallback) and keeps two read-only forms in one runbook. Rejected by ruling 2 |
| Scope N1's grep to the 5c block | Weakens N1 from file-wide to one block. Ruling 3 keeps it file-wide, with a structural exemption |
| Ban `-H` / `--header` spellings | The #12563 review showed that spelling lists leak one level down. Use exact text plus a census |
| Census over fenced lines only (advisor) | Overruled (7d): a bearer command in prose is still copy-pasteable, and today no prose line matches |
| Exempt only a line equal to `D(retired)` in N1 (advisor) | Overruled (7g): it duplicates N3b and undoes ruling 3. The exact multiset already reds any other expect-404 bearer line |
| Leave 5c on the earlier form | Its curl reads `.curlrc` and proxy variables and runs unbounded. Ruling 5 moves it; the dissent is recorded |

## Technical Considerations

### Attack Surface Enumeration

The ways the Hetzner read-only bearer can reach a process argument list from these two documents:

1. **curl argv** (`-H`, `--header`, `--oauth2-bearer`, `-u`, URL userinfo). Closed by the exact-text census: any byte
   other than `D`/`R` on a bearer line is red. `D` and `R` themselves are closed by two frozen literals in the suite
   (ruling 12a): `N3B_FROZEN_D` and `N3B_FROZEN_R` are each the whole pinned line, held in a quoted heredoc with `@ID@`
   the only placeholder, and the built line must equal its literal byte for byte. The closure comes from that literal,
   not from the slot, residual, curl-argv and env-dump word lists, which stay as defence in depth on both texts.
2. **The `doppler run` argv.** The token goes into the environment, never into the argv. The `sh -c` script is
   single-quoted, so the variable expands inside it, not in the caller's shell.
3. **`printf` inside `sh -c`.** `printf` is a builtin in dash and bash, so no new process receives the token. This
   exposure is the same as in runbook 6604 and is unchanged. The Phase 4 harness checks it: `command -V printf` in both
   shells, and argv-checking stubs on every external command the 5c line runs (ruling 8c).
4. **curl reading `.curlrc` or a proxy.** Closed by `--disable` first and `--noproxy "*"`.
5. **A line the census does not see, and an edited literal** (declared limits, narrowed by p3, rulings 8a, 9b, 11b,
   12a and 12b). The census reads logical lines: `\` continuations are joined (the join stops at a code fence) and the
   joined line is flagged by its Hetzner-specific arms, `api.hetzner.cloud` (p3) or a token name beside `curl` or
   `Authorization` (p4). The residual is a renamed token AND no literal `api.hetzner.cloud` on the logical line. Every
   literal-URL form is seen, on one line, split over `\` continuations, or with the host split inside its quotes across a
   `\` continuation (g1r16), with any client (H18 rows g1r11 and g1r12), and so is the token on a continuation line with
   the URL from a variable (g1r15). Known gaps inside that residual: same-line quote concatenation of the host (for
   example `"https://api.hetzner"".cloud/..."` beside a renamed token, which leaves the census at `seen D=1 R=1`). The
   remaining gap of the frozen literals: an edit to `N3B_FROZEN_D` or `N3B_FROZEN_R` (made together with the builders and
   the document copies) is a reviewed change the suite cannot catch; only the defence lists still face it. Any such
   construct would be new text in a reviewed diff.
6. **Other documents.** Runbook 6604 is covered by N3. Other runbooks are out of scope.
7. **The Doppler fallback file** (a declared cross-runbook residual, ruling 8b). doppler CLI v3.77.1 `doppler run` writes
   an encrypted snapshot of the fetched secrets to disk after each successful fetch unless given `--no-fallback`
   (`doppler run --help`, checked 2026-11-11). With `--only-secrets` the snapshot holds only the read-only token, and
   the file is readable only by the same user. No runbook line and no skill line passes `--no-fallback` today. This is a
   disk channel, not argv, so it is outside P1; adding the flag here alone would break ruling 2's single form and N3's
   shared builders.
8. **The environment channel** (a declared cross-runbook residual, ruling 8d). `doppler run` exports the token to its
   children (`sh`, `curl`, `jq`, `sed`, `tail`), whose `/proc/<pid>/environ` is readable by the same user or root, who
   already hold the Doppler session. curl also honours an inherited `SSLKEYLOGFILE`, which `--disable` and `--noproxy`
   do not cover; `env -u SSLKEYLOGFILE` is the candidate fix. Every runbook-6604 line has the same exposure.

### Precedent diff (deepen-plan 4.4)

The repo has two precedents for "a bearer without argv":

| Aspect | `scripts/lib/bearer-curl.sh` (`bc_curl`, workflows) | Runbook 6604 inline form (operator-run; this plan's `D`/`R`) |
| --- | --- | --- |
| Header channel | curl config on stdin (`--config -`) | Same, `printf "header = ..."` piped into `curl ... --config -` |
| curlrc / proxy | `--disable --noproxy '*'` first | Same, `--disable --noproxy "*"` first |
| Bound | the caller passes `--max-time` | `--max-time 30` |
| Token-shape guard | `bc_ok` refuses empty, whitespace-trailing or non-`[A-Za-z0-9._~+/=-]` values (a newline or quote would inject config) | Presence only (`[ -n ... ]` gives `missing-token`) |
| Argv refusals | refuses verbose, trace, redirect-follow, a second config, the caller's own credential flags | None; the exact-text pin (N3 / N3b) fixes the argv instead |

The plan adopts the 6604 inline form (ruling 2). Its missing token-shape guard is the residual recorded in Non-Goals.
On these documents that gap is bounded: the token comes from Doppler `prd_terraform`, minted in the console at step
O5, and is not attacker-written input. The exact-text pin stands in for `bc_curl`'s argv refusals.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly; the documents are operator-facing. A wrong 5c line
  would make the post-merge sole-copy read-back print `read-failed` or no word. The postmerge skill routes either as "the
  read did not happen", never as a lifted protection. The cost is one delayed verification of the delete-protection flag
  on the volume that holds every user's queue and run state.
- **If this leaks, the user's data is exposed via:** the read-only Hetzner token reaching a local process list on the
  machine running the read-back, which is what this fix closes. That token reads project metadata. It cannot detach,
  delete or change protection.
- **Brand-survival threshold:** `none`.
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`. The change removes a local, read-only exposure
  and alters no runtime path. The protected volume is untouched, and the guard can only add failures.
- `threshold: none, reason: the diff touches operator runbook text, a report-only skill line and a test; no runtime code,
  credential scope or user data path changes.`

## Observability

deepen-plan Phase 4.7 applies here because `## Files to Edit` names a `.test.sh` and a skill body. No runtime surface
changes; the signal is the drift suite's own verdict in CI.

```yaml
liveness_signal:
  what: the sole-copy drift suite's N3b and N1 pass lines (plugins/soleur/test/sole-copy-drift-check.test.sh)
  cadence: per PR whose diff touches a path in AFFECTED_PLUGINS_SOLEUR_TEST_SOLE_COPY_DRIFT_CHECK_TEST_SH_PATHS, and on every merge-to-main full run
  alert_target: a red `test` required check on the PR (merge blocked); a red main-health run after merge
  configured_in: scripts/lib/test-affected-paths.sh (AFFECTED_PLUGINS_SOLEUR_TEST_SOLE_COPY_DRIFT_CHECK_TEST_SH_PATHS) and scripts/test-all.sh, run by .github/workflows/ci.yml
error_reporting:
  destination: the CI job log and the PR check status (a repo test, so there is no Sentry surface)
  fail_loud: an "  FAIL: N3b ..." line naming the unclassified line, its file and the predicate (p1, p2 or p3), plus a non-zero suite exit
failure_modes:
  - mode: an edit puts the Hetzner bearer on curl argv in runbook 6894 or the postmerge skill
    detection: the N3b census reports the line as unclassified
    alert_route: the PR's red test check
  - mode: the 5c runbook line and its skill copy drift apart
    detection: the N3b exact multiset (and H2 in apps/web-platform/infra/inngest-luks-sole-copy.test.sh)
    alert_route: the PR's red test check
  - mode: N3b or N1 stops judging (a vacuous helper)
    detection: H18 mutants come back uncaught or did-not-land, and the outer FLOOR and count conservation catch a deleted row
    alert_route: the PR's red test check
logs:
  where: GitHub Actions job logs of the ci.yml test legs
  retention: the repository's Actions log retention setting
discoverability_test:
  command: grep -c -F -e 'curl --disable --noproxy "*" -sS --config - --max-time 30' knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md
  expected_output: "2"
```

## Guard Contract

### Guard 1 — N3b: every Hetzner-bearer line in runbook 6894 and the postmerge skill is one of two pinned stdin-header texts

**Property.** Every line of runbook 6894 and `plugins/soleur/skills/postmerge/SKILL.md` that carries a Hetzner bearer
(predicate p1, p2 or p3) equals, after leading whitespace is stripped, either `D(106261946)` or `R(pin)`. The counts are
exactly runbook `{D:1, R:1}` and skill `{R:1}`, and the runbook's destroy fence holds exactly `D`.

**Assembly.**

- **The census** is the chokepoint: one awk pass over **every line** of `$RUNBOOK` and of `$SKILL`, not a section.
- **The destroy-fence check** is the second route: string-equality heading match plus `fence1`.
- **The expected texts** have one source: `rb_line_readback` / `rb_line_get404` over `RB_WRAP` / `RB_HDR`, which N3
  (runbook 6604) shares.
- **The slots** are `_pin` (the workflow's `inngest` row, from `rows.json`) and `INNGEST_RETIRED_ID` (a suite literal).
- **Members that drift independently:** any new curl line in either file, and the skill copy. The census covers both.

**Mutation matrix** (each on a copy of the fixed document, checked by H18). "Expected" names the tag H18 requires in
`n3b`'s output:

| # | Mutation (section it is confined to) | Expected |
| --- | --- | --- |
| 1 | Destroy line: stdin header replaced by argv `-H "Authorization: Bearer $HCLOUD_TOKEN_READONLY"` (the #12616 shape) (destroy section) | RED, `destroy-fence:` |
| 2 | Runbook 5c line: `--disable` dropped (5c section) | RED, `unclassified p1:` naming the runbook |
| 3 | Destroy line names the pin: `v1/volumes/106261946'` becomes `v1/volumes/106903269'` (destroy section) | RED, `destroy-fence:` (also N1) |
| 4 | A non-404 line names 106261946: the `# expect 404` comment removed from the destroy line (destroy section) | RED, `destroy-fence:` (also N1) |
| 5 | Skill copy only: `--max-time 30` dropped, the runbook copy left compliant | RED, `unclassified p1:` naming the skill |
| 6 | Second member after a compliant first: a prose line `curl -sS -H "Authorization: Bearer $HCLOUD_TOKEN_READONLY" https://api.hetzner.cloud/v1/volumes` added after the compliant destroy fence | RED, `unclassified p1:` |
| 7 | Own dispatch / vacuity: the destroy fence's command line deleted | RED, `destroy-fence:` and `count D` |
| 8 | Argv header on a continuation line, away from `curl`: a prose line `-H "Authorization: Bearer $HCLOUD_TOKEN_READONLY" \` | RED, `unclassified p2:` |
| 9 | D and R swapped between the destroy fence and the 5c fence (both sections) | RED, `destroy-fence:` and **no** `count` line (the multiset alone is blind) |
| 10 | Bearer staged through a variable: a prose line `T=$HCLOUD_TOKEN_READONLY` followed by a prose line `curl -sS --oauth2-bearer "$T" https://api.hetzner.cloud/v1/volumes` (ruling 8a) | RED, `unclassified p3:` (p1 and p2 both miss the curl line) |

For N3b, rows 1, 3 and 4 travel the same path: each leaves the destroy line not equal to `D`. They stay because ruling 4
names these four mutants, but they count as one N3b behaviour, not three. Rows 3 and 4 earn their place on N1: H18
reuses the same copy files for Guard 2 rows 1 and 2, rather than building them twice (test-design review finding 4).

**Harness rows:**

| # | Edit | Expected |
| --- | --- | --- |
| H-a | Must-PASS non-canonical copy: the "Expect `404`." sentence reworded, plus a new prose line naming `curl` with no token name | PASS (n3b prints nothing) |
| H-b | Neutered slot: `n3b` called on the real fixed files with an empty pin, and again with pin equal to retired | RED, exactly one output line, tagged `slot:` (the early return proves the slot check fired, not the census) |
| H-c | Did-not-land: each mutant `cmp -s` against its source; an identical copy is reported `(did-not-land)` | reported, never counted as caught |

**Anchor.**

- **The retired id** is a suite literal, not read from the runbook, so one runbook edit cannot move the id and its oracle
  together.
- **The pin** comes from the workflow row, which N1, N1b and S1 anchor independently.
- **The expected text** is generated by the builders that N3 also binds to runbook 6604's five lines. Weakening them
  would also have to keep 6604 green, and would show as one suite diff plus three document diffs.

### Guard 2 — N1 with the expect-404 exemption

**Property.** In runbook 6894, the volume ids named by `--only-secrets HCLOUD_TOKEN_READONLY` lines that do not match
`RE404` are exactly `{pin}`, and no `RE404` line names the pin.

**Assembly.**

- `n1_rb <runbook> <pin>` is the only computation. N1 calls it on `$RUNBOOK`; H18 calls it on copies.
- Its input is every `--only-secrets HCLOUD_TOKEN_READONLY` line in the whole file.
- One `RE404` variable feeds both clauses, so a broken regex reds the set clause.
- The exemption is keyed on the comment, which is safe only together with N3b's multiset (ruling 7g; noted in a code
  comment).

**Mutation matrix** (each on a copy of the fixed runbook, judged by `n1_rb` only):

| # | Mutation | Expected |
| --- | --- | --- |
| 1 | The expect-404 destroy line names the pin (`106261946'` becomes `106903269'`) | RED (pin clause) |
| 2 | The `# expect 404` comment removed from the destroy line | RED (set is `{106261946, 106903269}`) |
| 3 | Own dispatch: every `--only-secrets` line removed | RED (empty set != `{pin}`) |
| 4 | Must-PASS: a second expect-404 read-only GET of another retired id (105149570) added | PASS. The exemption is structural. This row is judged by `n1_rb` only, since N3b reds it by design |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
| --- | --- | --- | --- |
| 1 | "The runbook-6894 \"Read-backs after `destroy` (read-only; re-runnable)\" command becomes the exact runbook-6604 retired-volume GET form with only the volume id swapped to 106261946" | Phase 2 step 4; text `D` | mapped |
| 2 | "N1 skips lines matching `v1/volumes/[0-9]+'[[:space:]]+# expect 404$` when collecting ids, plus a new clause that fails if an expect-404 line names the Inngest pin" | Phase 1 step 2; Guard 2 | mapped |
| 3 | "New suite row N3b pins the exact text of both runbook-6894 read-only commands" | Phase 1 step 2; Guard 1 | mapped |
| 4 | "Four mutant copies must each red it: argv `-H` header, dropped `--disable`, the 404 line naming the pin, a non-404 line naming 106261946" | Guard 1 rows 1-4; H18; Phase 3 | mapped |
| 5 | "The section 5c one-liner ... and its byte-identical copy in postmerge/SKILL.md section 5c move to the RB_HDR form" | Phase 2 step 5 | mapped |
| 6 | "Correct the testing paragraph under it" / "re-run the fake-tool cases locally against the new line and record results in the PR body; claim no real-API re-run" | Phase 2 step 6; Phase 4 | mapped |
| 7 | "`semver:patch`; normal ship and auto-merge" / "PR body has `Closes #12616`, `Ref #9927`, a `## Changelog` section" | Phase 5 | mapped |
| 8 | "no line in those two files has curl with `-H` plus a Hetzner token" | AC4 | mapped |
| 9 | "leave #12608 untouched" | Non-Goals | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
| --- | --- | --- |
| Helper extraction `rb_line_readback` / `rb_line_get404` | "built from the suite's existing RB_WRAP and RB_HDR" | asked |
| Census predicate p2 (token name and `Authorization`) | — | inferred. Justification: a strict superset of the ruled predicate that catches an argv header on a continuation line (row 8). The census today is unchanged at 3 lines. CTO ruled keep (7.1, 7e) |
| Census predicate p3 (`curl` and `api.hetzner.cloud`) and Guard 1 row 10 | — | inferred (test-design review). Justification: catches a bearer staged through a variable, previously declared limit 5. The census today is unchanged at 3 lines. CTO ruled keep (8a) |
| Guard 1 rows 5-9 and harness rows; Guard 2 rows 3-4 | — | inferred. Justification: Phase 2.12 requires a second-member row, a dispatch row and a must-PASS row. Row 9 covers the D/R swap (ruling 7c). Trimmed at plan review (7f) |
| Destroy-fence check (N3b check 1) | "pins the exact text of both runbook-6894 read-only commands" | asked (CTO 7c kept it) |
| `INNGEST_RETIRED_ID` literal | "variable parts are the Inngest pin from the workflow row and 106261946" | asked |

### Split Assessment

- Subsystems touched: 3 — `knowledge-base/engineering/operations/runbooks`, `plugins/soleur/skills/postmerge`,
  `plugins/soleur/test`.
- Planned files: 3. Estimated changed lines: about 130, most of them in the test.
- Thresholds: 4 or more subsystem roots, more than 25 planned files, or more than 800 estimated lines.
- Recommendation: single PR.

## Acceptance Criteria

- [x] **AC1. The suite passes.** `bash plugins/soleur/test/sole-copy-drift-check.test.sh` exits 0 with
  `=== Results: N/N passed, 0 failed ===`, where N equals FLOOR (expected 286). N1, N3, N3b, H14, H15 and H18 are `pass`
  lines.
- [x] **AC2. RED came first, and stays re-checkable.** On the unfixed documents (Phase 1 step 3), N3b was a `FAIL`
  naming the destroy fence and three unclassified lines. That line is quoted in the PR body. The same result can be
  reproduced at any time without the one-off run (test-design review finding 5): with the base commit pinned as
  `B=408ad9c0e1ae60a344f26e48b90357d6a7fdc22e` (recorded in the PR body; a live merge-base resolves to the fixed tree
  once this branch merges, CTO ruling 8e), write `git show "$B":<runbook>` and `git show "$B":<skill>` to scratch copies
  and call `n3b` on them with pin `106903269` and retired `106261946`. It prints a `destroy-fence:` line and three
  `unclassified` lines (runbook `:357`, runbook `:408`, skill `:506`). The work session runs this and pastes its output
  under the quoted FAIL line.
- [x] **AC3. Every mutant reds its guard.**
  - H18 passes: every Guard 1 row 1-10 and Guard 2 row 1-3 is caught with its expected tag, none is `did-not-land` or
    `misplaced`, H-b prints only `slot:`, and H-a and Guard 2 row 4 are silent.
  - For each of the four CTO mutants, the Phase 3 worktree run shows an N3b `FAIL`, plus an N1 `FAIL` for mutants 3 and
    4. These lines are in the PR body.
  - `git diff --quiet -- <file>` held after each Phase 3 restore.
- [x] **AC4. No argv bearer in either file.** This prints nothing:
  `grep -nE 'curl' knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md plugins/soleur/skills/postmerge/SKILL.md | grep -E -- '(^|[[:space:]"])(-H|--header)' | grep -E 'HCLOUD_TOKEN'`
- [x] **AC5. The two 5c copies match.** The runbook 5c fence line and the skill Phase 5.7 fence line are byte-identical,
  and `bash apps/web-platform/infra/inngest-luks-sole-copy.test.sh` passes (H2).
- [x] **AC6. The other gates pass.** After `git fetch origin main` (a stale ref changes the base),
  `bash tests/scripts/test-argv-bearer-sweep.sh` and `python3 scripts/lint-skill-body-budget.py --base origin/main` both
  pass.
- [x] **AC7. The testing paragraph is corrected.** The old claim is gone:
  `tr '\n' ' ' < knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md | tr -s ' ' | grep -c 'It was then run once against the real API'`
  prints `0`. The new wording is present in section 5c: the whitespace-normalized text of the section from
  `## 5c.` to `### Delivery route` contains both `was of the earlier form` and
  `has not been run against the real API`.
- [x] **AC8. The PR body is complete.** It carries `Closes #12616`, `Ref #9927`, `## Changelog` and the Phase 4 stub
  table. The table's call-log column is built from `$FAKE_LOG`: `accepted` on the seven rows that reach curl and
  `n/a, curl not run` on the other three, one table each for bash and dash, and no stub logged `refused:token-on-argv`.
  The body makes no real-API claim and states that strace was not available. The PR has the `semver:patch`
  label.
- [x] **AC9. The diff is confined.** After `git fetch origin main`, `git diff --name-only origin/main...HEAD` lists only the three files plus this
  branch's plan and spec artifacts, and the two review-ruled addenda in ADR-280 and ADR-282 (rulings 9a and 9e).
  Ticked at ship, 2026-11-11, with two recorded widenings: the compound learning plus its routed bullet in
  `ship/references/ci-run-diagnosis.md`, and the six main-drift files cherry-picked from #12665 byte-identical
  (decision-challenges ruling 10a and the overlap-vehicle row).
- [ ] **AC10. Normal merge.** Merged through `soleur:ship` and auto-merge, with no production step and no operator step.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed

**Assessment:** The CTO agent ruled the six technical forks before planning, and the seven plan-review items after
(`decision-challenges.md`). The change is runbook text, one report-only skill line and one test file. It creates no
infrastructure, store, connection or autonomous task. So these phases do not fire:

- 2.8 IaC;
- 2.9 Observability (no code-class path under `apps/*/server|src|infra` or `plugins/*/scripts`);
- 2.9.3 task design (no new task surface);
- 2.10 ADR/C4 (no architectural decision);
- 2.11 encryption (no store or connection).

Product, Marketing, Legal, Operations, Finance, Sales and Support have no stake: there is no user-facing surface and no
change to data processing.

## Plan Review

- **Panel:** DHH, Kieran and code-simplicity (eng panel); CTO (devex, named panel); a scoped advisor consult (plan Step
  4.5). The threshold is `none`, so the panel was not escalated.
- **Applied as mechanical:**
  - Kieran 3-9: the `n1_rb` file check and no `|| _g=0`; heading match by string equality; tolower census; a normalized
    negative check in AC7; Guard 2 row 4 judged by `n1_rb` only; the full header-comment edit.
  - Advisor: the refactor lands as its own commit with a `cmp` of `rb_expected`; FLOOR comes from the realized count.
  - DHH 7: the zsh paragraph is trimmed and AC6 no longer pins an exact byte count.
- **Ruled by the CTO (technical, rows 7a-7g):**
  - cut: the overrides and Phase 3 full-suite runs; the awk generator; N3b checks 2-3; Guard 1 old row 9; Guard 2 old
    row 3; the destroy-line stub run;
  - change: mutation 8 becomes an argv continuation line;
  - kept: the every-line census; the comment-keyed exemption; Guard 2 must-PASS row.

  Kieran 1, 2 and 10 dissolved with the generator cut.
- **Not applied:** DHH 5 (delete AC4). AC4 is the operator's stated done-when ("no line in those two files has curl
  with `-H` plus a Hetzner token"), and dropping operator scope is never mechanical.
- No Taste or User-Challenge items remain.

## Test Scenarios

- **(unit)** Given the fixed documents, when the suite runs, then N1, N3b and H18 pass and the total equals FLOOR (AC1).
- **(unit)** Given the unfixed documents, when the suite runs, then N3b fails, naming the destroy fence and three
  unclassified lines (AC2).
- **(unit)** H18 runs `n3b` or `n1_rb` on each copy:
  - Guard 1 rows 1-10 and Guard 2 rows 1-3 each report, with the tag the Guard Contract names;
  - H-a and Guard 2 row 4 are silent;
  - H-b reports only `slot:`;
  - no copy is `did-not-land` or `misplaced`.
- **(integration)** Given each of the four CTO mutants applied to the worktree, when the whole suite runs, then rc is
  non-zero and N3b's FAIL line names the mutant. After `git checkout`, `git diff --quiet` holds (AC3).
- **(integration)** Given the stub `doppler`, `curl`, `jq`, `sed` and `tail`, when the 5c line extracted from the fixed
  fence runs for each of the ten cases under `sh` as bash and again as dash, then it prints the expected word and exit,
  `$FAKE_LOG` shows one `accepted` curl call on each of the seven rows that reach curl, and no stub logs
  `refused:token-on-argv` (Phase 4).
- **(unit)** Regression for #12616: given a copy whose destroy line uses
  `-H "Authorization: Bearer $HCLOUD_TOKEN_READONLY"`, N3b is red (Guard 1 row 1).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails
  `deepen-plan` Phase 4.6.
- **N3b's census reads prose too.** A reworded sentence in either file is flagged as unclassified when it puts `curl`
  beside a token name, `Authorization` or `api.hetzner.cloud`, or a token name beside `Authorization`. Wrap such words
  onto separate lines.
  The failure message names the predicate that fired.
- **postmerge has 147 bytes of headroom before the 38-byte edit.** Do not add a sentence to Phase 5.7; the rationale
  belongs in the runbook.
- **Copy 6604's template line without its 5-space indentation.** `fence1` strips only the fence's own indentation.
- **The old real-API sentence wraps across runbook lines 432-433.** Edit it as a paragraph and verify with AC7's
  normalized grep, not a line grep.
- **Phase 3 edits the worktree's real files.** Restore with `git checkout -- <file>` and check with `git diff --quiet`
  before any `git add`. Never stash (`hr-never-git-stash-in-worktrees`).
- **Run markdownlint on this plan and `tasks.md` before committing them.**
