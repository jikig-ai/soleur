import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// argv-bearer sweep: configure-auth.sh PATCHes carry RESEND_API_KEY and the OAuth client secrets.
// A curl argument list is world-readable (/proc/<pid>/cmdline, `ps`), so the JSON body must travel
// in a 0600 file via `--data-binary @file` (stdin is already taken by the bearer config), the file
// must hold the secrets, no argv of ANY child (curl or jq) may, and the file must be gone on every
// exit path. Hermetic: a mock `curl` on PATH records argv, stdin and the body file's content and
// mode at call time. Nothing here touches the network or a real credential; every value is synthetic.

const SCRIPT = path.resolve(__dirname, "../supabase/scripts/configure-auth.sh");

const SYN = {
  token: "synthetic-fixture-token-0001",
  resend: "re_test_fake_key_123",
  googleId: "synthetic-google-id-0001",
  googleSecret: "synthetic-google-secret-0001",
  azureId: "synthetic-azure-id-0001",
  azureSecret: "synthetic-azure-secret-0001",
};

// One line of `argv` per curl call is recorded as a record separated by "\n--CALL--\n", each argument
// on its own line, so a secret hiding in any single argument is findable with a substring search.
const MOCK_CURL = `#!/usr/bin/env bash
n=$(( $(cat "$MOCK_DIR/count" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" > "$MOCK_DIR/count"
{ printf '%s\\n' "$@"; printf -- '--CALL--\\n'; } >> "$MOCK_DIR/argv"
args=("$@")
for ((i=0; i<\${#args[@]}; i++)); do
  if [[ "\${args[i]}" == "--config" && "\${args[i+1]:-}" == "-" ]]; then cat >> "$MOCK_DIR/stdin"; fi
  case "\${args[i]}" in
    --data-binary) next="\${args[i+1]:-}"
      if [[ "$next" == @* ]]; then
        f="\${next#@}"
        cp -- "$f" "$MOCK_DIR/body.$n"
        printf '%s %s\\n' "$(stat -c %a -- "$f")" "$f" >> "$MOCK_DIR/bodymeta"
      fi ;;
    -d|--data|--data-raw|--data-urlencode) printf '%s\\n' "\${args[i+1]:-}" >> "$MOCK_DIR/dflag" ;;
  esac
done
code=200
[[ "$n" == "\${MOCK_FAIL_ON:-0}" ]] && code="\${MOCK_FAIL_CODE:-500}"
printf '{}\\n%s' "$code"
`;

// jq is wrapped too, so jq's OWN argv can be asserted secret-free (a `--arg secret "$v"` would leak it).
const MOCK_JQ = `#!/usr/bin/env bash
{ printf '%s\\n' "$@"; printf -- '--CALL--\\n'; } >> "$MOCK_DIR/jqargv"
exec "$REAL_JQ" "$@"
`;

let root: string;
let binDir: string;

function findJq(): string {
  const r = spawnSync("bash", ["-c", "command -v jq"], { encoding: "utf8" });
  return r.stdout.trim();
}

beforeAll(() => {
  root = mkdtempSync(path.join(tmpdir(), "configure-auth-argv-"));
  binDir = path.join(root, "bin");
  spawnSync("mkdir", ["-p", binDir]);
  writeFileSync(path.join(binDir, "curl"), MOCK_CURL);
  writeFileSync(path.join(binDir, "jq"), MOCK_JQ);
  chmodSync(path.join(binDir, "curl"), 0o755);
  chmodSync(path.join(binDir, "jq"), 0o755);
});

afterAll(() => {
  rmSync(root, { recursive: true, force: true });
});

interface Run {
  rc: number | null;
  stdout: string;
  stderr: string;
  argv: string;
  jqargv: string;
  stdin: string;
  dflag: string;
  bodies: string[];
  bodymeta: string[];
  leftover: string[];
  calls: number;
}

function runScript(label: string, extraEnv: Record<string, string>, failOn = 0): Run {
  const dir = path.join(root, label);
  const mockDir = path.join(dir, "mock");
  const tmp = path.join(dir, "tmp");
  spawnSync("mkdir", ["-p", mockDir, tmp]);
  const r = spawnSync("bash", [SCRIPT], {
    encoding: "utf8",
    env: {
      PATH: `${binDir}:${process.env.PATH}`,
      NODE_ENV: "test",
      HOME: dir,
      TMPDIR: tmp,
      MOCK_DIR: mockDir,
      REAL_JQ: findJq(),
      MOCK_FAIL_ON: String(failOn),
      SUPABASE_ACCESS_TOKEN: SYN.token,
      PROJECT_REF: "mlwiodleouzwniehynfz",
      RESEND_API_KEY: SYN.resend,
      ...extraEnv,
    },
  });
  const read = (n: string) => (existsSync(path.join(mockDir, n)) ? readFileSync(path.join(mockDir, n), "utf8") : "");
  const calls = Number(read("count") || "0");
  const bodies: string[] = [];
  for (let i = 1; i <= calls; i++) bodies.push(read(`body.${i}`));
  return {
    rc: r.status,
    stdout: r.stdout,
    stderr: r.stderr,
    argv: read("argv"),
    jqargv: read("jqargv"),
    stdin: read("stdin"),
    dflag: read("dflag"),
    bodies,
    bodymeta: read("bodymeta").split("\n").filter(Boolean),
    leftover: readdirSync(tmp),
    calls,
  };
}

