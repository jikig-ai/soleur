---
title: "My ghcr.io deny guards proved one template arm and could not see a one-line provisioner"
date: 2026-09-30
category: infra
tags: [guard-contract, templatefile, terraform, provisioner, review-panel, mutation-battery]
issue: 9169
pr: 9264
---

# Learning: a parity guard over a templatefile covers only the arms it renders

## Problem

#9169 mirrored the registry host's ghcr.io hosts-file deny onto both web hosts: cloud-init
runcmd[1] for new hosts, and a `local.ghcr_deny_sh` run by two existing `terraform_data`
provisioners for the running ones. A new suite, `web-ghcr-deny.test.sh`, pinned the three copies
together and carried an 11-row mutation battery that went all red. The 9-seat review found no
defect in the deny. Every finding was a guard that covered less than the property it named:

- **One template arm.** The suite rendered `cloud-init.yml` with `web_tunnel_connector=false`, the
  web-2 shape. web-1 is born with `true`, so wrapping the deny in `%{ if !web_tunnel_connector ~}`
  would drop it from web-1's birth with every guard green.
- **One-line blocks.** Provisioner blocks were found with `^  provisioner "…" \{$`. A valid,
  `terraform fmt`-stable one-line block placed after the deny
  (`provisioner "remote-exec" { inline = ["sed -i /ghcr/d /etc/host?"] }`) undid it while the
  wiring check still saw the deny as last.
- **One file type.** The census walked `*.tf`, but a drifted `127.0.0.1` deny in a host script
  (`ci-deploy.sh`) reaches every web host.
- **One direction.** The classifier-agreement table had one "one name sinked" row, so an
  assertion that stopped probing `ghcr.io` itself passed.
- **Unpinned wiring.** `count = 0` on a route, a third entry in `var.web_hosts`, and a
  post-processed `user_data` expression were all green.

## Solution

Each gap got a check plus a mutation row that reds on that check alone (19 rows in all, floor
21 -> 29). The suite now:

- renders both template arms;
- finds provisioners at any indentation and length;
- refuses `count`, `for_each` and `lifecycle` on the two routes, and binds each route to its host;
- pins `var.web_hosts` to the hosts the routes reach, and `hcloud_server.web.user_data` to the
  plain render;
- matches hosts-file WRITES and real `for h in … ; do` loops across `.tf`/`.sh`/`.yml`/`.tmpl`;
- runs each classifier under its production shell.

Guard 1 also refuses a redefinition of `grep`, `printf`, `getent`, `awk` or `sort`, because
runcmd is ONE shell and such a function would run inside the admitted deny loop.

## Key Insight

A copy-parity test over a Terraform `templatefile` is a claim about the arms it RENDERED, not
about the template. Enumerate every boolean or conditional variable the real call sites pass
(here `web_tunnel_connector` differs between web-1 and web-2), and render each value. Separately,
any regex that finds HCL blocks by their multi-line shape is blind to the one-line form. Split on
the block keyword at any indentation and compare the normalized text instead.

## Session Errors

1. **The first commit's pre-commit battery queued behind a sibling's full gate.** Recovery:
   killed my own run with `proc.sh kill_mine`, then recommitted with `LEFTHOOK_EXCLUDE=bun-test`
   after running the changed suite directly. **Prevention:** run `test-all.sh --capacity` before
   a `.ts` commit on a contended box; already covered by work §9.
2. **A background `git commit` notified "exit 0" while the commit had failed.** Recovery: read
   `COMMIT_RC` from the log. **Prevention:** existing rule, `echo "COMMIT_RC=$?"` on the next line.
3. **A machine reboot left the affected gate with an empty log and no rc file.** Recovery:
   relaunched it, then stopped it on the operator's instruction to rely on CI. **Prevention:** a
   missing rc file is a reap, never a verdict (existing rule).
4. **The stop hook flagged a future-tense promise at the end of a turn, twice.** Recovery: stated
   the blocking condition explicitly. **Prevention:** close a waiting turn with the blocker, not
   with a promise.
5. **The security seat finished twice without delivering a report.** Recovery: asked it to write
   the report to a file and hand it back. **Prevention:** put "write your report to a file and
   end with WROTE <path>" in the SPAWN prompt (the review skill already says so).
6. **A `sed -n "$((n-12)),…"` read failed because the anchor grep matched nothing.**
   **Prevention:** guard the computed line number before using it.
7. **An incidental `git stash list` was blocked by the guardrail hook.** **Prevention:** probe for
   stashes with `git rev-parse --verify --quiet refs/stash`.
8. **Python was over-escaped inside a quoted heredoc (`\\n`, `\\s`).** Caught by reading it back.
   **Prevention:** inside `<<'EOF'`, write the literal Python source; escape only in the outer layer.
9. **The new shadow regex missed the YAML `- ` list marker.** Caught by its own mutation row.
   **Prevention:** build the mutation fixture from the real file shape (a runcmd list item), not
   from a bare line.
10. **The widened census flagged a Python string in `zot-image-rehearse.sh`.** **Prevention:**
    match the construct (`for h in … ; do`), never a token that a string can name.
11. **The guards covered less than their names claimed (nine shapes; see Problem).**
    **Prevention:** before committing a guard, name every axis the property quantifies over
    (template arms, hosts, file types, name directions, block forms) and write one fixture per
    axis; see the route-to-definition bullet in work §6.
12. **The `ci-deploy.test.sh` floor was left at 359 after 4 rows were added.** **Prevention:**
    raise a floor in the same edit that adds rows (existing rule).
13. **The default `sleep` mock would have made the getent "hang" fixture return at once.**
    **Prevention:** call `/bin/sleep` explicitly inside a mock that must really block.
14. **Plan phase: the issue's precondition was unsatisfiable as written** (the `IMAGE_VERIFY`
    `ref=` field is the app image, not the verifier), **and the first advisor consult went out
    without the plan text.** **Prevention:** verify a precondition on the field that actually
    carries it, and attach the artifact to every consult.
