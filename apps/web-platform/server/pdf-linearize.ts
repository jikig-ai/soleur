import { spawn } from "node:child_process";
import { writeFile, readFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

export type LinearizeReason =
  | "spawn_error"
  | "non_zero_exit"
  | "timeout"
  | "io_error"
  | "skip_signed";

export type LinearizeResult =
  | { ok: true; buffer: Buffer }
  | { ok: false; reason: LinearizeReason; detail?: string };

const TIMEOUT_MS = 10_000;

// qpdf --linearize rewrites xref + reorders objects, which invalidates any
// PKCS#7/PAdES signature byte-range. Skip if the PDF contains signature dicts.
function isSignedPdf(input: Buffer): boolean {
  const head = input.toString("latin1", 0, Math.min(input.length, 2_000_000));
  return /\/Type\s*\/Sig\b/.test(head) || /\/ByteRange\b/.test(head);
}

function sanitizeForLog(s: string): string {
  return s.replace(/[\x00-\x1f\x7f\u2028\u2029]/g, "?");
}

// qpdf 11.x cannot read stdin (`qpdf --help=usage`), so we use tempfiles.
export async function linearizePdf(input: Buffer): Promise<LinearizeResult> {
  if (isSignedPdf(input)) {
    return { ok: false, reason: "skip_signed" };
  }

  const dir = await mkdtemp(join(tmpdir(), "pdf-linearize-")).catch(() => null);
  if (!dir) {
    return { ok: false, reason: "io_error", detail: "mkdtemp failed" };
  }
  const inPath = join(dir, "in.pdf");
  const outPath = join(dir, "out.pdf");

  try {
    await writeFile(inPath, input);
    const run = await runQpdf(inPath, outPath);
    if (!run.ok) return run;
    const buffer = await readFile(outPath);
    if (buffer.length === 0) {
      return { ok: false, reason: "io_error", detail: "empty output" };
    }
    return { ok: true, buffer };
  } catch (err) {
    return {
      ok: false,
      reason: "io_error",
      detail: err instanceof Error ? err.message : String(err),
    };
  } finally {
    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }
}

type RunResult =
  | { ok: true }
  | {
      ok: false;
      reason: "spawn_error" | "non_zero_exit" | "timeout";
      detail?: string;
    };

function runQpdf(inPath: string, outPath: string): Promise<RunResult> {
  return new Promise((resolve) => {
    let settled = false;
    const settle = (r: RunResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(r);
    };
    // 10s leaves ~20s for GitHub PUT + workspace sync under route maxDuration=30.
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      settle({
        ok: false,
        reason: "timeout",
        detail: `exceeded ${TIMEOUT_MS}ms`,
      });
    }, TIMEOUT_MS);

    const env = Object.fromEntries(
      (["PATH", "LANG", "LC_ALL", "TMPDIR"] as const)
        .map((k) => [k, process.env[k]] as const)
        .filter(([, v]) => v !== undefined),
    ) as NodeJS.ProcessEnv;

    const child = spawn("qpdf", ["--linearize", inPath, outPath], {
      env,
      stdio: ["ignore", "ignore", "pipe"],
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
      const stderr = sanitizeForLog(
        Buffer.concat(stderrChunks).toString("utf8").slice(0, 512),
      );
      settle({
        ok: false,
        reason: "non_zero_exit",
        detail: `${exitPart} stderr=${stderr}`,
      });
    });
  });
}
