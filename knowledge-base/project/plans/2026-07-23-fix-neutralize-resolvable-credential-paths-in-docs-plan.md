---
title: Neutralize resolvable credential-file paths in tracked docs
type: fix
date: 2026-07-23
branch: feat-one-shot-neutralize-credfile-paths-in-docs
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# 🔒 fix: Neutralize resolvable credential-file paths in tracked docs

> **Self-referential hygiene note (load-bearing):** this plan, its spec, and its tasks are themselves tracked docs that load during `/work`. They therefore contain **no** home-relative-resolvable credential-file path and **never** the bare Doppler config filename. Credential files are named descriptively or via a directory-only form (e.g. `~/.doppler/`, which is a directory, not a resolvable file). Do not "helpfully" expand any of these to a full path while editing — that reintroduces the exact trigger this plan removes.

## Enhancement Summary

**Deepened on:** 2026-07-23 (headless one-shot pipeline; gate-verification + realism passes + architecture/spec-flow/simplicity review lenses applied directly — no sub-agent fan-out available in this context).

**Mandatory deepen-plan gates:** 4.6 User-Brand Impact ✅ (`single-user incident`), 4.7 Observability ✅ (5 fields, no-ssh discoverability), 4.8 PAT-shaped-var ✅ (none), 4.9 UI-wireframe — skipped (non-UI), 4.5 Network-Outage — skipped (no SSH trigger in Overview/Problem/Hypotheses; the incidental "SSH private keys" mention is in Implementation Phases only), 4.55 Downtime — skipped (no serving-surface offline op).

**Key improvements from the deepen pass:**
1. **Precedent-diff confirmed exactly** — `scripts/lint-infra-no-human-steps.py` already implements the full-scan-default + `--changed`/`--base` merge-base grandfathering + `*.md`-under-SCAN_DIRS-minus-archive shape the guard needs (verified: its `--changed`/`--base` argparse + `SCAN_DIRS` rglob at lines 51-52, 378-398, 405-441). The guard is a near-clone with a different regex table — low novelty, high confidence.
2. **Scope-completeness closed for the Doppler class** — the only carriers of the Doppler credential path under `plugins/`+`knowledge-base/` are `preflight/SKILL.md` (Phase 1) and the two `.ts` files (Phase 2, manual). After this PR, zero carriers remain in the touched surface; the `.md`-scoped guard prevents reintroduction and the existing preflight mirror-test keeps the two `.ts` strings honest. So the `.md`-only scope does not leave a Doppler-class gap.
3. **Simplicity finding folded** — the advisory (`/home/<user>/`, `/root/`) tier is explicitly optional for v1 (see Phase 3). The load-bearing MVP is the single hard-fail tier over home-relative + bare-Doppler-config forms; shipping advisory-tier is a documented enhancement, not a v1 requirement.

**New considerations discovered:**
- **Residual non-`.md` surface:** the guard scans `.md` only. `.yml`/`.sh`/`.njk` under `plugins/`+`knowledge-base/` are not scanned; today none carry a home-relative Doppler cred path (verified), but a future one could. Documented as a known limitation + optional guard extension.
- **Bare-Doppler-config false-positive risk:** flagging the bare Doppler config filename may catch a legitimate reference to the root project-pointer config; those get neutralized to prose ("the root Doppler project-pointer"). Low volume, acceptable.

## Overview

Claude Code's harness auto-attaches a file into model context when a **locally-resolvable filesystem path to an existing file** appears in loaded skill/doc prose (rendered to the model as a "Read tool result"). `plugins/soleur/skills/preflight/SKILL.md` Check 10 — the credentialed-CLI reject prose — writes the literal home-relative path to the operator's live Doppler CLI config at four sites. Because the preflight skill loads **on every ship**, the harness resolved that path and read the operator's real `dp.ct.*` Doppler token into 9 separate session transcripts. This is not an external attacker and not a rogue hook/MCP — the skill's own security prose (warning that commands must not read credential files) is what caused the credential file to be read. The token has already been rotated by the operator.

