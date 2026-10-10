/**
 * #9776 / ADR-282 — hosted must-ask lane: the pure destroy-family classifier.
 *
 * PROPERTY. A hosted Bash command that force-pushes over, deletes or mirror-pushes a protected branch, runs
 * `terraform|tofu destroy` (or `apply -destroy`), or deletes a ref or repository through `gh`, is reported as a
 * match so `canUseTool` can send it to the review gate. When the command cannot be read, or the classifier
 * throws, it fails toward a match, never toward a pass.
 *
 * PURE: no I/O, no clock, no logging. The one dependency, `resolveProtected`, is injected and awaited lazily,
 * only after a force, delete or mirror push with a named destination (or a gh ref delete) is found.
 *
 * NOT DECIDED (named residuals, ADR-282): variable-built command names, aliases (`git -c alias.p=push p`),
 * scripts written then run, `make`/`npm run` indirection, `terragrunt|pulumi destroy`, `git update-ref`,
 * recursive `rm`, force-pushes to non-default branches, GraphQL `deleteRef`/`deleteRepository`/`updateRef`
 * (near-miss telemetry only), non-owner approval. The corpus (`test/fixtures/destroy-ask-corpus.json`) is the
 * stored specification; `test/destroy-ask-hook-parity.test.ts` binds it to the plugin hook's D1 set.
 */

export const DESTROY_RULE_PREFIX = "hosted-destroy-ask:";

export const DESTROY_RULE_IDS = [
  `${DESTROY_RULE_PREFIX}git-force-default`,
  `${DESTROY_RULE_PREFIX}git-delete-default`,
  `${DESTROY_RULE_PREFIX}git-push-unknown-default`,
  `${DESTROY_RULE_PREFIX}git-force-implicit`,
  `${DESTROY_RULE_PREFIX}terraform-destroy`,
  `${DESTROY_RULE_PREFIX}gh-ref-delete-default`,
  `${DESTROY_RULE_PREFIX}gh-repo-delete`,
  `${DESTROY_RULE_PREFIX}fail-closed-keyword`,
  `${DESTROY_RULE_PREFIX}raw-scan`,
  `${DESTROY_RULE_PREFIX}classifier-error`,
] as const;

export type DestroyFamily =
  | "git-default-branch"
  | "terraform-destroy"
  | "gh-destroy"
  | "fail-closed";

export interface DestroyMatch {
  ruleId: string;
  family: DestroyFamily;
  /**
   * The matched simple command, unredacted. For the review-gate card ONLY — the caller must redact it and must
   * never put it in a log line, a Sentry tag, `extra` or a breadcrumb (CLO C5).
   */
  segment?: string;
  /** Set only on `classifier-error`; the caller mirrors it to Sentry (`destroy-classifier-error`). */
  error?: unknown;
  /** Whether the default branch was authoritatively resolved; null when the resolver was never consulted. */
  authoritative?: boolean | null;
}

export interface ProtectedBranches {
  names: ReadonlySet<string>;
  /** True when the default branch was read from the GitHub API with the server-held installation token. */
  authoritative: boolean;
}
export type ResolveProtected = () => Promise<ProtectedBranches>;

const MAX_LEN = 64 * 1024;
const MAX_DEPTH = 4;
const FALLBACK_NAMES: ReadonlySet<string> = new Set(["main", "master"]);

class Unparseable extends Error {}

type Words = string[];

// ---------------------------------------------------------------- lexer

function findParen(src: string, open: number): number {
  // `src[open]` is "(". Returns the index of its matching ")", honouring quotes and backslashes.
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (c === "\\") {
      i++;
    } else if (c === "'") {
      const e = src.indexOf("'", i + 1);
      if (e < 0) throw new Unparseable("sq");
      i = e;
    } else if (c === '"') {
      i++;
      while (i < src.length && src[i] !== '"') {
        if (src[i] === "\\") i++;
        i++;
      }
      if (i >= src.length) throw new Unparseable("dq");
    } else if (c === "(") {
      depth++;
    } else if (c === ")") {
      depth--;
      if (depth === 0) return i;
    }
  }
  throw new Unparseable("paren");
}

