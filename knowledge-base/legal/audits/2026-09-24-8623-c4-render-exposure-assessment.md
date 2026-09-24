---
title: "CLO assessment — prior exposure of the web-platform C4 re-render to tenant-controlled likec4 configuration (#8623)"
type: clo-attestation
date: 2026-09-24
issue: 8623
attestation-authority: clo
status: SIGNED-OFF PROVISIONAL (CLO-agent-attested, Soleur-as-tenant-zero v1, 2026-09-24)
disposition: "REACHABILITY-ONLY — assessment, NOT a presumed breach. Follows the 2026-06-29 REACHABILITY-ONLY precedent and the #8209 prior-exposure record's form. No Art. 33 duty and no Art. 34 duty are recorded on the facts established to date. The two limbs the plan named (L1 flag population, L2 repository scan) were RUN on 2026-09-24 and found NO evidence of use. PROVISIONAL: two further limbs (L3 workspace-resident content at render time, L4 runtime telemetry of the renders) and five named sub-limbs are INCONCLUSIVE and expressly NOT certified clean."
disposition_history: "SIGNED-OFF PROVISIONAL 2026-09-24. L1 and L2 run on 2026-09-24 and completed by 08:35Z, read-only, counts only. L3 and L4 not run; reasons recorded at §L3 and §L4."
signed_off_at: 2026-09-24
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
awareness_anchor: "2026-09-23T16:12:36Z — the filing of #8623 by the #8542 follow-up review audit, which measured config execution on the CLI invocation shape. No monitor surfaced this and none could: a render that executes a config is, to every instrument the platform has, a render."
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — no Art. 33 duty arose on the facts established to date, so nothing fell due 72h from the awareness anchor. Re-opens with a FRESH 72h from awareness of any evidence of use surfaced by a limb below."
open_limbs: "two limbs INCONCLUSIVE and not run: (L3) workspace-resident, untracked content in the tenant worktree at the moment of each render; (L4) runtime telemetry of the renders (Sentry `feature: c4-rerender`, Better Stack `c4_write` lines). Five sub-limbs of the RUN limbs are INCONCLUSIVE with named reasons: L1(e)(i) Flagsmith audit history, L1(e)(ii) edge identity-override history, L1(e)(iii) Doppler env-mirror history, L1(e)(iv) `users.role` history, L2(f) two repositories not readable."
exposure_window: "Opens 2026-06-05T11:41:52Z (Web Platform Release of #4965 complete; the in-place render first reached production). Closes on the first production deploy carrying PR #8687, which has NOT merged at the date of this record. Sub-window A, 2026-06-05T11:41:52Z to 2026-06-16T13:54:22Z: the PUT route checked no flag."
tier_classification: "Tier 1 — an internal assessment record. No public document is edited, no right is narrowed, no processing is added. The mirror/SHA/heading gates are NOT engaged."
semver: "No TC_VERSION bump."
---

# CLO assessment — #8623 prior exposure of the C4 re-render to tenant likec4 configuration

## Verdict — REACHABILITY-ONLY. An Art. 33 **assessment**, not a presumed breach. PROVISIONAL.

The facts established to date do not establish a personal-data breach under Art. 4(12). They
record no Art. 33 (supervisory authority) and no Art. 34 (data-subject) notification duty. **No
evidence of use was found.** Both limbs the plan named were run on 2026-09-24:

- **L1**, the flag population, was run.
- **L2**, the repository scan, was run and, from the same data, a census of the renders that
  actually ran on tenant content.

The assessment is nonetheless **PROVISIONAL**. Two limbs (L3, L4) and five sub-limbs are
**INCONCLUSIVE** and expressly **not certified clean**. The reasons are given where each limb is
recorded.

This record follows the **REACHABILITY-ONLY precedent** of
`knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md` and
the form of `knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md`. It applies the
standing rule that **reachability alone does not start the Art. 33 clock.**

Two points on which it departs from the #8209 record are recorded rather than left to be inferred:

