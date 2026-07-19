---
title: "fix(secret-scan): scope push:main to main's ancestry + allow the DSN placeholder shape"
date: 2026-07-19
type: fix
issue: 6706
branch: feat-one-shot-6706-secret-scan-gitleaks-scope
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(secret-scan): scope `push:main` to main's ancestry + allow the DSN placeholder shape

Closes #6706.

## Overview

`secret-scan` is red on `main`. Two independent defects compound:

1. **A false-positive** — the custom `database-url-with-password` rule fires on a *comment* in
   `apps/web-platform/infra/vector.toml` that documents the credential shape a DSN scrubber
   defends against. The rule already has a placeholder allowlist; the flagged text uses a
   placeholder spelling (`pass`) the allowlist does not enumerate.
2. **A scope defect** — the `push:main` job runs bare `gitleaks git`, which walks **every fetched
   ref**, not `main`'s ancestry. `actions/checkout` with `fetch-depth: 0` fetches all remote
   branches, so any in-flight branch carrying a finding reddens `main`'s gate.

Defect 2 is the interesting one: it means `main`'s gate can fail for a commit that never merged,
and the failure output names no branch, so triage requires manual `git branch -r --contains`
archaeology.

**Every claim in this plan was measured against the pinned gitleaks v8.24.2 binary and the real
repository**, not derived from documentation or from the issue body. Two of the issue body's
premises did not survive measurement — see Research Reconciliation.

## Research Reconciliation — Issue Body vs. Measured Reality

| Issue-body claim | Measured reality | Plan response |
| --- | --- | --- |
| "The flagged line **IS** the scrubber (`msg = replace(msg, r'([a-z][a-z0-9+.-]*://)...')`)" | **False.** The finding is at `vector.toml:384` **at commit `871fe6a94`**, which is the *comment* line `# ... INNGEST_POSTGRES_URI is a postgres://user:pass@host DSN in the`. The scrubber regex line contains no literal `postgres://`, so the rule (`keywords = ["postgres://","postgresql://"]`) cannot match it. Exactly **1** finding, not several. | Fix targets the *placeholder-comment* shape, not the scrubber. Rules out the issue's option 3 ("rewrite the pattern so it does not match its own rule") as solving a problem that does not exist. |
| "The current `main` tree contains zero credential-shaped DSNs" | **True, and stronger than stated.** The *current* tree's comment reads `postgres://<user>:<pw>@host`, which the **existing** allowlist already covers via its `<[^>]+>` branch. Measured: `gitleaks dir apps/web-platform/infra/vector.toml -c .gitleaks.toml` → `no leaks found`. | The finding is **purely historical**, living in the diff of commit `871fe6a94`. A working-tree fix is a no-op. The allowlist must match *historical content*. |
| Suggested fix: "`.gitleaksignore` entry keyed on the finding fingerprint … survives the branch merging" | **Contradiction, though not for the reason first assumed.** The fingerprint is `<commit-sha>:<file>:<rule>:<line>`. The documented workflow is `gh pr merge --squash --auto`, and squash **rewrites the SHA** → fingerprint dead on arrival. Note the repo *also* has `allow_merge_commit: true` and real 2-parent merges land on `main` (verified — see H10), under which SHAs *would* survive. So the fingerprint's survival is **strategy-dependent and therefore unreliable**, which is disqualifying on its own. | **Reject `.gitleaksignore`.** Choose the content-based allowlist: it is SHA-independent and survives *either* merge strategy. |
| Suggested fix: "`[[rules.allowlist]]` scoped to `apps/web-platform/infra/vector.toml`" | Mechanically works, but suppresses the **entire** rule for an infra file that legitimately carries DSN configuration — a real hardcoded `INNGEST_POSTGRES_URI` there would go undetected. Also adds a `paths` entry, which trips the `allowlist-diff` ack gate. | **Reject.** Prefer the narrower content-anchored `regexes` widening (see Alternatives). |
| (Implied by a research pass) "`database-url-with-password` is a default-pack rule — beware same-ID shadowing per the 2026-06-09 learning" | **False.** It is **our own** custom rule at `.gitleaks.toml:281`. Measured: `gitleaks dir <real-DSN-fixture>` with **no** `--config` → `no leaks found`, i.e. the default pack has no such rule. | The same-ID shadowing trap (`2026-06-09-gitleaks-same-id-custom-rule-shadows-default-pack-rule.md`) **does not constrain this fix**. We edit the existing custom rule in place; no new `[[rules]]` block is introduced. |

## Hypotheses — measured, not reasoned

Every verdict below is backed by a command that was actually run. No verdict rests on reading
config or documentation.

