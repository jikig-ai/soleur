---
title: "fix(infra): admit the Cloudflare DNS import-normalize update in the migration gate"
date: 2026-11-23
slug: fix-cf-dns-import-normalize-gate
branch: feat-one-shot-12931-dns-import-normalize
issue: 12931
closes: []
type: fix
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix(infra): admit the Cloudflare DNS import-normalize update in the migration gate

Ref #12931 (never a closing keyword: the issue stays open). PR #13019. Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-23

**Review coverage:** CTO agent (rulings F1-F14), CPO, advisor, sharp-edges, DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow, security-sentinel and a negative-claim audit (23 confirmed, 0
contradicted). The full all-agents fan-out was deliberately not run, because the brief asks for a
proportionate plan for a narrow gate admission.

**Key improvements:**

- The admitted shape comes from a measured plan JSON (Terraform 1.10.5, provider 4.52.7, read-only
  loopback mock, synthetic bodies), not from the rendered plan text, which shows `comment` differently.
- Every `redirects-dns` plan reads all 26 records, so a re-dispatch cannot reach PASS with no record
  confirmed (F13).
- The apply is bounded only where the gate admitted a record, with one INT at 1100 s, so the re-read
  still runs before the job's 30-minute limit, and `zone-rest` keeps today's argv (F11, F14).
- The post-apply re-read compares against the graded plan's `after` with the same comparator, and any
  difference halts with `forget=committed` (F2, F4).
- ADR-329 is amended in this PR, because its Decision would otherwise contradict the shipped gate (F7).
- The security review's four findings are fixed (S1-S4): a read can no longer reuse pre-write
  responses, an unusable live file refuses, the read keeps the token-shape guard, and the restore
  path has a checked value for `pages_apex` and `www`.
- One owner decision stays open before the first `rehearsal=false` dispatch, recorded on #12931 as
  `CF-MIGRATE-FIRST-PATCH: accept-unobserved` or `CF-MIGRATE-FIRST-PATCH: observe-first` (ruling Q8).

## Overview

The `redirects-dns` phase gate of the Cloudflare account migration refused all 26 `cloudflare_record`
imports in rehearsal run 45081671772. Each plans `["update"]` because the provider's Read fills
`content` only when it is already set, so every import shows `+ allow_overwrite = false` and
`+ content = <value>`. Apply would send one same-value PATCH per record and no delete.

This plan admits that one shape and nothing else, binds each admission to a live read of the pinned
record taken in the same run, and re-reads all 26 after the apply. Any difference halts.

**This PR widens a production safety gate. It stops at ready for the owner's review and is not
merged by the pipeline.** Nothing in this work dispatches a workflow, writes Doppler, calls a
Cloudflare write endpoint, runs `terraform apply` or opens an SSH session. The diff changes nothing a
running user sees: the infra apply is suppressed by the `[skip-web-platform-apply]` commit-body line,
and the release is the only thing the merge starts. `web-platform-release.yml` fires on
`apps/web-platform/**` and has two outcomes: it fails at the mirror step (#12937) and deploys nothing,
or the bridge works and it ships the backlog since the last successful deploy. The owner checks
#12937 immediately before merging.

## Research Insights

### Premise Validation

- #12931 is OPEN with no closing PR. PR #13019 is this branch's draft.
- Collision pre-check, read with `gh pr view 12958 --json files` on 2026-11-23: #12958 (draft,
  conflicting, tunnel re-home) edits `dns.tf`, `tunnel.tf`, `server.tf`,
  `apply-web-platform-infra.yml` and the shared registries `scripts/lib/test-affected-paths.sh`,
  `scripts/test-affected-kb-consumers.baseline.txt`, `scripts/suite-shard-legs.tsv` and
  `scripts/suite-durations.tsv`. It touches no gate, job, imports or runbook file, and the three
  records it adds are outside the `redirects-dns` spec. Re-read at every re-sync.
- The runbook's merge freeze (CTO ruling D5) holds changes under `apps/web-platform/infra/**` unless
  they belong to #12931. This PR does, so the freeze allows it.
- Rehearsal log, parsed block by block: 26 `cloudflare_record` blocks, all `updated in-place` and
  imported, every one changing exactly `+allow_overwrite` and `+content`, zero `known after apply`
  lines. Types: 12 TXT, 6 MX, 6 CNAME, 2 NS. All 26 refusals carry the same reason.
- `resource_cloudflare_record.go` is byte-identical at v4.52.7 (the lockfile) and v4.52.10. Read
  guards `content` at `_, contentOk := d.GetOk("content")`.
- Mechanism vs ADR corpus: ADR-329's Decision requires each import "to plan as a pure `["no-op"]`
  import". This change extends that Decision, so the ADR amendment is a deliverable here.

### Measured plan JSON

Measured with Terraform 1.10.5 (the workflow pin) and provider 4.52.7 against a loopback read-only
mock of the Cloudflare API, with an import-block plan and an in-state plan built by a scratch
`terraform import`. No apply ran, and no Cloudflare endpoint was contacted.

| Fact | Measured |
|---|---|
| Actions, both plans | `["update"]`; `importing` is `{id}` on the first and `null` on the retry |
| Changed keys, TXT/MX/CNAME/NS | exactly `["allow_overwrite","content"]` |
| `after_unknown` | `{}` |
| `before.content`, `before.value`, `after.value` | `null`, so **the plan holds no copy of the live content** |
| `before.comment`, `after.comment` | `""`, although the text plan renders `comment = null` |
| `before.tags`, `after.tags` | `[]` |
| `settings` | not in the provider schema; a live-only assertion |
| Full key set | `allow_overwrite comment content created_on data hostname id metadata modified_on name priority proxiable proxied tags timeouts ttl type value zone_id` |

A strict compare of `after.comment` against an API `null` refuses every record, so the suite's
fixtures must carry this measured key set rather than a hand-written `{zone_id}` stub.

**What this measurement does not cover.** The mock's response body is synthesized. No real
Cloudflare record response was read, so `tags`, `settings` and `comment` as the live API returns
them are first observed at the next rehearsal, where any mismatch refuses with nothing written.

### The PATCH, read from source only

`resourceCloudflareRecordUpdate` with cloudflare-go v0.116.0 sends one
`PATCH /zones/<z>/dns_records/<id>` carrying `type`, relative `name`, `content`, `ttl`, `proxied`,
`priority` (MX), `"comment":""`, `"tags":[]` and `"settings":{}`. `DNSRecordSettings` is a struct
value under `omitempty`, which `encoding/json` does not omit. So the empty-settings clause is
load-bearing: a record with non-empty settings could be reset by this write. **No PATCH was sent or
observed.**

### Learnings applied

- `2026-09-14-the-birth-gate-refused-the-real-birth-because-its-fixtures-never-showed-it-a-real-plan.md`:
  fixtures carry the measured shape.
- `2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme.md`:
  a degraded 200 is not evidence.
