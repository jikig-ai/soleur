---
module: questionnaire-generate
date: 2026-09-20
problem_type: security_issue
component: skill_definition
symptoms:
  - "redaction floor unreachable on every customer install (repo-relative path)"
  - "gate exited 0 whether the sentinel scanned clean or could not evaluate"
  - "fence halted reason=draft-empty on every run after the fix for the first defect"
  - "ci.yml scheduled no pull_request run for twelve hours across nine pushes"
root_cause: verified_by_reading_not_executing
resolution_type: code_fix
severity: critical
tags: [fail-open, verification-method, dry-run, merge-ref, prior-art-search, repo-global-ratchet]
synced_to: [review, qa]
---

# Learning: I verified by reading, and the gate that mattered failed open

## Problem

One review-and-QA phase on #8289 (PR #8405). Four times I committed a fix, described it as working,
and was wrong in a way that only **executing** it could reveal. Nine review seats had read the same
prose and passed it.

**1. The redaction floor was unreachable for every installed user.**
`questionnaire-generate/SKILL.md` cited the sentinel as
`plugins/soleur/skills/incident/scripts/redact-sentinel.sh`. The plugin ships as `./plugins/soleur`
(`.claude-plugin/marketplace.json`), so that path does not exist on a customer install. Step 3 is the
only thing between an un-scanned document and the founder's mail client. Caught by CI —
`apps/web-platform/test/plugin-root-anchoring.test.ts`, 3 failed / 1532 passed — firing G2 (every
gate-script occurrence reaches through the `${CLAUDE_PLUGIN_ROOT}` anchor), G3/G5 (both population
pins), and then G5b, which obligates the ADR-179 plugin-**identity** preflight because the cheaper
`[[ -r "$SENTINEL" ]]` shape check was measured bypassable.

That suite lives under `apps/web-platform/test/` and references none of the changed files, so the
sanctioned substitute selection — grep which suites *mention* the diff — structurally cannot return
it. **Third instance of that blind spot on this one branch.**

**2. The fix for (1) made the gate unrunnable.** The fence I wrote referenced `$DRAFT` four times and
never allocated it. `legal-generate`, whose pattern I copied, does `DRAFT="$(mktemp)"` first; I
dropped the line. `[ -s "$DRAFT" ]` was therefore false unconditionally and the floor halted
`reason=draft-empty` on every run — while my commit message asserted the fence made the floor
reachable.

**3. The gate failed OPEN.** A constrained dry run (executing the prose against a synthesized
scenario) returned NOT RUNNABLE and found it. `sentinel_rc=$?` was the fence's terminal statement, so
the fence exited 0 whatever the sentinel said; the dispatch lived in prose below — a *different*
fence, which cannot see the variable, as the skill itself states twelve lines above; and rc=0 and
rc=2 produce **byte-identical stdout, zero bytes each**, because the cannot-evaluate diagnostic goes
to stderr. Measured:

| draft | sentinel rc | stdout |
|---|---|---|
| clean | 0 | 0 bytes |
| synthetic PEM | 1 | 53 bytes |
| unreadable | 2 | **0 bytes** |

So an un-scanned document was indistinguishable from one that scanned clean, and the documented
"**2** — cannot evaluate. **Halt.**" arm was unreachable — in the one gate whose entire purpose is to
fail closed.

