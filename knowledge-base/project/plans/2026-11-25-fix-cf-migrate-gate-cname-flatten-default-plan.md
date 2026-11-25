---
title: "fix: cf-account-migrate gate treats a CNAME's live settings {\"flatten_cname\":false} as the API default"
date: 2026-11-25
slug: fix-cf-migrate-gate-cname-flatten-default
branch: feat-one-shot-13056-cname-flatten-settings
issue: 13056
closes: 13056
type: bug
lane: single-domain
domain: engineering
brand_survival_threshold: aggregate pattern
---

# fix: cf-account-migrate gate treats a CNAME's live settings {"flatten_cname":false} as the API default

## Enhancement Summary

**Deepened on:** 2026-11-25
**Sections enhanced:** 5 (Phase 1 block, Guard Contract, Acceptance Criteria, Scope Check, Observability)
**Agents used:** learnings-researcher (plan), dhh-rails-reviewer, kieran-rails-reviewer and code-simplicity-reviewer (plan-review), test-design-reviewer and security-sentinel (deepen). The deepen fan-out was kept to the two lenses that bear on a narrowed fail-closed comparator. It did not run every agent, because the design is CTO-ruled and the change is 4 files.

### Key Improvements

1. `M-flatten-after` is written inline so that it requires the mutant to still run and refuse on `type`. `gm_lost` would also pass a mutant whose jq fails to evaluate.
2. `n_flat` count guards on L11a, L11b, D5 and D6, so no row can pass on an unchanged read. The `M-flatten-guard` fixture is checked against the pristine gate.
3. AC2b makes the value conjunct's witnesses (L11c–L11f) reproducible. Prototype: `351 passed, 5 failed`.
4. The Scope Check was rewritten to the canonical Ask Mapping / Provenance / Split schema (deepen §4.12).
5. The Residual now states that both type conjuncts are diagnostic-only and that the `type` compare (`G1-7 type`) holds the verdict.

### New Considerations Discovered

- Security review found no bypass. jq `==` is strict and key-order-blind, and a `type` of `"cname"`/`"CNAME "` fails. Duplicate keys collapse once in `cf_account_migrate_live_collect`, so both conjuncts read the same `$r`. An absent `$after.type` is `null` and is refused. No new value-printing path exists.
- Precedent (§4.4): the new `elif` follows the shape of the existing `comment` clause, which also admits an empty-equivalent live value (`cfam_empty` on both sides) before naming the field. It uses `==` only, per the header rule against jq `//`.
- After the deepen edits, the prototype still gives GREEN `356 passed, 0 failed`, RED `350 passed, 6 failed`, and no new shellcheck findings.

The `redirects-dns` rehearsal (run 45623876678, main @ `1da76b3dcc`, 2026-11-25) was refused before
anything was written (`serial_unchanged=true backups_unchanged=true`). Six records printed
`REFUSE … differs from the live record (settings,settings:only-flatten-false)`: `pages_apex`, `www`,
`supabase_custom_domain`, `protonmail_dkim_1`, `protonmail_dkim_2` and `protonmail_dkim_3`. These six
are the only CNAMEs in the phase. Epic: #12931.

The CTO ruling on the issue fixes the cause and the scope. The fix goes in the live-record comparator
`cfam_live_diff` (inside `_CFAM_NORMALIZE_JQ` in `tests/scripts/lib/cf-account-migrate-gate.sh`), not in
`dns.tf`. A live `settings` of exactly `{"flatten_cname":false}` compares equal only when both the live
and the planned record are type `CNAME`. Every other `settings` value is still refused, and
`cfam_norm_shape` stays byte-identical. Both the gate and the job's post-apply re-read
(`cf_account_migrate_live_diff`) evaluate this one jq function, so one clause fixes both.

