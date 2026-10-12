---
title: "fix: skill-security-scan runtime-dir retention — document the shipped policy, extend the reap to scratch orphans, close #6760"
type: fix
date: 2026-10-12
slug: skill-security-scan-runtime-dir-retention
branch: feat-one-shot-6760-security-scan-dir-leak
issue: 6760
closes: [6760]
lane: cross-domain
domain: engineering
brand_survival_threshold: none
---

# fix: skill-security-scan runtime-dir retention — document the shipped policy, extend the reap to scratch orphans, close #6760

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-12
**Gate results:** Phase 4.6 User-Brand (pass — `none`, no sensitive-path
diff), 4.7 Observability (pass — `discoverability_test` suite-shape argued
down with measurement: 1,251 ms suite, `0 failed` literal), 4.8 PAT (no
hits), 4.9 UI-wireframe (no UI files — skip), 4.10 Encryption (no
store/connection triggers — skip), 4.11 Guard Contract
(`lint-guard-contract.py` green, 1 entry, structural assembly), 4.12 Scope
Check (1 unfenced section, all asks mapped/descoped+justified, single-PR
recommendation). 4.4 precedent-diff run inline (mirrors shipped sibling +
tmpfs-guard reaper shape). 4.5 network-outage / 4.55 downtime — not
triggered.

### Key Improvements from Deepening

