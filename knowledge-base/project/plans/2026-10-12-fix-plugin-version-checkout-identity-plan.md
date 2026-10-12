---
title: "fix: plugin version banner for an in-place (local folder) install"
type: fix
date: 2026-10-12
slug: plugin-version-checkout-identity
branch: fix-version-banner-inplace-install
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix: plugin version banner for an in-place (local folder) install

## Overview

The plugin-version resolver (`plugins/soleur/scripts/plugin-version.sh`, shared by the SessionStart
banner `plugins/soleur/hooks/version-banner.sh`, `/soleur:version` and `/soleur:help`, shipped by
#10064 on 2026-10-12) names an install from a manifest `version` key or from a 12-hex cache
directory name. A plugin loaded straight from a local Folder marketplace has neither, so the banner
stays silent and the version command prints `unknown`.

Reproduced against this machine's real install (read-only):

```text
$ claude plugin list    -> soleur@soleur  Version: e1bed15769a6  Read from: /data/git-repositories/jikig-ai/soleur/plugins/soleur
$ CLAUDE_PLUGIN_ROOT=/data/git-repositories/jikig-ai/soleur/plugins/soleur bash plugins/soleur/hooks/version-banner.sh
(prints nothing, rc 0)
$ CLAUDE_PLUGIN_ROOT=<same> bash plugins/soleur/scripts/plugin-version.sh --installed
source=unknown
```

This plan adds a third identity source, `source=checkout`: read the checkout's git HEAD with plain
file reads (never running git against it) and report `commit=<first 12>`. The banner then reads
`Soleur commit <sha12> (local checkout)`, `/soleur:version` gives local-folder update guidance, the
compare logic treats a checkout like a commit install, and the docs/legal wording that described
"a commit-hash install" is widened where (and only where) the new source changes a claim.

## Research Insights

### Premise Validation (Phase 0.6)

No issue numbers are cited. Checked by reference: PR #10064 is `MERGED` (2026-10-12T18:05:57Z) and
`plugin-version.sh`, `version-banner.sh`, `commands/version.md` exist on this branch's base;
`worktree-manager.sh` has `sync` (alias of `sync-bare-files`) but `sync_bare_files` only mirrors files
from the LOCAL HEAD (`read-tree` + `checkout-index`) and does not fetch; the fetch precedent in the
same script is `git fetch --no-tags origin main:main`. `.claude-plugin/marketplace.json` names the
marketplace `soleur` with `plugins[0].source` `./plugins/soleur`, so `claude plugin update
soleur@soleur` is the right pair for a folder marketplace. The ADR corpus has no ADR on the resolver
(`grep -l 'plugin-version.sh\|version-banner' knowledge-base/engineering/architecture/decisions/*.md`
returns nothing); ADR-182 D1 (keyless manifests) is unaffected. The reproduction in the brief held on
this machine. The real layout is a BARE repo in `<top>/.git` (`core.bare=true`, `HEAD` = `ref:
refs/heads/main`), `refs/heads/main` is ONLY in `packed-refs` (no loose file), and every feature
worktree's `.git` is a file (`gitdir: <top>/.git/worktrees/<name>`, per-worktree `HEAD`, `commondir` =
`../..`). So the packed-refs path is the production path, not an edge case. (A `git fetch origin
main:main` writes a LOOSE `refs/heads/main`, so after an update the loose path is the live one: both
must work.)

### Property List and Cut List (Phase 0.6b)

Properties the ask buys (each observable):

- **P1** An in-place folder install shows `Soleur commit <sha12> (local checkout)` at session start
  with no network call.
- **P2** The resolver never reports an identity it did not read from the plugin's own checkout, and
  never executes anything the found repository controls.
- **P3** Hostile or garbage repository state (malicious `.git/config`, FIFO or unreadable `HEAD`,
  reftable, sha-256, traversal refs) degrades to silence, never a hang or an error, at every session
  start of every project.
- **P4** `/soleur:version` and `/soleur:help` state the checkout identity accurately and give
  local-folder update guidance, never the GitHub marketplace commands.
- **P5** The relation logic works for a checkout like a commit install, and the legal/doc claims
  stay true ("nothing is sent without opt-in").

Cut List (mechanism -> property -> what already covers it or why it is cut):

- Free walk-up to the first `.git` -> P1 -> the layout-anchored lookup buys P1 for every supported
  layout; the free walk adds the dotfiles-`$HOME` and ambient-`/tmp/.git` hazards (P2). CUT.
- `marketplace.json` content or presence check in the anchor -> P2 -> `basename soleur` + parent
  `plugins` + `<top>/.git` already pins the layout, and a mirrored file can be stale in the bare layout,
  which would re-silence the banner in the bug's own scenario (CTO R2, DHH, simplicity). CUT.
- Back-pointer verification of `<gitdir>/gitdir` -> none -> anyone who controls the plugin root can
  already forge the identity; it also breaks on moved worktrees. CUT (CTO).
- Per-component ref-name allowlist, `.lock` / trailing-`.` rules, `<common>/reftable` directory check
  -> P2/P3 -> the final 40-hex gate plus a deny-list covers traversal; reftable falls through to
  unknown because no loose/packed entry exists; an allowlist would silently hide `fix/issue-#12`
  (CTO R1, all three reviewers). CUT.
- New `marketplace=` detection, new `reason=` codes, `curl -w %{http_code}` plumbing -> P4 -> one
  sentence in `version.md` covers `compare-failed` for an unpublished HEAD. CUT.
- `git merge-base --is-ancestor` (CLO suggestion) -> P5 -> runs git against the repo; forbidden. CUT.
- Compare only when on `main` -> P5/privacy -> a local `main` can carry unpublished commits too. CUT.
- reftable / sha-256 parsing, real-git reftable and sha-256 fixture generation -> none -> silent
  unknown is the answer; hand-written fixtures cover both without a git-version dependency. CUT.
- Per-key malicious-config sentinels (five), FIFO `packed-refs`, 1 MiB HEAD, `chmod 000`, non-ASCII
  branch, `grep -c read_file_capped` count-equality, named-set vacuity floor, standing 10-row mutation
  AC -> P2/P3 -> the recording `git` stub (`ncalls git == 0`) proves "never run git" for every config
  key at once; one chokepoint means one FIFO row suffices; the mutation matrix runs once during work.
  CUT (DHH, simplicity).
- Cookie Policy / Disclaimer speculative grep, runbook sequence duplication, Phase 6 interactive
  fallback and "closes #10064's M4" -> none -> CUT (the CLO named exactly three policies; the runbook
  gets a one-sentence pointer; M4 is its own measurement).