- `2026-09-11-a-post-write-probe-cannot-be-referenced-to-a-capture-taken-before-the-write.md`: the
  re-read's reference is the graded plan's `after`.
- `2026-09-02-every-guard-i-wrote-was-satisfiable-by-a-guard-that-asserts-nothing.md`: every admit
  clause gets its own mutation row.
- `2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md`: every
  extraction fails closed on empty output.

### Test baseline (this branch, before any change)

| Suite | Result |
|---|---|
| `tests/scripts/test-cf-account-migrate-gate.sh` | 155 passed, 0 failed |
| `apps/web-platform/infra/cf-account-migrate-job.test.sh` | 172 passed, 0 failed, **585 s** |
| `tests/scripts/test-cf-account-migration-runbook.sh` | 58 assertions, 0 failed |
| `tests/scripts/test-cf-account-migration-scope.sh` | 92 passed, 0 failed |

The job suite is slow, and a run cut off by a short `timeout` reports false failures (a 280 s cap
printed 19 failed; uncapped it is clean). Give it at least 15 minutes, and keep new job cases few by
pushing every comparator and shape row down into the gate suite, which takes about 22 s.

### Gates that do not fire

- **Infrastructure as code (Phase 2.8):** no new resource. The 26 records are already declared in `dns.tf`.
- **Task design (Phase 2.9.3):** no new workflow or scheduled surface.
- **GDPR gate (Phase 2.7, run because of the `single-user incident` threshold):** advisory, not legal
  review. None of the eight planned files matches the canonical regulated-data path regex, and the
  plan adds no schema column, foreign key or vendor. The new log lines carry addresses and field
  names, never record values.

### Property List

1. A `cloudflare_record` import whose only diff is the provider's `allow_overwrite`/`content` fill passes the gate.
2. Any other diff on such a record, including real drift or a swapped id, is still refused.
3. The admission rests on a live read of the pinned id taken after the plan in the same run.
4. A retry after a failed apply passes on the same shape with `importing == null`.
5. The log distinguishes this admission from an in-state update.
6. After the apply, all 26 records are confirmed unchanged, or the run halts.
7. The docs that today call this shape drift describe it correctly and keep refusing real drift.

### Cut List

- `ignore_changes` → property 1 → rejected by the CTO ruling (blinds 26 records to drift).
- Provider pin → property 1 → rejected (same Read).
- State push and CLI import → property 1 → rejected (hand-edits production state; ungated write).
- A second pre-apply read after the entrypoint gate → property 3 → already covered by the one read (ruling F9).
- An `expected_import_normalize` dispatch input → property 5 → the shape and the log line already bind it.
- A pre-apply snapshot file for the re-read → property 6 → the graded plan's `after` already covers it (ruling F2).
- A candidate-count helper → property 3 → cut by plan review once every `redirects-dns` plan reads (ruling F13).
- `admitted=<csv>` in the job's summary line → property 5 → no consumer; the gate already prints each address.
- A hand-run confirmation command after a halted run → property 6 → the rehearsal's unconditional read covers it (ruling F13).

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| Live GET "matches `after` on … comment" | `after.comment` is `""`; the API omits or nulls an empty comment | Null, absent and `""` are one empty value, for `comment` only (F1) |
| "with empty settings" | `settings` is not in the provider schema | Asserted on the live record alone (F3) |
| File list | ADR-329 Decision still says every import is a pure no-op | ADR-329 added (F7) |
| "Re-read all 26 after apply" | The provider's 5xx retry budget (`main.tf`, `retries = 6`) can consume the 30-minute job, and a job kill runs no re-read | One INT sent to the apply at 1100 s of script time (CTO missing item 1, F11) |
| "Apply sends one PATCH per record and no delete" | Confirmed from source; not observed | Carried into the PR body as unobserved |

## Proposed Solution

### Gate (`tests/scripts/lib/cf-account-migrate-gate.sh`)

New signature: `cf_account_migrate_gate <phase> <plan.json> [<state.json>] [<live.json>]`.

1. `cf_account_migrate_record_pins <phase>`: one `address<TAB>record-id` line per import-class
   `cloudflare_record`, from the phase spec and `_cfam_import_literals`. The literal is split on `/`
   into exactly two segments, and the zone segment must equal `CFAM_NEW_ZONE_ID`. Never a suffix match.
   It returns 1 unless the pin count equals the spec's count of import-class `cloudflare_record`
   addresses, because `_cfam_import_literals` silently drops a block it cannot parse.
2. `cf_account_migrate_live_collect <phase> <dir>`: builds `live.json` from one raw response file per
   record. An entry is `ok` only on HTTP 200, `success == true`, an object `result`, and `result.id`
   equal to the record segment; a present `result.zone_id` must equal the new zone. A 404 is
   `notfound`; anything else, including a missing file, is `unreadable`.
3. One shared jq definition, `_CFAM_NORMALIZE_JQ`, holds the shape and the comparator:

   ```jq
   def cfam_changed: .change as $c | (($c.before|keys)+($c.after|keys)|unique)
     | map(select($c.before[.] != $c.after[.]));
   def cfam_norm_shape:
     .type == "cloudflare_record" and .change.actions == ["update"]
     and (.change.before|type) == "object" and (.change.after|type) == "object"
     and cfam_changed == ["allow_overwrite","content"]
     and .change.before.allow_overwrite == null and .change.after.allow_overwrite == false
     and .change.before.content == null
     and (.change.after.content|type) == "string" and (.change.after.content|length) > 0
     and (.change.after_unknown|type) == "object"
     and ([.change.after_unknown|..|booleans|select(.)]|length) == 0;
   def cfam_fqdn: if . == "soleur.ai" or endswith(".soleur.ai") then . else . + ".soleur.ai" end;
   ```

   `cfam_live_diff($after; $entry)` returns value-free tokens:

   | Field | Rule |
   |---|---|
   | entry status | only exactly `ok` with an object `result` is compared; `notfound` is reported as that word; any other or absent status is `unreadable` (S2) |
   | `type`, `content`, `ttl`, `proxied`, `priority` | strict equality with `after` |
   | `content` trailing dot | a live `content` ending in `.` differs, because `suppressContent` hides that change from refresh (F13) |
   | `name` | live `name` equals `after.hostname`, **and** `after.hostname == (after.name \| cfam_fqdn)`, because `after.hostname` is refreshed from the same API (F13). The suffix is dot-anchored, so `evilsoleur.ai` is not in the zone |
   | `comment` | null, absent and `""` are one empty value; a non-string differs. No jq `//`, which also maps `false` |
   | `tags` | must be an array equal as a set to `after.tags`; an omitted `tags` differs and names the field (F10) |
   | `settings` | exactly `{}`, null or absent; `{"flatten_cname":false}` differs. No jq `//` (F3) |

   Only after the comparator has refused a field, it may add one token from a closed set:
   `tags:absent`, `content:quoted-equal`, `settings:only-flatten-false`, `settings:other`. These never
   change a verdict and carry no live-derived string; anything outside the set prints the bare field
   name (F12). `cf_account_migrate_live_diff <phase> <plan.json> <live.json>` is the one entry point
   the job's re-read calls, so the job never embeds `_CFAM_NORMALIZE_JQ`.
