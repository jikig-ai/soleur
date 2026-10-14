# ADR-Ordinal Collision Gate

Moved verbatim out of `ship/SKILL.md` Phase 5.5 to stay under the SKILL.md body ceiling (ADR-229); SKILL.md keeps the trigger and a load directive.

Blocks PR-ready when the branch adds a NEW `ADR-NNN-*.md` whose ordinal `NNN` is already taken on `origin/main` by a DIFFERENT file. The ordinal was free when the ADR was authored at plan/brainstorm time, but a sibling PR claimed it during the pipeline. A collision cannot reach `main` through the queued auto-merge (the `--admin` hatch in Phase 7 bypasses the whole `required_status_checks` rule, which is why its step 2 exists): `adr-ordinals` is a required status check and `main` is strict-up-to-date, so a sibling's ADR arriving through a Phase 7 sync reds the PR's own `adr-ordinals` job and the poll loop's required-check-failure exit stops there (Phase 7, "ADR-ordinal collision after a sync", cites the SSOT). This gate is defense-in-depth: catching the collision at PR-ready costs one commit, while catching it in Phase 7 costs a sync plus a full CI cycle (the ~35-minute figure the settle paragraph measures), and a renumber done inside the poll loop is the one most likely to leave the plan/tasks sweep undone.

**Detection.** Run the canonical sentinel named on the Trigger line in `ship/SKILL.md` (fetch `origin/main` first, run from the branch root).

`check-adr-ordinals.sh` exits 1 with `NEW ADR ordinal collision (not in pre-existing allowlist): ADR-NNN` when two files share ordinal `NNN` (it does NOT heading-check a new ADR — its layer-3 heading check is pinned to ADR-041/ADR-042 only, per the script header; ADR-210 shipped without a `## Status` heading and it passed). Exit 0 → pass silently.

**If it exits 1 on an ADR THIS branch introduced:** renumber to the next free ordinal BEFORE merge — never merge a colliding ADR:

1. Next free ordinal — **`max + 1`, after a fresh fetch. Never a presence check.**

   ```bash
   git fetch -q origin main
   HI=$(git ls-tree -r --name-only origin/main -- knowledge-base/engineering/architecture/decisions/ \
        | grep -oE 'ADR-[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)
   echo "highest=ADR-$HI  next free=ADR-$((HI+1))"
   ```

   The previous form here ended at `tail -1` and was labelled "next free" while returning
   the **highest** — follow it literally and you re-take the ordinal you just measured.
   And do not substitute a presence check: `grep -c 'ADR-<n>'` returns a **match count**,
   so a `|| echo FREE` fallback fires only when grep *fails*, and a successful match prints
   a number that is easy to read as the fallback's absence. **Why:** #7190/PR #7195 — three
   ordinals in one session (158 taken at plan time, 160 and 161 both claimed by siblings
   mid-pipeline); the second collision was nearly shipped on exactly that misread.
2. `git mv` the branch's ADR to `ADR-<next>-<slug>.md`, fix its `# ADR-NNN:` header, and sweep every reference in the SAME feature's artifacts (plan, `tasks.md`, `session-state.md`, learning, PR/issue bodies). Scope the sweep to YOUR ADR so the sibling that legitimately holds the ordinal is untouched: `grep -rln 'ADR-<old>' knowledge-base/ | xargs grep -l '<feature-slug>'`.

   **That `knowledge-base/`-scoped sweep is necessary but NOT sufficient — an ADR ordinal
   can be cited from CODE.** Sweep the branch's whole diff, then classify each hit:
   `for f in $(git diff --name-only origin/main...HEAD); do [[ -f $f ]] && grep -Hn 'ADR-<old>' "$f"; done`.
   Hits in a hook, a script or a test are the dangerous ones — an ADR reference inside a
   runtime **deny reason string** ships to the agent (or the operator) pointing at whatever
   unrelated ADR now holds that ordinal. Check the CLAUSE LABEL too: a provisional ADR
   drafted with `D1/D2/D3` sections that ships restructured leaves `ADR-<n> D3` dangling on
   both halves, and a pure ordinal bump does not fix it. **Why:** #7195 — nine `ADR-158 D3`
   citations shipped in a hand-ported hook mirror, five inside the agent-facing deny string;
   the plan's prescribed sweep globbed a per-feature `plans/` directory that does not exist
   (it holds flat files) and never covered that mirror at all. (The mirror itself was retired
   2026-09-23 — ADR-245 — but the lesson is about the sweep's reach, not that directory.)
3. Re-run `check-adr-ordinals.sh` → must exit 0. Commit + push (`incr ci_cycles` after).

**The collision window extends through Phase 7** (mirrors the migration-number-collision re-check in work Phase 2): a sibling's ADR can land on `main` and be pulled into the branch by a **BEHIND auto-sync AFTER this gate ran**. After any Phase 6.5 / Phase 7 sync whose merge output lists `knowledge-base/engineering/architecture/decisions/`, re-run `check-adr-ordinals.sh` and renumber-during-ship before the next merge attempt (see Phase 7 "ADR-ordinal collision after a sync").

**Why:** PR #5945 (#5933) chose ADR-081 at plan time (080 was the highest then); sibling PR #5934's ADR-081 landed during the ~90-min pipeline and auto-synced into the branch during Phase 7. The ruleset did not yet carry `adr-ordinals`, so the auto-merge fired on the green required set and the collision surfaced as RED CI on `main`, fixed by a follow-up renumber (#5952 → ADR-082). That gap closed two days later (see Phase 7, "ADR-ordinal collision after a sync", for the SSOT and the current failure model) — this gate is the cheaper, earlier catch.
