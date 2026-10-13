---
title: "Tasks — fix scan-workflow.test.sh pipefail + grep -q SIGPIPE"
issue: 6572
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-16-fix-scan-workflow-pipefail-sigpipe-plan.md
---

# Tasks — #6572

Derived from the **v2** (post-plan-review) plan. Single file:
`apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh`.

> **Read `## Root Cause` in the plan before editing.** Two facts decide every choice here:
> (1) SIGPIPE needs the producer to issue a **second `write()`** — under 4096 B it is
> unreachable, so 4 of the 7 sites are safe *today*; (2) the unfixed guard passes **0/400**
> locally, so **no local run of the guard proves the fix** — only the size-amplified
> differential (task 4.2) discriminates.

## Phase 0 — Preconditions

- [ ] 0.1 Confirm `set -uo pipefail` at `:25` and the `script_code | grep -qE` shape at `:284`.
- [ ] 0.2 Confirm the here-string is in-repo precedent, not invented:
      `git grep -n '<<<' -- 'apps/web-platform/infra/*.test.sh'`
      → expect `deploy-status-fanout-verify.test.sh:244` (`grep -q 'v1.2.3' <<<"$POSTBODIES"`).
- [ ] 0.3 Record baselines on `origin/main` (asserted later by AC1 / AC4):
      - residual shape count = **7**
      - flag counts = **16** `grep -qF`, **12** `grep -qE`
      ```bash
      RE='[|][[:space:]]*grep([[:space:]]+-[a-zA-Z0-9]+)*[[:space:]]+(-[a-zA-Z]*q[a-zA-Z]*|--quiet)([[:space:]]|$)'
      git show origin/main:apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh \
        | grep -vE '^[[:space:]]*#' | grep -cE "$RE"          # 7
      git show origin/main:apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh \
        | grep -oE 'grep -q[FE]?' | sort | uniq -c            # 12 -qE, 16 -qF
      ```

## Phase 1 — Mutation seam (MUST land before any mutation task)

- [ ] 1.1 Replace the hardcoded assignment at `:29` with an override-able default:
      ```bash
      SCRIPT="${SCRIPT_OVERRIDE:-$REPO_ROOT/scripts/supabase-advisor-scan.sh}"
      ```
      **Why first:** `SCRIPT` is currently hardcoded from `BASH_SOURCE`-derived `REPO_ROOT`,
      so "point the guard at a scratch copy" is impossible and every mutation test must edit
      **tracked source**. An interrupted run then leaves the tree dirty — this happened during
      planning and needed `git checkout --` to recover. Tasks 4.3/4.4 depend on this seam.
- [ ] 1.2 Verify the default is unchanged when `SCRIPT_OVERRIDE` is unset (guard still passes).

## Phase 2 — Capture once + convert the 7 sites

- [ ] 2.1 Replace the `script_code()` function (`:199`) with a single **lowercase** capture plus
      a non-empty guard:
      ```bash
      script_code="$(grep -vE '^\s*#' "$SCRIPT")"
      [[ -n "$script_code" ]] || { printf 'FATAL: script_code empty (grep -v failed?)\n' >&2; exit 1; }
      ```
      - **lowercase** to match its peers `advisor_block` / `rung3_gate`; uppercase would read
        as a path constant like `SCRIPT` / `WORKFLOW`.
      - The non-empty guard is **load-bearing**: capture-once consolidates 7 independent
        failure points into one variable, and an empty `script_code` makes `:200` take its
        `pass` branch — a *new* fail-open. `set -uo pipefail` has no `-e`, so the assignment
        would fail silently. Mirrors the file's `FATAL` precedent at `:45-46`.
- [ ] 2.2 Convert the 7 sites, **preserving polarity and flags exactly**:
      | Site | New form |
      |---|---|
      | `:157` | `grep -qE '\$\{\|\$\(\|\$[A-Za-z_]' <<<"$(grep -E '^\s*API=' "$SCRIPT")"` |
      | `:200` | `grep -qF '.lints[]?' <<<"$script_code"` |
      | `:207` | `grep -qF '.lints[]' <<<"$script_code"` |
      | `:225` | `grep -qE 'code" != "200"' <<<"$advisor_block"` |
      | `:231` | `grep -qF 'has("lints")' <<<"$advisor_block"` |
      | `:268` | `grep -qE '(^\|[^_])\bok\b\|advisor' <<<"$rung3_gate"` |
      | `:284` | `grep -qE '^[[:space:]]*\.[[:space:]].*lib/'"$lib"'\.sh' <<<"$script_code"` |
- [ ] 2.3 Update the mechanism prose in the comment blocks at `:192-198` and `:275-282`.
      **Keep both anchoring rationales verbatim** — `-F` is deliberate; anchor on the `.`
      sourcing syntax, not the bare path.

