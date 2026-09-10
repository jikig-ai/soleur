---
title: "Phase 0 measurements — probe_schema=8 (#8017, #8015, #8013)"
branch: feat-one-shot-8017-8015-8013-probe-schema-8
date: 2026-09-10
---

# Phase 0 — preconditions, measured

Every number below was re-derived in this session. Plan-quoted figures are preconditions, not facts.

## 0.1 — schema literals on `origin/main`

- `apps/web-platform/infra/inngest-bootstrap.sh:634` — `probe_schema=7`. CONFIRMED.
- `tests/scripts/lib/inngest-host-dark-gate.sh:373` — `expected_schema="7"`. CONFIRMED.

No sibling branch has bumped either, so the plan's shape holds.

## 0.3 — tool reachability in the probe's execution context

`cloud-init-inngest.yml` `packages:` carries `curl` and `jq` explicitly. `lsblk` and `findmnt` are
both util-linux, and the probe already calls `findmnt` successfully on the live host (the row in 0.4
carries a populated `data_mount_src`), so `lsblk`'s presence rests on a measured sibling rather than
on an assumption about the base image.

## 0.4 — the LIVE `redis_key_patterns`, read from the warehouse

**The instrument was verified before its output was read.** A `--grep SOLEUR_INNGEST_SERVER_PROBE`
query returned zero rows over 36h with rc=0 and empty stderr — the shape that is indistinguishable
between "no such event" and "the query is broken". Two positive controls (an unfiltered 1h query and
a broad `--grep SOLEUR` 6h query) each returned rows, and all three `BETTERSTACK_QUERY_*` secrets
resolved from `soleur/prd_terraform`, so the instrument is healthy and the zero is real.

> **RETRACTED 2026-09-10, same session, by measurement.** Everything from here to the end of this
> subsection was WRONG, and the error was mine, not the warehouse's. See the Addendum below.

**The zero is real because the marker is wrong, and that is a finding in its own right.** The live
host reports `vector_active=inactive`, so the probe does NOT reach the warehouse via the `logger`
line at `inngest-bootstrap.sh:891`. It arrives through the `inngest-boot-phone-home.sh` fallback at
line 908, which wraps the payload in `"marker":"SOLEUR_INNGEST_BOOT_STAGE"` with
`"stage":"inngest-server-probe-vector-down"`. The plan's `discoverability_test` command greps the
marker the healthy path would emit, so **as written it returns empty against the live host** and
would read as "no row" to anyone running it. Grep `inngest-server-probe` instead. Corrected in
`## Observability`.

Live value at `probe_schema=7` (host `soleur-inngest`, instance `hetzner-165360464`):

```
redis_key_patterns=?queue?:queue:*=8,?estate:01KYADCPBNEE10PYEYCPCJ08YA?:*=2,?queue?:partition:*=2,?connect?:gateways:*=1,?queue?:idx:*=1,?queue?:accounts:*=2
```

`?` is the existing `gsub(/[^A-Za-z0-9_:.*-]/, "?", k)` sanitising the braces. So the live shapes are:

| Live shape | Property it exercises |
|---|---|
| `{queue}:queue:…` | brace group with NO colon inside — must stay readable as a category |
| `{estate:<ULID>}:…` | brace group CONTAINING a colon, ULID inside the braces |
| `{queue}:partition:…`, `{queue}:idx:…`, `{queue}:accounts:…` | same-tag, different second segment |
| `{connect}:gateways:…` | a second distinct tag |

**The ULID `01KYADCPBNEE10PYEYCPCJ08YA` is in the third-party warehouse right now.** #8013 is not
hypothetical and not merely a shape concern; it is a live, ongoing leak.

## 0.5 — the measurements the design rests on

**(a) The leak is NOT brace-specific.** Running the emitter's current histogram awk verbatim over a
mixed corpus:

```
input:  {estate:01JQZX9K2M3N4P5Q6R7S8T9V0W}:runs:1
        estate:01JQZX9K2M3N4P5Q6R7S8T9V0W:runs:1   <- no brace anywhere
output: ?estate:01JQZX9K2M3N4P5Q6R7S8T9V0W?:*=1,estate:01JQZX9K2M3N4P5Q6R7S8T9V0W:*=2
```

