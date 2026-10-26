// scrub-transcript.mjs — the one scrubber behind every captured engine transcript
// (fixtures/pen-0.3.13-transcript.txt and the live probe's probe-transcript.md).
//
// scrubTranscript(text, opts)     generic scrub: credential in raw and encoded forms,
//                                 absolute paths and $HOME to placeholders, every UUID
//                                 (incl. a saved document's fileToken) to one synthetic
//                                 value, lines carrying an e-mail address removed.
//                                 `normalize: true` also strips ANSI and collapses the
//                                 run-specific bits (nonce, tool-use id, editId, timings,
//                                 stack frames, base64 payloads) so two runs compare equal.
// createNormalizer(opts)          the same scrub plus numbered node ids (<NODEID1>...) and
//                                 the reverse mapping, used by the capture CLI and by the
//                                 stub replay test so both sides share one definition.
// renderTranscript / parseTranscript   the `> command` / `< stdout` / `! stderr` file format
// replyLines(text, {stripPrompt}) raw stream text to transcript lines
// collapseReply(cmd, out, err)    read_skill replies are third-party markdown: only a marker
// findLeaks(text)                 UUIDs other than the synthetic one, key-shaped strings, e-mail
// gitleaksFindings(file)          runs `gitleaks detect --no-git` on a file; {ok, output}
// scrubFile(in, out, opts)        scrub + leak check + gitleaks; throws on any finding

import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync, copyFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { REPL_PROMPT, redactionForms } from "../../skills/pencil-setup/scripts/pencil-repl-surface.mjs";

