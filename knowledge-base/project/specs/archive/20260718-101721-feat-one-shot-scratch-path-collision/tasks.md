# Tasks — Collision-free scratch paths in agent-facing guidance

Plan: `knowledge-base/project/plans/2026-07-15-fix-scratch-path-collision-in-agent-guidance-plan.md`
Branch: `feat-one-shot-scratch-path-collision`
Lane: `cross-domain` (no spec.md `lane:` — defaulted fail-closed)

**Mechanism:** `mktemp` by default; **git-dir/workspace-scoped** when a *later, separate* Bash
call must find the artifact **by name**. Always echo the path.
**Guard home:** `plugins/soleur/test/scratch-path-collision.test.ts` — auto-discovered by
`scripts/test-all.sh:223`. **Do NOT edit `scripts/test-all.sh`.**

> **v2 (post-deepen-plan).** v1 anchored on redirect syntax and was blind to `-o`/`cp` writes;
> it caught `review:982` only by accident and would have shipped a **net regression** at
> `preflight:373`. v2 anchors on the **hazard**. Work-list is 9 files, not 8.

---

## Phase 0 — Preconditions (re-verify; trust nothing)

- [ ] 0.1 CWD = worktree root; branch = `feat-one-shot-scratch-path-collision`.
- [ ] 0.2 Re-run the **hazard-anchored** enumeration (write-verb alternations; `/tmp/` at a path
      boundary). Expect: **18 occurrences / 16 lines / 9 files to FIX**, 5 to WAIVE,
      `ux-audit` **compliant**.
      *(The naive `> /tmp/…` regex is WRONG — it misses `-o`, `cp`, and `work:607` itself.)*
- [ ] 0.3 `grep -nE '/tmp/|mktemp|TMPDIR' scripts/test-all.sh` → exit 1 (clean).
- [ ] 0.4 `test-all.sh:223` still reads `run_suite "plugins/soleur" bun test plugins/soleur/`.
- [ ] 0.5 Read `plugins/soleur/test/stock-preflight-coverage.test.ts` (allowlist + non-vacuity
      precedent) and `plugins/soleur/test/helpers.ts` (`discoverSkills()`, `PLUGIN_ROOT`).

## Phase 1 — Fix the cause (`work/SKILL.md`)

- [ ] 1.1 `:607` → `log=$(mktemp -t <name>.XXXXXXXX.log); bash <script> > "$log" 2>&1; rc=$?; echo "EXIT=$rc LOG=$log"`
- [ ] 1.2 **Preserve verbatim**: the `pipefail` explanation, explicit `rc=$?`, the
      never-`| tail`-a-load-bearing-exit guard, and the `#4011` **Why**. *(AC1)*
- [ ] 1.3 `:210` → `d=$(mktemp -t task.XXXXXXXX.diff); git diff > "$d"; echo "DIFF=$d"`. Keep the
      output-discipline intent (cite the path; never paste a large diff).
- [ ] 1.4 **Do NOT touch** `:611`, `:982` (Class C waivers).

## Phase 2 — Highest severity (`review/SKILL.md:982`)

- [ ] 2.1 `cp <file> /tmp/<file>.bak` → `bak=$(mktemp -t review-bak.XXXXXXXX); cp <file> "$bak"`;
      restore from `"$bak"`.
- [ ] 2.2 State **why** session-unique: it is a **restore source**, and parallel review agents
      share **one worktree** (`review:981`) — so git-dir scoping would NOT help here; only
      `mktemp` isolates. A collision silently restores another session's content.

## Phase 3 — Sweep the rest (apply the criterion)

- [ ] 3.1 **`preflight:369` + `:373` TOGETHER, one commit.** `:369` (`curl -o
      /tmp/preflight-login.html`) writes what `:373` reads. **Fixing `:373` alone is a NET
      REGRESSION.** Both → `PREFLIGHT_TMP` (later calls read them by name). *(AC6)*
- [ ] 3.2 `preflight:395` (`-o "/tmp/preflight-chunks/${base}"`) → `PREFLIGHT_TMP`.
- [ ] 3.3 `preflight:688` → `PREFLIGHT_TMP`.
- [ ] 3.4 `qa:46` — **TWO occurrences on one line** (Doppler + no-Doppler branches). Fix **both**.
      Log path only; port-3000 race scoped out.
