# ADR-173 — Execution boundary for plan-declared discoverability probes

- **Status:** accepted
- **Date:** 2026-08-10
- **Related:** #6772 (the folded-scalar fix whose fail-open transition motivated the retired
  denylist); #4148 (the DNS-typo regression Check 10 exists to catch); #1557
  (`enableWeakerNestedSandbox` — the nested-userns `/proc` precedent this adopts);
  #5733 / PR #5848 (bwrap mount-ordering semantics); #2634 (`failIfUnavailable` — the
  never-silently-unsandboxed precedent); #5000 / #5004 (userns-restriction drift class);
  ADR-074 (Stage A / Stage B isolation of untrusted PR-head content)
- **Supersedes:** nothing
- **Issue:** #7393
- **Enforced by:** `plugins/soleur/test/preflight-discoverability-test.test.ts` and
  `plugins/soleur/test/observability-schema-parity.test.ts`, both run by
  `scripts/test-all.sh` (the `bun` shard) and therefore by the required `test` context.

## Context

`/soleur:preflight` Check 10 parses `discoverability_test.command` out of a PR-linked plan
file and **executes it on the operator's workstation**. The plan file is
trust-on-PR-review, not trust-on-execution, and this repository is public — so the command
is attacker-authorable via any pull request.

Until #7393 the only guard was a **denylist** of ten credentialed CLIs (`doppler`, `gh`,
`aws`, `supabase`, `stripe`, `hcloud`, `wrangler`, `terraform`, `flyctl`, `vercel`). The
skill's own text already conceded the denylist could not be complete. #7393 supplied the
motivating case from the other direction: a probe whose verified property has **no
unauthenticated substitute** was rejected outright, with no sanctioned way to say so. The
author's only options were FAIL (verify nothing) or rewrite to a weaker property (verify
the wrong thing).

Three things defeated the invariant the check is supposed to preserve — *a plan author
must not become an execution oracle over the operator's ambient auth*:

1. **The denylist was unbounded-negative.** Ten CLIs enumerated; every future vendor CLI
   permitted by default; indirect invocation (`bash scripts/foo.sh` whose body self-wraps
   `doppler run -c prd`) never covered.
2. **There was no sanctioned path for a legitimately-credentialed probe.**
3. **The control was in the wrong layer entirely.** The probe ran with the whole
   filesystem readable and the worktree writable. Verb filtering in front of an open
   filesystem is not a boundary.

Point 3 is the one measurement settled. The first design proposed an **ephemeral `$HOME`**
and had what looked like decisive evidence: under `HOME=$(mktemp -d)` the Doppler token
read `token_len=0` and `gh api user` returned `DENIED`. That evidence measured *credential
discovery* and was presented as *credential reachability*. An absolute-path read of the
same file returned a live **294-byte** service token regardless of `$HOME`, as did a glob
across `/home/*/…`, as did `awk 'BEGIN{system(…)}'`. `env -i` and an ephemeral `$HOME`
scrub environment **variables**; they do not remove **files or sockets**.

The reachable surface, measured on the workstation: the Doppler CLI's live `dp.ct.*`
token, `~/.ssh` private keys, `~/.netrc`, `~/.aws/credentials`, `~/.docker/config.json`,
and the `/run/user/<uid>/bus` D-Bus socket exposing the Secret Service keyring. A probe
could also write `.git/hooks/pre-commit`, which `/soleur:ship` executes seconds later
**with the operator's real `$HOME`** — turning a few-second credential window into a full
compromise. One operator running `/soleur:ship` on one malicious PR suffices.

## Decision

A probe declared in a plan file executes inside a **filesystem-isolated sandbox**, with no
credential stores bound and the repository read-only. Three layers, in strict priority
order — the ordering is the point, because layers 2 and 3 are not security controls.

### Layer 1 — Authority: a bubblewrap filesystem boundary