1. **What bounds this matter.** In #8209 the reachable class was the only bound, because no limb
   had been run. Here the class is bounded and so is the **actual use of the path**. The
   render-invocation census (§L2(e)) shows that server-side renders of tenant content happened
   **at least 2 and at most 3 times**, all in one third-party repository, all inside sub-window A.
   The committed diagrams tree of that repository carried **no config, no symlink and no gitlink**
   at any commit that touched it.
2. **The exploitation precondition.** It is **not absent**, as it was in the 2026-06-29 matter. It
   is an **act by the tenant or by an agent in the tenant's workspace**: placing a config file
   where the render will read it. The repository limb looks for exactly that act and did not
   find it in any readable repository.

**A correction to the premise this assessment was commissioned on.** The brief said the path was
reachable "only where a user had `c4-visualizer` enabled with a connected repo, or the `c4-edit`
flag". That is true only from 2026-06-16T13:54:22Z. Before that, `PUT /api/kb/c4/[...path]`
checked **no flag**. The route as merged in #4965 and #4967 goes from
`authenticateAndResolveKbPath` straight to `writeC4Diagram`. The `c4-edit` gate arrived with
#5416 (merged 2026-06-16T13:43:05Z; Web Platform Release complete 2026-06-16T13:54:22Z). For
those eleven days the reachable class was **every authenticated account with a ready workspace
and a connected repository**. §The reachable class and §L1(d) are scoped accordingly.

## The fact pattern

`apps/web-platform/server/c4-render.ts` (`runLikeC4`) spawned the pinned `likec4@1.50.0` CLI with
`cwd` set to the tenant workspace's `knowledge-base/engineering/architecture/diagrams/` directory.
It did so after every `.c4` save through `writeC4Diagram` (`apps/web-platform/server/c4-writer.ts`),
following the save's Contents API commit and the workspace sync.

The plan measured the pinned binary with the server's argv and env shape
(`knowledge-base/project/plans/2026-09-24-fix-c4-render-tenant-likec4-config-execution-plan.md`,
§Measurement). What likec4 does with the directory it is given:

- A `likec4.config.{js,cjs,mjs,ts,cts,mts}` in the directory or a subdirectory **executes**.
- `.likec4rc`, `.likec4.config.json` and `likec4.config.json` are honoured, and their
  `include.paths` pull sources from outside the directory.
- Symlinked files and directories are followed.

ADR-050's 2026-09-24 amendment records the correction to that ADR's SECURITY framing.

The child runs as the app container's `soleur` user. What a config executing in it could reach,
had it ever executed:

| Reach | Why | Personal data behind it |
|---|---|---|
| The web-platform server's process environment | a same-uid child can read `/proc/<ppid>/environ`; the child's own env allow-list does not prevent that | none directly. It holds the platform's production secrets, among them `SUPABASE_SERVICE_ROLE_KEY` (read in `server/dsar-export.ts`) and `GITHUB_APP_PRIVATE_KEY` (read in `server/github-app.ts`), which reach every tenant's rows and every installed repository |
| Other tenants' checkouts under `/workspaces` | same uid, bind-mounted into the app container | Art. 30 **PA-2** (workspace files on the serving web host) |
| Another directory's `.c4` sources, pulled into a model the server then commits to the requesting tenant's repository | `include.paths` and symlinks | repository content of another tenant, disclosed to the requesting tenant |

As in the #8209 and 2026-06-29 records, severity is non-trivial had access occurred. The work is
done by the **likelihood** prong, which is now partly **measured** rather than inferred.

## The exposure window

- **Opens** 2026-06-05T11:41:52Z, when the Web Platform Release run for #4965 completed. That
  commit introduced `c4-render.ts` and the in-place spawn. The Concierge `edit_c4_diagram` tool
  (#4926, released 2026-06-04T10:03:58Z) and the PUT route (#4883) existed a day earlier but did
  not render. `likec4@1.50.0` has been the only pin in `apps/web-platform/Dockerfile` since that
  commit, so the measured behaviour applies to the whole window.
- **Closes** on the first production deploy carrying PR #8687. That PR removes the workspace from
  the render's input (`renderC4Model(stage)` takes no workspace path; `stageCommittedC4Sources`
  materialises only regular-file `.c4`/`.likec4`/`.like-c4` blobs fetched from GitHub). **PR #8687
  had not merged at the date of this record**, and the window is open until that deploy.
