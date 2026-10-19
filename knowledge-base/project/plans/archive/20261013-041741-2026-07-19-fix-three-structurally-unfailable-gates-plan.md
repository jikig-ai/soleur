---
title: "fix: three structurally-unfailable gates (secret-scan merge blindness, DSN allowlist bypass, /ship review-evidence Signal 1)"
date: 2026-07-19
type: fix
issues: [6721, 6723, 6724]
branch: feat-one-shot-6721-6723-6724-gitleaks-scan-gaps-ship-signal
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: three structurally-unfailable gates

## Enhancement Summary

**Deepened on:** 2026-07-19
**Agents:** security-sentinel, test-design-reviewer, architecture-strategist, git-history-analyzer

### Key improvements

1. **The issue's own "verified" candidate fix for #6723 is insufficient and introduces a regression.** Its `<[^>]+>` allowlist branch composes with the newly-permitted `@`/`:` so a whole real credential fits inside a "placeholder" — three shapes that are **detected today** would be **silenced**. Hardened to `<[^>@:]+>`; re-measured independently.
2. **The proposed path-allowlist entry was unanchored** — any parent directory laundered a real DSN into it. Anchored `^…$`.
3. **A zero-finding `/review` makes no commit**, so the planned trailer would never land and the merge gate would **deadlock the pipeline on exactly the branches where review went cleanest.** Fixed with `--allow-empty` + a mechanical script rather than a second prose convention (the existing prose convention has a measured compliance rate of zero).
4. **A third production copy of the defective grep** exists at `.openhands/hooks/pre-merge-rebase.sh` — named by neither the issue nor plan v1, and surfaced independently by two agents.
5. **The v1 mutation proof for #6721 was itself vacuous** — it hand-mirrored the workflow's log-opts instead of reading the YAML, so deleting `-m` left it green. Now extracts from the artifact.
6. **AC11 verified the wrong walk** — the old merge-blind one, not the `-m --all` walk the PR ships across 52 merges.
7. **The branch-scoped fix goes re-vacuous after the hook's own auto-sync** (it merges `origin/main` in and pushes, and Check 1 runs before the fetch).
8. **The PR-time window** is uncovered too, not just the cron — the more common real-world shape.

### New considerations discovered

