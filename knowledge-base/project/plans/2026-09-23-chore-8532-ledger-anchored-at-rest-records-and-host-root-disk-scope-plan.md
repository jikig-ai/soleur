---
title: "chore(8532): anchor at-rest records to the encryption ledger, and close the host root-disk scope gap"
date: 2026-09-23
slug: chore-8532-ledger-anchored-at-rest-records-and-host-root-disk-scope
branch: feat-ledger-root-disk-scope-and-record-anchors
issue: 8532
lane: cross-domain
type: chore
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Two gaps in the encryption-posture ledger, both of the same shape: a record that
states at-rest posture in prose with nothing resolving it against the ledger, and
a class of store the ledger's own scope never reasoned about.

Part A. Hetzner host root disks are absent from the ledger. `hcloud_server` sits
in `non_store_types`, which was seeded in bulk from the Terraform type inventory
rather than from a finding that host root disks hold nothing. They do hold
credentials, persistent journals and, on one host, a boot-time database
directory.

Part B (#8532). The Article 30 register and `model.c4` restate at-rest posture as
hand-written prose with no anchor back to a ledger store id, so the two drift and
every check over them is a bespoke grep.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Checked | Result |
|---|---|---|
| #8532 open, and is the register/model-anchor gap | `gh issue view 8532` | Holds. Open, milestone Phase 4 |
| #8527 open (`check_disclosed_as_not_encrypted` never runs on a `luks` row) | `gh issue view 8527` | Holds, and is the converse of Part B's check — folded in |
| `hcloud_server` sits in `non_store_types` | read `scripts/encryption-posture-ledger.json` | Holds. Seeded in bulk from the Terraform type inventory (2026-07-23 plan §R7), not from a reasoned exclusion |
| No ADR argues host root disks are out of scope | read ADR-140/141/142/199 | Holds. ADR-141 says "the observed **volumes** are already modeled" — volumes, not hosts |
| likec4 1.50.0's export carries no `metadata` | **FALSIFIED.** I read the committed `model.likec4.json` and inferred the exporter's capability from it; the CTO rendered a minimal model with `npx likec4@1.50.0 export json` and `metadata` survives export intact. The committed file lacks the field only because no element declares one. The plan reads the `.c4` SOURCE for two other reasons — the lint is pure-stdlib hermetic and must not bind to a generated artifact, and `c4-count-parity.test.sh` is the standing precedent — never for this one |
| The inngest LUKS passphrase is staged to the root disk | read `cloud-init-inngest.yml` `luks_key_stage` | Holds, and is deliberate: boot-reopen precedes the network, and the comment says so |
| Terraform `apps/web-platform/infra/**` edits fire a push apply | prior measurement, #8296 AC-G3 | Holds — this plan does not edit that tree |

### Property List (Phase 0.6b)

1. A host whose root disk holds credentials or user-derived data cannot ship without a ledger row stating its at-rest posture.
2. A new host cannot be added without the ledger failing closed until it is classified.
3. A record that states at-rest posture (the Article 30 register, `model.c4`) cannot drift from the ledger without a check failing.
4. An anchor that names a store id which no longer exists fails closed rather than rotting.
5. An encrypted row's record cannot claim plaintext, and a plaintext row's record cannot claim encryption. The second half exists today (R5); the first half is #8527.

### Cut List (Phase 0.6b)

| Cut | Property it would have bought | What already buys it |
|---|---|---|
| A new likec4 `tags`/metadata anchor scheme | 3, 4 | `resolve_disclosed_as()` already resolves `path:anchor` and fails closed. `c4-count-parity.test.sh` already reads the `.c4` SOURCE, so no JSON-export field is needed |
| A separate "record drift" lint | 3 | `lint-encryption-posture.py` already walks every row and is already a required CI job; a second walker would be a second declaration site |
| A bespoke grep per record surface | 3, 5 | One resolver, called per anchor, is the mechanism the ledger already uses for `disclosed_as` |

### Repo research (file:line)

- `scripts/lint-encryption-posture.py`: `check_at_rest()` dispatches by mechanism; `check_luks_row()` resolves `device_binding` (volume + attachment + mapper), never by name similarity; `check_positive_work_floor()` derives the expected count from the `*.tf` scan plus `non_iac_stores`, never from the ledger's own length; `check_resource_partition()` fails closed on an unknown resource type; `resolve_disclosed_as()` splits on the first colon, locates the anchor substring and returns a ±300-character region, refusing any path outside the repo root. Hermetic by contract: no network, no `gh`, offline date arithmetic.
- `scripts/lint-encryption-posture.test.sh`: fixture builders synthesize both the plaintext and the LUKS sibling (the adversarial namespace R1 exists for); `MIN_CASES=30` is an assertion-count floor; `MUTATION-TARGET: MB-N start/end` markers are consumed by `run_mutation()`, which requires the baseline to FAIL and the mutant to PASS.
- Ledger schema keys: `schema_version`, `store_classes`, `non_store_types`, `non_iac_stores`, `stores`, `connections`, `live_coverage_floor`.
- C4: `c4-count-parity.test.sh` reads the `.c4` SOURCE; `c4-model-freshness.test.sh` regenerates via `scripts/regenerate-c4-model.sh` (likec4 pinned 1.50.0) and byte-diffs the committed JSON.
- `knowledge-base/legal/article-30-register.md`: per-activity sections PA-1…PA-36+, at-rest measures inside the §(g) technical-and-organisational-measures cells. **Nothing mechanically checks this file today.**
- CI: the `encryption-posture` job runs `python3 scripts/lint-encryption-posture.py --repo-sweep` and rolls up into the required `test` check.

### Institutional learnings that bind this plan

- **ADR-193** — a suite's anti-vacuity floor must report with `printf >&2` + `exit 1` directly, never through the verdict helper it protects.
- **ADR-140 / ADR-141** — evidence must be resolvable, never name-similarity joined; a CI runner cannot verify guest-side encryption, so root-disk rows take `live_verification: unavailable:<reason>` rather than committing to a probe that does not exist.
- **ADR-200 / ADR-201** — the canonical record is the ledger; a second artifact must point at it, never transcribe it. A parallel allowlist becomes a declaration site nothing enforces.
- `2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator.md` — a floor fixtured only at 0 and 1 cannot tell `<` from `!=`. Fixture at magnitude ≥ 2 and include an over-coverage case.
- `cq-cite-content-anchor-not-line-number` — anchor on content that survives a reformat, never a line number.

### Measured defects found while planning (both pre-existing, both fold into this work)

1. **The positive-work floor has one unit of slack, and it is spendable.** `expected = tf_store_count (12) + len(non_iac_stores) (6) = 18`, while the ledger holds 19 rows — because `git_data.baked_credentials_on_host` is in neither term. Measured: deleting the `supabase.prd` row while leaving its `non_iac_stores` entry in place reported `19 -> 18 stores … 0 failing checks -> PASS`. `non_iac_stores` is counted, never joined to `stores[].store`.
2. **The ledger's address space is block-keyed, not instance-keyed.** `check_resource_partition` keys on `<type>.<name>`, but `hcloud_server.web` (`server.tf`) and `hcloud_volume.workspaces` (`server.tf`) both declare `for_each = var.web_hosts`. One row therefore covers two devices whose posture diverges, and adding `web-3` to `var.web_hosts` births a live host with no `.tf` block delta and no new row. Ledgering hosts without closing this does not deliver "a new host cannot ship unledgered".

- `2026-07-18-forbiddance-drift-guard-encodes-pre-refactor-threat-model.md` — a guard written during a refactor tends to guard the old mechanism; check the claim per resource class rather than blacklisting the retired one.

## Research Reconciliation — brief vs. codebase

| Claim in the brief | Reality | Plan response |
|---|---|---|
| likec4 1.50.0's export carries no `metadata` | False. `metadata` survives `export json`; the committed file has none because nothing declares one | Read the `.c4` SOURCE anyway — hermeticity and the `c4-count-parity` precedent. Never cite the false reason |
| The inngest journal is unbounded | False. `journald-soleur.conf` is web-scoped; the inngest host runs journald's default `min(10% of /var, 4 GB)` | Say "persistent, at the systemd default cap" |
| ADR-199 classifies `/var/lib/inngest` as user prompts and agent output | Overstated. ADR-199's Context opens on `hcloud_volume.inngest_redis` | State the SQLite classification as this plan's inference, not ADR-199's finding |
| `/root/.docker/config.json` is a web root-disk credential | False. `ci-deploy.sh` pins `DEPLOY_DOCKER_CONFIG_DIR` to `/mnt/data/deploy-docker`, on the LUKS volume | Drop it |
| The decrypted prd secret set is written to `/tmp` every boot | Wrong in both directions: cloud-init `runcmd` is first boot only, and `ci-deploy.sh` rewrites it on every deploy | State the deploy-time write |
| The root-disk snapshots are of the inngest host | False. `cutover-inngest.sh` posts to server `123931471`, its own comment says `soleur-web-platform` | Attribute to the web host |
| The Doppler fallback cache is untracked at two git-data sites | Partly. ADR-198's gc-unit leg is closed; two sites remain (`STAGE=luks_open`, `STAGE=bootstrap`) and the `/tmp/.doppler` binding lives in `cloud-init-git-data.yml`, not ADR-198 | Narrow the row's text to the two live sites |
| Error stack traces reach the pino/journald limb | Not established. PA-8 §(c) attributes stack traces to the Sentry limb | Drop it from register text |

## Implementation Phases

### PR-0 — the refusal path stops carrying the address (BLOCKING, ships first)

`docs/legal/privacy-policy.md:309` states "the plaintext recipient address is never stored". Verified false on refused sends: `outbound.ts:118,121` calls `validateEmailHeaders` / `assertRecipientAllowed`, which throw with the address interpolated (`outbound-compliance.ts:168,187,219`); `email-triage-tools.ts:332` mirrors that error through `reportSilentFallback`; `logger.ts` declares no serializers, so pino's default `err` serializer emits `message` verbatim; the container logs to journald with `Storage=persistent, SystemMaxUse=1G` on the web host's unencrypted root disk.

The operator's decision: **fix the code, keep the sentence.**

1. Replace the four interpolations with messages that name the failure class and no address, following `outbound.ts`'s own precedent ("a raw Resend error can echo the recipient … We pass a synthetic Error, not the raw vendor error object"). Keep the discriminating detail the caller needs (`code`), drop the value.
2. Add a `serializers.err` to `logger.ts`, or a scoped equivalent, so a future throw cannot reintroduce the class. Decide in work: a serializer is the class fix, the four edits are the instance fix. Both, per `hr-write-boundary-sentinel-sweep-all-write-sites`.
3. Test: assert that a refusal's emitted log record contains no substring of the input address, driven through the real emitter rather than a stub.
4. Sweep: `git grep -nE '\$\{(to|addr|recipient|email)\}' apps/web-platform/server/` and classify every hit.

### PR-1 — floor and anchor integrity (no new rows, no documents)

1. `check_non_iac_identity`: every `non_iac_stores` id must match a `stores[].store`. Closes the measured hole where deleting `supabase.prd` left CI green.
2. `resolve_disclosed_as`: require exactly one occurrence; fail closed on 0 and on >1, with distinct messages. Measured no-op on today's two live anchors, and a prerequisite for anchoring into the register, where store ids already repeat.
3. Close **#8527**: run the disclosure check on `luks` rows in the positive direction (the disclosure must not deny encryption). The four `luks` rows are the regression set.
4. Mutation rows MB-17/18/19.

### PR-2 — host root disks are ledgered stores

1. Move `hcloud_server` out of `non_store_types` into `store_classes` as `kind: host-root-disk`; add the kind to both enums. **Adjudication of a CTO/CLO fork:** the CTO rules for the move, the CLO against it (all-or-nothing across six hosts; no existing kind fits). The move wins because all-or-nothing is the property being bought — a host that holds nothing states so in a row, which is what the rehearsal volume's own exception row already does — and the enum objection is answered by adding the kind. The CLO's `reason` field for the remaining `non_store_types` entries is adopted: the bulk seed must not survive the fix.
2. Six rows: `hcloud_server.{web,inngest,git_data,registry,rehearsal,grok_dogfood}`. `git_data` absorbs the renamed `git_data.baked_credentials_on_host`, narrowed to the two live Doppler-fallback sites. `rehearsal` and `grok_dogfood` take exception rows on the `hcloud_volume.rehearsal` precedent (destroyed empty; `count = 0`), never a "no store here" mechanism, which would be an unfalsifiable self-certification.
3. `expires_on` stays a review clock; `reevaluate_when` names the **rebuild window**, because a root disk is encryptable only at rebuild.
4. `check_instance_multiplicity`: a row whose Terraform block declares `for_each`/`count` must declare its instances. This is what actually delivers "a new host cannot ship unledgered" — `hcloud_server.web` and `hcloud_volume.workspaces` are both `for_each = var.web_hosts` today, so one row covers two devices with divergent posture.
5. Amend the four `luks` rows' `does_not_defend`: none names the co-resident root-disk passphrase. Against a full-host seizure or a root-disk image, `hcloud_volume.inngest_redis_luks`'s LUKS defends nothing, and the ledger does not say so.
6. ADR: host root disks are ledgered stores (a change to what the gate's scope *is*).

### PR-3 — record anchors (#8532)

1. `records: ["path:anchor", …]`, sibling to `disclosed_as`, resolved by the same function. Separate field because the predicates are opposite: `disclosed_as` is checked for contradiction of a public claim, `records` for agreement with an internal one.
2. `check_records_resolve` (forward) and `check_record_anchors_named` (reverse, over a hard-coded `RECORD_SURFACES`) so a renamed store cannot leave an orphan anchor. The surface list is hard-coded, not ledger-declared: a ledger-declared list is deletable by the same commit that breaks the prose.
3. Carrier: a **visible** inline `(encryption-posture ledger: <store id>)` clause in the register cell — an Art. 30 record is produced to a supervisory authority, so an invisible HTML comment is not part of the record — and a `// ledger: <store id>` comment in `model.c4`, which is a `//`-comment DSL where HTML comments are not valid syntax.
4. Assert-only, never generate. No script writes into `knowledge-base/legal/**`.
5. Register amendments the CLO requires: PA-8 §(g) gains an at-rest limb in the register's own "NEGATIVE — encryption at rest is ABSENT" form; PA-13 §(e)/(g) gives `/var/lib/inngest` a posture; PA-27 §(e)'s cross-reference to a nonexistent PA-21/22 SQLite record is fixed; PA-31 §(e) gets the #6894 device amendment it never received; the cross-cutting "Resilience: Hetzner backups" bullet is corrected, since no `hcloud_server` declares `backups`.
6. Regenerate `model.likec4.json` in the same commit, or `c4-model-freshness` reds.

### PR-4 — the web-host root-disk images (operator-gated)

Four images (`398857857, 406654994, 407991378, 411798619`) of server `123931471`, released only when #6178 closes. Per the operator's decision, their retention is decided here:

1. Determine which are still needed as the #6178 rollback substrate, from the issue and the soak script, and record the finding.
2. Ledger row for the images as a provider-side derivative store, plus an Article 30 retention statement and an Art. 17 reachability note. This discharges PA-36 §(f)'s standing commitment that Hetzner-side retention "must be recorded before the cutover".
3. Deletion is a production mutation: it is proposed with the exact command, and runs only on the operator's per-command authorization, with an Art. 5(2) destruction record written at the time.

## Files to Edit

**PR-0:** `apps/web-platform/server/email-triage/outbound-compliance.ts` (four interpolations at the `throw` sites), `apps/web-platform/server/logger.ts` (an `err` serializer as the class fix), plus the covering test under `apps/web-platform/test/`.

**PR-1:** `scripts/lint-encryption-posture.py` (`resolve_disclosed_as` uniqueness, `check_non_iac_identity`, the `luks` direction of the disclosure check), `scripts/lint-encryption-posture.test.sh` (cases + MB-17/18/19), `scripts/encryption-posture-ledger.json` (delete the "asserted rather than linted for a luks row" honesty note from `hcloud_volume.registry`, which PR-1 makes false).

**PR-2:** `scripts/encryption-posture-ledger.json` (six rows; `store_classes`; `non_store_types` minus `hcloud_server`, plus a `reason` per remaining entry; the four `does_not_defend` corrections), `scripts/encryption-posture-ledger.schema.json`, `scripts/lint-encryption-posture.py` (both kind enums, `check_instance_multiplicity`), `scripts/lint-encryption-posture.test.sh` (MB-14 + fixtures), a new ADR.

**PR-3:** `scripts/lint-encryption-posture.py` (`records`, the two checks, `RECORD_SURFACES`), `scripts/lint-encryption-posture.test.sh` (MB-15/16), `scripts/encryption-posture-ledger.json` + schema, `knowledge-base/legal/article-30-register.md` (the five CLO amendments plus the anchors), `knowledge-base/engineering/architecture/diagrams/model.c4` and the regenerated `model.likec4.json`, a new ADR.

**PR-4:** `scripts/encryption-posture-ledger.json` (the images row), `knowledge-base/legal/article-30-register.md` (retention + Art. 17 limb), an Art. 5(2) destruction record under `knowledge-base/legal/audits/`.

**Explicitly not edited:** `apps/web-platform/infra/**` — a push there fires the targeted terraform apply. No `.tf` file needs to change; `hcloud_server` blocks are read, never written.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200) was searched for each planned file path; no open review issue names any of them.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — these are design-time gates. The failure that matters is the inverse: a gate that passes while a store's posture is wrong, which is how a plaintext volume came to be described as encrypted in the first place (#6588).

**If this leaks, the user's data is exposed via:** the web host's root disk. The on-disk journal holds `userIdHash`, conversation identifiers and request metadata, and — until PR-0 lands — a plaintext recipient address on any refused outbound send. Four provider-side images of that disk exist with no erasure path.

**Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true`.

## Domain Review

**Domains relevant:** legal, engineering.

### Legal (CLO)

**Status:** reviewed. Delivered a blocking objection (the false published claim, now PR-0), 19 must-do items, and the ruling that an Art. 30 anchor must be visible in the rendered record. Also reported a capability gap: `soleur:gdpr-gate` has no Art. 32 at-rest check across its SKILL.md and all six layer files, which is why the ledger's scope gap carries the whole weight. That gap is filed separately rather than fixed here.

**GDPR gate:** the Phase 2.7 invocation was covered by the CLO's own Art. 30 / Art. 32 pass rather than by the `soleur:gdpr-gate` skill. The CLO checked the skill first and reported zero at-rest hits, so the substitution is recorded as adequate for this diff and inadequate in general.

### Engineering (CTO)

**Status:** reviewed. Ruled for the store-class move plus instance multiplicity, the sibling `records` field, bidirectional anchor checks, reading the `.c4` source, and the three-PR split. Measured two pre-existing defects (the spendable floor slack; the block-vs-instance address space) and corrected one false premise of mine.

### Product/UX Gate

Not relevant: no user-facing surface. No file under `components/**`, `app/**/page.tsx` or `app/**/layout.tsx` is touched.

## Architecture Decision (ADR/C4)

### ADR

Two, both deliverables of this plan, ordinals provisional and re-verified at ship:

1. **Host root disks are ledgered stores, not non-store types** (PR-2). Moving a resource type across the R7 partition changes what the gate's scope *is*.
2. **Ledger-anchored record binding for regulator-facing documents** (PR-3). Records point at the ledger; the ledger never writes them.

ADR-140 is amended in PR-2 to record that its `non_store_types` seed was mechanical, and that a type's membership now carries a reason.

### C4 views

Container view. `model.c4` gains `// ledger: <store id>` comments on the store elements, and the Inngest store's description gains its at-rest posture, which it lacks today. Checked against all three `.c4` files for actors, systems and access relationships: this change adds no actor, no external system and no edge — it annotates existing elements — so the only C4 impact is the annotation plus the regenerated JSON. `c4-count-parity` is unaffected: no derived cardinality moves.

### Sequencing

PR-3's ADR is authored when the anchors land. PR-2's is authored with the rows.

## Encryption Posture

This plan introduces no store and no connection. It changes how stores are *recorded*:

```yaml
at_rest:
  new_rows: six host-root-disk rows, all mechanism plaintext-exception
  evidence: the cloud-init / bootstrap paths that write each credential, cited by symbol not line number
  defends_against: nothing at the device layer — a root disk is unencrypted
  does_not_defend: a seized or snapshot-imaged root disk exposes the credentials, the journal, and on inngest the SQLite queue state; on inngest it also exposes the LUKS passphrase for the encrypted volume beside it
  disclosed_as: not-publicly-claimed
  live_verification: unavailable — a CI runner cannot see guest-side disk state (ADR-141); no host emitter reports root-disk posture today
exception:
  justification: per host, written, never a sentinel mechanism
  tracking_issue: per host
  reevaluate_when: the host's next rebuild window — a root disk is encryptable only at rebuild
  expires_on: a review clock, not a remediation deadline
```

## Guard Contract

### Guard 1 — `check_non_iac_identity` (PR-1)

**Property.** Every id the positive-work floor counts names a row that exists.
**Assembly.** `non_iac_stores` entries and `stores[].store` ids, joined by the check; the floor is the consumer.
**Mutation matrix.**

| # | Edit | Must go |
|---|---|---|
| 1 | delete a `stores[]` row whose id is catalogued (measured GREEN today — this is the defect) | RED |
| 2 | add a catalogued id with no matching row | RED |
| 3 | delete the check's dispatch from the sweep | RED via the assertion floor |
| 4 | a catalogued id differing from the row's id only in case | RED |

**Harness rows.** Neuter the case's assertion helper → the count floor must RED independently, reporting via `printf >&2` + `exit 1` and never through the verdict helper it protects (ADR-193). One must-PASS: a ledger where every catalogued id resolves.
**Anchor.** The floor's operands are the `*.tf` scan and the catalog; neither is editable from the ledger's row list.

### Guard 2 — `check_instance_multiplicity` (PR-2)

**Property.** A row whose Terraform block declares `for_each`/`count` states which instances it covers, so one row cannot silently stand for two devices with different posture.
**Assembly.** Every block in the `*.tf` scan whose type is in `store_classes`, not only the ones that happen to be singletons today.
**Mutation matrix.**

| # | Edit | Must go |
|---|---|---|
| 1 | add a second key to a `for_each` map, row unchanged | RED |
| 2 | delete `multiplicity` from a `for_each` row | RED |
| 3 | declare `instances` that disagree with the `variables.tf` map literal | RED |
| 4 | add a new `hcloud_server` block with no row | RED via the partition check |

**Harness rows.** A fixture with two instances where the second is the offender, so a first-member-only walk cannot pass. One must-PASS: a singleton block with no `multiplicity`.
**Anchor.** `instances` is compared against the `variables.tf` literal, not against itself.

### Guard 3 — `check_records_resolve` / `check_record_anchors_named` (PR-3)

**Property.** Every record anchor resolves to exactly one place, and agrees with the row's mechanism; every anchor found in a record surface names a live row.
**Assembly.** `stores[].records[]` in one direction; every `ledger:` token in each file of `RECORD_SURFACES` in the other.
**Mutation matrix.**

| # | Edit | Must go |
|---|---|---|
| 1 | rename a store id, leaving the anchor in the record | RED via the reverse check |
| 2 | duplicate the anchored text so it occurs twice in the file | RED via the uniqueness rule |
| 3 | flip a row's mechanism so its record now contradicts it | RED |
| 4 | delete a surface from `RECORD_SURFACES` | RED via the surface-count floor |

**Harness rows.** Mutate the fixture register so the anchor text appears twice; one must-PASS where a row legitimately carries no `records` yet.
**Anchor.** `RECORD_SURFACES` is hard-coded in the script, so removing a surface is a code diff a reviewer sees, not a ledger edit.

## Observability

All of this is a Layer A design-time CI gate (`hr-observability-layer-citation`). Failures surface as `FAIL:` on stderr from the `encryption-posture` job and from preflight Check 12. No runtime execution path is added, so no Sentry or Better Stack emitter coverage is owed — stated explicitly rather than left blank.

**Note, and a reason PR-1 matters:** the `encryption-posture` job describes itself as advisory and is absent from `scripts/required-checks.txt`; arming it is #6907, open. A record that cites a gate which cannot block overstates the control, so PR-3's register cells say the anchor is advisory until #6907 lands.

```yaml
liveness_signal:
  what: the encryption-posture job's PASS line, which names the store count and the failing-check count
  cadence: every push and PR
  alert_target: the PR's required test rollup
  configured_in: .github/workflows/ci.yml
error_reporting:
  destination: the job log
  fail_loud: exit 1 with a FAIL line naming the store
failure_modes:
  - mode: a store's posture and its record disagree
    detection: check_records_resolve
    alert_route: the job fails
  - mode: a new host ships with no row
    detection: check_resource_partition plus check_instance_multiplicity
    alert_route: the job fails
  - mode: a catalogued id names no row
    detection: check_non_iac_identity
    alert_route: the job fails
logs:
  where: the GitHub Actions job log
  retention: the repo's default
discoverability_test:
  command: python3 scripts/lint-encryption-posture.py --repo-sweep
  expected_output: "0 failing checks"
```

## Risks

| Risk | Mitigation |
|---|---|
| Moving `hcloud_server` into `store_classes` makes all six hosts mandatory at once, so PR-2 cannot land half-written | That is the property being bought. The rows are written before the move lands in the same PR; the gate is fail-closed, so an unwritten row reds CI rather than shipping silently |
| A register edit is a regulated-document edit | PR-3 routes through the CLO before PR-ready; the anchors are assert-only and no script writes into `knowledge-base/legal/**` |
| The anchor makes the register cite a gate that cannot block (#6907 open) | The cells say the anchor is advisory until #6907 arms the job |
| PR-0 touches user-facing server code on a `single-user incident` threshold | It removes a value from an error message; the test asserts the emitted record contains no substring of the input address, driven through the real emitter |
| `count = 0` on `grok_dogfood` means the `.tf` scan sees a resource that may not exist live | Correct conservatism: it forces a written posture before the host can be born, the same pre-birth ordering the git-data row already uses |

## Alternatives Considered

| Alternative | Why not |
|---|---|
| A separate `host_root_disks` catalog beside `non_iac_stores` (the CLO's preference) | A second declaration site nothing joins. Measured: the existing uncatalogued row already buys enough floor slack to delete a different, catalogued row with CI green |
| A `mechanism` meaning "no store here" for the empty hosts | Unfalsifiable self-certification in a script whose premise is that every claim resolves against real code. The `hcloud_volume.rehearsal` exception row is the precedent instead |
| Widening `disclosed_as` to a list and reusing it for internal records | Forks three consumers plus the schema and every fixture, for no gain — the two predicates are opposite in direction |
| A likec4 `metadata` block as the C4 carrier | Valid (metadata does survive export), but binds a security gate to a generated artifact; the source is what `c4-count-parity` already reads |
| Anchoring the register with an HTML comment | An Art. 30 record is produced to a supervisory authority on request; an invisible pointer is not part of the record |
| Deferring #8527 to its own PR | It is the converse of PR-1's own check, on the same four rows; folding it in closes an issue rather than opening one |

## Acceptance Criteria

- [ ] **AC-0a** `git grep -nE '\$\{(to|addr|recipient|email)\}' apps/web-platform/server/email-triage/` returns no hit inside a `throw`.
- [ ] **AC-0b** A test drives a refused send through the real emitter and asserts the emitted record contains no substring of the input address; mutating the fix back out reds it.
- [ ] **AC-0c** `docs/legal/privacy-policy.md:309` is unchanged, and is now true.
- [ ] **AC-1a** Deleting any `stores[]` row whose id is in `non_iac_stores` fails the sweep. (Today it passes — this is the regression being closed.)
- [ ] **AC-1b** A `records`/`disclosed_as` anchor occurring twice in its file fails, with a message distinct from the not-found case.
- [ ] **AC-1c** #8527 is closed: a `luks` row whose disclosure denies encryption fails.
- [ ] **AC-2a** `python3 scripts/lint-encryption-posture.py --repo-sweep` reports **24** stores, 0 unledgered, 0 failing checks, and `hcloud_server` no longer appears in `non_store_types`. Derivation, to be re-run at work time rather than carried from here: today 19 rows against a floor of 18 (`tf_store_count` 12 + `non_iac_stores` 6); PR-2 renames one row rather than adding it (19 − 1 + 6 = 24) and raises `tf_store_count` to 18, so the floor becomes 18 + 6 = 24. Exact, no slack. If the measured numbers differ at work time, the measurement wins and this AC is amended.
- [ ] **AC-2b** Every remaining `non_store_types` entry carries a reason.
- [ ] **AC-2c** Adding a key to `var.web_hosts` without touching the ledger fails the sweep.
- [ ] **AC-2d** Each of the four `luks` rows' `does_not_defend` names where its passphrase lives.
- [ ] **AC-3a** Every `ledger:` token in a `RECORD_SURFACES` file names a live `stores[].store`, and each occurs exactly once per file.
- [ ] **AC-3b** The five CLO register amendments are present, each with a dated `**[YYYY-MM-DD AMENDMENT (#N): …]**` marker.
- [ ] **AC-3c** `bash plugins/soleur/test/c4-model-freshness.test.sh` passes with the regenerated JSON committed.
- [ ] **AC-4a** The four image ids are ledgered as a provider-side derivative store with a retention statement and an Art. 17 reachability note.
- [ ] **AC-4b** No image is deleted without the operator's per-command authorization and an Art. 5(2) record written at the time.
- [ ] **AC-G** No PR in this stack edits `apps/web-platform/infra/**`: `git diff --name-only origin/main...HEAD | grep -c '^apps/web-platform/infra/'` is 0.

## Test Scenarios

Given the ledger as committed / When a row whose id is catalogued in `non_iac_stores` is deleted / Then the sweep exits 1 naming the id.
Given a register fixture where a store id appears twice / When a `records` anchor names it / Then the sweep exits 1 with the ambiguity message.
Given a `for_each` block with two instances / When the row declares one / Then the sweep exits 1.
Given a refused outbound send with an invalid address / When the error is mirrored / Then no substring of the address appears in the emitted record.