- **Sub-window A**, 2026-06-05T11:41:52Z to 2026-06-16T13:54:22Z: the PUT route checked no flag.
- **Sub-window B**, 2026-06-16T13:54:22Z to the close: the PUT route is gated on `c4-edit`, and the
  Concierge path on `c4-visualizer`.

## The reachable class, stated precisely

Triggering a render needs a successful `.c4` save through one of two entry points. Each needs an
authenticated account with a ready workspace and a repository connected through the soleur-ai
GitHub App:

1. **`PUT /api/kb/c4/[...path]`.**
   - In sub-window A: **every such account**, with no flag.
   - In sub-window B: only identities for which `c4-edit` resolves ON. It resolves ON for no one.
     No Flagsmith feature named `c4-edit` exists. The installed SDK (`flagsmith-nodejs` 8.1.0,
     `Flags.getFlag`) returns `enabled: false` for an absent feature. The env-fallback mirror
     `FLAG_C4_EDIT` is unset in Doppler `dev` and `prd` today.
2. **The Concierge `edit_c4_diagram` tool.** Built only when `resolveC4FlagEnabled` returns true
   for `c4-visualizer` (`apps/web-platform/server/resolve-c4-eligible.ts`). In `prd` that resolves
   ON only for the `role == dev` trait cohort (§L1).

**Supplying the config** is a separate act from triggering the render. It could be:

- a commit to the tenant's own repository, which reaches the worktree through `syncWorkspace`'s
  `git pull --ff-only`; or
- a file written into the worktree by the tenant's agent, which runs with
  `allowWrite: [workspacePath]` in its sandbox. A prompt injection carried in content the agent
  reads could direct that write.

The first leaves a trace in the repository, which L2 reads. The second leaves no trace outside the
worktree, and L3 is the limb that would read it.

The class is therefore **not** "the public" and **not** "any GitHub account". It is a platform
account holder with a connected repository: any such account in sub-window A, and only the
`role == dev` cohort in sub-window B.

## Evidence discipline — load-bearing

- **Read-only.** No limb writes to Flagsmith, Doppler, Supabase or any repository. Flagsmith and
  Doppler were read with the management key and `doppler secrets get` exactly as
  `plugins/soleur/skills/flag-list/scripts/list.sh` reads them. Supabase was read with `HEAD`
  requests carrying `Prefer: count=exact`, which return a `Content-Range` count and **no rows**.
  The one exception reads `workspaces.repo_url` into process memory to compute a coverage figure.
  It prints counts and booleans and never a URL.
- **GitHub App tokens were minted least-privilege.** Each installation access token was requested
  with `{"permissions": {"contents": "read", "metadata": "read"}}`, which narrows it below the
  installation's own grant. Tokens and the App JWT lived in process memory for their one-hour
  life. None was written to disk or printed.
- **Counts only, under anonymous indices.** No user id, email, org, installation id, repository
  name, path, author or commit sha of a tenant is recorded here. `jikig-ai/soleur`, the operator's
  own public repository, is the one repository named.
- **Processing basis for the scan itself.** Reading tree modes, paths and commit metadata of
  tenant repositories is processing done through the App's access, for the security of the
  service (Art. 32). It also serves the processor's duty to assist controllers with Art. 32-34
  (Art. 28(3)(f)). It was minimised to one directory per repository, and nothing it read is
  retained beyond the counts below.
- **No instrument's zero is read as clean until the instrument has been shown to see a positive.**
  The controls are recorded beside each result (the ADR-197 error named in the 2026-09-03
  addendum to the 2026-06-29 precedent).

## L1 — the flag population (RUN 2026-09-24)

### L1(a) — `c4-visualizer` in Flagsmith