- [ ] 3.5 `qa:82` → `mktemp`.
- [ ] 3.6 `ship:1188` → `mktemp` (path swap only; `rc=$?` idiom already correct).
- [ ] 3.7 `ship:1855` → `mktemp`.
- [ ] 3.8 `plan:229` → `mktemp`.
- [ ] 3.9 `merge-pr:154`, `:155` → `mktemp`.
- [ ] 3.10 `schedule:472` → `mktemp`.
- [ ] 3.11 **`rclone:29`** (9th file) — `-o /tmp/rclone.zip` + `unzip -d /tmp` + `cp
      /tmp/rclone-*/rclone` → `mktemp -d`.
- [ ] 3.12 Classify `frontend-anti-slop:76` (`"screenshot_ref": "/tmp/anti-slop/…"` — a JSON
      example value): waive-with-reason, or fix if prescriptive.
- [ ] 3.13 **Do NOT touch** `preflight:114` (Class C) or `ux-audit` (already
      `${GITHUB_WORKSPACE}`-scoped = compliant).
- [ ] 3.14 Match the local `trap 'rm -f "$f"' EXIT INT TERM` convention (`ship:564`) for
      transient artifacts.

> **PROSE CONSTRAINT (Phases 1-3, load-bearing).** Explanatory prose added by a fix **must not
> quote the broken form** — quoting `cp <file> /tmp/<file>.bak` to say "this was wrong" mints a
> NEW hazard match and reddens the guard. Describe the defect; do not reproduce it.

## Phase 4 — Author the guard (fixtures FIRST)

- [ ] 4.1 Create `plugins/soleur/test/scratch-path-collision.test.ts` (bun:test).
      **Root at `PLUGIN_ROOT`** (`resolve(import.meta.dir, "..")`) — `discoverSkills()` returns
      paths relative to `plugins/soleur`. **`REPO_ROOT` → ENOENT.**
- [ ] 4.2 Export `findHazards(text): string[]` as a **pure function** (the whole guard hinges on
      this being unit-testable).
