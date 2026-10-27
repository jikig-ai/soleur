// pencil-save-gate.mjs — the pure decision logic behind every save the adapter sends
// (extracted so it can be unit-tested without the MCP SDK): the empty-overwrite sentinel
// (#11143), the stale-file guard (#11168), the load-fidelity check, the refusal and
// not-persisted message builders, and the dependency-injected `runGuardedSave` that
// orders them. The adapter owns I/O (reads, the REPL, the baseline); this module owns
// every verdict and every user-visible refusal text, so the marker contract (first line
// `REFUSED save: [reason=<code>] <file> ...` / `NOT PERSISTED: [reason=<code>] <file> ...`)
// lives in one place.

// --- Empty-overwrite sentinel (#11143) and stale-file guard (#11168) --------
//
// The headless engine writes only on `save()`, and a document opened without
// `--in` is empty (measured), so a save over an existing .pen would replace it with the
// 96-byte empty document. Every save goes through `runGuardedSave`:
//   1. an empty in-memory document is never written over a file that still holds
//      a top-level node, and nothing is written over a file that exists but is not
//      a recognizable .pen document (`decideSave`, #11143; compares the live file
//      with the live document, so there is no stored value for an edit to weaken);
//   2. a save never replaces a file whose content differs from what THIS session
//      last loaded or last saved (`decideStale`, #11168; compares a stored
//      baseline with a fresh read taken after the memory probe, immediately
//      before the engine's `save()`).
// Limits: a second writer between the fresh read and the engine's write is not
// caught, and the post-save read adopts whatever is on disk at that instant.

import { createHash } from "node:crypto";
import { parseCountReply } from "./pencil-repl-surface.mjs";
import { stripAnsi } from "./pencil-response-classify.mjs";

/** The file exists with content, but it is not a document the engine can load back. */
export const DISK_UNRECOGNIZED = "unrecognized";

/**
 * State of the .pen text on disk:
 *   null               missing or blank: nothing recoverable to protect
 *   a number           a parseable document with that many top-level nodes
 *   DISK_UNRECOGNIZED  non-blank text that is not a .pen document (unparseable
 *                      JSON, a git conflict, a document with no children array).
 *                      The engine loads such a file as an EMPTY document without
 *                      an error, so the next save would destroy hand-recoverable
 *                      content.
 */
export function diskTopLevelCount(text) {
  if (text === null || text === undefined) return null;
  let s = Buffer.isBuffer(text) ? text.toString("utf8") : String(text);
  if (s.charCodeAt(0) === 0xfeff) s = s.slice(1);
  if (s.trim() === "") return null;
  let doc;
  try {
    doc = JSON.parse(s);
  } catch {
    return DISK_UNRECOGNIZED;
  }
  if (doc && typeof doc === "object" && Array.isArray(doc.children)) {
    return doc.children.length;
  }
  return DISK_UNRECOGNIZED;
}

/**
 * Top-level node count of the in-memory document from the reply to the adapter's
 * count snippet (`execute` printing `TOPLEVEL_COUNT:<nonce>:<n>`). Exactly one
 * line carrying THIS call's nonce counts; zero lines, two lines, another nonce or
 * an error reply give null (the caller must treat that as unsafe, not as zero).
 * Pass the UNTRUNCATED reply text.
 */
export function memoryTopLevelCount(replyText, nonce) {
  if (replyText === null || replyText === undefined) return null;
  return parseCountReply(replyText, nonce);
}

/**
 * @returns {{ allow: boolean, reason: string }}
 */
export function decideSave({ diskCount, memoryCount }) {
  if (diskCount === null || diskCount === undefined) {
    return { allow: true, reason: "target missing or blank: nothing to protect" };
  }
  if (diskCount === DISK_UNRECOGNIZED) {
    return {
      allow: false,
      reason: "target exists but is not a recognizable .pen document",
    };
  }
  if (diskCount === 0) {
    return { allow: true, reason: "target holds no nodes: nothing to protect" };
  }
  if (memoryCount === null || memoryCount === undefined) {
    return {
      allow: false,
      reason: `target holds ${diskCount} top-level node(s) and the in-memory document could not be read`,
    };
  }
  if (memoryCount === 0) {
    return {
      allow: false,
      reason: `target holds ${diskCount} top-level node(s) but the in-memory document is empty`,
    };
  }
  return { allow: true, reason: `in-memory document has ${memoryCount} top-level node(s)` };
}

