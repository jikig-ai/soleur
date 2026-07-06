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
// The regex contract is two-stage, applied PER SEGMENT (see the
// `&&`-decomposition carve-out below):
//   1. SHELL_METACHAR_DENYLIST rejects ANY segment containing one of
//      `;`, `&`, `|`, `||`, backtick, `$(`, `${`, `>`, `>>`, `<`,
//      `<<`, newline, carriage return, backslash. Backslash itself is
//      rejected to seal the escape-sneak surface (`pwd\;ls`).
//   2. SAFE_BASH_PATTERNS matches the trimmed segment. Each per-tool
//      pattern uses a narrow path/identifier arg shape — no shell
//      metacharacters allowed in args either.
//
// Two carve-outs relax this for read-only multi-command ergonomics WITHOUT
// weakening the denylist (Issue B part 1):
//   (a) `&&`-decomposition (AC9): `isBashCommandSafe` splits the raw command
//       on `&&` and requires EVERY segment to pass stages 1+2 independently.
//       This is the ONLY reason a `&` may appear in the input — a single `&`
//       never splits, so its segment retains the `&` and stage 1 rejects it.
//       `;`/`|`/`||` are NOT split points: they stay inside a segment and
//       trip stage 1. The denylist regex is unchanged — `&` is still denied
//       per-segment; decomposition happens on the string BEFORE the segment
//       is denylist-checked.
//   (b) Trailing stderr redirect (AC10): a single trailing `2>/dev/null` or
//       `2>&1` is stripped from a segment BEFORE stage 1, so its `>`/`&` do
//       not trip the (unchanged) denylist. File-path redirects survive the
//       strip and are still rejected by stage 1.
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

// gh-arg token (Issue B part 1, AC6): a flag (`--json`, `-R`, `--state`) OR a
// value bareword. Adds `,` to PATH_TOKEN so `--json body,title,state` and
// `--json number,title,state` match. No shell metachars — the raw-string
// SHELL_METACHAR_DENYLIST still rejects `|`/`$`/backtick/`<`/`>` before any
// pattern runs, so a comma is the only extra char this admits over PATH_TOKEN.
const GH_ARG = String.raw`[\w./~+:=@,-]+`;

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
  // git read-only verbs. Arg shape is a SINGLE non-overlapping token branch
  // (`${PATH_TOKEN}` already covers `-flag`, `--flag`, `--flag=value`, paths,
  // and bare numbers — all within the metachar-free PATH_TOKEN charset). The
  // prior multi-branch form (`-[a-zA-Z]+ | --[a-zA-Z][\w-]* | PATH_TOKEN`) was
  // exponentially ambiguous: a `--foo` token matched BOTH the `--flag` branch
  // and the PATH_TOKEN branch, so a failing tail (e.g. a char outside the
  // charset) forced ~2^n backtracking — a per-Bash-call ReDoS reachable under
  // prompt injection (review PR #4868). One branch = linear. The
  // GIT_OUTPUT_REDIRECT_DENYLIST below rejects `--output=<file>` so this
  // read-allowlist cannot be turned into an arbitrary-file-write primitive.
  /^git\s+status\s*$/,
  new RegExp(String.raw`^git\s+log(?:\s+${PATH_TOKEN})*\s*$`),
  new RegExp(String.raw`^git\s+diff(?:\s+${PATH_TOKEN})*\s*$`),
  new RegExp(String.raw`^git\s+show(?:\s+${PATH_TOKEN})*\s*$`),
  new RegExp(String.raw`^git\s+branch(?:\s+${PATH_TOKEN})*\s*$`),
  new RegExp(String.raw`^git\s+rev-parse(?:\s+${PATH_TOKEN})*\s*$`),
  // git config --get only (no --set, no --unset, no --add)
  new RegExp(String.raw`^git\s+config\s+--get(?:\s+[\w.-]+)?\s*$`),
  // echo — quoted strings or barewords
  new RegExp(String.raw`^echo(?:\s+${ECHO_TOKEN})*\s*$`),
  // Read-only `gh` verbs (Issue B part 1, AC6). ONLY view/list/status/diff/
  // checks/repo-view — never a write verb (edit/comment/close/create/merge/
  // review/delete/secret/api). Arg shape: flags + comma-bearing values
  // (`--json body,title,state`). No shell metacharacters reach here — the
  // raw-string denylist already rejected `|`/`$`/backtick/redirects, so a
  // `--jq '.[] | x'` pipe-bearing form falls through to the review-gate.
  new RegExp(String.raw`^gh\s+issue\s+(?:view|list|status)(?:\s+${GH_ARG})*\s*$`),
  new RegExp(String.raw`^gh\s+pr\s+(?:view|list|status|diff|checks)(?:\s+${GH_ARG})*\s*$`),
  new RegExp(String.raw`^gh\s+repo\s+view(?:\s+${GH_ARG})*\s*$`),
  // NOTE (Slice B, #6121/ADR-093): the read-only `worktree-manager.sh (list|ls)`
  // auto-approve is NO LONGER a bare `(?:\./)?plugins/soleur/…` regex here. On the
  // Concierge SERVER surface, a CWD-relative `./plugins/soleur/…` resolves to the
  // connected repo's UNTRUSTED committed copy, so auto-approving it ran untrusted
  // code. It now lives in EXACT_LITERAL_SAFE_COMMANDS below as the deployed
  // `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` form (server → /app deployed copy;
  // CLI → local checkout), matched by exact string equality (no `$`-denylist
  // relaxation). See isSafeSingleSegment stage 0.
];