function findBacktick(src: string, open: number): number {
  for (let i = open + 1; i < src.length; i++) {
    if (src[i] === "\\") i++;
    else if (src[i] === "`") return i;
  }
  throw new Unparseable("backtick");
}

function findBrace(src: string, open: number): number {
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (c === "\\") i++;
    else if (c === "{") depth++;
    else if (c === "}") {
      depth--;
      if (depth === 0) return i;
    }
  }
  throw new Unparseable("brace");
}

function decodeAnsiC(raw: string): string {
  return raw.replace(/\\(x[0-9a-fA-F]{1,2}|[0-7]{1,3}|u[0-9a-fA-F]{1,4}|.)/g, (_m, g: string) => {
    if (g[0] === "x" && g.length > 1) return String.fromCharCode(parseInt(g.slice(1), 16));
    if (g[0] === "u" && g.length > 1) return String.fromCharCode(parseInt(g.slice(1), 16));
    if (/^[0-7]+$/.test(g)) return String.fromCharCode(parseInt(g, 8));
    switch (g) {
      case "n":
        return "\n";
      case "t":
        return "\t";
      default:
        return g;
    }
  });
}

function lexScript(src: string, depth: number, out: Words[]): void {
  if (depth > MAX_DEPTH) throw new Unparseable("depth");
  const n = src.length;
  let words: string[] = [];
  let buf = "";
  let inWord = false;
  let discardNext = false;
  let captureHeredoc: false | "plain" | "strip" = false;
  const heredocs: { delim: string; strip: boolean }[] = [];

  const nested = (inner: string): void => {
    for (const w of lexAll(inner, depth + 1)) out.push(w);
  };
  const pushWord = (): void => {
    if (!inWord) return;
    const w = buf;
    buf = "";
    inWord = false;
    if (captureHeredoc) {
      heredocs.push({ delim: w, strip: captureHeredoc === "strip" });
      captureHeredoc = false;
      return;
    }
    if (discardNext) {
      discardNext = false;
      return;
    }
    words.push(w);
  };
  const endCommand = (): void => {
    pushWord();
    if (words.length) out.push(words);
    words = [];
    discardNext = false;
    captureHeredoc = false;
  };

  let i = 0;
  while (i < n) {
    const c = src[i];
    if (c === "\u0000") throw new Unparseable("nul");
    if (c === "\\") {
      const e = src[i + 1];
      if (e === undefined) {
        buf += "\\";
        inWord = true;
        i++;
      } else if (e === "\n") {
        i += 2;
      } else {
        buf += e;
        inWord = true;
        i += 2;
      }
      continue;
    }
    if (c === "'") {
      const e = src.indexOf("'", i + 1);
      if (e < 0) throw new Unparseable("sq");
      buf += src.slice(i + 1, e);
      inWord = true;
      i = e + 1;
      continue;
    }
    if (c === '"') {
      inWord = true;
      i++;
      for (;;) {
        if (i >= n) throw new Unparseable("dq");
        const d = src[i];
        if (d === '"') {
          i++;
          break;
        }
        if (d === "\u0000") throw new Unparseable("nul");
        if (d === "\\") {
          const e = src[i + 1];
          if (e === undefined) throw new Unparseable("dq");
          if (e === "\n") {
            i += 2;
          } else if (e === "$" || e === "`" || e === '"' || e === "\\") {
            buf += e;
            i += 2;
          } else {
            buf += d;
            i++;
          }
          continue;
        }
        if (d === "$" && src[i + 1] === "(") {
          const end = findParen(src, i + 1);
          nested(src.slice(i + 2, end));
          buf += src.slice(i, end + 1);
          i = end + 1;
          continue;
        }
        if (d === "`") {
          const end = findBacktick(src, i);
          nested(src.slice(i + 1, end));
          buf += src.slice(i, end + 1);
          i = end + 1;
          continue;
        }
        buf += d;
        i++;
      }
      continue;
    }
    if (c === "`") {
      const end = findBacktick(src, i);
      nested(src.slice(i + 1, end));
      buf += src.slice(i, end + 1);
      inWord = true;
      i = end + 1;
      continue;
    }
    if (c === "$") {
      const nx = src[i + 1];
      if (nx === "(") {
        const end = findParen(src, i + 1);
        nested(src.slice(i + 2, end));
        buf += src.slice(i, end + 1);
        inWord = true;
        i = end + 1;
        continue;
      }
      if (nx === "{") {
        const end = findBrace(src, i + 1);
        buf += src.slice(i, end + 1);
        inWord = true;
        i = end + 1;
        continue;
      }
      if (nx === "'") {
        const e = src.indexOf("'", i + 2);
        if (e < 0) throw new Unparseable("ansi-c");
        buf += decodeAnsiC(src.slice(i + 2, e));
        inWord = true;
        i = e + 1;
        continue;
      }
      if (nx === '"') {
        i++; // `$"..."` is the same as `"..."` for our purposes: drop the `$`
        continue;
      }
      buf += "$";
      inWord = true;
      i++;
      continue;
    }
    if ((c === "<" || c === ">") && src[i + 1] === "(") {
      const end = findParen(src, i + 1);
      nested(src.slice(i + 2, end));
      buf += src.slice(i, end + 1);
      inWord = true;
      i = end + 1;
      continue;
    }
    if (c === "<" && src.startsWith("<<<", i)) {
      pushWord();
      i += 3;
      discardNext = true;
      continue;
    }
    if (c === "<" && src.startsWith("<<", i)) {
      pushWord();
      i += 2;
      let strip = false;
      if (src[i] === "-") {
        strip = true;
        i++;
      }
      captureHeredoc = strip ? "strip" : "plain";
      continue;
    }
    if (c === ">" || c === "<" || (c === "&" && src[i + 1] === ">")) {
      if (inWord && /^[0-9]+$/.test(buf)) {
        buf = "";
        inWord = false;
      } else {
        pushWord();
      }
      i++;
      while (i < n && (src[i] === ">" || src[i] === "&" || src[i] === "|")) i++;
      discardNext = true;
      continue;
    }
    if (c === "#" && !inWord) {
      while (i < n && src[i] !== "\n") i++;
      continue;
    }
    if (c === "\n") {
      endCommand();
      i++;
      while (heredocs.length) {
        const h = heredocs.shift()!;
        for (;;) {
          if (i >= n) break;
          let e = src.indexOf("\n", i);
          if (e < 0) e = n;
          let line = src.slice(i, e);
          i = Math.min(e + 1, n);
          if (h.strip) line = line.replace(/^\t+/, "");
          if (line === h.delim) break;
        }
      }
      continue;
    }
    if (c === ";" || c === "|" || c === "&" || c === "(" || c === ")") {
      endCommand();
      i++;
      continue;
    }
    if (c === " " || c === "\t" || c === "\r" || c === "\v" || c === "\f") {
      pushWord();
      i++;
      continue;
    }
    buf += c;
    inWord = true;
    i++;
  }
  endCommand();
}

