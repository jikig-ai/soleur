# Tasks — R2 has no object versioning: repair the rollback runbook, ADR-006, and the Art. 30 register

Plan: `knowledge-base/project/plans/2026-09-06-chore-r2-rollback-runbook-repair-plan.md`
Issue: #7836 (closes) · Branch: `feat-one-shot-7836-r2-no-object-versioning-rollback`

> **Read the plan's `## Enhancement Summary` first.** Deepen-plan review reshaped the recovery model:
> `infra/github/` auto-applies on merge, so the "operator takes a pre-apply snapshot" gesture is
> unavailable there, and state rollback does not fix a live-resource failure anyway. **Config-revert
> is the primary recovery.**

## Phase 0 — Re-probe and file the tracking issue (blocking, before any edit)

- [ ] 0.1 Export R2 keys **outside** `--name-transformer tf-var`:
      `export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)`
      and the same for `AWS_SECRET_ACCESS_KEY`.
- [ ] 0.2 Run the probe pair, exit codes on their own line (never through a pipe):
      control `s3api list-objects-v2` and `s3api list-object-versions`.
- [ ] 0.3 **Control-first branch.** Proceeding requires the **control to return rc=0**. If the control
      is non-zero (expired creds, network, token descope) the probe is **inconclusive, not
      confirmatory** — stop and fix credentials. Do NOT read "rc≠0 on both calls" as "gap persists".
- [ ] 0.4 If `list-object-versions` returns rc=0, **STOP** — Cloudflare shipped versioning; the plan
      changes shape to "make the claim true". Re-plan, do not edit.
- [ ] 0.5 **File the AC14 deferral issue NOW, not in Phase 5.** AC8/AC9b require the ADR note and the
      register cell to cite it *by number*; filing it later is circular. Include everything the plan's
      "What the AC14 issue must carry" list names (secret-lifetime retention, unverified lifecycle
      mechanism, same-job placement, orphan `telegram-bridge` object, the
      `moved-block-wedge-cutover-5887.md` `-force`/lineage correction, ADR-required-at-design-time).
- [ ] 0.6 Record the measured result + date in the PR body.

## Phase 1 — ADR-006 (origin of the false claim)

- [ ] 1.1 `## Decision`: drop "with bucket versioning". Keep R2-as-backend, per-app key paths,
      Doppler-first secrets, the every-new-root rule — all correct and load-bearing.
- [ ] 1.2 `## Consequences`: drop "State loss eliminated via bucket versioning".
- [ ] 1.3 **AC5b — Consequences must GAIN the negative.** Subtraction alone leaves three benefits and
      no cost. Add: no point-in-time recovery; a bad state write is not undoable from the backend;
      recovery is config-revert / re-import / per-root operator snapshot; gap tracked at the 0.5 issue.
- [ ] 1.4 `## Context`: restate as reliable, **off-host, single-writer** remote state.
      **NEVER "locked"** — all five backends set `use_lockfile = false`. Attribute serialization to the
      GitHub Actions concurrency groups, not the backend.
- [ ] 1.5 **AC2e — scope the gesture per root** in the amendment: benign on the re-importable ruleset
      root; on `apps/web-platform/infra/` a restore-then-`apply` plans destroys/replacements against
      live infrastructure, so a restore there is the *start of a reconcile*, not a rollback.
- [ ] 1.6 Add the amendment as a **section**: `## Amendment — <implementation date> (#7836)` — the ADR
      corpus convention (ADR-044/067/071/116/169/179/184). **Not** the register's inline bracket form.
      Frontmatter `status:` stays `active`.
- [ ] 1.7 The note cites: the `NotImplemented` result, the passing `list-objects-v2` control, the
      corrected recovery model, the absent state lock + its real serializer, the 0.5 issue, and
      **AP-021** (diagnostic honesty) + **AP-003** (register visibly unmoved).
- [ ] 1.8 Do **not** conclude "R2 offers no immutability primitive" — R2 Lock Rules exist and are used
      at `apps/cla-evidence/infra/object_lock.tf`. They give no PITR, which is why they do not fix this.
- [ ] 1.9 AC6b: `grep -in 'lock' <ADR-006>` returns only text attributing locking to the concurrency
      group or denying backend locking — never a bare claim the state is locked.

## Phase 2 — The runbook (`infra/github/README.md` §`## Phase 5 -- Rollback`)

> Anchor is a literal double hyphen `Phase 5 -- Rollback`, not an em dash.

