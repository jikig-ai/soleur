# Decision challenges - feat-one-shot-9372-web2-luks-closing-change

Appended by plan on 2026-10-06 (headless pipeline: not asked, persisted for the ship phase to render in the PR body and file as an
`action-required` issue). Where the planner argues for a change to the owner's stated direction, the default taken is named.

## User-Challenge

1. **Ask item 3 (flip the `hcloud_volume.workspaces` ledger row to `luks`, `live_verification: available`, floor 2 to 3, and update the
   Article 30 / compliance-posture sentences) is NOT in this PR.**
   - *Stated direction:* flip it in the closing change, saying nothing about the rebirth having happened.
   - *Signal 1 (written conditions):* the approved parent plan (`2026-10-05-feat-web2-luks-rebirth-workflow-plan.md`, Closing checklist
     item 2 and Timing), the runbook (`web2-luks-rebirth-9372.md`, closing row 2) and the CPO/CLO conditions all place the flip after the
     apply and the graded reboot proof: "No cell says LUKS-backed at boot before the graded reboot proof". The live web-2 volume is still
     ext4 and the dispatch has not run; a `luks` row asserts a state that does not exist (Art. 5(2) accountability). The CLO, asked
     again on 2026-10-06, ruled to leave the row, its `exception` block and the Article 30 / compliance-posture sentences untouched; a
     pre-dispatch retirement moves nothing in them.
   - *Signal 2 (mechanical):* measured on a scratch copy, `python3 scripts/lint-encryption-posture.py` FAILS a `luks` row for
     `hcloud_volume.workspaces` (its `attachment_binds_volume` regex does not accept `hcloud_volume.workspaces[each.key].id`, and
     `file_has_secret_pair` finds no secret pair in `server.tf`). The row also covers web-1's superseded plaintext backstop, which the row's
     own evidence says #9372 must split per host "before any flip". Shipping the flip as asked would redden a required gate or require
     redesigning the ADR-140 security linter inside a closing PR.
   - *Default taken:* items 1, 2 and 4 ship; item 3 is deferred. The ledger JSON and `knowledge-base/legal/**` are byte-unchanged
     (acceptance criterion), the prerequisites (per-host row split, linter binding change, Article 30 / compliance-posture supersession,
     floor 2 to 3) are filed as a tracked issue blocked on the graded reboot proof, and the runbook closing row 2 records them.
   - *Re-evaluate:* if the owner wants the flip pre-dispatch anyway, it needs the linter change and the row split first (a separate,
     larger change) and an explicit acceptance that the ledger would then say `luks` for a plaintext volume. The 2026-10-15 decision date
     stands: either the dispatch has run and the post-proof flip is in review, or the owner extends the exception on
     `hcloud_volume.workspaces` (expires 2026-10-22) citing #6931. Nothing in this PR extends it.

## Taste

2. **Scope of the `create` flip: the web-class pair only, not all six HALT addresses.** Issue #9372 says "those two addresses"; the CTO ruled
   the same. Counting `create` at all six also reds the inngest first-create rows (T60d, T60h). Default taken: web-class pair only;
   widening is filed as a follow-up. Re-evaluate when the inngest and web-1 creation routes are retired.
3. **`earliest=2026-10-18T00:00:00Z` for the #6931 directive.** The plan states a formula (rebirth + 3 days), not a literal; the value
   chosen is decision date 2026-10-15 + 3 days so the window closes 2026-10-22, the exception expiry. A later dispatch re-sets it from
   the actual rebirth time (runbook row 4). The directive lives in the issue body, so it is edited after merge.
