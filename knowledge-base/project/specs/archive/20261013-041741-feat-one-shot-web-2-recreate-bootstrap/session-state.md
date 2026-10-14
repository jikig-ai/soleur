# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-05-feat-web-2-recreate-bootstrap-plan.md
- Status: complete

### Errors
None. Two IaC-routing-hook blocks fired on systemctl/actor-imperative prose (existing root-cause + rejected-alternative descriptions, not prescribed steps) — resolved with the iac-routing-ack opt-out + rephrasing; plan + tasks pass lint-infra-no-human-steps clean.

### Decisions
- Precision destroy-guard (no [ack-destroy] bypass): extend destroy-guard-filter-web-platform.jq with a POSITIVE-scope web2_out_of_scope_changes key (any create/update/delete outside the exact 3-address web-2 allow-set via exact-equality IN(.address; web2_allow[])) + web2_server_replaced. Closes spec-flow P0-2 (a web-1 in-place update rebooting via a non-placement_group_id/server_type attr passed the delete-only counter).
- Digest pin via coherence preflight (durable :latest fix): read web-1 running .tag off-host → resolve @sha256 via docker buildx imagetools inspect (live-confirmed no-auth on public repo; multi-arch OCI index → pin the index digest) → docker-cp the digest's /opt/soleur/host-scripts, assert recomputed hash == terraform console local.host_scripts_content_hash BEFORE -replace. Abort loud on mismatch (the exact cloud-init boot check, run off-host pre-destruction).
- Volume preservation confirmed: hcloud_volume.workspaces["web-2"] is a separate resource with no server-id edge — a server -replace cannot recreate it; only server + hcloud_server_network.web["web-2"] + hcloud_volume_attachment.workspaces["web-2"] replace. All 3 targets are SSH-provisioner-free (Hetzner-API-only apply).
- Reuse existing warm_standby job shape; new web_2_recreate job adds only -replace + -var=image_name=$PINNED; shares the same R2 concurrency serializer. CI-side -target+-replace is novel for this repo (flag for review scrutiny).
- Blue-green: recreate hits a non-serving weight-0 host; ingress stays 100% on web-1 → zero user downtime, no maintenance window. CTO endorsed.

### Components Invoked
soleur:plan → soleur:deepen-plan; CTO agent; spec-flow-analyzer (P0-2 catch); Explore/repo-research/learnings-researcher; deepen-plan gates 4.5/4.55/4.6/4.7/4.8/4.9.