**Fix goal:** neutralize every literal, home-relative-resolvable credential-file path written as prose in tracked docs so the auto-attach matcher cannot resolve it to an existing file, while preserving the security prose's meaning and readability — then add a CI lint that prevents any future doc from reintroducing the trigger.

**Two deliverables:**
1. **Neutralize the every-ship trigger** — the four Doppler-config-path literals in `preflight/SKILL.md`, kept in lockstep with the byte-identical mirror string in `discoverability-test-parser.ts` and two explanatory comments. This drives the *proven-leaked* Doppler credential class to zero in the high-frequency loader.
2. **Durable guard** — `scripts/lint-credential-path-literals.py`, modeled on `scripts/lint-infra-no-human-steps.py` (Python doc-scanner + `--changed --base` grandfathering) and registered exactly like it (`test-all.sh` `run_suite` for the unit test + a step in the `lint-bot-statuses` CI job for the changed-files gate). The guard is non-vacuous: a positive fixture with a resolvable credential path fails; the neutralized forms pass.

**Scope (per the "sweep-if-cheap-else-follow-up" mandate):** The changed-files grandfathering model means this PR only needs to neutralize the docs it *touches* (preflight SKILL.md). The ~26 historical learnings/plans/specs that also carry home-relative credential paths are grandfathered by the guard (untouched → not flagged) and drained via **one consolidated follow-up issue**; any future PR that edits one of them must neutralize it then. This is the exact model the repo's `lint-infra-no-human-steps` already uses.

## Research Reconciliation — Spec vs. Codebase

| Claim (task framing) | Codebase reality (verified this session) | Plan response |
|---|---|---|
| Doppler config path appears at ~4 sites (~820/836/843/1075) | Confirmed: `preflight/SKILL.md` lines 820, 836, 843, 1075 | Neutralize all four (Phase 1) |
| Check-10 prose also names ssh key, netrc, git-credentials, aws, gcloud, docker | Confirmed: all in the single echo string at line 836 (and mirror at parser:231) | Neutralize the whole readable-files list to descriptive names |
| Tests may pin exact credential-path strings | **False** — `preflight-discoverability-test.test.ts` asserts only `/credentialed CLI/i` (line 901) + the denylist verb regex `(doppler\|gh\|aws\|supabase\|stripe` (line 1060); no assertion pins any credential PATH substring | No test-assertion change needed; comments at parser:36 + test:882 updated for hygiene only |
| The Check-10 verb reject must keep working | The denylist `CRED_REJECT_RE` verb regex at SKILL.md:835 + parser is separate from the echoed error prose | Do **not** touch the regex or `CMD_DEQ` logic — only the human-readable path literals in the echo/comments/prose |
| Repo ships a root project-pointer file → the bare Doppler config filename also resolves | Confirmed: `git ls-files` shows the root project-pointer file | Guard flags the bare Doppler config filename too; neutralized forms must avoid it, not just the full path |
| ~19 other docs write the Doppler config path | Refined: **5** md docs carry a resolvable Doppler-config form (incl. preflight); **~22** md docs carry other credential paths, but the majority are remote-host forms (`/home/deploy/...` ×17, `/root/...` ×5) that do **not** resolve on the operator's local machine | Guard hard-gates home-relative (`~/`,`$HOME/`) forms + the bare Doppler config filename; remote-host forms are advisory. Consolidated follow-up covers the residual home-relative population |
| Guard should catch `/home/.../.<cred>` absolute forms | The operative distinction is *local resolvability*: `~/`/`$HOME/` resolve for **any** loader; a hardcoded `/home/<other-user>/` resolves only on that user's box and is overwhelmingly remote-host documentation, not a local trigger | Hard gate matches `~/`+`$HOME/`+bare-Doppler-config-filename; `/home/<user>/` credential forms are surfaced as an **advisory** class (report-only) to avoid false-positives on legitimate remote-host runbooks |

