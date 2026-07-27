---
title: An issue's claim about RUNTIME state is refuted by a live signal, not more code reading — and the guard I wrote to replace it failed open in the same way, keyed on the delivery verb instead of the destination
date: 2026-07-27
category: best-practices
tags: [infra, terraform, for-each, issue-triage, drift-guard, premise-verification, cattle-hosts, ci-apply, mutation-testing, fail-open]
issues: [7000, 6459]
pr: 7001
---

## Problem

#7000 was a P1 `type/bug` with everything a good issue has: exact paths, a named precedent to
copy, a load-bearing trap in bold, a second trap ("this change is currently unguarded"), and six
acceptance criteria. It prescribed fanning 15 web-1-pinned `terraform_data` host provisioners in
`apps/web-platform/infra/server.tf` out over `var.web_hosts`.

Its central claim — *"`soleur-web-2` is a booted host, not a wired fleet member … never receives
the per-host env files, unit enablement, or config those provisioners write"* — was **false**, and
the prescribed fix would have **broken every merge-triggered infra apply**.

Then the guard I shipped in its place failed open in ~13 measured ways, including the exact
defect class I had fixed one commit earlier. That second half is the more useful learning.

## Part 1 — the premise

The issue reasoned from a `grep` over `server.tf` (15 resources hardcode
`connection.host = hcloud_server.web["web-1"]`) straight to a **runtime** conclusion. That skips
the second delivery path: #6459 Phase 2.2 had already given all 15 a fresh-boot route via the
image bake (`local.host_script_files` → `soleur-host-bootstrap.sh`) plus `cloud-init.yml`.

Settled in ~4 minutes by a live off-host signal:

```
soleur-web-zot-consumer-web-2   period=180s grace=60s   status=up   paused=false
```

A 180s/60s heartbeat cannot read `up` unless the host is beating, and that probe unit cannot
start without the `/etc/default/web-<probe>` EnvironmentFile the issue said only web-1 receives.