`/usr` and `/etc` bound read-only; `/home`, `/root`, `/run` and `/tmp` replaced with
tmpfs; the resolved `/etc/resolv.conf` target rebound; the repository bound **read-only**
and made the working directory; `--unshare-all --share-net --die-with-parent
--new-session`. Measured effect (bubblewrap 0.11.1):

| Probe, inside the sandbox | Result |
| --- | --- |
| absolute-path read of the home Doppler config | `No such file or directory` |
| glob read across `/home/*/…` | `No such file or directory` |
| home SSH private key | `No such file or directory` |
| `ls /run/user/<uid>/bus` (D-Bus → Secret Service) | `No such file or directory` |
| `awk 'BEGIN{system("<absolute-path read>")}'` | `cannot open` |
| append to a tracked repo file | `Read-only file system` |
| `curl https://soleur.ai/` | `200` |
| `dig +short soleur.ai` | resolves |
| `grep -c . AGENTS.md` | matches the host value |

Two operational properties are load-bearing and were both found empirically:

- **`--tmpfs /home` must precede `--ro-bind "$REPO_ROOT"`.** bwrap applies mounts in
  order and this repo lives under `/home`; reversed, the tmpfs silently clobbers the repo
  bind and every probe dies with `Can't chdir` — which reads as a bwrap incompatibility
  rather than an ordering bug. The agent sandbox's module header documents the same
  tmpfs-shadows-earlier-binds semantics (#5733 / PR #5848). Two independent discoveries of
  one rule is why it is written into the skill text and not only into a plan.
- **`--tmpfs /run` breaks DNS on systemd-resolved hosts.** `/etc/resolv.conf` symlinks to
  `/run/systemd/resolve/stub-resolv.conf`; removing the target makes every `curl` probe
  return rc=6 — **indistinguishable from the #4148 DNS-typo regression this check exists
  to catch**. The resolver rebind is mandatory, not hygiene.

**Fail-closed, with no unsandboxed fallback.** If `bwrap` is absent or the sandbox cannot
be established (the `kernel.apparmor_restrict_unprivileged_userns` drift class of
#5000/#5004 — measured `= 1` on this host, with bwrap still functional), Check 10 returns
**SKIP** with a named reason. This mirrors the agent sandbox's `failIfUnavailable: true`
(#2634 — *"without this flag the SDK silently runs unsandboxed… defense-in-depth
disappears with no Sentry signal"*), adapted: the agent path refuses to start, but a
preflight check has no session to refuse, so the honest terminal is SKIP. A degraded
sandbox that silently reverted to the status quo would be **worse than no sandbox**,
because the skill text would then claim a boundary that is not there.

**`--proc /proc` degrades rather than failing.** `/proc` cannot be mounted inside a nested
user namespace, and preflight runs inside exactly such a context on the containerized
one-shot pipeline path. The repo already paid for this lesson: `enableWeakerNestedSandbox`
in `apps/web-platform/server/agent-runner-sandbox-config.ts` (#1557). A hard `--proc`
would fail establishment in every containerized run and — because the design is
fail-closed — **SKIP Check 10 for all of them**, converting a security improvement into a
blanket disablement whose telemetry is indistinguishable from correct operation. The
runtime attempts `--proc /proc`, retries once without it, and only then SKIPs. Measured:
both forms keep every credential store unreachable and both run `curl`, `node`, `python3`
and `grep`, so the weaker form costs nothing the probe classes need.

### Layer 2 — Legibility: a deny-by-default probe-verb allowlist

`curl` · `bash` · `sh` · `grep` · `rg` · `jq` · `python3` · `node` · `bun` · `printf` ·
`git` — eleven verbs, each with ≥2 uses in a measured 632-command corpus of declared
probes. The effective verb is the first whitespace-delimited token of the **dequoted**
command, so `"doppler"` / `\doppler` / `dopp""ler` cannot launder it.

Arg rules close the inline-program equivalents: `bash`/`sh` reject `-c`;
`python3`/`node`/`bun` reject `-c`, `-e`, `-p`, `--eval`, `--print`. `awk`, `sed` and
`find` are **excluded from the allowlist**, measured as execution-equivalent to `bash -c`
(`awk 'BEGIN{system("…")}'` executes arbitrary commands and passes the shell-active-token
reject, which contains no `;`, `&&`, `|` or `$(`). Rejecting `bash -c` while permitting
`awk` would be incoherent.

Program-position paths must be repo-relative — no leading `/`, no `..` segment. This is a
**pure string rule**: no `git ls-files` oracle, so the predicate stays synchronous and
fixture-free. That is also a correctness point, not only a design preference — see
Consequences.

**Every allowlist entry is an authority grant.** Layer 1 bounds what a verb can *reach*,
but `curl` retains network egress and `bash <script>` retains arbitrary in-sandbox code
execution. Adding a verb warrants the scrutiny of an infra change. Conversely, the
allowlist bounds legibility and maintenance, **not** authority — it is the sandbox, not
the verb list, that makes a script self-wrapping `doppler run -c prd` fail loudly instead
of succeeding silently. Neither layer may be described as though it closed the class.

### Layer 3 — Declaration: `credentials_required` → `SKIP-DECLARED`

One optional sub-field of `discoverability_test`, holding `<scope> — <justification>`.
Present and non-placeholder ⇒ Check 10 **skips without executing** (executing under Layer
1 would fail for lack of credentials and say nothing about the property under test).
Absent ⇒ the normal path. Placeholder (`TODO`/`TBD`/`N/A`/…) ⇒ FAIL, via deepen-plan
§4.7's *existing* placeholder machinery rather than a newly-invented gate.

The residual risk is a **gradient, not a possibility**: this is the cheapest path to a
non-FAIL for any probe, for any reason, and in `/soleur:one-shot` the same agent authors
the declaration and runs the gate. Left unwatched it converts Check 10 from a verification
gate into self-certification. Three mechanical counterweights, chosen because prose is not
an enforcement mechanism:

1. Its own terminal, **`SKIP-DECLARED`**, never folded into ordinary `SKIP`, carrying the
   declared scope verbatim into the headless line and the Phase 2 aggregate row.
2. A **committed baseline count** of declaring plans asserted in the suite, so every new
   adoption is a reviewable diff line rather than invisible drift. The count is anchored
   on a *parsed declaration*, not on `grep -c credentials_required:` — the plan that
   introduced the field mentions it five times in prose and declares it zero times, so a
   bare grep would have read as adoption that never happened.
3. A named entry in `observability-coverage-reviewer`'s §Step 6 checklist.

It is a **verification waiver, not an execution bypass**: the declared path never
executes, so no verb reaches the sandbox. The waiver genuinely does span *any* verb, which
is why it is counted rather than reordered.

### Evaluation order

`ssh` reject → `credentials_required` → verb allowlist + arg rules → program-path rule →
shell-active-token reject → sandboxed execute. `ssh` stays first and is **not**
overridable: `hr-observability-as-plan-quality-gate` mandates a no-SSH probe
unconditionally.

## Alternatives Considered

**Do not execute untrusted content at all — adopt ADR-074's Stage A pattern.** The
strongest option on its face, and the one this ADR most owes an answer to. Defeated on
#4148 grounds: Check 10 exists *because* static gates produced "declared-verifiable but
unverified" plans, and a plan that declares a probe nobody ever runs is exactly the
failure mode that shipped a DNS typo. Not executing returns us there. What ADR-074
actually contributes is the **isolation** pattern, which this ADR adopts rather than
rejects: untrusted PR-head content executes only inside an isolation boundary. Check 10
now satisfies that invariant too.

**A probe registry** — the plan names a probe *id* resolving to a script tracked on
`main`, with arguments from a typed schema. Genuinely better long-term: it deletes the
entire parse → dequote → verb-extract → arg-rule surface, and `main`-tracked resolution
fixes the PR-head trust circularity properly rather than working around it. Too large for
this change. Recorded here as the **successor design**, tracked as #7403.

**Ephemeral `$HOME`** — the original design, falsified by measurement (see Context). Kept
on the record as the worked example of a control that changes *lookup* rather than
*reachability*, because the failure was not the idea but the proxy: the evidence for it
was real, decisive-looking, and answered the wrong question.

**Allowlist with no sandbox.** Falsified: `awk 'BEGIN{system(…)}'` and absolute-path reads
defeat it.

**Allowlist plus a static scan of wrapped scripts.** Defeatable by `eval`, dynamic
dispatch, and second-level scripts. A scanner that *reads* complete while being incomplete
is worse than an honest boundary — it is the denylist's defect in a new costume.

**A tracked-path oracle (`git ls-files --error-unmatch`).** Circular: it interrogates the
**PR-head index** — the attacker's own branch — and preflight runs *before* merge.
"Tracked" and "reviewed" are different properties. Only a `main`-anchored lookup
(`git cat-file -e "$(git merge-base origin/main HEAD):<path>"`) would mean the latter, and
that is what the probe registry does properly. Dropped entirely; it bought a false trust
claim, a subprocess inside a pure function, and a `./`-normalisation trap.

**Keep the denylist and extend it.** Unbounded-negative by construction. This is the
defect, not the fix.

**Exclude `bash` entirely.** Hard-blocks 78/632 corpus probes, most of them
uncredentialed, with no workaround.

**A scoped read-only token minted per check.** Per-vendor minting paths, and the token
must live somewhere readable — **reintroducing ambient auth**, which is the thing being
removed. It would also make an advisory local gate into a credential-issuing surface.

**Promote Check 10 to a hard merge gate.** Explicitly one of #7393's own
*re-evaluate-when* triggers, not a decision for this change. It would turn the ~40% of
declared probes that already cannot run into merge blockers overnight.

## Consequences

**Open — network egress remains.** `--share-net` is required (`curl` is the dominant probe
verb, 142/632), so an allowlisted verb can still exfiltrate *repository contents* to an
arbitrary host. The repository is public, which bounds the impact, but it is not zero.
Egress filtering is out of scope here. The agent sandbox's `allowManagedDomainsOnly` is
the precedent to follow if this is closed later.

**Open — the PR-head trust circularity is unresolved.** Both the plan and any script it
invokes are unreviewed at execution time. The sandbox contains the consequences; it does
not make the content trusted. The probe registry's `main`-tracked resolution is the fix,
tracked as #7403.

**Open — AP-020 is still violated by construction.** The principles register's AP-020
(*untrusted input at the agent boundary — never shell-evaluate it*) is not satisfied:
Check 10 shell-evaluates attacker-controlled text, and continues to. The violation is
**accepted within the sandbox**, on the ground that the alternative (a static gate) is the
documented #4148 failure. Recording it here rather than leaving the register silently
contradicted is the point; a future probe registry would resolve it rather than accept it.

**Accepted — ~40% of the corpus's declared probes cannot run today**, for reasons
unrelated to this change: `cd … && …` (97 occurrences) trips the `&&` reject, and `bun` /
`./node_modules/.bin/*` (28) fail rc=127 against the restricted `PATH`. `PATH` is
deliberately **not** widened here — that would be an authority grant inside a change that
narrows authority. What this change buys is that the failure becomes *legible* (a named
reject) instead of an opaque stdout mismatch. Corpus cleanup is tracked separately.

**Accepted — `dig` and `getent` are cut.** #7393 named them as candidate allowlist
entries; they appear **zero** times in the measured corpus. Deny-by-default means the
first author who needs one adds it in a reviewed one-line PR.

**Accepted — Check 10 is disabled on hosts without bubblewrap.** That is the fail-closed
posture working as designed, and it is visible: the SKIP names the sandbox.
