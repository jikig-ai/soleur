# Fix-round review — git-history-analyzer + semgrep-sast — PR #12127

Seats: `soleur:engineering:research:git-history-analyzer`, `soleur:engineering:review:semgrep-sast`.
Scope: fix diff `git diff 79db88e18b..HEAD` only (HEAD `73f497e48a`), worktree
`/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-10861-pr5z-strict-zero` (toplevel confirmed).
Report-only: no live-tree edits; no test suite run; semgrep/shellcheck are read-only scans.

The diff touches 11 paths: the 4 contract/test files named in the task (`.github/workflows/ci.yml` comment,
`knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` §7, `scripts/ci-pr-affected-replay.py`,
`plugins/soleur/test/ci-pr-affected-replay.test.sh`) plus 7 archived round-1 review reports under
`knowledge-base/project/specs/feat-one-shot-10861-pr5z-strict-zero/review/` (new files, additions only).
Review-report hits on retired phrasing are verbatim quotations of the old contract recorded as findings —
excluded from residue counts below and noted only where they bear on a verdict.

## (a) Surviving pre-strict-zero contract text — grep sweep of all touched files

| Pattern | Contract files | Verdict |
|---|---|---|
| `green on a tree whose audit exits 1` | 0 hits | CLEAN — ci.yml:401 and replay.py:135-137 both rewritten |
| `must EQUAL a committed` | 0 hits | CLEAN — replay.py docstring + argparse `help=` both rewritten |
| `wc -l` on `scripts/ci-pr-affected-audit.baseline.tsv` | 0 hits | CLEAN — runbook §7 instruction removed; all remaining `wc -l` calls count unrelated artifacts |
| `shrink-only` | 1 hit | residue-of-record (see R1) |
| `live equals` / `equals the baseline` | runbook `pass` row fixed → "the live set is empty"; 6 hits in test.sh | mostly defensible (retained `--baseline` machinery); 1 stale (see R2, R3) |
| `adoption`/`adopt` | see below | carve-out names retained; 2 residue-of-record (see R4, R5) |

### Residue report (file:line)

- **R1 — `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md:260`** — heading "**Cumulative shrink-only check.**" survives in the PR3b entry-condition section (outside the §7 fix hunks). The check text itself already tolerates the end state ("The baseline absent at the tip is the end state and fine"), and `git diff … -- baseline.tsv` remains evaluable on a deleted file, so this is not broken — but `shrink-only` names a property of a file that no longer exists. Round-1 code-quality P3-5 flagged the sibling line (:264, the `git diff` entry condition) as "superseded in kind; worth a parenthetical". **P3**, borderline.
- **R2 — `plugins/soleur/test/ci-pr-affected-replay.test.sh:2485`** — comment `# the committed baseline EXISTS (it does in CI): the floors still run`. The parenthetical "(it does in CI)" is now factually false — the committed baseline was deleted in this PR. The fixture's `scripts/bl-empty.tsv` still exists so the assertion is correct; only the parenthetical is stale. **P3.**
- **R3 — `plugins/soleur/test/ci-pr-affected-replay.test.sh:2400, 2869, 2881, 2905, 2927`** — chk labels/comments still phrase the pass/grown contract as "live minus accepted equals the baseline", "live set equals the committed baseline passes", "live equals it", "when the committed baseline exists". These describe the *retained* `--baseline <file>` override machinery (settled ruling: present/present machinery kept), where equality is still the real contract — defensible. Reported for the record since they are the same sentence shape the runbook row was corrected away from; a reader could misread them as the default-path contract. **P3**, borderline.
- **R4 — `plugins/soleur/test/ci-pr-affected-replay.test.sh:4895`** — mutant name `ratchet-unresolved-base-is-an-adoption` unchanged. The task carve-out intentionally retains `adopt` fixture tokens and `ratchet-adoption-refused` (:4889); :4895 is the same mutant-name class and was flagged alongside :4889 by all three round-1 reviewers (code-quality P3-4, pattern-recognition P3-3, test-design P3). If the carve-out covers the class this is intentional; read literally it is an unaddressed round-1 P3. **P3**, for the record.
- **R5 — `scripts/ci-pr-affected-replay.py:1869`** — `ratchet_base` docstring still ends "An unresolvable base is exit 2, never an adoption." Flagged round-1 (code-quality P3-4, pattern-recognition P3-3, test-design P3 note); unchanged by the fix. Contrastive prose describing what the helper refuses — borderline acceptable — but the noun belongs to the retired arm. **P3.**
- **R6 — `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md:186`** — `new-pair` table row still says "not declared, not accepted and not in the baseline". Under strict zero no baseline exists so the clause is vacuous on the default path; the row is not in the fix hunks and the table spans `--baseline` overrides where the clause is meaningful. **P3**, borderline.

### Verified intentional / not residue

