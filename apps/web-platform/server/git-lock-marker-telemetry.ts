// Mirror the in-sandbox git-lock wedge markers to a QUERYABLE sink (#6184 follow-up).
//
// worktree-manager.sh (running INSIDE the agent sandbox) emits diagnostic markers to
// the Bash tool's stdout/stderr when worktree creation is wedged by a masked
// `.git/config.lock`:
//   - SOLEUR_GIT_LOCK_DIAG            — forensic (file type, owner, perms, mtime, rdev, mount)
//   - SOLEUR_GIT_LOCK_UNREMOVABLE     — a lock that could not be cleared (the wedge)
//   - SOLEUR_GIT_LOCK_TEMP_WEDGED     — the lockless-writer temp lock was ALSO masked (glob mask)
//   - SOLEUR_GIT_LOCK_IDENTITY_WEDGED — ensure_worktree_identity's set-from-global write could
//                                       not be applied (reason=native-eexist|common-dir-unresolved)
//   - SOLEUR_GIT_LOCK_IDENTITY_DIAG   — benign precondition: the set-from-global branch was taken
//                                       (local identity absent → drift); NOT a wedge
//   - SOLEUR_GIT_BARE_POISON          — ensure_bare_config's shared-config normalization ran
//                                       (branch=healed broke the worktree-wedging config pair;
//                                       branch=clean found nothing to do). Benign either way —
//                                       a failure exits via "worktree wedge: ..." below. #7394
//   - SOLEUR_GIT_BARE_SELFHEAL        — the detection-time recovery for a worktree git reports
//                                       as bare (branch=ok healed it; branch=skipped could not
//                                       measure; branch=failed could not write the worktree's
//                                       own config.worktree → a WEDGE, because the script then
//                                       refuses every mutating subcommand for that worktree)
//   - SOLEUR_GIT_BARE_SEED            — the create-time core.bare=false pin on a NEW worktree
//                                       (branch=seed-failed). Defense-in-depth and inert while
//                                       the extension is absent, so never paged.
//   - "worktree wedge: ..."           — ensure_bare_config gave up
//
// Before this hook those lines went ONLY to blind agent-sandbox stdout — not mirrored
// to any sink an operator can query (ADR-081's stated observability gap). Diagnosing the
// #6184 wedge therefore required asking the operator to paste `findmnt` from the live
// session. This PostToolUse(Bash) hook runs SERVER-SIDE (the Node dispatch process, where
// the pino logger ships to stdout → journald → vector → Better Stack, plus a Sentry
// breadcrumb), scans Bash output for the markers, and re-emits each as a structured log —
// so the next wedge is self-diagnosable without a human round-trip.
//
// Design invariants:
//   - Observe-only + fail-open: always returns `{}`, never throws into the SDK turn.
//   - Privacy: emits ONLY the matched marker lines (device/path/mount forensic — no user
//     content), never the surrounding Bash output. A bounded scan (line count + line
//     length caps) prevents log spam / a pathological-output DoS.
//   - The marker text is diagnostic constants + filesystem metadata the platform owns; it
//     carries no repo contents, so re-logging it verbatim is safe.

import type { HookCallback, PostToolUseHookInput } from "@anthropic-ai/claude-agent-sdk";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";

const log = createChildLogger("git-lock-marker-telemetry");

