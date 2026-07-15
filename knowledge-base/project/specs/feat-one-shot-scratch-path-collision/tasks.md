# Tasks — Collision-free scratch paths in agent-facing guidance

Plan: `knowledge-base/project/plans/2026-07-15-fix-scratch-path-collision-in-agent-guidance-plan.md`
Branch: `feat-one-shot-scratch-path-collision`
Lane: `cross-domain` (no spec.md `lane:` present — defaulted fail-closed)

**Scratch mechanism (decided):** `mktemp`, path captured in a var and **echoed**.
**Guard home (decided):** `plugins/soleur/test/scratch-path-collision.test.ts` — auto-discovered
by `scripts/test-all.sh:223` (`bun test plugins/soleur/`). **Do NOT edit `scripts/test-all.sh`.**

Phase order is load-bearing: fixes land before the guard's allowlist/floor are finalized.

---

## Phase 0 — Preconditions (re-verify; do not trust the plan)

- [ ] 0.1 Confirm CWD is the worktree root and branch is `feat-one-shot-scratch-path-collision`.
- [ ] 0.2 Re-run the authoritative enumeration; expect **18 occurrences / 8 files**:
      `grep -rnoE '(>>?|&>)[[:space:]]*/tmp/[A-Za-z0-9_.<>$*{}-]+' plugins/soleur/skills/*/SKILL.md`
      *(The `<>` in the class is load-bearing — without it `work:607` is invisible.)*
- [ ] 0.3 Confirm `scripts/test-all.sh` is clean: `grep -nE '/tmp/|mktemp|TMPDIR' scripts/test-all.sh` → exit 1.
- [ ] 0.4 Confirm `test-all.sh:223` still reads `run_suite "plugins/soleur" bun test plugins/soleur/`
      (the auto-discovery claim the guard-home decision rests on).
- [ ] 0.5 Read the guard precedent before writing any test:
      `plugins/soleur/test/stock-preflight-coverage.test.ts` (allowlist + floor + non-vacuity)
      and `plugins/soleur/test/helpers.ts` (`discoverSkills()`).

## Phase 1 — Fix the cause (`work/SKILL.md`)

- [ ] 1.1 `work/SKILL.md:607` — replace `/tmp/<script>.log` with the mktemp form:
      `log=$(mktemp -t <name>.XXXXXXXX.log); bash <script> > "$log" 2>&1; rc=$?; echo "EXIT=$rc LOG=$log"`
- [ ] 1.2 **Preserve verbatim** in that bullet: the `pipefail` explanation, explicit `rc=$?`,
      the never-`| tail`-a-load-bearing-exit-code guard, and the `#4011` **Why** citation. *(AC2)*
- [ ] 1.3 `work/SKILL.md:210` — `git diff > /tmp/<task>.diff` →
      `d=$(mktemp -t task.XXXXXXXX.diff); git diff > "$d"; echo "DIFF=$d"`. Keep the
      output-discipline intent (cite the path; never paste a large diff inline).
- [ ] 1.4 **Do NOT touch** `work/SKILL.md:611` and `:982` — Class C (prose *about* the hazard).

## Phase 2 — Highest-severity site (`review/SKILL.md:982`)

- [ ] 2.1 `cp <file> /tmp/<file>.bak` → `bak=$(mktemp -t review-bak.XXXXXXXX); cp <file> "$bak"`;
      restore from `"$bak"`.
- [ ] 2.2 State in the prose **why** it must be session-unique: it is a **restore source**, so a
      collision silently restores another session's file content (not merely a confusing log).

## Phase 3 — Sweep remaining Class B sites

- [ ] 3.1 `qa/SKILL.md:46` — log path only. **Port-3000 race is scoped OUT** (tracking issue at ship).
- [ ] 3.2 `qa/SKILL.md:82` — `/tmp/qa-pw-install.log`.
- [ ] 3.3 `ship/SKILL.md:1188` — path swap only; the `rc=$?; echo "EXIT=$rc"` idiom is already correct.
- [ ] 3.4 `ship/SKILL.md:1855` — `/tmp/follow-through-body.md`.
- [ ] 3.5 `plan/SKILL.md:229` — `/tmp/open-review-issues.json`.
- [ ] 3.6 `preflight/SKILL.md:373` and `:688` — align with the skill's existing `PREFLIGHT_TMP`
      pattern (`preflight:34`) or `mktemp`, whichever reads more naturally at each site.
- [ ] 3.7 `merge-pr/SKILL.md:154,155` — changelog ours/theirs.
- [ ] 3.8 `schedule/SKILL.md:472` — `2>/tmp/merge.err`.
- [ ] 3.9 **Do NOT touch** `preflight/SKILL.md:114` — Class C (same-invocation write-then-read).
- [ ] 3.10 Where a site is a short-lived fixture, match the local
      `trap 'rm -f "$f"' EXIT INT TERM` convention (`ship:564`). Long-lived logs are kept deliberately.

