// Safe-Bash allowlist (plan: 2026-04-29-fix-command-center-qa-permissions).
// Extracted from `permission-callback.ts` for unit testability and to keep
// the callback file focused on the canUseTool decision flow (following the
// `tool-tiers.ts` / `tool-path-checker.ts` / `review-gate.ts` extraction
// pattern). The near-miss WeakMap stays in `permission-callback.ts` because
// it is keyed by `CanUseToolContext`; moving it here would create a cyclic
// import.
//
// Auto-approves read-only file/git/cwd inspection commands BEFORE the
// review-gate. Every entry is a LEADING-TOKEN regex against the trimmed
// command — substring matches do NOT count, so `pwd && curl evil` cannot
// match the `pwd` entry.
//
// The regex contract is two-stage:
//   1. SHELL_METACHAR_DENYLIST rejects ANY raw command containing one of
//      `;`, `&`, `&&`, `|`, `||`, backtick, `$(`, `${`, `>`, `>>`, `<`,
//      `<<`, newline, carriage return. Single-regex check on the raw
//      string (not after splitting) so escape-sneak attempts (`pwd\;ls`)
//      cannot launder through. Backslash itself is rejected to seal the
//      escape-sneak surface.
//   2. SAFE_BASH_PATTERNS matches the trimmed command. Each per-tool
//      pattern uses a narrow path/identifier arg shape — no shell
//      metacharacters allowed in args either.
//
// `find` and `grep` are intentionally OMITTED — both accept `-exec` and
// could shell out. `find` is also redundant with the SDK's `Glob` tool
// which is auto-allowed via FILE_TOOLS.
//
// `printenv` is intentionally OMITTED — without an arg it dumps the
// entire env (BYOK key, service tokens). Even with an arg, the env may
// hold secrets the agent never needs to read; users who want a single
// var should let the agent ask for it via the review-gate.
//
// `$` is in the metachar denylist so `echo "$VAR"` (which bash expands
// inside double quotes) is rejected. U+2028 / U+2029 are included to
// match the project's Unicode line-separator hardening pattern. The
// full C0 range (`\x00-\x1f`) plus DEL (`\x7f`) is rejected to seal
// log-injection / null-byte truncation surfaces — `\n` (`\x0a`) and
// `\r` (`\x0d`) fall inside that range and are therefore double-covered.
const SHELL_METACHAR_DENYLIST = /[;&|`<>$\\\x00-\x1f\x7f\u2028\u2029]/;
// Path-traversal denylist (#3252). Matches `..` only as a parent-dir segment
// — preceded by start-of-string, slash, or whitespace AND followed by
// end-of-string, slash, or whitespace. Filenames containing `..` (such as
// `..baz`, `my..backup.txt`, `...gitignore`, `....file`) are NOT matched.
//
// **DO NOT REMOVE** this denylist without auditing every PATH_TOKEN-using
// regex above for `..` acceptance. The `cd` regex (and other PATH_TOKEN
// args like `cat <path>`) accepts `../foo` as a path arg by token shape;
// this denylist is the only thing that rejects parent-dir traversal at
// the canUseTool boundary. extractToolPath/isPathInWorkspace does NOT
// apply to Bash (Bash uses `command`, not `file_path`/`path`), so the
// workspace-relative invariant is enforced here.
const PATH_TRAVERSAL_DENYLIST = /(?:^|[\s/])\.\.(?:$|[\s/])/;
// Belt-and-suspenders: a 4096-char input cap before regex matching keeps
// pathological-length inputs from amplifying any backtracking cost.
const SAFE_BASH_MAX_INPUT_LENGTH = 4096;

// Path/identifier arg shape: word chars, slash, dot, tilde, plus, colon,
// equals, hyphen, at-sign. No shell-special chars, no spaces inside a
// single token.
const PATH_TOKEN = String.raw`[\w./~+:=@-]+`;

// Quoted-or-bareword token for `echo` — accepts `"hello world"`,
// `'foo bar'`, or path-shape barewords. The metachar denylist already
// rejects `$`/backtick at the raw-string level, so quoted strings here
// cannot contain expansion sigils.
const ECHO_TOKEN = String.raw`(?:"[^"\\]*"|'[^'\\]*'|[\w./~+:=@-]+)`;

export const SAFE_BASH_PATTERNS: readonly RegExp[] = [
  // No-arg / fixed-form commands
  /^pwd\s*$/,
  /^whoami\s*$/,
  /^id\s*$/,
  /^date\s*$/,
  /^hostname\s*$/,
  // cd — optional single path arg. No flags (cd -, cd --, cd -P all
  // rejected via the negative lookahead). The `..` arg shape is
  // structurally accepted by PATH_TOKEN here but PATH_TRAVERSAL_DENYLIST
  // in isBashCommandSafe rejects it before this pattern runs; see TS6
  // for the regression pin.
  new RegExp(String.raw`^cd(?:\s+(?!-)${PATH_TOKEN})?\s*$`),
  // ls — optional flags + optional path args
  new RegExp(String.raw`^ls(?:\s+-[a-zA-Z]+)*(?:\s+${PATH_TOKEN})*\s*$`),
  // Single-arg path-taking commands
  new RegExp(String.raw`^cat\s+${PATH_TOKEN}\s*$`),
  new RegExp(String.raw`^head(?:\s+-n\s+\d+)?\s+${PATH_TOKEN}\s*$`),
  new RegExp(String.raw`^tail(?:\s+-n\s+\d+)?\s+${PATH_TOKEN}\s*$`),
  new RegExp(String.raw`^wc(?:\s+-[a-zA-Z]+)?\s+${PATH_TOKEN}\s*$`),
  new RegExp(String.raw`^file\s+${PATH_TOKEN}\s*$`),
  new RegExp(String.raw`^stat\s+${PATH_TOKEN}\s*$`),
  new RegExp(String.raw`^which\s+${PATH_TOKEN}\s*$`),
  // uname with optional flags
  /^uname(?:\s+-[a-zA-Z]+)*\s*$/,
  // git read-only verbs
  /^git\s+status\s*$/,
  new RegExp(
    String.raw`^git\s+log(?:\s+(?:-[a-zA-Z]+|--[a-zA-Z][\w-]*(?:=[\w./~+:=@-]+)?|-n\s+\d+|\d+|${PATH_TOKEN}))*\s*$`,
  ),
  new RegExp(
    String.raw`^git\s+diff(?:\s+(?:-[a-zA-Z]+|--[a-zA-Z][\w-]*(?:=[\w./~+:=@-]+)?|${PATH_TOKEN}))*\s*$`,
  ),
  new RegExp(
    String.raw`^git\s+show(?:\s+(?:-[a-zA-Z]+|--[a-zA-Z][\w-]*(?:=[\w./~+:=@-]+)?|${PATH_TOKEN}))*\s*$`,
  ),
  new RegExp(
    String.raw`^git\s+branch(?:\s+(?:-[a-zA-Z]+|--[a-zA-Z][\w-]*|${PATH_TOKEN}))*\s*$`,
  ),
  new RegExp(
    String.raw`^git\s+rev-parse(?:\s+(?:-[a-zA-Z]+|--[a-zA-Z][\w-]*|${PATH_TOKEN}))*\s*$`,
  ),
  // git config --get only (no --set, no --unset, no --add)
  new RegExp(String.raw`^git\s+config\s+--get(?:\s+[\w.-]+)?\s*$`),
  // echo — quoted strings or barewords
  new RegExp(String.raw`^echo(?:\s+${ECHO_TOKEN})*\s*$`),
];

// Single source of truth for the safe-bash verb list. Used by the
// per-pattern regexes above (informationally — each regex hardcodes its
// own leading verb) AND by SAFE_BASH_NEAR_MISS_PREFIX below (derived).
// When adding a new safe verb, append it here AND add a per-tool regex
// to SAFE_BASH_PATTERNS — the near-miss prefix updates automatically.
const SAFE_BASH_VERBS = [
  "pwd", "whoami", "id", "date", "hostname",
  "cd", "ls", "cat", "head", "tail", "wc",
  "file", "stat", "which", "uname", "git", "echo",
] as const;

// Near-miss prefix detection (#3252). Matches commands whose leading
// token starts with a known safe-bash allowlist verb but extends past
// it (lsof vs ls, cdrecord vs cd, pwdx vs pwd, catatonic vs cat).
// Used only for telemetry — the rejection path is the same either way
// (review-gate). When this fires, on-call sees drift before someone
// widens the allowlist into a confused-deputy escape.
//
// Surface intentionally includes lsblk/lsattr/lscpu/lsmod/lspci/lsusb/
// etc. — these ARE near-misses to `ls`, and the drift signal is correct.
// Operators monitoring `safe-bash-near-miss` should expect such tokens
// in normal exploration noise (see plan §Risks R5).
export const SAFE_BASH_NEAR_MISS_PREFIX = new RegExp(
  String.raw`^(?:${SAFE_BASH_VERBS.join("|")})\w`,
);

/**
 * Returns true iff `command` is a single, read-only file/git/cwd
 * inspection command safe to auto-approve without a user gate.
 *
 * Rejects:
 *   - non-string / empty input (defensive),
 *   - any command containing shell metacharacters (compound, redirect,
 *     subshell, expansion, escape),
 *   - any command whose leading token is not in SAFE_BASH_PATTERNS,
 *   - any command whose argument shape doesn't match the tight per-tool
 *     pattern.
 *
 * The check runs AFTER `isBashCommandBlocked` in the canUseTool flow so
 * the blocklist is authoritative when both could match.
 */
export function isBashCommandSafe(command: unknown): boolean {
  if (typeof command !== "string" || command.length === 0) return false;
  if (command.length > SAFE_BASH_MAX_INPUT_LENGTH) return false;
  // Stage 1: raw-string metacharacter denylist. Run BEFORE trim so
  // leading/trailing newlines (for example) are caught.
  if (SHELL_METACHAR_DENYLIST.test(command)) return false;
  // Stage 1b: parent-dir traversal denylist (#3252). Run BEFORE the
  // per-pattern allowlist so PATH_TOKEN-shape regexes (cd <path>,
  // cat <path>, ls <path>) cannot accept `../` arg shapes. Filenames
  // starting with `..` (e.g. `..baz`) are not matched — see the regex
  // definition. Bash uses `command`, not `file_path`/`path`, so the
  // canUseTool's isFileTool→isPathInWorkspace defense does NOT fire
  // for Bash invocations. This denylist is the canUseTool-boundary
  // check; the bubblewrap sandbox is the OS-syscall-boundary check.
  if (PATH_TRAVERSAL_DENYLIST.test(command)) return false;
  const trimmed = command.trim();
  if (trimmed.length === 0) return false;
  // Stage 2: leading-token allowlist match against trimmed string.
  for (const pattern of SAFE_BASH_PATTERNS) {
    if (pattern.test(trimmed)) return true;
  }
  return false;
}