- [ ] 2.1 **Rebuild as a failure taxonomy, config-revert first** (AC2): bad config → `git revert` +
      merge (auto-apply reconciles); state lost/corrupted → `terraform import` (ids are hardcoded);
      both → revert then import; ruleset deleted → `scripts/create-ci-required-ruleset.sh`.
- [ ] 2.2 Give §Phase 5 its own **cold-terminal preamble** (AC2d): `cd infra/github/`, the two
      `export`s, `terraform init -input=false`. Written for 3am, not for a warm shell.
- [ ] 2.3 Where `state push` is documented, carry its refusal modes (AC2b): `-force` for the
      always-lower serial; `-force` disables the wrong-root lineage guard (five roots share the bucket
      and the `/tmp/tfstate.pre-*.json` naming) so require a `.lineage`/`.serial`/cwd identity check;
      **`state push` has no `-backup`** so pull the current bad state to a second file FIRST; and a
      snapshot restores the record, not the world (reconcile partial applies before applying).
- [ ] 2.4 Snapshot hygiene (Encryption Posture): mode-`0600` file in a scratch dir + explicit deletion.
      A bare `/tmp/tfstate.pre-<op>.json` is not acceptable — state holds credentials in plaintext.
- [ ] 2.5 Note the concurrency hazard: a terminal-side push sits outside every concurrency group, and
      `scheduled-terraform-drift.yml`'s group is disjoint from the apply groups. Check for in-flight
      runs first.
- [ ] 2.6 **AC3 — fix the credential form at EVERY unsafe site in the file, not just step 3.** Four
      occurrences; two standalone `terraform import` blocks are broken, one is accidentally safe. The
      fix is the **two-layer** form (bare `AWS_*` exported first, then
      `doppler run … --name-transformer tf-var -- terraform …`) — do **not** drop the transformer, the
      root needs `TF_VAR_github_app_*`. Mirror the canonical form already ~70 lines above in this file.
- [ ] 2.7 Note that `state pull`/`state push` need only bare `AWS_*`; only `plan`/`apply` needs the
      `TF_VAR_*` layer.
- [ ] 2.8 **AC2c** — put the pre-write caution where it is read *before* the write: §"Authorization
      model: apply-on-merge", §Phase 1, or §Phase 2.
- [ ] 2.9 **AC19 — correct and reposition the emergency fallback**: 5 → **23** required contexts
      (`grep -c 'context *=' infra/github/ruleset-ci-required.tf`); repoint "re-import via Phase 2" →
      Phase 1 (Phase 2 has no import step); cover all three managed resources (`ruleset.cla_required`
      and the marketplace trio — "a destroy unpublishes the plugin"); prescribe
      `scripts/create-ci-required-ruleset.sh` instead of hand-clicking the UI. Move it **above** the
      state-recovery path.
- [ ] 2.10 AC4: the `-refresh-only` caveat survives.
- [ ] 2.11 Run every command in the rewritten section as written, read-only where possible.
      `terraform state push` is documented but **never** exercised.

## Phase 3 — Art. 30 register (`knowledge-base/legal/article-30-register.md`)