// Matches the marker sentinels emitted by two in-sandbox surfaces:
//   - worktree-manager.sh — the git-lock wedge markers (SOLEUR_GIT_LOCK_*, "worktree wedge:")
//     including the ensure_worktree_identity identity-authority markers
//     (SOLEUR_GIT_LOCK_IDENTITY_WEDGED = a failed set-from-global write;
//     SOLEUR_GIT_LOCK_IDENTITY_DIAG = the benign set-from-global precondition marker, #6184).
//   - git-repo-readiness-diag.sh — the readiness-gate forensic (SOLEUR_GIT_REPO_DIAG),
//     emitted by soleur:go Step 0.0 when git rejects the workspace repo (a layer ABOVE
//     worktree creation, previously uninstrumented — #6184 round 3).
// Kept in sync with those scripts; a drift test (git-lock-marker-telemetry.test.ts) pins
// the pattern set against the live scripts so a renamed sentinel fails CI instead of going
// silently unmirrored.
//   - SOLEUR_GIT_CONFIG_TARGET_MASKED — the #5934 LIVE wedge: the `.git/config` rename TARGET
//     itself is char-device/bind-mount masked, so atomic_git_config's lockless rename EBUSYs
//     (or a genuinely-bare repo cannot seed its config in-sandbox). A wedge.
//   - SOLEUR_GIT_CONFIG_MASK_SKIP     — benign: a masked config on a NON-bare clone where the
//     bare surgery was correctly skipped and native `git worktree add` proceeds. NOT a wedge.
//   - SOLEUR_FEATURE_PUSH_FAILED      — the -u push failed → local-only branch (was dropped at ingest).
//   - NO_GIT_REPOSITORY               — the repo-readiness gate: a repo-less workspace exits 3 (was dropped).
//   - SOLEUR_GIT_WORKTREE_VERIFY_FAILED — verify_worktree_created rejected the new worktree
//     (reason=path-mismatch|not-a-worktree|dir-not-created|unregistered|branch-missing). The
//     #5934 round-3 LIVE failure was reason=path-mismatch: a relative GIT_ROOT made the expected
//     path relative while git reported it absolute. This exit was SILENT to every sink before
//     round-3 (the round-2 wedge could only be seen via an operator paste). A wedge.
// The optional leading `(?:\[[a-z]+\] )?` prefix tolerates the `[error] ` / `[warn] ` prefix that
// headless_or_stderr stamps onto a marker when it reaches stderr instead of a bare stdout echo
// (D1c) — so the existing `[error] worktree wedge:` give-up finally matches.
//   - SOLEUR_ORPHAN_UNREMOVABLE       — benign-but-persistent (#7102): cleanup_orphan_worktree_dirs
//     could not `rm -rf` an orphan directory (root-owned Supabase bind-mount residue is the
//     recurring cause, errno=EACCES). reason=rm-partial means the survivor is a
//     partially-deleted hollow shell, not the intact worktree it looks like.
//     NOT paged (absent from WEDGE_RE): the reaper still returns 0 and the rest of cleanup
//     proceeds, so nothing is wedged — and it recurs on EVERY run until the residue is
//     cleared, which would make paging pure noise.
//     SURFACE SCOPE — mirrored on the platform surface, unmirrored from the local CLI.
//     `cleanup_orphan_worktree_dirs` is reached only via `cleanup-merged`, which the
//     platform-deployed `plugins/soleur/commands/go.md` Step 0 runs verbatim as its
//     session-start preamble; that plugin is loaded by the SAME options object that
//     registers this hook (agent-runner-query-options.ts — `plugins: [{type:"local"}]`
//     alongside `PostToolUse` matcher "Bash"), so the sentinel CAN reach this extractor
//     there. Note `safe-bash.ts`'s "write verbs … never here" is about the exact-literal
//     AUTO-APPROVE carve-out, not about session reachability — `cleanup-merged` simply
//     takes the normal permission path rather than being auto-approved.
//     What is NOT established is that a session has in FACT executed it (go.md's preamble
//     is allowed to "skip silently on first error"), so treat this as reachable-not-proven.
//     From the LOCAL CLI it is unmirrored — .claude/settings.json registers no PostToolUse
//     "Bash" hook — but that is a property of the CLI surface shared by every marker in
//     this list, not something specific to this one. On that surface the operative consumer
//     is the agent reading the tool result (stdout), plus the unconditional failure summary
//     on stderr — see git-worktree/SKILL.md §Sharp Edges.
//   - SOLEUR_WORKTREE_SLUG_COLLISION — `create` found the target directory already holding a
//     DIFFERENT branch (#7408). Worktree directory names are the slug of the branch name, and
//     that transform is many-to-one (`ci/foo` and `ci-foo` share a directory), so without this
//     the run silently entered the wrong branch's worktree and never created the requested ref.
//     NOT paged — the refusal is the safe outcome and it is already loud on stderr with a
//     specific remedy; a correctly-refused collision is operator-actionable, not a wedge. It is
//     mirrored so the frequency of the collision class is measurable rather than anecdotal.
//   - SOLEUR_ORPHAN_SKIP_DESCENDANT — the orphan reaper declined to reap an unregistered
//     directory because a REGISTERED worktree lives beneath it (#7408): the legacy nested
//     layout a pre-fix version produced for slash-bearing branches. Same surface scope as
//     the two markers around it. NOT paged — the skip is the SAFE outcome (it spares a
//     directory that would otherwise be `rm -rf`'d); what it reports is disk state needing
//     the migration runbook in git-worktree/SKILL.md §Sharp Edges, not a wedge.
//   - SOLEUR_ORPHAN_REGISTRY_UNAVAILABLE — the orphan reaper's fail-closed refusal (#7102):
//     `git worktree list` failed, so the registered-worktree allowlist would be EMPTY and
//     every directory would read as unregistered. The reaper declines to run rather than
//     delete the whole tree. Same surface scope as the marker above. NOT paged — the
//     refusal is the safe outcome; genuine git breakage surfaces as a wedge via the
//     creation path's own SOLEUR_GIT_LOCK_*/SOLEUR_GIT_CONFIG_* markers.
const MARKER_RE =
  /^(?:\[[a-z]+\]\s)?(?:SOLEUR_GIT_LOCK_(?:DIAG|UNREMOVABLE|TEMP_WEDGED)\b.*|SOLEUR_GIT_LOCK_IDENTITY_(?:WEDGED|DIAG)\b.*|SOLEUR_GIT_CONFIG_(?:TARGET_MASKED|MASK_SKIP)\b.*|SOLEUR_GIT_BARE_(?:POISON|SELFHEAL|SEED)\b.*|SOLEUR_GIT_WORKTREE_VERIFY_FAILED\b.*|SOLEUR_GIT_REPO_DIAG\b.*|SOLEUR_ORPHAN_(?:UNREMOVABLE|REGISTRY_UNAVAILABLE|SKIP_DESCENDANT)\b.*|SOLEUR_FEATURE_PUSH_FAILED\b.*|SOLEUR_WORKTREE_LEASE_LIB_MISSING\b.*|SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED\b.*|SOLEUR_SESSION_STATE_UNAVAILABLE\b.*|SOLEUR_WORKTREE_REAPER_ARMED\b.*|SOLEUR_WORKTREE_SLUG_COLLISION\b.*|SOLEUR_(?:INCIDENT|LEGAL_GENERATE|LINEAR_FETCH|TRIGGER_CRON)_HALT\b.*|NO_GIT_REPOSITORY\b.*|worktree wedge:.*)$/;