- `.github/workflows/ci.yml:431` — step name "Ratchet the audit against the committed baseline" is **intentionally byte-identical** per settled ruling (observation probe `ratchet-observation-window-10865.sh:88` `STEP=` literal matches it; test.sh:3908 mutant pins it). NOT a finding.
- `adopt`/`adoption` hits that ARE the fix's settled vocabulary ("never adopts", "can never adopt", "cannot be adopted"): ci.yml:403, runbook:155/187, replay.py:137/151/1747/2059-2060/2519, test.sh:2899. Also `adopt` fixture tokens (test.sh:2273/2304/2317/2473/2474) and `ratchet-adoption-refused` (:4889) per the explicit carve-out.
- `the adoption arm` at runbook:224, :272 — historical prose describing what was removed. Legitimate.
- `scripts/ci-pr-affected-audit.baseline.tsv` path mentions: runbook:264 (PR3b `git diff` entry condition — still evaluable on a deleted path), :272 (history), replay.py:136 ("is retired"), :1748 (`RATCHET_BASELINE` watch-path constant), :2522 (argparse default), test.sh fixture/oracle paths (:2281/:2682/:2699/:2827/:2860/:2864/:3027/:3201/:3259). All correct-in-context.
- `wc -l` survivors (ci.yml:696/:1236, runbook:245, ~25 sites in test.sh) count unrelated artifacts; none touch the baseline path.

## (b) Static analysis on the fix hunks — new findings only

Fix hunks: replay.py :135-137 (docstring), :1747 (comment), :2090-2094 (`base_text is not None and` guard + comment), :2519 (argparse `help=`); test.sh :2473 (`row_rt_reintroduced`), :2511 (`row_rt_big_baseline` line), :2970 (chk label).

- **Semgrep 1.181.0, `--config auto`** on `scripts/ci-pr-affected-replay.py` (whole file scanned, findings filtered to hunks): 290 rules, 1 target, ~100% parsed. One result: `python.lang.security.audit.exec-detected` at :1859 (WARNING) — outside every fix hunk and identical to the pre-existing hit already dispositioned in round-1 (`review/semgrep-sast.md`: "single semgrep hit (exec-detected, line 1859) … pre-existing and out-of-diff"). The live fire on :1859 doubles as the positive control: the packs can see real patterns in this file. **0 new findings on fix hunks.**
- **ShellCheck 0.11.0** on `plugins/soleur/test/ci-pr-affected-replay.test.sh`: 29 findings file-wide, all at lines {2649, 2715-2745, 2802-2814, 3241-3242, 3309, 3336, 3484-3521, 3560, 3795} — none inside or adjacent to the fix hunks (ranges 2470-2520 and 2965-2975 verified empty). The added constructs — `grep -qxF -- $'…\t…'`, `! grep -q -- '--print-baseline' <<<"$ROUTALL"`, `[[ "$r" -eq 0 ]]`, `grep -q '^baseline-dup'$'\t'` — are clean. **0 new findings on fix hunks.**

## Findings summary

| Sev | Item |
|---|---|
| P1 | none |
| P2 | none |
| P3 | R1 runbook:260 "Cumulative shrink-only check" heading; R2 test.sh:2485 "(it does in CI)" stale parenthetical; R3 test.sh:2400/2869/2881/2905/2927 "equals the committed baseline" chk-label family (borderline — retained `--baseline` contract); R4 test.sh:4895 `ratchet-unresolved-base-is-an-adoption` (class-covered by carve-out?); R5 replay.py:1869 "never an adoption" docstring; R6 runbook:186 `new-pair` row "not in the baseline" (borderline) |

## Verdict

- **(a) Targeted phrases all swept.** `green on a tree whose audit exits 1`, `must EQUAL a committed`, and `wc -l` on the deleted baseline path have **zero** surviving hits in every touched contract file — the two round-1 P2s are fixed at every site reviewers named (docstring opening, argparse `help=`, runbook §7 opening, ci.yml comment). Remaining residue is P3-cosmetic: the intentionally-retained `adopt`/`ratchet-adoption-refused` names plus six small stragglers listed above, of which only R2 is unambiguously stale (a false parenthetical, not contract text). The round-1 "retired adoption wording" item is only partially closed — :2970's chk label was fixed; :4895 and replay.py:1869 remain.
- **(b) Clean.** Semgrep (`--config auto`, 290 rules) and ShellCheck report **0 new findings** on any fix-hunk line; the only semgrep hit is the known pre-existing `exec-detected` at :1859.
- **Fix-hunk quality note (history seat):** the `base_text is not None and` guard at replay.py:2093 correctly implements round-1's remedy-tail finding (suppresses the restore/regenerate recipe when the base has no baseline — the common re-add shape); test.sh:2511 now pins `baseline-dup` co-firing and remedy absence under `baseline-reintroduced`, closing the "co-firing unpinned" round-1 P3; :2473 pins the arm's detail text and the absent `--print-baseline` remedy, closing the unasserted-message P3. All three in-scope round-1 items are implemented as diagnosed.

Nothing blocks. Report-only; no worktree files were modified by this seat.