// Exact-literal safe-command carve-out (Slice B, #6121). A CLOSED set of KNOWN
// fixed command literals that legitimately contain `${CLAUDE_PLUGIN_ROOT:-./plugins/
// soleur}` — a bash DEFAULT-VALUE expansion (`:-`), NOT command substitution
// (`$(…)`) — and would otherwise be rejected by SHELL_METACHAR_DENYLIST at stage 1.
// Matched by EXACT string equality on the trimmed (redirect-stripped) segment, so
// there is ZERO arg-variation / injection surface: only these precise strings pass,
// and their runtime expansion is trusted on BOTH surfaces (server → the platform-
// deployed `/app/shared/plugins/soleur`; CLI → the local `./plugins/soleur`
// checkout). This does NOT loosen the general `$`/`{`/`}` denylist for any other
// command — `${FOO}` / `$(…)` / a `..`-traversal / a different script path all
// still fall through to the denylist (verified in safe-bash.test.ts). Only
// read-only verbs (`list`/`ls`) are included; write verbs (create/cleanup-merged/
// draft-pr) stay gated (they run via the autonomous/sandbox path, never here).
const WORKTREE_MANAGER_DEPLOYED_FORM =
  "bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh";
export const EXACT_LITERAL_SAFE_COMMANDS: ReadonlySet<string> = new Set([
  `${WORKTREE_MANAGER_DEPLOYED_FORM} list`,
  `${WORKTREE_MANAGER_DEPLOYED_FORM} ls`,
]);