- The `paths` array has **no** guard at all (T8 covers `regexes` arity only), and no path widening is testable through the current fixture harness.
- The `allowlist-diff` ack gate will trip on the `paths` change, and is **blind** to the `regexes` widening (#3888).
- Two open User-Challenges are recorded in `specs/<branch>/decision-challenges.md` — a recommendation to split #6723 into its own PR (contradicts the operator's "bundle them" direction, so surfaced rather than applied), and an unmeasured `.gitleaksignore` alternative.
- One review verdict was **rejected**: `git-history-analyzer` marked the `#6706` citation CONTRADICTS after only running `gh pr view`. `#6706` is a real closed **issue** — the agent hit the PR-vs-issue disambiguation trap the plan skill documents. The citation stands.

## Overview

Three OPEN, pre-existing defects that share one shape: **a gate that structurally cannot fail**. Each certifies existence or placement rather than the property it is named for, so mutating the guarded property leaves the gate green.

| Issue | Gate | What it certifies | What it is named for |
|---|---|---|---|
| #6721 | `secret-scan` gitleaks jobs | content reachable via `git log -p` | all content on the scanned refs |
| #6723 | `database-url-with-password` allowlist | a placeholder prefix appears *somewhere* in the match | the whole credential is a placeholder |
| #6724 | `/ship` review-evidence Signal 1 | a tracked file exists in `todos/` | `/review` ran **on this branch** |

Two of the three (#6721, #6723) share `.gitleaks.toml` / `secret-scan.yml`. All three demand a **mutation proof** — a test that goes RED when the guarded property is absent. A green check that stays green under mutation is not acceptable evidence, because that is precisely the defect being fixed.

**Every claim below is measured, not inferred.** Measurements were run locally against the pinned `gitleaks 8.24.2` (`/home/jean/.local/bin/gitleaks`, version-confirmed) on this worktree. Raw commands and outputs are reproduced per phase.

## Research Reconciliation — Issue Claims vs. Measured Reality

| Issue claim | Measured reality | Plan response |
|---|---|---|
| #6721: "`-m` expands the walk substantially" | **False for this repo.** Same-breadth marginal cost: `--all` 16.11s → `-m --all` 18.98s (+2.9s, +18%) on a **weekly** cron. `HEAD` 15.81s → `-m HEAD` 16.35s (+0.5s). | Adopt direction 1 (`-m`) **and** direction 2. The cost objection that motivated "direction 2 only" does not hold. |
| #6721: "`--log-opts="-m --first-parent"` (or `--cc`)" — offered as equivalent | **`--cc` is a silent no-op.** Synthetic merge-exclusive secret: `--cc` → **rc=0 (MISSED)** despite `git log -p --cc` emitting 195 patch bytes. gitleaks' diff parser does not consume combined-diff (`@@@`) format. `-m` → **rc=1 (DETECTED)**. | Mandate `-m`. Document `--cc` as a trap in the workflow comment — shipping `--cc` would itself be a new structurally-unfailable gate. |
| #6721: direction 2 is "likely the cheapest real mitigation" | True on cost (`gitleaks dir .` = 6.11s) but it **only** covers content still on the tree. Direction 1 additionally covers merge-introduced content later removed. | Take both — they cover disjoint cases and together cost ~9s/week. |
| #6721: framed as merge commits **on main** (cron is the fix surface) | **Understated.** The PR job is uncovered too: a feature branch merging `origin/main` with a hand-resolved conflict yields rc=0 under today's `--no-merges BASE..HEAD`. That is the *more common* shape, and fixing only the cron leaves it on main for up to 7 days. | Extend scope to the PR / merge_group jobs (Phase 1.5, AC6a-AC6c). |
| #6723: candidate fix "measured against the placeholder/redaction shapes" | Reproduced — but the corpus was built from the **known** bypass shape only. All 5 T6 shapes stay quiet, all 5 T7 rows fire, all 4 multi-`@` shapes flip silenced → detected. | Necessary but not sufficient — see next row. |
| #6723: candidate fix is correct as written | **FALSE — the candidate is insufficient AND introduces a regression.** Its `<[^>]+>` branch composes with the newly-permitted `@`/`:` so an entire real credential fits inside a "placeholder": `postgres://user:<admin:R3alPassw0rd@prod.db.internal>@x.com` is **detected today (rc=1)** and **silenced by the candidate (rc=0)**. Same defect class that got #6706 reverted, via a different branch. | **Do not apply as written.** Ship the hardened `<[^>@:]+>` form; add the three regression fixtures as RED-on-mutation rows. |
| #6723: the proposed path-allowlist entry is safe | **FALSE — unanchored.** `evil/plugins/soleur/skills/review/SKILL.md` with a real DSN is silenced. Any parent directory launders. | Anchor it `^…$` (measured: laundering path flips back to detected). |
| #6723: candidate fix is safe to apply | **Incomplete.** Repo-wide diff surfaced exactly **one** new finding: `plugins/soleur/skills/review/SKILL.md:977`. A full main-ancestry history scan under the candidate config returns **rc=1** on commit `48b8bc4a5` (PR #6717) — the fix as-written **reddens `push:main` and the weekly cron retroactively**. | Bundle a path-allowlist mitigation (verified rc=0). See Phase 2. |
| #6724: gate lives in `/ship` Phase 1.5 + Phase 5.5 | **Understated.** The load-bearing *mechanical* gate is `.claude/hooks/pre-merge-rebase.sh:109`, a PreToolUse hook that returns `permissionDecision: "deny"` on `gh pr merge`. It carries the identical branch-unscoped grep and is **not named in the issue**. | Extend scope to the hook + its two test files. A SKILL.md-only fix would leave the real merge blocker vacuous — repeating the defect class. |
| #6724: Signal 2 greps `review:` | Ship SKILL.md anchors `^[a-f0-9]+ review: `; the hook uses unanchored `review: `. **Silent drift between the two copies of "the same three signals".** | Converge both on one machine-readable trailer (direction 3). |

## User-Brand Impact

**If this lands broken, the user experiences:** a merge gate that blocks every legitimate merge (over-tight review-evidence scoping), or a `secret-scan` job that reddens `main` on every push against a historical commit nobody can fix without a history rewrite — the founder's pipeline stops and the only visible artifact is a red required check with no actionable file at HEAD.

**If this leaks, the user's credentials are exposed via:** a production DSN whose password contains `@` committed to a public repository and silenced by the allowlist (#6723 — measured reachable today), or a credential introduced by a hand-resolved merge conflict that no scan job has ever read (#6721 — measured reachable today, `main` carries 35 merge commits with `allow_merge_commit: true`).

- **Brand-survival threshold:** `single-user incident` — one leaked production credential on a public repo is a brand-survival event, and both #6721 and #6723 are measured-reachable paths to exactly that.

## Open Code-Review Overlap

- **#3321** — `review: add CODEOWNERS coverage for knowledge-base/project/learnings/ subtree`. Mentions `.gitleaks.toml`. **Disposition: Acknowledge.** Different concern (CODEOWNERS ownership of the learnings subtree, not gitleaks rule semantics). This plan does not touch CODEOWNERS and does not close #3321.

No other open `code-review` issue references any file in this plan's edit list (61 open issues scanned).

## Files to Edit

- `.gitleaks.toml` — `database-url-with-password`: widen rule regex to last `@`; fully anchor the allowlist entry; add one path-allowlist entry for the self-documenting review skill file.
- `.github/workflows/secret-scan.yml` — cron job: add `-m --all` log-opts; add a `gitleaks dir` full-tree step; correct the `push:main` comment that currently cites #6721 as unfixed.
- `plugins/soleur/test/gitleaks-rules.test.sh` — extend T7 with multi-`@` rows; add T9 anchor-mutation guard.
- `plugins/soleur/skills/ship/SKILL.md` — Phase 1.5 Signal 1 branch-scoping; Signal 2 trailer; Phase 5.5 pointer.
- `.claude/hooks/pre-merge-rebase.sh` — Check 1 branch-scoping; move `git fetch origin main` ABOVE the gate; Check 2 trailer.
- **`.openhands/hooks/pre-merge-rebase.sh` — THIRD production copy of the identical defective grep (deepen finding; in neither the issue nor plan v1).** Tracked file, byte-identical `REVIEW_TODOS=$(grep -rl "code-review" "$WORK_DIR/todos/" ...)`. Independently surfaced by two review agents and verified directly. Fixing only `.claude/hooks/` reproduces this plan's own Sharp Edge one directory over.
- `.claude/hooks/pre-merge-rebase.test.sh` — give `init_git_repo` an optional bare `origin` with `main` pushed; fix T2; add vacuity + post-auto-sync regression cases.
- `.claude/hooks/pre-merge-rebase-headless.test.sh` — same.
- **`test/pre-merge-rebase.test.ts`** — bun-shard suite with 9 `addReviewEvidence` call sites. It survives branch-scoping only because Signal 2 catches it (coincidence, not design); if Phase 3.3 drops the legacy alternatives, all 9 go red at once.
- `plugins/soleur/skills/review/SKILL.md` — emit the review-evidence trailer at the fix-commit step.
- `knowledge-base/engineering/operations/secret-scanning.md` — document merge-commit coverage, the `--cc` trap, and the new rule semantics.

## Files to Create

- `plugins/soleur/test/gitleaks-merge-commit.test.sh` — synthetic merge-exclusive-secret mutation proof for #6721.

## Hypotheses

Not a network/SSH-class change — the network-outage checklist does not apply. No hypothesis table is load-bearing here because every claim in this plan was **measured**, not reasoned. Where a measurement was not obtainable it is stated as UNKNOWN rather than inferred (see Phase 3 open item on trailer adoption on in-flight branches).

## Implementation Phases

Phases are ordered so every **contract change precedes its consumer**.

### Phase 0 — Preconditions (verify, do not assume)

```bash
gitleaks version                        # must print 8.24.2
git rev-parse --abbrev-ref HEAD         # must NOT be main
```

Re-run the three baseline measurements below and confirm they still hold at HEAD before editing anything. If any diverges, STOP and reconcile — the plan's premises are measurement-bound.

```bash
# P0.1  #6723 bypass is live (expect: rc=0, silenced)
d=$(mktemp -d); printf 'postgres://user:password@Xq7vNp2LmWd4@db.prod.example.com/appdb\n' > "$d/f.conf"
gitleaks dir "$d" --no-banner --exit-code 1 -c .gitleaks.toml; echo "rc=$? (expect 0)"

# P0.2  #6724 Signal 1 is vacuous on this branch (expect: non-empty)
grep -rl "code-review" todos/ | head -1

# P0.3  #6724 branch-scoped variant is empty on this branch (expect: no output)
git diff --name-only origin/main...HEAD -- todos/ | xargs -r grep -l "code-review"
```

### Phase 1 — #6721: merge-commit coverage (contract: what the cron scans)

**1.1 — Land the mutation proof FIRST (RED).** Create `plugins/soleur/test/gitleaks-merge-commit.test.sh`. It builds a throwaway repo in `mktemp -d`, produces a genuine 2-parent merge whose **hand-resolved tree contains a synthesized DSN present in neither parent**, then asserts detection per log-opts variant. Reference harness (already executed; outputs below are real):

| `--log-opts` | rc | verdict |
|---|---|---|
| `--no-merges HEAD` | 0 | MISSED (today's PR/merge_group/push shape) |
| `HEAD` | 0 | MISSED |
| `--cc HEAD` | **0** | **MISSED — silent no-op** |
| `-m --first-parent HEAD` | 1 | DETECTED |
| `-m HEAD` | 1 | DETECTED |
| `gitleaks dir .` | 1 | DETECTED (content still on tree) |

Patch-byte measurement on that merge: plain `0`, `-m` `600`, `--cc` `195`. **`--cc` emits patch bytes and still detects nothing** — this is the load-bearing observation; assert it explicitly so a future edit cannot "simplify" `-m` into `--cc`.

The test MUST assert BOTH halves: `--no-merges` → rc=0 (the bug) and `-m` → rc=1 (the fix). A one-sided must-fire test passes vacuously if the scanner is degraded — the same trap `gitleaks-rules.test.sh` T7 exists to prevent (see its header comment).

**1.2 — Fix the cron.** In the `Scan (full history, weekly cron)` step, change:

```
./gitleaks git --redact --no-banner --exit-code 1 -v
```

to carry `--log-opts="-m --all"`.

**`--all` is load-bearing and MUST NOT be dropped to bare `-m`.** `git log` with no revision defaults to `HEAD`; `--log-opts="-m"` would silently narrow the cron's deliberate all-refs breadth. Measured: `--all` reaches 3303 commits / 52 merges; `HEAD` reaches 3146 / 35. Narrowing breadth here would regress #6706's cron design.

**1.3 — Add the full-tree complement (direction 2).** Add a `gitleaks dir .` step to the cron job. Rationale for taking both directions rather than the issue's favoured direction-2-only:

- Direction 1 (`-m`) covers merge-introduced content **anywhere in history, including content later removed** — direction 2 structurally cannot.
- Direction 2 (`gitleaks dir`) covers merge-introduced content **currently on the tree regardless of which commit introduced it** — cheaper and parser-independent, so it does not depend on gitleaks' diff parser behaving.
- Combined marginal cost on a **weekly** job: ~+9s. The cost argument for choosing one does not survive measurement.
- **This divergence from the issue's stated preference MUST be stated in the PR body**, per the issue's own instruction.

**1.4 — Correct the stale comment.** The `push:main` step comment currently says `--no-merges` is a no-op "— #6721" and that "#6721 direction 1 would invert it". Update it to reflect the shipped state and to record the `--cc` trap.

**1.5 — Close the PR-time window (deepen-plan finding — NOT in the issue).**

The issue frames #6721 around merge commits **on main**. Measurement shows the more common real-world shape is also uncovered: a developer merges `origin/main` into their feature branch, hand-resolves a conflict, and introduces a secret in the resolution. Synthetic PR-shape range (`BASE..HEAD` spanning such a merge), current config:

| `--log-opts` | rc | verdict |
|---|---|---|
| `--no-merges BASE..HEAD` (today's PR job) | 0 | **MISSED** |
| `BASE..HEAD` | 0 | MISSED |
| `-m BASE..HEAD` | 1 | detected |
| `gitleaks dir .` on the PR checkout | 1 | detected |

So today's PR job — the gate that runs on *every* PR — cannot see conflict-resolution secrets. Fixing only the weekly cron leaves that content on main for **up to seven days**.

**Recommended remedy for the PR / merge_group jobs: add a `gitleaks dir .` step, not `-m`.** Rationale: `gitleaks dir` catches the resolution content at ~6s with no coupling to main's history. Adding `-m` to a PR range makes the merge diff against each parent, which *may* pull content that main already carried into the PR's scanned diff — reddening a PR for content it did not introduce, and coupling every PR's gate to main being clean.

**UNKNOWN — measure at `/work` before choosing.** An attempt to demonstrate that `-m` coupling was **inconclusive** (both the `--no-merges` and `-m` arms returned rc=0 on the constructed fixture, meaning the fixture did not reach the intended state — it did not show coupling, and it did not rule it out). Do **not** record this as "no coupling". Build the fixture deliberately (clean merge of a main commit that carries a known finding, then scan the PR range both ways) and let the measurement decide `-m` vs `gitleaks dir` for the PR job. If the measurement is again inconclusive, ship `gitleaks dir` — it is the option whose failure mode is understood.

**1.6 — Add `-m --all` to the ADVISORY all-refs sweep (cheap latency fix).** The `Sweep (all refs, advisory — never blocks)` step passes *no* `--log-opts`, so it too is merge-blind. It is `|| echo`-guarded and **structurally cannot redden main**, so adding `-m --all` there is free of blocking risk and drops detection latency from ≤7 days to minutes. Cost: +2.9s on a step that already runs every push.

**Leave the BLOCKING `push:main` step on `--no-merges`.** Flipping it to `-m` would scan 35 historical merge resolutions that have never been measured under the new rule, and could permanently redden a required check with no tip-fixable remedy. State this trade-off in the workflow comment (Phase 1.4 already edits it).

**Honest scope statement (must appear in the plan and the PR body):** PR, merge_group, and blocking `push:main` remain merge-blind by design. Residual exposure is bounded by the advisory sweep (per-push, non-blocking), the new `gitleaks dir` steps, and the cron (weekly, blocking). Phase 1 is *not* a complete closure of merge-blindness and must not be described as one.

Direction 3 (enforce linear history) is **out of scope** — largest workflow impact, and it is the issue's own last-resort option. Record as a `Re-evaluate when` note rather than silently dropping it.

### Phase 2 — #6723: DSN allowlist bypass (contract: what the rule matches)

**2.1 — Land the mutation proof FIRST (RED).** Extend `plugins/soleur/test/gitleaks-rules.test.sh` T7 with multi-`@` rows. These MUST fail against today's config:

```
multi-at-password  | postgres://user:password@<realpw>@db.prod.example.com
multi-at-user      | postgres://<anything>:password@<realpw>@db.prod.example.com
multi-at-secret    | postgres://user:secret@<realpw>@db.example.com
multi-at-redacted  | postgres://user:***@<realpw>@db.example.com
```

All four measured **silenced (no rule fires)** under the current config and **detected** under the candidate. Per this file's existing convention, assemble every DSN at runtime from split literals — a contiguous credential-shaped literal in this file trips the repo's own scan (the file is deliberately not in the path allowlist).

**2.2 — Apply the rule + allowlist fix.**

> **The issue's candidate fix is INSUFFICIENT and introduces a REGRESSION. Do not apply it as written.** Surfaced by adversarial review and independently re-measured. See "P0 — the candidate fix must be hardened" below. Ship the hardened form:

```toml
regex   = '''postgres(?:ql)?://[^:/\s]+:[^/\s]+@[A-Za-z0-9.\-]+'''
regexes = ['''^postgres(?:ql)?://(?:USER|user|postgres|<[^>@:]+>):(?:PASSWORD|password|secret|<[^>@:]+>|\*+)@[A-Za-z0-9.\-]+$''']
```

**P0 — the candidate fix must be hardened (`<[^>]+>` → `<[^>@:]+>`).**

Widening the password class to `[^/\s]+` lets `@` and `:` live inside the password. The allowlist's `<[^>]+>` placeholder branch *already* permits `@` and `:` inside the brackets. Composed, an entire real `user:password@host` fits inside what the allowlist certifies as "a placeholder". Independently measured (rc: 1 = detected, 0 = silenced):

| fixture | current | issue's candidate | hardened |
|---|---|---|---|
| `postgres://user:<admin:R3alPassw0rd@prod.db.internal>@x.com` | **1** | **0 — REGRESSION** | **1** |
| `postgres://user:<R3alPassw0rd@prod-db.internal.corp>@localhost` | **1** | **0 — REGRESSION** | **1** |
| `postgres://user:<admin:R3alPassw0rd@prod.db.internal>@x.com:5432/appdb` | **1** | **0 — REGRESSION** | **1** |

These shapes are **detected today** and would be **silenced** by the issue's candidate — the fix would make the gate strictly worse for them. This is the same defect class that got the #6706 widening reverted, re-entering through a different allowlist branch.

Hardening preserves everything else (re-measured): all 4 placeholder shapes stay quiet (`<user>:<pw>`, `USER:PASSWORD`, `user:***`, `user:password`), and both #6723 multi-`@` bypasses still flip silenced → detected.

**Why the `$` anchor does not save it:** allowlist `regexes` match the *Secret*, and with no `secretGroup` the Secret is the whole match — which always terminates at the host class `[A-Za-z0-9.\-]+`. So `:5432/appdb` is simply outside the string `$` anchors. `$` means "end of match", never "end of DSN". The anchors are still load-bearing (a no-anchor variant silences shapes the anchored one catches) — they are just insufficient alone.

**This is the single most important finding of the planning session:** the issue body called its candidate "verified", and it is verified *against the known bypass shape only*. Its corpus contains no fixture exercising the `<[^>]+>` branch against the newly-permitted `@` — precisely the surface the widening opens. The T7/T9 rows MUST include these three lines as RED-on-mutation cases, or the test battery inherits the same blind spot.

Measured full matrix (current → candidate):

| fixture | current | candidate |
|---|---|---|
| `…user:password@Xq7vNp2LmWd4@db.prod.example.com/appdb` | silenced | **fires** |
| `…<anything>:password@RealS3cretHere@db.prod.example.com` | silenced | **fires** |
| `…user:secret@An0therRealPw@db.example.com` | silenced | **fires** |
| `…user:***@Rea1Secret@db.example.com` | silenced | **fires** |
| T6 ×5 placeholder shapes (`user:password`, `USER:PASSWORD`, `postgres:secret`, `<user>:<pw>`, `user:***`) | quiet | quiet |
| T7 ×5 real-credential rows | fires | fires |
| Supabase loopback `postgres:postgres@127.0.0.1:54322` | fires (path-allowlisted in situ) | unchanged |

**Note the arity constraint:** the fix **modifies** the existing single `regexes` entry — it does not add a second. T8's arity guard (exactly one entry, 2 triple-quote runs) must stay green; confirm rather than assume.

**2.3 — Mitigate the retroactive history regression (mandatory, not optional).**

Repo-wide scan under the candidate config surfaced exactly one new finding:

```
database-url-with-password   plugins/soleur/skills/review/SKILL.md:977
```

That line is the review skill's own bullet **documenting this very bypass** (`postgres://user:pass@<realsecret>@host`), added by PR #6717 in commit `48b8bc4a5`, which is on `main`. Full main-ancestry scan under the candidate config:

```
gitleaks git --config <candidate> --log-opts="--no-merges HEAD" --exit-code 1
→ rc=1, 1 finding, commit 48b8bc4a5
```

So the fix as-written **turns `push:main` and the weekly cron red on a historical commit**.

**A line-level `# gitleaks:allow` waiver does NOT work here.** History scans read the *old blob*, which has no waiver comment. The review skill states this trap in its own words at the cited line: *"because gitleaks scans the commit RANGE, fixing such a literal at the tip does NOT clear it — that is always a history rewrite."*

**The path allowlist is the only tip-fixable mitigation**, because a path predicate matches identically in history. Add to the `database-url-with-password` rule's `paths` array:

```
'''^plugins/soleur/skills/review/SKILL\.md$'''
```

**The leading `^` is load-bearing — P0.** Without it gitleaks matches the entry as a substring of the scan-root-relative path, so **any parent directory launders**. Measured with identical real-DSN content:

| path | unanchored entry | anchored entry |
|---|---|---|
| `evil/plugins/soleur/skills/review/SKILL.md` | **0 — SILENCED** | **1 — detected** |
| `plugins/soleur/skills/review/SKILL.md.bak` | 1 | 1 |
| `plugins/soleur/skills/review/xSKILL.md` | 1 | 1 |

Suffix rename-laundering (`.bak`, `xSKILL`) does not work, but a parent directory does. The carve-out is justified as "exactly one file" — the `^` anchor is what makes that sentence true, and it is the same discipline T9 demands of the `regexes` entry.

Verified: main-ancestry scan under the mitigated config → **rc=0, 0 findings**; working-tree scan returns to parity with today.

Scope cost and compensating controls (state these in the config comment, per the file's existing convention): this blinds **one file** to **one rule**. That file is skill prose, never a credential carrier. `lint-fixture-content`, GitHub push protection, and CODEOWNERS on `.gitleaks.toml` all remain live.

**2.4 — Add an anchor-mutation guard (T9).** T7 rows test *behaviour*; none can see the `^`/`$` anchors being removed while behaviour on sampled rows coincidentally survives. Add a guard asserting the allowlist entry is anchored at **both** ends. Removing either anchor must go RED.

### Phase 3 — #6724: review-evidence signals (contract: the trailer, then its consumers)

**Contract first, consumers second** — Phase 3.1 must land before 3.2/3.3, or the broadened signal is dead code.

**3.1 — Emit a machine-readable marker (direction 3).** `/review` currently emits only a *conversational* `## Review Phase Complete` marker — nothing durable, nothing greppable. Direction 3's root cause is real and measured: review fixes land as `fix(scope):` / `test(scope):`, which Signal 2's `review: ` prefix does not match; that is why Signal 2 returned empty on #6717 **despite a genuine 5-agent review**.

Broadening Signal 2 to match `fix(`/`test(` is rejected — every branch carries those, which would recreate the "cannot fail" shape in a new place.

Instead, have `/review` write a **commit trailer** on the commit it already makes:

```
Reviewed-By-Soleur: <change-class>/<agent-count>
```

Branch-scoped by construction (`git log origin/main..HEAD`). Signal 2 greps the trailer; legacy patterns stay as alternatives for in-flight branches. Squash semantics are **outside the trust path** — both consumers read the feature branch and the hook is a PreToolUse gate on `gh pr merge`, so it runs before any squash commit exists. (Do not assert squash-body survival; it depends on the mutable `squash_merge_commit_message` repo setting and nothing here needs it.)

**P0 — a zero-finding `/review` produces NO commit, so the trailer never lands and the gate denies a genuinely-reviewed branch.** Traced through `plugins/soleur/skills/review/SKILL.md`:

- **Pipeline mode** (`one-shot`/`work`): the §6 Exit Gate — which contains the commit step — is explicitly *skipped* ("If the conversation contains `skill: soleur:work` output … skip the exit gate"). The only commits are §5's per-finding `review: <summary> (P<N>)` fixes.
- **Zero findings ⇒ no fix commits ⇒ no commit at all ⇒ no trailer.**
- **Direct mode:** §6 says "If there are no local changes, skip the commit (**this is the expected case** — review's primary output is GitHub issues, which are remote-only)."

After Phase 3.2, on a clean-review branch all three signals are empty → `pre-merge-rebase.sh` returns `deny`, and that hook has **no escape hatch**. Ship's interactive "Skip review" does not help — the hook never consults ship. Ship's own text already names this case: *"this also covers zero-finding reviews where review ran cleanly."* Shipping Phase 3 without this fix would **deadlock the merge pipeline on exactly the branches where review went cleanest**.

**Required fix — mechanical, not prose.** The existing prose convention in this same file (`review: <summary> (P<N>)`) has a **measured compliance rate of zero** — that is why Signal 2 missed on #6717. Adding a second prose convention and hanging a `deny` gate on it repeats the plan's own Sharp Edge ("the prose gate and the mechanical gate are different artifacts"). So:

1. Add `plugins/soleur/skills/review/scripts/emit-review-trailer.sh <change-class> <agent-count>` which performs:
   `git commit --allow-empty -m "review: <N> findings (<change-class>)" -m "Reviewed-By-Soleur: <change-class>/<agent-count>"`
   `--allow-empty` is load-bearing — it is the only path yielding a commit on a zero-finding, zero-artifact review.
2. Have SKILL.md **invoke the script** at a step that runs in BOTH modes (the marker-emission step at §3 / end of §5) — never describe a `git commit` line for the agent to reproduce.

**UNKNOWN, to resolve at `/work` time, not to guess now:** whether any currently-in-flight branch would be blocked by a trailer that did not exist when its review ran. Keeping the legacy `review: ` and `refactor: add code review findings` alternatives is the mitigation, but the *set* of affected open branches has not been enumerated. Enumerate before shipping; do not assume it is empty.

**3.2 — Branch-scope Signal 1 (direction 1) in BOTH copies.**

```bash
git diff --name-only origin/main...HEAD -- todos/ | xargs -r grep -l "code-review" | head -1
```

Measured on this branch: current form returns `todos/023-complete-p3-missing-test-coverage-fetch-user-timeline.md` (vacuous pass; 52 files match repo-globally); scoped form returns **empty**. `xargs -r` is load-bearing — without it, empty input runs `grep -l "code-review"` against stdin and hangs.

Apply to **all three** production sites:
- `plugins/soleur/skills/ship/SKILL.md` Phase 1.5 Step 1 (Phase 5.5 references Phase 1.5 by pointer, so it inherits — verify the pointer text stays accurate).
- `.claude/hooks/pre-merge-rebase.sh` Check 1 — **the actual merge blocker.** Issue #6724 does not name this file.
- `.openhands/hooks/pre-merge-rebase.sh` Check 1 — **third copy, byte-identical.** Named by neither the issue nor plan v1.

**P0 — the branch-scoped form goes RE-VACUOUS after the hook's own auto-sync.** `pre-merge-rebase.sh` runs Check 1 **before** its `git fetch origin main`, and then *merges `origin/main` into the feature branch and pushes*. On any second `gh pr merge` attempt the branch now contains every `todos/` file main gained since the fork; against a stale `origin/main` those sit on the HEAD side of `origin/main...HEAD` — and the gate is vacuous again, exactly as before. Two fixes, take both:

1. Move `git fetch origin main` **above** the review-evidence gate (keeping its existing fail-open-on-network-error behaviour).
2. Prefer the commit-scoped form, which excludes ancestors of `origin/main` by construction:

```bash
REVIEW_TODOS=$(git -C "$WORK_DIR" log origin/main..HEAD --no-merges --name-only --pretty=format: -- todos/ 2>/dev/null \
  | sort -u | xargs -r grep -l "code-review" 2>/dev/null | head -1 || true)
```

Add a regression case: branch off main, merge main back in (main carrying a `code-review` todo added post-fork), no review → must still deny. Without that case this P0 ships silently.

**Test-harness corrections (deepen findings).** `init_git_repo` in `.claude/hooks/pre-merge-rebase.test.sh` creates **no remote**, so after branch-scoping `git diff origin/main...HEAD` errors → empty. Consequences: (a) T2 will fail on a rule_id mismatch (it will now deny via `rf-never-skip-qa-review-before-merging` instead of the uncommitted-changes rule) — it needs a bare `origin` with `main` pushed, like T3/T4 already have; (b) the vacuity case must seed `todos/*` containing `code-review` **on main, before the branch point** — the existing `seed_review_evidence` helper commits it *on the feature branch*, which under branch scoping still reads as "review ran" and would make the test fail after the fix rather than before it.

Direction 2 (retire Signal 1 entirely) is rejected: Signal 1 branch-scoped is cheap and still meaningful for genuinely `todos/`-driven reviews; retiring it removes a signal that direction 1 makes correct.

**3.3 — Converge the drifted Signal 2 regex.** Ship SKILL.md anchors `^[a-f0-9]+ review: `; the hook uses unanchored `review: `. Converge both on the same pattern (trailer + legacy alternatives) so "the same three signals" is true rather than aspirational.

**3.4 — Mutation proof.** Add to `.claude/hooks/pre-merge-rebase.test.sh` (and the headless variant) a case that reproduces the issue's own repro:

> branch fresh off `origin/main`, `todos/` populated exactly as the real repo has it, **no review run** → hook MUST return `permissionDecision: "deny"`.

Against today's hook this case **passes the gate** (the bug). After 3.2 it must DENY. Existing cases seed `todos/sample.md` with `code-review` and `git add` it — those seeds now need the file to be **part of the branch diff** to still represent "review ran", so update them deliberately rather than letting them flip meaning silently.

### Phase 4 — Documentation

Update `knowledge-base/engineering/operations/secret-scanning.md`. The file already carries the exact sections this change falsifies — update each by **content anchor**, not line number:

- **`## Ref scope per event: which commits each trigger actually scans`** — the table currently lists `--no-merges` for `pull_request`, `merge_group`, and `push` (main), and the cron with no log-opts. Update every row this plan changes, and add the new `gitleaks dir` steps as their own rows so the table stays the single source of truth for "what each trigger actually scans".
- **`**Blind spot: merge-commit-exclusive content.**`** — this paragraph currently documents #6721 as an open blind spot ("`gitleaks git` drives `git log -p` without `-m`/`--cc`, so a merge commit contributes **no** patch content to any…"). Rewrite it as *closed*, and replace it with the `--cc` trap warning: `--cc` emits patch bytes that gitleaks silently ignores, so it must never be substituted for `-m`. Include the measured rc table.
- **`### Placeholder-regex allowlist — database-url-with-password`** — update to the anchored `^…$` semantics and the widened password class, and state explicitly that the allowlist now requires the **whole** match to be a placeholder rather than merely containing one.
- **`### Allowlist semantics — read this carefully`** — add the path-allowlist carve-out for `plugins/soleur/skills/review/SKILL.md` with its rationale (self-documenting prose; a line waiver cannot clear history; path predicates match identically in history).
- **`## Author-Side Pitfalls`** — add the `--cc` trap and the "a line-level waiver cannot clear a history finding" pitfall alongside the existing entries.

## Acceptance Criteria

### Pre-merge (PR)

**#6721**

- AC1 — `plugins/soleur/test/gitleaks-merge-commit.test.sh` exists and exits 0.
- AC2 — Mutation: reverting the cron step to drop `-m` makes AC1's suite go **RED**.

  **The v1 form of this AC was vacuous** (deepen finding). The test built its own repo and hand-wrote the log-opts strings, so nothing read `.github/workflows/secret-scan.yml` — deleting `-m` from the workflow left the suite fully green. The test MUST extract the log-opts from the YAML and drive the assertion with the extracted value:

  ```bash
  CRON_OPTS=$(awk '/name: Scan \(full history, weekly cron\)/{f=1} f && /log-opts=/{print; exit}' \
    "$REPO_ROOT/.github/workflows/secret-scan.yml" | sed -E 's/.*--log-opts="([^"]*)".*/\1/')
  [[ -n "$CRON_OPTS" ]] || fail "could not extract cron log-opts from secret-scan.yml"
  ```

  The non-empty guard makes a YAML restructure fail loudly instead of silently passing. Keep the hardcoded `--no-merges`/`--cc`/`-m` rows as parser characterization (AC3), but the *gate* assertion must read the real artifact.
- AC2a — AC4, AC5 and AC6 are **committed assertions** in a `.test.sh` that `scripts/test-all.sh` globs — not shell one-liners living only in this plan. An AC phrased as a grep that never runs after merge is not a gate.
- AC3 — The test asserts `--cc` → rc=0 (no-op) **and** `-m` → rc=1, both explicitly.
- AC4 — `grep -c 'log-opts="-m --all"' .github/workflows/secret-scan.yml` returns ≥1; `grep -c 'log-opts="-m"'` (bare, no `--all`) returns 0.
- AC5 — The cron job contains a `gitleaks dir` step.
- AC6 — The `push:main` step comment no longer describes #6721 as unfixed.
- AC6a — The PR job (and merge_group job) carry merge-resolution coverage: a `gitleaks dir` step, or `-m` if the Phase 1.5 coupling measurement clears it.
- AC6b — Mutation: a synthetic PR-shape range spanning a conflict-resolution secret is DETECTED by the shipped PR job configuration. Against today's config this case is rc=0 — the mutation proof is that it flips to rc=1.
- AC6c — The Phase 1.5 `-m`-coupling measurement was actually run and its result recorded (either arm chosen, with data). An inconclusive result must be recorded as inconclusive and resolved by shipping `gitleaks dir`.

**#6723**

- AC7 — `bash plugins/soleur/test/gitleaks-rules.test.sh` exits 0 with T6, T7 (incl. 4 new multi-`@` rows), T8, T9 all passing.
- AC8 — Mutation: reverting the rule regex to `[^@/\s]+` makes the multi-`@` T7 rows go **RED**.
- AC9 — Mutation: removing either the `^` or the `$` from the allowlist entry makes T9 go **RED**.
- AC10 — T8 still reports exactly one `regexes` entry (2 triple-quote runs).
- AC11 — **The shipped walk** (not the old narrower one) returns rc=0 under the shipped config. All three required:
  - `gitleaks git -c .gitleaks.toml --no-banner --exit-code 1 --log-opts="-m --all"`
  - `gitleaks dir . -c .gitleaks.toml --no-banner --exit-code 1`
  - `gitleaks git -c .gitleaks.toml --no-banner --exit-code 1 --log-opts="--no-merges HEAD"` (the `push:main` step specifically)

  **Why this replaced the v1 AC:** v1 verified only `--no-merges HEAD` — the *old, narrower, merge-blind* walk. The cron ships `-m --all` (3303 commits / **52 merges**), so merge-exclusive content across 52 resolutions, evaluated under the new password class, was **unmeasured**. The cron is blocking and a finding there has no tip-fixable remedy. If any command returns rc=1, triage before merge — do not ship.
- AC11a — The hardened `<[^>@:]+>` form is shipped, and the three P0-1 regression fixtures are RED against the issue's unhardened candidate.
- AC11b — The path allowlist entry is anchored `^…$`; `evil/plugins/soleur/skills/review/SKILL.md` carrying a real DSN is DETECTED.
- AC11c — The `.gitleaks.toml` commit carries an `Allowlist-Widened-By: <name>` trailer. The `allowlist-diff` job (`secret-scan.yml`) requires the `secret-scan-allowlist-ack` label **or** that trailer for a `paths` change, and its parser is **blind to a `regexes` widening** (#3888) — so for the `regexes` half the trailer is convention, not an enforced gate. A PR whose entire subject is gates that cannot fail must not ship a `regexes` widening through a documented blind spot.
- AC12 — Working-tree scan under the shipped config introduces **no** finding absent from the pre-change baseline.

**#6724**

- AC13 — On a branch fresh off `origin/main` with no review, `pre-merge-rebase.sh` returns `permissionDecision: "deny"`.
- AC14 — Mutation: reverting Check 1 to the repo-global grep makes AC13 go **RED** (gate passes ⇒ test fails).
- AC15 — `bash .claude/hooks/pre-merge-rebase.test.sh` and `bash .claude/hooks/pre-merge-rebase-headless.test.sh` both exit 0.
- AC16 — No occurrence of the unscoped form remains anywhere. Scope the grep to **every hook root**, not the two files v1 named:
  `grep -rn 'grep -rl "code-review"' --include='*.sh' --include='*.md' .claude/ .openhands/ scripts/ tests/ plugins/soleur/skills/ship/` returns 0 matches outside `knowledge-base/`.
- AC17 — `/review` writes the `Reviewed-By-Soleur:` trailer via `emit-review-trailer.sh`, invoked from a step that runs in BOTH pipeline and direct mode; both consumers grep for it.
- AC17a — **Zero-finding proof:** on a branch where `/review` yields zero findings and zero file changes, the trailer IS present in `git log origin/main..HEAD`. Mutation: remove `--allow-empty` → **RED**. Without this AC the gate deadlocks clean-review branches.
- AC17b — Post-auto-sync proof: branch off main, merge main back in (main carrying a post-fork `code-review` todo), no review → hook still DENIES.
- AC18 — The in-flight-branch impact set for AC17 has been **enumerated** (not assumed empty), with the result recorded in the PR body.
- AC18a — `test/pre-merge-rebase.test.ts` (9 `addReviewEvidence` call sites) passes. It currently survives only because Signal 2 catches it — if Phase 3.3 drops the legacy alternatives, all 9 go red at once.
- AC18b — T10 exists: a block-scoped `paths` arity guard on `database-url-with-password`, pinned to the shipped entry count. **Nothing currently guards the `paths` array** — appending `'''plugins/soleur/.*\.md$'''` blinds a whole subtree while T6/T7/T8/T9 all stay green, because `scan_rules` writes fixtures to `fixture.txt` where no realistic path entry can ever match.
- AC18c — T8, T9 and T10 are positioned **above** the `command -v gitleaks` skip guard (they are pure config-text assertions needing no binary), and the new merge-commit test **aborts** rather than skips when gitleaks is absent — following the `code-to-prd` convention, so a fresh mutation proof can never be silently skipped.

**Cross-cutting**

- AC19 — PR body states why direction 1 + 2 were taken for #6721 instead of the issue's favoured direction-2-only, citing the measured costs.
- AC20 — PR body records that #6724's scope was extended to `pre-merge-rebase.sh`, which the issue does not name.
- AC21 — Every mutation AC (AC2, AC8, AC9, AC14) has its RED output pasted into the PR body. **An unexercised mutation claim is exactly the defect class this PR fixes** — assertion is not evidence.

### Post-merge (operator)

None. All verification is automatable in-session and pre-merge (`gitleaks` is installed locally at the pinned version; the hook and test suites are shell-invocable). No operator step is deferred.

## Observability

```yaml
liveness_signal:
  what: secret-scan workflow conclusion (scan job) + weekly cron run
  cadence: per PR / per push:main / weekly Mon 06:00 UTC
  alert_target: GitHub required-check status on main; cron failure surfaces as a red scheduled run
  configured_in: .github/workflows/secret-scan.yml
error_reporting:
  destination: GitHub Actions run log + required-check status
  fail_loud: true (--exit-code 1 on scan/cron; the all-refs sweep step is advisory by design)
failure_modes:
  - mode: merge-exclusive secret introduced by hand-resolved conflict
    detection: cron `-m --all` walk + `gitleaks dir` full-tree step
    alert_route: red weekly cron run
  - mode: multi-@ DSN silenced by allowlist
    detection: gitleaks-rules.test.sh T7 multi-@ rows (CI) + live rule on all scan jobs
    alert_route: red secret-scan check on the introducing PR
  - mode: rule change silently reddens main's history
    detection: AC11 full-ancestry scan run pre-merge
    alert_route: red push:main check (prevented pre-merge by AC11)
  - mode: merge proceeds with no review on branch
    detection: pre-merge-rebase.sh Check 1 (branch-scoped) → permissionDecision deny
    alert_route: emit_incident rf-never-skip-qa-review-before-merging
logs:
  where: GitHub Actions run logs (--redact applied); hook incidents via .claude/hooks/lib/incidents.sh
  retention: GitHub default (90d)
discoverability_test:
  command: gh run list --workflow=secret-scan.yml --limit 5 --json conclusion,event,createdAt
  expected_output: most recent schedule-event run present with conclusion success
```

No `ssh` in any verification command. No soak-gated closure criterion — every AC is decidable at merge time, so no follow-through enrollment is required.

## Architecture Decision (ADR/C4)

**No ADR required.** This plan changes no ownership/tenancy boundary, introduces no substrate or integration pattern, and reverses no existing ADR. It restores three existing gates to the behaviour their own documentation already claims. Test: would an engineer reading the current ADRs + C4 be *misled* about the system after this ships? No — the ADRs describe the gates' intent, which this plan makes true rather than changes.

**No C4 impact.** Read all three model files (`model.c4`, `views.c4`, `spec.c4`) and enumerated against the modelled set, rather than grepping for the feature's own noun:

- **External human actors** — modelled set is `founder` (Founder / Operator), `emailSender` (Inbound Correspondent), `betaContact` (Beta Tester / Prospect), `contributor` (Contributor / PR Author). This change adds no correspondent, reviewer, or recipient role, and alters no existing actor's description. `contributor` already covers the PR author whose merge the review-evidence gate blocks; that relationship is unchanged in kind.
- **External systems / vendors** — modelled set is `anthropic`, `github`, `cloudflare`, `doppler`, `discord`, `stripe`, `plausible`, `resend`, `ghcr`, `zotRegistry`, `letsencrypt`, `publicResolvers`, `betterstack`, `sentry`, `sigstore`. `github` is already modelled as *"Source control, CI/CD, issue tracking, and releases"*, which subsumes the secret-scan workflow. The pinned gitleaks binary is a CI-internal tool, not a modelled external system — no new webhook, outbound API, or third-party store is introduced. No edge to `github` is added, removed, or re-scoped.
- **Containers / data stores** — none touched. No runtime container, database, queue, or volume appears in this diff.
- **Access relationships** — unchanged. `grep -niE "github|action|ci|gitleaks|secret.?scan|pipeline" model.c4 views.c4` confirms no element models the secret-scan gate or the review-evidence gate; both are intra-CI controls, not modelled trust boundaries. No `view … include` line needs adding because no element does.

## Domain Review

**Domains relevant:** Engineering (security/CI). Product not relevant — no file in `## Files to Edit` or `## Files to Create` matches any UI-surface term or glob (no `components/**`, no `app/**/page.tsx`, no `app/**/layout.tsx`); the mechanical UI-surface override does not fire, so the Product/UX Gate is skipped.

### Engineering

**Status:** reviewed
**Assessment:** Two of three fixes alter live secret-scanning semantics with repo-wide blast radius, which is why each carries a measured before/after matrix and a full-history verification (AC11) rather than a fixture-only proof. The #6724 scope extension to `pre-merge-rebase.sh` is the finding with the highest leverage: the issue as filed would have produced a prose-only fix leaving the actual merge blocker vacuous. Highest residual risk is AC18 (in-flight branch impact of the trailer), deliberately left UNKNOWN rather than assumed.

## GDPR / Compliance Gate

Not applicable — no regulated-data surface. No schema, migration, auth flow, API route, or `.sql` file is touched; no new processing activity, no LLM/external-API call on operator data, no new cron reading `knowledge-base/project/learnings/`, no new artifact distribution surface. Skipped per the canonical regex and all four expansion triggers.

## Infrastructure (IaC)

Not applicable — no new server, systemd unit, cron host, vendor account, DNS record, TLS cert, secret, firewall rule, or monitoring webhook. The weekly `schedule:` trigger already exists in `secret-scan.yml`; this plan changes its arguments, not its existence. No operator SSH, no Doppler write, no vendor dashboard step.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Rule widening reddens main's history | **Measured, not theoretical** — exactly 1 finding at `48b8bc4a5`. Path-allowlist mitigation verified rc=0. AC11 gates it pre-merge. |
| Path allowlist over-blinds | Scoped to one file × one rule, anchored with `$`. Rationale + compensating controls recorded in-config per file convention. |
| Someone later "simplifies" `-m` → `--cc` | AC3 asserts `--cc` → rc=0 explicitly; workflow comment records the trap. |
| Someone later drops `--all` from `-m --all` | AC4 asserts the bare `-m` form returns 0 matches. |
| Branch-scoped Signal 1 blocks legitimate merges | Signals 2 and 3 remain; trailer (3.1) lands before consumers (3.2/3.3). |
| Trailer blocks in-flight branches | Legacy alternatives retained; AC18 requires enumerating the affected set rather than assuming it is empty. |
| Greedy `[^/\s]+` over-matches across two DSNs on one line | Password class excludes `/`, so a realistic DSN with a `/db` path terminates the match. T7's host/scheme/short-password rows are the regression net; add a two-DSN row if `/work` finds a counterexample. |

## Test Strategy

Runners are the ones already in the repo — no new framework. `plugins/soleur/test/gitleaks-rules.test.sh` is a plain `bash` script gated on `command -v gitleaks` (skips cleanly when absent); the new merge-commit test follows the same shape and the same `mktemp -d` + `trap` cleanup convention. Hook tests are `bash .claude/hooks/*.test.sh`.

**The mutation proofs are the deliverable, not a bonus.** For each of AC2 / AC8 / AC9 / AC14: apply the inverse edit, run the suite, capture the RED output, restore. Per the review skill's guidance, back up to a session-unique `mktemp` path and echo it, and run the restore in a **separate** Bash call under `timeout` — a mutation that removes a guard can hang rather than fail, and a trailing restore in the same call would never run.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| #6721 direction 2 only (issue's preference) | Measurement shows direction 1 is nearly free and covers merge-content later removed, which direction 2 cannot. Taking both costs ~9s/week. |
| #6721 via `--cc` | **Measured silent no-op** — emits patch bytes, detects nothing. Would ship a new unfailable gate. |
| #6721 direction 3 (linear history) | Largest workflow impact; closes the gap by construction but out of scope. Recorded as re-evaluate. |
| #6723 line-level `gitleaks:allow` waiver | Does not clear history — the old blob has no comment. Verified reasoning matches the review skill's own documented trap. |
| #6723 second `regexes` entry | Violates T8's deliberate arity guard; the guard exists precisely to stop allowlist growth. |
| #6724 direction 2 (retire Signal 1) | Direction 1 makes Signal 1 correct at near-zero cost; retiring removes a usable signal. |
| #6724 broaden Signal 2 to `fix(`/`test(` | Every branch carries those commits — recreates the cannot-fail shape elsewhere. |
| #6724 SKILL.md-only fix (issue as filed) | Leaves `pre-merge-rebase.sh` — the actual `deny` gate — vacuous. |

## Re-evaluate When

- `allow_merge_commit` is disabled on the repo — closes #6721 by construction; the `-m` walk could then be dropped.
- The gitleaks pin moves off 8.24.2 — re-measure `--cc` parser behaviour and re-verify the same-id default-pack override pattern.
- `todos/` is emptied or retired — would silently "fix" #6724 by accident; the branch-scoped form must remain regardless.
- The `database-url-with-password` rule is next touched for any reason — re-run the full before/after matrix and AC11.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- **`--cc` produces patch bytes that gitleaks silently ignores.** Byte-count measurement is NOT detection measurement. Always gate on `--exit-code 1` and read `rc`, never on output volume.
- **`--log-opts="-m"` silently narrows breadth to `HEAD`.** `git log` with no revision defaults to HEAD; the all-refs cron requires `-m --all`.
- **A line-level `gitleaks:allow` waiver cannot clear a history finding.** History scans read the old blob. Only a path predicate matches identically across history.
- **`xargs` without `-r` hangs on empty input.** The branch-scoped Signal 1 pipeline must use `xargs -r`.
- **Two copies of "the same three signals" drift.** `ship/SKILL.md` and `pre-merge-rebase.sh` already diverged on Signal 2's anchoring. Any future signal edit must touch both, or converge them behind one shared helper.
- **The prose gate and the mechanical gate are different artifacts.** An issue naming a SKILL.md phase may leave a PreToolUse hook carrying the identical defect. Grep `.claude/hooks/` for the defective expression before scoping any gate fix.
