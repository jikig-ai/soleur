---
module: Supabase Management API log query
date: 2026-09-02
problem_type: test_failure
component: shell_script
symptoms:
  - "Helper returned CONFIG_ERROR / exit 2 on every live invocation"
  - "HTTP 400 iso_timestamp_start: Invalid ISO datetime for every ref, window and source"
  - "Three suites, two mutation batteries and twelve review agents all green over it"
root_cause: test_seam_above_code_under_test
severity: critical
tags: [test-seams, mocking, external-api, mutation-testing, false-green, supabase]
synced_to: [review, work]
---

# My fake `curl` put the fixture seam above everything the vendor validates

## Problem

`scripts/supabase-logs-query.sh` shipped with `to_iso()` emitting a naive timestamp — no
timezone designator:

```bash
to_iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%S 2>/dev/null; }   # no Z
```

The Supabase analytics endpoint answers that with `HTTP 400 iso_timestamp_start: Invalid ISO
datetime` — for **every** project ref, **every** window, **every** source. The helper could not
complete a single real query. It reported `CONFIG_ERROR` / exit 2 and told the reader to go
check their ref, which is a diagnosis of the one thing that was not wrong.

Measured, same ref, same SQL, same window, sole variable:

| `iso_timestamp_start` | Response |
|---|---|
| `2026-08-26T00:00:00`  | HTTP 400 `Invalid ISO datetime` |
| `2026-08-26T00:00:00Z` | HTTP 200 `{"result":[{"c":5123}]}` |

## What it passed on the way in

- 3 test suites — 31 + 34 + 45 assertions
- 2 self-run mutation batteries — 7 rows and 12 rows, **both reporting no survivors**
- 12 review agents, including `security-sentinel`, a dedicated structural-enumeration seat,
  and `test-design-reviewer` — which found **12 other** surviving mutants and not this one
- `shellcheck -S warning`, `actionlint`
- a binding CLO ruling pass over the same branch

## Root cause

The suites drive a **PATH-shimmed fake `curl`** that echoes a fixture regardless of what it is
sent. That places the fixture seam **above** the code under test for every property the
**vendor** validates: request encoding, parameter format, header shape, auth form.

Two consequences, and the second is the one that makes this worth a learning:

1. Mocked coverage cannot reach that class at all. Not "reached it weakly" — cannot reach it.
2. **A mutation battery cannot reach it either**, because it perturbs the SUT and then observes
   the SUT *through the same seam*. Every row is scored by a fake that was never taught what
   the vendor rejects. A battery's green is evidence about the mutations its author imagined,
   evaluated by an oracle that shares the blind spot.

## Two near-misses that sharpen the rule

- **The plan's Phase 0 live probes did not catch it.** They were hand-written `curl`s with
  `Z`-suffixed bounds — correct by accident, because a human writing an ISO timestamp writes
  the `Z`. They probed the **endpoint**; the defect was in the **client**. *Probing the endpoint
  is not probing the client.*
- **A later fix agent added `_ref` and SQL-shape assertions to that same stub** and still added
  no timestamp-format assertion, because it was reasoning about what the SUT *sends* rather than
  about what the vendor *rejects*. Hardening a stub along the axes you already have in mind does
  not widen the axis set.

## Solution

Restore the designator, and teach the fake the contract:

```bash
to_iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; }
```

```bash
# in the fake curl: a bound with no timezone designator is what the live endpoint rejects
for _b in "$ts_start" "$ts_end"; do
  case "$_b" in
    *Z|*+[0-9][0-9]:[0-9][0-9]|*-[0-9][0-9]:[0-9][0-9]) : ;;
    *) printf 'STUB: iso bound %q has no timezone designator\n' "$_b" >&2; exit 69 ;;
  esac
done
```

Mutation-proven against a **green** control: dropping the `Z` takes the suite from
`31 passed / 0 failed` to `17 passed / 14 failed`. The new rejection immediately caught the
harness's **own** hand-written seam probe, which carried the same naive form — the harness was
violating the contract it now enforces.

## Prevention

- **For any client of an external API, at least one verification must exercise the REAL request
  path, end to end, with the client's own argument construction.** Not the endpoint with
  hand-written arguments — the client.
- **Teach the stub to reject what the vendor rejects.** A stub can only catch what it is taught;
  a stub that answers identically for every request is an oracle that certifies request shape it
  never inspected. Give it a distinct exit code per contract violation so a failure names itself.
- **Before crediting any mutation battery, ask what the ORACLE can see.** Rows are scored through
  the seam. If the seam is a permissive fake, no row can test a vendor-validated property, and
  "no survivors" is a statement about the SUT evaluated by something blind to a whole class.

