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

Take the first NON-EMPTY value, never `NR==1`.

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