> **Do NOT** convert the ERE sites to bash `[[ =~ ]]`: `=~` anchors `^` at **string** start,
> not line start, so `:284`'s per-line anchor breaks silently while looking simpler.
> **Do NOT** "improve" `-F` to `-E`: `[]?` makes the `]` optional, which would match the
> *correct* `.lints[]` and false-FAIL permanently.

## Phase 3 — Residual-shape self-check

- [ ] 3.1 Add the guard (inline pattern — **no fragment-building**; verified it cannot match
      its own source line, self-match count 0):
      ```bash
      # Forbids <producer> | grep -q… (incl. -qF/-qE/--quiet/-m1 -q): grep -q exits on first
      # match, SIGPIPEs the producer, and pipefail promotes 141 to the pipeline status (#6572).
      # Match against a here-string instead. Safe forms (grep -c, >/dev/null) are not matched.
      pipe_grep_q='[|][[:space:]]*grep([[:space:]]+-[a-zA-Z0-9]+)*[[:space:]]+(-[a-zA-Z]*q[a-zA-Z]*|--quiet)([[:space:]]|$)'
      residual="$(grep -vE '^[[:space:]]*#' "${BASH_SOURCE[0]}" | grep -cE "$pipe_grep_q")"
      ```
      then `pass` on `residual == 0`, else `fail` naming the count.
- [ ] 3.2 Confirm the pattern catches all 5 unsafe forms (`-q`, `-qF`, `-qE`, `--quiet`,
      `-m1 -q`) and none of the 4 safe forms (`grep -c`, `grep -E … >/dev/null`, here-string,
      the guard's own `grep -cE` line).

## Phase 4 — Verify

- [ ] 4.1 `bash apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh` → `all checks passed`, rc=0. **(AC2)**
- [ ] 4.2 **Size-amplified differential — the ONLY discriminating test. (AC3)**
      Build a scratch scan-script keeping the `strip-log-injection` source at **code line 5**
      and appending **≥1 MB of non-comment padding** (`script_code` strips `^\s*#`, so comment
      padding is a no-op). Assert:
      - unfixed shape (`producer | grep -q`) → false-FAILs **100/100**
      - fixed shape (`grep -q <<<"$var"`) → passes **100/100**
- [ ] 4.3 **Fail-closed mutation (AC5):** remove the `strip-log-injection` source line from a
      scratch copy → `SCRIPT_OVERRIDE=<scratch> bash <guard>` prints
      `FAIL sources lib/strip-log-injection.sh`, rc=1.
- [ ] 4.4 **Fail-open mutation (AC6):** inject `.lints[]?` at **code line 1** of a scratch copy
      → prints `FAIL script never uses the fail-open .lints[]? idiom`, rc=1.
      **Pin the injection position** — at end-of-file this mutation is 100% vacuous (the
      unfixed file also "passes"); even early it evades ~13% over 200 runs. Pair with 4.2's
      amplified tail to make it deterministic.
- [ ] 4.5 **Residual + flag drift (AC1, AC4):**
      ```bash
      grep -vE '^[[:space:]]*#' <file> | grep -cE "$RE"                       # 0  (main: 7)
      diff <(git show origin/main:<file> | grep -oE 'grep -q[FE]?' | sort | uniq -c) \
           <(grep -oE 'grep -q[FE]?' <file> | sort | uniq -c)                 # identical
      ```
- [ ] 4.6 **Clean tree (AC7):** `git status --short` clean — no mutation touched tracked source.

## Phase 5 — Ship artifacts

- [ ] 5.1 PR body: `Closes #6572`.
- [ ] 5.2 File the **narrow** tracking issue for the **31 sibling guards / 235 sites** under
      `apps/web-platform/infra/**` (`pipefail` + this shape), triaged by fail-open polarity.
      Milestone `Post-MVP / Later`; label `domain/engineering`. Cite this plan's evidence:
      the shape is *lucky*, not safe, and invisible to local runs (0/400).
      **Not** a repo-wide sweep (153 files / 591 sites) — that stays rejected.
- [ ] 5.3 `ship` renders `decision-challenges.md` (UC-1: cto's option-1 challenge) into the PR
      body and files the `action-required` issue.

## Out of scope (documented, not fixed)

- Six `| head -1` sites (`:262`, `:381`, `:383`, `:392`, `:393`, `:408`) — identical early-exit
  class, safe **by rc-discard** (each sits in an unchecked command substitution). The close
  condition covers `grep -q` only; do not let it imply coverage of the `head` class.
- Promoting `deploy-script-tests` to a **required** check — tracked in **#6480** (needs
  dropping `paths:`, adding `merge_group:`, registering in two places). Do not fold in.
</content>