// The reason codes, in the order the prose tables list them. Result text first lines are
// `REFUSED save: [reason=<code>] ...` for REFUSAL_REASON_CODES and
// `NOT PERSISTED: [reason=<code>] ...` for NOT_PERSISTED_REASON_CODES. (`recreated` is a
// stderr-only code: a recreated save succeeds.) The prose test imports these lists.
export const REFUSAL_REASON_CODES = Object.freeze(["stale", "unknown-baseline", "refusal-pending", "empty", "unrecognized"]);
export const NOT_PERSISTED_REASON_CODES = Object.freeze(["save-failed", "unconfirmed", "save-incomplete"]);
export const REASON_CODES = Object.freeze([...REFUSAL_REASON_CODES, ...NOT_PERSISTED_REASON_CODES]);

const NEVER_BYPASS = "Do not delete or recreate the file to bypass this check.";
// Shared text contract: SKILL.md and ux-design-lead.md quote these sentences verbatim.
// The repo's open guard refuses an untracked path; the agent asks before committing anything.
export const UNTRACKED_HINT = "(in the Soleur repo the open guard needs the path tracked: ask the user, then commit an empty placeholder)";
export const REPLAY_SAFETY_SENTENCE =
  "Before replaying, check whether the edit is already present (compare the node count open_document reports, or Get the nodes): this session's own interrupted save may already have written it.";
export const ONLY_COPY_SENTENCE =
  "If a retry is refused, the in-memory document is the only complete copy: read it out (get_editor_state, or Get/Print inside batch_design) or export it BEFORE calling open_document.";
const RESTORE_TRACKED = "If the file is tracked, restore it from version control first.";

/**
 * Refusal text. Its FIRST line is the marker `REFUSED save: [reason=<code>] <file> was
 * not modified.`; `code` is one of REFUSAL_REASON_CODES (anything else throws).
 * `empty` also covers an unreadable in-memory count (`memoryCount` null); `unknown-baseline`
 * takes a `cause` (and `detail`); `restart` (refusal-pending only) says why the engine was
 * respawned while the refusal was armed: "restart" (it was already armed, or edits were
 * unpersisted at the respawn), "external-change" or "file-missing" (the respawn found the
 * file changed or gone); the same parameter also names the cause that armed it outside a
 * respawn: "failed-write" (a save failed and the file changed during the write).
 * `recreated` (unknown-baseline/recreate-path-changed only, default true) says whether the
 * file had been removed: false for a present file whose path is no longer canonical.
 */
