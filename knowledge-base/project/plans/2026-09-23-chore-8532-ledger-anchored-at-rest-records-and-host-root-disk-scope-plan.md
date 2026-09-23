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
- CI: the `encryption-posture` job runs `python3 scripts/lint-encryption-posture.py --repo-sweep`. It is a **standalone, advisory** job: it is absent from `scripts/required-checks.txt`, and the required `test` aggregator needs only the four test/build jobs. A PR can merge with it red. Arming it is #6907, open. (An earlier draft of this line said it rolls up into `test`; that was false and is the claim the Observability section contradicts.)

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

**Three sinks, not one** (measured): journald on the web host's unencrypted root disk; **Sentry**, where `err.message` becomes the issue title and `sentry-scrub.ts` is key-name-based with zero handling of `exception.values[].value`; and **Better Stack**, because `vector.toml`'s email regex sits in a stage that is skipped for already-structured (pino JSON) lines. All three are closed prospectively by fixing the throw site, which is the argument for fixing it there.

**Two leaking sites, not four** (measured): `${addr}` and `${to}` (the latter carries the display name too). `${name}` is the header field name; `${domain}` and `${local}` are reached only for our own domains and a fixed role-name set, so neither carries user data. `notifications.ts` is the same class at a second site and is in scope for the sweep.

1. Replace the two leaking interpolations with messages that name the failure class and no address, following `outbound.ts`'s own precedent ("a raw Resend error can echo the recipient … We pass a synthetic Error, not the raw vendor error object"). Keep the discriminating detail the caller needs (`code`), drop the value.
2. Class fix at `sanitizeLogMessage` plus an `err`-shaped twin inside `reportSilentFallback`, NOT a pino `serializers.err`: `mirrorToSentry` runs before pino's render stage, so a serializer cannot reach either Sentry limb, and five marker loggers do not inherit from `logger.ts` at all.
3. Test: assert that a refusal's emitted log record contains no substring of the input address, driven through the real emitter rather than a stub.
4. Sweep the whole of `apps/web-platform/server/` for value-shaped tokens (`inviteeEmail|email|recipient|addr|to|sender`), classify every hit in the plan rather than at work time, and add `email`, `inviteeEmail`, `recipient` to `SENSITIVE_KEY_NAMES` — one line that covers six call sites.

### PR-1 — floor and anchor integrity (no new rows, no documents)

1. `check_non_iac_identity`: every `non_iac_stores` id must match a `stores[].store`. Closes the measured hole where deleting `supabase.prd` left CI green.
2. `resolve_disclosed_as`: require exactly one occurrence; fail closed on 0 and on >1, with distinct messages. Measured no-op on today's two live anchors, and a prerequisite for anchoring into the register, where store ids already repeat.
3. Close **#8527**: run the disclosure check on `luks` rows. There are **five** such rows, not four (`hcloud_volume.registry` is `luks` without the `_luks` suffix), and only `workspaces_luks` carries a resolvable anchor, so the live regression set is one row plus synthesized fixtures. The predicate must be **negation-aware and specified here**: the existing `LUKS|encrypt` regex fires on the register's own mandated "encryption at rest is ABSENT" form, so reusing it reds the committed ledger the moment this lands.
4. `check_store_id_accounted` (the forward direction): every `stores[].store` resolves to a `.tf` address or a `non_iac_stores` entry. This is what makes the floor exact by construction, and it closes the measured slack from both directions rather than one.
5. Mutation rows MB-17…MB-21, one per new behaviour; the uniqueness rule's two failure directions need separate markers. Raise `MIN_CASES` to the new count. The suite's floor exits **2**, not 1.

### PR-2 — host root disks are ledgered stores

