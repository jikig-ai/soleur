# Tasks — fix(secret-scan): ref-scope + DSN placeholder allowlist (#6706)

Plan: `knowledge-base/project/plans/2026-07-19-fix-secret-scan-gitleaks-ref-scope-and-dsn-placeholder-plan.md`
Lane: `cross-domain`

> **Three standing rules for every gitleaks assertion below** (each cost a wrong result during research):
> 1. Gate on **exit codes** — `no leaks found` contains the substring `leaks found`.
> 2. **Never pipe** an invocation whose exit code you assert — `$?` becomes the pipe's last stage.
> 3. Put fixtures in `$(mktemp -d)` **outside the worktree** — repo test dirs are path-allowlisted,
>    which makes negative assertions vacuous and positive ones fail spuriously.

## Phase 0 — Setup & RED baseline

- [x] 0.1 Install the pinned scanner (same version + SHA the workflow pins):
      `curl -sSLo gitleaks.tgz https://github.com/gitleaks/gitleaks/releases/download/v8.24.2/gitleaks_8.24.2_linux_x64.tar.gz`
      → `echo "fa0500f6b7e41d28791ebc680f5dd9899cd42b58629218a5f041efa899151a8e  gitleaks.tgz" | sha256sum -c -`
      → `tar -xzf gitleaks.tgz gitleaks && chmod +x gitleaks`.
- [x] 0.2 Ensure the flagged commit is present: `git cat-file -e 871fe6a94c7cbb13ec9badd2247c5b2d86f62b2f^{commit}`
      (else `git fetch origin feat-one-shot-6500-6466-inngest-cutover-blockers`).
- [x] 0.3 **Capture RED** — `./gitleaks git --no-banner --redact -v -c .gitleaks.toml --log-opts="--no-merges 871fe6a94~1..871fe6a94" .`
      → exit **1**, `RuleID: database-url-with-password`, `File: apps/web-platform/infra/vector.toml`, `Line: 384`.
      The flagged line is the **comment**, not the scrubber regex.
- [x] 0.4 Confirm the rule is a **Soleur custom rule**, not default-pack:
      `grep -c '^id = "database-url-with-password"' .gitleaks.toml` → **1**; and `./gitleaks dir <fixture>`
      with **no** `--config` → no leaks. (Guards the same-ID shadowing trap.)
- [x] 0.5 Confirm the current tree is already clean — proves the fix must target *history*:
      `./gitleaks dir apps/web-platform/infra/vector.toml --no-banner --exit-code 1 -c .gitleaks.toml` → **0**.

## Phase 1 — Allowlist the placeholder DSN shape ❌ REVERTED (do not implement)

> **Implemented, measured to silence real credentials, then reverted in full.**
> `.gitleaks.toml` is byte-identical to `origin/main` in the shipped PR. The ticked
> boxes below are the record of what was done before the revert — they are history,
> not shipped state. Do not re-implement this phase without first reading #6723,
> which is the pre-existing gap the widening would have broadened. Measurements: §S1.

- [x] 1.1 In `.gitleaks.toml`, inside the **existing** `[[rules.allowlists]]` block under
      `id = "database-url-with-password"`, extend **only** the password-side alternation to
      `(?:PASSWORD|password|passwd|pass|pw|secret|<[^>]+>|\*+)@`.
      Leave the user-side alternation, the `paths` array, and the rule `id`/`regex` untouched.
- [x] 1.2 Update the adjacent comment: cite `#6706` and the `@`-anchor property (matches only when the
      password is *exactly* the placeholder token).
- [x] 1.3 **Do NOT** add a `[[rules]]` block, change the rule id, add a `paths` entry, or create `.gitleaksignore`.
- [x] 1.4 Rerun 0.3 → exit **0** (GREEN). Re-run against the *unmodified* config → still exit **1** (AC1 both halves).
- [x] 1.5 No detection regression — each alone in a `$(mktemp -d)` file, must exit **1**:
      `postgres://admin:SuperSecretPassw0rd@db.example.com`, `postgres://prod:passw0rdREALLEAK@db.internal`,
      `postgres://svc:pass-but-longer@host.example`, `postgresql://root:hunter2@10.0.0.5`.
- [x] 1.6 Placeholders quiet — must exit **0**: `postgres://user:pass@host` (the only discriminating row),
      `postgres://<user>:<pw>@host`, `postgres://user:password@host`.
