---
title: "fix(ci): bump-cloud-init-pin fails with SOLEUR_CREDENTIAL_REFUSED reason=token_shape"
date: 2026-10-11
slug: fix-bump-cloud-init-pin-token-shape
branch: feat-one-shot-9972-bump-pin-token-shape
issue: 9972
closes: 9972
type: fix
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix(ci): bump-cloud-init-pin fails with SOLEUR_CREDENTIAL_REFUSED reason=token_shape

## Enhancement Summary

**Deepened on:** 2026-10-11. **Method:** all deepen-plan mechanical halts run
inline (4.6 user-brand, 4.7 observability, 4.8 PAT sweep, 4.9 UI, 4.10
encryption, 4.11 `lint-guard-contract.py` rc=0, 4.12 Scope Check count=1);
implementation-realism greps (§4.45) executed by the planner — no Task tool
exists in this subagent context, so the per-section research/review agent
fan-out (Phases 2–5) could not be spawned; the equivalent checks ran directly
against the tree.

- Tightened the "only narrow-class site" claim: the repo grep returned three
  sibling `[!A-Za-z0-9_]` hits, all identifier validators by design
  (`BS_TABLE`/`BS_TABLE_S3` ClickHouse identifiers in `betterstack-query.sh:247`
  and `git-data-rung2-evidence-capture.sh:1435`; a numeric/counter check in
  `hmac-sha1-b64.sh:81`) — none are credential-shape guards, so the claim holds
  with the enumeration named.
- Cited issue/PR numbers verified live: #9893 MERGED (guard's origin, commit
  `3eb0238125` confirmed on `origin/main`), #9905/#9939/#9964 OPEN, #9944 MERGED.
- Added the `2026-09-19` unpinned-wire learning: it is the direct precedent for
  the per-token `SHIM_B64` fix — a fixture that reads a value pinned to a
  sibling constant certifies the wrong wire.
- discoverability probe corrected at plan-write time: `grep -Fc` (literal
  needle), expected `1` — verified 0→1 against a scratch copy of the post-fix
  guard; the first draft's `&& printf ok` form would have failed Check 10's
  shell-active-token reject.

## Overview

The `bump-cloud-init-pin` job fails at its args stage on every run: the
credential-shape pre-guard in `.github/scripts/bump-inngest-bootstrap-pin.sh`
accepts only `[A-Za-z0-9_]`, an alphabet modeled on the legacy ~40-char `ghs_`
installation-token format, while GitHub's issued installation access tokens are
now ~390 chars and carry `.` and `-` bytes (measured live 2026-10-11 against
installation 166065653; the probe token was revoked). The job dies with
`SOLEUR_CREDENTIAL_REFUSED reason=token_shape` before any git network call, so
the IREF/ZIREF image pins in `apps/web-platform/infra/cloud-init-inngest.yml`
never advance and merged carrier edits never reach provisions. The fix adopts
the repo's canonical credential alphabet `[A-Za-z0-9._~+/=-]` — already used by
`scripts/lib/bearer-curl.sh` `bc_ok()` (`:59`) and every inline `_bearer_ok()`
copy in the workflows — in the guard, its die message and comments, and updates
the fixture suite so a real-shaped token proves the accept path while the
still-refused shapes keep their refusal pins.

## Problem Statement / Motivation

