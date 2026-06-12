#!/usr/bin/env node
// markdown -> Slack mrkdwn converter (self-contained, zero external deps).
//
// Slack messages do NOT render GitHub-flavored Markdown. Slack uses "mrkdwn":
// *bold* (single asterisk), _italic_, ~strike~ (single tilde), <url|label>
// links, and NO heading / table / inline-image syntax. Posting raw GFM to a
// Slack webhook renders the markers as literal characters (`**bold**`,
// `## heading`, `[text](url)` all show verbatim).
//
// This script rewrites the GFM subset that appears in release changelogs into
// mrkdwn while keeping UNTRUSTED input injection-inert: any author-typed
// <!channel>/<@U..>/<#C..>/<!subteam^..> or disguised <url|label> link is
// escaped so it can never fire a mass-ping or mint a link. Slack has no
// API-level mention suppression (unlike Discord's allowed_mentions); escaping
// &, <, > is the only defense. See:
//   - plugins/soleur/skills/ship/references/ci-workflow-authoring.md (convention)
//   - https://docs.slack.dev/messaging/formatting-message-text
//   - knowledge-base/project/learnings/2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md
//
// Usage (CLI): node scripts/md-to-mrkdwn.mjs [--max N] < input.md > output.txt
// API: import { toSlackMrkdwn, truncateMrkdwn } from "./md-to-mrkdwn.mjs";