// Single source of truth for the safe-bash verb list. Used by the
// per-pattern regexes above (informationally — each regex hardcodes its
// own leading verb) AND by SAFE_BASH_NEAR_MISS_PREFIX below (derived).
// When adding a new safe verb, append it here AND add a per-tool regex
// to SAFE_BASH_PATTERNS — the near-miss prefix updates automatically.
const SAFE_BASH_VERBS = [
  "pwd", "whoami", "id", "date", "hostname",
  "cd", "ls", "cat", "head", "tail", "wc",
  "file", "stat", "which", "uname", "git", "echo",
  "gh", "bash",
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
// Trailing stderr-redirect carve-out (Issue B part 1, AC10). ONLY the exact
// `2>/dev/null` and `2>&1` suffixes are recognized — both discard or merge
// stderr without writing to an arbitrary file. Stripped from a segment BEFORE
// the denylist runs so the suffix's own `>`/`&` don't trip SHELL_METACHAR_
// DENYLIST. File-path redirects (`>`, `>>`, `<`, `>&`) are NOT recognized and
// remain denied because they survive the strip and hit the denylist.
const TRAILING_SAFE_REDIRECT = /\s+(?:2>\/dev\/null|2>&1)\s*$/;

// git/gh write-to-file flag denylist (review PR #4868). `git diff|log|show
// --output=<file>` writes diff content to an arbitrary path — an
// arbitrary-file-write/truncate primitive that the PATH_TOKEN arg shape would
// otherwise auto-approve inside a "read-only" allowlist. `--output` is the
// only file-writing long option reachable by the allowlisted read verbs; the
// `=`-form and the space-separated form are both rejected. Applied to every
// segment (no allowlisted command legitimately uses `--output`).
const FILE_WRITE_FLAG_DENYLIST = /(?:^|\s)--output(?:=|\s|$)/;

/**
 * Is a single command segment (no `&&`) a safe, read-only command?
 *
 * Strips one recognized trailing stderr redirect, then applies the intact
 * SHELL_METACHAR_DENYLIST + PATH_TRAVERSAL_DENYLIST + SAFE_BASH_PATTERNS
 * allowlist. This is the per-segment unit that `isBashCommandSafe` composes
 * across an `&&` chain — each denylist is re-applied here, never relaxed.
 */
function isSafeSingleSegment(segment: string): boolean {
  // Strip a single recognized trailing stderr redirect (AC10). Anything else
  // containing `>`/`<`/`&` survives to the denylist below.
  const candidate = segment.replace(TRAILING_SAFE_REDIRECT, "");
  // Stage 0: exact-literal carve-out (Slice B, #6121). A CLOSED set of known
  // fixed command literals that legitimately carry `${CLAUDE_PLUGIN_ROOT:-…}` (a
  // default-value expansion, not `$(…)`). Matched by EXACT equality on the
  // trimmed segment BEFORE the `$`/`{`/`}` denylist, so these — and ONLY these
  // precise strings — are admitted; any arg variation, injection tail, or
  // different var/path falls through to the intact denylist below. `&&`-chains
  // are still decomposed by isBashCommandSafe, so a `<literal> && evil` segment 2
  // is independently denied. See EXACT_LITERAL_SAFE_COMMANDS.
  if (EXACT_LITERAL_SAFE_COMMANDS.has(candidate.trim())) return true;
  // Stage 1: raw-string metacharacter denylist. Run BEFORE trim so
  // leading/trailing newlines (for example) are caught.
  if (SHELL_METACHAR_DENYLIST.test(candidate)) return false;
  // Stage 1b: parent-dir traversal denylist (#3252). Run BEFORE the
  // per-pattern allowlist so PATH_TOKEN-shape regexes (cd <path>,
  // cat <path>, ls <path>) cannot accept `../` arg shapes.
  if (PATH_TRAVERSAL_DENYLIST.test(candidate)) return false;
  // Stage 1c: reject the `--output=<file>` write flag before the allowlist
  // (review PR #4868) so a read verb cannot write/truncate an arbitrary path.
  if (FILE_WRITE_FLAG_DENYLIST.test(candidate)) return false;
  const trimmed = candidate.trim();
  if (trimmed.length === 0) return false;
  // Stage 2: leading-token allowlist match against trimmed segment.
  for (const pattern of SAFE_BASH_PATTERNS) {
    if (pattern.test(trimmed)) return true;
  }
  return false;
}

export function isBashCommandSafe(command: unknown): boolean {
  if (typeof command !== "string" || command.length === 0) return false;
  if (command.length > SAFE_BASH_MAX_INPUT_LENGTH) return false;
  // Decompose on `&&` ONLY (Issue B part 1, AC9). Each segment must
  // independently be a safe single command. `&&`-decomposition is the ONLY
  // relaxation: it is implemented by splitting, NOT by removing `&`/`>`/`<`
  // from SHELL_METACHAR_DENYLIST. `;`/`|`/`||`/`$`/backtick/redirect stay
  // fully denied because they remain inside a segment and trip the intact
  // per-segment denylist. A single `&` (not `&&`) never splits, so the
  // segment retains it and is rejected. A dangling/leading `&&` yields an
  // empty segment, which fails the trimmed-length-0 check.
  //
  // `isBashCommandBlocked` (permission-callback.ts) is applied to the RAW
  // full command BEFORE this function runs, so a blocked verb anywhere in a
  // chain denies the whole command before decomposition is ever consulted.
  const segments = command.split("&&");
  return segments.every((seg) => isSafeSingleSegment(seg));
}