export function refusalMessage({ file, source, code, diskCount, memoryCount, memoryReason, cause, detail, restart, recreated = true }) {
  if (!REFUSAL_REASON_CODES.includes(code)) {
    throw new TypeError(`refusalMessage: unknown code '${code}'`);
  }
  const lines = [`REFUSED save: [reason=${code}] ${file} was not modified.`];
  const replay = `then replay the refused operations in order. Keep one writer per file (there is no lock). ${NEVER_BYPASS}`;
  const openFails = "If open_document itself fails on the changed file, stop: do not retry or recreate it, and tell the user the file was changed by another tool.";
  if (code === "stale") {
    lines.push(
      "It changed on disk since this session loaded or last saved it (another session, git, or an editor such as Pencil Desktop). Edits made since are not persisted, and re-opening discards them.",
      `Next step: stop editing, call open_document on ${file} ${UNTRACKED_HINT}, ${replay} ${openFails}`
    );
  } else if (code === "refusal-pending") {
    if (restart === "file-missing") {
      lines.push(
        "The session restarted (a crash or a timeout) and the file no longer exists on disk: the earlier edits lived in the engine that died and are gone. Edits made since are not persisted.",
        `Next step: tell the user the file was removed by another tool. ${RESTORE_TRACKED} Then call open_document on ${file} ${UNTRACKED_HINT} (a new empty document, if the file is still gone) or open_document a different .pen path, and recreate the edits from your context. Keep one writer per file. ${NEVER_BYPASS}`
      );
    } else if (restart === "external-change") {
      lines.push(
        "The session restarted (a crash or a timeout) and the engine reloaded NEW content: the file changed on disk since this session last loaded or saved it, so the earlier unsaved edits were lost with the old engine and any edit made since sits on a picture of the file this session never saw. Nothing on disk was overwritten.",
        `Next step: call open_document on ${file} ${UNTRACKED_HINT}, then replay the refused operations in order. ${REPLAY_SAFETY_SENTENCE} Keep one writer per file (there is no lock). ${NEVER_BYPASS} ${openFails}`
      );
    } else if (restart === "failed-write") {
      lines.push(
        "An earlier save failed and the file changed during a failed write (a partial write), and no open_document has succeeded since: the in-memory document is the only complete copy. Edits made since are not persisted, and re-opening discards them.",
        `Next step: read the in-memory document out first. ${ONLY_COPY_SENTENCE} Then call open_document on ${file} ${UNTRACKED_HINT}, ${replay} ${openFails}`
      );
    } else if (restart) {
      lines.push(
        "The session restarted (a crash or a timeout) while earlier edits were not persisted (a refused, failed or unconfirmed save): the earlier edits were discarded when the engine reloaded the file. Edits made since are not persisted.",
        `Next step: call open_document on ${file} ${UNTRACKED_HINT}, ${replay} ${openFails}`
      );
    } else {
      lines.push(
        "An earlier save was refused because the file changed on disk, and no open_document has succeeded since. Edits made since are not persisted, and re-opening discards them.",
        `Next step: call open_document on ${file} ${UNTRACKED_HINT}, ${replay} ${openFails}`
      );
    }
  } else if (code === "unknown-baseline") {
    // why the session cannot say what is on disk
    const why =
      cause === "unconfirmed-save"
        ? "The last save was not confirmed by the engine (its reply was not `Saved <file>`), so what is on disk is unknown: the edit may or may not have been written."
        : cause === "post-save-read-failed"
          ? `The last save was confirmed, but the file could not be read back afterwards${detail ? ` (${detail})` : ""}, so the session cannot tell whether what is on disk is what it saved.`
          : cause === "capture-failed"
            ? `The file could not be read to compare it with this session's copy${detail ? ` (${detail})` : ""}: it may have been replaced by a link or a special file.`
            : cause === "recreate-path-changed"
              ? recreated
                ? "The file was removed from disk and the path to it is no longer the one this session opened (a directory on the way to it is now a link or has moved), so recreating it could write somewhere else."
                : "The path to the file is no longer the one this session opened (a directory on the way to it is now a link or has moved), so a save could write somewhere else."
              : "This session has no record of what it loaded from the file, so it cannot tell whether the file changed.";
    lines.push(
      why,
      `Next step: call open_document on ${file} ${UNTRACKED_HINT} (it reloads what is on disk and re-baselines), then replay the refused operations in order. ${cause === "unconfirmed-save" ? `${REPLAY_SAFETY_SENTENCE} ` : ""}Keep one writer per file. ${NEVER_BYPASS} If open_document itself fails, stop and tell the user.`
    );
  } else if (code === "unrecognized") {
    lines.push(
      "It exists but is not a recognizable .pen document: unparseable JSON, git conflict markers, or not a Pencil file. The engine would load it as an empty document and the save would destroy content you may still be able to recover.",
      `Next step: open_document a new file path and continue the design there. ${ONLY_COPY_SENTENCE} ${NEVER_BYPASS}`
    );
  } else if (memoryCount === null || memoryCount === undefined) {
    lines.push(
      `It holds ${diskCount} top-level node(s) on disk, but the in-memory document could not be read${memoryReason ? `: ${memoryReason}` : ""}, so the save could not be checked.`,
      `Next step: retry the call; if it keeps failing, open_document a new file path. ${NEVER_BYPASS}`
    );
  } else {
    lines.push(
      `It holds ${diskCount} top-level node(s) on disk, but the in-memory document has ${memoryCount}; saving would replace the file with an empty document.`,
      `Likely cause: the file was never loaded into this session. Next step: call open_document on this file (it now loads the existing content), then re-apply the edit; to start over instead, open_document a new file path. ${NEVER_BYPASS}`
    );
  }
  if (source === "auto-save") {
    lines.push(
      "The edit you just made is applied in memory but not persisted, and will be lost on the next open_document."
    );
  }
  return lines.join("\n");
}