Run 38102444768 (the vinngest-v1.1.50 mint) failed `bump-cloud-init-pin` twice
identically with `SOLEUR_CREDENTIAL_REFUSED script=bump-inngest-bootstrap-pin
reason=token_shape`. The guard was added 2026-10-10 by PR #9893 (commit
`3eb0238125`, the S4 argv-credential sweep), modeled on the legacy `ghs_` base62
installation-token shape. GitHub's issued tokens no longer have that shape: a
token minted live on 2026-10-11 carried `.` and `-` interior bytes and passed
`mint-infra-app-token`'s own exact-grant checks — the defect is the guard's
alphabet, not the mint, not the grant, and not the stored secrets. While the
job is red, GuardA drift is expected but never reconciles: every carrier edit
merged to main ships user_data that pulls a stale image (issue #9972 impact
statement; #9939's cutover unit conditions are the stranded example, refs
#9944, #9964).

Spec lacks `lane:` (no spec.md on this branch) — defaulted to cross-domain (TR2
fail-closed).

## Research Insights

### Premise Validation (Phase 0.6 — all cited claims verified against the tree)

| Cited claim | Verified | Evidence |
|---|---|---|
| #9972 open, diagnosis accurate | YES | `gh issue view 9972` → state OPEN, title matches |
| Guard on the narrow class | YES | `.github/scripts/bump-inngest-bootstrap-pin.sh:237` `''\|*[!A-Za-z0-9_]*)`, die `:241`, comments `:47` and `:234` |
| Canonical alphabet is the repo boundary | YES | `scripts/lib/bearer-curl.sh:59` `bc_ok()` uses `''\|*[!A-Za-z0-9._~+/=-]*)`; identical inline `_bearer_ok()` copies at `deploy-inngest-image.yml:59,104`, `web-platform-release.yml:1348` |
| Guard is the ONLY narrow-class site | YES | repo grep for `!A-Za-z0-9_]` returns this guard + its test needle plus three identifier validators that are narrow BY DESIGN: `BS_TABLE`/`BS_TABLE_S3` ClickHouse identifiers (`scripts/betterstack-query.sh:247`, `scripts/followthroughs/git-data-rung2-evidence-capture.sh:1435`) and a numeric/counter check (`plugins/soleur/skills/community/scripts/lib/hmac-sha1-b64.sh:81`) — none judge a credential |
| Mint composite checks grant, not shape | YES | `.github/actions/mint-infra-app-token/action.yml` gates on permissions/repositories JSON, never token bytes |
| Test anchors | YES | needle `:1969`, `refuse_row dot` `:1981`, `run_shimmed` `:1240`, `SYN_TOK`/`SYN_B64` `:1171-1172` |
| Guard provenance | YES | `git log -S 'A-Za-z0-9_]'` → commit `3eb0238125`, PR #9893, merged 2026-10-10 |

Nothing stale. One addition beyond the brief: `ADR-280`'s S4 paragraph (`:190`)
documents this guard as "a shape guard (`[A-Za-z0-9_]`, the installation-token
class)" — the fix falsifies recorded architecture; the amendment is an
in-scope file.

### Property List (Phase 0.6b)

1. A GitHub-issued installation token in the measured post-change format
   (~390 chars, interior `.`/`-` bytes) is accepted by the args-stage pre-guard
   and reaches the header-build path.
2. Every value outside the canonical alphabet `[A-Za-z0-9._~+/=-]` — and every
   control byte — is still refused with `SOLEUR_CREDENTIAL_REFUSED` before any
   git network call (the protective property is unchanged).
3. The die message and comments name the alphabet the guard actually enforces
   (message ↔ mechanism parity; the suite needle asserts the message).
4. The suite proves property 1 with a value-free accept row, not only
   negatively (a guard that only has refuse rows cannot prove it admits the
   shape it exists to admit — the class of defect this fix repairs).

### Cut List

None. Every mechanism the brief names buys a listed property; the canonical
alphabet already exists on `origin/main` (`bearer-curl.sh:59`), so no new
machinery is invented.

### Relevant files

- `.github/scripts/bump-inngest-bootstrap-pin.sh:237` — the `case` guard
  (`else` arm when `BUMP_PUSH_URL` is unset — the real-remote path)
