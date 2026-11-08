# Tasks — feat-one-shot-11294-clo-reassessment

Plan: `knowledge-base/project/plans/2026-11-08-docs-11294-clo-reassessment-record-landing-plan.md`
Issues: Ref #11294, Ref #11711, Ref #9927, Ref #11922 — never Closes/Fixes/Resolves; all stay open.
Draft PR: #12387. Tier-1 internal record; `docs/legal/` untouched.

## 1. Land the CLO record verbatim

- [ ] 1.1 `cp /tmp/2026-11-08-clo-reassessment-11294-rotation-incomplete.md knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md`
- [ ] 1.2 `cmp /tmp/2026-11-08-clo-reassessment-11294-rotation-incomplete.md knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md` — must report identical (AC-1). Any diff → STOP.
- [ ] 1.3 Conventions check only (no prose edits): frontmatter parses; `type: clo-attestation`, `date: 2026-11-08`, `signed_off_at: 2026-11-08` present.
- [ ] 1.4 Secret-shaped-value scan (high-entropy base64url runs, `dck_`-style/Doppler token shapes) returns nothing — counts/dates/run-ids only. A finding → STOP and flag; never scrub the CLO's text.

## 2. Extend `lint-legal-registers.sh` cited-paths extraction

- [ ] 2.1 Rewrite the `cited_paths` awk producer (`scripts/lint-legal-registers.sh:263-267`): per index row, emit one line per backtick-enclosed span in `$(NF-1)` (trimmed), instead of the whole trimmed cell.
- [ ] 2.2 Add the zero-emission arm: a data row whose last cell yields no candidate fails with a named message distinct from the unresolvable-path message.
- [ ] 2.3 Replace the `resolved+broken == row_count` reconciliation with a `rows_emitting == row_count` reconciliation (emit both counts on mismatch; fail-closed).
- [ ] 2.4 Leave untouched: per-path resolution gauntlet (absolute/`..`/symlink/tracked/`-f`), `OUT_OF_SCOPE_ROW` literal check, `grep -qxF` joins in (c), disjointness, waiver parity (d), section scoping `inblk`.
- [ ] 2.5 Extend `scripts/lint-legal-registers.test.sh` with composite-cell fixtures: (i) two resolving spans → GREEN + both indexed; (ii) second span unresolvable → specific `(b)` RED; (iii) zero backticked span in a canonical cell → reconciliation RED; (iv) first row single-path + second row composite → both files counted indexed.
- [ ] 2.6 PROVE IN ISOLATION: `bash scripts/lint-legal-registers.sh` exits 0 against the UNMODIFIED register (all 15 single-path cells still parse); `bash scripts/lint-legal-registers.test.sh` exits 0. (AC-4 first half.)

## 3. Register edits — verify each cell before replacing

- [ ] 3.1 Re-grep `knowledge-base/legal/breach-register.md` for the three target cells' current text. All must match the quoted superseded text byte-for-byte (AC-3). Drift → STOP and flag; do NOT edit blind.
- [ ] 3.2 Event cell (a): replace `Containment and rotation are owner-gated and not yet done` with the CLO's containment/rotation sentence verbatim (brief deliverable 2a).
- [ ] 3.3 Open-limbs cell (b): replace the whole cell (`**Yes — all four, none closed.** … not yet contained`) with the CLO's `**Yes — all four, none certified clean.** …` text verbatim (brief 2b).
- [ ] 3.4 Canonical-source cell (c): append `` `; 2026-11-08 re-assessment: ` `` followed by `` `knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md` `` (brief 2c).
- [ ] 3.5 `related:` frontmatter: append the new record path after the 2026-10-31 entry (convention of commit 45df1eef3f).
- [ ] 3.6 Append `## Corrections — 2026-11-08 (#11294 re-assessment)` at file end: one `> **Superseded 2026-11-08 (#11294) — applied in-cell:**` blockquote per superseded clause (the replaced event-cell sentence; the whole prior open-limbs cell), quoting prior text verbatim; close with `**Determination unchanged.**` (row stays SECURITY INCIDENT/PROVISIONAL; Art. 33 and Art. 34 cells stay `No`) (brief 2d).
- [ ] 3.7 No standalone `TBD`/`TODO`/`XXX`/`FIXME` outside backticks in the file (lint assertion (a)).
- [ ] 3.8 `bash scripts/lint-legal-registers.sh` exits 0 post-edit — produced=43, both cited paths resolve + indexed, no waiver (AC-4 second half, AC-5). `bash scripts/lint-legal-registers.test.sh` exits 0 (AC-6).
- [ ] 3.9 `git diff --name-only` shows no `docs/legal/` path (AC-10).

## 4. Commit and PR

- [ ] 4.1 Commit `docs(legal): land the 2026-11-08 CLO re-assessment record for #11294 (Ref #11294, Ref #11711, Ref #9927, Ref #11922)` — `Ref` keywords only.
- [ ] 4.2 Push; update draft PR #12387 body: summary, `Ref` lines, and this post-merge runbook verbatim.
- [ ] 4.3 Verify no `Closes|Fixes|Resolves` token for any cited issue anywhere in commit message or PR body (AC-7).

## 5. Post-merge (runbook — execute AFTER the PR merges, never before)

- [ ] 5.1 Post on #11294, verbatim:
  > CLO re-assessment posted 2026-11-08 under the trigger that fired today (rotation not recorded complete here). Verdict: the 2026-10-29 determination stands — a security incident, not a presumed notifiable personal-data breach; no evidence of use of any exposed key was found, so no fresh 72-hour clock starts and the notification posture is unchanged. Rotation state: 7 of the 12 exposed values rotated complete, 2 retired as dead values, 1 rotated with its previous value still accepted, 1 not yet dispatched, 1 awaiting an owner decision on a separate window. Next re-assessment 2026-11-15 if still not recorded complete; evidence of use starts a fresh 72-hour clock at once. Record: knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md.

  Command: `gh issue comment 11294 --body "<verbatim text above>"`. Never close #11294.
