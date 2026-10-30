# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-11321-11424-11426/knowledge-base/project/plans/2026-10-28-feat-breakglass-mirror-image-tag-fix-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- Initial write of the full plan was rejected by the IaC-routing guard (literal `ssh deploy@<host>` text in the break-glass runbook description). Resolved via sanctioned `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out — no new infrastructure is provisioned; flagged text is runbook content.
- No Task/subagent tool in the planning subagent's environment, so agent fan-outs ran inline with sequential-fallback disclosure; no independent agent review is claimed.

### Decisions
- D1 (CTO ruling): normalize `image_tag` inside `resolve-web1-known-good-tag.sh` (`RUNNING_VERSION="${RUNNING_VERSION#v}"`) — chokepoint fix, strict `^vX.Y.Z` guard untouched.
- D3 (CTO ruling): break-glass GHCR exception represented as C4 description-level amendments + ADR-096 amendment — no new standing edge.
- D6 (CTO ruling): #11321 closes via evidence comment + `gh issue close` conditioned on live `versions_ok` (PR body carries `Refs #11321`), never unconditional `Closes`.
- D7 (CTO ruling): GHCR auth is operator-supplied PAT at invocation — never `GHCR_READ_TOKEN`.
- Merge-blast verified: neither edited file is referenced by any `.tf`; no resource changes attributable to this diff.

### Components Invoked
- skills/plan/SKILL.md (run to completion)
- skills/plan-review/SKILL.md (applied inline, sequential-fallback)
- skills/deepen-plan/SKILL.md (run to completion inline)

## Work Phase
- Status: implementation complete, committed `e1c09b5782` (10 files +1142/-19), pushed.
- WS-B: resolver #v normalization + fixtures (g)/(g2)/(g3) + workflow wording — TDD RED verified, 15/15, all cross-suites green. NOTE: apply-web-platform-infra.yml now 489,980/490,000 bytes (~20B headroom).
- WS-A: registry-breakglass-mirror SKILL.md + mirror-ghcr-to-zot.sh (~850 lines) + README row; components 1455 pass; script validated (bash -n, --help, --dry-run, xtrace refusal 78).
- ADR/C4: ADR-096 2026-10-28 amendment + 3 model.c4 description edits; model.likec4.json regenerated; c4 tests 35/35.
- WS-C: #11321 CLOSED with live evidence (4 conns @ 2026.10.4; run 40748202708 version_verdict=versions_ok).
- PR #11442 body updated (merge-blast first line, Closes #11424/#11426/#9669, Refs #11321, Changelog).
- GDPR gate: skipped (no regulated paths in diff). lint-ratchet: user-ruff not adopted (relayed).
- Affected-test exit gate RUNNING detached: log /var/tmp/soleur-11424-run/test-all.log, rc /var/tmp/soleur-11424-run/test-all.rc — MUST verify terminal `=== N/M suites passed ===` + rc=0 before review.
- cto_spawns=0 (all rulings inline). agent_rounds=2.
- Remaining: one-shot Steps 4-8 (review → resolve findings → qa → compound → ship → DONE).