## Session errors

- **`to_iso` shipped without the timezone designator (P0).** — Recovery: found by running the
  real script against the real API once; fixed and mutation-proven. — **Prevention:** the
  end-to-end live check above, now a required verification for any external-API client.
- **`DEFAULT_REF` pointed at the wrong Supabase project.** It was pinned specifically to close
  "a format-valid WRONG ref prints COVERED over another project's data", but the pinned value was
  the Inngest backing project while every documented consumer (both DSAR runbooks, the breach
  runbook, two skill bodies) needs the application project — a DSAR would have returned a clean
  zero from a database that never held the subject's data. — **Prevention:** a mitigation that
  installs a default is a silent assumption in the place the tool exists to make assumptions
  explicit; the fix REMOVED machinery (`--ref` is now required and names both projects).
- **Coverage was classified from the project-wide span, not the requested source's.** A quiet
  source returning 0 where a noisy sibling spanned the window classified FULL → exit 0 → "safe
  to quote". — **Prevention:** when a verdict is about X, derive it from X's own evidence; a
  sibling's data is not X's coverage.
- **My append-only verification was written as `git diff | grep -cE '^-[^-]' | head`.** The
  pipeline exit is `head`'s, so the `&&` branch fired regardless and it reported deletions in all
  three evidence records when there were none. — **Prevention:** never let a pipeline's exit
  status stand in for a predicate; grep a file and compare with `[[ ]]`.
- **My collision check printed `comm: input is not in sorted order` and returned an answer.** I
  nearly accepted it. — **Prevention:** `LC_ALL=C sort -u` into temp files before `comm`, and
  treat any tool diagnostic on stderr as voiding the result.
- **My reproduction of the guard's CRITICAL bypass was invalid** — the sandbox enumerated 0 files
  so the guard's scope-loss guard fired, and I read that output as a repro result. — **Prevention:**
  a reproduction needs a positive control proving the harness can produce the non-bug outcome.
- **A `.highwater` header shipped a stale `25` while its value was 26**, and a discharged
  re-measure instruction. — **Prevention:** a number that moves without a reason attached stops
  being evidence; record the transition, do not silently edit the digit.
- **ADR-197 and the plan shipped four false claims** (a property of an untouched runbook that says
  the opposite; `#6288` called "two-month" when it ran 8 days; `::error::` CI annotations that no
  script emits; a D-1 implementation count of two when one qualifies). — **Prevention:** for every
  causal or universal claim the prose ADDS, name the falsifying command and run it.
- **My `ci.yml` comment spelled out the projects-scoped path literal**, putting `ci.yml` into the
  guard's own assembly and reddening my own commit. — **Prevention:** a guard that greps whole
  files owns every file that mentions its literal, including the prose explaining the guard.
- **My `Z`-fixup regex blocked the `..` range separator along with `.NNNNNN` fractional seconds.**
  — **Prevention:** when a lookahead excludes a character class, enumerate what legitimately
  follows the match before assuming the exclusion is safe.
- **I ran `git stash list`, which tripped the guardrails hook.** — **Prevention:** the hook is
  correct; use `git show <commit>:<path>` to inspect instead.
- **`session-state.md` restated the plan's finding-C counts after a re-measurement had produced
  different ones.** Neither was stale — they are samples of a quantity that moves. — **Prevention:**
  cite the canonical file rather than restating; when two measurements of a moving quantity
  coexist, say so, because otherwise they read as a contradiction.
- **The plan's §6.3 named a post-mortem directory that does not exist.** — **Prevention:** a plan
  is authoritative for intent, never for paths.
- **Four agents died mid-flight on API errors.** — Recovery: **resumed, not respawned**, which
  preserved their transcripts and lost no committed work. — **Prevention:** resume by agent id;
  a fresh spawn discards findings already established.
- **Fixture row ids were prod-shape UUIDs**, found only because the content gate was extended to
  cover `tests/scripts/fixtures/**`. — **Prevention:** extending a gate is how you find out it was
  needed; fix at the fixtures rather than widening a shared security allowlist.

- **Routing this very learning, I wrote the bullet into an UNQUOTED heredoc** (`<<PY`), so bash
  command-substituted the backticks and `$(...)` inside the prose before python ever saw it —
  the same eaten-text trap this repo documents for `git commit -m`. — **Prevention:** any
  heredoc carrying prose with backticks must be quoted (`<<'PY'`); the tell is a
  `command not found` for a word that only ever appeared inside your text.
- **I misread which file held an anchor**, because `grep -n <pat> <single-file>` omits the
  filename prefix — I attributed `work/SKILL.md:202` to `review/SKILL.md` and then asserted three
  times against a file that never contained the string. — **Prevention:** pass two files, or
  `grep -H`, whenever the output will be used to decide WHICH file to edit.