- A new ADR -> none -> a plugin-local identity source with no trust-boundary change. CUT.

### Institutional learnings applied

- `2026-10-12-a-global-hook-that-shells-out-inherits-the-project-it-runs-in.md`: the cwd and ambient
  environment of a global hook are inputs; isolate, key state per identity, let "no problem" expire
  into "unknown". This plan carries the rule one step further: the repository under the plugin root
  is also untrusted input, so it is read with file reads and never handed to git.
- `2026-04-02-bare-repo-config-bleed-worktrees.md` and `2026-03-18-git-common-dir-vs-show-toplevel-semantics.md`:
  per-worktree `HEAD` lives in `<gitdir>/`, branch refs and `packed-refs` in the common dir
  (`commondir`); shared `core.bare=true` is never read as per-worktree. The resolver never reads
  `config` at all.
- `2026-04-03-git-env-var-leak-resolve-git-root-test.md` and AGENTS.md "Test Fixture Conventions":
  any fixture step that spawns real git uses `git_fixture_env`; the shell tripwire (rc 97) is not a
  flake.
- `2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md` and
  `2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md`: exact case floors, per-value
  assertions and a mutation battery are all needed; one sample proves nothing about a set.
- `2026-07-16-a-gate-that-proves-it-cannot-fail-open-shipped-its-own-proof-unwired.md`: both suites
  are auto-discovered by the `plugins/soleur/test/*.test.sh` glob and listed in `scripts/suite-shard-legs.tsv`;
  they stay registered.
- `2026-02-21-cookie-free-analytics-legal-update-pattern.md`: a network-touching behaviour change
  updates every legal document in lockstep (canonical, Eleventy mirror, SHA pin).
- plan Sharp Edge "a hand-written parser for attacker-written text must fixture the LANGUAGE's grammar,
  not the feature's use cases": the git formats parsed here (`.git` pointer file, `HEAD`,
  `refs/heads/*`, `packed-refs`) are enumerated in a grammar census (Test Scenarios T2) from
  `gitrepository-layout`, `git-check-ref-format` and the packed-refs format, one table row per rule.

### Open Code-Review Overlap

`gh issue list --label code-review --state open` (200) matched none of the planned files. None.

### Functional overlap / community discovery

No uncovered stack and no community artifact overlaps a 60-line resolver extension; both checks
skipped silently.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "walk up from the root to find a `.git`" | A free walk-up reports the wrong repo when the plugin root is any non-matching directory under a `$HOME` that is itself a git repo (dotfiles) or under an ambient `/tmp/.git`; the resolver's contract is "never reports a version it did not read". | Layout-anchored lookup (CTO F1, R2): `root` must be `<top>/plugins/soleur` and `<top>/.git` must exist (`-e`: a worktree's is a file). Deliberate narrowing of "walk up"; every miss is `source=unknown`. Covers bare-in-`.git`, clone, linked worktree and `--plugin-dir` into a worktree. |
| "(HEAD -> refs/... -> loose ref file or packed-refs)" | On the real machine `main` exists ONLY in `packed-refs`; after a `fetch origin main:main` it is a loose file; worktree refs resolve through `commondir`. | Both paths are first-class fixtures; `commondir` is resolved. |
| "The compare/latest logic treats a checkout like a commit install" | The compare URL then carries a local HEAD hash that may be unpublished; the policies say "your installed commit hash" next to marketplace installs. | Kept (operator default, CTO F4). CLO: clarification-only wording in 3 policies + 3 mirrors + SHA pin. CLO's preferred alternative (no compare for checkout) is recorded in `decision-challenges.md`. |
| "`git pull`/sync the folder (worktree-manager.sh sync)" | `worktree-manager.sh sync` mirrors files from the LOCAL HEAD and never fetches; a bare root has no work tree to `git pull` in. | Guidance and the post-merge steps say: bare layout `git fetch --no-tags origin main:main` THEN `worktree-manager.sh sync`; normal clone `git pull` (CTO R6). |
| "update ... harness-parity/README/legal wording only where the new source changes a claim" | "for a commit-hash install only" appears in `version.md`, README, `model.c4`, the resolver header (line "Relation for a commit-hash install"), a test comment (`version-banner-hook.test.sh` "Same for a commit-hash install"), and the three policies + mirrors; `help.md` carries the key list and the version-line template instead. | One sweep (Phase 4); `grep -rn 'commit-hash install' plugins/ docs/ knowledge-base/engineering/` must end with each hit widened or deliberately marketplace-only. |
| "the banner is silent in-place" | Also `--plugin-dir` into a worktree and any dev running the script from a worktree resolve to unknown today. | Same code path fixes all of them; row for a worktree-style root. |
| (implicit) the live banner renders | #10064's M4 (does Claude Code render a hook `systemMessage`?) was "not measured". | Phase 6 captures the headless line; absence is a follow-up issue, not a widened PR (CTO R9). |

## Decisions (technical rulings, persisted in `decision-challenges.md`)

All rows recorded as `Ruled by <agent>, 2026-10-12: <decision> - <rationale>`. Items 1-3 were revised
by the CTO after plan review (R1-R5).

1. **Lookup shape (CTO F1, R2).** Layout-anchored, no free walk-up, no `marketplace.json` read.
   Predicate (lexical on `${root%/}`, no `realpath`): `basename(root)==soleur`,
   `basename(dirname(root))==plugins`, `top=dirname(dirname(root))`, and `[[ -e "$top/.git" ]]`
   (directory, or file whose first line is `gitdir: <path>`). Runs only when there is no manifest
   `version` and no 12-hex directory name (precedence: manifest, 12-hex dir, checkout, unknown). A cache
   install never takes it (its basename is not `soleur`). A symlinked root whose basename is not
   `soleur` goes silent (accepted; Claude Code passes real paths).
