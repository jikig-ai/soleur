---
title: "chore(infra): decouple the zot version claim from ci-deploy.sh and take the fan-out HMAC key off argv (#9799 items 2 and 3)"
type: chore
date: 2026-10-09
slug: decouple-zot-claim-from-ci-deploy-and-hmac-key-off-argv
branch: feat-one-shot-9799-staleness-claim-hmac-argv
issue: 9799
closes: none
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# chore(infra): decouple the zot version claim from ci-deploy.sh and take the fan-out HMAC key off argv

## Enhancement Summary

**Deepened on:** 2026-10-09
**Method:** halt gates 4.6-4.12 run mechanically against the plan (all pass), plus targeted verification of every load-bearing negative and attribution claim. The full 40-agent review fan-out was deliberately not run: the change is two hunks in one shell script plus a test gate, the plan already carries a Guard Contract validated by `scripts/lint-guard-contract.py`, and every research question was answerable by a grep or a one-off run (recorded below).

### Key improvements

1. **Marker scope widened in the Delivery Contract.** `apply-web-platform-infra.yml` wakes on `apps/web-platform/infra/**` (`.github/workflows/apply-web-platform-infra.yml:20`) and `apply-deploy-pipeline-fix.yml` on the named trigger files, so the tests and the sidecar in this PR wake the first workflow even though only `ci-deploy.sh` feeds `triggers_replace`. Both markers are therefore required on every commit and on the squash body, not only the commit that touches `ci-deploy.sh`.
2. **Ship-skill text conflicts with the hold.** `plugins/soleur/skills/ship/SKILL.md` (Deploy Pipeline Fix Drift Gate) tells the author the apply "will auto-apply on merge — no action required". Under this PR's markers that sentence is false; `/ship` must not relay it as the delivery statement. The PR body carries the true statement (delivery waits for the next sanctioned apply).
3. **python3 resolution on the host verified.** `webhook.service` uses `EnvironmentFile=/etc/default/webhook-deploy` and sets no `PATH`, so systemd's default `PATH` (`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`) applies; `jq`, `curl` and `logger`, which `fan_out_to_peers` already needs, resolve from `/usr/bin`, and python3 sits beside them.

### Verification record (attribution and negative claims)

| Claim in the plan | Probe | Result |
|---|---|---|
| #9795 is the merged change that set v2.1.22 and carries the markers | `gh pr view 9795 --json state,mergedAt` | MERGED 2026-10-09T01:44:05Z; `git show f911a789…` body ends with the two marker lines, each alone on a line |
| `ci-deploy.sh` is in neither Rule A-E baseline | `git grep -n 'ci-deploy' scripts/lint-shell-trace-credential-refusal*.txt` | only `scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh` in the A/B/C file; the lint run on `ci-deploy.sh` reports `0 baselined` |
| Only one `openssl dgst` site exists in `ci-deploy.sh` | `git grep -n 'openssl dgst' apps/web-platform/infra/ci-deploy.sh` | line 359 (plus prose at 369-370) |
| `ci-deploy.sh` currently has exactly one `zot vN.N.N` claim | `grep -nE 'zot \(?v[0-9]+\.[0-9]+\.[0-9]+' apps/web-platform/infra/ci-deploy.sh` | line 1308 only |
| `/proc/<pid>/environ` is owner-only | `ls -ld /proc/self/environ` | `-r--------` (mode 0400) |
| Staleness gate floor equals today's assertion count | `bash zot-image-staleness.test.sh` | `RESULT: 15 passed, 0 failed`, `MIN_ASSERTIONS=15` |
| Battery has 18 cases | `grep -c '^run_mutation [a-z] ' apps/web-platform/infra/zot-image-staleness-mutation.test.sh` | 18 (cases a-r) |
| Cited rule ids exist | `cq-write-failing-tests-before`, `cq-test-fixtures-synthesized-only`, `hr-when-a-plan-specifies-relative-paths-e-g` | present in the AGENTS.md index |
| No fabricated or PAT-shaped variables (Phase 4.8) | regex sweep of the plan | no hits |

### Halt-gate results

4.6 User-Brand Impact: present, threshold `none` with the sensitive-path scope-out bullet (diff touches `apps/*/infra/`). 4.7 Observability: all five fields present; `command` starts with allowlisted `grep`, no `ssh`, finishes well inside the 15 s cap; `expected_output` is a single literal that the `grep -o` prints. The probe only matches once the new log line exists (post-implementation), which is when preflight Check 10 runs it. 4.9 UI wireframe: no UI surface, skipped. 4.10 Encryption posture: no store or new connection, skipped. 4.11 Guard Contract: `python3 scripts/lint-guard-contract.py` green, 2 entries; adequacy read: both Assembly paragraphs name the chokepoint (`CLAIM_RE`; the single `sig` assignment plus shape guard), not a member list. 4.12 Scope Check: all rows mapped or justified.


Draft PR: #9805. PR body carries `Ref #9799` (tracker stays open for items 1, 4 and the addendum) and `Ref #9597` (argv sweep). No close-keyword sits next to either number.

## Overview

Two debts from tracker #9799, delivered as ONE ordinary PR because both edit `apps/web-platform/infra/ci-deploy.sh`, a `deploy_pipeline_fix` trigger file. One edit to that file means one fleet redelivery instead of two.