- [ ] 3.1 **AC9a — audit PA12 §(g) in FULL.** Five false/stale safeguards, not one: (1)(3) PAT claims
      (migrated to GitHub App auth in #4384), (2) the "obsolete" 90-day rotation cadence, (5) a
      non-existent "Phase 2.3", and **(8) "No CI auto-apply"** — flatly false and the most material,
      since it misstates the authorization model of a production policy surface.
- [ ] 3.2 **AC9b — rewrite §(g)(4) IN PLACE, preserving the ordinal** (renumbering invalidates every
      citation). Record TLS in transit + provider-managed SSE at rest + no defence against the
      credential holder + the corrected recovery model as the restore limb, stated as manual and
      discretionary; cite the 0.5 issue. Do **not** truncate — that would zero PA12's Art. 32(1)(c).
- [ ] 3.3 **AC9c — §(f)** drops the retained-prior-versions claim and states the surviving trail
      affirmatively: §(b)'s limbs (ii) git history + (iii) GitHub's audit log survive intact.
      Also correct §(f)'s PAT rotation sentence.
- [ ] 3.4 **AC9d** — the correction note carries quoted prior text, date, issue, the probe pair *with
      its control*, and an explicit "no Art. 33/34 duty, no `breach-register.md` row" determination
      citing the two on-file precedents.
- [ ] 3.5 **AC9e** — put the re-evaluation trigger IN the cell (house convention; the #6474 defect).
- [ ] 3.6 **AC16 [CRITICAL] — Vendor / Sub-Processor Mapping**: the Cloudflare Inc row lists
      `1, 2, 4, 5; 7` and omits **12**, while PA12 §(e) names Cloudflare as R2 state custodian. Add `12`
      with a dated note. Same defect #7601 fixed for activity 7 and #7100 for the GitHub row.
- [ ] 3.7 Use the `[<date> CORRECTION (#7836): this cell previously read…]` convention throughout —
      house-proven in this cell at §(e)'s `[2026-08-20 CORRECTION (#7624)]`.

## Phase 4 — Compliance posture, specs, and the gate

- [ ] 4.1 **AC17** — add a posture-derived row to `knowledge-base/legal/compliance-posture.md`
      §"Active Compliance Items" naming the lapsed control + the 0.5 issue. Precedent: the #6474 row.
      An issue alone is invisible to `clo`, which reads this file and not the tracker.
- [ ] 4.2 **AC18 — RUN `/soleur:gdpr-gate`** against the diff; record output in the PR body. The
      waiver is removed: a hard-rule waiver must trace to the operator's own words, not a plan's
      paraphrase.
- [ ] 4.3 **AC11 — all THREE** stale criteria in `specs/feat-terraform-state-mgmt/`: `spec.md` **FR2**
      ("R2 bucket has versioning enabled for state recovery" — the miss), `spec.md`'s open checkbox,
      and `tasks.md`'s checked-but-never-done 1.3.
- [ ] 4.4 **AC21** — tick the already-satisfied
      `specs/feat-remove-telegram-bridge/tasks.md` 3.5 ADR-006 task while ADR-006 is open.

## Phase 5 — Sweeps and verification

- [ ] 5.1 **AC7 (this task was missing entirely)** — run the ADR residual assertion **section-scoped**
      to `## Context`, `## Decision`, `## Consequences`, exempting everything from
      `## Amendment — …` onward. Do NOT run a file-wide sweep here: it would hit the amendment note
      this plan requires be added.
- [ ] 5.2 **AC10 — BOUNDED sweep** (enumerated phrasings + path scope; the bare `versioning` token
      returns 200+ unrelated lines and brushes `hr-never-run-commands-with-unbounded-output`):

      git grep -inE 'bucket versioning|backend versioning|object versioning|versioning (is )?enabled|list-object-versions|versionId|State loss eliminated' \
        -- infra/ knowledge-base/engineering/ knowledge-base/legal/ knowledge-base/project/specs/ .github/

- [ ] 5.3 **AC10b** — name `.github/workflows/apply-sentry-infra.yml` as *the* deliberate carve-out:
      its comment cites the §Phase 5 point-in-time recovery this PR deletes, so the citation goes stale
      **on merge**. Decide the sequencing (follow-up after PR 7866, or a checkbox on 7866) and record it.
- [ ] 5.4 Confirm the other carve-outs untouched: `specs/feat-one-shot-7650-…/tasks.md`, dated plans
      and brainstorms — point-in-time records per the plan's carve-out criterion.
- [ ] 5.5 **AC1** — assert no *prescribed command* in §Phase 5's fenced `bash` blocks calls
      `list-object-versions` or `versionId`, **and** positively assert §Phase 5 still exists with its
      new anchors (so the check cannot pass against a deleted section).
- [ ] 5.6 **AC15 — presence-with-provenance table** in the PR body: every claim the diff ADDS traced to
      a named source. Absence sweeps alone shipped four defects in the cited 2026-07-20 learning.
- [ ] 5.7 **AC12** — state the measured scope in the PR body: #7836 says every root has an unrunnable
      rollback runbook; **exactly one does**.
- [ ] 5.8 **AC13** — `markdownlint` passes on every edited file.
- [ ] 5.9 Verify each AC by running its command. Where an AC is prose-only, name the literal sentence
      anchor the diff must add (`cq-assert-anchor-not-bare-token`) rather than asserting "it reads well".

## Out of scope (deliberate)

- The pre-apply snapshot capability itself — deferred to the 0.5 issue; triaged in the plan's
  `## Alternative Approaches Considered`.
- `.github/workflows/apply-sentry-infra.yml` — already honest, and it **already implements** the
  snapshot the deferred issue generalizes. Carve-out recorded at 5.3.