2. **Ref resolution (CTO F2, R1, R5).** `.git` file: first line `gitdir: <path>` (relative to the file's
   directory or absolute); per-worktree `HEAD` from `<gitdir>/HEAD`; `commondir` resolved (relative to
   gitdir) for refs and `packed-refs`; no back-pointer check. `HEAD` is exactly `^[0-9a-f]{40}$`
   (detached) or `ref: refs/heads/<name>` (one symbolic hop). Ref-name DENY-list (git
   check-ref-format style): control chars, space, `~ ^ : ? * [ \`, `@{`, `..`, `//`, leading or trailing
   `/`, any component starting with `.` (rejects reftable's `refs/heads/.invalid`); written as a regex
   plus `case` patterns, no arrays (bash 3.2 + `set -u` safe). If the loose ref path EXISTS it must be a
   regular file holding exactly 40 lowercase hex (trailing `\n` allowed) or the result is unknown (no
   fall-through to a stale packed entry; a `ref:` inside it is unknown, no second hop); only when the
   loose path is ABSENT, `packed-refs` (skip `#` and `^` lines, exact `$2==ref`, `$1` validated in bash).
   64-hex (sha-256) fails the 40-hex test -> unknown, never truncated.
3. **Robustness (CTO F3, R3, R5).** Small files (`.git` pointer, `commondir`, `HEAD`, loose ref): `[[ -f
   path ]]` then `IFS= read -r -n 512 var < path 2>/dev/null || true` (builtin, bounded, silent on NUL; a
   result of exactly 512 chars means truncated -> unknown). `packed-refs`: `[[ -f ]]` then
   `LC_ALL=C head -c 8388609 | awk`; more than 8388608 bytes -> unknown (no mid-line truncation). `-f`
   follows symlinks and rejects FIFOs and devices, so a FIFO `HEAD` cannot hang the hook. Nothing from the
   repo is executed, sourced or `eval`ed; `GIT_*` variables are ignored; `config`, `.gitattributes` and
   `hooks/` are never opened. Only a value that passed the 40-hex test is ever printed, so a symlinked
   HEAD is no content-injection channel. A NUL byte inside HEAD is dropped by `read`; the spliced string
   is still fully validated and names a real ref, which an attacker able to write HEAD could name
   directly, so this is documented as harmless, not rejected.
4. **Relation and cache (CTO F4, R4; operator default).** `compute_relation` treats `checkout` as
   `commit`: tag sha-prefix equality, else one unauthenticated compare call carrying only the 12-hex sha
   (never a branch name, path or remote URL). A HEAD not on the release line yields
   `diverged`/`compare-failed` -> `relation=unknown`, silent. Cache file for a checkout is the stable
   `latest-release.checkout` (not per-sha), while `INST_ID` stays the sha12 so `load_cache`'s existing
   `relation_for != INST_ID` check turns an entry written for another commit into `cache=corrupt`: one
   file instead of one per local commit. `corrupt` with `SOLEUR_UPDATE_CHECK=1` spawns the usual
   background refresh (at most one per 600 s lock) and stays silent when unset. A failed lookup writes no
   cache (existing behaviour); a failed compare is cached as `unknown` for at most one hour (existing
   `FAIL_FRESH_S`). Banner warning logic is unchanged (fires only on `older`, only with
   `SOLEUR_UPDATE_CHECK=1`).
5. **Wording (CTO F5, R6, R8).** Banner `Soleur commit <sha12> (local checkout)`; `version.md` Installed
   line `commit <sha12> (local checkout)  (source: checkout)`; `marketplace=` stays absent for a
   checkout; guidance chosen purely from `source=checkout`, marketplace fixed to `soleur` (the repo's
   `marketplace.json` name). The `source=checkout` arm is placed FIRST, in both the Step 2 template line
   and the "Choose by" list, so the GitHub pair cannot be chosen for it. Arm text: bare layout run `git
   fetch --no-tags origin main:main` in the repo root, then
   `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh sync` (`sync` only mirrors the local
   `main`, it does not fetch); normal clone `git pull`; then `claude plugin marketplace update soleur`
   and `claude plugin update soleur@soleur`, restart. One line for a `--plugin-dir` launch (marketplace
   commands do not apply; restart with the updated folder); one line that the identity is the checkout's
   HEAD commit, not its uncommitted or unsynced files; one line that a moving checkout re-checks on every
   new commit. These caveats live ONLY in `version.md`; README and the runbook carry one sentence and a
   pointer.
6. **Legal (CLO).** If the compare hash is sent, clarification-only edits (not substantive): privacy
   policy 4.1, GDPR policy ~line 53, DPD 3.1(e), each with an October 12 "Last Updated" note, mirrored to
   `plugins/soleur/docs/pages/legal/`, SHA-pinned in `legal-doc-shas.ts` (computed LAST, after the final
   edit). The recipient stays explicit (GitHub receives the hash; Jikigai receives nothing). No LIA, Art.
   30, sub-processor or compliance-posture change. "Nothing is sent without opt-in" stays accurate.
7. **ADR / C4 (CTO F5c).** No ADR. One C4 text edit: `model.c4` `plugin -> github` edge says "for a
   commit-hash install only"; widen to "commit-hash or local-checkout install", regenerate
   `model.likec4.json` (pre-commit hook / `bash scripts/regenerate-c4-model.sh`).
8. **Fixtures and test weight (plan author, CTO R7).** Hand-written fixture trees for every shape
   (no git needed, no tripwire exposure, exact bytes controlled) with ONE table-driven silent-garbage
   loop; ONE malicious-config fixture asserted through the recording `git` stub; ONE real-git witness row
   (the same fixture fires a `core.fsmonitor` sentinel under `git status`), gated on git; TWO real-git
   parity rows (a bare-in-`.git` clone with packed refs, and a linked worktree). Gated rows call
   `skip_case` with run-deficit credit so the exact `RUNS` equality survives a host without git.

## Architecture Decision (ADR/C4)

No architectural decision: a plugin-local identity source, no ownership, trust-boundary, substrate
or resolver-dispatch change; ADR-182 D1 (keyless manifests) is untouched. C4 completeness check
(all three of `model.c4`, `views.c4`, `spec.c4` read): external actors (the local user), external
systems (github.com via the existing `plugin -> github` edge; no new vendor, no new store), the
actor-to-surface relationship (user runs the plugin in place) are already modeled. The only falsified
sentence is the `plugin -> github` edge's "for a commit-hash install only", edited in Phase 4 and
guarded by a green `bash plugins/soleur/test/c4-count-parity.test.sh` (no derived count moves) plus the
C4 syntax/render tests under `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.

## Implementation Phases

### Phase 0 - RED first (`cq-write-failing-tests-before`)

Write the new rows in both suites (below) before touching the resolver; run both and record that the
checkout rows fail against the current code (and that every PRE-EXISTING row still passes, i.e. the
floors only fail on the new total). Do not edit the floors until Phase 5.

### Phase 1 - resolver (`plugins/soleur/scripts/plugin-version.sh`)

- Add `read_small file` (the `[[ -f ]]` + `IFS= read -r -n 512` primitive, sets a global; returns 1 on
  absent/irregular/over-length) and `packed_ref_sha common ref` (the capped awk stream). These two are
  the only readers of repository bytes. Tools stay inside the hook's restricted-PATH allowlist (`bash
  sh env dirname basename cat date stat mkdir rmdir rm mv chmod mktemp sed grep awk head tail tr sort cut
  jq`); no `readlink`, `realpath`, `wc`, `od`, `dd`, `xxd`. Bash 3.2 safe: no `mapfile`, `readarray`,
  `declare -A`, `${x,,}`, `[[ -v ]]`, no array splitting of the ref name (`set -u` plus an empty array
  aborts on 3.2); POSIX awk only.
- Add `resolve_checkout_commit root` -> sets/prints a 40-hex sha or nothing, implementing Decisions 1-3.
  Ref validation is a pure function (`valid_ref_name`) of regex + `case` patterns.
- In `resolve_installed`, after the 12-hex branch fails: call it; on success `INST_SOURCE=checkout
  INST_COMMIT=${sha:0:12} INST_ID=${sha:0:12}`, and set the cache file to `latest-release.checkout`
  (one-line change where `CACHE_FILE` is derived); else `unknown` as today. `INST_MARKETPLACE` stays
  empty.
- `compute_relation`: `commit)` becomes `commit|checkout)`. `print_installed` needs no change. Update the
  header comment (modes line, identity precedence, "Relation for a commit-hash install" -> commit-hash or
  checkout install).
- Never add a `git` invocation outside `fetch_latest`; `fetch_latest` is unchanged (cwd `/`, isolated).

### Phase 2 - hook (`plugins/soleur/hooks/version-banner.sh`)

- Add `checkout)  [[ "$commit" =~ ^[0-9a-f]{12}$ ]] || return 0; label="commit $commit (local checkout)" ;;`
  to the `case "$source"` (a strict whitelist; any other source value stays silent). Update the header
  comment. No change to refresh spawning: `spawn_refresh` already passes `CLAUDE_PLUGIN_ROOT` to the
  child, which re-runs the same resolver.

### Phase 3 - commands

- `commands/version.md`: the top paragraph says "for a commit-hash or local-checkout install only" and
  that the hash sent is the checkout's HEAD (possibly unpublished); Step 1 key notes list
  `source=checkout`; Installed line + "Installed line" rules add the `checkout` arm; the `compare-failed`
  sentence gains "a local checkout may be on a commit that was never published"; a `source=checkout` arm
  FIRST in the Step 2 template line and the "Choose by" list carrying the Decision 5 text. Use only
  `/soleur:`-prefixed slash forms (the harness-parity census flags bare `/version`).
- `commands/help.md`: the key list in Step 1 gains `source=checkout`; the version-line template gains
  `Soleur commit <commit> (local checkout)`.

### Phase 4 - docs, C4, legal

- `plugins/soleur/README.md` "Version Visibility": one in-place sentence plus a pointer to
  `/soleur:version`; "for a commit-hash install only" widened; "It makes no network call" unchanged and
  re-verified.
- `knowledge-base/engineering/operations/runbooks/plugin-delivery-recovery.md`: one sentence in "Reading
  `claude plugin list` / /soleur:version" pointing at the local-checkout arm of `/soleur:version`; no
  duplicated sequence.
- `model.c4` edge text widened; regenerate `model.likec4.json`.
- Legal (CLO wording; clarification only), canonical + mirror for each of: `privacy-policy.md` 4.1 (the
  hash clause becomes: "the 12-character commit hash; if you run the Plugin in place from a local git
  checkout, that is your checkout's current commit, which may be one you have never pushed anywhere, so
  the hash of an unpublished commit can reach GitHub this way"), `gdpr-policy.md` (~line 53: "for a local
  git checkout, the hash of its current commit, whether or not that commit has been published"),
  `data-protection-disclosure.md` 3.1(e) (same clause) and the 9.1(b) cross-reference check. Each gets an
  October 12, 2026 "Last Updated" note: "Clarification only; no change to the substance of processing ...
  Jikigai receives nothing; no new recipient, category, sub-processor or transfer." On the Eleventy
  mirrors the hero uses `Last Updated May 12, 2026` (no colon) and the body `**Last Updated:**`: any AC
  grep tolerates both (`Last Updated[: *]+October 12, 2026`). Compute `legal-doc-shas.ts` LAST
  (`sha256sum docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`).

### Phase 5 - floors and gates

Recompute the exact floors by running each suite after the new rows land, then set them as literals:
`MIN_CASES`/`MIN_RUNS` in `plugin-version.test.sh` (currently exactly 414 / 218; the verdict is `!=`;
add `SKIP_RUN_DEFICIT` credit to its RUNS check, as the hook suite already has) and
`MIN_CASES`/`MIN_RUNS`/`MIN_BANNERS` in `version-banner-hook.test.sh` (currently 210 / 93 / 79; those are
`<` floors, so set them to the new totals). Prove one floor red by deleting one new row. Then the gates in
Verification below, plus `npx markdownlint-cli2` over the plan, tasks and edited docs.

### Phase 6 - post-merge live verification (ship/postmerge; authorized by the brief)

On the maintainer machine, after the merge, in the bare root `/data/git-repositories/jikig-ai/soleur`:
(1) `git fetch --no-tags origin main:main` then
`bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh sync` (`sync` alone only mirrors the
stale local `main`); (2) `claude plugin marketplace update soleur && claude plugin update soleur@soleur`;
(3) one fresh headless session with hook events visible:

```bash
claude plugin list | grep -A1 'soleur@soleur'
claude -p "reply ok" --output-format stream-json --verbose --include-hook-events 2>&1 \
  | grep -o 'Soleur commit [0-9a-f]\{12\} (local checkout)'