Both shapes ship the ULID. `k = seg[1] ":" seg[2] ":*"` emits segment 2 verbatim, and when segment 2
IS the identifier no brace rule is involved. A collapse-only fix would close #8013 for the shape the
issue quoted and leave the identical leak standing — with a brace-derived acceptance criterion
passing over it. This is why D4 is identifier-aware.

**(b) `lsblk -s` walks partition -> parent as documented** (util-linux 2.41.3):

```
$ lsblk -nso NAME,SERIAL /dev/nvme0n1p3
nvme0n1p3
└─nvme0n1 63SC63Z3EFNK
```

**(c) `-d` does NOT collapse to one line** — the first-non-empty trap is real:

```
$ lsblk -nsdo SERIAL /dev/nvme0n1p3 | cat -A
63SC63Z3EFNK$
$
```

Take the first NON-EMPTY value, never `NR==1` — **for the `-d` form measured here**.

**The shipped emitter does NOT use `-d`.** It calls `lsblk -nso NAME`, which prints the full
inverse tree child->parent, so the base device is the **LAST** non-empty row, not the first. The two
rules are opposite and both are correct for their own command. Stated explicitly because acting on
this measurement's rule against the shipped command yields the dm node or the partition instead of
the base disk — a wrong device pin, which is the exact class #8017 exists to close.

**(d) A whole-`by-id` walk is multi-valued** — three aliases resolved to one device here (an eui
form and two model forms). This is what makes an unconstrained reverse map need an arbitrary
tiebreak, and why the glob is constrained to `scsi-0HC_Volume_*` with an `__AMBIGUOUS__` sentinel
rather than a single-valuedness premise.

## 0.6 — suite baselines (all re-run, all green)

| Suite | Result | Floors |
|---|---|---|
| `tests/scripts/test-inngest-host-dark-gate.sh` | 118 passed, 0 failed | `_FLOOR=118` (exactly equal), 22 predicates vs floor 21 |
| `apps/web-platform/infra/inngest.test.sh` | 324/324 | `INNGEST_MIN_ASSERTIONS=305` |
| `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` | 163/163 | `unconditional=123 floor=123` |
| `apps/web-platform/infra/inngest-cutover-flip.test.sh` | 147 passed, 0 failed | — |

Every plan-quoted baseline matched.

**0.6b — the four `apps/web-platform/infra/*.test.sh` suites are ABSENT from `test-all.sh
--enumerate all`.** CONFIRMED anchored. A first attempt using `grep -cE 'inngest\.test\.sh|…'`
returned 2 and read as a contradiction; both hits were
`.claude/hooks/*-prefer-inngest.test.sh` substring-matching the unanchored pattern. That is
`cq-assert-anchor-not-bare-token` reproduced inside its own verification step, and it is recorded
here because the false reading pointed at the plan rather than at the grep. Only
`apps/web-platform/infra/run-registered-suites.sh` is registered; it derives its list from
`infra-validation.yml`. So `test-all.sh` alone is NOT sufficient for this change, exactly as the
plan's Phase 6 states.

## 0.2 — the C4 enumeration behind "no C4 impact"

Recorded rather than asserted, because "no impact" is the conclusion easiest to reach without
looking. The model is three files — `model.c4`, `views.c4`, `spec.c4` — carrying **14 containers**
and **17 components**, with no `person` or `softwareSystem` declarations of its own.

Grepped every term this change introduces or renames against all three files:

| Term | `.c4` files naming it |
|---|---|
| `inngest-server-probe` | 0 |
| `probe_schema` | 0 |
| `data_mount` | 0 |
| `registry_fns` | 0 |
| `dark-gate` / `inngest_host_dark` | 0 |

The model describes containers and their relationships; this change alters the *fields inside one
observability event* and the *predicate one off-host gate applies to them*. It adds no external
actor, no external system, no container, and no access relationship — nothing the C4 model is a
model *of*. Branch touches 0 `.c4` files, and `plugins/soleur/test/c4-count-parity.test.sh` passes.