// MIRRORED-NOT-PAGED, deliberately: the four SOLEUR_*_HALT families (#7450).
//
// These are the secret gates' fail-closed refusals — `incident`, `legal-generate`,
// `linear-fetch`, `trigger-cron`. They belong in MARKER_RE because a refusal that reaches no
// sink is indistinguishable from a run that never happened, and the gate's whole purpose is to
// refuse. They must NOT go in WEDGE_RE: the dominant cause is a customer whose plugin simply
// is not installed, and paging an operator for that is how a page becomes noise.
//
// They were added at round-2 review, where the honest measurement was that C10 shipped these
// markers into payload markdown while NO consumer matched them — so the ADR's claim that a mass
// halt would be "visible in telemetry on the first occurrence" was false on both surfaces. This
// closes the hosted half. On the CLI surface they remain session-scoped (ADR-171 layer 7), which
// is the same residual `SOLEUR_SYNC_ROOT_UNRESOLVED` already carries at #7452.

// A wedge (vs. a benign DIAG) is any marker that indicates git operations could not
// proceed: an unremovable/masked lock, a temp-wedge, a config-TARGET-masked give-up, an
// MIRRORED-NOT-PAGED, deliberately: SOLEUR_WORKTREE_LEASE_LIB_MISSING. It means
// cleanup-merged found no lease library and is therefore refusing to reap ANY
// worktree — the fail-CLOSED direction, so nothing is destroyed and no git
// operation is blocked. It belongs in MARKER_RE because "cleanup has silently
// stopped doing anything" is otherwise indistinguishable from "cleanup ran and
// found nothing to do" (#5454). It does not belong in WEDGE_RE because paging on
// a safe degradation that fires once per load in every legacy worktree is how a
// page becomes noise. Same category as SOLEUR_GIT_LOCK_IDENTITY_DIAG.
//
// ensure_bare_config give-up, a failed identity set-from-global write, a readiness-gate
// rejection (SOLEUR_GIT_REPO_DIAG, EXCEPT its source=probe-unreachable arms — see below), a repo-less
// workspace (NO_GIT_REPOSITORY), OR a failed feature push (SOLEUR_FEATURE_PUSH_FAILED →
// local-only branch), OR a rejected worktree (SOLEUR_GIT_WORKTREE_VERIFY_FAILED → creation
// aborted with exit 1). EXCLUDED (benign, mirrored-not-paged): SOLEUR_GIT_LOCK_IDENTITY_DIAG
// (precondition) and SOLEUR_GIT_CONFIG_MASK_SKIP (non-bare-skip-under-mask → creation proceeds).
//   - SOLEUR_WORKTREE_REAPER_ARMED (#7409) — the one-time dry pass taken the first
//     time cleanup-merged can reap on a given store. MIRRORED so the transition is
//     measurable across the installed base (it fires once per machine, ever), NOT
//     paged: it reports that a destructive capability became available and that
//     nothing was deleted, which is the safe direction.
//
// OUTCOME-DISCRIMINATED (#7409): SOLEUR_SESSION_STATE_UNAVAILABLE is emitted by the
// SKILL.md degrade-open arms when the session-state library (or flock) cannot be
// reached. It is mirrored for every reason, and PAGED only at
// reason=worktree-UNLEASED-and-reapable. The split is the destructiveness gradient:
// reason=running-unlocked and reason=lease-not-released describe an ADVISORY
// operation that proceeded (a merge queued without serialisation, a lease left to
// expire on its own window) — real, bounded, not worth waking anyone. The reapable
// reason describes a worktree running with no lease AFTER this change armed the
// reaper for that population, which is the same exposure
// SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED already pages for.
//
// PAGED (PR #7373): SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED. It is strictly more
// consequential than SOLEUR_FEATURE_PUSH_FAILED, which is already here — a failed
// push leaves a local-only branch that MAY be reaped later; a failed lease leaves
// a worktree that a sibling cleanup-merged can reap NOW, deleting the worktree,
// the local branch, the remote branch, and closing the PR. Unlike
// SOLEUR_WORKTREE_LEASE_LIB_MISSING (mirrored-not-paged: fires once per load in
// every legacy worktree AND makes the reaper fail closed), this one fires only on
// a genuine acquire failure and leaves the worktree exposed.
//
// OUTCOME-DISCRIMINATED (#7394): SOLEUR_GIT_BARE_SELFHEAL is paged ONLY at
// `branch=failed`. That branch means the recovery could not write the worktree's own
// config.worktree, so git keeps reporting a valid worktree as bare and the script refuses
// every mutating subcommand from it until a human fixes the permissions. (The refusal is
// the source-time guard in worktree-manager.sh, NOT `require_working_tree` — that has a
// single call site and was never the mechanism.) `branch=ok`, `branch=skipped` and every
// SOLEUR_GIT_BARE_POISON branch are informational: the run proceeded, so they are mirrored,
// not paged. The create-time pin is a SEPARATE marker name (SOLEUR_GIT_BARE_SEED) rather
// than a reserved branch value, so paging cannot be re-armed by a future author "tidying"
// its branch string — the name is what keeps it out, and the drift guard derives names
// from the script automatically.
// SOLEUR_GIT_REPO_DIAG carries TWO distinct classes and only one is a wedge.
//
//   ready=false …                      → the probe RAN and said the workspace is not usable. A wedge.
//   source=probe-unreachable reason=…  → the probe could NOT run, because go.md could not resolve or
//                                        could not find it. That says nothing about the repo, and
//                                        go.md falls back to inline `git rev-parse` probes which
//                                        decide readiness on their own.
//
// The second class must not page. Its `reason=absent-from-verified-root` arm (#7474) fires when the
// plugin root verified but does not carry the probe — i.e. a stale install on a perfectly healthy
// repo — and go.md runs at EVERY session start, so an unqualified match turns a torn install into a
// recurring platform-integrity error for every affected customer. Both arms stay in MARKER_RE, so
// they are still mirrored; they are simply not classified as blocked sessions.
//
// Discriminating with a lookahead rather than a separate marker name matches what this file already
// does for SOLEUR_GIT_BARE_SELFHEAL (branch=failed) and SOLEUR_SESSION_STATE_UNAVAILABLE.
const WEDGE_RE =
  /^(?:\[[a-z]+\]\s)?(?:SOLEUR_GIT_LOCK_(?:UNREMOVABLE|TEMP_WEDGED)\b|SOLEUR_GIT_LOCK_IDENTITY_WEDGED\b|SOLEUR_GIT_CONFIG_TARGET_MASKED\b|SOLEUR_GIT_BARE_SELFHEAL\b(?=[^\n]*\sbranch=failed\s*$)|SOLEUR_GIT_WORKTREE_VERIFY_FAILED\b|SOLEUR_GIT_REPO_DIAG\b(?![^\n]*\ssource=probe-unreachable\b)|SOLEUR_FEATURE_PUSH_FAILED\b|SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED\b|SOLEUR_SESSION_STATE_UNAVAILABLE\b(?=[^\n]*\sreason=worktree-UNLEASED-and-reapable\s*$)|NO_GIT_REPOSITORY\b|worktree wedge:)/;