- **My scope-out was wrong on its own definition, and a prose guard I wrote was read by nobody.**
  I claimed `cross-cutting-refactor` (≥3 files *materially unrelated to the PR's core change*)
  for repointing 22 citations. Measured: **all 22 citing files were in this PR's diff and this
  PR authored every citation line** — zero unrelated. I had counted topical diversity (scripts /
  legal / ADR / runbooks / fixtures), which the criterion does not ask for. Worse, the
  re-evaluation trigger I proposed ("before anything archives that spec directory") had no
  detector: `archive-kb.sh` appends the whole `specs/feat-<slug>` directory and `git mv`s it,
  with **zero** guard-string matches in its 174 lines — so the in-file `DO NOT ARCHIVE` block I
  had just written was defensive prose nothing reads. — Recovery: closed the issue, did the
  `git mv` + repoint inline (26 occurrences, 22 files, zero residual, all gates green).
  — **Prevention:** count the criterion's OWN quantity, not a proxy for it; and before writing a
  guard, `grep` the thing that would have to honour it. A guard that no consumer reads is a
  comment with a threatening tone. Corollary the gate also caught: a citation inside an
  append-only block that THIS PR added is still your own working diff, so the "it's a signed
  record" hesitation dissolves pre-merge and hardens post-merge — which argues for fixing now.
- **I filed that `deferred-scope-out` issue (#7752) BEFORE invoking the CONCUR gate.** The gate
  exists for the DISSENT case, so filing first leaves a publicly-visible issue to retract if the
  second reviewer disagrees — the repo documents this exact ordering as a protocol violation
  "even when the agent eventually returns CONCUR". — Recovery: ran the gate immediately after,
  disclosed the ordering to it, and committed to closing the issue and fixing inline on a
  DISSENT. — **Prevention:** the gate is a precondition, not a confidence check; the pull toward
  skipping it is strongest exactly when every signal seems to align, which is the rationalization
  it was built to catch.

- **My plan wrote `credentials_required: none — replays synthesized fixtures ...`, and that
  GRANTED the credentials waiver.** Preflight Check 10 treats any non-placeholder value in that
  field as "this probe cannot run unauthenticated", returns SKIP-DECLARED, and never executes the
  command. Its anchored placeholder regex is `^(todo|tbd|n/a|na|none|...)$` — anchored, so the
  bare word `none` would have been caught, but `none — <explanation>` sails through. A field
  whose value says *no waiver is needed* was silently granting the waiver, on the most natural
  misreading of its own name. Same family as this document's primary finding: an instrument that
  returns a confident answer while measuring nothing. — Recovery: removed the field (absence is
  what makes Check 10 run), left a comment saying why it is absent, and verified by EXECUTING
  the gate — the probe ran inside bwrap, rc=0, `31 passed, 0 failed`. It would also have pushed
  the `check10-test-manifest` G1 corpus baseline 6 → 7; mutation-proven by re-adding the line and
  watching G1 go red. — **Prevention:** a schema field that can DISABLE a gate must be read as
  "does this value disable it?", never as "is this value informative?" — and the placeholder
  guard on such a field belongs on the first token, not the whole string, because every
  well-meaning author appends a justification.
- **The same plan's `## User-Brand Impact` answered Check 6 in full and still failed it**, because
  the threshold was prose rather than the canonical `- **Brand-survival threshold:**` bullet the
  anchored extractor requires. — **Prevention:** when a gate reads a document by anchored regex,
  the document is a machine input; run the gate's own extractor against the artifact rather than
  reading it and judging that the answer is present.
- **Neither gate would have run at all**: the PR body linked no plan file, so Check 6 fell back to
  the body alone and Check 10 returned SKIP at row 1. `/compound` had archived the plan to
  `plans/archive/`, and nothing re-pointed the PR body at it. — **Prevention:** archiving a plan
  moves the artifact two compliance gates resolve by path; a run that archives mid-pipeline must
  re-point the PR body, or the gates downgrade to SKIP and report silence as success.

## Related

- `knowledge-base/project/learnings/2026-08-11-my-fixture-shared-the-bug-so-the-test-could-not-see-it.md`
  — the sibling shape, where the fixture rather than the seam carries the defect.
- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
  — a battery is evidence about its mutations; this adds that it is also bounded by its ORACLE.
- `knowledge-base/project/learnings/integration-issues/2026-08-26-a-short-answer-is-the-bug-across-two-log-surfaces.md`
  — the same PR's other learning, on the invariant the helper enforces.