```

Paste both outputs: the 12 hex must equal `claude plugin list`'s `Version:`. If nothing matches, file a
follow-up issue with the captured events instead of widening this PR.

## Files to Edit

- `plugins/soleur/scripts/plugin-version.sh`
- `plugins/soleur/hooks/version-banner.sh`
- `plugins/soleur/commands/version.md`
- `plugins/soleur/commands/help.md`
- `plugins/soleur/test/plugin-version.test.sh`
- `plugins/soleur/test/version-banner-hook.test.sh`
- `plugins/soleur/README.md`
- `knowledge-base/engineering/operations/runbooks/plugin-delivery-recovery.md` (one sentence)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and the regenerated `model.likec4.json`)
- `docs/legal/privacy-policy.md`, `docs/legal/gdpr-policy.md`, `docs/legal/data-protection-disclosure.md`
- `plugins/soleur/docs/pages/legal/privacy-policy.md`, `.../gdpr-policy.md`, `.../data-protection-disclosure.md`
- `apps/web-platform/lib/legal/legal-doc-shas.ts`
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` (only if the scanner reports a new site; the
  resolver change adds reads only, no relative-destination writes)

## Files to Create

None (new fixtures live inside the two existing suites). Spec artifacts:
`knowledge-base/project/specs/fix-version-banner-inplace-install/{tasks.md,decision-challenges.md}`.