- [x] 1.7 Ack gate not silently tripped: added-paths set from `parse-gitleaks-allowlists.mjs`
      (origin/main vs HEAD) is **empty**.
- [x] 1.8 Commit with an `Allowlist-Widened-By: <name>` trailer — voluntary, because the gate cannot
      see `regexes` edits (#3888).

## Phase 2 — Scope `push:main` to main's ancestry

- [x] 2.1 Change the `push` step to
      `./gitleaks git --redact --no-banner --exit-code 1 --log-opts="--no-merges HEAD"`.
- [x] 2.2 Add a comment explaining why (bare form walks every fetched ref because checkout uses
      `fetch-depth: 0`; #6706), and note in-flight branches stay covered by `pull_request` + weekly cron.
- [x] 2.3 **Correct stale wording** — the workflow must not document behaviour it no longer has:
      - header trigger comment `push: branches: [main]   full-tree scan after merge` → `main-ancestry scan after merge`
      - step name `Scan (full tree, push:main)` → `Scan (main ancestry, push:main)`
      - verify: `grep -c 'full tree' .github/workflows/secret-scan.yml` → **0**
- [x] 2.4 Add a one-line note to the `on:.merge_group` block: Pattern B's "acked on its own" premise is
      convention-only for `regexes` widenings (#3888).
- [x] 2.5 **Verify Phase 2 in isolation** (the original AC tested Phase 1 by mistake): in a scratch clone,
      commit a synthetic **non-allowlisted** DSN (`postgres://admin:SuperSecretPassw0rd@db.example.com`)
      on a side branch published as `refs/remotes/origin/6706ac`, `main` clean. Against the **same
      post-fix config**: bare form → exit **1**; `--log-opts="--no-merges HEAD"` → exit **0**. Delete the ref.

## Phase 3 — Weekly cron diagnosability (minimal form)

- [x] 3.1 Add `-v` to the `schedule` step's invocation; keep its all-refs breadth.
- [x] 3.2 Comment it: `-v` prints `RuleID`/`File`/`Line`/`Commit`; resolve the owner with
      `git branch -r --contains <Commit>` (#6706).
- [x] 3.3 **Do NOT** build the JSON-report + `jq` + attribution-loop version. It was designed and verified,
      then cut at review: largest failure surface in the plan serving its smallest consumer, and a failing
      `jq` under `pipefail` replaces the scan verdict with jq's status (turning a *clean* run red).

## Phase 4 — Documentation

- [x] 4.1 Add a ref-scope subsection to `knowledge-base/engineering/operations/secret-scanning.md`
      (verified: no such section exists today) covering all four events:
      `pull_request` → `base..head`; `merge_group` → candidate diff; `push` → main ancestry;
      `schedule` → all refs.
- [x] 4.2 Document red-cron triage: `-v` fields + `git branch -r --contains <Commit>`.
- [x] 4.3 Record the accepted trade-off: a branch pushed with **no PR** is no longer swept by `push:main`;
      its detection window becomes the weekly cron.
- [x] 4.4 Record the merge-commit blind spot: `gitleaks git` uses `git log -p` with no `-m`/`--cc`, so
      merge-exclusive content is invisible to **every** job (not just the scoped one).

## Phase 5 — Follow-up issue (in-scope deliverable)

- [x] 5.1 File an issue for the merge-commit blind spot. Include the measurement (`git log -p -1 cbd6c948d`
      → 0 bytes vs 10901 for its parent; `main` carries 35 merge commits; `allow_merge_commit: true`).
      Labels `type/security` + `priority/p3-low`. Verify both labels exist first via `gh label list`.

## Phase 6 — Verification & ship

- [x] 6.1 `actionlint .github/workflows/secret-scan.yml` passes. Extract each modified `run:` block to a
      file and `bash -n` it. **Never** run `bash -n` on the `.yml` itself, and never `actionlint` a
      composite action.
- [x] 6.2 Existing suites green (neither should need changes):
      `apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh`,
      `plugins/soleur/test/gitleaks-rules.test.sh`.
- [ ] 6.3 Walk every AC in the plan, recording the actual command + output.
- [ ] 6.4 `secret-scan` green on the PR (all five required contexts).
- [ ] 6.5 PR body: `Closes #6706`, references #3888 (why the trailer is manual), links the Phase 5 issue.
- [ ] 6.6 No post-merge operator steps — the merge triggers the `push:main` run that is the real-world
      assertion of the fix; `/soleur:ship` already watches post-merge check status.

---

## AC verification record (task 6.3)

> **Read §S1 first — Phase 1 was reverted after this record was written.**
> **Superseded (tested the reverted widening, not shipped behaviour):** AC1, AC2,
> AC3 and the extra-fixture row, AC5 (trivially true now — the file is untouched),
> AC6 (no `.gitleaks.toml` change exists to ack, so the `Allowlist-Widened-By`
> trailer no longer applies). Retained verbatim as the record of what was verified
> at the time.
> **Still live, re-verified post-revert:** AC4, AC7, AC8, AC9, AC10, AC11, AC12 —
> though AC10/AC12's content changed with the revert (the runbook documents a
> known-gap rather than a widening; the PR body links #6723 as well as #6721).
> The replacement guard for rule behaviour is the T6/T7/T8 suite (§T1), which pins
> the allowlist as it exists on `main` rather than as this PR proposed to change it.


Pinned gitleaks v8.24.2 (sha256 verified against the workflow's literal). All gitleaks
assertions gate on **exit codes**; no invocation whose rc is asserted is piped; all
fixtures live in `$(mktemp -d)` outside the worktree.

| AC | Result | Evidence |
| --- | --- | --- |
| AC1 both halves | **PASS** | Range `871fe6a94~1..871fe6a94`: `origin/main` config → rc=**1**; post-fix config → rc=**0**. Both halves required — the post-fix half alone cannot distinguish "fixed" from "never broken". |
| AC2 real credentials still fire | **PASS** (4/4) | `admin:SuperSecretPassw0rd`, `prod:passw0rdREALLEAK`, `svc:pass-but-longer`, `postgresql://root:hunter2` → all rc=**1**. |
| AC3 placeholders quiet | **PASS** (3/3) | `user:pass` (the only discriminating row) → rc=**0**; `<user>:<pw>`, `user:password` → rc=**0**. |
| AC2/AC3 extra (added beyond plan) | **PASS**, after correcting a bad fixture | `user:pw`, `user:passwd` → rc=**0**. My first near-miss probes used `svc:` as the user — those fire because `svc` fails the allowlist's USER-side alternation, **not** because of the `@` anchor, and they pass identically with the anchor deleted. Re-done with `user:pass-but-longer` / `user:pwsecret123` / `user:passwdX9y` / `user:secretly` → rc=**1**, which mutation-testing confirms go silent when the `@` is removed. |
| AC4 Phase 2 isolation | **PASS** | Scratch clone, `main` clean, synthetic non-allowlisted DSN on `refs/remotes/origin/6706ac`. **Same post-fix config both halves**: bare → rc=**1**, `--log-opts="--no-merges HEAD"` → rc=**0**. Ref deleted. |
| AC5 rule identity | **PASS** | `grep -c '^id = "database-url-with-password"'` → **1**. |
| AC6 ack gate not tripped | **PASS** | Element-wise set diff of `parse-gitleaks-allowlists.mjs` output, base vs HEAD: 18 vs 18, **0 added / 0 removed**. (Whole-line `comm` would have been a weaker check — the parser emits one JSON line.) `Allowlist-Widened-By:` trailer confirmed via `git interpret-trailers --parse`. |
| AC7 workflow validity | **PASS, with a recorded caveat** | `bash -n` on both modified `run:` bodies → rc=0. `actionlint` reports **one pre-existing** `SC2016:info` finding, byte-identical on `origin/main` (line 211 there → 230 here, shifted only by added comment lines). It sits in the untouched `waiver-discipline` job where the single quotes are intentionally correct (a regex that must not expand). **No new finding introduced**; the AC's literal "actionlint passes" was never true on main either. |
| AC8 cron diagnosability | **PASS** | `schedule` step invocation contains `-v`; verified `-v` prints `RuleID`/`File`/`Line`/`Commit`/`Fingerprint` (observed in the Phase 0 RED capture). |
| AC9 secret-scan green on PR | pending CI | Asserted by the PR's own required contexts. |
| AC10 runbook updated | **PASS** | All four events present in the ref-scope table; `git branch -r --contains` attribution step present; un-PR'd-branch trade-off and merge-commit blind spot both recorded; in-page anchor resolves. |
| AC11 stale wording removed | **PASS** | `grep -c 'full tree' .github/workflows/secret-scan.yml` → **0**. |
| AC12 PR body | done at ship | `Closes #6706`, references #3888, links #6721. |

### Deviations from the plan, and why

1. **Plan-quoted commit counts were stale.** Plan H2/H3 recorded 3228 → 3094; re-measured
   today the same procedure gives **3241 → 3097** (`main` grew 13 commits since the plan was
   written). The mechanism is unchanged and the verdicts identical. The runbook therefore
   documents the *two-run comparison* rather than fixed totals, so it cannot rot the same way.
2. **The merge-commit byte measurement was imprecisely phrased.** Plan H9 says `git log -p -1`
   "emits 0 bytes" for a merge; it actually emits **302** bytes — the commit header, with zero
   patch beneath. The underlying claim (0 *patch* bytes vs 10901) is correct and was
   re-verified. Both the runbook and #6721 state the patch-portion command explicitly, since
   an operator running the literal command would otherwise see 302 and think the doc was wrong.
3. **Scope added, in-file:** the runbook's existing `### Placeholder-regex allowlist` section
   documented this exact allowlist without the new branches. Left alone it would have been
   stale on merge — the same defect class as the "full tree" wording AC11 exists to catch.
   Updated in the same edit cycle.

### Post-implementation addition: a committed guard for the `@` anchor

The plan shipped no automated regression test for the allowlist widening — its
safety rested on the `@` anchor, asserted only in prose. That is the
"prose-only guard" defect class: nothing would catch a future widening that
drops the anchor.

Added T6/T7 to `plugins/soleur/test/gitleaks-rules.test.sh` (10 assertions,
6/6 → 16/16). Mutation-verified in a sandbox mirror, tracked file untouched:

| Run | Result |
| --- | --- |
| Control (unmutated `.gitleaks.toml`) | **16/16 pass** |
| Mutant (trailing `@` deleted from the allowlist regex) | **12/16 — exactly the 4 T7 rows RED** |

T6 correctly stays green under the mutation (removing the anchor does not stop
placeholders being allowlisted), which is what makes T7 the load-bearing half.

**The fixture choice is the whole test.** `svc:pass-but-longer` fires under both
the real and mutated config — it fails the USER-side alternation, so it is
vacuous w.r.t. the anchor. Only a user in `user|USER|postgres|<...>` exercises
the password branch. This is recorded in a comment on T7 so the next editor does
not "simplify" the fixtures back into vacuity.

---

## Multi-agent review outcomes

All findings fixed inline (each ≤30 lines / ≤2 files — the cost-of-filing gate
requires inline). **Filed as scope-out: 0.**

### A1 (architecture, HIGH) — blocking scope and breadth are independent axes

The PR collapsed them: it narrowed `push:main`'s *verdict* scope and, in doing so,
silently dropped all-refs *breadth* too, pushing un-PR'd-branch detection from
minutes to the weekly cron. Restoring breadth costs **exactly the walk that already
ran before this PR**, so "cost/benefit" could not justify dropping it.

Added a second `push:main` step: all-refs, `-v`, `|| echo ::warning`, never blocks.
Main's required verdict stays scoped (the actual #6706 fix) while cross-branch
findings surface in minutes. This is also what the issue itself asked for — *"if
that breadth is intentional the failure should at least name the owning branch"*.

### A2 (architecture) — the `jq` rejection rationale was a strawman

Plan §3.3 rejected attribution because "a failing `jq` under `pipefail` replaces
the scan verdict with jq's exit status". True of *one implementation* (piping
gitleaks into jq) — `--report-path` writes a file and needs no pipe at all. The
conclusion (don't build the loop) still stands on complexity grounds; the stated
reason did not support it. The advisory step above achieves the goal with `|| echo`
and no parsing.

### A3 (architecture) — `--no-merges` is a documented no-op at a distance

The runbook said it; the workflow did not, so a reader at the call site would infer
merge-commit coverage. Worse, #6721 direction 1 proposes adding `-m`/`--cc`, which
would make the flag an active contradiction. Comment added at the call site.

### Q1 (quality, BLOCKING) — the sweep falsified three claims this PR authored

Adding the advisory step made the ref-scope table, the trade-off paragraph, and the
workflow's own trigger header describe a one-invocation world. All three re-derived.
This is the review catching me doing exactly what AC11 exists to prevent — shipping
prose that documents behavior the code no longer has.

### Q2 (quality) — same-file contradiction in the alert decision tree

`## When an alert fires` routes `push:main / weekly cron` straight to *ROTATE NOW /
assume exfil*, but the new triage section says an unmerged-branch finding is not a
`main` incident. Both all-refs surfaces can report a commit that never merged.
Added an explicit "resolve the owning ref BEFORE entering the tree" step.

### Q3 (quality) — "a few hundred more commits" overstated by ~2x

Measured delta is ~144–178, not "a few hundred". Magnitude dropped entirely; the
paragraph already tells readers to compare the two runs rather than trust a number.

### Q4 (quality) — trigger header omitted `merge_group`

Pre-existing omission in a block this PR edited. Added.

### H1 (git-history) — the acute symptom self-resolved mid-PR

`feat-one-shot-6500-6466-inngest-cutover-blockers` is now **gone from origin**;
no remote ref contains `871fe6a94`. `secret-scan` on `main` went green at 19:12Z
and 19:33Z without this PR — exactly the incidental resolution the issue predicted.
This PR fixes the **class**, not a currently-red gate. See the self-inflicted
recurrence below, which is the better evidence the class is live.

### S1 (security, P1) — Phase 1 REVERTED: the widening silenced real credentials

`security-sentinel` demonstrated that adding `pass|passwd|pw` to the placeholder
alternation **silences genuine credentials**, and I reproduced it independently:

| Fixture | pre-PR | with widening |
| --- | --- | --- |
| `postgres://user:pass@<realsecret>@db.prod.example.com/appdb` | **rc=1** detected | **rc=0 silenced** |
| `postgres://user:pw@<realsecret>@rds.amazonaws.com` | **rc=1** detected | **rc=0 silenced** |
| `postgres://postgres:pass@word2026@db.prod.internal` | **rc=1** detected | **rc=0 silenced** |

Mechanism: the rule's password class `[^@/\s]+` stops at the FIRST `@` while real
URL parsers take userinfo to the LAST one, and the allowlist is an unanchored
*search* against the rule's match — so `user:pass@<secret>@host` contains
`postgres://user:pass@` and allowlists itself. My `@`-anchor claim was true of the
string but not of the *credential*, which is the thing that matters.

**The whole of Phase 1 is reverted — `.gitleaks.toml` is now byte-identical to
`origin/main`.** Two independent facts made the widening unnecessary as well as
harmful, both measured:

1. `vector.toml` already documents the shape as `postgres://<user>:<pw>@host`,
   which the pre-existing `<[^>]+>` branch covers. The current tree scans **rc=0
   under `origin/main`'s own config** — no widening required.
2. The flagged commit's branch (`feat-one-shot-6500-6466-*`) has been **deleted
   from origin**; no remote ref contains `871fe6a94`, so the historical finding is
   unreachable. `secret-scan` on `main` went green at 19:12Z/19:33Z without this PR.

So the PR now ships **only** the ref-scope fix — which is the actual class defect
and the durable half of #6706. The narrow pre-existing multi-`@` gap is filed as
**#6723** (p2, `type/security`) rather than bundled: it is a discovered defect in a
different subsystem and changing the rule's match semantics has repo-wide blast
radius.

### T1 (test-design) — the guard sampled one point per dimension

The first version of T6/T7 varied the password token richly but held **user, host,
scheme, and password length constant**, so four mutations passed 16/16 while
silencing real credentials. Rewritten to vary exactly one dimension per row, plus
T8 for allowlist arity. Re-verified by mutation, sandbox copies, tracked file never
touched:

| Mutation | before | after |
| --- | --- | --- |
| pin rule host to `.example.com` | 16/16 green (blind) | **16/17 — RED** |
| drop `postgresql://` from the scheme | 16/16 green (blind) | **16/17 — RED** |
| password length floor `{8,}` | 16/16 green (blind) | **16/17 — RED** |
| append a 2nd allowlist entry (M1) | 16/16 green (blind) | **15/17 — RED** (behavioural + T8) |
| control | 16/16 | **17/17** |

M1 was the most plausible real regression — `.gitleaks.toml` already carries a
Supabase-CLI loopback carve-out, so "generalising" it writes exactly that line. It
is now caught twice.
