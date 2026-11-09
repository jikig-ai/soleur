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
import { SOLEUR_PLUGIN_PATH_DEFAULT } from "./plugin-path";

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

// git branch — READ-ONLY forms only (#9555). A bare positional arg CREATES a
// branch; -d/-D delete, -m/-M rename, -c/-C copy, -u/--set-upstream-to and
// --unset-upstream write config, -f/--force overwrites, --edit-description
// writes. -q/--quiet is EXCLUDED from the flag set: `git branch -q <name>`
// still creates silently (a one-keystroke repair of a refused write —
// cf. learning 2026-09-24-every-refusal-i-added-…). All such forms fall
// through to the review-gate. Positional args require a list-FORCING flag
// in the leading flag run — verified against git 2.55 (PR #9570 review):
// ONLY --list, --show-current, --contains/--no-contains, --merged/
// --no-merged, --points-at switch the command to list mode, and -a/-r fatal
// on a branch-name arg. The display modifiers (-v/--verbose, --sort=,
// --format=, --color, --column, --ignore-case, --abbrev) do NOT force list
// mode — `git branch -v <name>` CREATES. A positional arg must not start
// with `-` (a branch name can't), so a write flag cannot launder in as a
// pattern arg; `*` is outside PATH_TOKEN so only literal prefixes pass.
const GIT_BRANCH_LIST_FORCE = String.raw`(?:--list|--show-current|--all|--remotes|--contains|--no-contains|--merged|--no-merged|--points-at|-(?=[arv]*[ar])[arv]+)`;
const GIT_BRANCH_READ_FLAG = String.raw`(?:${GIT_BRANCH_LIST_FORCE}|-[v]+|--verbose|--sort=${PATH_TOKEN}|--format=${PATH_TOKEN}|--abbrev(?:=\d+)?|--column|--no-column|--color(?:=${PATH_TOKEN})?|--no-color|--ignore-case)`;

// git log|diff|show — the CLOSED flag grammar (#9600). ADMISSION RULE: a flag is added here only
// with a row in test/safe-bash-git-config-exec.test.ts showing real git never runs a repo-config
// helper, writes a file or reads an arbitrary file because of it, and never adds an exec channel the bare
// verb does not already have (so --no-ext-diff / --no-textconv are OUT: they swap one config-driven
// channel for another), plus a safe-bash test. A flag is NEVER admitted by prefix or by a generic
// `--[\w-]+=value` shape: only exact spellings count. A flag that is ABSENT is "not yet measured", not
// "known dangerous": most of what falls to the review card (-w, --follow, --date=, --color, -M,
// --check, --exit-code, --quiet ...) is inert, and the fall-through telemetry in permission-callback.ts
// is how the list is widened by evidence. Flags that DO ask git to execute a helper or read a file:
// --ext-diff, --textconv, -p/--patch/-u and -U<n> (patch output), -S, -G, -c/--cc (imply -p),
// -O<orderfile> (reads a file), --show-signature (gpg.program), --no-index (reads arbitrary paths),
// --output (writes; also in FILE_WRITE_FLAG_DENYLIST).
const GIT_READ_FLAG_TOKEN = String.raw`(?:--oneline|--stat|--name-only|--name-status|--numstat|--shortstat|--summary|--raw|--graph|--no-patch|-s|--cached|--staged|--no-color|--abbrev-commit|--decorate|--all|--first-parent|--no-merges|--merges|--reverse|-\d+|--max-count=\d+|--(?:since|until|author|grep)=${PATH_TOKEN}|--diff-filter=[A-Za-z]+|--)`;
const GIT_READ_FLAG = String.raw`(?:${GIT_READ_FLAG_TOKEN}|-n\s+\d+)`;
const GIT_READ_FLAG_TOKEN_RE = new RegExp(`^${GIT_READ_FLAG_TOKEN}$`);

/**
 * The first dash-token of a `git log|diff|show` tail that the closed grammar does NOT admit, or `null`
 * when every flag is admitted (the command then missed the allowlist for another reason). Walks the
 * SAME flag source as the allowlist pattern so the telemetry names the flag that actually fell
 * through, not merely the first flag on the line. `-n` is the one two-token flag (`-n 5`).
 */
