"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { safeReturnTo } from "@/lib/safe-return-to";
import { serif, sans } from "@/components/connect-repo/fonts";
import type { Repo, SetupStep } from "@/components/connect-repo/types";
import type { ProjectHealthSnapshot } from "@/server/project-scanner";
import { ChooseState } from "@/components/connect-repo/choose-state";
import { CreateProjectState } from "@/components/connect-repo/create-project-state";
import { GitHubRedirectState } from "@/components/connect-repo/github-redirect-state";
import { SelectProjectState } from "@/components/connect-repo/select-project-state";
import { NoProjectsState } from "@/components/connect-repo/no-projects-state";
import { SettingUpState } from "@/components/connect-repo/setting-up-state";
import { ReadyState } from "@/components/connect-repo/ready-state";
import { FailedState } from "@/components/connect-repo/failed-state";
import { InterruptedState } from "@/components/connect-repo/interrupted-state";
import { GitHubResolveState } from "@/components/connect-repo/github-resolve-state";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
type State =
  | "choose"
  | "create_project"
  | "github_redirect"
  | "github_resolve"
  | "select_project"
  | "no_projects"
  | "setting_up"
  | "ready"
  | "failed"
  | "interrupted";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const DEFAULT_GITHUB_APP_SLUG = process.env.NEXT_PUBLIC_GITHUB_APP_SLUG ?? "soleur-ai";

const SETUP_STEPS_TEMPLATE: SetupStep[] = [
  { label: "Cloning repository", status: "pending" },
  { label: "Scanning project", status: "pending" },
  { label: "Preparing your team", status: "pending" },
];

