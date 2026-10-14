# Tasks — fix(inngest): re-pin the bootstrap image and bind the pin to the bytes it names

Derived from `knowledge-base/project/plans/2026-09-07-fix-inngest-bootstrap-pin-and-guard-hardening-plan.md`.
**Read that plan first.** Every "why" lives there and is deliberately not restated here — this file
carries only actionable steps and the anchor to look the reasoning up under.

**Scope guard.** No cutover, no host replace, no recut dispatch, no change to the Hetzner volume,
nothing drained, flushed or `FLUSHALL`ed, and no revert of the `INNGEST_BASE_URL` repoint to the
co-located scheduler. See the plan's `## Non-Goals / Out of Scope`.

## Phase 0 — Preconditions (no writes)

- [ ] 0.1 Confirm `vinngest-v1.1.26` is unclaimed across every `origin/*` ref, not only `origin/main`.
- [ ] 0.2 Re-record the baselines the ACs compare against. Measured at plan time:
      `grep -c '@sha256:' apps/web-platform/infra/cloud-init.yml` → `0`, and
      `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` → 129/129, exit 0. Capture
      the per-section floor values too.

## Phase 1 — The three guards, then the carrier repair (RED first)

- [ ] 1.1 Add **Guard A** to `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`: for every
      path in `.github/workflows/build-inngest-bootstrap-image.yml`'s `COPY` list, compare
      `git show <pinned tag>:<path>` against HEAD's copy. Derive the path set from the `COPY` lines;
      read the tag from the pin literal. No network, no registry, no new binary.
      Spec: plan `### Guard A — carrier coherence`.
- [ ] 1.2 Extend **Guard B** by widening the existing digest-identity block (content anchor: the
      `ZG_GHCR_DIGEST` / `ZG_ZOT_DIGEST` comparison) to `cloud-init.yml`'s two pin sites. Exclude test
      fixtures from the site sweep by an **explicit rule**.
      Spec: plan `### Guard B — tag↔digest binding across every pin site`.
- [ ] 1.3 Add **Guard D**: every `cat > … <<` in `inngest-bootstrap.sh` uses a non-expanding
      delimiter. Match all three unquoted forms — `<<WORD`, `<<-WORD`, `<< WORD`. Scope to that one
      file. Encode the `DOPPLEREOF` exemption **by name, with a content assertion** that its body
      contains no backtick and no `$(`, and its `umask 0137` rationale inline in the guard's source.
      Spec: plan `### Guard D — quoted delimiters on generated artifacts`.
- [ ] 1.4 **Bump the affected anti-vacuity floor in the same edit** as 1.1-1.3. The suite carries
      several per-section exact-equality floors (measured baseline: 129/129 passing, with
      `Guard 1 … expected 40, ran 40` and `Row7 … expected 7, ran 7` among them). Bump the floor of
      the section each assert lands in — a guard added to the wrong section reds a floor nobody edited.
- [ ] 1.5 Confirm all three guards are RED against HEAD before any fix lands. Guard A reds on the real
      stale pin, Guard B on `cloud-init.yml`'s tag-only sites, Guard D on the heartbeat delimiter.
- [ ] 1.6 Quote the heartbeat unit heredoc delimiter (content anchor:
      `cat > "$HEARTBEAT_UNIT" <<HEARTBEATEOF`) and move `${DOPPLER_BIN}` / `${HEARTBEAT_SCRIPT}` to
      `@@DOPPLER_BIN@@` / `@@HEARTBEAT_SCRIPT@@` + `sed -i`, matching the `@@DARK_ARM@@` pattern
      already in the same file.
- [ ] 1.7 **Do not touch the `DOPPLEREOF` env-file write.** Documented exemption — see plan Phase 1.4.
- [ ] 1.8 Verify every directive in the heartbeat unit body survives byte-identical, naming
      `PrivateTmp=true`, `RuntimeDirectory=inngest-heartbeat`, `RuntimeDirectoryPreserve=yes` and
      `SyslogIdentifier=inngest-heartbeat` individually. Each has its own prior incident.