**4. My own step reorder broke the skill three ways.** Moving the glossary stop-list during review
put the redaction floor **upstream of the step that creates its input** (the floor consumed "the
assembled questionnaire" while assembly was Step 5 item 1), put a knowledge-base read on the drafting
path that Step 2 absolutely forbids, and let the stop-list rewrite text **after** the sentinel
cleared it — reintroducing the un-scanned preview the floor exists to prevent, legitimately, with
every gate green.

**Separately: `ci.yml` scheduled nothing for twelve hours across nine pushes.** The API reported
`total_count=2` for the branch while creating `pull_request` runs for seven *other* branches within
seconds of my push. No error, no queued run, nothing wrong with the workflow file.

## Solution

**The four verification defects.** Anchor the invocation through `${CLAUDE_PLUGIN_ROOT}`, add both
population pins, carry the ADR-179 identity preflight whose own arm exits 2, allocate `$DRAFT` with
`mktemp` plus a trap, and move the dispatch **inside** the fence as a `case` that emits exactly one
`SOLEUR_QUESTIONNAIRE_*` marker and halts on anything but clean. Reorder to: interview → assemble
Context → assemble the whole document and apply the stop-list → **redaction floor** → preview +
typed confirmation → emit, so the floor scans the bytes that actually go out and nothing edits after
it. Then drive every arm: clean → 0, secret → 1, empty → 2, no plugin root → 2.

**The CI block.** A PR marked `mergeable: CONFLICTING` gets **no `pull_request` workflow runs at
all**, because those run against the merge ref `refs/pull/N/merge`, which GitHub cannot compute for a
PR it cannot merge. `pull_request_target` (the CLA jobs) and CodeQL run against base/head and keep
firing — which is exactly why the signature is *some workflows run, one specific trigger is silently
absent*. The conflict was not real: `git merge-tree --write-tree origin/main HEAD` returned rc=0 with
zero conflict markers against a freshly-fetched current main, and the merge applied cleanly. A
**stale** `CONFLICTING` starves scheduling exactly as a genuine one does. One `git merge origin/main`
flipped `mergeable` to MERGEABLE and CI scheduled immediately.

## Key Insight

**Reading verifies syntax; only running verifies behaviour — and every one of these four defects was
invisible to reading by construction.** A path that is correct in the repo and wrong on an install, a
variable that is referenced but never bound, an exit code that is discarded by an assignment, and a
step order whose breakage is a *data dependency* between steps: none is visible in the text of the
change. Three of the four were introduced by me *while fixing* the previous one, which is the real
signal — a fix round is the least-audited part of a diff, and I kept grading mine by re-reading.

The operational rule: **for any gate, drive all of its arms before claiming it works, including the
cannot-evaluate arm.** A gate has three outcomes (clean / violated / could-not-measure) and the third
is the one that silently equals the first. `rc=0` and `rc=2` producing identical stdout is not an
exotic case — it is the default whenever a tool writes its diagnostics to stderr.

**And the second lesson is worse than the first: the remedy for the CI block already existed and I
re-derived it over ~15 probes.** `plugins/soleur/scripts/sync-pr-behind.sh:75-79` already treats
`DIRTY` as a sync candidate keyed on `git merge-tree`'s exit code, with a comment naming this exact
class — shipped the day before, by
[2026-09-19-githubs-merge-ref-runs-your-prs-own-defect-against-it.md](2026-09-19-githubs-merge-ref-runs-your-prs-own-defect-against-it.md),
which enumerates three surfaces of it. This session found a **fourth** surface (scheduling starvation,
where no run is created at all — distinct from that learning's stale-merge-ref-tree, where a run
exists and fails). But the diagnosis cost nothing to look up and ~15 probes to derive. `mergeable:
UNKNOWN` was in my *first* `gh pr view` of the phase and I read past it, then probed workflow-file
validity, `state=active`, actionlint, `[skip ci]` directives and concurrency groups — none of which
can produce "one trigger absent while others fire".

Diagnostic order, for next time: **when one trigger is silently absent while others fire on the same
push, read `mergeable` first, then search `knowledge-base/project/learnings/` and `plugins/soleur/scripts/`
for the class before deriving anything.**

## Prevention

- **A skill-prose change gets a constrained dry run, not a read.** Execute it against a synthesized
  scenario under no-write / no-send / no-credential constraints and report every sentence that cannot
  be followed. This is already in `qa/SKILL.md` §Notes from #8288; it found all of (2), (3) and (4)
  after nine seats missed them.
- **A fenced gate in a SKILL.md is a template, and its emptiness check is what catches an author who
  forgot the body.** Allocate the artifact in the same fence, and never let the fence's terminal
  statement be an assignment — dispatch inside it.
- **Grep the guard's own vocabulary for a sibling arm before calling a class fixed.** `bad-filename`
  and `no-frontmatter` were three lines apart with the identical early `return 0`.
- **A repo-global ratchet cannot be reached by a file-selected suite set.** Keep a hand-maintained
  list and re-run it; `plugin-root-anchoring.test.ts` now belongs on it for any diff touching a
  `SKILL.md` that cites a gate script.

## Session Errors

Items 1–8 forwarded from `specs/feat-one-shot-8289-kb-glossary-rejected-register/session-state.md`;
9–24 are this phase.

1. **Two tool calls denied by hooks** — `iac-plan-write-guard.sh` matched prose *describing the
   absence* of infra patterns; a `bash` call carried a secret-write literal. Recovery: reworded both.
   **Prevention:** never reach for the `iac-routing-ack` opt-out to clear a false positive — it
   asserts a reviewed infrastructure step that does not exist.
2. **A standing-AC check declared clean on ambient machine state**, never tested against a sibling
   branch moving a shared constant. **Prevention:** pin absolute literals in ACs; ambient state is
   not a measurement.
3. **The first rule-pointer design was unreachable** — `AUTHORITY_RE` wins before rung 5.
   **Prevention:** for a classifier, assert the ARM fires behaviourally, never that the text exists.
4. **A liveness probe pointed the lint at the one path its glob excludes** — would have stayed green
   with every entry check deleted. **Prevention:** a probe must be shown to fail on a known-bad input
   before its green is evidence.
5. **Five stale references survived the revisions.** **Prevention:** grep the OLD claim after
   correcting it, never the new one.
6. **R28 — the naming decision never propagated**: `register` ×64 and "the store" ×19 still named the
   new artifact, including `title:` frontmatter, while `tasks.md` already used the corrected names.
   **Prevention:** a decision sweep greps the decided-against term, and an independent pass runs it.
7. **The plan's mandated floor spelling would have shipped a guard the guard-guard cannot see** —
   `[[ … ]] && { … }` is invisible to `floor_lines_of()`. **Prevention:** the plan is authoritative
   for a floor's intent, not its syntax; check the detector's pattern.
8. **Then that ratchet reddened correctly** — cardinality floors read from the ids file pass over a
   suite that asserted nothing. **Prevention:** floor the quantity incremented at the CALL SITE.
9. **`plugin-root-anchoring.test.ts` failed in CI (3/1532)** — repo-relative sentinel path.
   **Prevention:** cite a gate script only through `${CLAUDE_PLUGIN_ROOT}`; the repo path is a
   different filesystem from the install.
10. **The fence referenced `$DRAFT` without allocating it** — halted unconditionally. **Prevention:**
    when copying a gate pattern, diff it against the source; the line you drop is the one that binds.
11. **The gate failed OPEN** — rc=0 and rc=2 byte-identical. **Prevention:** drive the
    cannot-evaluate arm explicitly; stderr-only diagnostics make it look clean.
12. **My step reorder broke three things.** **Prevention:** after reordering steps, trace each step's
    inputs to the step that produces them.
13. **`bad-filename` fixed, `no-frontmatter` twin left** (3 findings vs 1, identical bytes).
    **Prevention:** grep sibling arms in the same function before closing a class.
14. **README "never paste" corrected; the emitted template still said "paste the reply here".**
    **Prevention:** a rule change sweeps every artifact that *renders* the rule, not just the one that
    states it.
15. **`status: sent` written at emit time** — an unsent document reported itself overdue in an
    unattended sweep that posts to a public issue comment. **Prevention:** never emit a state that
    asserts an event the emitter did not observe.
16. **The root-README exemption compared path strings against an absolute `DEFAULT_DIR`** — refused my
    own `git push`. **Prevention:** compare canonical paths (`cd && pwd -P`), because lefthook hands
    repo-relative and the script derives absolute.
17. **A correct fix with a false rationale, twice** — the tmpfs/OOM story (892 KB not 7.7 GB; btrfs
    not tmpfs) and `MIN_ASSERTIONS`'s "ck sites inside loops" (zero exist). **Prevention:** name the
    command that falsifies each causal sentence you write, and run it.
18. **CONCUR dissented and was right** — my false-positive claim was inverted; the staged blob *is*
    the commit's content. **Prevention:** the gate exists for the dissent case; do not pre-argue it.
19. **Two commits OOM-reaped at ~22 min** under the contended full gate. **Prevention:** check
    `test-all.sh --capacity` first; a reaped task does not imply a reaped process tree.
20. **`rc=$?` after a pipe read `tail`'s status** and reported `push rc=0` on a FAILED push.
    **Prevention:** redirect and read `$?`; never pipe a command whose exit code is the result.
21. **`ci.yml` silent for 12 h across 9 pushes** — stale `CONFLICTING`. **Prevention:** read
    `mergeable` first when one trigger is absent; then search prior art before deriving.
22. **A backtick `scripts/` reference in my own edit** reddened `components.test.ts` 1368/1.
    **Prevention:** markdown links, not backticks, for `references|assets|scripts` paths.
23. **ADR-232 ordinal collision on merge** — renumbered to 234, rename scoped by hand because
    `model.c4`/`views.c4` cite a different #8359 ADR-232. **Prevention:** never repo-wide-sed an
    ordinal; scope to the diff's own files and verify the others are untouched.
24. **Two malformed mutation probes scored nothing** (rc=2 syntax errors) and one arithmetic
    prediction was wrong until measured. **Prevention:** a mutant that does not compile proves
    nothing — assert the mutation landed before reading the verdict.

## Tags

category: security-issues
module: questionnaire-generate
issues: #8289 #8405 #8151