| # | Hypothesis | Verdict | Evidence |
| --- | --- | --- | --- |
| H1 | Bare `gitleaks git` walks all refs, not HEAD ancestry | **CONFIRMED** | Synthetic repo: `trunk` ancestry = 1 commit, all-refs = 3. `gitleaks git` reported `3 commits scanned`. |
| H2 | The off-ref finding reddens a scan of the real repo | **CONFIRMED** | Created `refs/temp/6706probe` → `871fe6a94` (simulating CI's fetched `origin/<branch>`). Bare form: `3228 commits scanned` / `leaks found: 1`. Ref deleted; repo state restored. |
| H3 | `--log-opts="--no-merges HEAD"` scopes to main's ancestry and clears it | **CONFIRMED** | Same repo, same ref present: `3094 commits scanned` / `no leaks found`. |
| H4 | The flagged line is the scrubber regex | **REFUTED** | Finding is `vector.toml:384` = the comment. See Research Reconciliation row 1. |
| H5 | The current tree still trips the rule | **REFUTED** | `gitleaks dir apps/web-platform/infra/vector.toml -c .gitleaks.toml` → `no leaks found`. |
| H6 | Widening the placeholder alternation clears the finding **without** losing real-credential detection | **CONFIRMED** | Safety matrix below — 5 real-credential shapes still fire; only placeholder spellings go quiet. |
| H7 | A `regexes`-only edit trips the `allowlist-diff` ack gate | **REFUTED** | `parse-gitleaks-allowlists.mjs` on base vs candidate → added-paths set is **empty**. Gate does not fire. (We still add the trailer — see Risks.) |
| H8 | `refs/remotes/origin/*` exist in the CI checkout (precondition for Phase 3 attribution) | **CONFIRMED, by the defect itself** | The observed CI failure found a commit reachable **only** from an unmerged branch. gitleaks' `--all` walk can only reach a commit via a ref, so those remote-tracking refs must exist under `actions/checkout` `fetch-depth: 0`. The bug's existence *is* the proof that `git branch -r --contains` will resolve in Phase 3. |
| H9 | `--no-merges` is load-bearing in the new `--log-opts` | **REFUTED — it is a no-op** | `main` carries 35 merge commits, yet `--log-opts="HEAD"` and `--log-opts="--no-merges HEAD"` both scanned **3094** commits with identical exit 0. Mechanism confirmed directly: `git log -p -1 cbd6c948d` (a real 2-parent merge) emits **0 bytes** of patch, vs **10901 bytes** for its first parent — gitleaks drives `git log -p` without `-m`/`--cc`, so merge commits contribute no content to scan either way. Keep the flag only for symmetry with the PR jobs. |
| H10 | "The repo squash-merges, so `main` carries no merge commits" (a premise this plan originally asserted) | **REFUTED — the plan was wrong** | `git log --merges origin/main` → 35 merges, incl. `cbd6c948d` "Merge pull request #6326" (2026-07-11, **8 days** before this plan), `git cat-file -p` → 2 parents, confirmed ancestor of main. `gh api repos/jikig-ai/soleur` → `allow_merge_commit: true`, `allow_squash_merge: true`, no branch protection enforcing linear history. **Consequence:** any plan reasoning that depends on "SHAs are always rewritten at merge" or "main is linear" is unsound. Corrected in the `.gitleaksignore` row and the Risks table. |

### Safety matrix (measured — `gitleaks dir`, exit-code based)

| Input | Current config | After fix |
| --- | --- | --- |
| `postgres://user:pass@host` ← **the flagged content** | FIRES | allowlisted |
| `postgres://<user>:<pw>@host` ← current tree | allowlisted | allowlisted |
| `postgres://user:password@host` | allowlisted | allowlisted |
| `postgres://admin:SuperSecretPassw0rd@db.example.com` | **FIRES** | **FIRES** |
| `postgres://prod:passw0rdREALLEAK@db.internal` | **FIRES** | **FIRES** |
| `postgres://svc:pass-but-longer@host.example` | **FIRES** | **FIRES** |
| `postgresql://root:hunter2@10.0.0.5` | **FIRES** | **FIRES** |

The `@` terminator in the allowlist regex is what makes this safe: `pass` only matches when the
password is *exactly* `pass`. A real password merely *starting* with `pass` still fires (row 6).

> **Verification-command trap (cost me one wrong matrix):** `grep -cE 'leaks found'` matches
> `no leaks found` too, so the first safety matrix reported "FIRES" for all seven rows. Every AC
> in this plan therefore gates on **exit codes**, never on substring-matching gitleaks' summary
> line. Any future AC touching gitleaks output must do the same.

## User-Brand Impact

**If this lands broken, the user experiences:** either a permanently-red `secret-scan` on `main`
(normalizing a failed security gate until it is ignored — the failure mode this issue exists to
prevent), or, if the allowlist is written too broadly, a real database credential merged
undetected.

**If this leaks, the user's data is exposed via:** an un-detected `postgres://` DSN committed to
the repo, granting direct database access. This is why the fix is anchored on the placeholder
*terminator* (`@`) rather than on a file path — a path-scoped suppression would blind the rule
for `apps/web-platform/infra/`, the very directory where a real DSN would most plausibly land.

**Brand-survival threshold:** `none` — this is a CI-gate correctness fix. No user-facing surface,
no persisted data, no runtime code path. The security-relevant risk (weakening detection) is
bounded and measured by the safety matrix above; net detection coverage is unchanged for every
real-credential shape tested.

- `threshold: none, reason: the diff touches a sensitive path (.github/workflows/secret-scan.yml) but ships no user-facing surface, no persisted data and no runtime code path, and the only security-relevant axis — detection coverage — is measured unchanged for every real-credential shape in the safety matrix, since the allowlist widening admits only exact-match placeholder tokens terminated by @.`

## Implementation Phases

Phase order is load-bearing: Phase 1 (content allowlist) must precede Phase 2 (scope change), so
that after Phase 2 narrows the scan the finding is *already* neutralized for the moment the
branch merges into main's ancestry. Shipping Phase 2 alone would hide the finding rather than
resolve it.

### Phase 1 — Allow the placeholder DSN shape (clears the false positive permanently)

Edit the `regexes` allowlist on the **existing** `database-url-with-password` rule
(`.gitleaks.toml`, the `[[rules.allowlists]]` block under `id = "database-url-with-password"`).
Do **not** add a new `[[rules]]` block and do **not** change the rule `id`.

Extend only the password-placeholder alternation, adding `passwd`, `pass`, and `pw`:

```toml
  # Allow placeholder URLs (USER:PASSWORD shapes) AND asterisk-redacted shapes
  # (postgres://user:***@HOST) — `\*+` branch per #3877 recognizes the canonical
  # Doppler/psql/pooler-output redaction convention. `pass`/`passwd`/`pw` per #6706:
  # infra comments document the credential shape a scrubber defends against, and the
  # trailing `@` anchor means these match ONLY when the password is exactly the
  # placeholder token — `postgres://svc:pass-but-longer@h` still fires.
  regexes = ['''postgres(?:ql)?://(?:USER|user|postgres|<[^>]+>):(?:PASSWORD|password|passwd|pass|pw|secret|<[^>]+>|\*+)@''']
```

The user-side alternation is **unchanged**. Only the password side widens.

Because the `allowlist-diff` gate cannot see `regexes` edits (H7, and the known blind spot
tracked by open issue **#3888**), the commit MUST carry an `Allowlist-Widened-By: <name>`
trailer voluntarily, per
`knowledge-base/project/learnings/2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md`.

### Phase 2 — Scope the `push:main` scan to main's ancestry

In `.github/workflows/secret-scan.yml`, the `Scan (full tree, push:main)` step currently runs:

```bash
./gitleaks git --redact --no-banner --exit-code 1
```

Change it to scope the walk to the pushed ref's ancestry, with a comment recording *why* (the
bare form's `--all` default is the defect):

```bash
# `gitleaks git` with no --log-opts walks EVERY fetched ref (checkout uses
# fetch-depth: 0, which fetches all remote branches), so a finding on an
# unmerged in-flight branch reddens main's gate for a commit that never
# merged (#6706). Scope to the pushed ref's own ancestry. In-flight branches
# remain covered by the pull_request job (base..head) and by the weekly cron.
./gitleaks git --redact --no-banner --exit-code 1 --log-opts="--no-merges HEAD"
```

**Coverage impact, stated precisely.** For every branch that becomes a PR — the overwhelmingly
common path — coverage is unchanged: the `pull_request` job scans `base..head`, and the weekly
`schedule` job keeps all-ref breadth (Phase 3). What changes is *which gate reports it*, which is
the defect. The one real regression is un-PR'd branches (see Risks) — accepted and documented.

**Two stale comments MUST be corrected in the same edit** (they will otherwise document behaviour
the workflow no longer has):

1. The header trigger list, anchor `push: branches: [main]           full-tree scan after merge` →
   ```
   #   - push: branches: [main]           main-ancestry scan after merge
   #                                      (--log-opts="--no-merges HEAD"; NOT all
   #                                      fetched refs — see #6706)
   ```
2. The step name, anchor `name: Scan (full tree, push:main)` → `name: Scan (main ancestry, push:main)`.

**Merge-queue invariant — verified structurally intact, one advisory note.** The `on:.merge_group`
Pattern A/B invariant turns on the `scan` job re-running on `merge_group`; Phase 2 edits only the
step gated `if: github.event_name == 'push'`, so Pattern A still fires and Pattern B stays sound.
No invariant text needs rewriting. **However**, Pattern B's soundness argument says an allowlist
widening is safe because "that widening was a separate PR acked on its own" — and *this* PR is such
a widening whose ack the `allowlist-diff` gate structurally cannot see (H7 / #3888). The trailer is
voluntary; nothing fails closed if omitted. Add a one-line note in the `on:.merge_group` block
pointing at #3888 so the next reader does not over-trust the invariant.

### Phase 3 — Make the retained cross-branch breadth diagnosable (minimal form)

The weekly `schedule` job keeps its all-refs breadth on purpose — it is the retroactive safety
net that re-scans history with the current rule pack. But per the issue, retained breadth must
come with attribution, or a red weekly gate is undiagnosable.

**Adopt the minimal form: add `-v`.** Measured, `-v` already prints per finding:

```
RuleID:      database-url-with-password
File:        <path>
Line:        <n>
Commit:      <full sha>
Fingerprint: <sha>:<file>:<rule>:<line>
```

That is every field the elaborate form would emit *except* the branch name, already redacted,
for one flag. The branch name costs the operator exactly one command against a SHA that `-v`
hands them.

```yaml
      - name: Scan (full history, weekly cron)
        if: github.event_name == 'schedule'
        run: |
          set -euo pipefail
          # All-refs breadth is deliberate here (retroactive re-scan with the
          # current rule pack). `-v` prints RuleID/File/Line/Commit per finding
          # so a red cron is diagnosable; resolve the owning branch with
          # `git branch -r --contains <Commit>` (#6706). --redact still applies.
          ./gitleaks git --redact --no-banner --exit-code 1 -v
```

Phase 4 records the `git branch -r --contains <Commit>` follow-up step in the runbook.

**Why not the JSON-report + `jq` + `git branch -r --contains` loop?** It was designed, built, and
then rejected at review on cost/benefit. It works — the mechanism was verified end-to-end
(report carries `Commit`; `--redact` blanks `Secret` **and** `Match` *inside the report file*;
`actions/checkout` `fetch-depth: 0` really does create `refs/remotes/origin/*`, confirmed from
`ref-helper.ts` `getRefSpecForAllHistory` → `['+refs/heads/*:refs/remotes/origin/*', tagsRefSpec]`;
the annotation renders and `shellcheck` is clean). It was cut because it adds the plan's **largest
failure surface to serve its smallest consumer**: one weekly cron that is green almost every week.
Concretely it costs a report file, a `jq` dependency, an rc-capture/re-exit dance, a
`set -e`/`pipefail` interaction where a failing `jq` **replaces the scan verdict with jq's exit
status** (measured: `RC(jq-fails)=5`, turning a *clean* run red), reliance on in-report redaction,
and an extra AC. The `-v` form delivers ~90% of the diagnostic value for one flag and zero new
failure modes. If a future need justifies full attribution, the verified snippet is recoverable
from this plan's history — add `|| true` to terminate the `jq` pipeline.

### Phase 4 — Document the ref-scope semantics

Update `knowledge-base/engineering/operations/secret-scanning.md` (verified: it currently has **no**
ref-scope section, so this phase is genuinely needed) with a short subsection covering:

1. **Ref scope per event** — `pull_request` → `base..head`; `merge_group` → candidate diff;
   `push` → main's ancestry (`--no-merges HEAD`); `schedule` → all fetched refs.
2. **How to triage a red cron** — `-v` prints `RuleID`/`File`/`Line`/`Commit`; resolve the owner
   with `git branch -r --contains <Commit>`.
3. **The accepted trade-off** — a branch pushed to `origin` with no PR is no longer swept by
   `push:main`; its detection window is the weekly cron. Recorded as a deliberate decision.
4. **The merge-commit blind spot** — `gitleaks git` drives `git log -p` with no `-m`/`--cc`, so
   content introduced *only* by a merge commit's own tree is invisible to **every** job. Pre-existing,
   out of scope here, tracked by the follow-up issue below.

### Phase 5 — File the follow-up issue (in-scope deliverable, not a deferral)

Open an issue for the merge-commit blind spot surfaced by this plan's research: `gitleaks git`
never scans merge-commit-exclusive content in any job (measured: `git log -p` emits 0 bytes for
`cbd6c948d`), while `main` genuinely carries 35 merge commits and `allow_merge_commit: true`.
Include the measurement, note that hand-resolved conflict content is the plausible attack shape,
and label it `type/security` + `priority/p3-low`. This is a *finding*, not a regression from this
PR — but leaving it undocumented would make it invisible.

## Files to Edit

- `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-6706-secret-scan-gitleaks-scope/.gitleaks.toml` — widen the password-placeholder alternation on the existing `database-url-with-password` rule's `regexes` allowlist (Phase 1).
- `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-6706-secret-scan-gitleaks-scope/.github/workflows/secret-scan.yml` — ancestry-scope `push:main` **plus** correct the two stale "full tree" references (header trigger comment + step name) and add the #3888 note to the `on:.merge_group` block (Phase 2); add `-v` to `schedule` (Phase 3).
- `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-6706-secret-scan-gitleaks-scope/knowledge-base/engineering/operations/secret-scanning.md` — document per-event ref scope (Phase 4).

**Explicitly NOT edited:** `apps/web-platform/infra/vector.toml`. Measured clean (H5); the finding
is historical. Editing it would be a no-op that creates the illusion of a fix.

## Files to Create

None.

## Allowlist-surface consumer sweep

This is a hand-maintained allowlist, so every consumer was enumerated rather than assumed:

| Consumer | Impact of this change |
| --- | --- |
| `apps/web-platform/scripts/parse-gitleaks-allowlists.mjs` | Parses `paths` only. Added-paths set measured **empty** (H7). No change. |
| `apps/web-platform/scripts/allowlist-diff.sh` | Consumes the parser above → gate does not fire. Trailer added voluntarily anyway. |
| `apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh` | Asserts parser behaviour (T1–T9). Untouched — no `paths` or block-structure change. |
| `plugins/soleur/test/gitleaks-rules.test.sh` | Asserts rule *behaviour* (no-shadow for the Slack rule). Unaffected. |
| `.claude/hooks/git-commit-secret-scan.sh` | Reads the same `.gitleaks.toml`; inherits the widened allowlist. Intended. |
| `apps/web-platform/scripts/rename-guard.sh` | Keys on `paths` destinations. No `paths` change → unaffected. |

## Acceptance Criteria

### Pre-merge (PR)

All gitleaks ACs gate on **exit code**, never on substring-matching the summary line (`no leaks
found` contains `leaks found` — see the trap note above).

1. **AC1 — false positive cleared at the flagged commit, and the defect provably reproduced.**
   With the pinned v8.24.2 binary and
   `--log-opts="--no-merges 871fe6a94c7cbb13ec9badd2247c5b2d86f62b2f~1..871fe6a94c7cbb13ec9badd2247c5b2d86f62b2f"`:
   exits **1** against the **unmodified** `.gitleaks.toml`, and exits **0** against the fixed one.
   Both halves required — the post-fix half alone cannot distinguish "fixed" from "never broken".
2. **AC2 — real credentials still caught (no detection regression).** Each of these, alone in a
   file, scanned with `gitleaks dir <dir> --exit-code 1 -c .gitleaks.toml`, exits **1**:
   `postgres://admin:SuperSecretPassw0rd@db.example.com`,
   `postgres://prod:passw0rdREALLEAK@db.internal`,
   `postgres://svc:pass-but-longer@host.example`, `postgresql://root:hunter2@10.0.0.5`.
3. **AC3 — placeholder shapes quiet.** Same harness exits **0** for `postgres://user:pass@host`,
   `postgres://<user>:<pw>@host`, `postgres://user:password@host`. Note only the **first** row is
   discriminating: the other two are already allowlisted pre-fix, so they cannot detect a missing
   Phase 1.

   > **AC2/AC3 fixture-location requirement (load-bearing).** Fixtures MUST be written to
   > `$(mktemp -d)` **outside the repository worktree**. Path allowlists
   > (`__synthesized__/`, `__goldens__/`, `knowledge-base/**/plans/`) silence this rule by path —
   > measured: the same real credential exits **0** inside
   > `apps/web-platform/test/__synthesized__/` but **1** in a neutral dir. Placing fixtures in the
   > repo's test dirs would make AC3 pass **vacuously** and AC2 fail **spuriously**. This is a live
   > hazard because `cq-test-fixtures-synthesized-only` points the implementer at exactly the
   > allowlisted directory.

4. **AC4 — off-ref finding no longer reddens a push:main-shaped run.** *(Rewritten at review: the
   original construction tested Phase 1, not Phase 2 — because Phase 1 already clears the finding
   at `871fe6a94`, the bare all-refs form would also exit 0 post-Phase-1, so nothing in it detected
   an omitted or wrong Phase 2.)*
   In a **scratch clone**, commit a **synthetic, non-allowlisted** DSN
   (`postgres://admin:SuperSecretPassw0rd@db.example.com`) on a side branch, publish it as a
   remote-tracking ref (`refs/remotes/origin/6706ac`), and leave `main` clean. Then, **against the
   same post-fix config**:
   - bare form (`gitleaks git --redact --no-banner --exit-code 1`) exits **1**, and
   - Phase 2 form (`--log-opts="--no-merges HEAD"`) exits **0**.

   Using one config for both halves is what isolates Phase 2's scoping from Phase 1's allowlist.
   Delete the ref afterwards.
5. **AC5 — rule identity unchanged.** `grep -c '^id = "database-url-with-password"' .gitleaks.toml`
   returns exactly **1** (no duplicate/shadowing rule block introduced).
6. **AC6 — ack gate not silently tripped.** `comm -13` of
   `parse-gitleaks-allowlists.mjs` output between `origin/main` and HEAD yields an **empty**
   added-paths set, AND a commit in the range carries an `Allowlist-Widened-By:` trailer.
7. **AC7 — workflow YAML is valid and the embedded shell parses.** `actionlint
   .github/workflows/secret-scan.yml` passes, and each modified `run:` block extracted to a file
   passes `bash -n`. (Do **not** run `bash -n` on the `.yml` itself.)
8. **AC8 — the weekly cron prints diagnosable findings.** The `schedule` step's invocation contains
   `-v`, and a scan run with `-v` against a fixture finding prints `RuleID`, `File`, `Line`, and
   `Commit`. *(The original AC8 asserted the attribution annotation "does not contain
   `SuperSecret`" — vacuous, since the real finding is `postgres://user:pass@host` and never
   contained that string; it would pass with redaction fully disabled. Superseded along with the
   Phase 3 simplification.)*
9. **AC9 — `secret-scan` is green on this PR** (all five required contexts pass).
10. **AC10 — runbook updated.** `knowledge-base/engineering/operations/secret-scanning.md`
    contains a subsection naming the ref scope of each of the four events
    (`pull_request`, `merge_group`, `push`, `schedule`), the `git branch -r --contains <Commit>`
    attribution step, and the accepted un-PR'd-branch trade-off.
11. **AC11 — stale "full tree" wording removed.** `grep -c 'full tree' .github/workflows/secret-scan.yml`
    returns **0** — both the header comment (`push: branches: [main]  full-tree scan after merge`)
    and the step name (`Scan (full tree, push:main)`) must be corrected, or the workflow documents
    behaviour it no longer has.
12. **AC12 — PR body carries `Closes #6706`**, references **#3888** as the reason the
    `Allowlist-Widened-By:` trailer is manual, and links the follow-up issue for the merge-commit
    blind spot.

### Post-merge (operator)

None. All verification is automatable pre-merge and in CI.

Post-merge confirmation is mechanical and happens on its own: the merge to `main` triggers the
`push:main` `secret-scan` run, which is the real-world assertion of AC4. `/soleur:ship` already
watches post-merge check status, so no separate operator step is warranted.

## Observability

```yaml
liveness_signal:
  what: "secret-scan workflow conclusion on push:main + weekly cron"
  cadence: "every push to main; cron '0 6 * * 1'"
  alert_target: "GitHub Actions run status (required check on main)"
  configured_in: ".github/workflows/secret-scan.yml"
error_reporting:
  destination: "GitHub Actions job log + ::error:: annotations (file/line anchored)"
  fail_loud: true  # --exit-code 1; job fails closed on any finding
failure_modes:
  - mode: "Real secret committed to main's ancestry"
    detection: "push:main scan exits 1"
    alert_route: "required check fails; merge blocked / main gate red"
  - mode: "Secret on an in-flight branch"
    detection: "pull_request job scans base..head; weekly cron scans all refs"
    alert_route: "PR check fails; cron run fails with owning-branch annotation"
  - mode: "Red gate with no attributable owner (the #6706 triage cost)"
    detection: "Phase 3 attribution emits owning ref(s) per finding"
    alert_route: "::error:: annotation naming rule, file, line, short SHA, owning ref"
  - mode: "Allowlist widened without review"
    detection: "allowlist-diff gate on paths; Allowlist-Widened-By trailer for regexes"
    alert_route: "allowlist-diff check fails / trailer visible in commit history"
logs:
  where: "GitHub Actions run logs (public repo — no report artifact uploaded, by design)"
  retention: "90 days (GitHub default)"
discoverability_test:
  command: "gh run list --workflow=secret-scan.yml --branch=main --limit 5 --json conclusion,headSha,createdAt"
  expected_output: "most recent run conclusion == success"
```

No SSH anywhere in the verification path.

## Domain Review

**Domains relevant:** Engineering (security/CI)

### Engineering — Security

**Status:** reviewed
**Assessment:** The change narrows a security gate's *reporting scope* and widens an allowlist's
*content* match. Both directions were measured rather than argued:

- Scope narrowing does not reduce coverage — in-flight branches remain covered by the
  `pull_request` job and the weekly all-refs cron. What changes is *which gate* reports them,
  which is the defect.
- Allowlist widening admits only exact placeholder tokens terminated by `@`. Five real-credential
  shapes, including one whose password *starts with* `pass`, still fire (safety matrix).
- Rejected the path-scoped suppression precisely because it would blind the rule for
  `apps/web-platform/infra/` — where a real DSN is most likely to land.
- The Phase 3 report is parsed in-job and never uploaded, preserving the documented
  "logs only, forensics via local re-run" posture for a public repo.

Product/UX Gate: **not applicable** — no files in `## Files to Edit` or `## Files to Create`
match any UI-surface term or glob (config, workflow, and docs only). Product domain NONE.

## Architecture Decision (ADR/C4)

**No new ADR.** This is a defect fix on an existing gate, not a new architectural decision. The
ref-scope semantics are already documented in-repo at
`knowledge-base/engineering/operations/secret-scanning.md` plus the workflow's own extensive inline
rationale (the `on:.merge_group` invariant block), and Phase 4 keeps that record true — matching
this gate's established documentation pattern (its trust invariants live in the workflow header,
not in ADRs).

