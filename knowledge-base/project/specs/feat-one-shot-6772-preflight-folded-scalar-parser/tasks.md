# Tasks — fix preflight Check 10 folded-scalar parser (#6772)

Derived from `knowledge-base/project/plans/2026-07-21-fix-preflight-check-10-folded-scalar-parser-plan.md`
(post-deepen, post-CPO-conditions).

Phase order is load-bearing: contract (awk) → mirror (TS) → guard (parity harness).

**Threshold is `single-user incident`.** CPO signed off with three conditions; C1 and C2
are prerequisites to starting work and are already reflected below.

## 1. Setup / preconditions

- [ ] 1.1 Re-derive the corpus census with regexes (do not trust the plan's approximate
      counts — three reviewers disagreed on the exact numbers): count non-archive plans
      matching `^[[:space:]]*command:[[:space:]]*>[-+]?[[:space:]]*(#.*)?$` and the `|` form.
- [ ] 1.2 Re-read `plugins/soleur/skills/preflight/SKILL.md` Check 10 Steps 10.3–10.5 and
      `plugins/soleur/test/lib/discoverability-test-parser.ts` before editing either.
- [ ] 1.3 Create `plugins/soleur/skills/preflight/scripts/` if absent. Confirm the
      `git rev-parse --show-toplevel` path pattern (NOT `CLAUDE_PLUGIN_ROOT`, which is unset
      in a plain session).
- [ ] 1.4 Capture the **pre-fix** reject-verdict baseline for the whole corpus — needed for
      AC11's delta and to prove R2 is red before the fix.

## 2. RED — fixtures before the fix

- [ ] 2.1 Permissive: table-driven F1–F3 over `[">", ">-", ">+"]` × `["", " # trailing
      comment"]` + 2 continuations; F4 (single continuation, no leading/trailing space);
      F5 (continuation ending in trailing `\`).
- [ ] 2.2 Restrictive: N1 (sibling key at same indent), N1b (parent key at **less** indent —
      pins the `<` half of `<=`), N5 (deeper-indented jq object filter), **S1
      (less-indented non-key line must NOT be consumed — the security differential)**,
      N3 (dedent to col 0 then **indented content resumes** — the draft's fixture was
      verified dead), N6 (blank line inside fold and block).
- [ ] 2.3 Non-shadowing: I1 (inline), B1 (block + sibling key), B2 (block joins with `\n`),
      B3 (`command: |-` **with continuation lines** — the draft's was vacuous), E1 (`>-`
      with no continuations returns empty, not `">-"`).
- [ ] 2.4 Reject fixtures: R1 (block scalar with a second command line → rejected via `\n`),
      **R2 (folded `doppler run … prd_terraform …` → rejected as credentialed CLI)**,
      R3 (`curl`/`bun test`/`bash <script>` NOT rejected).
- [ ] 2.5 Run the suite. Confirm F1–F5, N1, N1b, N5, S1, N6, B1, R1, R2 are RED for the
      right reason. **Capture the failure output verbatim** — primary AC9 evidence.

## 3. Fix the production awk

- [ ] 3.1 Create `plugins/soleur/skills/preflight/scripts/parse-form-a.awk` per plan §Phase 2:
      header comment (bash-wins contract, three scalar shapes, indent-semantics rationale,
      trailing-backslash caveat), `indent()` helper, fold header FIRST **with the `(#.*)?$`
      tail**, block header, inline rule, **blank-line skip above the terminator**,
      `indent($0) <= key` terminator (no key regex), `indent > key` continuations, END.
- [ ] 3.2 SKILL.md Step 10.4: `test -r` guard + `awk -f` via `git rev-parse --show-toplevel`
      + **hard-fail on rc≠0 (no fallthrough to Form B)**.
- [ ] 3.3 SKILL.md Step 10.4: add the **credentialed-CLI reject** (`doppler|gh|aws|supabase|
      stripe` with `(^|[[:space:]]|/)` … `([[:space:]]|$)` boundaries) immediately after the
      existing `ssh` reject. **CPO condition C1 — this is not optional and not deferrable.**
- [ ] 3.4 SKILL.md Step 10.5: add `$'\n'` to the reject set. Comment it as covering
      block-mode chaining ONLY (C2).
- [ ] 3.5 Update Step 10.4 Form A prose to name inline, block **and** folded shapes.
- [ ] 3.6 Do NOT strip block indentation as a parity concession — dedent falls out of the
      indent model; never bend the authoritative runtime to match the mirror.

## 4. Mirror in TypeScript

- [ ] 4.1 `parseCommand()`: fold branch ahead of inline; block header widened incl. `(#.*)?$`;
      indent model (`indent > key` continuation, `indent <= key` exit, blank-line skip);
      fold joins with `" "`, no trailing separator.
- [ ] 4.2 Align blank-line handling to the awk (awk drops; TS currently pushes `""`).
- [ ] 4.3 Add `\n` to `SUBST_REJECT_RE`; mirror the credentialed-CLI reject in `rejectReason()`.

## 5. Parity harness

- [ ] 5.1 For every Form-A fixture, run the `.awk` via `Bun.spawn`; compare **byte-exact** to
      `parseCommand(block)`. **No normalization** — the indent model makes both dedent
      identically, and normalizing would blind the harness to real drift.
- [ ] 5.2 State the **surface** each matrix row asserts against (awk / TS / both).
- [ ] 5.3 P3: assert every fixture has a `command:` key and no competing fenced block
      (`parseCommand` falls back to Form B; the awk does not).
- [ ] 5.4 P2: assert known divergences **as known** — inline quote stripping AND CRLF.
- [ ] 5.5 Assert the awk interpreter (mawk vs gawk) so a CI image swap surfaces named.

## 6. GREEN + verification

- [ ] 6.1 `bash scripts/test-all.sh` from the worktree root (AC10). Not a bare `bun test`.
- [ ] 6.2 Sandbox mutation protocol for the eight already-green pins (I1, N3, B2, B3, E1, F5,
      P2, P3), including **step 4 — prove the mutation is reachable** (output differs from
      baseline). Step 3 alone cannot catch a dead mutation; the draft had two.
- [ ] 6.3 AC11 corpus re-parse **with reject-verdict delta**: old vs new parse and old vs new
      Step 10.4/10.5 verdict for every plan matching `command:\s*[>|]`. Enumerate every
      REJECT→EXEC flip. Baseline 2026-07-21 = 4 flips, all `doppler run -c prd_terraform`.
      **After AC14's reject, the flip list must contain 0 credentialed commands.** Report the
      true unblock count (F7). Derive counts from regex, never hardcode.

## 7. Follow-through

- [ ] 7.1 File tracking issue: flow-mapping `discoverability_test: { command: … }` (AC12a).
- [ ] 7.2 File tracking issue: inline quote-stripping divergence (AC12b).
- [ ] 7.3 File **Phase 4 roadmap issue** (AC15 / CPO C3): Check 10 should not require ambient
      operator credentials to prove a liveness signal is real. Mark as a CTO architecture
      decision. Separate from 7.1/7.2 — this is roadmap scope, not parser scope.
- [ ] 7.4 PR body: `Closes #6772`, Phase 1 RED output, mutation table with reachability
      column, AC11 corpus report + flip enumeration + sign-off line.
- [ ] 7.5 Confirm `ship` renders `decision-challenges.md` into the PR body.
