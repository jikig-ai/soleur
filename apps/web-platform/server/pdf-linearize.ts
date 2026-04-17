import { spawn } from "node:child_process";
import { writeFile, readFile, unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomBytes } from "node:crypto";

export type LinearizeResult =
  | { ok: true; buffer: Buffer }
  | {
      ok: false;
      reason: "spawn_error" | "non_zero_exit" | "timeout";
      detail?: string;
    };

const TIMEOUT_MS = 10_000;

// qpdf 11.x does not support reading PDFs from stdin (see `qpdf --help=usage`
// "reading from stdin is not supported"). We write the input to a tempfile,
// run `qpdf --linearize <in> <out>`, read the output, and clean up both.
export async function linearizePdf(input: Buffer): Promise<LinearizeResult> {
  const id = randomBytes(8).toString("hex");
  const inPath = join(tmpdir(), `pdf-linearize-in-${id}.pdf`);
  const outPath = join(tmpdir(), `pdf-linearize-out-${id}.pdf`);

  try {
    try {
      await writeFile(inPath, input);
    } catch (err) {
      return {
        ok: false,
        reason: "spawn_error",
        detail: `writeFile in: ${err instanceof Error ? err.message : String(err)}`,
      };
    }

    const subprocessResult = await runQpdf(inPath, outPath);
    if (!subprocessResult.ok) return subprocessResult;

    try {
      const buffer = await readFile(outPath);
      return { ok: true, buffer };
    } catch (err) {
      return {
        ok: false,
        reason: "spawn_error",
        detail: `readFile out: ${err instanceof Error ? err.message : String(err)}`,
      };
    }
  } finally {
    await Promise.allSettled([unlink(inPath), unlink(outPath)]);
  }
}

type RunResult =
  | { ok: true }
  | { ok: false; reason: "spawn_error" | "non_zero_exit" | "timeout"; detail?: string };

function runQpdf(inPath: string, outPath: string): Promise<RunResult> {
  return new Promise((resolve) => {
    let settled = false;
    let timer: NodeJS.Timeout | undefined;

    const settle = (r: RunResult) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      resolve(r);
    };

    const env: Record<string, string> = {};
    for (const key of ["PATH", "HOME", "LANG", "LC_ALL", "TMPDIR"] as const) {
      const v = process.env[key];
      if (v !== undefined) env[key] = v;
    }

    const child = spawn("qpdf", ["--linearize", inPath, outPath], {
      env: env as NodeJS.ProcessEnv,
      stdio: ["ignore", "pipe", "pipe"],
    });

    const stderrChunks: Buffer[] = [];
    child.stderr.on("data", (c: Buffer) => stderrChunks.push(c));
    child.on("error", (err) =>
      settle({ ok: false, reason: "spawn_error", detail: err.message }),
    );
    child.on("close", (code, signal) => {
      if (code === 0) {
        settle({ ok: true });
        return;
      }
      const exitPart = code === null ? `signal=${signal}` : `exit=${code}`;
      const stderr = Buffer.concat(stderrChunks).toString("utf8").slice(0, 512);
      settle({
        ok: false,
        reason: "non_zero_exit",
        detail: `${exitPart} stderr=${stderr}`,
      });
    });

    timer = setTimeout(() => {
      child.kill("SIGKILL");
      settle({
        ok: false,
        reason: "timeout",
        detail: `exceeded ${TIMEOUT_MS}ms`,
      });
    }, TIMEOUT_MS);
  });
}
