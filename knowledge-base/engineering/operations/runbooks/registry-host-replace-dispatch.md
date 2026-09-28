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
| `apply-failed` | the replace RAN and did not conclude success; the host may be dark, the volume is preserved | re-dispatch `registry-host-replace` |
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
| `ok` | the asset matched T, loaded, and its image ID is upstream C or D; zot runs by that ID | none. Expect `zot_image_digest=<D12>` and `ghcr_blocked=1` |
| `not_run` | the state file is absent: the fetch never ran on this instance | read the replace run's apply log. A host that predates the change reports this until its next replace |
| `download_failed` | curl could not fetch the asset (after 5 retries) | re-fire the replace (§ Re-fire after a refusal). If it recurs, check the asset URL with `bash scripts/registry-replace-preflight.sh --print-asset` and `curl -sSIL <url>` |
| `sha_mismatch` | the downloaded bytes are not T; nothing was loaded | do NOT re-publish over it. Compare the asset's API digest with T (P6 does). Re-dispatch `zot-image-mirror.yml` only if the release is absent |
| `load_failed` / `id_mismatch` | docker could not load it, or it loaded as an image that is neither C nor D | the pins disagree with the asset. Revert the PR that moved them (below) |
| `config_invalid` | `/etc/default/zot-image` is malformed (a template or render defect) | revert the PR that changed it |

In every refusal zot never starts. The zot liveness heartbeat goes absent, which is the page, and
`state_status=unknown` follows. Running web containers keep serving; deploys wait.

**Recovery, all workflow-only (no SSH):**

1. **Re-fire the replace.** Use this for a transient `download_failed`. Run
   `gh workflow run registry-host-replace-dispatch.yml -f reason='zot boot asset fetch retry'`.
2. **Re-publish a deleted asset.** Run `gh workflow run zot-image-mirror.yml`. It rebuilds from
   upstream D reproducibly, so P6 goes green once the digest equals T. Then re-fire. A published
   asset cannot be replaced (immutable releases), and `zot-image-*` releases are never deleted.
3. **Revert the PR.** Revert the PR that introduced or moved the pins. The dispatcher sees the
   rendered `user_data` change and replaces the host back onto the previous render. This is the
   rollback for the change itself.

**P6 refusal.** The preflight refuses a replace when the asset the render names is unpublished,
missing, ambiguous or carries a digest other than T. It refuses before P3's drain wait, and it
still gates the manual re-fire arm. Resolve it with step 2 above, or with the bump procedure in
`apps/web-platform/infra/zot-image.provenance.md`, then re-fire.

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
