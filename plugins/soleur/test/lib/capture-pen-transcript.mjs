// capture-pen-transcript.mjs — re-capture fixtures/pen-0.3.13-transcript.txt from
// the REAL engine. Run it on every CLI pin bump (a test pins the transcript's
// engine header to the version in check_deps.sh):
//
//   npm install --ignore-scripts @pen.dev/cli@<pin>      # in a scratch dir, credential vars unset
//   doppler run -p soleur -c dev -- node capture-pen-transcript.mjs \
//       --pen <scratch>/node_modules/@pen.dev/cli/dist/index.mjs \
//       --out plugins/soleur/test/fixtures/pen-<pin>-transcript.txt
//
// The credential comes from the environment (PEN_CLI_KEY, else PENCIL_CLI_KEY) and
// is handed to the child as PEN_CLI_KEY only. It is never printed: the output goes
// through scrub-transcript.mjs (credential in every encoded form, paths, UUIDs,
// e-mail lines) and `gitleaks detect --no-git`; any finding fails the run.
// Sessions are driven with the adapter's own command builders, so the transcript
// shows what the adapter really sends.

import { spawn } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  REPL_PROMPT,
  buildBatchDesignCommand,
  buildCountCommand,
  buildExportCommand,
  buildReadSkillCommand,
  buildScreenshotCommand,
  buildEditorStateCommand,
  buildSaveCommand,
  buildVariablesCommand,
  formatReplCommand,
} from "../../skills/pencil-setup/scripts/pencil-repl-surface.mjs";
import { stripAnsi } from "../../skills/pencil-setup/scripts/pencil-response-classify.mjs";
import { createNormalizer, collapseReply, findLeaks, gitleaksFindings, renderTranscript, replyLines } from "./scrub-transcript.mjs";

const NONCE = "0123456789abcdef0123456789abcdef";

// A command may depend on what earlier replies printed (a node id).
const firstNodeId = (history) => {
  for (const h of history) {
    const m = /": "([A-Za-z0-9_-]{3,})" \(= /.exec(stripAnsi(h));
    if (m) return m[1];
  }
  throw new Error("no node id printed yet");
};

export function canonicalSessions(work) {
  const cwd = join(work, "cwd");
  const ro = join(work, "ro");
  const exportDir = join(work, "exports");
  mkdirSync(cwd, { recursive: true });
  mkdirSync(ro, { recursive: true });
  writeFileSync(join(work, "garbage.pen"), "this is not a pen document\n");
  const doc = join(work, "doc.pen");
  const insertOps = 'frame=I(document,{type:"frame",name:"Hero\\nName",width:100,height:50})';
  return [
    {
      name: "main",
      cwd,
      args: ["--out", doc],
      cmds: [
        buildEditorStateCommand(),
        buildCountCommand(NONCE),
        buildBatchDesignCommand(insertOps),
        buildCountCommand(NONCE),
        buildVariablesCommand(),
        buildEditorStateCommand(),
        buildBatchDesignCommand('box=I(document,{type:"frame",name:"Box"});\nPrint("hello")'),
        (h) => buildScreenshotCommand(firstNodeId(h)),
        (h) => buildExportCommand({ nodeIds: [firstNodeId(h)], outputDir: exportDir, format: "png", scale: 1 }),
        buildBatchDesignCommand('Export(["nope"],"png",' + JSON.stringify(exportDir) + ",{scale:1})"),
        formatReplCommand("execute", { input: "bad syntax here (" }),
        formatReplCommand("execute", { input: "var n,c,Print;" }),
        buildCountCommand(NONCE),
        'batch_design({ input: "x" })',
        "batch_get({})",
        "get_editor_state()",
        buildReadSkillCommand(),
        buildReadSkillCommand("guide/table.md"),
        'read_skill({"path":"nope.md"})',
        buildSaveCommand(),
        buildEditorStateCommand(),
      ],
    },
    { name: "reload", cwd, args: ["--out", doc, "--in", doc], cmds: [buildEditorStateCommand(), buildCountCommand(NONCE)] },
    {
      name: "readonly",
      cwd,
      args: ["--out", join(ro, "x.pen")],
      cmds: [
        buildBatchDesignCommand('I(document,{type:"frame",name:"A",width:100,height:50})'),
        () => {
          chmodSync(ro, 0o555);
          return buildSaveCommand();
        },
      ],
    },
    { name: "badin", cwd, args: ["--out", join(work, "bad-out.pen"), "--in", join(work, "garbage.pen")], cmds: [], expectExit: true },
    { name: "nokey", cwd, args: ["--out", join(work, "nokey.pen")], cmds: [], expectExit: true, noKey: true },
  ];
}

