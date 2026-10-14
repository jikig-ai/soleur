# Tasks: web-2 LUKS evidence rule, immutability not reboot (#9372, Ref only)

Plan: knowledge-base/project/plans/2026-10-08-fix-web2-luks-evidence-immutability-not-reboot-plan.md
Scope (owner decision 2026-10-08, on the 2026-10-07 principle): the #6931 grader AND the soak-marker writer (`w2l_judge`) use the same rule, defined once in `w2l_ready_arm`.

## 1. Lib, judge, grader, workflow condition

- 1.1 Add `w2l_ready_arm` to `scripts/lib/web2-luks-rows.sh` after `w2l_ready_newest_age` (prints the newest readiness row's `luks_arm`; rc 0 only for formatted|opened; noop NOT accepted)
- 1.2 `w2l_judge`: marker-absent branch calls `w2l_ready_arm "$2"` (RED reason=ready_luks_arm on failure); delete the `w2l_reboot_seen` line and its comment (lines 291-292); delete `w2l_reboot_seen` (lines 258-268); rewrite lib header comment lines 33-37 and add one line to the `w2l_judge` header comment
- 1.3 Grader `scripts/followthroughs/web2-luks-live-6931.sh`: header arm 4 text, `declare -F` guard (`w2l_reboot_seen` -> `w2l_ready_arm`), replace lines 140-144 with the `if ! rarm="$(w2l_ready_arm ...)"; then unmet ...` check
- 1.4 `.github/workflows/workspaces-luks-verify.yml` lines 1184-1186: delete the two `reboot_not_seen` comment lines and `|| "$reason" == reboot_not_seen` from the not-live condition (nothing else)

## 2. Grader tests (`scripts/followthroughs/web2-luks-live-6931.test.sh`)

- 2.1 Flip T04, T04b, T04c, T04e to `run 0 PASS` and retitle; rewrite the comment at lines 143-144
- 2.2 Add T04f (older formatted + newer noop readiness row -> NOT YET naming `luks_arm=noop`) and T04g (`luks_arm=opened` -> PASS)
- 2.3 Replay: `arm 0 a_no_reboot`, `arm 0 a_ready_unknown`, add `a_noop` with a named-reason check; fix the comment at line 318
- 2.4 Delete mutants at lines 344-345; add "luks_arm check skipped" (grader) and "noop accepted" (lib) mutants
- 2.5 `EXPECTED_IDS` += T04f T04g (44 -> 46, matches the existing label); set `FLOOR` to the measured `[ok]` count (expected 85)

## 2b. Verify suite (`apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`)

- 2b.1 Flip S40 (line 1788), S53 (1846), S54 (1847) from `not_live reboot_not_seen` to `0 1 0 iso green marker_written`; rename the three ids to `...-is-GREEN`
- 2b.2 Add fixtures `r_noop` and `r_opened` (beside `r_armnone`, line 1622) and scenarios S59 (noop, marker absent -> `red ready_luks_arm`) and S60 (opened -> `green marker_written`); `G3_EXPECTED_IDS` += S59 S60; line 1862 `58` -> `60` (count and label)
- 2b.3 Replace mutation row 22 (lines 2008-2009) with "old reboot requirement restored" (ids S40 S53); add row 22b "noop accepted by the shared helper" (id S59); drop `|| "$reason" == reboot_not_seen` from the pinned strings of rows 12, 13, 13b (lines 1986-1991); keep row 16
- 2b.4 Rewrite the Guard 3 PROPERTY comment (lines 1325-1331) and the fixture comments at lines 1617 and 1621
- 2b.5 Set `WF_MIN_ASSERTIONS` (line 2250) to the measured green count (expected 332; measured 329 today vs stored 325); add a history line

## 3. Docs

- 3.1 Append the ADR-263 addendum dated 2026-10-08 (decision, rule, what the marker gates / coupling #2 and the loosening, what is unchanged, status of the claim); no old body edited
- 3.2 `web2-luks-rebirth-9372.md`: amendment block, lines 142-144 sentence, reboot-section sentence, closing rows 2 and 6
- 3.3 `web-host-reboot.md`: amendment block + superseded-for-the-grade pointer + rewrite "The marker consequence" (line 177)

## 4. Verify and hygiene

- 4.1 Run every Acceptance Criteria command (grader suite, verify suite, web-host-reboot suite, web2-rebirth suite, lb-weight-gate-with-marker suite, fixture-relative-assert, c4-count-parity, lint-guard-contract, the two greps)
- 4.2 PR body: `Ref #9372`, `Ref #6931`; no Closes. No dispatch, Doppler write, token mint or Terraform apply. (The former tracking-issue task is removed: the marker gap is closed in this PR.)