## User-Brand Impact

**If this lands broken, the user experiences:** a Soleur session start that hangs, prints an error, or
shows the wrong commit (another repository's HEAD) for every user running the plugin from a local
folder, or a banner that stays silent exactly as today.

**If this leaks, the user's workflow is exposed via:** the opt-in/explicit compare request, which now
may carry the 12-character hash of an unpublished local commit (no content, no branch name, no remote
URL; nothing goes to Jikigai), disclosed by the clarification-only legal wording.

**Brand-survival threshold:** aggregate pattern

(Threshold decision, challengeable: a bad banner is a repeated-trust paper cut across in-place
installs, not a single-user data or money incident; the hook fails open and the only off-box datum is
a hash behind an explicit opt-in. `none` would be wrong because the hook reads untrusted files at every
session start of every project.)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add a third identity source in the resolver, source=checkout: when CLAUDE_PLUGIN_ROOT has no manifest version and no 12-hex cache dir name, walk up from the root to find a `.git`" | Phase 1; Decision 1 (layout-anchored narrowing, justified) | mapped |
| 2 | "read HEAD by PLAIN FILE READS ONLY (HEAD -> refs/... -> loose ref file or packed-refs; detached HEAD holds the sha). Never run git against that repo" | Phase 1; Decisions 2-3; Guard 1 | mapped |
| 3 | "Validate the sha is 40 hex, print commit=<first 12>, source=checkout." | Phase 1 | mapped |
| 4 | "Banner/help/version wording for source=checkout: \"Soleur commit <sha12> (local checkout)\"" | Phases 2-3; Decision 5 | mapped |
| 5 | "/soleur:version update guidance for a local-folder marketplace must say to `git pull`/sync the folder (worktree-manager.sh sync) then `claude plugin marketplace update soleur && claude plugin update soleur@soleur`, and must NOT suggest the GitHub marketplace commands." | Phase 3 `version.md` arm; Decision 5 (fetch added: `sync` does not fetch) | mapped |
| 6 | "The compare/latest logic treats a checkout like a commit install." | Phase 1 `compute_relation`; Decision 4 | mapped |
| 7 | "Tests in plugins/soleur/test/plugin-version.test.sh and version-banner-hook.test.sh: fixtures for bare-with-mirrored-files, a normal clone, a git worktree (.git file), packed-refs only, detached HEAD, a malicious .git/config and an unreadable/garbage HEAD (must stay silent, never run git)" | Test Scenarios T1-T7; Phase 0 | mapped |
| 8 | "update the exact case floors, vacuity floors and the harness-parity/README/legal wording only where the new source changes a claim (privacy docs say nothing is sent without opt-in; keep that true)" | Phase 4 (wording), Phase 5 (floors), Decision 6 | mapped |
| 9 | "Update docs (plugins/soleur/README.md version section)." | Phase 4 README | mapped |
| 10 | "Verify live after merge: run `claude plugin marketplace update soleur && claude plugin update soleur@soleur`, restart, confirm a new session shows the banner, and paste the output." | Phase 6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Resolver `resolve_checkout_commit`, `read_small`, `packed_ref_sha` | "read HEAD by PLAIN FILE READS ONLY" (asks 1-3) | asked |
| Layout anchor (`plugins/soleur` basename + `.git` presence) | "walk up from the root to find a `.git`" (ask 1) | inferred - justification: the unanchored walk reports a dotfiles or `/tmp` repo's HEAD as Soleur's identity, violating the resolver's "never reports a version it did not read" contract; CTO F1/R2 |
| FIFO / size caps / `[[ -f ]]` | "an unreadable/garbage HEAD (must stay silent, never run git)" (ask 7) | asked |
| reftable and sha-256 rows | "an unreadable/garbage HEAD (must stay silent" (ask 7) | asked |
| `commondir` resolution | "a git worktree (.git file)" (ask 7) | asked |
| Stable `latest-release.checkout` cache file | "The compare/latest logic treats a checkout like a commit install." (ask 6) | inferred - justification: per-sha cache files would grow by one never-pruned file per local commit and one compare call per commit under the opt-in check; CTO R4 |
| Hook `checkout)` arm and label | "\"Soleur commit <sha12> (local checkout)\"" (ask 4) | asked |
| `version.md` arm + fetch-then-sync wording | asks 4-5 | asked |
| `help.md` version-line arm | "Banner/help/version wording for source=checkout" (ask 4) | asked |
| README sentence, runbook pointer | "Update docs (plugins/soleur/README.md version section)." (ask 9) | asked (runbook pointer: inferred - justification: `plugin-delivery-recovery.md` documents `/soleur:version` and would otherwise omit the new source) |
| `model.c4` edge text + JSON regen | "the harness-parity/README/legal wording only where the new source changes a claim" (ask 8) | asked |
| Legal clarification edits x6 + SHA pin | same quote (ask 8) | asked |
| Real-git witness + two parity rows | "this gives the same 12 chars `claude plugin list` shows" (ask 1 context) | asked |
| Guard Contract section | "must stay silent, never run git" (ask 7) | asked |
| Post-merge headless capture | "paste the output" (ask 10) | asked |
| Decisions file | "Persist every decision as a row of the `| Item | Class | Ruling |` table" | asked |

### Split Assessment

- Subsystems touched: 4 - `plugins/soleur`, `knowledge-base`, `docs`, `apps/web-platform` (one SHA-pin file)
- Planned files: 20 | Estimated changed lines: ~550 (about 300 in the two suites, ~100 resolver/hook, ~150 docs and legal)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the four roots are claim-coupled, not independent: the legal/doc edits
  describe the code's behaviour (a hash sent in the compare URL), so landing the code first would make
  the policies untrue for a window and landing the docs first would document behaviour that does not
  exist. `apps/web-platform` is one generated pin constant. The seam a split would draw
  (docs-after-code) is the wrong one.

## Acceptance Criteria

- [ ] `CLAUDE_PLUGIN_ROOT=<top>/plugins/soleur bash plugins/soleur/scripts/plugin-version.sh --installed`
  prints `source=checkout` and `commit=<12 hex>` (no `version=`, no `marketplace=`) for each positive
  fixture in T1 (bare-in-`.git` with mirrored files and packed-refs only, normal clone with a loose ref,
  linked worktree with absolute and relative `gitdir:`, loose ref beating a stale packed entry, detached
  HEAD, symlinked HEAD, odd-but-legal branch names).
- [ ] The same roots print `source=unknown` (hook: empty stdout, rc 0, empty stderr, inside the 10 s hook
  budget) for every row of the T2 silent-shapes table (garbage HEAD/refs, grammar census violations,
  FIFO HEAD, over-cap files, anchor misses including a dotfiles ancestor `.git` over an unrelated plain
  directory).
- [ ] Precedence: a manifest `version` beats the checkout; a 12-hex cache directory name beats the
  checkout; the checkout beats `unknown`.
- [ ] Zero git execution: a PATH `git` that records and fails shows `ncalls git == 0` for `--installed`
  and `--cached-latest` on every checkout fixture including the malicious-`config` one, and exactly one
  call (`ls-remote`, cwd `/`, `GIT_DIR` unset, `GIT_CONFIG_GLOBAL=/dev/null`) for `--compare`; the
  malicious fixture's `core.fsmonitor` sentinel stays absent, and the gated witness row proves real git
  fires it on the same fixture.
- [ ] A hook run from a cwd inside a DIFFERENT repository reports the plugin checkout's HEAD, never the
  cwd repo's.
- [ ] Banner: `{"systemMessage": "Soleur commit <sha12> (local checkout)"}` with default settings and
  zero network (restricted-PATH arm: no git/curl/wget call recorded); with `SOLEUR_UPDATE_CHECK=1` and a
  cached `older` answer it appends the existing "newer release vX.Y.Z available" suffix exactly as for a
  commit install; a cache written for another commit reads `cache=corrupt` and, with the opt-in set,
  spawns one refresh (silent when unset); `SOLEUR_DISABLE_VERSION_BANNER=1` and the Codex markers still
  silence it.
- [ ] Relation: checkout vs the tag's own commit -> `current` with no curl; ahead/behind/identical/
  diverged/unparseable map exactly as for `source=commit`; cache file `latest-release.checkout`; the curl
  URL contains only the 12-hex sha and the tag.
- [ ] `version.md`: an anchored extraction of the `source=checkout` arm contains `git fetch --no-tags
  origin main:main`, `worktree-manager.sh sync`, `git pull`, `claude plugin marketplace update soleur`,
  `claude plugin update soleur@soleur`, `--plugin-dir` and "HEAD commit"; that arm and the Step 2
  template line contain no `soleur-marketplace`; the arm precedes the "absent or `soleur-marketplace`"
  bullet; `disable-model-invocation: true` is still in the frontmatter.
- [ ] `grep -rn 'commit-hash install' plugins/ docs/ knowledge-base/engineering/` hits are each widened or
  intentionally marketplace-only; each legal canonical and mirror carry byte-identical new sentences;
  `legal-doc-shas.ts` equals `sha256sum` of the three canonical files; the legal gates, harness-parity
  census, components test and `c4-count-parity` are green.
- [ ] Both suites carry new exact floors; one floor proven red by deleting one new row; `shellcheck -s
  bash` clean on the resolver, hook and both suites; `grep -nE 'mapfile|readarray|declare -A|\$\{[^}]*(,,|\^\^)|\[\[ -v'`
  over the resolver prints nothing; no new `fixture-relative-assert` site; no `rc=97`.
- [ ] The mutation battery of Guard 1 was run once during work (each row RED, then restored GREEN) and its
  result pasted in the PR.
- [ ] Post-merge: the Phase 6 commands ran and their output (12 hex equal to `claude plugin list`
  `Version:`) is pasted in the PR.

## Guard Contract

### Guard 1 - checkout identity is read, never executed, never guessed

**Property.** For any plugin root and any contents of the repository found at its anchored location,
the resolver either prints exactly the first 12 hex characters of a 40-hex object name it read from
that repository's HEAD chain, or prints `source=unknown`; and it never executes, sources or hands to
git anything that repository controls, nor blocks on reading it.

**Assembly.** Every byte the resolver reads from the repository flows through two readers:
`read_small` (the `.git` pointer file, `commondir`, `HEAD`, the loose ref) and `packed_ref_sha`
(`packed-refs`). Every path that can START a lookup flows through `resolve_installed` ->
`resolve_checkout_commit` (the only caller), reached only after the manifest and 12-hex-name branches
fail. The only `git` execution in the resolver is `fetch_latest` (cwd `/`, isolated environment);
`compute_relation` runs `curl` only. Callers that consume the identity: `version-banner.sh` (its `case
"$source"` whitelist), `version.md`, `help.md` - each must gain the `checkout` arm or stay silent. The
"never ran git" half is proven behaviourally by the recording `git` stub, not by a grep over source text.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | In `read_small`, change `[[ -f ]]` to `[[ -e ]]` | RED: the FIFO-HEAD row exceeds its 5 s bound |
| 2 | Add `git -C "$top" rev-parse HEAD` anywhere in the checkout path | RED: the recording `git` stub logs a call on every `--installed` checkout row |
| 3 | Replace the layout anchor with "first ancestor containing `.git`" | RED: the dotfiles-ancestor row prints `source=checkout` |
| 4 | Accept 39/41/64-hex or uppercase in the validator | RED: the garbage-HEAD table rows print a commit |
| 5 | Make `resolve_checkout_commit` always return nothing (own dispatch dead) | RED: every positive fixture row AND the count-based vacuity floor (positive rows that printed `source=checkout` >= N) |
| 6 | Reorder: try the checkout before the manifest version | RED: the manifest-version-inside-a-checkout row prints `source=checkout` (order property, observed inside the window where both are present) |
| 7 | For a worktree read `HEAD` from `<top>/.git/HEAD` instead of `<gitdir>/HEAD` | RED: the linked-worktree row returns the bare repo's `main` sha, which the fixture makes different from the worktree branch sha |
| 8 | Banner arm prints the label without the `^[0-9a-f]{12}$` whitelist | RED: a fake resolver emitting `source=checkout` with `commit=ZZZ` (the existing `fo_tree` fail-open shape) prints a banner |

Packed-refs early stop and "stale packed beats loose" are enforced by fixture rows (second-member match
on the third line after a compliant non-matching entry and a `^` peel line; loose-wins), not mutations.
Run once during work against throwaway copies pointed at by the suites' `X_SUT`-style override (or a
`sed`-patched temp copy); never edit the committed files to test.