Ruled by CTO agent, 2026-11-25 (recorded on #13056 and copied here, not re-ruled): the comparator
changes and `dns.tf` does not. Rationale: provider cloudflare 4.52.7 (the lock file) has no `settings`
attribute, so `dns.tf` cannot declare one. cloudflare-go v0.116.0 `UpdateDNSRecordParams.Settings` is a
struct tagged `omitempty`, so the PATCH carries `"settings":{}`. Cloudflare's OpenAPI gives
`flatten_cname` a default of `false`. Either outcome of the PATCH leaves the value at `false`. This
supersedes ruling F3 of the 2026-11-23 import-normalize spec, which refused the case because nobody had
observed the effect.

**Hard boundaries for this branch (from the invocation):**

- Do not dispatch any `cf-account-migrate.yml` run, rehearsal or real. The parent session runs the
  re-rehearsal after merge.
- Never print a token value. No SSH. No Cloudflare writes. The old zone stays read-only.
- No change to `apps/web-platform/infra/dns.tf`, `apps/web-platform/infra/scripts/cf-account-migrate-job.sh`
  or `cfam_norm_shape`.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality on `main` @ `1da76b3dcc` | Plan response |
|---|---|---|
| "D4 and D5: the re-read with `{flatten_cname:false}` and with `{}`" | The suite already has `D1`–`D4` (`D4: live_diff refuses a missing live file`), plus an unrelated `D3` (cache_shared_binaries). | The two new re-read rows are labelled **D5** and **D6**, the next free labels. Same content, different labels. Recorded as a `taste` row in `decision-challenges.md`. |
| "L11: relabel only" | `L11` asserts `settings,settings:only-flatten-false` on `cloudflare_record.dkim_resend`, which is a TXT record (`dns.tf`). | After the fix, the row still holds byte-for-byte on a TXT record. Only its label changes, so it now says it covers a non-CNAME record. |
| "the six are the phase's only CNAMEs" | `dns.tf` has nine CNAMEs. Three of them (`deploy`, `ssh`, `registry`) belong to no `redirects-dns` spec (they are tunnel records). The `$NORM` fixture holds exactly the six. | The fixture assertion pins the six addresses as a sorted literal set, computed from `$NORM`. It does not count CNAMEs in `dns.tf`. |
| "The gate and the job's post-apply re-read both use it" | `cf-account-migrate-job.sh` calls `cf_account_migrate_live_diff` (around `reread_records`), which evaluates `cfam_live_diff`. | Confirmed. The job script needs no change. D5 and D6 exercise the re-read entry point. |
| Runbook "Step 2 token-table row" | The runbook's `### Step 2: redirects-dns rehearsal and apply` table has the row `` `settings:only-flatten-false` ``, which reads as "the PATCH's empty `settings` could reset" it. | Rewrite that row's Meaning cell. Add one prose sentence after "Every other diff is still refused." |
| "the ADR-329 `settings` sentence" | ADR-329's fourth-exception bullet ends "A `settings`, `data`, `after`, `tags:absent` or `content:quoted-equal` difference gets no edit and stops for an owner decision." | Amend that sentence so it carves out the CNAME default and cites the 2026-11-25 ruling. |

## Research Insights

**Premise Validation.** #13056 is OPEN and no merged PR closes it. Epic #12931 is OPEN. Draft PR #13057
is this branch's own PR. `collision-precheck.sh 13056` reported PR #13057 (ours) and four foreign
`test-all.sh` processes owned by worktree `chore-12846-h-capture-evidence`. Those processes are
unrelated to this issue, and we are not running `test-all.sh`. Every cited symbol exists on `main`:
`cfam_live_diff`, `cfam_norm_shape`, `_CFAM_NORMALIZE_JQ`, `cf_account_migrate_live_diff`, test rows
`L11`/`L12`/`L13`/`D1`–`D4`/`G1-7`/`G1-8b`, the runbook token table, and the ADR-329 sentence. The
premise holds.

**Property List (Phase 0.6b).**

1. P1: a CNAME whose live `settings` is exactly `{"flatten_cname":false}`, planned as a CNAME, is not a
   difference. The gate admits its import-normalize update, and the post-apply re-read reports it clean.
2. P2: every other non-empty `settings` value stays a refused difference: `true`, an extra key, the
   string `"false"`, `null`, `false` as a whole value, and any value on a non-CNAME record or when the
   live and planned types differ. Each case keeps its existing closed diagnostic token.
3. P3: no planned-shape admission changes. `cfam_norm_shape` stays byte-identical.
4. P4: the suite proves P1 and P2 through RED-on-mutation rows. The anti-vacuity floor moves to the new
   assertion count.

**Cut List.** The issue asks for none of these mechanisms, and nothing else on `main` already covers
the properties above:

- Declaring `settings` in `dns.tf`: cut. Provider 4.52.7 has no such attribute (CTO ruling).
- Changing the job's re-read: cut. It already evaluates `cfam_live_diff` through
  `cf_account_migrate_live_diff`.
- A new diagnostic token: cut. The existing `settings:only-flatten-false` and `settings:other` tokens
  keep their exact match predicates. Only the cases that reach them shrink.

**Prototype (verified on a scratch copy of `tests/`, `apps/web-platform/infra/` and
`.github/workflows/`, never in the worktree):**

- With the clause below and the test block in this plan, the suite prints `356 passed, 0 failed` in about
  51 s. Baseline on `main` is `344 passed, 0 failed`, with the floor at exactly 344.
- With the new test block against the **unfixed** lib, it prints `350 passed, 6 failed`. The six
  failures are `L11a`, `L11b`, `D5` and `D6` (both with non-empty `live_diff` output), and
  `M-flatten-guard` and `M-flatten-after` ("mutation did not land"). That is the TDD RED. These
  numbers come from the post-plan-review block (`norm_admits`/`lrow` reused, D6 mixed). The first
  draft's block gave 5 failures, and D6 repeated D1.
- A value-conjunct mutation (dropping `$r.settings == {"flatten_cname":false} and`) turns `L11c` through
  `L11f` RED. That shows they are the witnesses for the value clause.
- The existing rows `G1-7 settings` (`s/else "settings" end/else empty end/`) and `G1-8b`
  (`s/if \$r\.settings == null or \$r\.settings == {} then/…/`) still land and still go RED, because the
  rewrite keeps both anchor substrings intact.
- `shellcheck -x` on the new block adds no findings. The total stays at 5 info-level findings, the same
  as before.

**Relevant files.**

- `tests/scripts/lib/cf-account-migrate-gate.sh`: the header paragraph `IMPORT-NORMALIZE (CTO ruling
  2026-11-22, ADR-329)` and the `cfam_live_diff` `settings` clause inside `_CFAM_NORMALIZE_JQ`. The
  diagnostic block after it (`settings:only-flatten-false` / `settings:other`) stays unchanged.
- `tests/scripts/test-cf-account-migrate-gate.sh`: `lrow` (L-rows on `$NR` =
  `cloudflare_record.dkim_resend`, TXT), `live_of` (writes `settings:{}` for every record), `nf`,
  `check`, `gm` (= `gate_mutate_and_check`, which passes when the mutant returns rc 0), `gm_lost`
  (defined after the G1 block), and the anti-vacuity floor `344` at the end of the file.
- `tests/scripts/lib/gate-suite-harness.sh`: `gate_check` (substring needle plus rc) and
  `gate_mutate_and_check` (fails when the mutation lands nothing). Not edited.
- `knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md`: `### Step 2`, the
  token table.
- `knowledge-base/engineering/architecture/decisions/ADR-329-cloudflare-zone-resources-live-on-the-soleur-account-r2-stays.md`:
  the fourth-exception bullet.

**Institutional learnings applied.**

- `2026-02-14-sed-insertion-fails-silently-on-missing-pattern.md`: every new mutation goes through a
  helper that fails when the mutation lands nothing (`gm`, `gm_lost`).
- `workflow-patterns/2026-07-17-source-scan-guard-battery-must-vary-shape-not-just-value.md`: the
  refusal battery varies shape (an extra key, string versus boolean, null, a type mismatch), not only
  the value.
- `2026-09-28-every-guard-was-narrower-than-its-name-and-my-battery-mutated-only-whole-chokepoints.md`:
  each conjunct of the new admit condition has a named RED witness (see the Guard Contract). The one
  conjunct without one is disclosed as a residual.
- `2026-08-13-my-guard-was-green-with-its-property-inverted-…md`: mutation anchors break when the
  anchored code changes, so the existing `G1-7`/`G1-8b` anchors are kept byte-intact (verified above).
- `2026-09-07-my-instruments-reported-green-while-measuring-nothing.md`: the floor is re-derived from
  the post-change run (356), not estimated.
- jq `//` maps `false` to the fallback. The new clause uses `==` only, which matches the existing header
  rule "No jq `//` in a compare".

**Related PRs and overlap.** Draft PR #12958 (`feat-one-shot-12937-zot-bridge-handshake`, tunnel and
Access re-home) also edits `tests/scripts/lib/cf-account-migrate-gate.sh`,
`tests/scripts/test-cf-account-migrate-gate.sh`, the runbook and ADR-329. Its gate-lib hunks touch the
header, the phase list (it adds a `tunnel` phase whose `deploy`/`ssh`/`registry` CNAMEs are
**create**-class, so they never reach the live comparator) and the spec. None of its hunks contains
`settings`, `flatten` or `cfam_live_diff`. Whichever of the two lands second gets textual rebase
conflicts in the header comment and the test file's tail (the anti-vacuity floor line). It gets no
semantic conflict. This plan does not touch #12958. The sibling session on #13051 edits
`apps/web-platform/infra/cf-account-migrate-job.test.sh`, `run-registered-suites.sh` and
`infra-validation.yml`. This plan edits none of them.

