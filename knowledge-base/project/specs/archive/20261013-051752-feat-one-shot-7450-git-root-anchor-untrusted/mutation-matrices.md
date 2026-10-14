# Mutation matrices — #7450 (AC7, AC8)

Harness: each mutation applied to the real worktree, the guard run, the tree restored via
`git checkout --`, then the guard run AGAIN. Both directions are asserted, and a mutation that
fails to LAND is reported as such rather than silently counting as a survivor
(`hr-when-a-command-exits-non-zero-or-prints` applied to the harness itself). Tree verified
clean afterwards, with no mutant artifacts left behind.

**Result: 10/10 RED when applied, GREEN when reverted. Zero survivors.**

## Guard 1 — `apps/web-platform/test/plugin-root-anchoring.test.ts` (AC7)

| # | Mutation | Required | Observed | Reverted |
| --- | --- | --- | --- | --- |
| M1 | Revert `incident/SKILL.md`'s `SENTINEL=` to the git-root default form | RED | **RED** | GREEN |
| M2 | Point `linear-fetch`'s operand at CWD-relative `scripts/redact-linear-urls.sh` | RED | **RED** | GREEN |
| M3 | **Second member after a compliant first** — add a new `skills/zzmutant/SKILL.md` invoking `redact-sentinel.sh` through a git-root anchor while all four existing sites stay compliant | RED | **RED** | GREEN |
| M4 | **Own dispatch / anti-vacuity** — make the reference scan yield zero while the gate set stays non-empty | RED | **RED** | GREEN |
| M5 | **Derived script axis** — drop a new `redact-newthing.sh` on disk and invoke it through a git-root anchor | RED | **RED** | GREEN |
| M6 | Command-position bypass: `cd /tmp && bash "$(git rev-parse --show-toplevel)/…/redact-sentinel.sh"` | RED | **RED** | GREEN |

M3 and M4 are the mandatory rows and both hold. M3 is what proves the file axis quantifies over
every `SKILL.md` rather than the four filenames it was written against; a hardcoded four-file
list passes every other row and fails this one. M5 is the same proof for the script axis.

M4 is deliberately constructed to isolate the floor: the gate set stays populated (so `G0`
still passes) while the reference scan matches nothing, which is precisely the state in which
`G2` passes **vacuously** — zero references, therefore zero violations. Only the floor
distinguishes "compliant" from "scanned nothing".

## Guard 2 — `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` (AC8)

| # | Mutation | Required | Observed | Reverted |
| --- | --- | --- | --- | --- |
| M7 | Change the decoy from `exit 0` to `exit 2` | RED at the hazard-liveness assertion | **RED** | GREEN |
| M8 | Revert `incident/SKILL.md` to the git-root form | RED at the containment assertion | **RED** | GREEN |
| M9 | Delete the anchor extraction and hardcode a literal in the test | RED | **RED** | GREEN |
| M10 | Point Test 18's `ANCHOR` at the old literal while the SKILL.md files carry the new one | RED (count 0, not 1) | **RED** | GREEN |

M7 is the control on the control: if the decoy could not pass a file the real sentinel rejects,
the containment assertion in M8 would be asserting against an inert file. M9 is what stops the
oracle drifting into a self-referential copy — the test must keep reading its producer.

**M1–M10 are superseded as adequacy evidence, and retained as history.** The review panel's
post-mortem is the reason: all ten mutate the SUT, along five axes, and *"ten points along five
axes is not ten axes."* Six confirmed vacuities lived on the seven axes they never edit. They
still pass; they are simply not what establishes the guards are non-vacuous. The batteries below
are.

They also used a harness this file no longer sanctions — mutating the real worktree and reverting
via `git checkout --`. That is unsafe during a review pass (the tree is legitimately dirty, so
`git checkout --` can revert work in progress, and "did it land?" checked against `HEAD` gives the
wrong answer). Everything after this point mutates a **sandbox copy** and checks landing against a
**pristine backup**.

## Guard rebuild batteries (post-panel)

Run when the two guards were rebuilt to close the §A vacuities: **8 mutations against Guard 1, 6
against Guard 2, each with a GREEN control first and each asserted to have LANDED against a
pristine backup.** All RED. `M-D` of the Guard 2 battery was additionally proven non-equivalent.

*Record gap, stated rather than papered over:* the per-row detail of these two batteries was not
persisted at the time — `session-state.md` part 1, rows 2 and 3, carries the headline result and
the list of findings each closed, but not the individual mutations. The rows are therefore not
reproduced here, because inventing them after the fact would be exactly the self-graded-matrix
failure this project has already been bitten by twice
(`learnings/2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr…`).

## Battery 3 — the four assertions added by the review remediation (Tests 21, 22, 23, 24)

Guard 2 Tests 21 (B1 invariant), 22 (C10 telemetry markers), 23 (C12 / AC5d), 24 (stakes-keyed).

Harness: `cp -r` to a temp sandbox — every `${REPO_ROOT}`-relative read enumerated **from the
guard itself** rather than guessed, because a sandbox missing one produces a RED control that is
indistinguishable from a real regression (this happened on the first run and was fixed, not
worked around). Un-mutated control run FIRST and required GREEN. Each mutation compared against a
pristine backup before its verdict is believed.

**Control: GREEN, 96 pass / 0 fail. Result: 15/15 RED. Zero survivors, zero void rows.**

