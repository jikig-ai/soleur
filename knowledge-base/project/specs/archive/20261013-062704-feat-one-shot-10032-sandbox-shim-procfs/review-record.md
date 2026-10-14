# Review Record — PR #10039 (issue #10032)

## Design-validity pass (design-risk set — new mechanism)

| Seat | Verdict | Disposition |
|---|---|---|
| code-simplicity | PASS — mechanism minimal; keep re-home (relabel "semantic preservation", done in ADR) | filter-first reorder (optional, −50 lines) deferred — shipped shape correct & tested |
| architecture | PASS with R1 pre-merge | R1 fixed (dropped bind-fd → fd stripped from preserve); R2 umount-cover added to ADR+header; R3 boundaries documented; R4 verified 0.8.0 in-image; R5 runbook updated; R6 #9773 checklist noted |

## Panel (class=code, 9 seats incl. mandated CTO + CLO)

| Seat | Findings | Disposition |
|---|---|---|
| git-history | no repeats of reverted approaches; #9768's tmpfs rejection properly overturned by removing its recorded blocker | — |
| pattern-recognition | a3 stride HIGH (indep. found); triplication MEDIUM; rescan `other` arm; preserve adjacent-dup; norm_dest forks; e2e ls|grep | all fixed: a3 `+4`, `other` arm, strip-until-stable loop, proc_dest/proc_src fast-paths, glob probe; option-name-set dedup deferred (optional) |
| security-sentinel | F1 a3 (fixed); F2 nested --args HIGH; F3 source-side binds HIGH; F4 glob-inject; F5 mention-DoS; F6 TOCTOU; F7 keep-preserve | F2 refuse positional in payload filter; F3 proc_src on all bind-family arms + drop-all-`--proc`; F4 numeric guard; F5 missing-fd→skip (ENOENT = pre-PR outcome); F6 `/sys` refuse + contract comment; F7 keep (fd may be used by number) |
| performance-oracle | MEDIUM ~40 `$(norm_dest)` forks/spawn (+10–30ms) | proc_dest/proc_src literal fast-paths; filter+rescan gated on expose; mask detection folded into walks |
| data-integrity | a3 (found independently); `///` norm_dest HANG (pre-existing); nested --args; glob-inject; args_pos invariant | a3 fixed; `///` loop deleted (segment split already normalizes); nested refuse; numeric guard; `nread==args_pos` assert |
| agent-native | W2 flat `bwrap_shim_refused` reason = no-SSH blind spot; unnamed objects in 2 refusal msgs; mention-DoS | `detail` field on the 65 verdict → folded into deploy-state reason + Sentry (ci-deploy); `$cmd_fd_refs`/payload index in messages; mention acceptance recorded |
| code-quality | proc_dest F4 false-negatives (`proc`,`./proc`,`../proc`); preserve doc; `mask`→have_mask; emit `&&`→if; stale `argc`/comments; probe missing-/proc vacuous pass; test gaps | all fixed: non-absolute normalize; header doc; rename; if-block; `[ -d /proc ]` anti-vacuity; 6 new regression rows |
| **CTO** | APPROVE-WITH-CONDITIONS — C1 a3 stride (pre-merge) | C1 fixed + regression + divergence belt `expose=1 && dropped=0 → refuse`; C2 stale comments fixed; C3 PR body names the refuse-availability edge; C4 AC4 pointer in PR body |
| **CLO** | APPROVE-WITH-CONDITIONS — 3 record edits | C1 fail-closed basis inline in compliance entry; C2 measurements date corrected; C3 probe-witness bound in ADR |

## Deferred advisories (recorded, not blocking)

- Triplicated option-name sets / shared-walk consolidation (pattern + code-quality): the predicates are unified (proc_dest/proc_src); a walker-consolidation is diff-churn on a security-critical file — recommended for #9773-era rewrite.
- Simplicity filter-first reorder (~-50 lines): optional; shipped shape is correct and tested.
- Source-side `--bind-fd <procfs dirfd>` remains dest-checked only (fd source not readlink-checked) — off-vendored-shape, recorded.
- `systempaths=unconfined` — measured and rejected (ADR-075 addendum).