- `.github/scripts/bump-inngest-bootstrap-pin.sh:241` — die message
- `.github/scripts/bump-inngest-bootstrap-pin.sh:47`, `:234-235` — `ghs_` class comments
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh:1969` — `assert_refused` needle
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh:1979-1985` — refuse_row block (+ comment `:1959-1963` enumerating "a dot" as refused)
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh:1171-1172` — `SYN_TOK`/`SYN_B64` constants (legacy `ghs_`+36 shape)
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh:1240-1310` — `run_shimmed` + `argv`/`inherit` local accept rows (the accept pattern to mirror)
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh:1245` — `SHIM_B64="$SYN_B64"` is pinned to the legacy token's base64; a differently-shaped token needs a per-token value
- `scripts/lib/bearer-curl.sh:59` — the canonical alphabet's home
- `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md` — `:190` documents the narrow class
- `.github/workflows/build-inngest-bootstrap-image.yml` — calling job (`GH_TOKEN: ${{ steps.mint.outputs.token }}`); failure notification step exists (Slack)

### Institutional learnings applied

- `2026-10-06-a-permission-table-is-not-the-endpoint-and-the-first-real-run-found-it.md` —
  the first production run is the only test of a token's real shape; the
  diagnosis already did the prescribed probe (live mint + revoke). The accept
  row must therefore pin the REAL measured byte set, not the legacy fixture's
  shape.
- `2026-09-19-my-fix-for-the-unpinned-wire-injected-the-seam-under-test.md`
  (test-failures) — a fixture that reads a value pinned to a SIBLING constant
  certifies the wrong wire. Direct precedent for the `SHIM_B64` fix: pinned to
  `SYN_B64`, the `argv=b64`/`out_lacks` leak checks would judge the legacy
  token's base64 on a row running a different token — deriving per-token keeps
  the check honest.
- `2026-10-10-a-log-scraping-probe-matched-the-script-it-echoed-and-the-inline-copies-dropped-the-trim-the-library-had.md` —
  inline copies of a library guard silently lose the library's pre-processing.
  `bc_ok` trims trailing whitespace before judging; this guard does not.
  Weighed and scoped OUT (see Non-Goals): `GH_TOKEN` here is minted
  programmatically into env by `mint-infra-app-token`, never a human-stored
  secret — the trim hazard class does not apply to this channel.

### Research decisions

- External research: skipped — mechanical fix, complete diagnosis, the
  canonical alphabet is in-repo.
- Community discovery: no uncovered stack (bash CI script) — skipped.
- Functional-overlap agent: not spawned (no Task tool in the planning
  subagent); the equivalent check ran directly — `bc_ok`'s alphabet is the
  existing repo mechanism this fix adopts.
- Scoped advisor consult (Phase 4.5): skipped — single-file guard fix with no
  architecture choice; no Task tool available in this context regardless.
- Skill-description budget: no `description:` edits — skipped.

## Proposed Solution

Widen the args-stage `case` class to the canonical alphabet, byte-identical to
`bc_ok`'s spelling:

```bash
case "${GH_TOKEN:-}" in
  ''|*[!A-Za-z0-9._~+/=-]*)
    _refuse_reason=token_shape
    case "${GH_TOKEN:-}" in *[[:cntrl:]]*) _refuse_reason=control_char ;; esac
    printf 'SOLEUR_CREDENTIAL_REFUSED script=bump-inngest-bootstrap-pin reason=%s\n' "$_refuse_reason" >&2
    die args "GH_TOKEN (soleur-infra installation token) is required for the push remote and must match [A-Za-z0-9._~+/=-]+ (value not shown)"
    ;;
esac
```

**Why this is safe to widen:** the token never reaches an injection-shaped
channel. It flows `env GH_TOKEN` → `printf` → `base64` →
`GIT_CONFIG_VALUE_0="Authorization: basic <b64>"` (a per-command env prefix) →
the git child's environment. It is never on argv, never inside the remote URL
(`https://github.com/${REPO}.git` stays bare), and never parsed as config
syntax — the config VALUE only ever contains base64 output. The guard's real
job is fail-fast on an empty/mis-bound/garbage credential (e.g., the wrong
secret name bound, or an API error payload captured into the var); the refused
bytes (` `, `"`, `:`, control) remain refused, and the alphabet boundary it
shares with the rest of the repo is what was wrong, not the guard's placement.

### Alternative approaches considered

| Option | Verdict |
|---|---|
| Widen the inline `case` to `[A-Za-z0-9._~+/=-]` (this plan) | **Adopted.** Byte-identical to `bc_ok`/`_bearer_ok`; minimal diff; preserves the `token_shape`/`control_char` discrimination the suite pins. |
| Source `scripts/lib/bearer-curl.sh`, call `bc_ok_var GH_TOKEN` | Rejected. `bc_ok` returns bare `1` (`bc_refuse` does carry the `control_char`/`token_shape` split, but by reading the var by name inside the curl-shaped `bc_*` API); the library's chokepoint (`bc_curl`) serves curl's `--config -`, not the `GIT_CONFIG_*` env channel this site uses, so sourcing imports a curl-shaped API to reuse one `case` line; adds a `BASH_SOURCE`-relative path dependency to a self-contained script. Copy-vs-copy drift is pinned by the canonical-body parity row (`_CANON_BODY` sweep), bc_ok-vs-copies drift by the suite's `g1.bc-parity` row (both added as-built). |
| Also add trailing-whitespace trim (full `bc_ok` parity) | Rejected — scope. `GH_TOKEN` is minted into env by `mint-infra-app-token`, never human-stored; the 2026-10-10 learning's trim hazard was stored secrets. Non-Goal with rationale below. |
| Pin the exact measured format (e.g. `ghs_` + ~390 of a measured set) | Rejected — same fragility class as the bug: the canonical alphabet is the repo's chosen boundary; pinning today's vendor shape re-breaks on the next rotation. |

