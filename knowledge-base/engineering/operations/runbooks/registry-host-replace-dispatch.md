---
title: "registry-host-replace dispatcher — verdicts, trackers, re-fire"
category: runbook
tags: [registry, zot, cloud-init, dispatcher, delivery]
---

# registry-host-replace dispatcher

`.github/workflows/registry-host-replace-dispatch.yml` delivers a merged
`apps/web-platform/infra/cloud-init-registry.yml` change by firing `registry-host-replace`
(#7555, ADR-169 amendment 2026-08-16). Since #8279 it derives WHICH change a run delivers
(`scripts/registry-delivery-change.sh`) and records each run's verdict where that change is
tracked: the delivering PR(s), and/or a `tracker` you name on a re-fire, or — when nothing is
derivable — one open owner issue carrying `action-required`.

## What the gate delivers (#7582)

On a push, the gate decides on the **rendered** user_data, not the template: it renders
`registry-userdata-budget.sh` at the delivery watermark and at the head (the head's script on
both sides) and compares the bytes. It wakes on `cloud-init-registry.yml`, `zot-registry.tf`
and `variables.tf`. A zot digest bump alone delivers; a comment-only or `terraform fmt`-only edit,
or an unrelated `variables.tf` edit, does not. What the offline render must stub is compared
directly: `registry_server_type`, `registry_location` and `registry_volume_size` by value (an
unreadable value, or an arm64 `cax*` type, delivers), and in `zot-registry.tf` the user_data
map/wrapper, the derivation locals, and the `hcloud_server`/`hcloud_volume`/`doppler_service_token`/
`betteruptime_heartbeat`/`random_password.zot_*` registry blocks as comment-stripped text.
Reproduce the render it compares:

```bash
bash apps/web-platform/infra/registry-userdata-budget.sh --json /tmp/head-render.yml
```

A `gate-failed` verdict can now also mean: a watermark revision could not be read (3 attempts),
or the head render is unmeasurable or over Hetzner's 32,768 B cap — the gate's `::error::` says
which. These refusals apply on the push arm; a manual re-fire delivers without rendering. A
delivery decided by a non-template input names what the gate measured in its `Delivering:` line.

**What it still cannot see:** a render input moved out of the three watched files (a new local in
another `.tf`, a renamed template), the live Hetzner catalog's memory for the server type, and a
terraform/provider version change that alters `templatefile` output. A change of that kind is
delivered by a manual re-fire.

## Re-fire after a refusal

```bash
gh workflow run registry-host-replace-dispatch.yml -f reason='<why>' -f tracker=<issue-or-PR number>
```

`tracker` is optional, digits only (a leading `#` and whitespace are stripped). On a manual
re-fire the range from the last successful run is re-derived; when that range cannot be proven
(no watermark, a force-push, a compare failure) the verdict goes to your `tracker` (or the owner
issue) only — never to whatever PR `main` happens to be at.

## Reading a verdict

Every verdict body ends with a machine marker; the latest one for PR or issue `N`:

```bash
gh api --paginate --slurp "repos/jikig-ai/soleur/issues/N/comments?per_page=100" \
  | jq -r '[.[][] | select(.body | test("<!-- registry-delivery run=[0-9]+ kind=[a-z-]+"))] | last
           | if . == null then "no verdict" else {run: (.body|capture("run=(?<r>[0-9]+)").r), kind: (.body|capture("kind=(?<k>[a-z-]+)").k), at: .created_at, url: .html_url} end'
```

| `kind` | Meaning | Next action |
|---|---|---|
| `refused` | the read-only preflight declined (its own `::error::` names the predicate) | resolve the predicate (P1 local-cache pulls / P5 log channel / P6 boot asset, see § zot boot image), re-fire |
| `dispatch-failed` | `gh workflow run` exited non-zero; an apply MAY still have queued | read `apply-web-platform-infra.yml`'s run list before re-firing (double-replace hazard) |
| `apply-failed` | the replace RAN and did not conclude success; the host may be dark, the volume is preserved | read the apply step's `recovery-read` block first (#9510): it re-fetches stock for every planned create, names the post-failure `class=` per address and whether the address is absent or tainted in state; then re-dispatch `registry-host-replace` per that block |
| `unverified` | the apply's conclusion could not be read in the poll window (job stayed green) | read the apply run; the delivering change's follow-through is the authority |
| `cancelled` | the job hit its ceiling; a replace may be in flight | read the run before re-firing |
| `gate-failed` | the delta gate could not classify the diff (compare API), or the head render is unmeasurable / over the 32,768 B cap (#7582) | read the gate's `::error::`, fix, re-fire |
| `undetermined` | no step failed yet the job did not succeed (a checkout failure) | read the run |

The body's `Delivering:` line names the change(s); `(attribution unproven: …)` means the range
could not be proven and the named PR is the degraded `github.sha` guess.

## zot boot image (#8714)

Since #8714 step 5.3b-iii the registry host boots zot from a pinned GitHub release asset, not
from ghcr.io. It denies ghcr.io by name resolution on its first boot. The mechanism is described
in ADR-096's amendment of 2026-09-28 (part 2). Each boot records a verdict. The
`SOLEUR_ZOT_DISK` heartbeat ships it as `zot_image_fetch`, next to `zot_image_digest` and
`ghcr_blocked`:

```bash
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2h --grep SOLEUR_ZOT_DISK --limit 5
```

| `zot_image_fetch` | Meaning | Action |
|---|---|---|
| `ok` | the asset matched T, its manifest is D and names C, it loaded, and its image ID is C or D; zot runs by that ID | none. Expect `zot_image_digest=<D12>` and `ghcr_blocked=1` |
| `fetching` | the fetch is still inside its bounded retry window (at most ~35 min) | wait for the next row |
| `not_run` | the state file is absent: the fetch never ran on this instance | read the replace run's apply log. A host that predates the change reports this until its next replace |
| `download_failed` | curl gave up (retries bounded in total); `zot_image_fetch_rc` is curl's exit code (22 = HTTP error such as 404, 6/7/28/35 = DNS/connect/timeout/TLS) | on 22, run P6 (`bash scripts/registry-replace-preflight.sh --check-asset`). Otherwise re-fire the replace (step 1 below) |
| `sha_mismatch` / `manifest_mismatch` | the downloaded bytes are not T, or its manifest is not D naming C; nothing was loaded | the pins and the asset disagree. Revert the PR that moved them (step 3) |
| `docker_unavailable` | docker never answered within 60 s | re-fire the replace (step 1) |
| `load_failed` | `docker load` failed or timed out (rc in `zot_image_fetch_rc`), or the loaded ref was not inspectable | re-fire once (step 1). If it recurs, revert (step 3) |
| `id_mismatch` | it loaded as an image that is neither C nor D (the refused image is removed) | the host's docker disagrees with the pins. Revert (step 3) |
| `record_failed` / `config_invalid` | the host could not write its state, or `/etc/default/zot-image` is malformed (a template or render defect) | revert the PR that changed it (step 3) |

In every refusal zot never starts. The zot liveness heartbeat goes absent, which is the page, and
`state_status=unknown` follows. Running web containers keep serving; deploys wait.

**Recovery, all workflow-only (no SSH):**

1. **Re-fire the replace.** Use this for a transient failure. Run
   `gh workflow run registry-host-replace-dispatch.yml -f reason='zot boot asset fetch retry'`.
   This manual arm skips P1, which a dark registry itself trips (deploys fall back to local-cache).
2. **A missing asset for a NEW pin.** Publish it: `gh workflow run zot-image-mirror.yml --ref
   <branch>`. It rebuilds from upstream D reproducibly; P6 goes green once the digest equals T.
   A release that WAS published and has since been deleted **cannot** be re-created under the same
   tag, because this repo's releases are immutable. For that case use step 3.
3. **Revert the PR.** Revert the PR that introduced or moved the pins. The dispatcher sees the
   rendered `user_data` change and replaces the host back onto the previous render. If its push-arm
   run is refused on P1 (deploys fell back to local-cache during the outage), re-fire it through the
   manual arm (step 1), which skips P1.
4. **zot dark for more than 24 hours.** P5 then finds no container-log rows and refuses even the
   manual arm. First confirm the asset with `--check-asset`, then run the replace directly:
   `gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace -f reason='<why>'`.
   That job runs P6 (`--check-asset`) itself before terraform.

**P6 refusal.** The preflight refuses a replace when the asset the render names is unpublished,
missing, ambiguous or carries a digest other than T. It refuses before P3's drain wait, it still
gates the manual re-fire arm, and the three direct `apply-web-platform-infra.yml` registry jobs
(`registry-host-replace`, `registry-luks-recut`, `registry-region-migrate`) run it too. Resolve it
with step 2 (new pin) or step 3 (vanished release), then re-fire.

## Reproduce a derivation locally

```bash
WM="$(gh run list --workflow=registry-host-replace-dispatch.yml --branch main --status success \
  --limit 50 --json headSha,createdAt --jq 'sort_by(.createdAt) | last | .headSha')"
bash scripts/registry-delivery-change.sh --repo jikig-ai/soleur --after "$(git rev-parse origin/main)" --before "$WM"
```

Prints the six `key=value` lines the `change` step appends to `$GITHUB_OUTPUT`. The signals the
run itself leaves: the `change` step tees the same lines to the run log (`gh run view <id> --log`),
`::warning::` annotations are readable unauthenticated at
`/repos/jikig-ai/soleur/check-runs/<job-id>/annotations`, and the step summary is human-only.
