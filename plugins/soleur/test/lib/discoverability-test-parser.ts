/**
 * Reference implementation of preflight Check 10's parser + classifier.
 *
 * The production runtime is the bash in `plugins/soleur/skills/preflight/SKILL.md`
 * §"Check 10: Discoverability Test Execution". This TypeScript mirror exists
 * so the decision matrix can be unit-tested without subshells, fake `curl`,
 * or live network. If the bash and TS drift, the bash wins and this file
 * is the bug.
 */

export type ExecResult = { rc: number; stdout: string };
export type Executor = (cmd: string, timeoutMs: number) => Promise<ExecResult>;

/**
 * `discoverability_test.kind` — which property Check 10 is able to observe.
 *
 * - `live-probe` (the default when `kind:` is absent) — today's behaviour,
 *   byte-for-byte: the command is executed and its output matched.
 * - `run-log` — the evidence lives in a run log that does not exist yet at
 *   preflight time (e.g. `gh run view <run-id> --log`). Check 10 declines to
 *   execute and returns SKIP **with the marker recorded**, so a post-merge
 *   follow-through can assert it.
 *
 * `run-log` is not a weakening: guardrails 4 and 5 (below) require that a real
 * emitter for the marker exists in the tree and that the declared command
 * actually names it — assertions the live-probe path never makes.
 */
export type DiscoverabilityKind = "live-probe" | "run-log";

export type ClassificationResult = {
  result: "PASS" | "FAIL" | "SKIP";
  reason?: string;
  /** Set only on a valid `kind: run-log` SKIP — the recorded marker literal. */
  marker?: string;
};

export type ClassifyInput = {
  planPath: string;
  planBody: string;
  prBody: string;
  runner: Executor;
  timeoutMs?: number;
  /**
   * Guardrail 4's oracle: does an emitter for `marker` exist in the tree
   * OUTSIDE planning artifacts? Injected so this module stays pure and so
   * fixtures 09 (emitter present) and 11 (emitter absent) — which are
   * otherwise byte-identical in shape — are distinguishable.
   *
   * The production runtime supplies
   *   git grep -F -- "$MARKER" -- <EMITTER_ALLOWLIST_PATHSPECS>
   * i.e. a POSITIVE allowlist of emitter directories, not a blacklist. The
   * previous two-entry blacklist (`:!knowledge-base/project/{plans,specs}`) was
   * self-satisfiable: any OTHER author-controlled file counted, so this PR's own
   * test fixture `09-run-log-pass.md` satisfied its own marker. See
   * `EMITTER_ALLOWLIST_PATHSPECS` for the list and its `:(top)` rationale.
   *
   * Defaults to fail-closed (`() => false`) — an omitted oracle must never
   * silently satisfy the guardrail.
   */
  markerLookup?: (marker: string) => boolean;
};

// A NEGATED word-character class, not `\s`/`\b`. Two properties are load-bearing:
//
//  1. No JS-`\s`-vs-bash-`[[:space:]]` drift. `\s` in JS matches Unicode
//     whitespace (U+00A0, U+2028, …) that bash `[[:space:]]` in C-locale does
//     not, so a `\s`-based reject and its bash mirror would disagree on exotic
//     separators. `[^A-Za-z0-9_.-]` is expressible IDENTICALLY in JS regex and
//     bash ERE and therefore cannot drift.
//  2. Every shell metacharacter is a delimiter. The previous form only accepted
//     whitespace, `/`, or start-of-string before `ssh`, so `|ssh`, `;ssh`,
//     `&&ssh` and `"ssh"` all slipped through. On origin/main that gap was
//     masked because the substitution reject ran unconditionally and tripped on
//     the `|`/`;`/`&&`; once the substitution reject moved below the run-log
//     branch the gap became a live bypass of hr-no-ssh-fallback-in-runbooks.
//
// Matches:     `ssh h`, `|ssh`, `;ssh`, `&&ssh`, `"ssh"`, `/usr/bin/ssh`, bare `ssh`.
// Does NOT match: `sshd`, `pushshell`, `SOLEUR_ssh_x`, `ssh.example.com` as a
// suffix of a longer identifier — `.`, `-` and `_` stay word characters so
// marker/hostname identifiers containing `ssh` are not false positives.
const SSH_REJECT_RE = /(^|[^A-Za-z0-9_.-])ssh([^A-Za-z0-9_.-]|$)/;