/**
 * First line of a not-persisted outcome that is NOT a refusal:
 * `NOT PERSISTED: [reason=<code>] <file> ...`, codes save-failed (a definite
 * `Save failed:` reply), unconfirmed (an ambiguous, timed-out or unmatched reply) and
 * save-incomplete (the edit applied but the save step threw or did not finish).
 * `detail` is already redacted and capped by the caller; `changed` (save-failed only) says
 * the file's content differs from the baseline after the failed write.
 */
export function notPersistedMessage({ code, file, detail, changed }) {
  const why = detail ? ` (${detail})` : "";
  if (code === "save-failed") {
    if (changed) {
      return [
        `NOT PERSISTED: [reason=save-failed] ${file} was not written cleanly: the engine reported a failed save${why}.`,
        `The edit is applied in memory only, and the file changed during the failed write; the in-memory document is the only complete copy: read it out (get_editor_state, or Get/Print inside batch_design) or export it, then call open_document on ${file}. Further saves are refused until you do.`,
      ].join("\n");
    }
    return [
      `NOT PERSISTED: [reason=save-failed] ${file} was not written: the engine reported a failed save${why}.`,
      `The edit is applied in memory only. Fix the cause (permissions, disk space, path) and call save again. Do NOT call open_document: it discards the edit. ${ONLY_COPY_SENTENCE}`,
    ].join("\n");
  }
  if (code === "unconfirmed") {
    return [
      `NOT PERSISTED: [reason=unconfirmed] ${file} may or may not have been written: the engine's reply was not \`Saved <file>\`${why}.`,
      `Next step: call open_document on ${file} before saving again (it reloads what is on disk and re-baselines) ${UNTRACKED_HINT}, then replay the edit. ${REPLAY_SAFETY_SENTENCE}`,
    ].join("\n");
  }
  if (code === "save-incomplete") {
    return [
      `NOT PERSISTED: [reason=save-incomplete] ${file}: the edit was applied in memory but the save did not complete${why}; it is not persisted.`,
      `The engine was stopped, so the edit in memory is gone with it, and saves are refused until the document is reopened. Next step: call open_document on ${file} ${UNTRACKED_HINT}, then replay the edit. ${REPLAY_SAFETY_SENTENCE}`,
    ].join("\n");
  }
  throw new TypeError(`notPersistedMessage: unknown code '${code}'`);
}

/** The note that prefixes the result of a save that recreated a file removed behind a live session. */
export function recreatedNote(file) {
  return `NOTE: ${file} had been removed from disk (a branch switch, a move or a delete); this save recreated it from the session's copy - tell the user and check that the file belongs at that path`;
}

/**
 * Load fidelity: at load nothing has been edited, so fewer top-level nodes in memory than
 * in the file the engine loaded means it dropped content, and the next save would write
 * the smaller set over the customer's file. Returns the error text, or null when the load
 * is faithful (or there was nothing on disk to compare). `diskCount` is
 * diskTopLevelCount() of the bytes read BEFORE the engine started; `memoryCount` is the
 * engine's count (null = unreadable). A count cannot see nested nodes that were dropped.
 */
export function loadFidelityFailure({ file, diskCount, memoryCount }) {
  if (diskCount === DISK_UNRECOGNIZED) {
    return `${file} exists but is not a recognizable .pen document (the engine loads such a file as empty); it was not modified`;
  }
  if (typeof diskCount !== "number" || diskCount <= 0) return null;
  if (typeof memoryCount === "number" && memoryCount >= diskCount) return null;
  const loaded = memoryCount === null || memoryCount === undefined ? "unreadable" : memoryCount === 0 ? "empty" : String(memoryCount);
  return `${file} holds ${diskCount} top-level node(s) on disk but loaded ${loaded}; it was not modified`;
}

/**
 * A definite failed save: the reply has a `Save failed:` line, no `Saved` line, and is not
 * the confirmation (callers ask isConfirmed first). Empty, timed-out, wrong-path and
 * otherwise unmatched replies are not definite.
 */
export function isDefiniteSaveFailure(raw) {
  if (typeof raw !== "string") return false;
  const lines = stripAnsi(raw).split(/\r?\n/);
  return lines.some((l) => /^Save failed:/.test(l)) && !lines.some((l) => /^Saved\b/.test(l));
}

/** The `Save failed:` line of a reply (ANSI stripped, trimmed), else "". */
export function saveFailureLine(raw) {
  const line = stripAnsi(String(raw ?? "")).split(/\r?\n/).find((l) => /^Save failed:/.test(l));
  return line ? line.trim() : "";
}