// Escape the three entities Slack interprets (and un-escapes for display).
// This is the single load-bearing injection defense: an escaped <!channel>
// renders as the literal text "<!channel>", never a live mass-ping.
function esc(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// A URL is only minted into a <url|label> link if it is an absolute http(s)
// or mailto URL. Anything else (relative, javascript:, data:) degrades to
// escaped literal text so the converter can never emit a dangerous link.
function isMintableUrl(url) {
  return /^(https?:\/\/|mailto:)/i.test(url.trim());
}

// Sanitize the URL segment of a minted link: a raw `|` would re-open the
// <url|label> grammar (Slack's 3-entity escape does NOT cover `|`), and raw
// `<`/`>` would break the delimiters. Percent-encode `|`, entity-escape &<>.
function sanitizeLinkUrl(url) {
  return esc(url.trim().replace(/\|/g, "%7C"));
}

// Sanitize the label segment: escape &<> (keeps mentions inert) and strip any
// `|` (which would otherwise re-open the grammar — there is no label-side
// escape for `|` in mrkdwn).
function sanitizeLinkLabel(label) {
  return esc(label.replace(/\|/g, ""));
}

// Mint a <url|label> link, or degrade safely. Returns escaped literal text
// when the URL is not mintable or both segments collapse to nothing.
function mintLink(label, url, originalLiteral) {
  if (!isMintableUrl(url)) return esc(originalLiteral);
  const safeUrl = sanitizeLinkUrl(url);
  const safeLabel = sanitizeLinkLabel(label);
  // Empty label -> bare url (Slack auto-links it); empty url already rejected
  // by isMintableUrl above.
  if (safeLabel.length === 0) return safeUrl;
  return `<${safeUrl}|${safeLabel}>`;
}

// Convert one line of inline (non-code-block) GFM to mrkdwn. Scans left to
// right, matching the highest-priority token at each position; any character
// that is not part of a recognized token is entity-escaped as a text node.
// This single-pass, context-aware design is what lets a converter-minted `<`
// coexist with an escaped author-typed `<` in the same line.
function convertInline(text, refs) {
  let out = "";
  let i = 0;
  const n = text.length;

  while (i < n) {
    const rest = text.slice(i);
    let m;

    // 1. Inline code span: escape-only, never convert (Slack renders mentions
    //    inside backticks, so verbatim would be a mass-ping hole).
    m = /^(`+)([\s\S]*?)\1/.exec(rest);
    if (m && m[2].length >= 0) {
      out += m[1] + esc(m[2]) + m[1];
      i += m[0].length;
      continue;
    }

    // 2. Image ![alt](url) -> degrade to <url|alt> link.
    m = /^!\[([^\]]*)\]\(([^)]*)\)/.exec(rest);
    if (m) {
      out += mintLink(m[1], m[2], m[0]);
      i += m[0].length;
      continue;
    }

    // 3. Inline link [label](url).
    m = /^\[([^\]]*)\]\(([^)]*)\)/.exec(rest);
    if (m) {
      out += mintLink(m[1], m[2], m[0]);
      i += m[0].length;
      continue;
    }

    // 4. Reference link [label][ref] or collapsed [label][].
    m = /^\[([^\]]*)\]\[([^\]]*)\]/.exec(rest);
    if (m) {
      const key = (m[2] || m[1]).toLowerCase();
      const url = refs.get(key);
      if (url) {
        out += mintLink(m[1], url, m[0]);
        i += m[0].length;
        continue;
      }
      // unresolved reference -> fall through to escape the '[' as text
    }

    // 5. Autolink <scheme:...> -> bare unwrapped url (Slack auto-links it).
    //    Reject any inner `|` (would be a disguised link) and any inner <>.
    m = /^<((?:https?:\/\/|mailto:)[^\s<>|]+)>/i.exec(rest);
    if (m) {
      out += m[1];
      i += m[0].length;
      continue;
    }

    // 6. Bare url in prose -> emitted unwrapped (stop at whitespace/<>).
    m = /^(https?:\/\/[^\s<>]+)/i.exec(rest);
    if (m) {
      out += m[1];
      i += m[0].length;
      continue;
    }

    // 7. Bold **x** / __x__ -> *x* (inner re-converted, so nested emphasis and
    //    any mention inside are handled by the recursive call).
    m = /^(\*\*|__)([\s\S]+?)\1/.exec(rest);
    if (m) {
      out += "*" + convertInline(m[2], refs) + "*";
      i += m[0].length;
      continue;
    }

    // 8. Strikethrough ~~x~~ -> ~x~.
    m = /^~~([\s\S]+?)~~/.exec(rest);
    if (m) {
      out += "~" + convertInline(m[1], refs) + "~";
      i += m[0].length;
      continue;
    }

    // 9. Italic *x* / _x_ -> _x_.
    m = /^\*([^\s*][\s\S]*?)\*/.exec(rest) || /^_([^\s_][\s\S]*?)_/.exec(rest);
    if (m) {
      out += "_" + convertInline(m[1], refs) + "_";
      i += m[0].length;
      continue;
    }

    // 10. Plain text node: escape the three Slack entities, emit verbatim
    //     otherwise. This is what neutralizes a raw <!channel> typed in prose.
    const ch = text[i];
    out += ch === "&" ? "&amp;" : ch === "<" ? "&lt;" : ch === ">" ? "&gt;" : ch;
    i += 1;
  }

  return out;
}

const RE_FENCE = /^(\s*)(```|~~~)(.*)$/;
const RE_REF_DEF = /^\s{0,3}\[([^\]]+)\]:\s+(\S+)(?:\s+.*)?$/;
const RE_TABLE_SEP = /^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$/;
const RE_THEMATIC = /^\s*(\*\s*){3,}$|^\s*(-\s*){3,}$|^\s*(_\s*){3,}$/;
const RE_ATX = /^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/;
const RE_BLOCKQUOTE = /^\s{0,3}>\s?(.*)$/;
const RE_TASK = /^(\s*)[-*+]\s+\[([ xX])\]\s+(.*)$/;
const RE_BULLET = /^(\s*)[-*+]\s+(.*)$/;
const RE_ORDERED = /^(\s*)(\d+)\.\s+(.*)$/;

function collectRefs(lines) {
  const refs = new Map();
  for (const line of lines) {
    const m = RE_REF_DEF.exec(line);
    if (m) refs.set(m[1].toLowerCase(), m[2]);
  }
  return refs;
}

// Convert a full markdown document to Slack mrkdwn.
export function toSlackMrkdwn(md) {
  if (!md) return "";
  const lines = md.split("\n");
  const refs = collectRefs(lines);
  const result = [];
  let i = 0;
  let inFence = false;

  while (i < lines.length) {
    const line = lines[i];

    // Fence open/close. Inside a fence, lines are escape-only (no conversion).
    const fence = RE_FENCE.exec(line);
    if (fence) {
      inFence = !inFence;
      result.push("```"); // normalize: strip indent + info string
      i += 1;
      continue;
    }
    if (inFence) {
      result.push(esc(line));
      i += 1;
      continue;
    }

    // Reference-definition lines are consumed (resolved in collectRefs).
    if (RE_REF_DEF.test(line)) {
      i += 1;
      continue;
    }

    // GFM pipe table: header row + separator row -> wrap whole block in a
    // code fence (monospace degrade; Slack has no table syntax).
    if (line.includes("|") && i + 1 < lines.length && RE_TABLE_SEP.test(lines[i + 1])) {
      result.push("```");
      result.push(esc(line));
      let j = i + 1;
      while (j < lines.length && lines[j].includes("|")) {
        result.push(esc(lines[j]));
        j += 1;
      }
      result.push("```");
      i = j;
      continue;
    }

    // Setext H1 (text followed by a === underline) -> bold line.
    if (line.trim() && i + 1 < lines.length && /^\s{0,3}=+\s*$/.test(lines[i + 1])) {
      result.push("*" + convertInline(line.trim(), refs) + "*");
      i += 2;
      continue;
    }

    // Thematic break -> blank line (no HR in mrkdwn). Checked before the
    // bullet rule so a bare `***`/`---`/`___` is not read as a list item.
    if (RE_THEMATIC.test(line)) {
      result.push("");
      i += 1;
      continue;
    }

    let m;
    if ((m = RE_ATX.exec(line))) {
      result.push("*" + convertInline(m[2], refs) + "*");
    } else if ((m = RE_BLOCKQUOTE.exec(line))) {
      result.push("> " + convertInline(m[1], refs));
    } else if ((m = RE_TASK.exec(line))) {
      const glyph = m[2] === " " ? "☐" : "☑";
      result.push(m[1] + "• " + glyph + " " + convertInline(m[3], refs));
    } else if ((m = RE_BULLET.exec(line))) {
      result.push(m[1] + "• " + convertInline(m[2], refs));
    } else if ((m = RE_ORDERED.exec(line))) {
      result.push(m[1] + m[2] + ". " + convertInline(m[3], refs));
    } else {
      result.push(convertInline(line, refs));
    }
    i += 1;
  }

  return result.join("\n");
}

// Structure-aware truncation of already-converted mrkdwn. Cuts at a token
// boundary, never mid-link (no dangling `<url|`), appends an ellipsis, and
// closes an unbalanced code fence. Truncation runs AFTER conversion so the
// cut operates on rendered mrkdwn, not raw GFM.
export function truncateMrkdwn(text, max) {
  if (!Number.isFinite(max) || max <= 0 || text.length <= max) return text;

  let slice = text.slice(0, max - 1);

  // Never cut inside a minted link: if a '<' is still open (no matching '>'
  // after it) in the slice, trim back to before that '<'.
  const lastOpen = slice.lastIndexOf("<");
  const lastClose = slice.lastIndexOf(">");
  if (lastOpen > lastClose) slice = slice.slice(0, lastOpen);

  // Prefer a newline or word boundary if it is not too far back.
  const boundary = Math.max(slice.lastIndexOf("\n"), slice.lastIndexOf(" "));
  if (boundary > max * 0.5) slice = slice.slice(0, boundary);

  slice = slice.replace(/\s+$/, "") + "…";

  // Close an unbalanced code fence so the tail does not render as raw code.
  const fences = (slice.match(/```/g) || []).length;
  if (fences % 2 === 1) slice += "\n```";

  return slice;
}

// --- CLI ---------------------------------------------------------------------
// Runs only when invoked directly (not when imported by the test file).
import { fileURLToPath } from "node:url";

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  let max = 0;
  const maxIdx = process.argv.indexOf("--max");
  if (maxIdx !== -1 && process.argv[maxIdx + 1]) {
    max = parseInt(process.argv[maxIdx + 1], 10) || 0;
  }

  const chunks = [];
  process.stdin.on("data", (c) => chunks.push(c));
  process.stdin.on("end", () => {
    const input = Buffer.concat(chunks).toString("utf8");
    let out = toSlackMrkdwn(input);
    if (max > 0) out = truncateMrkdwn(out, max);
    process.stdout.write(out);
  });
}