4. **One evaluation.** A single `verdicts="$(jq` step yields one `{address, action, why, live}` per
   pinned record. `live` holds its `cfam_live_diff` tokens whatever its planned action (F5, F13). For
   a planned `["update"]`, `why` collects `shape` if `cfam_norm_shape` fails, `pin` if `before.id` is
   not the pinned id, and `state-id` if `importing == null` and the pre-plan state's `values.id` is
   not the pin or the state is missing (F6). `norm` is the `update` addresses with an empty `why`. It
   is empty if no `live.json` was supplied or any record's `live` is non-empty. The committed-literal
   check is unchanged and is not subtracted.
5. The two existing refusals subtract `norm`: the class check's `$cls == "import"` arm and the
   `not a pure no-op import` check. Pass `--argjson norm` **after** the filter, so the suite's
   anchors on those `v="$(jq` lines keep matching. Everything outside `norm` is refused exactly as
   today, with the same message.
6. **A fourth argument must be a usable read (S2).** This check runs first, before step 4, on any plan
   including an all-no-op one. Calls with 2 or 3 arguments keep today's behaviour and make no live
   check, so the job's `redirects-dns` call always passes four:

   ```bash
   if (($# >= 4)); then
     [[ -r "$4" ]] && jq -e 'type == "object" and length > 0' "$4" >/dev/null 2>&1 \
       || { echo "cf_account_migrate_gate: REFUSE — the live read is missing or unusable"; return 1; }
   fi
   ```

   With a usable file, one `v="$(jq` over `verdicts` refuses every record with a non-empty
   `live`, including a no-op (F13). The `why` reasons go into a separate `norm_why`, printed inside
   the refusal block after `violations` and never added to it, so the suite's `M-pure` row still
   admits row 9 when the pure-import check is neutered.
7. On PASS only, each admitted record prints `cf_account_migrate_gate: import-normalize <address>`.
   It never prints `in-state-update`, so `CFAM_EXPECTED_IN_STATE_UPDATES` is unaffected.

### Job (`apps/web-platform/infra/scripts/cf-account-migrate-job.sh`)

1. **Pre-gate read.** In `plan_and_gate`, after `terraform show -json tfplan` and immediately before
   the phase gate, on **every `redirects-dns` plan**, rehearsal and apply, even an all-no-op plan:
   read all 26 by pinned id into `$W/live-records.json` and **always** call the gate with four
   arguments. A failed read is non-fatal here and reaches the gate's one refusal through the existing
   `gate-refused` path (S2): `read_live_records "$live" || live=""`, so a stale file is never graded.
   `zone-rest` has no pins and makes no read. A read is never carried between runs (F9, F13). Print
   `cf-account-migrate live-read records=<n>`.
2. **`read_live_records <out>`.** A `LIVE_READ_SH` inner script under `TF_ENV` issues one GET per
   record with `TF_VAR_cf_api_token`, using the existing bearer-on-stdin form
   (`curl --disable --noproxy '*' -sS --max-time 5 -w '\n%{http_code}' --config -`). The URL's zone
   is `CFAM_NEW_ZONE_ID`. Each response goes to its own file as it lands. One `read_end` 90 s
   deadline spans all passes and is enforced **from outside** `doppler run`, because a Doppler stall
   happens before any inner timer starts:

   ```bash
   left=$((read_end - SECONDS)); ((left > 5)) || break
   timeout -k 5 "$((left - 5))" "${TF_ENV[@]}" bash -c "$LIVE_READ_SH" _ "$dir" ...
   ```

   A record with no file at the deadline is `unreadable`.

   Each call starts clean (S1): `rm -f "$out"`, then a new `mktemp -d "$W/live.XXXXXX"`, and retries
   stay inside that directory. Each response is written to `<file>.tmp` and moved into place, and the
   collect output goes through `$out.tmp` then `mv`. If `rm` or `mktemp` fails, the call returns
   non-zero and all 26 count as `unreadable`.

   `LIVE_READ_SH` opens with the `PREFLIGHT_SH` token-shape guard, because each `doppler run` fetches
   the value again and the bearer is fed to `curl --config -`, where a quote and newline add directives
   (S3). On the `legacy` credential path a branch actor can plant that value until operator step O11.
   On `tier_b`, `--preserve-env` should make a planted value inert; this plan did not verify that for
   this token, so the guard applies on both.

   ```bash
   t="${TF_VAR_cf_api_token:-}"
   case "$t" in ""|*[!A-Za-z0-9._~+/=-]*) exit 3 ;; esac
   ```

   Exit 3 ends the retry loop at once, because a bad shape is not transient. No curl runs, all 26 stay
   `unreadable`, and no part of the value is printed.
3. **Bounded apply, only when the gate admitted at least one record** (F11 as narrowed by F14).
   Every other apply, including all of `zone-rest`, keeps today's argv, because an INT between the
   delete and create of `doppler_secret.cf_api_token_dns_edit` would leave the `prd` secret deleted.

   ```bash
   local -a bound=()
   if [[ "$NORM_COUNT" -gt 0 ]]; then
     remaining=$((APPLY_DEADLINE - SECONDS))   # APPLY_DEADLINE=1100
     ((remaining > 0)) || refuse apply-budget-exhausted "no apply budget left; nothing was applied.${fg}" "applied=false${fx:+ $fx}"
     bound=(timeout --foreground -s INT "$remaining")
   fi
   tf_env ${bound[@]+"${bound[@]}"} terraform apply -no-color -input=false -auto-approve "$W/tfplan" 2>&1 | tf_redact_random_ids
   ```

   `NORM_COUNT` is the number of `import-normalize` lines in the gate output, set in `plan_and_gate`.
   The budget check and its refusal run **before** the `applying=true` line is printed, so a refusal
   never follows it; the `bound` array is built there and used by the apply line.

   Exit 124 follows the existing `apply-failed` path. No SIGKILL is sent to the apply. The no-budget
   refusal matters because `timeout 0` disables the bound. `--foreground` is load-bearing: plain
   `timeout -s INT` signals the child and its group, and although the delivered count is not stable
   (reviewers measured mostly 1, sometimes 2, on coreutils 9.12), a second INT makes Terraform exit
   at once, which can lose in-flight creates from state. The contract is "one INT sent at 1100 s",
   not "the apply ends by 1100 s": Terraform's graceful stop has no time limit.
