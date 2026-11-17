# Learning: converting the changed-path readers to NUL-delimited lists traded C-quoting for newline names — and the skill prose that calls the helper read every failure as "no match"

## Problem

PR #12357 (issue #12332, arc tracker #12246) applied the #12326 construction (`git diff -z --no-renames --ignore-submodules=none --name-only | tr '\0' '\n'`) to the remaining changed-path readers: seven workflows plus a constraint-gates template, five hooks/scripts, and the preflight/ship/review skill prose via a new helper `plugins/soleur/scripts/changed-paths.sh`. The author's mutation battery and a 222-assertion suite were green. A ten-seat review and a three-seat verification pass then found the following, almost all in the conversion's own new code:

1. **C-quoting had been an accidental newline defence.** `git diff --name-only` renders a name holding a newline as `"zz\ndocs/..."`; the NUL form plus `tr '\0' '\n'` turns the same name into two "lines". For a gate that ALLOWS on a match (`pr-quality-guards` legal-lockstep `grep -Fxc`, `ship-cmo-content-gate`) a directory called `zz<LF>docs/legal/privacy-policy.md` satisfied a required-document match it did not own. The helper header even said a newline "can only add a false positive". Fix: match over the NUL stream (`grep -z`) where a match allows, and make the helper exit 2 on a newline name.
2. **Every skill-prose call site read a helper failure as "no match / skip".** A garbled paste (`changed-paths.shchanged-paths.sh`) made the UNTRUSTED-CI notice unreachable; preflight discarded the helper's exit code, so Checks 1/2/5/6/7/8/10 read an empty cache as SKIP; `${CLAUDE_PLUGIN_ROOT}` unset under `set -u` died at rc 1, which the `[ $? -eq 1 ]` idiom reads as "no match"; `helper | head -n 200` dropped the status; Steps 11.1/12.1's `> "$DIFF" || true` turned a MISSING cache into a zero-byte "existing, empty" one. No test referenced the prose, though the suite header claimed it "carries its own pins".
3. **The helper itself had three small fail-opens.** A here-string into grep (an unwritable TMPDIR skips grep and `exit $?` returns 1 = "none"); output-format and bundled flags (`-s`, `--output`, `-ps`) exit 0 with an empty list; a caller-appended `-M` re-enables rename hiding. The newline guard written in round 1 was dead (`$(tr -dc '\n' | head -c 1)` — command substitution strips the LF).
4. **The census sentinel reported failures without failing.** `UNLISTED`/`STALE` rows called `fail()` inside a `grep | while` pipe, so the counter moved in a subshell and five injected unconverted sites exited 0.
5. **A raw byte stream meets the locale.** Under a UTF-8 locale GNU grep reports a name with an invalid UTF-8 byte as "binary file matches" and `sed`'s `.` stops at it, so the infra-validation matrix fanned out to zero jobs; the harness pinned `LC_ALL=C` and could never see it.
6. **A fail-safe for one job was a fan-out for another.** infra-validation's "validate every root when the diff fails" also fed the live `terraform plan` matrix on the pull_request arm.

## Solution

