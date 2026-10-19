---
title: "feat: Inngest TLS with certificate verification (encryption-posture private-network exceptions, Inngest leg)"
type: feat
date: 2026-10-18
slug: inngest-tls-verification
branch: feat-one-shot-10136-inngest-tls-verification
issue: 10136
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# feat: Inngest TLS with certificate verification

## Enhancement Summary

**Deepened on:** 2026-10-18. **Research and review agents used:** terraform-architect, security-sentinel, observability-coverage-reviewer, user-impact-reviewer, deployment-verification-agent, three general-purpose verification agents (Doppler/actuator/delivery census, container experiments with stunnel/nft/Node, mechanical negatives and citations), CTO (rulings G1-G6) and the earlier plan-review panel.

**Key improvements:** (1) the flip actuator credential question is resolved to a Tier-B Terraform-managed flag (no new token), (2) the resolver reads the flag from the env snapshot and never downgrades with the flag on, (3) the CA file is validated and base64-delivered, (4) an `## Downtime & Cutover` section grounded in measured replace incidents, including the inherited-`done` strand (A1b `op=resume`) the first draft omitted, (5) measured stunnel/nft/Node/Doppler behaviour replaced assumptions, (6) the probe wiring was corrected (the consumer probe has no web-2 twin, so link resolution lives in the registry probe), (7) the refusal marker must use the multi-line `emit_refusal` form or the drift guard reds, (8) user-visible failure modes (lost spawns, 502 on reminder arming, swallowed Stripe sends) are named with follow-ups.

**New considerations:** key in the `inngest-server` environment (accepted), the CA as a trust anchor for all Node outbound TLS (CA:FALSE, SAN-bound), event-key rotation, the 2026-10-28 #10405 checkpoint, and the Better Stack query-limit truncation of the 48 h soak.

Ref #10136, Ref #10205 (item 4), Ref #10382 (row 1), Ref #9139. Draft PR #10501. This plan never closes #10136: the issue stays open for the zot rows, the ledger and legal-wording PR, and the Cloudflare leg (#10479).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
IaC routing note (Phase 2.8 reviewed): every infrastructure resource in this plan is Terraform or cloud-init (see `## Infrastructure (IaC)`). The two phrases the plan-write guard matches are (1) unit-enable lines that are cloud-init `runcmd` content, and (2) the single non-secret flag write `INNGEST_LINK_TLS` to Doppler `soleur/prd`, which is a runtime toggle recorded as a production act under the owner's recorded go (the invocation lists Doppler secret writes as production actions). The Terraform-managed alternative for the flag (ignore_changes on the value plus a replace dispatch) is recorded under Alternatives Considered.

## Overview