// Bounds: scan at most this many lines, keep at most this many matched markers, and
// truncate any single marker line to this many chars. A wedged run emits a handful of
// markers; these caps only fire on pathological/hostile output.
const MAX_SCAN_LINES = 4000;
const MAX_MARKERS = 12;
const MAX_MARKER_LEN = 600;

/**
 * Coerce a PostToolUse `tool_response` (typed `unknown`) into scannable text. The Bash
 * tool's response is commonly a string, or an object with `stdout`/`stderr`, or an array
 * of `{ type: "text", text }` content blocks. Unknown shapes yield "" (no markers).
 */
export function toolResponseToText(resp: unknown): string {
  if (typeof resp === "string") return resp;
  if (Array.isArray(resp)) {
    return resp
      .map((b) =>
        b && typeof b === "object" && typeof (b as { text?: unknown }).text === "string"
          ? (b as { text: string }).text
          : "",
      )
      .join("\n");
  }
  if (resp && typeof resp === "object") {
    const o = resp as { stdout?: unknown; stderr?: unknown; content?: unknown };
    if (typeof o.content === "string") return o.content;
    if (Array.isArray(o.content)) return toolResponseToText(o.content);
    const parts: string[] = [];
    if (typeof o.stdout === "string") parts.push(o.stdout);
    if (typeof o.stderr === "string") parts.push(o.stderr);
    if (parts.length > 0) return parts.join("\n");
  }
  return "";
}