1. Move `hcloud_server` out of `non_store_types` into `store_classes` as `kind: host-root-disk`; add the kind to **four** declaration sites (`STORE_KIND_ENUM`, `STORE_CLASS_KIND_ENUM`, and the schema's two `kind` enums) plus an assertion that the script's accepted set equals the schema's, since the validator never reads the schema. **The `reason`-per-`non_store_types`-entry idea is CUT**: it satisfies no listed property, is the same unfalsifiable self-certification this PR rejects for hosts, and would crash `check_resource_partition`, which builds a `set()` over that list. The ADR amendment already records that the seed was mechanical. **Adjudication of a CTO/CLO fork:** the CTO rules for the move, the CLO against it (all-or-nothing across six hosts; no existing kind fits). The move wins because all-or-nothing is the property being bought — a host that holds nothing states so in a row, which is what the rehearsal volume's own exception row already does — and the enum objection is answered by adding the kind. The CLO's `reason` field for the remaining `non_store_types` entries is adopted: the bulk seed must not survive the fix.
2. Six rows: `hcloud_server.{web,inngest,git_data,registry,rehearsal,grok_dogfood}`. **`git_data.baked_credentials_on_host` is NOT absorbed** — it records a different threat (root reading `user_data` from the metadata endpoint, narrowed by the #7772 nftables drop), and folding it in to make an arithmetic total come out even would discard that distinction. It gains a `non_iac_stores` entry instead, which the new forward check requires.
2b. **`hcloud_volume.workspaces` is edited in this PR.** It is `for_each` over both web hosts while `workspaces_luks` is a singleton, so one row covers two devices whose posture differs — web-2 has no encrypted volume at all. Without this edit the new multiplicity check reds PR-2's own CI. `rehearsal` and `grok_dogfood` take exception rows on the `hcloud_volume.rehearsal` precedent (destroyed empty; `count = 0`), never a "no store here" mechanism, which would be an unfalsifiable self-certification.
3. `expires_on` stays a review clock; `reevaluate_when` names the **rebuild window**, because a root disk is encryptable only at rebuild.
4. `check_instance_multiplicity`, defined **per shape**: `for_each` over a `variables.tf` map literal is compared against that literal; `count` over a local, and any module-instantiated block, **fail closed** demanding an explicit `instances` declaration plus a `reevaluate_when` naming the gating variable. A resolver that silently does not apply is the defect this check exists to close — and `grok_dogfood`, the host most likely to be born next, is exactly that shape.
4b. `check_no_orphan_rows`: a row whose address parses to a `store_classes` type must resolve to a real `.tf` block, so deleting a block cannot leave a ghost row and restore slack.
4c. Stagger the six `expires_on` dates; give the two hosts that cannot be rebuilt (`rehearsal`, destroyed each run; `grok_dogfood`, never born) a `reevaluate_when` keyed on **birth**, since a rebuild window that can never occur is unfalsifiable.
5. Amend the four `luks` rows' `does_not_defend`: none names the co-resident root-disk passphrase. Against a full-host seizure or a root-disk image, `hcloud_volume.inngest_redis_luks`'s LUKS defends nothing, and the ledger does not say so.
6. ADR: host root disks are ledgered stores (a change to what the gate's scope *is*).

### PR-3 — record anchors (#8532)

1. `records: ["path:anchor", …]`, sibling to `disclosed_as`, resolved by the same function. Separate field because the predicates are opposite: `disclosed_as` is checked for contradiction of a public claim, `records` for agreement with an internal one.
2. `check_records_resolve` (forward) and `check_record_anchors_named` (reverse, over `RECORD_SURFACES`) so a renamed store cannot leave an orphan anchor. Where the surface list lives is decided by 3c below (R11 reversed an earlier hard-coded-in-script design).
3. Carrier: a **visible, self-describing** clause carrying the mechanism, compared by **equality** rather than by regex over prose — `(encryption-posture ledger: <store id> — at rest: <mechanism>)`. Measured, a regex cannot work here: the register is additive-only, so an amended cell holds superseded text beside current text, and 8 of 10 windows around one store id contain both `LUKS` and `plaintext`. The same clause form goes in `model.c4` as a `//` comment (HTML comments are not valid in that DSL; C4 is an internal record, so the visibility rule that governs the register does not bind there — stated rather than left as an unexplained asymmetry).
3b. **Cardinality: per section, not per file.** A store legitimately appears under several processing activities — measured, `hcloud_volume.git_data` in three, `inngest_redis` in three. A file-unique rule would let only one cell be anchored and leave the rest as ungated prose, which is worse than no anchor. Anchors resolve **within their PA section**, and every occurrence must resolve and agree. File-level uniqueness stays where it belongs, on `disclosed_as`.
3c. `RECORD_SURFACES` moves **into the ledger**, not the script. Hard-coding a repo path makes the check untestable under the synthesized-fixture rule, which would leave it either silently passing on an absent file or unfixturable. Protect the list with a count floor that reports directly, plus a CODEOWNERS pin on the ledger and the register.
4. Assert-only, never generate. No script writes into `knowledge-base/legal/**`.
5. Register amendments the CLO requires: PA-8 §(g) gains an at-rest limb in the register's own "NEGATIVE — encryption at rest is ABSENT" form; PA-13 §(e)/(g) gives `/var/lib/inngest` a posture; PA-27 §(e)'s cross-reference to a nonexistent PA-21/22 SQLite record is fixed; PA-31 §(e) gets the #6894 device amendment it never received; the cross-cutting "Resilience: Hetzner backups" bullet is corrected, since no `hcloud_server` declares `backups`.
6. Regenerate `model.likec4.json` in the same commit, or `c4-model-freshness` reds.

### PR-4 — the web-host root-disk images (operator-gated)

Four images (`398857857, 406654994, 407991378, 411798619`) of server **`123931471`, the web host** (not the inngest host), released only when #6178 closes. Per the operator's decision their retention is decided here, split so the recording lands now and only the deletion waits:

**PR-4a (lands with PR-3, no live mutation):**

1. Determine which are still needed as the #6178 rollback substrate, from the issue and the soak script, and record the finding.
2. Ledger row for the images as a provider-side derivative store, plus an Article 30 retention statement and an Art. 17 reachability note. This discharges PA-36 §(f)'s standing commitment that Hetzner-side retention "must be recorded before the cutover".
3. A dated, empty Art. 5(2) template is committed **as a precondition** of any delete — the repo's own precedent says a record drafted after the act is a justification, drafted before it is a precondition — and the superseded inngest template cannot be reused.

**PR-4b (operator-gated, after #6178):** deletion is a production mutation, proposed with the exact command, run only on per-command authorization, and the template flips to `complete` at that moment. Each image gets an explicit disposition (`delete-now` or `retained-until: <condition>`), because one of the four is already pinned as un-deletable by #6178's own spec.

**The class, not just the instance.** Deleting these images does not reach the live journal that keeps growing on the same disk, nor Better Stack or Sentry (90 days each). The Art. 17 note records the whole class, and states plainly that the on-host journal is the one copy with no bound.

## Files to Edit

**PR-0 (shipped as PR #8617):** `apps/web-platform/server/email-triage/outbound-compliance.ts` (the two leaking interpolations, per R6), a leaf `server/pii-redact.ts` wired into `observability.ts`, the `logger.ts` `logMethod` hook and `sentry-scrub.ts` (the class fix; not a pino serializer, per R8), `sensitive-keys.ts`, the offline gate notification and aborted-turn summary for outbound-email tools, and the three published legal documents scoped by CLO ruling. Tests under `apps/web-platform/test/server/`.

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
**Anchor.** `RECORD_SURFACES` lives in the ledger (3c, per R11), protected by a count floor that reports directly and a CODEOWNERS pin, so removing a surface is both a reviewed ledger diff and a floor failure.

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

- [ ] **AC-0a** A sentinel test over `OutboundComplianceError` messages asserts no message contains any substring of the input address. A directory-scoped grep is not the gate: it is blind to `notifications.ts` and to any future rename.
- [ ] **AC-0b** A test drives a refused send through the real emitter and asserts the emitted record contains no substring of the input address; mutating the fix back out reds it.
- [ ] **AC-0c-i** The privacy-policy sentence (anchored on its text, not a line number) is unchanged and is true for every send **after PR-0 deploys** — merging does not make it true, so this is verified in production.
- [ ] **AC-0c-ii** Pre-fix copies already in journald, Better Stack and Sentry are recorded as an Art. 17 reachability finding, in the same place as the images.
- [ ] **AC-1a** Deleting any `stores[]` row whose id is in `non_iac_stores` fails the sweep. (Today it passes — this is the regression being closed.)
- [ ] **AC-1b** A `records`/`disclosed_as` anchor occurring twice in its file fails, with a message distinct from the not-found case.
- [ ] **AC-1c** #8527 is closed: a `luks` row whose disclosure denies encryption fails.
- [ ] **AC-2a** `python3 scripts/lint-encryption-posture.py --repo-sweep` reports **25** stores (the git_data credentials row is kept and catalogued rather than absorbed; re-measure at work time), 0 unledgered, 0 failing checks, and `hcloud_server` no longer appears in `non_store_types`. Derivation, to be re-run at work time rather than carried from here: today 19 rows against a floor of 18 (`tf_store_count` 12 + `non_iac_stores` 6); PR-2 renames one row rather than adding it (19 − 1 + 6 = 24) and raises `tf_store_count` to 18, so the floor becomes 18 + 6 = 24. Exact, no slack. If the measured numbers differ at work time, the measurement wins and this AC is amended.
- [ ] **AC-2b** `hcloud_volume.workspaces` carries an `instances` declaration, and adding a key to `var.web_hosts` without touching the ledger fails the sweep.
- [ ] **AC-2c** Adding a key to `var.web_hosts` without touching the ledger fails the sweep.
- [ ] **AC-2d** Each of the four `luks` rows' `does_not_defend` names where its passphrase lives.
- [ ] **AC-3a** Every carrier clause in a record surface names a live `stores[].store` and its `at rest:` token equals that row's mechanism; each resolves uniquely **within its PA section**. Not once per file — measured, the register states one store's posture under up to three activities.
- [ ] **AC-3b** The five CLO register amendments are present, each with a dated `**[YYYY-MM-DD AMENDMENT (#N): …]**` marker.
- [ ] **AC-3c** `bash plugins/soleur/test/c4-model-freshness.test.sh` passes with the regenerated JSON committed.
- [ ] **AC-4a** The four image ids are ledgered as a provider-side derivative store with a retention statement and an Art. 17 reachability note covering the whole class (images, the live journals on ~~five~~ three hosts — web-1, web-2, registry; the inngest and git-data hosts set no persistent journal (measured 2026-09-23, CLO) — Better Stack, Sentry).
- [ ] **AC-4c** Each image carries a disposition: `delete-now` or `retained-until: <condition>`, with the retention expiry recorded. A PR that deletes nothing and states nothing does not satisfy this.
- [ ] **AC-4b** No image is deleted without the operator's per-command authorization and an Art. 5(2) record written at the time.
- [ ] **AC-G** No PR in this stack edits `apps/web-platform/infra/**`: `git diff --name-only origin/main...HEAD | grep -c '^apps/web-platform/infra/'` is 0.

## Test Scenarios

Given the ledger as committed / When a row whose id is catalogued in `non_iac_stores` is deleted / Then the sweep exits 1 naming the id.
Given a register fixture where a store id appears twice / When a `records` anchor names it / Then the sweep exits 1 with the ambiguity message.
Given a `for_each` block with two instances / When the row declares one / Then the sweep exits 1.
Given a refused outbound send with an invalid address / When the error is mirrored / Then no substring of the address appears in the emitted record.

## Plan Review Revisions

Five agents reviewed this plan (simplicity per mechanism, Kieran, DHH, architecture, spec-flow). Every measurement below was re-derived in the worktree.

| # | Finding | Revision |
|---|---|---|
| R1 | **The gate cannot block.** `encryption-posture` is absent from `required-checks.txt`; a PR merges with it red. Three reviewers reached this independently. My Research Insights had claimed the opposite | Corrected. Property 2 is **advisory until #6907**, stated as such. The cheapest arming route — a blocking sweep against the real ledger inside the already-required `test` check — becomes step 1 of the work, ahead of PR-1 |
| R2 | The agreement predicate is unbuildable: the register's own mandated "encryption at rest is ABSENT" form matches `LUKS\|encrypt`, and 8 of 10 measured windows carry both polarities | Carrier is self-describing and compared by equality; no regex over prose |
| R3 | File-level uniqueness is incompatible with a per-activity Art. 30 record (one store, up to three PAs) | Anchors resolve per PA section; uniqueness stays on `disclosed_as` |
| R4 | PR-2 as scoped lands red on its own CI: `hcloud_volume.workspaces` needs the new declaration and was not in the edit list | Added to PR-2 |
| R5 | The `reason` per `non_store_types` entry crashes `check_resource_partition` (`set()` over dicts) and satisfies no property | Cut |
| R6 | PR-0's site list was wrong: `${name}` is a header field name; `${domain}` and `${local}` are bounded to our own domains and a fixed role set. Two sites leak, not four | Corrected to `${addr}` and `${to}` |
| R7 | Two sinks were missing: Sentry (the issue title, unscrubbed — `sentry-scrub.ts` never touches exception values) and Better Stack (Vector's email regex is skipped for structured pino lines) | Both named; the fix stays at the throw site because it closes all three |
| R8 | A pino `serializers.err` cannot deliver the class fix: `mirrorToSentry` runs before the render stage, and five marker loggers do not inherit from `logger.ts` | Class fix moved to `sanitizeLogMessage` plus an `err` twin in `reportSilentFallback` |
| R9 | Five `luks` rows, not four (`hcloud_volume.registry`), and only one carries a resolvable anchor | Corrected; regression set is one live row plus fixtures |
| R10 | The floor's exactness was a coincidence; a future non-Terraform row re-opens the slack | Added the forward check: every row resolves to a `.tf` address or a catalogue entry |
| R11 | Hard-coding `RECORD_SURFACES` breaks the synthesized-fixture rule, leaving the guard untestable. This reverses the CTO's ruling on the fixture argument, which the ruling did not consider | Moved into the ledger with a count floor and a CODEOWNERS pin |
| R12 | `check_instance_multiplicity` had no defined behaviour for `count`-over-a-local or module-instantiated blocks — including `grok_dogfood`, the host most likely to be born next | Fail closed per shape |
| R13 | PR-4 could ship with nothing deleted and both ACs green; and its Art. 5(2) record was prescribed after the act, against the repo's own precedent | Split into 4a (records, lands now) and 4b (operator-gated deletion); template committed first; per-image disposition required |
| R14 | Deleting the images leaves the live journal, which is the same content class with no bound | The Art. 17 note covers the class |
| R15 | The account-deletion dialog promises "all your data… permanently deleted", which is currently false | Recorded as a finding for the CPO sign-off the frontmatter already requires; not silently absorbed |
| R16 | Five PRs is more structure than the work needs; PR-1 → PR-2 is not a real dependency | Collapsed: #6907 first, then one ledger PR (old 1+2+3+4a), with PR-0 shipping independently and 4b operator-gated |

**Kept against a reviewer's recommendation.** `check_instance_multiplicity` survives DHH's cut: he argued the `for_each` instances have identical posture by construction, but `workspaces_luks` is a singleton while `workspaces` is `for_each`, so web-2 has no encrypted volume — the divergence is live today.

## CPO Sign-off (2026-09-23)

**Verdict: SIGN-OFF WITH CONDITIONS.** The plan reduces user harm and adds no new store. Conditions and their disposition:

| # | Condition | Disposition |
|---|---|---|
| C1 | R15, the account-deletion dialog, is a user-facing misrepresentation. Reword the copy, do not widen deletion; CLO review of copy and policy required; must land before this ledger PR is marked ready | #8095 widened, raised to P1, moved to Phase 4, CPO's drafted copy attached |
| C2 | "Files to Edit" and Guard 3's Anchor contradicted R6, R8 and R11 | Corrected in place above |
| C3 | Purge the refusal-path copies from Sentry, don't only record them (AC-0c-ii) | Owed after PR #8617 merges; recorded in its PIR and in Article 30 PA-28 §(c) |
| C4 | PR-0 ships first, and AC-0c-i is checked automatically after deploy | PR #8617 is PR-0; the production check is on its post-merge list |
| C5 | Every retained root-disk image needs a real expiry date, not "until #6178 closes" | Binding on PR-4a (AC-4c) |

**Correction to R8 (architecture review of PR #8617, measured).** The five marker loggers (`claude-cost`, `compound-promote`, `cron-liveness`, `cron-filing-deny`, `cert-reissue`) log no `err`, so they were never the reason a pino serializer could not deliver the class fix. The reason that holds is that `mirrorToSentry` runs in the `logMethod` hook before pino renders. PR #8617 puts the redaction in that hook.

**PR-0 outcome that changes this plan's premise.** The CLO ruled that "the plaintext recipient address is never stored" could not stand, even with the code fixed: the address and body also persist in the drafting agent conversation (#3418). The published sentences are now scoped to "our outbound-email records". The operator's "keep the sentence" is honoured in form, not in scope.