4. **Post-apply re-read, `reread_records <phase>`, when the gate admitted at least one record.** Re-read all 26 into
   its own `$W/live-reread.json`, never `live-records.json` (S1), and compare each with the graded
   plan's `after`, through `cf_account_migrate_live_diff`. A non-zero return from `read_live_records`
   is `reread=unreadable=<all 26>`:
   - a difference halts at once; a 404 is `reread=differs=<addr>:notfound`;
   - `unreadable` gets up to 3 passes, 5 s apart (capped by `CFAM_VERIFY_SLEEP`), inside the 90 s deadline;
   - on failure, refuse `import-normalize-reread-failed` with the fields
     `applied=true forget=committed reread=<r> verify=<v>`;
   - on `apply-failed` with an admitted record, the same re-read runs **first**; the field order is
     `forget=committed reread=<r> verify=<v>`, and with no admitted record `reread=` is omitted, so
     the existing exact-line rows hold;
   - `<r>` is `ok`, `differs=<addr:field,...>` (a 404 is `differs=<addr>:notfound`) or
     `unreadable=<addr,...>`; `<v>` is `ok`, `skipped`, or the existing `failing=<list>` form in
     place of `verify=`;
   - on either refusal (ruling F4 for the re-read failure, F11 for `apply-failed`), the new
     `partial_apply_verdict` wraps `probe_partial_apply` and starts the existing 60 s probe only if
     `SECONDS <= 1395` (the last start that ends by the 1500 s verdict cap with a 105 s pass);
     otherwise it sets `verify=skipped`. An overrun then costs the probe, never the re-read or the
     refusal line.
5. Print `cf-account-migrate import-normalize count=<n>` and add it to the step summary.
6. Correct the `apply-failed` text ("imports already in state plan as no-op"), which is no longer the
   whole truth, and extend the VERIFY BOUND and REFUSAL FIELDS header contracts.

Worst-case timing, for a graceful stop that ends promptly: INT at 1100 s, re-read done by 1190 s,
and `verify_live`'s cap is 1385 s. On `apply-failed`: 1100 + 90 (re-read) + 225 (probe at the maximum
`CFAM_VERIFY_SLEEP` of 60: 60 + 60 + 105) = 1415 s, plus up to 300 s of earlier workflow steps =
1715 s, which leaves 85 s of the job's 1800 s as slack for the stop. A stop that outlasts that slack
is the documented no-refusal-line residual, covered by the runbook's cancelled-run Halt.

### Docs

- `apps/web-platform/infra/cf-account-migration-imports.tf` header: replace "EVERY IMPORT MUST PLAN AS
  A PURE NO-OP" with the admitted shape, and say the live read is now what catches a swapped id.
