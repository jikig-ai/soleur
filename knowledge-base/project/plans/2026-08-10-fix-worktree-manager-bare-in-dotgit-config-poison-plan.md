---
date: 2026-08-10
issue: "#7394"
pr: 7407
branch: feat-one-shot-7394-worktree-manager-bare-repo-layout
type: bug
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
tags: [git, worktrees, bare-repo, worktree-manager, core.bare, extensions.worktreeConfig]
---

# 🐛 fix(git-worktree): `ensure_bare_config` cannot run on the operator's bare-repo-in-`.git` layout, so nothing can break the config pair that wedges every worktree

> **Lane note.** No `knowledge-base/project/specs/feat-one-shot-7394-.../spec.md` exists for this
> branch, so `lane:` could not be carried forward — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

`worktree-manager.sh` refuses to run from inside a perfectly valid worktree:

```
Error: Cannot run from bare repo root (no working tree available).
```

The refusal is correct given its inputs — from inside the affected worktree git itself reports
`--is-bare-repository = true` and `--show-toplevel` fatals — so `IS_IN_WORKTREE` is `false` and
`require_working_tree` exits 1.

The wedge is a **two-key pair in the shared `.git/config`**: `core.bare = true` *together with*
`extensions.worktreeConfig = true`, while a linked worktree's own
`.git/worktrees/<name>/config.worktree` carries no `core.bare` override. `ensure_bare_config` is
the function whose entire job is to prevent that pair — its header says `core.bare` must live
**only** in `.git/config.worktree`, never in `.git/config` — but on this repo's layout its
`#5934` round-6 fast-path guard matches and returns before any surgery can run. The function is
**unreachable dead code on the operator's layout**, permanently.

This already caused a real outage: **fourteen worktrees went down simultaneously mid-rebase on
2026-08-09** ([`knowledge-base/project/learnings/2026-08-09-one-shared-config-key-took-all-fourteen-worktrees-down-mid-rebase.md`](../learnings/2026-08-09-one-shared-config-key-took-all-fourteen-worktrees-down-mid-rebase.md)).
That learning's own **Prevention** line names the missing mechanism verbatim:

> A local-bare-repo counterpart to the `#4826` heal would close it mechanically.

This plan builds that counterpart.

**The design turn.** The issue proposes unblocking the existing surgery so it runs. Measurement
says that is the *wrong direction*: the surgery's end state is one of two equally-correct states,
and reaching it from where the repo stands today requires walking **through** the exact hybrid
state that caused the outage. The plan therefore **reverses the surgery's polarity** — enforce
"extension absent, `core.bare` in the shared config" rather than "extension on, `core.bare` in
`config.worktree`" — which dissolves the hazard window by construction instead of sequencing
around it. Evidence for that turn is in *Reproduction* and *Alternatives Considered* below.

---

## Reproduction Condition (VERIFIED — do not re-derive)

All measurements on **git 2.53.0**, against synthesized fixtures (a bare repo whose gitdir IS
`<root>/.git`, and one linked worktree `wt1`). `is_bare` / `toplevel` are read **from inside `wt1`**.

> **Re-measured independently 2026-08-10** by a second planning pass, on fresh fixtures built by
> `git clone --bare <seed> <root>/.git`, with **no** `config.worktree` at the root. Rows 1, 3, 4, 5
> and facts 1, 2, 3, 5, 6 all reproduced. Two amendments landed from that pass: **fact 4 is
> falsified** (see below) and **fact 7 is new**. Note the minimality this establishes — a root
> `config.worktree` is **not** part of the trigger; row 3 reproduces without one.

| # | `extensions.worktreeConfig` | shared `core.bare` | `wt1/config.worktree` seeded `bare=false` | `--is-bare-repository` | `--show-toplevel` |
|---|---|---|---|---|---|
| 1 | off | `true` | no  | `false` | resolves |
| 2 | off | `true` | yes | `false` | resolves |
| 3 | **on** | **`true`** | **no** | **`true`** | **`fatal: this operation must be run in a work tree`** |
| 4 | on | `true` | yes | `false` | resolves |
| 5 | on | *absent* | no | `false` | resolves |

**Row 3 is the bug**, and it is the only failing row.

Commands (abridged; full harness rebuilt per case):

```bash
# Minimal row-3 reproduction — no root config.worktree needed.
git clone --bare "$seed" "$root/.git"
git -C "$root/.git" config core.bare true
git -C "$root/.git" worktree add "$root/.worktrees/wt1" -b wt1 main
( cd "$root/.worktrees/wt1" && git rev-parse --is-bare-repository )  # -> false   (row 1: healthy)

git -C "$root/.git" config extensions.worktreeConfig true            # the poison key
( cd "$root/.worktrees/wt1" && git rev-parse --is-bare-repository )  # -> true    (row 3: the bug)
( cd "$root/.worktrees/wt1" && git rev-parse --show-toplevel )       # -> fatal: ... must be run in a work tree
```

