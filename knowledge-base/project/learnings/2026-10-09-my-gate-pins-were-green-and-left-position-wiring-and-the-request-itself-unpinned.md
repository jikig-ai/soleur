# Learning: a parsed-YAML gate pin certified the gate string and left everything around it unpinned

## Problem

#7256 added a failure-gated sibling step (`Post to Slack (release BLOCKED)`) because the
existing Slack step has a plain `if:` (implicit `success()`), so a blocking zot mirror failure
skipped it. The first cut had a 53-assertion suite on the parsed workflow (whole-value `if:`
equality, a census of steps that reference the webhook secret, env wiring, the real run block
under a curl stub) and an 11-row mutation battery that killed every row. Review then found 22
further surviving mutants, all on axes the battery never edited:

- **Position.** Moving the notifier before Finalise, before the bridge, or before
  `create_release` stayed green. `failure()` is evaluated when the step is reached and
  `released` is only set by `create_release`, so a step in the wrong place can never fire.
- **Step-id resolution.** Renaming `id: zot_mirror` or `id: token_preflight` stayed green: the
  env pins compared strings, an undefined id renders as the empty string in Actions, and the
  run-block test sets env directly so it cannot see the wiring.
- **The request itself.** The curl stub recorded only `-d`, so a different URL, a dropped
  `Content-Type`, `--max-time`, `-s`, `::add-mask::`, or a non-2xx path all survived.
- **Dispatch.** Deleting the whole new section left 26/26 green (no assertion floor).
- **Message content.** `nothing was published` (the exact claim ADR-166 forbids), a dropped
  version slot (the fixture's VERSION was a substring of its TAG) and a dropped `(the draft is
  kept)` all survived.

Three correctness defects were also in the step's own code, none visible to the green suite:

1. `${v//&/&amp;}` is not an escape in bash >= 5.2: `&` in the replacement expands to the
   matched text (`patsub_replacement`). The escape fixture caught it; reading did not.
2. `|| echo "000"` after `curl -w "%{http_code}"` prints `000000` on a transport failure,
   because curl already printed `000`. My stub exited non-zero without printing, so the
   doubling could not appear and the mutation row reverting it survived.
3. `MIRROR_REASON` is empty on a SUCCESSFUL mirror too (only `degraded()` writes it), so the
   fallback text `not reached` asserted a cause the job never measured.

## Solution

- Workflow: `|| HTTP_CODE=000`, `--proto '=https'`, an honest fallback
  (`n/a (failed before or outside the mirror step)`), and comments that say "expected, not
  verified" about the timeout window.
- Suite: pin the step's index against create_release / teardown / Finalise; resolve every
  `steps.<id>` the step reads against the job's real ids (and pin the referenced set, so the
  extractor cannot go quiet); pin the exact env key set; assert no `shell:` override; derive
  gate parity from the real Finalise and Email steps; make the curl stub record argv and honour
  `CURL_CODE`/`CURL_FAIL` the way real curl does (print `000` before a non-zero exit); assert
  `::add-mask::` and that the raw webhook appears exactly once; use a VERSION that is not a
  substring of the TAG; add an anti-vacuity floor (`MIN_ASSERTIONS`, `printf` + `exit 1`,
  literal adjacent to the `if`, so `guard-vacuity-floor.test.sh` can build its mutant).

## Key Insight

A whole-value gate-equality pin answers "is the condition string what I wrote", not "will the
step fire where it is placed, read what it reads, and send what Slack needs". For a step
whose job is to fire on failure, **position and wiring are part of the gate**. Likewise a
stub is only as strong as its fidelity to the real tool's output on the failing path: a stub
that exits without printing what the real tool prints before it fails hides every fallback
that interacts with that output.

Two process notes:

- A file with a path trigger (`build-inngest-bootstrap-image.yml` fires a mint + zot push,
  `plugins/soleur/**` fires a web deploy) can carry a live stale comment you cannot fix in the
  same PR. Record it in the PR body instead of editing it.
- My own 11-row battery was green because every row perturbed bytes an assertion already read.
  Count the AXES a battery edits (position, id resolution, key set, argv, dispatch, message
  content), not the rows.

## Session Errors

1. **`${v//&/&amp;}` expanded `&` to the match under bash 5.2** — Recovery: `sed` entity
   escape — Prevention: never use `&` in a bash pattern-substitution replacement; run the
   escape fixture against a hostile value, not just a clean one.
2. **`|| echo "000"` doubled curl's `000`; stub did not model curl's `-w` output** — Recovery:
   `|| HTTP_CODE=000` and a faithful stub — Prevention: a stub for a tool with `-w`/exit-code
   behaviour must print what the real tool prints before it exits non-zero.
3. **SC2016 on backticks inside a single-quoted printf format** — Recovery: double-quoted
   format with escaped backticks — Prevention: run actionlint (with shellcheck) on the new
   step before committing, diffed against `origin/main`.
4. **Census expected-order wrong** (`(release BLOCKED)` sorts before `(release)`) —
   Recovery: corrected the literal — Prevention: derive an expected sorted list from `sort`,
   not from reading names left to right.
5. **11-row self-battery missed 22 mutants** — Recovery: second battery on the missing axes —
   Prevention: enumerate battery axes before crediting it; ask the test-design seat to find
   what the battery missed, not to re-run it.
6. **My own replace merged the test header's usage line** — Recovery: restored the line —
   Prevention: re-read the edited region after a scripted multi-line replace.
7. **`not reached` fallback claimed an unmeasured cause** — Recovery: non-committal fallback
   pinned both ways — Prevention: a fallback label may only state what the job measured
   (ADR-166); ask "what produces this value's empty state besides the failure I imagine?"

## Tags
category: test-failures
module: reusable-release