export const SYNTHETIC_UUID = "00000000-0000-4000-8000-000000000000";
const UUID_RE = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/g;
const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/;
const ANSI_RE = /\x1b\[[0-9;]*[a-zA-Z]/g;
const KEY_SHAPED_RE = /[A-Za-z0-9+/_=-]{32,}/g;
const SKILL_MARKER = "<SKILL-TEXT>";

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

// ["abs path", "<PLACEHOLDER>"] pairs, longest path first so a child directory is
// replaced before its parent.
function pathPairs(paths) {
  return [...(paths ?? [])]
    .filter(([p]) => typeof p === "string" && p.length > 1)
    .sort((a, b) => b[0].length - a[0].length);
}

export function scrubTranscript(text, opts = {}) {
  const { secrets = [], paths = [], normalize = false } = opts;
  let out = String(text ?? "");
  if (normalize) out = out.replace(ANSI_RE, "");

  for (const secret of secrets) {
    for (const form of redactionForms(secret)) out = out.split(form).join("<REDACTED>");
  }
  for (const [abs, placeholder] of pathPairs(paths)) out = out.split(abs).join(placeholder);

  out = out.replace(UUID_RE, SYNTHETIC_UUID);
  out = out
    .split("\n")
    .filter((line) => !EMAIL_RE.test(line))
    .join("\n");

  if (normalize) {
    out = out
      // collapse a run of stack frames to one marker line
      .replace(/(?:^[ \t]+at [^\n]*(?:\n|$))+/gm, "    at <STACK>\n")
      .replace(/("image": ")[^"]*(")/g, "$1<B64>$2")
      .replace(/[A-Za-z0-9+/]{100,}={0,2}/g, "<B64>")
      .replace(/\btool-use-\d+/g, "tool-use-<N>")
      .replace(/(`editId`: ")[^"]*(")/g, "$1<EDITID>$2")
      .replace(/\bafter \d+ms\b/g, "after <N>ms")
      .replace(/\b[0-9a-f]{32}\b/g, "<NONCE>");
  }
  return out;
}

// Node ids the engine prints for created nodes: `"<name>": "<id>" (= var)` or the
// same without the variable, always at the end of a line.
// get_app_state lists them as `<id>` (<type>): <name> [..], one entry after another.
export function harvestNodeIds(text) {
  const ids = [];
  const plain = String(text ?? "").replace(ANSI_RE, "");
  const found = [];
  for (const m of plain.matchAll(/": "([A-Za-z0-9_-]{3,})"(?: \(= [A-Za-z0-9_$]+\))?$/gm)) found.push([m.index, m[1]]);
  for (const m of plain.matchAll(/(?:^- Top-level nodes: |, )`([A-Za-z0-9_-]{3,})` \(\w+\)/gm)) found.push([m.index, m[1]]);
  for (const [, id] of found.sort((a, b) => a[0] - b[0])) if (!ids.includes(id)) ids.push(id);
  return ids;
}

export function createNormalizer(opts = {}) {
  const ids = [];
  const api = {
    ids,
    harvest(rawText) {
      for (const id of harvestNodeIds(rawText)) if (!ids.includes(id)) ids.push(id);
    },
    scrub(text) {
      let out = scrubTranscript(text, { ...opts, normalize: true });
      ids.forEach((id, i) => {
        out = out.replace(new RegExp(`(?<![A-Za-z0-9_-])${escapeRe(id)}(?![A-Za-z0-9_-])`, "g"), `<NODEID${i + 1}>`);
      });
      return out;
    },
    // A transcript command back to something runnable against a fresh session.
    unscrubCommand(cmd, { nonce = "0123456789abcdef0123456789abcdef" } = {}) {
      return api.unscrubArg(cmd.replace(/<NODEID(\d+)>/g, (m, n) => ids[Number(n) - 1] ?? m).replace(/<NONCE>/g, nonce));
    },
    unscrubArg(arg) {
      let out = arg;
      for (const [abs, placeholder] of pathPairs(opts.paths)) out = out.split(placeholder).join(abs);
      return out;
    },
  };
  return api;
}

// Raw stream text -> transcript lines: ANSI stripped, the trailing prompt dropped
// from stdout, one trailing newline dropped.
export function replyLines(text, { stripPrompt }) {
  let t = String(text ?? "").replace(ANSI_RE, "");
  if (stripPrompt && t.endsWith(REPL_PROMPT)) t = t.slice(0, -REPL_PROMPT.length);
  if (t === "") return [];
  const lines = t.split("\n");
  if (lines[lines.length - 1] === "") lines.pop();
  return lines;
}

// read_skill replies are the vendor's own markdown: the fixture keeps a marker,
// not the text. Applied to both the captured and the replayed reply.
export function collapseReply(cmd, stdout, stderr = []) {
  return /^read_skill\(/.test(cmd) && stderr.length === 0 ? [SKILL_MARKER] : stdout;
}

// ---------------------------------------------------------------------------
// File format.
//   # comment / header
//   @ session <name> <args...>
//   = startup | = exit <code>
//   > <command>      (one line)
//   < <stdout line>  ("<" alone is an empty line)
//   ! <stderr line>  ("!" alone is an empty line)

export function renderTranscript({ header, sessions }) {
  const out = [...header.map((h) => `# ${h}`).map((l) => l.trimEnd())];
  const emit = (marker, lines) => {
    for (const l of lines) out.push(l === "" ? marker : `${marker} ${l}`);
  };
  for (const s of sessions) {
    out.push(`@ session ${s.name}${s.args.length ? " " + s.args.join(" ") : ""}${s.noKey ? " (no key)" : ""}`);
    out.push("= startup");
    emit("<", s.startup.stdout);
    emit("!", s.startup.stderr);
    for (const step of s.steps) {
      out.push(`> ${step.cmd}`);
      emit("<", step.stdout);
      emit("!", step.stderr);
    }
    if (s.exit !== null && s.exit !== undefined) out.push(`= exit ${s.exit}`);
  }
  return out.join("\n") + "\n";
}

export function parseTranscript(text) {
  const header = [];
  const sessions = [];
  let session = null;
  let target = null; // where < and ! lines go
  for (const line of String(text).split("\n")) {
    if (line === "") continue;
    if (line.startsWith("# ")) {
      if (!session) header.push(line.slice(2));
      continue;
    }
    const sm = /^@ session (\S+)(?: (.*?))?(?: \(no key\))?$/.exec(line);
    if (sm) {
      const noKey = line.endsWith(" (no key)");
      const argText = (sm[2] ?? "").replace(/ \(no key\)$/, "");
      session = { name: sm[1], args: argText ? argText.split(" ") : [], noKey, startup: { stdout: [], stderr: [] }, steps: [], exit: null };
      sessions.push(session);
      target = null;
      continue;
    }
    if (!session) throw new Error(`transcript line outside a session: ${line}`);
    if (line === "= startup") {
      target = session.startup;
      continue;
    }
    const em = /^= exit (\d+)$/.exec(line);
    if (em) {
      session.exit = Number(em[1]);
      continue;
    }
    if (line.startsWith("> ")) {
      target = { cmd: line.slice(2), stdout: [], stderr: [] };
      session.steps.push(target);
      continue;
    }
    if (line === "<" || line.startsWith("< ")) {
      target.stdout.push(line === "<" ? "" : line.slice(2));
      continue;
    }
    if (line === "!" || line.startsWith("! ")) {
      target.stderr.push(line === "!" ? "" : line.slice(2));
      continue;
    }
    throw new Error(`unparseable transcript line: ${line.slice(0, 80)}`);
  }
  return { header, sessions };
}

// ---------------------------------------------------------------------------
// Leak checks.

export function findLeaks(text, { secrets = [] } = {}) {
  const leaks = [];
  const t = String(text ?? "");
  for (const m of t.matchAll(UUID_RE)) if (m[0] !== SYNTHETIC_UUID) leaks.push(`uuid:${m[0]}`);
  for (const line of t.split("\n")) if (EMAIL_RE.test(line)) leaks.push(`email:${line.slice(0, 60)}`);
  for (const m of t.replace(UUID_RE, " ").matchAll(KEY_SHAPED_RE)) {
    // placeholders and plain words are not key-shaped; a 32+ run of key alphabet is
    if (/[0-9]/.test(m[0]) && /[A-Za-z]/.test(m[0])) leaks.push(`key-shaped:${m[0].slice(0, 8)}...`);
  }
  for (const secret of secrets) {
    for (const form of redactionForms(secret)) if (t.includes(form)) leaks.push("credential");
  }
  return leaks;
}

// gitleaks reads a directory: copy the one file into a fresh temp directory.
export function gitleaksFindings(file) {
  const dir = mkdtempSync(join(tmpdir(), "gitleaks-scrub-"));
  try {
    copyFileSync(file, join(dir, basename(file)));
    const r = spawnSync("gitleaks", ["detect", "--no-git", "--no-banner", "--redact", "--source", dir], { encoding: "utf8" });
    if (r.error) return { ok: false, output: `gitleaks could not run: ${r.error.message}`, missing: true };
    return { ok: r.status === 0, output: `${r.stdout}${r.stderr}`.slice(0, 2000), missing: false };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// Scrub a file's text, check for leaks and run gitleaks on the result. Throws on
// any finding (a missing gitleaks binary is a failure too: no unchecked output).
export function scrubFile(inPath, outPath, opts = {}) {
  const scrubbed = scrubTranscript(readFileSync(inPath, "utf8"), opts);
  writeFileSync(outPath, scrubbed);
  const leaks = findLeaks(scrubbed, { secrets: opts.secrets });
  if (leaks.length > 0) throw new Error(`scrubbed output still has leaks: ${leaks.slice(0, 5).join(", ")}`);
  const g = gitleaksFindings(outPath);
  if (!g.ok) throw new Error(`gitleaks finding or failure: ${g.output}`);
  return scrubbed;
}