function runSession(penBin, key, home, sess) {
  return new Promise((resolveSession, reject) => {
    const env = { PATH: process.env.PATH, HOME: home };
    if (!sess.noKey) env.PEN_CLI_KEY = key;
    const child = spawn(process.execPath, [penBin, "interactive", ...sess.args], { cwd: sess.cwd, env, stdio: ["pipe", "pipe", "pipe"] });
    let out = "";
    let err = "";
    let exited = null;
    child.stdout.on("data", (c) => (out += c.toString("utf8")));
    child.stderr.on("data", (c) => (err += c.toString("utf8")));
    child.on("exit", (code) => (exited = code ?? -1));
    const result = { name: sess.name, args: sess.args, noKey: Boolean(sess.noKey), startup: null, steps: [], exit: null };
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const waitPrompt = async () => {
      const t0 = Date.now();
      for (;;) {
        if (exited !== null) return false;
        if (stripAnsi(out).endsWith(REPL_PROMPT)) {
          const len = out.length;
          await sleep(120);
          if (out.length === len) {
            await sleep(120); // let stderr drain
            return true;
          }
        }
        if (Date.now() - t0 > 90_000) throw new Error(`timeout in ${sess.name}; stdout tail ${JSON.stringify(out.slice(-200))}`);
        await sleep(30);
      }
    };
    const take = () => {
      const snap = { out, err };
      out = "";
      err = "";
      return snap;
    };
    (async () => {
      const ready = await waitPrompt();
      if (!ready) {
        await sleep(300);
        result.startup = take();
        result.exit = exited;
        return resolveSession(result);
      }
      result.startup = take();
      const history = [];
      for (const spec of sess.cmds) {
        const cmd = typeof spec === "function" ? spec(history) : spec;
        child.stdin.write(cmd + "\n");
        if (!(await waitPrompt())) throw new Error(`engine exited during ${sess.name}: ${cmd.slice(0, 60)}`);
        const snap = take();
        history.push(snap.out);
        result.steps.push({ cmd, ...snap });
      }
      child.stdin.write("exit()\n");
      const t0 = Date.now();
      while (exited === null && Date.now() - t0 < 8000) await sleep(50);
      if (exited === null) child.kill();
      result.exit = exited ?? 0;
      resolveSession(result);
    })().catch((e) => {
      child.kill();
      reject(e);
    });
  });
}

const toLines = replyLines;

