# AC1–AC18 walk (task 8.3)

Evidence for each acceptance criterion. Four ACs were amended because
measurement refuted them — the amendment and its argument are in the plan's
§Implementation Reconciliation; the verdict column below says `AMENDED` and
states what was actually verified.

| AC | Verdict | Evidence |
|---|---|---|
| **AC1a** byte-exact emitted command | ✅ | `grep-rewrite.test.sh` asserts the 487-byte prefix as a full literal (the one place a literal belongs — it is the drift guard) and asserts prefix+original with a byte-identical remainder, including a fixture carrying quotes, a pipe, `$X` and a trailing comment. |
| **AC1b** that string is cheap; shim not reached | ✅ | The #7163 reproducer class (two bounded repeats over a wide atom, literal present in subject) run under `ulimit -v 2000000` + `timeout 20`: completed in **119 ms**, peak RSS **7,416 KB** (< 100 MB gate). A shim stand-in writes a marker file if reached — **not written**. |
| **AC2** sibling `deny` beats `updatedInput` | ✅ *(precondition)* | Isolated `claude -p`, two-hook probe: PostToolUse never fired → nothing executed → **deny wins**. Tests Claude Code, not this diff. |
| **AC3** no `permissionDecision` at any depth | ✅ | Asserted on the non-empty and empty cases **separately** (`jq -e` exits 4 on empty stdin, so a combined assertion is vacuous for the empty case). Also: no top-level `decision`/`continue`, and `hookEventName` rides in the same object as `updatedInput`. |
| **AC4** sibling `tool_input` keys survive | ✅ | `description`, `timeout`, `run_in_background` and `sandbox: false` all survive; key set asserted exactly, so nothing is invented or lost. `sandbox: false` is deliberate — a falsy-default bug would drop it. |
| **AC5** corpus replay | ⚠️ **AMENDED** | **12,057** unique real commands (plan estimated ~6,100). **0 corrupted.** 4 declined (0.03%) — each carries a literal RS byte (0x1E), the separator `lib/hook-input.sh` uses; the shared parser reports a boundary forge and the hook fails open, leaving the command untouched. All four are fixtures from the PR that authored that parser. |
| **AC6** seven bypass/resolution forms | ✅ | direct, pipeline, `$( )`, backticks, subshell, `G=grep; $G`, `eval "grep …"` — all rewrite and reach the real binary; shim reached by **none**. The last two are the forms v1 declared unfixable. |
| **AC7** 12 bypass arms get no injected flags | ✅ | One representative flag per arm, argv asserted exactly via a fake `grep` binary. Plus a **positive control** — a non-bypass call must receive the injected set, or an always-bypass regression would leave all 12 green. |
| **AC8** differential results | ⚠️ **AMENDED** | "Identical stdout" is **false**. Measured against **real ugrep** (capped) on a synthesized tree with `.git`, a binary file, a gitignored dir and hidden files. Four divergence classes enumerated and accepted in ADR-160 §Accepted divergences. |
| **AC9** hook tracked at index mode 100755 | ✅ | Asserted from the **git index** (`git ls-files -s`), not `test -x` — a local chmod does not travel. Generalized to **all 34** registered hooks. Mutation-proved: `update-index --chmod=-x` → RED. |
| **AC10** fail-open triad | ⚠️ **AMENDED** | exit 0 + empty stdout fixtured for **9** malformed shapes (empty stdin, non-JSON, no `.tool_input`, 1 MB binary, array command, non-object `tool_input`, non-object root, jq exits 1, jq emits garbage at rc 0). Disarm telemetry re-pointed to `lib/hook-input.sh`; "no `.tool_input`" correctly emits **no** incident; "perl absent" asserted as a mechanism ban. |
| **AC11** idempotency / fixed point | ✅ | Feeding the hook its own output emits nothing; exactly one prefix in the once-rewritten command. Mutation-proved: removing the sentinel check → RED. |
| **AC12** kill switch | ✅ | `SOLEUR_DISABLE_GREP_REWRITE=1` → exit 0, empty stdout. **Ordering** asserted via a lib-less copy on **empty stderr** (rc alone cannot distinguish the two paths, since both exit 0), with a switch-off control that must complain. |
| **AC13** single-rewriter invariant | ✅ | Exactly one hook source may emit `updatedInput`; one-entry allowlist. Mutation-proved across **three** emission spellings (printf-escaped, jq unquoted, plain-quoted). The printf spelling initially **survived** — the fix was found by mutation, not review. |
| **AC14** registration membership | ✅ | Derived from `.claude/settings.json`; `grep-rewrite.sh` present in the `PreToolUse`/`Bash` list. A **non-vacuity check runs first** (all=34, Bash=19) so a broken derivation cannot make membership pass by iterating nothing. Mutation-proved: registration removed → RED. |
| **AC15** aggregator tolerates `grep-rewrite-*` | ✅ | Verified **RED first** (rc=5, "orphan rule_id(s) … : grep-rewrite-would-rewrite"). T20 asserts the exemption; **T21** is its non-vacuity partner — a real orphan alongside a `grep-rewrite-*` row must still exit 5. Suite: 63/63. |
| **AC16** `test-all.sh` scripts shard | ⚠️ see PR | `.claude/hooks/*.test.sh` **is** auto-globbed at `test-all.sh:577` (inside `if want_scripts`), so the new suite is discovered — checked explicitly rather than assumed. Full-shard result reported in the PR; the five suites this diff touches are green individually. |
| **AC17** hot-path latency | ⚠️ **AMENDED** | Absolute 50 ms is unreachable by construction (14 ms process floor, 20 ms/jq fork, 103–124 ms for every sibling). Replaced with a **relative, machine-independent** gate: grep-rewrite **89 ms** ≤ `no-memory-write` **116 ms**. |
| **AC18** C4 regenerated | ✅ | `model.c4` container technology + description and the `hooks -> claude` relationship relabelled; `model.likec4.json` regenerated (65 elements, 125 relations, 67 views). `c4-model-freshness.test.sh` 3/3 green. |

## Staged rollout (`wg-dark-launch-deploy-gates`)

Not a mode flag pretending to be a rollout — the hook was genuinely dark until a
gate passed:

1. Hook committed **unregistered**. It could not run: nothing referenced it.
2. Corpus replay over 12,057 real commands through the hook's real code path —
   the soak.
3. Only then registered in `.claude/settings.json`.

`SOLEUR_GREP_REWRITE_OBSERVE=1` is retained as a diagnostic (emits
`grep-rewrite-would-rewrite`, returns no envelope), and
`SOLEUR_DISABLE_GREP_REWRITE=1` is the rollback lever.

## Mutation proof

A green suite that cannot fail certifies nothing, so both suites were mutated.

**grep-rewrite.test.sh — 10/10 real mutations RED:** dropped `--exclude-dir`,
dropped a bypass arm, emitted only `.command` (the v1 P0-5 bug), added
`permissionDecision: allow`, removed the idempotency check, removed the kill
switch, dropped `hookEventName`, gate always fires, parse failure exits 2,
bypass arms fall through to injected flags. An 11th (`exit 0` → `:` on the
parse-failure path) survived and was confirmed an **equivalent mutant** — a
later `[[ -z "$CMD" ]] && exit 0` still catches it, so behavior is byte-identical
(rc=0, empty stdout), not suite blindness.

**hookeventname-coverage.test.sh — 4/4 RED** (index mode, registration, second
rewriter, empty derivation), with a control confirming a *comment* mentioning
`updatedInput` correctly does **not** trip the single-rewriter gate.