- Runbook `cloudflare-account-migration.md`:
  - Rewrite the Step 2 "never widen the gate" note to describe this one admitted shape and keep
    refusing every other diff.
  - Expected log: `live-read records=26` on every `redirects-dns` run. `import-normalize count=26`
    applies to the first apply only. After an earlier `applying=true`, any `count` from 0 to 26 is
    valid: it counts the records the apply never reached. The gate's `imports=` falls when a record
    enters state, whether or not its write succeeded. Admitted records never belong in
    `expected_in_state_updates`.
  - Rewrite "the plan then skips imports already in state" to say a record whose PATCH failed plans a
    no-op if live still matches, and a record the apply never reached plans the admitted update.
  - Refusal list: add `import-normalize-reread-failed` and `apply-budget-exhausted`. The latter
    prints `applied=false` and `forget=committed`: re-rehearse and re-dispatch once; on a second
    consecutive refusal, stop for an owner decision. `APPLY_DEADLINE` is never raised to get past it.
  - In `A stop before applying=true`, except `import-normalize-reread-failed` and any refusal covered
    by the new bullet below.
  - New top-level Halt bullet, **A DNS record may hold a wrong value** (`import-normalize-reread-failed`,
    `apply-failed` with `reread=differs=`, or `gate-refused` naming a `cloudflare_record` after an
    earlier `rehearsal=false` run printed `mode=apply applying=true`). Treat it as live user impact
    and restore before any PR, in the order `api`, MX/SPF/DKIM/DMARC, then the rest. The expected
    value is the record's `dns.tf` block. For `pages_apex` and `www`, whose block is
    `cloudflare_pages_project.docs.subdomain`, it is `result.subdomain` from a GET of
    `accounts/<CFAM_NEW_ACCOUNT_ID>/pages/projects/soleur-docs` with `CF_API_TOKEN_PAGES`, requiring
    HTTP 200, `success == true`, `result.name == "soleur-docs"` and a subdomain equal to
    `soleur-docs-40x.pages.dev`, the host the runbook already probes. A failed read or a mismatch
    means no edit and a stop for an owner decision (S4). `Operator-authorizes:` one edit of the named field on the
    NEW zone. A `settings` difference gets no edit: stop for an owner decision (F3). `verify=skipped`
    means no public probe ran, so run the local Verify block. `verify=ok` does not clear this bullet,
    because those probes read no mail record. Then rehearse, which reads all 26, and re-dispatch.
  - In that bullet, **`<addr>:notfound`**: a re-dispatch cannot repair a deleted record, because a
    recreated record has a new id. `Operator-authorizes:` recreating it on the NEW zone from its
    `dns.tf` block (the same value source for `pages_apex` and `www`) to restore service, post the new id on #12931, and stop for an owner decision. No
    `terraform state rm`, `terraform import`, state push or lone literal edit: the path back into
    state needs a reviewed PR and a CTO ruling.
  - A `proxied` difference on `pages_apex` or `www` is treated as drift. Review removed an earlier sentence blaming
    `cron-gh-pages-cert-reissue`: that cron cannot write the new zone at this stage (R5).
  - **No completed re-read** (`reread=unreadable=`, or a cancelled run with `mode=apply applying=true`):
    edit nothing and dispatch a rehearsal, which reads all 26 even on an all-no-op plan. A refusal
    naming a record goes to the bullet above.
  - Record that nobody edits this zone by hand during the apply (the CTO's stated residual).
- ADR-329: amend the Decision bullet and the Principle Alignment sentence.

## Files to Edit

- `tests/scripts/lib/cf-account-migrate-gate.sh`
- `apps/web-platform/infra/scripts/cf-account-migrate-job.sh`
- `apps/web-platform/infra/cf-account-migration-imports.tf` (header comment only)
- `knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md`
- `knowledge-base/engineering/architecture/decisions/ADR-329-cloudflare-zone-resources-live-on-the-soleur-account-r2-stays.md`
- `tests/scripts/test-cf-account-migrate-gate.sh`
- `apps/web-platform/infra/cf-account-migrate-job.test.sh`
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` (exact-count rows for the job, its suite and the gate suite; regenerate with `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline` in the same commit as the source edits)

## Files to Create

None.

## Open Code-Review Overlap

None. Open `code-review` issues were searched for the gate, job, imports file, runbook, gate suite and ADR-329.

## Implementation Phases

### Phase 1: RED tests (`cq-write-failing-tests-before`)

Add a fixture builder that emits the measured key set with synthesized values, and a live-record
builder. Add the gate rows and job cases in Test Scenarios. Confirm they fail against the current gate.
Also in this phase:

- Move the job suite's `redirects-dns` record fixtures to the measured key set, and have the curl stub
  answer each `dns_records/<id>` GET from that fixture, because every such plan now reads all 26.
- Add a `timeout` PATH shim that logs argv and `exec`s the real binary.
- Set `LIB_FN_COUNT` in the gate suite to the final derived count (it is an exact-match row).
- Re-anchor job-suite mutants V6, V7 and V25 in the same commit as the `apply-failed` edit.

### Phase 2: Gate

Implement the pins, collect, comparator and admission. Update the gate's header. Row 9
must keep passing unchanged, because its fixture is off-shape.

### Phase 3: Job

Implement the read, bounded apply and re-read. Update the header contracts.

### Phase 4: Docs

Edit the imports header, runbook and ADR-329.

### Phase 5: Ship to ready, not merged

1. Put a line that is exactly `[skip-web-platform-apply]` in a **branch commit body**. A PR-body line
   never reaches `main`, and a subject line is not matched.
2. Confirm it with the runbook's count, which must print `1` or more:

   ```bash
   gh pr view 13019 --json commits --jq '[.commits[].messageBody | split("\n")[] | select(. == "[skip-web-platform-apply]")] | length'
   ```

3. PR body, first line: `This diff changes nothing a running user sees. Merging fires web-platform-release.yml, which either fails at the mirror step (#12937) and deploys nothing, or ships the backlog since the last successful deploy, so the owner checks #12937 immediately before merging. apply-web-platform-infra.yml is suppressed by the [skip-web-platform-apply] line in a branch commit body. No migration dispatch is fired by the merge.` Then `Ref #12931`, no closing keyword, the merge constraint above, and the Unverified list below.
4. Mark ready and **stop**. No auto-merge and no merge queue: the owner reviews a widened production gate.

### Unverified, carried into the PR body

- No DNS answer gap on an identical PATCH.
- Empty settings preserved by a PATCH that sends `"settings":{}`.
- TXT bytes unchanged (the post-apply re-read catches a change, after the write).
- Import retained after a failed update; a retry may plan as this shape or as a plain no-op, and both are admitted.
- **The first PATCH is unobserved**: its body is known from source only.
- The live record response shape; a rehearsal that finds `tags` omitted refuses with nothing written (F10).
- A dashboard edit landing between the read and a PATCH is overwritten, and the re-read then passes.
- **A bad write is detected, not undone.** The re-read halts with the wrong value still live, and users stay affected until the value is restored and resolver caches expire.
- **All 26 records are written in one apply, with no canary.** The first check of a written value is the re-read after the apply finishes. If the provider's PATCH changed values and still returned 200, `api`, MX, SPF, DKIM and DMARC could all be wrong at once. The job detects this and does not undo it; the values stay wrong until restored and resolver caches expire. The owner accepts or declines this through the `CF-MIGRATE-FIRST-PATCH` token.

### Out of scope

The zone-rest probe control fix in `cf-token-scope.sh` is a separate later PR. **Hold rule until
Phase 3 step 5: do not fire `cron/gh-pages-cert-reissue.manual-trigger` with `probeOnly:false`.**

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-329 (no new ADR): the Decision's "each required to plan as a pure `["no-op"]` import" gains
the one admitted exception and its live-read binding, and the Principle Alignment sentence
("every record import plans as a pure no-op") is corrected. Ruled by CTO agent, 2026-11-23 (F7).

### C4 views

No C4 impact. All three of `model.c4`, `views.c4` and `spec.c4` were read in full.

- **External human actors:** none added. The owner's approval of the job's environment is unchanged.
- **External systems:** `cloudflare`, `github` and `doppler` are already modeled.
- **Containers and data stores:** none touched.
- **Access relationships:** unchanged. The `github -> cloudflare` edge already records that "every
  provider write" targets the Soleur account and its zone. The job already issues a DNS-records GET
  with this token (`token_probe_path`).
- **Counts:** no monitor or email emitter is added. `plugins/soleur/test/c4-count-parity.test.sh` is green.

### Sequencing

ADR-329 stays `adopting`; the amendment describes the gate as it will be once this PR merges.

## User-Brand Impact

- **If this lands broken, the user experiences:** sign-in and app data failing for every user while
  `app.soleur.ai` still loads, if the `api.soleur.ai` record is altered; `soleur.ai` or `www` not
  resolving; sign-in codes never arriving, because DMARC is `p=reject` and a broken SPF or DKIM record
  can get them rejected; or mail to `@soleur.ai` bouncing or misrouting. Two records fail with no
  immediate symptom, and the public probes read neither: a wrong `buttondown_ns1` or `buttondown_ns2`
  value redelegates `mail.soleur.ai`, and a wrong `supabase_acme_challenge` value can break `api`
  certificate validation later. The runbook's Halt restore order names both.
- **If this leaks, the user's workflow is exposed via:** a widened gate admitting a real drift or a
  swapped record id, which would write a wrong value into production DNS under cover of an import.
  The new read handles only public DNS data and logs addresses and field names; the token stays on
  the curl stdin channel.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one bad record write reaches every user's mail or site at
  once and cannot be undone by the gate after the PATCH, so this is not an aggregate pattern.

CPO sign-off is required before `soleur:work`. `soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "the cf-account-migrate job's verdict lines, including `cf-account-migrate live-read records=<n>` and `cf-account-migrate import-normalize count=<n>`"
  cadence: per dispatch (one-shot migration job)
  alert_target: the job's existing failure email to ops, sent on failure or cancel
  configured_in: .github/workflows/cf-account-migrate.yml
error_reporting:
  destination: GitHub Actions run log, a `::error` annotation and the step summary, through the job's `refuse`
  fail_loud: "`cf-account-migrate phase=redirects-dns verdict=refuse reason=import-normalize-reread-failed applied=true forget=committed reread=differs=<addr:field>`"
failure_modes:
  - mode: an off-shape update or a live record that differs before apply
    detection: the gate prints `REFUSE <address>` naming the clause or field, then `reason=gate-refused`
    alert_route: job failure email
  - mode: a record differs or vanished after the PATCH
    detection: the post-apply re-read refuses `import-normalize-reread-failed` with `reread=differs=<addr:field>`
    alert_route: job failure email, then runbook Halt
  - mode: the Cloudflare API cannot be read after the apply
    detection: the same refusal with `reread=unreadable=<addr>`
    alert_route: job failure email, then runbook Halt
  - mode: the apply hangs on provider retries
    detection: the 1100 s bound exits 124 into `reason=apply-failed` with a `reread=` field
    alert_route: job failure email
logs:
  where: GitHub Actions run log of cf-account-migrate.yml
  retention: 90 days (repository Actions log retention, read from the API on 2026-11-23)
discoverability_test:
  command: grep -m1 -o "import-normalize count=" apps/web-platform/infra/scripts/cf-account-migrate-job.sh
  expected_output: "import-normalize count="
```

## Downtime & Cutover

- **Operation and surface:** one in-place, same-value `PATCH` on each of the 26 records in the live zone (site, `api`, mail). No delete and no replace; the gate refuses both.
- **Zero-downtime path, and the default:** an in-place update of an existing record id, with the value proven equal to the live record in the same run. There is no blue-green alternative for adopting a record that already serves traffic, and every rejected alternative (`ignore_changes`, state push, CLI import) is recorded in the Cut List.
- **Per-stage verification:** the pre-gate read of all 26, then the post-apply re-read, then the existing live probes. Any difference halts, with the restore path in the runbook.
- **Residual:** whether an identical PATCH causes any DNS answer gap is unverified (see the Unverified list). No maintenance window is declared; the owner's authorization of the `rehearsal=false` dispatch is the sign-off.
- **Merge:** the diff changes nothing a running user sees. `web-platform-release.yml` fires on merge and either fails at the mirror step (#12937) and deploys nothing, or ships the backlog since the last successful deploy. The owner checks #12937 immediately before merging.

## Encryption Posture

No new store and no new connection. The one `.tf` edit is a comment header. The row below records the existing connection the new read reuses.

```yaml
at_rest: []
in_transit:
  - connection: cf-account-migrate job -> api.cloudflare.com (DNS records GET)
    enforced_at: apps/web-platform/infra/scripts/cf-account-migrate-job.sh:LIVE_READ_SH
    tls: HTTPS, with no TLS override, so the minimum version is the runner's curl default
    cert_verification: on
    does_not_defend: a compromised runner, a leaked API token, or Cloudflare itself returning a wrong record
    disclosed_as: not-publicly-claimed
```

## Guard Contract

### Guard 1 — import-normalize admission

**Property.** A `cloudflare_record` update passes the phase gate only if its changed keys are exactly `allow_overwrite` (null to false) and `content` (null to string), nothing is unknown, it is bound to the committed pinned id, and a live read taken in this run equals its planned `after`.

**Assembly.** One chokepoint: the `norm` array, built once from `_CFAM_NORMALIZE_JQ`, is the only thing subtracted from the two refusals that block a non-no-op import (the class check's `$cls == "import"` arm and the `not a pure no-op import` check). The population is every import-class `cloudflare_record` in `cf_account_migrate_phase_spec` joined to `_cfam_import_literals`. The one production caller is `plan_and_gate`. `verdicts` is evaluated once, so the decision and its explanation cannot disagree. A second subtraction site would be the defect.

**Anchor.** The pins come from the committed `import {}` literals and the zone constant, so a weakening has to edit `cf-account-migration-imports.tf` or the gate in a diff the owner reviews. The suite's expected count of 26 records is a literal in the suite.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the `cfam_changed` clause, so a `ttl` change is admitted | RED |
| 2 | Drop the `before.content == null` clause, so real content drift is admitted | RED |
| 3 | Drop the `allow_overwrite` false clause | RED |
| 4 | Replace the recursive unknown scan with a top-level check, so a nested unknown is admitted | RED |
| 5 | Drop the `before.id` pin clause | RED |
| 6 | Drop the pre-plan state id clause on the retry arm | RED |
| 7 | Neuter each `cfam_live_diff` field in turn (`type`, `name`, `content`, `ttl`, `proxied`, `priority`, `comment`, `tags`, `settings`) | RED |
| 8 | Write `comment` or `settings` with jq `//`, so `false` reads as empty | RED |
| 9 | Own dispatch: make `norm` admit when `live.json` is absent or empty | RED |
| 10 | Second member: stop at the first record, so a compliant first plus an off-shape second passes | RED |
| 11 | Compare only records planned `update`, so a drifted no-op record passes (F5) | RED |
| 12 | Print `in-state-update` for an admitted record | RED |
| 13 | Reorder: move the live read before `terraform plan` in `plan_and_gate` | RED |
| 14 | Skip the read on an all-no-op `redirects-dns` plan, so a re-dispatch reaches PASS unconfirmed (F13) | RED |
| 15 | Drop the `after.hostname == (after.name \| cfam_fqdn)` binding | RED |
| 16 | Replace the dot-anchored suffix with `endswith("soleur.ai")`, admitting `evilsoleur.ai` | RED |
| 17 | Drop the live trailing-dot refusal | RED |
| 18 | Let a closed-set diagnostic token change a verdict | RED |
| 19 | Treat an unusable fourth-argument file as not supplied, so an all-no-op plan passes (S2) | RED |
| 20 | Compare an entry whose status is absent or unknown instead of reporting `unreadable` (S2) | RED |
| 21 | Call the gate with three arguments on `redirects-dns` (S2; U8 keeps this arity, pinned by a static suite row) | RED |
| 22 | Drop the managed-mode clause of the exactly-once check, so a non-managed entry at a spec address passes (Q5 U1) | RED |
| 23 | Drop the `length != 1` clause of the exactly-once check, so a duplicate address passes (Q5 U2) | RED |
| 24 | Remove the refusal of a non-no-op `cloudflare_record` outside `norm`, so a create-class or mutable record update passes (Q5 U3) | RED |
| 25 | Drop the unique-id check in `cf_account_migrate_record_pins`, so one record id pins two addresses (Q5 U4) | RED |
| 26 | Drop `noop_id_ok`, so a no-op on a record id other than its pin passes (Q5 U5) | RED |
| 27 | Drop the live `data` clause, so a non-empty live `data` passes (Q5 U6) | RED |
| 28 | Drop the `result.id` or `result.zone_id` binding from `cfam_live_diff`, so a live entry for another record or zone passes (Q5 U7) | RED |

**Harness rows:**

| # | Edit | Expected |
|---|---|---|
| H1 | Suite edit: build the admit fixture with a hand-written `{zone_id}` `after` | RED (admit row fails) |
| H2 | Must-PASS, not the canonical: a retry plan mixing no-op and update records | PASS |
| H3 | Must-PASS, not the canonical: an empty comment read as absent, null and `""` | PASS |

### Guard 2 — post-apply re-read

**Property.** After any apply that carried an admitted import-normalize update, all 26 pinned records are read and compared with the graded plan's `after`, and a difference or an unread record ends the run with a refusal.

**Assembly.** `run_apply` has two post-apply exits, `rc == 0` and `rc != 0`; both flow through one `reread_records` function, which uses the Guard 1 comparator and `cf_account_migrate_record_pins`. The reference is the `tfplan.json` the apply consumed.

**Anchor.** The comparator is the gate library's, not a copy in the job, so the suite's `ONE SOURCE` rows bind it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the re-read on the `rc == 0` path | RED |
| 2 | Delete the re-read on the `apply-failed` path | RED |
| 3 | Own dispatch: treat an empty pin list as `reread=ok` | RED |
| 4 | Second member: stop at the first differing or first compliant record | RED |
| 5 | Treat a 404 as `unreadable` and retry it | RED |
| 6 | Reorder: run the re-read before `terraform apply` | RED |
| 7 | Remove the `timeout -s INT` bound from the apply | RED |
| 8 | Drop `--foreground`, or move `timeout` outside `tf_env`: the shim's argv no longer starts with `--foreground -s INT <n> terraform apply` | RED |
| 9 | Run the partial-apply probe before the re-read on `apply-failed` | RED |
| 10 | Remove the no-budget refusal, so `timeout 0` runs an unbounded apply | RED |
| 11 | Bound a `zone-rest` apply, whose argv must stay unchanged (F14) | RED |
| 12 | Reuse the pre-gate directory or `live-records.json` for the re-read, so a Doppler failure passes on pre-write responses (S1) | RED |
| 13 | Remove the token-shape guard from `LIVE_READ_SH` (S3) | RED |
| 14 | Retry after the guard's `exit 3` (S3) | RED |
| 15 | Remove the `::stop-commands::` window or the `tf_line` filter from the plan or apply pipeline, so Terraform output can open a workflow command (Q7) | RED |

**Harness rows:**

| # | Edit | Expected |
|---|---|---|
| H1 | Suite edit: the curl stub always answers the planned record, whatever the case set | RED (the differs case fails) |
| H2 | Must-PASS: one `unreadable` pass followed by a clean pass | PASS |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "admit the update narrowly in the gate and let apply send the 26 same-value writes" | Gate 4-6 | mapped |
| 2 | "the changed keys are exactly allow_overwrite (null to false) and content (null to string), with nothing unknown" | `cfam_norm_shape` | mapped |
| 3 | "a live GET by the pinned id, taken after the plan, matches `after` on type, hostname, content, ttl, proxied, priority, comment and tags, with empty settings" | `cfam_live_diff`, Job 1-2 | mapped |
| 4 | "Admit the same shape with importing == null, for retries after a failed apply." | Gate 4 (retry arm: `state-id`), Gate 5 | mapped |
| 5 | "Log it as `import-normalize`, not `in-state-update`." | Gate 7, Job 5 | mapped |
| 6 | "Re-read all 26 after apply; any difference halts." | Job 4 | mapped |
| 7 | "its 'never widen the gate' note must describe this one admitted shape and keep refusing real drift" | Docs, runbook | mapped |
| 8 | "Tests: tests/scripts/test-cf-account-migrate-gate.sh (admit, retry, each off-shape refusal), apps/web-platform/infra/cf-account-migrate-job.test.sh." | Phase 1, Test Scenarios | mapped |
| 9 | "Put that line in a commit body and confirm it with the runbook's `gh pr view <PR> --json commits` count." | Phase 5 steps 1-2 | mapped |
| 10 | "Unverified, carry into the PR body" | Unverified list | mapped |
| 11 | "Do NOT merge: stop with the PR ready for the owner's review" | Phase 5 step 4 | mapped |
| 12 | "Ref only, never a closing keyword" | Frontmatter `closes: []`, Phase 5 step 3 | mapped |
| 13 | "the zone-rest probe control fix in cf-token-scope.sh" | Out of scope | descoped — justification: the brief assigns it to a separate later PR |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cf-account-migrate-gate.sh` | asks 1-5 | asked |
| `cf-account-migrate-job.sh` read and re-read | asks 3, 6 | asked |
| `cf-account-migration-imports.tf` header | "apps/web-platform/infra/cf-account-migration-imports.tf (header)" | asked |
| Runbook | ask 7 | asked |
| Both test suites | ask 8 | asked |
| ADR-329 amendment | — | inferred — justification: the ADR's Decision states the opposite of the shipped gate, and plan Phase 4 makes the amendment a deliverable (CTO ruling F7) |
| Bounded apply (`timeout -s INT`) | — | inferred — justification: safety dependency of ask 6, because a job killed by its 30-minute timeout runs no re-read (CTO missing item 1) |
| `fixture-relative-assert.baseline.txt` | — | inferred — justification: the ratchet requires row equality in the same commit as the source edit |
| `cfam_live_diff` closed diagnostic tokens | — | inferred — justification: the live response shape is unread, and a token separates a comparator correction from real drift without a second read (CTO ruling F12) |
| Read on every `redirects-dns` plan | — | inferred — justification: without it a re-dispatch reaches PASS with no record confirmed, which breaks ask 6 (CTO ruling F13) |

### Split Assessment

- Subsystems touched: 4 — `tests`, `apps/web-platform`, `knowledge-base`, `plugins/soleur` (one regenerated baseline file)
- Planned files: 8 | Estimated changed lines: 750
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — the only seam is docs (runbook, ADR) from code. Declined: the brief fixes "ONE PR", the baseline must move in the same commit as the source, and shipping the gate without its runbook restore path would leave a widened gate with no recovery text.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: a plan of 26 measured-shape updates with matching live records passes, printing 26 `import-normalize` lines and 0 `in-state-update` lines.
- [ ] AC2: the same shape with `importing == null` passes only when `before.id` and the pre-plan state id both equal the pin.
- [ ] AC3: every off-shape row in Test Scenarios is refused, and row 9 still refuses with `not a pure no-op import`.
- [ ] AC4: any live field difference, an omitted `tags`, non-empty `settings`, a 404, a degraded 200 or a missing read refuses with nothing applied, naming the address and field and printing no value.
- [ ] AC5: on every `redirects-dns` plan, including an all-no-op one, the job reads all 26 after the plan and before the phase gate, in rehearsal and apply, with the bearer never in argv, four gate arguments, a fresh directory per read and a separate re-read output file; a read that made no GET is `unreadable`, and a token failing the shape guard makes no curl call; `zone-rest` makes no read.
- [ ] AC6: a post-apply difference refuses `import-normalize-reread-failed applied=true forget=committed`; when the gate admitted at least one record, an `apply-failed` refusal carries `reread=` in the order `forget=committed reread=<r> verify=<v>`, and otherwise omits it.
- [ ] AC7: an apply with an admitted record runs as `tf_env timeout --foreground -s INT <n> terraform apply` with the INT at 1100 s of script time (asserted on the shim's argv), exit 124 reaches `apply-failed`, no budget refuses before `applying=true`, and `partial_apply_verdict` past 1395 s sets `verify=skipped` (a function-level test on the virtual clock). A `zone-rest` apply's argv is unchanged.
- [ ] AC8: every Guard 1 and Guard 2 mutation row drives its suite red, and each must-PASS row passes.
- [ ] AC9: `bash tests/scripts/test-cf-account-migrate-gate.sh`, `bash apps/web-platform/infra/cf-account-migrate-job.test.sh`, `bash tests/scripts/test-cf-account-migration-runbook.sh`, `bash tests/scripts/test-cf-account-migration-scope.sh`, `bash plugins/soleur/test/fixture-relative-assert.test.sh` and `bash scripts/test-all.sh --affected` all exit 0.
- [ ] AC10: every hit of the command below is rewritten to describe the admitted shape, except two that stay true: the gate's `not a pure no-op import` refusal message and the job's verify-failed text about a dashboard-edited rule.

  ```bash
  git grep -n -i -E 'pure no-op|pure import|pure .?\["no-op"\]|plans? as (a )?(pure )?no-op|skips imports|never widen the gate' -- \
    apps/web-platform/infra/cf-account-migration-imports.tf apps/web-platform/infra/scripts/cf-account-migrate-job.sh \
    knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md \
    'knowledge-base/engineering/architecture/decisions/ADR-329-*.md' tests/scripts/lib/cf-account-migrate-gate.sh
  ```

- [ ] AC11: the `gh pr view 13019 --json commits` count prints `1` or more.
- [ ] AC12: the PR body says `Ref #12931`, has no closing keyword, and carries the Unverified list and the hold rule.
- [ ] AC13: the PR is ready for review and **not merged or queued**.

### Post-merge (operator)

`Operator-authorizes:` the `redirects-dns` rehearsal dispatch (`gh workflow run cf-account-migrate.yml --ref main -f migrate_phase=redirects-dns -f confirm=MIGRATE-CF-redirects-dns -f rehearsal=true -f reason='#12931 import-normalize rehearsal'`). An agent runs it once the owner types go naming it (`hr-menu-option-ack-not-prod-write-auth`). Tracked on #12931. This pipeline does not dispatch it.

- [ ] The rehearsal prints `live-read records=26`, `import-normalize count=26` and `verdict=PASS`, or refuses naming a live field with nothing written.
- [ ] Before the first `redirects-dns` `rehearsal=false` dispatch, the owner posts a comment on #12931 whose first line is exactly `CF-MIGRATE-FIRST-PATCH: accept-unobserved` or `CF-MIGRATE-FIRST-PATCH: observe-first`. The runbook's read command must print `accept-unobserved` for the dispatch to be proposed; empty, `edited` or `observe-first` holds it. `accept-unobserved` includes the one-run risk that all 26 records are written with no canary.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** The CTO agent's 2026-11-22 ruling is binding. Its 2026-11-23 rulings F1-F14 are recorded in `decision-challenges.md` and folded into this plan.

### Product

**Status:** reviewed
**Assessment:** CPO sign-off, 2026-11-23: approved with changes, all applied. The named failure now leads with `api.soleur.ai` and sign-in codes under DMARC `p=reject`, and the plan records that a bad write is detected but not undone, with the restore path in the runbook. No UI surface is touched, so the Product/UX Gate tier is none.

## Test Scenarios

All `unit` unless marked. Job cases are `integration` against the suite's PATH stubs; nothing reaches a network.

**Gate, admit:** 26 records with the measured key set; retry; retry mixing no-op and update; empty comment as absent, null and `""`.

**Gate, off-shape refusals (one row each):** extra changed key (`ttl`, `proxied`, `name`); `allow_overwrite` to true; `before.allow_overwrite` non-null; `before.content` non-null (real drift); `after.content` null, empty or non-string; `after_unknown` true at top level and nested; a non-record import planned `update` (Pages); a replace; a wrong import literal; retry with `before.id` off the pin; retry absent from state; retry with no state file; a literal whose zone segment is not the new zone.

**Gate, live refusals:** no `live.json`; a missing address; each of the nine compared fields differing; a live `content` ending in `.`; `after.hostname` not matching `after.name`; a hostname of `evilsoleur.ai`; omitted `tags`; `settings` of `{"flatten_cname":false}`; a non-empty live comment; a `false` comment; a drifted no-op record alongside admitted updates; a compliant first record with an off-shape second; on an all-no-op plan, a fourth argument that is a missing file, an empty string, an empty file, `null` or `{}`; an entry with an absent or unknown status.

**Collect:** HTTP 200 with `success:false`; a non-object `result`; `result.id` off the pin; a differing `result.zone_id`; an unparseable body; a 404 as `notfound`; a 429 and a 500 as `unreadable`.

**Job (`integration`):**

- Rehearsal reads 26 records, applies nothing, and leaves the serial unchanged.
- Apply reads in the order plan, read, gate, entrypoint gate, `applying=true`, apply, re-read, verify.
- Read failure before apply: `gate-refused`, no apply.
- Post-apply difference, post-apply 404, and unreadable-then-clean.
- Unreadable through the deadline.
- Doppler succeeds before the gate and fails on the re-read: `reread=unreadable=` names all 26 (S1).
- A token failing the shape guard: zero curl calls, one attempt, all 26 `unreadable`, no part of the value printed (S3).
- The `redirects-dns` gate call has four arguments, including after a failed read (S2).
- `apply-failed` with each `reread=` value; apply exit 124; no budget left before apply; the `timeout` shim logs `--foreground -s INT <n> terraform apply`; `partial_apply_verdict` past 1395 s sets `verify=skipped` (function-level, virtual clock).
- A pin list shorter than the spec's record count refuses.
- Each closed-set token appears for its case (`tags:absent`, `content:quoted-equal`, `settings:only-flatten-false`, `settings:other`), with no record value in the output.
- An all-no-op `redirects-dns` plan reads all 26, refuses on a difference, and runs no post-apply re-read.
- A `zone-rest` run makes no record read, and its apply argv is unchanged.
- The in-state-update set is unaffected by admitted records.
- No record GET carries `-X`, and the bearer never appears in argv.

## Dependencies & Risks

- **The live response shape is unread.** A strict `tags` compare may refuse at rehearsal if the API omits the field. Nothing is written, and the relaxation needs a new ruling and a PR (F10).
- **A non-empty default in live `settings`** refuses the same way (F3).
- **The first write is unobserved.** The re-read detects a change only after it lands on production DNS.
- **A bad write is detected, not undone.** The re-read halts with the wrong value still live, and users stay affected until the value is restored and resolver caches expire. A re-dispatch cannot repair it, because a record whose state already holds `content` is off-shape and refused. The runbook's Halt bullet therefore carries the restore path, and it must be merged before any `rehearsal=false` dispatch is authorized.
- **Concurrent dashboard edit:** a residual the CTO accepted; the runbook says no hand edits during the apply.
- **SIGINT stop:** a provider call that ignores cancellation can still run to the job's 30-minute kill, which prints no refusal. The runbook's cancelled-run Halt covers this.

## References

- Rehearsal run 45081671772
- ADR-329, `knowledge-base/engineering/architecture/decisions/ADR-329-cloudflare-zone-resources-live-on-the-soleur-account-r2-stays.md`
- Runbook, `knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md`
- Decisions, `knowledge-base/project/specs/feat-one-shot-12931-dns-import-normalize/decision-challenges.md`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- jq's `//` treats `false` as absent. It must not appear in the `comment`, `tags` or `settings` compare.
- Do not build the admit fixture by hand from a `{zone_id}` stub: `before.comment` is `""`, and the real key set is listed under Measured plan JSON.
- `after.name` is relative (`send`); compare the live `name` with `after.hostname`.
- The existing job fixtures plan no-op imports with a stub `after`. Every `redirects-dns` plan now reads all 26, so those fixtures must move to the measured key set first, or every case refuses for the wrong reason.
- `--argjson norm` goes after the jq filter, and the `why` reasons stay out of `violations`. Either mistake breaks the suite's `M-pure` row or its anchor census.