1. **Item 2 — staleness check 7 forces a trigger-file edit on every zot bump.** `zot-image-staleness.test.sh` check 7 requires a `zot vX.Y.Z` claim comment in `ci-deploy.sh`, `ci-deploy.test.sh` and `cloud-init-registry.yml`. `ci-deploy.sh` is hashed by `terraform_data.deploy_pipeline_fix` and `…_web2` (`server.tf` `triggers_replace`), so a comment-only re-date there reaches the SSH provisioners on both web hosts. Fix: remove the version from the `ci-deploy.sh` comment (point it at the claim register in `zot-image.provenance.md`, which is not a trigger file), drop `ci-deploy.sh` from check 7's followers and required claim locations, and add a new decoupling check that FAILS if a `zot vX.Y.Z` claim ever reappears in `ci-deploy.sh`.
2. **Item 3 — `openssl dgst -sha256 -hmac "$secret"` puts the peer fan-out webhook secret on argv** (`fan_out_to_peers`, `ci-deploy.sh:359`). Fix: use the repo's canonical keyed-HMAC snippet (key in the python3 child's environment only, never argv), refuse to forward unless a 64-hex signature was produced, and prove byte-identity against the old `openssl dgst -hmac` form inside `ci-deploy.test.sh`.

Delivery constraint (hold in force): this PR triggers no infrastructure apply, touches no host, and does not replace the registry host. Because `ci-deploy.sh` is a trigger file, the commit body and the squash body at merge carry the two kill-switch marker lines (see "Delivery contract"). The redelivery to running hosts waits for the next sanctioned apply (tracker item 1).

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief / tracker | Reality (measured in this worktree) | Plan response |
|---|---|---|
| The `zot vX.Y.Z` claim in `ci-deploy.sh` is "currently stale at line ~1303: says v2.1.20, pin is v2.1.22" | Already re-dated by #9795: `ci-deploy.sh:1308` reads `zot v2.1.22`, and `bash zot-image-staleness.test.sh` ends `RESULT: 15 passed, 0 failed`. The structural defect (a bump must edit the file) is unchanged. | Plan fixes the structure, not the date. The comment loses its version token entirely. |
| `ci-deploy.sh` line ~359 is the only HMAC argv site | Confirmed: `git grep -n 'openssl dgst' apps/web-platform/infra/ci-deploy.sh` returns exactly line 359 (plus the prose at 369-370). | One site converted; the "Known remaining site" comment is removed. |
| "Feed the key via stdin/fd; `-macopt hexkey:` is also argv; use a process-substitution fd keyfile or another openssl invocation that takes the key from stdin" | `openssl dgst -help` (OpenSSL 3.6.4) offers only `-hmac val`, `-mac val`, `-macopt val` and `-sign`; `openssl mac -help` offers only `-macopt val`. There is no openssl option that reads an HMAC key from stdin, a file or an fd, and `-sign` cannot load a raw HMAC key. | An openssl-only fd form does not exist. Use the repo's canonical snippet (python3 `hmac`, key via per-command environment prefix), landed and oracle-tested in #9597 S2. Rationale and rejected options in "Technical Considerations". |
| Argv-sweep trackers #9597 / #9757 may already claim the `ci-deploy.sh` HMAC site | #9597 S4 lists `ci-deploy.sh` as "(python3-on-host row)" of the push-triggered production-class files. #9757 only holds the two `cutover-inngest.sh` arms, heartbeat URLs, linkedin write-env and the Better Stack stderr item. Neither baseline (`scripts/lint-shell-trace-credential-refusal*.baseline.txt`) lists `ci-deploy.sh`; the lint passes on it today (`0 baselined`). | #9799 item 3 names this site explicitly, so it is done here. Cite #9597 S4 in the PR body (`Ref #9597`) and leave one comment on #9597 after merge noting the `ci-deploy.sh` row is done. No new issue. |
| Open drafts #9767 and #9529 also edit `ci-deploy.sh` | #9767 touches cron-drain/canary/swap hunks only (no `fan_out`, no `zot v`). #9529 carries an OLD copy of the `fan_out_to_peers` curl hunk (`-H "X-Signature-256…"` to `-K -`) that #9795 already superseded on main, so it must rebase regardless. | Keep this PR's `ci-deploy.sh` diff to two hunks: the `sig=` assignment plus its two comment lines in `fan_out_to_peers`, and the one comment sentence above `_docker_login_failure_class`. Do not reformat the curl command. |

## Research Insights

**Premise validation (Phase 0.6).** Cited by reference: #9799 (OPEN, body read), #9795 (merged; commit `f911a789` read via `git show`), #9805 (OPEN draft PR on this branch), #9597 and #9757 (OPEN trackers), #9767 and #9529 (OPEN drafts). All premises hold except the staleness of the comment date (above). The ADR corpus mechanism check: ADR-096 owns the zot registry and the staleness gate; its decision is unaffected (a follower list narrows, no new mechanism).

**Property List (Phase 0.6b).**

- P1: a zot version bump can reach green without modifying any `deploy_pipeline_fix` trigger file.
- P2: the staleness gate stays at least as strong: every remaining follower is still checked for staleness, and the claim locations the sidecar register names are still required to carry a claim.
- P3: nothing can silently reintroduce the coupling (a claim in a trigger file reddens the gate).
- P4: the hook secret never appears on any process's argv during peer fan-out.
- P5: the signature sent to peers is byte-identical to the old `openssl dgst -sha256 -hmac` output.
- P6: an empty, null or unsignable secret forwards nothing (fail closed) and the failure is visible in the existing `FANOUT:` log lines.

**Cut List.**