export function firstRejectedGitFlag(tail: string): string | null {
  const tokens = tail.split(/\s+/).filter(Boolean);
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (!t.startsWith("-")) continue;
    if (t === "-n" && /^\d+$/.test(tokens[i + 1] ?? "")) {
      i += 1;
      continue;
    }
    if (!GIT_READ_FLAG_TOKEN_RE.test(t)) return t;
  }
  return null;
}

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
  // git read-only verbs. `git status` is bare-only. `git log|diff|show` take a CLOSED flag
  // grammar (#9600): every flag must be in GIT_READ_FLAG, a positional must not start with `-`,
  // and anything else — including every unknown flag, every unique-prefix abbreviation and every
  // `--flag=value` outside the list — misses this pattern and falls to the review card (never a
  // hard deny). The prior free tail (`${PATH_TOKEN}` for every token) auto-approved
  // `--ext-diff`, `--textconv`, `-p`, `-S`, `-G`, `-O<file>` and `--show-signature`, each of which
  // asks git to run a repo-config helper (diff.external, textconv, gpg.program) or read a file.
  // A token is EITHER a listed flag OR a non-dash positional, so no token matches both branches
  // and a failing tail cannot backtrack exponentially (the #4868 ReDoS lesson). The
  // FILE_WRITE_FLAG_DENYLIST below still rejects `--output` as a second layer.
  /^git\s+status\s*$/,
  new RegExp(String.raw`^git\s+(?:log|diff|show)(?:\s+(?:${GIT_READ_FLAG}|(?!-)${PATH_TOKEN}))*\s*$`),
  // Arm 1: bare `git branch` or flag-only forms (incl. --show-current, -v).
  new RegExp(String.raw`^git\s+branch(?:\s+${GIT_BRANCH_READ_FLAG})*\s*$`),
  // Arm 2: the leading flag run must contain ≥1 list-FORCING flag before any
  // positional arg (the lookahead), then flags and non-dash args mix freely.
  new RegExp(String.raw`^git\s+branch(?=\s+(?:${GIT_BRANCH_READ_FLAG}\s+)*?${GIT_BRANCH_LIST_FORCE}(?=\s|$))\s+${GIT_BRANCH_READ_FLAG}(?:\s+(?:${GIT_BRANCH_READ_FLAG}|(?!-)${PATH_TOKEN}))*\s*$`),
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
  // code. It now lives in EXACT_LITERAL_SAFE_COMMANDS below as the loader-substituted
  // deployed form (ADR-179 A19, #7453), matched by exact string equality (no
  // denylist relaxation). See isSafeSingleSegment stage 1d.
];

// Exact-literal safe-command carve-out (Slice B, #6121; re-anchored by #7453 — rationale in
// ADR-179 A19). A CLOSED set of the `worktree-manager.sh list|ls` literals the git-worktree
// skill emits, as the SDK loader delivers them: the token substituted with the deployed root
// (`--plugin-dir`; A10 measured the substitution on the CLI, and the SDK uses the same flag).
// Matched by EXACT string equality on the redirect-stripped segment after every denylist
// has run (stage 1d) — zero arg variation, and no denylist is relaxed. An unsubstituted token, or a SOLEUR_PLUGIN_PATH repoint, misses and
// falls back to an approval prompt (fail-safe). The root is the constant, not getPluginPath(),
// so the admitted set cannot depend on the environment at import time. Write verbs stay gated.
const WORKTREE_MANAGER_DEPLOYED_FORM = `bash "${SOLEUR_PLUGIN_PATH_DEFAULT}/skills/git-worktree/scripts/worktree-manager.sh"`;
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
export const TRAILING_SAFE_REDIRECT = /\s+(?:2>\/dev\/null|2>&1)\s*$/;

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
  // Stage 1d: exact-literal carve-out (Slice B, #6121; ADR-179 A19). A CLOSED set of
  // fixed literals no SAFE_BASH_PATTERNS entry matches (a quoted absolute script path).
  // It runs AFTER every denylist, so the carve-out bypasses none of them, and trims only
  // ASCII space/tab — String.trim() also strips \f, NBSP and U+FEFF, which bash does not
  // treat as separators, so `<literal>\u00a0` would reach the script as a different argv.
  // Any arg variation or different path falls through to the allowlist and fails.
  if (EXACT_LITERAL_SAFE_COMMANDS.has(candidate.replace(/^[ \t]+|[ \t]+$/g, ""))) return true;
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
