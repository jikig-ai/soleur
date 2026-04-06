"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { safeReturnTo } from "@/lib/safe-return-to";
import { serif, sans } from "@/components/connect-repo/fonts";
import type { Repo, SetupStep } from "@/components/connect-repo/types";
import { ChooseState } from "@/components/connect-repo/choose-state";
import { CreateProjectState } from "@/components/connect-repo/create-project-state";
import { GitHubRedirectState } from "@/components/connect-repo/github-redirect-state";
import { SelectProjectState } from "@/components/connect-repo/select-project-state";
import { NoProjectsState } from "@/components/connect-repo/no-projects-state";
import { SettingUpState } from "@/components/connect-repo/setting-up-state";
import { ReadyState } from "@/components/connect-repo/ready-state";
import { FailedState } from "@/components/connect-repo/failed-state";
import { InterruptedState } from "@/components/connect-repo/interrupted-state";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
type State =
  | "choose"
  | "create_project"
  | "github_redirect"
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
  { label: "Copying your project files", status: "pending" },
  { label: "Scanning project structure", status: "pending" },
  { label: "Detecting knowledge base", status: "pending" },
  { label: "Analyzing conventions and patterns", status: "pending" },
  { label: "Preparing your AI team to work on your project", status: "pending" },
];

// ---------------------------------------------------------------------------
// Main Page Component
// ---------------------------------------------------------------------------
export default function ConnectRepoPage() {
  const router = useRouter();
  const searchParams = useSearchParams();

  const [state, setState] = useState<State>(() => {
    // Avoid flashing the "choose" screen when returning from GitHub App install
    if (typeof window !== "undefined") {
      const params = new URLSearchParams(window.location.search);
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
  const [pendingCreate, setPendingCreate] = useState<{
    name: string;
    isPrivate: boolean;
  } | null>(null);
  const [appSlug, setAppSlug] = useState(DEFAULT_GITHUB_APP_SLUG);

  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const stepTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // ---------------------------------------------------------------------------
  // On mount: fetch dynamic app slug and check for GitHub callback params
  // ---------------------------------------------------------------------------
  useEffect(() => {
    fetch("/api/repo/app-info")
      .then((res) => (res.ok ? res.json() : null))
      .then((data) => { if (data?.slug) setAppSlug(data.slug); })
      .catch(() => { /* retain env var fallback */ });
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
          startSetup(data.repoUrl, data.fullName);
        } else {
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
  // Start setup + polling
  // ---------------------------------------------------------------------------
  const startSetup = useCallback(
    async (repoUrl: string, repoName: string) => {
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
      }, 3000);

      // Kick off setup
      try {
        const res = await fetch("/api/repo/setup", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ repoUrl }),
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
    setState("create_project");
  }

  async function handleConnectExisting() {
    setReposLoading(true);
    try {
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
    } catch {
      // Network error — fall through to GitHub redirect
    } finally {
      setReposLoading(false);
    }
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
        startSetup(data.repoUrl, data.fullName);
        return;
      }
      const errorData = await createRes.json().catch(() => null);
      // 400 with "not installed" → fall back to GitHub redirect
      if (createRes.status === 400) {
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
    startSetup(`https://github.com/${repo.fullName}`, repo.fullName);
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
    setPendingCreate(null);
    setState("choose");
  }

  function handleOpenDashboard() {
    router.push(consumeReturnTo());
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
          <ChooseState
            onCreateNew={handleCreateNew}
            onConnectExisting={handleConnectExisting}
            onSkip={handleSkip}
          />
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
        {state === "select_project" && (
          <SelectProjectState
            repos={repos}
            loading={reposLoading}
            onSelect={handleSelectProject}
            onBack={() => setState("choose")}
          />
        )}
        {state === "no_projects" && (
          <NoProjectsState
            onUpdateAccess={handleUpdateAccess}
            onBack={() => setState("choose")}
          />
        )}
        {state === "setting_up" && <SettingUpState steps={setupSteps} />}
        {state === "ready" && (
          <ReadyState
            repoName={connectedRepoName}
            onContinue={handleOpenDashboard}
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