- [ ] 1.9 Guard D goes GREEN. Guards A and B stay RED — that is the coupling, not a failure.
- [ ] 1.10 Execute every mutation row in all three matrices and observe RED; execute every harness
      must-PASS row and observe GREEN. Capture per-row output, never a summary count.

## Phase 2 — Bake (freeze, then tag)

- [ ] 2.1 Drive review to green on every carrier file, then **freeze the branch**. Land no further
      carrier edit after this point. **See `decision-challenges.md` UC-1 first** — the advisor
      consult recommends tagging a merge commit on `main` in a two-PR shape. Open operator decision.
- [ ] 2.2 Push tag `vinngest-v1.1.26` at the frozen commit and let the build publish to GHCR,
      cosign-sign `${IMAGE}@${DIGEST}`, and mirror to zot. **No workflow edit is needed** — the
      cosign step already echoes `Signed <image>@<digest>` to stdout, so the run log carries the
      signed digest. Do not add an artifact upload; see the plan's Phase 2 note.

## Phase 3 — Pin (the coupled unit)

- [ ] 3.1 Read the digest **programmatically** from the tagged run's log, anchored on the
      `Signed <image>@<digest>` line. Never transcribe it, never eyeball it. Cross-check
      independently with `docker buildx imagetools inspect` where credentials permit; a disagreement
      halts the phase.
- [ ] 3.2 Bump all four pin sites to `v1.1.26@sha256:<digest>` — `cloud-init-inngest.yml`'s `IREF=`
      and `ZIREF=`, and `cloud-init.yml`'s `IREF=` and `ZIREF=`, **adding the digest to the latter
      two**, which have none today.
- [ ] 3.3 Rewrite the drift-guard comment in `cloud-init-inngest.yml` whose last line currently reads
      "…a v1.1.25 tag pinned to v1.1.24's bytes — silently, since the drift guard only reads tags" so
      it describes the new binding. **Preserve** the adjacent note explaining the tag literal is
      retained so the semver-max guard stays armed.
- [ ] 3.4 Widen the IREF-shape assertion in `apps/web-platform/infra/inngest-host.test.sh` (content
      anchor: the `IREF=ghcr\.io/jikig-ai/soleur-inngest-bootstrap:v…@sha256:[0-9a-f]{64}$` regex) to
      cover `cloud-init.yml`'s two sites.
- [ ] 3.5 Guards A and B go GREEN, and green only against these values.
- [ ] 3.6 Confirm the deliberately-stale negative-control fixture in
      `cloud-init-inngest-zot-pull-mutation.test.sh` is **still stale**. A sweep that updates it
      destroys the control.
- [ ] 3.7 Confirm Guard A also runs against the post-rebase tree.
- [ ] 3.8 Add live tag→digest re-resolution to `.github/workflows/apply-web-platform-infra.yml`'s
      inngest host-replace preflight, beside the existing `docker buildx imagetools inspect` call
      that already runs there with GHCR credentials. **Not** in `deploy-script-tests` — see plan
      `### Correction 2`.

## Phase 4 — Make the #7761 follow-through measurable

Read the plan's `#### 4.0` first — it resolves an exit-contract conflict with the committed script's
own header, and the resolution is load-bearing for every step below.

- [ ] 4.1 In `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh`, derive the boundary when
      neither `FLIP_ROLLOUT_AFTER` nor the `.after` sidecar is set: read the pinned digest out of
      `cloud-init-inngest.yml`, then take `AFTER` from the **earliest** `SOLEUR_INNGEST_SERVER_PROBE`
      row whose `image_ref` carries that digest. Both existing overrides keep precedence.
- [ ] 4.2 **Cap the derived arm at PASS-or-TRANSIENT. It must never exit 1.** Implement as a single
      guarded exit helper whose **comment states the rule and its reason**, so a later edit cannot
      restore the false-`stale_image` hazard silently. Where the derived arm would have failed, exit
      2 with `derived_boundary_stale_supply_authoritative_boundary`.