// --- The stale-file guard (#11168) -------------------------------------------
//
// The session keeps ONE baseline of the file it is bound to, as a tagged value:
//   { tag: "none" }                          no target bound
//   { tag: "missing" }                       the file was absent when captured
//   { tag: "hash", hash }                    SHA-256 of the canonical document
//   { tag: "unknown", cause, detail? }       a capture, a read-back or a save reply failed
// A present blank file is a `hash` (of the empty bytes), not `missing`.

// Recursive sorted-key JSON: object key order carries no meaning in a .pen document, so a
// formatter that reorders keys must not make every save refuse. Arrays keep their order.
function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value !== null && typeof value === "object") {
    return `{${Object.keys(value)
      .sort()
      .map((k) => `${JSON.stringify(k)}:${canonicalJson(value[k])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

/**
 * SHA-256 (hex) of the canonical JSON of the document: BOM stripped, keys sorted
 * recursively, so line endings, indentation, key order and a formatter cannot make every
 * save refuse. Text that does not parse is hashed as the raw bytes (any change to it is a
 * change).
 */
export function fingerprintBytes(bytes) {
  const buf = Buffer.isBuffer(bytes) ? bytes : Buffer.from(String(bytes ?? ""), "utf8");
  let text = buf.toString("utf8");
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  let material = buf;
  try {
    material = Buffer.from(canonicalJson(JSON.parse(text)), "utf8");
  } catch {
    // not a JSON document: the raw bytes are the fingerprint
  }
  return createHash("sha256").update(material).digest("hex");
}

/** Bytes (Buffer|string) or null (the file does not exist) -> a baseline state. */
export function fingerprintState(bytes) {
  if (bytes === null || bytes === undefined) return { tag: "missing" };
  return { tag: "hash", hash: fingerprintBytes(bytes) };
}

/** First 8 hex characters of a hash, for log lines (never the full value). */
export function hash8(hash) {
  return typeof hash === "string" && /^[0-9a-f]{8,}$/.test(hash) ? hash.slice(0, 8) : "-";
}

/**
 * The stale check: a pure function of the stored baseline, the file as it is now and the
 * refusalPending flag. Only an exact `missing`/`hash` match allows, plus ONE amendment: a
 * `hash` baseline whose file is now missing allows with `recreated: true` (a live engine's
 * in-memory document is then the only copy of the session's saved edits and nothing on
 * disk can be overwritten; the respawn case is refused by the adapter before it gets here).
 *
 * @returns {{ allow: true, recreated?: true } | { allow: false, code: "stale"|"unknown-baseline"|"refusal-pending",
 *            arm: boolean, cause?: string, detail?: string, baselineHash?: string, diskHash?: string, reason: string }}
 */
export function decideStale({ baseline, current, refusalPending }) {
  const baselineHash = baseline?.tag === "hash" ? baseline.hash : undefined;
  const diskHash = current?.tag === "hash" ? current.hash : undefined;
  const refuse = (code, reason, extra = {}) => ({ allow: false, code, reason, arm: false, baselineHash, diskHash, ...extra });
  if (refusalPending) {
    return refuse("refusal-pending", "an earlier save was refused as stale and no open_document has succeeded since");
  }
  if (!baseline || (baseline.tag !== "missing" && baseline.tag !== "hash" && baseline.tag !== "unknown")) {
    return refuse("unknown-baseline", "no baseline: the session has no record of what it loaded", { cause: "no-baseline" });
  }
  if (baseline.tag === "unknown") {
    return refuse("unknown-baseline", "the session cannot tell what is on disk", { cause: baseline.cause ?? "unknown", detail: baseline.detail });
  }
  if (!current || current.tag === "unknown") {
    return refuse("unknown-baseline", "the file could not be read to compare it", {
      cause: current?.cause ?? "capture-failed",
      detail: current?.detail,
    });
  }
  if (baseline.tag === "missing") {
    return current.tag === "missing"
      ? { allow: true }
      : refuse("stale", "the file appeared on disk after this session started on a missing path", { arm: true });
  }
  // baseline.tag === "hash"
  if (current.tag === "missing") return { allow: true, recreated: true };
  if (current.hash === baseline.hash) return { allow: true };
  return refuse("stale", "the file changed on disk since this session loaded or last saved it", { arm: true });
}

/** The path of exactly one `Saved <path>` line (ANSI stripped, trimmed), else null. */
export function savedReplyPath(raw) {
  if (typeof raw !== "string") return null;
  const text = stripAnsi(raw).trim();
  const m = /^Saved ([^\n]+)$/.exec(text);
  return m ? m[1].trim() : null;
}

const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));