| # | Mutation | Target | Required | Observed |
| --- | --- | --- | --- | --- |
| M-A | **Review finding §B1's own prescription, applied literally** — its `case` statement added to incident's preflight fence | SUT | RED at Test 21 | **RED** |
| M-B | **Harness mutation** — fence extractor re-keyed to a language that never appears, so it yields an empty stream | **guard** | RED at Test 21's anti-vacuity control | **RED** |
| M-C | Delete the `redaction-ineffective` telemetry marker | SUT | RED at Test 22 | **RED** |
| M-D | Redirect a marker to stderr (marker present, but off the mirrored stream) | SUT | RED at Test 22 | **RED** |
| M-E | **Delete `[ -n "$PERSIST_SAFE" ]` outright** — finding C12's defect verbatim | SUT | RED at Test 23 | **RED** |
| M-F | Retain the non-empty check, convert its halt arm to `true` (the A2 fail-open shape) | SUT | RED at Test 23 | **RED** |
| M-G | Revert `community`'s router anchor to the `:-` form — **the site Test 24 found** | SUT | RED at Test 24 | **RED** |
| M-H | **Harness mutation** — gut the credential predicate so discovery returns nothing | **guard** | RED at Test 24's floor | **RED** |
| M-I | **Harness mutation, PARTIAL** — narrow the predicate so one required member vanishes while the COUNT stays healthy | **guard** | RED at Test 24's floor | **RED** |
| M-J | **A credential-setup invocation reverted to the BARE repo-relative form** — the shape the `:-`-keyed predicate could not see at all | SUT | RED at Test 24 | **RED** |
| M-K | Gate fence relabelled ` ```sh `, with B1's `case` planted inside it — one word, still executable to the agent | SUT | RED at Test 21 | **RED** |
| M-L | **Comment laundering** — delete the non-empty arm, leave its text in a comment | SUT | RED at Test 23 | **RED** |
| M-M | `exit 2; } >&2` — the redirect on the enclosing BRACE GROUP, marker line clean | SUT | RED at Test 22 | **RED** |
| M-N | **Population growth** — a NEW unmarked fail-closed halt added to a gate fence | SUT | RED at Test 22's growth floor | **RED** |
| M-O | **Harness dispatch** — every PASS/FAIL counter neutered (a suite that asserts nothing) | **guard** | RED at the EXPECTED_MIN floor | **RED** |

### Round 2 — the axes the first nine rows never edited

The nine rows above were written against the pre-review predicates and reported 9/9. Review then
found **15 vacuities on eight axes none of them touched**, having verified its own instruments
first (a known-positive and a known-negative both fired), so every survivor it reported was real
rather than a mutation that failed to land. `M-J`…`M-O` are those axes: invocation SHAPE (bare vs
`:-`), fence SYNTAX, comment laundering, redirect PLACEMENT, population GROWTH, and harness
DISPATCH.

**Five rows had to be re-pointed** after their landing checks reported `NOT APPLIED` against the
rewritten code. Reported here rather than silently repaired, because a stale mutation reports the
baseline and a baseline is indistinguishable from a pass.

`M-G` was re-pointed for a different and more interesting reason: its original target,
`community-router.sh`, correctly **LEAVES** the population under acquisition-keying (its only
credential mention is inside a routing-table string), so the row had been passing for the wrong
reason. It now targets `trigger-cron`, which is in the population — and in that form it initially
**SURVIVED**, exposing the assign-then-invoke gap described below.

The assign-then-invoke gap M-G exposed is worth its own line: Test 24's execution-context check
required a verb on the SAME line, so it missed `TRIGGER="…"` followed by `bash "$TRIGGER"` —
THE dominant shape in this corpus, and the reason Guard 1 needs G2 at all. All three of
`trigger-cron`'s sites are one assignment and two bare quoted-path invocations, so reverting its
anchor to `:-` was invisible until the check learned both shapes.

M-B is the row that answers the panel's post-mortem directly: *harness/guard mutation* was one of
the seven axes M1–M10 never touched, and it is the axis on which a guard silently stops guarding.
M-D and M-F are the "present but neutered" pair — both would pass a presence grep, which is why
neither test is written as one.

M-F is also the row that validates the harness. On its first run the mutation failed to apply (a
quoting error), and the landing check reported **`NOT APPLIED — row VOID`** instead of a verdict.
Without that check it would have been recorded as a survivor, and the natural response to a
"survivor" is to weaken or delete the assertion — a mutation battery whose bugs push toward
removing real coverage. It is reported here rather than quietly re-run.

### Two battery defects that produced wrong rows before they produced right ones

Both are recorded because each fails in the direction of false confidence.

1. **Cross-row contamination.** `restore()` initially omitted `community/SKILL.md`, so M-G's
   mutation survived into M-H and **M-H reported RED for M-G's reason** — a fake row
   indistinguishable from a real one, in a battery whose whole purpose is to be believed.
   `restore()` is now total rather than per-row.
2. **The anti-vacuity floor was a COUNT, and counts fail open on shrinkage.** Test 24's floor
   was `>= 5` against a real population of 21, and a PARTIAL predicate mutation survived it.
   *(Corrected at round-2 review: this paragraph credited **M-H**, and re-measurement shows M-H
   as committed EMPTIES the population — 0 < 5, which a count floor catches trivially. The row
   that actually survives a count floor is **M-I**, which drops the population to 9 while one
   required member vanishes. The conclusion — membership beats a count — is unchanged; the
   evidence row cited for it was wrong, and the battery script's own comment for M-H said
   "so the population goes empty", contradicting the narrative.)* That is finding A10 (`GATE_REF_FLOOR` fails open on additions) in
   another guise, reintroduced by me in the same PR that fixed it. The floor is now **required
   membership**: three pinned scripts, each a distinct credential-acquisition shape (secrets-manager
   read / ambient bot token / platform API key set). **M-I exists specifically to prove the
   replacement is stronger than the thing it replaced** — it narrows the predicate so exactly one
   required member disappears while the count stays healthy, and the old floor would have passed it.
