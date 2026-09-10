---
title: "fix: inngest probe_schema=8 — a satisfiable mount pin, registry evidence, and a hash-tag-safe key histogram"
date: 2026-09-10
slug: fix-inngest-probe-schema-8-mount-devid
branch: feat-one-shot-8017-8015-8013-probe-schema-8
lane: cross-domain
type: bug
issue: 8017
refs: 8017, 8015, 8013   # Ref, never Closes — see ## Delivery
priority: p0
domain: engineering
brand_survival_threshold: none
---

## Overview

`inngest_host_dark_gate` is the twenty-predicate gate (ADR-199) that authorizes the destructive
`inngest-volume-recut` dispatch. One of its predicates — the one ADR-199 calls the bridge from
"a Redis process is empty" to "the block device being destroyed is empty" — compares the probe's
`data_mount_src` field against `/dev/disk/by-id/scsi-0HC_Volume_<id>`. The kernel records the
canonical device name in `/proc/self/mountinfo`, never the by-id symlink, so that arm is
unreachable: the only value it can ever match is `/dev/mapper/inngest-redis`, a device that does
not exist until the recut the gate is supposed to authorize. The gate is circular and #7695's
capability is inert.

This plan makes that predicate satisfiable by emitting a device identity the gate can compare —
a `data_mount_devid=` field derived on the host by resolving the Hetzner by-id namespace against
what is actually mounted — and bumps the probe's schema from 7 to 8. Because the emitter is baked
into an OCI image and reaches the host only through a digest literal in `user_data`, one schema
bump costs one image build and one host replace. Two other changes are therefore folded into the
same bump so a single replace clears all three:

- **#8015** — the #7674 serving probe grants PASS on `server_active=active` + `http_code=200`,
  which a diagnostic boot produces while adopting no function registry. The row gains a
  registry-evidence field and the probe's positive discriminator requires it.
- **#8013** — the key-name histogram reduces each key to its first two colon segments, which
  passes a Redis cluster hash tag's contents through verbatim, shipping an internal estate ULID
  to the logs sink. Hash tags collapse to their pre-colon prefix before the reduction.

**Explicitly out of scope, and stated as a constraint the implementation must respect: this work
does not dispatch `inngest-volume-recut` or any other destructive `apply_target`. The deliverable
is the code change plus the schema bump that make the mount predicate satisfiable. The one
authorized FLUSHALL is UNSPENT and remains unspent — nothing here writes to Redis.**

## Live state this plan is designed against

Read 2026-09-09 22:45Z and carried into the design; every value below is a premise, not a claim
this plan re-establishes:

| Fact | Value |
|---|---|
| Dedicated host id | 165360464 |
| `boot_id` | `906c015b-b648-400f-93ea-ced42e048ed9` |
| `INNGEST_DIAGNOSTIC_BOOT` | `1` |
| `INNGEST_CUTOVER_FLIP` | `aborted` |
| `flush_latched` | `false` |
| `redis_keys` | 16 |
| Redis AOF volume id | 106261946 (ext4, intact) |
| Authorized FLUSHALL | UNSPENT |
| Pinned image | `v1.1.31@sha256:876b5996ecf536c8642da487e3468870453a59f562e04314c5e682b82b9c72b7` |

Two consequences the plan leans on. First, `redis_keys=16` means G13 refuses today regardless of
this change, so no reachable path exists from this work to a destroy — the schema bump strictly
cannot authorize anything that was not already blocked. Second, `INNGEST_DIAGNOSTIC_BOOT=1` means
G20 also refuses today; #8015's defect is therefore live in the #7674 probe (which the daily
sweeper and the tracker's closure depend on) rather than in the gate's current verdict.

## Research Insights

**Load-bearing paths.** Emitter `apps/web-platform/infra/inngest-bootstrap.sh` (`probe_schema=7`;
the `dedicated)` arm's `findmnt` capture; the histogram awk; the two emit sites; the probe unit's
`TimeoutStartSec=120` and its `Budget (#7695)` comment). Gate library
`tests/scripts/lib/inngest-host-dark-gate.sh` (`expected_schema="7"` default binding; `_ihdg_field`,
which refuses any message with a duplicated field name or an embedded newline; the G14 comparison).
Gate battery `tests/scripts/test-inngest-host-dark-gate.sh` (the `bs_line`/`msg`/`mk_rows` fixture
builders; `PROBE_FIELDS` in emit order; the `mutate` helper with its four independent failure
modes; two floors). Emitter battery `apps/web-platform/infra/inngest.test.sh` (extracts the probe
heredoc and runs it under `sh`; PATH stubs for `logger`, `curl`, `systemctl`, `findmnt`, `du`,
`redis-cli`). Serving probe `scripts/followthroughs/inngest-host-not-serving-7674.sh`. Registry
predicate `apps/web-platform/infra/inngest-cutover-flip.sh` › `verify_serving()`. Pin sites and
their guards `apps/web-platform/infra/cloud-init-inngest.yml`, `.../cloud-init.yml`,
`.../cloud-init-inngest-bootstrap.test.sh`. Transport `apps/web-platform/infra/vector.toml`
Source 4. Sole gate caller `.github/workflows/apply-web-platform-infra.yml`.

**Institutional learnings that apply directly.**
`knowledge-base/project/learnings/2026-09-02-i-built-a-host-discriminator-out-of-an-absence-and-fixtured-the-absence.md`
— a discriminator built from an absence discriminates nothing, and a fixture built in a sandbox
that also lacks the thing will agree with it; assert the value that must never appear, not the
expected token; a floor that dispatches through the counter it protects is not a floor. That is
the shape of this whole change: the mount predicate was never exercised because the only fixture
that could have exercised it carried a string the emitter cannot produce.
`knowledge-base/project/learnings/2026-09-03-the-gate-cleared-the-destroy-and-never-graded-the-create.md`
— a predicate that cannot distinguish two states is not a predicate however it reads;
anti-vacuity machinery is itself vacuity-prone one level up; a drop-one battery asserting only
refusals is blind to the too-aggressive direction, which is why every guard here carries a
must-PASS non-canonical input. The #8005 precedent lives in `inngest.test.sh`'s schema-7 block: an
invented CLI flag cost four host replaces and no stub could ever catch it, so the surviving check
is a source assertion — the same instrument this change needs for its new invocations.

**Conventions carried in.** `hr-observability-as-plan-quality-gate` and
`hr-observability-layer-citation` (the Observability block, with each failure mode routed to a
named layer and a no-SSH discoverability command); `hr-type-widening-cross-consumer-grep` (the
consumer enumeration behind the Files-to-Edit list); `cq-write-failing-tests-before` (Phase 1 is
RED); `cq-assert-anchor-not-bare-token` (every acceptance criterion anchors on a value shape or a
call form, never on a token a comment could also satisfy); `hr-prod-host-config-change-immutable-redeploy`
(the change reaches the host by image bump and server replace, never by an in-place edit);
`hr-verify-repo-capability-claim-before-assert` (every "X is not available" claim in this plan was
grepped before it was written — see the #8015 option-1 row in the reconciliation table).

**Reconciling `cq-test-fixtures-synthesized-only` against the real-output-shape requirement.**
#8017 closes by requiring a fixture carrying a real `findmnt -no SOURCE` shape for a plain block
device. No conflict: the rule is path-scoped to `__goldens__/**`, `**/*.snap` and
`apps/web-platform/test/fixtures/**`, none of which is a shell battery here; its forbidden classes
are secrets and personal data, which a kernel device node is not; and precedent already exists on
this exact subject — `inngest.test.sh` stubs `findmnt` to echo `/dev/sdb` and asserts
`data_mount_src=/dev/sdb`. The requirement is an instance of `cq-assert-anchor-not-bare-token`, not
an exception to anything: a synthesized `/dev/fake` would make the arm vacuous.

**Live telemetry read during planning, with the command the plan then prescribes.** Running the
`discoverability_test` form against the warehouse returned the dedicated host's current row:
`http_code=200 server_active=active vector_active=inactive redis_active=active boot_id=906c015b-…
image_ref=10.0.1.30:5000/jikig-ai/soleur-inngest-bootstrap:v1.1.31@sha256:876b5996… instance_id=hetzner-165360464
cutover_flag=aborted probe_schema=7 … redis_keys=16 data_mount_src=/dev/sdb`. Three things follow.

First, the host is confirmed to be running the currently-pinned image, so a replace against a new
pin will genuinely deliver the new emitter — the premise the whole sequencing rests on.

Second, **the identifier isolation in the probe command is load-bearing, and the first form written
here was wrong.** A bare `--grep SOLEUR_INNGEST_SERVER_PROBE` matches every warehouse row
*containing* that string, including rows that merely quote it inside another document; the measured
output carried trailing markdown fragments where a real field value should have ended. The
Observability section's command is the corrected form, and four further corrections to it are
recorded there.

Third, and not a blocker but worth stating so nobody discovers it mid-implementation: **the web host
is still emitting `probe_schema=4`** (`instance_id=hetzner-123931471`, `host_role=web`,
`image_ref=unknown`, uptime ≈176 days). It is already three schemas behind, so this bump neither
creates nor worsens that divergence. Every consumer that matters filters on `host_role=dedicated`
plus the two identity fields, so a stale web row cannot reach the gate or the #7674 probe. No
web-host action is a precondition for this work.

**Measured baselines, run on this branch before any edit** — a suite that has never executed is not
evidence, and its first run is a measurement:

- `bash tests/scripts/test-inngest-host-dark-gate.sh` → `118 passed, 0 failed`;
  `drop-one floor: 22 distinct predicates covered across 23 cases (floor 21)`;
  `anti-vacuity floor: 118 assertions ran (floor 118)`. **The assertion floor has zero slack** —
  exactly at the current count — so every case this plan adds must raise `_FLOOR` in the same edit;
  the distinct-predicate floor has exactly one of slack.
- `bash apps/web-platform/infra/inngest.test.sh` → `324/324 passed, 0 failed` against
  `INNGEST_MIN_ASSERTIONS=305`, i.e. 19 of slack there.
- `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` → `163/163 passed`,
  `BOOTSTRAP_SUITE_OK unconditional=123 floor=123 total=163`. That file carries **five** separate
  anti-vacuity inventories, each an exact count any added assertion must bump: Guard 1 `expected
  50`, Guard A `expected 11`, Guard B `expected 9`, Guard D `expected 11`, Row 7 `expected 7`.
- `bash apps/web-platform/infra/inngest-cutover-flip.test.sh` → `147 passed, 0 failed`.
- `bash tests/scripts/test-inngest-volume-recut-gate.sh` → `53 passed, 0 failed`, floor 53 — another
  zero-slack floor, on the sibling destroy-guard this change does not touch.
- `bash scripts/test-all.sh --enumerate all` → the three `apps/web-platform/infra/*.test.sh` suites
  above are **not** in the enumeration. They run only from `infra-validation.yml`'s advisory
  `deploy-script-tests` job, which is why they carry their own acceptance criteria.

**Related issues.** #8017 (P0, the mount pin), #8015 (P1, G18 vacuity), #8013 (chore, the ULID
leak) — all OPEN, all closed by this work. #7695 (the recut capability this unblocks), #7674 (the
tracker whose probe #8015 fixes), #6894 (the encryption posture), #7777 (the flush latch, not
addressed here) — all OPEN. #7978, #8001, #8005 (schemas 4, 6, 7) — MERGED, and #8005 is the
precedent this plan's testing discipline is built on.

The Premise Validation note, the Property List and the Cut List are carried in full in their own
sections below rather than duplicated here.

## Research Reconciliation — issue claims vs. codebase

| Claim (source) | Reality (measured) | Plan response |
|---|---|---|
| #8017: G14 compares `data_mount_src` against a by-id path (`inngest-host-dark-gate.sh`) | Confirmed. `expected_dev="/dev/disk/by-id/scsi-0HC_Volume_${expected_volume_id}"` then `if [[ "$data_mount_src" != "$expected_dev" && "$data_mount_src" != "/dev/mapper/inngest-redis" ]]` | Fix as described |
| #8017: `findmnt` never reports a by-id path | Confirmed against the real binary here (util-linux 2.41.3): `findmnt -no SOURCE /` → `/dev/nvme0n1p3` while three by-id symlinks for that exact device exist | Adopt option 2 (emit a resolved identity) |
| #8017 option 2 suggests `findmnt -no MAJ:MIN` | **Rejected on two measured grounds.** (a) The output is space-padded: `od -c` shows `2 5 9 : 3 SPACE SPACE \n`, and the probe row is whitespace-token parsed by `_ihdg_field`, so an untrimmed value splits the row and the gate refuses it as a duplicate/short field. (b) `259:3` carries no relation to volume id `106261946` — the gate cannot pin the volume from a MAJ:MIN pair | Emit the resolved **by-id alias**, not MAJ:MIN |
| "The gate's test battery uses synthesized by-id strings, which no live emitter produces" | Confirmed for the **gate** battery. The **emitter** battery already stubs the real shape: `apps/web-platform/infra/inngest.test.sh` writes a `findmnt` stub that echoes `/dev/sdb` and asserts `grep -qE 'data_mount_src=/dev/sdb( \|$)'` | The two sides were fixtured against different shapes and nothing compared them. The plan adds the comparison, not just a new fixture |
| #8015: emitting `INNGEST_DIAGNOSTIC_BOOT` "would also let G20 read the row rather than taking a synchronous Doppler read" | The synchronous read is **fresher** than a ≤90-minute-old row and ADR-199 chose it deliberately as one of four dispatch-time re-reads | **Cut.** G20 keeps its synchronous read. See Cut List |
| #8015 option 1: "require registry evidence — needs no host replace" | Not implementable off-host today. There is no recurring registry-count signal in the warehouse: `inngest-registry-probe.sh` logs `registry probe: empty=… function_count=…` from its `main()`, but the only timer that runs is `inngest-consumer-probe.timer`, and the consumer probe **sources** that script and calls `fetch_functions()` only — which emits no markers. Its tag *is* allowlisted in `vector.toml` Source 4, so the channel exists and is unused | The registry evidence must be a probe field. Confirmed the replace is genuinely needed |
| #8013: the two-segment reduction passes the ULID through | Reproduced exactly. Running the emitter's own awk over a fixture in the real brace shape yields `?estate:01KYADCPBNEE10PYEYCPCJ08YA?:*=2` — byte-for-byte the leak the issue quotes | Fix as described |
| #8013: "shipping this needs an image bump, a re-pin of the four sites, and a host replace" | Confirmed and mechanically enforced. Guard A in `cloud-init-inngest-bootstrap.test.sh` compares every baked carrier against `git show <pinned tag>:<path>`, so editing `inngest-bootstrap.sh` without moving the pin reddens CI | The image bump is not optional; it is the first phase |
| #7674, #7695, #6894, #7777 all OPEN; #7978, #8001, #8005 MERGED | Verified via `gh issue view` | Premises hold |
| The gate battery's `G14` label is unique | **False — `G14` is overloaded.** The predicate index lists `G14` twice: the `redis_keys`/`redis_key_patterns` coherence check (verdict `unreadable`) and the mount check (verdict `mount_mismatch`). The battery uses the label for both AND writes `rows-g14.json` / `rows-g14b.json` twice, so `mutate G14` silently consumes the second (mount) content | Rename the mount predicate's cases and fixtures so the two are distinguishable; a case inserted between them today silently repoints the mutation row |
| The emitter runs under bash in its own battery | **False.** `inngest.test.sh` extracts the probe's heredoc body with `awk` and executes it with `sh "$PROBE_BODY"`. The probe is POSIX sh | All new emitter code must be POSIX sh: no `[[ ]]`, no arrays, no `local` beyond what the file already uses |
| Stubs on `PATH` can fixture the new resolution | **False for the parts that read paths rather than binaries.** A `/dev/disk/by-id` glob and a `/sys/block/.../slaves` read are filesystem paths, not `PATH` lookups | Both need an env seam in the emitter, following the `PROBE_DATA_MOUNT` / `PROBE_LATCH_DIR` convention already in the file. Without a seam the guard has no fixture and the matrix cannot be written |
| The suites that gate this change are required CI checks | **False for two of three.** `infra-validation.yml`'s `deploy-script-tests` job — which runs both `inngest.test.sh` and `cloud-init-inngest-bootstrap.test.sh` (Guards A and B) — is documented in-file as ADVISORY; the required job is `infra-validate-required`. Only the dark-gate suite reaches a required check, via `ci.yml`'s sharded `test-scripts` → `scripts/test-all.sh scripts` | A partial pin bump would not block merge on a required check. The acceptance criteria must name those two suites explicitly rather than relying on CI redness |
| `inngest-volume-recut` is a real `apply_target` | Confirmed: it is one of 16 choices on `apply-web-platform-infra.yml`, requires `confirm=RECUT-INNGEST-VOLUME`, `expected_inngest_volume_id`, and `environment: inngest-cutover` review | Named only to state that this plan does not dispatch it |

