# Phase 0 measurements - WikiSkill Phase 2 (#10550)

Recorded 2026-10-26 on branch `feat-one-shot-10550-wikiskill-phase-2-new-skill-creation`, rebased on `origin/main`
(the one unrelated infra commit on main did not touch `plugins/soleur/skills`). Every number below came from a command
run in this worktree; where a claim could not be verified here it is listed under "Not verified".

## 0.1 / 0.2 Budget: total, cap, headroom

Scratch script (not committed; calls the same helpers `components.test.ts` calls, skips `disable-model-invocation === true`,
`split(/\s+/).filter(Boolean)`, reads the cap constant by regex from `components.test.ts`):

```text
import { discoverSkills, parseComponent } from "./helpers";
loop over discoverSkills(): parseComponent(p).frontmatter;
  if frontmatter["disable-model-invocation"] === true -> skip;
  total += String(frontmatter.description ?? "").split(/\s+/).filter(Boolean).length
cap = Number(/const SKILL_DESCRIPTION_WORD_BUDGET = (\d+);/.exec(components.test.ts)[1])
```

| Moment | skills | disable-model-invocation | total | cap | headroom |
|---|---|---|---|---|---|
| Before the trims (current tree) | 104 | 8 | 2436 | 2443 | 7 |
| After the five trims | 104 | 8 | 2402 | 2436 | 34 |

Output (before): `{"skills":104,"disableModelInvocation":8,"total":2436,"cap":2443,"headroom":7}`
Output (after):  `{"skills":104,"disableModelInvocation":8,"total":2402,"cap":2436,"headroom":34}`

The plan's quoted facts hold on the current tree: 2436 total, cap 2443, 7 headroom. No sibling merged a new skill, so the
trim set was not re-derived. All five exact "before" description lines (invoice, drain-prs, trigger-cron, reproduce-bug,
docs-site) matched the plan table character for character; the after-state freed exactly 34 words (7+5+4+10+8).