```bash
bash plugins/soleur/skills/flag-list/scripts/list.sh --json    # read-only; flags c4-visualizer, c4-edit
# plus, with the same management key:
GET /api/v1/projects/39082/features/<c4-visualizer>/                         # created, default_enabled
GET /api/v1/environments/<env id>/features/<c4-visualizer>/versions/         # v2 versioning history
GET /api/v1/environments/<env id>/features/<c4-visualizer>/versions/<v>/featurestates/
GET /api/v1/projects/39082/segments/                                         # role-dev rule
GET /api/v1/environments/<env key>/edge-identity-overrides?feature=<c4-visualizer>
GET /api/v1/environments/<env key>/edge-identities/                          # identifier SHAPES only
```

Findings:

- The feature was created 2026-06-04T07:33Z.
- The project uses v2 feature versioning. **Production and Development each carry exactly one
  version**, published 2026-06-04T07:42Z. Its states are: environment default **OFF**, and the
  `role-dev` segment override **ON**. So the targeting has **not changed** since before the window
  opened.
- The `role-dev` segment's rule is `role EQUAL dev`.
- **Zero** edge identity overrides for the feature, in either environment.
- Flagsmith identities are **role cohorts, not persons**. `fetchRuntimeFlagsFromFlagsmith` keys
  the identity `role:<role>`, or `org:<orgId>:<role>` when an org is bound, with the trait
  `role`. The Concierge path passes `orgId: null`.
- The Production environment holds 4 edge identities. By shape: 1 `role:dev`, 1 `role:prd`,
  1 org-scoped `prd`, and 1 other.

### L1(b) — `c4-edit` in Flagsmith

- There is **no Flagsmith feature** named `c4-edit`. A feature search for `c4` returns only
  `c4-visualizer`.
- An absent feature resolves `enabled: false` (§The reachable class).

### L1(c) — the env-fallback mirrors

- `FLAG_C4_VISUALIZER` and `FLAG_C4_EDIT` are **unset** in Doppler `dev` and `prd` today.
  `apps/web-platform/.env.example` carries both as `0`.
- The fallback is read only when Flagsmith is unreachable. Unset, it can only deny.

### L1(d) — natural persons behind the cohort (Supabase `prd`, counts only)

| Measure (state at 2026-09-24) | Count |
|---|---|
| accounts (`users`) | 17 |
| accounts with `role = dev` | 4 |
| `role = dev` accounts with a repository-connected workspace | 3 (5 account-workspace pairs, over 3 distinct repositories: 2 operator-owned, 1 third-party) |
| workspaces with a connected repository | 6, over 5 distinct repositories |
| of those, workspaces created before 2026-06-17 (the proxy for sub-window A) | 5 |

The sub-window A figure is a **current-state proxy**. A workspace deleted since then is not
counted by it. That gap is covered from the repository side by L2, which scans every repository
visible to any installation, not only the connected ones.

### L1(e) — sub-limbs that could not answer (INCONCLUSIVE)

- **(i) Flagsmith audit history.** `GET /api/v1/projects/39082/audit/` answered 200 with
  `count: 0`. That is impossible for a project whose features were demonstrably created and
  flipped, so the instrument cannot answer and the zero is not evidence. The organisation-level
  `/api/v1/audit/` answered 500. The v2 version history in L1(a) is what carries the "unchanged
  since 2026-06-04" finding. It covers the feature's environment and segment states only.
- **(ii) Edge identity-override history.** Overrides are not versioned. The zero in L1(a) is a
  present-tense reading. It does not prove that no override was ever set and later removed.
- **(iii) Doppler env-mirror history.** `doppler configs logs -p soleur -c prd` returned 71
  entries, the oldest dated 2026-06-30. Its diffs carry **no secret names**: zero `FLAG_` tokens
  in all 71. So it cannot say whether either mirror was ever set. It also does not reach back to
  sub-window A.
- **(iv) `users.role` history.** The column carries no history. The L1(d) counts are today's
  state. An account that was `role = dev` during the window and has since been changed would not
  appear.

## L2 — the GitHub App repository scan (RUN 2026-09-24)