- Newline names: `grep -z` over the NUL stream where a match allows; helper exits 2; pr-quality-guards logs control bytes as `?`.
- One canonical call form in prose — `bash "${CLAUDE_PLUGIN_ROOT:-}/scripts/changed-paths.sh" ...` (the `:-` makes an unset root rc 127, i.e. unknown), `|| { [ $? -eq 1 ] || var=unknown; }`, and "unknown fires the gate" stated at each site; preflight removes the cache on failure and a MISSING cache means RUN; Steps 11.1/12.1 write to a temp name and `mv`.
  > **Superseded 2026-11-16 (Ref #12246):** the call form above is wrong. Its `${CLAUDE_PLUGIN_ROOT:-}` did turn an unset root into rc 127 (unknown), but under `set -u` any OTHER unbound variable on the line (`$CANONICAL_REGEX`, `$DPF_REGEX`), or one inside the helper, exits 1, the same code the helper used for no match, so `[ $? -eq 1 ]` read that shell failure as "nothing gated changed". The `:-` is dropped because the root is loader-substituted on Claude Code and an unbound root now reads as unknown on its own. `changed-paths.sh --match` now exits 42 for no match, and the one call form is `var=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" --match ERE origin/main...HEAD) || { [ $? -eq 42 ] || var=unknown; }`. Every other non-zero exit (1, 2, 126, 127, 128+N) is unknown. See the helper's header CONTRACT.
- The helper takes an ALLOWLIST of options, writes the NUL stream to a temp file first, checks every write, and runs grep in the byte locale from a `printf` pipe.
- Suite: sentinel failures via process substitution; sentinel regex accepts any option words, `$GIT` launchers and quoted verbs; SKILL.md spelling pins plus handler/base/marker pins with their own self-test; positive controls for every verdict-owning helper; floors set to the exact count.

## Key Insight

When a conversion REMOVES a representation (C-quoting), ask what protection that representation provided by accident; the replacement inherits the hazard the old form hid. And when the artifact is a helper whose callers are PROSE an agent executes, the callers are the code under test: pin their spelling AND their failure arm, or "exit 2 means unknown" is a sentence nothing reads. The mutation battery cannot find either — it mutates the helper and the workflows, never the paragraph that invokes them.

## Session Errors

1. **Skill-prose conversion shipped a garbled command (`changed-paths.shchanged-paths.sh`)** — Recovery: round-1 fix plus per-site spelling pins — Prevention: pin every call site of a new helper in the same commit that adds the prose.
2. **Round-1 newline guard was dead (`head -c 1` inside `$( )` strips the LF)** — Recovery: `wc -c` count — Prevention: a guard written in a fix round needs its own RED row before commit; the fix agent's rows found it because they drove a newline name.
3. **The sentinel's `fail()` ran in a pipe subshell** — Recovery: process substitution; found by the lead's mutation battery (5/5 injected sites exited 0) — Prevention: grep the diff for `| while` followed by `fail`/`pass` whenever a suite is added.
4. **The DIFF_FAILED if/else broke the mirror test, which slices the step at its first column-10 `fi`** — Recovery: single-line `[ ] && { ...; }` list — Prevention: run the sibling mirror suite (`infra-validation-detect.test.sh`) after editing any workflow block it extracts.
5. **Two `git stash list` commands were blocked by the stash hook (typed by habit)** — Recovery: re-ran without it — Prevention: none needed beyond the existing hook (one-off).
6. **`test-all-affected.test.sh` exceeded the fan-out agent's 3000 s timeout and the long pin suites ran in parallel** — Recovery: left to CI as a non-reader of the changed lines — Prevention: run pin suites alone, never alongside siblings.
7. **The mutation battery's `git archive` copy was not a git repo, so the sentinel's `git ls-files` scanned nothing and the control went red** — Recovery: a one-call git shim — Prevention: any sandbox for a git-census guard is `git init && git add -A`.
8. **The accept-row audit needed re-deriving after each of four suite edits** — Recovery: a small script — Prevention: recurring toil, not fixed here (a regenerate verb for `ci-pr-affected-audit.accept.tsv` would belong in its own PR).

## Addendum — 2026-11-17 (PR #12809, Ref #12246)

**Problem.** The exit-42 fix makes `changed-paths.sh --match` exit 42 on "none match". It was meant to stop an unset `${CLAUDE_PLUGIN_ROOT}` under `set -u` (rc 1) from reading as "no match". It took four fix rounds, and each round's own new code opened a new fail-open path in the counsel gate:

- Round 2 read every open PR on the branch name, so a fork PR's body could supply a draft marker.
- Round 2's legal `git diff` honoured `diff.relative`, `diff.external` and textconv from config.
- Round 3's archive lookup matched a suffix-lookalike file.
- Round 3 keyed a skip on `legal=unknown`, not on "no readable base". So any helper failure in a repo with no tracked legal docs skipped counsel.

Each verification pass then found a sibling shape. You approved going past the 2+1 cap twice: A, then A2, with the last round verified only by the lead's mutant battery.

**Key insight.** Code added to a fail-closed gate in a fix round is a new input surface. List every external input it reads (PR bodies, git config, attributes, file names) before writing it. A skip arm must be keyed on the measured cause ("base unreadable and nothing tracked"), never on the generic `unknown` the gate already treats as a fire.

**Session errors (this PR).**
9. **Each fix round added fail-opens in its own new code** — Recovery: rounds 3–4, owner-approved — Prevention: before writing a fix-round predicate, list its external inputs and add one hostile-input row per input (routed to `risk-tier-and-fix-rounds.md`).
10. **I gave `review-scan-gate.sh` its paths on stdin; it printed `skip files=0` rc 0** — Recovery: re-ran with argv — Prevention: tracked on #12779 (refuse zero argv).
11. **A shim row passed for the wrong reason (`REAL_GIT` not passed, so every git call failed)** — Recovery: `counsel_run` passes `REAL_GIT`, and the row asserts `legal_touch` — Prevention: every shim row asserts one field the real binary must produce.
12. **A mutant went RED only because the shim refused its argv** — Recovery: the detached row passes `GH_EXPECT_BRANCH=` — Prevention: read why a mutant is RED, not only that it is.
13. **`lint-rule-bodies.py` run without `--check --base`** (rc 2) — Recovery: re-ran with the flags — Prevention: one-off; read the runner's invocation.
14. **The KB-ratchet baseline fix broke the file's 2-column format** — Recovery: restored 2 columns — Prevention: diff a baseline edit against its neighbouring rows.
15. **A single-file grep row expected a `file:` prefix** — Recovery: fixed the expected value — Prevention: one-off.
16. **`gh issue create` was refused twice (no milestone, then no filing exit)** — Recovery: added both — Prevention: already hook-enforced.
17. **The pre-push lane `fixture-dir-operand-assert` went RED on this host only** — Recovery: ran it directly (green) and left it to CI — Prevention: one-off.
18. **A seat could not delete its scratch repo (`rm -rf` hook on a dir holding `.git`)** — Recovery: owner removes it — Prevention: brief seats to clean up with `find <dir> -delete`.
19. **The scratchpad was wiped between sessions, so the verify brief was lost** — Recovery: rewrote it — Prevention: one-off; re-derive from the PR.
20. **Round 4's skip arm keyed "no base" on a missing merge base alone, so a shallow clone (base ref resolves, no merge base) of a branch deleting every legal doc skipped.** The lead's battery passed because no fixture had a base ref that resolves with no merge base. The CTO ruling pass that ship's technical-ruling gate requires found it — Recovery: round 5 (owner-approved), which also requires the base tree to hold no legal doc, plus fixture G, battery 12/12 RED — Prevention: when a predicate reads "X cannot be read", add a fixture for each way X can be half-readable (the ref resolves but the merge base, tree or object is missing).

## Tags

category: workflow-issues
module: changed-path readers, ship/preflight/review skill prose, ci workflows
