---
title: "Deploy-user → root sudo helper: three escalation traps (caller attrs, sudoers dest, file-path TOCTOU)"
date: 2026-06-02
category: security-issues
module: apps/web-platform/infra
issue: 4827
tags: [sudo, privilege-escalation, toctou, infra, webhook, deploy-pipeline]
---

# Learning: hardening a deploy-user-invokable `sudo` escalation helper

## Problem

#4827: the `/hooks/infra-config` webhook handler (`infra-config-apply.sh`, runs as
`User=deploy`) lands its managed files in `root:root 0755` dirs the deploy user
cannot `mktemp` into (EACCES) — every push wrote 0 files. The fix escalates the
write to root via a pinned, wildcard-free sudoers helper
(`deploy ALL=(root) NOPASSWD: /usr/local/bin/infra-config-install`).

The sudoers grant pins only the COMMAND PATH (sudo-rs forbids argument wildcards),
so **the deploy user can invoke the helper directly with arbitrary arguments and
stdin** — not only through the handler. The helper is the sole security boundary.
The first two designs each shipped an escalation hole that automated review caught.

## Solution — three traps and their fixes

1. **Never trust caller-supplied `mode`/`owner`.** The first helper took
   `<src> <dest> <mode> <owner>` and applied them. A deploy user could call
   `sudo infra-config-install <x> /usr/local/bin/ci-deploy.sh 4755 root:root` to
   **setuid a root binary**, or `... 755 deploy:deploy` to seize it. Fix: derive
   mode/owner from an authoritative in-helper `declare -rA DEST_SPEC` table keyed
   on the canonical dest; reject (rc=3) any call whose supplied values disagree.
   The install uses the TABLE values, never the caller's.

2. **Never let the helper write the grant-definition file.** `/etc/sudoers.d/*`
   was in the allowlist. A deploy user could install `deploy ALL=(root) NOPASSWD:
   ALL` directly — instant full root. `visudo -cf` validates SYNTAX, not POLICY,
   so it cannot make sudoers content-write safe. Fix: remove the sudoers dest from
   both the helper allowlist AND the handler `FILE_MAP` (8→7 managed files); deliver
   the grant root-only (SSH bridge `terraform_data.infra_config_handler_bootstrap`
   with `visudo` + atomic `install`, plus cloud-init). The webhook/deploy-user path
   never mutates the file that defines its own privileges.

3. **Pass the payload over STDIN, not a file path.** The staging dir (`/var/lock`)
   is deploy-writable, so a file-path source is TOCTOU-attackable: between the
   helper's symlink/owner check and its `cp`, a direct caller swaps the path to a
   symlink → `/etc/shadow`, and root's `cp` follows it, writing a root-only file
   into a world-readable 0755 dest (confidentiality break / privesc). Fix: the
   helper reads the payload from STDIN; the handler pipes `sudo helper <dest>
   <mode> <owner> < "$tmpfile"`. The `< file` redirect is opened by the DEPLOY
   user before sudo elevates, so a caller can only ever feed bytes they could
   already read (`... < /etc/shadow` fails at open as deploy). The swappable
   on-disk source is eliminated — there is no path, so no TOCTOU.

## Key Insight

A sudoers grant that pins only the command path moves the ENTIRE security boundary
into the helper. Design the helper as if the deploy user is the adversary calling
it directly (because the grant lets them): (a) trust nothing from argv that affects
privilege — derive it from an internal table; (b) exclude the file that defines the
grants themselves from anything the grant can write; (c) feed content over stdin so
there is no caller-resolvable path to symlink-swap. The chicken-and-egg (the helper
+ the new grant must exist before the handler's first escalation) is solved by
root-SSH bootstrap (`depends_on` the bridge so it lands before the webhook push).

## Session Errors

1. **Caller-controlled mode/owner + sudoers-writable (CRITICAL, automated commit review).** Recovery: authoritative `DEST_SPEC` table + sudoers removed from FILE_MAP/allowlist, root-only delivery. Prevention: treat a path-pinned sudoers grant as "deploy user can call this directly"; derive privileged attrs from a table and exclude the grant file from day one.
2. **File-path source TOCTOU (P1, multi-agent review).** Recovery: stdin payload contract (no on-disk source). Prevention: hand privileged helpers bytes via stdin, never a deploy-writable file path.
3. **`grep -c … || echo 0` double-emitted `0`** → false test FAIL. Recovery: `|| true` (grep -c already prints the count on no match). Prevention: never chain `|| echo 0` onto `grep -c`.
4. **Test grep used a leading `|`** after the arg shape dropped the src field (log line now starts with the dest). Recovery: anchored `^<dest>|`. Prevention: re-derive log-field positions when a recorded arg list changes.

## Tags
category: security-issues
module: apps/web-platform/infra