- [ ] 4.3 Anchor on the **hazard** via **separate write-verb alternations** — never let `>` do
      double duty (it is both a redirect and `<placeholder>`'s bracket):
      redirect `(>>?|&>|2>)`; flag `(-o|--output)`; verb `\b(cp|mv|tee|install)\b`, `unzip … -d`.
- [ ] 4.4 `<path>` = `/tmp/` at a **path boundary** `(^|[\s"'=])` + class
      `[A-Za-z0-9_.<>${}*/-]`. **Boundary** or `${GITHUB_WORKSPACE}/tmp/…` false-matches;
      **`<>`** or `work:607` is invisible. Subtract variable-rooted paths.
- [ ] 4.5 **Committed fixture suite (AC3)** — synthesized strings only
      (`cq-test-fixtures-synthesized-only`):
      RED: `> /tmp/<mutant>.log` (placeholder), `> /tmp/mutant.log` (literal),
      `cp somefile /tmp/fixed.bak` (**no redirect**), `curl -o /tmp/fixed.html` (**flag**).
      GREEN: `> "$log"`, `"$PREFLIGHT_TMP/x.txt"`, `${GITHUB_WORKSPACE}/tmp/ux-audit/a.png`,
      bare prose mentioning `/tmp/foo.log`.
      *Without this, `<>` and the verb alternations are load-bearing for ZERO committed
      assertions after the fix — someone narrows the regex and the suite stays GREEN.*
- [ ] 4.6 **Allowlist: content-addressed** — key `(file, exact offending text)` + **mandatory
      reason**. **NOT line numbers** (Phases 1-2 shift lines 611/982; and a position-keyed waiver
      silently absolves a future offender landing there).
- [ ] 4.7 Seed waivers: `work:611`, `work:982`, `preflight:114` (×2, reason = *"narrow race
      window, self-limiting, accepted"* — **not** "not a defect"), `frontend-anti-slop:76` if
      waived.
- [ ] 4.8 Non-vacuity: `discoverSkills().length > 0` + anti-rot (every waiver resolves).
      **Do NOT add `MIN_SCANNED_SITES`** — anti-rot strictly implies it.
- [ ] 4.9 Report: `offenders[]` → one `throw` naming file:line, text, and the constant to extend.
- [ ] 4.10 Header comment with **DOCUMENTED LIMITATIONS**: the `skills/*/SKILL.md` glob (misses
      `incident/scripts/dry-run.sh:9`); the runtime-improvised population (needs a hook);
      no fence-awareness (explicit waiver > silent skip).
- [ ] 4.11 Confirm RED against pre-fix text via **`git show <commit>:<path>`** —
      **NEVER `git stash`** (`hr-never-git-stash-in-worktrees`, **hook-enforced**). GREEN after
      Phases 1-3. *(AC2)*

## Phase 5 — Harness mutations (scratch copy only)

- [ ] 5.1 **M3**: delete an allowlist entry whose Class C text still exists → RED. *(AC5)*
- [ ] 5.2 **M4**: point the glob at an empty dir → RED (vacuity caught). *(AC4)*
- [ ] 5.3 Run against a **scratch copy**. Never mutate the working tree — it carries this plan's
      own uncommitted edits (the `review:982` clobber class).

## Phase 6 — ADR-009 amendment (in scope, not a follow-up)

- [ ] 6.1 Amend `ADR-009-git-worktree-isolation.md` Consequences: `:20` claims *"full
      isolation"*; bound it — worktrees isolate the **working tree**, not process-level scratch;
      `/tmp` is a namespace shared across all worktrees.
- [ ] 6.2 Record the mechanism criterion (mktemp vs git-dir/workspace by concurrency domain).
- [ ] 6.3 No new ADR (this corrects an existing decision). No `.c4` change expected; if any,
      run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 7 — Verification & exit gate

- [ ] 7.1 **AC1**: rewritten `work:607` bullet still matches `pipefail` AND `rc=$?` AND `4011`.
- [ ] 7.2 **AC2**: pre-fix `work:607` → guard FAILS naming it.
- [ ] 7.3 **AC3**: fixture suite green; narrowing the class or dropping a verb alternation → RED.
- [ ] 7.4 **AC6**: `preflight:369` + `:373` in the **same commit** — verify by walking the
      commit's diff for both regions. **NOT `git log -- A B`** (a **union** filter — it passes on
      an asymmetric fix).
- [ ] 7.5 **AC7**: full suite green, dogfooding the new guidance:
      `log=$(mktemp -t test-all.XXXXXXXX.log); bash scripts/test-all.sh > "$log" 2>&1; rc=$?; echo "EXIT=$rc LOG=$log"`
      Inspect `rc` **first**; then grep `"$log"`. Output names `scratch-path-collision`; no
      `test-all.sh` edit.
- [ ] 7.6 Coupling check: all 9 edited SKILL.md files are read by existing tests. Expect green —
      no `description:` frontmatter touched (all line 3; edits ≥46); `plan:229` is far from the
      Observability schema block at `plan:487`.

## Phase 8 — Ship

- [ ] 8.1 File: **qa port-3000 race** (P3; `deferred-scope-out`, `domain/engineering`,
      `priority/p3-low` — all verified to exist).
- [ ] 8.2 File: **PreToolUse Bash hook** for the runtime-improvised `/tmp` population (the
      ~30 ad-hoc paths no SKILL.md scan can reach). Precedent:
      `.claude/hooks/background-poll-prefer-monitor.sh:8-12`.
- [ ] 8.3 File: **`TMPDIR` via `.claude/settings.json` `env`** — would make the scratchpad
      synthesis real; needs verification the harness applies it to Bash calls.
- [ ] 8.4 File: **`incident/scripts/dry-run.sh:9`** (same class, outside the guard's glob).
- [ ] 8.5 `/soleur:ship`. PR body carries the AC3 fixture list + the AC6 same-commit evidence.
- [ ] 8.6 `/compound` the session learning (the anchor-on-hazard-not-syntax lesson is the durable
      one). **Note:** ACs permit `knowledge-base/project/{plans,specs,learnings}/` — do not fence
      `/compound` out.

---

## Traps (read first)

1. **The obvious anchor is wrong twice.** `[A-Za-z0-9_.-]` misses `work:607`. A **redirect**
   anchor misses `-o`/`cp`/`tee` and catches `review:982` only because `<file>`'s `>` fakes a
   redirect. Anchor on the **hazard**, `/tmp/` at a **path boundary**.
2. **`preflight:369` + `:373` are ONE unit.** Reader-only fix = **net regression**.
3. **`qa:46` has TWO occurrences on one line.**
4. **`review:982` is a restore source**, not a log. Same-worktree agents → `mktemp` only.
5. **`ux-audit` is already compliant** (`${GITHUB_WORKSPACE}/tmp/…`). Do not "fix" it; the guard
   must stay GREEN on it.
6. **Fix prose must not quote the broken form.**
7. **Never `git stash`** (hook-enforced). Use `git show <commit>:<path>`.
8. **Never mutate real skill files to test the guard** — fixtures only.
9. **Do not edit `scripts/test-all.sh`** — no registration needed.
10. **Do not use `iac-routing-ack`** to write a "no infrastructure" section — it records a false
    `bypass`. Describe the token classes abstractly instead.