**Harness rows (edit the SUITE, not the guard).** (a) Replace the recording `git` stub with a no-op:
the stub self-test (existing `stub-git-records-*` rows plus one new sentinel row) goes RED. (b) Make
`run()` skip the subject: the `RUNS` floor and the vacuity floor go RED. (c) Delete one new positive row:
the exact `MIN_CASES` equality goes RED. Must-PASS inputs that are NOT the canonical fixture: a relative
`gitdir:` pointer, `commondir` `../..` and an absolute path, a symlinked `HEAD`, a branch named
`feat/x-1.2_y+z@w` and one named `fix/issue-#12`, a `packed-refs` with the `# pack-refs with:` header and
peeled `^` lines, a `HEAD` without a trailing newline.

**Anchor.** The exact case/run floors are literals in the file they police, so one commit can lower both
a floor and the rows it counts; they prove consistency, not integrity. The independent anchors are the
Guard 1 mutation battery run during work and the suite's registration by name in
`scripts/suite-shard-legs.tsv` plus `scripts/test-all-weight-drift.test.sh`.

## Observability

Layer 7 (code executing on a customer's self-hosted CLI, `hr-observability-layer-citation`): the
resolver and hook run on the user's machine, fail open, and emit no telemetry by design (the privacy
policies promise none).

