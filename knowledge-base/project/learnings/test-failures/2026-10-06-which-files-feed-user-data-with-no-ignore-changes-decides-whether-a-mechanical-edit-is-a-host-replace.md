# Learning: which files feed `user_data` with no `ignore_changes` decides whether a "mechanical" edit is a host replace

## Problem

Wave A2 of the pipe-fed early-exit `grep` sweep (tracker #9217) was framed as "convert 92 hits under
`apps/web-platform/infra/*`, then delete the deferral row". A census by what each file DELIVERS, not by
directory, showed 21 of the 92 sit in four files whose bytes are rendered into `user_data` of
`hcloud_server.registry`, `hcloud_server.inngest` and `hcloud_server.git_data`: `cloud-init-registry.yml` (13),
`cloud-init-inngest.yml` (4), `cloud-init-git-data.yml` (3), `git-data-bootstrap.sh` (1, embedded by the
git-data userdata module). Those three servers carry no `ignore_changes = [user_data]`, and `user_data` is
ForceNew on the provider, so a one-token lint edit to any of them is a host replace at the next full apply or
maintenance-window dispatch.

## Root cause

Two things hide it. First, the per-merge apply is an allow-list that EXCLUDES these hosts (operator-applied or
dispatch-only), so merging the edit replaces nothing and the PR plan comment is the only place the drift shows;
the replace happens later, on a different run, authorised by a different person for a different reason. Second,
the deferral table was keyed on a directory glob, so "92 hits in one subtree" read as one class when it was
two (host-replacing and not).

## Solution

Split the row by file, make each of the four rows exact (`=`), and write the reason beside them in the table
(ADR-100 for the sole scheduler, ADR-169 for the sole pull path). Convert them only inside a PR that is already
scheduled for the maintenance-window dispatch, and delete the row there. A guard check now also asserts that
every loose (`<=`) row is test-shaped, so a broad production row cannot absorb a future hit.

## Key insight

Before calling an edit mechanical, ask what the file is a CARRIER of, not what directory it lives in. The
question has a mechanical answer: read the `lifecycle` block of every resource that renders the file
(`grep -n ignore_changes` on the server resources) and check whether the per-merge apply covers that resource.
The same file can be inert on one host (`cloud-init.yml` on web-1, `ignore_changes=[user_data]`) and a replace
trigger on another.

## Tags

category: test-failures
module: grep-q-pipe-guard, infra-user-data

## Related

- `2026-10-05-a-reader-that-exits-early-flipped-three-suites-and-the-stub-had-to-read-too.md`
- Trackers: #9217, #7005, #6601