## Implementation Phases

### Phase 1 — Suite first (red)

`cq-write-failing-tests-before`: the accept row must exist and be RED against
the unmodified script before the guard changes.

1. In `test-bump-inngest-bootstrap-pin.sh`, define `SYN_TOK_V2` beside
   `SYN_TOK` (`:1171`): a synthetic token ≥100 chars modeled on the measured
   ~390-char issue format, carrying at least one of every byte the legacy class
   lacked — `.`, `-`, `~`, `+`, `/`, `=` — plus `SYN_B64_V2` computed the same
   way as `SYN_B64`. Synthesized only (cq-test-fixtures-synthesized-only);
   split literal concatenation as `SYN_TOK` does so no contiguous token-shaped
   literal sits in source.
2. In `run_shimmed` (`:1245`), derive `SHIM_B64` from the passed token
   (`printf '%s' "x-access-token:${tok}" | base64 | tr -d '\n'`) instead of
   pinning `SYN_B64` — behavior-identical for every existing row (they all pass
   `SYN_TOK`), and it makes the new row's `argv=b64` leak check judge the RIGHT
   base64.
3. Replace `refuse_row dot` (`:1981`) with an accept row mirroring the `argv`
   local row (`:1260-1297`): `new_fixture_repo` → `write_fixture_cloud_inits` →
   `fixture_commit` → `seed_tag vinngest-v1.1.38` → crane-map append →
   `push` → `run_shimmed newshape local "$SYN_TOK_V2"`, then the full assertion
   set: `assert_rc 0`, `assert_result opened`,
   `assert_origin_branch ... 'soleur/inngest-pin-v1.1.38' present`,
   `shim_count 'net=1' == 2`, `sub=ls-remote`/`sub=push` == 1 each,
   `argv=token`/`argv=b64` == 0, `net=1 argv=clean url=ok` == 2,
   `net=1 .*env=header-ok` == 2, `net=0 .*env=header` == 0,
   `out_lacks` for `$SYN_TOK_V2` and `$SYN_B64_V2`.
4. Update the `assert_refused` needle (`:1969`) to the new die wording and the
   refuse-block comment (`:1959-1963`) — drop "a dot" from the refused-shapes
   list, note `.`/`-` are now in-class and covered by the accept row.
5. Run `bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh` —
   the `newshape` row must be RED at the guard (rc non-zero / refusal), every
   other row unchanged. This is the failing-test-first proof.

### Phase 2 — Widen the guard (green)

6. `bump-inngest-bootstrap-pin.sh:237`: `''|*[!A-Za-z0-9_]*)` →
   `''|*[!A-Za-z0-9._~+/=-]*)` (byte-identical to `bc_ok` `:59`).
7. `:241` die message → `must match [A-Za-z0-9._~+/=-]+ (value not shown)`.
8. `:47` comment → name the canonical alphabet and its home
   (`scripts/lib/bearer-curl.sh` `bc_ok`).