export async function capture({ penBin, key, outFile, date = new Date().toISOString().slice(0, 10) }) {
  const work = realpathSync(mkdtempSync(join(tmpdir(), "pen-capture-")));
  const home = realpathSync(mkdtempSync(join(tmpdir(), "pen-capture-home-")));
  const pkgDir = dirname(dirname(realpathSync(penBin)));
  const pkg = JSON.parse(readFileSync(join(pkgDir, "package.json"), "utf8"));
  try {
    const raw = [];
    for (const sess of canonicalSessions(work)) raw.push(await runSession(penBin, key, home, sess));

    const norm = createNormalizer({
      secrets: [key],
      paths: [
        [work, "<WORK>"],
        [pkgDir, "<PEN>"],
        [home, "<HOME>"],
        [realpathSync(homedir()), "<REALHOME>"],
        [tmpdir(), "<TMP>"],
      ],
    });
    const sessions = raw.map((s) => {
      norm.ids.length = 0; // ids are numbered per session
      const startup = { stdout: [], stderr: [] };
      norm.harvest(s.startup.out);
      startup.stdout = toLines(norm.scrub(s.startup.out), { stripPrompt: true });
      startup.stderr = toLines(norm.scrub(s.startup.err), { stripPrompt: false });
      const steps = s.steps.map((st) => {
        norm.harvest(st.out + "\n" + st.err);
        const cmd = norm.scrub(st.cmd);
        const stderr = toLines(norm.scrub(st.err), { stripPrompt: false });
        return { cmd, stdout: collapseReply(cmd, toLines(norm.scrub(st.out), { stripPrompt: true }), stderr), stderr };
      });
      return { name: s.name, args: s.args.map((a) => norm.scrub(a)), noKey: s.noKey, startup, steps, exit: s.exit };
    });

    const text = renderTranscript({
      header: [
        `engine: ${pkg.name}@${pkg.version} captured ${date}`,
        "regenerate with test/lib/capture-pen-transcript.mjs (credential from the environment, scrubbed, gitleaks-checked)",
        "format: `@ session` starts a REPL session, `> ` is a command line, `< ` is stdout, `! ` is stderr, `= exit N` the exit code",
        "ansi: YES. The engine colours stdout and stderr even when piped; this file stores the text with the escapes stripped.",
        "ansi: prompt is ESC[36mpenESC[39m ESC[2m>ESC[22m followed by a space (REPL_PROMPT_RAW); Saved is green (32), Error: and Save failed: red (31), Unknown tool: yellow (33)",
        "streams: success replies are on stdout; every failure (Error:, [ERROR], Save failed:, Unknown tool:, Authentication required) is on stderr and stdout carries only a blank line",
        "placeholders: <WORK> scratch directory, <PEN> installed package, <NODEIDn> n-th node id of the session, <NONCE> count nonce, <B64> image payload, <SKILL-TEXT> read_skill markdown",
        "stack frames are collapsed to `at <STACK>`; every UUID is the synthetic 00000000-0000-4000-8000-000000000000",
      ],
      sessions,
    });
    const leaks = findLeaks(text, { secrets: [key] });
    if (leaks.length > 0) throw new Error(`transcript still has leaks: ${leaks.slice(0, 5).join(", ")}`);
    writeFileSync(outFile, text);
    const g = gitleaksFindings(outFile);
    if (!g.ok) {
      rmSync(outFile, { force: true });
      throw new Error(`gitleaks: ${g.output}`);
    }
    return { sessions: sessions.length, steps: sessions.reduce((n, s) => n + s.steps.length, 0) };
  } finally {
    try {
      chmodSync(join(work, "ro"), 0o755);
    } catch {}
    rmSync(work, { recursive: true, force: true });
    rmSync(home, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const arg = (name) => {
    const i = process.argv.indexOf(name);
    return i === -1 ? null : process.argv[i + 1];
  };
  const key = (process.env.PEN_CLI_KEY || process.env.PENCIL_CLI_KEY || "").trim();
  if (!key) {
    process.stderr.write("capture: no credential in PEN_CLI_KEY or PENCIL_CLI_KEY (run under doppler)\n");
    process.exit(3);
  }
  const penBin = arg("--pen");
  const outFile = arg("--out");
  if (!penBin || !outFile) {
    process.stderr.write("usage: capture-pen-transcript.mjs --pen <dist/index.mjs> --out <file>\n");
    process.exit(2);
  }
  capture({ penBin: resolve(penBin), key, outFile: resolve(outFile) }).then(
    (r) => process.stdout.write(`captured ${r.sessions} sessions, ${r.steps} commands -> ${outFile}\n`),
    (e) => {
      process.stderr.write(`capture failed: ${String(e.message).split(key).join("<redacted>")}\n`);
      process.exit(1);
    }
  );
}