Note the second and third lines differ only in the extension key — **the same worktree, the same
shared `core.bare`, flips from healthy to wedged on that one write.** That is the whole bug, and it
is why `worktree-manager.sh:653-654` (the repo's only setter of that key) is the live hazard even
though the clone reads healthy today.

### Seven facts this establishes

1. **`core.bare = true` in the shared config is INERT for linked worktrees unless
   `extensions.worktreeConfig` is also enabled** (rows 1–2 vs row 3). The issue body's stated
   cause is correct but incomplete — it does not name the extension as a *necessary* co-condition.
2. **The extension is honoured at `core.repositoryformatversion = 0`** on git 2.53.0. Measured:
   row 3 was produced with `repositoryformatversion = 0`. This **falsifies** the mechanism recorded
   in [`2026-04-02-bare-repo-config-bleed-worktrees.md`](../learnings/2026-04-02-bare-repo-config-bleed-worktrees.md)
   ("the `extensions.worktreeConfig = true` setting was inert" at v0). The *outcome* that learning
   describes still occurs; its *explanation* does not hold on the installed git. **No fix may gate
   on `repositoryformatversion`.**
3. **`git worktree add` does NOT write `core.bare = false` into the shared config** on git 2.53.0 —
   measured on the bare-in-`.git` layout and on a genuine `git init --bare repo.git` layout, and
   from the root *and* from inside an existing worktree. The shared `[core]` block was byte-identical
   before and after every `add`. This is the corruption `ensure_bare_config`'s header cites as its
   whole reason for existing (`worktree-manager.sh`, anchor: *"Fixes TWO broken states that git
   worktree add creates on bare repos"*, and the two call-site comments *"git worktree add on bare
   repos writes core.bare=false to shared config — fix it"*). **That premise is not reproducible on
   the installed git.**
4. **`git worktree add` writes NO `config.worktree` at all** — corrected 2026-08-10. The earlier
   draft of this plan claimed it writes an **empty (0-byte)** one when the extension is on.
   Re-measured on git 2.53.0 with the extension enabled: after `git worktree add`, `[[ -e
   .git/worktrees/<name>/config.worktree ]]` is **false** — the file is never created. Corroborated
   on the live repo, where the 9 most recently created worktrees (`feat-herdr-worktree-placement`,
   `feat-kb-archival-gate`, `feat-one-shot-7394-…`, …) have no such file, while the 9 older ones
   carry a hand/older-git-written `bare = false`.

   **Absent and empty are equivalent for inheritance** — neither sets an override, so both inherit
   the shared `core.bare`. The fix direction is unchanged. But every place this plan, its tasks, or
   its tests describe the post-`add` state must say **"absent (git creates no `config.worktree`)"**,
   never "0-byte" — a test asserting `stat -c%s … == 0` would fail on a correct implementation, and
   an implementer reading "empty" may write a truncate-if-exists heal that never fires.
5. **The local per-worktree self-heal works and needs no shared-config write.** From inside a
   row-3 worktree, `git rev-parse --absolute-git-dir` still resolves correctly to
   `<common>/worktrees/<name>`, and writing `core.bare = false` to that directory's
   `config.worktree` flips `--is-bare-repository` to `false` and makes `--show-toplevel` resolve —
   with the shared config untouched.
6. **The masked-config probe degrades safely.** With `.git/config` replaced by a symlink to
   `/dev/null` (the `#5934` char-device signature — `[[ -c ]]` dereferences the symlink, so
   `_config_target_masked` classifies it MASKED), `git config --file .git/config --get core.bare`
   returns **rc=1 with empty output**. Re-measured 2026-08-10: **both** the plain form and the
   `--get --type=bool` form return rc=1 / empty. A guard that requires `core.bare == true` from that
   read therefore **cannot fire under the mask** — the round-6 protection is preserved by
   construction, not by an added special case.

7. **NEW (2026-08-10) — `core.bare = true` in the shared config is what keeps the ROOT bare, and
   removing it is NOT a safe permanent fix.** Measured on the row-3 fixture: after
   `git config --file .git/config --unset core.bare` (the hand workaround the issue body records),
   `git rev-parse --is-bare-repository` **from the root** flips to `false` and `--show-toplevel`
   resolves to the root itself. That is not a repaired bare repo — it is a bare repo that now
   presents as a normal clone, which flips `worktree-manager.sh`'s top-of-script `IS_BARE` to
   `false` at the root and changes every downstream branch (fetch strategy, `GIT_ROOT` derivation,
   `WORKTREE_DIR`, `sync-bare`). **This retires the issue's suggested workaround as a candidate
   end state** and is the measurement behind Phase 3 step 3 (keep `core.bare` in the shared config;
   remove only the extension).

8. **NEW (2026-08-10) — the repo's `core.repositoryformatversion` is `0`, and
   `worktree-manager.sh`'s own file header is stale on all three of its claims.** The header
   (lines 7–14, anchor: *"BARE REPO NOTE: This repo uses core.bare=true with
   extensions.worktreeConfig=true"*) asserts `extensions.worktreeConfig=true` (**absent** —
   `git config --get` exits 1), `repositoryformatversion=1` (**it is 0**), and — the load-bearing
   one — *"linked worktrees inherit `core.bare=false` by default"*. That last sentence is **exactly
   backwards**: under the extension a linked worktree with no override inherits `core.bare=`**`true`**,
   which IS this bug. The header is the false belief that hid the defect from every reader of the
   file, including the author of the round-6 guard. Correcting it is in scope (Phase 3 step 6), not
   cosmetic.

### Why the pipeline runner could not reproduce it on this clone

The runner's note stated the shared config carried **both** keys. Measured now:

```
$ git config --file /home/jean/git-repositories/jikig-ai/soleur/.git/config --get core.bare
true
$ git config --file /home/jean/git-repositories/jikig-ai/soleur/.git/config --get extensions.worktreeConfig
$ echo $?
1
```

`extensions.worktreeConfig` is **absent**. The clone sits in the harmless **row 1**, which is why
`draft-pr` succeeded and created PR #7407. The runner's premise about the extension was wrong; the
rest of its note (that the trigger is narrower than "any worktree on this layout") was right.

**The bug is latent, not absent.** `worktree-manager.sh:653-654` is the **only** site in the entire
repository that *sets* `extensions.worktreeConfig = true` (verified by repo-wide grep; every other
mention — `worktree-config-seed.ts`, `ensure-workspace-repo.ts`, `workspace.test.ts` — *removes* or
asserts the absence of it). One successful run of that line against this repo re-creates row 3 for
every worktree lacking a seeded override.

---

## Root Cause

`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`, function `ensure_bare_config`,
anchor comment *"ROUND-6 root cause (#5934, operator-CONFIRMED non-bare workspace)"*:

```bash
if [[ "$git_dir" == */.git && -d "$git_dir" ]]; then
  # ... benign mask diagnostic ...
  return 0
fi
```

The guard treats **"gitdir is a `.git` DIRECTORY"** as pure-filesystem proof of a normal clone. That
inference was sound for the two surfaces it was written against. It is **false for the operator's
local layout**, which is a *bare repo stored in a `.git` subdirectory*: `GIT_ROOT/.git` is a real
directory **and** `core.bare = true`. The guard matches, `return 0` fires, and the surgery — plus
every repair the function could perform — is skipped forever.

`ADR-099` (*Git Surface Topology*) is where this should have been caught. Its table row 3 reads:

| **Local CLI dev** | **BARE** root + linked worktrees | a `.git` **file** in each worktree | operator's checkout | operator's own clone |

The `.git` column describes only the **worktrees** (a `.git` file). It never states what the **root**
carries — a `.git` *directory* that is bare — which is precisely the fingerprint that collides with
row 2 (*Agent workspace*, NON-BARE, "a `.git` **directory**"). **The filesystem fingerprint the
round-6 guard relies on cannot discriminate row 2 from row 3's root.** ADR-099 documents the guard's
consequence for row 2 and is silent on row 3, so the guard's blind spot was invisible in the record.

### Second defect in the same function — the write order opens the bug window

The surgery writes in this order:

1. `core.repositoryformatversion 1` **and `extensions.worktreeConfig true`**
2. `--unset core.bare` from the shared config
3. `core.bare true` into `.git/config.worktree`

Steps 1 → 2 transit **through row 3**. If step 2 fails, the function `return 1`s and leaves the repo
**permanently** in row 3. Today this is unreachable on the operator's layout (defect 1 shields it);
the moment defect 1 is fixed the window becomes live. The polarity reversal below removes step 1
entirely, so no ordering can produce row 3 — this is why the reversal is a *fix* rather than a
sequencing patch.

### How the other thirteen worktrees actually get healed (stated explicitly — [R7], plan-review)

This mechanic is load-bearing and was nowhere in the plan, so a reader could not tell which
subcommand fixes what. Recorded here as the canonical answer:

- **One** successful `ensure_bare_config` run — from **any** worktree, via `create`,
  `create-for-feature`, or `cleanup-merged` — removes `extensions.worktreeConfig` from the
  **shared** config. Per fact 1 that instantly makes the shared `core.bare` inert for **every**
  linked worktree, on their very next `git` invocation, with no per-worktree action. That is what
  heals all fourteen.
- **Phase 5's self-heal is strictly local.** It repairs only the worktree the operator is standing
  in. Running `list` / `switch` / `draft-pr` from worktrees 2–14 does **nothing** for the other
  thirteen. It exists to make the *current* worktree usable immediately — including from
  `draft-pr`, which never calls `ensure_bare_config` — not to fix the repo.
- **Phase 4's seed never backfills.** `cleanup_merged_worktrees` calls `ensure_bare_config` once
  per run, not once per worktree, and Phase 4 fires only at creation time. So worktrees created
  *before* this fix never receive the individual `core.bare=false` override that would make them
  immune "regardless of what the shared config later says". Post-fix worktrees are immune; legacy
  ones rely solely on the central invariant. **Accepted, not hidden** — a backfill loop is
  deliberately out of scope (it would be a write to N files to defend against a writer this PR
  deletes), but the asymmetry must be stated rather than implied by the Risks table's
  version-scope mitigation, which over-claims if read as covering legacy worktrees.

### Third defect — the symptom has no recovery path

`ensure_bare_config` is called only from `create_worktree`, `create_for_feature`, and
`cleanup_merged_worktrees`. `draft-pr` — the reported failing subcommand — never calls it. And
`IS_BARE` / `IS_IN_WORKTREE` are computed **once at script-source time**, before any repair could
run. So a user standing in an already-poisoned worktree gets a hard refusal from *every* subcommand,
with a message telling them to do the thing they are already doing ("Run from an existing worktree").
Fixing the cause does not fix the already-poisoned worktree; that needs its own local self-heal.

---

## Research Reconciliation — Claim vs. Codebase

| Claim (issue / prior art) | Reality (measured / read) | Plan response |
|---|---|---|
| Shared config has `core.bare=true` **and** `extensions.worktreeConfig=true` today (issue + runner note) | `core.bare=true` present; `extensions.worktreeConfig` **absent** (rc=1). Repo is in harmless row 1 | Reframe as **latent**: `worktree-manager.sh:653-654` is the sole setter in the repo; one run re-creates row 3 |
| "`core.bare=true` in shared config bleeds into worktrees" (issue) | Only when the extension is **also** on (rows 1–2 vs 3) | Fix targets the **pair**, not either key alone |
| Linked worktrees "had an EMPTY `config.worktree`" (issue) | **Partially falsified** (fact 4) — git creates **no** `config.worktree` at all. Absent, not empty. Equivalent for inheritance, so the issue's conclusion stands; its mechanism does not | Belt-and-braces seed of `core.bare=false` at create time; all prose/tests say "absent", never "0-byte" |
| "Workaround applied by hand: `git config --file .git/config --unset core.bare`" (issue) | **Retired as an end state** (fact 7) — measured, that unset makes the bare ROOT report `--is-bare-repository=false` and resolve a toplevel, flipping `IS_BARE` at the root | Keep `core.bare` in the shared config; remove only `extensions.worktreeConfig` (Phase 3) |
| `worktree-manager.sh` header: "extensions.worktreeConfig=true … repositoryformatversion=1 … linked worktrees inherit core.bare=false by default" | **Stale on all three** (fact 8). The third is inverted — the inherited value is `true`, which IS the bug | Correct the header in Phase 3 step 6; AC pins the inverted sentence's removal |
| `extensions.worktreeConfig` is inert at `repositoryformatversion=0` ([2026-04-02 learning](../learnings/2026-04-02-bare-repo-config-bleed-worktrees.md)) | **Falsified** on git 2.53.0 — row 3 was produced at v0 | No fix may gate on `repositoryformatversion` |
| "`git worktree add` on bare repos writes `core.bare=false` to shared config" (`ensure_bare_config` header + 2 call-site comments) | **Not reproducible** on git 2.53.0 — bare-in-`.git` *and* genuine-bare, from root *and* from a worktree; shared `[core]` byte-identical after `add` | Correct the stale comments; record the version scope; this is the premise the polarity reversal retires |
| ADR-099 enumerates the layouts | Row 3 describes only the *worktrees'* `.git` **file**, never the *root's* `.git` **directory** | **Amend ADR-099** — the fingerprint collision is the recorded gap |
| `#4826` is the issue behind the worktree-config-seed heal (code comments + 2026-08-09 learning) | `gh issue view 4826` → *"feat: nav-rail position resume"*; `gh pr view 4826` → does not resolve | Cite the **artifacts** (`worktree-config-seed.ts`, `workspace.test.ts`), not the ordinal; note the stale citation, do not chase it |
| Server-side bare git-data would be affected by a polarity change | `git-data-provision.sh` runs a plain `git init --bare` with **no** config surgery; `model.c4` records the git-data host as **NOT YET PROVISIONED (#6977)** | Blast radius on that surface is currently **zero**; still covered by a genuine-bare test case |

### Premise Validation

Every reference in the issue body was probed. `#7394` is **OPEN** with no
`closedByPullRequestsReferences` — not already fixed. PR **#7407** is the open WIP draft on this
branch. `#5934`, `#6184`, `#5912`, `#6186`, `#6191` are CLOSED; `#6206`, `#7373` are MERGED — all
consistent with the prior art the issue cites. Every cited file path was read directly. The one
stale premise found is the `#4826` ordinal (row above). No premise was accepted on paraphrase.

---

## User-Brand Impact

**If this lands broken, the user experiences:** every `git` write command in every one of their
worktrees failing with `fatal: this operation must be run in a work tree`, and every
`worktree-manager.sh` subcommand refusing with *"Cannot run from bare repo root"* — from inside a
worktree that is manifestly valid. Their in-flight work is not lost but is completely inaccessible
to tooling until they hand-edit git config, which a non-technical Soleur user cannot do. This is not
hypothetical: it happened on 2026-08-09 to 14 worktrees at once, mid-rebase.

**If this leaks, the user's data is exposed via:** nothing — this change reads and writes only local
git configuration (`core.bare`, `extensions.worktreeConfig`, `core.worktree`). It touches no user
content, no credentials, no network surface, and adds no new persisted field. There is no exposure
vector.

**Brand-survival threshold:** `single-user incident` — one user losing their entire local working
surface to a config key Soleur's own tooling wrote is brand-damaging on its own, without any
aggregate pattern. **[R-cpo] This is not only the founder's machine.** The self-hosted CLI plugin
carrying `worktree-manager.sh` has been in the hands of an external alpha tester since 2026-08-06
(`knowledge-base/product/roadmap.md`, tracked against `#1439`). The 2026-08-09 outage is the
*internal* instance of this failure; the alpha tester is the higher-stakes one, and unlike the
founder they have no way to diagnose a git-config wedge at all. CPO sign-off is required at plan time (see *Domain Review*); `user-impact-reviewer`
runs at PR-review time per `plugins/soleur/skills/review/SKILL.md`.

---

## Architecture Decision (ADR/C4)

Detected: this plan **reverses a cross-cutting invariant** (which config state a bare repo is
normalized *to*) and **adds a third surface** to a documented topology. Both are deliverables here,
not follow-ups.

### ADR

Two records, both in scope for this PR:

1. **Amend `ADR-099` (Git Surface Topology).** Its layout table's row 3 (*Local CLI dev*) must state
   that the **root** carries a `.git` **directory** that is bare (`core.bare=true`), and the table
   must gain an explicit note that **the filesystem fingerprint `[[ -d <root>/.git ]]` cannot
   discriminate row 2 (non-bare agent workspace) from row 3's root** — which is the exact inference
   the round-6 guard makes. Its existing sentence about the guard making `ensure_bare_config` a
   no-op on the Concierge workspace must be extended to record that it is *also* a no-op on row 3,
   and that this was the defect (#7394).
2. **New ADR — `ADR-173`: bare-repo config normalization targets the extension-absent state.**
   Decision: on any bare layout, `worktree-manager.sh` normalizes to **`extensions.worktreeConfig`
   absent + `core.bare` in the shared config**, and NEVER enables the extension. Alternatives
   Considered must carry the extension-on state (measured equally correct as a *steady* state, row 5)
   and record precisely why it loses: the transition into it passes through row 3, and the
   `git worktree add` corruption it was adopted to prevent is not reproducible on git 2.53.0.
   The ADR must scope its measurement to that version and name the re-evaluation trigger —
   **[R12]** widened to *either* (a) a git release that restores shared-config writes on
   `worktree add`, *or* (b) a re-audit finding a new setter of `extensions.worktreeConfig` anywhere
   in the toolchain (including tools outside this repo: herdr, the Concierge runtime).

   Two further requirements, both from plan-review:
   - **[R13] Cite `apps/web-platform/server/worktree-config-seed.ts` by path**, not by prose. The
     same invariant ("never enable `extensions.worktreeConfig`") is now encoded twice, in two
     languages, on two disjoint surfaces, with no mechanical link — and that file's own header
     records the invariant being shipped *backwards* once already (`#6064`/`#6068`). The ADR is the
     only anchor from which a future reader can find both encodings; a path makes it greppable.
   - **[R14] Record the convergence as a positive consequence.** Before this reversal the two
     surfaces actively disagreed — `ensure_bare_config` *set* the extension while
     `worktree-config-seed.ts` *unset* it. That disagreement was unreachable only because the
     round-6 guard blocked the surgery. The reversal therefore **removes a latent cross-surface
     contradiction** rather than creating one: a real consistency argument for the decision,
     independent of the row-3 bug.

> **Ordinal is provisional.** `ADR-173` is the next free ordinal as of 2026-08-10
> (`ADR-172` is the highest present). A sibling PR can claim it. `/ship`'s ADR-Ordinal Collision
> Gate re-verifies against `origin/main` before merge. **On renumber, sweep this plan, `tasks.md`,
> and every AC naming the ordinal** — `grep -rn 'ADR-173' knowledge-base/project/{plans,specs}/feat-one-shot-7394-*/`.

### C4 views

**No C4 impact.** All three model files were read — `knowledge-base/engineering/architecture/diagrams/{spec.c4,model.c4,views.c4}` — not grepped for the feature's own noun. Enumeration checked:

- **External human actors:** `founder`, `emailSender`, `betaContact`, `contributor`. This change
  introduces no new human role; the founder/operator already owns the local checkout.
- **External systems / vendors:** `anthropic`, `github`, `cloudflare`, `doppler`, `discord`,
  `stripe`, `plausible`, `resend`, `pushService`, `ghcr`, `projectZot`, `zotRegistry`,
  `betterstack`, `sentry`, `sigstore`, `letsencrypt`, `publicResolvers`, `systemdUser`. No new
  integration, inbound webhook, or outbound API.
- **Containers / data stores:** `platform.plugin.{skills,agents,kb}`,
  `platform.infra.{gitDataStore,workspacesVolume,sessionStore,supabase,…}`. The change is confined
  to a script inside `platform.plugin.skills`; it creates no store and moves no data between stores.
- **Access relationships:** none change. No single-owner → multi-owner shift, no new trust boundary.
- **L3 components of `platform.plugin`:** `go`, `sync`, `help`, `brainstorm`, `plan`, `work`,
  `review`, `compound`, `ship`, `oneshot`, `architecture`, `cto`, `cmo`, `cpo`, `archstrat`,
  `evalharness`, `constraintscaffold`. **The `git-worktree` skill is not modeled as a component at
  L3 at all**, so there is no element whose description this change falsifies.

No element description becomes false as a result of this change. No `views.c4` `include` line needs
adding. Consequently `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` are
unaffected, and `scripts/regenerate-c4-model.sh` need not run.

### Sequencing

Both records are authored in this PR. `ADR-173` ships at `status: accepted` — the decision is true
the moment the code lands; there is no soak or later slice it depends on.

---

## Observability

The affected surface is **observability layer 7** — plugin code executing on a customer's
self-hosted CLI, where the operator has no dashboard and no shell into the failure. The existing
marker family (`SOLEUR_GIT_*` on stdout, mirrored server-side by
`apps/web-platform/server/git-lock-marker-telemetry.ts`) is the only channel, so the new state must
join it.

```yaml
liveness_signal:
  what:          "SOLEUR_GIT_BARE_POISON marker emitted by ensure_bare_config on every create /
                  create-for-feature / cleanup-merged invocation on a bare layout — branch=healed
                  when the pair was broken, branch=clean when the invariant already held."
  cadence:       "every worktree create and every cleanup-merged run (session-start gate)"
  alert_target:  "Better Stack via git-lock-marker-telemetry.ts's pino sink (benign class — logged,
                  not paged); the wedge class routes to Sentry as today"
  configured_in: "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh (emit)
                  + apps/web-platform/server/git-lock-marker-telemetry.ts (MARKER_RE + wedge
                  classification)"

error_reporting:
  destination:   "stdout marker -> git-lock-marker-telemetry.ts -> pino/Better Stack; the
                  'worktree wedge:' give-up class continues to route as a WEDGE (paged)"
  fail_loud:     true   # a failed pair-break returns 1 and emits `worktree wedge: ...`, exactly as
                        # the existing unset-core.bare failure path does — never a silent continue

failure_modes:
  - mode:        "The poisoned pair (extension on + shared core.bare) exists and the break FAILS
                  (masked config / unremovable lock)."
    detection:   "IN-SURFACE: `worktree wedge: could not break the bare-config pair in <git_dir>`
                  on stdout from the CLI itself, plus SOLEUR_GIT_CONFIG_TARGET_MASKED when the
                  target is masked. Discriminating fields in one event: git_dir, extension=<on|off>,
                  shared_bare=<true|false|absent>, wt_override=<true|false|absent>, branch=<...>
                  — so masked-target, lock-wedged, and already-clean are separable from a single
                  line without a second run."
    alert_route: "wedge class in git-lock-marker-telemetry.ts -> Sentry"
  - mode:        "A worktree is ALREADY poisoned and the local self-heal fails (its own
                  config.worktree is unwritable)."
    detection:   "IN-SURFACE: SOLEUR_GIT_BARE_SELFHEAL with branch=failed and worktree=<name>
                  ([R6] — one marker, outcome in branch=, matching BARE_POISON's convention).
                  Emitted from inside the affected worktree, the only place that state is
                  observable. Pin the ACTUAL field set emitted at this call site rather than
                  promising 'the same' by reference: the arm fires from the top-of-script block
                  before most state exists, in the branch where detection is already failing, so
                  prefer fields readable without a further git invocation. git_version= is
                  mandatory on both markers."
    alert_route: "wedge class (branch=failed) -> Sentry"
  - mode:        "Regression: the round-6 non-bare skip stops firing on a genuinely non-bare
                  clone (would re-open #5934 / #6184 under the sandbox mask)."
    detection:   "SOLEUR_GIT_CONFIG_MASK_SKIP with branch=non-bare-skip must still appear;
                  its ABSENCE on a masked non-bare workspace is the signal. Pinned by the two
                  existing regression tests (worktree-manager-atomic-config.test.sh tests 23-24)
                  plus the new negative cases."
    alert_route: "CI (test-all.sh) — pre-merge, not runtime"

logs:
  where:     "CLI stdout (operator-visible immediately) + Better Stack via the server-side mirror
              for Concierge-hosted sessions"
  retention: "Better Stack default retention for the pino sink; CLI stdout is per-invocation"

discoverability_test:
  command: |
    bash plugins/soleur/test/worktree-manager-bare-in-dotgit-layout.test.sh
    # and, against a live checkout, with NO ssh:
    bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh list 2>&1 \
      | grep -E 'SOLEUR_GIT_BARE_POISON|worktree wedge:' || echo "invariant clean"
  expected_output: |
    All assertions pass; and on a healthy repo either `SOLEUR_GIT_BARE_POISON ... branch=clean`
    or `invariant clean`. Neither command uses ssh.
```

---

## Open Code-Review Overlap

**None.** Queried all 64 open `code-review` issues (`gh issue list --label code-review --state open
--json number,title,body --limit 200`) and matched their bodies against every planned file path
(`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`, the bare basename
`worktree-manager.sh`, and `ADR-099`). Zero matches on any of the three.

---

## Implementation Phases

Phases are ordered by **dependency direction**: the contract change (the invariant + its helper)
lands before every consumer of it.

### Phase 0 — Preconditions (read-only, no writes)

1. Re-read `ensure_bare_config` end-to-end and confirm the anchors this plan cites still exist:
   the `ROUND-6 root cause` comment, the `*/.git && -d` guard, the `_bare_status` authoritative
   check, and the three-step write order.
2. Confirm `plugins/soleur/test/test-helpers.sh` exposes `assert_eq`, `assert_contains`,
   `assert_file_exists`, `assert_file_not_exists`, `print_results`.
3. Confirm the auto-glob at `scripts/test-all.sh` (anchor: `for f in plugins/soleur/test/*.test.sh
   plugins/soleur/skills/*/test/*.test.sh …`) still covers `plugins/soleur/test/*.test.sh`, so the
   new suite needs no explicit registration.
4. Record `git --version` in the PR body. Every measurement in this plan is scoped to it.

### Phase 1 — RED: the regression suite (write failing tests FIRST, per `cq-write-failing-tests-before`)

Create `plugins/soleur/test/worktree-manager-bare-in-dotgit-layout.test.sh`. All fixtures
synthesized with `git init` (`cq-test-fixtures-synthesized-only`). Follow the sibling
`worktree-manager-atomic-config.test.sh` conventions verbatim: `set -euo pipefail`, unset every
`GIT_*` env var, `source test-helpers.sh`, and source `worktree-manager.sh` (its `BASH_SOURCE == $0`
guard means `main()` does not run on source).

> **Sourcing note (load-bearing).** `IS_BARE` / `IS_IN_WORKTREE` / `GIT_ROOT` are computed at
> **source time**. Every case that needs different detection state must `cd` into its fixture and
> source the script in a **fresh subshell** — re-sourcing in the same shell will not recompute them.

Cases:

| # | Fixture | Assertion |
|---|---|---|
| 1 | bare-in-`.git` + linked worktree + row-3 poison applied | **`require_working_tree` SUCCEEDS from inside the worktree** (the issue's asked-for assertion; fails on today's code). **[R8 — attribution corrected]** The plan originally worded this "after `ensure_bare_config` has run", which is wrong and contradicts the *Third defect* section: `require_working_tree` reads only the source-time globals, and nothing in Phases 2–3 re-derives them. What makes this case pass is **Phase 5**, which fires during `source` — *before* any subcommand could call `ensure_bare_config`. Word the case to attribute the fix to Phase 5, and cover Phase 3's separate contribution in case 3 (post-state matches row 1) rather than conflating the two here |
| 2 | bare-in-`.git`, clean | `ensure_bare_config` performs its normalization instead of returning early: shared `core.bare` retained, `extensions.worktreeConfig` absent, stale `core.worktree` removed |
| 3 | bare-in-`.git` + row-3 poison | `ensure_bare_config` breaks the pair; post-state matches row 1; `git rev-parse --is-bare-repository` from the worktree is `false` |
| 4 | genuine bare (`repo.git`, gitdir IS root) + linked worktree | same invariant holds — the fix is not special-cased to the `.git`-subdirectory shape |
| 5 | **NEGATIVE** — normal non-bare clone (`.git` dir, `core.bare` absent) | short-circuits with **zero** config writes; `.git/config` mtime + byte-identical content unchanged (pins `#6184`) |
| 6 | **NEGATIVE** — masked shared config (`ln -s /dev/null .git/config`) on a `.git`-directory layout | still short-circuits; emits `SOLEUR_GIT_CONFIG_MASK_SKIP … branch=non-bare-skip`; attempts no write (pins `#5934` round 6) |
| 7 | **INVARIANT** | `extensions.worktreeConfig` is never enabled while `core.bare` is present in the shared config — assert across every intermediate state the function can produce |
| 8 | already-poisoned worktree, `ensure_bare_config` NOT called | the detection-time self-heal alone makes `require_working_tree` succeed, and the **shared config is byte-unchanged** |
| 9 | after `create` | the new worktree's `config.worktree` carries `core.bare = false`. Pre-assert the baseline in the same case: a raw `git worktree add` leaves the path **non-existent** (`[[ ! -e … ]]`) — this pins fact 4 so a future git that *does* seed the file trips the suite instead of silently changing the premise |
| 10 | bare-in-`.git`, clean, after `ensure_bare_config` | `git rev-parse --is-bare-repository` **from the ROOT** is still `true` (pins fact 7 — the fix must not de-bare the root the way the issue's hand workaround does) |
| 11 | **[R1]** bare-in-`.git`, **already clean** (extension absent), `ensure_bare_config` run | returns **0**, emits `branch=clean`, and does **not** emit `worktree wedge:`. Pins the `--unset-all` idempotence defect: on today's `atomic_git_config` this case FAILS with rc≠0 |
| 12 | **[R5]** row-3 worktree whose own `config.worktree` target is **unwritable** (`chmod a-w` the `worktrees/<name>/` dir) | self-heal fails; `SOLEUR_GIT_BARE_SELFHEAL … branch=failed` is emitted; the CLI prints the absolute unwritable path and a concrete next step; the script exits non-zero rather than proceeding into git commands that will fatal |
| 13 | **[R3]** row-3 worktree, after self-heal | `WORKTREE_DIR` equals `<root>/.worktrees` (NOT a path under `.git/worktrees/…`), and a subsequent `create` places the new worktree under `<root>/.worktrees/`. Asserting `require_working_tree` returns 0 is **not** sufficient — that passes while `WORKTREE_DIR` is corrupt |
| 14 | **[R-arch2] NEGATIVE** — normal non-bare `.git`-directory clone whose shared config has been corrupted to `core.bare = true` | pins the residual row-2/row-3 ambiguity the narrowed guard necessarily introduces. Assert the **intended** behaviour explicitly (heal or refuse) rather than leaving it to fall out of the implementation — the old blanket guard skipped this unconditionally; the new one cannot |

Run and confirm cases 1, 3, 7, 8, 9 **FAIL** before writing any implementation. (Cases 2, 4, 5, 6
10 and 14 are expected to pass or be vacuous on today's code — 10 in particular passes today because
the surgery never runs; it exists to stay green through the change.)

### Phase 2 — GREEN (a): narrow the round-6 fast-path guard

In `ensure_bare_config`, replace the unconditional `.git`-directory skip with a **two-condition**
skip that still defaults to SKIP:

- Read `core.bare` from the shared config **file** (`git config --file "$git_dir/config" --get
  --type=bool core.bare`), not from `git rev-parse`.
- If that read yields anything other than `true` — absent, `false`, non-zero rc, empty (**the masked
  case**, verified rc=1/empty on a `/dev/null` symlink) — keep the existing behaviour exactly:
  emit the benign `SOLEUR_GIT_CONFIG_MASK_SKIP … branch=non-bare-skip` diagnostic when the config
  family is masked, and `return 0`.
- Only when the read is unambiguously `true` does control fall through to the existing authoritative
  `git rev-parse --is-bare-repository` check.

Update the guard's comment block to state the third surface explicitly and to record *why* the
config read is mask-safe (it degrades to "absent", which routes to the skip).

**Do not gate on `core.repositoryformatversion`** — fact 2 above.

### Phase 3 — GREEN (b): reverse the surgery's polarity

Replace the three-step surgery with the **pair-breaker**. Target state = row 1: `core.bare = true`
in the shared config, `extensions.worktreeConfig` **absent**.

1. **Delete** the `atomic_git_config "$shared_config" extensions.worktreeConfig true` and the
   `core.repositoryformatversion 1` writes.
2. **Add**: if `extensions.worktreeConfig` is present in the shared config, `--unset-all` it via
   `atomic_git_config`. This is the local-bare-repo counterpart of the
   `worktree-config-seed.ts` heal that the 2026-08-09 learning asked for.

   > **[R1 — P0, plan-review 2026-08-10] `atomic_git_config` must be taught `--unset-all` FIRST, or
   > this step breaks every healthy repo.** Its FR2 read-first idempotence branch
   > (`worktree-manager.sh:448`) matches only the **literal string** `--unset`; `--unset-all` fails
   > that test *and* fails the `elif`'s `"$1" != --*` guard (`:456`), so neither fast path fires and
   > the call reaches the native writer unconditionally. Measured on git 2.53.0 in this environment:
   > `git config --file <f> --unset-all <absent-key>` exits **5**. So on the **target state itself**
   > — row 1, extension already absent, i.e. the state this function is supposed to leave the repo
   > in and the state the operator's repo is in today — the call returns non-zero,
   > `ensure_bare_config` takes its `if ! atomic_git_config` branch, emits `worktree wedge:`, and
   > returns 1. That fails `create_worktree`, `create_for_feature` **and** `cleanup_merged_worktrees`
   > (`:1280`, `:1414`, `:1942`) on a perfectly healthy repo — relocating the outage, not closing it.
   >
   > **Required, in this order, inside Phase 3:** extend the FR2 branch at `:448` to
   > `[[ "${1:-}" == "--unset" || "${1:-}" == "--unset-all" ]]`. The existing skip condition
   > (`--get` rc 1 → absent → `return 0`) is correct for both forms; the rc-2 multi-valued
   > fall-through documented at `:449-452` is *also* correct for `--unset-all` (present-and-multiple
   > is exactly what `--unset-all` is for, so proceeding is right). `atomic_git_config` therefore
   > joins `## Files to Edit` as a Phase 3 change, not an untouched dependency.
   >
   > This also **falsifies the plan's own claim** in *Risks & Mitigations* that both shared-config
   > writes are "already routed through `atomic_git_config`'s read-first idempotence — a no-op when
   > the invariant already holds"; that row is corrected below.
3. **Keep** `core.bare = true` in the shared config (it is what keeps the root bare) and **remove**
   the `--unset core.bare` step. Retain the `--unset core.worktree` step unchanged — that half of
   the surgery is still correct.
4. **Keep** `.git/config.worktree` on disk untouched; with the extension absent it is inert and
   harmless. Do not delete it (a deletion is a destructive write with no benefit).
5. Emit `SOLEUR_GIT_BARE_POISON … branch=healed|clean` with the discriminating fields listed in
   the Observability block. On any write failure, `return 1` and emit
   `worktree wedge: could not break the bare-config pair in <git_dir>` — mirroring the existing
   give-up shape so `git-lock-marker-telemetry.ts` classifies it as a wedge.
6. Correct the now-false comments — **three sites, not two**:
   - The **file header (lines 7–14)**, anchor *"BARE REPO NOTE: This repo uses core.bare=true with
     extensions.worktreeConfig=true"*. All three of its claims are stale (fact 8); the sentence
     *"linked worktrees inherit core.bare=false by default"* is **inverted** and must be replaced
     with the measured behaviour: *under `extensions.worktreeConfig`, a linked worktree with no
     `config.worktree` override inherits the shared `core.bare` — i.e. `true` — and git then treats
     it as bare.* Add the normalization invariant the fix establishes (extension absent;
     `core.bare` stays in the shared config) and cite `ADR-173`.
   - The function header's *"Fixes TWO broken states that git worktree add creates on bare repos"*.
   - The two call-site comments *"git worktree add on bare repos writes core.bare=false to shared
     config — fix it"*.

   Replace each with what was measured, scoped to the git version.

7. **Decide the fourth write block** — `worktree-manager.sh:684-694`, anchor *"Ensure per-worktree
   config has core.bare=true for the bare root"*, which writes `core.bare true` into the **bare
   root's own** `$git_dir/config.worktree`. Phase 3's other bullets never mention it. Under the
   reversed polarity the extension is permanently absent, so git never reads that file and the
   write can never take observable effect — it becomes vestigial. **Delete it**, and say so in the
   header comment. (Keeping it as inert dead code recreates precisely the "nobody remembers why
   this write exists" condition that step 6 exists to end. Note this is a *write*, not the file:
   fact 4 / Phase 3 step 4 keeps the existing `config.worktree` **on disk** untouched.)

8. **Correct `atomic_git_config`'s own docstring** (`:413`, *"…is the sole config-mutation entry
   point for ensure_bare_config below"*). After Phases 4 and 5 it gains two further call-site
   classes (the post-`add` seed, and the top-of-script self-heal). The sentence stays literally
   true while reading as though `ensure_bare_config` were still the only caller — the same
   stale-header failure mode as the round-6 guard.

**Ordering safety is structural, not sequential:** because the extension is never written, no
interleaving of these steps can produce row 3.

> **[R2 — P0, plan-review 2026-08-10] Phases 2 and 3 MUST land as one atomic commit.** The
> "structural safety" sentence above covers ordering *within* Phase 3 only. It says nothing about
> the Phase-2/Phase-3 boundary — and that boundary is dangerous in exactly the way this plan
> documents. Phase 2 alone makes `ensure_bare_config` **newly reachable** on the operator's layout
> while Phase 3 has not yet deleted the `extensions.worktreeConfig true` write at `:653-654`. The
> first `create` / `create-for-feature` / `cleanup-merged` after a Phase-2-only commit would
> therefore *construct* row 3 on the operator's own repo — the 2026-08-09 outage, self-inflicted by
> the fix for it. `cleanup_merged_worktrees` is what the session-start gate runs, so a session
> boundary falling between the two phases is a realistic trigger, not a theoretical one.
>
> Note this **inverts** the plan's stated ordering principle ("the contract change lands before
> every consumer of it"): Phase 2 is not safe standing alone; it requires Phase 3 to already exist.
> `/work` must not create an intermediate commit between them, and the two must never be
> independently revertable.

### Phase 4 — GREEN (c): belt-and-braces per-worktree seed

After a successful `git worktree add` in `create_worktree` and `create_for_feature`, write
`core.bare = false` into the new worktree's `.git/worktrees/<name>/config.worktree` via
`atomic_git_config`. This is the second half of the 2026-08-09 recorded recovery — the half that
learning says *"matters more than the first"* — and it makes a future stray extension write
**harmless** for every worktree this tool creates (row 4).

**Why this survives given Phase 5 exists ([R11], plan-review).** Phase 5 heals reactively, on the
hot path, once a worktree is already poisoned. Phase 4 makes tool-created worktrees never *become*
poisoned, so the self-heal never has to fire for them — which matters because the self-heal is new
code running on **every** invocation of **every** subcommand, and the cheapest failure is the one
that never needs recovering. They are not redundant: Phase 4 is prophylactic and narrow (two call
sites, creation time), Phase 5 is curative and broad (all subcommands, all origins). Neither
subsumes the other, and the 2026-08-09 learning names this half as the one that *"matters more"*.
Its explicit limit is recorded above: it does **not** backfill worktrees that already exist.

**Per fact 4, the file does not exist at this point** — git creates none. So this is a *create*,
not a repair of an empty file: `atomic_git_config` must be able to write a `config.worktree` that
is absent (it already can — it is the same path `ensure_bare_config` uses for the root's
`config.worktree`). Do **not** write a heal that only fires when the file exists-and-is-empty; that
condition is never true.

Resolve the path from `git -C "$worktree_path" rev-parse --absolute-git-dir`, never by string-joining
a guessed worktree name.

### Phase 5 — GREEN (d): detection-time self-heal for an already-poisoned worktree

In the top-of-script detection block, after `IS_IN_WORKTREE` is computed and found `false`, add a
narrow recovery arm that fires **only** when all of these hold:

- `.git` in the CWD (or the nearest ancestor) is a **FILE** whose content is `gitdir: <path>`;
- that path resolves under `<git-common-dir>/worktrees/`;
- `git rev-parse --is-bare-repository` reports `true`.

That combination is unambiguously "physically inside a linked worktree that git believes is bare" —
row 3. Recovery: write `core.bare = false` into **this worktree's own** `config.worktree` via
`atomic_git_config`, then re-derive the detection state. Emit
`SOLEUR_GIT_BARE_SELFHEAL … worktree=<name> branch=ok` on success, `… branch=failed` on failure
(and leave the existing refusal path intact on failure — never proceed into git commands that will
fatal).

> **[R3 — P0, plan-review 2026-08-10] `WORKTREE_DIR` is a stale consumer the recompute list omits.**
> `WORKTREE_DIR="$GIT_ROOT/.worktrees"` is assigned **eagerly**, once, at `worktree-manager.sh:160`
> — it is the only non-function-body use of `GIT_ROOT` in the file. Re-deriving only
> `IS_IN_WORKTREE`, `IS_BARE`, and `GIT_ROOT` therefore leaves `WORKTREE_DIR` holding a value
> computed from the **pre-heal, corrupted** `GIT_ROOT`.
>
> This is not cosmetic. In row 3 the pre-heal path takes the `IS_BARE=true` branch and sets
> `_git_dir=$(git rev-parse --absolute-git-dir)`, which for a linked worktree resolves to
> `<common>/worktrees/<name>` (fact 5). That does **not** end in `/.git`, so `:117` sets
> `GIT_ROOT="$_git_dir"` — git's internal bookkeeping directory, not the repo root — and
> `WORKTREE_DIR` becomes `<root>/.git/worktrees/<name>/.worktrees`. After a "successful" self-heal
> the operator's next `create` would place a worktree *inside git's own metadata directory*, and
> `list` / `switch` would report nothing found while real worktrees exist.
>
> **Required:** place the recovery arm **before** `:159-160` and let `ensure_git_root_absolute` +
> `WORKTREE_DIR="$GIT_ROOT/.worktrees"` run once, afterwards, on healed state — the structurally
> safer option, since it needs no recompute list to be kept in sync. If it must go after, then
> `WORKTREE_DIR` (and `ensure_git_root_absolute`) join the explicit recompute list.

> **[R4 — plan-review 2026-08-10] Pin the path resolution, as Phase 4 already does.** Resolve the
> target from `git rev-parse --absolute-git-dir`, **never** by string-joining a guessed worktree
> name. Fact 5 is exactly what licenses trusting that command from inside a row-3 worktree. Phase 4
> states this; Phase 5 must too, or a future edit reintroduces a guessed-path bug in the safety net
> itself.

> **[R5 — P0, plan-review 2026-08-10] The failure arm must not reuse the message this plan
> criticises.** "Leave the existing refusal path intact" as written drops the operator back into
> `require_working_tree`'s *"Run from an existing worktree"* text — the exact message the *Third
> defect* section calls out for telling them to do what they are already doing. On self-heal
> failure the CLI MUST print, in plain language: the **absolute path** it could not write, the most
> likely causes (file permissions / ownership / disk full / a read-only mount), and one concrete
> next step. A raw `SOLEUR_GIT_BARE_SELFHEAL` marker line is telemetry, not an operator message —
> a non-technical Soleur user cannot act on it.

**The shared config must not be touched here.** The self-heal runs from an arbitrary subcommand
(including `draft-pr`) with no lock discipline around the shared config; scoping it to the
worktree's own file keeps blast radius at 1.

### Phase 6 — Telemetry registration

> **[R6 — plan-review 2026-08-10] Two markers, not three, and both carry `git_version`.**
> `SOLEUR_GIT_BARE_SELFHEAL` and `SOLEUR_GIT_BARE_SELFHEAL_FAILED` are one event with a success/
> failure outcome, minted as two names immediately after `SOLEUR_GIT_BARE_POISON` establishes
> `branch=healed|clean` as the convention for exactly that. Collapse to
> `SOLEUR_GIT_BARE_SELFHEAL … branch=ok|failed` — fewer `MARKER_RE` alternatives, fewer
> wedge/benign branches to keep in sync, one coherent event type. Wedge classification then keys on
> `branch=failed`, not on a distinct marker name.
>
> Separately, **both** markers MUST carry `git_version=<git --version output>`. Every behavioural
> fact behind this fix is scoped to git 2.53.0 and the *Risks* table concedes an older git may
> diverge; these markers are the **only** channel into a layer-7 failure (no shell, no dashboard).
> Without the version in the line, triaging a customer report costs a round-trip just to rule the
> known version-scoping gap in or out. AC4 records the version in the *PR body* — developer-time,
> once; this is customer-time, every time.
>
> Phase 5 must also state which fields are genuinely cheap at its call site: the self-heal fires
> from the top-of-script block, **before** most state is computed, in the branch where detection is
> already failing. Do not promise "the same discriminating field set" by reference — pin the actual
> emitted set, and prefer fields readable without a further git invocation that could fail under
> the same mask/lock conditions that made the heal necessary.

Extend `MARKER_RE` in `apps/web-platform/server/git-lock-marker-telemetry.ts` to include
`SOLEUR_GIT_BARE_POISON`, `SOLEUR_GIT_BARE_SELFHEAL`, and `SOLEUR_GIT_BARE_SELFHEAL_FAILED`, and
classify the two `*_FAILED`/wedge-shaped ones as **wedges** and the informational ones as **benign**
— matching the existing `SOLEUR_GIT_CONFIG_TARGET_MASKED` (wedge) vs `SOLEUR_GIT_CONFIG_MASK_SKIP`
(benign) split. Update the file's header marker inventory comment. Extend
`apps/web-platform/test/git-lock-marker-telemetry.test.ts` with one case per new marker.

### Phase 7 — Architecture records

Amend `ADR-099` and author `ADR-173` per the *Architecture Decision* section, via
`/soleur:architecture`.

### Phase 8 — Verification

Run the new suite, the two sibling worktree-manager suites, and the full runner:

```bash
bash plugins/soleur/test/worktree-manager-bare-in-dotgit-layout.test.sh
bash plugins/soleur/test/worktree-manager-atomic-config.test.sh
bash plugins/soleur/test/worktree-manager-bare-sync.test.sh
bash scripts/test-all.sh
```

Read the **summary line** (`N/M`), not a piped exit code — per
[`2026-08-09-one-shared-config-key-took-all-fourteen-worktrees-down-mid-rebase.md`](../learnings/2026-08-09-one-shared-config-key-took-all-fourteen-worktrees-down-mid-rebase.md) §6,
where `tail`'s status was misread as the suite's verdict.

---

## Files to Edit

| File | Change |
|---|---|
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | Narrow the round-6 guard (Phase 2); reverse the surgery polarity + new markers + corrected comments (Phase 3); per-worktree `core.bare=false` seed after `git worktree add` (Phase 4); detection-time self-heal (Phase 5) |
| `apps/web-platform/server/git-lock-marker-telemetry.ts` | Register **2** new markers in `MARKER_RE` + wedge/benign classification (wedge keys on `branch=failed`) + header inventory (Phase 6, as revised by [R6]) |
| `apps/web-platform/test/git-lock-marker-telemetry.test.ts` | One case per new marker (Phase 6) |
| `knowledge-base/engineering/architecture/decisions/ADR-099-git-surface-topology.md` | Row 3 gains the root's `.git` **directory**; new note on the fingerprint collision; guard-consequence sentence extended to row 3 (Phase 7) |

## Files to Create

| File | Purpose |
|---|---|
| `plugins/soleur/test/worktree-manager-bare-in-dotgit-layout.test.sh` | The 14-case regression suite (auto-globbed by `scripts/test-all.sh` — no registration needed) |
| `knowledge-base/engineering/architecture/decisions/ADR-173-bare-repo-config-normalization-polarity.md` | The polarity decision + measurement scope + re-evaluation trigger (ordinal provisional) |
| `knowledge-base/project/specs/feat-one-shot-7394-worktree-manager-bare-repo-layout/tasks.md` | Task breakdown derived from these phases |

**No SKILL.md `description:` edit is candidate**, so the 1800-word cumulative budget check does not
fire. No new AGENTS.md rule is proposed, so the 46000-byte always-loaded budget is untouched.

---

## Acceptance Criteria

### Pre-merge (PR)

1. `bash plugins/soleur/test/worktree-manager-bare-in-dotgit-layout.test.sh` passes all 14 cases.
2. **Case 1 (the issue's assertion)**: from inside a linked worktree of a bare-in-`.git` repo that
   was poisoned to row 3, `require_working_tree` returns 0 after `ensure_bare_config` runs.
3. **Case 5 (`#6184` regression)**: on a normal non-bare clone, `.git/config` is byte-identical
   (`cmp` against a pre-run copy) after `ensure_bare_config` returns 0.
4. **Case 6 (`#5934` round-6 regression)**: with `.git/config` a symlink to `/dev/null` on a
   `.git`-directory layout, `ensure_bare_config` returns 0, emits
   `SOLEUR_GIT_CONFIG_MASK_SKIP` with `branch=non-bare-skip`, and attempts no write.
5. **Case 7 (the invariant)**: no reachable state of `ensure_bare_config` leaves
   `extensions.worktreeConfig` enabled while `core.bare` is present in the shared config.
6. `bash plugins/soleur/test/worktree-manager-atomic-config.test.sh` passes — specifically its
   existing tests 23 and 24 (the two `#5934 D3` non-bare-guard cases) are **unchanged and green**.
7. `git grep -n 'atomic_git_config "\$shared_config" extensions.worktreeConfig true' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
   returns **zero** matches (the sole setter in the repo is removed). **[R9]** Anchor on the full
   call form, not the bare token `extensions.worktreeConfig true` — Phase 3 step 6's rewritten
   prose legitimately needs to *name* the key it no longer writes, and a bare-token absence-grep
   would false-fail on correct documentation (`cq-assert-anchor-not-bare-token`). Positive
   counterpart: the file contains a comment stating the extension is never enabled, citing
   `ADR-173`.
7a. **[R-kieran2] Sibling test 23 does not become stale documentation.**
    `worktree-manager-atomic-config.test.sh` test 23's fixture is a normal `.git`-directory clone
    with `core.bare` set to `true` — i.e. an **unmasked** read that returns literally `true`, so
    under the narrowed guard it now *falls through* rather than skipping. Its three existing
    assertions still pass, but for a different reason than its own comment claims ("the HARDENED
    guard detects non-bare via `.git`-is-a-directory and SKIPS regardless of rev-parse"). Either
    add `[[ ! -e "$WS24/.git/config.worktree" ]]` so the test genuinely exercises the new
    behaviour, or update its comment to record that safety now comes from Phase 3's structural
    removal of the dangerous write. **Do not leave the comment asserting behaviour that no longer
    holds** — that is the exact defect class Phase 3 step 6 exists to end. Test 24 (genuinely
    masked config) is unaffected: the masked read returns empty per fact 6 and correctly skips.
8. `git grep -cn 'worktree add on bare repos writes core.bare=false' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
   returns **0** (the falsified premise no longer stated as fact at the two call sites).
   **[R10 — scope corrected]** That literal matches only the two call-site comments (`:1380`,
   `:1489`). Phase 3 step 6 requires a **third** correction — the function header at `:548`,
   *"Fixes TWO broken states that git worktree add creates on bare repos"* — which does **not**
   contain the grepped substring, so AC8 alone can pass with the header's stale claim intact. Add:
   `git grep -c 'Fixes TWO broken states' <script>` returns **0**, plus a positive assertion that
   the function header now states the reversed-polarity invariant.
8a. **File-header correction (fact 8).** In `worktree-manager.sh`:
    `git grep -c 'linked worktrees inherit' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
    returns **0** — the inverted sentence is gone; and
    `git grep -c 'repositoryformatversion=1' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
    returns **0**. Positive counterpart (do not rely on absence alone, per
    `cq-assert-anchor-not-bare-token`): the header contains a sentence stating that a linked
    worktree with **no** `config.worktree` override inherits the shared `core.bare`, and names the
    normalization invariant (`extensions.worktreeConfig` absent).
8b. **Case 10 (fact 7 — the root stays bare).** On a bare-in-`.git` fixture, after
    `ensure_bare_config` runs, `git -C <root> rev-parse --is-bare-repository` is `true` and
    `git config --file <root>/.git/config --get core.bare` is `true`. The fix must never reach the
    de-bared state the issue's hand workaround produces.
8c. **Case 9 baseline (fact 4).** In the same fixture, immediately after a raw `git worktree add`
    and *before* Phase 4's seed, `[[ ! -e <root>/.git/worktrees/<name>/config.worktree ]]` holds.
    No assertion anywhere in the suite expects a 0-byte `config.worktree`:
    `git grep -cE 'stat -c%s.*config\.worktree|0-byte' plugins/soleur/test/worktree-manager-bare-in-dotgit-layout.test.sh`
    returns **0**.
8d. **[R1] `atomic_git_config` handles `--unset-all` idempotently.** `git grep -n 'unset-all'
    plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` shows the FR2 branch at ~`:448`
    testing for it, and **case 11** passes: `ensure_bare_config` on an already-clean bare-in-`.git`
    fixture returns 0 and emits no `worktree wedge:`.
8e. **[R2] Phases 2 and 3 are one commit.** `git log --format='%H' <base>..HEAD -- <script>` — no
    commit exists in which `git grep -c 'extensions.worktreeConfig true' <script>` is non-zero
    while the round-6 `*/.git && -d` guard has already been narrowed. Verify per-commit with
    `git show <sha>:<path>`, **not** a `git log -- pathA pathB` union filter.
8f. **[R3] `WORKTREE_DIR` survives the self-heal.** Case 13 passes: from inside a row-3 worktree,
    after self-heal, `WORKTREE_DIR` is `<root>/.worktrees` and a subsequent `create` lands there —
    not under `.git/worktrees/`.
8g. **[R5] Self-heal failure is covered and actionable.** Case 12 passes: on an unwritable target
    the CLI output contains the **absolute path** of the file it could not write and a concrete
    next step, and does **not** fall back to the bare `Run from an existing worktree` text alone.
8h. **[Phase 4 positive]** After `create`, `git config --file <root>/.git/worktrees/<name>/config.worktree --get core.bare`
    returns `false`. (AC8c pins only the pre-seed baseline; this pins the seed itself.)
8i. **[Phase 5 positive]** Case 8 passes: from inside an already-poisoned worktree with
    `ensure_bare_config` never invoked, `require_working_tree` returns 0 and
    `SOLEUR_GIT_BARE_SELFHEAL … worktree=<name> branch=ok` is emitted.
9. Each of `SOLEUR_GIT_BARE_POISON` and `SOLEUR_GIT_BARE_SELFHEAL` (**two** markers — [R6] collapsed
   the `_FAILED` variant into `branch=ok|failed`) appears in `MARKER_RE` in
   `apps/web-platform/server/git-lock-marker-telemetry.ts` **and** has a case in
   `apps/web-platform/test/git-lock-marker-telemetry.test.ts`, including a `branch=failed` case
   asserting it classifies as a **wedge**. `git grep -c 'SOLEUR_GIT_BARE_SELFHEAL_FAILED'` returns
   **0** repo-wide. Both markers emit a `git_version=` field.
10. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
11. `ADR-099` row 3's `.git` column names the root's `.git` **directory**, and the file contains an
    explicit statement that `[[ -d <root>/.git ]]` cannot discriminate row 2 from row 3's root.
12. `ADR-173` (or its collision-resolved ordinal) exists, records the polarity decision, pins the
    measurement to the exact `git --version`, and carries the extension-on state in
    `## Alternatives Considered` with the transition-through-row-3 rationale.
13. Every `ADR-173` reference in this plan and in `tasks.md` matches the ordinal actually used
    (`grep -rn 'ADR-173' knowledge-base/project/{plans,specs}/feat-one-shot-7394-*/`).
14. `bash scripts/test-all.sh` — read the `N/M` summary line; no new failures vs. the pre-change
    baseline recorded in Phase 0.
15. PR body uses `Closes #7394` (this is a code fix that takes effect at merge, not an
    ops-remediation, so `Closes` — not `Ref` — is correct).

### Post-merge (operator)

None. Every step is automated in-workflow. The operator's own repo is normalized by the next
`create` / `create-for-feature` / `cleanup-merged` run, which the session-start gate
(`wg-at-session-start-run-bash-plugins-soleur`) already performs.

---

## Alternatives Considered

| Approach | Verdict |
|---|---|
| **A. Unblock the existing surgery unchanged** (the issue's suggested fix): narrow the guard, let the function set `extensions.worktreeConfig=true` and move `core.bare` into `config.worktree` (row 5). | **Rejected.** Row 5 is a correct *steady* state (measured), but the operator's repo is in row 1 today and the transition passes **through row 3** — the exact state that took 14 worktrees down on 2026-08-09. It also re-introduces a key this repo classifies as harmful in three separate artifacts, and preserves a permanent-strand failure mode if the `--unset core.bare` write fails. |
| **B. Unblock the surgery + reorder the writes** (config.worktree first, unset `core.bare` second, extension last). | **Rejected.** Strictly better than A — no ordering reaches row 3 — but it still ends in row 5, still writes the harmful key, and still depends on the unverifiable `git worktree add` corruption premise to justify writing it at all. It sequences around the hazard where the chosen fix removes it. |
| **C. Seed `core.bare=false` per worktree only** (skip the guard fix entirely). | **Rejected as sufficient, adopted as a component.** It immunizes worktrees this tool creates (row 4) but does nothing for worktrees created by raw `git worktree add`, herdr, or the Concierge, and leaves `ensure_bare_config` permanently dead on this layout. Shipped as Phase 4, not as the fix. |
| **D. Fix only `require_working_tree` / `IS_IN_WORKTREE` detection** (treat a `.git` file under `worktrees/` as proof of a worktree). | **Rejected as sufficient.** It would let the script proceed, but every subsequent `git` command still fatals — it converts a clear refusal into an obscure downstream failure. The self-heal in Phase 5 is the correct form of this idea because it fixes the *state*, not just the script's opinion of it. |
| **E. Delete `ensure_bare_config` entirely** (git 2.53 needs none of it). | **Rejected.** The `core.worktree` cleanup and the stale-lock sweep are still load-bearing, the `git worktree add` behaviour is measured on one version only, and the function is the only place a poisoned pair can be *healed*. Deleting it would leave no mechanism to close the 2026-08-09 class. |

### Deferrals

**[R-cto1 — corrected; this section previously read "None", which the plan's own facts 2 and 3
contradict.]**

One deferral, and it must be filed as a tracked issue before this PR is marked ready:

- **Shrink `ensure_bare_config` to what facts 2 and 3 leave load-bearing.** This plan *measured*
  that two of the function's three stated reasons for existing are not reproducible on git 2.53.0
  (`git worktree add` does not corrupt the shared config; the `repositoryformatversion` gating
  premise is falsified). Its justification surface has shrunk while this PR grows its code surface.
  The residually load-bearing parts are the `core.worktree` unset and the stale-lock sweep — those
  do not need the three-step "surgery" apparatus around them. Alternative E ("delete the function")
  is rejected in this plan partly on grounds that are really arguments for keeping *those two
  sub-behaviours*, not this *shape*; and partly on "it is the only place a poisoned pair can be
  healed", which Phase 5 itself falsifies by adding an independent healing path.
  **Re-evaluation criteria:** after this PR soaks, and once `git worktree add` behaviour has been
  measured on the oldest git version Soleur supports. **Not folded in here** because it would mean
  restructuring the function in the same PR that reverses its polarity — two large changes to one
  function, with the regression suite pinning the old shape.
- The `#4826` ordinal cited in `worktree-config-seed.ts` and the 2026-08-09 learning does not
  resolve; deliberately **not** chased in this PR (see *Sharp Edges*). No issue filed — the correct
  ordinal is unknown, so there is nothing actionable to track.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Version-scoped measurement.** Facts 2–4 are measured on git 2.53.0 only. An older git may genuinely write `core.bare=false` to the shared config on `worktree add`. | Row 1 (the target state) is measured correct; and Phase 4's per-worktree `core.bare=false` seed makes every managed worktree immune **regardless** of what the shared config later says. `ADR-173` records the version scope and the re-evaluation trigger. |
| **Blast radius on the server-side bare git-data surface** (ADR-099 row 1), where the surgery currently does run. | `git-data-provision.sh` performs a plain `git init --bare` with no config surgery, and `model.c4` records the git-data host as **NOT YET PROVISIONED (#6977)** — live blast radius is currently zero. Test case 4 covers the genuine-bare layout so the invariant is pinned for when it is provisioned. |
| **Re-opening `#5934` / `#6184`** by weakening the non-bare skip. | The narrowed guard is *strictly more* likely to skip than the current one for every input except "shared config unambiguously says `core.bare=true`". The masked read degrades to absent → skip (fact 6, measured). Pinned by AC3, AC4, AC6 and the two untouched sibling tests. |
| **The detection-time self-heal writing config on every invocation.** | It fires only on the three-way conjunction in Phase 5 (worktree `.git` **file** + resolves under `worktrees/` + git reports bare) — unreachable in any healthy state. It writes exactly one file, the worktree's own, never the shared config. |
| **Concurrent sessions.** A repo-wide `.git/config` write is a blast-radius-14 action (2026-08-09). | The pair-breaker performs at most **two** shared-config writes (`--unset-all extensions.worktreeConfig`, `--unset core.worktree`). **[R1 — corrected]** Only the `--unset` form is a no-op today; `--unset-all` is **not** covered by `atomic_git_config`'s FR2 read-first branch and currently exits 5 on an absent key. Phase 3 must extend FR2 to `--unset-all` **before** this mitigation is true. Once extended, both are no-ops when the invariant already holds — the common case. The self-heal touches no shared file. |
| **[R-cto2] An older customer git may write `core.bare=false` into the shared config on `worktree add` by itself** — the very premise fact 3 retires. That write is git's own behaviour and happens whether or not this script ever touches `extensions.worktreeConfig`, producing the de-bared root of fact 7 through a route this fix does not close. | Phase 4's per-worktree seed protects worktrees, not the **root's** shared config, so it does not cover this. Cheap detection instead of new machinery: `SOLEUR_GIT_BARE_POISON` already carries `shared_bare` — emit it on the `create` path **after** the `git worktree add`, so an unexpected flip is one grep away instead of a support escalation with no trail. `ADR-173`'s re-evaluation trigger already names "a git release that restores shared-config writes on `worktree add`"; this makes that trigger *observable* rather than aspirational. |
| **[R-specflow3] An actor outside this repo sets the poison key.** The "sole setter" grep is scoped to this codebase; it cannot prove herdr, the Concierge runtime, or an operator's own hand never runs `git config extensions.worktreeConfig true`. | Accepted residual risk — and precisely why Phase 3's defensive `--unset-all` (rather than merely deleting the writer) and Phase 5's self-heal earn their place: they defend the one channel an outside actor can reach. Widen `ADR-173`'s re-evaluation trigger to include "a re-audit finds a new setter of `extensions.worktreeConfig` anywhere in the toolchain", not the git version alone. |
| **`config.worktree` left on disk becomes confusing.** | Inert with the extension absent (measured). `ADR-173` records why it is left rather than deleted. |

---

## Test Scenarios

Beyond the 9 suite cases:

- **Idempotence:** run `ensure_bare_config` three times on each fixture; assert the shared config is
  byte-identical after runs 2 and 3, and that `branch=clean` (not `branch=healed`) is emitted.
- **Concurrency smoke:** two `ensure_bare_config` invocations racing on one fixture leave a valid
  config (no half-written file) — `atomic_git_config`'s temp-copy + same-dir rename already
  guarantees this; assert it rather than assume it.
- **End-to-end:** on a bare-in-`.git` fixture poisoned to row 3, run the real
  `worktree-manager.sh create` and assert the created worktree is immediately usable
  (`git -C <wt> status` exits 0).

---

## Sharp Edges

- **`IS_BARE` / `IS_IN_WORKTREE` / `GIT_ROOT` are computed once at source time.** Any test case
  needing different detection state must source the script in a fresh subshell. Re-sourcing in the
  same shell silently reuses the first computation and produces a green test that proves nothing.
- **Do not gate anything on `core.repositoryformatversion`.** Measured: the extension is honoured at
  version 0 on git 2.53.0, contradicting the 2026-04-02 learning. A `formatversion == 1` precondition
  would make the fix miss the exact state that caused the outage.
- **`git config --file <masked> --get` returns rc=1 with empty output, it does not error loudly.**
  That is what makes the narrowed guard mask-safe — but it also means an implementation that treats
  "empty" as "go ahead and check with rev-parse" would re-open `#5934`. Default to SKIP on anything
  that is not literally `true`.
- **`git worktree add` writes NO `config.worktree` at all** (fact 4 — corrected 2026-08-10; an
  earlier draft of this plan said "empty/0-byte", which is wrong). Do not assume git seeds the
  override, and do not write a heal predicated on the file existing. Phase 4 *creates* the file.
  Any test asserting a 0-byte `config.worktree` after `git worktree add` will fail on correct code.
- **Do NOT "fix" this by unsetting `core.bare` from the shared config** (fact 7). It is the issue
  body's hand workaround and it is measured to make the bare root report as a normal working tree,
  flipping `IS_BARE` at the root and rerouting every downstream branch in this script.
- **The file header (lines 7–14) is stale on all three of its claims and inverted on the third**
  (fact 8). Anyone reasoning about this function from the header will reach the wrong conclusion —
  which is how the round-6 guard came to be written. Correct it in the same PR.
- **The `#4826` ordinal cited in `worktree-config-seed.ts` and the 2026-08-09 learning does not
  resolve** to a worktree-config issue (`gh issue view 4826` → *"feat: nav-rail position resume"*;
  `gh pr view 4826` → no such PR). Cite the artifacts, not the number. Do not "fix" the citation as
  part of this PR — it is out of scope and the correct ordinal is unknown.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This one is filled; keep it
  filled through any revision.
- **[R1] `atomic_git_config`'s FR2 idempotence matches the literal string `--unset` only.**
  `--unset-all` falls through both fast paths and reaches the native writer, which exits **5** on
  an absent key. Any new `--unset-all` call site is a latent "wedge on a healthy repo" bug until
  the FR2 branch is widened. The same trap waits for `--replace-all`, `--unset-all --fixed-value`,
  and any other `--`-prefixed form added later.
- **[R3] `WORKTREE_DIR` is assigned eagerly at `:160` and is the only non-function-body consumer of
  `GIT_ROOT`.** Anything that repairs `GIT_ROOT` after that line must repair `WORKTREE_DIR` too, or
  run before it. A test that only asserts `require_working_tree` returns 0 passes while
  `WORKTREE_DIR` points inside `.git/worktrees/`.
- **[R2] Never let a commit boundary fall between the guard-narrowing and the polarity reversal.**
  Guard-narrowing alone makes the *unreversed* surgery reachable, which constructs the outage state
  on the operator's own repo at the next session-start `cleanup-merged`.
- **Read the suite's `N/M` summary line, never a piped exit code.** `bash scripts/test-all.sh > log
  2>&1; echo "EXIT=$?"; tail -30 log` reports `tail`'s status — a false green, the most expensive
  direction (2026-08-09 §6).

---

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Wholly-internal developer tooling change to a bash script that ships in the Soleur
plugin, plus one server-side telemetry registration and two architecture records. The load-bearing
engineering concerns are (a) not re-opening the `#5934` / `#6184` char-device-mask protections, which
the narrowed guard preserves by construction and three ACs pin; (b) the polarity reversal's effect on
the server-side bare git-data surface, currently zero because that host is unprovisioned; and (c) the
version-scoped nature of the `git worktree add` measurement, mitigated by the per-worktree seed which
is correct independent of git version. No new dependency, no new runtime process, no schema change.

### Product/UX Gate

Not applicable. The mechanical UI-surface override did not fire: `## Files to Edit` and
`## Files to Create` contain no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any
other UI-surface path. Product was not flagged as relevant by the domain sweep. Tier: **NONE**.

**CPO sign-off:** required by the `single-user incident` threshold (§ *User-Brand Impact*). No
brainstorm preceded this plan, so there is no carry-forward; CPO must review the threshold framing
and the *User-Brand Impact* declarations before `/work` begins.

### Gates that did not fire

- **GDPR / Compliance (2.7):** no regulated-data surface. No schema, migration, auth flow, API route,
  or `.sql` file is touched; no LLM/external-API processing of operator data is introduced; no new
  artifact-distribution surface. None of triggers (a)–(d) fire. Skipped.
- **Infrastructure-as-Code (2.8):** no server, service, cron, vendor account, DNS record, cert,
  secret, or firewall rule. Pure code change against already-provisioned surfaces. Skipped.
- **Encryption Posture (2.11):** no persistent store and no new cross-component connection.
  Skipped.
- **Soak Follow-Through (2.9.1):** no acceptance criterion is time-gated; nothing closes on a soak.
  Skipped.
- **Network-Outage Checklist (1.4):** the feature description matches none of the trigger patterns
  (`SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`, `502/503/504`,
  `handshake`, `EHOSTUNREACH`, `ECONNRESET`), and no `provisioner`/`connection` Terraform block is
  in scope. Skipped.
- **Community discovery (1.5) / functional overlap (1.5b):** the change is a guard-condition fix
  inside an existing internal bash script with no external analogue; no uncovered stack is
  introduced. No registry search would return an applicable artifact.
- **External research (1.6):** skipped. The authoritative source for every behavioural question here
  is the installed `git` binary, which was measured directly (5-row matrix + 4 supplementary
  fixtures). Vendor documentation would be weaker evidence than the measurement.

---

## Plan Review Revisions (2026-08-10)

7-agent panel. Eng panel escalated to 5 by the `single-user incident` threshold
(dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist,
spec-flow-analyzer). Named panel activated by an independent relevance read of the plan body:
`cto` (devex — a 2651-line bash script on a self-hosted CLI) and `cpo` (the threshold requires
sign-off). `ux-design-lead` and `cmo` were **not** activated: the mechanical UI-surface scan over
`## Files to Edit` + `## Files to Create` found no `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx`, or any other UI-surface path.

### Mechanical findings — applied above

| Ref | Severity | Source | Finding |
|---|---|---|---|
| **R1** | **P0** | architecture-strategist | `--unset-all` bypasses `atomic_git_config`'s FR2 idempotence and exits 5 on an absent key → Phase 3 as written wedges **every healthy repo**. Independently re-verified against `:448-460` and live git 2.53.0 before applying. |
| **R2** | **P0** | kieran | Phase 2 alone makes the *unreversed* surgery reachable → must be atomic with Phase 3. |
| **R3** | **P0** | spec-flow | `WORKTREE_DIR` (`:160`) is a stale consumer omitted from Phase 5's recompute list. |
| **R5** | **P0** | spec-flow | Self-heal failure path untested and reuses the unhelpful message this plan criticises. |
| **R7** | **P0** | spec-flow | The mechanic that heals the *other* thirteen worktrees was never stated anywhere. |
| R6 | P1 | dhh | 3 markers → 2; `branch=ok\|failed` matches the plan's own `BARE_POISON` convention. |
| R8 | P1 | kieran | Case 1 attributed the fix to `ensure_bare_config`; it is actually Phase 5. |
| R10 | P1 | kieran | AC8's grep reaches 2 of the 3 comment sites Phase 3 step 6 promises to fix. |
| R11 | P1 | dhh | Phase 4 lacked any justification *given Phase 5 exists*. |
| R9 | P2 | kieran | AC7 was a bare absence-grep that its own Phase 3 prose would false-fail. |
| — | P2 | kieran | Phase 3 never addressed the fourth write block (`:684-694`) → now step 7. |
| — | P2 | kieran/arch | Sibling test 23 becomes stale documentation under the new guard → AC7a. |
| R12–R14 | P2 | cto/arch | ADR-173: widen the re-evaluation trigger, cite `worktree-config-seed.ts` by path, record the cross-surface convergence. |
| — | P2 | arch | Phase 5 path resolution not pinned to `--absolute-git-dir` as Phase 4 is → R4. |
| — | P2 | arch | Narrowed guard's residual row-2/row-3 ambiguity → new negative case 14. |
| — | P2 | cto | Markers lacked `git_version`; no detection for a git-native shared-config de-bare. |
| — | P2 | cto | `## Deferrals: None` contradicted the plan's own facts 2 and 3 → one deferral filed. |
| — | — | cpo | **SIGN-OFF: APPROVED**, no blocking conditions. Non-blocking: name the live alpha-tester exposure in `## User-Brand Impact` — applied. |

Verified-correct by the panel and recorded so they are not re-litigated: the `BASH_SOURCE == $0`
guard exists (`:2649`); `scripts/test-all.sh:743` globs `plugins/soleur/test/*.test.sh`;
`test-helpers.sh` exposes all five cited helpers; every quoted anchor and line citation in this
plan checks out verbatim; `git-data-provision.sh` does no config surgery; ADR-172 is the highest
existing ordinal; and `ensure_bare_config` ↔ `worktree-config-seed.ts` do **not** oscillate.

### Dissent — surfaced, NOT auto-applied

`code-simplicity-reviewer` argued for cutting Phase 4 and Phase 5 entirely, folding `ADR-173` into
the `ADR-099` amendment, and keeping one marker — roughly a third of the plan's scope. It is a
well-argued minimal position and it was **not** applied. Recorded in
`knowledge-base/project/specs/feat-one-shot-7394-worktree-manager-bare-repo-layout/decision-challenges.md`
for operator adjudication (headless run — persisted rather than asked, per ADR-084).

Why the plan holds its scope, on the panel's own evidence:

- **The simplification panel split.** `dhh-rails-reviewer` — the other simplification lens —
  independently concluded Phase 5 *"is not optional"* because Phases 2+3 structurally cannot close
  the catch-22 (an already-poisoned worktree refuses every subcommand, **including** the ones that
  would run the repair, because `IS_BARE`/`IS_IN_WORKTREE` are computed at source time). A split
  simplification panel does not trigger the "both panels fire → prefer delete" rule.
- **Cutting Phase 5 would fail to fix the reported bug.** `spec-flow-analyzer` traced the actual
  failing subcommand and confirmed `create_draft_pr` (`:2419`) calls `require_working_tree` and
  never `ensure_bare_config`. Phase 5 is the *only* phase reachable from `draft-pr`. The issue is
  titled against `draft-pr`.
- **`architecture-strategist` explicitly endorsed the two-ADR structure** as "architecturally sound
  and appropriately scoped", against the fold-in proposal.
- On marker cardinality the two simplification reviewers disagreed (3→1 vs 3→2); the plan took
  dhh's 3→2, which is the one consistent with the convention `BARE_POISON` already establishes.
