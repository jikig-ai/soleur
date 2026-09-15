---
title: "Counsel review audit — #8189 / PR #8206 (Art. 30 PA-36 §(g)(13) root-key TOM added; stale 'unborn' wording marked Superseded; Secrets-management bullet qualified)"
type: counsel-review
date: 2026-09-15
issue: 8189
pr: 8206
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-15
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED subject to FOUR in-PR text corrections (C1–C4, below) that the lead applies before merge. One artifact in scope: knowledge-base/legal/article-30-register.md — the Hetzner vendor row marker, the Cross-Cutting Secrets-management qualification, the PA-36 Scope-note marker, the PA-36 §(g) header marker, the §(g)(1) step-name marker, the §(g)(5) and §(g)(6) cross-references, and the new §(g)(13). The diff is additions-only (word-diff shows no deleted token), touches no Status cell and no PA-2 §(g)(17) text, and no docs/legal/** or Eleventy mirror file. Every implementation claim was checked against the shipped bodies (git-data-root-key/{key,access,main,variables}.tf, git-data.tf, cloud-init-git-data.yml, git-data-root-key-arm-gate.sh and its two call sites, apply-git-data-root-key.yml, git-data-cutover.yml, git-data-cutover.sh, the encryption-posture ledger), not against the plan or ADR-220. One claim is FALSE against the code: §(g)(13) and its (5) cross-reference count the root key as 'a fourth SSH authority', but every create of hcloud_server.git_data also carries hcloud_ssh_key.default (the operator's key) as a root login key with no forced command, and the create gate REQUIRES exactly that pair — so the enumeration omits a root authority that is on the live host today. That is the #4353/#4558 drift class and the #7349 count class; it is C1. C2–C4 are wording that is literally true but reads as a claim the record must not make or points at a stale sentence. No MUST-NOT limit is breached. No Art. 33 and no Art. 34 duty arises: the store holds no repository."
blocking_findings: []
required_before_merge_DISCHARGED:
  - "C1 — PA-36 §(g)(13) heading and first sentence, §(g)(5) and §(g)(6) cross-references: stop counting the root key as the fourth authority and name hcloud_ssh_key.default as the other root authority without a forced command (exact text under §Conditions)."
  - "C2 — PA-36 §(g)(13) custody sentence: 'isolated Doppler project … not in the `prd` config' is ambiguous (the secret lives in soleur-git-data-root's own config slugged `prd`) and 'isolated' reads as the custody isolation the plan-time limit forbids; qualify it and cross-reference the Secrets-management qualification and #8209."
  - "C3 — PA-36 Scope-note marker says 'the Status row governs' while the untouched Status cell reads 'the host is unborn'; re-point the marker to the Status DISPOSITION and supersede those words from the marker (no Status-cell edit). Add the matching marker to the header surface-list sentence, which carries the same dated wording the vendor-row marker already supersedes."
  - "C4 — PA-36 §(g)(1) marker: 'the repoint is now the real cutover's repoint step (#8211)' asserts a step that does not exist (#8211 is OPEN, rebuild not landed); use the future tense."
optional_precision_notes:
  - "O1 — §(g)(13) 'a create is refused unless the key matches a fingerprint committed to the repository' is true, but the arm reads the fingerprint from the DISPATCHED ref's checkout: git_data_host_create is environment-gated to main (reviewed anchor); git_data_host_replace has no environment:, so a branch dispatch supplies its branch's anchor (key.tf header, arm-gate header, #8093). The sentence claims no review, so nothing is false; a clause naming #8093 would pre-empt a reader inferring one."
  - "O2 — 'delivered only by a create of hcloud_server.git_data' is true of the Terraform path. An HCLOUD_TOKEN holder can also select any project key for a rescue boot or a rebuild outside Terraform (ADR-220 D4 residual: HCLOUD_TOKEN already reaches root on the host). Not a condition — that holder already has root reach without this key — but it is the residual the sentence's 'only' sits beside."
  - "O3 — Stale 'unborn' sentences outside this PR's envelope remain unmarked: PA-1 §(g)(13) 'The host is additionally unborn as of 2026-07-27', its PA-2 §(g)(17) twin (excluded from this PR by the plan-time limit), and the PA-2 replication row 'the host is still unborn and has no birth route, #6977'. The replication-row sentence is undated and now false (born 2026-09-14 through the ADR-149 route). Recommend a tracking issue for a marker-only sweep; breach-register.md's 2026-09-12 row is a dated historical record and needs nothing."
  - "O4 — Engineering records outside this attestation carry the same count as C1: ADR-149 'Addendum — #8189 (2026-09-15): a fourth, root authority beside item 10's three keys' and ADR-220 D3 'Accounting … a fourth, distinct authority'. Flagged to the lead, not conditioned."
attests:
  - "knowledge-base/legal/article-30-register.md — the eight insertions of PR #8206 ONLY (Hetzner vendor row marker; Cross-Cutting Secrets-management Qualification; PA-36 Scope-note marker; §(g) header marker; §(g)(1) step-name marker; §(g)(5) and §(g)(6) cross-references; §(g)(13))"
does_not_attest:
  - "knowledge-base/engineering/architecture/decisions/ADR-220-*.md and ADR-149-*.md (engineering records; see O4)"
  - "The pre-existing PA-1 §(g)(13), PA-2 §(g)(17) and PA-2 replication-row 'unborn' sentences (see O3)"
  - "docs/legal/** and plugins/soleur/docs/pages/legal/** — untouched by the PR, correctly so"
art_33_triggered: false
art_34_triggered: false
re_evaluation_triggers: "The post-merge replace that delivers the root key (plan AC18) — §(g)(13)'s 'will authenticate … as root, with no forced command' becomes measurable at the AC19 dry run reading role=git-data-auth verdict=ok, and if it instead reads auth_refused because root's authorized_keys carries a cloud-init command= prefix, (13) must be corrected. Also: #8209 closing (the Secrets-management qualification changes); #8211 landing (the (1) marker's future tense resolves); GIT_DATA_STORE_ENABLED flipping or the first repository written (PA-36 Status re-runs, per the #8043 audit). Standing external-counsel triggers: first arms-length workspace owner, any EEA-out owner, any regulated-industry owner."
---

# Counsel review audit — #8189 / PR #8206 (root-key TOM, PA-36)

This file is the load-bearing evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on
PR #8206 (plan brand-survival threshold `single-user incident`). The register diff is the only legal
artifact in the PR. The CLO agent is the v1 attestation authority; the operator holds an optional veto.

## Scope and limit check

- **Additions only.** `git diff origin/main --word-diff=porcelain -- knowledge-base/legal/article-30-register.md`
  yields eight `+` token runs and no `-` token run. Four hunks: the Hetzner vendor row, the Cross-Cutting
  Secrets-management bullet, the PA-36 Scope note, the PA-36 §(g) cell.
- **No Status cell, no PA-2 §(g)(17).** The PA-36 Status cell and both PA-2 rows are byte-identical to
  `origin/main`.
- **MAY-say limits.** §(g)(13) says: root, no forced command, able to bypass (2) and (5)–(8); held in the
  Doppler project `soleur-git-data-root` and the R2 state object, not `prd`; delivered only by a create;
  checked by a committed fingerprint. All within the limits. The limits were a ceiling, not a warrant for
  the count — see C1.
- **MUST-NOT limits.** No expiry, no two-party review, no host-key verification, no host-side revocation,
  nothing on encryption at rest (the §(g)(1) marker renames a step and states the activation rule is
  unchanged). Custody isolation from repo-secret holders is not claimed outright, and the added
  Qualification states the opposite; the word "isolated" in §(g)(13) sits close enough to that claim to
  warrant C2.

## Drift table

| # | Claim added | Checked against (file / anchor) | Verdict |
|---|---|---|---|
| D1 | Vendor row: host born 2026-09-14; PA-36 still declared, not live; store holds no repository | `scripts/encryption-posture-ledger.json` git-data row `live_verification` ("born 2026-09-14 by run 34836141887, re-birthed by run 34861860722"); `workspace-resolver.ts` reads `GIT_DATA_STORE_ENABLED === "true"`; #8171 MERGED 2026-09-14 | **Holds** |
| D2 | Secrets bullet: a repository CI token reads `prd_terraform`, which holds a Doppler workplace token, an R2 token, the Hetzner API token and the GitHub App private key; eviction tracked in #8209 | `git-data-cutover.yml` header (`secrets.DOPPLER_TOKEN` = `prd_terraform` read); `apply-web-platform-infra.yml` secrets comment; `git-data-root-key/variables.tf` (all four resolved from `prd_terraform`, `doppler_token_tf` described as workplace-scope); #8209 OPEN, title names `DOPPLER_TOKEN_TF`, `CF_API_TOKEN_R2`, `GITHUB_APP_PRIVATE_KEY`, `HCLOUD_TOKEN` | **Holds** |
| D3 | Scope-note marker: born through the interlocked route; store empty; future tense stays; "the Status row governs" | As D1; PA-36 Status cell still reads "the host is unborn" | **Holds as to the facts; the pointer lands on a stale sentence → C3** |
| D4 | §(g) header marker: host born; items keep DRAFTED / NOT-YET-ACTIVE | As D1 | **Holds** |
| D5 | §(g)(1) marker: `repoint_luks_mount` deleted with the cutover body; "the repoint is now the real cutover's repoint step (#8211)" | `git-data-cutover.sh` header "WHAT IT NO LONGER DOES … body was deleted"; `grep -c repoint_luks_mount` → 0 (was present on `origin/main`); #8211 OPEN "rebuild the real modes" | **Deletion holds; "is now" asserts a step that does not exist → C4** |
| D6 | §(g)(5)/(13): "a fourth SSH authority" beside the three forced-command keys | `git-data.tf` `resource "hcloud_server" "git_data"` `ssh_keys = concat([hcloud_ssh_key.default.id], …)`; `git_data_root_key_arm` `server_keys` reason (every created host carries EXACTLY {default id, root id}); `cloud-init-git-data.yml` `01-hardening.conf` `PermitRootLogin prohibit-password`; ADR-220 Context wall 3 (the default key's fingerprint matches the operator's personal public key) | **FALSE by omission — the default key is a root login key with no forced command on every create, including the live host → C1** |
| D7 | Root key authenticates as root, no forced command | `git-data-cutover.yml` ssh config `User root` with the fetched key; Hetzner `ssh_keys` carries no `command=` option; `PermitRootLogin prohibit-password` | **Holds as a future-tense statement** (unmeasured until plan AC19; see re-evaluation triggers) |
| D8 | Able to bypass (2) and (5)–(8) | (2) and (8) are wrapper checks, (5) and (6) the `git` map, (7) the hook dir — root is subject to none | **Holds** (and "does not constrain what the key's holder can do" covers the rest) |
| D9 | Private half held in `soleur-git-data-root` and in the R2 state object of the minting root, not in `prd` | `access.tf` `doppler_secret.git_data_root_ssh_private_key` (project `soleur-git-data-root`, config `doppler_environment.git_data_root_prd.slug` = `prd`); `key.tf` `tls_private_key.git_data_root` (private key in state); `main.tf` backend key `web-platform/git-data-root-key/terraform.tfstate`; `git-data.tf` reads only `data "hcloud_ssh_keys"` ids; `github_actions_secret.doppler_token_git_data_root` carries the read token, not the key | **Holds, but "not in the `prd` config" is ambiguous (the project's own config is `prd`) and "isolated" nears a MUST-NOT → C2** |
| D10 | Delivered only by a create of `hcloud_server.git_data` | `git-data.tf` `lifecycle { ignore_changes = [ssh_keys] }` (a live host never receives it); the key appears in no cloud-init template | **Holds for the Terraform path** (O2) |
| D11 | A create is refused unless the key matches a committed fingerprint | `git-data-root-key-arm-gate.sh` `git_data_root_key_arm` (SHA256 derived from `public_key` vs `git-data-root-key.fingerprint`; `fingerprint_file_missing` refuses); called from `git-data-host-birth-gate.sh` and `git-data-host-replace-gate.sh` only | **Holds** (O1: branch-dispatched replace reads its branch's anchor) |
| D12 | §(g)(6): the root authority is not in the `git` map and not constrained by it | `cloud-init-git-data.yml` `/home/git/.ssh/authorized_keys` write_files entry carries only the three forced-command lines; Hetzner keys land on root | **Holds** (pluralised by C1) |

## Findings

- **F1 (C1).** The count. The plan-time limit let §(g)(13) say "a fourth SSH authority", and ADR-149 and
  ADR-220 use the same count, but the code gives a fifth: `hcloud_ssh_key.default` is placed on every
  create next to the root key, has no forced command, and root login accepts keys. It was on the host born
  2026-09-14 before this PR existed and PA-36 has never recorded it. The PR did not create that omission,
  but its new sentence turns silence into a count that a reader will take as complete. A register count
  that the resource block falsifies is the #7349 "eleven processing activities" class. Ruled a correction
  rather than a block: the store is empty, and the fix is additions to text this PR adds.
- **F2 (C2).** Custody wording. "Isolated" is accurate about project scoping (a `soleur` branch-config
  token cannot resolve it) and inaccurate about holders of repo secrets (#8209; ADR-220 D4). The
  qualification that says so sits in the Cross-Cutting section, not beside (13).
- **F3 (C3).** A half-applied supersession. The PR marks "unborn" in the vendor row, the Scope note and the
  §(g) header, but the Scope-note marker hands authority to a Status cell whose words it has just
  superseded, and the header surface list keeps the same dated wording the vendor row now marks. Per
  `2026-09-14-closing-a-limb-by-decision…` the marker goes under every superseded sentence. The Status
  cell stays untouched (plan AC13) because the marker can supersede its words from outside.
- **F4 (C4).** Present tense for an unbuilt step.
- **F5.** No published document must change. The store is empty and no `docs/legal/**` page names the
  git-data host, so the five `docs/legal/**` CI gates are not engaged.

## Conditions

All four edit only text that this PR inserts, or add a marker. None edits a Status cell or PA-2 §(g)(17).
File: `knowledge-base/legal/article-30-register.md`.

**C1 — PA-36 §(g)(13), (5), (6).**

In (13), replace:

> (13) **A fourth SSH authority: root, with no forced command.** Beside the three keys in (5), a dedicated root key (`tls_private_key.git_data_root`) will authenticate to the git-data host as **root, with no forced command**, so it is able to bypass (2) and (5)–(8).

with:

> (13) **Root SSH authorities, with no forced command.** Beside the three keys in (5), a dedicated root key (`tls_private_key.git_data_root`) will authenticate to the git-data host as **root, with no forced command**, so it is able to bypass (2) and (5)–(8). It is not the only root authority: the Hetzner key object `hcloud_ssh_key.default` (the operator's public key, per ADR-220 Context) is also delivered as a root login key, with no forced command, by every create of `hcloud_server.git_data`, including the host born 2026-09-14, and the create gate requires every created host to carry exactly that key and the root key.

In (5), replace:

> A fourth, root authority with no forced command sits outside these three; see (13).

with:

> Two root authorities with no forced command sit outside these three; see (13).

In (6), replace:

> The root authority in (13) is not in this map and is not constrained by it; see (13).

with:

> The root authorities in (13) are not in this map and are not constrained by it; see (13).

**C2 — PA-36 §(g)(13) custody sentence.** Replace:

> Its private half is held in the isolated Doppler project `soleur-git-data-root` and in the R2 state object of the Terraform root that mints it, not in the `prd` config.

with:

> Its private half is held in the separate Doppler project `soleur-git-data-root` (its own `prd` config) and in the R2 state object of the Terraform root that mints it, not in the `soleur` project's `prd` config. That separation does not isolate it from holders of repository-level CI secrets; see the Secrets-management qualification under Cross-Cutting Technical & Organisational Measures (#8209).

**C3 — PA-36 Scope note, and the header surface list.** In the Scope note, replace:

> **[Superseded 2026-09-15 (#8171): the host was born 2026-09-14 through that interlocked route. The store still holds no repository, so the future tense below stays correct and the Status row governs.]**

with:

> **[Superseded 2026-09-15 (#8171): the host was born 2026-09-14 through that interlocked route. The store still holds no repository, so the future tense below stays correct and the Status row's disposition (declared, not live) governs; its words "the host is unborn" are superseded by this marker.]**

In the header surface list ("Surfaces currently in scope under that test"), replace:

> an infrastructure-limb surface whose host is unborn as of 2026-09-11 (PA-36).

with:

> an infrastructure-limb surface whose host is unborn as of 2026-09-11 (PA-36). **[Superseded 2026-09-15 (#8171): the host was born 2026-09-14; the store holds no repository, so the surface stays declared, not live.]**

**C4 — PA-36 §(g)(1) marker.** Replace:

> the repoint is now the real cutover's repoint step (#8211).

with:

> the repoint will be a step of the rebuilt cutover (#8211, open), which does not exist yet.

No other text change is required. O1–O4 are non-blocking.

## Verification commands (re-runnable from the worktree)

- `git diff origin/main --word-diff=porcelain -- knowledge-base/legal/article-30-register.md | grep -c '^-[^-]'` → 0 (additions only).
- `grep -n 'ssh_keys = concat' apps/web-platform/infra/git-data.tf` → the default key plus the label-selected root key (C1).
- `grep -n 'PermitRootLogin' apps/web-platform/infra/cloud-init-git-data.yml` → `prohibit-password` (C1).
- `grep -n 'server_keys' tests/scripts/lib/git-data-root-key-arm-gate.sh` → "exactly {default key id, root key id}" (C1).
- `grep -n 'config  *= doppler_environment.git_data_root_prd.slug' apps/web-platform/infra/git-data-root-key/access.tf` and `grep -n 'slug    = "prd"'` in the same file (C2).
- `grep -rn 'git_data_root_key_arm "' tests/scripts/lib/` → exactly the birth and replace gates (D11).
- `grep -c repoint_luks_mount apps/web-platform/infra/git-data-cutover.sh` → 0 (D5).
- `grep -o 'born 2026-09-14 by run 34836141887' scripts/encryption-posture-ledger.json` → present (D1).
- `gh issue view 8209 --json state` → OPEN; `gh issue view 8211 --json state` → OPEN; `gh pr view 8171 --json state` → MERGED (2026-09-14T20:03Z).

## Lead application record (2026-09-15)

- **C1–C4** were applied verbatim to `knowledge-base/legal/article-30-register.md`. The word-diff against `origin/main` still shows 0 deleted tokens, so the register change remains additions-only.
- **O4:** ADR-149's "Addendum — #8189" and ADR-220 D3 "Accounting" no longer count the root key as a "fourth" authority. Both now name `hcloud_ssh_key.default` as the other root login key. For consistency with C2, the same "isolated" wording was also replaced with "separate" in `git-data-root-key/main.tf`, the cutover runbook, the root-key suite's pass labels, and the PR body. These are engineering records and are not covered by this attestation.
- **O3** is tracked in #8218, a marker-only sweep that gets its own counsel review.
- **O1 and O2** need no change. O1's branch-dispatch anchor is already tracked in #8093.
- The audit is waived as not-a-determination in `scripts/lint-legal-registers.sh` `NOT_TRANSCRIBED` and in the `breach-register.md` waiver table, following the #8043 precedent.