// The run-log endorsement reject. Nothing is EXECUTED under `kind: run-log`, so
// these tokens carry no execution risk here — but the SKIP message reads
// "Verified statically: an emitter exists and the command names it", which
// ENDORSES the command to a human who may later paste it into a shell. A
// `$TOKEN`-exfiltrating or command-chaining command must not receive that
// endorsement.
//
// Deliberately NARROWER than SUBST_REJECT_RE: bare `|`, `<` and `>` are ALLOWED
// because the canonical run-log command is
// `gh run view <run-id> --log | grep MARKER` — it needs the pipe, and `<`/`>`
// for the `<run-id>` placeholder. Applying the full live-probe reject here
// would reject the feature's own canonical shape.
//
// Rejected: $( , backtick, <( , >( , ; , && , || , & , $VAR / ${VAR}.
const RUNLOG_SUBST_REJECT_RE = /(\$\(|`|<\(|>\(|;|&&|\|\||&|\$\{?[A-Za-z_])/;

// Credentialed CLIs — mirrors SKILL.md Step 10.4. Check 10 runs `$CMD` with the
// operator's ambient FILE-BACKED CLI auth reachable: `env -i` scrubs env vars
// but preserves $HOME, so e.g. the Doppler CLI still reads a live `dp.ct.*`
// token from its on-disk config under ~/.doppler/.
//
// This is the load-bearing control for the #6772 folded-scalar fix, which is a
// fail-open transition — commands that used to parse to the literal `>` and
// self-reject now reach execution. A folded scalar joins with a SPACE and so
// carries no shell-active token by construction; SUBST_REJECT_RE therefore
// covers none of that class. Only this verb reject does.
//
// The `/` in the leading class catches `/usr/local/bin/gh`; the trailing
// boundary keeps `curl https://app.soleur.ai/highlights` runnable.
const CRED_REJECT_RE =
  /(^|[\t\n\r \f\v/])(doppler|gh|aws|supabase|stripe|hcloud|wrangler|terraform|flyctl|vercel)([\t\n\r \f\v]|$)/;

// Bash resolves `"doppler"`, `\doppler` and `dopp""ler` to the same binary, but the
// word-boundary anchors above cannot see through the quote characters. Strip them
// from a COPY before matching — mirrors the `CMD_DEQ` substitution in SKILL.md
// Step 10.4. Never strip from the string that would be executed.
const dequote = (cmd: string): string => cmd.replace(/["'\\]/g, "");

// Shell-active tokens that route command output / chain commands / spawn
// subshells / expand vars. The plan author is trust-on-PR-review but the env
// scrub in SKILL.md Step 10.5 is the load-bearing mitigation — this regex
// is defense-in-depth. Note: `$` (parameter expansion) IS rejected to block
// `curl https://api.example.com/?leak=$TOKEN` even with env scrub.
//
// `\n` closes BLOCK-mode chaining only: a block scalar joins with newlines,
// which `bash -c` runs as separate statements. It contributes zero coverage to
// folded scalars — see CRED_REJECT_RE above.
const SUBST_REJECT_RE = /(\$\(|`|<\(|>\(|;|&&|\|\||\||>|<|&|\n|\$\{?[A-Za-z_])/;

// Return the body of EVERY `## Observability` section (each: lines after the
// heading up to the next `^## ` heading). A doc may carry several such sections
// (e.g. plan-issue-templates.md ships one per verbosity tier), which the
// schema-parity guard walks. `extractObservabilityBlock` below is the
// first-block-only view the preflight runtime consumes.
export function extractAllObservabilityBlocks(planBody: string): string[] {
  return extractBlocksMatching(planBody, /^## Observability(?:\s|$)/);
}

/**
 * ‼️ ANCHORED heading match — `/^## Observability$/`, NOT the prefix form.
 *
 * The preflight runtime's awk is anchored (`/^## Observability$/`, SKILL.md
 * Step 10.3, load-bearing per #6698). A prefix match here diverges from the
 * bash in BOTH directions, measured:
 *
 *  - Plan with `## Observability layer citation` before the real section (a
 *    heading `hr-observability-layer-citation` actively encourages): bash
 *    extracts the real block and PASSes; the prefix mirror extracted the
 *    citation and FAILed.
 *  - Plan whose only such heading is `## Observability / Rollback` (this shape
 *    exists on disk — see
 *    knowledge-base/project/plans/2026-04-17-fix-settings-nav-expanded-chevron-alignment-plan.md):
 *    bash yields 0 bytes and FAILs; the prefix mirror yielded a block and
 *    parsed on.
 *
 * The anchor belongs on THIS single-block runtime view only.
 * `extractAllObservabilityBlocks` keeps the prefix form for its second
 * consumer — the schema-parity guard walking `plan-issue-templates.md`'s
 * per-tier sections (`observability-schema-parity.test.ts`).
 */
export function extractObservabilityBlock(planBody: string): string {
  return extractBlocksMatching(planBody, /^## Observability$/)[0] ?? "";
}

// Shared walker: body lines after each heading matching `headingRe`, up to the
// next `^## ` heading.
function extractBlocksMatching(planBody: string, headingRe: RegExp): string[] {
  const lines = planBody.split(/\r?\n/);
  const blocks: string[] = [];
  let collected: string[] | null = null;
  for (const line of lines) {
    if (headingRe.test(line)) {
      if (collected) blocks.push(collected.join("\n"));
      collected = [];
      continue;
    }
    if (collected && /^## /.test(line)) {
      blocks.push(collected.join("\n"));
      collected = null;
      continue;
    }
    if (collected) collected.push(line);
  }
  if (collected) blocks.push(collected.join("\n"));
  return blocks;
}

// Horizontal whitespace, POSIX [[:space:]] minus \n (lines are already split)
// and minus \r (stripped by the split — the documented CRLF divergence from awk).
// Deliberately NOT `\s`, which matches Unicode whitespace bash does not.
const H = "[ \\t\\f\\v]";
const FOLD_HEADER_RE = new RegExp(`^${H}*command:${H}*>[-+]?${H}*(#.*)?$`);
const BLOCK_HEADER_RE = new RegExp(`^${H}*command:${H}*\\|[-+]?${H}*(#.*)?$`);
const INLINE_KEY_RE = new RegExp(`^${H}*command:${H}*(\\S.*)$`);
const BLANK_RE = new RegExp(`^${H}*$`);

const indentOf = (line: string): number =>
  (new RegExp(`^${H}*`).exec(line)?.[0] ?? "").length;

export function parseCommand(observabilityBlock: string): string {
  const lines = observabilityBlock.split(/\r?\n/);

  // Form A — strict YAML key (strongest signal).
  //
  // Mirrors plugins/soleur/skills/preflight/scripts/parse-form-a.awk. That file
  // is authoritative; if these drift, the awk wins and this is the bug.
  //
  // Scalar extent follows YAML indent semantics: a continuation is a non-empty
  // line indented MORE than the `command:` key, and the first line indented <=
  // the key ends the scalar. No key-name matching — a key regex both truncates
  // legitimate content (a jq object filter's `host_present:`) and leaves a
  // differential where a LESS-indented non-key line is consumed anyway, which a
  // PR reviewer reads as outside the command but the shell executes.
  let mode: "fold" | "block" | null = null;
  let keyIndent = 0;
  const scalarLines: string[] = [];
  for (const line of lines) {
    if (mode === null) {
      // Fold/block headers MUST be tested before the inline rule: the inline
      // pattern also matches `command: >-` and would return the literal
      // indicator, which then self-rejects as a shell-active token (#6772).
      if (FOLD_HEADER_RE.test(line)) {
        mode = "fold";
        keyIndent = indentOf(line);
        continue;
      }
      if (BLOCK_HEADER_RE.test(line)) {
        mode = "block";
        keyIndent = indentOf(line);
        continue;
      }
      const inlineKey = line.match(INLINE_KEY_RE);
      if (inlineKey) return stripQuotes(inlineKey[1].trim());
      continue;
    }
    // Blank lines are legal inside a scalar and carry no indentation, so this
    // MUST precede the terminator or indentOf("") === 0 would end every scalar
    // at its first blank line. The awk drops them; this mirrors that (it used
    // to push "" and emit a spurious empty line).
    if (BLANK_RE.test(line)) continue;
    if (indentOf(line) <= keyIndent) break;
    scalarLines.push(line.replace(new RegExp(`^${H}+`), ""));
  }
  if (scalarLines.length > 0) {
    return scalarLines.join(mode === "fold" ? " " : "\n");
  }

  // Form B — prose `discoverability_test` marker + first fenced code block.
  let sawMarker = false;
  let inFence = false;
  const fenceLines: string[] = [];
  for (const line of lines) {
    if (!sawMarker && /discoverability_test/.test(line)) {
      sawMarker = true;
      continue;
    }
    if (!sawMarker) continue;
    if (/^\s*```/.test(line)) {
      if (!inFence) {
        inFence = true;
        continue;
      }
      break;
    }
    if (inFence) {
      if (/^\s*#/.test(line)) continue;
      fenceLines.push(line);
    }
  }
  return fenceLines.join("\n").trim();
}

export function parseExpected(observabilityBlock: string): string {
  const lines = observabilityBlock.split(/\r?\n/);
  for (const line of lines) {
    const yamlKey = line.match(/^\s*expected_output:\s*(.+)$/);
    if (yamlKey) return stripQuotes(yamlKey[1].trim());
  }
  // Prose form accepts bold-wrapped (`**Expected output:**`) since markdown
  // plans frequently bold the inline label. Both `Expected output:` and
  // `**Expected output:**` produce the same captured value.
  for (const line of lines) {
    const prose = line.match(/^\s*(?:\*\*)?Expected output:(?:\*\*)?\s*(.+)$/i);
    if (prose) return stripQuotes(prose[1].trim());
  }
  return "";
}

export function matchExpected(expected: string, actualStdout: string): boolean {
  const normalized = actualStdout.replace(/\n+$/, "").trim();
  if (normalized === "") return false;
  const tokens = tokenizeExpected(expected);
  return tokens.some((tok) => {
    if (tok === "") return false;
    // Short tokens (≤ 2 chars) match only when stdout is exactly the token —
    // prevents `expected_output: "0"` matching every HTTP error response that
    // happens to contain a `0` digit (500, 404, 200, 302, etc.).
    if (tok.length <= 2) return normalized === tok;
    return normalized.includes(tok);
  });
}

export function tokenizeExpected(expected: string): string[] {
  return expected
    .split(/,|\s+or\s+|\bor\b|[`"'\[\]/]+/i)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

/**
 * The SSH reject. Runs UNCONDITIONALLY for every `kind` — see F2 in the plan.
 *
 * This was deliberately split out of the old fused `rejectReason`. If it sat
 * behind the `kind` branch, `kind: run-log` + `command: ssh host 'grep M …'`
 * would return SKIP and `hr-no-ssh-fallback-in-runbooks` would be silently
 * defeated. Never move this below kind resolution.
 */
export function sshRejectReason(cmd: string): string | null {
  if (SSH_REJECT_RE.test(cmd)) {
    return "discoverability_test.command contains ssh (rule violation per hr-observability-as-plan-quality-gate)";
  }
  return null;
}

/**
 * The shell-substitution reject. Applies to `live-probe` ONLY, because it is a
 * property of *executing* the command — under `run-log` nothing is executed, so
 * the tokens carry no execution risk (a run-log command is characteristically
 * `gh run view <run-id> --log | grep MARKER`, which trips `|`, `<` and `>`).
 *
 * The message string is operator-facing and is asserted verbatim downstream —
 * it enumerates every rejected token. Do not reword it.
 *
 * Also carries the CREDENTIALED-CLI reject, which arrived on main as part of the
 * fused `rejectReason` this function was split out of. It belongs HERE, not in
 * `sshRejectReason`, for the same reason the token reject does: it is an
 * execution property. Putting it on the unconditional path would break the
 * feature's own canonical run-log shape — `gh` is in CRED_REJECT_RE and the
 * documented run-log command is `gh run view <run-id> --log | grep MARKER`, so a
 * run-log-applicable cred reject would refuse every correct run-log plan.
 */
export function substRejectReason(cmd: string): string | null {
  // Ordered to mirror the runtime: Step 10.4's verb rejects run before Step
  // 10.5's shell-active-token reject.
  if (CRED_REJECT_RE.test(dequote(cmd))) {
    return "discoverability_test.command invokes a credentialed CLI; refusing to run. Check 10 executes with the operator's ambient file-backed CLI auth reachable (env -i does NOT scrub it — $HOME is preserved, so the Doppler CLI token, SSH private keys, netrc, git credentials, AWS credentials, the gcloud credentials database, and the Docker config are all readable). Use an unauthenticated probe, or see the Check-10 credentialed-probe design issue if this probe genuinely needs credentials.";
  }
  if (SUBST_REJECT_RE.test(cmd)) {
    return "discoverability_test.command contains shell-active token (;, &&, ||, |, >, <, &, $var, $(, `, <(, >() — refusing to run. Plans must compose single-statement commands without chaining or substitution.";
  }
  return null;
}

/**
 * The run-log endorsement reject — see `RUNLOG_SUBST_REJECT_RE`. Applies to
 * `kind: run-log` ONLY, and allows bare `|`, `<`, `>` (which the canonical
 * `gh run view <run-id> --log | grep MARKER` shape requires).
 */
export function runLogSubstRejectReason(cmd: string): string | null {
  if (RUNLOG_SUBST_REJECT_RE.test(cmd)) {
    return "discoverability_test.command declares `kind: run-log` but contains a chaining/substitution token (;, &&, ||, &, $var, $(, `, <(, >() — refusing to endorse it. A run-log SKIP tells a human the command is statically verified; that endorsement must never cover a command that chains or expands variables. Bare `|`, `<` and `>` are allowed (the `gh run view <run-id> --log | grep MARKER` shape needs them).";
  }
  return null;
}

// `kind`/`marker` are Form-A-only sub-fields of `discoverability_test` and MUST
// be indented. A column-0 `kind:` would become a sixth TOP-LEVEL key of the
// `## Observability` schema and break `observability-schema-parity.test.ts`'s
// `CANONICAL.length === 5` (plus three sibling assertions) — so the strict
// parsers below require leading whitespace, and the loose token detectors
// deliberately DO match a column-0 or prose form so it FAILs loudly (guardrail 6)
// rather than being silently ignored.
// Quote handling accepts ONLY `"?`, never `['"]?`. YAML treats 'x' and "x"
// identically, but the bash runtime (SKILL.md Step 10.4b) greps `"?` alone —
// so `kind: 'run-log'` FAILs there (guardrails 2 + 6). Bash is the SSOT: if the
// mirror accepted single quotes it would report SKIP for a plan that gets a red
// preflight, i.e. a green suite certifying a broken plan. Widening this to also
// accept `'` is a runtime change and must start in the bash.
const KIND_STRICT_RE = /^[ \t]+kind:[ \t]*"?(live-probe|run-log)"?[ \t]*$/m;
const MARKER_STRICT_RE = /^[ \t]+marker:[ \t]*"?([^\s"]*)"?[ \t]*$/m;

// "a line whose first meaningful token is a `kind`/`marker` key", tolerating
// list bullets, blockquotes and bold decoration. Narrow enough not to fire on
// incidental prose like "this kind of check".
const KIND_TOKEN_RE = /^[ \t]*(?:[->*]+[ \t]*)*\**[ \t]*kind[ \t]*\**[ \t]*:/im;
const MARKER_TOKEN_RE = /^[ \t]*(?:[->*]+[ \t]*)*\**[ \t]*marker[ \t]*\**[ \t]*:/im;

/** The declared kind, or null if absent OR present-but-unparseable. */
export function parseKind(
  observabilityBlock: string,
): DiscoverabilityKind | null {
  const m = observabilityBlock.match(KIND_STRICT_RE);
  return m ? (m[1] as DiscoverabilityKind) : null;
}

/** Whether SOME `kind` key token appears — the guardrail-6 fail-closed trigger. */
export function hasKindToken(observabilityBlock: string): boolean {
  return KIND_TOKEN_RE.test(observabilityBlock);
}

/**
 * The declared marker, RAW — malformed values are returned as-is so the
 * classifier (not the parser) owns the charset verdict and can name the bad
 * value in its diagnostic.
 */
export function parseMarker(observabilityBlock: string): string | null {
  const m = observabilityBlock.match(MARKER_STRICT_RE);
  return m ? m[1] : null;
}

/** Whether SOME `marker` key token appears — the guardrail-7 fail-closed trigger. */
export function hasMarkerToken(observabilityBlock: string): boolean {
  return MARKER_TOKEN_RE.test(observabilityBlock);
}

const MARKER_CHARSET_RE = /^[A-Za-z0-9_]+$/;

/**
 * Guardrail 4's emitter-directory ALLOWLIST — the pathspecs the runtime's
 * `git grep` is restricted to. Mirrored verbatim in SKILL.md Step 10.4b.
 *
 * Why an allowlist and not the old `:!knowledge-base/project/{plans,specs}`
 * blacklist: a two-entry blacklist admits every other author-controlled file in
 * the repo, so a plan author could satisfy guardrail 4 by writing the marker
 * into a doc, a fixture, or a second plan-adjacent file. It was demonstrably
 * self-satisfiable — this suite's own fixture `09-run-log-pass.md` matched its
 * own marker. An allowlist inverts the burden: the marker must appear on a
 * surface that actually EXECUTES and can emit into a run log.
 *
 * `:(top)` makes every pathspec repo-root-relative. Without it a pathspec is
 * resolved against the CWD, so running the check from a subdirectory silently
 * changes which paths it covers. Preflight runs at the repo root today, so this
 * is latent — but a latent cwd dependency in a security guard is exactly the
 * "cannot fail" class this PR exists to remove.
 *
 * Fail-closed by construction: an emitter in a directory outside this list
 * produces a FAIL naming the allowlist, which an author can read and act on.
 * Widening the list is a deliberate, reviewable edit — in BOTH copies.
 */
export const EMITTER_ALLOWLIST_PATHSPECS = [
  ":(top)apps/",
  ":(top).github/",
  ":(top)infra/",
  ":(top)scripts/",
  ":(top)bin/",
  ":(top)tools/",
  ":(top)plugins/soleur/skills/",
  ":(top)plugins/soleur/hooks/",
] as const;

export async function classifyDiscoverabilityResult(
  input: ClassifyInput,
): Promise<ClassificationResult> {
  const {
    planPath,
    planBody,
    runner,
    timeoutMs = 15_000,
    markerLookup = () => false, // fail-closed; see ClassifyInput.markerLookup
  } = input;

  if (!planPath || planBody === "") {
    return {
      result: "SKIP",
      reason:
        "no plan file linked from PR body — Check 10 deferred to next preflight run after PR has a plan link",
    };
  }

  const block = extractObservabilityBlock(planBody);
  if (block === "") {
    return {
      result: "FAIL",
      reason: `plan ${planPath} is missing the ## Observability block (sensitive-path diff requires one per hr-observability-as-plan-quality-gate)`,
    };
  }

  const cmd = parseCommand(block);
  if (cmd === "") {
    return {
      result: "FAIL",
      reason: `plan ${planPath} declares an Observability block but no discoverability_test.command could be parsed (see plan-issue-templates.md §Observability for the canonical YAML schema)`,
    };
  }

  // ---- ORDER IS LOAD-BEARING (plan F2). Do not reorder these three stages. ----
  //   1. ssh reject        — ALWAYS, before any `kind` branch
  //   2. kind resolution + guardrails 2-7
  //   3. subst reject      — live-probe only
  // Moving (1) below (2) lets `kind: run-log` + `ssh …` return SKIP, defeating
  // hr-no-ssh-fallback-in-runbooks. That is a LARGER downgrade than the one
  // direction 3 was rejected for.

  // --- Stage 1: the SSH reject, unconditionally, for both kinds. ---
  const sshRejected = sshRejectReason(cmd);
  if (sshRejected !== null) return { result: "FAIL", reason: sshRejected };

  // --- Stage 2: kind resolution + guardrails 2-7. ---

  const kindDeclared = parseKind(block);

  // Guardrails 2 + 6: a `kind` token that the strict Form-A parser cannot read
  // is malformed — an unknown value, a prose `Kind:`, or a column-0 key. Fail
  // loudly. Never fall back to live-probe: an author who wrote `kind:` believes
  // they declared something, and silently ignoring it is the downgrade.
  if (kindDeclared === null && hasKindToken(block)) {
    return {
      result: "FAIL",
      reason: `plan ${planPath} declares a discoverability_test kind that could not be parsed. \`kind:\` is Form A only (a strictly INDENTED sub-field of \`discoverability_test:\`) and must be exactly \`live-probe\` or \`run-log\`. A prose or column-0 \`kind\` is refused rather than defaulted.`,
    };
  }

  // Guardrail 1: absent `kind` means live-probe — every pre-existing plan
  // behaves exactly as it did before this field existed.
  const kind: DiscoverabilityKind = kindDeclared ?? "live-probe";

  // Guardrail 7: a `marker:` outside `kind: run-log` is consumed by nothing. It
  // signals an author who thinks they declared a run-log test. Fail, don't ignore.
  if (kind !== "run-log" && hasMarkerToken(block)) {
    return {
      result: "FAIL",
      reason: `plan ${planPath} declares a discoverability_test marker but kind is \`${kind}\` — \`marker:\` is only meaningful under \`kind: run-log\` and nothing consumes it otherwise. Either set \`kind: run-log\` or remove the marker.`,
    };
  }

  if (kind === "run-log") {
    // Guardrail 8: the endorsement reject. Runs FIRST inside the branch so a
    // chaining/exfiltrating command is refused before the emitter lookup, and
    // before any SKIP prose vouches for it. See RUNLOG_SUBST_REJECT_RE.
    const runLogRejected = runLogSubstRejectReason(cmd);
    if (runLogRejected !== null) {
      return { result: "FAIL", reason: runLogRejected };
    }

    const marker = parseMarker(block);

    // Guardrail 3: run-log without a well-formed marker records nothing, so
    // nothing downstream could ever assert anything — strictly worse than a FAIL.
    if (marker === null || !MARKER_CHARSET_RE.test(marker)) {
      return {
        result: "FAIL",
        reason: `plan ${planPath} declares \`kind: run-log\` but its discoverability_test marker is ${marker === null ? "missing" : `malformed (${JSON.stringify(marker)})`}. \`marker:\` is required under run-log and must match ^[A-Za-z0-9_]+$ so a post-merge follow-through can grep for it.`,
      };
    }

    // Guardrail 4: the marker must have a REAL emitter on an EXECUTING surface.
    // The oracle is an allowlist of emitter directories, not a blacklist of
    // planning dirs — see EMITTER_ALLOWLIST_PATHSPECS for why.
    if (!markerLookup(marker)) {
      return {
        result: "FAIL",
        reason: `plan ${planPath} declares \`kind: run-log\` with marker ${marker}, but no emitter for it exists on an executing surface. A run-log test may only be declared once something actually emits the marker (git grep -F -- "${marker}" -- ${EMITTER_ALLOWLIST_PATHSPECS.map((p) => `'${p}'`).join(" ")}).`,
      };
    }

    // Guardrail 5: the command must actually name the marker IN EXECUTABLE
    // TEXT, else run-log would certify a command with nothing to do with the
    // recorded evidence. Shell comments are stripped first: a Form A block
    // scalar preserves `#` lines verbatim (only Form B's fence reader drops
    // them), so a bare `cmd.includes(marker)` was satisfiable by
    // `echo unrelated` + a commented-out `# SOLEUR_M` mention — a
    // commented-out marker surfaces nothing.
    if (!stripShellComments(cmd).includes(marker)) {
      return {
        result: "FAIL",
        reason: `plan ${planPath} declares \`kind: run-log\` with marker ${marker}, but its discoverability_test command does not contain that literal outside of shell comments. The command must be the one that surfaces the marker.`,
      };
    }

    // Valid run-log. SKIP — not PASS: the gate must never certify a property it
    // did not observe. Per
    // knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md
    // SKIP is correct only when truly indeterminate, and a run that has not
    // executed yet is genuinely indeterminate.
    return {
      result: "SKIP",
      marker,
      reason: `discoverability_test declares \`kind: run-log\` with marker ${marker}; the evidence lives in a run log that does not exist at preflight time, so the probe is deferred rather than run. Verified statically: an emitter for ${marker} exists in the tree and the command names it outside comments, and the command carries no chaining or substitution tokens. The marker is appended to $PREFLIGHT_TMP/preflight-run-log-markers.txt so a post-merge follow-through can read it.`,
    };
  }

  // --- Stage 3: the substitution reject — live-probe only (nothing is executed
  // under run-log, so these tokens carry no execution risk there). ---
  const substRejected = substRejectReason(cmd);
  if (substRejected !== null) return { result: "FAIL", reason: substRejected };

  const expected = parseExpected(block);
  const result = await runner(cmd, timeoutMs);

  if (result.rc === 6) {
    return {
      result: "FAIL",
      reason: `command failed DNS resolution (curl rc=6 — hostname did not resolve). Verify the hostname in plan ${planPath}'s discoverability_test.command.`,
    };
  }

  if (result.rc === 28 || result.rc === 124) {
    return {
      result: "FAIL",
      reason: `command timed out after ${timeoutMs} ms (rc=${result.rc}). Either the endpoint is unreachable or the command lacks --max-time.`,
    };
  }

  if (result.rc === 22 && /401|403/.test(result.stdout)) {
    const tokens = tokenizeExpected(expected);
    const listsAuth = tokens.some((t) => /401|403/.test(t));
    if (!listsAuth) {
      return {
        result: "SKIP",
        reason: `auth-gated probe returned ${result.stdout.trim()} but expected_output does not list 401/403. Add the auth shape to expected_output OR provision Doppler creds for the probe variant.`,
      };
    }
  }

  if (!matchExpected(expected, result.stdout)) {
    return {
      result: "FAIL",
      reason: `stdout mismatch: command returned ${JSON.stringify(result.stdout.trim())}, expected_output was ${JSON.stringify(expected)} (rc=${result.rc}). Plan's expectation has drifted from production reality.`,
    };
  }

  return { result: "PASS" };
}

function stripQuotes(value: string): string {
  return value.replace(/^["'](.*)["']$/, "$1");
}

/**
 * Drop shell comments so guardrail 5 sees only executable text. A `#` starts a
 * comment at start-of-line or after whitespace; a `#` glued to a preceding
 * non-space character is a URL fragment or a literal and is preserved.
 *
 * Bash mirror (SKILL.md Step 10.4b):
 *   printf '%s\n' "$CMD" | sed -E 's/(^|[[:space:]])#.*$//'
 */
export function stripShellComments(cmd: string): string {
  return cmd
    .split(/\r?\n/)
    .map((line) => line.replace(/(^|\s)#.*$/, ""))
    .join("\n");
}