## WS-R1 (review phase, 2026-10-28 ~21:00)
- PANEL_SHA=623f1b346d. 8 seats run via `devin -p` headless + `devin -r <id> -p` resume trick (Write-to-/var/tmp is outside workspace → rejected; report = final stdout msg). Reports: /var/tmp/soleur-11424-run/review/*.report.out. Seat session ids: architecture=elemental-countess git-history=sequoia-bench structural=mini-crayon test-design=mewing-clutch security=boiled-creature pattern=hexagonal-prepared agent-native=laced-journey code-quality=ahead-production.
- Findings: 4 P2 + ~26 P3, ALL pr-introduced → fix inline. Dedup ledger + dispositions applied:
  FIXED: mirror-ghcr-to-zot.sh (jq `.layers|.size`→`[]|.size` P2-verified jq errors; GHCR_USER+ZOT_TARGET validation; die C0/DEL strip; crane bootstrap gated on DRY_RUN==0; || die 6 on fs ops; classify end-of-string 502/503/504; verify_pushed manifest-arm signature→verify_blobs_of; dry-run digest sha256 check; dry-run n_layers die-4; children jq ||true→die; sig-404 hedge; SIGKILL+triplication comments), SKILL.md (cloud-mode marker + Inputs/repo+ref-discovery + env-transport + dry-run-read-text + close-out probe + GHCR_USER row + host prereqs + subject.digest wording), resolver (RAW_VERSION + sanitizer \177+\xe2\x80\xa8/a9), test.sh (reject rows -ne0→-eq1; g4 raw-input diag row; g5 regex-parity row; 17/17 green), devin-cloud-mode.test.ts (UNION+MARKED_SET+67→68), track.sh:105 + apply-deploy-pipeline-fix.yml:2296 (v-normalization), apply-web-platform-infra.yml dup comment dropped (489,939B now), plan premise annotation.
  WONTFIX: doh_ip first-A-record (accepted residual, GHCR_IP override), plain-HTTP zot creds on L2 (standing posture, pre-existing).
- PENDING: mirror-ghcr-to-zot.test.sh fixture (closes zero-coverage + CRANE_CMD-seam findings) + registration; verify (shellcheck, bash -n, both suites + devin-cloud-mode bun test); commit fix batch; emit main trailer + Review-Evidence comment; push; ADR-267 fix round (respawn reporting∪path-mapped∪security = ~8 seats + 1 verifier over diff PANEL_SHA..HEAD, cap 2); QA (fixture-suite evidence; census already closed #11321); compound; ship (Phase 6.45 archive-kb.sh handles KB archival; UNTRUSTED-CI caveat — PR touches .github/workflows so no agent --admin fallback); DONE.
- Affected gate: /var/tmp/soleur-11424-run/test-all.log LOCK_QUEUED position≈3 of siblings (one-shot fleet); rc file /var/tmp/soleur-11424-run/test-all.rc — wait `until [ -s rc ]`.
- Tally: seats=8 (+1 consult pending), ci_cycles=1, fix_rounds=0, agent_rounds=2.

## WS-R2 (fix-round 1, 2026-10-28 ~21:40)
- Pushed 623f1b346d..6062b74b8d (fix commit f33b9f088b + trailer). Review-Evidence comment posted on #11442.
- Fix-round 1: 8 seats resumed (same session ids) over `git diff 623f1b346d..HEAD`; reports at /var/tmp/soleur-11424-run/fixround/<seat>.out. fix_rounds=1.
- New findings (round 1): P1 verify_blobs_of:578 same jq `[]` bug (fixed+live-stub fixture h); P2 (g5) vacuous grep → anchored `IMAGE_TAG_RAW" =~ \^v?` ==2; P3s: classify `" 502"` boundary, CRANE_TIMEOUT 900+docs+shape check, n_layers local, ZOT_TARGET guard after flag-parse, tr -cd '[:print:]' portable sanitizer, :5337 indent+comment restored (489,9xx), RAW_VERSION at track.sh+apply-deploy-pipeline-fix.yml, Run-comment path, (c) env -u GHCR_TOKEN, SKILL.md timeout prereq + mirror.env rm. suite-durations.tsv is generated → NO row.
- Remaining: verify (fixture incl new live row (h) exercising verify_blobs_of; shellcheck; suites) → commit → 1 verification-pass seat (code-quality=ahead-production found the P1) → emit --fix-round --since 623f1b346d trailer → push → affected-gate rc → QA → compound → ship → DONE.

## WS-R3 (pós fix-round, ~22:30)
- Fix-round 1 completo: ff6a7cd2f9 + ccc9f7aea8 + trailer a08c566efe — PUSHED. Remote head = a08c566efe.
- Verification pass (ahead-production): 9/9 VERIFIED + P1 confirmado; 2 residuais corrigidos.
- GATE: test-all.log ~38k linhas, ainda rodando; rc file ainda vazio; seguir esperando `until [ -s test-all.rc ]`.
- Próximo: gate rc → QA → compound → ship → DONE.

## WS-R4 (gate wait, ~00:30)
- Tudo pushed até a08c566efe (fix-round trailer). GATE test-all.log >51k linhas, suites na fase PASS-roll final (infra z-*); rc file ainda vazio — seguir polling `[ -s test-all.rc ]`.
- Depois do gate: QA (fixture suites já 7/7 + 17/17 + devin-cloud-mode 42/42) → compound (learnings: 490KB ceiling, resolver-canonical D1, DoH/--resolve, devin -p seat mechanism, jq `[arr|.field]` bug class) → ship (Phase 6.45 archive-kb.sh; UNTRUSTED-CI: PR toca .github/workflows → sem --admin fallback) → postmerge → pipeline-tally show → DONE.

## WS-QA (~01:10)
- QA PASS: resolver 17/17, mirror fixture 7/7 (incl live-path row h), devin-cloud-mode 42/42, components 1455/1455, integration greps (2 IMAGE_TAG_RAW =~ ^v? sites, unstripped pass-through, no #v in workflow, --insecure only on zot leg). SKILL.md backtick→markdown-link fix para components.test.
- e2e census: já executado (evidência no PR body; #11321 fechado).
- Gate regressions pré-existentes NÃO relacionadas ao diff: vinngest pin drift v1.1.64 vs v1.1.66 (main avançou), code-to-prd T11 (camada secret-scan alheia), runtime ceiling exit-3 (ambiental — fila + 4h).
- Próximo: compound → ship (Phase 6.45 archive-kb; UNTRUSTED-CI: .github/workflows tocado → sem --admin) → postmerge → DONE.

## WS-C (compound, ~01:30)
- Learnings escritos: 2026-10-29-fixing-one-copy-of-a-triplicated-jq-bug-leaves-the-p1-twin.md + 2026-10-29-running-review-seats-as-headless-devin-subprocesses.md (ambos com Session Errors + Prevention).
- Triage: erros da sessão = one-offs já capturados pelos gates (SC2218, indent-artifact, undispositioned strip, grep -q); o único recurring = "fix one copy of a triplicated bug" → resolvido inline pelo NOTE lockstep + fixture live-path; sem AGENTS.md rule (constraint não-hidden, coberta pelo fix-round).
- Próximo: ship completo (phases, archive-kb, overlap preflight, ready, CI poll, merge --squash --auto, postmerge) → DONE.
