import { spawn } from "node:child_process";

export type LinearizeResult =
  | { ok: true; buffer: Buffer }
  | {
      ok: false;
      reason: "spawn_error" | "non_zero_exit" | "timeout";
      detail?: string;
    };

const TIMEOUT_MS = 10_000;

export async function linearizePdf(input: Buffer): Promise<LinearizeResult> {
  return new Promise((resolve) => {
    let settled = false;
    let timer: NodeJS.Timeout | undefined;

    const settle = (r: LinearizeResult) => {
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

    const child = spawn("qpdf", ["--linearize", "-", "-"], {
      env: env as NodeJS.ProcessEnv,
      stdio: ["pipe", "pipe", "pipe"],
    });

    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];

    child.stdout.on("data", (c: Buffer) => stdoutChunks.push(c));
    child.stderr.on("data", (c: Buffer) => stderrChunks.push(c));
    child.on("error", (err) =>
      settle({ ok: false, reason: "spawn_error", detail: err.message }),
    );
    child.on("close", (code, signal) => {
      if (code === 0) {
        settle({ ok: true, buffer: Buffer.concat(stdoutChunks) });
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

    child.stdin.on("error", (err) =>
      settle({
        ok: false,
        reason: "spawn_error",
        detail: `stdin: ${err.message}`,
      }),
    );
    child.stdin.end(input);
  });
}