function requireDeps(deps, names) {
  for (const name of names) {
    if (typeof deps[name] !== "function") {
      throw new TypeError(`runGuardedSave: dependency '${name}' is required (an unguarded save path is not allowed)`);
    }
  }
}

/**
 * The only save path. Dependencies are injected so the ordering (checks before
 * save, no save sent on refusal) is unit-testable without the MCP SDK.
 *
 *   readDisk()        bytes (Buffer|string) or null when the file does not exist; may throw
 *   probeMemory()     { text, nonce }: the count-snippet reply and the nonce it carried; may throw
 *   readFresh()       like readDisk, called AFTER the probe, immediately before the save
 *   getBaseline()     the stored baseline state
 *   isRefusalPending() the refusalPending flag
 *   send()            emits the engine's save and returns its reply (the adapter's one emission site)
 *   isConfirmed(raw)  true only for `Saved <this file>`
 *   isDefiniteFailure(raw)  optional (default false): true for a definite `Save failed:` reply
 *   readAfterSave()   bytes after a confirmed save; retried 3 times
 *   adoptBaseline(s)  stores a new baseline state (called once per save, after `send`, except
 *                     on a definite failure, which keeps the previous baseline)
 *   canRecreate()     optional: called when the decision is `recreated` and on every save whose
 *                     baseline is a hash; false (or a throw) when the path to the file is no
 *                     longer its canonical one (a directory swapped for a link), which refuses
 *                     as unknown-baseline/recreate-path-changed
 *   wasRestarted()    optional: why the engine was respawned while a refusal was armed
 *                     (false | "restart" | "external-change" | "file-missing" | "failed-write"; wording only)
 *
 * Order: readDisk, probeMemory (only when the file holds nodes), decideSave
 * (empty / unrecognized), readFresh, decideStale, send, readAfterSave, adoptBaseline.
 * Results: `refused` (never sent), `failed` (definite `Save failed:`, baseline kept; the file
 * is read once more and `changedDuringFailedWrite`/`arm` say it no longer matches the baseline),
 * `unconfirmed` (baseline now unknown), `saved`. `recreated: true` marks a decision that
 * allowed a save over a file removed behind a live session.
 */