No new ADR either: the decision lands as an ADR-199 amendment (see that file's 2026-09-10 entry),
because it changes HOW C1's stated conjunction is measured rather than taking a new architectural
position. A new ordinal would also have created a renumber-sweep hazard against sibling branches.

## Merge-safety: does this diff force a replace of anything targeted on merge?

Checked because the plan warns that editing ANY infra file — *including a comment* — can
destroy-and-recreate a `terraform_data` whose `triggers_replace` hashes it, and that if such a
resource sits in the per-merge `-target=` allow-list, **merging root-SSHes the live serving host**.

A first pass grepped the `.tf` files for my carriers' basenames and returned three hits, which read
as a real finding. It was not: every hit in `server.tf` is a **comment**. Re-run with comment lines
stripped, over each `resource "terraform_data"` block individually:

| Check | Result |
|---|---|
| `terraform_data` blocks whose NON-COMMENT body references `inngest-bootstrap.sh`, `cloud-init-inngest.yml` or `cloud-init.yml` | **none** |
| `terraform_data` resources in the workflow's `-target=` allow-list | 15 |
| Intersection | **empty** |

The one genuine executable use is `server.tf:311`,
`user_data = base64gzip(templatefile("${path.module}/cloud-init.yml", …))` on `hcloud_server.web` —
which carries `ignore_changes = [user_data, …]` (stated again at `server.tf:1892`), so the web pin
is a fresh-boot value and delivers nothing to the running host.

`hcloud_server.inngest` deliberately carries NO such `ignore_changes`, so a cloud-init edit DOES
force-replace it — but no `hcloud_server.*` appears in the `-target=` allow-list at all, so the
merge apply cannot reach it. From merge onward, any `inngest-host` or `inngest-host-replace`
dispatch — for any unrelated reason, by anyone — will deliver this change. That is the plan's stated
sequencing consequence, not a new one.

**Conclusion: merging this PR replaces nothing and opens no shell on any host.** Delivery happens
only through a later, separately-approved replace.


## Addendum — 2026-09-10: §0.4's delivery conclusion was an artifact of my own flag

**What I claimed:** that `vector_active=inactive` on the live host meant the `logger` line never
reaches Better Stack, and that the probe row arrives only through the `inngest-boot-phone-home.sh`
fallback under a different marker.

**What is true, measured:** the `logger` line is the primary live channel and it works.

| Query (36h window, source 2457081) | Rows |
|---|---|
| `--grep SOLEUR_INNGEST_SERVER_PROBE` | **57** |
| the same query **plus `--raw-only`** | **0** |
| host-isolated (`host=soleur-inngest ∧ host_name=soleur-inngest-prd`) | **31**, every one `shipper=vector` |
| ↳ `vector_active=active` | 26, newest at `uptime_s=36285` — vector had been up ~10 hours |
| ↳ `vector_active=inactive` | 5, at `uptime_s` 64/65/69/76/192, each on a DISTINCT `boot_id` |

**The cause.** `scripts/betterstack-query.sh` implements `--raw-only` as
`raw NOT LIKE '%SYSLOG_IDENTIFIER%'`, which excludes **every journald row by construction** — and
Vector ships journald rows. I passed `--raw-only`, got zero, and read the zero as a fact about the
host instead of a fact about my query.

**`vector_active=inactive` is a ~70-second BOOT RACE, not a host state.** All five instances sit at
low `uptime_s` on distinct boots: the probe's first fire beats `vector.service` up. The
phone-home fallback exists for exactly that window, which is why the only rows `--raw-only` CAN
return are the handful from it — and that is what made the artifact look like corroboration.

**Why my instrument check did not catch it.** §0.4 above records two positive controls. Both used
`--raw-only`, so both could only ever return non-journald rows. An instrument that has never been
shown to produce a positive **for the class under test** has not returned a negative about it. The
controls proved the transport worked; they could not detect a filter biased against the one
channel the question was about.

**What this invalidates, and what it does not.**

- INVALID: "the host does not reach the warehouse via the logger line"; the `discoverability_test`
  command's first *and* second forms, both of which keep `--raw-only` and are therefore
  structurally blind to the field's actual channel. Corrected in the plan.
- STILL VALID: `data_mount_src=/dev/sdb` on the live host (so G14's by-id arm really was
  unreachable), and the live `redis_key_patterns` carrying a 26-char ULID (so #8013's premise is
  confirmed against live data). Both were read off row content, not off row counts, and both
  reproduce on the corrected query.