**CLAUDE.md conventions.** Read before editing. Cite content anchors, not line numbers
(`cq-cite-content-anchor-not-line-number`). Synthesized fixtures only (`cq-test-fixtures-synthesized-only`):
every record value in the new rows is synthetic (`synthetic-<label>`) or a dns.tf shape.

## Implementation Phases

### Phase 1: RED (test rows first, `cq-write-failing-tests-before`)

Edit `tests/scripts/test-cf-account-migrate-gate.sh`:

1. **`norm_admits` takes an optional live file** (plan-review: reuse it instead of adding a near-copy).
   Change its header and first two body lines to:

   ```bash
   norm_admits() { # <gate-file> [<live>]: empty when the canonical plan passes with 26 import-normalize lines and no in-state-update
     local o rc live="${2:-$NLIVE}"
     o="$(bash -c 'source "$1"; source "$2"; cf_account_migrate_gate redirects-dns "$3" "" "$4"' _ "$PREAMBLE" "$1" "$NORM" "$live" 2>&1)"; rc=$?
   ```

   Existing callers (`N1`, `G1-12`) pass one argument and keep today's behaviour.
2. **`lrow` takes an optional address** (plan-review: reuse it instead of adding a second refusal helper):

   ```bash
   lrow() { # <label> <tokens> <live-filter on the record's entry> [<address>, default the first record]
     local r="${4:-$NR}"
     jq -c --arg r "$r" "(.[\$r]) |= ($3)" "$NLIVE" > "$TMP/lr.json"
     check "$1" 1 "REFUSE $r differs from the live record ($2)" redirects-dns "$NORM" "" "$TMP/lr.json"
   }
   ```

3. **Relabel `L11` only.** `"L11: live settings flatten_cname=false differ"` becomes
   `"L11: a non-CNAME record's live settings flatten_cname=false differ"`. Its tokens and filter stay
   unchanged.
4. **Insert the block below immediately before the `# Anti-vacuity floor, reported outside
   pass()/fail() (ADR-193).` comment.** It must come after `gm_lost`'s definition, which is why it is
   not placed beside the L-rows.
5. **Raise the floor.** `-lt 344` / `(floor 344)` become `-lt 356` / `(floor 356)`.
6. **Run the suite against the unfixed lib.** Expect exactly 6 failures: `L11a`, `L11b`, `D5`, `D6`,
   `M-flatten-guard` and `M-flatten-after`.