9. `:234-235` comment → canonical alphabet + why (GitHub's issued installation
   tokens now carry `.`/`-`; measured live 2026-10-11, #9972).
10. Re-run the suite — all rows green, including `newshape`.

### Phase 3 — Recorded architecture

11. Amend `ADR-280` `:190`: the guard's class reads `[A-Za-z0-9._~+/=-]` (the
    canonical alphabet, `bc_ok`), with a dated correction note that GitHub's
    issued installation tokens changed format (measured 2026-10-11; the legacy
    `ghs_` base62 assumption was the defect #9972 repaired).

### Phase 4 — Verify and ship

12. Full suite green; residual greps:
    `grep -n 'A-Za-z0-9_\]' .github/scripts/bump-inngest-bootstrap-pin.sh`
    returns nothing; `grep -n 'ghs_ class' .github/scripts/bump-inngest-bootstrap-pin.sh`
    returns nothing.
13. Commit fix + suite + ADR amendment; plan/tasks artifacts commit separately.

## Files to Edit

- `.github/scripts/bump-inngest-bootstrap-pin.sh` — guard class `:237`, die
  message `:241`, comments `:47` and `:234-235` (ask 1).
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — needle `:1969`,
  `refuse_row dot` `:1981` → `newshape` accept row, `SYN_TOK_V2`/`SYN_B64_V2`
  constants `:1171`, per-token `SHIM_B64` in `run_shimmed` `:1245`, refuse-block
  comment `:1959-1963` (ask 2).
- `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md`
  — `:190` prose correction (inferred — the fix falsifies recorded
  architecture; the ADR is `adopting`, amendment is in-scope not a new ADR).

## Files to Create

None.

## User-Brand Impact

- **If this lands broken, the user experiences:** carrier fixes "merged" to
  main but never delivered — every provisioned host's cloud-init keeps pulling
  the stale pinned image (IREF/ZIREF), so a user hits a bug that was fixed days
  ago. Manifests as an aggregate of stale provisions, loud at the CI layer
  (failed run + `#releases` Slack post), never silent per-host.
- **If this leaks, the user's data / workflow / money is exposed via:** no new
  exposure. The guard is a refusal boundary, not a secrecy boundary — the
  refusal marker is value-free before and after; the token only ever reaches
  the wire inside `base64(x-access-token:TOKEN)` in a per-command env
  `extraheader`, never argv/URL/config-file, so the widened class admits no
  injection channel. Worst misjudgment direction is under-refusal (a malformed
  credential reaches git and dies as a generic auth error — loud, same
  outcome).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the blast radius is every future
  provision's image staleness — broad but loud (Slack + red run), revertible,
  and never data-exposing; not `single-user incident` because no one user's
  trust boundary breaks, and not `none` because stale-image delivery is a real
  user-facing artifact.

## Observability

```yaml
liveness_signal:
  what: "bump-cloud-init-pin job result line (result=opened|noop|existing|error) in build-inngest-bootstrap-image.yml runs"
  cadence: "per vinngest-v* publish and manual dispatch"
  alert_target: "#releases Slack via the job's 'Post to Slack (pin-bump failure)' step (SLACK_RELEASES_WEBHOOK_URL), fires on if: failure()"
  configured_in: ".github/workflows/build-inngest-bootstrap-image.yml (Post to Slack (pin-bump failure) step)"
error_reporting:
  destination: "GitHub Actions run log — ::error::args: annotation plus the stderr marker"
  fail_loud: "SOLEUR_CREDENTIAL_REFUSED script=bump-inngest-bootstrap-pin reason=<token_shape|control_char> + failed run + Slack post"
failure_modes:
  - mode: "a valid post-format token is refused again (regression of this fix)"
    detection: "newshape accept row red pre-merge; live: reason=token_shape marker in the job log + Slack failure post"
    alert_route: "#releases Slack pin-bump failure step"
  - mode: "a malformed or empty credential reaches git (under-refusal)"
    detection: "refuse rows pin zero net=1 git calls plus the value-free marker for space/quote/colon/control/empty"
    alert_route: "suite red pre-merge; live: generic git auth failure (loud)"
  - mode: "GH_TOKEN unbound or mint output empty"
    detection: "empty-token refuse row; live: reason=token_shape marker"
    alert_route: "#releases Slack pin-bump failure step"
logs:
  where: "GitHub Actions run log, bump-cloud-init-pin job"
  retention: "GitHub default run-log retention"
discoverability_test:
  command: "grep -Fc -- '*[!A-Za-z0-9._~+/=-]*' .github/scripts/bump-inngest-bootstrap-pin.sh"
  expected_output: "1"
```

## Guard Contract

### Guard 1 — args-stage GH_TOKEN shape pre-guard

**Property.** A `GH_TOKEN` value reaches the header-build path only if it is
non-empty and composed entirely of bytes in the canonical credential alphabet
`[A-Za-z0-9._~+/=-]`; anything else dies at `args` with the value-free
`SOLEUR_CREDENTIAL_REFUSED` marker before any git network call.

**Assembly.** The single `case "${GH_TOKEN:-}"` site in
`bump-inngest-bootstrap-pin.sh` on the real-remote branch (the `else` arm taken
when `BUMP_PUSH_URL` is unset) — the only chokepoint between the env var and
`AUTH_HDR` construction; the `BUMP_PUSH_URL` arm is the fixture seam that
bypasses it by design. The suite's Guard-1 `run_shimmed ... local` rows are the
enforcement fixture: refuse rows assert zero `net=1` calls; the `newshape`
accept row asserts `ls-remote` + `push` both carry the env-delivered header.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Re-narrow the class to `[A-Za-z0-9_]` (revert this fix) | RED — the `newshape` accept row fails at the guard: `assert_rc 0`/`result opened` red |
| 2 | Drop one byte from the admitted set (e.g. remove `-` — a "second member" after `.` was admitted) | RED — `newshape`'s token carries `-`; the row goes red at the guard |
| 3 | Delete the guard `case` entirely (own-dispatch) | RED — `refuse_row empty` reaches the push path: `assert_refused` + `no-git-network-call` + `no-bump-branch` all red |
| 4 | Admit one refused byte (e.g. add ` ` or `:` to the class) | RED — `refuse_row space`/`colon` lose their refusal and marker |
| 5 | Collapse the `[[:cntrl:]]` sub-case into flat `token_shape` | RED — `refuse_row newline`/`tab` assert `reason=control_char` |
| 6 | Harness: change the `assert_refused` needle to a string the script never prints | RED — every refuse row fails at `assert_out_has wording` (proves the needle is wired to the die text) |
| 7 | Harness: pin `run_shimmed`'s `SHIM_B64` to `SYN_B64` regardless of token (the pre-fix form) | RED — `newshape`'s `argv=b64`/`env=header-ok` checks judge the wrong base64 (a weakening this fix removes; keeping per-token derivation prevents a vacuous leak check) |

**Anchor.** The guard compares no stored value; the property is per-value and
the artifact is the alphabet itself, pinned by the accept row's byte coverage
— a re-narrowing is caught by row 1/2, not by a count.

**Must-PASS control.** `SYN_TOK_V2` carries `~`, `+`, `/`, `=` alongside the
measured `.`/`-` — bytes the contract admits that GitHub is not known to emit.
The `newshape` row is the non-canonical input that must PASS: a guard that
rejects everything cannot satisfy it.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "adopt the wider alphabet in the guard, the die message, and the two 'ghs_ class' comments (~lines 47 and 234)" [brief] | `.github/scripts/bump-inngest-bootstrap-pin.sh` edits (Phase 2) | mapped |
| 2 | "update .github/scripts/test/test-bump-inngest-bootstrap-pin.sh — the assert_refused needle 'must match [A-Za-z0-9_]+' (~line 1969) and `refuse_row dot` (~line 1981), which must flip to an accept-path row proving a '.'/'-'-carrying token passes the guard and reaches the fixture push path" [brief] | `test-bump-inngest-bootstrap-pin.sh` edits (Phase 1) | mapped |
| 3 | "note as a possible Non-Goal/follow-up if you judge it worth it, e.g. whether new-format ghs_ tokens still match detection regexes" [brief] | Non-Goals + Context | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Guard/die/comment widening (`bump-inngest-bootstrap-pin.sh`) | ask 1 | asked |
| Needle update + `refuse_row dot` → accept row (`test-bump-inngest-bootstrap-pin.sh`) | ask 2 | asked |
| `SYN_TOK_V2`/`SYN_B64_V2` constants + full `argv`-row assertion set | — | inferred — the accept row needs a token value and the assertion set the existing accept pattern uses; ask 2's "proving ... reaches the fixture push path" requires them |
| Per-token `SHIM_B64` in `run_shimmed` | — | inferred — without it the new row's `argv=b64`/`out_lacks` b64 checks judge the legacy token's base64, not the row's own token (vacuous leak check) |
| Refuse-block comment update (`:1959-1963`) | — | inferred — it enumerates "a dot" as a refused shape; falsified by the fix |
| ADR-280 `:190` amendment | — | inferred — recorded architecture names `[A-Za-z0-9_]` for this guard; the fix makes it lie (wg-architecture-decision-is-a-plan-deliverable) |
| tasks.md under `specs/feat-one-shot-9972-bump-pin-token-shape/` | — | inferred — pipeline convention (Save Tasks) |

### Split Assessment

- Subsystems touched: 2 — `.github`, `knowledge-base`
- Planned files: 3 | Estimated changed lines: ~60
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `.github/scripts/bump-inngest-bootstrap-pin.sh` args-stage guard reads
      `''|*[!A-Za-z0-9._~+/=-]*)` (byte-identical to `bc_ok` at
      `scripts/lib/bearer-curl.sh:59`) and the die message names
      `[A-Za-z0-9._~+/=-]+`.
- [ ] AC2: `refuse_row dot` is gone; a `newshape` accept row runs a synthetic
      token carrying every newly-admitted byte (at least `.` and `-`) through
      `run_shimmed ... local` and asserts `rc=0`, `result=opened`, the
      `soleur/inngest-pin-v1.1.38` branch pushed, exactly `ls-remote`+`push`
      remote calls with `env=header-ok`, and no token/base64 on argv or stdout.
- [ ] AC3: `refuse_row` space, quote, colon, newline, tab, empty still refuse —
      `reason=token_shape`/`control_char` as pinned, zero `net=1` git calls,
      value never echoed.
- [ ] AC4: `bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh` exits
      green.
- [ ] AC5: `grep -n 'A-Za-z0-9_\]' .github/scripts/bump-inngest-bootstrap-pin.sh`
      and `grep -n 'ghs_ class' .github/scripts/bump-inngest-bootstrap-pin.sh`
      return nothing.
- [ ] AC6: `run_shimmed` derives `SHIM_B64` from its `<token>` argument; the
      `SYN_TOK`/`inherit`/`wire` rows' behavior is unchanged.
- [ ] AC7: ADR-280's S4 paragraph names the canonical alphabet with the dated
      correction note.

### Post-merge (pipeline — parent session owns; not gating this PR)

- [ ] AC8: the parent session re-runs run 38102444768's failed
      `bump-cloud-init-pin` job; the `SOLEUR_CREDENTIAL_REFUSED` marker is
      absent and a `soleur/inngest-pin-v1.1.50` bump PR opens.

## Domain Review

**Domains relevant:** Engineering (CI/credential infrastructure)

### Engineering

**Status:** reviewed (inline — no Task-tool domain-leader spawn available in
the planning subagent; fresh assessment per brainstorm-domain-config)
**Assessment:** single-domain infra fix inside the existing credential-refusal
boundary. No new mechanism, no new trust edge; the canonical alphabet is
already the repo's decided boundary (ADR-280). `lane: cross-domain` recorded
fail-closed (no spec.md; `infra`/`auth` keyword triggers also present), but no
second domain's assessment question matches the content.

Product/UX Gate: mechanical UI-surface check on Files-to-Edit/Create — no
`.tsx`/`page`/`layout`/component/email paths — **NONE**, gate does not fire.

## Test Scenarios

- Given `GH_TOKEN` carrying every newly-admitted byte (`.`/`-`/`~`/`+`/`/`/`=`),
  when the script runs the real-remote path under the git shim, then the guard
  accepts, the header is built per-command, and `ls-remote`+`push` complete
  against the fixture remote (`integration` — the `newshape` row; the failing
  test written first per `cq-write-failing-tests-before`).
- Given `GH_TOKEN` with an embedded space, quote, or colon, when the script
  reaches the args stage, then `reason=token_shape`, the die message names
  `[A-Za-z0-9._~+/=-]+`, and zero `net=1` git calls occur (`integration` —
  existing rows).
- Given `GH_TOKEN` with a control byte or unset, when the args stage runs,
  then `reason=control_char`/`token_shape` as before (`integration`).
- Given `run_shimmed` invoked with a non-`SYN_TOK` token, when the shim records
  argv, then `argv=b64` judges that token's base64 — per-token `SHIM_B64`
  (`unit`).
- Mutation rows per `## Guard Contract` (design-derived, written before the
  guard change).

## Architecture Decision (ADR/C4)

No new architectural decision: the canonical credential alphabet was already
decided by ADR-280 (`bc_ok` judges `[A-Za-z0-9._~+/=-]`); this plan aligns the
one site that deviated from it.

- `### ADR` — amend ADR-280's S4 descriptive paragraph (`:190`): the recorded
  `[A-Za-z0-9_]` class is falsified by this fix; in-scope task (Phase 3), not a
  new ADR.
- `### C4 views` — no C4 impact. Checked all three model files
  (`model.c4`, `views.c4`, `spec.c4`): (a) external human actors — none added,
  this touches no user surface; (b) external systems — `github` already
  modeled, no new vendor edge; (c) containers/data-stores — none (the bump
  script is workflow glue, not a platform container; `infra` system unchanged);
  (d) access relationships — unchanged (the credential flow already exists;
  only the alphabet judgement widens). No element description is falsified.
- `### Sequencing` — none; the amendment ships in this PR.

## Open Code-Review Overlap

None — `gh issue list --label code-review` bodies contain no reference to
`bump-inngest-bootstrap-pin` or `test-bump-inngest-bootstrap-pin` (checked
2026-10-11).

## Non-Goals / Out of Scope

- **`ghs_` detection-sentinel regexes.** `scripts/learning-retrieval-bench.sh:611`
  pins `ghs_[a-zA-Z0-9]{36}` — a new ~390-char token with `.`/`-` would NOT
  match; `apply-sentry-infra.yml:150` and `extract-api-spend.sh:83` use the
  bare `ghs_` prefix, which still matches. Whether new-format tokens still trip
  the length-anchored sentinels is a possible follow-up issue for the parent —
  deliberately out of scope per the brief.
- **Trailing-whitespace trim (`bc_ok` parity).** The minted env credential is
  never human-stored; the trim hazard class (2026-10-10 learning) does not
  apply here. Revisit only if a stored-secret path ever feeds `GH_TOKEN`.
- **Sourcing `scripts/lib/bearer-curl.sh`.** Rejected alternative — see the
  table; drift is pinned by the accept row instead.
- **Re-running run 38102444768's failed job** — parent session's scope (AC8
  records it).
- **#9905 (S4 first-real-run tracker), #9939, #9944, #9964** — context only;
  no edits.

## Risks

- **Vendor format rotates again.** Mitigated: the guard now shares the repo's
  canonical alphabet boundary rather than a vendor-shape assumption; a future
  rotation fails loud (marker + Slack), not silent.
- **Under-refusal via the wider class.** Analyzed above: the token only ever
  reaches the wire inside base64 in env-config; the refused bytes retain their
  rows. Worst case is a generic git auth failure — same loudness class.
- **Accept-row over-fits the fixture.** The row asserts the real-remote
  behavior contract (branch push + header env), not the token's specific value
  — the fixture is synthetic by rule.

## Context

The issue's original "Fix-Size" note guessed "likely an App permission/scope
or a secret rotation"; the completed diagnosis rules both out — the minted
token passes `mint-infra-app-token`'s exact-grant checks and the failure is
the guard's alphabet. Specimen of the class #9905 tracks (S4 credential
conversions' first real runs). The failed job in run 38102444768 is re-run by
the parent session after merge — not this PR's scope.

## References

- Issue: #9972 (this plan), #9905 (S4 verification tracker), #9939, #9944, #9964
- Guard added by: PR #9893 / commit `3eb0238125` (S4 argv-credential sweep, 2026-10-10)
- Canonical alphabet: `scripts/lib/bearer-curl.sh:59` (`bc_ok`), ADR-280
- Caller: `.github/workflows/build-inngest-bootstrap-image.yml` (`bump-cloud-init-pin` job)

## Sharp Edges

- The guard only fires on the real-remote path (`BUMP_PUSH_URL` unset). Every
  `run_bump` fixture row bypasses it via `GH_TOKEN="${RB_GH_TOKEN-...}"` — the
  accept proof MUST go through `run_shimmed`, not `run_bump`.
- `run_shimmed` pinned `SHIM_B64="$SYN_B64"` before this fix; a differently
  shaped token silently tests the wrong base64. Keep the per-token derivation.
- `SYN_TOK` itself is the legacy `ghs_`+36 shape — do NOT "fix" the fixture by
  mutating `SYN_TOK`; the legacy shape must stay accepted (it is still inside
  the canonical alphabet) and the refuse rows' `${SYN_TOK:0:12}` splices depend
  on its length.
- `:` stays refused — it is the config/URL injection byte the refuse rows pin;
  do not widen past the canonical set "for symmetry".
- The xtrace refusal (rc 78) fires before credential judgement and is
  untouched by this change — do not reorder it after the guard.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6.
