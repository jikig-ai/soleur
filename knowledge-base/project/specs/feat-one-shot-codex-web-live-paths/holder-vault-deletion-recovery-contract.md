# Candidate vault deletion and recovery contract

Status: **design only; all deletion remains refused**. This narrows the deletion
and restoration requirements already ruled in [holder-retention-controller-design.md](holder-retention-controller-design.md).
It does not authorize collection, provisioning, cleanup, or use of the local
receipt store with real data. The existing `ReceiptStore.delete()` unconditionally
refuses; its injected callbacks and local tombstone are not independent proof.

## Required inputs and refusal boundary

The deletion operation must receive one independently authenticated, scoped
capability binding the vault identity, operation, generation, fixed entry set,
allowed action, authority revision, expiry and issuer/key version. It must read
current revocation and the generation/epoch from a separately operated,
non-rollback authority, and compare these to the durable local state while the
same exclusive mutation fence covers the entire operation. Missing, stale,
ambiguous, mismatched or unavailable information returns `unknown`; a caller
boolean, local file, signed historical receipt or unverified HTTP header cannot
substitute. The capability and current status must be bound to the authenticated
worker, with role and replay checks. Key and capability expiration do not revoke
already issued tokens. Define and measure the maximum revocation propagation
latency, including any key/status cache; refuse where freshness cannot support
the claimed bound. Instantaneous revocation is not claimed.
The authority-to-vault protocol must specify how an epoch or revocation change
is fenced against a mutation already in flight. A fresh read immediately before
unlink is not atomic with an external authority update and cannot establish that
fence by itself.

Before deleting, the vault must prove capture stopped or that an independent,
bounded clock's **lower** time bound has reached the authorized earliest cleanup
time. It must persist a sealed state and fence future opens, writes and readers,
including in-flight calls, under the same generation and mutation fence. A
worker assertion is not proof of stopped capture. A separate inventory must
account for controlled open descriptors, file-backed memory mappings, forked
descendants, processes and copies. The substrate
must establish whether backups, snapshots, swap, dumps, logs and telemetry can
contain the receipt and how they are excluded or removed. Unaccounted handles
or copies leave the result `unknown`, even if the named file is absent.

## Exact-entry mutation and persistence sequence

1. Revalidate the original pinned directory descriptor, filesystem and vault
   identity, generation, exclusive mutation authority, state and allowed fixed
   entry names. Reject symlinks, hard links, changed owner, device, inode,
   unexpected entries or types. Never traverse provider-supplied paths or widen
   cleanup to the parent directory. The immutable ownership record must bind
   each existing entry to its creation and generation.
2. Under the same fence, durably record a bounded deletion intent and sealed
   generation before any unlink. Include an opaque command identifier, exact
   target identity, authority revision and time decision, but no receipt body.
   Sync the intent file and its parent directory; if any result is ambiguous,
   stop and report `unknown`.
3. Recheck the current epoch, authority/revocation, directory and target
   identity immediately before mutation. Perform only the fixed-entry operation
   guaranteed by the selected substrate's ownership/fencing contract. Sync the
   directory after unlink; record and sync a terminal local tombstone and sync
   its parent directory after creation or rename. Any failed sync is unknown.
   These operations must be recoverable after process or host interruption. An error,
   timeout or lost response is ambiguous, including when a later read sees no
   entry while an earlier operation might still be in flight.
4. A separately authenticated verifier checks the original vault and generation,
   independently observes the absent entry, and obtains a healthy control read.
   It must also verify the registered handle/copy inventory and applicable
   deadline using an independently bounded interval whose upper endpoint is
   strictly before it for a timely result. A crossing interval is unknown;
   completion established at or after the deadline is late. Append the minimized result through the independent authority;
   late or incomplete evidence stays `late` or `unknown`. No result from unlink,
   tombstone creation, a process exit, or an inaccessible vault alone means
   `deleted`.

POSIX `unlinkat(dirfd, name, 0)` is pathname-based: opening and `fstat`ing a
file, then unlinking its name, is not an atomic compare-and-unlink. A same-UID
process able to replace that entry can cause deletion of a replacement after
verification. `O_NOFOLLOW`, inode checks, directory FDs and advisory `flock`
do not close that race. Before implementing actual unlink, the chosen runtime
must prove that no untrusted process can mutate the private namespace and that
all authorized writers use the same exclusive fence, or supply another reviewed
substrate primitive with equivalent atomic ownership guarantees. If neither is
established, refuse unlink. The current local prototype does not establish it.

## Recovery rules

On restart, first establish the original vault identity and a fresh independent
epoch that cannot roll back with the volume. Keep all writes and deletes fenced
until reconciliation. Compare durable authority state, local generation, sealed
state, deletion intent and each recorded target identity. A higher or ambiguous
external epoch, changed object, unexpected entry, missing authority or stale
restoration is `unknown`; never treat an empty restored directory as completion.