- "Have check 7 read one claim register" (the issue's alternative) -> cut: the register already exists (`## Version-scoped claim register` in the sidecar) and is not a trigger file; making the gate parse a table adds a new parser for no property that removing one follower does not already buy.
- Deriving the full `deploy_pipeline_fix` trigger set from `server.tf` inside the staleness gate -> cut: P3 is bought for the one file the tracker names by a single grep; `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` already owns the trigger-file list.
- A new HMAC helper script or `scripts/lib/` library -> cut: the canonical one-line snippet exists and is oracle-tested (`tests/scripts/test-argv-bearer-sweep.sh`, stage S2-A part 2: 8 keys x 4 bodies). `ci-deploy.sh` runs standalone on the host and cannot source a repo library.
- A fd-based python3 key channel (`3< <(printf …)`) -> cut: `/proc/<pid>/environ` is owner-only (mode 0400), so it gives the same exposure class as an fd table; it adds a bash process-substitution and a second protocol for nothing, and it would diverge from the S2 snippet the census regexes know.
- A pure-openssl manual HMAC construction (as in `hmac-sha1-b64.sh`) -> cut: python3 is a cloud-init dependency present on every host (`soleur-host-bootstrap.sh`: "python3 is a cloud-init dependency, always present"); the manual construction is ~30 lines of block-size handling to remove a dependency that already exists. Missing python3 fails closed anyway (P6).

**Learnings applied.**

- `2026-10-09-a-rollback-recipe-nobody-had-run-and-a-baselined-file-touched-without-its-changed-lint.md`: touching `ci-deploy.sh` applies `lint-shell-trace-credential-refusal.py --changed` to its whole body; run it BEFORE editing (measured clean today). Also: a recovery recipe is first executed in an incident, so the sidecar's revert recipe is dry-run in a scratch worktree after this PR edits it (AC).
- `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md`: process substitution, not a pipe, feeds curl's stdin config (already the case at `ci-deploy.sh:373`); do not touch it.
- Existing harness T-9795-1/-2 in `ci-deploy.test.sh` (lines ~9934-9973) already runs the real `fan_out_to_peers` against a curl stub and pins the signature against an `openssl dgst -hmac` oracle; the new rows extend that harness rather than inventing one.

**Evidence gathered.** `bash zot-image-staleness.test.sh` -> 15 passed, 0 failed. A scratch copy with the version coherently bumped to `v9.9.9` everywhere EXCEPT a `ci-deploy.sh` claim comment (removed) fails exactly one check today: check 7's required-location rule (`14 passed, 1 failed`). That single failure is the defect, reproduced. `python3 scripts/lint-shell-trace-credential-refusal.py apps/web-platform/infra/ci-deploy.sh` -> OK, 0 baselined. The canonical snippet equals `openssl dgst -hmac` for a shell-hostile key (`a"b\c $d e;f|g&h`) in a one-off check.

## Technical Considerations

### Item 2 — design

`ci-deploy.sh` currently has exactly one claim, in the comment block above `_docker_login_failure_class`: `# zot v2.1.22 (local.zot_image_amd64 in zot-registry.tf), with this repo's exact accessControl, MEASURED 2026-10-08 …`. The sidecar register row 1 names this location.

Change:

- **`ci-deploy.sh`** (comment only): replace the version token with a pointer, e.g. `# The pinned zot (its version lives in zot-registry.tf; the claim's dated measurement is in zot-image.provenance.md, '## Version-scoped claim register'), with this repo's exact accessControl, MEASURED …`. The new sentence must contain no `zot vN.N.N` / `zot (vN.N.N` shape (check 11 enforces it).
- **`zot-image-staleness.test.sh`**:
  - Hoist the claim shape into ONE variable `CLAIM_RE='zot \(?v[0-9]+\.[0-9]+\.[0-9]+'` used by checks 7 and 11 (the file's own comment says "If a new phrasing appears, widen this shape", so there must be one place to widen).
  - Check 7: `followers=("$DIR/ci-deploy.test.sh" "$DIR/cloud-init-registry.yml")`; `required_claim_locations` becomes the same two files (the register's `ci-deploy.test.sh` row 1 location and the `cloud-init-registry.yml` rows 2-3 locations). Previously `ci-deploy.test.sh` was a follower but not a required location, so the requirement set is strengthened on that file, not weakened.
  - New check 11 (decoupling invariant): `ci-deploy.sh` must exist and match `CLAIM_RE` zero times. Missing file -> `fail` (zero examined is not clean). One match, stale OR current -> `fail` with the remedy "point the comment at the sidecar register; a version token here makes every zot bump edit a deploy_pipeline_fix trigger file".
  - `MIN_ASSERTIONS` 15 -> 16 (measured: the gate runs 15 assertions today and gains one).
  - Header comment: document that `ci-deploy.sh` is deliberately NOT a follower and why.
- **`zot-image.provenance.md`** (sidecar; not hashed by any `triggers_replace`, not a registry render input): (a) recovery step 1: drop `ci-deploy.sh` from the list of files carrying `zot vX.Y.Z` claim comments; (b) recovery step 2: make the marker requirement conditional ("if the commit being reverted touched any `deploy_pipeline_fix` trigger file — check `git show --stat <sha>` against `server.tf` `triggers_replace` — its message BODY must carry the two marker lines"; the #9795 commit touched `server.tf` and `ci-deploy.sh`, the next bump will touch neither); (c) register row 1 location: keep `ci-deploy.sh` as the place the claim's COMMENT lives but say it now carries a pointer, no version; (d) add one sentence to `## Bump procedure` and the register intro: trigger files carry no version-scoped claim; check 11 enforces it.
- **`zot-image-staleness-mutation.test.sh`** (battery): retarget the cases that assumed `ci-deploy.sh` is a follower, and add the new cases (see Guard Contract, Guard 1).

Out of scope: `cloud-init-registry.yml` and `zot-registry.tf` are NOT edited (they are registry-host render inputs; `registry-host-replace-dispatch.yml` wakes on them). AC pins this with a diff-name check.

### Item 3 — design

In `fan_out_to_peers`, replace

```bash
sig=$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "$secret" | sed 's/.*= //')
```

with the canonical snippet (byte-for-byte the line the S2 slice oracle-tested; 198 bytes, `$WEBHOOK_SECRET` replaced by `$secret`):

```bash
sig=$(printf '%s' "$payload" | HMAC_KEY="$secret" python3 -I -c 'import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or sys.exit(1);sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())') || sig=""
if [[ ! "$sig" =~ ^[0-9a-f]{64}$ ]]; then
  logger -t "$LOG_TAG" "FANOUT: could not compute the request signature (python3 unavailable or empty key) — not forwarding an unsigned request"
  return 1
fi
```

- The key rides the python3 child's environment only. `/proc/<pid>/environ` is readable only by the owning user and root, unlike `/proc/<pid>/cmdline`, which is world-readable (the exposure the tracker names).
- Fail-closed layers, in order: (1) the existing `[[ -z "$secret" || "$secret" == "null" ]]` guard before any signing (also catches the jq `null` that would otherwise be a valid-looking 4-byte key); (2) the snippet's own `k or sys.exit(1)` for an empty key; (3) the new 64-hex shape guard, which also covers python3 missing (`127` -> `|| sig=""`) or any crash. Under `set -euo pipefail` the `|| sig=""` keeps a signing failure from aborting the whole deploy script: `fan_out_to_peers` returns 1, which the caller already folds into the deploy-status reason ("web-1 ok, web-2 down").
- Replace the two comment lines 369-370 ("Known remaining site: …") with a one-line statement that the key is environment-only now.
- Equality with the old form holds for any key length: HMAC pre-hashes keys over 64 bytes identically in both implementations (the S2 oracle covers 1, 20, 63, 64, 65, 96, 200 bytes and shell-hostile characters).

**What the tracker's fd wording cannot do.** An openssl-only fd/stdin key does not exist (evidence in the reconciliation table). The python3 environment channel is the repo's decided answer (#9597 S2, `scripts/cutover-inngest.sh`, `scripts/check-deploy-script-parity.sh:163`).

**Residual after this PR.** In the sweep, `ci-deploy.sh` is the last `openssl dgst -hmac` site under `apps/web-platform/infra/ci-deploy*.sh`. Other `apps/web-platform/infra/*` sites (`push-infra-config.sh`, `infra-config-verify.sh`, `verify-tunnel-ingress-origin.sh`) remain tracked under #9597 S4/S5 and are not touched here (each would add a trigger-file edit).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly; a broken fan-out leaves web-2 on an older build until the next deploy (the failure is logged as `FANOUT: …` and surfaced in `deploy-status`, so the release workflow reports "web-1 ok, web-2 down"), and both hosts keep serving traffic.
- **If this leaks, the user's workflow is exposed via:** the peer webhook secret briefly visible in `/proc/<pid>/cmdline` of an `openssl` process on a web host to any local user (the exposure this PR removes); a forged `/hooks/deploy-peer` request would need the secret AND private-network reachability.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none` and not `aggregate pattern` because the change only removes an exposure and fails closed; no user data path, no new credential, no behavior change when it works.

`threshold: none, reason: apps/web-platform/infra/ci-deploy.sh is a sensitive path, but the diff strictly narrows credential exposure (key moves from argv to a per-command environment) and fails closed on any signing failure; it adds no credential, no data path and no network surface.`

## Observability

```yaml
liveness_signal:
  what: the existing journald FANOUT lines from ci-deploy.sh ("FANOUT: peer <ip> accepted deploy (HTTP 202)") plus the DEPLOY_SCRIPT_SHA marker each ci-deploy.sh invocation emits, shipped by Vector to Better Stack
  cadence: per deploy that has peers configured
  alert_target: the release workflow's deploy-status poll (web-platform-release.yml) fails the release step, which pages through the existing release-failure notification
  configured_in: apps/web-platform/infra/ci-deploy.sh (fan_out_to_peers and the DEPLOY_SCRIPT_SHA emit); Vector Source 4 in apps/web-platform/infra
error_reporting:
  destination: journald tag LOG_TAG -> Vector -> Better Stack (same path as every other ci-deploy.sh log line); the fan-out return code is folded into the deploy-status reason
  fail_loud: the new log line "FANOUT: could not compute the request signature (python3 unavailable or empty key)" and a non-zero return from fan_out_to_peers
failure_modes:
  - mode: signature cannot be computed (python3 missing, empty or null secret)
    detection: the new FANOUT log line, plus the existing "FANOUT: webhook secret unavailable" line for the empty/null case; the function returns 1 so deploy-status carries the reason
    alert_route: release workflow deploy-status poll -> release failure notification
  - mode: signature computed but peer rejects it (key or payload mismatch)
    detection: existing "FANOUT: peer <ip> NOT accepted (HTTP <code>)" line and the peer's own deploy-status
    alert_route: same as above
logs:
  where: journalctl -t <LOG_TAG> on the host, aggregated in Better Stack
  retention: Better Stack plan retention (unchanged)
discoverability_test:
  command: grep -o "FANOUT: could not compute the request signature" apps/web-platform/infra/ci-deploy.sh
  expected_output: FANOUT: could not compute the request signature
```

The runtime behavior is enforced in CI by the T-9799 rows in `ci-deploy.test.sh` (which execute the real function); the probe above only proves the operator-visible failure line is present in the deployed script's source.

## Guard Contract

### Guard 1 — zot staleness check 7 decoupling (check 7 narrowed, check 11 added)

**Property.** A zot version bump that moves the pin, the sidecar and the non-trigger followers coherently reaches green without editing `ci-deploy.sh`, while a version claim reappearing in `ci-deploy.sh`, or a registered claim location losing or staling its claim, still reddens the gate.

**Assembly.** Everything the property quantifies over: the `followers` array and the `required_claim_locations` array in `zot-image-staleness.test.sh` (members: `ci-deploy.test.sh`, `cloud-init-registry.yml`); the decoupling target `ci-deploy.sh` (check 11); the ONE shared chokepoint `CLAIM_RE` that both checks match through (so widening the phrasing widens both); the sidecar register rows that name claim locations (`zot-image.provenance.md`, `## Version-scoped claim register`); and the mutation battery `zot-image-staleness-mutation.test.sh` that observes the gate through a sandbox copy. Members drift; the structural fact is that every location is matched by `CLAIM_RE` and counted against `MIN_ASSERTIONS`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Append a claim naming the CURRENT pinned version to `ci-deploy.sh` (a correct claim, not a stale one) | RED, rc 10, check 11 names `ci-deploy.sh` |
| 2 | Delete `ci-deploy.sh` from the sandbox (zero files examined must not read as clean) | RED, rc 10, check 11 reports the file missing |
| 3 | Delete check 11 from the gate (its own dispatch; the assertion count falls below the raised `MIN_ASSERTIONS`) | RED, rc 2 (detector failure) |
| 4 | Stale claim (`zot v2.1.2`) in `cloud-init-registry.yml` only, while `ci-deploy.test.sh` is compliant (a second member after a compliant first) | RED, rc 10, "version-scoped claims name a version we no longer pin" |
| 5 | Reword the claim in `ci-deploy.test.sh` so `CLAIM_RE` cannot see it (required location, now strengthened) | RED, rc 10, "0 version-scoped claims found" |
| 6 | Coherent bump of the version string in `zot-registry.tf`, the sidecar, `ci-deploy.test.sh` and `cloud-init-registry.yml`, with `ci-deploy.sh` byte-identical to pristine (asserted with `cmp`) | GREEN, rc 0 (the proof that a bump no longer touches `ci-deploy.sh`) |

**Harness rows.** Edit to the SUITE (not the guard): the existing `m_k` / `m_m` cases (neuter `pass()`/`fail()`) stay and must still reach rc 2; the sandbox-landing check (`diff -rq` against pristine) already rejects a no-op mutator, and row 6 additionally asserts the `cmp` of `ci-deploy.sh`. Must-PASS non-canonical input: row 6 (a version string the gate has never seen, `v9.9.9`, differing from the canonical fixture in a way the contract permits) plus the existing known-offline-gap case `n`.

**Anchor.** The gate compares claims to the pin, both in the same diff, so it proves consistency, not integrity (already stated in its header). The new invariant (zero claims in `ci-deploy.sh`) is anchored by the mutation battery living in the same registered suite family and by the ship-time deploy-pipeline-fix gate that already fires on any `ci-deploy.sh` edit; weakening check 11 requires editing the gate, which a reviewer sees in the diff.

### Guard 2 — fan-out signing: key off argv, fail closed, byte-identical

**Property.** `fan_out_to_peers` never places the hook secret on any process's argv, never issues a request unless it holds a 64-hex signature computed from a non-empty key, and that signature equals `openssl dgst -sha256 -hmac` of the same payload and key byte-for-byte.

**Assembly.** Every command in the `fan_out_to_peers` body: `jq` (reads the secret from the hooks file; the secret is never a jq argument), the signing pipeline (`python3` with the key in its environment), `curl` (signature on the stdin config, already pinned by T-9795-1/-2), `logger`, and the three refusal arms (empty/null secret before signing; signing failure; non-64-hex signature) that all flow through the single `sig` assignment and the single shape guard before the peer loop. Callers of the function inherit the contract through its return code. A source census row (`ci-deploy.sh` contains no `openssl dgst`) closes the "a second signing site appears" gap.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `openssl dgst -sha256 -hmac "$secret"` as the signer | RED: the argv-recorder row sees the secret in an `openssl` argv, the source census row finds `dgst` |
| 2 | Remove the 64-hex shape guard while a `python3` stub prints garbage (the guard's own dispatch: a function that "signs" nothing and still forwards) | RED: the curl-call counter is 1, expected 0 |
| 3 | Make the helper truncate the key at 64 bytes (a long key after a compliant short one) | RED: the 65-, 96- and 200-byte rows mismatch the oracle |
| 4 | Remove the empty/null secret guard and feed `"null"` | RED: a request is signed under the key `null` (curl-call counter is 1, expected 0) |
| 5 | Replace `|| sig=""` with `|| true` and shadow `python3` as a function returning 127 | RED: an unsigned request is forwarded (curl-call counter is 1, expected 0) |
| 6 | Zero the oracle matrix loop (iterates nothing) | RED: the matrix row asserts it ran exactly 18 comparisons |

**Harness rows.** Edit to the suite: row 6 above (the vacuity floor on the matrix), and the existing T-9795-1/-2 rows stay as an independent check of the request shape. Must-PASS inputs that are NOT the canonical `fixture-fanout-secret`: the 200-byte secret and the shell-hostile secret (`a"b\c $d 'e;f|g&h`) must produce signatures equal to the oracle.

**Anchor.** The oracle is `openssl dgst -sha256 -hmac`, an independent implementation executed in the test with synthetic keys; nothing in the diff can move the expected value, so a weakening of the signer cannot also weaken its reference.

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` — two hunks only: `fan_out_to_peers` (`sig=` line, new shape guard, replace the "Known remaining site" comment) and the one comment sentence above `_docker_login_failure_class` (drop the version token). Trigger file: see "Delivery contract".
- `apps/web-platform/infra/ci-deploy.test.sh` — new T-9799 rows next to T-9795-1/-2 (~line 9973); raise `CI_DEPLOY_ASSERT_FLOOR` by the measured number of added rows (expected 502 -> 509; use the measured count, per the file's own history comments).
- `apps/web-platform/infra/zot-image-staleness.test.sh` — `CLAIM_RE`, check 7 followers/required locations, new check 11, `MIN_ASSERTIONS` 15 -> 16, header comment.
- `apps/web-platform/infra/zot-image-staleness-mutation.test.sh` — retarget `m_l` (remove `ci-deploy.test.sh`, marker `follower file missing`), `m_q` (reword the claim in `ci-deploy.test.sh`), `m_p` (drop `ci-deploy.sh` from its file list); add cases for matrix rows 1-4 and 6 above (row 3 as a gate-mutating case).
- `apps/web-platform/infra/zot-image.provenance.md` — recovery step 1 and 2, register row 1 location text, one sentence on the trigger-file policy.

Glob/census check (`hr-when-a-plan-specifies-relative-paths-e-g`): every path above is a tracked file (`git ls-files` confirmed for all five).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9799-staleness-claim-hmac-argv/tasks.md` (plan artifact only).

Explicitly NOT edited: `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf` (registry-host replace wake paths), `server.tf` (no trigger-list change), `apply-*.yml`, any `scripts/lint-shell-trace-credential-refusal*` file (no baseline row to change; verify with the lint), `tests/scripts/test-argv-bearer-sweep.sh` (its census is about `cutover-inngest.sh`).

## Open Code-Review Overlap

None. Checked the five planned `apps/web-platform/infra/*` paths against all open `code-review` issues (`gh issue list --label code-review --state open`, two-stage `jq --arg`): no body names any of them.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to a deploy script, its test suite and a staleness gate. No UI surface, no schema, no regulated data, no new store or connection (the peer fan-out connection already exists and is unchanged), no architectural decision (a follower list narrows and an existing signing snippet is reused; the ADR/C4 test "would an engineer be misled" is no: ADR-096's decision is unchanged). C4 completeness: no actor, system, container or relationship changes, so no `.c4` edit; the `c4-count-parity` gate is unaffected because no counted entity moves.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Work down items 2 and 3 of tracker #9799 as ONE ordinary PR" [brief] | Overview; single PR; Files to Edit | mapped |
| 2 | "remove the claim from ci-deploy.sh (or have check 7 read one claim register that is not a trigger file), keeping check 7 meaningful for the remaining followers" [brief] | Item 2 design; check 7 narrowing; Cut List | mapped |
| 3 | "Do not weaken the staleness gate; prove with a test that a bump no longer requires touching ci-deploy.sh" [brief] | Check 11; Guard 1 rows 1-6 (row 6 is the bump proof); `MIN_ASSERTIONS` 16 | mapped |
| 4 | "Feed the key via stdin/fd … or another openssl invocation that takes the key from stdin" [brief] | Item 3 design (environment channel; fd form shown not to exist for openssl) | mapped — deviation justified in the reconciliation table |
| 5 | "prove byte-identical signatures vs the old form in ci-deploy.test.sh. Failure-closed on empty secret." [brief] | Guard 2; T-9799 rows | mapped |
| 6 | "the commit body (and the squash body at merge) MUST carry the two kill-switch marker lines" [brief] | Delivery contract | mapped |
| 7 | "the PR body should state that delivery to running hosts waits for the next sanctioned apply (tracker item 1)" [brief] | Delivery contract; AC | mapped |
| 8 | "Check scripts/check-deploy-script-parity.sh (it calls doppler itself)" [brief] | Phase 4 (self-test and its suite only; no live arm) | mapped |
| 9 | "Open argv-sweep tracker issues exist (9597, 9757); check whether the ci-deploy.sh HMAC site is claimed by them and cite rather than duplicate." [brief] | Reconciliation table row 4; PR body `Ref #9597` | mapped |
| 10 | "keep the diff minimal to reduce conflicts" [brief] | Files to Edit hunk limits | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `ci-deploy.sh` comment reword + `sig=` conversion | "remove the claim from ci-deploy.sh" / "Feed the key via stdin/fd" | asked |
| `ci-deploy.test.sh` T-9799 rows and floor raise | "prove byte-identical signatures vs the old form in ci-deploy.test.sh" | asked |
| `zot-image-staleness.test.sh` check 7 + check 11 + floor | "Do not weaken the staleness gate" | asked |
| Mutation battery cases | "prove with a test that a bump no longer requires touching ci-deploy.sh" | asked |
| Sidecar edits (`zot-image.provenance.md`) | — | inferred — the sidecar's recovery recipe and register name `ci-deploy.sh` as a claim carrier; leaving them would make the documented revert recipe and the register contradict the gate (the exact class the 2026-10-09 learning records) |
| Shape guard on the signature | "Failure-closed on empty secret." | asked |
| `CLAIM_RE` hoist | — | inferred — two checks now match the same shape; one definition keeps "widen this shape" a single edit |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform/infra/`
- Planned files: 5 edited, 1 plan artifact | Estimated changed lines: ~230 (the tests dominate)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (also the operator's explicit instruction: one edit to a trigger file means one redelivery)

## Delivery Contract (trigger-file PR under an operator hold)

`ci-deploy.sh` is hashed by `terraform_data.deploy_pipeline_fix` (web-1) and `deploy_pipeline_fix_web2`, and `apps/web-platform/infra/**` wakes `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` on push to main.

- Every commit body that carries the `ci-deploy.sh` change, and the squash body at merge, ends with the paragraph and two marker lines in the exact form of `f911a789340ecf83db40a6fa236f0260ce8bae1f` (each marker alone on its own line, because the workflows anchor with `(^|\n)\[…\]($|\n)`):

  ```text
  The two lines below keep the merge-time push applies away from web-1 and web-2: this change edits ci-deploy.sh, which feeds triggers_replace of SSH provisioners that would otherwise re-run on the running web hosts.

  [skip-web-platform-apply]
  [skip-deploy-fix-apply]

  Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
  ```

- The markers are required on EVERY commit of this PR and on the squash body, not only the one touching `ci-deploy.sh`: `apply-web-platform-infra.yml` wakes on `apps/web-platform/infra/**` (so the test and sidecar edits wake it), while `apply-deploy-pipeline-fix.yml` wakes on the named trigger files. Each workflow reads the marker from the head commit message of the push, anchored on its own line, so the squash body is the one that matters at merge.
- `/ship`'s Deploy Pipeline Fix Drift Gate text ("will auto-apply on merge — no action required") does not apply under these markers; the PR body states the true delivery path instead.
- Never an `[ack-destroy]` line. This change plans no destroy.
- PR body: states that delivery of the new `ci-deploy.sh` to running hosts waits for the next sanctioned apply (tracker item 1, which stays open), carries `Ref #9799` and `Ref #9597`, no close-keyword adjacent to either number, avoids the word the brief bans, has a `## Changelog` section, and ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Expected consequence to disclose, not fix: until that apply, drift reports for `zot_consumer_probe_install` / `deploy_pipeline_fix_web2` (already expected by tracker item 1) now also reflect this file, and `check-deploy-script-parity.sh` reads repo-vs-running-host as drifted. Both are the known state, not a regression.
- Merge through the normal merge queue; do not sync a queued PR. No host, no `terraform apply`, no registry replace: AC verifies the diff touches none of `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`.

## Implementation Phases

### Phase 0 — baseline (read-only)

- `python3 scripts/lint-shell-trace-credential-refusal.py --changed` and the plain run on `ci-deploy.sh` (clean today).
- `bash apps/web-platform/infra/zot-image-staleness.test.sh` (15/0) and `bash apps/web-platform/infra/zot-image-staleness-mutation.test.sh` (18/18) to record the baseline.
- `bash apps/web-platform/infra/ci-deploy.test.sh` baseline row count (expect 502) — confirm before changing the floor.

### Phase 1 — RED tests first (`cq-write-failing-tests-before`)

- Add the T-9799 rows in `ci-deploy.test.sh` (all fail against the current `openssl` form where applicable), the staleness check 11 (fails on the current `zot v2.1.22` comment), and the new battery cases. Confirm each is RED for the stated reason before any source edit.
- T-9799 row design (extends the T-9795 harness; synthetic secrets only, `cq-test-fixtures-synthesized-only`):
  1. **Byte-identity matrix**: 6 secrets (`fixture-fanout-secret`, 63-, 64-, 65-, 200-byte, `a"b\c $d 'e;f|g&h`) x 3 `SSH_ORIGINAL_COMMAND` values (plain, quotes/backslash/unicode, long) = 18 comparisons of the stdin-config signature against `openssl dgst -sha256 -hmac` computed in the test; asserts exactly 18 ran and every signature is 64-hex.
  2. **No secret on any argv**: `python3`, `openssl` and `curl` shadow functions record argv; the secret string appears in none; `openssl` is never invoked.
  3. **Empty secret and `"null"`** (two hooks files): rc 1, curl never called, no stdin config produced.
  4. **python3 unavailable** (shadow function returning 127): rc 1, curl never called.
  5. **Malformed signature** (shadow `python3` printing a non-hex string): rc 1, curl never called.
  6. **Source census**: the `fan_out_to_peers` body and the file contain no `openssl dgst`, and the canonical snippet is present once.
  7. **Key not on argv under a real python3**: the `python3` shadow records `"$*"` of the real call and `HMAC_KEY` presence, asserting the key is in the environment of that call only.
- Raise `CI_DEPLOY_ASSERT_FLOOR` to the measured total in the same edit, with a dated history comment in the file's style.

### Phase 2 — GREEN: item 3 then item 2 source edits

- `ci-deploy.sh` `fan_out_to_peers` conversion; re-run T-9795-1/-2 (must stay green, they pin the request shape) and T-9799.
- `ci-deploy.sh` comment reword; `zot-image-staleness.test.sh` edits; sidecar edits; battery retargeting. Dry-run the sidecar's revert recipe in a scratch detached worktree (`git revert --no-commit` of the branch's commits, then the gates the revert PR must pass), per the 2026-10-09 learning.

### Phase 3 — mutation proof by hand

- For Guard 2 rows 1-5 and Guard 1 rows 1-4: apply each mutation to a scratch copy, confirm the named row reddens, restore. Record the rc/marker table in the PR body's test section.

### Phase 4 — gates

- `python3 scripts/lint-shell-trace-credential-refusal.py --changed` and plain runs; `bash scripts/check-deploy-script-parity.sh --self-test` and `bash scripts/check-deploy-script-parity.test.sh` only (no live arm: the live arms read web-1 status and Better Stack via Doppler, and the hold says not to touch web-1); `bash apps/web-platform/infra/zot-image-staleness.test.sh` (16/0), the battery, `ci-deploy.test.sh`, and `bash apps/web-platform/infra/run-registered-suites.test.sh` if the suite registry is affected (no new suite files are added, so shard manifests need no change).
- `git diff --name-only origin/main...HEAD` shows none of `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, `server.tf`.
- Typecheck is left to CI (local `apps/web-platform/node_modules` is stale; no TypeScript file changes).

### Phase 5 — ship

- Commit bodies per the Delivery Contract; `/ship` handles the deploy-pipeline-fix gate (the operator-notice path for trigger-file edits), review and the merge queue. After merge: one comment on #9597 noting the `ci-deploy.sh` S4 row is done (no new issue). Tracker #9799 stays open for items 1, 4 and the addendum.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash apps/web-platform/infra/zot-image-staleness.test.sh` exits 0 with `RESULT: 16 passed, 0 failed` and `MIN_ASSERTIONS=16`.
- [ ] `git grep -nE 'zot \(?v[0-9]+\.[0-9]+\.[0-9]+' apps/web-platform/infra/ci-deploy.sh` returns nothing.
- [ ] Check 7 followers and required locations are exactly `ci-deploy.test.sh` and `cloud-init-registry.yml`; check 11 asserts `ci-deploy.sh` exists and carries zero claims.
- [ ] `bash apps/web-platform/infra/zot-image-staleness-mutation.test.sh` reports every case behaving as expected, including the new rows 1-4 and the coherent-bump GREEN case, whose sandbox asserts `ci-deploy.sh` is `cmp`-identical to pristine (this IS the "a bump no longer requires touching ci-deploy.sh" test).
- [ ] `git grep -n 'openssl dgst' apps/web-platform/infra/ci-deploy.sh` returns nothing; the "Known remaining site" comment is gone.
- [ ] `bash apps/web-platform/infra/ci-deploy.test.sh` is green with the raised `CI_DEPLOY_ASSERT_FLOOR` equal to the measured total; T-9795-1/-2 unchanged and green; T-9799 rows cover the 18-comparison byte-identity matrix, no-secret-on-argv, empty and `null` secret, python3 unavailable, malformed signature, source census.
- [ ] Hand-run mutation table (Phase 3) recorded in the PR body; each row went RED for the stated reason and was restored.
- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py` (plain and `--changed`) is OK with no baseline edit; `bash scripts/check-deploy-script-parity.sh --self-test` and `scripts/check-deploy-script-parity.test.sh` pass.
- [ ] The sidecar revert recipe, executed once in a scratch worktree, leaves `zot-image-staleness.test.sh` green; recipe text no longer names `ci-deploy.sh` as a claim carrier and states the marker requirement conditionally.
- [ ] Diff name list contains none of `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, `server.tf`, `.github/workflows/*`.
- [ ] Every commit touching `ci-deploy.sh` and the final squash body carry `[skip-web-platform-apply]` and `[skip-deploy-fix-apply]` alone on their own lines, no `[ack-destroy]`.
- [ ] PR body: `Ref #9799`, `Ref #9597`, no `Closes`/`Fixes`/`Resolves` next to either, the delivery-waits-for-next-sanctioned-apply statement, no use of the banned word from the brief, ends with the Claude Code attribution line.

### Post-merge

- [ ] #9799 remains open (items 1, 4 and the addendum), one comment on #9597 records the `ci-deploy.sh` row as done. Delivery to running hosts is tracker item 1 and is not an action of this PR.

## Test Scenarios

- Given the pin bumped to a new version in `zot-registry.tf`, the sidecar, `ci-deploy.test.sh` and `cloud-init-registry.yml`, when the staleness gate runs, then it exits 0 with `ci-deploy.sh` unchanged (unit; the battery's GREEN case).
- Given a `zot vX.Y.Z` token reintroduced in `ci-deploy.sh` (current or stale), when the gate runs, then it exits 10 naming check 11 (unit).
- Given a stale claim in only one remaining follower, when the gate runs, then it exits 10 (unit).
- Given a hooks file with secret S and a payload P, when `fan_out_to_peers` runs, then the stdin config carries exactly `openssl dgst -sha256 -hmac S` of P and S appears on no argv (integration against the real function).
- Given an empty or `null` secret, python3 unavailable, or a non-hex signature, when `fan_out_to_peers` runs, then it returns 1, logs a `FANOUT:` line and calls curl zero times (integration).
- Regression: T-9795-1/-2 (request shape, header on stdin) stay green.

## Risks and Sharp Edges

- **python3 on the host.** Documented as always present (cloud-init dependency); absence fails closed and is logged, so the worst case is a visible "web-2 down" release message, never an unsigned request. If a host lacked python3 the previous openssl form would have kept working — the trade is a new hard dependency for a removed exposure; recorded, accepted.
- **The environment is not a vault.** `HMAC_KEY` in the child's environment is visible to root and the same uid via `/proc/<pid>/environ` for the child's lifetime (milliseconds); that is the repo-wide decided exposure class (#9597). Do NOT export `HMAC_KEY` in the shell (per-command prefix only).
- **Trigger-file hunk size.** Keep both `ci-deploy.sh` hunks minimal; do not reflow neighbours (conflicts with #9529/#9767 and a larger redelivery diff).
- **Check 11 regex.** `CLAIM_RE` only catches `zot v1.2.3` / `zot (v1.2.3` shapes; a reworded version token (`zot 2.1.22`) is invisible to it, as it is to check 7 today. The shared variable is the single widening point; do not add a second regex.
- **`MIN_ASSERTIONS` / `CI_DEPLOY_ASSERT_FLOOR`:** raise to the measured counts in the same edit; never leave slack.
- **A plan whose `## User-Brand Impact` is empty or placeholder text fails deepen-plan.** This one carries the scope-out bullet because the diff touches `apps/*/infra/`.
- **Parent-session notes:** no `pkill -f`, never `git stash`, always `cd <worktree> &&` in Bash, no memory writes. Net-issue-flow: no new issues; any hook demanding them needs measured `User-Impact:` and `Fix-Size: N lines / M files` lines (this plan: ~230 lines / 5 files).
