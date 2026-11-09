import { describe, test, expect, beforeEach, afterEach, vi } from "vitest";
import { ALLOWED_SERVICE_ENV_VARS, AGENT_GIT_GLOBAL_CONFIG, buildAgentEnv } from "../server/agent-env";

// Force the production branch of the plugin-path guard (mirrors the harness in
// plugin-path.test.ts). The `buildAgentEnv` describe's afterEach calls
// vi.unstubAllEnvs() to revert these. Under the ambient VITEST runner the guard
// is a no-op — the fail-closed injection only fires in a production env.
function stubProductionEnv(): void {
  vi.stubEnv("VITEST", "");
  vi.stubEnv("NODE_ENV", "production");
}

// Intentionally duplicated from agent-env.ts -- importing would defeat the
// security boundary test. Changes to the allowlist must be reflected here,
// forcing an explicit review of what the subprocess can see.
const SERVER_SECRETS = [
  "SUPABASE_SERVICE_ROLE_KEY",
  "BYOK_ENCRYPTION_KEY",
  "STRIPE_SECRET_KEY",
  "STRIPE_WEBHOOK_SECRET",
  "STRIPE_PRICE_ID",
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  "PORT",
  "WORKSPACES_ROOT",
  "SOLEUR_PLUGIN_PATH",
  "CLAUDECODE",
  "RANDOM_NEW_SECRET",
] as const;

const EXPECTED_ALLOWLIST = [
  "HOME",
  "PATH",
  "NODE_ENV",
  "LANG",
  "LC_ALL",
  "TERM",
  "USER",
  "SHELL",
  "TMPDIR",
  // Proxy vars are DELIBERATELY absent (structural review A8): ambient proxy
  // env would steer every session outside the egress guard.
  "SOLEUR_BWRAP_SECCOMP_BPF",
] as const;

const EXPECTED_OVERRIDES: Record<string, string> = {
  DISABLE_AUTOUPDATER: "1",
  DISABLE_TELEMETRY: "1",
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
  // Plugin Stop hook `unkept-promise-hook.sh` is operator-CLI vocabulary; the web
  // Concierge loads the plugin's hooks.json, so it must opt out (ADR-093 amendment).
  SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK: "1",
  // Plugin PreToolUse hook `operator-stage-approval.sh` (ADR-264): no web approval adapter yet, so it
  // must be a no-op in the web runtime and a staged write fails closed at exit 75.
  SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK: "1",
  // Plugin PreToolUse hook `destructive-command-guard.sh` (ADR-093/ADR-277): switched off for hosted sessions by decision D8 (the hosted
  // `ask` path is unmeasured; see the comment at the override in agent-env.ts for what actually gates hosted Bash).
  SOLEUR_DISABLE_DESTRUCTIVE_GUARD: "1",
  // launch-check refuses to file issues or write its report when unattended; a hosted session is unattended (ADR-314).
  LAUNCH_CHECK_HEADLESS: "1",
  // #9600 git config-carrier pin, applied to every session (git-auth or not): see the describe below.
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_CONFIG_GLOBAL: "/usr/local/share/soleur/agent.gitconfig",
  GIT_CONFIG_COUNT: "1",
  GIT_CONFIG_KEY_0: "safe.bareRepository",
  GIT_CONFIG_VALUE_0: "explicit",
};