### L2(a) — scope and coverage

- The App holds **3 installations**: 1 operator-owned and 2 third-party. They list **33
  repositories** (12 operator-owned, 21 third-party). 5 are empty (no commits) and have nothing to
  scan.
- **Coverage of connected repositories:** of the **5** distinct repositories connected to a
  workspace today, **4** are visible to an installation and were scanned. The fifth is at L2(f).
- The scan reads **true tree modes** from the Git Trees API, never the Contents API. The Contents
  API lists symlinks and submodules as `"file"` (plan, §GitHub API shapes). It walks the tree from
  the root through `knowledge-base`, `engineering` and `architecture` to `diagrams`, recording
  whether any of those segments is a symlink (mode `120000`) or a gitlink (`160000`). It then lists
  the `diagrams` subtree recursively and counts, by basename, each of the 9 config names:

  ```text
  .likec4rc  .likec4.config.json  likec4.config.json
  likec4.config.{js,cjs,mjs,ts,cts,mts}
  ```

  It also counts mode-`120000` and mode-`160000` entries, and flags a truncated listing.

```bash
# Shapes of the calls, per installation token (contents:read + metadata:read):
GET /installation/repositories
GET /repos/{o}/{r}/branches/{default}                       # root tree sha
GET /repos/{o}/{r}/git/trees/{sha}                          # walk root → diagrams, true modes
GET /repos/{o}/{r}/git/trees/{diagrams sha}?recursive=1     # the subtree
GET /repos/{o}/{r}/commits?sha={default}&path=knowledge-base/engineering/architecture/diagrams/{name}   # x9 names
GET /repos/{o}/{r}/commits?sha={default}&path=knowledge-base/engineering/architecture/diagrams         # every commit touching the dir
GET /repos/{o}/{r}/commits?sha={default}&path={each ancestor}                                           # ancestor replaced by a link
GET /repos/{o}/{r}/branches                                 # every branch tip
```

### L2(b) — HEAD of the default branch

- The `diagrams` directory is present in **3** repositories: 2 operator-owned, one of which is
  `jikig-ai/soleur`, and 1 third-party.
- **0** config files, **0** symlinks and **0** gitlinks. No listing was truncated.
- In no repository is `diagrams` or any of its ancestors a symlink or a gitlink.

### L2(c) — default-branch history

Through the API, for the 26 non-empty repositories other than `jikig-ai/soleur` that could be read:

- The **9 per-name `path=` queries** returned **0** commits in total.
- **10 commits** touch the `diagrams` directory: 8 in the one third-party repository that has it,
  and 2 in an operator-owned repository. Every one of them was walked by true modes. **0** carry a
  config, **0** a symlink, **0** a gitlink, and **0** replace the directory with a link. 0 were
  unresolvable and 0 truncated.
- **30 further commits** touch only an ancestor path. **0** of them turn the directory or an
  ancestor into a link.

For `jikig-ai/soleur`, the scan used the local clone across **all 7,411 refs**:

- **625** commits touch the directory.
- **0** config paths were ever committed there.
- **0** symlink or gitlink entries were ever added or modified under it.
- The directory and its ancestors were never a link.

### L2(d) — every branch tip

A workspace clones the default branch, but an agent session can leave the worktree on another
branch. So the tip of **every branch** of every readable repository was walked the same way. That
is 123 branch tips: 11 across the operator-owned repositories other than `jikig-ai/soleur` (which
is covered at all refs by L2(c)), and 112 across 20 third-party repositories.

- The `diagrams` directory is present at 2 tips.
- **0** config files, **0** symlinks and **0** gitlinks.

### L2(e) — render-invocation census (from the same scan)

`writeC4Diagram` commits every save through the Contents API before it syncs and renders. It
renders only for a `.c4` path, only after that commit and the sync succeed, and commits a
regenerated model only when the render succeeds. Both commits carry fixed messages that have not
changed since #4965 (`Update <file> via Soleur diagram editor`,
`Re-render model.likec4.json via Soleur diagram editor`). Both are attributed to the App's bot
account. So App-attributed commits carrying those messages **bound the renders**:

- save commits bound them from **above**, since a `.md` view-embed save commits but does not
  render; and
- re-render commits bound them from **below**.

| Repositories (default branch) | Save commits | Re-render commits | Inside the window | After 2026-06-16T13:54:22Z |
|---|---|---|---|---|
| third-party (18 read) | 3 | 2 | 3 (1 save, 2 re-renders), all in **one** repository | **0** |
| operator-owned (8 read through the API) | 2 | 0 | **0** (both saves predate the render's release) | **0** |
| `jikig-ai/soleur` (local, all refs) | 0 | 0 | 0 | 0 |

**Reading.** The only server-side renders of tenant content that GitHub evidences are **at least 2
and at most 3**, in one third-party repository, all inside sub-window A. The committed `diagrams`
tree of that repository was clean at **every** commit that touched it (L2(c)). Neither entry
point has produced an App-attributed save on any readable repository since the `c4-edit` gate
deployed.

### L2(f) — repositories that could not be read (INCONCLUSIVE)

- **One connected repository is not visible to any installation.** Its owner has no installation
  today, and an unauthenticated read returns 404 (private or deleted). Its only workspace belongs
  to an account whose role is not `dev` and was created 2026-06-17, after sub-window A closed. On
  L1's data it was therefore never in the reachable class: `c4-edit` is OFF for everyone, and
  `c4-visualizer` is OFF for a non-`dev` role. That conclusion inherits L1(e)(iv): role history is
  not recorded.
- **One third-party repository is listed by its installation and returns 404** by name and by id.
  The installation is not suspended and holds `contents: write`. It is connected to no current
  workspace. Neither HEAD nor history could be read.

### L2 controls — the zeros are not an instrument that cannot see

- **Operator repository, local instrument.** Over the same history, the mode filter finds **23**
  symlink or gitlink entries elsewhere in the repository, and the path filter finds **517** `.c4`
  paths in the directory.
- **API instrument.** A synthetic tree fed to the same classifier was used as a control. It held
  a nested `likec4.config.mjs`, a `.likec4rc`, a symlinked `.c4` and a gitlink. It reported 2
  configs, 1 symlink and 1 gitlink. A `diagrams` entry of mode `120000` was reported as a link at
  depth 3.
- **Live reads.** The same walk read 3 real `diagrams` subtrees with non-zero source counts.

## L3 — workspace-resident content at render time (NOT RUN, INCONCLUSIVE)

Each render read the worktree, not the commit. An untracked config placed there by the tenant's
agent would leave no trace in any repository, so L2 cannot see it.

The only surface that could show it is the `/workspaces` volume on the web host. It is not
readable without host access, and this record does not take an SSH route
(`hr-no-ssh-fallback-in-runbooks`). Even with access, the worktree today is not the worktree at
the 2-3 renders of sub-window A. **Not run; INCONCLUSIVE; not expected to be recoverable.**

What bounds it is L2(e): the question is confined to the 2-3 renders in one workspace in
sub-window A.

## L4 — runtime telemetry of the renders (NOT RUN, INCONCLUSIVE)

`rerenderAndCommit` mirrors a failed render to Sentry (`feature: c4-rerender`). `writeC4Diagram`
logs `event: c4_write` to the log pipeline. Neither records what a child process did beyond its
exit and stderr. Both would at most corroborate the L2(e) census.

**Not run.** Whether any event from sub-window A is still retained in either sink was **not
established**, and this record does not assert that it has or has not expired.

## Findings

| Limb | Status | Coverage verdict (the surface actually queried) | Result |
|---|---|---|---|
| L1(a)-(c) flag state | RUN 2026-09-24 | Flagsmith v2 version history of `c4-visualizer` (both environments), present-tense overrides, feature list, Doppler `dev`/`prd` values | `c4-visualizer` ON only for `role == dev`, unchanged since 2026-06-04T07:42Z. 0 identity overrides. `c4-edit` OFF for all. |
| L1(d) persons | RUN 2026-09-24 | Supabase `prd` counts, present state | 17 accounts; 4 `role = dev`; 3 of them with a connected repository (3 distinct repositories, 1 third-party). 5 connected repositories overall. |
| L1(e)(i)-(iv) | INCONCLUSIVE | audit log zero on a mutated project; overrides unversioned; Doppler log nameless and from 2026-06-30; role unversioned | not certified clean |
| L2(b)-(d) repository scan | RUN 2026-09-24 | 3 installations, 33 repositories, 32 readable (27 of them non-empty), default-branch HEAD and history, every branch tip; `jikig-ai/soleur` at all refs | **0** configs, **0** symlinks, **0** gitlinks, **0** link-replaced directories, at every point read |
| L2(e) render census | RUN 2026-09-24 | App-attributed writer commits, default branch | 2 to 3 renders of tenant content, 1 third-party repository, all in sub-window A, over clean committed trees. None after the gate. |
| L2(f) | INCONCLUSIVE | 1 connected repository with no installation; 1 listed repository returning 404 | not read. The first sits outside the reachable class on current role data. |
| L3 worktree content | NOT RUN, INCONCLUSIVE | none | not expected to be recoverable; bounded by L2(e) |
| L4 telemetry | NOT RUN, INCONCLUSIVE | none | retention not established |

**Evidence of use: none found.** No Art. 33 clock starts, and no rotation is triggered by this
record.

## If the finding flips

A limb flips if it surfaces any of these:

- a config, a symlink or a gitlink in a tenant's diagrams tree at a point a render read it;
- an untracked config in a worktree;
- telemetry of a render child doing anything but parse.

On a flip:

1. **A FRESH 72h Art. 33(1) clock** starts from awareness of that evidence. It does not run from
   the 2026-09-23 anchor.
2. **Every secret the server process held is rotated**, each with its own negative probe
   (`401` or verify-failure on the old value). A config executing in the child could read the
   parent's environment, so rotation is what makes a past read stop mattering.
3. **Art. 33(2) processor notification** goes to each affected controller (the tenant whose
   repository content, or whose checkout under `/workspaces`, was reachable). Jikigai acts as
   processor toward them for that content, and the Art. 33(2) duty is not conditioned on the
   Art. 33(1) risk threshold.
4. **Art. 34 is re-run, not inherited.** It requires *high* risk, and it is assessed on the facts
   of the flipped limb.

## Conditions / residual actions

- **REQUIRED — the window closes on the production deploy carrying PR #8687**, not on its merge.
  This record's window end fires on that deploy. If PR #8687 closes unmerged, the window remains
  open and this record must be addended.
- **REQUIRED — the disposition is not final while L3, L4 or any L1(e)/L2(f) sub-limb is
  INCONCLUSIVE.** A later reading is added as a dated addendum. L3 is expected to stay
  INCONCLUSIVE. If it is closed, it is closed **by decision**, and the "inconclusive?" axis keeps
  its value (the `breach-register.md` 2026-09-03 row precedent).
- **DECIDED, NOT REQUIRED — precautionary rotation of the server's secrets.** No limb shows use.
  The path ran 2-3 times on content whose committed tree held no config. Rotation is required
  only on a flip. The operator may elect it.
- **PROCESS — no advisory to users.** Art. 34 is not engaged. The fix is server-side, and users
  have nothing to patch. The public issue and PR #8687 carry no working exploit (a harmless
  sentinel only), and the PR body should say "not known to have been exploited; assessment
  recorded" with a pointer here. The sibling `git pull` surface (plan Phase 5.4), if measured
  open, goes to a **private** GitHub Security Advisory and not to a public issue.
- **PROCESS — register cross-reference.** This assessment is indexed at
  `knowledge-base/legal/breach-register.md`. That index is a pointer, not a copy. This file is the
  canonical record.

## Amendment convention

This record is **append-only**. A later limb result, a changed disposition or a correction is
added as a dated addendum below, citing the text it annotates and amending nothing above it. That
is the 2026-06-29 precedent's convention.
