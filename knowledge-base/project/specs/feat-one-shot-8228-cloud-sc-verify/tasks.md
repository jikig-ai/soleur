# feat-one-shot-8228-cloud-sc-verify — tasks

Plan: `knowledge-base/project/plans/2026-09-17-chore-post-merge-cloud-sc-verify-plan.md` · Issue: #8228 · Parent: #8159 · Residual tracker: #8172

## Phase 1 — Pre-flight (local)

- [ ] 1.1 Run `devin cloud drs whoami`; record org identity + auth status in the session record. MUST report `org_id == org-ca24688f494a49eea7e43e9eb57f2710` and `api_key_set: true` (verified output shape at deepen time — whoami emits `org_id`/`devin_api_url`/`api_key_set` only; the slug `jean-deruelle-ca24688f494a` is corroborated by the session's org surface, not by whoami). Any Jikigai limb → STOP, escalate CLO per D10 before `sandbox-create`. (AC1)
- [ ] 1.2 Confirm `git show origin/main:.devin/config.json` carries `requiredPlugins` (verified at plan time; re-check at run time — main moves). Record merge-commit baseline `6c1dbcbbcc36365b6db10a500827bedec0f2585e`.
- [ ] 1.3 Stage the verbatim sandbox prompt from the plan §Technical Approach (Steps 1–4, findings file `/tmp/sc-verify/findings.md`, SC3 secrets arm last and unprimed).

## Phase 2 — Cloud session + evidence capture

- [ ] 2.1 `devin cloud drs sandbox-create --repo jikig-ai/soleur --prompt "<verbatim prompt>"`; capture `devin-<id>` + `https://app.devin.ai/sessions/<id>` URL. `--repo`+`--prompt` ONLY — never `--secret KEY=VALUE` (an injected secret voids the zero-credential baseline). On create failure: CANNOT ESTABLISH + one retry after a delay; no verdict rows without a session.
- [ ] 2.2 Operator-side checks via `drs run` (independent of the agent): `cloud-detect.sh` verdict + `--banner`, `lock.json`, `env | grep -o '^DEVIN[A-Z_]*'`. A `local` verdict → abort, file P1 bug, record no PASS. (AC3)
- [ ] 2.3 Shipped-implementation check: `git fetch origin main && git merge-base --is-ancestor 6c1dbcbbcc36365b6db10a500827bedec0f2585e <lock-sha>` — must exit 0 before any SC verdict; stale cache → CANNOT ESTABLISH, retry once after a delay. (AC2)
- [ ] 2.4 Poll `/tmp/sc-verify/findings.md` via bounded foreground `drs run` loop (15 × 120s). Score per plan §Phase 2 verdict inputs: SC1 (banner quote + routed stage + `Reviewed-Coverage: sequential-fallback`), SC3 (Step-3 marker tail + >=10 min silence + suspension-or-documented-defer shape = PASS; session ended/idled with no Step-4 output and no documented defer = PARTIAL; ANY Step-4 output = FAIL — distinguish suspended-vs-ended via `drs run` liveness), SC4 (skill count + lock provenance vs `managed`-only pre-merge baseline). (AC4/AC5/AC6)
- [ ] 2.5 Edge arm: an earlier `message_user` stall (e.g., inside the `/soleur:go` stage) counts as ack-gate evidence — record which step produced it.
- [ ] 2.6 Session cleanup: leave for audit or `devin rm`; record which. Cost bound: one session, ~30-45 min.

## Phase 3 — Evidence write-up + follow-through (local)

- [ ] 3.1 Append `## Post-merge verification` to `knowledge-base/project/specs/feat-devin-cloud-session-parity/cloud-probe.md` — session header (id, URL, lock SHA, clone SHA, credential-determination carry-forward) + verdict table with unfenced `SC1`/`SC3`/`SC4` tokens, per the plan's template block. (AC7 input)
- [ ] 3.2 Self-check: `bash scripts/followthroughs/cloud-mode-postmerge-evidence-8159.sh` exits 2 BEFORE the append and 5 against the worktree after — the 2→5 transition is the verified contract. (AC7)
- [ ] 3.3 File follow-up issues for every AC not reaching PASS (expected: SC4 marginal effect if `managed` still masks → clean-account arm, cross-ref #8172; any FAIL → bug issue). Filing-gate compliance: `Mandated-By: wg-when-deferring-a-capability-create-a` on its own line, or `--label meta/machinery`, or `User-Impact:`+`Fix-Size:`; inline `--body` or repo-relative body file only. (AC8)
- [ ] 3.4 `gh issue comment 8228` with evidence pointer + per-AC verdict summary; leave #8228 OPEN (operator closes per the sweeper's ACTION REQUIRED). (AC9)
- [ ] 3.5 Diff-scope check: committed files limited to `cloud-probe.md`, `specs/feat-one-shot-8228-cloud-sc-verify/*`, plan file, generated index/session-state artifacts. (AC10)
- [ ] 3.6 No secret values / credentials / personal data in any written artifact — env probes record variable names only. (AC11)
