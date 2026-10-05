---
title: "fix: migrate the stock-preflight gate off the removed GET /datacenters onto /server_types locations[]"
date: 2026-10-05
slug: stock-preflight-server-types-locations
branch: feat-one-shot-stock-preflight-server-types-locations
issue: 9377
type: fix
lane: single-domain
requires_cpo_signoff: true
---

# fix: migrate the stock-preflight gate off the removed GET /datacenters onto /server_types locations[]

## Overview

Hetzner removed `GET /v1/datacenters` (it now answers HTTP 410, announcement
`https://docs.hetzner.cloud/changelog#2026-06-02-datacenters-deprecated`, removal stated as "after 1 Oct. 2026").
The sourced stock gate `tests/scripts/lib/stock-preflight-gate.sh` makes a second API call to that endpoint
(line ~138) and reads `.datacenters[].server_types.available` (lines ~82, ~154). It therefore aborts
fail-closed on every host create, replace or recut that sources it: eight call sites in
`.github/workflows/apply-web-platform-infra.yml` call `stock_preflight_gate`, and the registry recut also calls
`stock_preflight` directly (advisory pre-rehearsal probe). Runs 37279684488 and 37280063535 (web-host-replace,
plan-only) passed the plan and the replace gate and then died at the stock gate. That blocks R-step 5 (replace
standby web-2).

The fix derives availability from the one `GET /v1/server_types?name=<type>` response the gate already makes:
`server_types[].locations[]` carries `{id, name, available, recommended, deprecation}` per location. The second
call, the numeric type-id join key and every `.datacenters` read are deleted. The gate stays fail-closed, keeps
the EU-only residency filter for the alternatives list, keeps the distinct stock-miss and API-blip messages, and
keeps the repair-path text for #6463.

## Enhancement Summary

