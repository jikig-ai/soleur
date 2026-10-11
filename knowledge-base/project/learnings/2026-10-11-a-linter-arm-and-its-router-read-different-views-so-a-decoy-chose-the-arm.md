# Learning: a lint arm and the code that routes to it read different views of the same file, so a decoy chose the arm

## Problem

#9941 added an indexed (`for_each`) `luks` arm to `scripts/lint-encryption-posture.py` so the web-2
`hcloud_volume.workspaces` row can be flipped without the #6588 false-PASS (citing a sibling volume's
apparatus by name similarity). The first design passed its own suite and the first review panel anyway:

- Arm routing and the singleton scanners read the **first raw regex match** in the file.
- The indexed arm read **unique, comment-free declarations**.
- A commented or string-literal decoy therefore chose which arm graded the row, and the weaker arm passed it.

Three fix rounds followed. Each round's fix was applied to the instance the seat named, and the next seat
found the same class one input shape over (wrapped ternary, comma in a value, nested object, quoted key,
nested ternary). The last round was fixed at the class: every consumer reads one shared view.

## Solution

- One comment-stripped, string-masked view per file; routing, the singleton scanners and the indexed arm all
  take their input from it.
- Routing reads the single `volume_id` argument of a **unique** declaration at depth 1, not the first match.
- `user_data` is parsed as a template map (one attribute per top-level value), and `for_each` values are
  compared whole, not by prefix.
- Schema: `minLength: 1` on every `device_binding` string, `pattern ^random_password\.` on the password.
- A mutation row for each load-bearing check (`# MUTATION-TARGET: MB-Ln`), run both FAIL->PASS and PASS->FAIL.
- Limits that remain are written into the ADR-140 addendum ("What a PASS grades", "Known limits") rather than implied.

## Key Insight

**When a gate has more than one reader of the same input, the defect is the divergence between the views,
not any one reader.** Ask of every new arm: "which view does the code that picks this arm read, and is it the
view the arm reads?" A fix that hardens one reader leaves the router free to choose the weaker one.
Grep every consumer of the input before declaring a class closed, and count the fix commit as the
least-reviewed code in the diff: three of the five regressions came from fix rounds.

A linter PASS also grades configured wiring only. State what it does not grade (recovery, reopen after
reboot) in the ledger-flip record, or the next reader treats green as proof.

## Session Errors

1. **`$TMPDIR` unset in the shell** — Recovery: used the scratchpad directory. Prevention: write scratch files to the session scratchpad, never assume `$TMPDIR`.
2. **`No module named 'yaml'` from the repo's Python wrappers** — Recovery: `PATH=/usr/bin:$PATH` to pick the system interpreter. Prevention: one-off; host Python via mise lacks the module.
3. **`ensure-semgrep.sh` returned rc=0 on a dead launcher** (shebang Python had no `semgrep` module) — Recovery: isolated venv, `ulimit -s unlimited`. Prevention: filed in #9984 (needs a `semgrep --version` check).
4. **Schema JSON reformatting by a tool changed unrelated lines** — Recovery: reverted. Prevention: edit the schema surgically, diff before commit.
5. **WC-37 regex, ADR edit anchor, shellcheck SC2016 infos** — Recovery: fixed inline. Prevention: one-off.
6. **WC-64 wrapped-ternary case failed after the first fix** — Recovery: operator continuation in `attr_sites`. Prevention: fixture the wrapped form for every new scanner, not just the single-line form.
7. **Fix rounds introduced regressions (comma, nested-object, nested-ternary, quoted-key)** — Recovery: class-level fix through one shared view, plus fixture per shape. Prevention: after any scanner fix, run the whole shape matrix (wrap, comma, nesting, quoting), and send the fix commit to a targeted seat.
8. **Last commit (`b69da869fa`) was not re-reviewed by a seat** — Recovery: disclosed in the review marker; verified by suite, real-ledger sweep parity and ratchets only. Prevention: none beyond disclosure; do not claim a re-review that did not run.
9. **`gh issue create` refused by the filing hook twice** (body file not yet written when the command ran; no user-visible-consequence line) — Recovery: write the body in a separate step, then `--label meta/machinery`. Prevention: write the body file first, label machinery findings `meta/machinery` up front.
10. **Shell cwd reset to the bare repo root mid-session** — Recovery: re-entered the worktree. Prevention: use absolute worktree paths.
11. **Queued `test-all.sh --affected` was too slow to wait on** — Recovery: killed it and ran the affected ratchets directly. Prevention: one-off.

## Tags
category: logic-errors
module: scripts/lint-encryption-posture.py