The web-platform app talks to the dedicated Inngest host (`10.0.1.40`) over plain HTTP on `:8288`. That hop carries `INNGEST_EVENT_KEY` (in the `/e/<key>` path), the hashed signing key as a Bearer on run-list reads, and event payloads (user prompts and agent output). The CTO and CLO rulings of 2026-10-18 (issue comment on #10136; `/var/tmp/10136-rulings/issue-comment-rulings.md`) require TLS with certificate verification on this hop, live by 2026-11-12 (fallback 2026-11-19; CLO hard stop 2026-12-10). The owner go is recorded (2026-10-18, #10136): build the PR, one Inngest host replace by 2026-11-05, and `INNGEST_SIGNING_KEY` rotation.

The design (ruled in detail by the CTO on 2026-10-18, see Rulings table):

- A host-local `stunnel4` terminator on the Inngest host, `10.0.1.40:8443` to `127.0.0.1:8288`, in its own systemd unit that `inngest-server` does not depend on.
- A self-signed ECDSA cert with SAN IP `10.0.1.40`, minted by Terraform (`proxy-tls.tf` pattern), key and cert delivered through Doppler, never baked in user_data.
- The CA reaches web containers as a host file `/mnt/data/inngest-link/inngest-ca.pem` (written by `ci-deploy.sh` from Doppler), mounted read-only, with `NODE_EXTRA_CA_CERTS` at the three `docker run` sites.
- The URL flip is data-driven: a Doppler flag `INNGEST_LINK_TLS=1` read by one resolver in `ci-deploy.sh`. Flip and rollback need a Doppler write and a redeploy, never a code merge. This is what makes "one PR, inert until the host replace" possible under a merge queue that forbids sync pushes.
- Old `:8288` stays open for the soak, with a named nftables counter `legacy_8288`. The soak closes on 48 h of gap-free emits with delta zero.

Everything in this PR is **inert at merge**: the default resolver output is still `http://10.0.1.40:8288`; the new Terraform resources are unreferenced; the new egress accept, CA file and probes are additive. Nothing changes for running traffic until (1) the single Inngest host replace, (2) the flag flip through a canary deploy.

## Research Reconciliation: Spec vs. Codebase

| Spec / ruling claim | Reality (origin/main `840dc667fc`) | Plan response |
|---|---|---|
| CTO: "public cert committed" (proxy-tls precedent) | `tls_self_signed_cert` computes validity at apply, so a committed PEM cannot exist before the first apply; a committed generator would pass the private key through an agent session. | CTO amended (D2): no committed cert. One Terraform cert resource feeds three Doppler copies, so drift is structurally impossible. Runtime verification replaces the committed-copy check. |
| "NODE_EXTRA_CA_CERTS at the three docker run sites" | Node needs a readable file path; the tuple gate (`lib/docker-run-tuple.py`) pins exact `-e` value sets and exact `-v` strings; docker creates a DIRECTORY for a missing bind source; web-1 cloud-init is frozen (`ignore_changes=[user_data]`). | CA is a host file written by `ci-deploy.sh` before every `docker run`; gate gains the `-v` string and env key; placeholder file when the flag is off (D3). |
| "counter on the old 8288 rule" | `nft list chain` prints `counter packets N bytes M` which changes per read; PR #10405 adds an `nft_sha256` fingerprint of the raw chain listing in the boot `net-health` emit. An inline counter makes the fingerprint vary per read. | A separate, preceding, verdict-less rule `counter name "legacy_8288"` (named counter object). Existing accept line stays byte-identical (`inngest-host.test.sh` greps it); chain text stays stable (D6). |
| "~8 probe scripts to --cacert" | Measured: three web-host probes hit `10.0.1.40:8288` (`inngest-registry-probe.sh`, `inngest-doublefire-probe.sh`, `inngest-consumer-probe.sh`), one inngest-host self-curl diag, one app fallback constant. Every other `8288` reference is loopback (`127.0.0.1:8288`) and unaffected. | Link resolution lives in `inngest-registry-probe.sh` (the consumer probe sources it; the doublefire probe reads the same default), so `inngest-consumer-probe.sh` and its web-1-only provisioner are not edited; the host self-curl stays http (it hits the legacy listener on purpose); the fallback constant stays http (D4) and is unused because the container always receives `INNGEST_BASE_URL`. |
| Infra-merge rule: read `registry-host-replace-dispatch.md` | That runbook covers the registry dispatcher. The Inngest host has no dispatcher analogue: replace is `apply-web-platform-infra.yml -f apply_target=inngest-host-replace` (environment `infra-privileged`, shared inngest mutex, destroy-guard, stock preflight). | Both are read in Phase 0; the double-replace hazard (read the apply run list before any re-fire) applies to both. |
| Owner go: replace "after the TLS PR and #10405 are merged and deployed" | #10405 is a DRAFT, OPEN, last updated 2026-10-15, base blob stale (hunk offsets ~36 lines behind main). | Hard precondition on the replace (Production Actions). This PR touches different hunks and does not touch the `net-health` emit or `inngest-cutover-flip.sh` (D7). |
| CLO: TLS must cover three legs | The sdk_url poll (`--sdk-url http://10.0.1.10:3000/api/inngest`, every 60 s) needs a TLS listener on the web hosts, which do not have one (proxy TLS server is dormant behind `host_proxy_tls_enabled=false`). The step-call driver refuses private IPs and runs through Cloudflare (`serveHost https://app.soleur.ai`); Cloudflare to origin is flexible/plain (#10479). | CLO (same day, narrower question) allowed the poll as a dated second step to 2026-12-10; CTO ruled (c). Step-call leg is gated on #10479. This PR covers legs 2 and 3 by explicit dated rows and closure predicates, not by absorbing #10479 (Legs section). |
| (not in rulings) user_data size | `bash apps/web-platform/infra/inngest-userdata-budget.sh` measured 2026-10-18: stored 30,916 B, cap 32,768 B (headroom 1,852 B); the repo test budget `INNGEST_GZIP_BUDGET = 32_300` leaves 1,384 B. | Top implementation risk. Phase 0 measures the real delta first; fallback ladder in Risks. |
| (not in rulings) web-host egress | Container egress is default-drop (`cron-egress-nftables.sh`); only `10.0.1.40:8288` is allowed. `:8443` would be silently dropped. | New accept rule + postapply assert + test, delivered by the existing `deploy_pipeline_fix` / `cron_egress_firewall` provisioners (web-1 and web-2 twins already exist). |
| Brief: "whether Connect gateway ports are used" | No app code uses Connect (`inngest/next` serve only; SDK 3.54.2). Ports 8289/50052/50053 are wildcard-bound; only 8289 is in the nft drop set. | Left unchanged, recorded as a pre-existing residual in Risks; not part of this PR. |
| Brief: "Inngest v1.45.1 TLS flags" | `cmd/start/cmd.go` at tag v1.45.1 has zero `tls\|ssl\|cert` strings (source-level, read via `gh api`). The binary's `--help` was NOT run. | Phase 0 runs `inngest start --help` from the sha256-verified tarball in a scratch dir. |
| `--host 0.0.0.0` (inngest-bootstrap.sh ExecStart) | The plaintext listener binds all interfaces; nftables is the only scoping. Binding loopback needs a bootstrap-image rebuild. | Not changed here (second replace). Follow-up issue: bind loopback at the next unrelated replace (D6). |

## Research Insights

**Premise validation (Phase 0.6).** Checked by command: `gh issue view` on #10136 (OPEN), #10382 (OPEN), #10205 (OPEN, epic), #10479 (OPEN), #9139 (OPEN); `gh pr view 10405` (DRAFT, OPEN, branch `feat-inngest-arc-window`, 8 files); `gh pr view 10501` (this PR, draft). `gh run list` for `apply-web-platform-infra.yml` (last 5 all success, latest 2026-10-18T03:35Z) and `registry-host-replace-dispatch.yml` (last 5 all success, latest 2026-10-15T18:39Z): nothing in flight at planning time. ADR corpus grep for the mechanism (TLS terminator, self-signed pin, flag flip): ADR-100 (dedicated Inngest host), ADR-118 amendment (proxy cert SANs, `host_proxy_tls_enabled`), ADR-135 (config-refresh channel), ADR-140 (encryption posture), ADR-243 (serve streaming) read; none rejects a host-local terminator. Nothing cited was stale.

**Property list (Phase 0.6b).**

- P1. After the flip, every app-to-Inngest request on the send path (events, run-list reads, GraphQL probes) uses TLS and the client verifies the server cert against the pinned CA.
- P2. Before the flip, nothing observable changes (inert merge).
- P3. Flip and rollback are one Doppler write plus a redeploy; neither needs a code merge.
- P4. Residual plaintext use of `:8288` from web hosts is measurable off-box (no SSH) and provably zero over 48 h before the soak closes.
- P5. Verification is really on: a client without the CA fails the handshake.
- P6. Legs 2 (sdk_url poll) and 3 (Cloudflare step-call) each have a dated, owned disposition and a closure predicate.
- P7. The signing key is rotated only after the link is protected, and a "no known access" record follows.

**Cut list (Phase 0.6b).**

| Mechanism | Property it would buy | Cut because |
|---|---|---|
| Committed public cert + generator script | P1 | Unsatisfiable in one PR; key would transit an agent session. Terraform + Doppler single source already buys it (D2). |
| CA baked into the app image | P1 | Ties rollback to an image rebuild; host-side probes need a host file anyway (D3). |
| Second PR (or code-line commit) for the flip | P3 | Doppler flag buys it with no merge (D4). |
| New Vector tag / bootstrap-image mint for TLS health | P4 | `inngest-boot-phone-home.sh` posts directly to Better Stack and its tag is already allowlisted (D6). |
| `--host 127.0.0.1` now | P4 | Needs an image rebuild plus a second replace; follow-up instead (D6). |
| Web-side TLS listener for the sdk_url poll | P6 | Multi-host epic; poll carries HMAC and public metadata only (D5). |
| Repoint `--sdk-url` to `https://app.soleur.ai` | P6 | Worse than today while Cloudflare is flexible (CLO, CTO). |
| Ledger / `docs/legal/**` edits in this PR | P6 | CLO: separate later mirror-paired PR after handshake evidence. |
| Restrict Connect ports 50052/50053 | (none) | Not used by app code; out of scope. |

**Institutional learnings applied** (learnings-researcher, 15 hits): `2026-07-03-cloud-init-32kb-cap-bake-and-extract-not-compress.md` and `2026-07-06-cloud-init-user-data-cap-bake-bodies-and-set-e-scope-fix-ungates-security-checks.md` (comments count toward the cap; `set -e` leaks across runcmd items, so every cert/key/nft check must be explicitly fail-closed); `2026-07-26-an-existence-assertion-that-ran-before-the-file-existed-bricked-every-boot.md` (put `test -f` after the heredoc that writes it); ADR-118 amendment (cert resources count-gated until the flip, SANs track the roster); runbook `inngest-server.md` (a replaced host inherits Doppler-held state; replace is the only delivery path); `inngest-host-no-cloud-firewall-8754-postmortem.md` and `2026-07-07-immutable-redeploy.md` (replace must carry the network, volume and firewall attachments; verify the private NIC from the boot event); ADR-052 and `2026-10-05-docker-interbridge-reply-path-ct-state-new.md` (first-match-wins order; scope drops to `ct state new`); `2026-06-14-nft-injection-via-unvalidated-config-reject-whole-file.md` (validate values interpolated into `nft -f`); `2026-04-06-node-slim-missing-ca-certificates.md` (Node uses its own store, so `NODE_EXTRA_CA_CERTS`; no learning mentions it, so Phase 0 and the canary test it); `2026-07-19-a-false-comment-correction-carried-two-new-false-claims.md` (audit argv/stderr of any new unit before it can reach a third-party log sink). Gaps: nothing on stunnel/nginx terminators or cert-expiry monitors.

**Measured facts feeding the design** (repo-research-analyst, read-only, 2026-10-18): Inngest server flags at v1.45.1 have no TLS option; the server runs `inngest start --host 0.0.0.0 --port 8288 --poll-interval 60 --sdk-url http://10.0.1.10:3000/api/inngest`; the step-call driver (`pkg/execution/exechttp`) refuses private IPs and uses Go's default TLS verification (no `InsecureSkipVerify`); Go on Linux honours `SSL_CERT_FILE`/`SSL_CERT_DIR` (stdlib docs; not verified against this binary, and not needed under the D5 ruling). Node 26 here accepts an empty, missing or directory `NODE_EXTRA_CA_CERTS` without failing (probed locally 2026-10-18); production runs `node:22-slim`, so the canary must re-verify on Node 22.

**Measured at deepen (2026-10-18, throwaway containers and read-only CLI calls; fixtures to commit).**

- stunnel4 on ubuntu:24.04: package `3:5.72-1build2`, OpenSSL 3.0.13; user and group `stunnel4` (uid/gid 995, nologin); the packaged units are the template `stunnel@.service` and `stunnel.target` with NO instance enabled and a SysV script installed disabled (`defaults-disabled`); the unit has no `User=` or `Type=`, so stunnel runs as root and needs `foreground = yes`; `stunnel4 -test` is unsupported (read as a config file name), so there is no dry run. Config keys that parse: `foreground`, `pid =`, `syslog = no`, `debug`, `setuid`, `setgid`, `sslVersionMin = TLSv1.2`, `ciphers = ECDHE+AESGCM:ECDHE+CHACHA20`, `ciphersuites`, `options = CIPHER_SERVER_PREFERENCE`/`NO_TICKET`, `accept`, `connect`, `cert`, `key`; unknown keys fail with `"<key>": Specified option name is not valid here`.
- Handshake behaviour: `curl --cacert good.pem` succeeds; without `--cacert` curl exits 60 (`self-signed certificate`); a cert whose SAN lacks the IP exits 60 (`no alternative certificate subject name matches target host name`); TLS 1.0/1.1 are refused; a client offering only `AES256-SHA` gets `no shared cipher`. A key at `0640 root:stunnel4` works with `setuid = stunnel4` and survives a SIGHUP reload; `0600 root:root` starts but the reload fails (`Permission denied`, `Failed to reload the configuration file`). Key and cert bytes never appear in any stunnel log line, even at debug level.
- stunnel failure and success lines for fixtures: unreadable key `SSL_CTX_use_PrivateKey_file ... Permission denied` then `Failed to initialize TLS context`, missing key `<path>: No such file or directory (2)`, mismatched pair `key values mismatch`, bad option `Illegal TLS option`, port busy `Binding service [inngest] failed`, connect target down: curl exit 56 and `s_connect: connect 127.0.0.1:<port>: Connection refused (111)`, success `Configuration successful` and `Service [inngest] accepted connection from ...`. Handshake failures from a rejecting client log as `SSL_accept: ... unsupported protocol` only for protocol errors; a client that aborts on a bad cert leaves only a normal accept/close line, which is why `hs_fail_15m` is a weak signal and `served_sha256` plus the canary are the real proofs.
- nftables v1.0.9: `nft -c -f` passes the planned ruleset; `nft list chain inet soleur_inngest input` carries no packet counts (named counters print as `counter name "legacy_8288"`); `nft list counter inet soleur_inngest legacy_8288` prints `packets N bytes M` (measured `packets 6 bytes 338` after real traffic from a peer netns using a web source address), parsed by `awk '/packets/{print $2}'` / `$4`; a non-allowlisted source times out on the drop; loading the same file twice exits 0 but merges (6, 12, 18 rules), which evidences the boot-only claim; a variant that begins with `table ...` then `delete table ...` is idempotent and resets counters.
- Node 22 (`node:22-slim` v22.23.3): `NODE_EXTRA_CA_CERTS` is loaded lazily on first TLS use; empty file and directory are silent and verification then fails with `DEPTH_ZERO_SELF_SIGNED_CERT`; a missing path prints `Warning: Ignoring extra certs from <path>, load failed` at first TLS use; a valid PEM through stunnel returns 200; without the env var `FAIL DEPTH_ZERO_SELF_SIGNED_CERT`; a wrong CA still fails; `NODE_TLS_REJECT_UNAUTHORIZED=0` alone defeats verification (hence the pinned absence); Node 22 verifies IP SANs for an IP-literal URL (`ERR_TLS_CERT_ALTNAME_INVALID` when only a DNS SAN exists); plain `http://` to the TLS port gives `ECONNRESET`.
- Doppler CLI read errors (local 3.77.0; hosts run 3.75.3): a missing secret prints `Doppler Error: Could not find requested secret: NAME` rc 1 (colour codes are emitted even when piped); a bad config/project prints `Could not find requested config|project ...`; a bad token prints `Invalid Auth token`; an unreachable API prints a `dial tcp` error. The CTO ruled the resolver reads the flag from the env snapshot, so none of these strings is parsed.
- Delivery census (read from `server.tf` and the workflows' `paths:`): `ci-deploy.sh` and `hooks.json.tmpl` reach web-1 by the infra-config webhook and web-2 by the `deploy_pipeline_fix_web2` SSH twin; `cron-egress-nftables.sh` and its postapply assert reach web-1 via `cron_egress_firewall` and web-2 via `deploy_pipeline_fix_web2`; `inngest-registry-probe.sh` and `inngest-doublefire-probe.sh` are in the `apply-deploy-pipeline-fix.yml` paths and both twins; `inngest-consumer-probe.sh` is NOT in those paths and `inngest_consumer_probe_install` has no web-2 twin (so web-2 never receives it; it is `birth-covered` in the parity test); `cloud-init.yml` reaches fresh hosts only (`hcloud_server.web` ignores user_data changes). `cron-egress-nftables.sh` already carries `tcp dport 8443 accept` for the egress gateway, so the new postapply assert must grep `10.0.1.40 tcp dport 8443 accept`, not a bare `dport 8443`.
- Flip credential survey: `DOPPLER_TOKEN_WRITE` is `prd_terraform` only (Tier B); the inngest arm token is `soleur-inngest/prd` only; `DOPPLER_TOKEN_GIT_DATA_FLAG` is unprovisioned (#8573 open); Doppler tokens are config-scoped so a token that can write `soleur/prd` can write every prd secret.
- User-visible send behaviour read from code (`server/inngest/send-with-retry.ts`: three attempts, 0.5 s then 1 s backoff, then throw): dashboard send route archives the draft on failure; `schedule-reminder` returns 503 only for connection refusal; the Stripe webhook swallows a failed send and returns 200 with the dedup row claimed.
- Corrections to the first draft found at deepen: the replace job has no confirm or id-pin input (only `reason`); the first draft omitted the inherited-`done` strand and `op=resume`; the consumer probe has no web-2 twin; the drift guard needs the multi-line `emit_refusal` form; the isolation-regex rows live in `inngest-host.test.sh`; ADR-291 is claimed by a pushed branch; `early_renewal_hours` conflicts with `prevent_destroy`.

**Code-review overlap (Phase 1.7.5).** Open `code-review` issues touching planned files: #10243 (nft comment correction on `cloud-init-inngest.yml`): already satisfied on main (the comment now records that `nft -f` merges and the bare declare is boot-only safe); **Acknowledge**, close candidate, no fold. #10112 (residuals of parked #10081 on `cloud-init-inngest.yml` and the ledger): **Acknowledge**, different concern (image-baked rollback arm, rehearsal volume), needs its own cycle. #3216 and #2197 match `server.tf` only by path substring on unrelated billing/canary content: **Acknowledge**, unrelated.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "implement Inngest TLS with verification per the CTO and CLO rulings" | Phases 1-4 | mapped |
| 2 | "Terminator unit in cloud-init-inngest.yml (:8443 -> 127.0.0.1:8288, nft accept for web IPs, counter on old 8288 rule)" | Phase 2 (stunnel unit, nft rules, named counter) | mapped |
| 3 | "self-signed cert SAN IP 10.0.1.40 on the proxy-tls.tf precedent (key in Doppler, public cert committed)" | Phase 1 (`inngest-tls.tf`); "committed" amended by CTO D2 | mapped (amended) |
| 4 | "NODE_EXTRA_CA_CERTS at the three docker run sites" | Phase 3 (resolver, CA file, tuple gate) | mapped |
| 5 | "`INNGEST_BASE_URL=https://10.0.1.40:8443`" | Phase 3 resolver output when flag on | mapped |
| 6 | "~8 probe scripts to --cacert" | Phase 3 (registry and doublefire probes, the consumer probe via the registry probe it sources, and the `--tls-handshake` mode; the rest are loopback) | mapped |
| 7 | "merge web side inert; one host replace bundled with draft PR #10405" | Inert matrix, Production Actions A1 | mapped |
| 8 | "flip URL via canary; 48h soak; 8288 counter stays zero" | Production Actions A3-A4, Guard 2, follow-through | mapped |
| 9 | "Also cover the three TLS legs: :8288 send path, sdk_url callback to 10.0.1.10:3000, Cloudflare serve-URL step-call (#9139)" | Legs section; dated rows; closure predicates | mapped |
| 10 | "INNGEST_SIGNING_KEY rotation (#10382 row 1) go given" | Production Actions A5; the apply route is the separate rotation follow-up (CTO F3), A5 waits on it | mapped (executed after the follow-up) |
| 11 | "PR body uses Ref #10136 never closing keywords and includes ## Changelog" | Acceptance Criteria (ship) | mapped |
| 12 | "before any infra merge check gh run list for apply-web-platform-infra.yml and registry-host-replace-dispatch.yml and read knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md" | Phase 0 step 1 | mapped |
| 13 | "ship to verified production state (deploy-arm.sh find --wait <full-sha> then served <full-sha> from a detached origin/main worktree)" | Acceptance Criteria (post-merge) | mapped |
| 14 | "#10479 (Cloudflare flexible SSL) is a separate tracker, not in this PR" | Legs section (gate predicate only) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `inngest-tls.tf` | "self-signed cert SAN IP 10.0.1.40 on the proxy-tls.tf precedent" | asked |
| stunnel unit + nft rules | "Terminator unit in cloud-init-inngest.yml" | asked |
| Doppler flag resolver in `ci-deploy.sh` | "flip URL via canary" and "merge web side inert" | asked (mechanism ruled by CTO D4) |
| Web egress `:8443` accept | "`INNGEST_BASE_URL=https://10.0.1.40:8443`" (the URL is unreachable without it) | inferred - justification: container egress is default-drop; verified in `cron-egress-nftables.sh` |
| `tls-health` periodic emit + soak follow-through | "48h soak; 8288 counter stays zero" | asked |
| Handshake evidence (`--tls-handshake` mode of `inngest-registry-probe.sh`) | "a post-merge probe plan (handshake with verification on, 8288 counter delta zero)" | asked |
| `inngest-link-flip.yml` workflow with lease and revert step | "flip URL via canary" and "never ask the owner to watch CI or paste logs" | asked (mechanism ruled by CTO F6; it is how a flip happens with no merge) |
| ADR-292 + C4 edit | (none) | inferred - justification: Phase 2.10 gate; a new trust-boundary mechanism is an architectural decision |
| Better Stack alert for listener/cert expiry | "key in Doppler" custody (a 10-year cert needs an expiry monitor, `proxy-tls.tf` precedent) | inferred - justification: CTO D2 requires an alert under 90 days |
| Runbook section in `inngest-server.md` | (none) | inferred - justification: hr-no-ssh-fallback-in-runbooks; flip, rollback and replace order must be written down |

### Split Assessment

- Subsystems touched: 4 roots - `apps/web-platform/infra`, `.github/workflows`, `apps/web-platform/test`, `knowledge-base` (+ `scripts/followthroughs`, `plugins/soleur/test`).
- Planned files: ~38 | Estimated changed lines: ~900 (tests dominate).
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines - all three trip.
- Recommendation: single PR - **owner constraint ("one PR") and a technical reason**: the host replace delivers `cloud-init-inngest.yml` only once, the data-driven flag removes the need for a second code commit, and splitting the web side from the host side would let either half merge without its counterpart's tests. The ledger and legal-wording PR is a deliberate later PR (CLO ruling), not a split of this one.

## User-Brand Impact

- **If this lands broken, the user experiences:** an approved Concierge action (`agent.spawn.requested`, `actionSendId`) whose send fails is archived with no agent run (`app/api/dashboard/today/[id]/send/route.ts` sets `degraded = enqueue_failed` and archives the draft anyway), a reminder arm (`reminder.scheduled`, `reminderId`) returns 502 "Dispatch failed" on a TLS or timeout failure and nothing is persisted (`app/api/internal/schedule-reminder/route.ts` maps only ECONNREFUSED to the retryable 503), and a `finance.payment_failed` send failure is swallowed with the Stripe dedup row already claimed so the CFO draft is permanently skipped; the replace window can lose the same kinds of work. All of these fail today whenever the scheduler is unavailable; the flip and the replace add new ways to trigger them.
- **If this leaks, the user's prompts and agent output are exposed via:** the existing plaintext `:8288` hop, readable by any peer on `10.0.1.0/24`: event payloads (prompts, agent output), `INNGEST_EVENT_KEY` in the `/e/<key>` path (a sniffed key permits forged `agent.spawn.requested` / `finance.payment_failed` events until it is rotated; TLS does not invalidate it - event-key rotation is tracked as O5 with a dated issue), and the hashed signing key as a Bearer on run-list reads. Residual after this PR: step outputs between Cloudflare and the origin stay plaintext until #10479, and the `sdk_url` registration poll stays plaintext until 2026-12-10 (Phase 0 records whether its response can alter registered step URLs; if it can, an on-net peer could redirect step calls, which is a void trigger for that leg). This PR narrows the exposure; a mis-flip leaves clients on http and the soak counters detect it.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one founder's prompts or agent output readable on a shared subnet, or forged agent spawns running under their account, is a single-user brand event on its own; that is the exposure this PR exists to close. The aggregate argument (a broken flip degrades every user at once) reinforces it but is not the basis.

`requires_cpo_signoff: true`. `soleur:engineering:review:user-impact-reviewer` runs at review time. CPO sign-off is recorded in Domain Review below.

## Legs: how the three TLS legs are covered

| Leg | Today | This PR | Closure predicate / owner |
|---|---|---|---|
| 1. App to Inngest `:8288` send path (events, run-list reads, GraphQL probes) | plain HTTP, private net | **Implemented**: `stunnel4` on `:8443`, pinned CA, flag-gated flip, legacy counter | 48 h soak with `legacy_8288` delta zero + handshake evidence; then the later ledger/legal PR converts the row |
| 2. Inngest server to app `sdk_url` poll (`http://10.0.1.10:3000/api/inngest`, 60 s) | plain HTTP; HMAC-signed request, public function metadata, no user content or key material | **Dated disposition only** (CTO D5 (c), CLO 2026-10-18 conditions): own ledger row, longest date **2026-12-10**; replacement (web-side listener or poll removal) chosen and merged by **2026-11-12** per CLO; never repoint `--sdk-url` to the public host while Cloudflare is flexible | Needs an **owner-signed accepted-risk record** for the row (owner item, legal-risk; Production Actions A7). Voids on: user content/key material found on the poll, step driver able to use the link, a server beyond the five attached hosts, any non-Jikigai peer or public exposure, a replay beyond HMAC. Tracked by a new issue (Deferral Tracking) |
| 3. Step-call through Cloudflare (`serveHost https://app.soleur.ai`, step outputs = user content) | TLS to the Cloudflare edge; Cloudflare to origin flexible (plain HTTP over the public internet), #10479 | **Modelled, not fixed**: own ledger row (per #9139) marked blocked-by #10479; no Cloudflare change here | #10136 may not close until #10479 is green (live zone mode verified, origin serves TLS the edge verifies). No exception, renewal or acceptance past 2026-12-10 without a fresh CLO ruling; the CLO will not clear Privacy Policy s11 until #10479 settles the live mode |

Ledger values (`tls`, `cert_verification`, `disclosed_as`, `expires_on`) and all of `docs/legal/**` are NOT changed in this PR (CLO ruling 4); at most `enforced_at` pointers if the encryption-posture lint forces them. The later PR carries the mirror-paired privacy documents, SHA pins and CLO attestation, and must land before the 2026-11-12 re-review.

## Rulings (persisted in `knowledge-base/project/specs/feat-one-shot-10136-inngest-tls-verification/decision-challenges.md`)

| Fork | Ruling (condensed) |
|---|---|
| D1 Terminator | `stunnel4` (apt) in `soleur-inngest-tls.service`; `accept=10.0.1.40:8443`, `connect=127.0.0.1:8288`, TLS >= 1.2; `ExecStartPre=+` fetches `INNGEST_TLS_KEY`/`INNGEST_TLS_CERT` from `soleur-inngest/prd` with the existing `/etc/default/inngest-doppler` token into a tmpfs `RuntimeDirectory` (0700; key `root:stunnel4` 0640); hardened; NOT a dependency of `inngest-server`; bodies inline in user_data; both secret names added to the boot isolation regex (floor stays 5); keep >= 300 B margin; never raise or bypass the budget gate. |
| D2 Cert custody | Terraform `tls_private_key` + `tls_self_signed_cert` (ECDSA P256, 10 y, `prevent_destroy`, SAN `ip_addresses=["10.0.1.40"]` only) in a new `.tf`; masked `doppler_secret` x2 in `soleur-inngest/prd`, cert also in `soleur/prd` as `INNGEST_TLS_CA`; one cert resource feeds all copies; runtime verification (canary handshake with `--cacert`, host emits served-cert sha256 and days-to-`notAfter`); alert under 90 days. |
| D3 CA to web | Host file, not baked: `ci-deploy.sh` writes `INNGEST_TLS_CA` atomically to `/mnt/data/inngest-link/inngest-ca.pem` before every `docker run`; all three sites get `-v ...:ro` + `-e NODE_EXTRA_CA_CERTS`, pinned in the tuple gate; fetch failure non-fatal while the flag is off (empty placeholder), fatal when on. |
| D4 Flip lever | Data-driven: Doppler `soleur/prd INNGEST_LINK_TLS=1` read by one resolver in `ci-deploy.sh` that sets `INNGEST_BASE_URL` (absent means `http://10.0.1.40:8288`) and writes `/mnt/data/inngest-link/inngest-link.env` for the probes; self-gate (amended by CTO F1 after plan review: with the flag on a failed self-gate fails the deploy instead of falling back to http; see the amendment row below); tuple gate accepts exactly two values via one pinned expansion; `INNGEST_HOST_FALLBACK` stays http while `:8288` is open; watchdog parity test relaxed to set membership. |
| D5 Legs 2 and 3 | (c) bounded, tracked, dated 2026-12-10 for the poll (void trigger: user content found on the poll); step-call leg gated on #10479 with a ledger row and a closure-guard predicate on #10479. CLO confirmed sequencing with conditions (Legs table). |
| D6 Old 8288 | Keep the accept; add a separate preceding counting rule with named counter `legacy_8288`; read with `nft list counter` from a periodic emitter shipped via the allowlisted phone-home tag; do not bind loopback now (needs image rebuild + second replace); soak closes on 48 h gap-free emits with delta zero since the flip (reboot restarts the clock); follow-through enrollment; physically closing `:8288` rides the next unrelated replace (tracked issue). |
| D7 Ordering | Merges inert: TF secrets (added to the merge `-target` list), web egress accept, resolver + CA write (default http), tuple gate, scheme-aware probes, cloud-init edits (no `hcloud_server` in the merge apply). Must precede the replace: egress accept on every web host (`cron-egress-postapply-assert`), CA file on every web host (one deploy), secrets present in both Doppler projects. Dispatch checks: budget gate, destroy-guard, stock preflight, #10405 merged or explicitly bundled. After: handshake from each web host, canary with flag, prod, soak. Do not touch the `net-health` emit or `inngest-cutover-flip.sh`; TLS fields go in a new `tls-health` phone-home line in a different hunk; nft edit confined to the nftables script; rebase after #10405 merges. |
| CLO 1-4 | Poll leg may follow as a dated tracked step (2026-12-10; own row; never repoint publicly); `:8288` row converts to measured TLS after handshake evidence, other legs carry their own rows; wording until each leg is verified stays as corrected in PR #10326, s11 may cover only application-to-scheduler event submission when the `:8288` leg is verified, DPD 8.1(c) flips for that leg only; "no known access" record format fixed (A6); engineering PR carries no `docs/legal/**` change. |
| Plan-review amendments (CTO F1-F6) | F1: with the flag on, a failed self-gate, a flag read error or an empty/invalid CA fails the deploy (no http downgrade); the canary `docker inspect`s https, fetches the handed URL in-container and runs a CA-withheld negative control. F2: TLS key in the server environment accepted and recorded, follow-up for `--only-secrets`. F3: the rotation apply route is a separate follow-up; A5 waits. F4: add named counter `tls_8443` as the positive control; soak needs legacy delta 0 and `tls_8443` delta >= 90% of cadence. F5: internal checkpoint 2026-10-28 for #10405, then replace without it using `nft8443_sha256` and rule count. F6: T = last prod swap + drain with a baseline row; the flip is a dispatch workflow with a failure/cancel revert step and a 30-minute `pending:<epoch>` lease. |
| Deepen-plan amendments (CTO G1-G6) | G1: the flag is Terraform-managed (`doppler_secret.inngest_link_tls`, count-gated) changed by a new Tier-B `apply_target` job under `infra-privileged`, source of truth the `prd_terraform` key, resource kept out of the per-merge `-target` list; the flip workflow orchestrates pending, canary, on and a best-effort off step, the 30-minute lease being the real control. G2: read the flag from the `resolve_env_file` snapshot (a missing key is authoritative absence), allowlist `^(1\|pending:[0-9]{1,10})$`, epoch at most now+31 min, scope guard `DOPPLER_PROJECT==soleur` and `DOPPLER_CONFIG==prd`. G3: validate the CA before writing (<= 4 KiB, no PRIVATE KEY, SAN exactly `IP:10.0.1.40`, serverAuth only, notAfter in the future, 1-2 certificates), `mktemp` + rename, re-check before `docker run`, `INNGEST_TLS_CA` base64, probes parse and never source the link env. G4: fold in the 503 mapping for timeout/TLS causes; file follow-ups for the Stripe (P1) and dashboard-send losses; window controls and a replay check; canary does a real in-container `inngest.send` of `soleur.tls-canary.ping` (test that no function listens). G5: add A1b `op=resume`, no confirm input in this PR, abort thresholds 10 min / 2 h, per-host proof is each host's own canary. G6: file the event-key issue now (decision due 2026-11-12), rotate it with the signing key in one window. |

## Inert / active matrix

| Item | At merge | After host replace | After flag flip |
|---|---|---|---|
| `inngest-tls.tf` resources, 3 Doppler secrets | created by the merge apply, unreferenced by any running process | referenced by the new host | unchanged |
| Web egress `:8443` accept | present on web-1 and web-2 (additive) | unchanged | used |
| `/mnt/data/inngest-link/inngest-ca.pem` | written (empty placeholder if secret absent) at next deploy | real PEM | real PEM |
| Resolver in `ci-deploy.sh`, tuple gate | default output `http://10.0.1.40:8288` | unchanged | `https://10.0.1.40:8443` |
| Probes | scheme-aware, default http | handshake probe usable (explicit mode) | follow the resolver |
| cloud-init edits (stunnel, nft, tls-health) | in the template only; the host has no `ignore_changes=[user_data]` but the merge apply targets no `hcloud_server` | live | live |
| Old `:8288` | open | open, counted | open, counter must stay zero for 48 h |

## Does merging this PR alone mutate production?

Yes, in additive ways only - stated from the workflows' `paths:` triggers and `-target=` lists, and the PR body's first line must say the same:

1. `apply-web-platform-infra.yml` (push to `apps/web-platform/infra/*.tf`) creates the cert, key and three Doppler secrets (names only; nothing reads them) - the host resource is not in the merge `-target` list, so the Inngest host is NOT replaced by the merge.
2. `apply-deploy-pipeline-fix.yml` and the web-host provisioners deliver `ci-deploy.sh`, the hook template, the egress script and the probe scripts to web-1 and web-2 (delivery census in Phase 3).
3. The next `web-platform-release.yml` deploy restarts the app container with two extra arguments (`-v` CA file, `-e NODE_EXTRA_CA_CERTS`) and the unchanged `INNGEST_BASE_URL` value; the CA file is an empty placeholder until the flag exists.
4. No change to the Inngest host, to `:8288` traffic, to Cloudflare, to the ledger or to any legal document.

## Implementation Phases

### Phase 0: Preflight and spikes (no behaviour change)

1. Infra-merge checks (standing rule): `gh run list --workflow apply-web-platform-infra.yml --limit 5` and `--workflow registry-host-replace-dispatch.yml --limit 5`, both must show nothing in progress at arming; re-read `registry-host-replace-dispatch.md` and `inngest-server.md` section "Replace triggers".
2. Measure the budget delta first: author the stunnel config + unit + fetch script + tls-health emitter + nft lines in a scratch copy, run `bash apps/web-platform/infra/inngest-userdata-budget.sh`, record stored bytes and margin. If margin < 300 B or the repo test budget (`INNGEST_GZIP_BUDGET` in `plugins/soleur/test/cloud-init-user-data-size.test.ts`) is exceeded, apply the Risks fallback ladder before any other work.
3. `inngest start --help` at v1.45.1: `gh release download v1.45.1 -R inngest/inngest -p 'inngest_*linux_amd64.tar.gz' -D <fresh-scratch-dir>`, verify sha256 against `inngest.tf` (`inngest_cli_sha256`), run in a sandbox, record "no TLS flag" in Research Insights. Treat the archive as untrusted (separate empty dir, no interpreter run from inside it).
4. Node 22 (measured at deepen on `node:22-slim` v22.23.3, see Research Insights): `NODE_EXTRA_CA_CERTS` is loaded lazily on first TLS use; an empty file or a directory is silent and verification then fails with `DEPTH_ZERO_SELF_SIGNED_CERT`, a missing path prints a `Warning: Ignoring extra certs` line at first TLS use, none stops startup. Re-run on the exact image digest the Dockerfile pins, and prove offline that Node accepts a self-signed `CA:FALSE` leaf as an extra root (a throwaway cert in the test suite); if it is rejected the canary fails the flip safely.
5. stunnel4 on Ubuntu 24.04 (measured at deepen: package 3:5.72-1build2, user and group `stunnel4`, packaged unit is the template `stunnel@.service` plus `stunnel.target` with no instance enabled, `stunnel4 -test` unsupported so there is no dry run, config keys listed in Research Insights): remaining checks are NIC ordering (the unit must order after the private NIC is up; `soleur-inngest-nic-wait` helper in the template; post-mortem 2026-09-22), that the distro units never glob our conf (keep it outside `/etc/stunnel/*.conf`; `write_files` runs before the apt install), and the `accept = 8443` + nft-drop fallback if binding `10.0.1.40` races the NIC (recorded as a CTO-visible deviation in `decision-challenges.md`).
6. Fixtures from the real binaries are captured at deepen (nft v1.0.9 rule text, counter output and its parse, stunnel failure and success lines, curl exit codes 60 and 56, Node error codes) and committed as test fixtures; Phase 0 only re-runs them against the production package versions.
7. Name the periodic emitter: `inngest-boot-phone-home.sh` (written by cloud-init `write_files`, tag already in the Vector Source 4 allowlist) plus a small timer unit, and confirm its redaction pass (`inngest-redact.sh`) preserves a labelled `sha256=<64hex>` field for the served-cert fingerprint.
8. Coordination measurements (CTO F5, architecture and spec-flow review): (a) grep the diff of #10405 (`gh pr diff 10405`) for pinned nft chain literals, expected rule counts or hashes in its tests and in `inngest-cutover-flip.sh`; record the result in Research Insights (this PR's rules change the chain text, so a pinned literal there would break after a rebase); (b) run `inngest-userdata-budget.sh` on a trial merge of both branches and name the PR that yields bytes (the one that merges second); (c) measure what the app does when an event send fails during a scheduler disruption (Inngest client retry behaviour, Sentry noise) and how long a replace plus bootstrap takes (post-mortems 2026-09-22 and the replace runs on file), and write the duration and event-loss/replay behaviour in the runbook so a low-traffic window and any status notice can be decided (CPO condition); (d) the flag is read from the `resolve_env_file` full-config snapshot (CTO G2), so no stderr parse is needed; confirm in a test that a snapshot without the key is treated as absent and that a snapshot read failure is an error; (e) confirm `openssl` exists on the web hosts (the CA validation uses it) and otherwise validate with `node -e` inside the app image.

### Phase 1: Terraform - cert, key, Doppler copies

- New `apps/web-platform/infra/inngest-tls.tf`: `tls_private_key.inngest_link`, `tls_self_signed_cert.inngest_link` (ECDSA P256, `validity_period_hours = 87600`, `ip_addresses = [local.inngest_private_ip]`, no DNS names, `is_ca_certificate = false` (explicit), `allowed_uses` digital_signature/key_encipherment/server_auth, subject CN `soleur-inngest-link`), `lifecycle { prevent_destroy = true }` on key and cert, `doppler_secret.inngest_tls_key` and `doppler_secret.inngest_tls_cert` in `soleur-inngest`/`prd` (masked; reference `doppler_project.inngest.name` and `doppler_environment.inngest_prd.slug` rather than literals, as the sibling `inngest_*_dedicated` secrets do, and no `ignore_changes` because Terraform owns the value), `doppler_secret.inngest_tls_ca` named `INNGEST_TLS_CA` in `soleur`/`prd` (masked, value `base64encode(cert_pem)` because the multi-line PEM would otherwise reach the container through the docker env-file format; `ci-deploy.sh` decodes it; literals `"soleur"`/`"prd"` as in `proxy-tls.tf`), and the flag: `variable "inngest_link_tls"` (string, default `""`, not a secret) with `resource "doppler_secret" "inngest_link_tls"` (project `soleur`, config `prd`, `count = var.inngest_link_tls == "" ? 0 : 1`, value `var.inngest_link_tls`) so an unset flag is a secret that does not exist (read as absent = http). No `early_renewal_hours` (it would plan a replace that `prevent_destroy` blocks, failing every later merge apply once inside the window; the 90-day alert is the warning). Not count-gated: unreferenced until used; ADR-118's gating existed because the proxy server logged a silent fallback on mere presence, which no process here does.
- Merge `-target` list in `.github/workflows/apply-web-platform-infra.yml`: add `tls_private_key.inngest_link`, `tls_self_signed_cert.inngest_link`, `doppler_secret.inngest_tls_key`, `doppler_secret.inngest_tls_cert`, `doppler_secret.inngest_tls_ca` after the last inngest `-target=doppler_secret.inngest_redis_luks_key` line and before `-target=supabase_project.prd` in the saved-plan command (key and cert together, as ADR-118 notes). `doppler_secret.inngest_link_tls` stays OUT of the per-merge list (CTO G1). Guard suites that assert on the list: `plugins/soleur/test/terraform-target-parity.test.ts` and `tests/scripts/test-infra-privileged-tier-census.sh` (plus the `git grep -ln -e '-target='` sweep). The addresses' dependency closure must not reach `hcloud_server.inngest`: no `templatefile` variable in `inngest-host.tf` may reference `tls_*` or `doppler_secret.inngest_tls_*` (it would pull them into the `inngest-host-replace` closure, where `inngest_out_of_scope_changes` aborts the replace, and would make a cert change force-replace the host); add one gate row in `tests/scripts/test-inngest-host-replace-gate.sh` asserting a plan containing a `tls_*` create aborts. If a new templatefile variable is ever needed, mirror it in `inngest-provision-rehearsal/rehearsal.tf` and the `inngest-userdata-budget.sh` stubs.
- Boot isolation: add `INNGEST_TLS_KEY`/`INNGEST_TLS_CERT` to the allowed-name regex and keep the floor at 5. The regex rows live in `apps/web-platform/infra/inngest-host.test.sh` (the `isolation_decision` replay near its regex rows), not in `doppler-injection-bound.test.sh` (that suite guards `doppler run` command-position injection and is also edited by #10405): add PASS rows for the two names and FATAL rows for a bare `TLS_KEY` and a suffixed look-alike. Sequencing note: the merge apply creates the two names before the replace; the running host keeps the old regex, but its provision unit is latched (`ConditionPathExists=!.../done`), so a reboot does not re-run the check - the hazard is only a re-provision from a build without the regex, which matters for the replace-without-#10405 path.
- Rotation of this cert is out of scope (10 y, alert at 90 days); documented in the runbook.

### Phase 2: Inngest host (cloud-init-inngest.yml)

- `packages:` add `stunnel4`.
- `write_files`: the stunnel conf at a path outside `/etc/stunnel/*.conf` (so no distro unit can glob it): `foreground = yes`, `pid =` (blank), no `chroot`, `setuid = stunnel4`, `setgid = stunnel4`, `accept = 10.0.1.40:8443`, `connect = 127.0.0.1:8288`, `cert`/`key` from the tmpfs `RuntimeDirectory`, `sslVersionMin = TLSv1.2`, `ciphers = ECDHE+AESGCM:ECDHE+CHACHA20`, `options = NO_TICKET`, `renegotiation = no`, output to journald (all keys measured to parse at deepen). `soleur-inngest-tls.service`: its own `SyslogIdentifier`, NO `EnvironmentFile=` (the Doppler token must not reach the network-facing process: the `ExecStartPre=+` script sources `/etc/default/inngest-doppler` itself in a subshell), `ExecStart=/usr/bin/stunnel4 <conf>` (runs as root, drops to `stunnel4` via `setuid`), `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, `PrivateDevices`, empty `CapabilityBoundingSet`, `RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`, `SystemCallFilter=@system-service`, `MemoryDenyWriteExecute=yes`, `RuntimeDirectory` mode 0750 with `RuntimeDirectoryPreserve=restart`, `Requires=` and `After=inngest-nftables.service` (the listener never runs without its drop rule) and after the private-NIC wait, `Restart=on-failure`, a `RestartSec` backoff and `StartLimitIntervalSec=0` (a Doppler disruption at boot cannot leave it permanently failed). The packaged `stunnel@.service` template is simply never instantiated. The fetch: explicitly fail-closed (`|| { emit; exit 1; }`, never relying on errexit), `umask 0077`, key written by stdout redirection into a temp file inside the RuntimeDirectory (never `--token`, `set -x` or a command substitution that echoes it), `openssl pkey -noout` plus a check that the key's public key equals the cert's before the `mv`, key `0640 root:stunnel4` (SIGHUP reload after the privilege drop fails with `0600 root:root`, measured). `soleur-inngest-tls-health.service` + `.timer` (5 min, ordered `After=inngest-bs-token-restage.service` so rows are not `TRACE_LOST`) emitting through `inngest-boot-phone-home.sh tls-health "unit=<state> nrestarts=<n> fetch_rc=<n> bind=<addr:port> listener=<0|1> served_sha256=<64hex> cert_sha256=<64hex> notafter_days=<n> legacy_8288_packets=<n> tls_8443_packets=<n> nft8443_sha256=<64hex> nft_rules=<n> boot_id=<8-char prefix or dashed>"` (the periodic series that ships regardless of priority; `served_sha256` is a handshake against `10.0.1.40:8443` in DER, lowercase, no colons; (removed in round 3, no consumer) was the only host-side signal that a web client rejects the CA; a dashless 32-hex `boot_id` would be redacted, which would make the soak's single-boot check vacuous; the helper's own `sed` preserves labelled `sha256=<64hex>` suffixes and redacts other 32+ hex runs) and, only on `listener=0` or `notafter_days < 90`, through a multi-line shell function `emit_refusal() {` newline `logger -p user.crit -t inngest-tls-health "$1"` newline `}` called as `emit_refusal "SOLEUR_INNGEST_TLS_REFUSED reason=<token> ..."` (the drift guard requires the multi-line definer plus a call; a bare `logger` line or a one-line definer reds it, measured). The counter predicate lives in the soak script, which owns the flip timestamp. No secret or key material in either line; never reuse a tag listed in the `vector.toml` exclude arrays.
- nft script (the `inngest-nftables.sh` block only): declare `counter legacy_8288 { }` and `counter tls_8443 { }` in `table inet soleur_inngest`; add `tcp dport 8288 ip saddr { ${web_host_private_ips} } counter name "legacy_8288"` BEFORE the existing accept (verdict-less, falls through) and `tcp dport 8443 ip saddr { ${web_host_private_ips} } counter name "tls_8443"` BEFORE the 8443 accept (the positive control: a flat legacy counter proves nothing at zero traffic); add `tcp dport 8443 ip saddr { ${web_host_private_ips} } accept` and `tcp dport 8443 drop`; keep the existing `8288/8289` accept and drop lines byte-identical. Values interpolated into `nft -f` stay the Terraform constant `web_host_private_ips` (no user input).
- `runcmd`: enable and start the TLS unit and the health timer after the nftables unit, each failing loudly to the boot phone-home (a malformed unit surfaces at provision, not at the next reboot).
- Do NOT edit the `net-health` emit region or `inngest-cutover-flip.sh` (owned by #10405).
- Update the tests that pin this file: `inngest-host.test.sh` (new rules, accept line unchanged), `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-provision-unit.test.sh` (no other `write_files` entry pulls or logs in), `inngest-redis-luks.test.sh` (top-level key set must still be exactly `package_update packages groups users write_files runcmd`), `plugins/soleur/test/cloud-init-user-data-size.test.ts`; register any new `.test.sh` in `.github/workflows/infra-validation.yml`.

### Phase 3: Web side (inert)

- `ci-deploy.sh`: one resolver function `resolve_inngest_link` run before both `docker run` sites (CTO F1/F6/G2/G3). Flag read: from the `resolve_env_file` full-config snapshot already written before `docker run` (a missing key there is authoritative absence; never parse stderr and do not rely on `--no-exit-on-missing-secret`), with a `DOPPLER_PROJECT==soleur` and `DOPPLER_CONFIG==prd` scope guard so a mis-bound token never reads "absent". Value allowlist `^(1|pending:[0-9]{1,10})$`; any other non-empty value fails the deploy; absent = `http://10.0.1.40:8288` (the only http path besides a lapsed lease); `pending:<epoch>` is honoured only while the epoch is at most now+31 min AND inside the 30-minute lease, after which it resolves to http plus an event (a deliberate rollback, not a downgrade); `1` = fail-closed. With the flag on, ANY of {self-gate fails, the CA read errors, CA empty or invalid} makes the deploy exit non-zero and the old container keeps serving - no downgrade. CA: read `INNGEST_TLS_CA` (base64) through `_doppler_get_observed`, decode, then validate BEFORE writing: at most 4 KiB, no PRIVATE KEY block, 1-2 CERTIFICATE blocks, self-signed with `CA:FALSE`, SAN exactly `IP:10.0.1.40`, serverAuth only, notAfter in the future; write via `mktemp` inside `/etc/soleur` plus rename to `/mnt/data/inngest-link/inngest-ca.pem` (0644; with the flag off write the placeholder or only a structurally validated PEM, never an unvalidated one); immediately before each `docker run` re-check `-f && ! -L` and the sha256. Write `/mnt/data/inngest-link/inngest-link.env` from enum branches and constants only (`INNGEST_LINK_URL` one of two literals, `INNGEST_LINK_SCHEME`, `INNGEST_LINK_CACERT`), never from flag or CA text. The host-side `curl --cacert <validated file> --noproxy '*' https://10.0.1.40:8443/health` (no `-k`, no `--capath`) self-gate runs for both `pending` and `1` in the host OUTPUT chain: it does NOT prove container egress or Node trust (the canary does); a substituted CA fails against the real host, so it denies service rather than enabling a MITM. Both docker run sites use `-e INNGEST_BASE_URL="$INNGEST_BASE_URL_RESOLVED"`, `-v /etc/soleur/inngest-ca.pem:/etc/soleur/inngest-ca.pem:ro`, `-e NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem`. While the flag is on a broken gate also blocks ordinary releases (accepted by the CTO; the runbook says so). The third `docker run` in the file (the cosign verifier with `--rm`) is exempt in the tuple gate and is untouched. Tests: a prd env containing `NODE_TLS_REJECT_UNAUTHORIZED` or `NODE_EXTRA_CA_CERTS` returns rc 1 from `overlay_github_app_key`'s `NODE_*` refusal (add the rows).
- `cloud-init.yml` first-boot site: add the `-v`/`-e NODE_EXTRA_CA_CERTS` for a fresh host with a placeholder file created by cloud-init; `INNGEST_BASE_URL` stays http there (the first deploy after birth re-resolves).
- `lib/docker-run-tuple.py`: `INNGEST_BASE_URL` set becomes the resolver expansion (plus its literal for the first-boot tuple); add `NODE_EXTRA_CA_CERTS` to `_COMMON_ENV` and the first-boot env; add the CA `-v` string to `_VOLS`; pin that `NODE_TLS_REJECT_UNAUTHORIZED` is absent from every tuple (a `0` there would silently defeat verification); extend `docker-run-tuple.test.sh` mutation rows (K07*/K10*). The gate's digest (`e959fc801d99`) covers AppArmor, seccomp and tmpfs only, so the env/volume additions are anchored by the exact-set checks, the K07/K10 rows and the canary negative control, not by the posture literal (no edit to `docker-run-tuple-posture.test.ts`).
- `cron-egress-nftables.sh`: add `ip daddr 10.0.1.40 tcp dport 8443 accept` with a `soleur-egress` comment next to the 8288 rule; `cron-egress-postapply-assert.sh` asserts both; `cron-egress-firewall.test.sh` pins both. Delivered by the existing `deploy_pipeline_fix`/`cron_egress_firewall` provisioners (web-1 and web-2 twins already exist: see Host fan-out).
- Probes: link resolution lives ONLY in `inngest-registry-probe.sh`, which `inngest-consumer-probe.sh` sources (and `inngest-doublefire-probe.sh` reads the same default): it prefers `/mnt/data/inngest-link/inngest-link.env` over any inherited `INNGEST_REMOTE_GQL_URL` (`server.tf` writes an explicit `http://${local.inngest_private_ip}:8288/v0/gql` into the consumer probe's env file, which would otherwise win), parses the env file with a key allowlist and a literal-URL check and NEVER sources it, defaults to http. `inngest-consumer-probe.sh`, `inngest_consumer_probe_install` (web-1 only, `birth-covered` for web-2 in `web-host-provisioner-parity.test.sh`), `server.tf` and `web-probe-envwrite.sh` are NOT edited, so web-2 (which never had the consumer-probe unit) is unaffected and the provisioners are not re-triggered; the registry probe reaches both hosts (webhook for web-1, `deploy_pipeline_fix_web2` for web-2). Suites updated: `inngest-registry-probe.test.sh`, `inngest-doublefire-probe.test.sh`.
- Delivery census (plan-time answer to "which workflow delivers each web-host file to BOTH hosts"): bounded to the files that actually change - for each changed web-host file (`ci-deploy.sh`, `hooks.json.tmpl`, `cron-egress-nftables.sh`, `cron-egress-postapply-assert.sh`, the three probes, the new handshake probe, `web-probe-envwrite.sh`, `server.tf`), name the workflow whose `paths:` filter fires on it (`apply-deploy-pipeline-fix.yml` lists `ci-deploy.sh`, `hooks.json.tmpl`, `infra-config-apply.sh` and several inngest scripts; `apply-web-platform-infra.yml` fires on `*.tf`; check the rest with `git grep`) and the provisioner that delivers it to web-1 and web-2 (`triggers_replace` hashes in `server.tf`); add any missing `paths:` entry and `triggers_replace` input, with a test. A file nothing fires on would sit on disk in the repo while production keeps the old bytes.
- Handshake evidence without a new probe script: `inngest-registry-probe.sh --tls-handshake` mode asserts (a) `curl --cacert` returns 200 on `/health` and (b) the same request WITHOUT the CA fails with a certificate-verification error (curl exit 60); output is rc plus fixed tokens only, never curl stderr. The existing `inngest-registry-probe` hook has no argument pass-through and `cutover-inngest.sh` parses its body as registry JSON, so add a dedicated hook entry `inngest-tls-handshake` in `hooks.json.tmpl` that runs the mode with fixed arguments (`hooks.json.tmpl` is already in the `apply-deploy-pipeline-fix.yml` `paths:` list). Cert fingerprint equality is dropped from the probe (a successful verify against the pinned CA proves it; A1 compares the host `cert_sha256` and `served_sha256` emits with the Terraform cert). The hook channel terminates on web-1 (web-2 is a standby), so the per-host proof is each host's own ci-deploy canary, not this hook.
- `apps/web-platform/test/server/inngest/cron-inngest-cron-watchdog.test.ts`: parity test relaxed to set membership over the two resolver values; `INNGEST_HOST_FALLBACK` stays `http://10.0.1.40:8288`.
- App-side mitigation folded in (CTO G4): `apps/web-platform/app/api/internal/schedule-reminder/route.ts` maps only `ECONNREFUSED` to the retryable 503 (+ `Retry-After`, `X-Soleur-Unavailable`); extend it to 503 for ETIMEDOUT, ECONNRESET, UND_ERR_CONNECT_TIMEOUT, `ERR_TLS_*` and the cert-verify codes (`DEPTH_ZERO_SELF_SIGNED_CERT`, `UNABLE_TO_VERIFY_LEAF_SIGNATURE`), with a test, so `inngest-rearm-reminders.sh` aborts instead of continuing past a lost arm. It changes behaviour only on failure.
- Canary layer (`canary-probe-set.md`) - the container-level proof, whenever the flag is on: (1) `docker inspect` shows the canary's `INNGEST_BASE_URL` is https; (2) one in-container `fetch` of the URL the container was actually handed (`/health` and `/v1/events?limit=1` with the Bearer) succeeds; (3) a real in-container `inngest.send` of a synthetic event named `soleur.tls-canary.ping` is accepted (grep the FULL function-trigger set under `apps/web-platform/server/inngest/functions/` and add a test asserting no function triggers on it); (4) a negative control with the CA withheld (`env -u NODE_EXTRA_CA_CERTS` in the same container) fails with a verification error; (5) registry non-empty over https. Counter reads happen only after the prod swap on BOTH hosts completes (the old prod container still dials `:8288` until then). The soak enumerates every known plaintext caller: the watchdog `INNGEST_HOST_FALLBACK` stays http but is only used when `INNGEST_BASE_URL` is unset in the container, which the tuple gate forbids - a test asserts it, and the soak counts rather than excludes it.
- Flip actuator (CTO F6 amended by G1): the flag is the Terraform-managed `doppler_secret.inngest_link_tls` (Phase 1), source of truth the `prd_terraform` key `INNGEST_LINK_TLS`, changed only by a new `apply_target` job in `apply-web-platform-infra.yml` under `environment: infra-privileged` with the existing Tier-B write credential (precedent `ci_ssh_token_replace`; 8 of 25 dispatch inputs used): inside that one job the source key is written first, then `-target=doppler_secret.inngest_link_tls` is applied; the resource stays out of the per-merge `-target` list. No existing narrow Doppler write credential for `soleur/prd` exists (a prd token can overwrite every prd secret; the arm token is `soleur-inngest/prd` only; the git-data flag token is unprovisioned, #8573), so no new token is minted. A thin dispatch workflow `.github/workflows/inngest-link-flip.yml` orchestrates: apply `pending:<epoch>`, dispatch the canary-then-prod release, verify the canary layer and both prod swaps, apply `1`; an `if: failure() || cancelled()` step applies the safe baseline (flag absent) and dispatches a redeploy. CTO caveat: if `infra-privileged` has required reviewers, that off step would block on an approval nobody is there to give, so the 30-minute lease is the real control and the off step is best-effort; the runbook says so. Three applies of about 2 minutes each are acceptable for a once-only act. Add the new job to the ADR-241 D8 census and to `infra-credential-tiers-8209.md`.

### Phase 4: Observability, follow-through, docs

- Paging (CTO E2): no new Better Stack Logs alert (15 exist, free-tier cap unmeasured, ADR-218); opt in to the existing `monitor_send_failed` alert, whose SQL already matches `PRIORITY = '2'` plus the `_REFUSED` needle (confirmed against `betterstack-logs-alerts.tf`; no SQL change, no `probe_rev` bump). Two emitters: the periodic series through `inngest-boot-phone-home.sh` (stage `tls-health`, direct POST to source 2457081) and the crit refusal marker through `logger -p user.crit -t inngest-tls-health` (ships through Vector Source 2, PRIORITY 0-2 from any unit except `inngest-server`; the same `vector.toml` runs on the Inngest host; `vector.service` starts late in the bootstrap, so the phone-home row is the Vector-independent twin). Owed: the multi-line `emit_refusal` form (Phase 2), the drift guard `betterstack-send-failed-alert.test.sh` going from 79 passed / 9 cases to 81 / 10 with `BASELINE_PASSES=81` and `BASELINE_CASES=10` re-pinned in `betterstack-send-failed-alert-mutation.test.sh` plus a mutation row for the new marker, a decode row in `knowledge-base/engineering/operations/runbooks/monitor-send-failed-alert.md` (the alert email links it; its `incident_cause` text says "from a web-1 monitor unit", which is wrong for this marker - fix the wording) and in `betterstack-log-query.md`, and a synthetic proof (`synthetic=1` row queried through `scripts/betterstack-query.sh`) before relying on the route. Dead-emitter detection is the soak gap predicate plus a monthly cert days-left follow-through; after the flip the web-side probes dial https `:8443`, so a down listener already trips the existing probe alarms.
- `scripts/followthroughs/inngest-tls-soak-10136.sh` (+ test): queries Better Stack for the `tls-health` series since T with `scripts/betterstack-query.sh --limit 1000` or more (the default 100 would silently truncate 48 h at 5 minutes, about 576 rows; never `--no-archive`). Exit 0 only when the series is gap-free (expected rows per hour with jitter allowance), a single `boot_id` since T, the `legacy_8288` packet delta is 0 AND the `tls_8443` delta is at least 90% of the expected probe cadence. Exit 2 (transient) on empty or transport failure. T and the baseline row are read from the tracker comment through `scripts/lib/trusted-verdict.sh` (the repo is public, so comment authorship must be verified). The sweeper already wires `BETTERSTACK_QUERY_HOST`, `BETTERSTACK_QUERY_USERNAME` and `BETTERSTACK_QUERY_PASSWORD`, so no workflow edit is needed: directive `secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD,GH_TOKEN`; the script runs under `env -i`, so it calls `betterstack-query.sh` directly with no `doppler run`. Dry-run with `gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true`. The tracker directive is `<!-- soleur:followthrough script=scripts/followthroughs/inngest-tls-soak-10136.sh earliest=<T+2d> secrets=... -->`.
- Runbook: new section in `knowledge-base/engineering/operations/runbooks/inngest-server.md` ("Link TLS (#10136)": flag, rollback, replace order, cert expiry, reading `tls-health` without SSH). No SSH in any step.
- ADR-292 (provisional ordinal; re-verify against `origin/main` at ship per the ADR-ordinal gate) and an ADR-100 addendum pointer; C4 edit (Architecture Decision section). Sweep for `ADR-<n>` renumbering across plan, tasks and specs if the ordinal moves.

## Production Actions (post-merge) and Gates

These run AFTER this PR merges and deploys. They are deliberately NOT recorded under an `## Operator Holds` heading: `soleur:ship` evaluates every hold at the draft exit and again before arming, so a hold whose condition is "this PR is merged" would block the PR's own arming. The preconditions below use the hold grammar's vocabulary (`pr-merged N`, `no-inflight-run <workflow>`) so the executing session can run the same probe. No `Delegation:` record exists on #10205, so every act below proceeds on the owner's recorded go quoted here (an explicit statement, not a menu acknowledgement), one act at a time, with the evidence column checked before the next. A failed replace waits for a FRESH owner go before any re-dispatch (standing rule; the owner reserves this decision).

Owner go (quoted, recorded 2026-10-18 on #10136): "go on the Inngest TLS PR and go for the host replace and INNGEST SIGNING KEY Rotation".

Placement and bookkeeping (CTO E1 ruling 2026-10-18): post-merge acts are not holds; the Production Envelope for these acts lives in a committed runbook that survives the Phase 6.45 archive (the new "Link TLS (#10136)" section of `inngest-server.md`), not in this plan; one follow-through issue is enrolled per act (A1, A3, A5) with predicates the sweeper checks; no delegation is needed to build or merge the PR, and the calling skill asks the epic-start question at ship time with a Scope naming exactly the host-replace dispatch, the flag-write-plus-release dispatch and the rotation (only delegable command classes). The recorded owner go names the replace and the rotation; it does NOT name the flag write, which is a separate production act (A3) needing its own dated go.

| # | Act | Owner go / due | Preconditions (evaluate, never assume) | Mechanism (no SSH) | Success evidence | Rollback |
|---|---|---|---|---|---|---|
| A0 | Merge this PR (inert) | normal merge queue after review and green CI | review done; `gh run list` shows no in-flight `apply-web-platform-infra.yml`/`registry-host-replace-dispatch.yml`; rebased on `origin/main` (never merge main); compound run | single bare `gh pr merge 10501 --squash --auto`, then no sync pushes; the 3 secrets are `tls_*` plus `doppler_secret.inngest_tls_*` only (the flag resource is count-gated off) | `deploy-arm.sh find --wait <full-sha>` then `served <full-sha>` from a detached `origin/main` worktree; merge apply created the 3 secrets (names only, never values); egress assert green on web-1 and web-2; CA file on both web hosts equals the Doppler copy (sha256 compare via a deploy-state hook; re-check after the first post-merge release, since the merge apply can race the first deploy and leave the empty placeholder) | revert the PR; nothing referenced the new resources |
| A1 | Inngest host replace (one disruption, bundled with #10405 unless it slips) | "go for the host replace", due **2026-11-05** | `pr-merged 10501`; `pr-merged 10405` OR the internal checkpoint 2026-10-28 has passed without #10405 being mergeable (then the replace proceeds without it; evidence comes from this PR's own `nft8443_sha256` and `nft_rules` fields, never reusing #10405's `nft_sha256` name; whichever PR merges second rebases); every web host reports the CA fingerprint and the 8443 egress rule (A0 evidence for web-1 AND web-2); `no-inflight-run apply-web-platform-infra.yml`; `inngest-userdata-budget.sh` green with >= 300 B margin on the trial merge of both branches (the PR that merges second yields bytes); runbook `inngest-server.md` "Replace triggers", "Inherited done after a host replace (#7228)" and the registry runbook's double-replace rule re-read; stock preflight and destroy-guard pass; replace duration and send-failure behaviour measured in Phase 0 and written in the runbook; a low-traffic window chosen; the quiesce op of `cutover-inngest.yml` set for the window (it covers reminder arming only) and the host id pinned in the runbook before and after | `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason='PR 10501 inngest link TLS'` (the job has a required `reason` input only - no confirm or id-pin input; adding one is a follow-up, CTO G5); it carries the network, volume and firewall attachments (post-mortem 8754) | the apply job concludes success AND the scheduler serves: boot event shows the private NIC up (no `provision-nic-ABSENT`), `bootstrap-done` for the new `iid`, `tls-health` rows with `listener=1`, `served_sha256` = `cert_sha256` = the Terraform cert, `nft8443_sha256`/`nft_rules` showing the 8443 accept, drop and both named counters, the `routine_runs` catch-up shows one run per missed tick; abort thresholds from the runbook: 10 min armed with no attempt, 2 h with no `bootstrap-done` | nothing points at 8443 yet, so the web side needs no rollback; a failed replace (apply non-success, or `tls-health` absent 30 min after the apply): read the apply run's recovery-read block, WAIT for a fresh owner go, then re-dispatch once; the inherited-`done` strand is recovered by A1b, not by re-dispatch |
| A1b | `cutover-inngest.yml -f op=resume` after the replace (inherited `done`, #7228) | pending - a separate owner act: the `inngest-cutover` environment approval is a human gate no delegation can bypass and it authorizes a production scheduler start; the recorded replace go does not name it, so the owner's go must name `op=resume` | A1 dispatched; `INNGEST_CUTOVER_FLIP=done` inherited from Doppler so the new host refuses to start; the G3/G4 gates in the runbook (`bootstrap-done` for the current `iid`) | `gh workflow run cutover-inngest.yml -f op=resume` (waits in `Waiting` for the owner's environment approval) | the FSM returns to `noop-done`; `inngest-server` active with stable `NRestarts`; expect a false DOUBLE-FIRE from the bucket proxy in `op=verify` and attribute it against `routine_runs`; do not re-fire missed ticks (each fired exactly once on the 2026-09-17 resume) | none - never re-dispatch the replace for an inherited `done` |
| A2 | Handshake verification pre-flip | part of the A1 go | A1 evidence | web-host hook `/hooks/inngest-tls-handshake` (web-1; the hook channel terminates there) | (a) verified 200, (b) failure without the CA (exit 60); web-2's container path is proven by its own ci-deploy canary at A3 | n/a (read-only) |
| A3 | Flip through `inngest-link-flip.yml` (apply `pending:<epoch>`, canary, prod, apply `1`) | the recorded go names the PR build and "URL flip behind a canary" as build scope only; the flag WRITE needs its own dated owner go naming it (asked via the epic-start question at ship time or an action-required issue) | A1 and A2 green; `no-inflight-run` for the release workflow; flip date noted in the tracker; flip actuator credential resolved (open item above) | `gh workflow run inngest-link-flip.yml` (each flag change is a Tier-B `apply_target` job, about 2 minutes) | canary layer passes (all five checks, including the real in-container send); both prod hosts swapped and healthy; `ci-deploy` resolver log shows `https` on both; T = last prod swap complete plus old-container drain, with a counter baseline sample taken after the drain | the workflow's failure/cancel step applies the flag-absent baseline and redeploys (best-effort - the 30-minute lease is the control if the Tier-B job blocks on a reviewer); manual rollback is the same workflow `action=off` plus redeploy; `:8288` is still serving, so the host needs nothing |
| A4 | 48 h soak | n/a | A3 timestamp T and baseline row | follow-through sweeper runs `inngest-tls-soak-10136.sh` | gap-free `tls-health` series since T, one `boot_id`, `legacy_8288` packet delta 0 AND `tls_8443` delta >= 90% of the expected probe cadence, for 48 h; a reboot restarts the clock (re-anchor by a new tracker comment) | any non-zero legacy delta: run the flip workflow with `action=off`, find which caller still dials 8288 |
| A5 | `INNGEST_SIGNING_KEY` rotation (#10382 row 1), together with `INNGEST_EVENT_KEY` if the owner extends the go (O5) | "INNGEST SIGNING KEY Rotation", recorded on #10382 | A4 passed (the new key never rides plaintext); the separate rotation follow-up PR with a minimal `apply_target` (CTO F3; not built in this PR) has landed; runbook `inngest-server.md` "Key rotation" re-read; both copies identified (host: `random_id.inngest_signing_key_dedicated` in `soleur-inngest/prd`; app: `soleur/prd INNGEST_SIGNING_KEY`, `ignore_changes=[value]`, copied out-of-band per `inngest.tf`; whether the dedicated `doppler_secret` carries `ignore_changes` is to be verified); the Stripe-webhook and dashboard-send loss defects (follow-up issues) fixed first, or the rotation runs inside a quiesced window with the replay check | set both values, then restart `inngest-server` (`restart-inngest-server.yml`) and redeploy web (`web-platform-release.yml`) back to back; no host replace is forced (keys are read from Doppler at start); during the mismatch window step calls fail signature verification (Inngest retries them) and `inngest.send` fails with 401 if the event key rotates too | old-key rejection check (status code only; the old value retained until it passes), new key accepted, `.services.inngest_server` active with stable `NRestarts` | the runbook's rollback; after A5 a flag-off rollback puts the NEW key back on `:8288`, so a post-A5 rollback requires a re-rotation, and the legacy listener closure (deferral issue) gets a date |
| A6 | "No known access" record | CLO condition | A5 complete; measured re-read from the deployed #10405 emit; Hetzner member list enumerated read-only (`hcloud network describe <net> -o json`, servers field) | file `knowledge-base/legal/audits/<date>-inngest-signing-key-rotation-no-known-access.md`, linked from #10382 and #10136; owner states the facts starting "SIGNED BY OWNER (human, not an agent)", CLO agent adds a separate attestation line; contents per the CLO ruling (rotation timestamp UTC, secret name and version entry, every config/host that got the key, old-key rejection status code, exposure window from before PR #10371 through the rotation, what was searched, the explicit "no evidence found, not none occurred" limit, whether `INNGEST_EVENT_KEY` was also rotated); dated after A5, the deployed re-read and the enumeration | the record exists and is linked | n/a |
| A7 | Leg-2 accepted-risk record (poll) | owner item, class `operator (legal-risk)` | CLO conditions (Legs table) | owner-typed record on #10136 beginning "SIGNED BY OWNER (human, not an agent)"; an agent-posted record does not satisfy it | record exists before the poll row is relied on | n/a |

`INNGEST_EVENT_KEY` rotation is NOT covered by the recorded go. The A6 record states whether it was rotated; if not, it covers the signing key only. Extending the go to the event key is an owner decision (`operator (production-mutating)` row in `decision-challenges.md`).

## Post-merge probe plan (evidence for the issue; the owner is never asked to watch CI or paste logs)

1. Handshake with verification on: `inngest-registry-probe.sh --tls-handshake` from each web host: verified 200; unverified request fails with a certificate-verification error (the host `cert_sha256` emit is compared with the Terraform cert at A1). Output is a structured line the agent reads from the hook.
2. Canary proof (A3): `docker inspect` shows an https `INNGEST_BASE_URL`; one in-container `fetch` of the handed URL and a `/v1/events?limit=1` Bearer read succeed; the CA-withheld negative control fails; registry non-empty over TLS.
3. Counters: a baseline sample taken after the last prod swap plus old-container drain (T), then +15 min, +1 h, +24 h, +48 h from `tls-health` rows (Better Stack query, `bash scripts/betterstack-query.sh --since <window> --grep tls-health`); the `legacy_8288` delta must be zero and the `tls_8443` delta at least 90% of the expected probe cadence (positive control); any non-zero legacy delta names the caller by correlating with the `ci-deploy` resolver log.
4. Cert health: the `notafter_days` row value (expect ~3650) and the 90-day alert wired.
5. Measured nftables re-read (CLO condition, shared with #10405): the full chain with the `8443` accept, drop, and both counting rules, plus `nft8443_sha256` and `nft_rules` (and #10405's `nft_sha256` when it has merged).
6. Hetzner member list (read-only), dated, attached to the A6 record.

## Downtime & Cutover

**Offline-inducing operation.** `apply-web-platform-infra.yml -f apply_target=inngest-host-replace` (job `inngest_host_replace`) destroys and recreates `hcloud_server.inngest`. The user_data change forces it because the host has no `ignore_changes=[user_data]`; code delivery to this host is replace-only (ADR-100 addendum 2026-08-25).

**Surface.** The sole scheduler `10.0.1.40`: crons, event ingestion, reminders and step dispatch for every user. The Redis AOF volume `inngest_redis_luks` is kept by omission and the destroy-guard asserts zero deletes.

**Zero-downtime paths evaluated.** A second or blue-green scheduler double-fires every cron (ADR-100: N servers means N-times fire; the runbook section on the bounded window), so it is rejected; an in-place edit is impossible because the host has no inbound path; the Terraform apply for this PR deliberately contains no `hcloud_server` so the merge itself causes no disruption. A bounded replace window is therefore the default, bundled with #10405 so there is exactly one.

**Duration (measured vs not).** Measured: the apply job takes about 2 minutes (2026-09-27: server created 14:56:48, job done 14:57:36); a green apply does not mean the scheduler is serving (2026-09-22: apply green 07:00:54, scheduler dark until 07:58). Measured incidents: about 59 min (NIC race, a second replace, `op=resume`) and about 76 min (inherited `done`, two replaces). Unmeasured: the clean-path cloud-init to `bootstrap-done` time - Phase 0 item 8c reads `provision-unit-armed` to `bootstrap-done` for the 2026-09-27 `iid` in Better Stack; until then plan for 15 to 60 minutes plus owner approval latency for A1b. A failed replace waits for a fresh owner go, so the disruption can outlast the window if the owner is away.

**Events during the window.** `sendInngestWithRetry` makes three attempts with 0.5 s and 1 s backoff, then throws. GitHub-push and resend-inbound webhooks release the dedup row and return 500 (redelivered). `schedule-reminder` returns 503 only on connection refusal today (this PR extends it to timeouts and TLS causes, Phase 3); a host-absent timeout otherwise returns 502 and the caller must re-arm. The dashboard send path archives the draft with `degraded=enqueue_failed` and no retry, and the Stripe `invoice.payment_failed` route swallows the failure and returns 200 with the dedup row claimed (both pre-existing, follow-up issues; the Stripe one is P1 and scheduled before the replace date). Window controls: a low-traffic dispatch, the `cutover-inngest.yml` quiesce op (`INNGEST_CUTOVER_QUIESCE=1` covers reminder arming only; how it reaches the container without a redeploy is unverified, so use the existing op), and a post-window replay check of `action_sends` rows without a spawn plus Stripe dedup rows.

**In-flight work.** Queue state and the cron schedule live in Redis on the retained AOF volume; queued items survive a re-provision, and after the 2026-09-17 76-minute gap each missed tick fired exactly once (do not re-fire manually). Not documented: a step HTTP call in flight when the scheduler dies (presumably re-driven at-least-once); check non-idempotent steps before A1.

**Stages, each verified before the next.** S0 preconditions (budget gate, no in-flight runs, secrets present in both Doppler projects, owner reachable for the A1b approval); S1 dispatch (destroy-guard, stock preflight); S2 boot (private-NIC event, `provision-unit-8562.sh` verdict PASS for the new `iid`); S3 `op=resume` approved (A1b), FSM at `noop-done`; S4 `tls-health` `listener=1`; S5 handshake hook. Rollback: there is no revert of a destroyed host; recovery is re-dispatch (mid-replace apply failure only, after a fresh owner go) or `op=resume` (inherited `done`) - re-dispatch is the trap for an inherited `done`. A5 also needs a restart-window answer (a second, shorter window).

## Network Layer Verification (L3 to L7)

The plan's words match the network checklist triggers (firewall, handshake, timeout), so each layer carries a verification status (the plan skill's network-hypothesis checklist reference):

| Layer | Status | Artifact or the command that would verify |
|---|---|---|
| L3 firewall allow-list | Partly verified | The nft allow-list for the Inngest host is read from `cloud-init-inngest.yml` and the ruleset was loaded and listed in a throwaway netns (a non-allowlisted source times out on the drop; Research Insights). The Hetzner cloud firewall on the host filters the public interface only (CTO ruling; post-mortem 8754) - NOT verified live here (`hcloud` CLI absent): at A1 read it with `curl -s -H "Authorization: Bearer <token from Doppler prd_terraform>" https://api.hetzner.cloud/v1/firewalls` (read-only, token never printed) and diff that the private interface is unfiltered and the attachment survived the replace. The web hosts' container egress allow-list is default-drop and gets the new `10.0.1.40:8443` accept (postapply assert + canary) |
| L3 DNS and routing | Verified by construction | Everything uses the IP literal `10.0.1.40` on the Hetzner private network (no DNS name, no SAN DNS entry); reachability of `10.0.1.40:8443` from each web host is proven by that host's own canary fetch at A3 and by the handshake hook from web-1 at A2 |
| L7 TLS and proxy | Measured | stunnel + curl/Node handshake, hostname (IP SAN) mismatch, protocol floor and cipher behaviour measured at deepen; Cloudflare is not on this path (private IP) |
| L7 application | Verified at A1/A3 | `/health` and `/v1/events` over TLS, a real `inngest.send`, registry non-empty over https |

**Precedent diffs (pattern-bound behaviours, Phase 4.4).** Atomic file write: precedent `_atomic_write` in `ci-deploy.sh` (`mktemp` in the destination directory, rename) - the CA write follows it and adds validation before the rename; unit hardening: precedent the existing inngest host units in `cloud-init-inngest.yml` (`NoNewPrivileges`, `ProtectSystem`, scoped `EnvironmentFile`) - the TLS unit deliberately omits `EnvironmentFile=`; nft ruleset: precedent the `inngest-nftables.sh` block (`table inet soleur_inngest`, boot-only declare, measured to merge on re-load) - the plan adds named counters and rules without touching the existing accept line; self-signed pinned cert: precedent `proxy-tls.tf` (ECDSA P256, shared cert as the client's trust anchor) - differs by `prevent_destroy`, no `early_renewal_hours`, no count gate, `is_ca_certificate = false`; Doppler flag with Terraform ownership: precedent `cf-cert-reissue-token.tf` and `ci_ssh_token_replace` - differs by being count-gated on a variable sourced from `prd_terraform`.

## Infrastructure (IaC)

### Terraform changes

- New `apps/web-platform/infra/inngest-tls.tf` (existing root; R2 backend already present). Providers: `hashicorp/tls` (lock file pins 4.3.0, `~> 4.0`; `terraform init -backend=false && terraform validate` passed in a scratch copy with the planned resource shapes on Terraform 1.9.8, CI uses 1.10.5) and the existing `doppler` provider. Sensitive: none new as variables (the key is generated, never an input). `doppler_secret` resources are masked; the private key lands in `terraform.tfstate` on the encrypted R2 backend (ledger store `r2.terraform_state_backend`).
- `apply-web-platform-infra.yml`: add the five addresses to the merge `-target` list (not the flag resource), and a new `apply_target` job for the flag under `infra-privileged`.
- `inngest-host.tf`: no change expected (the stunnel conf is static; `inngest_private_ip` is already a local). If the template needs a new templatefile variable, add it and update the `inngest-userdata-budget.sh` stubs (exact-length bound).

### Apply path

(b) `terraform apply -replace` of the Inngest host through the dedicated `inngest-host-replace` dispatch (the host has no `ignore_changes=[user_data]`, so the cloud-init edit force-replaces it only through that dispatch; the merge apply carries no `hcloud_server`). Expected disruption: the single scheduler host is unavailable for the replace window (replace plus bootstrap, Redis AOF volume reattached). Bundled with #10405 so there is one disruption, not two.

### Host fan-out

The SSH `terraform_data` provisioners reached are the existing cron-egress ones (`deploy_pipeline_fix` for web-1 and `deploy_pipeline_fix_web2`, which hashes and delivers `cron-egress-nftables.sh` and `cron-egress-postapply-assert.sh` to web-2; `cron_egress_firewall` for web-1): `twin` for the egress rule. Probe link resolution lives only in `inngest-registry-probe.sh`, which both hosts receive (webhook for web-1, `deploy_pipeline_fix_web2` for web-2) and which overrides any inherited `INNGEST_REMOTE_GQL_URL`; `inngest-consumer-probe.sh` and `inngest_consumer_probe_install` (web-1 only, classified `birth-covered` for web-2) are NOT edited. The CA file is written by `ci-deploy.sh` on every deploy on both hosts (not claimed `birth-covered`). `cloud-init.yml` edits reach fresh hosts only; a running host picks nothing up without a replace. No new SSH provisioner is added.

### Distinctness / drift safeguards

`dev != prd`: the new secrets are created in `prd` configs only; dev has no Inngest host. `lifecycle.prevent_destroy` on key and cert (a re-mint would invalidate the CA on every web host until redeploy); the three copies derive from one cert resource so drift cannot occur, and the handshake probe's fingerprint-equality check detects a stale CA file. Roster-change warning (ADR-118): the SAN is the single private IP `10.0.1.40`; changing `inngest_private_ip` plans a cert destroy that `prevent_destroy` rejects at PLAN time, which would fail every merge apply until a dedicated reviewed PR lifts it (the key survives). The replace does not re-mint (the cert and key live in state, not user_data), so the CA on the web hosts stays valid across it.

### Vendor-tier reality check

Better Stack Logs alerts: 15 already exist and the free-tier cap is unmeasured (ADR-218), so this plan adds NO new alert resource and opts in to the existing `monitor_send_failed` alert by needle (Phase 4). Doppler secret count is well under plan limits.

## Observability

```yaml
liveness_signal:
  what: Better Stack Logs row from the Inngest host, stage tls-health (unit state, restarts, fetch rc, bind, listener, served and Terraform cert sha256, days to expiry, handshake failures, legacy_8288 and tls_8443 packets, nft8443_sha256, boot_id)
  cadence: every 5 minutes
  alert_target: the existing monitor_send_failed Better Stack alert (needle opt-in, PRIORITY-2 SOLEUR_INNGEST_TLS_REFUSED via logger -p user.crit -t inngest-tls-health) plus the follow-through sweeper trackers
  configured_in: apps/web-platform/infra/cloud-init-inngest.yml (timer and emitter); the existing monitor_send_failed alert in apps/web-platform/infra/betterstack-logs-alerts.tf already matches the marker (no change)
error_reporting:
  destination: Better Stack Logs source 2457081 - periodic tls-health series via inngest-boot-phone-home.sh (direct POST, layer 3 vector sink twin); refusal marker via logger -p user.crit (layer 3 vector, Source 2); web-side resolver failure via the ci-deploy workflow run log (layer 6) and logger -t ci-deploy (layer 3 vector, Source 4)
  fail_loud: SOLEUR_INNGEST_TLS_REFUSED crit row on listener=0 or cert under 90 days (host emitter); a failing flag-on gate exits the deploy non-zero with a ::error:: line (no downgrade)
failure_modes:
  - mode: stunnel unit down, fetch failed, or key/cert mismatch on the Inngest host
    detection: SOLEUR_INNGEST_TLS_REFUSED crit row (layer 3 vector, Source 2, PRIORITY 2) carrying unit state, nrestarts, fetch_rc and bind in the same tls-health row to separate stunnel dead from fetch failed from nft drop
    alert_route: monitor_send_failed
  - mode: cert nearing expiry (10 y cert, no rotation cron)
    detection: notafter_days < 90 in tls-health and the same crit marker (layer 3 vector); monthly follow-through re-check
    alert_route: monitor_send_failed
  - mode: a web caller still uses plaintext 8288 after the flip
    detection: soak script on the legacy_8288 delta plus the tls_8443 positive control (follow-through tracker comment, no page by ruling)
    alert_route: follow-through sweeper tracker
  - mode: web CA file stale, empty or invalid while the flag is on
    detection: the resolver validation or self-gate fails the deploy (layer 6 workflow run log ::error::) and the canary or the host-side self-gate fails (stunnel handshake failures from a client that rejects the CA)
    alert_route: failed ci-deploy run on the release workflow, and the soak tracker
  - mode: emitter dead (series gap)
    detection: a gap in the tls-health series fails the soak predicate; after the flip the web-side probes dial https 8443 so a down listener already trips the existing probe alarms
    alert_route: no page by ruling (CTO E2): the soak gap predicate and the monthly cert days-left follow-through
logs:
  where: Better Stack Logs (Inngest host source 2457081) and journald on the host; web side journald tag ci-deploy
  retention: Better Stack Logs source retention (existing)
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 15m --grep stage=tls-health --limit 1
  expected_output: listener=1
  credentials_required: BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME and BETTERSTACK_QUERY_PASSWORD (ClickHouse read credentials, Doppler soleur/prd_terraform) - Better Stack warehouse reads have no anonymous path and the ingest token is write-only; no rows exist before the A1 host replace, so A1's success evidence is the live verification
```

## Encryption Posture

```yaml
# No persistent store is introduced. The fetched key/cert copy on the Inngest host lives in a tmpfs
# RuntimeDirectory (memory only, removed with the unit) and is a transient runtime file, not a store.
at_rest:
  - store: doppler.secrets (new keys INNGEST_TLS_KEY, INNGEST_TLS_CERT in soleur-inngest/prd; INNGEST_TLS_CA in soleur/prd)
    mechanism: provider-managed:doppler-aes256-gcm
    evidence: scripts/encryption-posture-ledger.json non_iac_stores entry "doppler.secrets" (attestation https://www.doppler.com/security, retrieved_on 2026-07-24); the new keys add no new store, they live in the already-ledgered Doppler store
    defends_against: physical-media compromise of Doppler's secret storage
    does_not_defend: a leaked Doppler service token (the Inngest host holds one for soleur-inngest) or a compromised host with a live token; whoever reads the key can impersonate the terminator to any client that trusts the CA; a state-file reader (the key is also in Terraform state on the encrypted R2 backend; if the read-only R2 state key the runbook lists as Tier A covers this root's bucket the key is branch-reachable - verify which bucket); and, accepted by the CTO (F2), every process that `doppler run --config` starts on the Inngest host (`inngest-server`, `vector`, the heartbeat) receives `INNGEST_TLS_KEY` in its environment because those units use no `--only-secrets` (follow-up: split config at the next image bake)
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:Doppler attestation formalization pending, tracked #6911
in_transit:
  - connection: web-platform app (web hosts) -> dedicated inngest host 10.0.1.40:8443 (stunnel to 127.0.0.1:8288), AFTER the flag flip
    enforced_at: apps/web-platform/infra/ci-deploy.sh resolve_inngest_link and the three docker run sites (INNGEST_BASE_URL + NODE_EXTRA_CA_CERTS); apps/web-platform/infra/cloud-init-inngest.yml soleur-inngest-tls.service
    tls: TLS 1.2 or higher (stunnel sslVersionMin)
    cert_verification: on (Node verifies against the pinned CA via NODE_EXTRA_CA_CERTS; curl probes use --cacert; a client without the CA fails - asserted by the canary and the handshake probe)
    does_not_defend: a reader of Terraform state or Doppler prd who holds the key plus a private-network position; the loopback hop stunnel to inngest (127.0.0.1:8288) is plaintext inside the host; the cert is a CA:FALSE leaf (a leaked key can only impersonate 10.0.1.40 - OpenSSL will not let a non-CA anchor issue certificates and the IP SAN blocks hostname matches) but it becomes a trust anchor for ALL outbound TLS in the Node app via NODE_EXTRA_CA_CERTS; a 10-year single-purpose cert forces a disruptive rotation unless the CA file holds two certificates (allowed, 1-2 blocks); while the legacy :8288 listener stays open a mis-pointed client still sends plaintext (the legacy_8288 counter detects it)
    disclosed_as: not-publicly-claimed (published wording unchanged until handshake evidence; later PR)
  - connection: Inngest server -> web app sdk_url registration poll (http://10.0.1.10:3000/api/inngest)
    enforced_at: apps/web-platform/infra/inngest-host.tf sdk_url; inngest-bootstrap.sh ExecStart --sdk-url
    tls: none (plain HTTP, private net)
    cert_verification: off
    does_not_defend: a passive on-net reader sees the HMAC-signed registration request and public function metadata; replay beyond HMAC is not possible per the ledger reading but is not wire-verified
    disclosed_as: not-publicly-claimed
  - connection: Inngest server -> app step-call via Cloudflare (serveHost https://app.soleur.ai)
    enforced_at: apps/web-platform/app/api/inngest/route.ts SERVE_HOST; dns.tf cloudflare_record.app; seo-config-rules.tf ssl flexible
    tls: HTTPS to the Cloudflare edge; Cloudflare to origin plain HTTP while ssl=flexible (#10479, live mode unverified)
    cert_verification: on to the edge, none to origin
    does_not_defend: any observer between Cloudflare and the origin reads step outputs (user content)
    disclosed_as: not-publicly-claimed
exception:
  # two rows, both outside this PR's fix; this PR only records them (ledger edits are the later PR)
  - connection: sdk_url poll
    justification: HMAC and public metadata only; web hosts have no TLS listener (CTO D5 (c), CLO 2026-10-18)
    tracking_issue: "#10136"
    reevaluate_when: user content or key material found on the poll; step driver able to use the link; a server beyond the five attached hosts; any non-Jikigai peer or public exposure; a replay beyond HMAC
    expires_on: 2026-12-10
  - connection: Cloudflare step-call leg
    justification: Cloudflare to origin is flexible; the fix is #10479, a separate tracker
    tracking_issue: "#10479"
    reevaluate_when: #10479 settles the live mode, or any origin TLS change
    expires_on: 2026-12-10
```

## Architecture Decision (ADR/C4)

### ADR

New **ADR-292** (provisional ordinal; `soleur:ship` re-verifies the next free number against `origin/main` and after every sync): "Inngest link TLS via a host-local stunnel terminator, a Terraform-minted pinned cert in Doppler, and a Doppler-flagged data-driven flip". Status `adopting` (true after the flip and soak). Decision: terminator unit independent of `inngest-server`; single cert resource with three Doppler copies; CA as host file mounted into containers; resolver as the single chokepoint for the scheme; legacy `:8288` kept and counted for the soak, closed physically at the next unrelated replace. Alternatives considered: native TLS (does not exist at v1.45.1), baked CA in the image, committed cert, second-PR flip, `--host 127.0.0.1` now, nginx/socat/caddy terminators. Amend **ADR-100** with an Addendum pointing at ADR-292 (ADR-100 records transport confidentiality on this link as "accepted, not provided" with the exception tracked on #6897/#10136; the addendum states that this ADR supersedes that acceptance for the `:8288` send path once the soak passes, and the ordinal was re-derived across all `origin/*` refs at deepen: ADR-291 is claimed by a pushed branch ("add an opencode plugin adapter"), so this plan uses ADR-292) (it records the ":8288 control-API scoped by nftables" substrate this changes). Cross-reference ADR-140 and ADR-118.

### C4 views

Read all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Enumerated against the feature: (a) external human actors: none new; (b) external systems: none new (stunnel is a host-level systemd unit of the same deployment node as the `inngest` container, not a process inside it; Cloudflare, Doppler, Better Stack already modelled); (c) data stores: none new (the Doppler store is already modelled); (d) actor-to-surface access changes: none. Changes: the edge `api -> inngest "Sends events" { technology "HTTP private-net :8288" }` becomes `HTTP :8288 (legacy, retired after the soak) / HTTPS :8443 (stunnel terminator, pinned CA, flag-gated, ADOPTING #10136)`; keep two edges so the model never claims TLS before the flip: the existing plaintext edge marked legacy and a new HTTPS edge marked ADOPTING; the `inngest` container description gains one line on the host-level terminator. Run `plugins/soleur/test/c4-count-parity.test.sh` and the C4 syntax/render tests in `apps/web-platform/test/` after editing. The edit lands as "ADOPTING" wording so the model never claims TLS before the flip.

### Sequencing

ADR and C4 land in THIS PR with `adopting` wording; the status flips to `accepted` in the later ledger/legal PR on the handshake and soak evidence. Not a deferred issue.

## Guard Contract

### Guard 1 - Inngest link scheme chokepoint

**Property.** Every consumer of the Inngest link scheme (canary and prod docker run, the first-boot run, the probes, the web egress rule, the watchdog parity test) accepts exactly the http-or-https pair produced by the single `resolve_inngest_link` resolver (http only on a clean not-found or a lapsed lease, otherwise https or a failed deploy), and a client that lacks the pinned CA cannot complete a handshake.

**Assembly.** Chokepoint: `resolve_inngest_link` in `ci-deploy.sh` (writes `INNGEST_BASE_URL_RESOLVED`, `/mnt/data/inngest-link/inngest-link.env`, `/mnt/data/inngest-link/inngest-ca.pem`). Members flowing through it: the canary `docker run` and the prod `docker run` (both in `ci-deploy.sh`), `inngest-registry-probe.sh` (parses the env file; the consumer probe sources it) and `inngest-doublefire-probe.sh`. Members that cannot call the resolver: the first-boot `docker run` in `cloud-init.yml` (literal http, re-resolved at the next deploy), `cron-egress-nftables.sh` (accepts both ports), `cron-inngest-cron-watchdog.test.ts` parity. More than one chokepoint exists on purpose; `docker-run-tuple.py` quantifies over `docker run` sites by file, so a fourth site is a member of the gate, and the gate covers all three run sites.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the canary site's `INNGEST_BASE_URL` with a literal `https://10.0.1.40:8443` (bypass the resolver) | tuple gate RED |
| 2 | Delete the `dport 8443` accept from `cron-egress-nftables.sh` | `cron-egress-firewall.test.sh` and the postapply assert RED |
| 3 | Add a fourth `docker run` site after the compliant three, carrying the old literal | tuple gate RED (unknown site); a gate that stops at the third site is itself the defect |
| 4 | Make the tuple gate find zero `docker run` sites (point it at an empty file) | RED, never "0 checked, exit 0" (the guard's own dispatch) |
| 5 | Remove the resolver's `curl --cacert` self-gate so a flag-on, CA-empty host keeps https | resolver unit test RED (must exit non-zero and keep the old container, never downgrade) |
| 6 | Drop `-v ...inngest-ca.pem:ro` from the prod site only | tuple gate RED |
| 7 | Probe scripts ignore `/mnt/data/inngest-link/inngest-link.env` and keep the http default | probe suites RED once the flag fixture is set |
| 8 | Resolver emits a third value (for example `http://10.0.1.40:8443`) | resolver unit test and tuple expansion check RED |
| 9 | Flag previously on and the Doppler read errors (not a clean not-found) | resolver exits non-zero; mutation making it fall through to http goes RED |
| 10 | CA validation weakened: accept a PEM containing a PRIVATE KEY block, a wrong SAN, `CA:TRUE`, or more than 2 certificates | resolver unit test RED for each variant (separate rows) |
| 11 | Flag value outside the allowlist (`0`, `true`, `pending:abc`, an epoch more than 31 minutes ahead, an expired lease) | resolver unit test: non-allowlisted fails the deploy, expired lease resolves to http plus an event |
| 12 | A prd env containing `NODE_TLS_REJECT_UNAUTHORIZED` or `NODE_EXTRA_CA_CERTS` | `overlay_github_app_key` refusal test RED (rc 1) |

**Harness rows:** (H1) edit the SUITE: stub `curl` in the resolver test to always succeed - the "CA withheld must fail" case must go RED, proving the test can see a vacuous self-gate; (H3) a leaf signed with the cert's own key must NOT validate in Node (proves a non-CA anchor cannot issue); (H2) must-PASS non-canonical input: flag unset (default http) and flag on with a valid CA both PASS, and a flag-on case whose CA file differs in whitespace/trailing newline from the canonical fixture PASSes (a suite that only accepts the canonical bytes is vacuous in the other direction).

**Anchor.** The allowed value pair lives in `docker-run-tuple.py`, which a PR can edit together with the site; the independent anchors are the K07/K10 mutation rows, the pinned absence of `NODE_TLS_REJECT_UNAUTHORIZED`, and the runtime canary (`docker inspect` https, in-container fetch, CA-withheld negative control), which no static edit can fake. The posture literal does NOT anchor env or volumes (its digest covers AppArmor, seccomp and tmpfs only).

### Guard 2 - Legacy 8288 soak predicate

**Property.** The soak passes only if the `legacy_8288` counter delta is zero (the value never increases after the post-drain baseline row; it is cumulative since boot and legitimately non-zero before the flip) while the `tls_8443` delta stays at least 90% of the expected probe cadence, across a gap-free `tls-health` series since T on a single boot.

**Assembly.** Emitter (`soleur-inngest-tls-health.timer` on the host) to Better Stack to `scripts/followthroughs/inngest-tls-soak-10136.sh` to the tracker directive; the follow-through script is the single chokepoint that decides pass or fail. Members: every row in the window (a check that inspects only the last row is the defect).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture series where the legacy counter increases mid-window after the baseline row | script exits non-zero |
| 2 | Fixture series all-zero but with a 3-hour gap | exits non-zero (gap) |
| 3 | Add a second `boot_id` partway (reboot) after compliant rows | exits non-zero and reports the clock restart |
| 4 | Query returns zero rows or a transport error | exits transient/non-zero, never PASS (the guard's own dispatch) |
| 5 | Series with a flat NON-zero legacy counter after the baseline (pre-flip traffic) and rising `tls_8443` | PASS (delta, not absolute) |
| 6 | Legacy counter flat and `tls_8443` flat too (zero traffic) | exits non-zero (a flat counter at zero traffic proves nothing) |
| 7 | Legacy counter decreases without a `boot_id` change | exits non-zero (treated as a reset anomaly) |

**Harness rows:** (H1) edit the suite: make the fixture builder emit all rows with the same timestamp - the gap case must still be detectable (the builder must be able to produce a gap); (H2) must-PASS non-canonical: emits at 5 min +/- 20 s jitter, 48 h exactly, counters 0 - PASSes.

**Anchor.** T (last prod swap plus drain) and the baseline row are read from the tracker comment authored at flip time, not from the script, so a weakening of the script cannot move the window.

## Domain Review

**Domains relevant:** engineering, legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** CTO agent ruled D1-D7 on 2026-10-18 (Rulings table). Concerns carried into the plan: user_data headroom, tuple gate and parity-test coupling, web egress default-drop, #10405 hunk coordination, the flag actuator being an agent-run Doppler write, the Production Envelope requirement (no `Delegation:` record exists; see Production Actions).

### Legal (CLO)

**Status:** reviewed
**Assessment:** CLO agent ruled 2026-10-18: the poll leg may be a dated tracked second step to 2026-12-10 with its own row; the `:8288` row converts to measured TLS for that leg only after handshake evidence; the step-call row is gated on #10479; wording stays as corrected in PR #10326; the engineering PR carries no `docs/legal/**` or ledger-value changes; the "no known access" record format is fixed (A6). Draft material, not external counsel advice.

### Product/UX Gate

**Tier:** none (no user-facing surface; infrastructure and server change). Mechanical UI-surface override checked: no `components/**`, `app/**/page.tsx` or `layout.tsx` file in Files to Create/Edit.
**Decision:** not applicable
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

### Other reviewers run at deepen

security-sentinel, observability-coverage-reviewer, user-impact-reviewer, terraform-architect and deployment-verification-agent ran at deepen; their findings are folded in (see Enhancement Summary). No domain beyond engineering and legal is relevant.

**CPO sign-off (`requires_cpo_signoff: true`):** SIGN-OFF WITH CONDITIONS (CPO agent, plan review 2026-10-18). Conditions folded into the plan: (1) replace duration and event-loss/replay behaviour measured and written in the runbook, a low-traffic window and a status-notice decision (Phase 0 item 8c, A1); (2) #10405 decision checkpoint 2026-10-28 with the replace-without-it fallback (Risks, A1); (3) follow-up issues filed before merge (Deferral Tracking); (4) an owner-go checklist for O1, O3, O4, O5 with dates on #10136 (ship-time `action-required` issue). `user-impact-reviewer` still runs at review time.

## Dependencies & Risks

- **user_data budget (top risk).** Real headroom 1,852 B against the Hetzner cap and 1,384 B against the repo test budget (`INNGEST_GZIP_BUDGET = 32_300`). CTO estimate for the terminator alone: 1.2-1.5 KB raw. Fallback ladder, in order: (1) terse comments (comments are stripped from the measured size, but keep rationale in `.tf`/runbook, not the template); (2) dedupe existing code bytes in the diagnostic blocks of the template (CTO-sanctioned); (3) fold the tls-health emitter into the stunnel unit's own `ExecStartPost` loop instead of a timer unit; (4) STOP and escalate to the CTO - never raise the cap or bypass the gate. A rejected user_data at replace time is a stranded host (2026-09-08 precedent): the gate must be green before A1.
- **#10405 coordination.** Draft in another session's worktree; read-only for us. Our hunks: nft script block, `packages`, new `write_files`, `runcmd` additions, `inngest-host.test.sh` isolation-regex rows (`doppler-injection-bound.test.sh`, which they also edit, is not touched by this PR). Theirs: `net-health` emit, `inngest-cutover-flip.sh`, rehearsal workflow/tests. Rebase onto `origin/main` after it merges (never merge main). If both land, re-run the full `cloud-init-inngest-*` and `inngest-host` suites and `doppler-injection-bound.test.sh`.
- **Egress silent drop.** Without the web egress accept, every https call times out; mitigated by the postapply assert and the canary layer.
- **Flag actuator.** The flip is an agent-run Doppler write by an executing session under the owner's recorded go. If a standing delegation record is created later, A3 and A5 can move under it; until then each act is one explicit step.
- **Key in the server environment (CTO F2, accepted).** `inngest-server`, `vector` and the heartbeat run under `doppler run --config` without `--only-secrets`, so `INNGEST_TLS_KEY` reaches their environments; the marginal exposure is small because a process that can read that environment already holds the signing and event keys. Recorded in `does_not_defend`; follow-up: `--only-secrets` or a split config at the next image bake.
- **A broken gate blocks releases while the flag is on (CTO F1, accepted).** The runbook says so; rollback is the flip workflow with `action=off`.
- **Mixed fleet.** web-1 and web-2 resolve the flag at their own deploys; the flip workflow promotes the flag only after both prod swaps verify, and A1/A3 preconditions assert both hosts report the CA fingerprint and the egress rule.
- **Replace duration and event loss are unmeasured.** The scheduler host is unavailable for the replace window; whether events sent meanwhile are lost or replayed is measured in Phase 0 (item 8c) and written in the runbook before A1; a failed replace waits for a fresh owner go, so the disruption can outlast the window if the owner is away. The owner may choose to pre-authorize one bounded retry; that is their decision, not assumed here.
- **#10405 slip.** Internal checkpoint 2026-10-28 (CTO F5): if #10405 is not mergeable by then, the replace proceeds without it and this PR's own `nft8443_sha256`/rule-count fields are the measured evidence; the CLO's measured-re-read condition then rests on that field.
- **Workflows that can apply the touched Terraform.** `apply-web-platform-infra.yml` (push on `*.tf`; the merge `-target` list gains the new addresses), `apply-deploy-pipeline-fix.yml` (push on deploy-script paths; delivers `ci-deploy.sh` and the hook template), and the Inngest host only via the `inngest-host-replace` dispatch; `inngest-provision-rehearsal.yml` boots the changed template on a throwaway host (the real-boot proof of the stunnel unit) and is also edited by #10405 - rebase carefully.
- **Cert has no rotation cron.** 10-year cert, alert at 90 days; a re-mint forces a redeploy of every web host (CA file) and a host replace (key/cert fetch) - documented in the runbook.
- **Residual pre-existing exposures (unchanged here):** Connect ports 50052/50053 are not nft-scoped and unused; `--host 0.0.0.0` keeps the plaintext listener on all interfaces until the follow-up. Both tracked in the deferral issue.
- **Node 22 behaviour** with an empty extra-CA file is probed locally on Node 26 only; the canary re-verifies on `node:22-slim`.
- **Time pressure:** replace due 2026-11-05; ledger row expires 2026-11-12; CLO hard stop 2026-12-10. Hold no merge for #10405 unless a conflict forces it.

## Deferral Tracking

Issues to file during the work phase (each with a milestone from `knowledge-base/product/roadmap.md`; the epic's milestone is "Phase 4: Validate + Scale"; `gh issue edit <n> --add-blocked-by` where a blocker is known):

1. "Inngest sdk_url poll TLS: web-side listener or poll removal (leg 2 of #10136), merge by 2026-11-12, row lapses 2026-12-10" - Ref #10136. File BEFORE merge (CPO condition).
2. "Inngest host: bind :8288 to loopback, drop the legacy accept, restrict Connect ports 50052/50053 at the next unrelated replace" - Ref #10136; re-evaluate when the next replace is scheduled.
3. The ledger-and-legal-wording PR (mirror-paired privacy documents, SHA pins, ledger value conversion, NFR-026 update, CLO attestation) is tracked on #10136 itself (already listed as "Not started"); add a checklist line there rather than a new issue.
4. A comment on #10479 that #10136 may not close until it is green.
5. Follow-through enrollment (created at the moment each act runs, with the sweeper directive): one issue per production act A1, A3, A5, a soak tracker (A4), and a monthly cert days-left re-check tracker (`notafter_days` stays above 90) - Ref #10136, label `follow-through`.
6. "INNGEST_SIGNING_KEY rotation apply route: a minimal `apply_target` for rotating the dedicated and app copies (CTO F3)" - Ref #10382, Ref #10136; A5 waits on it.
8. "Stripe webhook swallows an Inngest send failure and returns 200 with the dedup row claimed - a lost `invoice.payment_failed` send is permanent" - P1, schedule before 2026-11-05 (pre-existing; found at deepen).
9. "Dashboard send archives the draft when `inngest.send` throws (`degraded = enqueue_failed`), losing an approved Concierge action" - pre-existing; found at deepen.
10. "INNGEST_EVENT_KEY rotation decision: a sniffed key permits forged `agent.spawn.requested` / `finance.payment_failed` events" - Ref #10382; decision due 2026-11-12; rotate with the signing key in the same follow-up `apply_target`, in one restart-and-redeploy window (CTO G6).
11. "`inngest_host_replace` has no confirm or id-pin input; add one" - Ref #10136 (CTO G5).
7. "Inngest host: run `doppler run` units with `--only-secrets` or a split config so the TLS key is not in the server environment (CTO F2)" - Ref #10136; next image bake.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| nginx stream / socat / caddy terminator | stunnel4 has the smallest config, no per-connection fork, and one apt package; the byte budget favours it (CTO D1). |
| Baked CA in the app image | Rollback would need an image rebuild; host-side probes need the file on disk anyway (D3). |
| Committed generator script minting the key | The private key would pass through an agent session; "public cert committed" is unsatisfiable in one PR (D2). |
| Code-line URL flip in a second PR | Violates "one PR" and the merge-queue no-sync-push rule; the Doppler flag buys flip and rollback with no merge (D4). |
| Terraform-managed flag (`doppler_secret` with ignore_changes plus a replace dispatch) | Possible, but adds a new apply target and a dispatch workflow for a single toggle; revisit in deepen-plan only if the Doppler CLI write is judged non-delegable. |
| `--host 127.0.0.1` on the Inngest server now | Requires a bootstrap-image rebuild and a second replace (D6). |
| Repoint `--sdk-url` to `https://app.soleur.ai` | While Cloudflare is flexible this moves the poll onto plain HTTP over the public internet, worse than today (D5, CLO). |
| Remove the sdk_url poll | Depends on unverified SDK auto-registration; loses the self-heal described in `route.ts` (D5). |
| Bake the TLS helper into the OCI bootstrap image / config-refresh channel | Not available at first boot; an image mint is required (D1). |

## Acceptance Criteria

<!-- founder-stated check: owner constraints from the invocation are mapped in Scope Check -->

### Pre-merge (PR)

### Functional Requirements

- [ ] `inngest-tls.tf` creates the cert, key and three Doppler secrets; the new addresses are on the merge `-target` list; `terraform validate` and plan show only additive changes (no `hcloud_server`).
- [ ] `cloud-init-inngest.yml` renders with `stunnel4`, the unit, the fetch step, the `tls-health` timer and the nft changes; `inngest-userdata-budget.sh` stays green with >= 300 B margin and the repo budget test passes unchanged.
- [ ] nft: the existing `8288/8289` accept and drop lines are byte-identical; the `legacy_8288` counting rule precedes the accept; `8443` accept for web IPs then drop; `nft -c -f` validates the rendered script.
- [ ] `ci-deploy.sh` resolver: flag unset gives `http://10.0.1.40:8288`; flag on with a valid CA gives `https://10.0.1.40:8443`; flag `pending:<epoch>` is https inside the 30-minute lease and http plus an event after it; flag on with a failed self-gate, a read error or an empty/invalid CA exits non-zero (no downgrade); the CA file always exists before `docker run`.
- [ ] `docker-run-tuple.py` accepts only the resolver expansion for `INNGEST_BASE_URL`, the `NODE_EXTRA_CA_CERTS` env and the CA `-v` string at all three sites; each Guard 1 mutation row goes RED in `docker-run-tuple.test.sh`.
- [ ] Web egress `:8443` accept present, asserted by `cron-egress-postapply-assert.sh`, pinned in `cron-egress-firewall.test.sh`.
- [ ] The registry and doublefire probes (and the consumer probe through the registry probe) honour `/mnt/data/inngest-link/inngest-link.env`, overriding an inherited `INNGEST_REMOTE_GQL_URL`; `inngest-registry-probe.sh --tls-handshake` implements checks (a) and (b).
- [ ] `inngest-tls-soak-10136.sh` and its test cover every Guard 2 row (delta semantics, the `tls_8443` positive control, the reboot and decrease anomalies); sweeper `secrets=` additions made if needed.
- [ ] ADR-292 and the ADR-100 addendum are written; C4 edited; `c4-count-parity` and C4 render tests pass; runbook section added; `scripts/lint-encryption-posture.py` still PASS (ledger values untouched).
- [ ] No change under `docs/legal/**`; no ledger value change.

### Non-Functional Requirements

- [ ] Nothing in the PR changes behaviour of running traffic at merge (the default path's resolver output is the old URL).
- [ ] No secret values in any log, emit, plan, PR body or test fixture (`cq-test-fixtures-synthesized-only`); the key never appears on argv or stderr of stunnel or the fetch step.
- [ ] No SSH in any runbook step or probe; all reads go through hooks, workflows or the Better Stack query script.
- [ ] NFR register assessment (a plan-time review step, not a post-condition): `soleur:architecture assess` against `knowledge-base/engineering/architecture/nfr-register.md` (NFR-026 status is updated in the later PR, not here).
- [ ] Words: "unavailable"/"disruption" only, in code comments, runbook and PR body (`git grep -n -i 'out''age' -- <changed files>` empty).

### Quality Gates (pre-merge)

- [ ] `bash apps/web-platform/infra/inngest-userdata-budget.sh` exits 0 and prints a margin of at least 300 B; the repo budget test passes unchanged; `docker-run-tuple.py` check passes on all three tuples; the `-target` guard suites pass; `scripts/lint-encryption-posture.py` PASS.
- [ ] PR body: `Ref #10136` (no closing keyword), `## Changelog` section, `semver:patch` label rationale, Production Actions summary, the decision-challenges render.
- [ ] PR body first line states the answer to "does merging this alone mutate production" (section above), uses `Ref #10136` only, and carries `## Changelog`.

### Post-merge (automated, no owner log-watching)

- [ ] `deploy-arm.sh find --wait <full-sha>` then `served <full-sha>` from a detached `origin/main` worktree; merge-apply secrets present (names only); both web hosts show the egress accept and the CA file fingerprint.
- [ ] Production Actions A1-A6 executed in order against their evidence columns, each only after its preconditions are evaluated; A7 is an owner item. A failed replace waits for a fresh owner go.
- [ ] `#10136` stays open; a checklist line records the later ledger-and-legal-wording PR and the #10479 gate.

## Test Scenarios

Labels: unit / integration / e2e (pyramid-justified markers where e2e).

### Acceptance Tests (RED phase targets)

- unit: Given the flag is unset, when `resolve_inngest_link` runs, then `INNGEST_BASE_URL_RESOLVED=http://10.0.1.40:8288` and `/mnt/data/inngest-link/inngest-ca.pem` exists (possibly empty).
- unit: Given the flag is `1` (or an unexpired `pending:<epoch>`) and `curl --cacert` succeeds, then the resolved URL is `https://10.0.1.40:8443` and the link env file says `scheme=https`.
- unit: Given the flag is on and the self-gate fails, then the deploy exits non-zero, the old container keeps serving and no http URL is handed to the new container.
- unit: Given each Guard 1 and Guard 2 mutation, then the named suite fails (see matrices).
- integration: Given the rendered `cloud-init-inngest.yml`, when the extracted nft script is passed to `nft -c -f`, then it validates and the accept line text is unchanged.
- integration: Given a self-signed cert with SAN 10.0.1.40 and a local stunnel fixture, when `curl --cacert` hits it, then 200; without `--cacert`, curl exit 60; with a cert whose SAN lacks the IP, curl fails hostname verification.
- e2e (pyramid-justified: the canary container is the only place Node 22, the real mount and the egress rules meet): the canary container reaches `/health` over TLS with the env and fails without it.

### Regression Tests

- Given the default path, when `docker-run-tuple.test.sh` runs, then the pre-existing mutation rows still pass.
- Given the `net-health` region of `cloud-init-inngest.yml`, then this PR's diff does not touch it (hunk-disjoint check against #10405's diff).

### Edge Cases

- Given web-1 cloud-init is frozen, when the CA file is needed, then `ci-deploy.sh` (not cloud-init) provides it; a fresh host gets a placeholder from cloud-init.
- Given Docker is asked to bind-mount a missing file, then the resolver has created it first (docker would create a directory).
- Given a host reboot during the soak, then the `boot_id` changes and the soak clock restarts.
- Given the NIC is late at boot, then the stunnel unit restarts until the bind succeeds (or the `accept = 8443` fallback applies) and `legacy_8288` still counts.

### Integration Verification (for `soleur:qa`)

- **API verify:** `bash scripts/betterstack-query.sh --since 15m --grep tls-health --limit 1` expects a row containing `tls-health` (credentials via Doppler `prd_terraform`).
- **Handshake:** web-host hook `/hooks/inngest-registry-probe` in `--tls-handshake` mode expects `verified=200 unverified=fail`.

## Files to Edit

- `apps/web-platform/infra/cloud-init-inngest.yml` (packages, write_files, nft block, runcmd)
- `apps/web-platform/infra/ci-deploy.sh` (resolver, CA write, two run sites)
- `apps/web-platform/infra/cloud-init.yml` (first-boot run site, placeholder CA file)
- `apps/web-platform/infra/lib/docker-run-tuple.py`, `apps/web-platform/infra/docker-run-tuple.test.sh`
- `apps/web-platform/infra/cron-egress-nftables.sh`, `cron-egress-postapply-assert.sh`, `cron-egress-firewall.test.sh`
- `apps/web-platform/infra/inngest-registry-probe.sh` (+ `.test.sh`; link resolution and `--tls-handshake` mode), `inngest-doublefire-probe.sh` (+ `.test.sh`), `hooks.json.tmpl` (new `inngest-tls-handshake` hook entry)
- `apps/web-platform/infra/inngest-host.test.sh` (new nft rules with the accept line unchanged; isolation-regex PASS/FATAL rows), `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `apps/web-platform/infra/variables.tf` (`inngest_link_tls`)
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` (one guard row for the new marker) and `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (one decode row); `betterstack-logs-alerts.tf` itself needs no change (SQL already matches)
- `.github/workflows/apply-web-platform-infra.yml` (merge `-target` list), `.github/workflows/infra-validation.yml` (register new tests), `.github/workflows/scheduled-followthrough-sweeper.yml` (secrets, if needed)
- `apps/web-platform/test/server/inngest/cron-inngest-cron-watchdog.test.ts` (parity relaxed to set membership)
- `apps/web-platform/app/api/internal/schedule-reminder/route.ts` (+ its test): 503 mapping for timeout and TLS causes
- `plugins/soleur/test/terraform-target-parity.test.ts`, `tests/scripts/test-infra-privileged-tier-census.sh`, `tests/scripts/test-inngest-host-replace-gate.sh` (a `tls_*` create aborts), `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` (D8 census row for the flip job), `knowledge-base/engineering/operations/runbooks/monitor-send-failed-alert.md` (decode row, wording fix), `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` (`BASELINE_PASSES=81`, `BASELINE_CASES=10`, new mutation row)
- `.github/workflows/apply-web-platform-infra.yml` also gains the flip `apply_target` job (and its dispatch-input option)
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` (only if constants or enumerations need the new entries)
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES` bump from 69, with a PLACEMENT/TRUTH/NO-SUBSTITUTE comment: the Observability block declares `credentials_required`)
- `-target` allow-list guard suites: derive with `git grep -ln -e '-target=' -- tests/ scripts/ apps/web-platform/test/ plugins/soleur/test/` and add every suite that asserts on the merge `-target` list (the alert drift guards under `apps/web-platform/test/infra/` and any orphan scope-guard suite) to this list at work time
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and `views.c4` if an include is needed)
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` (addendum)
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`, `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`
- `scripts/encryption-posture-ledger.json` - ONLY `enforced_at` pointers if the lint forces them (CLO ruling 4)

## Files to Create

- `apps/web-platform/infra/inngest-tls.tf`
- `.github/workflows/inngest-link-flip.yml` (dispatch-only flip workflow; may need a `scripts/pr-fanout-ledger.txt` row only if it ever gains `on: pull_request`) and its drift/guard test; register in `.github/workflows/infra-validation.yml` as needed
- `apps/web-platform/infra/inngest-link-resolver.test.sh` (resolver unit suite; the resolver function lives in `ci-deploy.sh`)
- `scripts/followthroughs/inngest-tls-soak-10136.sh` (+ `.test.sh`)
- `knowledge-base/engineering/architecture/decisions/ADR-292-inngest-link-tls-terminator-and-flagged-flip.md` (provisional ordinal)
- `knowledge-base/project/specs/feat-one-shot-10136-inngest-tls-verification/decision-challenges.md`, `tasks.md`
- (after A6, not in the PR) `knowledge-base/legal/audits/<date>-inngest-signing-key-rotation-no-known-access.md`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it (`single-user incident`).
- `nft -f` merges into an existing table; the nftables unit is a boot-time oneshot, so a counter object and rules are safe to declare once per boot only. Never re-run the script within a boot to "refresh" counters.
- Reading the counter must use `nft list counter inet soleur_inngest legacy_8288`, not the chain listing; the chain text is hashed by #10405's fingerprint and must stay stable.
- The tuple gate's digest does not cover env or volumes (`e959fc801d99` covers AppArmor, seccomp and tmpfs only); the env and volume additions are pinned by the exact-set checks and the K07/K10 mutation rows - keep the posture literal in both pinned places in lockstep.
- `NODE_EXTRA_CA_CERTS` is read once at process start; a CA change needs a container restart (a redeploy), not a reload.
- A fixture PEM in tests must be synthesized (`cq-test-fixtures-synthesized-only`); never commit the real cert or key, and never paste either into a PR or log.
- Rationale prose in `cloud-init-inngest.yml` is stripped by the budget gate but still ships on the host; keep long rationale in `inngest-tls.tf` and the runbook (the repo convention for this template).
- The plan-write guard matches `systemctl <verb>` and the Doppler write phrase; production acts here are phrased as agent-run steps under a recorded go, and the IaC-routing acknowledgement at the top of this file records the review.