describe("buildAgentEnv", () => {
  const savedEnv: Record<string, string | undefined> = {};
  const env = process.env as Record<string, string | undefined>;

  beforeEach(() => {
    // Save and set all allowlisted vars so tests are deterministic
    for (const key of EXPECTED_ALLOWLIST) {
      savedEnv[key] = env[key];
      env[key] = `test-${key.toLowerCase()}`;
    }
    // Inject server secrets into process.env
    for (const key of SERVER_SECRETS) {
      savedEnv[key] = env[key];
      env[key] = `secret-${key.toLowerCase()}`;
    }
  });

  afterEach(() => {
    // Revert any vi.stubEnv from stubProductionEnv() FIRST, before the manual
    // save/restore below re-asserts the beforeEach-set allowlist values.
    vi.unstubAllEnvs();
    // Restore original env
    for (const key of [...EXPECTED_ALLOWLIST, ...SERVER_SECRETS]) {
      if (savedEnv[key] === undefined) {
        delete env[key];
      } else {
        env[key] = savedEnv[key];
      }
    }
  });

  test("sets ANTHROPIC_API_KEY to the provided key", () => {
    const env = buildAgentEnv({ value: "sk-ant-test-key", scheme: "api_key" });
    expect(env.ANTHROPIC_API_KEY).toBe("sk-ant-test-key");
  });

  test("forwards all allowlisted vars when present", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    for (const key of EXPECTED_ALLOWLIST) {
      expect(env[key]).toBe(`test-${key.toLowerCase()}`);
    }
  });

  test("excludes all known server secrets", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    for (const key of SERVER_SECRETS) {
      expect(env).not.toHaveProperty(key);
    }
  });

  test("always includes hardcoded overrides", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    for (const [key, value] of Object.entries(EXPECTED_OVERRIDES)) {
      expect(env[key]).toBe(value);
    }
  });

  test("operator-only Stop hook opt-out is set for both schemes and an ambient value cannot override it", () => {
    // Rides AGENT_ENV_OVERRIDES, not the allowlist: an ambient "0" must lose.
    vi.stubEnv("SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK", "0");
    const apiKeyEnv = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    const oauthEnv = buildAgentEnv({ value: "oauth-test", scheme: "oauth_token" });
    expect(apiKeyEnv.SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK).toBe("1");
    expect(oauthEnv.SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK).toBe("1");
  });

  test("the operator-stage approval hook opt-out is set for both schemes, ambient 0 loses, and only the exact value 1 is ever emitted (ADR-264)", () => {
    // If buildAgentEnv stops setting this, the web Concierge would load the plugin's approval hook with
    // no approval surface behind it. Rides AGENT_ENV_OVERRIDES, not the allowlist.
    vi.stubEnv("SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK", "0");
    const apiKeyEnv = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    const oauthEnv = buildAgentEnv({ value: "oauth-test", scheme: "oauth_token" });
    expect(apiKeyEnv.SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK).toBe("1");
    expect(oauthEnv.SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK).toBe("1");
  });

  test("the destructive-command guard opt-out is set for both schemes, ambient 0 loses, and only the exact value 1 is ever emitted (ADR-093/ADR-277)", () => {
    // If buildAgentEnv stops setting this, or lets an ambient value win, the web Concierge would load the plugin's
    // destructive-command guard, whose `ask` has no prompt to reach in a hosted session. Rides AGENT_ENV_OVERRIDES, not the allowlist.
    vi.stubEnv("SOLEUR_DISABLE_DESTRUCTIVE_GUARD", "0");
    const apiKeyEnv = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    const oauthEnv = buildAgentEnv({ value: "oauth-test", scheme: "oauth_token" });
    expect(apiKeyEnv.SOLEUR_DISABLE_DESTRUCTIVE_GUARD).toBe("1");
    expect(oauthEnv.SOLEUR_DISABLE_DESTRUCTIVE_GUARD).toBe("1");
  });

  test("launch-check is told the hosted session is unattended for both schemes, and an ambient 0 loses", () => {
    vi.stubEnv("LAUNCH_CHECK_HEADLESS", "0");
    const apiKeyEnv = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    const oauthEnv = buildAgentEnv({ value: "oauth-test", scheme: "oauth_token" });
    expect(apiKeyEnv.LAUNCH_CHECK_HEADLESS).toBe("1");
    expect(oauthEnv.LAUNCH_CHECK_HEADLESS).toBe("1");
  });

  test("omits allowlisted vars not present in process.env", () => {
    const mutableEnv = process.env as Record<string, string | undefined>;
    delete mutableEnv.LANG;
    delete mutableEnv.LC_ALL;
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    expect(env).not.toHaveProperty("LANG");
    expect(env).not.toHaveProperty("LC_ALL");
  });

  test("total key count matches allowlist + overrides + ANTHROPIC_API_KEY", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    const expectedCount =
      EXPECTED_ALLOWLIST.length +
      Object.keys(EXPECTED_OVERRIDES).length +
      1; // ANTHROPIC_API_KEY
    expect(Object.keys(env).length).toBe(expectedCount);
  });

  test("does not contain CLAUDECODE (prevents nested-session error)", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    expect(env).not.toHaveProperty("CLAUDECODE");
  });

  test("does NOT forward ambient proxy vars (default-deny; the egressProxy injection is the only carrier)", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    expect(env.HTTPS_PROXY).toBeUndefined();
    expect(env.http_proxy).toBeUndefined();
    expect(env.HTTP_PROXY).toBeUndefined();
    expect(env.NO_PROXY).toBeUndefined();
  });

  test("contains only known keys (no process.env leakage)", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    expect(env).not.toHaveProperty("RANDOM_NEW_SECRET");
  });

  test("injects service tokens when provided", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" }, {
      CLOUDFLARE_API_TOKEN: "cf-token-123",
      STRIPE_SECRET_KEY: "sk_test_456",
    });
    expect(env.ANTHROPIC_API_KEY).toBe("sk-ant-test");
    expect(env.CLOUDFLARE_API_TOKEN).toBe("cf-token-123");
    expect(env.STRIPE_SECRET_KEY).toBe("sk_test_456");
  });

  test("works without service tokens (backward compatible)", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    expect(env.ANTHROPIC_API_KEY).toBe("sk-ant-test");
    expect(env).not.toHaveProperty("CLOUDFLARE_API_TOKEN");
  });

  test("service tokens do not leak server secrets", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" }, {
      GITHUB_TOKEN: "ghp_test",
    });
    expect(env.GITHUB_TOKEN).toBe("ghp_test");
    for (const key of SERVER_SECRETS) {
      if (key === "STRIPE_SECRET_KEY") continue; // Not injected in this test
      expect(env).not.toHaveProperty(key);
    }
  });

  test("empty service tokens map does not affect output", () => {
    const envWithout = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    const envWith = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" }, {});
    expect(Object.keys(envWith).length).toBe(Object.keys(envWithout).length);
  });

  // #9600 — the git config-carrier pin. A bare repository committed into an untrusted connected repo is a
  // working config carrier after a plain clone (the real-git proof is in safe-bash-git-config-exec.test.ts);
  // `safe.bareRepository=explicit` makes git ignore it. The pin must hold for every session shape.
  describe("git config-carrier pin (#9600)", () => {
    const PIN = {
      GIT_CONFIG_NOSYSTEM: "1",
      GIT_CONFIG_GLOBAL: "/usr/local/share/soleur/agent.gitconfig",
      GIT_CONFIG_COUNT: "1",
      GIT_CONFIG_KEY_0: "safe.bareRepository",
      GIT_CONFIG_VALUE_0: "explicit",
    } as const;
    const CREDS = [
      { value: "sk-ant-test", scheme: "api_key" as const },
      { value: "sk-oauth-test", scheme: "oauth_token" as const },
    ];
    const OPTS = [
      undefined,
      {},
      { ghToken: "ghs_minted_install_token" },
      { gitAskpassScriptPath: "/workspaces/w/.askpass.sh", gitInstallationToken: "ghs_install_token_value" },
      { egressProxy: { workspaceId: "w", token: "t", port: 3128 } },
    ];

    test("present for every auth scheme x session shape (with and without git-auth)", () => {
      let n = 0;
      for (const cred of CREDS) {
        for (const opts of OPTS) {
          const out = buildAgentEnv(cred, undefined, opts);
          for (const [k, v] of Object.entries(PIN)) expect(out[k], `${cred.scheme} ${JSON.stringify(opts)} ${k}`).toBe(v);
          n++;
        }
      }
      expect(n).toBe(CREDS.length * OPTS.length); // floor: the loop really ran every combination
    });

    test("GIT_CONFIG_GLOBAL is the image-owned identity file (never /dev/null, never HOME), shared with the Dockerfile", () => {
      expect(AGENT_GIT_GLOBAL_CONFIG).toBe("/usr/local/share/soleur/agent.gitconfig");
      const out = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
      expect(out.GIT_CONFIG_GLOBAL).toBe(AGENT_GIT_GLOBAL_CONFIG);
      expect(out.GIT_CONFIG_GLOBAL).not.toBe("/dev/null");
    });

    // The pin is spread into the overrides, so what keeps it from being displaced is that NO later source
    // (the ambient allowlist, the BYOK service-token set) can name a GIT_CONFIG_* variable. Assert THAT
    // set-level property directly: a behavioural "ambient value cannot displace it" test passes only
    // because of this filtering and would stay green if the filtering were removed along with a re-assert.
    test("no ambient-allowlisted or service-token variable may be a GIT_CONFIG_* name", () => {
      expect(EXPECTED_ALLOWLIST.filter((k) => /^GIT_CONFIG_/.test(k))).toEqual([]);
      expect([...ALLOWED_SERVICE_ENV_VARS].filter((k) => /^GIT_CONFIG_/.test(k))).toEqual([]);
      expect(ALLOWED_SERVICE_ENV_VARS.size).toBeGreaterThan(0); // the set really was enumerated
    });

    test("an ambient GIT_CONFIG_* process value never reaches the agent env and the pin is exactly one config pair", () => {
      const keys = ["GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0", "GIT_CONFIG_GLOBAL"];
      const saved = keys.map((k) => [k, env[k]] as const);
      try {
        env.GIT_CONFIG_COUNT = "9";
        env.GIT_CONFIG_KEY_0 = "core.fsmonitor";
        env.GIT_CONFIG_VALUE_0 = "/tmp/evil";
        env.GIT_CONFIG_GLOBAL = "/tmp/evil-gitconfig";
        const out = buildAgentEnv(
          { value: "sk-ant-test", scheme: "api_key" },
          { GIT_CONFIG_VALUE_0: "all", GIT_CONFIG_COUNT: "0" },
        );
        for (const [k, v] of Object.entries(PIN)) expect(out[k], k).toBe(v);
        expect(Object.keys(out).filter((k) => /^GIT_CONFIG_(KEY|VALUE)_\d+$/.test(k)).sort()).toEqual([
          "GIT_CONFIG_KEY_0",
          "GIT_CONFIG_VALUE_0",
        ]);
      } finally {
        for (const [k, v] of saved) {
          if (v === undefined) delete env[k];
          else env[k] = v;
        }
      }
    });
  });

  // --- GH_TOKEN injection (Issue A — Concierge gh-auth, AC3) ---------------
  // The minted GitHub App installation token rides as `GH_TOKEN` (the var
  // `gh` prefers over `GITHUB_TOKEN`) via a dedicated typed `opts.ghToken`
  // param — NOT through the serviceTokens map (which keys to GITHUB_TOKEN
  // and is BYOK-clobberable). See agent-env.ts and cc-dispatcher.ts.
  describe("ghToken injection", () => {
    test("injects GH_TOKEN when opts.ghToken is set", () => {
      const env = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        undefined,
        { ghToken: "ghs_minted_install_token" },
      );
      expect(env.GH_TOKEN).toBe("ghs_minted_install_token");
      // Auth-var switch untouched.
      expect(env.ANTHROPIC_API_KEY).toBe("sk-ant-test");
    });

    test("omits GH_TOKEN when opts.ghToken is absent or empty", () => {
      const envNoOpts = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
      expect(envNoOpts).not.toHaveProperty("GH_TOKEN");
      const envEmpty = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        undefined,
        { ghToken: "" },
      );
      expect(envEmpty).not.toHaveProperty("GH_TOKEN");
      const envUndef = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        undefined,
        {},
      );
      expect(envUndef).not.toHaveProperty("GH_TOKEN");
    });

    test("GH_TOKEN (minted) and GITHUB_TOKEN (BYOK service token) coexist; gh prefers GH_TOKEN", () => {
      const env = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        { GITHUB_TOKEN: "ghp_byok_pat" },
        { ghToken: "ghs_minted_install_token" },
      );
      // Both present — the minted install token is the gh-preferred var,
      // and the BYOK PAT is left untouched under its own var.
      expect(env.GH_TOKEN).toBe("ghs_minted_install_token");
      expect(env.GITHUB_TOKEN).toBe("ghp_byok_pat");
    });

    test("GH_TOKEN is injected even though it is NOT in ALLOWED_SERVICE_ENV_VARS (bypasses the service-token loop)", () => {
      // Passing GH_TOKEN through the serviceTokens map would be dropped by the
      // allowlist; the opts param is the only path that lands it.
      const viaServiceTokens = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        { GH_TOKEN: "should_be_dropped" },
      );
      expect(viaServiceTokens).not.toHaveProperty("GH_TOKEN");
      const viaOpts = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        undefined,
        { ghToken: "lands_via_opts" },
      );
      expect(viaOpts.GH_TOKEN).toBe("lands_via_opts");
    });
  });

  // --- CLAUDE_PLUGIN_ROOT injection (Slice B / AC3 — connected-repo shadow
  // fix) -------------------------------------------------------------------
  // The per-dispatch deployed plugin root (`getPluginPath()` →
  // `/app/shared/plugins/soleur`) rides as `CLAUDE_PLUGIN_ROOT` via a typed
  // `opts.pluginPath` param. It is deliberately NOT in AGENT_ENV_ALLOWLIST
  // (that list copies ambient process.env; this is a per-dispatch value), so
  // an ambient process.env.CLAUDE_PLUGIN_ROOT must NEVER leak into the agent
  // env — only the explicit opts value lands. The deployed skills'
  // bare `"${CLAUDE_PLUGIN_ROOT}/…"` shell-outs (ADR-179 A18) read this var so
  // they run the platform-deployed script, not the untrusted workspace copy.
  describe("CLAUDE_PLUGIN_ROOT injection", () => {
    test("injects CLAUDE_PLUGIN_ROOT when opts.pluginPath is set", () => {
      const env = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        undefined,
        { pluginPath: "/app/shared/plugins/soleur" },
      );
      expect(env.CLAUDE_PLUGIN_ROOT).toBe("/app/shared/plugins/soleur");
      // Auth-var switch untouched.
      expect(env.ANTHROPIC_API_KEY).toBe("sk-ant-test");
    });

    // AC2 (mutation coverage — closes the fail-OPEN hole). A fail-OPEN
    // implementation (bare `if (opts?.pluginPath)` assignment that sets an
    // UNVALIDATED path and silently omits when absent) MUST NOT pass this set.
    // The prod-simulated cases below (empty/absent→throw, non-empty-invalid→
    // throw, valid-/app→set) can only pass a fail-CLOSED injection that routes
    // through assertTrustedPluginPath and throws on an absent/empty export.
    describe("AC2 — fail-closed injection (prod-simulated)", () => {
      test("prod, empty pluginPath → throws (export required)", () => {
        stubProductionEnv();
        expect(() =>
          buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" }, undefined, {
            pluginPath: "",
          }),
        ).toThrow(/CLAUDE_PLUGIN_ROOT export required/);
      });

      test("prod, absent pluginPath (no opts) → throws (export required)", () => {
        stubProductionEnv();
        expect(() =>
          buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" }),
        ).toThrow(/CLAUDE_PLUGIN_ROOT export required/);
      });

      // One isolated, self-labeling case per invalid shape (a shared loop would
      // throw on the first bad element and mask the rest). Each would be SET
      // verbatim by a fail-open bare assignment; the fail-closed injection routes
      // it through assertTrustedPluginPath, which throws /plugin path/i for any
      // non-/app/ (or relative/traversal) value.
      test.each([
        "/workspaces/abc/plugins/soleur",
        "/tmp/evil/plugins/soleur",
        "plugins/soleur", // relative
        "/app/../workspaces/x/plugins/soleur", // traversal → resolves outside /app/
      ])(
        "prod, non-empty INVALID pluginPath %s → throws via assertTrustedPluginPath (not a bare assignment)",
        (bad) => {
          stubProductionEnv();
          expect(() =>
            buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" }, undefined, {
              pluginPath: bad,
            }),
          ).toThrow(/plugin path/i);
        },
      );

      test("prod, valid /app pluginPath → sets it (survives validation, not only the ambient-VITEST no-op)", () => {
        stubProductionEnv();
        const env = buildAgentEnv(
          { value: "sk-ant-test", scheme: "api_key" },
          undefined,
          { pluginPath: "/app/shared/plugins/soleur" },
        );
        expect(env.CLAUDE_PLUGIN_ROOT).toBe("/app/shared/plugins/soleur");
      });
    });

    test("ambient-VITEST, absent/empty pluginPath → still omits (fixture ergonomics preserved)", () => {
      const envNoOpts = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
      expect(envNoOpts).not.toHaveProperty("CLAUDE_PLUGIN_ROOT");
      const envEmpty = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        undefined,
        { pluginPath: "" },
      );
      expect(envEmpty).not.toHaveProperty("CLAUDE_PLUGIN_ROOT");
      const envUndef = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        undefined,
        {},
      );
      expect(envUndef).not.toHaveProperty("CLAUDE_PLUGIN_ROOT");
    });

    test("does NOT forward an ambient process.env.CLAUDE_PLUGIN_ROOT (not allowlisted)", () => {
      const mutableEnv = process.env as Record<string, string | undefined>;
      const saved = mutableEnv.CLAUDE_PLUGIN_ROOT;
      mutableEnv.CLAUDE_PLUGIN_ROOT = "/app/ambient-should-not-leak";
      try {
        // No opts.pluginPath → the ambient value must not ride through the
        // allowlist loop (CLAUDE_PLUGIN_ROOT is intentionally not allowlisted).
        const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
        expect(env).not.toHaveProperty("CLAUDE_PLUGIN_ROOT");
      } finally {
        if (saved === undefined) delete mutableEnv.CLAUDE_PLUGIN_ROOT;
        else mutableEnv.CLAUDE_PLUGIN_ROOT = saved;
      }
    });
  });
});