**C4 views — no impact, enumerated rather than asserted.** Read all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` and check:
(a) **external human actors** — none introduced; the change adds no correspondent, reviewer, or
recipient; (b) **external systems/vendors** — none; gitleaks is an existing pinned CI binary
already inside the build boundary, and no new vendor edge is added; (c) **containers/data stores**
— none touched; no runtime container, no persisted data; (d) **actor↔surface access
relationships** — unchanged; the gate's *reporting scope* narrows but no actor gains or loses
access to any surface. If any of (a)–(d) turns out to be modeled differently than stated, the
`.c4` edit is in scope for this PR (plus the `views.c4` include line) — do not defer it.

## Open Code-Review Overlap

- **#3888** — *"secret-scan: allowlist-diff parser should surface per-rule paths AND regexes."*
  **Directly relevant**: our Phase 1 edits a `regexes` line, which is exactly the surface this
  open issue says the ack gate cannot see. **Disposition: acknowledge, do not fold in.** Teaching
  the parser to diff `regexes` is a separate change with its own test surface
  (`parse-gitleaks-allowlists.test.sh` T1–T9) and its own ack-semantics design question; bundling
  it would couple a red-gate hotfix to a gate-semantics change. We mitigate in-scope by adding the
  `Allowlist-Widened-By:` trailer voluntarily, and the PR body should reference #3888 as the
  reason the trailer is manual.
- **#3321** — CODEOWNERS coverage for the `knowledge-base/project/learnings/` subtree. Mentions
  `.gitleaks.toml` but concerns a different surface. **Disposition: acknowledge**, no action.

## Alternatives Considered

| Option | Verdict | Reason |
| --- | --- | --- |
| **Widen the `regexes` placeholder alternation** (chosen) | **Adopted** | Content-anchored → SHA-independent → genuinely survives squash-merge. Narrowest option that preserves detection for every real-credential shape tested. |
| `.gitleaksignore` fingerprint entry | Rejected | Fingerprint embeds the commit SHA, so its survival is **merge-strategy-dependent**: the documented `gh pr merge --squash` rewrites the SHA and kills it, while a merge-commit merge (also enabled — H10) preserves it. An allowlist whose correctness depends on which button gets pressed fails the issue's "must survive the branch merging" requirement by construction. Also introduces a second allowlist mechanism with no trailer/review discipline, which the repo deliberately avoided (see the #3121 rollout learning). |
| `[[rules.allowlists]] paths` scoped to `vector.toml` | Rejected | Suppresses the whole rule for an infra directory where a real DSN is most likely to land. Also trips the ack gate for a strictly worse trade. |
| Rewrite the scrubber regex so it does not self-match | Rejected | Solves a non-problem — measurement shows the scrubber line never matched (H4); the comment did. |
| Do nothing; wait for the branch to merge or be deleted | Rejected | Leaves a red required check on `main` (normalizes gate failure) and leaves the class defect live for the next in-flight branch. |
| Scope the weekly cron to main's ancestry too | Rejected | The cron is the retroactive safety net; all-refs breadth is deliberate there. Phase 3 makes that breadth diagnosable instead of removing it. |

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Widening the allowlist hides a real credential whose password is literally `pass`/`pw` | Such a value is placeholder-grade, not a secret. The `@` anchor means only exact matches qualify; `pass-but-longer` still fires (measured). |
| Ancestry-scoping hides an in-flight-branch finding | Still caught by the `pull_request` job (`base..head`) and the weekly all-refs cron. Only the *reporting gate* changes. |
| "Evil merge" content (introduced by a merge commit's own tree, e.g. hand-resolved conflicts) is never scanned | **Real, pre-existing, and NOT introduced by this change — and the weekly cron is *not* a backstop for it.** Measured (H9): `git log -p` emits 0 bytes for a merge commit, and gitleaks passes no `-m`/`--cc`, so **every** job (PR, merge_group, push, cron) is equally blind. `--no-merges` therefore removes nothing. This matters because merge commits genuinely land on `main` (H10 — 35 of them). **Out of scope here** (the gate is no worse after this PR than before), but it is a real gap → file a follow-up issue rather than leave it implicit. |
| Un-PR'd branches lose near-continuous coverage | A branch pushed to `origin` with **no PR opened** is invisible to the `pull_request` job and, after Phase 2, no longer swept by `push:main`. Its detection window widens from "next push to main" (minutes/hours on this repo) to "next weekly cron" — or never, if deleted first. This is the deliberate flip side of the fix, not an oversight. **Mitigation:** document it explicitly in the Phase 4 runbook as an accepted trade-off, so it is a recorded decision rather than an implicit regression. The common path (every branch that becomes a PR) is unaffected. |
| The ack gate can't see the `regexes` widening (#3888) | Voluntary `Allowlist-Widened-By:` trailer, per the 2026-05-16 learning's explicit instruction. |
| Phase 3's `--exit-code 1` aborts the step before attribution prints | Capture rc via `|| scan_rc=$?` and re-exit at the end; AC8 asserts the annotation actually renders. |
| Attribution output leaks secret material into public logs | `--redact` verified to redact `Secret`/`Match` **inside the JSON report**; only rule/file/line/SHA/branch are echoed. Report is never uploaded as an artifact. AC8 asserts no unredacted material. |

## Test Strategy

No new test framework. Verification uses the pinned gitleaks binary the workflow itself installs,
driven by exit codes:

- Allowlist behaviour → `gitleaks dir` on single-line fixtures (AC2/AC3). Fixtures are
  **synthesized**, never real credentials (`cq-test-fixtures-synthesized-only`).
- Ref-scope behaviour → temp-ref reproduction, asserting the defect reproduces pre-fix and clears
  post-fix (AC4). Temp ref deleted after.
- Workflow validity → `actionlint` on the workflow + `bash -n` on extracted `run:` snippets (AC7).
- Existing suites (`parse-gitleaks-allowlists.test.sh`, `gitleaks-rules.test.sh`) must stay green;
  neither should change, since no `paths` and no rule-block structure change.

## Sharp Edges

- **`no leaks found` contains the substring `leaks found`.** Any grep-based assertion on gitleaks'
  summary line silently passes on both outcomes. Gate on exit codes. This produced a fully-wrong
  safety matrix during research before being caught.
- **Never pipe a gitleaks invocation whose exit code you are asserting.** `gitleaks … | tail -3; echo $?`
  reports **tail's** status, not gitleaks'. Observed printing `leaks found: 1` alongside `rc=0` —
  the same class as the trap above, and it will bite whoever implements these exit-code ACs.
  Redirect to a file, then check `$?` on the unpiped command.
- **A path allowlist silences the rule by location, so fixture placement decides the result.** The
  identical real credential exits 0 inside `apps/web-platform/test/__synthesized__/` and 1 in a
  neutral directory. Any AC that scans a fixture must pin it to `$(mktemp -d)` outside the worktree,
  or it measures the allowlist rather than the rule.
- **An AC that passes because of a *different* phase is not a test of the phase it names.** AC4
  originally planted the real flagged commit — which Phase 1 already clears — so its assertion held
  whether or not Phase 2 was implemented. When two changes both suppress the same finding, the AC
  for each must use a fixture only *that* change affects.
- **`gitleaks git --redact` alone prints no per-finding detail.** Add `-v` for diagnosis
  (`Finding/RuleID/File/Line/Commit/Fingerprint`). Documented in the 2026-05-16 learning; confirmed
  again here.
- **gitleaks scans the commit *range*, not the working tree.** Fixing a file in a later commit does
  not clear a finding introduced by an earlier one. This is why editing `vector.toml` would be a
  no-op for #6706.
- **A gitleaks fingerprint embeds the commit SHA**, so it does not survive squash-merge, rebase, or
  amend. Never use `.gitleaksignore` for a finding that must stay suppressed across a merge.
- **`database-url-with-password` is a Soleur custom rule, not default-pack.** Verify before
  assuming shadowing constraints apply: `gitleaks dir <fixture>` with **no** `--config` shows what
  the default pack alone detects.
- **`actionlint` validates workflows only.** Do not run it against composite action files, and
  never run `bash -n` against a `.yml`.