## Phase 4 — Author the guard (RED first)

- [ ] 4.1 Create `plugins/soleur/test/scratch-path-collision.test.ts` (bun:test), rooted
      `resolve(import.meta.dir, "../../..")`, enumerating via `discoverSkills()` from `./helpers`.
- [ ] 4.2 Anchor on the **syntactic write construct** `(>>?|&>)\s*/tmp/<path>` — never a bare
      `/tmp` token (it false-matches prose and the guard's own docs).
- [ ] 4.3 Path char class **MUST** include placeholder metacharacters `<>$*{}` — otherwise the
      guard cannot go red on `work:607`, its own root cause.
- [ ] 4.4 `ALLOWLIST: Map<string,string>` with **mandatory reason strings**, seeded with the 3
      Class C anchors (`work:611`, `work:982`, `preflight:114`).
- [ ] 4.5 Non-vacuity: assert `discoverSkills().length > 0` **and**
      `candidates.length >= MIN_SCANNED_SITES` (`>=`, not `==`). Name the test `(non-vacuity)`.
- [ ] 4.6 Anti-rot: assert every allowlist entry still resolves to a real matching line.
- [ ] 4.7 Report via `offenders[]` → one `throw new Error` naming file:line, the text, and the
      allowlist constant to extend.
- [ ] 4.8 Header comment: what it prevents, why (issue/PR refs), documented limitations, and
      `// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).`
- [ ] 4.9 Confirm **RED against pre-fix state**, then **GREEN** after Phases 1-3.

## Phase 5 — Mutation-test the guard (mandatory)

Inject → confirm **RED with a clear message** → restore. All four:

- [ ] 5.1 **M1** literal: append `bash x > /tmp/mutant.log 2>&1` to a skill → RED.
- [ ] 5.2 **M2** placeholder: append `bash x > /tmp/<mutant>.log 2>&1` → RED.
      *(Non-negotiable — this is the class the brief's regex misses.)*
- [ ] 5.3 **M3** allowlist: delete an entry whose Class C line still exists → RED.
- [ ] 5.4 **M4** vacuity: point the glob at an empty dir → the **floor** fires → RED.
- [ ] 5.5 Restore the tree after each; confirm final state GREEN. Capture evidence for the PR body. *(AC7)*

## Phase 6 — Verification & exit gate

- [ ] 6.1 **AC5:** re-run the enumeration; expect exactly **4** remaining occurrences
      (`work:611` ×1, `work:982` ×1, `preflight:114` ×2). *(18 total − 14 fixed = 4)*
- [ ] 6.2 **AC1:** `grep -c '/tmp/<script>.log' plugins/soleur/skills/work/SKILL.md` → `0`.
- [ ] 6.3 **AC6:** revert `work:607` to pre-fix text → guard FAILS naming `work/SKILL.md:607`; restore.
- [ ] 6.4 **AC10:** `bun test plugins/soleur/` includes `scratch-path-collision`, with **no**
      edit to `scripts/test-all.sh`.
- [ ] 6.5 **AC12:** `git diff --name-only origin/main...HEAD` → only the 8 SKILL.md files, the new
      test, and `knowledge-base/project/{plans,specs}/`. No product code. No `scripts/test-all.sh`.
- [ ] 6.6 **AC11:** full suite green — dogfood the new guidance:
      `log=$(mktemp -t test-all.XXXXXXXX.log); bash scripts/test-all.sh > "$log" 2>&1; rc=$?; echo "EXIT=$rc LOG=$log"`
      Inspect `rc` **first**; only then grep `"$log"`.

## Phase 7 — Ship

- [ ] 7.1 File the deferred **qa port-3000 race** tracking issue
      (`wg-when-deferring-a-capability-create-a`): what/why/re-evaluation criteria + milestone.
- [ ] 7.2 `/soleur:ship` — PR body carries the M1-M4 mutation evidence and the AC5 count.
- [ ] 7.3 Capture the session learning (the placeholder-regex blind spot + the
      `iac-plan-write-guard` self-negation episode are both compound-worthy).

---

## Traps (read before starting)

- **The obvious regex is wrong.** `[A-Za-z0-9_.-]` excludes `<` → `work:607` looks already-fixed.
  Always use the placeholder-aware class.
- **`review:982` is a restore source**, not a log. Highest severity; do not downgrade it.
- **`preflight:114` is a decoy** — same-invocation write-then-read. Allowlist, don't rewrite.
- **Never serialize sessions** as a "fix". Parallel worktrees are the intended workflow (16 live).
- **Do not edit `scripts/test-all.sh`** — no registration is needed, and SCOPE forbids it.
- **Writing a "no infrastructure" section can trip `.claude/hooks/iac-plan-write-guard.sh`** if you
  name its trigger tokens to negate them. Describe the classes abstractly; do **not** use the
  `iac-routing-ack` opt-out (it records a false `bypass` incident).