const ALL_PROVIDERS = {
  GOOGLE_CLIENT_ID: SYN.googleId,
  GOOGLE_CLIENT_SECRET: SYN.googleSecret,
  AZURE_CLIENT_ID: SYN.azureId,
  AZURE_CLIENT_SECRET: SYN.azureSecret,
};

describe("configure-auth.sh keeps secrets off every argv (success path, both PATCH sites)", () => {
  let run: Run;
  beforeAll(() => {
    run = runScript("ok", ALL_PROVIDERS);
  });

  it("completes and makes the main PATCH plus one PATCH per configured provider", () => {
    expect(run.rc).toBe(0);
    expect(run.calls).toBe(3);
  });

  it("main PATCH body file holds the Resend key and the confirmation template", () => {
    const body = JSON.parse(run.bodies[0]);
    expect(body.smtp_pass).toBe(SYN.resend);
    expect(body.mailer_templates_magic_link_content.length).toBeGreaterThan(0);
  });

  it("provider PATCH body files hold each client secret", () => {
    const g = JSON.parse(run.bodies[1]);
    expect(g.external_google_secret).toBe(SYN.googleSecret);
    expect(g.external_google_client_id).toBe(SYN.googleId);
    const a = JSON.parse(run.bodies[2]);
    expect(a.external_azure_secret).toBe(SYN.azureSecret);
    expect(a.external_azure_url).toBe("https://login.microsoftonline.com/common");
  });

  it("no secret value appears in any curl argv or any jq argv", () => {
    for (const v of [SYN.resend, SYN.googleSecret, SYN.azureSecret]) {
      expect(run.argv).not.toContain(v);
      expect(run.jqargv).not.toContain(v);
    }
  });

  it("every PATCH sends the body with --data-binary @file, never an inline -d/--data flag", () => {
    expect(run.dflag).toBe("");
    expect(run.bodymeta).toHaveLength(3);
    const dataBinary = run.argv.split("\n").filter((l) => l === "--data-binary");
    expect(dataBinary).toHaveLength(3);
    expect(run.argv).toContain("Content-Type: application/json");
  });

  it("body files are private (0600) and exist only inside the script's TMPDIR", () => {
    for (const m of run.bodymeta) {
      const [mode, file] = m.split(" ");
      expect(mode).toBe("600");
      expect(path.basename(file)).toMatch(/^configure-auth-body\./);
    }
  });

  it("the bearer still rides curl's stdin config and not argv", () => {
    expect(run.stdin).toContain(`header = "Authorization: Bearer ${SYN.token}"`);
    expect(run.argv).not.toContain(SYN.token);
    // The bearer only ever goes to the pinned Management API host (the PAT-exfil seam the host-pin lint guards).
    expect(run.argv).toContain("https://api.supabase.com/v1/projects/");
  });

  it("the body file is removed on success", () => {
    expect(run.leftover).toEqual([]);
  });
});

describe("configure-auth.sh removes the body file on every error path", () => {
  it("main PATCH rejected (HTTP 500): exits 1, no secret in argv, file removed", () => {
    const run = runScript("err-main", ALL_PROVIDERS, 1);
    expect(run.rc).toBe(1);
    expect(run.calls).toBe(1);
    expect(JSON.parse(run.bodies[0]).smtp_pass).toBe(SYN.resend);
    expect(run.argv).not.toContain(SYN.resend);
    expect(run.leftover).toEqual([]);
  });

  it("provider PATCH rejected (HTTP 500): warns, no secret in argv, file removed", () => {
    const run = runScript("err-provider", ALL_PROVIDERS, 2);
    expect(run.rc).toBe(0);
    expect(run.stderr).toContain("google OAuth config failed");
    expect(run.argv).not.toContain(SYN.googleSecret);
    expect(run.leftover).toEqual([]);
  });

  it("an unusable bearer token is refused before any body file is created or any curl runs", () => {
    const run = runScript("bad-token", { SUPABASE_ACCESS_TOKEN: 'bad "token' });
    expect(run.rc).toBe(1);
    expect(run.calls).toBe(0);
    expect(run.leftover).toEqual([]);
  });
});