export async function runGuardedSave(deps) {
  requireDeps(deps, [
    "readDisk",
    "probeMemory",
    "readFresh",
    "getBaseline",
    "isRefusalPending",
    "send",
    "isConfirmed",
    "readAfterSave",
    "adoptBaseline",
  ]);
  const { file, source, readDisk, probeMemory, readFresh, getBaseline, isRefusalPending, send, isConfirmed, readAfterSave, adoptBaseline } = deps;
  const retryDelayMs = deps.retryDelayMs ?? 100;

  let diskCount;
  try {
    diskCount = diskTopLevelCount(await readDisk());
  } catch (err) {
    const reason = String(err?.message ?? err);
    return {
      saved: false,
      refused: true,
      code: "unknown-baseline",
      cause: "capture-failed",
      detail: err?.code,
      reason: `the file could not be read: ${reason}`,
      message: refusalMessage({ file, source, code: "unknown-baseline", cause: "capture-failed", detail: reason }),
    };
  }

  let memoryCount = null;
  let memoryReason;
  if (typeof diskCount === "number" && diskCount > 0) {
    try {
      const { text, nonce } = await probeMemory();
      memoryCount = memoryTopLevelCount(text, nonce);
      if (memoryCount === null) memoryReason = "the count probe reply carried no single count line with this call's nonce";
    } catch (err) {
      memoryReason = String(err?.message ?? err);
    }
  }
  const decision = decideSave({ diskCount, memoryCount });
  if (!decision.allow) {
    return {
      saved: false,
      refused: true,
      code: diskCount === DISK_UNRECOGNIZED ? "unrecognized" : "empty",
      reason: decision.reason,
      message: refusalMessage({
        file,
        source,
        code: diskCount === DISK_UNRECOGNIZED ? "unrecognized" : "empty",
        diskCount,
        memoryCount,
        memoryReason,
      }),
    };
  }

  // The stale decision uses a read taken NOW (after the probe), not the first one.
  let current;
  try {
    current = fingerprintState(await readFresh());
  } catch (err) {
    current = { tag: "unknown", cause: "capture-failed", detail: String(err?.code ?? err?.message ?? err) };
  }
  const stale = decideStale({ baseline: getBaseline(), current, refusalPending: isRefusalPending() });
  if (!stale.allow) {
    return {
      saved: false,
      refused: true,
      code: stale.code,
      reason: stale.reason,
      arm: stale.arm,
      cause: stale.cause,
      detail: stale.detail,
      baselineHash: stale.baselineHash,
      diskHash: stale.diskHash,
      message: refusalMessage({
        file,
        source,
        code: stale.code,
        cause: stale.cause,
        detail: stale.detail,
        restart: typeof deps.wasRestarted === "function" ? deps.wasRestarted() : false,
      }),
    };
  }
  const recreated = stale.recreated === true;
  const baselineHash = getBaseline()?.tag === "hash" ? getBaseline().hash : undefined;
  // The path the engine writes to must still be the canonical one this session opened: a
  // recreate (the file is gone) and every save over a hashed baseline (a directory swapped
  // for a link to a byte-identical copy matches the hash and would be written through).
  if ((recreated || getBaseline()?.tag === "hash") && typeof deps.canRecreate === "function") {
    let canonical = false;
    try {
      canonical = (await deps.canRecreate()) === true;
    } catch {
      // an unanswerable check is a refusal
    }
    if (!canonical) {
      return {
        saved: false,
        refused: true,
        code: "unknown-baseline",
        cause: "recreate-path-changed",
        reason: recreated
          ? "the file was removed and the path to it is no longer the canonical one"
          : "the path to the file is no longer the canonical one",
        baselineHash,
        message: refusalMessage({ file, source, code: "unknown-baseline", cause: "recreate-path-changed", recreated }),
      };
    }
  }

  const raw = await send();
  if (!isConfirmed(raw)) {
    if (typeof deps.isDefiniteFailure === "function" && deps.isDefiniteFailure(raw)) {
      // A definite failure wrote nothing the session cannot detect: the previous baseline
      // stays, so a retry after the cause is fixed is not blocked (a partial write shows up
      // as a changed hash and refuses as stale, the safe direction). The file is read once:
      // a partial write leaves content the baseline does not match, and then the in-memory
      // document is the only complete copy (the caller arms the refusal).
      let changedDuringFailedWrite = false;
      try {
        const now = fingerprintState(await readFresh());
        const expected = recreated ? { tag: "missing" } : getBaseline();
        changedDuringFailedWrite = now.tag !== expected?.tag || (now.tag === "hash" && now.hash !== expected.hash);
      } catch {
        // an unreadable file after the failure makes no claim
      }
      return { saved: false, refused: false, failed: true, recreated, baselineHash, raw, changedDuringFailedWrite, arm: changedDuringFailedWrite };
    }
    adoptBaseline({ tag: "unknown", cause: "unconfirmed-save" });
    return { saved: false, refused: false, unconfirmed: true, recreated, baselineHash, raw };
  }
  let after = null;
  let lastErr = null;
  for (let attempt = 0; attempt < 3 && after === null; attempt++) {
    if (attempt > 0) await sleepMs(retryDelayMs);
    try {
      after = fingerprintState(await readAfterSave());
      if (after.tag === "missing") {
        lastErr = new Error("the file is missing right after a confirmed save");
        lastErr.code = "ENOENT";
        after = null;
      }
    } catch (err) {
      lastErr = err;
      after = null;
    }
  }
  if (after === null) {
    adoptBaseline({ tag: "unknown", cause: "post-save-read-failed" });
    return {
      saved: true,
      refused: false,
      confirmed: true,
      recreated,
      baselineHash,
      raw,
      detail: String(lastErr?.code ?? lastErr?.message ?? lastErr),
      warning: `The save was confirmed, but the file could not be read back (${String(lastErr?.code ?? lastErr?.message ?? lastErr)}); the next save is refused until open_document is called on it.`,
    };
  }
  adoptBaseline(after);
  return { saved: true, refused: false, confirmed: true, recreated, baselineHash, raw };
}