## Premise Validation (Phase 0.6)

Every reference the brief cites was probed. Three issues (#8017 P0, #8015 P1, #8013 chore) are
OPEN and none is closed by a merged PR. Every cited path exists and every cited code anchor
resolves to the quoted text. The
mechanism (a `probe_schema` bump plus a new emitted field) was grepped against the ADR corpus:
ADR-199 governs the gate's contract and does not version-pin the schema number, so a 7→8 bump is
compatible with it; ADR-142 carries a stale `probe_schema=3` narrative reference. Neither records
this mechanism in a rejected-alternatives table. Nothing was stale.

## Property List and Cut List (Phase 0.6b)

**Properties this work must buy** (observable outcomes, not mechanisms):

- P1. The dark gate's mount predicate can be satisfied by a host in its pre-recut state, and
  refuses a host whose `/mnt/data` is not on the volume the dispatch named.
- P2. The gate's satisfaction of P1 is pinned to the *volume id the dispatch names*, not merely
  to "some device" — a wrong volume must still refuse.
- P3. A dispatch against a host serving no function registry cannot obtain a PASS from the #7674
  probe, and therefore cannot clear G18.
- P4. The key-name histogram that reaches the logs sink carries key *categories* and no
  identifier, for the brace shape production actually uses.
- P5. Every consumer of the probe row agrees about which schema it is reading, so a bump cannot
  leave one side silently grading a shape it has never seen.
- P6. Each of P1–P4 is exercised by a test that can be driven RED by a realistic edit.

**Cut List** — mechanisms named in the ask that buy no property, or one already covered:

| Mechanism | Property it would buy | Why cut |
|---|---|---|
| `data_mount_devid=` as `findmnt -no MAJ:MIN` | P2 | Buys none of it: `259:3` cannot be compared to volume id `106261946`. Also space-padded (measured with `od -c`), which corrupts the whitespace-tokenised row |
| Emit `diagnostic_boot=` so G20 reads it from the row | none new | G20 already reads `INNGEST_DIAGNOSTIC_BOOT` synchronously at dispatch time (`--diagnostic-boot`), which is strictly fresher than a row up to 90 minutes old. ADR-199 chose the synchronous form deliberately. Emitting a row copy would add a second, staler source for a value that already has an authoritative one — the "two signals that can disagree, and every disagreement resolves fail-open" shape |
| A new off-host registry probe timer on the web host | P3 | Would work, and is cheaper in isolation (no image bump). Cut for a mechanical reason rather than a doctrinal one: the registry count is a per-host, per-moment fact of the same kind as `server_active` and `http_code`, and the #7674 probe already refuses to assemble those two out of different moments. A count emitted by a *different host* under a *different marker* at a *different time* cannot be conjoined with them without recreating exactly the composition that probe's host-isolation section spends four paragraphs rejecting. Since a replace is already being spent for #8017, same-row evidence is nearly free |
| A new ADR for the gate's mount semantics | — | **Not cut.** See `## Architecture Decision (ADR/C4)` |

## Hypotheses

The Phase 1.4 network-outage gate fired mechanically on the substring `unreachable` in the brief.
It is recorded rather than skipped, because a skipped gate and a passed gate are indistinguishable
afterwards — but the subject is an unreachable *branch* in a bash comparison, not an unreachable
host, and no connectivity symptom is in scope.

The L3 and L7 layers are therefore not merely inapplicable but positively contradicted: the host's
telemetry path is demonstrably up, since this plan read a live probe row from host 165360464 out of
the Better Stack warehouse during planning. A row that arrived is proof the path works. No sshd,
fail2ban or service-drift hypothesis is proposed, so the checklist's L3→L7 ordering rule is
satisfied rather than violated.

The one hypothesis that is in scope is service-layer and is the defect itself: `findmnt` reads
`/proc/self/mountinfo`, which records the canonical kernel device name. Reproduced against the real
binary (util-linux 2.41.3) with by-id symlinks present for the same device.

### Network-Outage Deep-Dive

Required by the checklist whenever the gate fires. Layer-by-layer verification status:

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall allow-list | **Not verified, and not required** | No connectivity symptom is in scope and this plan opens no session to the host. The `hcloud firewall describe` / egress-IP diff the checklist prescribes would answer a question nobody is asking here |
| L3 DNS / routing | **Verified UP, incidentally** | The planning session read a live probe row from host 165360464 out of the Better Stack warehouse — `boot_id=906c015b-…`, `probe_schema=7`, `redis_keys=16`. A row that arrived is end-to-end proof of the host → Vector → warehouse path |
| L7 TLS / proxy | **Not applicable** | No HTTPS symptom. The one new network call this plan adds is loopback `http://127.0.0.1:8288/v0/gql`, which crosses no proxy and terminates on the same host |
| L7 application | **This is the whole defect** | A string comparison against a path form `/proc/self/mountinfo` cannot contain. Reproduced against the real binary |

**Gap that needs closing before implementation: none at these layers.** The plan proposes no sshd,
fail2ban or service-drift remedy, so the L3→L7 ordering rule is satisfied rather than deferred. The
one residual network question — whether the probe's new loopback query can reach `:8288` on a host
whose `--sdk-url` points at a closed port — is answered by the field's own design: a transport
failure renders `__UNREADABLE__`, which refuses, rather than `0`, which would read as a measured
empty registry.

## Downtime & Cutover

The Phase 4.55 gate fires. Two operations in this plan's blast radius take a serving surface
offline, and the default must be the zero-downtime path rather than downtime-as-baseline.

**The offline-inducing operation, named exactly.** `hcloud_server.inngest` carries no
`lifecycle.ignore_changes = [user_data]` — deliberately, so that a cloud-init edit forces a replace
rather than drifting silently. The four pin-site edits in Phase 3 are `user_data` edits for that
resource. The surface affected is the Inngest scheduler, which under ADR-100 is a **singleton
control plane**: there is one, and replacing it destroys before it creates.

**What this pull request itself does: nothing offline.** The merge apply cannot fire the replace,
because `apply-web-platform-infra.yml`'s `-target=` allow-list contains no `hcloud_server.*`. So
the change lands as configuration and waits. That is the zero-downtime path for the PR, and it is
not an accident of the allow-list — it is the interlock ADR-100's maintenance-window discipline
relies on.

**What the later delivery does, and why blue-green is unavailable here.** Delivering the new image
means `apply_target=inngest-host-replace`, which is a destroy-and-recreate that preserves the AOF
volume by omission. Blue-green — provision the replacement alongside, drain, cut over, retire the
old — is the pattern this repo uses for `hcloud_server.web` (#5887's web-2 cutover) and is not
available for this host for a structural reason worth stating rather than assuming: the scheduler's
durable state is a **single attached volume**, and a Hetzner volume attaches to one server at a
time. A second scheduler cannot be born holding the same store, and two schedulers holding
*different* stores is the double-fire state ADR-146 and the flip guard exist to prevent. So the
residual downtime is accepted, not defaulted to, and it is bounded by:

- **Scope:** the Inngest scheduler only. The web platform, the Concierge surface and the registry
  are untouched; nothing a person interacts with goes offline.
- **Effect:** queued work is durable in the AOF on the preserved volume, so the window defers
  execution rather than losing it. The cron-outage window is ADR-100's known cost for this host and
  is why the replace is maintenance-window-gated in the first place.
- **Duration:** one cloud-init boot, the same window every prior `inngest-host-replace` has taken.
- **Verification per stage:** the boot emits `SOLEUR_INNGEST_BOOT_STAGE` markers, and the closing
  condition in `## Delivery` is a probe row on a **new `boot_id`** — so "did it come back, and did
  it come back correct" is one observation rather than two guesses.
- **Rollback:** none, and `## Risks & Mitigations` says so plainly rather than implying one exists.
  Roll-forward under a reserved next tag is the exit.

**And the sequencing consequence that is easy to miss.** From merge onward, the pinned `user_data`
differs from what the running host booted, so **any** later `inngest-host` or `inngest-host-replace`
dispatch — for any unrelated reason, by anyone — delivers this change and takes that window. That is
stated here and in `## Sequencing` so the next dispatch is a decision rather than a surprise.

The database-lock class and the deploy/router class do not apply: this plan contains no migration,
no DDL, and no change to any request path.

## Design

### D1 — `data_mount_devid=`: what the emitter measures

The gate runs off-host and cannot resolve the host's `/dev`. The host can. So the host resolves,
and emits an identity the gate can compare to the value it already has (the dispatch's
`expected_inngest_volume_id`).

**Where the block goes, and why the placement is a correctness question.** Immediately after
`[ -n "$data_mount_src" ] || data_mount_src=__UNREADABLE__`, and **before** the inner
`case "$data_mount_src"`. That inner case's `__UNREADABLE__` branch binds only three fields and
falls through everything else — which is how `redis_key_patterns` and `redis_expires` legitimately
stay at their `n/a` default on that path today. A resolution block placed inside the `*)` sub-arm
would leave `data_mount_devid=n/a` on a `host_role=dedicated` row: the web-arm sentinel on a
dedicated row, which G14 would then refuse as a mount mismatch while pointing at the volume
attachment. The block is placed once, above the case, and both fields are bound on every dedicated
path.

The emitter then:

1. Resolves `data_mount_src` to a **base block device** with `lsblk -s`, whose inverse-tree walk
   descends through a device-mapper node to its backing device *and* through a partition to its
   parent disk, in one flag. `lsblk` is util-linux, the same package as the `findmnt` this probe
   already calls, and is already used against a Hetzner host in this repo
   (`cloud-init-registry.yml` runs `lsblk -bno SIZE /dev/mapper/registry`). Critically it is a
   **binary**, so it is stubbed on `PATH` exactly like the existing `findmnt` stub — no new fixture
   machinery, and one env seam instead of two.
2. Reverse-maps that base device within the **Hetzner namespace only** —
   `/dev/disk/by-id/scsi-0HC_Volume_*` — by resolving each alias and comparing. Constraining the
   glob to that namespace is load-bearing: measured here, a whole-`by-id` walk returns *three*
   aliases for one device (model, eui, and partition forms), so an unconstrained reverse-map is
   multi-valued and would need an arbitrary tiebreak.
3. Emits the alias **basename** — `data_mount_devid=scsi-0HC_Volume_106261946` — or one of the
   sentinels below. Never a path, so the value cannot be confused with `data_mount_src`.
4. Emits `data_mount_base=<kernel name>` from the same `lsblk` call, at no extra cost and inside
   the same timeout. This is not decoration: without it, `__UNREADABLE__` on `data_mount_devid` is a
   **three-way** collision — nothing was mounted, the resolution is broken, or the volume is not
   attached — and those have different remedies. With it the row separates them:
   `src=__UNREADABLE__ base=n/a` is no mount, `src=/dev/sdb base=__UNREADABLE__` is a broken
   resolution, and a resolved base with `devid=__NOMATCH__` is the wrong device.

| Value | Meaning |
|---|---|
| `scsi-0HC_Volume_<id>` | the mounted filesystem's backing device is that Hetzner volume |
| `__NOMATCH__` | the base device resolved, but no `scsi-0HC_Volume_*` alias points at it — `/mnt/data` is mounted from a device that is not a Hetzner volume |
| `__AMBIGUOUS__` | more than one Hetzner alias resolved to the same base device |
| `__UNREADABLE__` | the resolution failed, or `data_mount_src` was already `__UNREADABLE__` |
| `n/a` | the web host arm, as every other store field does |

**Correcting a claim an earlier draft of this plan made about `__NOMATCH__`.** It is *not* "the
root-disk fallback this predicate exists to catch". The emitter runs
`findmnt -no SOURCE "$data_mount"` **without `-T`**, so when the `nofail` mount is skipped and
`/mnt/data` is a plain directory on the root filesystem, `findmnt` prints nothing and the next line
binds `__UNREADABLE__` — never a root-disk device path. The root-disk case therefore reaches G14 as
`__UNREADABLE__`, which refuses; `__NOMATCH__` covers the narrower case of a mount from some other
real device. Both refuse, so the gate's behaviour is right either way, but the narrative had to be
corrected before it was written into a comment: **an earlier version of this very plan built a
sentinel out of a state production cannot produce and then fixtured that state**, which is the
2026-09-02 learning reproduced inside its own fix. Adding `-T` to the capture would make the
root-disk case a positive measurement, and is deliberately **not** done here: it changes
`data_mount_src`'s audit semantics for every existing consumer, including the destruction record,
and that is a separate decision from making the pin satisfiable.

**`__AMBIGUOUS__` converts a premise into a measurement.** An earlier draft asserted "within the
Hetzner namespace there is one alias per volume". Nothing in this repo measures that, and the live
host's `/dev/disk/by-id` listing is not readable from here — the host is deny-all-public and this
plan does not open a shell on it. So instead of asserting single-valuedness, the emitter counts the
matches and says so. A count above one is a refusing value carrying its own diagnosis, which is
what the #8005 class costs when it is left as a premise. The `-partN` case is handled upstream by
`lsblk -s`, which resolves a partition to its parent disk before the reverse map runs.

**Why `lsblk -s` and not a hand-rolled `/sys/block/<dm>/slaves/` walk — measured.** A slaves
readdir names only the *immediate* backing device, so a stacked mapper needs a recursive walk and a
dm node on a *partition* resolves to `sdb1`, whose only Hetzner alias is
`scsi-0HC_Volume_<id>-part1`. `lsblk -s` does both walks as documented behaviour. Measured here
(util-linux 2.41.3) against a partition: `lsblk -nso NAME,SERIAL /dev/nvme0n1p3` prints
`nvme0n1p3` with an empty serial, then `└─nvme0n1 63SC63Z3EFNK` — the parent. Neither shape arises
in today's layout (nothing in `cloud-init-inngest.yml` creates a partition table;
`cryptsetup luksFormat` runs against the whole by-id device and `mkfs.ext4` against the mapper), but
"does not arise today" describes one layout and the cost of being wrong is a second tag and a
second host replace.

**One measured trap in that command.** `lsblk -nsdo <col>` does **not** collapse to a single line:
`lsblk -nsdo SERIAL /dev/nvme0n1p3` printed `63SC63Z3EFNK` followed by an empty line. The
implementation takes the first **non-empty** value, not `NR==1`.

**And why the by-id reverse map stays rather than composing the alias from `lsblk`'s SERIAL.**
Composing `scsi-0HC_Volume_${serial}` would be one call and no glob, but it rests on an assumption
this work cannot verify before the replace: that Hetzner's reported SCSI serial equals the volume
id. The by-id alias's existence is not an assumption — `cloud-init-inngest.yml` mounts from
`/dev/disk/by-id/scsi-0HC_Volume_${inngest_volume_id}` and the live probe row shows that mount
succeeded. The resolution uses the measured fact, not the plausible one.

**A terminal charset collapse on the field, and it is normative rather than a Risks-table
aspiration.** The gate's `_ihdg_field` refuses *duplicated* field names — which catches an injected
`redis_keys=0`, because that name is already in the row. It does **not** catch a value that merely
*splits*: an alias basename of `scsi-0HC_Volume_106261946 junk` tokenises to a valid
`data_mount_devid=` plus a stray `junk`, no duplicate, and G14 would PASS against a device that is
not the one resolved. Two concrete routes to such a value: the alias name derives from the SCSI
serial the hypervisor supplies, escaped by udev — an undocumented external dependency doing the
emitter's sanitising for it — and, in POSIX sh, an **unmatched glob iterates once over the literal
pattern**, so `for a in /dev/disk/by-id/scsi-0HC_Volume_*` on a host with no such alias yields a
basename of `scsi-0HC_Volume_*`, a `*` in a field the gate compares. Measured:
`sh -c 'for a in /nonexistent/scsi-0HC_Volume_*; do basename "$a"; done'` prints
`scsi-0HC_Volume_*`.

So: guard the loop with `[ -e "$a" ] || continue`, and end the block with the same terminal collapse
the histogram already uses one screen above the emit line —
`case "$data_mount_devid" in '' | *[!A-Za-z0-9_.:-]*) data_mount_devid=__UNREADABLE__ ;; esac` —
with the numeric-or-sentinel equivalent for `registry_fns` and `data_mount_base`. The precedent is
two defences, not one, and its own comment says why: *"if anything above emitted whitespace, the
token parser downstream would see extra fields."*

**Two constraints the fixture imposes, both found by reading the battery rather than the emitter.**
First, `inngest.test.sh` extracts the probe's heredoc body and runs it with `sh` (and `sh -n`), so
this code is **POSIX sh** — no `[[ ]]`, no arrays. Second, a `PATH` stub cannot fixture a filesystem
read: `lsblk` is stubbed on `PATH` like `findmnt`, but the by-id directory is a path and needs an
env seam with a production default, exactly as `PROBE_DATA_MOUNT` and `PROBE_LATCH_DIR` already do
in this same block.

**Bounding, with the arithmetic stated rather than deferred.** Every capture precedes the
unconditional emit, so each is bounded; the unit's `TimeoutStartSec=120` sits against a documented
`curl 5 + curl 3 + inngest 10 + doppler 10 + findmnt 5 + du 15 + redis-cli 5 = 53s`. Schema 8 adds
`lsblk 5`, the by-id map at 5 (a `/dev` read can block in D-state on a sick controller) and the
registry query's `curl 5` from D3, taking the documented budget to **68s** against the unchanged
120s ceiling. That number goes in the unit's budget comment; a comment updated to "some larger
figure" is not a record.

### D2 — G14 after the change

G14 becomes one comparison on one field, but it is **five** lines and not two, and every one of the
other four is load-bearing. An earlier draft of this plan wrote the two-line form and, seven lines
below it, stated the principle the two-line form violates.

```
local data_mount_devid expected_devid
data_mount_devid="$(_ihdg_field "$chosen_msg" data_mount_devid)" || { _ihdg_verdict "unreadable"; return $?; }
[[ "$expected_volume_id" =~ ^[0-9]+$ ]] || { _ihdg_verdict "id_pin_mismatch"; return $?; }
expected_devid="scsi-0HC_Volume_${expected_volume_id}"
[[ -n "$data_mount_devid" && -n "$expected_devid" ]] || { _ihdg_verdict "mount_mismatch"; return $?; }
[[ "$data_mount_devid" == "$expected_devid" ]]      || { _ihdg_verdict "mount_mismatch"; return $?; }
```

- **The numeric validation of `expected_volume_id` is kept, not deleted.** It exists in today's G14
  and it is the only thing constraining a raw `workflow_dispatch` string before it is interpolated
  into the comparand. Nothing between the input and the gate constrains its charset.
- **The RHS stays quoted, and this is measured rather than stylistic.** `[[ ]]`'s right-hand side is
  a glob by default. Reproduced here on bash 5.3.9: with `v="scsi-0HC_Volume_999"` and
  `e="scsi-0HC_Volume_*"`, `[[ "$v" == $e ]]` matches and `[[ "$v" == "$e" ]]` does not. A dispatch
  with `--expected-volume-id '*'` against an unquoted RHS matches **any** Hetzner volume alias. G17
  would still refuse today, but relying on that is precisely what this plan says elsewhere it must
  not do — the predicates exist separately for the same reason ADR-199 forbids merging G12 and G13.
- **The empty-operand guard is explicit** so the predicate does not depend on the caller's shell
  options. Measured: `bash -c '[[ "$a" == "$b" ]]'` succeeds while `bash -c 'set -u; …'` aborts, and
  the two contexts that matter disagree — the dispatch step runs `set -uo pipefail`, the gate battery
  runs the mutated library under a bare `bash -c`. A stale `expected_dev` left behind by the rewrite,
  or a `data_mount_devid`/`data_mount_dev_id` typo, would be `[[ "" == "" ]]` → PASS in the harness
  and an abort in production. A harness laxer than the thing it grades cannot certify the predicate.
- **The two-line `local` form.** `local x="$(cmd)"` masks the substitution's exit status with
  `local`'s own; today's code declares then assigns, and the rewrite keeps that.

`data_mount_src` stays emitted and stays read, but its role changes from *predicate* to *audit
record* — the same role `data_bytes` already has under G15. Worth recording rather than leaving
incidental: dropping it from the predicate does not open a hole, because the mountpoint duty is
still fail-closed through G15. The emitter binds `data_bytes=__UNREADABLE__` on the same
`__UNREADABLE__` mount branch, and G15 requires `data_bytes` to be numeric.

This is a strict strengthening in both eras. Pre-recut, the predicate becomes satisfiable at all.
Post-recut, the mapper arm stops being a bare string match on a name any local `cryptsetup` could
create and becomes a claim about which volume backs the mapper.

**Every value that is not the expected alias must refuse, and refuse loudly.** That set is: the
field absent entirely (a host still on the old image, the realistic partial-bump failure —
`_ihdg_field` returns non-zero and the verdict is a refusing token, not a skipped predicate); the
empty string; `n/a` on a row whose `host_role` is `dedicated`, which means the emitter took the web
arm on the wrong host; `__NOMATCH__`, `__AMBIGUOUS__` and `__UNREADABLE__`; and any other volume's
alias. (A `-partN` alias cannot reach G14 because the resolution walks a partition to its parent
disk first — but the gate does not depend on that, since anything that is not the exact expected
alias refuses.)

Two mechanical consequences in the battery. The G14 mutation row's sed is anchored on the literal
source text `if [[ "$data_mount_src" != "$expected_dev"` — rewriting that line makes the sed match
nothing, which `mutate` reports as *"the mutation matched NOTHING in the gate"* rather than passing
silently. That is the harness working; the row must be re-anchored on the new comparison in the
same edit. And because `G14` currently labels two unrelated predicates and their fixture filenames
collide, the mount cases and their `rows-g14*.json` files must be renamed to a distinct label so a
later insertion cannot silently repoint the mutation row at the wrong fixture.

The `mount_mismatch` remediation text must be rewritten in the same change. Today it reads "the
mount failed open and Redis is on the root disk — do not recut; the volume's real contents are
unmeasured", which is the wrong reading for the distinctions the new sentinel set can now draw.

### D3 — `registry_fns=`: the field #8015 needs

The dedicated host already exposes the endpoint the cutover FSM's `verify_serving` queries:
`http://127.0.0.1:8288/v0/gql`, with `query RegistryProbe { functions { id } }`. The probe adds a
bounded query for the count, in the dedicated arm, before the unconditional emit.

| Value | Meaning |
|---|---|
| `<N>` | a well-formed array of that length |
| `__UNREADABLE__` | non-array, error envelope, transport failure, a non-200 `/health`, or `jq` unavailable |
| `n/a` | the web host arm |

`0` is a **measurement**, not an absence — a server that answers and owns nothing. That is the
diagnostic-boot signature, and keeping it distinct from `__UNREADABLE__` is the point: the #7674
probe's positive discriminator becomes `server_active=active` AND `http_code=200` AND
`registry_fns` matching `^[1-9][0-9]*$`, all in the SAME row. A diagnostic boot then reads
`registry_fns=0` and correctly fails to PASS.

**Placement, same reasoning as D1.** `registry_fns` is bound in the `dedicated)` arm **above** the
inner `case "$data_mount_src"`, alongside `data_mount_devid`. Inside the `*)` sub-arm it would
inherit the identical defect — `n/a`, the web-arm sentinel, on a dedicated row — and a registry
count has nothing to do with whether `/mnt/data` is readable. That is fail-closed in effect, but it
would make #7674 permanently uncloseable whenever the mount is unreadable.

**Both new calls carry `2>/dev/null`, and the reason is a shipping hazard rather than tidiness.**
`verify_serving`, the function this mirrors, carries it on both its curl and its jq. The emitter's
own `cutover_flag` capture, forty lines above where this block lands, records the principle:
doppler's stderr is discarded, never shipped, because this row's tag is allowlisted and raw stderr
from a credentialed CLI would route the tool's own error text to Better Stack. Unredirected `jq`
stderr on a malformed body echoes the offending input — an untrusted HTTP response — into journald
and thence into the third-party warehouse. And a **deliberate asymmetry with the redis arm**, stated
so an implementer does not "fix" it: unlike `probe_scan_err`, no GQL error text is ever shipped.
A future revision that wants a snippet must pass it through the same
`tr -c 'A-Za-z0-9' '_' | cut -c1-48` shape.

**No secret reaches argv.** The loopback endpoint needs no auth and the request body carries only
the query text, so `/proc/<pid>/cmdline` gains nothing. The `REDISCLI_AUTH`-not-`-a` discipline is
untouched: `INNGEST_REDIS_PASSWORD` is in the probe's environment but nothing new reads it.

**The consumer's conjunct needs a token boundary.** The existing discriminator is
`grep -F 'server_active=active' | grep -cF 'http_code=200'`. A third conjunct written
`grep -cE 'registry_fns=[1-9][0-9]*'` matches `registry_fns=1abc`. It must be
`grep -cE 'registry_fns=[1-9][0-9]*( |$)'`, with a Guard 2 fixture carrying a trailing-garbage value.

**`jq` is a host fact, not an image fact, and the probe uses none today.** The probe body is
`#!/bin/sh` and calls `jq` zero times; `verify_serving` is bash and does call it, but it is a
different script. `jq` reaches the dedicated host through `cloud-init-inngest.yml`'s `packages:`
list — provisioning, which the OCI image does not carry and this emitter has no `apt-get` to
self-provide. So the parse is guarded: `command -v jq >/dev/null 2>&1 ||
registry_fns=__UNREADABLE__` before the call, so a host without it produces a measurement failure
rather than a silent zero. The parse itself mirrors `verify_serving`'s expression, whose comment
records why it is written that way: *"jq indexes null as null, so an `{"errors":…,"data":null}`
envelope yields type `null` and lands on the non-numeric arm rather than being read as a count of
zero."* That property — an error envelope must render `__UNREADABLE__`, never `0` — is Guard 2's
mutation row 3.

**Drift pin: two files become three, and the extractor constrains the form.** `FUNCTIONS_GQL_QUERY`
is `readonly`-defined in **three** files today, and the distinction matters for how the widened pin
is scoped. Two of them — `inngest-registry-probe.sh` and `inngest-cutover-flip.sh` — carry the
byte-identical `query RegistryProbe { functions { id } }` and are the pair pinned by
`inngest-cutover-flip.test.sh` (the FSM's own comment explains why it cannot source
`inngest-registry-probe.sh`: that file is delivered to the web host only). The third,
`inngest-inventory.sh`, reuses the same **constant name** for a different query
(`query InvFunctions { functions { id name slug } }`) and is deliberately outside the pin. So the
widened assertion must select the RegistryProbe copies by their **value**, not by every
`readonly FUNCTIONS_GQL_QUERY=` line in the repo — a name-scoped widening would drag the inventory
query in and fail on a difference that is correct. Adding the probe's copy makes the pinned set
three of four definitions. The existing extractor is
`grep -oE "^readonly FUNCTIONS_GQL_QUERY=.*"`, so the probe's copy must be a **column-zero**
`readonly FUNCTIONS_GQL_QUERY='…'` line inside the heredoc or the widened pin reports "could not
extract … the drift pin is vacuous" — a failure mode that suite already names. The `jq` parse
expression is the *second* thing now triplicated; widen the pin to cover it too, on the same
extractor shape, because the property Guard 2 row 3 tests lives in the parse and not in the query.

**Precedent-diff: do not become a fourth `_pf_scrub` consumer.** The three cutover-path probes
(`inngest-registry-probe.sh`, `inngest-doublefire-probe.sh`, `inngest-inventory.sh`) triplicate a
bash `_pf_scrub()` sanitiser, pinned byte-identical by `inngest-registry-probe.test.sh`, whose
comment records that *"extraction is deferred until a fourth consumer appears"*. This probe must
not be that fourth consumer: it is POSIX `sh`, not bash, and its output need is far narrower —
`registry_fns` is a count, so the correct sanitisation is the emitter's existing shape, a `case`
refusing anything that is not `^[0-9]+$`. Adding a fourth copy would trip a recorded extraction
trigger for no benefit; reusing the emitter's own idiom keeps the value on the one code path that
already guarantees the row stays whitespace-free.

**The drift pin now spans a baked carrier, and that changes the cost of editing the query.** Both
existing copies live in files delivered by the config-push path; this third copy is baked into the
OCI image. A future edit to the canonical query text is therefore no longer merely a drift-pin
failure to fix — propagating it to the dedicated host needs an image bump. One line in the comment
so the next person editing that query learns it before rather than after.

**Absence still only downgrades.** #8015 keeps the absence-arm ban: a row lacking `registry_fns`
must never grant a PASS, and the probe's existing `channel_dark` / `credentials_unprovisioned`
TRANSIENT arms already encode that shape. The cost of that choice is a real window, named in
`## Delivery` below.

### D4 — the key-name reduction, made identifier-aware

**#8013 names the braced shape, and fixing only that shape leaves the identical leak standing.**
Measured against the emitter's current awk over a brace-FREE fixture:

```
input:   estate:01KYADCPBNEE10PYEYCPCJ08YA:runs:1
output:  estate:01KYADCPBNEE10PYEYCPCJ08YA:*=1
```

Same ULID, same field, same third-party sink — only the brace is gone. The two-segment reduction
`k = seg[1] ":" seg[2] ":*"` ships segment 2 verbatim, and when segment 2 *is* the identifier the
collapse rule never runs. An earlier draft of this plan stated the property two contradictory ways:
the property list said "for the brace shape production actually uses" (which restates the
mechanism) while the guard said "for every key shape the live store actually produces" (which is
the property #8013 actually needs). The second is correct and the design follows it.

**So the reduction becomes identifier-aware rather than brace-aware.** After segmenting, any segment
matching an identifier shape is replaced with a fixed token, and the same test is applied to brace
contents:

| Shape | Pattern |
|---|---|
| ULID | `^[0-9A-HJKMNP-TV-Z]{26}$` |
| UUID | `^[0-9a-f]{8}-[0-9a-f]{4}-` |
| long hex | `^[0-9a-f]{16,}$` |
| long digit run | `^[0-9]{6,}$` |

Measured before and after, over a mixed corpus:

```
before:  ?queue?:queue:*=2,?estate:01KYADCPBNEE10PYEYCPCJ08YA?:*=2,estate:01KYADCPBNEE10PYEYCPCJ08YA:*=1
after:   ?queue?:queue:*=2,?estate?:runs:*=2,estate:*:*=1
```

The brace collapse still happens — it keeps the tag readable as a category — but it is no longer
the thing carrying the privacy property. Three constraints on the implementation:

- Handle a hash tag that is **not** at the start of the key. Redis takes the first `{...}` wherever
  it appears; a fix anchored on `^\{` is narrower than the property.
- Handle a brace group with no colon inside it, and leave `{queue}:queue:x` unchanged — the most
  common live shape, and the one that sits in the tension between "strip aggressively" and "keep the
  category".
- Be idempotent.

**Phase 0 reads the live shapes rather than guessing them.** The host already emits
`redis_key_patterns` and the `discoverability_test` command reaches it with no SSH. The fixture
corpus is derived from what that row names — and it must contain at least one **brace-free**
`<ns>:<identifier>:…` key and at least one non-ULID identifier, or the acceptance criterion tests
only the shape the issue happened to quote. That is this plan's own cited learning — *a fixture
built in a sandbox that also lacks the thing will agree with it* — and it very nearly reproduced it.

### D5 — the schema number and its consumers

`probe_schema=8` in the emitter; `expected_schema="8"` in the gate library's default binding. The
workflow does not pass `--expected-schema`, so the library default is what runs. Every other
consumer is enumerated in `## Files to Edit`.

## Sequencing — why the image bump is Phase 3, and what it costs while it is open

`inngest-bootstrap.sh` is a baked carrier. Guard A in `cloud-init-inngest-bootstrap.test.sh`
compares each baked carrier in the working tree against `git show <pinned tag>:<path>`, so the
moment the emitter is edited, CI is red until the pin names an image built from a tree containing
that edit. Guard B row 6 additionally requires that the tag and the digest move together relative
to `origin/main`. And the digest is not knowable until the build has run.

The only ordering that satisfies all three:

1. Commit the carrier edits (emitter, plus the FSM drift-pin sibling). CI is red on Guard A —
   expected.
2. Push the annotated tag `vinngest-v1.1.32` at that commit.
   `.github/workflows/build-inngest-bootstrap-image.yml` fires on `vinngest-v*.*.*`, builds,
   cosign-signs the digest, and mirrors GHCR → zot. **The signature is a presence token, not a
   verified provenance claim on the delivery path** — the host pull path calls no verify step, as
   `cloud-init-inngest.yml` and the build workflow both state in their own comments. The `@sha256:`
   pin buys integrity; provenance here is unenforced, which makes post-merge criterion 22's
   `crane export` the only check in this plan that grades the delivered bytes.
3. **Watch that run to completion and read the published digest from its step summary before
   touching any pin site.** If it fails, the decision of whether the tag can be re-issued is keyed
   on the **registry**, not on the run's conclusion — and an earlier draft of this plan got that
   wrong. The workflow builds and pushes first, then installs crane, then cosign-signs, then mirrors
   to zot; its own concurrency comment records that push→sign is not atomic. A run that fails at
   signing or at the mirror has **already published to GHCR**, and deleting a git tag does not
   delete a registry tag. So the test is
   `crane manifest ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.32` returning 404. If it 404s the
   tag is disposable: delete the remote tag (`git push origin :refs/tags/vinngest-v1.1.32`), fix the
   carrier, re-tag at the corrected commit under the same number. If it resolves, the number is
   spent whatever the run said — go to `vinngest-v1.1.33`. Never re-dispatch the default path on an
   existing tag: it rebuilds and **moves** the digest, invalidating pins already committed and
   orphaning the cosign signature over an abandoned digest.
4. Commit the digest into all four pin sites. Guard A goes green because the tag's tree equals the
   working tree's carriers; Guard B goes green because tag and digest moved together.
5. Commit the off-host consumers (gate library, batteries, docs). These are not baked carriers, so
   they are free of the pin ordering.

**Steps 2→4 open a window in which CI is red repo-wide, not only on this branch.** The pin
drift-guard's AC6 asserts the pin equals the semver-max published `vinngest-v*` tag, for both
cloud-init files. Between the tag push and the digest commit, that assertion fails on `main` and on
every concurrently open pull request that runs the suite. Keep the window to the length of one
build run; do not push the tag until the digest commit is ready to land. The build workflow has no
failure notification of any kind — its only `always()` step tears down the cloudflared bridge and
its Slack step is gated on a degraded zot mirror — so nobody is told the window has stayed open.

**A throwaway pre-validation build is not available.** The build workflow's `workflow_dispatch`
validates its `ref` input against `^vinngest-v[0-9]+\.[0-9]+\.[0-9]+$` before checkout, so it
cannot be pointed at a branch.

The four pin sites are two refs (`IREF` and `ZIREF`) in each of two files —
`cloud-init-inngest.yml` (dedicated host) and `cloud-init.yml` (web host). A fifth ref exists in
`cloud-init-inngest-zot-pull-mutation.test.sh` pinned at `v1.1.24`; it is a **deliberately stale
negative control**, and what keeps it out of Guard B's population is only that a `.test.sh` cannot
match the `cloud-init*.yml` glob — Guard B's own comment calls that "weak on its own". A Phase 3
`sed -i` across `apps/web-platform/infra/*` would turn a guard red.

**Editing those pins is a `user_data` edit, and the two hosts respond to it differently.**
`hcloud_server.inngest` deliberately carries **no** `lifecycle.ignore_changes = [user_data]` —
`inngest-host.tf` states it outright, so that every cloud-init edit force-replaces the host and the
change is gated to a maintenance-window dispatch. The merge apply itself is safe, because
`apply-web-platform-infra.yml`'s `-target=` allow-list contains no `hcloud_server.*`. But from merge
onward, **any** `inngest-host` or `inngest-host-replace` dispatch — for any unrelated reason, by
anyone — delivers this change. `hcloud_server.web` by contrast *does* carry
`ignore_changes = [user_data, …]`, so the two `cloud-init.yml` pin sites deliver nothing to the
running web host and are fresh-boot values only. The four-site sweep is still correct; the asymmetry
is stated so nobody expects the web pin to act.

**And `inngest-host-replace` is not the mild operation an earlier draft of this plan called it.**
It is a destroy-and-recreate of the sole scheduler that preserves the AOF volume by omission. It
has **no `environment:` reviewer gate, no confirm token and no dark gate** — the workflow's own
`confirm` input description says so — and its entire protection is the plan-shape destroy-guard plus
the stock preflight. It carries the ADR-100 cron-outage window. Delivery to the web host is
`deploy-inngest-image.yml` with `tag=v1.1.32` (no `vinngest-` prefix there). Both are dispatches for
a later, separately-approved step; this plan fires neither, and neither is a precondition for the
pull request being correct.

## Delivery — what merging does and does not achieve

All three fixes live in the OCI image and reach production only through the host replace this plan
does not run. Stating that plainly, because the acceptance criteria would otherwise close three
issues on evidence of a build rather than of delivery:

- At merge, the ULID is still shipping to Better Stack, the mount pin is still unsatisfiable, and
  the registry evidence is still absent from every row.
- **#8015 is the one that gets temporarily worse, and it is worth naming.** Its off-host half — the
  `registry_fns` conjunct in the #7674 probe — takes effect at merge, while the field that satisfies
  it arrives only after the replace. In that window every row lacks the field, so the probe returns
  2 with `reason=not_serving` against a host whose serving state has not changed, and G18 refuses on
  what is really a schema gap. That is fail-closed and therefore the correct direction, and it
  blocks nothing that G13 (`redis_keys=16`) and G20 (`INNGEST_DIAGNOSTIC_BOOT=1`) do not already
  block. It is called out here so the reading is not mistaken for a host fault. Conditioning the
  conjunct on the row's schema was considered and rejected: it would re-open the vacuity for exactly
  the rows the fix exists to grade.
- The closing condition is a probe row on a **new `boot_id`** carrying `probe_schema=8`,
  `data_mount_devid=scsi-0HC_Volume_106261946`, `registry_fns` present and matching `^[0-9]+$`, and
  a `redis_key_patterns` free of any ULID-shaped substring — read with the `discoverability_test`
  command, no SSH. `0` is an accepting value for `registry_fns` here and the reason is decisive:
  `INNGEST_DIAGNOSTIC_BOOT` is a Doppler variable, so it survives the replace, and the live state
  has it set. A gate demanding a non-empty registry would return TRANSIENT forever after the replace
  that actually delivered the fixes.
- **The PR body uses `Ref #8017`, `Ref #8015`, `Ref #8013` — never `Closes`.** `Closes` would close
  all three at merge, and the sweeper lists `--state open`, so every follow-through directive on
  them would become a permanent silent no-op: the precise defect the #7674 probe's header
  memorialises about its own predecessor. Each issue body carries its own directive pointing at the
  same script, because a directive closes only the issue whose body holds it and only the first per
  body is honored.

**There is no rollback, and the plan should not pretend otherwise.** If the new emitter is broken on
the real host, the gate verdicts `silent` or `unreadable`, and the only lever for the dedicated host
is another `inngest-host-replace`, which re-delivers the same bytes. Pinning back to an older tag is
structurally CI-red, because AC6 asserts the pin equals the semver-max published tag. Roll-forward
under a new tag is the only exit; reserve the next number rather than discovering that mid-incident.

## Files to Edit

**Baked carriers (drive the image bump — Phase 3):**

- `apps/web-platform/infra/inngest-bootstrap.sh` — `probe_schema=7` → `8`; bind
  `data_mount_devid` and `registry_fns` with `n/a` defaults alongside the other
  unconditional-emit fields; the resolution block, placed above the inner
  `case "$data_mount_src"` per D1; the guarded registry query and its column-zero
  `readonly FUNCTIONS_GQL_QUERY` line; the identifier-aware reduction in the histogram awk (see D4 —
  brace-aware is not enough); **both** emit
  sites (the `logger` line and the `inngest-boot-phone-home.sh` fallback) — a
  byte-identical-payload assertion compares them as strings; the `Budget (#7695)` comment, to the
  stated total of 68s.

**Pin sites (Phase 3, after the digest exists):**

- `apps/web-platform/infra/cloud-init-inngest.yml` — `IREF` and `ZIREF`.
- `apps/web-platform/infra/cloud-init.yml` — `IREF` and `ZIREF`.

**Off-host consumers (Phase 4):**

- `tests/scripts/lib/inngest-host-dark-gate.sh` — `expected_schema="7"` → `"8"`; the G14 mount
  predicate; the G14 rationale comment; the predicate index line
  `G14 data_mount_src == the pinned device`; the `stale_schema` header note naming schema 7; the
  stale `BUMPED 3 -> 4 (#7695, 2026-09-09)` line.
- `tests/scripts/lib/inngest-host-replace-gate.sh` — one comment line describing the dark gate's
  mount predicate as "the pinned device => mount_mismatch" against `data_mount_src`. A sibling
  gate library's doc-comment, found by grepping every file that names the verdict token rather than
  only the files that implement it; it goes stale the moment the pin field changes.
- `scripts/followthroughs/inngest-host-not-serving-7674.sh` — the positive discriminator gains the
  `registry_fns` conjunct in the same row; the header's "WHY BOTH FIELDS" section becomes three;
  the `not_serving` diagnostic line reports the observed value.
- `.github/workflows/apply-web-platform-infra.yml` — **unconditional, not conditional.** Its
  `::error::` refusal line and its `workflow_dispatch` input description both quote the verdict
  vocabulary, and the refusal line carries a recovery instruction that is already wrong and becomes
  actively harmful at schema 8: *"Confirm with: git show …:apps/web-platform/infra/inngest-bootstrap.sh
  | grep -c probe_schema=3 — a 0 means replacing will not help."* Against a correct v1.1.32 image
  that grep returns 0, so the documented confirmation says "do not replace" in precisely the case
  where replacing is the fix. Sweep the `mount_mismatch` text and the `probe_schema=3` literal
  together.
- `scripts/test-all.sh` — the `run_suite` registration for the new followthrough suite below.
  Followthrough suites are not auto-globbed; an unregistered `.test.sh` reddens
  `scripts/lint-orphan-test-suites.sh`.

**Test batteries (Phase 1 and Phase 4 — written before the code they grade):**

- `apps/web-platform/infra/inngest.test.sh` — the `probe_schema=7` assertion and the four section
  headers labelled "schema 7"; `PROBE_7695_FIELDS` and `PROBE_7695_NEVER_ZERO`; the `-eq 8` and
  `-eq 5` cardinality guards, which certify nothing if a field is added without bumping them, and
  whose messages carry numbers that go stale with them (the `-eq 8` assertion's text claims "three
  MORE fields than the never-zero list" while never comparing the two lists, and a sibling says
  "each of the 5 store fields" while looping over 8 — the same message/comparison drift this change
  is already fixing in the gate battery, in a file it already edits); the assertion floor
  `INNGEST_MIN_ASSERTIONS=305`; new arms for `data_mount_devid`, `registry_fns` and a brace-shaped
  key fixture. The `redis-cli` stub is the only place in the repo that produces key names and all
  seven of its literals are `ns:kind:id`, which is why #8013 survived three schema generations, so
  the brace corpus goes there. A GQL stub is needed for `registry_fns`; note the existing `curl`
  stub returns `exit 7` unconditionally, so an arg-aware variant is required. Following the #8005
  precedent in this same file, add **source assertions** for the classes no stub can catch — a stub
  ignores an invented flag, so the shape of the new `lsblk`/`readlink` invocations and the absence
  of a pipe that would swallow an exit status are asserted against the emitter's text.
  **This file has no mutation harness** — `grep -n 'mutate\|PRISTINE'` returns nothing — so it also
  gains a `mutate_emitter` helper that seds a pristine copy of `inngest-bootstrap.sh`, re-extracts
  the probe body and re-runs it. Without it, every emitter-side mutation row is a hand-applied audit
  rather than a runnable row, which is the distinction the Guard Contract exists to enforce.
- `tests/scripts/test-inngest-host-dark-gate.sh` — the `PROBE_FIELDS` emit-order array (gains both
  new fields, at the **tail**, after `data_bytes`, so they sit downstream of the histogram's
  `substr(out, 1, 400)` cap and cannot displace an existing field) and the `PD[probe_schema]=7`
  default, which **every** fixture inherits: leave it at 7 and every `mutate` row's unmutated
  control collapses to `stale_schema` and reports "does not exercise the check". The G4
  previous-schema row moves `probe_schema=6` → `7`. The two hand-written probe strings and the
  python heredoc that spell `probe_schema=7` inline — note the heredoc at the `dark=` template is
  **single-quoted**, so its `${PD[...]}` references are literal rather than expanded, a latent
  defect adjacent to the literals being swept. The `G14c` label text naming "schema-7". The G14
  mount cases and their `rows-g14*.json` filenames, renamed away from the collision. The G4 and G14
  mutation-row sed anchors. The B12 emitter↔gate field contract loop, which today omits
  `redis_expires` and `redis_key_patterns` (a **pre-existing** coverage gap from schemas 6 and 7,
  named as such rather than folded silently into this change's scope, and fixed inline because it
  is the backstop for the one failure mode with no CI backstop) and which builds its comparison
  string through `sort -u` — so it grades a sorted line and does **not** pin emit order, which
  ADR-199 records as load-bearing. Both floors: the distinct-predicate floor (`-lt 21` against 22
  covered) and `_FLOOR=118`, measured at exactly the current count. And the distinct-predicate
  floor's FAIL message, which says "floor is 20" while its comparison is `-lt 21` and its ok
  message says "floor 21".
- `apps/web-platform/infra/inngest-redis-luks-loopback.test.sh` — a real-device arm resolving a
  genuine mapper through a genuine device tree to its backing device, proving the resolution
  against a kernel-built tree rather than an invented one. Invoked as `sudo bash` from
  `infra-validation.yml` and deliberately invisible to the registered-suite runner; adding an arm
  to the existing file needs no registration change.
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — whichever of its five
  anti-vacuity inventories an added assertion lands in (Guard 1 `expected 50`, Guard A `expected
  11`, Guard B `expected 9`, Guard D `expected 11`, Row 7 `expected 7`), plus the unconditional
  floor of 123. Also its own stale `probe_schema=3` comment.
- `apps/web-platform/infra/inngest-cutover-flip.test.sh` — the `FUNCTIONS_GQL_QUERY` drift pin,
  widened from two files to three, and extended to cover the `jq` parse expression.

**Consumer verified and deliberately not edited:** `plugins/soleur/test/terraform-target-parity.test.ts`
asserts `/^\s*if ! inngest_host_dark_gate /m` against the recut job block and that the gate runs
before `terraform plan`. It runs in the **required** `bun` shard, unlike the two advisory infra
suites. The workflow edits above touch neither the call form nor the ordering, so it should stay
green — enumerated here rather than omitted, per `hr-type-widening-cross-consumer-grep`.

**Documentation and records (Phase 5):**

- `knowledge-base/engineering/architecture/decisions/ADR-199-destructive-clearance-requires-a-measured-empty-store-and-a-dark-host.md`
  — an amendment recording that C1's mount pin moved to `data_mount_devid`; see
  `## Architecture Decision (ADR/C4)`. Its sequencing walkthrough also still reads `probe_schema=3`;
  sweep that in the same edit.
- `knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md`
  — the stale `probe_schema=3` narrative reference. A pre-existing doc gap, fixed inline because it
  names the very field family this change renumbers and the correction is one token
  (`wg-when-an-audit-identifies-pre-existing`, `rf-review-finding-default-fix-inline`).
- `knowledge-base/legal/audits/inngest-aof-destruction-record.md` — the field table gains a
  `data_mount_devid` row. Its checklist **also** carries a `data_mount_src=/dev/mapper/inngest-redis`
  line, the same post-recut string being demoted from predicate to audit field; sweep both. This
  record is a precondition artifact, and a field the gate now authorizes on that the record does not
  transcribe would understate what was measured.
- `scripts/encryption-posture-ledger.json` — the `hcloud_volume.inngest_redis` entry's
  `live_verification` carries the `probe_schema=3` phrase and names `data_mount_src` as the
  substrate signal. Do not re-date `expires_on`; the entry carries an explicit note that extending
  it buys time rather than closing a gap.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — the pin-count sentence says
  three refs in one file; there are four across two. Pre-existing gap, fixed inline because a wrong
  count in the runbook is exactly what produces a partial bump. Add one line noting that
  `scheduled-inngest-health.yml` will keep reporting healthy on a row the recut gate refuses as
  `stale_schema`, by design.

## Files to Create

- `scripts/followthroughs/inngest-host-not-serving-7674.test.sh` — Guard 2's suite, which **does
  not exist today**. Without it, five mutation rows and two harness rows mutate a file that is not
  there and the #7674 acceptance criteria are unrunnable. The probe is already fixturable: it reads
  `QUERY="${INNGEST_SERVING_QUERY_BIN:-…/betterstack-query.sh}"` plus `INNGEST_SERVING_HOST`,
  `_HOST_NAME`, `_WINDOW` and `_LIMIT`, so a fixture harness is cheap. Registering it in
  `scripts/test-all.sh` also puts Guard 2 inside the **required** `test-scripts` shard — strictly
  better placement than Guards 1 and 3, which sit in an advisory job.
- `scripts/followthroughs/<name>-8017.sh` — the delivery follow-through probe described in
  `## Observability` › Follow-through enrollment, plus its `run_suite` registration and its
  `run_suite` registration. **No sweeper workflow change is needed** — verified:
  `.github/workflows/scheduled-followthrough-sweeper.yml` already passes `BETTERSTACK_QUERY_HOST`,
  `_USERNAME` and `_PASSWORD` into the probe env. Only the directive's own `secrets=` clause names
  them.
- `knowledge-base/project/specs/feat-one-shot-8017-8015-8013-probe-schema-8/tasks.md`

No new ADR. See `## Architecture Decision (ADR/C4)` for why the decision lands as an ADR-199
amendment instead.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned 65 issues; none of
their bodies names any path in `## Files to Edit`.

## Architecture Decision (ADR/C4)

### ADR

**An amendment to ADR-199, not a new ADR.** ADR-199's Decision C1 states that emptiness is
`redis_keys == 0` *conjoined with* `data_mount_src` pinned to the physical device, and calls that
conjunction "what bridges process to device". This plan does not reverse that decision — it
establishes that the decision was never implemented, because the pin was written against a path
form `/proc/self/mountinfo` cannot contain. The decision content therefore already has a home: C1
itself. ADR-199 gains an amendment recording that the mount pin moved from `data_mount_src` to
`data_mount_devid`, why the original comparison was unsatisfiable, and that `data_mount_src` was
retained as an audit field.

A new ordinal was considered and cut. The generalisable lesson — *a predicate that pins a resource
identity must compare a value the measuring interface actually produces* — is the shape of a
learning, not of a decision record, and this plan already leans on two learnings of exactly that
shape. Minting an ADR for it would add a file, a provisional ordinal, and a renumber-sweep hazard
in exchange for a sentence the amendment carries anyway. (Next free ordinal, independently verified
across 80 `origin/*` refs during planning, is 216 — recorded here only so a later change does not
have to re-derive it.)

### C4 views

**No C4 impact.** The enumeration behind that conclusion, checked in Phase 5 against all three of
`{model.c4,views.c4,spec.c4}`: no external human actor is added or changed; no external system or
vendor edge appears (Hetzner, Better Stack and GHCR are already modelled); no container or data
store is added; no actor↔surface access relationship changes. The change adds two fields to an
existing marker that already flows over an already-modelled edge. Phase 5 must still run
`plugins/soleur/test/c4-count-parity.test.sh` green, because `model.c4` embeds derived
cardinalities in edge prose that the actor/system rubric does not reach.

### Sequencing

The ADR is authored in this pull request, describing the state that exists once it merges. It is
not deferred to a follow-up.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — the dark gate fails closed, so
every failure mode of this change refuses a dispatch rather than permitting one. The indirect cost
is that #7695's capability stays inert, #6894's plaintext-at-rest posture on the Inngest queue
volume cannot be closed, and the in-flight job payloads on that volume stay unencrypted for longer.

**If this leaks, the user's data is exposed via:** the key-name histogram in the
`SOLEUR_INNGEST_SERVER_PROBE` row shipped to Better Stack. #8013 measured two rows carrying an
Inngest-internal estate ULID. This plan reduces that surface; the new `registry_fns` field is a
count, and `data_mount_devid` is a device alias — neither can carry a key name or a payload. No
new value in the row is influenced by anything writing to Redis.

- **Brand-survival threshold:** none.

*Threshold `none` scope-out, required because `cloud-init.*\.ya?ml` is a sensitive path:*
`threshold: none, reason: the change narrows the redis_key_patterns identifier surface and adds
three derived, sanitised metadata fields to an existing diagnostic marker — one of which, the
Hetzner volume id, is an infrastructure identifier that did not previously ship on this row; it is
the same class as the instance_id=hetzner-165360464 already shipped there, it is what the gate must
compare off-host, and none of it is personal data. No user-facing surface and no credential is
added, moved, or newly exposed.`

An earlier draft of this scope-out said the change "strictly narrows an existing identifier leak",
which was not accurate: it narrows one identifier surface and adds another. Both are justified —
`data_mount_devid` is the pin and cannot do its job off-host otherwise — but the claim had to match
the change. The same wording carries into the destruction-record field-table row.

## Encryption Posture

The Phase 2.11 gate fires because `cloud-init-inngest.yml` and `cloud-init.yml` are in
`## Files to Edit`. This change introduces **no new persistent store**; the edits to those two files
are digest-literal re-pins.

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis (unchanged by this work)
    mechanism: plaintext-exception
    evidence: apps/web-platform/infra/inngest-host.tf, resource "hcloud_volume" "inngest_redis" — no format attribute, lifecycle ignores changes to one; ledger entry stores[6] in scripts/encryption-posture-ledger.json
    defends_against: nothing at rest today; Hetzner-side volume deletion only
    does_not_defend: a seized or snapshotted disk exposes the Inngest queue and run-state AOF, i.e. in-flight job payloads (user prompts and agent output)
    disclosed_as: the existing ledger exception on stores[6]
    live_verification: the SOLEUR_INNGEST_SERVER_PROBE row. THIS PLAN CHANGES WHICH FIELD CARRIES IT — the ledger's live_verification is written against data_mount_src at probe_schema=3, and the authoritative substrate field becomes data_mount_devid at probe_schema=8. (The ledger's separate reevaluate_when names SOLEUR_INNGEST_LUKS_STAGE stage=verify with data_mount_src=/dev/mapper/inngest-redis and does not mention probe_schema; an earlier draft of this block conflated the two.) The ledger entry is in Files to Edit for exactly this reason
in_transit:
  - connection: the probe's new registry query, 127.0.0.1:8288/v0/gql (loopback, same host)
    tls: none
    cert_verification: "off"
    does_not_defend: any process already able to bind or read loopback on the dedicated host; the same posture the cutover FSM's verify_serving already has against the same endpoint, which binds loopback only
    disclosed_as: not a new trust boundary — no new network path is opened and nothing leaves the host that was not already leaving it
exception:
  justification: the loopback GQL call adds no reachable surface; TLS on a same-host loopback socket to a process that binds 127.0.0.1 only would defend against nothing this host does not already concede. The at-rest exception is pre-existing and unchanged by this work
  tracking_issue: "#6894"
  reevaluate_when: the recut dispatch completes AND a boot is observed with data_mount_devid resolving through /dev/mapper/inngest-redis to the pinned volume
  expires_on: 2026-10-22
```

The `expires_on` above mirrors the ledger's own value rather than extending it. The ledger carries
an explicit `expires_on_not_extended` note recording that re-dating an at-rest exception forward is
buying time rather than closing a gap; an earlier draft of this block quietly wrote a later date,
which would have contradicted it.

## Observability

```yaml
liveness_signal:
  what: the SOLEUR_INNGEST_SERVER_PROBE row, now carrying probe_schema=8, data_mount_devid=, data_mount_base= and registry_fns=
  cadence: hourly (inngest-server-probe.timer), unconditional emit — no branch may precede it (ADR-117)
  alert_target: Better Stack warehouse via Vector Source 4 (SYSLOG_IDENTIFIER=inngest-server-probe, already allowlisted since #6617a — no new tag is introduced); the */15 dedicated arm of .github/workflows/scheduled-inngest-health.yml classifies each row
  configured_in: apps/web-platform/infra/inngest-bootstrap.sh (unit + timer), apps/web-platform/infra/vector.toml (Source 4 allowlist)
error_reporting:
  destination: journald -> Vector -> Better Stack (layer 3); the second channel is inngest-boot-phone-home.sh with the byte-identical payload, a direct HTTPS POST that does not depend on Vector, which exists precisely for the vector_active=inactive case
  fail_loud: yes for the row itself — every new field has a distinct sentinel and no path degrades to a numeric or clearing value. NOT unconditional, and the caveat is pre-existing (#7228) rather than introduced here - the second channel has its own dark failure mode, because vector.toml deliberately omits `inngest-boot-phone-home` from the Source 4 allowlist, so when its per-boot token file in /run (tmpfs) is missing its own SOLEUR_INNGEST_BOOT_TRACE_LOST marker reaches no sink. On the first boot after a replace, exactly when this plan leans on the second channel, both halves can be dark at once
failure_modes:
  - mode: /mnt/data is mounted from a real device that is NOT a Hetzner volume
    detection: data_mount_devid=__NOMATCH__ in the row itself, alongside data_mount_base naming the device that was resolved — an in-surface measurement from the host, not a host-side inference (layer 3)
    alert_route: the dark gate verdicts mount_mismatch and the dispatch refuses with that token in the workflow run log (layer 6); the row is also readable from the warehouse with no SSH. NOTE - this is deliberately NOT described as "the root-disk fallback"- see D1- findmnt runs without -T, so a skipped nofail mount yields no output and binds __UNREADABLE__, never a device path. An earlier draft of this block re-committed exactly the error D1 corrects
  - mode: the mount rests on MORE THAN ONE physical device (md/RAID, LVM, multipath)
    detection: data_mount_base=__AMBIGUOUS__, and data_mount_devid refuses with it (layer 3)
    alert_route: the gate refuses (layer 6). Distinct from the alias case below - that one is a Hetzner-side naming condition, this one is a real multi-device stack, and the remedy differs (there is no single volume to pin, so the recut has no correct target). Two revisions were needed here and the second is the load-bearing one: counting nodes at the MAXIMUM DEPTH is not counting leaves, and on a fork whose legs are partitioned unevenly (md0 -> {sdb1 -> sdb, sdc}) the only node at max depth is sdb, so the emitter pinned it CONFIDENTLY while the mount spanned both. Every fork fixture written for the first revision was depth-symmetric
  - mode: more than one Hetzner alias resolves to the same base device
    detection: data_mount_devid=__AMBIGUOUS__ (layer 3)
    alert_route: the gate refuses (layer 6). Its remedy differs from its siblings- a stale by-id alias surviving a detach, or two volumes aliased to one device, are Hetzner-side conditions rather than host faults, which is why it is a distinct sentinel and a distinct mode
  - mode: the resolution itself fails, or there was no mount to resolve
    detection: THREE states share __UNREADABLE__ on data_mount_devid alone, so the row carries data_mount_base to separate them - src=__UNREADABLE__ with base=n/a is "nothing was mounted"; src=/dev/sdb with base=__UNREADABLE__ is "the resolution is broken"; a resolved base with devid=__NOMATCH__ is "wrong device". An earlier draft claimed two sentinels discriminated this and they do not (layer 3)
    alert_route: the gate refuses (layer 6). data_mount_base costs nothing- it comes from the lsblk call already being made, inside the same timeout
  - mode: the host serves but adopts no registry (the INNGEST_DIAGNOSTIC_BOOT=1 state live today)
    detection: registry_fns=0 in the same row as server_active=active and http_code=200 (layer 3)
    alert_route: scripts/followthroughs/inngest-host-not-serving-7674.sh returns 2 with reason=not_serving naming registry_fns=0, and the daily sweeper comments on #7674 (layer 6); G18 refuses the dispatch
  - mode: the GQL endpoint answers with an error envelope, is unreachable from loopback, or jq is absent
    detection: registry_fns=__UNREADABLE__, never 0 — an error must not render as an empty registry (layer 3)
    alert_route: same probe, same tracker comment (layer 6); the gate refuses because __UNREADABLE__ is not in the accepting set
  - mode: the emitter moves to schema 8 while a consumer stays at 7
    detection: the gate verdicts stale_schema on every dispatch
    alert_route: NONE AT RUNTIME as things stand, and an earlier draft labelled only the mode below that way. A dispatch may not happen for months, so a CI-side inference at dispatch time is not an alert route. Closed by the same one-line change as the mode below - teach scripts/inngest-dedicated-host-classify.sh a schema-drift verdict comparing the row's probe_schema against the expected value, which runs OFF the host on the */15 arm (layer 6) and reuses the existing action-required issue class
  - mode: the new emitter runs but emits a well-formed row that silently lacks the schema-8 fields
    detection: a row carrying server_active and http_code but no probe_schema=8 classifies `healthy` today and nothing fires
    alert_route: this is the REAL gap, and it is narrower than an earlier draft claimed. The zero-rows half IS covered- scripts/inngest-dedicated-host-classify.sh returns probe-unavailable on rows==0, on an unreadable query and on an unparseable row, and the */15 arm then emits a workflow error and files an action-required issue (layer 6). What is uncovered is the well-formed-but-stale-shape row, closed by the same classify arm as the mode above
  - mode: a new field's value contains whitespace or a token that looks like another field
    detection: the gate's _ihdg_field refuses any message with a duplicated field name and any message containing a newline (layer 3 for the row, layer 6 for the refusal)
    alert_route: verdict unreadable, dispatch refuses. Reinforced by the emitter-side charset sanitisation both new fields must carry
logs:
  where: Better Stack Telemetry (ClickHouse warehouse), source soleur-inngest-vector-prd (id 2457081)
  retention: hot window ~40 minutes via remote(), plus the s3Cluster archive — betterstack-query.sh unions both
discoverability_test:
  # CORRECTED TWICE, and the second correction retracts the first. Recorded because the failure
  # mode is the interesting part, not the command.
  #
  # v1 grepped SOLEUR_INNGEST_SERVER_PROBE with --raw-only and returned ZERO rows. I read that
  # zero as a fact about the HOST ("vector is inactive, so the logger line never delivers") and
  # rewrote the command to chase the phone-home fallback instead. That was wrong.
  #
  # `betterstack-query.sh` implements --raw-only as `raw NOT LIKE '%SYSLOG_IDENTIFIER%'`, which
  # excludes EVERY journald row by construction -- and Vector ships journald rows. Measured: the
  # same query returns 57 rows without the flag and 0 with it; host-isolated, 31 rows, every one
  # shipper=vector, 26 of them vector_active=active with the newest at uptime_s=36285. The five
  # `inactive` rows sit at uptime_s 64-192 on distinct boot_ids: a ~70-second BOOT RACE where the
  # probe's first fire beats vector.service up, which is precisely what the phone-home fallback
  # exists for -- and why the only rows --raw-only CAN return are from it, which made the artifact
  # look like corroboration.
  #
  # Both positive controls I ran to "verify the instrument" also used --raw-only, so neither could
  # detect a filter biased against the one channel in question. An instrument never shown to
  # produce a positive FOR THE CLASS UNDER TEST has not returned a negative about it.
  #
  # This matters more than a normal typo: credentials_required below makes preflight Check 10 SKIP
  # WITHOUT EXECUTING, so nothing but a human running this command would ever have caught either
  # version.
  command: bash -c 'doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 36h --limit 500 --grep SOLEUR_INNGEST_SERVER_PROBE | jq -R -r "fromjson? | .raw? | fromjson? | select(.host == \"soleur-inngest\" and .host_name == \"soleur-inngest-prd\") | .message? // empty" | grep -F probe_schema=8'
  expected_output: |
    whole matched rows, not per-field fragments, each carrying probe_schema=8 …
    data_mount_devid=scsi-0HC_Volume_106261946 … registry_fns=<an integer; 0 while
    INNGEST_DIAGNOSTIC_BOOT is set, which is the live state today>
  credentials_required: "BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD from Doppler soleur/prd_terraform — the probe row exists only in the Better Stack warehouse and the dedicated host is deny-all-public, so no unauthenticated probe can read a live on-host emit. The same three secrets the #7674 follow-through already declares."
```

**Five corrections to this command, each of which an earlier draft got wrong, and none of which any
gate would have caught.** The `credentials_required` declaration makes preflight Check 10 skip
without executing, so this section is the only place the command is graded:

1. **`doppler run` is required.** `betterstack-query.sh`'s own header states it does not read Doppler
   itself and it hard-exits on unset `BETTERSTACK_QUERY_*`. Both the runbook and this plan's own
   live read wrap it.
2. **`jq -R` plus `fromjson?` at both levels.** Without `-R`, one malformed line aborts the whole
   invocation and every valid row after it is lost — the sibling probe forbids the bare form in its
   own comment for exactly this reason. And without `--raw-only` the stream carries host-metric rows
   with no `.raw`, so the first one errors.
3. **Host isolation on TWO fields.** This plan's own research recorded web-1 emitting the same
   marker under the same shared renderer at `probe_schema=4`. A `SYSLOG_IDENTIFIER`-only filter
   interleaves the two hosts unattributably. The sibling probe requires `host` *and* `host_name`
   because #6616 is open on `host_name` lying.
4. **`--limit 500`, not 20.** This plan measured marker-quoting contamination in the warehouse; the
   sibling probe uses 500.
5. **Keep whole rows.** A per-field `grep -oE` destroys the same-row conjunction that D3 is built
   on — the property becomes unverifiable from the command's own output.

### Follow-through enrollment

**Required, and an earlier draft of this plan wrongly said it was not.** That draft reasoned that
nothing here is time-gated because the probe row appears on the first boot after the replace. True —
but the replace is not part of this pull request, so the delivery observation is deferred, and a
closure left to human memory is exactly the rot the sweeper exists to prevent.

**The `Closes #` shape had to be decided, because the obvious one is a permanent silent no-op.**
`sweep-followthroughs.sh` lists `--state open`. If the PR body carries `Closes #8017 / #8015 /
#8013`, all three close at merge and any directive on them is never swept again — the precise defect
`inngest-host-not-serving-7674.sh`'s header memorialises about its own predecessor. So the PR body
uses **`Ref #8017`, `Ref #8015`, `Ref #8013`**, not `Closes`, and each of the three issue bodies
carries its own directive pointing at the same script. One directive per body is required because a
directive closes only the issue whose body holds it, and only the first directive per body is
honored. This is the same disposition the repo already applies to `ops-remediation` work whose fix
executes after merge.

**What the probe asserts, and one thing it must assert that an earlier draft omitted.** Exit 0 only
when the warehouse holds a `SOLEUR_INNGEST_SERVER_PROBE` row from the dedicated host, on a `boot_id`
**other than** `906c015b-b648-400f-93ea-ced42e048ed9`, carrying — all in the same row:

- `probe_schema=8`,
- `data_mount_devid=scsi-0HC_Volume_106261946`,
- `registry_fns` present and matching `^[0-9]+$`,
- and `redis_key_patterns` containing **no** substring matching `[0-9A-HJKMNP-TV-Z]{26}` — the
  identical ULID-alphabet regex the acceptance criteria use. Without this conjunct the probe would
  auto-close **#8013 on evidence of a different fix**: it reads nothing the ULID leak lives in.
  This is a lawful absence arm because it only *downgrades* a positive that `probe_schema=8` on a
  fresh `boot_id` has separately established.

**`^[0-9]+$` and not `^[1-9][0-9]*$`, and this is the finding that would have made the closure
unreachable.** `INNGEST_DIAGNOSTIC_BOOT` is a Doppler variable, not image state, so it **survives a
host replace**. The live state records it as `1`. A delivery gate demanding a non-empty registry
would therefore return 2 forever *after* the replace that genuinely delivered all three fixes, and
none of the three issues would ever close — while also smuggling an unrelated Doppler flip into a
delivery gate. `0` is a measurement here, and the delivery probe grades what the replace delivers.
The non-empty requirement belongs where it was designed to live: the #7674 serving discriminator.

**Exit contract, stated so the work phase builds it rather than rediscovering it at CI.** 0 = PASS;
2 = TRANSIENT; **1 is reserved and unreachable** — the sweeper comments on every exit-1 run and "the
replace has not been dispatched yet" is a wait, not an actionable fault. `credentials_unprovisioned`
and `query_failed` each exit 2 with a **distinct reason string**, because the two have opposite
remedies and only one of them is a wait. The `${VAR:?msg}` form is **banned** and the ban is
mechanical — `scripts/lint-followthrough-varq-ban.sh` reddens CI on it — because that expansion
aborts with status 1 under the sweeper's non-interactive shell, which this contract reads as FAIL,
posting a daily false-FAIL forever on an unprovisioned secret.

**`earliest=`, and the cost of getting it wrong in the other direction.** The sweeper comments on
every TRANSIENT for an open issue, so a probe waiting on an indefinitely-deferred replace posts a
daily comment from merge onward. The #7674 directive waits on the same deferred window and pins
`earliest=2026-11-30` for precisely that reason, with the instruction to push the date rather than
weaken an arm. These directives take the same treatment: pin `earliest=` past the same maintenance
window, and if the replace slips, move the date.

The three `BETTERSTACK_QUERY_*` secrets are **already** in the sweeper workflow's probe env, wired
for the #7674 probe, so no workflow change is needed — only the directives' own `secrets=` clauses
name them.

## Guard Contract

**Harness inventory first, because two review panels converged on the same defect: three guards
were written against a harness that, for six of fifteen rows, did not exist.** That is the plan's
own cited learning — *a discriminator built from an absence discriminates nothing* — recurring one
level up. So:

- Guard 1's gate-side rows run under `mutate()` in `tests/scripts/test-inngest-host-dark-gate.sh`,
  which already exists. Its contract is strict and shapes the rows below: the sed must change
  **exactly one line** (a multi-line move is rejected as "broader than the check it names"), the
  **unmutated control must return the expected token today** or the row is declared non-exercising,
  and the mutated run must return a *different* token.
- Guard 1's and Guard 3's **emitter-side** rows have no harness at all — `grep -n 'mutate\|PRISTINE'`
  over `apps/web-platform/infra/inngest.test.sh` returns nothing. A `mutate_emitter` helper is a
  deliverable of this plan, and naming it is not specifying it. Its contract, mirroring `mutate()`
  property for property:
  1. It mutates the **extracted probe body** — post-`awk`, the same text `sh "$PROBE_BODY"` runs —
     not `inngest-bootstrap.sh` whole. Mutating the outer file would let a sed land in bash code the
     probe never executes and report a pass.
  2. The mutation must be proven to have **landed inside the probe-body region**: `cmp -s` against
     the pristine copy, plus a changed-line count of exactly 1. An anchor that matches nothing is
     reported as such, never silently passed.
  3. The **unmutated control** must produce the expected field value today, or the row is declared
     non-exercising.
  4. The mutated run must produce a **different** value.
  5. It carries its own `SELFTEST` row driving an anchor that cannot land, exactly as the gate
     battery self-tests `mutate()`.
  Rule 2's one-line requirement means a **multi-line move cannot be expressed as a mutation row**.
  Where a matrix row below is a move, it is written as the behavioural assertion the move would
  break, not as a sed.
- Guard 2 has **no suite whatsoever**. Creating it is a deliverable, listed in `## Files to Create`.
- Rows whose sed anchor is text that ships in Phase 2 or Phase 4 cannot be authored against the
  current tree in a way that reds for the named reason; `mutate()` reports "matched NOTHING". Phase
  1 authors them expecting exactly that report, and re-anchors each in the same commit that lands
  its target. This is stated because an earlier draft's Phase 1 contract contradicted it.

### Guard 1 — the mount pin (G14 in `inngest-host-dark-gate.sh`)

**Property.** No `inngest-volume-recut` dispatch is authorized unless the filesystem whose
emptiness was measured is backed by the exact Hetzner volume the dispatch named — for every state
the host can be in, pre-recut (raw ext4) and post-recut (LUKS mapper) alike.

**Assembly.** The property quantifies over the single chokepoint where device identity enters the
verdict: the value of `data_mount_devid` on the one row the gate selected. Structurally that is
(a) the emitter's resolution block, including its placement above the inner
`case "$data_mount_src"`, (b) the two emit sites, which must carry the field byte-identically,
(c) the gate's `_ihdg_field` extraction, which refuses duplicated or whitespace-split fields, and
(d) the G14 comparison. `data_mount_src` leaves the assembly and joins the audit set. The
membership that drifts — which sentinel values exist — is not the assembly; those four code paths
are. Path (a) is reachable by a test only through a `PATH` stub for `lsblk` and one env seam for
the by-id directory, which is why the seam is a deliverable rather than an implementation detail.

**Mutation matrix.**

Each `mutate` row names its fixture and the token the **unmutated** control must return — under
that harness a row without the pair is not yet applicable.

| # | Edit | Harness (fixture → control token) | Must go RED because |
|---|---|---|---|
| 1 | Replace the G14 comparison body with `:` | `mutate` (the mount-mismatch fixture → `mount_mismatch`) | The guard's own dispatch. A predicate that no longer compares anything must not leave the battery green |
| 2 | Emit `data_mount_devid` from the `logger` site only, leaving the phone-home fallback unchanged | `mutate_emitter` | A second member added after a compliant first. The byte-identical-payload assertion is the only thing that sees this, and the Vector-down channel is when the row matters most |
| 3 | Widen the reverse-map glob to the whole `/dev/disk/by-id/` | `mutate_emitter` | Measured: three aliases resolve to one device, so the value becomes order-dependent. A fixture with two aliases for the mounted device must red — and must red as `__AMBIGUOUS__`, not as an arbitrary pick |
| 4 | Collapse `__NOMATCH__` and `__AMBIGUOUS__` into `__UNREADABLE__` | `mutate_emitter` | Three states with three remedies rendered as one. The gate refuses either way, so only the battery can catch this — the definition of a guard that must not be vacuous |
| 5 | Make the resolution report the device it was handed rather than its backing base device | `mutate_emitter` | Behavioural, not step-anchored: whatever tool the implementation uses, a mapper and a partition must both resolve to the backing volume. The four-shape fixture is what reds |
| 6 | Bind `data_mount_devid` only on the branch where `data_mount_src` was readable | `mutate_emitter` | The field then stays `n/a` on a `host_role=dedicated` row — the web-arm sentinel on a dedicated host. Reds through the existing `field=[^ ]` presence loop once the field joins `PROBE_7695_FIELDS`. Written as a binding change rather than a block move, because a move cannot satisfy the one-line rule |
| 7 | Accept `data_mount_devid=n/a` on a row whose `host_role` is `dedicated` | `mutate` (an `n/a`-on-dedicated fixture → `mount_mismatch`) | The web-host sentinel on a dedicated row means the emitter took the wrong arm; accepting it clears a dispatch on an unmeasured store |
| 8 | Unquote the G14 right-hand side | `mutate` (canonical fixture, dispatched `--expected-volume-id '*'` → must still refuse) | Measured on bash 5.3.9: an unquoted `[[ ]]` RHS is a glob, so `*` matches every Hetzner alias. Without this row the matrix scores full marks on a gate one missing pair of quotes turns into a wildcard |
| 9 | Delete the numeric validation of `expected_volume_id` | `mutate` (a non-numeric pin → `id_pin_mismatch`) | A raw `workflow_dispatch` string is interpolated into the comparand; nothing between the input and the gate constrains its charset |
| 10 | Delete the emitter's terminal charset collapse | `mutate_emitter` (an alias containing a space) | The row must render `__UNREADABLE__`, not a splittable value. `_ihdg_field` refuses duplicates, not splits, so nothing downstream catches this |

Rows 4 and 7 of an earlier draft — "read `lsblk -s`'s first line" and "drop the `-s` flag" — were
cut deliberately. Both were anchored on a specific tool and a specific extraction step, so a legal
refactor of the resolution would red them for no behavioural reason, and the properties they claimed
are bought behaviourally by the four-shape fixture instead. The measured first-non-empty trap stays
in `## Design` as an implementation note, where it belongs.

Row 1's sed must be re-anchored on the new comparison — the existing G14 mutation row is anchored
on the literal `if [[ "$data_mount_src" != "$expected_dev"`, which this change deletes. Note also
that a row reintroducing `$data_mount_src` into the G14 block must re-bind it locally: `mutate()`
runs the mutated library under `bash -c` with no `set -u`, so an unbound reference evaluates empty
and the row would red for the wrong reason.

**Harness rows.**

| # | Edit to the SUITE | Must go RED because |
|---|---|---|
| H1 | Point the mount fixture's `data_mount_devid` at a volume id that is not the `--expected-volume-id` | Must FAIL the gate; if the suite stays green, the comparison is not reading the fixture |
| H2 | Leave `PD[probe_schema]` at `7` after the emitter moves to 8 | Every `mutate` row's unmutated control collapses to `stale_schema` and reports "does not exercise the check". A half-done bump must be loud |
| H3 | Insert a predicate case between the coherence `G14` block and the mount block, keeping today's shared `rows-g14.json` filename | The mutation row would silently consume a different fixture. After the rename this must be impossible; before it, it is a live hazard |
| H4 | Blank both G14 operands | Must refuse. And the harness itself must be corrected first: `mutate()` runs the mutated library under a bare `bash -c` while the dispatch step runs `set -uo pipefail`, so today `[[ "" == "" ]]` PASSES in the battery and aborts in production. Add `set -uo pipefail;` to that `bash -c` string so the harness grades what production runs |

**Must-PASS inputs that are not the canonical — and the second one is the only test of Property P2.**

1. A row carrying `data_mount_src=/dev/mapper/inngest-redis` with
   `data_mount_devid=scsi-0HC_Volume_<the expected id>` must PASS — a post-recut host, differing
   from the canonical pre-recut row in a way the contract explicitly permits. Without a must-PASS
   at all, a guard that rejects everything scores full marks on the RED matrix.
2. **A DIFFERENT volume id, matching.** With `--expected-volume-id 105149570` (the suite's existing
   `OTHERID`) and `data_mount_devid=scsi-0HC_Volume_105149570`, the verdict must be `dark`. This is
   the row an earlier draft was missing, and its absence was a demonstrable hole: a G14 written as
   `[[ "$data_mount_devid" == "scsi-0HC_Volume_106261946" ]]` — the expected id hardcoded,
   `$expected_volume_id` ignored — passes every RED row, every harness row, and must-PASS 1. Only
   an input that varies the pin can distinguish a comparison from an equality against a baked-in
   literal, and Property P2 says the pin is what the dispatch names. Note that must-PASS 1 varies
   `data_mount_src`, which D2 removes from the predicate — from G14's point of view it is identical
   to the canonical, so it cannot serve this purpose.

### Guard 2 — the serving discriminator (`inngest-host-not-serving-7674.sh`, read by G18)

**Property.** A PASS is granted only for an observed row, from the dedicated host, proving in one
moment that the host both answered `/health` and had adopted a non-empty function registry.

**Assembly.** One chokepoint: the positive-discriminator block that counts rows satisfying all
conjuncts. It quantifies over (a) the host-identity filter on both `host` and `host_name`, applied
after decoding the double-encoded `raw` column, (b) the same-row conjunction of `server_active`,
`http_code` and `registry_fns`, (c) the exit-code contract 0/1/2 the sweeper reads, where 1 is
deliberately unreachable, and (d) the emitter's `registry_fns` binding, the only producer of the new
conjunct. The rows in the window are members and drift; the conjunction and the filter are the
assembly. **The suite that exercises this assembly does not exist yet and is a deliverable.**

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Drop the `registry_fns` conjunct | The whole defect: a diagnostic-boot row must stop reading as PASS |
| 2 | Accept `registry_fns=0` as satisfying the conjunct | `0` is the diagnostic-boot signature; a `-ge 0` or a bare numeric test passes it |
| 3 | Accept `registry_fns=__UNREADABLE__` | An unreadable registry must never grant a positive; absence may only downgrade. This is the property the `jq` parse carries — an error envelope must render `__UNREADABLE__`, never `0` |
| 4 | Assemble the conjuncts across rows rather than within one | A window holding an old serving row and a recent diagnostic row must not compose into a PASS — the guard's own historical defect shape |
| 5 | Remove the `host_name` half of the identity filter, keeping `host` | web-1 legitimately reports `server_active=active http_code=200`; with a registry count it could now report a positive third field too |
| 6 | Treat a row with **no `registry_fns` field at all** as satisfying the conjunct | This is not a hypothetical: `## Delivery` establishes that between merge and the host replace, EVERY row lacks the field. Absence is a different mutation from a bad value — the sibling gate suite carries separate rows for exactly that reason — and it is the state production will actually be in |

**Harness rows.**

| # | Edit to the SUITE | Must go RED because |
|---|---|---|
| H1 | Make every fixture row identical to the canonical PASS row | A suite whose only must-PASS input is the canonical cannot distinguish a correct guard from `diff $1 canonical` |
| H2 | Replace the suite's failure-counter increment with a no-op | A floor that dispatches through the counter it protects is not a floor |
| H3 | Fixture a window whose PASS row is older than the newest dark row | G8/G9 require the newest row to be dark while G18 requires a serving row inside 24h; the suite must show the two are jointly satisfiable and that this is the shape that satisfies them |
| H4 | Replace the fixture's **double-encoded** `raw` column with a single-encoded object | The assembly names decoding as item (a), and #7674 measured that an outer-level match returns 0/40 while a post-decode match returns 40/40. A new suite whose fixtures put the seam above the decode reproduces that measurement exactly and would pass while testing nothing |
| H5 | Replace the suite's assertion wrapper with a bare `pass` that still increments | The sharper vacuity class in this repo's history: a counter no-op is caught by any must-FAIL arm, but a *counting* wrapper stub is caught only by driving the wrapper in the must-FAIL direction. The gate battery records a run where neutering `predicate()` left the floor printing "20 distinct predicates covered" at 112 passes and 0 failures |

**Must-PASS input that is not the canonical.** A row with `registry_fns=1` rather than a larger
count, and a `cutover_flag` value differing from the canonical fixture's, must still PASS — the
contract is "non-empty", not "matches the fixture". `1` sits exactly on the boundary of
`^[1-9][0-9]*$`, which is the point.

**The suite carries its own floor and its own instrument self-test.** It is a brand-new file, so
Phase 1d's "every floor touched is raised" does not reach it — there is no floor to touch. It gets
an assertion-count floor and a must-FAIL wrapper self-test on the pattern the gate battery already
uses, or it is a suite whose greenness means nothing.

**An ordering constraint this guard creates, which nothing currently documents.** G8/G9 need the
**newest** row dark; G18 needs a row inside the probe's 24h window carrying all three positive
conjuncts. After this change the host must additionally have adopted a registry — which requires
`INNGEST_DIAGNOSTIC_BOOT` cleared, as G20 requires anyway — and *then* be taken dark, all inside
24h. On a dark host the probe's own loopback query fails, so recent rows read
`registry_fns=__UNREADABLE__` and only pre-dark rows can carry the PASS. The sequence is: clear the
diagnostic flag → observe a row with all three conjuncts → take the host dark → dispatch within 24h
of that row. The 24h window literal and the gate's `--max-row-age 5400` are independent numbers
today; the suite should compare them rather than leave them to drift.

### Guard 3 — the key-name histogram (`redis_key_patterns` in the emitter)

**Property.** Every value the histogram ships names a key *category* and contains no identifier,
for every key shape the live store actually produces — braced or not. The brace is where #8013
found the leak; it is not where the property lives. A brace-free `<ns>:<identifier>:…` key ships
its identifier through the two-segment reduction with no brace rule involved, measured.

**Assembly.** One chokepoint: the awk program that renders `redis_key_patterns`. It quantifies over
(a) the identifier test applied to segments and to brace contents alike, (b) the brace collapse,
(c) the two-segment reduction, (d) the charset sanitiser, (e) the
distinct-pattern cap and truncation marker, and (f) the whitespace-collapse arm that follows. The
key names in the store are members; the transformation pipeline is the assembly. The fixtures that
feed it are harness, not assembly — which is exactly why every one of them being `ns:kind:id`
shaped let the defect survive three schema generations.

**Mutation matrix.** All rows run under `mutate_emitter`.

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Remove the identifier test entirely | The defect restored, in both shapes; the braced and the brace-free fixture must each produce the identifier again |
| 2 | Anchor the collapse on `^\{` | Narrower than the property: a key whose tag is not at the start passes the identifier through |
| 3 | Remove the identifier test from **segment 2**, keeping it only inside brace contents | The brace-free `estate:<ULID>:runs:1` shape then leaks exactly as it does today. This is the row that would have caught the defect an earlier draft of this plan shipped |
| 4 | Narrow the identifier test to the ULID alphabet alone | A UUID- or long-hex-shaped identifier passes. The property is about identifiers, not about one encoding |
| 5 | Replace an identified segment with the empty string rather than a fixed token | Over-collapses: every estate merges into one indistinguishable bucket and the field stops answering the question it exists for |
| 6 | Apply the reduction BEFORE the identifier test | Order matters: by then the identifier has already become segment 2 and been emitted |

**Harness rows.**

| # | Edit to the SUITE | Must go RED because |
|---|---|---|
| H1 | Narrow the fixture corpus to braced keys only | The exact edit an earlier draft of this plan made by omission. The corpus must contain at least one brace-free `<ns>:<identifier>:…` key and at least one non-ULID identifier, and the suite must assert the corpus's shape rather than only its output |
| H2 | Assert only that the output contains `estate` | A bare-token assertion the leaked string also satisfies. The assertion must be that the ULID is ABSENT and the category PRESENT |

**No downstream consumer parses the histogram's value shape.** Grepped before changing it: the only
readers of `redis_key_patterns` outside the emitter are the two batteries and the gate's coherence
predicate, and the latter compares against the literal `__NONE__` only. No dashboard, alert or
terraform resource matches the old pattern shape.

**Must-PASS inputs that are not the canonical.** Two, because the collapse must be judged on what
it leaves alone as much as on what it strips:

1. A key with no braces at all (`inngest:run:<ulid>`) still reduces to `inngest:run:*` — the
   collapse must not alter shapes it does not apply to.
2. `{queue}:queue:x` renders `?queue?:queue:*`, unchanged and idempotent. This is the **most common
   live shape** and it sits directly in the tension between matrix rows 3 and 4: a rule aggressive
   enough to strip a colon-free brace group's contents must still not flatten a colon-free group
   that is already a category. It is also the only test of D4's third constraint.

## Implementation Phases

### Phase 0 — preconditions (no writes)

1. Confirm `origin/main` still carries `probe_schema=7` in the emitter and `expected_schema="7"` in
   the gate library; a sibling branch bumping either changes this plan's shape.
2. Read all three `.c4` model files and record the external-actor / external-system / container /
   access-relationship enumeration behind the "no C4 impact" conclusion.
3. Confirm `jq`, `curl` and `lsblk` are reachable from the probe's execution context, by reading how
   `inngest-cutover-flip.sh` (same host, uses the first two) is delivered and how `findmnt` — the
   same util-linux package as `lsblk` — reaches the probe. `jq` in particular arrives via
   cloud-init `packages:`, not via the image, which is why D3 guards on it. Do not assume.
4. Read the **live** `redis_key_patterns` value out of the warehouse with the `discoverability_test`
   command and paste it into the spec. The Phase 1 brace fixture corpus is derived from the shapes
   that row names, not from the single shape #8013 quoted.
5. Re-run and record the measurements the design rests on: the emitter's current histogram awk over
   a brace-shaped fixture (the leak); `lsblk -nso NAME,SERIAL` and `lsblk -nsdo SERIAL` against a
   partition (the parent walk, and the first-line trap); a whole-`by-id` walk (multi-valued).
6. Record the four suite baselines measured during planning: dark gate 118/118 with `_FLOOR` at
   exactly 118 and 22 predicates against a floor of 21; emitter 324/324 against 305; pin
   drift-guard 163/163 with `unconditional=123 floor=123`; cutover flip 147/147.

### Phase 1 — RED: the harness first, then the batteries

Per `cq-write-failing-tests-before` and §2.12's "write the matrix BEFORE the guard". Split by what
is authorable against the current tree:

**1a — build the missing harness.** The `mutate_emitter` helper in `inngest.test.sh`; the new
`scripts/followthroughs/inngest-host-not-serving-7674.test.sh` and its `run_suite` registration in
`scripts/test-all.sh`; the one env seam in the emitter for the by-id directory. None of these grade
anything yet; all three are preconditions for rows that do.

**1b — rows authorable now.** Fixture shapes carrying a real `findmnt -no SOURCE` output
(`/dev/sdb`), never a synthesized by-id string; the must-PASS post-recut row; the
`--expected-volume-id` mismatch; the brace-shaped key corpus from Phase 0 step 4; every harness row;
`PD[probe_schema]=8`; the G14 label and fixture-filename rename; the two floor-message corrections.

**1c — rows whose anchor ships later.** Guard 1 row 1 and Guard 2 row 1 sed against text that does
not exist until Phase 2 or 4. Author them now, expect `mutate` to report "the mutation matched
NOTHING", and re-anchor each in the same commit that lands its target. An earlier draft's blanket
"they must fail for the reason the matrix names" was unsatisfiable for these.

**1d — anti-vacuity counters.** Every floor touched is raised in the same edit that adds an
assertion to its block. These are all `-lt` refusals, so a floor set *above* the count fails the
suite: `_FLOOR` is set equal to the new assertion count, `INNGEST_MIN_ASSERTIONS` to the new count,
and the distinct-predicate floor keeps its one of slack.

### Phase 2 — GREEN: the emitter

`probe_schema=8`; both new fields bound with `n/a` defaults beside the existing store fields; the
resolution block placed above the inner `case` per D1; the guarded registry query with its
column-zero `readonly FUNCTIONS_GQL_QUERY`; the identifier-aware reduction; both emit sites; the unit's
budget comment at 68s; the drift pin widened to three files and extended to the `jq` parse.

### Phase 3 — the image bump

Commit the carriers; push `vinngest-v1.1.32`; **watch the run to completion and read the digest
before touching a pin site**; move all four pins. Leave the `v1.1.24` negative control untouched,
and do not sweep with a directory-wide `sed`. See `## Sequencing` for the failure path and for the
repo-wide red window this opens.

### Phase 4 — GREEN: the off-host consumers

`expected_schema="8"`; the G14 comparison and its rationale; the predicate index line; the
`mount_mismatch` remediation text and the `probe_schema=3` recovery command in the workflow; the
#7674 discriminator's third conjunct; the B12 loop widened.

### Phase 5 — records

The ADR-199 amendment (including its own stale schema narrative); ADR-142's stale reference; the
destruction-record field table and its `data_mount_src` checklist line; the encryption-posture
ledger; the runbook's pin count; Guard A's stale comment. Then
`plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 6 — full battery

`bash scripts/test-all.sh`, plus the three `apps/web-platform/infra/*.test.sh` suites it does **not**
reach, plus the loopback suite under `sudo`. See the acceptance criteria for the exact set and why
`test-all.sh` alone is not sufficient here.

## Acceptance Criteria

### Pre-merge (PR)

Deliberately short. A criterion that restates a phase instruction is ceremony. Each line is a
checkable post-condition on file state, command output, or merged behaviour.

1. `grep -cE '^probe_schema=8$'` on `apps/web-platform/infra/inngest-bootstrap.sh` returns 1 and
   `grep -cE '^probe_schema='` returns 1 — anchored on the assignment, not the token, because this
   file's own convention is to leave a `# … probe_schema=N …` comment beside each bump and a bare
   token count would fail on a correct implementation.
2. **The emitter↔gate schema agreement is a CI assertion, not a one-shot grep.** The dark-gate
   suite — which runs in the required `test-scripts` shard — extracts `probe_schema=([0-9]+)` from
   the emitter and `expected_schema="([0-9]+)"` from the gate library, fails loudly if either
   extraction comes back empty, and asserts the two are equal. An earlier draft answered this with
   a literal grep that does not generalise to schema 9 and is not a gate — while the plan's own
   risk table called it "the one failure mode with no CI backstop" and then did not build one. The
   literal sweep is kept as a secondary check: `git grep -n 'expected_schema="7"'` repo-wide,
   excluding `knowledge-base/project/plans/`, `knowledge-base/project/specs/` and `**/archive/**`
   (which legitimately record the old value), returns nothing.

3. `git grep -c 'probe_schema=3' -- .github/ tests/ scripts/` returns 0 — the recovery instruction
   in the workflow's refusal line no longer tells a reader that replacing will not help.
4. Running the emitter under the dedicated-arm fixture **extended with the by-id seam** produces a
   row matching `data_mount_devid=scsi-0HC_Volume_[0-9]+`, anchored on the value's shape rather
   than the bare token. (Under the *unextended* fixture, which stubs `findmnt` to `/dev/sdb` and has
   no by-id tree, the correct value is `__NOMATCH__` — an earlier draft named the wrong fixture.)
5. That fixture resolves all four mount shapes to the same expected alias: a raw block device, a
   mapper on a whole disk, a mapper on a partition, and a two-level stacked mapper.
6. With the by-id directory emptied the row carries `__NOMATCH__`; with two Hetzner aliases
   resolving to the same device it carries `__AMBIGUOUS__`; with the resolution failing,
   `__UNREADABLE__`. Three distinct values.
7. The gate refuses on every value that is not the expected alias — field absent, `n/a` on a
   `host_role=dedicated` row, and each of the three sentinels — with a refusing verdict token; and
   `n/a` for either new field on a dedicated row is itself a suite failure.
8. The emitter's histogram over the Phase-0-derived corpus produces no substring matching any of
   the four identifier shapes in D4, and **the corpus itself contains at least one brace-free
   `<ns>:<identifier>:…` key and at least one non-ULID identifier** — otherwise the criterion tests
   only the shape the issue happened to quote, which is how the brace-free leak survived an earlier
   draft of this plan. `{queue}:queue:x` still renders `?queue?:queue:*` unchanged, and a brace-free
   non-identifier key still reduces to `inngest:run:*`.
9. Both new fields carry the terminal charset collapse: a fixture whose by-id alias contains a
   space renders `__UNREADABLE__`, not a splittable value. `_ihdg_field` refuses duplicated field
   names, not values that merely split, so nothing downstream catches this. The unmatched-glob case
   is covered too — measured, POSIX `sh` iterates once over the literal pattern.

10. The #7674 probe returns 2 for a window whose only rows carry
   `server_active=active http_code=200 registry_fns=0`; returns 0 for a window with one row
   carrying all three positive conjuncts; returns 2 when the three are split across two rows; and
   returns 2 for `registry_fns=__UNREADABLE__`.
11. The field name in the #7674 discriminator is byte-identical to the one in the emitter's logger
    line, asserted by an extraction across both files that fails loudly if either side comes back
    empty. Without this, #8015 is the one of the three fixes that can silently do nothing: the gate
    never reads `registry_fns`, so a dropped or renamed conjunct breaks no other assertion.
12. `PROBE_FIELDS` in the gate battery equals the emitter's logger-line order **as a sequence**,
    not as a set, with both new fields at the tail after `data_bytes`.
13. Every mutation-matrix row and harness row in `## Guard Contract` has been applied and recorded
    with the RED output it produced, and every must-PASS non-canonical input passed. Evidence goes
    in the spec directory, one line per row.
14. `git grep -c 'soleur-inngest-bootstrap:v1\.1\.32@sha256:' -- apps/web-platform/infra/cloud-init-inngest.yml apps/web-platform/infra/cloud-init.yml`
    returns 2 and 2, `cloud-init-inngest-zot-pull-mutation.test.sh` still names `v1.1.24`, **and all
    four pinned digests are byte-identical to each other and equal
    `crane digest ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.32`**. The count alone asserts that
    a tag and *a* digest are present, not that the digest is the right one — and that exact defect
    is recorded in `cloud-init-inngest.yml`'s own comment, where `v1.1.26@sha256:<v1.1.25's digest>`
    was written at all four sites and shipped.

15. `bash scripts/test-all.sh` is green. It does **not** reach the three
    `apps/web-platform/infra/*.test.sh` suites — verified with `--enumerate all` — so it is not
    sufficient on its own; criteria 15 and 16 cover the rest. It does reach the new followthrough
    suite and `plugins/soleur/test/c4-count-parity.test.sh`.
16. Each of these passes as its own invocation, because all three run only in the advisory
    `deploy-script-tests` job: `bash apps/web-platform/infra/inngest.test.sh` (the suite grading
    most of Guards 1 and 3, and the one an earlier draft named in no criterion at all),
    `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` (Guards A and B), and
    `bash apps/web-platform/infra/inngest-cutover-flip.test.sh` (the widened drift pin).
17. `sudo bash apps/web-platform/infra/inngest-redis-luks-loopback.test.sh` passes with the
    real-device arm. It is invoked as a multi-line `sudo bash` step, deliberately invisible to the
    registered-suite runner, and exits non-zero with the literal `LOOPBACK_UNAVAILABLE` rather than
    self-skipping — so an unprivileged run is a visible failure, not a false green.
18. The extracted probe body passes `sh -n` and runs under `sh` — the behavioural proof that the new
    emitter code is POSIX, which is stronger than grepping for bashisms. An absence-grep for `[[`
    is deliberately *not* used: the probe body legitimately contains `*[[:space:]]*` and this change
    adds more of them.
19. Every anti-vacuity counter touched has been raised to track its new count, each being a `-lt`
    refusal so a floor above the count fails the suite: `_FLOOR` equal to the new assertion count,
    `INNGEST_MIN_ASSERTIONS` at the new count, the distinct-predicate floor keeping its one of
    slack. Every floor's FAIL message states the same number its comparison uses — including the
    two in `inngest.test.sh` whose text claims "three MORE fields" and "the 5 store fields" while
    comparing against 8.
20. `python3 scripts/lint-guard-contract.py` and
    `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` both pass.
21. ADR-199 carries an amendment naming `data_mount_devid`, and
    `knowledge-base/legal/audits/inngest-aof-destruction-record.md` carries a `data_mount_devid`
    row in its field table.

### Post-merge

22. The image build fired on `vinngest-v1.1.32` and the published digest equals the one pinned at
    all four sites — read from the workflow run, not from memory.
23. The **artifact** carries the fix, not just the source that fed it:
    `crane export ghcr.io/jikig-ai/soleur-inngest-bootstrap@<digest> - | tar -xO inngest-bootstrap.sh`
    contains `probe_schema=8` and `data_mount_devid=`. Guard A binds tag→source and says so in its
    own comment; nothing else in the chain grades the registry bytes, and the live arm that comment
    claims exists on the apply path does not.
24. **Delivery, which is what actually closes the three issues.** A probe row on a **new `boot_id`**
    carrying `probe_schema=8`, `data_mount_devid=scsi-0HC_Volume_106261946` and a non-empty
    `registry_fns`, read with the `discoverability_test` command. If the host replace has not
    happened by merge, this is carried by a follow-through directive rather than asserted as done —
    see `## Delivery`.

*(The recut dispatch itself is deliberately absent. It is a separate, separately-approved step and
this plan's correctness does not depend on it having run.)*

## Non-Goals

- Dispatching `inngest-volume-recut`, or any other destructive `apply_target`.
- Spending the one authorized FLUSHALL.
- Clearing the standing flush latch (#7777 — still open, still unaddressed here).
- Closing #6894's encryption posture. This work unblocks the path; it does not walk it.
- Any change to G12/G13, which ADR-199 forbids merging.

The FLUSHALL stays unspent for a mechanical reason worth writing down rather than assuming: its only
writer is `inngest-cutover-flip.sh` under `INNGEST_CUTOVER_FLIP ∈ {arm, execute}`, and the flag is
`aborted`, which that FSM treats as a terminal idempotent no-op. A host replace restarts
`inngest-cutover-flip.timer` (`OnBootSec=30s`), so the replace **does** re-enter the FSM half a
minute after boot — what keeps that harmless is the flag's terminal value, an out-of-band fact this
plan lists as a premise and which must be re-read at delivery time, not assumed to have held.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The emitter moves to 8 while a consumer stays at 7, and nothing in CI binds the literal 7 | AC2 asserts the absence repo-wide; the B12 emitter↔gate contract reads the real emitter's logger line. Both pre-merge |
| The build fails after the tag is pushed, and nothing tells anyone | The build workflow has no failure notification. Sequencing step 3 watches the run before any pin is touched, and the tag is deleted and re-issued at the same number while no image exists for it |
| The tag push reddens `main` and every open PR until the digest lands | The pin drift-guard's AC6 asserts the pin equals the semver-max published tag. The window is bounded to one build run by not pushing the tag until the digest commit is ready |
| The new emitter is broken on the real host and there is no way back | There is none: pinning to an older tag is structurally CI-red under AC6, and the only delivery lever re-delivers the same bytes. Roll-forward under a reserved next tag is the exit, named before it is needed |
| The probe runs but emits nothing, exiting 0 | The existing bootstrap-failure telemetry fires only on a non-zero exit, so this is uncovered today. Detection is "zero `probe_schema=8` rows on the new `boot_id`", stated in `## Observability` with `alert_route: none today` rather than papered over |
| Merging arms a `user_data` force-replace for whoever dispatches `inngest-host` next, for any reason | `hcloud_server.inngest` carries no `ignore_changes = [user_data]` by design. The merge apply cannot fire it (`-target=` excludes `hcloud_server.*`), but the next dispatch delivers this change; stated in `## Sequencing` |
| A new field's value splits the whitespace-tokenised row | Both new fields are constrained to a fixed charset at the emitter and asserted whitespace-free. Beyond `_ihdg_field`, `inngest-cutover-flip-rollout-7761.sh` whitespace-splits the whole message to extract `image_ref` — the consumer a whitespace-bearing value would actually corrupt |
| The registry query adds latency before an unconditional emit | Bounded like every sibling call, guarded on `jq`, and the unit's budget comment moves to a stated 68s against an unchanged 120s ceiling |
| The reverse map is order-dependent | Constrained to the `scsi-0HC_Volume_*` namespace and, where more than one alias still resolves, refused as `__AMBIGUOUS__` rather than picked arbitrarily. Matrix row 3 reds on a widened glob |
| Guard 1's and Guard 3's emitter-side rows have no harness | `mutate_emitter` is a Phase 1a deliverable, and Guard 2's suite is a `## Files to Create` entry. Six of fifteen rows were unrunnable before review caught it |
| The `G14` label names two unrelated predicates and their fixture filenames collide | Renamed in this change. Until then, any case inserted between the two blocks silently repoints the mutation row at the wrong fixture |
| New emitter code written in bash rather than POSIX sh | The battery runs the extracted body under `sh` and `sh -n`, so a bashism fails there rather than in production |
| `scheduled-inngest-health.yml` keeps reporting healthy on a row the recut gate refuses as `stale_schema` | By design — it binds no schema literal and grades a different question. Worth one line in the runbook so the disagreement is not read as a fault |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Emit `findmnt -no MAJ:MIN` (#8017 option 2, first form) | `259:3` cannot be compared to a Hetzner volume id, which is decisive on its own |
| A hand-rolled recursive `/sys/block/<dm>/slaves` walk | `lsblk -s` is documented behaviour of a binary the probe's siblings already use, is `PATH`-stubbable, and halves the seams the fixture needs |
| Compose the alias from `lsblk`'s reported SERIAL | Rests on an assumption no measurement available before the replace can confirm: that Hetzner's SCSI serial equals the volume id. Recorded as a follow-up if a live host ever establishes it |
| Emit the resolved kernel name and have G14 compare against it (#8017 option 3) | The gate would then need the host's `/dev` to know what the by-id path resolves to — the same off-host blindness the issue names. Emitting the *alias* instead of the *target* puts the comparison back in terms the dispatch already holds |
| Deliver the volume id to the probe via `/etc/default/` and let the emitter compare on-host | Stronger than the doctrinal objection: `expected_volume_id` is a **dispatch input**, chosen when the recut is requested, so it is not knowable at host-provision time — a baked-in id would be whatever the host was told at boot, a different value from the one the gate must pin against. Separately, it makes the row a restatement rather than a measurement |
| Fix #8015 off-host only, no schema bump | Not implementable: no recurring registry-count signal reaches the warehouse today (see Research Reconciliation) |
| Emit a registry count from `inngest-consumer-probe.sh` on the web host instead | Cheaper in isolation, but violates the #7674 probe's same-row doctrine. Recorded in the Cut List with its reason |
| Ship the three fixes as three PRs | Each would need its own image bump and its own host replace. The standing disposition on #8013 is explicitly that they ride one replace |

## Domain Review

**Domains relevant:** none

**GDPR / compliance gate (Phase 2.7):** assessed and not invoked. No regulated-data surface is
touched — no schema, migration, auth flow, API route or `.sql` file is in scope — and none of the
four expansion triggers fires: no new LLM or external-API processing of session-derived data, the
brand-survival threshold is `none`, no new workflow reads `learnings/` or `specs/`, and no new
distribution surface is created (the OCI publish path already exists). The one data-movement
question in scope is #8013's identifier leak into a third-party logs sink; the issue measured it as
an Inngest-internal estate identifier rather than personal data, and this change strictly reduces
it. The legal record that *does* need updating — the destruction-record field table — is already a
Files-to-Edit entry.

No cross-domain implications detected — infrastructure and tooling change. No user-facing surface,
no pricing, contract, or content surface. The one adjacent domain, legal, is touched only as a
records update to an existing audit template that this change keeps accurate rather than alters.