```yaml
liveness_signal:
  what: the resolver's own output, source=checkout with a 12-hex commit, readable by the user at session start (banner) and on demand (/soleur:version)
  cadence: every session start (banner) and per explicit command
  alert_target: the user's terminal; regression alert is the CI suites plus the daily marketplace-drift canary for delivery
  configured_in: plugins/soleur/hooks/hooks.json (SessionStart startup entry) and plugins/soleur/scripts/plugin-version.sh
error_reporting:
  destination: none by design on the user's machine (no telemetry, fail open); development-time reporting is the failing CI test run
  fail_loud: both suites exit non-zero with the named FAILURES ledger; the hook exits 0 silently on any fault
failure_modes:
  - mode: checkout identity reported for the wrong repository, or a hang/error at session start on hostile repo state
    detection: layout-anchor negative rows, the FIFO/garbage table and the recording git stub in the two suites
    alert_route: red `test` check on the PR
  - mode: the live banner does not render after merge
    detection: Phase 6 headless run with hook events visible
    alert_route: ship/postmerge records the output; a missing line becomes a follow-up issue
logs:
  where: none persisted (stdout key=value lines; the latest-release.checkout cache file holds one tag string)
  retention: cache file stays until replaced or deleted
discoverability_test:
  command: bash plugins/soleur/scripts/plugin-version.sh --installed
  expected_output: source=
```

## Domain Review

