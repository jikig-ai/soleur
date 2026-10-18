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

Ref #10136, Ref #10205 (item 4), Ref #10382 (row 1), Ref #9139. Draft PR #10501. This plan never closes #10136: the issue stays open for the zot rows, the ledger and legal-wording PR, and the Cloudflare leg (#10479).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
IaC routing note (Phase 2.8 reviewed): every infrastructure resource in this plan is Terraform or cloud-init (see `## Infrastructure (IaC)`). The two phrases the plan-write guard matches are (1) unit-enable lines that are cloud-init `runcmd` content, and (2) the single non-secret flag write `INNGEST_LINK_TLS` to Doppler `soleur/prd`, which is a runtime toggle recorded as a production act under the owner's recorded go (the invocation lists Doppler secret writes as production actions). The Terraform-managed alternative for the flag (ignore_changes on the value plus a replace dispatch) is recorded under Alternatives Considered.

## Overview

The web-platform app talks to the dedicated Inngest host (`10.0.1.40`) over plain HTTP on `:8288`. That hop carries `INNGEST_EVENT_KEY` (in the `/e/<key>` path), the hashed signing key as a Bearer on run-list reads, and event payloads (user prompts and agent output). The CTO and CLO rulings of 2026-10-18 (issue comment on #10136; `/var/tmp/10136-rulings/issue-comment-rulings.md`) require TLS with certificate verification on this hop, live by 2026-11-12 (fallback 2026-11-19; CLO hard stop 2026-12-10). The owner go is recorded (2026-10-18, #10136): build the PR, one Inngest host replace by 2026-11-05, and `INNGEST_SIGNING_KEY` rotation.

The design (ruled in detail by the CTO on 2026-10-18, see Rulings table):

- A host-local `stunnel4` terminator on the Inngest host, `10.0.1.40:8443` to `127.0.0.1:8288`, in its own systemd unit that `inngest-server` does not depend on.
- A self-signed ECDSA cert with SAN IP `10.0.1.40`, minted by Terraform (`proxy-tls.tf` pattern), key and cert delivered through Doppler, never baked in user_data.
- The CA reaches web containers as a host file `/etc/soleur/inngest-ca.pem` (written by `ci-deploy.sh` from Doppler), mounted read-only, with `NODE_EXTRA_CA_CERTS` at the three `docker run` sites.
- The URL flip is data-driven: a Doppler flag `INNGEST_LINK_TLS=1` read by one resolver in `ci-deploy.sh`. Flip and rollback need a Doppler write and a redeploy, never a code merge. This is what makes "one PR, inert until the host replace" possible under a merge queue that forbids sync pushes.
- Old `:8288` stays open for the soak, with a named nftables counter `legacy_8288`. The soak closes on 48 h of gap-free emits with delta zero.

Everything in this PR is **inert at merge**: the default resolver output is still `http://10.0.1.40:8288`; the new Terraform resources are unreferenced; the new egress accept, CA file and probes are additive. Nothing changes for running traffic until (1) the single Inngest host replace, (2) the flag flip through a canary deploy.

## Research Reconciliation: Spec vs. Codebase

| Spec / ruling claim | Reality (origin/main `840dc667fc`) | Plan response |
|---|---|---|
| CTO: "public cert committed" (proxy-tls precedent) | `tls_self_signed_cert` computes validity at apply, so a committed PEM cannot exist before the first apply; a committed generator would pass the private key through an agent session. | CTO amended (D2): no committed cert. One Terraform cert resource feeds three Doppler copies, so drift is structurally impossible. Runtime verification replaces the committed-copy check. |
| "NODE_EXTRA_CA_CERTS at the three docker run sites" | Node needs a readable file path; the tuple gate (`lib/docker-run-tuple.py`) pins exact `-e` value sets and exact `-v` strings; docker creates a DIRECTORY for a missing bind source; web-1 cloud-init is frozen (`ignore_changes=[user_data]`). | CA is a host file written by `ci-deploy.sh` before every `docker run`; gate gains the `-v` string and env key; placeholder file when the flag is off (D3). |
| "counter on the old 8288 rule" | `nft list chain` prints `counter packets N bytes M` which changes per read; PR #10405 adds an `nft_sha256` fingerprint of the raw chain listing in the boot `net-health` emit. An inline counter makes the fingerprint vary per read. | A separate, preceding, verdict-less rule `counter name "legacy_8288"` (named counter object). Existing accept line stays byte-identical (`inngest-host.test.sh` greps it); chain text stays stable (D6). |
| "~8 probe scripts to --cacert" | Measured: three web-host probes hit `10.0.1.40:8288` (`inngest-registry-probe.sh`, `inngest-doublefire-probe.sh`, `inngest-consumer-probe.sh`), one inngest-host self-curl diag, one app fallback constant. Every other `8288` reference is loopback (`127.0.0.1:8288`) and unaffected. | Three probes become scheme-aware through `/etc/soleur/inngest-link.env`; the host self-curl stays http (it hits the legacy listener on purpose); fallback constant stays http (D4). |
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
| 6 | "~8 probe scripts to --cacert" | Phase 3 (three probes + handshake probe; the rest are loopback) | mapped |
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

- **If this lands broken, the user experiences:** agent runs, reminders and scheduled work that depend on event sends to the scheduler stop starting for every user (the app cannot reach the Inngest host), until the flag is unset and the app redeployed (minutes) - or, if the host replace goes wrong, the scheduler host is unavailable for the duration of the replace window and recovery.
- **If this leaks, the user's prompts and agent output are exposed via:** the existing plaintext `:8288` hop, readable by any peer on `10.0.1.0/24` (passive read; `INNGEST_EVENT_KEY` is in the `/e/<key>` path). This PR narrows that exposure; a mis-flip that leaves clients on `http` keeps today's exposure, and the soak counter is what detects it.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one user's prompt or agent output readable on a shared subnet is a brand-level event even at today's single-digit tenancy; this is the exposure the PR exists to close, and a broken flip degrades every user at once, so the stricter tier is kept.

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
| D3 CA to web | Host file, not baked: `ci-deploy.sh` writes `INNGEST_TLS_CA` atomically to `/etc/soleur/inngest-ca.pem` before every `docker run`; all three sites get `-v ...:ro` + `-e NODE_EXTRA_CA_CERTS`, pinned in the tuple gate; fetch failure non-fatal while the flag is off (empty placeholder), fatal when on. |
| D4 Flip lever | Data-driven: Doppler `soleur/prd INNGEST_LINK_TLS=1` read by one resolver in `ci-deploy.sh` that sets `INNGEST_BASE_URL` (absent means `http://10.0.1.40:8288`) and writes `/etc/soleur/inngest-link.env` for the probes; self-gate (amended by CTO F1 after plan review: with the flag on a failed self-gate fails the deploy instead of falling back to http; see the amendment row below); tuple gate accepts exactly two values via one pinned expansion; `INNGEST_HOST_FALLBACK` stays http while `:8288` is open; watchdog parity test relaxed to set membership. |
| D5 Legs 2 and 3 | (c) bounded, tracked, dated 2026-12-10 for the poll (void trigger: user content found on the poll); step-call leg gated on #10479 with a ledger row and a closure-guard predicate on #10479. CLO confirmed sequencing with conditions (Legs table). |
| D6 Old 8288 | Keep the accept; add a separate preceding counting rule with named counter `legacy_8288`; read with `nft list counter` from a periodic emitter shipped via the allowlisted phone-home tag; do not bind loopback now (needs image rebuild + second replace); soak closes on 48 h gap-free emits with delta zero since the flip (reboot restarts the clock); follow-through enrollment; physically closing `:8288` rides the next unrelated replace (tracked issue). |
| D7 Ordering | Merges inert: TF secrets (added to the merge `-target` list), web egress accept, resolver + CA write (default http), tuple gate, scheme-aware probes, cloud-init edits (no `hcloud_server` in the merge apply). Must precede the replace: egress accept on every web host (`cron-egress-postapply-assert`), CA file on every web host (one deploy), secrets present in both Doppler projects. Dispatch checks: budget gate, destroy-guard, stock preflight, #10405 merged or explicitly bundled. After: handshake from each web host, canary with flag, prod, soak. Do not touch the `net-health` emit or `inngest-cutover-flip.sh`; TLS fields go in a new `tls-health` phone-home line in a different hunk; nft edit confined to the nftables script; rebase after #10405 merges. |
| CLO 1-4 | Poll leg may follow as a dated tracked step (2026-12-10; own row; never repoint publicly); `:8288` row converts to measured TLS after handshake evidence, other legs carry their own rows; wording until each leg is verified stays as corrected in PR #10326, s11 may cover only application-to-scheduler event submission when the `:8288` leg is verified, DPD 8.1(c) flips for that leg only; "no known access" record format fixed (A6); engineering PR carries no `docs/legal/**` change. |
| Plan-review amendments (CTO F1-F6) | F1: with the flag on, a failed self-gate, a flag read error or an empty/invalid CA fails the deploy (no http downgrade); the canary `docker inspect`s https, fetches the handed URL in-container and runs a CA-withheld negative control. F2: TLS key in the server environment accepted and recorded, follow-up for `--only-secrets`. F3: the rotation apply route is a separate follow-up; A5 waits. F4: add named counter `tls_8443` as the positive control; soak needs legacy delta 0 and `tls_8443` delta >= 90% of cadence. F5: internal checkpoint 2026-10-28 for #10405, then replace without it using `nft8443_sha256` and rule count. F6: T = last prod swap + drain with a baseline row; the flip is a dispatch workflow with a failure/cancel revert step and a 30-minute `pending:<epoch>` lease. |

## Inert / active matrix

| Item | At merge | After host replace | After flag flip |
|---|---|---|---|
| `inngest-tls.tf` resources, 3 Doppler secrets | created by the merge apply, unreferenced by any running process | referenced by the new host | unchanged |
| Web egress `:8443` accept | present on web-1 and web-2 (additive) | unchanged | used |
| `/etc/soleur/inngest-ca.pem` | written (empty placeholder if secret absent) at next deploy | real PEM | real PEM |
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
4. Node 22: `NODE_EXTRA_CA_CERTS` with an empty file, a missing file and a directory must not stop startup (docker image `node:22-slim` as in the Dockerfile); record the exact warning text.
5. Confirm stunnel4 on Ubuntu 24.04 (apt candidate version, `sslVersionMin = TLSv1.2`, journald logging with no key material on argv/stderr), and the NIC ordering: the unit must order after the private NIC is up (`soleur-inngest-nic-wait` helper in the template; post-mortem 2026-09-22). If binding to `10.0.1.40` races the NIC despite ordering, fall back to `accept = 8443` with `8443` added to the nft drop set (recorded as a CTO-visible deviation in `decision-challenges.md`).
6. Measure, with the real binaries, every third-party behaviour the design leans on and keep the captured output as the test fixture (a fixture written from the author's model agrees with the model by construction): (a) nft named-counter syntax and that `nft list chain` stays free of counter values - already measured 2026-10-18 on nftables v1.1.7 in an unshare network namespace (`nft -c -f` OK, chain listing carries `counter name "legacy_8288"` with no packet counts, `nft list counter` returns `packets 0 bytes 0`); re-run on the Ubuntu 24.04 container that ships nftables v1.0.9; (b) stunnel4 config semantics (`accept`/`connect`/`cert`/`key`/`sslVersionMin`, foreground mode, journald output, the `stunnel4` user and group the package creates, which the key file mode depends on - cite the package, not memory) in an `ubuntu:24.04` container with a loopback listener; (c) `curl --cacert` exit 60 against a cert the CA does not sign, and against a cert whose SAN lacks the IP.
7. Name the periodic emitter: `inngest-boot-phone-home.sh` (written by cloud-init `write_files`, tag already in the Vector Source 4 allowlist) plus a small timer unit, and confirm its redaction pass (`inngest-redact.sh`) preserves a labelled `sha256=<64hex>` field for the served-cert fingerprint.
8. Coordination measurements (CTO F5, architecture and spec-flow review): (a) grep the diff of #10405 (`gh pr diff 10405`) for pinned nft chain literals, expected rule counts or hashes in its tests and in `inngest-cutover-flip.sh`; record the result in Research Insights (this PR's rules change the chain text, so a pinned literal there would break after a rebase); (b) run `inngest-userdata-budget.sh` on a trial merge of both branches and name the PR that yields bytes (the one that merges second); (c) measure what the app does when an event send fails during a scheduler outage (Inngest client retry behaviour, Sentry noise) and how long a replace plus bootstrap takes (post-mortems 2026-09-22 and the replace runs on file), and write the duration and event-loss/replay behaviour in the runbook so a low-traffic window and any status notice can be decided (CPO condition); (d) show the doppler stderr parse that separates "secret not found" from other read errors against the real CLI (CTO F1), or fall back to treating every non-zero read as an error.

### Phase 1: Terraform - cert, key, Doppler copies

- New `apps/web-platform/infra/inngest-tls.tf`: `tls_private_key.inngest_link`, `tls_self_signed_cert.inngest_link` (ECDSA P256, `validity_period_hours = 87600`, `ip_addresses = [local.inngest_private_ip]`, no DNS names, `allowed_uses` digital_signature/key_encipherment/server_auth, subject CN `soleur-inngest-link`), `lifecycle { prevent_destroy = true }` on key and cert, `doppler_secret.inngest_tls_key` and `doppler_secret.inngest_tls_cert` in `soleur-inngest`/`prd` (masked), `doppler_secret.inngest_tls_ca` named `INNGEST_TLS_CA` in `soleur`/`prd` (masked). No `early_renewal_hours` (it would plan a replace that `prevent_destroy` blocks, failing every later merge apply once inside the window; the 90-day alert is the warning). Not count-gated: unreferenced until used; ADR-118's gating existed because the proxy server logged a silent fallback on mere presence, which no process here does.
- Add the three addresses plus the key and cert resources to the merge `-target` list in `.github/workflows/apply-web-platform-infra.yml` (key and cert together, as ADR-118 notes). Confirm the `inngest_host_replace` job's plan-shape check (`tests/scripts/lib/inngest-host-replace-gate.sh`) tolerates the new resources (they are outside that job's scope).
- Boot isolation: add `INNGEST_TLS_KEY`/`INNGEST_TLS_CERT` to the allowed-name regex and keep the floor at 5 (`doppler-injection-bound.test.sh`, and the matching check in the template). PR #10405 also edits that test file (two hunks): rebase after it merges.
- Rotation of this cert is out of scope (10 y, alert at 90 days); documented in the runbook.

### Phase 2: Inngest host (cloud-init-inngest.yml)

- `packages:` add `stunnel4`.
- `write_files`: `/etc/stunnel/soleur-inngest.conf` (foreground, `accept = 10.0.1.40:8443`, `connect = 127.0.0.1:8288`, `cert`/`key` from the tmpfs `RuntimeDirectory`, `sslVersionMin = TLSv1.2`, output to journald); `soleur-inngest-tls.service` (D1 hardening, its own `SyslogIdentifier`, `Restart=on-failure`, a `RestartSec` backoff and `StartLimitIntervalSec=0` so a Doppler outage at boot cannot leave it permanently failed; the distro-packaged `stunnel4.service` is masked so it cannot double-bind `:8443`); the `ExecStartPre=+` fetch (explicitly fail-closed with `|| { emit; exit 1; }`, never relying on errexit); `soleur-inngest-tls-health.service` + `.timer` (5 min) calling `inngest-boot-phone-home.sh tls-health "listener=<0|1> cert_sha256=<64hex> notafter_days=<n> legacy_8288_packets=<n> tls_8443_packets=<n> nft8443_sha256=<64hex> nft_rules=<n> boot_id=<id>"` (the periodic series that ships regardless of priority) and, only on a refusal condition (`listener=0` or `notafter_days < 90`; the counter predicate lives in the soak script, which owns the flip timestamp - the host has no flip marker), `logger -p user.crit -t inngest-tls-health "SOLEUR_INNGEST_TLS_REFUSED reason=<token> ..."` (never reuse a tag listed in the `vector.toml` exclude arrays; no secret or key material in either line).
- nft script (the `inngest-nftables.sh` block only): declare `counter legacy_8288 { }` and `counter tls_8443 { }` in `table inet soleur_inngest`; add `tcp dport 8288 ip saddr { ${web_host_private_ips} } counter name "legacy_8288"` BEFORE the existing accept (verdict-less, falls through) and `tcp dport 8443 ip saddr { ${web_host_private_ips} } counter name "tls_8443"` BEFORE the 8443 accept (the positive control: a flat legacy counter proves nothing at zero traffic); add `tcp dport 8443 ip saddr { ${web_host_private_ips} } accept` and `tcp dport 8443 drop`; keep the existing `8288/8289` accept and drop lines byte-identical. Values interpolated into `nft -f` stay the Terraform constant `web_host_private_ips` (no user input).
- `runcmd`: enable and start the TLS unit and the health timer after the nftables unit, each failing loudly to the boot phone-home (a malformed unit surfaces at provision, not at the next reboot).
- Do NOT edit the `net-health` emit region or `inngest-cutover-flip.sh` (owned by #10405).
- Update the tests that pin this file: `inngest-host.test.sh` (new rules, accept line unchanged), `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-provision-unit.test.sh` (no other `write_files` entry pulls or logs in), `inngest-redis-luks.test.sh` (top-level key set must still be exactly `package_update packages groups users write_files runcmd`), `plugins/soleur/test/cloud-init-user-data-size.test.ts`; register any new `.test.sh` in `.github/workflows/infra-validation.yml`.

### Phase 3: Web side (inert)

- `ci-deploy.sh`: one resolver function `resolve_inngest_link` run before both `docker run` sites (CTO F1/F6 rulings 2026-10-18). Inputs from Doppler `soleur/prd` through the existing observed-read helper (`_doppler_get_observed`; `CRED_RC` and `_cred_err_tail` near the helper): `INNGEST_LINK_TLS` and `INNGEST_TLS_CA`. Flag semantics: a clean not-found = `http://10.0.1.40:8288` (the only http path); `pending:<epoch>` = https for 30 minutes from the epoch, then http plus an event (a lapsed lease is a deliberate rollback, not a downgrade); `1` = fail-closed. With the flag on, ANY of {self-gate fails, flag read errors, CA empty/invalid} makes the deploy exit non-zero and the old container keeps serving - no downgrade. The not-found-versus-error split needs a parse of doppler's stderr that is NOT yet verified; Phase 0 must show the parse against the real CLI, otherwise every non-zero read is treated as an error (ci-deploy already hard-depends on Doppler). Outputs: `/etc/soleur/inngest-ca.pem` (atomic write, 0644, always exists), `/etc/soleur/inngest-link.env` (`INNGEST_LINK_URL`, `INNGEST_LINK_SCHEME`, `INNGEST_LINK_CACERT`). The host-side `curl --cacert https://10.0.1.40:8443/health` self-gate runs in the host OUTPUT chain: it does NOT prove container egress or Node trust (the canary does). Both docker run sites use `-e INNGEST_BASE_URL="$INNGEST_BASE_URL_RESOLVED"`, `-v /etc/soleur/inngest-ca.pem:/etc/soleur/inngest-ca.pem:ro`, `-e NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem`. While the flag is on a broken gate also blocks ordinary releases (accepted by the CTO; the runbook says so). Shell inside `cloud-init` templates uses `$${...}`; this function lives in `ci-deploy.sh`, not the template.
- `cloud-init.yml` first-boot site: add the `-v`/`-e NODE_EXTRA_CA_CERTS` for a fresh host with a placeholder file created by cloud-init; `INNGEST_BASE_URL` stays http there (the first deploy after birth re-resolves).
- `lib/docker-run-tuple.py`: `INNGEST_BASE_URL` set becomes the resolver expansion (plus its literal for the first-boot tuple); add `NODE_EXTRA_CA_CERTS` to `_COMMON_ENV` and the first-boot env; add the CA `-v` string to `_VOLS`; pin that `NODE_TLS_REJECT_UNAUTHORIZED` is absent from every tuple (a `0` there would silently defeat verification); extend `docker-run-tuple.test.sh` mutation rows (K07*/K10*). The gate's digest (`e959fc801d99`) covers AppArmor, seccomp and tmpfs only, so the env/volume additions are anchored by the exact-set checks, the K07/K10 rows and the canary negative control, not by the posture literal (no edit to `docker-run-tuple-posture.test.ts`).
- `cron-egress-nftables.sh`: add `ip daddr 10.0.1.40 tcp dport 8443 accept` with a `soleur-egress` comment next to the 8288 rule; `cron-egress-postapply-assert.sh` asserts both; `cron-egress-firewall.test.sh` pins both. Delivered by the existing `deploy_pipeline_fix`/`cron_egress_firewall` provisioners (web-1 and web-2 twins already exist: see Host fan-out).
- Probes: `inngest-registry-probe.sh`, `inngest-doublefire-probe.sh`, `inngest-consumer-probe.sh` prefer `/etc/soleur/inngest-link.env` over any inherited URL (URL, `--cacert`) when present, default http. No `server.tf` or `web-probe-envwrite.sh` edit: the env file is the only seam, so the web-host provisioners are not re-triggered for it. Their `.test.sh` suites are updated (URL literals in `inngest-registry-probe.test.sh` and `inngest-doublefire-probe.test.sh`).
- Delivery census (plan-time answer to "which workflow delivers each web-host file to BOTH hosts"): bounded to the files that actually change - for each changed web-host file (`ci-deploy.sh`, `hooks.json.tmpl`, `cron-egress-nftables.sh`, `cron-egress-postapply-assert.sh`, the three probes, the new handshake probe, `web-probe-envwrite.sh`, `server.tf`), name the workflow whose `paths:` filter fires on it (`apply-deploy-pipeline-fix.yml` lists `ci-deploy.sh`, `hooks.json.tmpl`, `infra-config-apply.sh` and several inngest scripts; `apply-web-platform-infra.yml` fires on `*.tf`; check the rest with `git grep`) and the provisioner that delivers it to web-1 and web-2 (`triggers_replace` hashes in `server.tf`); add any missing `paths:` entry and `triggers_replace` input, with a test. A file nothing fires on would sit on disk in the repo while production keeps the old bytes.
- Handshake evidence without a new delivery path: `inngest-registry-probe.sh` (already webhook-delivered at `/hooks/inngest-registry-probe`, and run by `cutover-inngest.yml` op=registry-probe) gains a `--tls-handshake` mode asserting (a) `curl --cacert` returns 200 on `/health` and (b) the same request WITHOUT the CA fails with a certificate-verification error (curl exit 60). Check (c), cert fingerprint equality, is dropped: a successful verify against the pinned CA already proves it, and the host `cert_sha256` emit is compared with the Terraform cert at A1. A separate new probe script would need `infra-config-install.sh` DEST_SPEC, `push-infra-config.sh`, `infra-config-apply.sh` FILE_MAP, `server.tf` chown/chmod/sha lines, the `apply-deploy-pipeline-fix.yml` `paths:` list and `ship-deploy-pipeline-fix-gate.test.ts` edits for no extra property.
- `apps/web-platform/test/server/inngest/cron-inngest-cron-watchdog.test.ts`: parity test relaxed to set membership over the two resolver values; `INNGEST_HOST_FALLBACK` stays `http://10.0.1.40:8288`.
- Canary layer (`canary-probe-set.md`) - the container-level proof, whenever the flag is on: (1) `docker inspect` shows the canary's `INNGEST_BASE_URL` is https; (2) one in-container `fetch` of the URL the container was actually handed (`/health` and `/v1/events?limit=1` with the Bearer) succeeds; (3) a negative control with the CA withheld (`env -u NODE_EXTRA_CA_CERTS` in the same container) fails with a verification error; (4) registry non-empty over https. Counter reads happen only after the prod swap on BOTH hosts completes (the old prod container still dials `:8288` until then).
- Flip actuator (CTO F6): a new `.github/workflows/inngest-link-flip.yml` (dispatch only). It writes `INNGEST_LINK_TLS=pending:<epoch>`, dispatches the canary-then-prod release, verifies the canary layer and both prod swaps, then promotes the flag to `1`; an `if: failure() || cancelled()` step unsets the flag, so a dead session cannot leave a half-flipped fleet, and the 30-minute lease in the resolver covers a dead workflow. Rollback is the same workflow with `action=off` (or unsetting the flag) plus a redeploy. **Open item for deepen-plan (credential tier):** which credential lets this workflow write the one flag key. Doppler tokens are config-scoped, so a token that can write `soleur/prd` can write every `prd` secret; check `inngest-arm-write-token.tf` (the `op=arm` precedent scoped to the Inngest project), ADR-241 tiers and the `infra-privileged` environment, and prefer a dedicated config or a narrowly scoped token over a broad one. If no sanctioned narrow route exists, say so and escalate to the CTO rather than widening a token silently.

### Phase 4: Observability, follow-through, docs

- Paging (CTO E2 ruling 2026-10-18): add NO new Better Stack Logs alert (15 exist, free-tier cap unmeasured, ADR-218); opt in to the existing `monitor_send_failed` alert, whose SQL already matches `PRIORITY = '2'` plus the `_REFUSED` needle, so there is no SQL change and no `probe_rev` bump (steps 4-7 of the file's "add another alert" list do not apply). Two emitters, deliberately separate: (1) the periodic `tls-health` series (soak, cert days-left, legacy counter) goes through `inngest-boot-phone-home.sh` (direct POST to source 2457081, marker `SOLEUR_INNGEST_BOOT_STAGE`, stage `tls-health`) because an unlisted tag at notice priority would never ship; (2) the refusal marker is emitted by the tls-health unit itself with `logger -p user.crit -t inngest-tls-health "SOLEUR_INNGEST_TLS_REFUSED ..."` when `listener=0`, `notafter_days < 90`, or `legacy_8288_packets` rises after the flip marker. The tag `inngest-tls-health` is in neither allowlist/exclude array of `vector.toml`, so it ships through Source 2 (PRIORITY 0-2, any unit except `inngest-server`) with no vector change (`vector.toml` reaches the host only through the baked image). Owed: one guard row in the `monitor_send_failed` drift guard, one decode row in `betterstack-log-query.md`, and a synthetic proof (`synthetic=1` row queried through `scripts/betterstack-query.sh`) before relying on the route. Dead-emitter detection is the soak gap predicate plus a monthly follow-through re-check of cert days-left; after the flip the web-side probes dial https `:8443`, so a down listener already trips the existing probe alarms.
- `scripts/followthroughs/inngest-tls-soak-10136.sh` (+ test): queries Better Stack for the `tls-health` series since the flip timestamp; exit 0 only when the series is gap-free (expected rows per hour with jitter allowance), a single `boot_id` since the flip, and `legacy_8288_packets` delta 0. The tracker directive `<!-- soleur:followthrough script=scripts/followthroughs/inngest-tls-soak-10136.sh earliest=<flip+2d> secrets=... -->` is set on a new tracker issue at flip time; sweeper `secrets=` additions go in `.github/workflows/scheduled-followthrough-sweeper.yml` (see `followthrough-convention.md`).
- Runbook: new section in `knowledge-base/engineering/operations/runbooks/inngest-server.md` ("Link TLS (#10136)": flag, rollback, replace order, cert expiry, reading `tls-health` without SSH). No SSH in any step.
- ADR-292 (provisional ordinal; re-verify against `origin/main` at ship per the ADR-ordinal gate) and an ADR-100 addendum pointer; C4 edit (Architecture Decision section). Sweep for `ADR-<n>` renumbering across plan, tasks and specs if the ordinal moves.

## Production Actions (post-merge) and Gates

These run AFTER this PR merges and deploys. They are deliberately NOT recorded under an `## Operator Holds` heading: `soleur:ship` evaluates every hold at the draft exit and again before arming, so a hold whose condition is "this PR is merged" would block the PR's own arming. The preconditions below use the hold grammar's vocabulary (`pr-merged N`, `no-inflight-run <workflow>`) so the executing session can run the same probe. No `Delegation:` record exists on #10205, so every act below proceeds on the owner's recorded go quoted here (an explicit statement, not a menu acknowledgement), one act at a time, with the evidence column checked before the next. A failed replace waits for a FRESH owner go before any re-dispatch (standing rule; the owner reserves this decision).

Owner go (quoted, recorded 2026-10-18 on #10136): "go on the Inngest TLS PR and go for the host replace and INNGEST SIGNING KEY Rotation".

Placement and bookkeeping (CTO E1 ruling 2026-10-18): post-merge acts are not holds; the Production Envelope for these acts lives in a committed runbook that survives the Phase 6.45 archive (the new "Link TLS (#10136)" section of `inngest-server.md`), not in this plan; one follow-through issue is enrolled per act (A1, A3, A5) with predicates the sweeper checks; no delegation is needed to build or merge the PR, and the calling skill asks the epic-start question at ship time with a Scope naming exactly the host-replace dispatch, the flag-write-plus-release dispatch and the rotation (only delegable command classes). The recorded owner go names the replace and the rotation; it does NOT name the flag write, which is a separate production act (A3) needing its own dated go.

| # | Act | Owner go / due | Preconditions (evaluate, never assume) | Mechanism (no SSH) | Success evidence | Rollback |
|---|---|---|---|---|---|---|
| A0 | Merge this PR (inert) | normal merge queue after review and green CI | review done; `gh run list` shows no in-flight `apply-web-platform-infra.yml`/`registry-host-replace-dispatch.yml`; rebased on `origin/main` (never merge main); compound run | single bare `gh pr merge 10501 --squash --auto`, then no sync pushes | `deploy-arm.sh find --wait <full-sha>` then `served <full-sha>` from a detached `origin/main` worktree; merge apply created the 3 secrets (names only, never values); egress assert green on web-1 and web-2; CA file on both web hosts equals the Doppler copy (sha256 compare via a deploy-state hook; re-check after the first post-merge release, since the merge apply can race the first deploy and leave the empty placeholder) | revert the PR; nothing referenced the new resources |
| A1 | Inngest host replace (one disruption, bundled with #10405 unless it slips) | "go for the host replace", due **2026-11-05** | `pr-merged 10501`; `pr-merged 10405` OR the internal checkpoint 2026-10-28 has passed without #10405 being mergeable (then the replace proceeds without it and the measured evidence comes from this PR's own `nft8443_sha256` and rule-count fields; whichever PR merges second rebases); both web hosts report the CA fingerprint and the 8443 egress rule; `no-inflight-run apply-web-platform-infra.yml`; `inngest-userdata-budget.sh` green with >= 300 B margin on the trial merge of both branches (the PR that merges second yields bytes); runbook `inngest-server.md` "Replace triggers" and the registry runbook's double-replace rule re-read; stock preflight and destroy-guard pass; replace duration and send-failure behaviour during the window measured in Phase 0 and written in the runbook; a low-traffic window chosen | `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace ...` with the runbook's confirm and id-pin inputs; the replace must carry the network, volume and firewall attachments (post-mortem 8754) | boot event shows the private NIC up; `tls-health` rows arrive with `listener=1`, `cert_sha256` equal to the Terraform cert, `nft8443_sha256` and rule count showing the 8443 accept, drop and both named counters; `--tls-handshake` mode green from BOTH web hosts | nothing points at 8443 yet, so the web side needs no rollback; a failed replace (the apply run concludes non-success, or `tls-health` is absent 30 minutes after the apply): read the apply run's recovery-read block, WAIT for a fresh owner go, then re-dispatch once |
| A2 | Handshake verification pre-flip | part of the A1 go | A1 evidence | web-host hook `/hooks/inngest-registry-probe` in `--tls-handshake` mode | (a) verified 200, (b) failure without the CA (exit 60) | n/a (read-only) |
| A3 | Flip through the `inngest-link-flip.yml` workflow (lease, canary, prod, promote) | the recorded go names the PR build and "URL flip behind a canary" as build scope only; the flag WRITE needs its own dated owner go naming it (asked via the epic-start question at ship time or an action-required issue) | A1 and A2 green; `no-inflight-run` for the release workflow; flip date noted in the tracker; flip actuator credential resolved (open item above) | `gh workflow run inngest-link-flip.yml` | canary layer passes (all four checks); both prod hosts swapped and healthy; `ci-deploy` resolver log shows `https` on both; T = last prod swap complete plus old-container drain, with a counter baseline sample taken after the drain | the workflow's failure/cancel step unsets the flag; manual rollback is the same workflow `action=off` plus redeploy; `:8288` is still serving, so the host needs nothing |
| A4 | 48 h soak | n/a | A3 timestamp T and baseline row | follow-through sweeper runs `inngest-tls-soak-10136.sh` | gap-free `tls-health` series since T, one `boot_id`, `legacy_8288` packet delta 0 AND `tls_8443` delta >= 90% of the expected probe cadence, for 48 h; a reboot restarts the clock (re-anchor by a new tracker comment) | any non-zero legacy delta: run the flip workflow with `action=off`, find which caller still dials 8288 |
| A5 | `INNGEST_SIGNING_KEY` rotation (#10382 row 1) | "INNGEST SIGNING KEY Rotation", recorded on #10382 | A4 passed (the new key never rides plaintext); the separate rotation follow-up (CTO F3: a minimal `apply_target`, not built in this PR) has landed; runbook `inngest-server.md` "Key rotation" re-read; both copies identified (host: `random_id.inngest_signing_key_dedicated` in `soleur-inngest/prd`; app: `soleur/prd INNGEST_SIGNING_KEY`, `ignore_changes=[value]`, copied out-of-band per `inngest.tf`) | set both values, then restart `inngest-server` (`restart-inngest-server.yml`) and redeploy web (`web-platform-release.yml`) back to back; no host replace is forced (keys are read from Doppler at start; the `ignore_changes` state of the dedicated secret is to be verified); during the mismatch window step calls fail signature verification and Inngest retries them | old-key rejection check (status code only; the old value retained until it passes), new key accepted, `.services.inngest_server` active with stable `NRestarts` | the runbook's rollback; note that after A5 a flag-off rollback puts the NEW key back on `:8288`, so a post-A5 rollback requires a re-rotation and the legacy listener closure (deferral issue) gets a date |
| A6 | "No known access" record | CLO condition | A5 complete; measured re-read from the deployed #10405 emit; Hetzner member list enumerated read-only (`hcloud network describe <net> -o json`, servers field) | file `knowledge-base/legal/audits/<date>-inngest-signing-key-rotation-no-known-access.md`, linked from #10382 and #10136; owner states the facts starting "SIGNED BY OWNER (human, not an agent)", CLO agent adds a separate attestation line; contents per the CLO ruling (rotation timestamp UTC, secret name and version entry, every config/host that got the key, old-key rejection status code, exposure window from before PR #10371 through the rotation, what was searched, the explicit "no evidence found, not none occurred" limit, whether `INNGEST_EVENT_KEY` was also rotated); dated after A5, the deployed re-read and the enumeration | the record exists and is linked | n/a |
| A7 | Leg-2 accepted-risk record (poll) | owner item, class `operator (legal-risk)` | CLO conditions (Legs table) | owner-typed record on #10136 beginning "SIGNED BY OWNER (human, not an agent)"; an agent-posted record does not satisfy it | record exists before the poll row is relied on | n/a |

`INNGEST_EVENT_KEY` rotation is NOT covered by the recorded go. The A6 record states whether it was rotated; if not, it covers the signing key only. Extending the go to the event key is an owner decision (`operator (production-mutating)` row in `decision-challenges.md`).

## Post-merge probe plan (evidence for the issue; the owner is never asked to watch CI or paste logs)

1. Handshake with verification on: `inngest-registry-probe.sh --tls-handshake` from each web host: verified 200; unverified request fails with a certificate-verification error (the host `cert_sha256` emit is compared with the Terraform cert at A1). Output is a structured line the agent reads from the hook.
2. Canary proof (A3): `docker inspect` shows an https `INNGEST_BASE_URL`; one in-container `fetch` of the handed URL and a `/v1/events?limit=1` Bearer read succeed; the CA-withheld negative control fails; registry non-empty over TLS.
3. Counters: a baseline sample taken after the last prod swap plus old-container drain (T), then +15 min, +1 h, +24 h, +48 h from `tls-health` rows (Better Stack query, `bash scripts/betterstack-query.sh --since <window> --grep tls-health`); the `legacy_8288` delta must be zero and the `tls_8443` delta at least 90% of the expected probe cadence (positive control); any non-zero legacy delta names the caller by correlating with the `ci-deploy` resolver log.
4. Cert health: the `notafter_days` row value (expect ~3650) and the 90-day alert wired.
5. Measured nftables re-read (CLO condition, shared with #10405): the full chain with the `8443` accept, drop, and `legacy_8288` rule, plus `nft_sha256`.
6. Hetzner member list (read-only), dated, attached to the A6 record.

## Infrastructure (IaC)

### Terraform changes

- New `apps/web-platform/infra/inngest-tls.tf` (existing root; R2 backend already present). Providers: `hashicorp/tls` (already used by `proxy-tls.tf`, same pin) and the existing `doppler` provider. Sensitive: none new as variables (the key is generated, never an input). `doppler_secret` resources are masked; the private key lands in `terraform.tfstate` on the encrypted R2 backend (ledger store `r2.terraform_state_backend`).
- `apply-web-platform-infra.yml`: add the new addresses to the merge `-target` list.
- `inngest-host.tf`: no change expected (the stunnel conf is static; `inngest_private_ip` is already a local). If the template needs a new templatefile variable, add it and update the `inngest-userdata-budget.sh` stubs (exact-length bound).

### Apply path

(b) `terraform apply -replace` of the Inngest host through the dedicated `inngest-host-replace` dispatch (the host has no `ignore_changes=[user_data]`, so the cloud-init edit force-replaces it only through that dispatch; the merge apply carries no `hcloud_server`). Expected disruption: the single scheduler host is unavailable for the replace window (replace plus bootstrap, Redis AOF volume reattached). Bundled with #10405 so there is one disruption, not two.

### Host fan-out

The only SSH `terraform_data` provisioners touched are the existing cron-egress ones (`deploy_pipeline_fix`, `deploy_pipeline_fix_web2`, `cron_egress_firewall`, and `inngest_consumer_probe_install` for the probe env): web-1 and web-2 twins already exist and the parity test (`web-host-provisioner-parity.test.sh`) already classifies them; no new provisioner is added. Classification: `twin` for the egress rule and probe env (both hosts get it hot); `birth-covered` is NOT claimed for the CA file because `ci-deploy.sh` writes it on every deploy to both hosts.

### Distinctness / drift safeguards

`dev != prd`: the new secrets are created in `prd` configs only; dev has no Inngest host. `lifecycle.prevent_destroy` on key and cert (a re-mint would invalidate the CA on every web host until redeploy); the three copies derive from one cert resource so drift cannot occur, and the handshake probe's fingerprint-equality check detects a stale CA file. Roster-change warning (ADR-118): the SAN is the single private IP `10.0.1.40`; changing `inngest_private_ip` forces a re-mint.

### Vendor-tier reality check

Better Stack Logs alerts: 15 already exist and the free-tier cap is unmeasured (ADR-218), so this plan adds NO new alert resource and opts in to the existing `monitor_send_failed` alert by needle (Phase 4). Doppler secret count is well under plan limits.

## Observability

```yaml
liveness_signal:
  what: Better Stack Logs row from the Inngest host, stage tls-health (listener, served-cert sha256, notafter_days, legacy_8288 packets/bytes, boot_id)
  cadence: every 5 minutes
  alert_target: the existing monitor_send_failed Better Stack alert (needle opt-in, PRIORITY-2 SOLEUR_INNGEST_TLS_REFUSED via logger -p user.crit -t inngest-tls-health) plus the follow-through sweeper trackers
  configured_in: apps/web-platform/infra/cloud-init-inngest.yml (timer) (timer and emitter); the existing monitor_send_failed alert in apps/web-platform/infra/betterstack-logs-alerts.tf already matches the marker (no change)
error_reporting:
  destination: Better Stack Logs source 2457081 - periodic tls-health series via inngest-boot-phone-home.sh (direct POST); refusal marker via logger -p user.crit (Vector Source 2); web-side resolver fallback via logger -t ci-deploy (Vector Source 4)
  fail_loud: SOLEUR_INNGEST_TLS_REFUSED crit row on listener=0 / cert under 90 days / legacy counter rising after the flip, resolver event "INNGEST_LINK fallback to http" while the flag is on, canary layer failure fails the deploy
failure_modes:
  - mode: stunnel unit down or key/cert fetch failed on the Inngest host
    detection: tls-health listener=0 or row absent > 15 min
    alert_route: Better Stack alert policy
  - mode: cert nearing expiry (10 y cert, no rotation cron)
    detection: notafter_days < 90 in tls-health
    alert_route: Better Stack alert policy
  - mode: a web caller still uses plaintext 8288 after the flip
    detection: legacy_8288 packets increasing after the flip marker; the soak script exits non-zero
    alert_route: follow-through sweeper tracker plus Better Stack alert
  - mode: web CA file stale or empty while the flag is on
    detection: resolver self-gate fails (fallback event) and the handshake probe fingerprint mismatch
    alert_route: ci-deploy journald row to Better Stack; the deploy fails when the flag is on and the fetch fails
  - mode: legacy counter silently absent (emitter dead)
    detection: a gap in the tls-health series fails the soak predicate
    alert_route: no page by ruling (CTO E2): the soak gap predicate and the monthly cert days-left follow-through; after the flip the web-side probes dial https :8443, so a down listener already trips the existing probe alarms
logs:
  where: Better Stack Logs (Inngest host source) and journald on the host; web side journald tag ci-deploy
  retention: Better Stack Logs source retention (existing)
discoverability_test:
  command: bash scripts/betterstack-query.sh --since 15m --grep tls-health --limit 1
  expected_output: tls-health
  credentials_required: Doppler soleur/prd_terraform read of the Better Stack query token - there is no unauthenticated substitute for reading the Logs warehouse
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
    does_not_defend: a leaked Doppler service token (the Inngest host holds one for soleur-inngest) or a compromised host with a live token; whoever reads the key can impersonate the terminator to any client that trusts the CA; a state-file reader (the key is also in Terraform state on the encrypted R2 backend)
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:Doppler attestation formalization pending, tracked #6911
in_transit:
  - connection: web-platform app (web hosts) -> dedicated inngest host 10.0.1.40:8443 (stunnel to 127.0.0.1:8288), AFTER the flag flip
    enforced_at: apps/web-platform/infra/ci-deploy.sh resolve_inngest_link and the three docker run sites (INNGEST_BASE_URL + NODE_EXTRA_CA_CERTS); apps/web-platform/infra/cloud-init-inngest.yml soleur-inngest-tls.service
    tls: TLS 1.2 or higher (stunnel sslVersionMin)
    cert_verification: on (Node verifies against the pinned CA via NODE_EXTRA_CA_CERTS; curl probes use --cacert; a client without the CA fails - asserted by the canary and the handshake probe)
    does_not_defend: a reader of Terraform state or Doppler prd who holds the key plus a private-network position; the loopback hop stunnel to inngest (127.0.0.1:8288) is plaintext inside the host; while the legacy :8288 listener stays open a mis-pointed client still sends plaintext (the legacy_8288 counter detects it)
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

New **ADR-292** (provisional ordinal; `soleur:ship` re-verifies the next free number against `origin/main` and after every sync): "Inngest link TLS via a host-local stunnel terminator, a Terraform-minted pinned cert in Doppler, and a Doppler-flagged data-driven flip". Status `adopting` (true after the flip and soak). Decision: terminator unit independent of `inngest-server`; single cert resource with three Doppler copies; CA as host file mounted into containers; resolver as the single chokepoint for the scheme; legacy `:8288` kept and counted for the soak, closed physically at the next unrelated replace. Alternatives considered: native TLS (does not exist at v1.45.1), baked CA in the image, committed cert, second-PR flip, `--host 127.0.0.1` now, nginx/socat/caddy terminators. Amend **ADR-100** with an Addendum pointing at ADR-292 (it records the ":8288 control-API scoped by nftables" substrate this changes). Cross-reference ADR-140 and ADR-118.

### C4 views

Read all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Enumerated against the feature: (a) external human actors: none new; (b) external systems: none new (stunnel is a host-level systemd unit of the same deployment node as the `inngest` container, not a process inside it; Cloudflare, Doppler, Better Stack already modelled); (c) data stores: none new (the Doppler store is already modelled); (d) actor-to-surface access changes: none. Changes: the edge `api -> inngest "Sends events" { technology "HTTP private-net :8288" }` becomes `HTTP :8288 (legacy, retired after the soak) / HTTPS :8443 (stunnel terminator, pinned CA, flag-gated, ADOPTING #10136)`; keep two edges so the model never claims TLS before the flip: the existing plaintext edge marked legacy and a new HTTPS edge marked ADOPTING; the `inngest` container description gains one line on the host-level terminator. Run `plugins/soleur/test/c4-count-parity.test.sh` and the C4 syntax/render tests in `apps/web-platform/test/` after editing. The edit lands as "ADOPTING" wording so the model never claims TLS before the flip.

### Sequencing

ADR and C4 land in THIS PR with `adopting` wording; the status flips to `accepted` in the later ledger/legal PR on the handshake and soak evidence. Not a deferred issue.

## Guard Contract

### Guard 1 - Inngest link scheme chokepoint

**Property.** Every consumer of the Inngest link scheme (canary and prod docker run, the first-boot run, the three probes, the web egress rule, the watchdog parity test) accepts exactly the http-or-https pair produced by the single `resolve_inngest_link` resolver (http only on a clean not-found or a lapsed lease, otherwise https or a failed deploy), and a client that lacks the pinned CA cannot complete a handshake.

**Assembly.** Chokepoint: `resolve_inngest_link` in `ci-deploy.sh` (writes `INNGEST_BASE_URL_RESOLVED`, `/etc/soleur/inngest-link.env`, `/etc/soleur/inngest-ca.pem`). Members flowing through it: the canary `docker run` and the prod `docker run` (both in `ci-deploy.sh`), `inngest-registry-probe.sh`, `inngest-doublefire-probe.sh`, `inngest-consumer-probe.sh` (read the env file). Members that cannot call the resolver: the first-boot `docker run` in `cloud-init.yml` (literal http, re-resolved at the next deploy), `cron-egress-nftables.sh` (accepts both ports), `cron-inngest-cron-watchdog.test.ts` parity. More than one chokepoint exists on purpose; `docker-run-tuple.py` quantifies over `docker run` sites by file, so a fourth site is a member of the gate, and the gate covers all three run sites.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the canary site's `INNGEST_BASE_URL` with a literal `https://10.0.1.40:8443` (bypass the resolver) | tuple gate RED |
| 2 | Delete the `dport 8443` accept from `cron-egress-nftables.sh` | `cron-egress-firewall.test.sh` and the postapply assert RED |
| 3 | Add a fourth `docker run` site after the compliant three, carrying the old literal | tuple gate RED (unknown site); a gate that stops at the third site is itself the defect |
| 4 | Make the tuple gate find zero `docker run` sites (point it at an empty file) | RED, never "0 checked, exit 0" (the guard's own dispatch) |
| 5 | Remove the resolver's `curl --cacert` self-gate so a flag-on, CA-empty host keeps https | resolver unit test RED (must exit non-zero and keep the old container, never downgrade) |
| 6 | Drop `-v ...inngest-ca.pem:ro` from the prod site only | tuple gate RED |
| 7 | Probe scripts ignore `/etc/soleur/inngest-link.env` and keep the http default | probe suites RED once the flag fixture is set |
| 8 | Resolver emits a third value (for example `http://10.0.1.40:8443`) | resolver unit test and tuple expansion check RED |
| 9 | Flag previously on and the Doppler read errors (not a clean not-found) | resolver exits non-zero; mutation making it fall through to http goes RED |

**Harness rows:** (H1) edit the SUITE: stub `curl` in the resolver test to always succeed - the "CA withheld must fail" case must go RED, proving the test can see a vacuous self-gate; (H2) must-PASS non-canonical input: flag unset (default http) and flag on with a valid CA both PASS, and a flag-on case whose CA file differs in whitespace/trailing newline from the canonical fixture PASSes (a suite that only accepts the canonical bytes is vacuous in the other direction).

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

**CPO sign-off (`requires_cpo_signoff: true`):** SIGN-OFF WITH CONDITIONS (CPO agent, plan review 2026-10-18). Conditions folded into the plan: (1) replace duration and event-loss/replay behaviour measured and written in the runbook, a low-traffic window and a status-notice decision (Phase 0 item 8c, A1); (2) #10405 decision checkpoint 2026-10-28 with the replace-without-it fallback (Risks, A1); (3) follow-up issues filed before merge (Deferral Tracking); (4) an owner-go checklist for O1, O3, O4, O5 with dates on #10136 (ship-time `action-required` issue). `user-impact-reviewer` still runs at review time.

## Dependencies & Risks

- **user_data budget (top risk).** Real headroom 1,852 B against the Hetzner cap and 1,384 B against the repo test budget (`INNGEST_GZIP_BUDGET = 32_300`). CTO estimate for the terminator alone: 1.2-1.5 KB raw. Fallback ladder, in order: (1) terse comments (comments are stripped from the measured size, but keep rationale in `.tf`/runbook, not the template); (2) dedupe existing code bytes in the diagnostic blocks of the template (CTO-sanctioned); (3) fold the tls-health emitter into the stunnel unit's own `ExecStartPost` loop instead of a timer unit; (4) STOP and escalate to the CTO - never raise the cap or bypass the gate. A rejected user_data at replace time is a stranded host (2026-09-08 precedent): the gate must be green before A1.
- **#10405 coordination.** Draft in another session's worktree; read-only for us. Our hunks: nft script block, `packages`, new `write_files`, `runcmd` additions, `doppler-injection-bound.test.sh` allowed-names regex. Theirs: `net-health` emit, `inngest-cutover-flip.sh`, rehearsal workflow/tests. Rebase onto `origin/main` after it merges (never merge main). If both land, re-run the full `cloud-init-inngest-*` and `doppler-injection-bound` suites.
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
- [ ] The three probes honour `/etc/soleur/inngest-link.env`; `inngest-registry-probe.sh --tls-handshake` implements checks (a) and (b).
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

- unit: Given the flag is unset, when `resolve_inngest_link` runs, then `INNGEST_BASE_URL_RESOLVED=http://10.0.1.40:8288` and `/etc/soleur/inngest-ca.pem` exists (possibly empty).
- unit: Given the flag is on and `curl --cacert` succeeds, then the resolved URL is `https://10.0.1.40:8443` and the link env file says `scheme=https`.
- unit: Given the flag is on and the self-gate fails, then the URL is http and a `ci-deploy` event row is emitted.
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
- `apps/web-platform/infra/inngest-registry-probe.sh` (+ `.test.sh`; adds `--tls-handshake` mode), `inngest-doublefire-probe.sh` (+ `.test.sh`), `inngest-consumer-probe.sh` (+ `.test.sh`), `hooks.json.tmpl` (only if the registry-probe hook needs to pass the mode argument)
- `apps/web-platform/infra/doppler-injection-bound.test.sh`, `inngest-host.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-provision-unit.test.sh`
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` (one guard row for the new marker) and `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (one decode row); `betterstack-logs-alerts.tf` itself needs no change (SQL already matches)
- `.github/workflows/apply-web-platform-infra.yml` (merge `-target` list), `.github/workflows/infra-validation.yml` (register new tests), `.github/workflows/scheduled-followthrough-sweeper.yml` (secrets, if needed)
- `apps/web-platform/test/server/inngest/cron-inngest-cron-watchdog.test.ts` (parity relaxed to set membership)
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
