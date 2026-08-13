---
title: "CLO counsel review — registry zot container-log shipper, Art. 30 PA-8 amendment (#7440)"
type: clo-attestation
date: 2026-08-12
issue: 7440
pr: 7444
attestation-authority: clo
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
disposition: DISCHARGED
signed_off_at: 2026-08-12
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
disposition_history: "BLOCKED at first review (B1-B6) — 2026-08-12 -> B1-B6 VERIFIED FIXED at re-review (22f298dde) -> BLOCKED at re-review on B7, a table-breaking defect introduced by this authority's own §7 B2 draft -> B7 VERIFIED FIXED (649f983dd) and DISCHARGED 2026-08-12, verified against the RENDERED cell split rather than the raw line -> 2026-08-13 (#7455): DISCHARGE STANDS on a spent premise. The change no longer ships INERT — delivered 2026-08-12T20:54:12Z, live since 21:03:51Z. The three INERT-dependent passages are annotated at §11; none was load-bearing on the substantive holdings, which are re-confirmed. NOT re-opened."
attested_commits: "22f298dde (B1-B6), 649f983dd (B7)"
tier_classification: "Tier 3 (internal record-keeping) — Art. 30(1)(d)/(g) amendment to an existing Processing Activity. No new recipient, no new sub-processor, no new third-country transfer, no user-facing legal-document surface. `docs/legal/**` untouched, so none of the five mirror/SHA/heading gates are engaged."
semver: "N/A — no `docs/legal/**` document changed; TC_VERSION unaffected"
brand_survival_threshold: single-user incident
attested_commit_range: origin/main...HEAD (legal surface: 3 insertions / 3 deletions across 2 files)
written_against: the diff as landed and the implementation it describes, not the plan
re_evaluation_triggers:
  - "Any change admitting PUBLIC ingress to zot (an inbound rule on `hcloud_firewall.registry`, or a tunnel/proxy topology that puts a forwarded public address into a top-level zot log field). This is the trigger that converts `clientIP` from estate metadata into Art. 4(1) personal data on a path that carries no redaction. It is the single strongest external-counsel candidate on this Activity."
  - "Execution of the Better Stack s.r.o. Vendor DPA (currently PENDING). Four emitters now rely on an unexecuted Art. 28(3) instrument; execution retires that exposure and should be recorded in the same pass."
  - "First arms-length (non-Jikigai) principal holding `zot-pull` / `zot-push` credentials. The §(g) basis for declining a general free-text scrubber is that zot's identity model carries only service principals; a human-held credential re-opens that reasoning."
  - "Any zot version bump that changes the log schema — in particular one that stops self-masking `Authorization`, moves credentials outside the `headers` object, or adds a top-level identifier field."
  - "Any `clientIP` value observed on Better Stack source 2457081 from the `soleur-registry` plane that is not an RFC1918 address. Post-delivery (2026-08-12T20:54:12Z) this is the observable signature of the public-ingress trigger above having fired, on rows already in flight. The §(c) re-attestation of 2026-08-13 verifies the topology that bounds observable values; it does not audit shipped values."
---

# CLO counsel review — #7440 / PR #7444 (registry zot container-log shipper)

This audit is the load-bearing evidence for the `/ship` Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #7444. The gate fired because the diff touches `knowledge-base/legal/` and the plan declares `brand_survival_threshold: single-user incident`. No `[DRAFT — pending CLO/counsel review]` markers were present, so this is a pure attestation rather than a marker-clearing pass.

I am the reviewing authority for the Soleur-as-tenant-zero v1 posture. The operator is a non-lawyer founder and does not sign off here.

**Final disposition: DISCHARGED** at 649f983dd. This section records the first review, which was BLOCKED; §9 and §10 record the two re-reviews that closed it. The narrative below is preserved as written on first reading, because the reasoning is the record.

---

**Disposition at first review: BLOCKED.**

The safeguards this change describes are real, and I verified them against the code rather than against the prose. The redaction boundary is correctly designed, correctly implemented, and correctly tested. That is not what blocks this.

What blocks it is that the register's headline factual claim about *why this change matters* is false, and the falsity runs in the unsafe direction — it tells a reader the registry host had no direct path to Better Stack before this PR, when it has had two since #6122/#6244, and one of them ships zot log content through no redactor at all. A supervisory authority reading PA-8 §(d)/§(g) as amended would form a materially wrong picture of this host's egress posture, and would form it in the direction of believing more is covered than is.

Every blocker below is small and locally fixable. None requires redesigning anything that was built.

---

## 1. Per-artifact verdicts