// ---------------------------------------------------------------------------
// Main Page Component
// ---------------------------------------------------------------------------
export default function ConnectRepoPage() {
  const router = useRouter();
  const searchParams = useSearchParams();

  const [state, setState] = useState<State>(() => {
    if (typeof window !== "undefined") {
      const params = new URLSearchParams(window.location.search);
      // Returning from GitHub App install callback
      const action = params.get("setup_action");
      if (params.get("installation_id") && (action === "install" || action === "update")) {
        return "github_redirect";
      }
    }
    return "choose";
  });
  const [repos, setRepos] = useState<Repo[]>([]);
  const [reposLoading, setReposLoading] = useState(false);
  const [connectedRepoName, setConnectedRepoName] = useState("");
  const [setupSteps, setSetupSteps] = useState<SetupStep[]>(SETUP_STEPS_TEMPLATE);
  const [setupError, setSetupError] = useState<string | null>(null);
  const [healthSnapshot, setHealthSnapshot] = useState<ProjectHealthSnapshot | null>(null);
  const [syncConversationId, setSyncConversationId] = useState<string | null>(null);
  const [pendingCreate, setPendingCreate] = useState<{
    name: string;
    isPrivate: boolean;
  } | null>(null);
  const [appSlug, setAppSlug] = useState(DEFAULT_GITHUB_APP_SLUG);
  const resolveError = searchParams.get("resolve_error") === "1";

  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const stepTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const stateRef = useRef<State>(state);
  const loadingRef = useRef(false);
  const detectAttemptedRef = useRef(false);

  // ---------------------------------------------------------------------------
  // On mount: fetch dynamic app slug and check for GitHub callback params
  // ---------------------------------------------------------------------------
  useEffect(() => {
    fetch("/api/repo/app-info")
      .then((res) => (res.ok ? res.json() : null))
      .then((data) => { if (data?.slug) setAppSlug(data.slug); })
      .catch(() => { /* retain env var fallback */ });
  }, []);

  // ---------------------------------------------------------------------------
  // On mount (no callback): auto-detect existing installation to break loop
  // ---------------------------------------------------------------------------
  useEffect(() => {
    // Skip if returning from GitHub callback (handled by the next useEffect)
    if (searchParams.get("installation_id")) return;
    if (detectAttemptedRef.current) return;
    detectAttemptedRef.current = true;

    // Guard: skip auto-detect when user is in the create flow
    try {
      if (sessionStorage.getItem("soleur_create_flow") === "true") return;
    } catch { /* sessionStorage unavailable */ }

    // Clear stale state to prevent flash of old repo list on remount
    setRepos([]);
    setReposLoading(false);

    (async () => {
      // Guard: redirect to dashboard if project is already ready
      try {
        const statusRes = await fetch("/api/repo/status");
        if (statusRes.ok) {
          const statusData = await statusRes.json();
          if (statusData.status === "ready") {
            router.push("/dashboard");
            return;
          }
        }
      } catch { /* continue to auto-detect */ }

      try {
        const res = await fetch("/api/repo/detect-installation", {
          method: "POST",
        });
        if (!res.ok) return;
        const data = await res.json();
        if (data.installed && data.repos) {
          if (data.repos.length > 0) {
            setRepos(data.repos);
            setState("select_project");
          } else {
            setState("no_projects");
          }
        }
      } catch {
        // Silent — user can still proceed manually via choose screen
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const installationId = searchParams.get("installation_id");
    const setupAction = searchParams.get("setup_action");

    if (!installationId || (setupAction !== "install" && setupAction !== "update")) return;

    // Single atomic effect: register install, then handle pending create or
    // fetch repos. Merging these prevents concurrent useEffect race conditions
    // where stale sessionStorage could overwrite the install callback state.
    (async () => {
      try {
        // Step 1: Register the installation
        const installRes = await fetch("/api/repo/install", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ installationId: Number(installationId) }),
        });
        if (!installRes.ok) {
          setState("interrupted");
          return;
        }

        // Step 2: Check for pending create (from "Start Fresh" flow)
        let pendingCreateData: { name: string; isPrivate: boolean } | null =
          null;
        try {
          const raw = sessionStorage.getItem("soleur_create_project");
          if (raw) {
            pendingCreateData = JSON.parse(raw);
            sessionStorage.removeItem("soleur_create_project");
          }
        } catch {
          // sessionStorage unavailable
        }

        if (pendingCreateData) {
          const createRes = await fetch("/api/repo/create", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              name: pendingCreateData.name,
              private: pendingCreateData.isPrivate,
            }),
          });
          if (!createRes.ok) {
            const data = await createRes.json().catch(() => null);
            setSetupError(data?.error ?? "Failed to create repository");
            setState("failed");
            return;
          }
          const data = await createRes.json();
          startSetup(data.repoUrl, data.fullName, "start_fresh");
        } else {
          // SessionStorage may have been lost. Check if project is already ready
          // before falling through to the import screen.
          try {
            const statusRes = await fetch("/api/repo/status");
            if (statusRes.ok) {
              const statusData = await statusRes.json();
              if (statusData.status === "ready") {
                router.push("/dashboard");
                return;
              }
            }
          } catch { /* fall through to fetchRepos */ }
          await fetchRepos();
        }
      } catch {
        setState("interrupted");
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ---------------------------------------------------------------------------
  // Cleanup polling on unmount
  // ---------------------------------------------------------------------------
  useEffect(() => {
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
      if (stepTimerRef.current) clearInterval(stepTimerRef.current);
    };
  }, []);

  // Keep stateRef in sync for use in event listeners
  useEffect(() => {
    stateRef.current = state;
  }, [state]);

  // ---------------------------------------------------------------------------
  // Fetch repos
  // ---------------------------------------------------------------------------
  const fetchRepos = useCallback(async () => {
    setReposLoading(true);
    try {
      const res = await fetch("/api/repo/repos");
      if (!res.ok) throw new Error("Failed to fetch repos");
      const data = await res.json();
      if (data.repos && data.repos.length > 0) {
        setRepos(data.repos);
        setState("select_project");
      } else {
        setState("no_projects");
      }
    } catch {
      setState("interrupted");
    } finally {
      setReposLoading(false);
    }
  }, []);

  // ---------------------------------------------------------------------------
  // Refresh repos (error-safe — keeps current state on failure)
  // ---------------------------------------------------------------------------
  const refreshRepos = useCallback(async () => {
    if (loadingRef.current) return;
    const currentState = stateRef.current;
    if (currentState !== "select_project" && currentState !== "no_projects") return;
    loadingRef.current = true;
    setReposLoading(true);
    try {
      const res = await fetch("/api/repo/repos");
      if (!res.ok) return;
      const data = await res.json();
      if (data.repos && data.repos.length > 0) {
        setRepos(data.repos);
        setState("select_project");
      } else {
        setState("no_projects");
      }
    } catch {
      // Silently keep current state — don't transition to interrupted
    } finally {
      loadingRef.current = false;
      setReposLoading(false);
    }
  }, []);

  // ---------------------------------------------------------------------------
  // Auto-refresh on tab focus
  // ---------------------------------------------------------------------------
  useEffect(() => {
    function handleVisibilityChange() {
      if (document.visibilityState === "visible") {
        refreshRepos();
      }
    }
    document.addEventListener("visibilitychange", handleVisibilityChange);
    return () => document.removeEventListener("visibilitychange", handleVisibilityChange);
  }, [refreshRepos]);

  // ---------------------------------------------------------------------------
  // Start setup + polling
  // ---------------------------------------------------------------------------
  const startSetup = useCallback(
    async (repoUrl: string, repoName: string, source?: "start_fresh" | "connect_existing") => {
      setConnectedRepoName(repoName);
      setState("setting_up");

      // Reset steps
      const steps = SETUP_STEPS_TEMPLATE.map((s) => ({ ...s }));
      steps[0].status = "active";
      setSetupSteps(steps);

      // Animate steps forward over time (visual polish)
      let currentStep = 0;
      stepTimerRef.current = setInterval(() => {
        currentStep++;
        if (currentStep >= steps.length) {
          if (stepTimerRef.current) clearInterval(stepTimerRef.current);
          return;
        }
        setSetupSteps((prev) =>
          prev.map((s, i) => ({
            ...s,
            status:
              i < currentStep ? "done" : i === currentStep ? "active" : "pending",
          })),
        );
      }, 2000);

      // Kick off setup
      try {
        const res = await fetch("/api/repo/setup", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ repoUrl, source: source ?? "connect_existing" }),
        });
        if (!res.ok) {
          if (stepTimerRef.current) clearInterval(stepTimerRef.current);
          const data = await res.json().catch(() => null);
          setSetupError(data?.error ?? "Failed to start project setup");
          setState("failed");
          return;
        }
      } catch {
        if (stepTimerRef.current) clearInterval(stepTimerRef.current);
        setState("failed");
        return;
      }

      // Poll status (max 60 attempts = 2 minutes before timeout)
      let pollAttempts = 0;
      const MAX_POLL_ATTEMPTS = 60;

      pollRef.current = setInterval(async () => {
        pollAttempts++;
        if (pollAttempts > MAX_POLL_ATTEMPTS) {
          if (pollRef.current) clearInterval(pollRef.current);
          if (stepTimerRef.current) clearInterval(stepTimerRef.current);
          setState("failed");
          return;
        }

        try {
          const res = await fetch("/api/repo/status");
          if (!res.ok) return;
          const data = await res.json();
          if (data.status === "ready") {
            if (pollRef.current) clearInterval(pollRef.current);
            if (stepTimerRef.current) clearInterval(stepTimerRef.current);
            // Mark all steps done
            setSetupSteps((prev) =>
              prev.map((s) => ({ ...s, status: "done" as const })),
            );
            setConnectedRepoName(data.repoName ?? repoName);
            if (data.healthSnapshot) setHealthSnapshot(data.healthSnapshot);
            setSyncConversationId(data.syncConversationId ?? null);
            // Brief delay so user sees the completed checklist
            setTimeout(() => setState("ready"), 800);
          } else if (data.status === "error") {
            if (pollRef.current) clearInterval(pollRef.current);
            if (stepTimerRef.current) clearInterval(stepTimerRef.current);
            setSetupError(data.errorMessage ?? null);
            setState("failed");
          }
        } catch {
          // Network blip — keep polling
        }
      }, 2000);
    },
    [],
  );

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------
  function handleCreateNew() {
    try {
      sessionStorage.setItem("soleur_create_flow", "true");
    } catch { /* sessionStorage unavailable */ }
    setState("create_project");
  }

  async function handleConnectExisting() {
    if (loadingRef.current) return;
    loadingRef.current = true;
    setReposLoading(true);
    try {
      // 1. Try repos directly (installation already registered)
      const res = await fetch("/api/repo/repos");
      if (res.ok) {
        const data = await res.json();
        if (data.repos && data.repos.length > 0) {
          setRepos(data.repos);
          setState("select_project");
        } else {
          setState("no_projects");
        }
        return;
      }

      // 2. Try auto-detection (app installed on GitHub but not registered in DB)
      const detectRes = await fetch("/api/repo/detect-installation", {
        method: "POST",
      });
      if (detectRes.ok) {
        const detectData = await detectRes.json();
        if (detectData.installed && detectData.repos) {
          if (detectData.repos.length > 0) {
            setRepos(detectData.repos);
            setState("select_project");
          } else {
            setState("no_projects");
          }
          return;
        }
        // Email-only user: resolve GitHub identity via OAuth first
        if (detectData.reason === "no_github_identity") {
          setState("github_resolve");
          return;
        }
      }
    } catch {
      // Network error — fall through to GitHub redirect
    } finally {
      loadingRef.current = false;
      setReposLoading(false);
    }
    // 3. Not installed — redirect to GitHub App install flow
    setState("github_redirect");
  }

  /** Read and clear the stored return path from sessionStorage. */
  function consumeReturnTo(): string {
    try {
      const stored = sessionStorage.getItem("soleur_return_to");
      if (stored) {
        sessionStorage.removeItem("soleur_return_to");
        return safeReturnTo(stored);
      }
    } catch {
      // sessionStorage unavailable
    }
    return "/dashboard";
  }

  function handleSkip() {
    let returnPath = consumeReturnTo();
    if (returnPath === "/dashboard") {
      // Also check URL param directly (no GitHub redirect happened)
      returnPath = safeReturnTo(searchParams.get("return_to"));
    }
    router.push(returnPath);
  }

  async function handleCreateSubmit(name: string, isPrivate: boolean) {
    // Try creating directly — skip GitHub redirect if already installed
    try {
      const createRes = await fetch("/api/repo/create", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, private: isPrivate }),
      });
      if (createRes.ok) {
        const data = await createRes.json();
        startSetup(data.repoUrl, data.fullName, "start_fresh");
        return;
      }
      const errorData = await createRes.json().catch(() => null);
      // 400 with "not installed" → try auto-detection before GitHub redirect
      if (createRes.status === 400) {
        const detectRes = await fetch("/api/repo/detect-installation", {
          method: "POST",
        });
        if (detectRes.ok) {
          const detectData = await detectRes.json();
          if (detectData.installed) {
            // Installation found — retry create
            const retryRes = await fetch("/api/repo/create", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ name, private: isPrivate }),
            });
            if (retryRes.ok) {
              const data = await retryRes.json();
              startSetup(data.repoUrl, data.fullName, "start_fresh");
              return;
            }
          }
          // Email-only user: resolve GitHub identity via OAuth first
          if (detectData.reason === "no_github_identity") {
            setState("github_resolve");
            return;
          }
        }
        setPendingCreate({ name, isPrivate });
        setState("github_redirect");
        return;
      }
      // Other errors → show failed state
      setSetupError(errorData?.error ?? "Failed to create repository");
      setState("failed");
      return;
    } catch {
      // Network error — fall back to GitHub redirect
    }
    setPendingCreate({ name, isPrivate });
    setState("github_redirect");
  }

  function handleGitHubRedirectContinue() {
    if (pendingCreate) {
      // Create flow: redirect to GitHub, then after callback create the repo
      // Store intent in sessionStorage so we know to create after callback
      try {
        sessionStorage.setItem(
          "soleur_create_project",
          JSON.stringify(pendingCreate),
        );
      } catch {
        // sessionStorage unavailable — proceed anyway
      }
    }
    // Persist return_to so it survives the GitHub redirect (validate before storing)
    try {
      const returnTo = searchParams.get("return_to");
      const validated = safeReturnTo(returnTo);
      if (validated !== "/dashboard") {
        sessionStorage.setItem("soleur_return_to", validated);
      }
    } catch {
      // sessionStorage unavailable
    }
    window.location.href = `https://github.com/apps/${appSlug}/installations/new`;
  }

  function handleGitHubRedirectBack() {
    if (pendingCreate) {
      setPendingCreate(null);
      setState("create_project");
    } else {
      setState("choose");
    }
  }

  function handleSelectProject(repo: Repo) {
    startSetup(`https://github.com/${repo.fullName}`, repo.fullName, "connect_existing");
  }

  function handleUpdateAccess() {
    window.location.href = `https://github.com/apps/${appSlug}/installations/new`;
  }

  function handleRetry() {
    setSetupError(null);
    setState("choose");
  }

  function handleResume() {
    window.location.href = `https://github.com/apps/${appSlug}/installations/new`;
  }

  function handleStartOver() {
    try {
      sessionStorage.removeItem("soleur_create_flow");
    } catch { /* sessionStorage unavailable */ }
    setPendingCreate(null);
    setState("choose");
  }

  function handleOpenDashboard() {
    try {
      sessionStorage.removeItem("soleur_create_flow");
    } catch { /* sessionStorage unavailable */ }
    router.push(consumeReturnTo());
  }

  function handleViewKb() {
    router.push("/dashboard/kb");
  }

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------
  return (
    <main
      className={`${serif.variable} ${sans.variable} flex min-h-screen items-center justify-center p-4`}
      style={{ fontFamily: "var(--font-sans), system-ui, sans-serif" }}
    >
      <div className="w-full max-w-3xl">
        {state === "choose" && (
          <>
            {resolveError && (
              <div className="mb-4 rounded-lg border border-red-800/50 bg-red-950/30 px-4 py-3 text-sm text-red-300">
                GitHub connection failed. Please try again.
              </div>
            )}
            <ChooseState
              onCreateNew={handleCreateNew}
              onConnectExisting={handleConnectExisting}
              onSkip={handleSkip}
            />
          </>
        )}
        {state === "create_project" && (
          <CreateProjectState
            onBack={() => setState("choose")}
            onSubmit={handleCreateSubmit}
          />
        )}
        {state === "github_redirect" && (
          <GitHubRedirectState
            onContinue={handleGitHubRedirectContinue}
            onBack={handleGitHubRedirectBack}
          />
        )}
        {state === "github_resolve" && (
          <GitHubResolveState
            onContinue={() => {
              window.location.href = "/api/auth/github-resolve";
            }}
            onBack={() => setState("choose")}
          />
        )}
        {state === "select_project" && (
          <SelectProjectState
            repos={repos}
            loading={reposLoading}
            onSelect={handleSelectProject}
            onBack={() => setState("choose")}
            onRefresh={refreshRepos}
          />
        )}
        {state === "no_projects" && (
          <NoProjectsState
            onUpdateAccess={handleUpdateAccess}
            onBack={() => setState("choose")}
            onRefresh={refreshRepos}
          />
        )}
        {state === "setting_up" && <SettingUpState steps={setupSteps} />}
        {state === "ready" && (
          <ReadyState
            repoName={connectedRepoName}
            onContinue={handleOpenDashboard}
            onViewKb={handleViewKb}
            healthSnapshot={healthSnapshot}
            syncConversationId={syncConversationId}
          />
        )}
        {state === "failed" && <FailedState onRetry={handleRetry} errorMessage={setupError} />}
        {state === "interrupted" && (
          <InterruptedState
            onResume={handleResume}
            onStartOver={handleStartOver}
          />
        )}
      </div>
    </main>
  );
}