## User-Brand Impact

**If this lands broken, the user experiences:** every `/ship` continues to silently read their live Doppler CLI token into the session transcript (and any other home-relative credential the Check-10 prose names — SSH private key, AWS creds, Docker config), exfiltrating infrastructure credentials into stored transcripts on every ship.

**If this leaks, the user's infrastructure credentials are exposed via:** the auto-attached `type: file` read of the resolved credential path, rendered to the model and persisted in the transcript — the exact vector that already fired 9 times before rotation.

**Brand-survival threshold:** single-user incident — a real infrastructure credential (Doppler CLI token) was leaked into transcripts for one operator. CPO sign-off required at plan time before `/work`; `user-impact-reviewer` runs at review time.

## Implementation Phases

### Phase 1 — Neutralize the every-ship trigger (`preflight/SKILL.md`)

Read the four current literals in-file (the plan deliberately does not reproduce the resolvable string) and neutralize each while preserving meaning. Technique per site — describe the file without a home-relative resolvable path; never collapse to the bare Doppler config filename (it resolves to the root project-pointer):

- **Line ~820** ("the Doppler CLI reads a live `dp.ct.*` token from `<home-relative doppler config path>`") → replace the path with a non-resolvable description, e.g. "…reads a live `dp.ct.*` token from its on-disk config in the home Doppler directory (`~/.doppler/`)." (Trailing-slash directory is not a file → not resolvable.)
- **Line ~836** (the `echo "FAIL: … all readable …"` reject message) → replace the parenthetical list of home-relative paths with descriptive names: "…`$HOME` is preserved, so the Doppler CLI token, SSH private keys, netrc, git credentials, AWS credentials, the gcloud credentials database, and the Docker config are all readable…". Keep every other word of the message (it is the operator-facing rejection reason).
- **Line ~843** (`a curl --data-binary @<home-relative doppler config path> exfiltration`) → replace the resolvable `@`-path with a placeholder that preserves the attack shape: "a `curl --data-binary @<doppler-config>` exfiltration".
- **Line ~1075** (Sharp Edge: "the Doppler CLI's `<home-relative doppler config path>` token stays reachable") → "the Doppler CLI's on-disk token stays reachable".

**Do NOT touch:** the `CMD_DEQ` quote-strip logic, the `CRED_REJECT_RE` verb regex `(^|[[:space:]]|/)(doppler|gh|aws|supabase|stripe|hcloud|wrangler|terraform|flyctl|vercel)([[:space:]]|$)`, the SSH reject regex, or the `SUBST_REJECT_RE` shell-active reject. Those are the load-bearing runtime denylist; only the human-readable path prose changes.

### Phase 2 — Keep the runtime mirror in lockstep (`test/lib/discoverability-test-parser.ts` + comments)

- **`discoverability-test-parser.ts:231`** returns the byte-identical error string that SKILL.md:836 echoes. Apply the *same* neutralization so the runtime error message and the doc stay mirrored (and so the `.ts` string literal is no longer a resolvable-path carrier).
- **`discoverability-test-parser.ts:36`** and **`preflight-discoverability-test.test.ts:882`** are explanatory comments naming the home-relative Doppler config path → neutralize to the descriptive form ("its on-disk config under `~/.doppler/`").
- Re-run `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` — expect green (assertions are on `/credentialed CLI/i` + the verb regex, unaffected). If any assertion unexpectedly reddens, it pinned a path substring the reconciliation missed → update it in lockstep and record it.

### Phase 3 — Build the durable guard (`scripts/lint-credential-path-literals.py`)

Model on `scripts/lint-infra-no-human-steps.py` (structure, arg surface, `--changed --base` diffing, changed-files grandfathering). Requirements:

- **Scope:** tracked `*.md` under `plugins/**` and `knowledge-base/**`. Exclude `**/archive/**` (point-in-time records). Do **not** blanket-exclude `knowledge-base/project/{plans,specs}/**` — plans load during `/work`, so they must stay protected; this PR's own artifacts are written in neutralized form instead (see Sharp Edges).
- **Match class (hard fail)** — a home-relative resolvable path to a known credential file. Enumerate as data (the guard's regex table, not prose):
  - **Doppler config:** home-relative form (`~/` or `$HOME/` + the `.doppler` dir + the config filename) **and** the bare config filename (root project-pointer resolves it). Anchor so the directory-only form (`~/.doppler/`) and the bare dir do **not** match.
  - **SSH private keys:** `~/.ssh/` + `id_ed25519` | `id_rsa` | `id_ecdsa` | `id_dsa` (exclude `*.pub`).
  - **netrc / git-credentials:** `~/` + the netrc / git-credentials home-dotfile names.
  - **AWS / gcloud / Docker:** the credential filename **only under its credential dir** (`~/.aws/`, `~/.config/gcloud/`, `~/.docker/`) — because those filenames (`credentials`, `credentials.db`, `config.json`) are generic and must never match bare.
  - Same set under the `$HOME/` prefix.
- **Advisory class (report-only — OPTIONAL for v1):** the identical credential filenames under a hardcoded `/home/<user>/` or `/root/` prefix — surfaced in output but not gating, because these are overwhelmingly remote-host runbook documentation, not a local-load trigger. **The load-bearing MVP is the single hard-fail tier above** (home-relative + bare Doppler config); the advisory tier may be deferred to keep v1 simple (a single-tier guard is easier to reason about and cannot false-fail). If shipped, it is strictly report-only.
- **Modes:** repo-wide (default; used by the unit test + manual runs) and `--changed --base <ref>` (used by CI — grandfathers untouched historical docs, exactly like `lint-infra-no-human-steps`).
- **Output on a hard-fail match:** file, line, the matched literal, and the neutralization recipe ("describe the file without a resolvable path, e.g. `the Doppler CLI config under ~/.doppler/`"); exit non-zero.

### Phase 4 — Non-vacuous unit test (`scripts/lint-credential-path-literals.test.sh`)

Model on `scripts/lint-infra-no-human-steps.test.sh`. **Synthesize fixtures at runtime via `mktemp` + heredoc** (no committed file carries a real credential literal — the trigger string exists only transiently during the test run):
- **Positive (non-vacuity — required):** a temp `.md` containing a resolvable home-relative Doppler config path → guard exits **non-zero** and names the match. Repeat for the bare Doppler config filename and for a `~/.ssh/` private-key path.
- **Negative:** temp `.md` with the neutralized forms (`the Doppler CLI config under ~/.doppler/`; `~/.ssh/` + "private keys"; the descriptive readable-files list) → guard exits **zero**.
- **Boundary:** `~/.doppler/` (dir only), a `.bak`-suffixed embedded name, an `id_ed25519.pub` public key → do **not** match.
- **Advisory-not-fail:** a fixture with a `/home/deploy/`-prefixed Docker config → guard exits **zero** (advisory only) but the report lists it.

### Phase 5 — Register the guard (mirror `lint-infra-no-human-steps` / `lint-trap-tempfile-ownership`)

- **`scripts/test-all.sh`** — add `run_suite "scripts/lint-credential-path-literals" bash scripts/lint-credential-path-literals.test.sh` (adjacent to the line-185 `lint-infra-no-human-steps` registration). This also satisfies `lint-orphan-test-suites.sh` (every `scripts/*.test.sh` must be registered).
- **`.github/workflows/ci.yml`** — add a step to the existing `lint-bot-statuses` job (which already has `fetch-depth: 0` for merge-base diffing), mirroring the `lint-infra-no-human-steps` changed-mode block:
  ```yaml
  - name: Lint resolvable credential-file paths in docs (changed vs base)
    env:
      BASE_REF: ${{ github.base_ref }}
    run: |
      if [ -n "$BASE_REF" ]; then
        python3 scripts/lint-credential-path-literals.py --changed --base "origin/$BASE_REF"
      else
        python3 scripts/lint-credential-path-literals.py --changed
      fi
  ```
- Confirm whether `lint-bot-statuses` is in `scripts/required-checks.txt` + the branch-protection ruleset. If it is NOT (like the advisory tempfile ratchet), state so honestly in the PR body — a guard that claims teeth it lacks is worse than none. Recommend promoting `lint-bot-statuses` (or adding a dedicated required step) so the credential gate is blocking; if promotion is out of scope, add it to the follow-up.

### Phase 6 — Consolidated follow-up issue (residual population)

File ONE issue enumerating the grandfathered home-relative credential-path docs (the residual from the Phase-1 grep, excluding preflight which is fixed here) with: the file list, the neutralization recipe, and the note that the changed-files guard forces neutralization on next edit. Verify the label exists via `gh label list` before citing it. Do **not** use `Closes` — this is a drain-over-time tracker.

## Acceptance Criteria

### Pre-merge (PR)
- [x] The four Doppler-config-path literals are gone from `preflight/SKILL.md`: a grep for the resolvable home-relative Doppler config literal (and its `@`-prefixed exfil form) returns **0** lines. (/work constructs the grep from the in-file literal; the AC does not embed it.)
- [x] `grep -c 'credentialed CLI' plugins/soleur/skills/preflight/SKILL.md` is unchanged (≥1) — the reject message still exists, only its path list changed.
- [x] The verb denylist regex line is byte-identical to `origin/main`: `git diff origin/main -- plugins/soleur/skills/preflight/SKILL.md` shows no change to the `(doppler|gh|aws|supabase|stripe|hcloud|wrangler|terraform|flyctl|vercel)` line.
- [x] `discoverability-test-parser.ts:231` return string and the SKILL.md reject echo carry the same neutralized text (mirror preserved); a grep for the Doppler config filename in `discoverability-test-parser.ts` returns 0.
- [x] `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` passes.
- [x] `bash scripts/lint-credential-path-literals.test.sh` passes, with ≥1 positive fixture proving non-vacuity (guard exits non-zero on a resolvable home-relative Doppler config path) and neutralized-form fixtures passing.
- [x] `python3 scripts/lint-credential-path-literals.py --changed --base origin/main` exits 0 (this PR's touched docs — SKILL.md + own plan/spec/tasks — carry no resolvable credential path).
- [x] `python3 scripts/lint-credential-path-literals.py <this plan> <spec> <tasks>` exits 0 — the planning artifacts do not reintroduce the trigger they fix.
- [x] `bash scripts/lint-orphan-test-suites.sh` passes (new `.test.sh` is registered in `test-all.sh`).
- [x] `grep -q lint-credential-path-literals scripts/test-all.sh` (new suite is wired into the aggregate runner).

### Post-merge (operator)
- [x] None require the operator. The consolidated follow-up (Phase 6) is filed via `gh issue create` (automatable, in `/ship`). The real-world confirmation of the fix (no future auto-attach) is a **harness behavior** the test suite cannot exercise (see Verification Limitation).

## Verification Limitation (recorded honestly)

The fix's ultimate success — that Claude Code no longer auto-attaches a credential file when the preflight skill loads — **cannot be exercised by the test suite**, because auto-attach is harness behavior, not code under test in this repo. The mechanical, testable invariant is *"no tracked (touched) doc contains a home-relative-resolvable credential-file path,"* which the new lint enforces at CI. Real-world confirmation is the **absence of the `type: file` credential attachment in future sessions** — observed operationally, not asserted in CI.

## Domain Review

**Domains relevant:** Engineering (CTO — security hardening + CI guard). Product: NONE (mechanical UI-surface override did not fire — no files under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`; the change is skill prose + a CI lint).

### Engineering (CTO)
**Status:** reviewed (self-assessed; deepen-plan + review-phase agents deepen)
**Assessment:** Security-hardening + doc-hygiene guard. Load-bearing risks: (a) not breaking the Check-10 runtime denylist while neutralizing its prose (mitigated: no regex/logic edit — only echo/comment/prose; tests assert the verb-set + `/credentialed CLI/i`, both untouched); (b) guard vacuity (mitigated: positive fixture required by AC); (c) guard scope precision — home-relative hard-fail vs remote-host advisory — to avoid false-positives that erode trust in the gate. Modeled directly on two shipped sibling guards (`lint-infra-no-human-steps`, `lint-trap-tempfile-ownership`).

### Product/UX Gate
Not applicable — no user-facing surface. Tier: NONE.

## Architecture Decision (ADR/C4)

**No architectural decision.** This is a CI doc-hygiene lint plus prose neutralization, directly modeled on ~20 existing sibling `lint-*.py`/`lint-*.sh` guards, none of which carry an ADR. No data-model/tenancy boundary, substrate, resolver, or trust-boundary change; no existing ADR is reversed or extended.

**No C4 impact.** Checked against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` for: (a) external human actors — none added; (b) external systems/vendors — none added (the Doppler CLI already exists in the operator's runtime; no new integration edge); (c) containers/data-stores — none touched (a CI lint script adds no runtime container); (d) actor↔surface access relationships — unchanged. A CI lint guard is not a modeled architecture element. (Deepen-plan Phase 2.10 should confirm by reading the three `.c4` files.)

## GDPR / Compliance Gate

Assessed — **skip (no regulated personal-data surface).** The leaked artifact is an infrastructure credential (Doppler CLI `dp.ct.*` token), not personal data; no schema/migration/auth-flow/API-route is touched, and no new processing activity is created. No Art. 30 register entry is warranted. (Recorded because the `single-user incident` threshold triggers the (b) consideration; the substance is credential hygiene, not data processing.)

## Infrastructure (IaC)

Skip — no new infrastructure (no server, service, cron, vendor account, secret, DNS, cert, or firewall rule). The change is skill prose + one CI-registered lint script.

## Observability

```yaml
liveness_signal:
  what: "lint-credential-path-literals CI step in the lint-bot-statuses job"
  cadence: "every PR + push to main"
  alert_target: "CI red on the lint-bot-statuses job (GitHub Checks)"
  configured_in: ".github/workflows/ci.yml (lint-bot-statuses job)"
error_reporting:
  destination: "GitHub Actions job log + non-zero exit surfaced as a failed check"
  fail_loud: true
failure_modes:
  - mode: "a future doc reintroduces a home-relative resolvable credential path"
    detection: "python3 scripts/lint-credential-path-literals.py --changed --base origin/<base> exits non-zero"
    alert_route: "lint-bot-statuses check fails on the PR"
  - mode: "guard regressed to vacuous (matches nothing)"
    detection: "scripts/lint-credential-path-literals.test.sh positive fixture asserts a non-zero exit on a resolvable Doppler config path"
    alert_route: "test-all.sh run_suite failure"
logs:
  where: "GitHub Actions run logs for the lint-bot-statuses job"
  retention: "GitHub default workflow-log retention"
discoverability_test:
  command: "bash scripts/lint-credential-path-literals.test.sh"
  expected_output: "all fixtures pass (positive fixture exits non-zero; neutralized fixtures exit zero); suite reports OK"
```

## Risks & Mitigations (deepen synthesis)

**Precedent diff (4.4 — pattern-bound behavior):** the guard is modeled on `scripts/lint-infra-no-human-steps.py`, which establishes the canonical shape for a Python doc-scanner gate in this repo:

| Dimension | `lint-infra-no-human-steps.py` (precedent) | `lint-credential-path-literals.py` (this plan) |
|---|---|---|
| Scan target | `*.md` under `SCAN_DIRS`, minus `**/archive/**` | same (`plugins/**` + `knowledge-base/**`) |
| Full-scan default | yes | yes (used by unit test + manual) |
| `--changed --base` grandfathering | yes (merge-base diff) | yes (identical CLI + CI wiring) |
| CI wiring | step in `lint-bot-statuses` job (`fetch-depth: 0`) | same job, adjacent step |
| Match engine | regex table over doc lines | regex table over doc lines (credential-path class) |

No novel mechanism is introduced — only the regex table differs. `lint-trap-tempfile-ownership.py` supplies the secondary precedent for a security-hygiene ratchet, if a highwater baseline is ever preferred over changed-files grandfathering (not needed here).

**Review-lens findings (architecture / spec-flow / simplicity, applied directly):**
- **Architecture (scope precision):** the home-relative-hard-fail vs remote-host-advisory split is the correct expression of the root cause (local resolvability), not an arbitrary cut. Residual risk: the `.md`-only scope; mitigated because the only current non-`.md` carriers are the two `.ts` files handled in Phase 2, and the existing preflight mirror-test keeps them honest.
- **Spec-flow (proxy-vs-invariant):** the CI invariant ("no resolvable path in touched docs") is a *proxy* for the true goal ("no future auto-attach"), which is harness behavior CI cannot exercise — this is stated honestly in Verification Limitation. The invariant is non-vacuous by the positive-fixture AC. The `.md`-scope→Doppler-outcome gap is closed (verified: zero non-`.md` `.md`-scope-invisible Doppler carriers remain after Phase 2).
- **Simplicity (YAGNI):** the advisory tier is marked optional for v1 (Phase 3); the hard-fail home-relative + bare tier is the MVP. Runtime-synthesized fixtures (Phase 4) avoid committing a trigger literal.

**Scoped-out (with rationale):**
- Extending the guard to `.yml`/`.sh`/`.njk` source string-literals — deferred; today none carry a home-relative Doppler cred path (verified), and code legitimately references paths (false-positive risk). Revisit if a non-`.md` carrier appears.
- Sweeping the ~26 grandfathered historical docs in this PR — deferred to the Phase-6 consolidated follow-up per the "sweep-if-cheap-else-follow-up" mandate; the changed-files guard forces neutralization on next edit of any of them.

## Sharp Edges

- **The plan/spec/tasks must not reintroduce the trigger they fix.** These artifacts live under `knowledge-base/project/` (in-scope for the guard) and are "changed" files in this PR, so the changed-mode guard scans them. Write them using only neutralized forms — never a resolvable home-relative credential path, never the bare Doppler config filename, never a `~/.ssh/`-prefixed key name. Refer to the credential file descriptively or with a directory-only form (`~/.doppler/`). An AC self-scans these files.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled with the `single-user incident` threshold.
- **Do not neutralize the parser without neutralizing SKILL.md:836 identically** (and vice-versa) — they are a mirrored pair the `#6772` invariant expects to match; drift between them would make the runtime error and the doc diverge.
- **The guard's hard-fail class is home-relative only by design.** Widening it to all `/home/<user>/` absolute forms would false-flag legitimate remote-host runbooks (a `/home/deploy/`-prefixed Docker config appears ×17). Keep those advisory unless review proves the false-positive population is empty.
- **The positive fixture must carry a real trigger literal, so synthesize it at runtime via `mktemp`** — do not commit a fixture file containing the resolvable path (a committed fixture is itself an auto-attach carrier). The literal then exists only transiently during the test run, under `scripts/` (out of the guard's `plugins/**`+`knowledge-base/**` scope).
- **Verify `lint-bot-statuses` blocking status before claiming the gate has teeth.** If it is absent from `scripts/required-checks.txt` and the branch-protection ruleset, the guard is advisory — state that explicitly in the PR body (per the `lint-trap-tempfile-ownership` precedent) rather than implying enforcement it lacks.