1. The scratch sweep's design hardened during the inline spec-flow pass:
   own-scratch exclusions were added because own-scratch — unlike
   `meta_dir` — is created *before* the reap site, so a stale positional
   INPUT or a long scan would otherwise be a reap candidate (the asymmetry
   the shipped comment does not cover). Review hardened the sketch further:
   the exclusions are `! -samefile` (inode compare — a relative or
   glob-shaped INPUT defeats `-path` string equality), the TMPDIR root is
   `cd -P`-canonicalized (find `-P` does not descend a symlinked
   startpoint), both sweeps clamp to a ≥60-min floor (`-mmin "+0"` matches
   any past mtime → a low floor reaps a concurrent peer's live scratch),
   `10#` normalizes octal-legal leading zeros, and the name window gained
   `sss-write.*.err` (the write-hook's err capture).
2. The sweep's `-o` arm covers `skill-security-scan-*` under `${TMPDIR:-/tmp}`
   (the XDG-toggle crossover), discovered while enumerating allocation roots.
3. Verified mechanically: `mktemp -t` honors `TMPDIR` on this host
   (`/tmp/mkt-td/skill-scan-test-*` produced); `meta-dir-reap.test.sh` runs
   green ("9 passed, 0 failed"); `lint-guard-contract.py` scans the plan
   clean; every `knowledge-base/*.md` citation in the plan resolves; no
   open `code-review` issues touch the five target files.

### New Considerations Discovered

- The `find` probe on this host reports 234 live `skill-security-scan-*`
  dirs under the current runtime base — within-window steady state, the
  shipped policy working as designed.
- `tmp-classify.sh:27` carries a second `skill-security-scan-*` mention in a
  descriptive protected-names list — left untouched (accurate; only the
  `:108` justification is stale).
- Plan-review panel and scoped advisor consult could not spawn (no Task
  capability in this context) — recorded in `decision-challenges.md`;
  deepen-plan's gate phases serve as the next verification layer.

## Overview

Issue #6760 reported `run-scan.sh` leaking one `skill-security-scan-<pid>` dir
per invocation on the `XDG_RUNTIME_DIR` tmpfs (7,603 observed) and asked for a
retention policy rather than a trap. The policy the issue's option (a) names —
a startup age-reap of older siblings — already shipped on `main` via PR #6828
(issue #6789, commit `0c9ef2290a`): `run-scan.sh:215-224` reaps
`skill-security-scan-*` dirs older than `SKILL_SCAN_META_REAP_MIN` (default
10080 min = 7 days, `-user`-scoped, name-filtered) before creating its own
`meta_dir`, guarded by the registered suite
`plugins/soleur/skills/skill-security-scan/test/meta-dir-reap.test.sh`
(7 arms, 9 assertions — measured green 2026-10-12).

The remaining work is the close-out the issue was deliberately left open for:
document the shipped retention policy where operators and override-artifact
authors actually read, extend the same startup reap to the sibling scratch
families a killed scan leaves behind (measured: 45 `skill-scan-input-*` files
and 4 `skill-scan-results-*` dirs dated 2026-07-20, tallied across the
2026-07-22 and 2026-07-27 plans), correct the stale `#6760 deliberate
retention` justification on the `tmp-classify.sh` protection row (added by
PR #8738; stale against the shipped #6828 reap), and close #6760 with
evidence via the PR body.

## Problem Statement / Motivation

- The issue's core ask is satisfied on `main` but the issue is still open —
  nobody connected PR #6828's reap to #6760, and two later plans explicitly
  deferred to it ("acknowledge, do not fold in" — 2026-07-27 plan;
  "#6760 … out of scope" — 2026-10-12 mktemp-census plan).
- The retention policy exists only inside `run-scan.sh` comments. SKILL.md's
  Output section names the `.scan-meta.json` location but not its TTL;
  `override-mechanism.md` tells operators to reference that path in an
  override artifact without saying the path expires — a `findings_json`
  path-form reference to a reaped dir dangles.
- The `skill-scan-*` scratch families (`skill-scan-input-*`,
  `skill-scan-results-*`, `skill-scan-XXXXXX` plus `.code/.fm/.body/.req/.resp`
  siblings from `lib.sh`'s `stdin_to_tempfile`) are EXIT-trap-owned but have no
  reaper. Under SIGKILL — which tmpfs pressure produces — they leak with no
  recovery path, the same harm class the issue describes. Measured leak: 45
  input + 4 results artifacts dated 2026-07-20.
- `plugins/soleur/scripts/lib/tmp-classify.sh:108` protects
  `skill-security-scan-*` from generic sweepers with the comment
  `# #6760 deliberate retention`. The protection is correct (a generic reaper
  must not out-race the evidence window the scanner's own policy grants), but
  the justification is stale: retention is now *bounded by policy*, not
  "deliberate". (The sibling lineage's open task 8.8 flags a different
  `#6760` comment — the harm-reduction claim that lineage posted on the
  issue itself, recorded in the 2026-07-27 plan's Action item and its R8
  retraction; this row's comment was added later by PR #8738 and is stale
  on its own.)

## Proposed Solution

Three small edits at existing seams, no new machinery:

1. **Extend the startup reap** in `run-scan.sh` with a second `find` sweep
   placed adjacent to the existing reap block so the two sweeps read as one
   retention site:

   ```bash
   # Scratch orphans (`skill-scan-*`), meta_dir orphans a previous run left
   # under TMPDIR when XDG_RUNTIME_DIR was unset, and the write-hook's
   # `sss-write.*.err` captures. SIGKILL leaks these; measured 45
   # `skill-scan-input-*` + 4 `skill-scan-results-*` dated 2026-07-20
   # (#6760). Unlike `meta_dir`, own-scratch is created BEFORE this point,
   # so exclude the live paths by inode — under a pathological low
   # `SKILL_SCAN_META_REAP_MIN` the age gate alone does not protect a stale
   # positional input (both sweeps clamp to a >=60-min floor).
   tmp_root="$(cd -P "${TMPDIR:-/tmp}" && pwd -P || true)"
   if [ -n "$tmp_root" ]; then
     find "$tmp_root" -mindepth 1 -maxdepth 1 -user "$(id -u)" \
       -mmin "+${_reap_min}" \
       \( -name 'skill-security-scan-*' -o -name 'skill-scan-*' \
           -o -name 'sss-write.*.err' \) \
       ${_excl[@]+"${_excl[@]}"} \
       -exec rm -rf {} + 2>/dev/null || echo "..." >&2
   fi
   # (as built: `_excl` holds `! -samefile` for each of INPUT/results_dir
   # that still exists — `-path` string equality is defeated by relative
   # and glob-shaped INPUT spellings)
   ```

   The `skill-security-scan-*` arm under `TMPDIR` covers the XDG-toggle
   crossover (meta dirs created under `/tmp` before `XDG_RUNTIME_DIR` was
   set are unreachable by the first sweep once the env flips). Add `#6760`
   alongside `#6789` in the rationale comment — #6760 is the leak-tracking
   issue.

2. **Document the policy** in `SKILL.md` (Output section: retention floor,
   both env seams, the startup-reap-not-trap contract) and
   `override-mechanism.md` (`findings_json` path-form is only valid inside the
   retention window; inline copy is the durable alternative).
3. **Correct the stale justification** at `tmp-classify.sh:108` — keep the
   protection, restate the reason (bounded by the scanner's own startup reap;
   generic sweepers must not out-race the evidence window).
4. **Extend `meta-dir-reap.test.sh`** with arms for the scratch families (old
   input file reaped, old results dir reaped, old lib-tempfile sibling reaped,
   fresh scratch spared, source anchors for the new predicate) — the suite is
   already CI-registered via the `plugins/soleur/skills/*/test/*.test.sh`
   glob; new arms need no registration.
5. **PR body** carries `Closes #6760` with the evidence trail (shipped reap,
   this PR's extension, the registered suite).

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 6760` — OPEN, created 2026-07-20, triaged `priority/p2-medium`,
  `type/chore`, `domain/engineering`.
- `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh` — exists on
  this branch (created from current `main`, `0c9ef2290a` merged 2026-07-22 via
  PR #6828) and **already contains the retention mechanism the issue asks
  for**: startup age-reap, `SKILL_SCAN_META_REAP_MIN` default 10080, uid-scoped,
  name-filtered, `-mmin` age gate. The issue's premise "nothing ever removes
  it" is **stale for the meta_dir family** — but the issue was deliberately
  kept open by two subsequent plans (see related issues below) for exactly the
  residual scope this plan picks up.
- `plugins/soleur/test/skill-security-scan.test.ts` — the post-exit consumer
  contract the issue cites is intact (`/scan-meta\.json written to: (\S+)/`
  then file read); no contract change proposed.
- `scripts/lint-trap-tempfile-ownership.py` — rule (c) population census run:
  `run-scan.sh` is not a class-b member (it registers owning traps);
  `skill-security-scan/scripts/lib.sh` is an accepted class-b member
  (caller-owns contract). No lint interaction.
- Mechanism-vs-ADR grep: the ask's mechanism (age-based startup reap) matches
  what shipped; no ADR rejects it. ADR-129 (accepted class-b mktemp
  population) is consistent — this plan adds no new untrapped `mktemp`.

### Property List (Phase 0.6b)

- P1 — `skill-security-scan-*` meta dirs do not accumulate without bound on
  tmpfs. **Already covered on `main`** by the shipped reap.
- P2 — The policy must not break the post-exit consumer contract
  (`.scan-meta.json` readable after exit; no EXIT-trap on `meta_dir`).
  Covered + guarded by test arms 3–5.
- P3 — The retention policy is discoverable where consumers read (SKILL.md,
  override-mechanism.md). **Not covered** — this plan's doc edits.
- P4 — The scanner's *scratch* allocations (all `skill-scan-*` families) are
  bounded under the same tmpfs harm the issue names. **Not covered** —
  SIGKILL orphans leak forever today; this plan's reap extension.
- P5 — The tracking issue closes with evidence instead of rotting open next
  to a shipped fix. **This plan's PR body.**
- P6 — `tmp-classify.sh`'s protection row tells the truth about why
  `skill-security-scan-*` is protected. **This plan's comment correction.**

### Cut List (Phase 0.6b)

- Count-cap reaper ("keep newest K") — buys instant-count boundedness the age
  floor does not give, at ordering/race cost; the issue's harm (tmpfs fill) is
  bounded adequately by age. Cut.
- Shorter scratch floor / separate `SKILL_SCAN_SCRATCH_REAP_MIN` seam — a new
  tunable buying a tighter bound on artifacts with no retention value;
  `_reap_min` reuse is adequate (a >7-day-old scratch artifact belongs to a
  dead scan). Cut; recorded as a decision-challenges row.
- Caller-owned lifetime / stable-path rewrite — the issue's own analysis
  shows these change the consumer contract or the concurrency model; the
  shipped mechanism already chose option (a). Cut.
- systemd timer / cron sweeper — an infrastructure mechanism for a property
  the producer-side startup reap already buys; also an IaC-routing violation
  if operator-installed. Cut.
- `tmpfs-guard.sh` Reaper-2 coverage — its 100 MB size floor is structurally
  blind to count-shaped leaks (recorded learning in the sibling task file:
  "a size-thresholded reaper cannot see a count-shaped leak"); not a
  candidate mechanism for P1/P4. Noted, not pursued.

### Repo facts

- Allocation inventory (verified by `git grep`):
  - `run-scan.sh:30` `mktemp -t skill-scan-input-XXXXXX` — file, `${TMPDIR:-/tmp}`
  - `run-scan.sh:103` `mktemp -dt skill-scan-results-XXXXXX` — dir, same root
  - `run-scan.sh:226` `mkdir "$meta_base/skill-security-scan-$$"` — dir,
    `${SKILL_SCAN_META_BASE:-${XDG_RUNTIME_DIR:-/tmp}}` — already reaped
  - `lib.sh:148` `mktemp -t skill-scan-XXXXXX` — file, same scratch root;
    callers append `.code/.fm/.body/.req/.resp` siblings — all match
    `skill-scan-*`
- Consumers of the printed meta path: `skill-security-scan.test.ts` (CI) and
  the operator (override flow, `override-mechanism.md`); the PreToolUse hook
  `skill-security-scan-write.sh` consumes the verdict line only.
- `meta-dir-reap.test.sh` is CI-registered via `test-all.sh` SUITE_GLOBS
  (`plugins/soleur/skills/*/test/*.test.sh`); measured duration 1251 ms
  (`suite-durations.tsv`).
- `tc_is_protected` (`plugins/soleur/scripts/lib/tmp-classify.sh:102`)
  protects `skill-security-scan-*` at line 108; consumers are the worktree
  sweep (`worktree-manager.sh`) and tmpfs-guard install tooling. Protection
  semantics are correct; only the comment justification is stale.
- `parse-override.sh` validates `findings_json` as either a path string or an
  inline copy (`override-artifact-schema.json:31`) — the path form is what
  dangles after the floor.

### Institutional learnings applied

- `2026-09-19-cleanup-on-failure-is-a-property-of-the-window-not-the-arms.md`
  (#8288) — the reap must run *before* the run's own allocations become
  candidates; the age floor is what protects the current run's files (they
  are younger than any floor), so placement is cohesion, not safety.
- `2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper.md` —
  the sibling-allocation sweep: every `mktemp`/`mkdir` family this producer
  creates was enumerated above, not only the one the issue named.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-*` (#7493 class) —
  new test arms include a source-anchor positive control so a narrowed glob
  cannot green vacuously.
- `scripts/suite-shard-legs.tsv`/`suite-durations.tsv` — the suite is already
  registered; no `test-all.sh` edit needed (verified, not assumed).

### Related issues / PRs

- #6760 (this work, OPEN) · #6789 / PR #6828 (shipped the meta reap,
  2026-07-22) · 2026-07-20 (date of the measured leaked entries — the
  earlier plans' "`#6726`" label resolves to a merged PR, not an incident
  tracker) ·
  #6734 (trap-ownership class — the issue explicitly distinguishes itself) ·
  #10017 / PR #10129 (mktemp census — drew the "#6760 out of scope"
  boundary) · ADR-129 (accepted class-b population, unchanged).

### Conventions

- `#!/usr/bin/env bash`, `set -euo pipefail`, `local`, stderr for diagnostics.
- Symbol anchors in comments, never line numbers.
- Test assertions anchor on content (`cq-assert-anchor-not-bare-token`),
  including positive controls for negative arms.
- No `#NNNN` at line start in prose (markdownlint MD025).

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #6760) | Codebase reality | Plan response |
|---|---|---|
| "creates one directory per invocation that nothing ever removes" | the `meta_base` startup reap in `run-scan.sh` age-reaps `skill-security-scan-*` siblings older than `SKILL_SCAN_META_REAP_MIN` (shipped 2026-07-22, #6828) | Stale for the meta family. Plan re-scopes to close-out + residual families; records the ruling in `decision-challenges.md`. |
| "It needs a retention policy" | Policy exists in code but is undocumented anywhere a consumer reads | Phase 2 doc edits (SKILL.md, override-mechanism.md). |
| Options: prune-at-startup / caller-owns / stable-path | Option (a) already chosen and shipped | No second decision needed; floor value recorded as a decision-challenges row. |
| (implicit) only meta dirs leak | Measured 45 `skill-scan-input-*` + 4 `skill-scan-results-*` leaks dated 2026-07-20 (2026-07-22 + 2026-07-27 plans) | Extend the same reap to the `skill-scan-*` scratch family. |
| `#6760 deliberate retention` (`tmp-classify.sh:108`) | Retention is bounded-by-policy, not "deliberate" — the comment postdates the shipped #6828 reap it should cite (added by PR #8738) | Correct the comment; keep the protection. |

## Technical Considerations

- **`find` predicate grouping.** Two `-name` alternatives require the
  grouped form `\( -name A -o -name B \)` — `X -o Y -exec` binds the
  `-exec` to `Y` only, which would run the delete on just one arm. The
  `! -path` exclusions sit outside the group; `rm -rf` handles both files
  and dirs so no `-type` split is needed.
- **Own-scratch predates the reap — the asymmetry the shipped block does
  not have.** The shipped meta reap is safe-by-construction because
  `meta_dir` is created *after* it runs; `INPUT` (line ~30) and
  `results_dir` (line ~103) are created *before*. Under the shipped floor
  (10080 min) a fresh own-scratch entry is never a candidate, but under a
  pathological low `SKILL_SCAN_META_REAP_MIN` (the test seam uses `0`) a
  scan whose five category checks take ≥ 1 min (e.g. slow OSV calls in
  `check-supply-chain.sh`) would reap its own live scratch mid-run. The
  `! -samefile` exclusions close exactly that window (inode compare —
  `-path` string equality is defeated by relative/glob spellings);
  a concurrent sibling's scratch carries the same accepted
  exposure the shipped reap already has for meta dirs.
- **Two roots, not one.** Meta dirs live in
  `${SKILL_SCAN_META_BASE:-${XDG_RUNTIME_DIR:-/tmp}}`; scratch lives in
  `${TMPDIR:-/tmp}`. The sweeps run over both roots independently; when they
  coincide (both `/tmp`) each find is idempotent so no dedupe is needed.
- **Age-only abandonment holds for scratch a fortiori.** Scratch artifacts
  have no post-exit consumer (unlike `.scan-meta.json`); a scratch file older
  than the 7-day floor belongs to a dead scan by construction. Same-floor
  reuse avoids a second tunable.
- **Concurrency.** A sibling scan's live scratch is younger than the floor,
  so a concurrent reap never touches it — identical to the shipped argument
  for meta dirs. `-user "$(id -u)"` keeps the sweep uid-scoped on shared
  hosts.
- **Precedent (deepen-plan 4.4).** The prescribed sweep mirrors the shipped
  sibling verbatim — same `-mindepth 1 -maxdepth 1 -user "$(id -u)" -mmin`
  predicate set, same `-exec rm -rf {} + 2>/dev/null || true` tolerance —
  and the same shape as `scripts/tmpfs-guard.sh`'s reaper candidate scan
  (`find … -mindepth 1 -maxdepth 1 -user "$uid" -mmin "+${age_min}"`). The
  only novel elements are the grouped `-o` name pair (precedent shape:
  `\( A -o B \)` is the canonical `find` grouping) and the `! -path`
  exclusions (no precedent needed — inode-exclusion of own-scratch is new
  because the scratch family is the first whose allocations predate the
  reap).
- **`skill-scan-*` prefix ownership.** The producer set is fully enumerated
  in Research Insights; no other repo tool writes that prefix to `${TMPDIR}`
  (verified by `git grep`). The scratch glob does NOT collide with the
  durable family (`skill-scan-*` vs `skill-security-scan-*` are distinct
  prefixes); the durable family's inclusion under `TMPDIR` is by the
  deliberate `-o` arm for the XDG-toggle crossover, and it is governed by
  the identical floor — the same policy, not a weaker one.
- **SIGPIPE/`set -e` safety.** The new find carries `2>/dev/null || true`
  like its sibling — a vanished candidate mid-reap (concurrent cleanup) is
  tolerated, never fatal to the scan.
- **`tmp-classify.sh` interplay.** The protection row at line 108 is for
  *generic* sweepers (worktree sweep, tmpfs-guard tooling) and stays —
  `skill-security-scan-*` is evidence-bearing and its lifetime is owned by
  the scanner's own policy, not by count/size-based reapers.
- **Env seams for tests.** `SKILL_SCAN_META_BASE` already exists; the scratch
  root needs no new seam — `TMPDIR` is the real one `mktemp` honors, and the
  test sets it.
- **NFRs.** No new attack surface (uid-scoped, fixed prefix, no symlink
  following — `find` at `-maxdepth 1` with `rm -rf` on entries it
  enumerates); performance is one extra `find` per scan startup, ~ms on a
  healthy tmpfs. Security note: `rm -rf` on a name-enumerated entry does not
  follow symlinks for the entry itself — consistent with the bulk-cleanup
  constitution rule (no `realpath`/`lstat` decision change: find's default
  is `-P`, never `-L`).

## Implementation Phases

### Phase 1 — Code

- `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh` — after the
  existing `skill-security-scan-*` reap block (~line 224), add the
  `skill-scan-*` scratch sweep over `${TMPDIR:-/tmp}`; add `#6760` to the
  rationale comment; update the comment to state both families are bounded
  here.
- `plugins/soleur/skills/skill-security-scan/test/meta-dir-reap.test.sh` —
  add scratch-family arms (see Test Scenarios); test sets `TMPDIR` to a
  fixture root.
- `plugins/soleur/scripts/lib/tmp-classify.sh` — replace the
  `# #6760 deliberate retention` comment with the accurate justification
  (protection retained — bounded by the scanner's own startup reap; generic
  sweepers must not out-race the evidence window).
- Verify: `bash plugins/soleur/skills/skill-security-scan/test/meta-dir-reap.test.sh`.

### Phase 2 — Docs

- `plugins/soleur/skills/skill-security-scan/SKILL.md` — extend the Output
  section: `.scan-meta.json` lifetime (startup reaped past
  `SKILL_SCAN_META_REAP_MIN`, default 7 days), the `SKILL_SCAN_META_BASE`
  seam, and the no-EXIT-trap contract.
- `plugins/soleur/skills/skill-security-scan/references/override-mechanism.md` —
  in the `findings_json` guidance: the path form is valid only inside the
  retention window; for references that must outlive it, use the inline-copy
  form (schema-permitted) or create the override within the window.
- Verify: `npx markdownlint` (or repo lint) on both files; content-anchor
  greps for the new tokens.

### Phase 3 — Close-out

- PR body: `Closes #6760`, evidence trail (reap shipped via #6828; this PR
  documents the policy, extends the sweep to scratch orphans, corrects the
  stale `tmp-classify.sh` justification), `## Changelog` section per AGENTS.md.
- Semver label: `semver:patch` (bug-fix-class docs+hardening on
  `plugins/soleur/`).

## Files to Edit

- `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh` — scratch
  reap + comment refs (~15 lines)
- `plugins/soleur/skills/skill-security-scan/test/meta-dir-reap.test.sh` —
  new arms (~60 lines)
- `plugins/soleur/scripts/lib/tmp-classify.sh` — comment correction (1 line)
- `plugins/soleur/skills/skill-security-scan/SKILL.md` — retention docs
  (~10 lines)
- `plugins/soleur/skills/skill-security-scan/references/override-mechanism.md` —
  `findings_json` TTL guidance (~6 lines)

## Files to Create

None.

## User-Brand Impact

- **If this lands broken, the user experiences:** a `skill-scan-*` reap that
  is too broad could delete scratch belonging to a concurrently running scan
  or an unrelated user file matching the prefix — the user sees a crashed
  scan or a missing temp file; too narrow, the leak persists silently and
  tmpfs pressure returns as unrelated suite failures.
- **If this leaks, the user's workflow is exposed via:** unbounded
  `skill-scan-*` accumulation on a RAM-backed tmpfs exhausting the very
  resource the scanner's other work needs — the issue's observed failure was
  unrelated suites dying with confusing errors at 100% `/tmp`.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the blast radius is the operator's
  own dev-box tmpfs and their own scratch files — no customer data, revenue
  path, or external user surface; `none` rather than `single-user incident`
  because the worst case is a local test-suite failure the operator can
  re-run, not a lost artifact (the durable `.scan-meta.json` family keeps its
  existing protection).

## Observability

```yaml
liveness_signal:
  what:            "meta-dir-reap.test.sh suite result — asserts both reap families (meta dirs + scratch orphans) and the post-exit artifact contract"
  cadence:         "per CI run (registered via test-all.sh SUITE_GLOBS: plugins/soleur/skills/*/test/*.test.sh)"
  alert_target:    "CI failure on the PR / main branch pipeline"
  configured_in:   "scripts/test-all.sh SUITE_GLOBS; scripts/suite-shard-legs.tsv"

error_reporting:
  destination:     "CI job log — suite prints '[FAIL] <arm>' lines to stderr and a 'N passed, M failed' summary"
  fail_loud:       "non-zero exit from the suite fails the CI leg; a FAIL arm names the broken property"

failure_modes:
  - mode:          "scratch reap removed or its -name/-user/-mmin predicate narrowed"
    detection:     "meta-dir-reap.test.sh scratch arms red (old fixture survives / source-anchor arm fails)"
    alert_route:   "CI failure on the PR"
  - mode:          "reap too broad — current run's own dir or a fresh sibling deleted"
    detection:     "AC8 arm and the fresh-sibling arm red"
    alert_route:   "CI failure on the PR"
  - mode:          "find errors (vanished candidate, perms)"
    detection:     "tolerated by 2>/dev/null || true — scan proceeds; residual dirs age out next run"
    alert_route:   "none needed — self-healing next invocation"

logs:
  where:           "CI job log (suite stdout/stderr); no runtime log — reaper is silent by design"
  retention:       "CI retention window"

discoverability_test:
  command:         bash plugins/soleur/skills/skill-security-scan/test/meta-dir-reap.test.sh
  expected_output: "0 failed"
  # Argued down (deepen-plan 4.7 over-inclusive suite proxy): the command
  # matches the suite-shape reject regex (*.test.*), but it IS the smallest
  # command producing the signal liveness_signal.what names — measured
  # 1,251 ms in scripts/suite-durations.tsv (re-run green 2026-10-12, "9
  # passed, 0 failed"), well inside Check 10's 15 s cap. A registration
  # probe (grep of suite-shard-legs.tsv) would prove scheduling, not health.
```

## Guard Contract

### Guard 1 — scratch-orphan reap coverage (meta-dir-reap.test.sh extension)

**Property.** Every `skill-scan-*` entry in `${TMPDIR:-/tmp}` older than the
retention floor is removed at `run-scan.sh` startup; every entry younger than
the floor, and every non-`skill-scan-*` entry, is untouched.

**Assembly.** The single chokepoint is the `find` sweep in `run-scan.sh`
adjacent to the existing meta-dir reap — it is the only site that removes
`skill-scan-*` orphans; all producer call sites
(`run-scan.sh` `mktemp -t skill-scan-input-*`, `mktemp -dt
skill-scan-results-*`; `lib.sh` `stdin_to_tempfile`'s `skill-scan-XXXXXX` and
its `.code/.fm/.body/.req/.resp` siblings) share the `skill-scan-*` prefix
the predicate enumerates.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the new `find` sweep (guard's own dispatch) — old fixtures survive | RED |
| 2 | Narrow the glob to `skill-scan-input-*` only — a `skill-scan-results-*` dir or `skill-scan-*.code` sibling survives (second-member row) | RED |
| 3 | Invert the age gate (`-mmin "+X"` → `-mmin "-X"`) — fresh fixtures get reaped | RED |
| 4 | Drop `-user "$(id -u)"` — the source-anchor arm fails | RED |
| 5 | Remove `-name` filter entirely — the unrelated-dir fixture gets reaped | RED |
| 6 | Drop the `! -path` exclusions — the source-anchor arm fails (the floor=0 own-scratch window reopens) | RED |
| 7 | Suite-side: delete the positive-control arm — a dead regex must not green vacuously | RED |
| 8 | A recent `skill-scan-results-*` dir is present (must-PASS input, not the canonical old-dir shape) | PASS |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change on a
dev-time scanner script, docs, and a test suite. Mechanical UI-surface
override: no `Files to Create`/`Files to Edit` entry matches the UI-surface
glob superset (all paths are `.sh`/`.md` under `plugins/soleur/`).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "It needs a retention policy" [issue #6760] | Already shipped (`meta_base` reap in run-scan.sh, #6828); documented by Phase 2 doc edits; issue closed by Phase 3 PR body | mapped |
| 2 | "prune `skill-security-scan-*` older than N hours at scan startup (simplest, self-healing, no consumer contract change)" [issue #6760] | Shipped mechanism retained unchanged; Phase 1 keeps the same site/floor for the sibling family | mapped |
| 3 | "have callers own the lifetime and delete after reading (correct but changes the contract for every consumer)" [issue #6760] | — | descoped — justification: alternative already rejected by the shipped design (option (a) was chosen and merged); re-litigating reopens a closed decision |
| 4 | "write to a single stable path and overwrite, if concurrent scans need not coexist" [issue #6760] | — | descoped — justification: same as ask 3; also concurrent scans DO coexist (parallel category children + concurrent invocations) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `run-scan.sh` scratch-orphan reap | — | inferred — justification: ask 1's property is bounded scanner footprint on the RAM-backed tmpfs the issue names as the harm ("`XDG_RUNTIME_DIR` is a tmpfs — it consumes RAM"); the `skill-scan-*` families are the same producer's same-class allocations, the leak is measured (45 input + 4 results artifacts dated 2026-07-20), and the fix is the same already-shipped mechanism at the same site |
| `meta-dir-reap.test.sh` new arms | — | inferred — justification: the guard contract for the reap extension; the suite is the existing assertion site for this property (arms 1–7 already pin the meta family) |
| `SKILL.md` retention docs | "It needs a retention policy" | asked |
| `override-mechanism.md` TTL guidance | "It needs a retention policy" | asked — the path-form `findings_json` guidance is where the policy's consumer-visible TTL must live |
| `tmp-classify.sh` comment correction | — | inferred — justification: the `#6760 deliberate retention` comment (added by PR #8738, after the #6828 reap it should cite) certifies a policy that does not exist — retention is bounded by the scanner's own startup reap, not "deliberate" |
| PR body `Closes #6760` + evidence | "It needs a retention policy" | asked — closing the tracking issue against the shipped mechanism is the ask's completion |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur` (skills + scripts/lib)
- Planned files: 5 | Estimated changed lines: ~95
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `run-scan.sh` reaps `skill-scan-*` entries (files and dirs) older than
  `_reap_min` under `${TMPDIR:-/tmp}` at startup, uid-scoped
  (`-user "$(id -u)"`), with the same `2>/dev/null || true` tolerance as the
  existing sweep
- [ ] The same sweep's `-o` arm reaps `skill-security-scan-*` dirs under
  `${TMPDIR:-/tmp}` (XDG-toggle crossover) at the same floor, while the
  shipped meta-base sweep is unchanged
- [ ] The sweep excludes the current run's own `$INPUT` and `$results_dir`
  (`! -path` exclusions present in the live code)
- [ ] Entries matching the swept patterns but younger than the floor are not
  reaped; entries matching neither `skill-scan-*` nor
  `skill-security-scan-*` are never reaped
- [ ] The current run's own `.scan-meta.json` exists after the process exits
  (existing AC8 contract preserved — no EXIT trap over `meta_dir`/`meta_path`)
- [ ] `run-scan.sh` comments reference `#6760` alongside `#6789` for the
  retention mechanism
- [ ] `SKILL.md` documents the `.scan-meta.json` retention window, the
  `SKILL_SCAN_META_REAP_MIN` default (7 days), the `SKILL_SCAN_META_BASE`
  seam, and the startup-reap-not-trap contract
- [ ] `override-mechanism.md` states the `findings_json` path form is valid
  only within the retention window and names the durable alternative
- [ ] `tmp-classify.sh`'s `skill-security-scan-*` protection row no longer
  justifies itself as `#6760 deliberate retention`; the protection itself is
  unchanged (verified: `grep -n "skill-security-scan-" plugins/soleur/scripts/lib/tmp-classify.sh` shows the `return 0` arm retained)
- [ ] `bash plugins/soleur/skills/skill-security-scan/test/meta-dir-reap.test.sh`
  exits 0 with all arms passing
- [ ] `bash scripts/lint-trap-tempfile-ownership.py --changed` (or the PR's
  normal lint leg) reports no new class-b member — this change adds no
  `mktemp`
- [ ] PR body contains `Closes #6760` and cites the shipped reap plus this
  PR's extension

## Test Scenarios

- Given an old `skill-scan-input-999001` file (mtime > floor) under the test
  `TMPDIR`, when `run-scan.sh` runs, then the file is gone — `unit`
- Given an old `skill-scan-results-999002` dir under the test `TMPDIR`, when
  `run-scan.sh` runs, then the dir is gone — `unit`
- Given an old `skill-scan-abc123.code`-style sibling file under the test
  `TMPDIR`, when `run-scan.sh` runs, then it is gone — `unit`
- Given a fresh `skill-scan-results-*` dir (current mtime) under the test
  `TMPDIR`, when `run-scan.sh` runs, then it survives — `unit`
- Given an old dir named `some-unrelated-dir`, when `run-scan.sh` runs, then
  it survives (existing arm, unchanged) — `unit`
- Given the source of `run-scan.sh`, when comments are stripped and the code
  greps for the scratch sweep, then `-name 'skill-scan-*'`,
  `-user "$(id -u)"`, and the `! -samefile` own-scratch exclusions are
  present (positive control: same regexes match the live code) — `unit`
- Regression: existing arms 1–7 (old meta dir reaped, recent spared, AC8
  artifact survives, floor=0 own-dir safe, no meta-dir EXIT trap + regex
  positive control, name filter, uid scope) stay green — `unit`
- Verification command: `bash
  plugins/soleur/skills/skill-security-scan/test/meta-dir-reap.test.sh`
  expects `0 failed`

## Open Code-Review Overlap

**None.** All 200 open `code-review`-labelled issues fetched; zero bodies
contain `plugins/soleur/skills/skill-security-scan` or
`plugins/soleur/scripts/lib/tmp-classify.sh`.

## Success Metrics

- `find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'skill-scan-*' -mmin +10080`
  returns empty after any scan invocation on a host that previously leaked
- The `meta-dir-reap` suite reports all arms passing in CI
- #6760 closes with the mechanism cited, and no follow-up issue is needed

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| `skill-scan-*` glob wider than the producer set | Producer set enumerated by `git grep` (Research Insights); prefix is scanner-owned; `-user` + `-mmin` bound the blast radius; unrelated-name arm guards the boundary |
| `find` precedence/`${TMPDIR}` fallback subtleties | Single `-name` predicate (no `-o` grouping needed); `${TMPDIR:-/tmp}` mirrors `mktemp -t` semantics exactly |
| Reaping a live sibling's scratch | Fresh files are younger than the floor by construction; a >7-day-old live scan is already wedged |
| Comment-only `tmp-classify.sh` edit regresses a protection | AC asserts the `return 0` arm is retained; the change touches only the comment |
| Issue was already "the right shape" — re-litigating the option choice | Plan records the close-out rationale; decision-challenges carries the floor-value row for operator visibility |

## Alternative Approaches Considered

- **Do nothing / comment-only close of #6760.** Rejected: leaves the policy
  undocumented (P3), the scratch families unbounded (P4, measured leak), and
  the stale `tmp-classify.sh` justification in place (P6).
- **Extend tmpfs-guard Reaper 2.** Rejected: its 100 MB size floor is
  structurally blind to count-shaped leaks (the sibling task file's own
  learning); the scanner's producer-side startup reap is the correct site.
- **Separate `SKILL_SCAN_SCRATCH_REAP_MIN` with a shorter default.**
  Rejected: new tunable for a marginal bound; recorded in
  `decision-challenges.md` for operator visibility.
- **Caller-owned lifetime / stable-path overwrite.** Rejected by the issue's
  own analysis (contract change / concurrency), and the shipped mechanism
  already chose option (a).

## Non-Goals

- No change to the retention floor value (7-day default stays; env-overridable).
- No change to the consumer contract (`scan-meta.json written to:` output,
  meta_dir durability post-exit).
- No reaper for unrelated `tmp.*` families — owned by the mktemp-census
  lineage (#10017) and tmpfiles.d, not this issue.
- No ADR — no architectural decision (see Conditional Gate Dispositions).
- No changes to `lib.sh`'s caller-owns contract (accepted class-b member,
  ADR-129).

## Conditional Gate Dispositions

- **Architecture Decision (ADR/C4):** no architectural decision — a bug-fix
  extension of an existing mechanism plus docs; no ownership/substrate/trust
  boundary change and no ADR divergence. Section not emitted per the
  skip-silently rule.
- **Encryption Posture:** no persistent store or new cross-component
  connection. Skip.
- **GDPR gate:** no regulated-data surface (`.scan-meta.json` is already
  redacted at write; this change deletes files by name only, never reads
  them); none of the (a)–(d) triggers fires. Skip.
- **IaC routing:** no new infrastructure — the reap runs inside the existing
  scan entry point; no cron, service, secret, or vendor. Skip.
- **Skill description budget:** no `description:` frontmatter edit (SKILL.md
  body only). Skip.
- **Community discovery / functional overlap:** bash on an internal plugin
  script; covered stack, no registry surface. Skip.
- **Network-outage checklist:** no trigger pattern. Skip.
- **Founder check:** headless pipeline — deferred to ship-phase rendering.
- **Scoped advisor consult:** no agent-spawn capability in this planning
  context; recorded in `decision-challenges.md`.
- **Plan-review panel:** executed as an inline self-review against the
  eng-panel lenses (overengineering / correctness / YAGNI) — no Task spawn
  capability; recorded in `decision-challenges.md`.

## References & Research

- `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh` (reap block
  ~`:187-287`, allocations at `:30`, `:103`, meta dir at `:290`)
- `plugins/soleur/skills/skill-security-scan/scripts/lib.sh` (`stdin_to_tempfile`)
- `plugins/soleur/skills/skill-security-scan/test/meta-dir-reap.test.sh`
- `plugins/soleur/scripts/lib/tmp-classify.sh` (`tc_is_protected`)
- `plugins/soleur/test/skill-security-scan.test.ts` (post-exit consumer
  contract)
- `knowledge-base/project/plans/2026-07-22-fix-testall-worktree-contention-plan.md`
  (measured scratch leak: 45 `skill-scan-input-*`, 4 `skill-scan-results-*`,
  12,780 `skill-security-scan-*` dirs)
- `knowledge-base/project/specs/feat-one-shot-tmp-tmpfs-mktemp-leak/tasks.md`
  (open items 8.8/8.9 — stale `#6760` comment, size-threshold blindness)
- `knowledge-base/project/specs/feat-one-shot-10017-mktemp-tmp-leak/mktemp-census.md`
  (lib.sh caller-owns disposition)
- Related: issue #6760, issue #6789, PR #6828, issue #10017, PR #10129,
  issue #6734, ADR-129