A crash after durable deletion intent but before the result may have occurred
before, during or after unlink. Reconcile only through the same pinned generation,
ownership and independently checked absence/copy/handle protocol; an immediately
absent entry is not by itself proof that an old operation cannot still act.
The authority must resolve or fence every in-flight operation before retry or
claiming completion; a restart or descriptor close alone does not establish
that an old process, mapping or in-flight system call has stopped.

The current store can leave `receipt` bytes with state still recording no
receipt after a post-write gate fails or the process crashes. That orphan has no
recorded inode in the committed state, and its current presence cannot prove
which creation produced it. Keep the directory blocked and alert. Do not delete
or adopt the file based on its name, hash or a caller assertion. A future
implementation needs an independently bound creation reservation and a reviewed
recovery protocol covering the gap between file creation and durable identity
recording; if that gap cannot be closed or safely reconciled on the real
substrate, the orphan stays unknown. The same rule applies to `state-next` and
other interrupted metadata. No automatic cleanup is authorized here.

### Candidate creation reservation — not implemented

An independent investigation considered reserving the operation, generation,
vault and entry with the authority, then creating an empty inode and binding
its device and inode to the reservation before writing receipt bytes. One
Linux candidate is `O_TMPFILE` followed by `linkat` of that same descriptor.
Linux documents the unnamed-file and linking mechanisms in [open(2)](https://man7.org/linux/man-pages/man2/open.2.html)
and [link(2)](https://man7.org/linux/man-pages/man2/link.2.html); a successful
link still requires [directory fsync](https://man7.org/linux/man-pages/man2/fsync.2.html).

A local synthetic probe linked an unnamed inode using both documented forms,
and observed that a duplicated descriptor retained its bytes after the original
was closed. This is not target-host evidence or proof of deletion. Kernel,
filesystem, procfs and capability behavior must be tested in the actual
disposable substrate. External reservation and local link are not one atomic
transaction; a crash, lost acknowledgement, reused inode or restored volume
requires reconciliation under an independent current epoch. A retained unnamed
descriptor, backup, snapshot or cache can still hold bytes. The approach does
not solve deadline-crossing I/O, namespace replacement, revocation, independent
cleanup or verification. No receipt bytes may be written until the independent
reservation and exact inode binding are durably verified; this remains a
candidate, not a selected or implemented control.

Ruled by CTO agent, 2026-10-30: use a fixed empty
`O_CREAT|O_EXCL|O_NOFOLLOW` entry under a proven exclusive namespace, with an
independent durable reservation and exact inode binding, as the gated candidate.
It permits visible orphan inventory without adding `O_TMPFILE`'s separate
linking and procfs/capability dependencies. Dissent: none.

Reserve an opaque operation, generation, epoch, name and nonce externally first.
Create the fixed entry empty, verify its held descriptor, sync the file and
directory, then durably bind its device, inode, filesystem and vault identity
to the same reservation in the independent authority. Resolve a lost binding
response only through an exact authenticated read and fencing of in-flight
calls. Revalidate descriptor, namespace, authority, epoch, revocation and time
before accepting the first byte. A crash or ambiguous result remains unknown;
never resume or delete using an inode number or pathname alone. Test every
crash and sync boundary, delayed acknowledgements, replay, inode reuse,
replacement, restore, clock crossing and old handles on synthetic data and the
separately authorized target substrate. This ruling establishes no working
service, retention guarantee or permission for live collection.

## Acceptance evidence

Before implementing a live deletion path, require tests for:

- denied, expired, wrong issuer/worker/action/generation/operation and revoked
  capabilities; delayed revocation and authority or epoch outages; restored
  old volumes and stale generation/replay after terminal tombstones;
- same-UID path replacement at every check/mutation boundary, symlink and hard
  link substitution, changed inode/owner/device, unexpected entries and active
  competing writers; verify that replacement objects survive each refusal;
- process termination at every durable step, including before/after receipt
  creation, state rename, directory sync, unlink and terminal tombstone;
  verify orphaned bytes are reported and never silently adopted or deleted;
- in-flight readers, writers and child processes, process/host crash, volume
  reattachment, and each backup/snapshot/swap/dump/log/telemetry copy surface;
  a failed inventory or unhealthy control read must never yield `deleted`;
- cross-deadline stalls in every write and deletion step, clock rollback and
  uncertainty, ambiguous or delayed unlink, concurrent replay, lost response,
  and a retry after an earlier operation is still in flight.

Synthetic disposable-directory tests can exercise state handling and refusal.
They cannot demonstrate the actual platform's namespace exclusivity, independent
identity and epoch, complete copy inventory, failure-domain independence, or
host-loss recovery. Those require a separately authorized, isolated substrate
rehearsal and independent technical and legal review before collection.
