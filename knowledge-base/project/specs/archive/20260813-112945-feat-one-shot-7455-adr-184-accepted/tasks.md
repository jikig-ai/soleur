# Tasks — flip ADR-184 adopting → accepted

Plan: `knowledge-base/project/plans/2026-08-12-chore-adr-184-status-flip-accepted-plan.md`
Branch: `feat-one-shot-7455-adr-184-accepted` · Tracker: #7455 (Ref only — do NOT close) · PR: #7514

## Phase 1 — ADR-184: the flip and its evidence

- [x] 1.1 Flip frontmatter `status: adopting` → `status: accepted`
- [x] 1.2 Repair `related_specs:` to the archived path
      `knowledge-base/project/specs/archive/20260812-194844-feat-one-shot-7440-zot-log-shipping/session-state.md`
- [x] 1.3 Add `7455` to frontmatter `related:` (currently `[7440]`)
- [x] 1.4 Append `## Amendment 2026-08-12 — first PASS observed (status ACCEPTED)`, following the
      ADR-044 precedent shape (`dbf0e89d0`). Must contain:
  - [x] 1.4.1 `**Status flip:** adopting → accepted` + verbatim probe counts
        (`envelope=37 control=7 gc_start=1 gc_done=1 gc_blobs=1 patch_upload=0 dropped_rows=2`,
        window 30m, floor 7, `boot_marker(1)`, 27/37 carrying `zotregistry.dev/zot/v2/pkg/api`)
  - [x] 1.4.2 Why §6/§7 are preserved rather than rewritten, and what they got wrong: delivery did
        NOT ride step 6 — the ordered path's replace fired inside `registry-luks-recut` on
        2026-08-10T22:08Z, ~45h before the shipper merged (2026-08-12T19:38Z)
  - [x] 1.4.3 The delivering run: `registry-host-replace` run 31437037877 → **31639782781**,
        completed 2026-08-12T20:54:12Z
  - [x] 1.4.4 Generalisable lesson: a rider is valid only while its vehicle is still pending
  - [x] 1.4.5 Boot-id transition `bc135d5b-…` → `93c52405-…`
  - [x] 1.4.6 First operational reading: `dropped_rows=2` of 37, clear of the floor of 7

## Phase 2 — Runbook: invert the falsified warning box

- [x] 2.1 In `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`, replace the
      box anchored on `**⚠️ THIS CHANNEL IS LIVE ONLY AFTER DELIVERY.` — the channel is live as of
      2026-08-12; zero rows is now a **fault**, not a not-yet. Keep the enrolled-probe pointer as
      the first diagnostic step

## Phase 3 — C4 coherence and regeneration

- [x] 3.1 In `knowledge-base/engineering/architecture/diagrams/model.c4`, correct the trailing
      clause of the `zotRegistry -> betterstack` edge anchored on
      `A host-side change is still INERT UNTIL A PROVISIONING EVENT`. Record delivery on
      2026-08-12 via a dedicated `registry-host-replace` (explicitly not step 6); keep the
      cloud-init-only inertness rule as still-true for future changes. Preserve the file's existing
      RETRACTED/CORRECTED annotation style
- [x] 3.2 `bash scripts/regenerate-c4-model.sh` and commit the updated `model.likec4.json`
      (never hand-edit — it is byte-diffed)
- [x] 3.3 `bash plugins/soleur/test/c4-model-freshness.test.sh` → PASS
- [x] 3.4 **Abort arm:** if `npx -y likec4@1.50.0` cannot be fetched, DROP Phase 3 entirely rather
      than hand-editing the JSON. Phases 1–2 stand alone

## Phase 4 — Verification

- [x] 4.1 AC1: `grep -c '^status: accepted'` = 1 and `grep -c '^status: adopting'` = 0 on ADR-184
- [x] 4.2 AC2: the `related_specs:` path resolves on disk
- [x] 4.3 AC3/AC4: `^## Amendment 2026-08-12` heading present, containing `envelope=37` and `31639782781`
- [x] 4.4 AC5/AC6: runbook no longer contains `THIS CHANNEL IS LIVE ONLY AFTER DELIVERY` nor
      `not-yet, not a fault`
- [x] 4.5 AC7: `INERT UNTIL A PROVISIONING EVENT` count in `model.c4` = 0
- [x] 4.6 AC8: `c4-model-freshness.test.sh` exits 0
- [x] 4.7 AC10: `git diff origin/main...HEAD --name-only` touches no `apps/web-platform/infra/`
      and no `.tf`. **AC amended 2026-08-12 during /review — `scripts/followthroughs/` removed from
      the exclusion.** Two agents independently found the probe's `not_delivered` advice is now a
      live operator hazard (post-delivery that arm means a regression, and the sweeper republishes
      its stdout verbatim to a public issue), with a green `C2` assertion pinning the false
      instruction. Probe advice + header + `C2` corrected together; exit codes, `reason=` tokens and
      queries untouched; fixture suite 70/70. `cloud-init-registry.yml` stays excluded because
      `user_data = base64gzip(replace(templatefile(…)))` carries **no `ignore_changes`**, so any
      edit — even a comment — is ForceNew on `hcloud_server.registry`.
- [x] 4.8 Claim-class sweep re-run. **AC amended 2026-08-12 — the original expectation ("exactly
      one survivor") was written before the retraction wording existed and was wrong.** A
      file-level grep cannot distinguish a live claim from prose *quoting* the claim it retracts,
      so the check is now line-level: 6 files survive, and each match was inspected —
      - `model.c4` + `model.likec4.json` (generated mirror): match sits inside the
        `is RETRACTED 2026-08-12 (#7455)` sentence, quoting the clause it retracts. This is the
        file's own annotation style.
      - `betterstack-log-query.md`: matches `was **merged inert**`, a true past-tense statement
        immediately followed by the delivery timestamp.
      - this plan + this tasks.md: the feature's own planning artifacts (documented carve-out).
      - `scripts/followthroughs/zot-log-channel-7440.sh`: was the documented Acknowledge;
        **superseded 2026-08-12 during /review — it is now CORRECTED, not acknowledged** (see 4.7).

      Zero live stale claims. Same false-positive class as
      `2026-06-17-grep-assertion-over-script-body-false-matches-own-comments`, inverted: a
      correction grep false-*fires* on the correction's own quotation of what it corrected.

      **Further amended 2026-08-12 during /review — the bound itself was too narrow.** The three
      literals miss on punctuation and wording: `cloud-init-registry.yml` writes ``step-6
      `registry-host-replace` `` with backticks and `INERT UNTIL PROVISIONED` (not `… A
      PROVISIONING`), so both literals returned 0 against the origin text every downstream artifact
      paraphrased. The legal corpus never uses the engineering phrasings at all — widening to
      `Ships INERT|delivery rides|no additional data flows` returns 4 hits there. Both are tracked
      as follow-ups rather than swept here (the first is ForceNew infra; the second is a CLO call).
- [ ] 4.9 Full-suite gate at its usual `/work` point; no suite regresses

## Phase 5 — Follow-up to file (not folded in)

- [ ] 5.1 File an issue for `model.c4`'s stale zot-image-pin clause
      (*"the LIVE host still runs v2.1.2 and will until the registry-host-replace apply fires"*).
      Already-measured datum for the fix: live `SOLEUR_ZOT_DISK` reports
      `zot_image_digest=95a837a0afac`, matching the `v2.1.20@sha256:95a837a0afac…` pin in ADR-184 §3.
      Note it needs a `regenerate-c4-model.sh` run, so batch with other `model.c4` work
