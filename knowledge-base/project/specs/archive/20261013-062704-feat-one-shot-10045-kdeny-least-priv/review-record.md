---
feature: feat-one-shot-10045-kdeny-least-priv
issue: 10045
pr: 10063
reviewed_at: 2026-10-12
panel_sha: 9005da404844a6f627bc343b75de8d7bf5cf78c9
head_at_review: 52835a43c7
class: code
risk_tier: none (plan-declared; sensitive-path scope-out honored — *.sudoers + host IaC)
design_risk: no
seats_spawned: 8 (+ shellcheck deterministic gate, bash-only substitution for semgrep-sast)
---

# Review Record — #10045 kdeny least-privilege kernel-stream grant

## Panel

8 seats (all resumed successfully after a transient rate-limit kill at spawn):
git-history-analyzer, pattern-recognition-specialist, architecture-strategist,
security-sentinel, code-quality-analyst, performance-oracle (path-triggered),
test-design-reviewer (path-triggered), structural-enumeration (Guard Contract in
plan). No conditional seats fired beyond these (no Rails/migration/gdpr/domain-model/
user-impact/anti-slop surfaces). shellcheck run clean on all touched `.sh` (the
bash-only PR's semgrep-sast substitution per the #4045 rule).

## Pre-panel gates

- PR was **CONFLICTING** with main (sibling #10060 touched `server.tf`) — rebased
  onto `cddc15da8d`, conflict resolved keeping both hunks, force-pushed.
  `pull_request` workflows had been suppressed on the DIRTY state; re-verified
  MERGEABLE after rebase.
- Touched-suite green at panel time: ci-deploy.test.sh 614/614,
  cloud-init-inngest-bootstrap.test.sh 249/249,
  infra-config-handler-bootstrap.test.sh 59/59, visudo -cf OK, terraform validate OK.

## Dedup ledger

~20 raw findings → 16 unique defects + 4 deliberate skips.

| Defect | Reporting seats | Severity | Disposition |
|---|---|---|---|
| `^sudo:`-only denial signature misses GNU `Sorry,`-prefixed policy denial — dead fallback, grant-less host emits j=error (a new failure class) | test-design P1, code-quality P1, git-history P2, pattern P2 | **P1** | FIXED — class widened to `^(sudo:\|Sorry,)` + recognized-phrase requirement; mock pins both recorded bodies (`rs`, `gnu`); D10k3/k4 loop both shapes |
| Guard-1 "no wider journalctl grant" census covers only the `Cmnd_Alias` form — 4 widening shapes evade (direct grant, space-less `=`, appended command, include) | struct-enum P1, security P3, test-design P3 | **P1** | FIXED — comment-stripped journalctl-mention totality (==1), `grep -qxF` anchored grant lines on both surfaces, `^[[:space:]]*[@#]include` absence assert |
| Accepted-run `sudo:`-prefixed stderr (e.g. `unable to resolve host`) merges via 2>&1 into the counted stream — `empty` misread `ok`; could satisfy the denial shape on a real tool failure | security P3 | P3→P2-class | FIXED — post-check `^sudo:` strip + phrase requirement + MOCK_SUDO_WARN fixtures (D10k6/k7) |
| d10g census: per-line `grep -vF` exclusion lets a second read smuggled onto the pinned line evade | struct-enum P2 | **P2** | FIXED — strip-first per-occurrence rewrite + SMUGGLE fixture |
| d10g census: appended-flag drift after `-o cat` admitted | struct-enum P3 | P3 | FIXED — `^ 2>&1([[:space:]]\|$)` residual rule + SUFFIX fixture |
| d10g census: path-qualified `/usr/bin/journalctl` invisible to `kern` boundary | architecture P3 | P3 | FIXED — boundary widened to word-char exclusion + `)`/`|` trailing |
| Mock pins `sudo: a password is required` — auth-required subclass, not the policy-denial class the grant-absent case produces | pattern P2, test-design P1, code-quality P1 | P2 | FIXED — `rs` = recorded fleet emission `sudo: deploy : command not allowed`; `gnu` = infra-config-apply.test.sh:842's `Sorry, user …`; unknown values exit 70 |
| `CI_DEPLOY_ASSERT_FLOOR` stale at 609 (un-ratcheted kdeny rows) | test-design P2 (fix-round) | P2 | FIXED — ratcheted to measured 618 with ledger line |
| `^sudo:` strip shipped with zero fixture coverage | test-design P2 (fix-round) | P2 | FIXED — MOCK_SUDO_WARN=1 + D10k6 (empty stays empty) + D10k7 (no masquerading denial) |
| `SJ`/`KJ` counters substring-loose; `KD -ge 1` loose; dead mock disjuncts; `sudo[[:space:]]` EOL gap; census ` = ` spacing | test-design, code-quality P3s | P3 | FIXED |
| `KDENY_CALL_ARGV`/`KDENY_PROBE_ARGV` extraction reads comments | struct-enum note, test-design P3 | P3 | FIXED — `^[[:space:]]*#` pre-filter |
| "caught BOTH" comment mechanically false pre-fix | 4 seats P3 | P3 | FIXED — now mechanically TRUE after boundary widening |
| `server.tf` FILE_MAP comment contradicts #4827 NOTE | struct-enum note | P3 | FIXED |
| `SOLEUR-DEBT` "has LANDED" premature | pattern P3 | P3 | FIXED — "ships with this change and lands via the bridges" |
| Plan prose: `paths:` includes `cloud-init.yml` (false); "six existing `Cmnd_Alias`" (eleven); `dmesg_restrict` attribution | git-history P3s, architecture P3 | P3 | FIXED |
| Stale `MOCK_SUDO_DENY=1` docs in contract/tasks/plan/runbook | code-quality P3, struct-enum note | P3 | FIXED |

## Deliberate skips (recorded, not defects)

- `runuser` execute probes have no `timeout` — matches the sibling probe convention;
  journalctl `-n 400 --since` is self-terminating (perf-oracle note).
- `dmesg;`/`dmesg>`/`dmesg&` trailing-semicolon/metachar smuggle shapes — the `;`
  exclusion is deliberate (`for rung in journal dmesg; do` false-positive);
  documented in the predicate comment.
- `cat-deploy-state.sh:276` pre-existing unprivileged `journalctl -k -n 200` —
  outside every guard's window by design (argv differs → sudo denies; fail-closed).
- Cloud-init birth path has no Guard-2 execute probe — declared in the plan's
  fan-out table; consequence bounded to `src=none` by the reader fallback.

## Fix-round verification

- Round 1 (8 seats, resumed, over `9005da4048..1366a35ecf`): all findings CLOSED;
  two new P2s found and fixed (floor ratchet, warn fixtures).
- Verification pass (fresh-eyes seat, `aa84c16f`, over cumulative fix range):
  all fixes CLOSED, **no new defects**. Residuals are documented nits (P4-level).

## Suite state at review exit

- `ci-deploy.test.sh`: **618/618** (floor ratcheted 609→618, exact measured count)
- `cloud-init-inngest-bootstrap.test.sh`: **250/250** (floor 173)
- `infra-config-handler-bootstrap.test.sh`: **59/59** (floor 59)
- `web-host-provisioner-parity.test.sh`: 18/18 + Guard-2 9/9 (rebase re-verify)
- `visudo -cf` OK; `terraform validate` OK; shellcheck clean

## Verdict

No open P1/P2/P3 findings. The two P1 clusters (dead fallback on GNU-sudo shapes;
Guard-1 totality gap) were the panel's real catches — both would have shipped
invisible-to-suite defects (a fallback that only fired on one sudo flavor, and a
census that only watched one grant syntax). The fixes are themselves fixture-pinned
(dual denial bodies, warn arm, smuggle/suffix controls, totality census).