- [ ] 4.3 **Amend the script's header in the same edit** so its "a boundary that is OLD with still no
      markers is a FAIL" sentence is scoped to a *supplied* boundary. Do not leave it unqualified.
- [ ] 4.4 Match on the **digest only** (`@sha256:<64hex>`), field-isolated from the decoded
      `image_ref`, never the whole ref — the live host reports the **zot** prefix while the pin
      literal is GHCR, so whole-ref comparison never matches.
- [ ] 4.5 Normalise the ClickHouse `dt` (space-separated, no `T`/`Z`) with
      `date -u -d "$dt" +%Y-%m-%dT%H:%M:%SZ`, then run it through the script's **existing** ISO-8601
      validator. Never bypass the validator for a derived value.
- [ ] 4.6 Add a sibling selector to `mine()` that binds the outer row before descending into `raw`,
      so it can emit `dt` alongside `.message`. `mine()` emits `.message` only and the probe row
      carries no time field inside its message — this is a new function, not a flag.
- [ ] 4.7 Order the derivation **after** the `BETTERSTACK_QUERY_*` and `jq` preflights. Keep the
      supplied read where it is, but do not exit there when nothing is supplied — record that the
      boundary must be derived and continue.
- [ ] 4.8 Inherit `mine()`'s two-field `.host` / `.host_name` filter (#6616). The co-located web host
      emits the same marker and this PR gives all four pin sites one digest.
- [ ] 4.9 Raise the row limit for the derivation query, and record in the code comment that a
      newest-slice can only make the boundary **later** — which under 4.2 delays a PASS and can never
      manufacture a condemnation.
- [ ] 4.10 Cover the derived arm in
      `scripts/followthroughs/inngest-cutover-flip-rollout-7761.test.sh`: plan scenarios T1-T7,
      including the T5/T6 provenance-split pair.

## Phase 5 — Framing, architecture, and the record

- [ ] 5.1 Retitle #7674 to match the measured reality (it bound `:8288`, served HTTP 200 at
      `uptime_s=49`, and the flip FSM's rollback arm stopped it by design). **Do not close it.**
- [ ] 5.2 Amend ADR-199's Phase-2 → Phase-3 interlock with the one-sentence precondition that the
      pinned image must carry the emitter, pointing at Guard A. **No new ADR ordinal.**
- [ ] 5.3 File the four follow-on tracking issues listed in the plan's `## Non-Goals`, including the
      `type/security` issue carrying the bounded exposure window, the `INNGEST_REDIS_LUKS_KEY`
      negative, and the 2026-11-18 retention deadline.
- [ ] 5.4 PR body: `Ref #7695`, `Ref #7761`, `Ref #7674`, `Ref #6894` — never `Closes`. State that
      this PR makes an image carrying the emitter **exist**, not **run**, and that a green CI here is
      not clearance to recut. Record the projected `store_populated` ordering constraint, quoting
      ADR-142's addendum.
- [ ] 5.5 Paste into the PR body: the per-file Guard A output, the digest-capture command and its
      output, and the #7761 probe's before (`boundary_unknown`) and after
      (`boundary_underivable`) verdicts.
- [ ] 5.6 State in the PR body that this PR **arms** a force-replacement of the sole scheduler —
      `hcloud_server.inngest` carries no `ignore_changes=[user_data]`, so a cloud-init edit
      force-replaces it — and that merging does **not** fire it (no `hcloud_server` appears in any
      merge-apply `-target=`; verified). The replace is the delivery vehicle, reachable only through
      the gated `apply_target=inngest-host` dispatch. See the plan's `### Downtime & Cutover`.

## Exit

- [ ] E.1 Run the full battery for the touched shards through each suite's own entry point, never a
      hand-enumerated file list.
- [ ] E.2 Walk `## Acceptance Criteria` AC1-AC16 in the plan and record evidence for each.