**Deepened on:** 2026-10-05
**Sections enhanced:** Observability, Research Insights (related issues), Risks
**Research agents used:** six-reviewer plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO devex) ran before this pass; this pass ran the deepen-plan halt gates and the live-verification checklist directly (a second fan-out was judged redundant against the panel's coverage of the same plan text).

### Key Improvements
1. Observability probe rewritten: the first draft's `discoverability_test.command` ran the whole suite (rejected by Phase 4.7: suite-shaped, cap risk). Replaced with a one-line `git grep -c` liveness-line probe whose `expected_output` is a matchable literal.
2. Citation correction: #6393 is a merged PR (the relocation that wedged the deploy leg), not a wedge issue; wording fixed and verified live with `gh issue view`.
3. jq version risk recorded (verified on 1.8.2 only; runners ship 1.7.x).

### Gate results
User-Brand Impact present with a valid threshold (4.6); Observability schema present, probe verb allowlisted, SSH-free, under the cap (4.7); no PAT-shaped variable (4.8); no UI surface (4.9); Encryption Posture not triggered (no `.tf`/migration/cloud-init/compose file, no store or connection; section states N/A with reason) (4.10); `lint-guard-contract.py` green on 5 entries and the Assembly rows name chokepoints, not today's members (4.11); one unfenced `## Scope Check`, every ask quoted from the brief, no `status: BLOCKED` (4.12); cited rule ids exist (`cq-test-fixtures-synthesized-only`, `cq-write-failing-tests-before`); cited issues verified live (#9377, #8609, #7044, #6730 open; #6463, #6400, #6453, #6570, #6969 closed; #6393 merged). Verify-the-negative: `git grep -n datacenters -- .github scripts plugins/soleur/skills` returns nothing, and nothing outside the lib and its suite references `_stock_fetch`, `HCLOUD_API` or `_stock_eu_locations_for`, so the "no workflow parses /datacenters" and "callers unchanged" claims hold.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief | Reality (verified in this worktree) | Plan response |
|---|---|---|
| "Do NOT edit .github/workflows unless a workflow itself parses /datacenters (grep first)" | `git grep -n datacenters -- .github` returns nothing. The workflow only `source`s the lib and calls `stock_preflight_gate tfplan.json` (8 sites, all `if ! ...`) and `stock_preflight "$SRV_TYPE" "$SRV_LOC"` (1 site, advisory, `set +e`). No workflow parses /datacenters. | No workflow edit. Public function names, arguments and return codes are unchanged. State in the PR body that none parses /datacenters. |
| "inngest-host-replace, registry-host-replace and others source the lib" | Correct: six plan steps (inngest-host-replace, registry-host-replace, registry-region-migrate, git-data-host-replace, web-host-create, web-host-replace) plus the registry-recut gate call and its advisory probe. | One lib edit covers all. `plugins/soleur/test/stock-preflight-coverage.test.ts` and `terraform-target-parity.test.ts` assert workflow structure only; they are run, not edited. |
| "Update every fixture/stub and test that models the old /datacenters shape" | Only `tests/scripts/test-stock-preflight-gate.sh` models it (`fixture_dcs`, `FETCH_MODE=fail_dcs`, the `/datacenters*)` seam arm, T14, and header/T4/T14 comments mentioning `/datacenters` and `.supported`). `test-eu-location-allowset-parity.sh` greps only the `STOCK_PREFLIGHT_EU_LOCATIONS="${...:-nbg1 fsn1 hel1}"` default line. Nothing outside the lib and its suite references `_stock_fetch`, `HCLOUD_API` or `_stock_eu_locations_for`. | Rewrite the one suite, including its stale comments; keep the default-line shape. |
| "Refs #9377 and Refs #8609" | #9377 is OPEN, titled "split the web-host LUKS header-escrow credential from web-1's backup bucket access"; #8609 is OPEN, titled "the soleur-ai runtime App key in Doppler prd is reachable from any branch". Neither title mentions a stock gate. | Keep the operator's numbers (`Refs`, never `Closes`) and flag the title mismatch in the PR body. |
| "keep the repair-path text for the earlier stock-shortage issue" | That is #6463 (CLOSED); the abort menu names it and T2/T10b/T10c assert the text. | Keep the menu verbatim (AC7). |
| Terraform side: does the apply leg still work once the gate passes? | `apps/web-platform/infra/*.tf` set `location`, never a `datacenter =` argument (grep). The provider is `hetznercloud/hcloud ~> 1.49`; the plan-only runs already passed `terraform plan`. Whether provider create/refresh paths touch the removed endpoint cannot be proven without a live apply. | Out of scope; recorded as a residual risk. AC9 (the operator's re-dispatch) is the first real verification. |

## Research Insights

### Premise Validation

Checked: the cited run ids and the 410 body come from the operator's read-only probe and are not re-probed (no live
credentialed calls are permitted); #9377/#8609/#6463/#7044 states read with `gh issue view`; the lib exists on this branch
at the cited line numbers (320 lines); the Hetzner changelog (public, WebFetch, no credentials) was read for the semantics of
`server_types.locations`. Held: the gate calls /datacenters at line 138 and reads `.datacenters` at 82/139/146/154. Mismatched:
the two Refs issue titles. Doc facts that shape the design, quoted from the changelog: a type "is implied to be supported if the
`server_types.locations` property returns the Location", and `locations.available` "remains only an indicator whether resources
are currently available and is no guarantee". So (a) PRESENCE of a location entry is the new "supported" and must never be read as
orderable, and (b) `available` carries the old orderable-now meaning with the caveat the gate's TRIPWIRE framing already carries.
The `available` semantics are doc- and operator-probe-derived; no live 200 sample is captured here, so every fixture is only as
accurate as that source. Mechanism vs ADR corpus: no ADR decides the /datacenters mechanism (ADR-143/154 cite dated measurements).

### Property List

1. P1: the gate decides "is server type T orderable in location L right now" from the /server_types?name=T response alone and never requests /datacenters.
2. P2: the gate authorizes (rc 0) only when a 2xx, single-JSON-document, error-free response contains exactly one server type named T whose `locations` array contains exactly one entry named L whose `available` is the JSON boolean `true`.
3. P3: every other outcome returns rc 1 with a message that distinguishes stock miss (`available:false`), unknown type, unknown/not-offered location, and unprovable (transport, HTTP error, malformed) and says WHY for the last class.
4. P4: the "orderable in EU" alternatives list contains only EU-allow-set locations whose `available` is the boolean `true`.
5. P5: callers, function names, arguments, return codes, the `STOCK_PREFLIGHT_EU_LOCATIONS` default-line shape and the #6463 repair text are unchanged.

### Cut List (mechanism minimality, Phase 0.6b, updated after plan review)

| Mechanism | Property it would buy | Cut / kept, and what already covers it |
|---|---|---|
| Second API call to a replacement endpoint | none | Cut. `locations[]` is in the first response. |
| Numeric `type_id` join key | none | Cut. It only joined the type to `.datacenters[].server_types.available` (ids). |
| Reading `locations[].deprecation` to deny | P2 | Cut as a denial rule; the old gate never read it and Hetzner folds `unavailable_after` into `available`. The canonical must-PASS fixture carries a non-null `deprecation` with `available:true` so the decision is explicit. |
| Committed mutation-battery suite; `STOCK_PREFLIGHT_GATE_FILE` override in the committed suite | anti-vacuity | Cut (review: simplicity, SpecFlow C4, Kieran L1). The battery runs once at work time against a scratch MIRROR of `tests/scripts/` (the suite derives `REPO_ROOT` from its own path, so a mirrored tree needs no override seam); results go in the PR body. |
| Name-shape guard (`^[a-z0-9-]+$`) and word-splitting `case` loop in the alternatives list | P4 | Cut (review: DHH, simplicity; Kieran M3 showed the regex was version-fragile). The EU intersection moves into jq (`--arg eu`, `IN($allow[])`), so there is no shell word-splitting to inject into and no regex to maintain. |
| `any(type != "object")` junk-sibling clauses | P2 | Cut (review). `.name` on a non-object member makes jq exit non-zero with no output, which the capture's `|| verdict=""` routes to the blip arm; a `null` sibling is harmless. Pinned by T17b without a dedicated guard. |
| Early empty-body test before the verdict | P3 | Cut (Kieran M2): an empty body yields an empty verdict, already the `case` default arm. |
| Separate `fail_types` seam mode, T7e/T20d "410 at /datacenters leaves the verdict unchanged" | P1 | Cut (identical to `fail_all` / duplicates the single-fetch tripwire). One tripwire assertion covers P1. |
| Guard 5 harness-row family | suite non-vacuity | Reduced to the existing `MIN_ASSERTIONS` floor plus T14, three rows. |
| Editing `.github/workflows/*`, `variables.tf`, `zot-registry.tf`, ADR bodies | none | Cut. None parses /datacenters; the `.tf`/ADR mentions are dated history and `.tf` edits path-trigger infra workflows. |
| `--fail-with-body` on the curl seam | P2 (non-2xx must abort) | KEPT, inferred (Scope Check). The only status-aware control. |
| Loopback python3 wire-level test | exercises the real `_stock_fetch` | KEPT, trimmed to the cases only it can see (Kieran, CTO, SpecFlow want it; DHH, simplicity want a PATH `curl` shim instead). Recorded as a taste challenge in `decision-challenges.md`. |

### Plan-review consolidation (six reviewers, headless)

Mechanical, applied: capture the verdict with `|| verdict=""` (Kieran H1: jq 1.8.2 printed `ORDERABLE` and then exited 5 on `{valid}garbage`; reproduced locally); `MALFORMED:<reason>` tokens and a curl-exit/HTTP hint in the blip message (CTO, SpecFlow C1); filter-ignored/paginated responses become `MALFORMED:filter-ignored`, not "typo" (SpecFlow C3); fix equivalent-mutant rows 1.5/1.6, T19 and naming collisions (Kieran M1-M5); battery rows assert `! cmp -s`, `bash -n` and the failing case id (Kieran M6); loopback re-sources the lib in a subshell, neutralizes proxies, composes traps, bounds the readiness wait (Kieran M4, SpecFlow C2); prose-churn list completed (Kieran L3); dated header pointer for the ADR-154 probe (Architecture 6, CTO); a PR-body note that the `available` semantics are doc-derived and AC9 is the first live verification (Architecture 1). Taste/User-Challenge, persisted to `knowledge-base/project/specs/feat-one-shot-stock-preflight-server-types-locations/decision-challenges.md`: collapse to a `== [true]` one-liner and drop exactly-one/enum (DHH), loopback vs curl shim, deny on a past `deprecation.unavailable_after` (SpecFlow I5), committing the mutation battery (CTO), `-w '%{http_code}'` 2xx-only gating (Kieran L2).

### Institutional learnings applied

- `cq-test-fixtures-synthesized-only`: all fixtures synthesized; synthetic type ids and names; the 410 body is a synthesized copy of the measured shape.
- Suite header: stock is time-varying; never assert live stock; `_stock_fetch` stays the only fetch path.
- jq `//` on a boolean eats `false` (`.available // empty`); the verdict branches on `type == "boolean"` and never uses `//` on `available`. A one-line comment at that site says why.
- `$(...)` is a subshell: a call counter in the test seam does not survive; the tripwire writes to a file under `$TMP`.
- `curl -sS` exits 0 on HTTP 4xx/5xx and prints the body; today's 410 only aborts because `.datacenters` is absent from the error body. The new path must not rely on that accident.
- jq may print a value and then exit non-zero on trailing bytes; an unchecked capture authorizes. Always `|| verdict=""` and require the exact token.

### Related issues and PRs

#6463 (closed; the repair path the abort text cites), #6393 (merged PR whose relocation wedged the web-1 deploy leg ~10 h, per the gate's own header; PIR correction #6400), which is the failure the gate prevents, #7044 (open: preamble retrofit of this gate; acknowledged, not folded in), #6453, #6570, #6730, #6969 (added callers).

## User-Brand Impact

- **If this lands broken, the user experiences:** either every host create or replace stays blocked (today: the standby web-2 cannot be rebuilt, so the fleet stays one host short and the ADR-143 active-active posture cannot be restored), or a wrong "orderable" answer lets a `-replace` destroy a live host whose create then fails with `resource_unavailable`, leaving the product without that host and with no rollback (the #6393 wedge, a prod deploy leg frozen ~10 h).
- **If this leaks, the user's workflow is exposed via:** no data path is touched. The gate reads public catalog data with a read-only token; the only vector is a mis-authorized destroy-first replace that strands capacity (availability, not confidentiality). The token is never printed (`::add-mask::` stays at the workflow call site; tests use only a synthetic token).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one wrongly authorized destroy of a live production host takes real users' sessions down with no rollback, so this is not an aggregate-pattern risk; the operator's brief states the same threshold. DHH and the simplicity reviewer argued the gate is "only a tripwire" and the plan is oversized for it; the threshold is why the exactly-one and enum guards were kept.

CPO sign-off is required at plan time before `soleur:work` (`requires_cpo_signoff: true`; no brainstorm carry-forward exists on the one-shot path). `soleur:engineering:review:user-impact-reviewer` runs at review time. No new CLO/CTO concern (no data, no residency change; the EU allow-set is preserved and re-tested).

## Design

### Verdict function

One jq program reads the single /server_types response and prints exactly one token. The caller captures it as
`verdict=$(_stock_verdict "$types_json" "$want_type" "$want_loc") || verdict=""` (`verdict` declared separately, never
`local v=$(...)`), and ONLY the exact string `ORDERABLE` returns 0; every other value, including empty, a two-line string
(two JSON documents) and a non-zero jq exit, falls to the blip arm. Validated locally on synthetic inputs: canonical orderable,
unavailable, string/number/absent `available`, absent/null/object/array `locations`, error body, `{"error":..}`, `[]`, `null`,
`"x"`, HTML, wrong type name, duplicate entries, junk siblings, `{valid}garbage` (jq prints then exits 5), `{valid}{valid}`.

```bash
# _stock_verdict <types_json> <type> <loc>
#   -> ORDERABLE | UNAVAILABLE | UNKNOWN_TYPE | UNKNOWN_LOCATION | MALFORMED:<reason>
_stock_verdict() {
  printf '%s' "$1" | jq -r --arg t "$2" --arg l "$3" '
    if (type != "object") or has("error") or ((.server_types | type) != "array") then "MALFORMED:shape"
    elif (.server_types | length) == 0 then "UNKNOWN_TYPE"
    else [.server_types[] | select(.name == $t)] as $m
      | if   ($m | length) == 0 then "MALFORMED:filter-ignored"
        elif ($m | length) >  1 then "MALFORMED:duplicate-type"
        elif ($m[0].locations | type) != "array" then "MALFORMED:locations"
        else [$m[0].locations[] | select(.name == $l)] as $e
          | if   ($e | length) == 0 then "UNKNOWN_LOCATION"
            elif ($e | length) >  1 then "MALFORMED:duplicate-location"
            elif ($e[0].available | type) != "boolean" then "MALFORMED:available"
            elif $e[0].available then "ORDERABLE" else "UNAVAILABLE" end
        end
    end' 2>/dev/null
}
```

Key points: select by `.name == $t`, not `.server_types[0]` (if `?name=` is ever ignored, `[0]` answers about a different type);
a non-empty list with no name match is `MALFORMED:filter-ignored` (never "typo", never authorization), an empty list is
`UNKNOWN_TYPE`; exactly-one matches; `locations` absent/null/object is `MALFORMED:locations`, an empty array is
`UNKNOWN_LOCATION`; `available` must be the boolean (`"true"`, `1`, `null`, absent are `MALFORMED:available`, never orderable and
never "stock miss"). The `type != "object"` clause stays LEFT of `has("error")` (jq `or` short-circuits).

### Alternatives list (EU filter retained, no shell word-splitting)

```bash
# _stock_eu_locations_for <types_json> <type>   (takes only what it reads)
_stock_eu_locations_for() {
  printf '%s' "$1" | jq -r --arg t "$2" --arg eu "$STOCK_PREFLIGHT_EU_LOCATIONS" '
    ($eu | split(" ") | map(select(. != ""))) as $allow
    | [.server_types[] | select(.name == $t)] | if length == 1 then .[0].locations[]? else empty end
    | select(.available == true and (.name | IN($allow[]))) | .name' 2>/dev/null | sort -u | paste -sd' ' -
}
```

Strict `== true` (a string `"true"` or `1` is not suggested); the allow-set intersection is inside jq, so no location name
can word-split into a shell loop. It runs only on the UNAVAILABLE arm; a failure degrades the `<none>` text, never the decision.

### Fetch seam and the blip message

`_stock_fetch` keeps its name, signature and `HCLOUD_API` override and gains `--fail-with-body` (curl >= 7.76; CI runners and the dev
box are far past it; on an older curl the unknown flag exits non-zero, which is a loud fail-closed outage, not a false green). The
caller captures `fetch_rc` instead of discarding it: `types_json=$(_stock_fetch ... 2>/dev/null) || fetch_rc=$?`. The blip message
becomes: `cannot PROVE stock for 'T' in 'L' (Hetzner API unreachable or malformed at /server_types: <reason>). An unreachable API is
not evidence of availability. Re-dispatch; if it repeats on consecutive dispatches the API contract has likely changed — see the
header of this file and the changelog URL.` where `<reason>` is `curl exit N`, `empty body` or the `MALFORMED:<reason>` token. The
first line still starts `stock-preflight ABORT:` and never contains "NOT orderable", so the advisory probe's `head -1` re-emit
(`apply-web-platform-infra.yml`, "NOT currently orderable ... " prefix) reads accurately enough and is noted in the PR body.

### stock_preflight flow after the change

shape-guards on `want_type`/`want_loc` (unchanged) -> ONE `_stock_fetch "/server_types?name=${want_type}"` -> non-zero fetch rc or empty
body = blip -> `_stock_verdict` -> `case`: `ORDERABLE` rc 0 (the only `return 0` in the function); `UNAVAILABLE` stock-miss abort with the
unchanged remediation menu and the new alternatives list; `UNKNOWN_TYPE` "unknown server_type"; `UNKNOWN_LOCATION` "unknown location '<L>' for
server_type '<T>' (not in /server_types locations[]: a mistyped location, or a type Hetzner does not offer there — check `location` in the plan
and variables.tf)"; `*)` blip. Header comment adds: `available` is an indicator, not a reservation (Hetzner's wording); the dated 410 note
and changelog URL; the equivalent re-evaluation probe for ADR-154's old trigger is `GET /v1/server_types?name=cx33` -> `locations[]`; #7044 link.

## Implementation Phases

### Phase 1 — RED first (cq-write-failing-tests-before)

1. Rewrite the fixtures to the new shape (topology unchanged: eu-a, eu-b, eu-c EU; far non-EU; synthetic names/ids; entries carry `id,name,available,recommended,deprecation`). The canonical orderable fixture gives beta22's eu-b entry a non-null `deprecation` object.
2. Replace `fixture_dcs` and the `/datacenters*` seam arm with a TRIPWIRE: the seam appends EVERY requested path to `$TMP/calls.log` (file, subshell-safe) and serves the synthesized 410 body with rc 0 for `/datacenters*`. Update the stale header, T4 and T14 comments that describe `/datacenters`/`.supported`. Add a comment at the seam saying why the log is a file.
3. Run the suite against the UNCHANGED lib; record the RED case ids.

### Phase 2 — GREEN: the lib

`--fail-with-body`; `_stock_verdict`; two-arg `_stock_eu_locations_for`; the `stock_preflight` flow above; delete `type_id`, `dcs_json`, `dc_name`, `orderable`, the `/datacenters` fetch; rewrite the header ("`.supported`" -> "presence = supported, `.available` = orderable now", the residency note, the stale "each location maps to exactly one datacenter" paragraph, the `/v1/datacenters` mentions). Keep `STOCK_PREFLIGHT_EU_LOCATIONS="${STOCK_PREFLIGHT_EU_LOCATIONS:-nbg1 fsn1 hel1}"` byte-identical and the abort menu `echo` lines byte-identical (AC7).

### Phase 3 — verify (targeted suites only, never the full battery; nothing is dispatched; no credentialed probe)

```bash
bash tests/scripts/test-stock-preflight-gate.sh
bash tests/scripts/test-eu-location-allowset-parity.sh
bash tests/scripts/test-plan-gate-preamble.sh
bun test plugins/soleur/test/stock-preflight-coverage.test.ts plugins/soleur/test/terraform-target-parity.test.ts
shellcheck tests/scripts/lib/stock-preflight-gate.sh tests/scripts/test-stock-preflight-gate.sh
python3 scripts/lint-shell-capture-exit.py tests/scripts/lib/stock-preflight-gate.sh tests/scripts/test-stock-preflight-gate.sh
```

### Phase 4 — mutation battery (scratch, not committed)

Mirror `tests/scripts/` into the scratchpad (`REPO_ROOT` is derived from the suite's own path, so no override seam is needed). Per Guard Contract row: copy the finished lib to `<mirror>/tests/scripts/lib/`, apply the one edit with `sed`/`python3`, then require ALL of: the edit changed the file (`! cmp -s`), the mutant parses (`bash -n`), the suite exits non-zero, and the failing case id equals the row's expected id (a RED for the wrong reason is a defect in the row). Harness rows edit the mirrored suite instead. The worktree lib is never edited (no git stash). Paste the table (row, verdict, failing ids) into the PR body; rows that stay green must be explained (equivalent mutant) or fixed.

## Files to Edit

- `tests/scripts/lib/stock-preflight-gate.sh` — header prose, `_stock_fetch` flag, `_stock_verdict` (new), `_stock_eu_locations_for`, `stock_preflight`.
- `tests/scripts/test-stock-preflight-gate.sh` — fixtures, seam tripwire, new cases, stale comments, `MIN_ASSERTIONS` floor raised to the measured count (re-measure whenever a block is removed or consolidated; `-lt`, so adding cases never trips it).

## Files to Create

None beyond the plan and `knowledge-base/project/specs/feat-one-shot-stock-preflight-server-types-locations/{tasks.md,decision-challenges.md}`.

Verified-unaffected (run, not edited): `tests/scripts/test-eu-location-allowset-parity.sh`, `tests/scripts/test-plan-gate-preamble.sh`, `plugins/soleur/test/stock-preflight-coverage.test.ts`, `plugins/soleur/test/terraform-target-parity.test.ts`, `scripts/lib/test-affected-paths.sh` (lib already mapped), `scripts/test-all.sh` (suite registered).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (87 issues) was searched for each of the three files; zero bodies name them. Related, not folded: #7044 (preamble retrofit) is a different concern.

## Infrastructure (IaC) and Encryption Posture

Not applicable: no server, secret, vendor, DNS or Terraform resource and no persistent store or new cross-component connection. The existing HTTPS call to `api.hetzner.cloud` keeps curl's default certificate verification; the loopback test server is test-only plain HTTP on 127.0.0.1 with a synthetic token.

## Observability

```yaml
liveness_signal:
  what: the gate's own PASS/ABORT annotation in the apply workflow run log ("stock-preflight PASS: N planned server create(s) orderable" / "stock-preflight ABORT: ...")
  cadence: every dispatch that creates or replaces a host
  alert_target: GitHub Actions run annotation (::error:: on abort); the dispatching operator reads it in the run log
  configured_in: tests/scripts/lib/stock-preflight-gate.sh (the success echo at the end of stock_preflight_gate)
error_reporting:
  destination: GitHub Actions ::error:: annotations
  fail_loud: true
failure_modes:
  - mode: Hetzner removes or changes the /server_types locations[] shape again
    detection: every stock_preflight returns the "cannot PROVE stock ... malformed at /server_types: MALFORMED:<reason>" message, distinct from a shortage, visible on the first dispatch
    alert_route: ::error:: annotation on the dispatching run
  - mode: gate silently authorizes a malformed document
    detection: the closed verdict enum plus the suite's malformed-shape cases and the mutation battery; no runtime detector exists for a false green, which is why only the exact token ORDERABLE authorizes
    alert_route: CI red on tests/scripts/stock-preflight-gate
  - mode: HTTP error status with a valid-looking body
    detection: curl exits 22 under --fail-with-body; the blip message carries "curl exit 22"; covered by the loopback case
    alert_route: ::error:: annotation
logs:
  where: GitHub Actions run logs (apply-web-platform-infra.yml)
  retention: GitHub default run-log retention
discoverability_test:
  command: git grep -c 'stock-preflight PASS:' -- '*stock-preflight-gate.sh'
  expected_output: stock-preflight-gate.sh:1
```

The command proves the positive liveness line still exists in the gate (a rotted gate silent on success would not carry it) in well under Check 10's 15-second cap. It deliberately is NOT the suite (`bash tests/scripts/test-stock-preflight-gate.sh` is the way to TEST the gate, not to DISCOVER its signal; plan Phase 2.9 rejects a suite-shaped probe).

## Guard Contract

Matrices are written from the DESIGN (the property) before the code. Mutants are copies of the lib in the scratch mirror; harness rows edit the mirrored suite.

### Guard 1 — Fail-closed response and status gate (P2, P3)

**Property.** No response other than a 2xx, single-JSON-document, error-free object with an array `.server_types` can authorize a destroy; every other response returns rc 1 through the blip message, never the stock-miss message.

**Assembly.** Every path by which a body reaches a verdict: the `_stock_fetch` curl invocation (status), the `fetch_rc` capture, the `_stock_verdict` top-level `if`, the `|| verdict=""` capture (jq exit status), and the caller's `case` default arm. The chokepoint is the exact-token match: only the literal `ORDERABLE` returns 0, and everything else (empty, multi-line, unexpected word) falls to rc 1.

**Mutation matrix.**

| # | Edit | Must go RED at | Notes |
|---|------|----------------|-------|
| 1.1 | Remove `--fail-with-body` from `_stock_fetch` | T20c: loopback HTTP 502 with a VALID `available:true` body must return rc 1 | only a status-aware test sees this |
| 1.2 | Drop `or has("error")` | T7f: 200 body carrying a valid orderable beta22 AND an `error` key must return rc 1 | the bare 410 body lacks `.server_types`, so it cannot catch this |
| 1.3 | Drop the `|| verdict=""` (capture ignores jq's exit status) | T7i: `<valid orderable doc>garbage` must return rc 1 | jq prints ORDERABLE then exits 5 (reproduced) |
| 1.4 | Change the `case` default arm to `*) return 0` | T7 (fail_all), T7c (garbage), T7d family | dispatch of the guard itself |
| 1.5 | Drop the `((.server_types \| type) != "array")` clause | T7d table: `{"server_types":null}`, `{"server_types":{}}`, `{}`, `[]`, `null`, `"x"` | a second malformed shape after a compliant first: the table iterates ALL bodies |
| 1.6 | Drop the exact-token match (use `*ORDERABLE*`) | T7j: `{valid}{valid}` (two documents, two-line verdict) must return rc 1 | substring match over a multi-line verdict |
| 1.7 (harness) | Edit the SUITE: make the `fail_all` seam return a VALID orderable doc with rc 1 | T7 must stay GREEN (the gate must honour the fetch rc, not the body) | the failure injection is real in the direction that matters |
| 1.8 (must-PASS, non-canonical) | Valid doc with extra unknown fields, reversed `locations` order, `deprecation` non-null object with `available:true` | rc 0 | a guard that rejects everything cannot pass this |

**Anchor.** None: no stored value is compared. The suite floor (Guard 5) is the only count and is paired with named cases.

### Guard 2 — Exact verdict extraction (P2)

**Property.** Rc 0 requires exactly one server type named T, whose `locations` array holds exactly one entry named L, whose `available` is the boolean `true`.

**Assembly.** The three selection stages in `_stock_verdict` (type by name, location by name, `available` type) plus the caller's one-token-to-one-message mapping. Members drift (Hetzner adds fields, reorders lists); the structural chokepoint is that every positive path goes through the one `ORDERABLE` branch, and `stock_preflight` has exactly one `return 0`.

**Mutation matrix.**

| # | Edit | Must go RED at | Notes |
|---|------|----------------|-------|
| 2.1 | Select the type with `.server_types[0]` instead of by name | T18a: `[other(true everywhere), wanted(false at eu-b)]` must abort | the filter-ignored fail-open |
| 2.2 | Remove the `($m \| length) > 1` branch | T17a: duplicate type entries must be MALFORMED | second member after a compliant first |
| 2.3 | Remove the `($e \| length) > 1` branch | T17b/T17c: two entries for L, (true,false) and (false,true), must abort | both orders |
| 2.4 | Replace the boolean check with `// true` / `.available // empty` | T16: `"true"`, `1`, `null`, absent must be `MALFORMED:available`; real `false` must stay the stock-miss message | the `false // x` trap; one comment in the lib names it |
| 2.5 | Read presence as orderable (return ORDERABLE when the entry exists) | T2, T3, T4 (alpha33/arm11/sing44 are present-but-unavailable) | the old `.supported` trap relocated; T14 pins the fixture |
| 2.6 | Treat `locations` absent/`{}` as UNKNOWN_LOCATION or stock miss | T15: absent key, `null`, `{}` -> `MALFORMED:locations`; `[]` -> unknown location; none rc 0 | |
| 2.7 | Dispatch: replace `.name == $l` with `true` | T6 (`atlantis`, and partial55@eu-b) and T2 | a verdict that ignores L passes T1 only |
| 2.8 | Make a non-empty list with no name match return UNKNOWN_TYPE | T18c: `[other]` must say filter-ignored, not "typo" | the misdirection class (SpecFlow C3) |
| 2.9 (must-PASS, non-canonical) | beta22 listed second in `.server_types`, eu-b last among locations, a `null` sibling in `.server_types`, extra fields | rc 0 | permitted variation |

**Anchor.** None (no stored value).

### Guard 3 — EU residency filter and strict alternatives list (P4)

**Property.** The "orderable in EU" list never contains a non-EU location or a location whose `available` is not the boolean `true`.

**Assembly.** `_stock_eu_locations_for` (selection, `== true`, allow-set intersection inside jq) and its single call site in the UNAVAILABLE arm. The EU default line is also encoded in `variables.tf` x3 and pinned by `test-eu-location-allowset-parity.sh`; that suite is part of the assembly.

**Mutation matrix.**

| # | Edit | Must go RED at | Notes |
|---|------|----------------|-------|
| 3.1 | Remove the `IN($allow[])` intersection | T4: sing44 (available only in `far`) must read `orderable in EU: <none>` and `far` must not appear | residency |
| 3.2 | Change `.available == true` to truthiness | T19: eu-c with `available:"true"` and `1` must not be suggested | strict boolean |
| 3.3 | Include `available:false` locations | T2/T3 | list reads wrong |
| 3.4 | Change the `STOCK_PREFLIGHT_EU_LOCATIONS` default (remove `hel1`) | `test-eu-location-allowset-parity.sh` must go RED | cross-suite row; the anchor is that independent file |
| 3.5 (must-PASS) | Two EU locations available, one non-EU: payload after `orderable in EU: ` equals exactly `eu-b eu-c` (assert the exact payload, not `grep -q`) | rc 1 abort with that list | a filter that rejects everything fails here |

**Anchor.** The EU set is anchored by the parity suite comparing the lib default with `variables.tf`, an independent file; editing one without the other reddens it.

### Guard 4 — No /datacenters dependency, single fetch (P1)

**Property.** `stock_preflight` makes exactly one fetch, to `/server_types?name=<type>`, and its verdict is independent of anything /datacenters returns.

**Assembly.** Every `_stock_fetch` call site in the lib (`git grep -n '_stock_fetch' tests/scripts/lib/stock-preflight-gate.sh`: the definition and the one call) and the suite seam, which logs EVERY requested path to `$TMP/calls.log`. The chokepoint is `_stock_fetch`.

**Mutation matrix.**

| # | Edit | Must go RED at | Notes |
|---|------|----------------|-------|
| 4.1 | Re-add any `_stock_fetch "/datacenters"` call whose result is ignored | T1b: `calls.log` after a passing `stock_preflight beta22 eu-b` must equal exactly `/server_types?name=beta22` | file-based counter |
| 4.2 | Re-add the call and make it required (`|| return 1`) | T1 itself: the seam serves the 410 body at `/datacenters`, so beta22@eu-b stops returning 0 | the exact production failure |
| 4.3 | Add a second `/server_types` fetch | T1b (exact single line) | "drop the second API call" |
| 4.4 (harness) | Edit the SUITE seam so it stops logging | T1b must go RED via a self-check that calls the seam once directly and asserts the log line exists | proves the tripwire records |

**Anchor.** None.

### Guard 5 — Suite cardinality and non-vacuity floor (harness)

**Property.** A truncated, early-exiting or block-deleted suite cannot report green, and the fixtures keep present-but-unavailable entries so a presence-as-orderable regression stays detectable.

**Assembly.** The suite's single tally (`MIN_ASSERTIONS`, `-lt`), T14, and the named case blocks. The chokepoint is the final tally.

**Mutation matrix.**

| # | Edit | Must go RED at | Notes |
|---|------|----------------|-------|
| 5.1 | Insert `exit 0` after T1 in the mirrored suite | floor message, exit 1 | truncation |
| 5.2 | Delete each new case block in turn (T15, T16, T17, T18, T19, T20) | floor trips (floor = measured count) | every block removable independently; run all six |
| 5.3 | Edit alpha33 so its locations all read `available:true` | T14 fails | non-vacuity |

**Anchor.** The floor is a count; it is paired with named blocks (5.2 deletes each) so a substitution that preserves the count is caught by the per-block cases.

## Test Scenarios (suite rewrite, all fixtures synthesized)

Fixture types: `alpha33` (present in eu-a, eu-b, eu-c, far, all `available:false`), `beta22` (eu-a false, eu-b true with non-null `deprecation`, eu-c true, far true), `arm11` (all false), `sing44` (only `far` true), `partial55` (lists only eu-c). Malformed bodies are built with `jq -n`, never heredoc interpolation, and the malformed families run as ONE table-driven loop (each body expecting rc 1 and "cannot PROVE").

| Id | Scenario | Expected |
|----|----------|----------|
| T1 / T1b | beta22@eu-b; then `calls.log` content | rc 0; log is exactly `/server_types?name=beta22` (no `/datacenters`) |
| T2 | alpha33@eu-b (`available:false`) | rc 1, "NOT orderable in 'eu-b'", full remediation menu unchanged |
| T3 | arm11@eu-a | rc 1, `orderable in EU: <none>` |
| T4 | sing44@eu-a | rc 1, `far` absent, `<none>` |
| T5 | bogus99 (`{"server_types":[]}`) | rc 1, "unknown server_type" |
| T6 | beta22@atlantis; partial55@eu-b | rc 1, "unknown location", never the stock-miss text |
| T7 / T7c | `fail_all`; garbage `{"unexpected":"shape"}` | rc 1, "cannot PROVE", not "NOT orderable"; blip carries `curl exit` for the fetch failure |
| T7d | table: empty body, HTML, `[]`, `null`, `"x"`, `{}`, `{"server_types":null}`, `{"server_types":{}}`, a junk member (`["x"]` in `.server_types`) | rc 1 blip for every body |
| T7f | 200 body with a valid orderable beta22 AND an `error` key; and the bare synthesized 410 body at /server_types | rc 1 blip |
| T7i / T7j | `<valid orderable doc>garbage`; `<doc><doc>` | rc 1 blip |
| T8-T13b | gate-over-tfplan cases | unchanged |
| T14 | non-vacuity: alpha33 has present location entries and zero `available:true` | pass |
| T15 | locations absent/null/`{}`/`[]` | rc 1; `[]` says unknown location, others `MALFORMED:locations` |
| T16 | `available` `"true"`/`1`/`null`/absent -> blip with `MALFORMED:available`; real `false` -> stock miss | rc 1, messages distinct |
| T17 | a duplicate type; duplicate location entries (true,false) and (false,true); a junk member in `locations` | rc 1 |
| T18 | a `[other(true everywhere), wanted(false at eu-b)]` aborts; b `[other, wanted(true)]` passes; c `[other]` says filter-ignored | per case |
| T19 | alternatives strictness: eu-c `available:"true"` and `1` not suggested; exact payload asserted | per case |
| T20 | wire-level loopback (python3 stdlib `http.server`, 127.0.0.1, ephemeral port; per-case mode file; request log; `log_message` overridden), re-sourcing the lib in a subshell with `HCLOUD_API`/`HCLOUD_TOKEN` set BEFORE the source and `NO_PROXY=127.0.0.1`: (a) 200 orderable doc -> rc 0, exactly one request, `Authorization: Bearer <synthetic>`; (b) HTTP 410 + synthesized error body at /server_types -> rc 1, blip with `curl exit 22`; (c) HTTP 502 with a VALID `available:true` body -> rc 1 | per case |
| must-PASS | extra fields, reversed order, null sibling, non-null `deprecation` + `available:true` | rc 0 |

T20 specifics: bind port 0 and publish it via a readiness file with a BOUNDED wait loop and a named failure message; compose the new `trap` with the existing `rm -rf "$TMP"` EXIT trap (a replacement trap leaks `$TMP`); kill the server on every exit path; if python3 or loopback is unavailable the suite FAILS with a named message, never skips (a skip would silently drop the only status-aware test). Non-goal, stated: no wire-level timeout case (`--max-time 20`) and no 3xx case.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "migrate the gate to derive availability from the /server_types?name=<type> response (locations[] where name==want_loc, .available)" | Design: Verdict function; Phase 2; Files to Edit (lib) | mapped |
| 2 | "keep it FAIL-CLOSED (a missing locations array, missing location entry, non-boolean available, non-2xx or non-JSON body, or an error object must abort, never authorize)" | Guard 1, Guard 2; T7*, T15-T18, T20 | mapped |
| 3 | "keep the EU-only residency filter (STOCK_PREFLIGHT_EU_LOCATIONS) for the alternatives list" | Design: Alternatives list; Guard 3; T4, T19 | mapped |
| 4 | "drop the second API call" | Guard 4; Phase 2; T1b | mapped |
| 5 | "keep the distinct stock-miss versus API-blip messages and the repair-path text for the earlier stock-shortage issue" | Design: flow and blip message; T2, T7, T16; AC7 | mapped |
| 6 | "Update every fixture/stub and test that models the old /datacenters shape (grep tests and the workflows that source the lib: apply-web-platform-infra.yml web-host-replace, inngest-host-replace, registry-host-replace and others)" | Research Reconciliation rows 1-3; Phase 1; Files to Edit (suite) | mapped |
| 7 | "add fixtures for the new shape including the 410 body, an unavailable location, an unknown location, and a type with locations missing" | T2, T6, T7f (410), T15 | mapped |
| 8 | "Mutation-test each new guard." | Guard Contract (5 guards) and Phase 4 | mapped |
| 9 | "Do NOT edit .github/workflows unless a workflow itself parses /datacenters (grep first); if one does, say so." | Research Reconciliation row 1 | mapped |
| 10 | "Do not dispatch any workflow to validate; local targeted suites only." | Phase 3 | mapped |
| 11 | "PR body: Refs #9377 and Refs #8609, never Closes." | PR body reminder; AC8 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| lib rewrite (verdict, alternatives, header) | "migrate the gate to derive availability from the /server_types?name=<type> response" | asked |
| suite rewrite, fixtures, 410/unavailable/unknown/missing cases | "add fixtures for the new shape including the 410 body, an unavailable location, an unknown location, and a type with locations missing" | asked |
| Guard Contract and scratch mutation battery | "Mutation-test each new guard." | asked |
| select the type by `.name`; filter-ignored token | "an error object must abort, never authorize" | inferred — justification: the fail-closed contract; an ignored `?name=` would make `[0]` answer about a different type and authorize a destroy that cannot recreate |
| exactly-one type and exactly-one location entry | "missing location entry ... must abort, never authorize" | inferred — justification: two entries are ambiguity and the fail-closed contract has no safe resolution of two answers (one clause each; challenged by DHH/simplicity, kept for the single-user threshold) |
| `--fail-with-body` on the curl seam | "non-2xx or non-JSON body" | inferred — justification: `curl -sS` exits 0 on HTTP 4xx/5xx, so no body-shape guard can see a status |
| `|| verdict=""` capture and exact-token match | "never authorize" | inferred — justification: jq 1.8.2 prints `ORDERABLE` then exits 5 on trailing junk (reproduced); an unchecked capture would authorize |
| `MALFORMED:<reason>` and `curl exit N` in the blip message | "keep the distinct stock-miss versus API-blip messages" | inferred — justification: without the reason an operator re-dispatches forever on a permanent contract change, which is today's outage |
| T20 loopback wire-level test | "Mutation-test each new guard." | inferred — justification: the status guard (row 1.1) is unreachable through the redefined `_stock_fetch` seam, so its mutation cannot go RED without a real curl exchange |
| non-null `deprecation` in the canonical fixture | "keep it FAIL-CLOSED" | inferred — justification: records the deliberate decision not to deny on deprecation so a later change is a visible test edit |

### Split Assessment

- Subsystems touched: 1 (`tests/scripts`)
- Planned files: 2 edited (+ plan, tasks, decision-challenges) | Estimated changed lines: ~330 (lib ~90, suite ~240)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `git grep -n 'datacenters' -- tests/scripts/lib/stock-preflight-gate.sh` finds no request path and no `.datacenters` read; remaining mentions are prose only (dated 410 note, changelog URL, the ADR-154 probe pointer).
- [ ] AC2: `bash tests/scripts/test-stock-preflight-gate.sh` exits 0, and the Phase 1 run against the unchanged lib was recorded RED (case ids in the PR body).
- [ ] AC3: the suite proves exactly one request per `stock_preflight` (`/server_types?name=<type>`) through the seam log and through the loopback request log.
- [ ] AC4: every Guard Contract row was executed per Phase 4 (applied, parses, RED at the expected case id) and the table is in the PR body; no row stayed green unexplained.
- [ ] AC5: the Phase 3 command list passes, including the parity suite, `test-plan-gate-preamble.sh`, the two bun files, shellcheck and `lint-shell-capture-exit.py`; `python3 scripts/lint-guard-contract.py` passes on this plan.
- [ ] AC6: `git diff --name-only origin/main...HEAD` contains no `.github/workflows/**` and no `apps/web-platform/infra/**` path.
- [ ] AC7: the stock-miss abort text (PRIMARY / SECONDARY / web-1 clause / "Do NOT bypass" / `#6463`) is byte-identical to main apart from the `orderable in EU:` payload.
- [ ] AC8: PR body says `Refs #9377` and `Refs #8609` (no `Closes`/`Fixes`), states that no workflow parses /datacenters, flags the issue-title mismatch, states that the `available` semantics are doc-derived with AC9 as the first live verification, notes the advisory probe's `head -1` wording, and names the residual risk that the mutation battery is not committed.

### Post-merge (operator)

- [ ] AC9: re-run of the web-host-replace plan-only dispatch reaches `stock-preflight PASS` or a genuine stock-miss abort. This is the operator's existing R-step 5 dispatch (not triggered by this work and not part of its validation); the first real confirmation that `locations[].available` behaves as documented, and that the provider's create path does not itself need the removed endpoint.

## Domain Review

**Domains relevant:** Engineering (infrastructure gate). No Product/UX surface, no marketing, legal, finance or sales implication.

### Engineering

**Status:** reviewed (plan-time assessment plus a six-reviewer plan-review panel)
**Assessment:** the fail-closed contract is preserved and strengthened (name-keyed selection, exactly-one matching, boolean-only `available`, status-aware curl, exact-token authorization). Residual risk is Hetzner's own caveat that `locations.available` "is no guarantee"; the gate has always been a tripwire, not a reservation.

### Product/UX Gate

**Tier:** none (no new or changed user-facing UI; no `components/`, `app/` page or layout file in Files to Edit/Create).

### CPO sign-off (single-user incident threshold)

Required before `soleur:work`: confirm that authorizing only on a literal boolean `true` for exactly one matching location is the correct blast-radius posture. Review-time: `soleur:engineering:review:user-impact-reviewer`.

## Risks and Sharp Edges

- A guard that rejects everything looks safe; today's state IS that failure. The must-PASS rows (1.8, 2.9, 3.5, T20a) separate "fail-closed" from "always closed".
- Presence is not availability: rows 2.5 and T14.
- Never `//` on `.available`; never an unchecked `verdict=$(...)`; never `local v=$(...)`.
- Subshell counters: file-based only.
- The unknown-location arm cannot tell a typo from "type not offered there"; both fail closed and the message says so.
- `--fail-with-body` needs curl >= 7.76 (fail-closed and loud if absent). A 3xx with a valid body is not rejected by it (non-goal; redirects are not followed by default).
- `hcloud` provider create/refresh paths may still depend on removed API surface; unknowable offline (AC9).
- Do not hard-code today's stock anywhere in a test or comment; the measured "cpx22 available in fsn1/nbg1/hel1/sin" lives only in the PR body.
- Stale prose left on purpose: ADR-143/154 and `variables.tf`/`zot-registry.tf` cite `/v1/datacenters` as dated measurements; the lib header gets one dated pointer to the equivalent `GET /v1/server_types?name=cx33` probe for ADR-154's re-evaluation trigger.
- Local verification used jq 1.8.2. GitHub-hosted runners ship jq 1.7.x: before shipping, re-run the verdict/alternatives programs over the T7/T15-T18 body table under jq 1.7 if obtainable (the programs use only `has`, `any`-free constructs, `IN`, `.[]?`, `paste`; jq's print-then-exit-5 on trailing bytes is version-dependent, which is why the capture checks the exit status instead of relying on it).
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one is filled; keep it filled.

## PR body reminder

Title: `fix(infra): derive the stock-preflight verdict from /server_types locations[] (Hetzner removed /datacenters)`. Body: what and why, the measured facts, the mutation table, that no workflow parses /datacenters and none was edited, the issue-title mismatch note, `Refs #9377` and `Refs #8609` (never `Closes`), then the session attribution line.