const SHELLS = new Set(["sh", "bash", "zsh", "dash", "ksh", "ash"]);

function basename(w: string): string {
  const k = w.lastIndexOf("/");
  return (k < 0 ? w : w.slice(k + 1)).toLowerCase();
}

/** Scripts a simple command hands to a shell (`bash -lc '...'`) or to `eval`; each is lexed as its own program. */
function nestedScripts(words: Words): string[] {
  const scripts: string[] = [];
  for (let i = 0; i < words.length; i++) {
    const base = basename(words[i]);
    if (base === "eval") {
      scripts.push(words.slice(i + 1).join(" "));
      continue;
    }
    if (!SHELLS.has(base)) continue;
    let sawC = false;
    for (let j = i + 1; j < words.length; j++) {
      const a = words[j];
      if (a === "--") continue;
      if (a.startsWith("--")) continue;
      if (a.startsWith("-") || a.startsWith("+")) {
        const cluster = a.slice(1);
        if (a[0] === "-" && cluster.includes("c")) sawC = true;
        if (cluster.endsWith("o")) j++; // `-o errexit` consumes a word
        continue;
      }
      if (sawC) scripts.push(a);
      break;
    }
  }
  return scripts;
}

function lexAll(src: string, depth: number): Words[] {
  if (depth > MAX_DEPTH) throw new Unparseable("depth");
  const simples: Words[] = [];
  lexScript(src, depth, simples);
  const all: Words[] = [];
  for (const w of simples) {
    all.push(w);
    for (const script of nestedScripts(w)) {
      for (const inner of lexAll(script, depth + 1)) all.push(inner);
    }
  }
  return all;
}