And the fan-out was unapplyable: CI can SSH exactly one host (`outputs.tf` exposes only web-1 as
`server_ip`; the tunnel bridge installs ONE iptables NAT rule; the connector is web-1-only by
construction; web-2's `:22` is firewalled to `var.admin_ips`). All 15 are `-target`ed by **bare
address** across two workflows, and a bare `-target` hits **every** `for_each` instance — so a
fan-out makes every merge dial `web-2:22` and hang to the SSH timeout (no `timeout` is set on any
connection block). ADR-114 already recorded this constraint in prose; I did not decide new
architecture, I mechanised existing architecture.

## Part 2 — the guard failed open the same way the code did

The replacement guard keyed on four enumerated delivery **CHANNELS**: `provisioner "file"`
source, remote-exec heredoc, rendered `content=`, and `printf`. A ten-agent review panel found
~13 fail-opens, each reproduced by execution. The representative three:

- **Prose satisfied delivery.** I comment-stripped `server.tf` and matched `cloud-init.yml` and
  `web-probe-envwrite.sh` as raw substrings. Renaming the real `/etc/webhook/hooks.json` write
  away and leaving one **comment** → guard reported it covered, 21/0 green. Two of the 35 real
  sources were passing on comment text alone, so the shipped green was partly coincidental.
- **A fifth channel already existed.** `server.tf:1421` writes via `echo … > /etc/sysctl.d/…`.
  My header claimed "all four that server.tf actually uses". `echo AUTH_TOKEN=xyz > /etc/default/
  phantom-env` → green. `sed >`, `install`, `tee`, `cp` were all live and all evaded it.
- **A row was verified by a consumer.** The COVERAGE table claimed cloud-init rendered
  `hooks.json`; `soleur-host-bootstrap.sh` does. The row passed on a systemd `ExecStart` —
  a *reader* of the file — being present in cloud-init.

My own 11-mutation battery caught none of it: it mutated only the bake list, and `expect_red`
discarded output and credited any non-zero exit, so nine checks were deletable with it green and
a `UnicodeDecodeError` scored as a detection.

## Rules

1. **When an issue's claim is about RUNTIME state ("host X does not have Y"), verify it with a
   live off-host signal before writing code.** Static analysis of the provisioning code cannot
   see a *second* delivery path, and a dual-delivery (pet + cattle) fleet always has one. Caveat
   learned at review: the static path *was* also conclusive here — `cloud-init.yml` invokes the
   env-writer ungated with per-host inputs — so the honest rule is "read the OTHER path's file,
   and corroborate off-host", not "code reading cannot settle it".

2. **A "nothing guards this" claim must be measured per-subject, not by grepping one keyword.**
   #7000 supported its second trap with `git grep 'terraform_data' -- '*.test.sh'` → nothing.
   True, and misleading: `fresh-boot-parity.test.sh` already guarded 5 of the 15, keyed on the
   **artifacts** they deliver. A per-resource loop returned the real numbers (10 of 15 unguarded,
   5 named by no suite). Guards commonly key on the artifact or the destination — never assume
   the resource name is the index.

3. **Before converting a singleton to `for_each`, grep how CI `-target`s it.** A bare
   `-target=X` hits every instance, silently widening the blast radius of every apply to hosts CI
   may have no route to. The `moved`-block trap the issue led with was real but second-order —
   the change could not apply at all.

4. **Key a delivery guard on the DESTINATION, not the delivery VERB.** "Which command performed
   the write" is an **open set** — `echo >`, `sed >`, `install`, `tee`, `cp`, a heredoc, a
   rendered `content=`, a python one-liner. Enumerating it guarantees a future verb walks past.
   The destination is the **closed set**: it is what a fresh host does or does not have. Keying on
   it made the fifth channel a non-event, replaced a hand-maintained coverage table with coverage
   *derived* from real install/write statements (which is what let the false `hooks.json` row
   exist at all), and made the guard shorter. When a guard needs an ever-growing list of things to
   recognise, the axis is wrong.

5. **A hardening fix applied to one input is not applied.** I comment-stripped `server.tf` and
   left the other two inputs raw — the same defect, one wall over, in the same file, one commit
   later. When you fix one arm of a disjunction (or one of N parsed inputs), sweep the others in
   the same edit. And strip **trailing** comments, not just full-line ones: a trailing
   `# "phantom.sh"` injected a phantom baked filename past a guard whose header argued trailing
   comments were safe.

6. **A mutation battery must assert WHICH check fired.** Crediting a bare non-zero exit credits
   crashes as detections and lets one mutation's collateral damage cover for a check that is
   already dead. Give every case the anchor it expects from the guard's own failure text. And
   carry **two** positive controls — benign-edit-stays-green proves it is not always-red, but only
   a *legitimate addition* stays-green proves it does not over-fire on any new artifact.

7. **`written_by`, not `mentions`.** Anchor a coverage check on the write construct (`> path`,
   `install … path`, `- path:`), never bare containment. Otherwise an `ExecStart`, a `chmod`, or a
   sentence certifies delivery.

8. **When a guard has an extraction half and a coverage half, they fail in OPPOSITE directions —
   shape each accordingly.** This took three passes to see. Extraction ("what does the code
   write?") fails SILENT: a miss means the item never enters the set, so nothing is checked and
   the guard reports a clean sweep. Coverage ("does the other path provide it?") fails LOUD: a
   miss reports as uncovered. So enumeration is fail-open on the extraction side and safe on the
   coverage side, while over-crediting is harmless on extraction and fatal on coverage. v2 got
   both backwards — it enumerated write verbs for extraction (so `mv`, `dd of=`, `curl -o`,
   `python3 - /path` and any quoted path walked past) and matched loosely for coverage (so a path
   appearing as an `install` SOURCE argument credited itself as written). The fix is asymmetric:
   INVERT extraction (everything is a delivery unless it is under a read-only verb, so an unknown
   verb fails loud) and make coverage POSITIONALLY STRICT (for `install`/`cp`/`mv` the token must
   be the LAST path). Ask of any guard: *for each half, does a miss produce a failure or a
   silence?* Shape the half that produces silence to over-approximate.

9. **"Not statically provable" is a finding, not a skip.** v2 dropped `destination = "${local.x}/y"`
   via a `startswith('/')` filter — silently, with no diagnostic. An interpolated value the guard
   cannot resolve is precisely the case where it cannot make its claim, so it must say so.

10. **A mutation battery's own vacuities are the last place anyone looks.** Four shipped here:
    (a) crediting any non-zero exit scored a `UnicodeDecodeError` crash as a detection and left
    nine checks deletable while green — the anchor must appear on a `[FAIL]` line, not merely
    somewhere in combined output; (b) two mutators were malformed (one injected unescaped quotes
    so the HCL string closed early; one mutated a single file so nothing REQUIRED the artifact and
    the case was vacuous) — a mutation must be verified to produce the *intended* broken state,
    not merely to differ from pristine; (c) two labels described mutations that never occurred
    (one byte-identical to its predecessor, one claiming a rename it did not perform); (d) both
    positive controls were tautological — one edited bytes the guard discards during comment
    stripping, the other named a destination already in the swept set, so neither could
    distinguish "correctly ignored" from "never seen". **A control must move a number the guard
    prints.** Litmus for each case: *name the implementation that satisfies this assertion while
    violating the property.*

11. **Three review rounds each found real defects in a guard that measured green.** Rounds 1 and 2
    found present fail-opens; round 3 found battery-completeness gaps. The value came from giving
    each panel the previous findings and an explicit mandate to attack the NEW shape rather than
    re-report the old — and from reproducing every claim independently before acting on it (one
    round-1 finding did not reproduce on my first attempt because my test removed the comment
    along with the real writer; the correction was to fix the test, not dismiss the finding).

## Resolution

No `.tf` logic changed (one stale comment count corrected, 11 → 15). Delivered:

- `web-host-provisioner-parity.test.sh` — destination-keyed. Sweeps **52** absolute destinations
  the 15 provisioners write and requires each to have a *derived* fresh-boot writer (cloud-init
  `write_files`, a cloud-init write, a `soleur-host-bootstrap.sh` install, or the baked
  env-writer). Also checks the reverse — a bootstrap install whose seed file is not baked — and
  byte-identity on the 4 dual-written unit bodies. Extraction inverted (fail-closed), coverage
  positionally strict. Every input comment-stripped string-aware; HCL blocks brace-balanced.
  Residual battery-completeness gaps filed as #7014.
- `web-host-provisioner-parity-mutation.test.sh` — **28 attributed mutations** (anchors must land
  on a `[FAIL]` line) plus **3 direction controls**, including one that genuinely moves the swept
  count 52 -> 53. M18-M28 pin every hostile mutation from review round 2.
- ADR-114's constraint amended (count 12 → 15) and noted as now mechanically enforced; the two
  suites registered in the plan's Phase-5 coupling register so they are retired *with* §5.3(c).

Related: [[2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name]],
[[2026-07-19-my-own-mutation-battery-was-the-false-confidence]],
[[2026-06-01-symptom-root-cause-trace-the-actual-redirect-not-the-plan-hypothesis]].