```bash
# ── CNAME flatten_cname default (CTO ruling 2026-11-25, #13056) ─────────────────────────────
# The fixture's CNAMEs are exactly the six the redirects-dns rehearsal refused.
CNAMES="cloudflare_record.pages_apex cloudflare_record.protonmail_dkim_1 cloudflare_record.protonmail_dkim_2 cloudflare_record.protonmail_dkim_3 cloudflare_record.supabase_custom_domain cloudflare_record.www"
CN="cloudflare_record.www"
got_cn="$(jq -r '[.resource_changes[] | select(.type == "cloudflare_record" and .change.after.type == "CNAME") | .address] | sort | join(" ")' "$NORM")"
if [[ "$got_cn" == "$CNAMES" ]]; then pass "F5-cname: the fixture's CNAME set is exactly the six rehearsal-refused records"
else fail "F5-cname: the fixture's CNAME set drifted" 1 "$got_cn"; fi
# flat_live <out> <address...>: $NLIVE with each named record's live settings at {flatten_cname:false}.
flat_live() {
  local out="$1"; shift
  jq -c --arg c "$*" '($c | split(" ")) as $cs | with_entries(if (.key | IN($cs[])) then .value.result.settings = {flatten_cname:false} else . end)' "$NLIVE" > "$out"
}
FLAT_ALL="$TMP/flat-all.json"; FLAT_MIX="$TMP/flat-mix.json"
# shellcheck disable=SC2086 # CNAMES is a word list
flat_live "$FLAT_ALL" $CNAMES
flat_live "$TMP/flat-one.json" "$CN"
# Either outcome of the PATCH: three still at the default, three reset to {} (live_of's value).
flat_live "$FLAT_MIX" cloudflare_record.pages_apex cloudflare_record.protonmail_dkim_1 cloudflare_record.protonmail_dkim_2
n_flat() { jq '[.[] | select(.result.settings == {flatten_cname:false})] | length' "$1"; }   # <live>: records at the default
na="$(norm_admits "$GATE" "$TMP/flat-one.json")"
if [[ -z "$na" && "$(n_flat "$TMP/flat-one.json")" -eq 1 ]]; then pass "L11a: one CNAME's live settings {flatten_cname:false} compares equal (26 import-normalize, PASS)"
else fail "L11a: a CNAME's flatten_cname=false default was refused" 1 "$na"; fi
na="$(norm_admits "$GATE" "$FLAT_ALL")"
if [[ -z "$na" && "$(n_flat "$FLAT_ALL")" -eq 6 ]]; then pass "L11b: all six CNAMEs at {flatten_cname:false} pass (the rehearsal's read)"
else fail "L11b: the rehearsal's six-CNAME read was refused" 1 "$na"; fi
lrow "L11c: a CNAME's flatten_cname=true differs" "settings,settings:other" '.result.settings = {flatten_cname:true}' "$CN"
lrow "L11d: a CNAME's flatten_cname=false with an extra key differs" "settings,settings:other" '.result.settings = {flatten_cname:false, ipv4_only:true}' "$CN"
lrow "L11e: a CNAME's flatten_cname string \"false\" differs" "settings,settings:other" '.result.settings = {flatten_cname:"false"}' "$CN"
lrow "L11f: a CNAME's flatten_cname null differs" "settings,settings:other" '.result.settings = {flatten_cname:null}' "$CN"
lrow "L11g: a live CNAME with flatten_cname=false against a planned TXT differs on type and settings" "type,settings,settings:only-flatten-false" '.result.type = "CNAME" | .result.settings = {flatten_cname:false}'
L11G="REFUSE $NR differs from the live record (type,settings,settings:only-flatten-false)"
cp "$TMP/lr.json" "$TMP/l11g.json"   # lrow's last read: L11g's
d5="$(cf_account_migrate_live_diff redirects-dns "$NORM" "$FLAT_ALL")"; d5_rc=$?
if [[ "$d5_rc" -eq 0 && -z "$d5" && "$(n_flat "$FLAT_ALL")" -eq 6 ]]; then pass "D5: the re-read with the six CNAMEs at {flatten_cname:false} is clean"
else fail "D5: the re-read refused the flatten_cname=false default" "$d5_rc" "$d5"; fi
d6="$(cf_account_migrate_live_diff redirects-dns "$NORM" "$FLAT_MIX")"; d6_rc=$?
if [[ "$d6_rc" -eq 0 && -z "$d6" && "$(n_flat "$FLAT_MIX")" -eq 3 ]] && ! cmp -s "$FLAT_MIX" "$NLIVE" && ! cmp -s "$FLAT_MIX" "$FLAT_ALL"; then
  pass "D6: a re-read with three CNAMEs at {flatten_cname:false} and three at {} (the PATCH reset) is clean"
else fail "D6: the mixed re-read was refused, or the fixture is not mixed" "$d6_rc" "$d6"; fi
jq -c --arg r "$NR" '.[$r].result.settings = {flatten_cname:false}' "$NLIVE" > "$TMP/m-flat-txt.json"
# The pristine gate must refuse this fixture (L11's case), or the mutant passing it proves nothing.
cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/m-flat-txt.json" >/dev/null 2>&1 && fail "M-flatten-guard: the pristine gate admits its own fixture" 0 ""
# shellcheck disable=SC2016 # sed expression matches literal jq text
gm "M-flatten-guard: dropping the CNAME type guard admits a TXT record's flatten_cname=false (L11)" \
  's/ and \$r\.type == "CNAME" and \$after\.type == "CNAME" then empty$/ then empty/' cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/m-flat-txt.json"
# The mutant must still run and refuse on `type` alone: a mutant whose jq fails would also lose the needle.
# shellcheck disable=SC2016 # sed expression matches literal jq text
sed 's/ and \$after\.type == "CNAME" then empty$/ then empty/' "$GATE" > "$TMP/m-flat-after.sh"
mfa="$(gate_in "$TMP/m-flat-after.sh" redirects-dns "$NORM" "" "$TMP/l11g.json")"
if cmp -s "$TMP/m-flat-after.sh" "$GATE"; then fail "M-flatten-after: the mutation did not land" 1 ""
elif grep -qxF "REFUSE $NR differs from the live record (type)" <<<"$mfa" && ! grep -qF "$L11G" <<<"$mfa"; then
  pass "M-flatten-after: dropping the planned-type clause leaves L11g refused on type alone (RED)"
else fail "M-flatten-after: the mutant did not refuse L11g on type alone" 1 "$mfa"; fi
```

This adds 12 assertions: `F5-cname`, `L11a`, `L11b`, `L11c`–`L11f` (4), `L11g`, `D5`, `D6`,
`M-flatten-guard` and `M-flatten-after`. 344 + 12 = 356. D6 uses a **mixed** read: three CNAMEs at
`{flatten_cname:false}` and three at `{}`. That covers both outcomes of the PATCH. A read of all six
at `{}` would be byte-identical to `$NLIVE`, because `live_of` writes `settings:{}`, and would only
repeat D1. `n_flat` makes each of L11a, L11b, D5 and D6 prove that its fixture really holds 1, 6, 6
or 3 records at the default, so none can pass on an unchanged read. Deepen-pass tightening: the
`M-flatten-guard` fixture is checked against the pristine gate, which must refuse it. `M-flatten-after`
is written inline rather than through `gm_lost`, because `gm_lost` would also pass on a mutant whose jq
fails to evaluate. The inline row requires the mutant to still print
`REFUSE <NR> differs from the live record (type)` as a whole line.

### Phase 2: GREEN (the comparator clause and one header sentence)

Edit `tests/scripts/lib/cf-account-migrate-gate.sh`.

**2a.** In `cfam_live_diff`, replace the one-line `settings` clause:

```jq
        (if $r.settings == null or $r.settings == {} then empty else "settings" end),
```

with:

```jq
        (if $r.settings == null or $r.settings == {} then empty
         elif $r.settings == {"flatten_cname":false} and $r.type == "CNAME" and $after.type == "CNAME" then empty
         else "settings" end),
```

Keep these substrings byte-intact, because existing mutation rows anchor on them:

- `if $r.settings == null or $r.settings == {} then` (`G1-8b`)
- `else "settings" end` (`G1-7`)
- ` and $r.type == "CNAME" and $after.type == "CNAME" then empty` at end of line (`M-flatten-guard`)
- ` and $after.type == "CNAME" then empty` at end of line (`M-flatten-after`)

The diagnostic block (`elif $r.settings == {"flatten_cname":false} then "settings:only-flatten-false"
else "settings:other" end`) stays unchanged. It now fires only when the type guard fails, which is
what the relabelled `L11` and `L11g` pin. `cfam_norm_shape` stays unchanged; AC4 checks this with a
byte-identity diff.

**2b.** Append one sentence to the header paragraph that begins `# IMPORT-NORMALIZE (CTO ruling
2026-11-22, ADR-329).`, directly after its line ending `` never `in-state-update`. ``:

```bash
# A live CNAME's `settings` of exactly {"flatten_cname":false} compares equal to a planned CNAME
# (CTO ruling 2026-11-25, #13056): provider 4.52.7 has no `settings` attribute, cloudflare-go v0.116.0
# sends `"settings":{}` under `omitempty` and Cloudflare's OpenAPI defaults `flatten_cname` to false,
# so either outcome of the PATCH leaves it false; every other `settings` value is still refused.
```

**2c.** Run `bash tests/scripts/test-cf-account-migrate-gate.sh`. It must print `356 passed, 0 failed`
and exit 0.

### Phase 3: Docs (runbook and ADR-329)

**3a.** In the runbook's `### Step 2: redirects-dns rehearsal and apply`:

- **Prose.** After the sentence `Every other diff is still refused.`, insert the text below. In the
  file that sentence wraps across two lines ("Every other" / "diff is still refused."), so locate it by
  the paragraph that ends "(ADR-329, CTO ruling 2026-11-22)", not by a single-line grep. Insert: ``A CNAME whose live
  `settings` is exactly `{"flatten_cname":false}` is not a difference: that is the API default, and the
  PATCH leaves it `false` (CTO ruling 2026-11-25, #13056).``
- **Token table.** Replace the Meaning cell of the `` `settings:only-flatten-false` `` row with: ``The
  live `settings` is exactly `{"flatten_cname":false}` on a record that is not a CNAME in both the live
  read and the plan (on a CNAME it is the API default and compares equal, CTO ruling 2026-11-25)``. The Action cell stays
  `Stop token. No edit; stop for an owner decision`. The `settings:other` row stays unchanged.

**3b.** In ADR-329's fourth-exception bullet, change `A \`settings\`, \`data\`, \`after\`,
\`tags:absent\` or \`content:quoted-equal\` difference gets no edit and stops for an owner decision.` to
``A `settings` (other than a CNAME's `{"flatten_cname":false}`, the API default, which is not a
difference: CTO ruling 2026-11-25, #13056), `data`, `after`, `tags:absent` or `content:quoted-equal`
difference gets no edit and stops for an owner decision.``. In the file, the original sentence wraps
after `` `tags:absent` `` onto a two-space-indented line. Keep the bullet's wrap and indentation.

**3c.** Run `bash tests/scripts/test-cf-account-migration-runbook.sh` and
`bash tests/scripts/test-cf-account-migration-scope.sh`. Both read the runbook and must stay green.
Neither pins the edited row today. This run confirms that no pinned phrase moved.

### Phase 4: Verification hand-off (no dispatch)

The branch's work ends at a green suite. The issue's **Done when** is a `redirects-dns`
re-rehearsal on `main`. The parent session runs it after merge, and this branch does not dispatch it.
The expected log lines are recorded under Acceptance Criteria (Post-merge) so the parent can check
them.

## Files to Edit

- `tests/scripts/lib/cf-account-migrate-gate.sh`: the `cfam_live_diff` `settings` clause and one header
  sentence.
- `tests/scripts/test-cf-account-migrate-gate.sh`: an optional live-file argument for `norm_admits`, an
  optional address argument for `lrow`, the `L11` relabel, the new block, and the floor 344 → 356.
- `knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md`: one Step 2 prose
  sentence and the `settings:only-flatten-false` token-table row.
- `knowledge-base/engineering/architecture/decisions/ADR-329-cloudflare-zone-resources-live-on-the-soleur-account-r2-stays.md`:
  the `settings` sentence.

## Files to Create

None. Planning artifacts (`knowledge-base/project/specs/feat-one-shot-13056-cname-flatten-settings/`)
are excluded.

**Explicitly not edited:** `apps/web-platform/infra/dns.tf`,
`apps/web-platform/infra/scripts/cf-account-migrate-job.sh`, `cfam_norm_shape`,
`apps/web-platform/infra/cf-account-migrate-job.test.sh`,
`apps/web-platform/infra/run-registered-suites.sh`, `.github/workflows/infra-validation.yml` (the #13051
sibling's files), and anything on PR #12958's branch.

## Open Code-Review Overlap

None. No open `code-review` issue (96 checked) names any of the four files or ADR-329.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "[issue #13056] `tests/scripts/lib/cf-account-migrate-gate.sh`: the `settings` clause of `cfam_live_diff`, plus one header sentence citing the evidence." | Phase 2a, Phase 2b; Files to Edit entry 1 | mapped |
| 2 | "[issue #13056] L11: relabel only." | Phase 1 item 3 | mapped |
| 3 | "[issue #13056] L11a and L11b: CNAME `{flatten_cname:false}` passes, one record and all six." | Phase 1 block (`norm_admits` with a live file) | mapped |
| 4 | "[issue #13056] L11c to L11f: `true`, an extra key, the string `\"false\"` and `null` are refused as `settings:other`." | Phase 1 block (`lrow` with the CNAME address) | mapped |
| 5 | "[issue #13056] L11g: live CNAME against a planned TXT is refused." | Phase 1 block | mapped |
| 6 | "[issue #13056] D4 and D5: the re-read with `{flatten_cname:false}` and with `{}`." | Phase 1 block as D5/D6 (D4 is taken). D6 is a mixed read | mapped |
| 7 | "[issue #13056] Mutations M-flatten-guard and M-flatten-after." | Phase 1 block | mapped |
| 8 | "[issue #13056] A fixture assertion that the CNAME set in `$NORM` is exactly these six." | Phase 1 block (`F5-cname`) | mapped |
| 9 | "[issue #13056] The runbook's Step 2 token-table row and one sentence of prose, and the ADR-329 `settings` sentence." | Phase 3a, Phase 3b; Files to Edit entries 3-4 | mapped |
| 10 | "[brief] No change to dns.tf, cf-account-migrate-job.sh or cfam_norm_shape." | Explicitly-not-edited list; AC4 | mapped |
| 11 | "[brief] Do NOT dispatch any cf-account-migrate.yml workflow run (rehearsal or real)" | Phase 4; AC8; AC9 assigned to the parent session | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `tests/scripts/lib/cf-account-migrate-gate.sh` (Phase 2a/2b) | ask 1 | asked |
| `tests/scripts/test-cf-account-migrate-gate.sh` rows (Phase 1 block, L11 relabel) | asks 2-8 | asked |
| `norm_admits` optional live argument, `lrow` optional address argument | — | inferred — justification: plan review found that the separate `flat_admits`/`crow_s` helpers duplicated these two, and two helpers with one contract drift. The extension is what lets asks 3-4 reuse the suite's verified assertions |
| Anti-vacuity floor 344 → 356 | — | inferred — justification: the suite's ADR-193 floor sits at exactly 344 today. Leaving it there lets the 12 new assertions vanish silently, which is the enforcement contract the floor exists for |
| Runbook + ADR-329 edits (Phase 3) | ask 9 | asked |
| Phase 4 hand-off / AC8 | ask 11 | asked |

### Split Assessment

- Subsystems touched: 2 — `tests`, `knowledge-base`
- Planned files: 4 | Estimated changed lines: about 75
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Guard Contract

### Guard 1 — CNAME flatten_cname default in the live comparator

**Property.** A live record's non-empty `settings` is a refused difference unless it is exactly
`{"flatten_cname":false}` and both the live record and the planned record are type `CNAME`.

**Assembly.** The one chokepoint is the jq function `cfam_live_diff` inside `_CFAM_NORMALIZE_JQ`
(`tests/scripts/lib/cf-account-migrate-gate.sh`). Two callers reach it, both through that string:

- `cf_account_migrate_gate`'s live compare (`live: (if $hl then cfam_live_diff(...)`), which runs for
  every import-class record including no-ops.
- `cf_account_migrate_live_diff` (`cfam_live_diff($afters[$a]; $lv[0][$a]; $pins[$a]; $z)`), which is
  the job's post-apply re-read.

No other code path compares `settings`. The job script (`reread_records`) only consumes
`cf_account_migrate_live_diff` output.

**Mutation matrix.**

| # | Edit (design-derived) | Must go RED | Witness |
|---|---|---|---|
| 1 | Drop the whole type guard (`and $r.type == "CNAME" and $after.type == "CNAME"`) | A TXT record's `{flatten_cname:false}` is admitted | `M-flatten-guard` (`gm`, mutant rc 0 on L11's fixture) |
| 2 | Drop only the planned-type conjunct (`and $after.type == "CNAME"`) | L11g's REFUSE line becomes exactly `(type)` | `M-flatten-after` (inline; requires the mutant to still run and refuse on `type`) |
| 3 | Drop the value conjunct (admit any `settings` on a CNAME pair) | L11c–L11f PASS | L11c–L11f themselves. Reproduced by AC2b: the sandbox run ends `351 passed, 5 failed`, failing L11c, L11d, L11e, L11f and M-flatten-guard ("did not land", because its anchor sits on the mutated line) |
| 4 | Revert the `elif` (today's code) | L11a, L11b, D5, D6 refuse | L11a, L11b, D5, D6 (the Phase 1 RED) |
| 5 (dispatch) | Either caller stops reaching the carve-out (the gate's live compare or the re-read's `cf_account_migrate_live_diff`) | The other caller's rows stay green while this one's go red | L11a/L11b reach it through `cf_account_migrate_gate`; D5/D6 reach it through `cf_account_migrate_live_diff`. Existing `G1-9` covers the gate's live-read dispatch |
| 6 (second member) | Admit only the first CNAME (a per-record short-circuit) | L11b (all six) refuses or prints fewer than 26 import-normalize lines | `L11b` via `norm_admits "$GATE" "$FLAT_ALL"` (counts 26 lines, exact verdict, no in-state-update) |
| 7 (precondition holds, property fails) | Live is CNAME with `{flatten_cname:false}`, plan is TXT | Must still refuse | `L11g` |

**Harness rows.**

- RED on a suite edit: the `F5-cname` literal set. If the fixture loses or gains a CNAME (for example a
  `dns.tf` type edit), `F5-cname` fails before any L11a/L11b verdict can be read as meaningful.
- Must-PASS non-canonical inputs: `L11a` (one CNAME changed) and `D6`/`FLAT_MIX` (three CNAMEs at
  `{flatten_cname:false}`, three at `{}`). `n_flat` guards each fixture's count. `cfam_live_diff`
  compares record by record, so D6 adds no independent evidence beyond D5 and D1. It stays because the
  issue asks for the `{}` re-read, and it documents that the PATCH's two outcomes can coexist. `G1-8b`
  stays as the `//`-on-false harness row.
- The anti-vacuity floor (356) catches a block that silently stops running.

**Anchor.** The admitted value is a literal in the reviewed jq source, not a stored hash. The witness
literals (`CNAMES`, `L11G`, the floor) live in the suite, and the RED/GREEN evidence is recorded in this
plan from a run on the unfixed lib. Weakening the clause needs a diff to both files, which a reviewer
sees.

**Residual.** The separate `type` compare already refuses every pair whose live and planned types
differ, so dropping either type conjunct ALONE never changes the verdict. Only the diagnostic tokens
change. `M-flatten-guard` is the verdict witness for the type guard as a whole. `M-flatten-after` is a
diagnostic witness for the planned-type conjunct. The live-type conjunct (`$r.type == "CNAME"`) has no
witness of its own: it would show only on a live TXT / planned CNAME pair. The verdict on such pairs is
held by the `type` compare, whose mutation row is `G1-7: neutering the type compare admits a differing
type`. If a later change loosens the `type` compare too, nothing in this block catches the live-type
gap. The issue's closed scope names two mutations, so this is disclosed rather than added (security
review proposed a row; recorded in `decision-challenges.md`).

## Acceptance Criteria

### Pre-merge (this branch)

- [x] AC1: `bash tests/scripts/test-cf-account-migrate-gate.sh` exits 0 and its last line is
  `356 passed, 0 failed`.
- [x] AC2: the RED evidence is reproduced at work time. The Phase 1 edits run against the unfixed lib
  fail exactly `L11a`, `L11b`, `D5`, `D6`, `M-flatten-guard` and `M-flatten-after`. The output ends
  `350 passed, 6 failed`.
- [x] AC2b: the value conjunct's witnesses are reproduced. On a scratch copy of the fixed lib, apply
  `sed 's/elif \$r\.settings == {"flatten_cname":false} and /elif /'` and run the suite against it.
  It ends `351 passed, 5 failed`, failing exactly `L11c`, `L11d`, `L11e`, `L11f` and `M-flatten-guard`
  ("mutation did not land"). The worktree lib is not left mutated.
- [x] AC3: the existing `L11` (tokens `settings,settings:only-flatten-false` on
  `cloudflare_record.dkim_resend`), `L12`, `L13`, `G1-7 settings` and `G1-8b` rows still pass
  unchanged, except for L11's label.
- [x] AC4: `git diff --name-only origin/main...HEAD` lists only the four Files to Edit plus files
  the pipeline writes: this plan,
  `knowledge-base/project/specs/feat-one-shot-13056-cname-flatten-settings/**` (tasks.md,
  decision-challenges.md, session-state.md), and a regenerated `knowledge-base/INDEX.md` if the
  pipeline commits one. `git diff origin/main...HEAD -- apps/web-platform/infra/dns.tf
  apps/web-platform/infra/scripts/cf-account-migrate-job.sh` is empty. The `def cfam_norm_shape:` body
  is byte-identical: `diff <(git show origin/main:tests/scripts/lib/cf-account-migrate-gate.sh | sed -n
  '/^def cfam_norm_shape:/,/^def cfam_fqdn/p') <(sed -n '/^def cfam_norm_shape:/,/^def cfam_fqdn/p'
  tests/scripts/lib/cf-account-migrate-gate.sh)` prints nothing, and the base-side range is not empty:
  `git show origin/main:tests/scripts/lib/cf-account-migrate-gate.sh | sed -n '/^def cfam_norm_shape:/,/^def cfam_fqdn/p' | wc -l`
  prints `10`.
- [x] AC5: `bash tests/scripts/test-cf-account-migration-runbook.sh` and
  `bash tests/scripts/test-cf-account-migration-scope.sh` exit 0.
- [x] AC6: `shellcheck -x tests/scripts/test-cf-account-migrate-gate.sh tests/scripts/lib/cf-account-migrate-gate.sh`
  reports no finding that is not already on `origin/main`.
- [x] AC7: the edited lines themselves carry the carve-out, not only somewhere in each file.
  `grep -F '| \`settings:only-flatten-false\` |' knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md | grep -c 'compares equal, CTO ruling 2026-11-25'`
  prints `1`.
  `tr -s '\n ' '  ' < knowledge-base/engineering/architecture/decisions/ADR-329-*.md | grep -c 'the API default, which is not a difference: CTO ruling 2026-11-25'`
  prints `1`. The `tr` handles the bullet's line wrap. Table rows are single lines and need none.
- [x] AC7b: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0. This
  is the same invocation CI uses for changed docs.
- [x] AC8: no `cf-account-migrate.yml` run is dispatched from this branch. Check with
  `gh run list --workflow cf-account-migrate.yml --branch feat-one-shot-13056-cname-flatten-settings --json databaseId --jq length`,
  which must print `0`.

### Post-merge (the parent session, not this branch)

- [ ] AC9: a `redirects-dns` re-rehearsal on `main` prints `live-read records=26`, 26 `import-normalize`
  lines, `cf_account_migrate_gate: phase=redirects-dns verdict=PASS creates=8 imports=29 destroys=0`
  and `import-normalize count=26`, with no `REFUSE` line. The parent session dispatches and reads it.
  This branch never runs it. A rehearsal does not apply, so it never reaches the job's post-apply
  re-read (`reread_records`, printing `import-normalize reread=ok records=26`). That path is shown
  only by D5/D6 before merge and by the real apply afterwards.

## User-Brand Impact

**If this lands broken, the user experiences:** the `redirects-dns` migration either stays blocked,
which leaves the redirect rulesets and the docs-site and email records stuck in their transitional
state, or it over-admits. In the over-admit case, a real live `settings` difference on a soleur.ai record
(`www`, the apex, the Supabase auth custom domain, or a ProtonMail DKIM CNAME) is overwritten by the
apply. That could break docs-site resolution, sign-in through the custom auth domain, or mail
authentication for every visitor.

**If this leaks, the user's data / workflow / money is exposed via:** no new exposure. The comparator
prints field names and closed tokens only (`L28` pins that no record value reaches the output), and this
change adds no output path.

**Brand-survival threshold:** aggregate pattern. A DNS mis-apply would hit every visitor at once rather
than leak one user's data. The change narrows a refusal to one value that the CTO ruled the API default
and the PATCH preserves, with every other value still refused.

- threshold: aggregate pattern, reason: production DNS for all users sits behind this gate, but the
  diff touches no `SENSITIVE_PATH_RE` path and no per-user data surface.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an infrastructure/tooling change to an internal
migration gate. The engineering ruling is already on the issue (CTO agent, 2026-11-25). Product/UX:
none (no UI surface in Files to Edit or Create).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-329, fourth-exception bullet, with one sentence (Phase 3b). This records that the CTO ruling
of 2026-11-25 supersedes F3 of the 2026-11-23 import-normalize spec for a CNAME's
`{"flatten_cname":false}`. No new ADR: the decision refines an existing stop rule and does not create a
boundary.

### C4 views

No C4 impact. Checked against all three model files (`model.c4`, `views.c4` and `spec.c4` under
`knowledge-base/engineering/architecture/diagrams/`). The `cloudflare` system and the Cloudflare Tunnel
container already model the vendor and the transitional migration (#12931, ADR-329). No external actor,
system, data store or access relationship changes. The change is an internal comparator predicate inside
CI tooling, which no element describes. `bash plugins/soleur/test/c4-count-parity.test.sh` printed
`ALL TESTS PASSED` at plan time.

### Sequencing

None. The ADR sentence is true at merge.

## Observability

```yaml
liveness_signal:
  what: the cf-account-migrate job's run-log lines `live-read records=26`, `import-normalize count=26` and the gate verdict line, emitted on every redirects-dns rehearsal or apply
  cadence: per dispatched cf-account-migrate.yml run (operator-authorized; the next one is the parent's post-merge re-rehearsal)
  alert_target: the job's existing refusal path (`refuse` with reason, plus the GitHub Actions run conclusion), which the parent session reads with gh run view --log
  configured_in: apps/web-platform/infra/scripts/cf-account-migrate-job.sh (unchanged) and .github/workflows/cf-account-migrate.yml (unchanged)
error_reporting:
  destination: the GitHub Actions run log and run conclusion of cf-account-migrate.yml, through the job's existing refuse/summary lines
  fail_loud: true — a settings value outside the carve-out prints `REFUSE <addr> differs from the live record (settings,settings:other|settings:only-flatten-false)` and the job refuses with nothing applied
failure_modes:
  - mode: the carve-out over-admits (a real settings difference passes)
    detection: L11, L11c-L11g plus M-flatten-guard and M-flatten-after in tests/scripts/test-cf-account-migrate-gate.sh, run by infra-validation.yml on every PR touching the gate
    alert_route: the required infra-validation CI check goes red on the PR
  - mode: the carve-out under-admits (the six CNAMEs still refused)
    detection: L11a, L11b, D5 in the suite; in production the re-rehearsal's REFUSE lines
    alert_route: CI red on the PR; the rehearsal run refuses with serial_unchanged=true
  - mode: the post-apply re-read reports the flatten default as a difference
    detection: D5 and D6 (the cf_account_migrate_live_diff entry point). In production the job prints `reread=differs=<addr>:settings+settings:…`, because it joins tokens with `+`
    alert_route: the job's import-normalize-reread-failed refusal in the run log
logs:
  where: GitHub Actions logs of cf-account-migrate.yml and infra-validation.yml
  retention: GitHub Actions default log retention for the repository
discoverability_test:
  command: grep -c 'and $after.type == "CNAME" then empty' tests/scripts/lib/cf-account-migrate-gate.sh
  expected_output: "1"
```

The command's path contains `tests/`, which trips deepen-plan §4.7's suite-shape proxy. That hit is a
false positive. The command is one `grep -c` over one library file and finishes in milliseconds, well
inside Check 10's 15 s cap. `probe-verb-gate.sh` accepts it (rc 0). It prints `0` on `origin/main`
today and `1` after the fix, so it can tell the two trees apart.

## Test Scenarios

1. A canonical plan with one CNAME at `{flatten_cname:false}` passes with 26 import-normalize lines (L11a).
2. All six CNAMEs at `{flatten_cname:false}` (the rehearsal's real read) pass with the exact Done-when verdict (L11b).
3. A CNAME at `{flatten_cname:true}`, with an extra key, with `"false"` or with `null` is refused as `settings,settings:other` (L11c–L11f).
4. A TXT at `{flatten_cname:false}` is still refused as `settings,settings:only-flatten-false` (L11).
5. A live CNAME at `{flatten_cname:false}` against a planned TXT is refused as `type,settings,settings:only-flatten-false` (L11g).
6. The re-read (`cf_account_migrate_live_diff`) is clean with the six at `{flatten_cname:false}` (D5) and at `{}` (D6).
7. Each mutation in the Guard Contract goes RED (M-flatten-guard, M-flatten-after, and the value conjunct via L11c–L11f).
8. The fixture's CNAME set is exactly the six (F5-cname).

## Sharp Edges

- `gm_lost` is defined **after** the G1 mutation block. A new block placed beside the L-rows calls an
  undefined function, which fails at runtime, not at shellcheck. Put the block before the anti-vacuity
  floor.
- The `gm`/`gm_lost` sed expressions anchor on ` then empty$` at end of line. Keep the new `elif` on one
  physical line, ending in `then empty`, or both mutations report "did not land".
- `live_of` writes `settings:{}` for every record, so the CNAME rows must patch `$NLIVE` by address.
  They must not regenerate it from a plan.
- A plan whose `## User-Brand Impact` section is empty, holds only placeholder text, or omits the
  threshold fails `deepen-plan` Phase 4.6.
- Rebase note: PR #12958 edits the same four files. Whichever lands second re-derives the anti-vacuity
  floor from its own post-rebase run. It must not add the two deltas by hand.
