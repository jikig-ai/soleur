# Decision Challenges — feat-one-shot-6721-6723-6724

Persisted in headless mode per ADR-084 / `decision-principles.md`. The operator's stated
direction is the default; these are surfaced, not applied. `/ship` renders these into the
PR body and files them as an `action-required` issue.

---

## UC-1 — Split #6723 into its own PR, landing #6721 first

**Class:** User-Challenge (contradicts the operator's stated direction).

**Operator's stated direction:** *"Bundle them — they share the 'a gate that structurally cannot fail' shape and two share the same config file."*

**The challenge:** `architecture-strategist` recommends splitting #6723 out and sequencing it after #6721.

**Grounds:**

1. **The stated reason for bundling does not hold.** The three fixes are **file-disjoint**: #6721 touches only `secret-scan.yml`; #6723 touches only `.gitleaks.toml`; #6724 touches the ship skill and three hook copies. No file is shared between #6721 and #6723 — only the *subsystem* is.
2. **Blast radius differs by an order of magnitude.** #6723 changes live scan semantics on every job on every PR repo-wide, plus retroactively across history, and ships with a known-red history state whose mitigation must be verified in the same commit. #6721 and #6724 are CI config and a merge gate, verified by local fixtures.
3. **Sequencing makes the key measurement stronger.** AC11 now requires verifying the widened rule against the `-m --all` walk. If #6721 lands first, #6723 is verified against the *live, merged* cron walk rather than a hypothetical one.
4. **Reviewability.** The PR body must already carry four-plus pasted mutation RED outputs, an enumeration, and two divergence rationales. A real finding is easy to lose in that payload.
5. **Ack-scope leakage.** The `secret-scan-allowlist-ack` label is PR-scoped — bundling means whoever acks the allowlist widening also acks hook changes they may not have read.

**Counter-argument for the operator's direction:** the three fixes share a theme and a learning; one PR keeps that narrative intact and avoids three review cycles.

**Reviewer's framing:** *"The three fixes share a theme. That justifies one learning file, not one PR."*

**Recommendation if split:** land #6721 (+#6724) first, then #6723 verified against the merged cron walk.

**Status:** UNRESOLVED — operator decision required. The plan as written remains bundled per the stated direction.

---

## UC-2 — `.gitleaksignore` as an alternative to the path-allowlist carve-out

**Class:** Taste / design alternative (does not contradict a stated direction, but was rejected by inheritance rather than by measurement).

**Context:** The plan silences a self-referential doc literal in `plugins/soleur/skills/review/SKILL.md` by adding an anchored path entry to the `database-url-with-password` rule. That entry permanently blinds the file to that rule.

**The alternative:** a finding-scoped `.gitleaksignore` entry suppresses one commit × one file × one rule × one line, without blinding the file to a future real DSN.

**Why it was dismissed too quickly:** the sibling #6706 plan rejected `.gitleaksignore` because *"the fingerprint embeds the commit SHA, so its survival is merge-strategy-dependent."* That premise **does not hold here** — `48b8bc4a5` is already an ancestor of `main`, so its SHA is frozen and cannot be rewritten. The plan inherited the rejection without re-testing it against this case.

**Caveat:** the new `gitleaks dir` step scans the tip, where the literal still lives, and a git-fingerprint does not cover a `dir` scan. So the full composite would be: split the tip literal (the runtime-assembly convention the test suite already uses) + `.gitleaksignore` for the frozen historical commit + add `.gitleaksignore` to CODEOWNERS.

**Status: MEASURED → REJECTED.** No longer an open question, and not an
operator decision — it was an empirical one, and it has been answered.

What was measured:

| check | result |
|---|---|
| history scan, `.gitleaksignore` + fingerprint, no carve-out | rc=0 — clears the frozen finding |
| tree scan, tip literal elided | rc=0 |
| a NEW real DSN pasted into `review/SKILL.md`, UC-2 config | **rc=1 — caught** |
| the same, under the shipped path carve-out | **rc=0 — blinded** |

On the security property alone UC-2 wins: the path carve-out permanently
blinds the file to the rule, so a future real credential pasted there is
silent, whereas UC-2 keeps it live. Its failure mode is also safer (a broken
fingerprint reds the gate; a path predicate fails open and silent).

**What killed it:** the fingerprint is commit-pinned, and the cron walks
`-m --all`. That walk surfaced the *same content at a second commit*
(`d85d7d577`) with a different fingerprint, unignored. So the ignore set is not
one line — it grows with every branch and merge that carries the file, and any
one missed reds the weekly cron. The path predicate is commit-independent by
construction, which is precisely why it was chosen for a finding frozen in
history.

The premise inherited from #6706 ("the fingerprint embeds the commit SHA, so
survival is merge-strategy-dependent") was indeed wrong for this case — the SHA
is frozen. But re-measuring found a *different* and stronger objection the
inherited reasoning had not identified. Both the original rejection and its
stated reason were wrong; the conclusion happens to stand.

**Byproduct:** running this measurement is what exposed that this PR's own
branch history carried two DSN literals and was failing its own PR-range gate.
See `session-state.md`.
