# Phase 0 measurements (#12600)

All fixtures synthesized (`cq-test-fixtures-synthesized-only`). Scripts: `probes-12600/probe6.sh` .. `probe11.sh`
(take an optional scratch root). Outputs: `probes-12600/output-local-git-2.56.0.txt` and
`probes-12600/output-runner-image-git-2.39.5.txt`.

## 0.1 Runner image vs local (R10)

| Where | git |
|---|---|
| Dockerfile `runner` stage, built locally (`docker build --target runner`, plugin vendored as CI does; no push) | 2.39.5 |
| Local development host | 2.56.0 |
| CI (`ubuntu-latest`) | not measured from here; the battery prints `git --version` once per run (`[kb-only-push battery]` line) |

Probes run inside the image with `--network none`. Result: every row is identical on both versions (diff of the
two outputs, shas masked) except the `git --version` lines and one `fsck` message suffix in `probe7.sh`
("invalid sha1 pointer in cache-tree" vs "... of .git/index"), which is wording, not a verdict. No hash-check or
hand-off row differs, so R10's P0-redesign clause does not apply and no CTO spawn was needed.

First runner run showed `objects to hand over: 2` (local 3). Root cause: the probe's `awk -v RS='\0'` with a
`{40}` interval; the image ships `mawk 1.3.4`, which supports neither, so the tree was never rewritten (S's tree
equalled T's). Not a git difference: the probes now use a bash `read -d ''` loop and self-check
(`S tree differs from T tree: yes`), and both versions report 3 objects. The product code parses trees in Node, not
awk.

| Probe | Row | 2.56.0 | 2.39.5 |
|---|---|---|---|
| probe6 | S non-KB diff vs T | 0 | 0 |
| probe6 | objects handed over (S, S-tree, M) | 3 | 3 |
| probe6 | CAS ok / wrong old value refused | yes / yes | yes / yes |
| probe6 | foreign object absent on remote after pushing S | yes | yes |
| probe6 | `pull --ff-only` after, remote tip ancestor of HEAD, turn 2 T ancestor | ok | ok |
| probe7 | history walk over planted tree bytes (`rev-list` count / `diff-tree` rc), also via alternate | 0 / 0 / 0 | 0 / 0 / 0 |
| probe8 | `cat-file` -> `hash-object --stdin`: genuine ok, forged loose FAIL, forged packed FAIL | same | same |

## 0.2 Hardened isolated arm against a `file://` bare remote (`probe9.sh`)

`ls-remote --symref <url> HEAD refs/heads/soleur/kb-sync` (rc 0):

```
ref: refs/heads/main	HEAD
<sha>	HEAD
<sha>	refs/heads/soleur/kb-sync
```

`fetch --depth 1 --no-tags <url> refs/heads/soleur/kb-sync` into the isolated dir: rc 0, `FETCH_HEAD` equals the
side tip, the side commit becomes present (it was absent before), the workspace `shallow` is unchanged, the isolated
`shallow` gains the fetched boundary (2 lines). Same on both versions.

## 0.3 Two-parent side commit (`probe10.sh`)

Side commit with parents `(P, T)` (P = older side tip on T0, T = upstream main moved on), tree = T's root with
HEAD's `knowledge-base`: non-force push to `soleur/kb-sync` ok; local main CAS to side ok; after a simulated PR merge
into main, `pull --ff-only` in the workspace is a fast-forward and side is an ancestor of HEAD. Same on both versions.

## 0.4 Non-default branch, before this change (`probe11.sh`)

Single-branch `--depth 1` clone, new local branch `feature`, today's bare `git push`: rc 128 "The current branch
feature has no upstream branch", nothing pushed; the same when the remote already has a `feature` branch the clone
does not track. So a user on a feature branch already got no KB push from `syncPush`; `non_default_branch` makes it
an explicit, observable refusal instead of a failed push caught by the outer catch.

## 0.5 Battery

`apps/web-platform/test/session-sync-kb-only-push-real-git.test.ts`: 32 rows. On the unmodified `syncPush`:
29 RED, 3 pass (H6 "no token on the next turn", matrix 14 "syncWorkspace fast-forwards after the push" because the old
code pushed HEAD itself, and the R18 positive control). Record: `red-runs/phase0-battery-on-unmodified-syncPush.txt`.
Runtime: about 5 s locally (tests 4.6 s), far under the webplat shard timeout.