// ---------------------------------------------------------------- analysis

type Lazy = () => Promise<ProtectedBranches>;

const ASSIGN_RE = /^[A-Za-z_][A-Za-z0-9_]*=/;
const TF_ENV_RE = /^TF_CLI_ARGS[A-Za-z0-9_]*=.*destroy/i;
const GLOB_OR_VAR_RE = /[*?[$`]/;
// Commands that print or search text: a `git`/`terraform` word after them is data, not a command.
const NON_EXEC = new Set([
  "echo", "printf", "cat", "grep", "egrep", "fgrep", "rg", "ag", "man", "less", "more", "head", "tail", "ls", "cd",
  "pushd", "popd", "mkdir", "cp", "mv", "touch", "wc", "sort", "uniq", "diff", "cmp", "stat", "file", "which", "whereis",
  "type", "test", "[", "sed", "awk", "find", "tee", "basename", "dirname", "realpath", "readlink",
]);

function match(ruleSuffix: string, family: DestroyFamily, words: Words): DestroyMatch {
  return { ruleId: `${DESTROY_RULE_PREFIX}${ruleSuffix}`, family, segment: words.join(" ") };
}

function stripRefs(dest: string): string {
  let d = dest;
  if (d.startsWith("refs/heads/")) d = d.slice("refs/heads/".length);
  else if (d.startsWith("heads/")) d = d.slice("heads/".length);
  return d.toLowerCase();
}

const GIT_PUSH_LONG = [
  "all", "branches", "prune", "mirror", "delete", "tags", "follow-tags", "atomic", "signed", "dry-run", "porcelain",
  "force", "force-with-lease", "force-if-includes", "repo", "receive-pack", "exec", "thin", "no-thin", "verbose",
  "quiet", "progress", "set-upstream", "push-option", "recurse-submodules", "verify", "no-verify", "ipv4", "ipv6",
];
const GIT_PUSH_VALUE_LONG = new Set(["repo", "receive-pack", "exec", "push-option"]);

async function analyzeGit(args: Words, words: Words, lazy: Lazy): Promise<DestroyMatch | null> {
  const pushIdx = args.indexOf("push");
  if (pushIdx < 0) return null;
  const tail = args.slice(pushIdx + 1);
  let force = false;
  let del = false;
  let mirror = false;
  let all = false;
  let prune = false;
  let repoFlag = false;
  let endOpts = false;
  const positionals: string[] = [];
  for (let k = 0; k < tail.length; k++) {
    const a = tail[k];
    if (endOpts) {
      positionals.push(a);
    } else if (a === "--") {
      endOpts = true;
    } else if (a.startsWith("--")) {
      const eq = a.indexOf("=");
      const name = eq < 0 ? a.slice(2) : a.slice(2, eq);
      const cands = GIT_PUSH_LONG.includes(name) ? [name] : GIT_PUSH_LONG.filter((o) => name.length > 0 && o.startsWith(name));
      for (const o of cands) {
        if (o === "force" || o === "force-with-lease" || o === "force-if-includes") force = true;
        else if (o === "delete") del = true;
        else if (o === "mirror") mirror = true;
        else if (o === "prune") prune = true;
        else if (o === "all" || o === "branches") all = true;
        else if (o === "repo") repoFlag = true;
      }
      if (eq < 0 && cands.some((o) => GIT_PUSH_VALUE_LONG.has(o))) k++;
    } else if (a.startsWith("-") && a.length > 1) {
      for (let q = 1; q < a.length; q++) {
        const ch = a[q];
        if (ch === "f") force = true;
        else if (ch === "d") del = true;
        else if (ch === "o") {
          if (q === a.length - 1) k++;
          break;
        }
      }
    } else {
      positionals.push(a);
    }
  }
  const refspecs = repoFlag ? positionals : positionals.slice(1);
  const forcedSpec = refspecs.some((r) => r.startsWith("+"));
  const deleteSpec = (r: string): boolean => del || prune || (r.startsWith(":") && r.length > 1);
  const isForce = force || forcedSpec;
  const isDelete = del || prune || refspecs.some((r) => r.startsWith(":") && r.length > 1);
  if (!isForce && !isDelete && !mirror) return null;
  if (mirror) return match("git-force-default", "git-default-branch", words);
  if (all && isForce) return match("git-force-default", "git-default-branch", words);

  const named: { dest: string; isDel: boolean }[] = [];
  let implicit = refspecs.length === 0;
  for (const r of refspecs) {
    const spec = r.startsWith("+") ? r.slice(1) : r;
    const colon = spec.lastIndexOf(":");
    const dest = colon < 0 ? spec : spec.slice(colon + 1);
    const isDel = deleteSpec(r);
    if (dest === "") {
      if (isForce) return match(isDel ? "git-delete-default" : "git-force-default", "git-default-branch", words);
      continue; // a bare `:` without a force flag is an ordinary matching push
    }
    if (GLOB_OR_VAR_RE.test(dest)) {
      return match(isDel ? "git-delete-default" : "git-force-default", "git-default-branch", words);
    }
    const norm = stripRefs(dest);
    if (norm === "head" || norm === "@" || norm === ".") {
      implicit = true;
      continue;
    }
    named.push({ dest: norm, isDel });
  }
  let resolved: ProtectedBranches | null = null;
  if (named.length) {
    resolved = await lazy();
    for (const d of named) {
      if (resolved.names.has(d.dest)) {
        return match(d.isDel ? "git-delete-default" : "git-force-default", "git-default-branch", words);
      }
    }
  }
  if (implicit) {
    return match(isForce ? "git-force-implicit" : "git-delete-default", "git-default-branch", words);
  }
  if (resolved && !resolved.authoritative) {
    return match("git-push-unknown-default", "git-default-branch", words);
  }
  return null;
}

const TF_FALSE_VALUES = new Set(["0", "f", "F", "false", "FALSE", "False"]);

function analyzeTerraform(args: Words, words: Words): DestroyMatch | null {
  if (args.includes("destroy")) return match("terraform-destroy", "terraform-destroy", words);
  if (args.includes("apply")) {
    for (const a of args) {
      const m = /^--?destroy(?:=(.*))?$/.exec(a);
      if (m && (m[1] === undefined || !TF_FALSE_VALUES.has(m[1]))) {
        return match("terraform-destroy", "terraform-destroy", words);
      }
    }
  }
  return null;
}

const GH_VALUE_LONG = new Set(["header", "jq", "template", "hostname", "cache", "preview"]);
const GH_FORCE_FIELD_RE = /^force=(?!false$|0$)/i;

async function analyzeGh(args: Words, words: Words, lazy: Lazy): Promise<DestroyMatch | null> {
  const repoIdx = args.indexOf("repo");
  if (repoIdx >= 0) {
    const next = args.slice(repoIdx + 1).find((a) => !a.startsWith("-"));
    if (next === "delete") return match("gh-repo-delete", "gh-destroy", words);
  }
  const apiIdx = args.indexOf("api");
  if (apiIdx < 0) return null;
  const tail = args.slice(apiIdx + 1);
  let method = "";
  let endpoint = "";
  let forceField = false;
  let hasInput = false;
  for (let k = 0; k < tail.length; k++) {
    const a = tail[k];
    if (a.startsWith("--")) {
      const eq = a.indexOf("=");
      const name = eq < 0 ? a.slice(2) : a.slice(2, eq);
      const val = eq < 0 ? undefined : a.slice(eq + 1);
      if (name === "method") method = val ?? tail[++k] ?? "";
      else if (name === "input") {
        hasInput = true;
        if (val === undefined) k++;
      } else if (name === "field" || name === "raw-field") {
        const v = val ?? tail[++k] ?? "";
        if (GH_FORCE_FIELD_RE.test(v)) forceField = true;
      } else if (GH_VALUE_LONG.has(name) && val === undefined) k++;
    } else if (a.startsWith("-") && a.length > 1) {
      const ch = a[1];
      const rest = a.slice(2);
      if (ch === "X") method = rest || tail[++k] || "";
      else if (ch === "f" || ch === "F") {
        const v = rest || tail[++k] || "";
        if (GH_FORCE_FIELD_RE.test(v)) forceField = true;
      } else if ("Hqtp".includes(ch) && !rest) k++;
    } else if (!endpoint) {
      endpoint = a;
    }
  }
  method = method.toUpperCase();
  const path = endpoint.replace(/^\/+/, "").replace(/\?.*$/, "");
  const refMatch = /^repos\/[^/]+\/[^/]+\/git\/refs\/(.*)$/i.exec(path);
  const repoMatch = /^repos\/[^/]+\/[^/]+\/?$/i.test(path);
  if (method === "DELETE" && repoMatch) return match("gh-repo-delete", "gh-destroy", words);
  const refIsDestructive =
    method === "DELETE" || ((method === "PATCH" || method === "PUT") && (forceField || hasInput));
  if (refIsDestructive && refMatch) {
    let name = refMatch[1];
    if (/^tags\//i.test(name)) return null;
    if (/^heads\//i.test(name)) name = name.slice("heads/".length);
    if (name === "" || GLOB_OR_VAR_RE.test(name)) return match("gh-ref-delete-default", "gh-destroy", words);
    const resolved = await lazy();
    if (resolved.names.has(name.toLowerCase())) return match("gh-ref-delete-default", "gh-destroy", words);
    if (!resolved.authoritative) return match("git-push-unknown-default", "gh-destroy", words);
    return null;
  }
  if (method === "DELETE" && (path === "" || GLOB_OR_VAR_RE.test(path))) {
    return match("gh-ref-delete-default", "gh-destroy", words);
  }
  return null;
}

async function analyzeSimple(words: Words, lazy: Lazy): Promise<DestroyMatch | null> {
  if (words.some((w) => TF_ENV_RE.test(w))) return match("terraform-destroy", "terraform-destroy", words);
  for (let i = 0; i < words.length; i++) {
    const w = words[i];
    if (ASSIGN_RE.test(w)) continue;
    const base = basename(w);
    if (base === "git") return analyzeGit(words.slice(i + 1), words, lazy);
    if (base === "terraform" || base === "tofu") return analyzeTerraform(words.slice(i + 1), words);
    if (base === "gh") return analyzeGh(words.slice(i + 1), words, lazy);
    if (NON_EXEC.has(base)) return null;
  }
  return null;
}

const RAW_SCAN_TRIGGER_RE = /<<|\|&?\s*(?:sudo\s+)?(?:ba|z|da|k|a)?sh\b|\bxargs\b/i;
const FORCE_MARK_RE = /(?:^|\s)(?:-[A-Za-z]*[fd][A-Za-z]*|--force\S*|--delete|--mirror|\+\S+|:\S+)(?=\s|$)/;

async function rawScan(command: string, lazy: Lazy): Promise<boolean> {
  if (!RAW_SCAN_TRIGGER_RE.test(command)) return false;
  if (/\bdestroy\b/i.test(command)) return true;
  if (/\bpush\b/i.test(command) && FORCE_MARK_RE.test(command)) {
    const resolved = await lazy();
    if (!resolved.authoritative) return true;
    const text = command.toLowerCase();
    for (const name of resolved.names) {
      const esc = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      if (new RegExp(`(?:^|[^a-z0-9._-])${esc}(?:$|[^a-z0-9._-])`).test(text)) return true;
    }
  }
  return false;
}

function memoise(resolve: ResolveProtected, seen: { authoritative: boolean | null }): Lazy {
  let p: Promise<ProtectedBranches> | null = null;
  return () => {
    if (!p) {
      p = (async () => {
        let out: ProtectedBranches;
        try {
          const v = await resolve();
          const names = new Set<string>();
          for (const x of v.names) names.add(String(x).toLowerCase());
          out = { names, authoritative: v.authoritative === true };
        } catch {
          // A throwing resolver degrades to "unresolved": every force/delete push asks.
          out = { names: new Set(FALLBACK_NAMES), authoritative: false };
        }
        seen.authoritative = out.authoritative;
        return out;
      })();
    }
    return p;
  };
}

/**
 * Keyword-only near-miss: a destructive-looking word is present but nothing matched. Returned for telemetry
 * (`destroy-classifier-near-miss`); never an ask. Null for an ordinary command.
 */
export function destroyNearMiss(command: string): "destroy" | "push-force" | "gh-delete" | "gh-graphql" | null {
  if (typeof command !== "string") return null;
  if (/\bdestroy\b/i.test(command)) return "destroy";
  if (/\bpush\b/i.test(command) && FORCE_MARK_RE.test(command)) return "push-force";
  if (/\b(?:deleteRef|updateRef|deleteRepository)\b/.test(command)) return "gh-graphql";
  if (/\bgh\b/.test(command) && /\bapi\b/.test(command) && /\bgraphql\b/.test(command) && /--input\b/.test(command)) {
    return "gh-graphql";
  }
  if (/\bgh\b/.test(command) && /\bdelete\b/i.test(command)) return "gh-delete";
  return null;
}

/**
 * Classify a hosted Bash command. Returns a match when the command must be sent to the review gate, else null.
 * Never throws: an internal error is itself a match (`classifier-error`, with `error` set).
 */
export async function classifyDestroyFamily(
  command: string,
  resolveProtected: ResolveProtected,
): Promise<DestroyMatch | null> {
  let src = "";
  try {
    src = typeof command === "string" ? command : String(command);
    const seen: { authoritative: boolean | null } = { authoritative: null };
    const lazy = memoise(resolveProtected, seen);
    let simples: Words[];
    try {
      if (src.length > MAX_LEN) throw new Unparseable("size");
      simples = lexAll(src, 0);
    } catch (err) {
      if (!(err instanceof Unparseable)) throw err;
      const stripped = src.replace(/['"\\]/g, "").toLowerCase();
      if (stripped.includes("destroy") || stripped.includes("push")) {
        return { ruleId: `${DESTROY_RULE_PREFIX}fail-closed-keyword`, family: "fail-closed", authoritative: null };
      }
      return null;
    }
    for (const words of simples) {
      const m = await analyzeSimple(words, lazy);
      if (m) return { ...m, authoritative: seen.authoritative };
    }
    if (await rawScan(src, lazy)) {
      return { ruleId: `${DESTROY_RULE_PREFIX}raw-scan`, family: "fail-closed", authoritative: seen.authoritative };
    }
    return null;
  } catch (error) {
    return { ruleId: `${DESTROY_RULE_PREFIX}classifier-error`, family: "fail-closed", error, authoritative: null };
  }
}