| # | Artifact | Verdict | Basis |
|---|----------|---------|-------|
| 1 | `knowledge-base/legal/article-30-register.md` — PA-8 §(d) recipients (line 177), `[2026-08-12 UPDATE (#7440 / ADR-184)]` block | **DISCHARGED** (was BLOCKED) | **B1.** The block's headline — "the **FIRST** that reaches source 2457081 **WITHOUT** Vector" — is false. See §2. Everything else in the block is verified sound: no new recipient, no new sub-processor, no new third-country transfer, correct Art. 30(1)(d) characterisation, correct INERT statement. |
| 2 | `knowledge-base/legal/article-30-register.md` — PA-8 §(g) TOMs (line 180), `[2026-08-12 UPDATE (#7440 / ADR-184)]` block | **DISCHARGED** (was BLOCKED) | **B2** — the redaction assurance is written at host level ("Because `soleur-registry` runs no Vector agent, ... its own `redact()` is the whole boundary") and is false at host level. **B3** — "each with a mutation arm proving the assertion can fail" is not true of the file it cites. The substantive description of `redact()` itself is **verified correct in every particular**; see §3. |
| 3 | `knowledge-base/legal/article-30-register.md` — PA-8 §(c) categories of personal data (line 174) | **DISCHARGED** (was BLOCKED) | **B4.** The §(d) block states in terms that this edit "makes the phrase 'shipped by Vector' in this cell and in §(c) an incomplete description of this Activity" — and then leaves §(c) unamended. A register that names its own inaccuracy and does not repair it is worse than one that has not noticed. Compounded by the unrecorded `clientIP` category; see §4. |
| 4 | `knowledge-base/legal/article-30-register.md` — Vendor / Sub-Processor Mapping, Better Stack row (line 446) | **DISCHARGED** (was BLOCKED) | **B5.** Still reads "Vector-shipped journald + host_metrics; `userIdHash` pseudonymised at the VRL boundary". Not annotated. The same row already carries the exact annotation pattern this omission needs, added by #7100 for the PA-31 CLI-stderr path. The file's own precedent was available and not followed. |
| 5 | `knowledge-base/legal/compliance-posture.md` — Better Stack sub-processor row (line 96) | **DISCHARGED** (was BLOCKED) | **B6.** The edit created a contradiction inside a single table cell: the new parenthetical says the `pii_scrub_*` transforms "do not cover it", and two sentences later the cell still asserts, unqualified, "Pseudonymisation: `userIdHash` HMAC-SHA256 at the VRL boundary". Style observation at §6.1. |
| 6 | `apps/web-platform/infra/cloud-init-registry.yml` — `zot-log-shipper.sh` `redact()` | **VERIFIED SOUND** (not a legal artifact; reviewed as the referent of §(g)) | Allowlist, depth-coverage, fail-closed and residual-refusal all confirmed against the code and against a 150/150 suite run. See §3. |

**Overall disposition at first review: BLOCKED.** Six blockers, B1–B6. Recommended wording for all six was drafted at §7 and applied at 22f298dde; each is verified closed at §9.1. The verdict column above reflects the final position. A seventh blocker, B7, surfaced at re-review as a consequence of my own §7 draft and is recorded at §9.2; it was closed at 649f983dd.

---

## 2. B1 — the "FIRST without Vector" claim is false

The §(d) block opens:

> **[2026-08-12 UPDATE (#7440 / ADR-184): a FOURTH emitter, and the FIRST that reaches source 2457081 WITHOUT Vector.**

`soleur-registry` has been reaching Better Stack Logs source 2457081 without Vector since well before this PR. On `origin/main`, `apps/web-platform/infra/cloud-init-registry.yml` already contains two direct `curl` POSTs to `${betterstack_ingest_url}`, each with its own `Authorization: Bearer $TOKEN` and no Vector agent anywhere in the path:

- the `SOLEUR_ZOT_DISK` 5-minute cron reporter (#6122 / #6244), and
- the `SOLEUR_PRIVATE_NIC` guard reporter.

Both are unchanged by this PR. The claim is not merely imprecise; it is the load-bearing premise of the whole entry, and it is wrong.

The distinction that *is* real, and that the register should have recorded instead, is a payload-class distinction rather than a transport one. The pre-existing reporters emit a fixed-schema `key=value` line assembled by the template from values the template chose. The new shipper emits **whole zot journald rows** — variable content, shaped in part by whatever a client puts on the wire. That is the change that carries the data-protection significance, and stating it correctly costs one sentence.

This matters beyond pedantry because B1 and B2 compound. Told that Vector's absence is new, a reader infers that whatever redaction now exists at the emitter is the host's first and therefore complete emitter-side control. Neither half of that inference holds.

---

## 3. The redaction claim, checked against the code

This is the question the gate was convened to answer, so I answer it directly and in full.

**Is "redaction is owned by the emitter itself" true of `redact()`? Yes — every specific property §(g) asserts is true.** I verified each against `apps/web-platform/infra/cloud-init-registry.yml` (the `zot-log-shipper.sh` `write_files` block) and confirmed the behavioural contract by running `apps/web-platform/infra/zot-log-shipper.test.sh`: **150 passed, 0 failed.**

- **Name allowlist, not denylist — confirmed.** `HDR_KEEP` enumerates nine routing headers (`content-type`, `content-length`, `accept`, `accept-encoding`, `user-agent`, `host`, `connection`, `range`, `docker-distribution-api-version`). The jq `scrub` function redacts the value of every key in a `headers` object that is *not* in that list. A header nobody anticipated is redacted by construction. T6 pins this positively with `X-Future-Header`, and — importantly — the suite's earlier form of that assertion was the *inverse* (it asserted an unknown header **survived**) and was corrected under #7444 F-10. The assertion now points the right way.
- **Depth and case coverage — confirmed.** `walk(...)` reaches every object at any depth and the container key is compared `ascii_downcase`, so `{"request":{"headers":…}}`, `{"Headers":…}`, a top-level array, and a bare top-level `{"Authorization":…}` are all covered. Each of those five shapes leaked in an earlier draft and each now has a T6b fixture.
- **Fails closed — confirmed, and confirmed at the right seam.** The JSON/non-JSON branch is chosen by an explicit `jq -e 'type == "object" or type == "array"'` probe *before* redaction, not by whether the redaction pipeline happened to exit zero. That distinction is the difference between failing closed and failing open, and the code gets it right. A JSON row whose `headers` value is not an object raises `error("nonobj headers")`; `redact()` returns non-zero; the caller drops the row, accounts it under its own `reason=redact_failed`, and advances the cursor. It is not shipped.
- **Non-JSON backstop plus residual refusal — confirmed.** A `sed -E … gI` pass covers all five `CRED_HDRS` names across bare, quoted and bracketed renderings, and a following `grep -qiE` refuses to ship any row where a credential-bearing header name still carries a non-`REDACTED` value. `CRED_HDRS` is single-sourced between the two, so they cannot drift apart.
- **Applied to every shipped row — confirmed.** In the read loop, `redact()` sits ahead of `sanitize()` and `ship()` on the only path that emits row content. The other two things that reach `ship()` are drop-accounting rows and the boot marker, both assembled entirely from template-controlled scalars.

**Is there any path by which an `Authorization` / `Cookie` / `x-api-key` value reaches the POST through this shipper?** Routes to the wire are exhaustive and I walked all four:

1. JSON row with an object-valued `headers` at any depth → allowlist redacts it.
2. JSON row with a non-object `headers` → `error(…)` → dropped, accounted.
3. JSON row with no `headers` key and the credential embedded as free text inside some other string value → **not redacted, ships.**
4. Non-JSON row → `sed` backstop, then residual refusal → redacted or dropped.

Route 3 is a real residual, and §(g) **discloses it accurately**: "the boundary covers the header object and the `Authorization`-shaped renderings a plaintext line can take — it is not a general free-text PII scrubber". The stated basis for accepting it — that zot's identity model carries no email or `user_id`, its accounts being the `zot-pull`/`zot-push` service principals — is confirmed against the zot config (`"auth": {"htpasswd": …}`, deny-by-default `accessControl`). I accept that reasoning for this emitter.

Two smaller observations, neither blocking. `X-Forwarded-For` is not in `HDR_KEEP` and is therefore redacted — a genuine strength worth having on the record, because it is what stops a future proxy topology from leaking a forwarded public address through the *headers* path. And `user-agent`, `range` and `accept` are allowlisted and client-controlled, so a private-net client can place arbitrary text of its own choosing into a shipped row; that is its own data, on a deny-all-public host, and I do not consider it material.

**So the §(g) description of `redact()` is accurate. What is inaccurate is its scope.**

### B2 — the assurance is written at host level and is false at host level

> "Because `soleur-registry` runs no Vector agent, the shared `pii_scrub_*` VRL transforms are structurally unavailable to this emitter and **its own `redact()` is the whole boundary**."

The subject of that sentence is the host. Read at host level it is false, and the counter-example ships the same content to the same source.

The pre-existing `SOLEUR_ZOT_DISK` reporter carries a field `zot_last_err`, built from zot's own log output by a four-tier sample: `panic:`/`fatal error`/`[signal SIG`/`runtime error`, then `"level":"(error|fatal)"`, then a `cannot |failed to |unable to |…` sweep, and finally — when none of those match — `docker logs --tail 3 zot`. It is then passed through `tr '\n\r\t' ' ' | tr -cd '\40-\176' | tr -d '"\\' | head -c 300`.

That pipeline is the *payload-integrity sanitizer*. It is not a redactor, and the template's own comments are scrupulous elsewhere about not conflating the two. There is no `redact()` anywhere on this path — I grepped the first 500 lines of the file and the string does not appear.

The fallback tier is the one that matters. Under ordinary operation zot logs every request at `info`, so `docker logs --tail 3` is routinely three `HTTP API` rows carrying the full `headers` object. zot self-masks `Authorization` on the pinned image — but the template's own measurement note records that a **non-`Authorization` header is logged verbatim** (`"X-Custom":["plainvalue"]`), which is precisely why the new shipper was built around the header object rather than around one header's known masking. So a `Cookie` or `X-Api-Key` value can reach Better Stack through the sibling reporter, within its 300-character cap, having passed through nothing that was trying to stop it.

I want to be exact about what I am and am not saying. **This PR did not introduce that path**, the exposure is bounded (≤300 chars, sampled, and only when such a row lands in the selected tier), the host takes no public ingress, and the credential would be a private-net client's own registry credential. I am not blocking on the existence of the gap. I am blocking because **this PR is the one that writes into the Art. 30 register a host-level sentence asserting a boundary the host does not have**, and I will not attest a security-measures cell that overstates coverage in the direction of safety.

The fix is to scope the sentence to the emitter and disclose the sibling path as a known bounded residual. That is honest, it is short, and it costs the change nothing.

The underlying question — whether `zot_last_err` should route through `redact()` — is an engineering decision and is **referred to the CTO**, not resolved here. It should carry its own issue. My concern is discharged by accurate disclosure either way.

### B3 — the mutation-arm claim is not true of the file it cites

> "Enforced by behavioural tests asserting against the bytes leaving the process, each with a mutation arm proving the assertion can fail (`apps/web-platform/infra/zot-log-shipper.test.sh` §T6/§T6b)."

`zot-log-shipper.test.sh` contains no mutation harness. The word "mutation" appears three times in it, always in prose describing past defects. What the suite actually carries is a harness canary (proving `assert()` registers both verdicts), an assertion floor of 150 enforced from an `EXIT` trap, and per-block non-vacuity controls — for instance T6's "the row shipped (non-vacuity for the four assertions below)" and T6b's "a credential-free plaintext line still ships, content intact". Those are good controls. They are not mutation arms, and they prove a different thing: that the leak assertions are not vacuously satisfied by a dropped or empty row.

The mutation evidence does exist — an 11-mutant battery, all RED against a GREEN baseline — but it was run at development time and is recorded only in the PR's `session-state.md`. An auditor following the citation in the register will not find it.

What makes this more than a slip is where the wording came from. The sibling #6982 block in the same cell says "Enforced by behavioural tests (`apps/web-platform/infra/git-data-emit.test.sh`) that assert against the bytes leaving the process, each carrying a mutation arm proving the assertion can fail" — and **that claim is true**: `git-data-emit.test.sh` carries `mutate_del`, `mutate_sub` and `run_mutant` as resident harness functions, and even guards against a vacuous mutation arm. The #7440 block borrowed a sentence whose assurance was earned by a different file, and pointed it at a file that has not earned it. That is the drift class this authority is specifically charged with catching.

---

## 4. Categories of personal data, and `clientIP`

**Is the categories statement still accurate for this emitter? No — because there isn't one.** §(c) was not amended, and it contains no occurrence of `registry`, `zot`, `IP address`, `client IP` or `remote_addr`. The registry plane is absent from the cell that exists to describe what personal data goes where.

Worse, §(c) as it stands reads:

> "From PR #4279 onward, Vector reads journald … and ships journald + host_metrics to Better Stack Logs as a separate processor under §(d). The VRL `pii_scrub_drop_userdata` + `pii_scrub_structured` + `pii_scrub_string` transforms … provide defense-in-depth Art-9 user-content drop + `userId` → `userIdHash` rename + string-level scrub **before egress**."

A reader confined to §(c) — which is where a supervisory authority goes first — concludes that everything reaching Better Stack passes those transforms. The §(d) block predicts exactly this misreading, names it, and leaves it in place. **The register's pseudonymisation machinery (`SENTRY_USERID_PEPPER`, Recital 26) is a Sentry/Vector-plane property and confers nothing on the registry plane**, and the confirmation asked for is: yes, §(c)'s current wording can be read as claiming protection this path does not have, and it should be read that way, because nothing in the cell tells the reader otherwise.

**Is `clientIP` shipped? Yes, unredacted.** zot emits it as a top-level zerolog field — the measured fixture is `"clientIP":"10.0.1.30:39330"` — and `redact()` touches only `headers` objects and keys named `authorization`. It reaches the POST verbatim.

**Is it personal data? On the current topology, no.** `hcloud_firewall.registry` is declared with zero inbound rules, so the public interface is deny-all; ingress is intra-`10.0.1.0/24`, and the Cloudflare tunnel's origin is `tcp://10.0.1.30:5000`, which means even a tunnelled pull presents the connector's private address to zot rather than the initiator's public one. Every `clientIP` zot can observe is therefore an RFC1918 address belonging to a host in the controller's own estate. Under *Breyer* the analysis turns on whether the controller can combine the address with additional data to reach a natural person; here the only additional data is the estate's own IaC, and it resolves `10.0.1.30` to a server. It identifies a machine. It is not Art. 4(1) personal data.

**But that conclusion rests entirely on a firewall invariant that appears nowhere in the legal record**, and §(g)'s stated basis for declining a free-text scrubber reasons only about zot's identity model carrying no email or `user_id`. That is true and it is also beside the point for the one identifier class present in every single row. A future inbound rule, or a proxy configuration that lands a forwarded public address in a top-level field, silently converts `clientIP` into personal data on a path with no redaction and no disclosure. The register must state the category, state the conclusion, and state the condition the conclusion depends on. That is why it is a re-evaluation trigger in this audit's frontmatter, and why the §(c) fix at §7 carries it.

---

## 5. Art. 30(1) characterisation and Art. 33/34 — CONFIRMED

**The characterisation is right and I confirm it.** This is an Art. 30(1)(d)/(g) record-keeping discharge. Nothing here engages Art. 33 or Art. 34.

- **No personal data breach.** Art. 4(12) requires a breach of security leading to accidental or unlawful destruction, loss, alteration, or unauthorised disclosure of or access to personal data. Nothing was destroyed, lost, altered, or disclosed to an unauthorised party. Better Stack is an existing PA-8 recipient on this exact source, under processor terms, and the transfer is intra-EU (CZ controller → DE `eu-fsn-3`).
- **No new recipient, sub-processor, or third-country transfer** — verified. The host is in the existing Hetzner EU account under the same AVV; the source ID is unchanged.
- **The `#6982` precedent is correctly invoked.** That block recorded a third emitting host on the ground that "the SET of hosts that can emit personal-data-adjacent context grew, which is an Art. 30(1)(d) record-keeping fact even when the recipient list is unchanged". #7440 generalises "hosts" to "emitters", which is the more precise framing given that this host was already counted. Characterisation accurate.
- **The INERT statement is accurate** — verified against `apps/web-platform/infra/zot-registry.tf` and `apply-web-platform-infra.yml`: `hcloud_server.registry` is cloud-init-only per ADR-096 and the registry resources are `OPERATOR_APPLIED_EXCLUSION`s, so merging applies nothing and delivery rides a subsequent operator-authorized host replace. This is also what keeps B2's residual from crystallising on merge.
- **Lawful basis is adequate and unchanged.** PA-8 rests on Art. 6(1)(f) (legitimate interest in service security and integrity, balanced against confidentiality and mitigated by access scoping and short retention) and Art. 6(1)(c) (Art. 33 clock-anchor evidence). A new emitter within the same purpose set requires no new basis and no fresh LIA. Purpose (b)(vi) — off-host long-tail operational log aggregation for diagnostic recall without SSH — covers this squarely.

One Art. 28(3) observation, recorded rather than blocking. The Better Stack Vendor DPA is still `PENDING` in `compliance-posture.md`. This change adds a fourth emitter's worth of reliance on an unexecuted processor instrument. The gap is pre-existing and independently tracked (AC15 escalation to `compliance/critical`), and the INERT posture means no additional data flows on merge — so it does not block this diff. It is in the frontmatter triggers.

---

## 6. Non-blocking observations

**6.1 — House style: the `compliance-posture.md` edit is in-place rather than appended.** The sub-processor table's convention, visible in the Hetzner row directly above at line 85, is a dated bracketed block: `**[2026-07-17 (Ref #6538/#6463): …]**`. The #7440 edit instead splices a parenthetical into the middle of prose written on 2026-05-22. It carries its own `#7440/ADR-184` provenance, so the trail is reconstructible and I do not treat it as an audit-trail failure — but it silently changes what a dated row asserts, and the file has a better pattern available. Worth conforming when B6 is fixed, since that cell is being edited anyway.

**6.2 — ADR renumbering: CLEAN.** The shipper's ADR was renumbered 179 → 182 → 184 during review, so I checked for stragglers. `ADR-179`, `ADR-182` and `ADR-185` have **zero** occurrences in either legal file. Both files reference `ADR-184` only, and only in the new blocks. `ADR-179` on `origin/main` is claimed by an unrelated decision (bare-plugin-root anchor), so a stale reference would have pointed somewhere real and wrong — it does not. Nothing to fix. Correctly, ADR-185 (`user_data` headroom policy) is not referenced from the legal corpus; it has no legal surface.

**6.3 — CI gates: none engaged.** The diff touches no `docs/legal/**` file and no `plugins/soleur/docs/pages/legal/**` mirror, so the scope-block placement linter, the mirror-drift ratchet, the `check-tc-document-sha.sh` pin, the heading-parity vitest and the `EXPECTED_COUNT` sentinel are all out of scope. No re-pin is required and no `SOLEUR_LEGAL_DRIFT_ACCEPT` is needed. `knowledge-base/legal/` is the internal accountability corpus and is not a published surface.

**6.4 — The `SOLEUR_ZOT_LOG_BOOT` marker is clean.** The `runcmd` boot reporter added by this PR ships `boot_id`, hostname, and two enum flags (`shipper_cron`, `journald_storage`). No personal data, no client-influenced content. It needs no §(c) entry and does not change the emitter count in any way that matters to §(d).

---

## 7. Drafted wording for the six blockers

Offered as drafts, not as mandated text. Any wording that states the same facts accurately discharges the blocker.

**B1 — PA-8 §(d), replace the opening clause.** Replace "a FOURTH emitter, and the FIRST that reaches source 2457081 WITHOUT Vector." with:

> a FOURTH emitter, and the first to carry VARIABLE, CLIENT-INFLUENCED log content to source 2457081 without Vector. `soleur-registry` has reached this source without Vector since #6122/#6244 — the `SOLEUR_ZOT_DISK` reporter and the `SOLEUR_PRIVATE_NIC` guard both `curl`-POST directly, and both are unchanged here. What is new is the payload class, not the transport: a fixed-schema `key=value` line assembled by the template is joined by whole zot journald rows whose content is shaped in part by what a client puts on the wire. That is the change with data-protection significance.

**B2 — PA-8 §(g), scope the assurance and disclose the sibling path.** Replace "its own `redact()` is the whole boundary" with "its own `redact()` is the whole boundary **for this emitter**", and append before the closing sentence:

> **It is NOT the whole boundary for the host, and that is recorded rather than left to inference.** The pre-existing `SOLEUR_ZOT_DISK` reporter POSTs to this same source and carries `zot_last_err`, a ≤300-character sample of zot's own log output (tiered: `panic:`/`fatal error`/signal/`runtime error`, then `level:error|fatal`, then a `cannot|failed to|unable to` sweep, then a `docker logs --tail 3` fallback). That sample passes through the payload-integrity sanitizer only and through no `redact()` at all. On the fallback tier it is routinely an `info`-level `HTTP API` row carrying the `headers` object; zot self-masks `Authorization` on the pinned image but does not mask `Cookie`, `X-Api-Key` or arbitrary headers. Recorded as a known, bounded residual on a host that takes no public ingress; remediation tracked at #<TBD>.

**B3 — PA-8 §(g), correct the test-assurance sentence.** Replace it with:

> Enforced by behavioural tests asserting against the bytes leaving the process, each block paired with a non-vacuity control proving the assertion is not satisfied by a dropped or empty row (`apps/web-platform/infra/zot-log-shipper.test.sh` §T6/§T6b; 150/150 at attestation, with a harness canary and a 150-assertion floor). Validated additionally at development time against an 11-mutant battery (all RED against a GREEN baseline). Unlike `git-data-emit.test.sh` in the #6982 entry above, that battery is **not** resident in the suite.

**B4 — PA-8 §(c), append a bracketed block** (the cell currently has none for this Activity):

> **[2026-08-12 UPDATE (#7440 / ADR-184): the Vector framing above is an incomplete description of this Activity.** Not every path to Better Stack Logs source 2457081 traverses Vector. `soleur-registry` POSTs directly by `curl`: the pre-existing `SOLEUR_ZOT_DISK` and `SOLEUR_PRIVATE_NIC` reporters, and from #7440 the zot container-log shipper. The `pii_scrub_*` VRL transforms named above do NOT run on those paths and no `userIdHash` pseudonymisation occurs on them — **the Recital 26 basis stated in this cell is a Sentry/Vector-plane property and must not be read as covering the registry plane.** Categories on the registry plane: OCI image references and digests, HTTP method / path / status / latency / byte-count, `User-Agent`, and `clientIP`. **`clientIP` is shipped unredacted** (zot emits it as a top-level field; the emitter's redaction covers header objects, not top-level scalars). It is not Art. 4(1) personal data on the current topology: `hcloud_firewall.registry` carries zero inbound rules, so ingress is intra-`10.0.1.0/24` plus a Cloudflare tunnel whose origin is `tcp://10.0.1.30:5000` — every observable `clientIP` is an RFC1918 address of a host in the controller's own estate, identifying a machine and not a natural person. **That conclusion is TOPOLOGY-DEPENDENT.** Any inbound rule admitting public ingress to zot, or any configuration that lands a forwarded public address in a top-level zot field, converts `clientIP` into personal data on a path carrying no redaction, and requires this cell, §(g) and the emitter to be revisited. `X-Forwarded-For` is not in the emitter's header allowlist and is therefore redacted, which bounds — but does not close — the proxy case. Recorded as a re-evaluation trigger.**]

**B5 — Vendor / Sub-Processor Mapping, Better Stack row (line 446), append** — following the #7100 pattern already resident in that row:

> **[2026-08-12 (#7440): PA-8 §(d)/§(g) record `soleur-registry` as a DIRECT, non-Vector emitter to source 2457081 — the pre-existing `SOLEUR_ZOT_DISK`/`SOLEUR_PRIVATE_NIC` reporters and the zot container-log shipper. "Vector-shipped … pseudonymised at the VRL boundary" above describes the Vector plane and does not hold for these paths: no VRL transform runs and no `userIdHash` is computed. Emitter-side redaction on the log-shipper path is a header-object name allowlist that fails closed; on the `SOLEUR_ZOT_DISK` path it is a payload-integrity sanitizer only.]**

**B6 — `compliance-posture.md` line 96, qualify the pseudonymisation sentence.** Replace "Pseudonymisation: `userIdHash` HMAC-SHA256 at the VRL boundary (`apps/web-platform/infra/vector.toml` `pii_scrub_*` transforms)." with:

> Pseudonymisation: `userIdHash` HMAC-SHA256 at the VRL boundary (`apps/web-platform/infra/vector.toml` `pii_scrub_*` transforms) — **on the Vector-shipped paths only. The direct `soleur-registry` emitters noted above traverse no VRL transform and carry no `userIdHash` pseudonymisation.**

Per §6.1, consider recasting the whole #7440 amendment in that cell as a dated `**[2026-08-12 (Ref #7440/ADR-184): …]**` block, matching the Hetzner row's convention.

---

## 8. Re-review path

Fix B1–B6 and re-invoke this gate. Re-review is confined to the two legal files and should take one pass — I do not need to re-verify `redact()`, the Art. 30(1) characterisation, the lawful basis, the recipient/sub-processor/transfer analysis, the INERT posture, or the ADR cross-references. All are recorded as sound in §§3–6 above and are not re-litigable absent a change to the implementation they describe.

On a clean re-review this becomes `status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)` / `disposition: DISCHARGED`, with `disposition_history` extended.

**Referred out of this domain:** whether `zot_last_err` should route through `redact()` on the `SOLEUR_ZOT_DISK` path is a CTO decision (§3, B2). My gate is discharged by accurate disclosure regardless of which way it goes, but it should carry its own issue rather than being folded into a docs fix.

**Standing note.** This attestation is the v1 *internal* sign-off under the Soleur-as-tenant-zero posture. The operator retains an optional veto. External counsel re-review is reserved for the frontmatter triggers, of which the public-ingress trigger is the strongest candidate.

---

## 9. Re-review — 2026-08-12, commit `22f298dde`

Confined to the two legal files per §8. I did not re-verify `redact()`, the Art. 30(1) characterisation, the lawful basis, the recipient/sub-processor/transfer analysis, the INERT posture, or the ADR cross-references.

**Disposition at this re-review: BLOCKED** on one new finding, B7, which this authority introduced. Closed at the second re-review; see §10.

### 9.1 B1–B6: all six verified fixed

| Blocker | Verdict at re-review |
|---|---|
| B1 — false "FIRST without Vector" | **FIXED.** Headline recast to payload class; #6122/#6244 credited; both pre-existing reporters named as unchanged. Zero residual occurrences of the false string in either file. |
| B2 — host-level assurance false at host level | **FIXED.** `redact()` scoped "**for this emitter**"; the host-level residual disclosure is present with the `zot_last_err` tiering, the sanitizer-not-redactor distinction, and the `Cookie`/`X-Api-Key` gap. `#<TBD>` correctly resolved to **#7500** (verified OPEN, correctly titled and labelled). |
| B3 — mutation-arm claim untrue of the cited file | **FIXED.** Recast to non-vacuity controls, with the 150/150 count, the harness canary, the assertion floor, the development-time 11-mutant battery, and the explicit contrast against `git-data-emit.test.sh`. |
| B4 — §(c) left stale | **FIXED.** Block appended to the PA-8 §(c) cell. |
| B5 — vendor-mapping row unannotated | **FIXED**, and improved: adding `(#7500)` to the `SOLEUR_ZOT_DISK` clause was the coordinator's own addition and is right — the residual now points at its tracker from the mapping table too. |
| B6 — within-cell contradiction | **FIXED.** Pseudonymisation sentence scoped to the Vector plane. |

**On the two questions raised.** The B4 anchor is **correct as applied** — appending to the end of the existing PA-8 §(c) cell is what was intended; this table is two-column (`| Art. 30(1) limb | Entry |`), so a "separate cell" is not a structure it admits. And **do not recast the `compliance-posture.md` cell** per §6.1: the inline sentence is now correctly qualified, §6.1 was a style preference and nothing more, and widening a docs fix past its blocker is the wrong instinct. Declining it was the right call. Consider it withdrawn.

The one ordering deviation — the host-level residual disclosure appended *after* the test-methodology sentence rather than before it — is accepted. The block closes on the residual rather than on the enforcement, which reads slightly oddly, but the scoping fix opens the block and the disclosure sits in the same block in the same cell. No reader is misled. Not worth a round-trip.

### 9.2 B7 — BLOCKING: three unescaped pipes break the §(g) table row

**This defect came from my own §7 B2 draft. I wrote the text, I did not check it against the file's conventions, and the coordinator applied it in good faith verbatim. The finding is mine to own.**

`article-30-register.md` line 180 (the §(g) row) went from **3 pipes to 6**. The three new ones are unescaped `|` characters inside backtick spans in the residual-disclosure sentence:

> (tiered: `panic:`/`fatal error`/signal/`runtime error`, then `` `level:error|fatal` ``, then a `` `cannot|failed to|unable to` `` sweep, then a `docker logs --tail 3` fallback)

Backticks do **not** protect a pipe in a Markdown table. GFM splits the row into cells on `|` before it parses inline code. This table declares two columns (`|---|---|`), so a row arriving with four cells has the surplus **dropped from the rendered output entirely**.

The truncation begins at `level:error`. Everything after it is invisible in any rendered view — GitHub, the Eleventy build, any export handed to a supervisory authority:

- the `cannot|failed to|unable to` and `docker logs --tail 3` fallback tiers,
- "That sample passes through the payload-integrity sanitizer only and through no `redact()` at all",
- the `Cookie` / `X-Api-Key` non-masking gap,
- and the #7500 remediation pointer.

That is the entire substance of B2. The source is correct; the record as read is truncated at precisely the sentence B2 was raised to install, and it fails in the direction of understating exposure — the same failure direction as B1 and B2 themselves. I will not attest a safeguards cell whose disclosure disappears on render.

**The file already knows this rule and follows it everywhere else.** `article-30-register.md` carries ten existing escaped pipes — `` `in_progress\|ok\|error` ``, `` `terraform show -json \| jq` ``, `` `^(payment\|legal\|auth)\.` `` among them. My draft was the only place that departed from the file's own convention.

**Fix — two substitutions on line 180, three characters total:**

| Current | Replace with |
|---|---|
| `` `level:error|fatal` `` | `` `level:error\|fatal` `` |
| `` `cannot|failed to|unable to` `` | `` `cannot\|failed to\|unable to` `` |

Line 180 must return to a pipe count of **3**.

### 9.3 Scope check on the rest of the commit

No other cell gained a pipe. `article-30-register.md` line 174 (§(c), B4) 5→5, line 177 (§(d), B1) 3→3, line 446 (B5) 7→7; `compliance-posture.md` line 96 (B6) 7→7. **B7 is confined to line 180.** No other structural defect found.

### 9.4 One non-blocking precision note, also on my draft

§(d) now reads "the first to carry VARIABLE, CLIENT-INFLUENCED log content to source 2457081 without Vector", contrasted against "a fixed-schema `key=value` line assembled by the template".

Strictly, the pre-existing `SOLEUR_ZOT_DISK` line is fixed-schema only in its *keys*. The value of `zot_last_err` is a ≤300-character sample of raw zot output whose fallback tier is `HTTP API` rows carrying client-controlled headers — so it too is variable and client-influenced, in bounded form. My §7 draft drew the contrast one notch too sharply, in the same direction B1 erred.

**Not blocking, and I am not asking for a change now.** §(g) in this same amendment discloses the `zot_last_err` sampling exactly and completely, so the two cells read together give an accurate picture and no reader of PA-8 can be misled. The distinction that survives is one of degree and it is a real one: whole journald rows continuously, against a bounded error sample. If §(d) is edited for any other reason, tighten "a fixed-schema `key=value` line" to "a fixed-schema `key=value` line whose only variable field is a bounded error sample". Recorded so it is not rediscovered as a defect later.

### 9.5 Re-review path

Apply the two substitutions at §9.2 and re-invoke. Nothing else is open. B1–B6 are closed and are not re-litigable; §9.4 is recorded, not required. On confirmation that line 180 carries 3 pipes, this becomes `status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)` / `disposition: DISCHARGED`.

---

## 10. Second re-review and discharge — 2026-08-12, commit `649f983dd`

**B7: VERIFIED FIXED. Overall disposition: DISCHARGED.**

Both substitutions applied as prescribed. I verified against the **rendered** form rather than the raw line, because the whole substance of B7 was that source and render diverge:

- **Unescaped pipes on line 180: 3.** Raw `|` characters remain 6 — escaping adds a backslash, it does not remove the character — of which 3 are now `\|`. My first-review measurement counted raw pipes, so "back to 3" is correctly read as 3 *unescaped*, which is what GFM cares about. The coordinator's framing was right and my original phrasing of the target was loose; recorded so the next reader of this audit does not repeat the ambiguity.
- **Cell split is correct.** Splitting on pipes not preceded by a backslash yields four fields — a leading empty, the `(g)` label cell, the entry cell, and a trailing empty — i.e. exactly **2 content cells**, matching the table's two-column declaration.
- **The B2 substance survives into the rendered entry cell.** I asserted presence inside the second content cell, not merely inside the raw line: `` no `redact()` at all ``, `X-Api-Key`, `Cookie`, `payload-integrity sanitizer`, `docker logs --tail 3`, `#7500`, and both escaped spans `` `level:error\|fatal` `` and `` `cannot\|failed to\|unable to` ``. All present. Nothing is truncated on render.
- **Whole-file sweep, not just line 180.** Every pipe-leading row in `article-30-register.md` was split the same way. The PA-8 activity tables carry 2 content cells throughout; the Vendor / Sub-Processor Mapping table at lines 438–452 carries 6 throughout, including the B5-edited row 446, consistent with its own six-column header. No row is ragged as a result of this change set. (Line 660 carries 1 content cell and is pre-existing, untouched by this PR and outside this review's scope.)
- **Commit scope is clean:** `649f983dd` touches `article-30-register.md` and this audit file only.

§9.4 was correctly taken as recorded-not-actioned. Declining to re-open settled wording over a non-blocking precision note was the right instinct, and it is the second time in this review that instinct produced the better outcome.

### 10.1 Disposition of record

The PA-8 Art. 30(1)(c)/(d)/(g) amendment for #7440, and the corresponding `compliance-posture.md` sub-processor entry, are **DISCHARGED** and attested under the Soleur-as-tenant-zero v1 posture.

The register now states accurately: that `soleur-registry` has reached Better Stack source 2457081 without Vector since #6122/#6244 and that the new fact is payload class; that the shipper's `redact()` is a fail-closed header-name allowlist and is the boundary **for that emitter only**; that the sibling `SOLEUR_ZOT_DISK` path carries a bounded, unredacted sample of zot's own log output, with remediation tracked at #7500; that the registry plane traverses no VRL transform and carries no `userIdHash`; and that `clientIP` is shipped unredacted, is not Art. 4(1) personal data on the current topology, and ceases not to be if the topology changes.

No Art. 33 or Art. 34 notification is warranted. No new recipient, sub-processor or third-country transfer. Lawful basis unchanged and adequate. The change ships INERT.

**Standing caveat.** This is the v1 *internal* sign-off. The operator retains an optional veto. External counsel re-review is reserved for the frontmatter triggers, of which public ingress to zot is the strongest candidate — it is the one condition that converts `clientIP` into personal data on a path with no redaction.

### 10.2 Note for the next author of a fix draft

Two of the seven blockers in this review — B7, and the imprecision at §9.4 — originated in wording I drafted, not in the change under review. Drafted remediation text is convenient and it is also unreviewed text entering a regulator-facing record. It should be checked against the target file's own conventions before it is applied. `article-30-register.md` carried ten correctly escaped pipes before mine arrived; the convention was there to be read.

---

## 11. Premise expiry — 2026-08-13 (#7455): the change no longer ships INERT

**Disposition: DISCHARGED — UNCHANGED. This section annotates a spent premise; it does not re-open the attestation.**

The shipper merged INERT on 2026-08-12T19:38Z exactly as §5 recorded, and applied nothing. It was
then **delivered** by a separate, dedicated `registry_host_replace` job (workflow run 31639782781)
completing **2026-08-12T20:54:12Z**, with first warehouse readback at **21:03:51Z** — 37 envelope
rows read back out of Better Stack Logs source 2457081. Delivery did not ride the step-6 replace
this review saw as pending; that replace had already fired 2026-08-10T22:08Z, ~45h before the merge.
Whole zot journald rows now flow continuously to source 2457081 by direct host POST.

Three passages in this audit rest on inertness. I take them separately, because they are not
equally load-bearing.

**(1) §5, "This is also what keeps B2's residual from crystallising on merge."** Premise spent.
Disposition unaffected: the word "also" is doing exactly the work it appears to do, and §3/B2 states
in terms that "I am **not** blocking on the existence of the gap". The block was on the register's
host-level *sentence*, which was fixed at 22f298dde and remains fixed. What genuinely changes is
that the `SOLEUR_ZOT_DISK` `zot_last_err` residual is now a **LIVE** bounded residual rather than a
prospective one. Its bounds are unchanged (≤300 chars, sampled, fallback tier only, deny-all-public
host, credential would be a private-net client's own). Its **priority** is not: #7500 should be
treated as live-exposure remediation rather than engineering hygiene. Still a CTO decision, still
non-blocking on this gate, which is discharged by accurate disclosure either way.

**(2) §5, the Better Stack Art. 28(3) paragraph — "the INERT posture means no additional data flows
on merge — so it does not block this diff."** This is the one passage where inertness was genuinely
load-bearing, and the ground is now spent. It is **replaced, not restated**. The correct and durable
ground: reliance on this unexecuted instrument is pre-existing and predates the registry emitter by
roughly three months (Better Stack has received Vector-shipped journald and host_metrics on source
2457081 since #4279 merged 2026-05-21, a materially richer personal-data payload); and the registry
plane's incremental payload carries no Art. 4(1) personal data on the current topology, re-attested
at PA-8 §(c). Going live adds no new personal data to the exposure. **Still a tracked risk, still
not a blocker — but no longer open-ended.** The AC15 `compliance/critical` escalation that
`compliance-posture.md` announces has never been filed: a 2026-08-13 search of issue titles and of
the `compliance/critical` label returns no Better Stack DPA item. Directed at
`compliance-posture.md` line 96, with re-evaluation on execution or 2026-11-13, whichever is first.

**(3) §10.1, "The change ships INERT."** Surplusage, and its expiry changes nothing. Art. 33 and
Art. 34 turn on Art. 4(12), not on inertness. Authorised disclosure to an existing processor on an
existing source under processor terms, intra-EU, is not a personal data breach whether the channel
is live or inert. **Re-confirmed on live traffic: no Art. 33 or Art. 34 notification is warranted.**

### 11.1 What is re-verified rather than inherited

The `clientIP` Art. 4(1) conclusion at §4 was reasoned prospectively about a channel carrying
nothing. It now governs live rows, so it is re-attested against the IaC the replace applied rather
than carried forward:

- `apps/web-platform/infra/zot-registry.tf` — `resource "hcloud_firewall" "registry"` declares a
  name and labels and **no `rule` block of any kind**. Deny-all public ingress survives the replace.
- `local.registry_private_ip` remains pinned to `10.0.1.30`, single-sourced, consumed by
  `network.tf` and by the `tunnel.tf` `ingress_rule` origin `tcp://10.0.1.30:5000`.

Conclusion unchanged: every observable `clientIP` is an RFC1918 address of a host in the
controller's own estate; it identifies a machine and is not Art. 4(1) personal data.

**Stated rather than implied:** this verifies the topology that bounds which values are
*observable*. It is not an observed-value audit of rows shipped since 21:03:51Z. Converting the
topology-dependence into a continuously-enforced invariant — an RFC1918 assertion on the readback
path, so drift fails a probe instead of silently reclassifying a field already in flight — is
**referred to the CTO** and should carry its own issue. It is recorded as a new frontmatter trigger.

### 11.2 Everything else, re-confirmed on live traffic

No new recipient. No new sub-processor. No new third-country transfer. Lawful basis unchanged and
adequate — Art. 6(1)(f) plus Art. 6(1)(c), with purpose (b)(vi) covering this squarely; a described
operation starting requires no new basis and no fresh LIA. The `redact()` verification at §3, the
Art. 30(1) characterisation at §5, and the ADR cross-reference check at §6.2 are undisturbed and
are not re-litigable absent a change to the implementation they describe.

### 11.3 Scope note on PR #7514

PR #7514 (ADR-184 `adopting → accepted`) touches seven files, **none** under
`knowledge-base/legal/**` or `docs/legal/**`. It did not cause the delivery and is not the trigger
for this correction — the Art. 30(1)/Art. 5(2) currency duty arose at 20:54:12Z and would exist
identically had #7514 never been opened. It is **not blocked**. The register amendments are
directed to land with it, because splitting the record of one event across two PRs is how currency
gaps are born; failing that, within 24 hours in a dedicated PR.

### 11.4 The generalisable lesson

An attestation written against a pending change acquires a **shelf life at the moment of delivery**,
and nothing in the pipeline detects its expiry — the same structural blindness ADR-184's own
amendment records about the spent rider. Two guards follow from this. A compliance record must never
assert deployment state in a tense that silently becomes false; state it as dated fact about the
merge, as the amendment above now does. And a topology-dependent legal conclusion reasoned against
an inert channel is a **prediction**, not an attestation — it must be re-verified, and visibly
re-dated, on the day the channel starts carrying traffic.