`bash scripts/sync-readme-counts.sh --check`: `67 agents, 4 commands, 104 skills` ... `All component counts are in sync.` rc=0
(no skill added or removed in this PR's commits 1-2, so README counts do not move).

## 0.7 BASELINE_DECLARED_PROBES

`bun test plugins/soleur/test/preflight-discoverability-test.test.ts -t G1` on the tree with only the committed plan: expected 83,
received 84 (rc=1). The plan file itself is the 84th declaring plan, so the ratchet is red until the baseline moves 83 -> 84 in the
same commit that carries the plan's declaration; done in commit 1.

## 0.3 / 0.7(a) Runner-image tool set (command output)

`apps/web-platform/Dockerfile` runner stage: `FROM cli-tools` (which is `FROM node:22-slim@sha256:4f77a690...`), then
`apt-get install ... ca-certificates git bubblewrap socat qpdf jq openssh-client libcap2-bin`, then `curl`, `gh`. No `bun` anywhere
in the Dockerfile (`grep -n "bun\b" apps/web-platform/Dockerfile` = no output).

The real production image (`ghcr.io/jikig-ai/soleur-web-platform:latest`) is not pullable from this host
(`Error response from daemon: error from registry: denied`). Substitute proof: an ephemeral container from the SAME pinned base
digest plus the Dockerfile's own apt package list:

```text
$ docker run --rm --network none node@sha256:4f77a690...   # pinned base alone
node v22.22.1
bash /usr/bin/bash | jq MISSING | sha256sum awk sed grep find mktemp tr timeout present | git MISSING | curl MISSING | bun MISSING

$ docker run ... node@sha256:4f77a690...  (apt-get install the Dockerfile list + curl)
apt_rc=0   node v22.22.1
bash jq sha256sum awk sed grep find mktemp tr timeout git curl: all present (paths under /usr/bin)
bun: MISSING
```

Result: bash, jq, sha256sum, awk, sed, grep, find, mktemp, tr, timeout are all present in an image built from the Dockerfile's
base and apt layer. `bun` is absent.

## 0.7(a) CTO G3: does the unmodified Cursor generator run in the runner image?

`plugins/soleur/scripts/sync-cursor-name-map.ts` has a `#!/usr/bin/env bun` shebang and `import { parse } from "yaml"`.

```text
$ (in the simulated runner container) cp sync-cursor-name-map.ts /tmp && node sync-cursor-name-map.ts --check
Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'yaml' imported from /tmp/sync-cursor-name-map.ts
node_generator_rc=1
```

Bun is absent, and under node the unmodified script cannot resolve `yaml` from a clone path (the clone has no `node_modules`;
`yaml` lives in `/app/node_modules`, which is not an ancestor of the clone). **G3 resolves to: the unmodified generator does NOT
run there. Keep the pure `renderCursorSkillStub` duplicate and the byte-for-byte parity test (Guard 4); do not add bun to the image.**

## 0.4 vitest resolves the generator and `yaml`

`apps/web-platform/package.json` has `yaml ^2.9.0` (dependency) and `vitest ^4.1.11`. Probe in a scratch tree that mimics CI's
`test-webplat` job (only `apps/web-platform/node_modules`, no repo-root `node_modules`):

```text
test("generator import resolves") imports ../../../plugins/soleur/scripts/sync-cursor-name-map and calls cursorSkillName("invoice")
 Test Files  1 passed (1)   Tests  1 passed (1)   rc=0
```

Vite resolves the bare `yaml` import through the vitest project root, so the parity test can import `buildCursorNameMap` (and
`cursorSkillName`) from the script with vitest in `apps/web-platform`. `ci.yml` job `test-webplat` runs `oven-sh/setup-bun` with
`.bun-version` (so (e), bun availability for any parity/dry-render test that shells to bun, holds in the vitest job).

## 0.5 How the existing `input: patterns` model call is bounded

- One `postAnthropicMessage` call in the `cluster` step with `maxTokens: ANTHROPIC_MAX_TOKENS` (16384) and
  `markerSource: "cron-compound-promote"` (per-cron spend attribution); function registration has
  `concurrency: [{scope:"fn",limit:1},{scope:"account",key:'"cron-platform"',limit:1}]` and `retries: 1`.
- `cron-compound-promote` has no `CLAUDE_BUDGET_USD` entry (as the plan says); no entry is invented.
- Manual-fire throttle: none. `apps/web-platform/app/api/internal/trigger-cron/route.ts` and
  `server/routines/run-routine.ts` contain no rate limit, throttle or cooldown (grep for throttl/rate/cooldown/debounce/429 = no
  hits). The only brakes on repeated manual fires are the Inngest concurrency limits above (a replay flood collapses to serial runs)
  and the week-cap (open `self-healing/auto` PRs). `create-propose` therefore binds to: the same `postAnthropicMessage` helper, its
  own `maxTokens` (`CREATE_MAX_TOKENS = 3000`), the same `markerSource`, and one call per run. Worst case is one extra call per
  manual fire.

## 0.7(b) trigger-cron passes `allow_create`

`MANUAL_TRIGGER_EVENTS` is derived from the cron manifest (`cron-compound-promote` is in it, and `routine-metadata.ts` marks it
`manualTrigger: "allowed"`). The route forwards `data` when it is a plain object (only `typeof object` and not array is checked;
"each consuming cron validates its own fields"). So `{input:"patterns", allow_create:true}` passes through unchanged; no route or
schema edit is needed, and the consuming handler must (and per the plan will) validate `allow_create === true` itself.

## 0.7(c) Holders of INNGEST_MANUAL_TRIGGER_SECRET (CTO G1 flip evidence)

Found by `grep -rln INNGEST_MANUAL_TRIGGER_SECRET`:

- Doppler `soleur` project, configs `prd` and `dev` (provisioned by `apps/web-platform/infra/inngest.tf`, `visibility = "masked"`).
- The web-platform server process env (`lib/internal-auth.ts` reads `process.env`).
- Operator and operator-run agent sessions that read it with `doppler secrets get ... --plain` (documented in the `trigger-cron`,
  `ship` and `review` skills, `scripts/arm-checkpoint.sh`, `.claude/hooks/durable-reminder-prefer-inngest.sh`).
- Host-side infra scripts (`inngest-rearm-reminders.sh`, `inngest-wiped-volume-verify.sh`).
- No `.github/workflows/*` file references it.

Reachability from tenant sandboxes: the tenant agent subprocess gets a frozen allowlist environment
(`AGENT_ENV_ALLOWLIST` in `apps/web-platform/server/agent-env.ts`: HOME, PATH, NODE_ENV, LANG, LC_ALL, TERM, USER, SHELL, TMPDIR,
`SOLEUR_BWRAP_SECCOMP_BPF`), which does not contain the secret. The route is an internet-reachable public path but is gated by the
Bearer compare. **Finding: no tenant-facing route and no tenant agent sandbox holds the secret; the holders are the operator
principal (including operator-run agent sessions through Doppler) and platform infrastructure.** That does not trigger the G1
"flag in this PR" flip. Caveat: Doppler project membership and who else can run `doppler secrets get` cannot be read from the
worktree; see "Not verified".

## 0.7(d) Suite registration

- The new bun suite `plugins/soleur/test/purpose-template.test.ts` is picked up by the directory run (`bun test plugins/soleur/`;
  `scripts/test-all.sh` comment: "a bun suite under plugins/soleur/test/ ..., picked up by that directory's run"). No
  registration edit is needed for it.
- `lint-orphan-test-suites.sh` keys on `*.test.sh`; it does not see `.test.ts`. vitest suites under `apps/web-platform/test/**` are
  covered by the `include: ["test/**/*.test.ts"]` glob in `apps/web-platform/vitest.config.ts`. Whether any Phase 3+ suite also
  needs `test/repo-wide-suites.ts` or `scripts/lib/test-affected-paths.sh` registration is a Phase 3-5 check (those files are not
  touched in commits 1-2).

## 0.6 Input-size ceiling (12k tokens) and overlap threshold

Measured with bytes-per-token bounds (no tokenizer helper exists under `apps/web-platform/server`):

```text
{"patternPages":7,"patternPageBytesUpperBound":19303,"skills":104,"skillListBytes":19981,"totalBytes":39284,
 "boundTokensBytesDiv4":9821,"boundTokensBytesDiv3":13095,"ceiling":12000}
```

(pattern-page bytes are the whole files, an upper bound on the rendered index; skill list is `- name: description` for all 104
skills.) Under bytes/4 the input is about 9.8k tokens (about 18% under the ceiling); under a pessimistic bytes/3 it is 13.1k and
would exceed it. The ceiling holds on the documented bytes/4 bound only. Phase 3 should either list only model-visible skills
with names and descriptions, or state the bound it uses, and the input-size gate refuses (never truncates) over the ceiling.
`OVERLAP_REFUSE_THRESHOLD` calibration needs the overlap-ranking function that Phase 3 writes; it is not calibrated here
(the plan itself says "calibrated in Phase 3").

## Not verified in Phase 0 (and why)

1. The real production runner image: the registry denies an anonymous pull. The tool set was proven on the same pinned base
   digest plus the Dockerfile's apt package list, not on the built image.
2. Doppler membership and any non-operator holder of the trigger secret: the Doppler project ACL is not readable from the worktree.
3. `OVERLAP_REFUSE_THRESHOLD`: depends on the Phase 3 ranking function.
4. Exact token count of the create-propose input: only bytes/4 and bytes/3 bounds; no tokenizer is available in this tree.