**Domains relevant:** engineering, legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Layout-anchored lookup instead of a free walk-up (dotfiles/`/tmp` hazards, "never
reports a version it did not read"); one symbolic hop, `commondir` resolved, no back-pointer check; every
read `[[ -f ]]` + bounded read; keep the commit-like compare for a checkout; no ADR, one C4 text edit.
After plan review the CTO revised: ref deny-list instead of an allowlist, no `marketplace.json` anchor,
builtin `read -n` instead of `head -c` in a substitution, stable checkout cache file, loose-absent-only
fall-through to packed-refs and an over-cap rule, the fetch-then-sync bare-layout sequence. Risks adopted:
hardcoded "commit-hash install only" text sweep, hermetic fixtures with a layout inside `mktemp`, every
`source=` consumer gains the `checkout` arm or the bug stays silent, resolver ordering, HEAD-vs-files
staleness documented rather than claimed away.

### Legal (CLO)

**Status:** reviewed
**Assessment:** If the checkout hash is sent, the policies become incomplete by implication (they sit
next to "installed commit" for marketplace installs) but not false: clarification-only edits in three
policies and three mirrors, SHA re-pin; no new recipient, category, sub-processor or transfer; no LIA,
Art. 30 or compliance-posture change. "Nothing is sent without opt-in" remains accurate. CLO's preferred
alternative (never send a checkout's hash; answer `current` only on tag equality) is recorded as an
operator-visible option in `decision-challenges.md`; this plan keeps the operator's direction. Re-verify
at ship: README "It makes no network call", policy 4.1 "with it off the Plugin makes no such request",
DPD 9.1(b), the c4 edge "no user config, no ssh, no credentials, https only" (true: the compare runs from
`/` with `GIT_DIR` unset), DPD 3.1(b) (HEAD is read from the plugin root, never the user's project;
asserted by the cwd-in-another-repo row), and that only the hash is sent, never a branch name or remote
URL (asserted on the curl argv).

### Product/UX Gate

Not relevant: terminal text only; no page, component or flow (UI-surface glob superset matches no
planned file). Tier: none.

## Test Scenarios

Layers: all `integration` (shell suites driving the real resolver/hook with stubbed `git`/`curl`),
including the gated real-git rows. No `e2e`.

- **T1 positive shapes** (plugin-version.test.sh `--installed`, then the banner in
  version-banner-hook.test.sh): bare-in-`.git` + mirrored files (`core.bare = true`, `HEAD` ->
  `refs/heads/main`, ref only in `packed-refs`, exactly this machine's shape); the same after a loose
  `refs/heads/main` appears; normal clone (`.git` dir, loose ref); linked worktree (`.git` file with
  absolute and relative `gitdir:`, per-worktree HEAD, `commondir`, ref loose and packed); packed-refs with
  header + peeled lines and a second-member match; detached HEAD; loose beats stale packed; symlinked
  HEAD; odd-but-legal branch names; a worktree-style root (`--plugin-dir`).
- **T2 silent shapes - ONE table-driven loop**, each row: `source=unknown`, empty banner stdout, rc 0,
  empty stderr. Grammar census (one row per rule, derived from `gitrepository-layout` and
  `git-check-ref-format`, plus the stricter-than-git ones we choose): HEAD empty / binary / CRLF / exactly
  512 chars / 39-hex / 41-hex / 64-hex / uppercase hex; `ref:` with `..`, `//`, leading or trailing `/`,
  a component starting `.` (reftable `.invalid`), control char, space, each of `~ ^ : ? * [ \`, `@{`;
  `refs/tags/x`; absolute path; loose ref garbage / nested `ref:` / over-length; loose path present but
  invalid beside a valid packed entry (no fall-through); missing ref; HEAD as directory; HEAD as FIFO
  (5 s bound); packed-refs over the cap with the ref past it; a packed line cut at the cap that would
  match a shorter ref; `gitdir:` pointing nowhere / unreadable / without the `gitdir:` prefix; layout
  anchor misses (basename not `soleur`, parent not `plugins`, no `.git`); a dotfiles ancestor `.git` over
  an unrelated plain directory; the sandbox-precondition row (the sandbox itself is not an anchored
  layout).
- **T3 never run git**: the malicious `.git/config` fixture (fsmonitor, `core.sshCommand`, `[include]`,
  `credential.helper`, `url.<x>.insteadOf`) beside a planted `hooks/post-checkout`; the recording `git`
  stub reports `ncalls git == 0` for `--installed`/`--cached-latest` and exactly one isolated `ls-remote`
  for `--compare`; the single gated witness row runs real `git status` on the same fixture and requires
  the fsmonitor sentinel to appear (skipped with run-deficit credit when git or the config behaviour is
  unavailable), while the resolver run leaves it absent.
- **T4 precedence and ordering**: manifest version over checkout; 12-hex dir over checkout; reorder row.
- **T5 relation/cache**: tag-sha equality, ahead/behind/identical/diverged/unparseable, cache file
  `latest-release.checkout`, a cache for another commit reads `corrupt` and (opt-in) triggers one
  refresh, silent when unset, curl argv carries only sha + tag, stale cache never `current`.
- **T6 hook arms**: default zero-network arm on checkout fixtures under the restricted PATH (every
  network binary records and fails; allowlist tools only); opt-in older warning; kill switch; Codex
  markers; fail-open `fo_tree` row with `source=checkout` + garbage commit; cwd in another repository.
- **T7 real-git parity** (gated on git; subshell + `git_fixture_env`): `rev-parse HEAD` first 12 equals
  `commit=` for a bare-in-`.git` clone with packed refs (the machine's shape) and a `git worktree add`.
- **T8 docs rows**: `version.md` checkout arm content and no-GitHub-pair (anchored extraction),
  `disable-model-invocation` retained, `help.md` arm present, README sentence, legal canonical == mirror
  new sentence (tolerating both Last-Updated punctuation forms), `legal-doc-shas.ts` pins match.

Verification commands (Phase 5): `bash plugins/soleur/test/plugin-version.test.sh`,
`bash plugins/soleur/test/version-banner-hook.test.sh`, `bun test plugins/soleur/test/harness-parity-tree.test.ts
plugins/soleur/test/harness-parity.test.ts plugins/soleur/test/components.test.ts`,
`bash plugins/soleur/test/c4-count-parity.test.sh`, the C4 syntax/render vitest files,
`bash apps/web-platform/scripts/check-tc-document-sha.sh`, `bash scripts/lint-legal-registers.test.sh`,
`bash scripts/lint-legal-scope-block-placement.test.sh`, `bash scripts/lint-legal-mirror-drift-baseline.test.sh`,
`apps/web-platform/test/legal-doc-shas-guard.test.ts`, `apps/web-platform/test/legal-doc-consistency.test.ts`,
`python3 scripts/lint-guard-contract.py`, `shellcheck -s bash` on the edited scripts and suites,
`npx markdownlint-cli2` on the plan, tasks and edited docs, and the `fixture-relative-assert` scanner.
Run each affected gate once, early.

## Risks and Sharp Edges

- **A hook that reads untrusted files at every session start of every project.** The two readers, `-f`,
  the caps and the anchor are the controls; the FIFO row is the one that would otherwise only be found in
  the field.
- **Hook PATH allowlist.** The no-network arm runs the resolver under a PATH with a fixed tool list; a
  new `readlink`/`wc`/`od` in the checkout path would silently return unknown there while passing
  elsewhere. Keep to the list; the T6 default-off rows prove it.
- **bash 3.2 / BSD.** No array splitting of the ref name, no bash-4 features, POSIX awk; the portability
  grep in Acceptance Criteria is the command check.
- **NUL / 512-char HEAD.** `read -n 512` drops NUL silently (documented, harmless: only a validated 40-hex
  of a real ref is printed); a result of exactly 512 chars is treated as truncated -> unknown, and the
  same cap-plus-one rule applies to `packed-refs` so a mid-line cut can never match a shorter ref name.
- **Symlinked root** with a non-`soleur` basename goes silent (accepted; lexical anchor, no `realpath`).
- **Sandbox must not sit under a repo.** Existing `unknown` rows rely on plain directories; the layout
  anchor makes that independent of an ambient `.git`, and a precondition row asserts the sandbox itself is
  not an anchored layout.
- **Staleness and the update sequence.** In the bare + mirrored layout HEAD can be ahead of or behind the
  mirrored files, and `worktree-manager.sh sync` does not fetch; docs say "HEAD commit, not its files" and
  always give fetch-then-sync, never `sync` alone.
- **A feature-branch checkout** shows `commit <its HEAD> (local checkout)`; the compare then returns
  `diverged`/`compare-failed` -> `relation=unknown` (silent). A moving checkout makes the shared cache
  file read `corrupt` and re-check on each new commit under the opt-in; bounded by the 600 s lock.
- **Legal pairs.** Canonical and mirror must carry byte-identical new sentences; the SHA pin is over the
  canonical file's raw bytes; edit, then compute the hash last. Keep the recipient explicit (GitHub), not
  "nothing is sent" in a way that reads as covering GitHub.
- **Harness parity census** flags a bare `/version`-style slash form in a new doc sentence; use
  `/soleur:version` everywhere.
- **Markdownlint** runs at the first commit of the work phase: no literal tabs, a blank line before every
  list.

## Deferral tracking

Nothing deferred. Two non-goals, neither a deferral: parsing reftable or sha-256 repositories (silent
unknown is the designed answer) and a Concierge/web-platform equivalent (the resolver runs only in the
CLI plugin).

## Plan Review Outcome (2026-10-12)

Panel (threshold `aggregate pattern`, 3-agent baseline): DHH, Kieran, code-simplicity. The named
CTO/CLO panel was the pre-research consults, re-engaged once (CTO R1-R9) on the contested items; no
CPO/CMO/UX relevance (terminal text only). Classification per ADR-084:

- Mechanical, applied: Kieran P1-1 (NUL warning -> builtin `read`), P1-2 (RUNS/skip deficit), P1-3
  (`sync` does not fetch), P1-4 (witness vectors -> one fsmonitor row, rest stub-only), P2-6 (loose
  existence, packed cap), P2-7 (bash 3.2 guards), P2-9 (unverifiable ACs rewritten), P2-10 (legal order);
  simplicity factual slip (`help.md` is not in the phrase sweep) and #10; DHH #4/#5/#8.
- Technical forks, ruled by the CTO agent: ref deny-list, drop the `marketplace.json` anchor, stable
  checkout cache file, test-weight trims, doc de-duplication, Phase 6 trim (see `decision-challenges.md`).
- Not adopted: DHH #3's "drop the real-git witness entirely" (kept as ONE gated row so "never ran git"
  is not vacuous; CTO R7). Blocker 2 from the CTO (reject a NUL-spliced HEAD) is documented as harmless
  rather than implemented: the spliced string must still be a valid ref holding a real 40-hex.
- Taste / user-challenge: none new. The CLO's data-minimising alternative stays recorded as the
  operator-visible option (decision-challenges.md, F4-alt).
