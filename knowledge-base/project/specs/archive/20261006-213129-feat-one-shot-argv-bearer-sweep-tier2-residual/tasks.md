# Tasks: argv-bearer sweep, Tier 2 and residual credentials (Ref #7797, Ref #9597)

Plan: knowledge-base/project/plans/2026-10-06-fix-argv-bearer-sweep-tier2-and-residual-credentials-plan.md

## Phase 0 - Census, shim, RED rows
- 0.1 Re-run census-argv-bearer.py; confirm baseline E = 11 files / 13 sites
- 0.2 Extend shim in its own commit (decode `\\` `\"`; record user/data-urlencode; `--data-binary @file`; `-I`, `--proto-redir`; per-row credential matcher) + harness rows
- 0.3 Record per-script success marker, exit code, refusal-marker family
- 0.4 RED rows per converted call site (argv clean, stdin exact, refusal, real token shape)
- 0.5 List and plan updates for tests pinning old argv text
- 0.6 Check xtrace-refusal lint need (zot-image-oci-archive, plugin scripts); parity/size tests vs host_scripts_content_hash

## Phase 1 - Live-in-apply / release pipeline
- 1.1 fresh-host-boot-trail.sh (2 sites)
- 1.2 verify-tunnel-ingress-origin.sh (2 calls: Bearer; CF-Access + X-Signature-256)
- 1.3 zot-image-oci-archive.sh (2 sites)
- 1.4 zot-entry-gate.sh (`-u`)

## Phase 2 - Residual non-Bearer argv
- 2.1 Flagsmith Api-Key: flip.sh, create.sh, delete.sh, list.sh
- 2.2 linkedin-setup.sh (3 fields, `_cfg_ok`)
- 2.3 x-community.sh, x-setup.sh (`_cfg_q`, add --disable --noproxy)
- 2.4 check-cloudflare-token-drift.sh (+ minimal mock edit; check #9348 diff first)
- 2.5 configure-auth.sh (`--data-binary @file`, 2 PATCH sites)

## Phase 3 - Host-deployed (separate commit group)
- 3.1 container-restart-monitor, cron-egress-alarm, disk-monitor, resource-monitor
- 3.2 inngest-rearm-reminders, inngest-wiped-volume-verify (guard before wipe)
- 3.3 web-zot-consumer-probe.sh (`-u`)
- 3.4 soleur-host-bootstrap.sh embedded post (pipe form, bad_token_shape branch, POSIX)

## Phase 4 - Ratchet, tracking
- 4.1 Delete converted lines from baseline E (nic-guard line stays)
- 4.2 Run all local gates (see plan ACs); one push
- 4.3 Restate #9597 body; comment on #7797; SENTRY_PROJECT outcome line in PR body