export interface GitLockMarker {
  /** The marker line, trimmed + length-bounded. */
  line: string;
  /** true when the marker indicates worktree creation is wedged (not a benign DIAG). */
  wedged: boolean;
}

/**
 * Extract the git-lock marker lines from arbitrary Bash output. Pure + bounded so it is
 * unit-testable and cannot be turned into a log-amplification vector by hostile output.
 */
export function extractGitLockMarkers(text: string): GitLockMarker[] {
  if (!text) return [];
  const out: GitLockMarker[] = [];
  let scanned = 0;
  for (const raw of text.split("\n")) {
    if (scanned++ >= MAX_SCAN_LINES || out.length >= MAX_MARKERS) break;
    const line = raw.trim();
    if (!MARKER_RE.test(line)) continue;
    out.push({
      line: line.length > MAX_MARKER_LEN ? `${line.slice(0, MAX_MARKER_LEN)}…` : line,
      wedged: WEDGE_RE.test(line),
    });
  }
  return out;
}

/**
 * Build the PostToolUse(Bash) hook that mirrors in-sandbox git-lock markers to the
 * server-side logger. Factory is side-effect-free so a builder-time call inside the
 * `options.hooks` literal can never throw into `query()` startup.
 *
 * @param workspacePath included in each structured log so a wedge is attributable to a
 *   workspace without correlating separate lines.
 */
export function createGitLockMarkerHook(workspacePath: string): HookCallback {
  return async (input) => {
    try {
      const i = input as PostToolUseHookInput;
      if (i.tool_name !== "Bash") return {};
      const markers = extractGitLockMarkers(toolResponseToText(i.tool_response));
      if (markers.length === 0) return {};
      const anyWedged = markers.some((m) => m.wedged);
      const payload = {
        // `sec: true` — this is a platform-integrity signal, not per-user noise.
        sec: true,
        workspacePath,
        wedged: anyWedged,
        markerCount: markers.length,
        markers: markers.map((m) => m.line),
      };
      // A wedge is an error (a blocked session — a git-lock wedge OR a readiness-gate
      // rejection); a benign DIAG is a warning. Both reach Better Stack (pino → stdout →
      // journald → vector) and a Sentry breadcrumb.
      if (anyWedged) {
        log.error(payload, "in-sandbox git wedge/rejection detected (worktree or readiness-gate blocked)");
      } else {
        log.warn(payload, "in-sandbox git diagnostic emitted (no wedge)");
      }
      return {};
    } catch (err) {
      // Fail-open: never throw into the SDK turn. The scanned text is model-adjacent, so
      // keep the error message STATIC and route the detail through the silent-fallback
      // mirror rather than interpolating tool output into the log line.
      log.warn({ err, workspacePath }, "git-lock marker hook failed (fail-open: no mirror)");
      reportSilentFallback(err, { feature: "git-lock-marker-telemetry", op: "scan" });
      return {};
    }
  };
}
