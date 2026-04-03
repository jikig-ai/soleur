"use client";

import { useState, useRef, useCallback, useEffect } from "react";
import { useRouter } from "next/navigation";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { ChatInput } from "@/components/chat/chat-input";
import { AtMentionDropdown } from "@/components/chat/at-mention-dropdown";
import { LEADER_BG_COLORS } from "@/components/chat/leader-colors";
import { WelcomeCard } from "@/components/chat/welcome-card";
import { PwaInstallBanner } from "@/components/chat/pwa-install-banner";
import { createClient } from "@/lib/supabase/client";

const SUGGESTED_PROMPTS = [
  {
    icon: "📊",
    title: "Review my go-to-market strategy",
    leaders: ["cmo", "cro"] as DomainLeaderId[],
  },
  {
    icon: "📋",
    title: "Draft a privacy policy for my SaaS",
    leaders: ["clo", "cpo"] as DomainLeaderId[],
  },
  {
    icon: "💰",
    title: "Plan Q2 budget and runway",
    leaders: ["cfo", "coo"] as DomainLeaderId[],
  },
  {
    icon: "🗺️",
    title: "Prioritize my product roadmap",
    leaders: ["cpo", "cto"] as DomainLeaderId[],
  },
];

export default function DashboardPage() {
  const router = useRouter();
  const [atQuery, setAtQuery] = useState("");
  const [atVisible, setAtVisible] = useState(false);
  const [atPosition, setAtPosition] = useState(0);
  const insertRef = useRef<((text: string, replaceFrom: number) => void) | null>(null);
  const [onboardingLoaded, setOnboardingLoaded] = useState(false);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [pwaDismissed, setPwaDismissed] = useState(true); // default hidden until fetch

  useEffect(() => {
    const supabase = createClient();
    supabase.auth.getUser().then(({ data: { user } }) => {
      if (!user) {
        setOnboardingLoaded(true);
        return;
      }
      supabase
        .from("users")
        .select("onboarding_completed_at, pwa_banner_dismissed_at")
        .eq("id", user.id)
        .single()
        .then(({ data, error }) => {
          if (error) {
            console.error("[onboarding] fetch error:", error.message);
          } else if (data) {
            if (!data.onboarding_completed_at) setShowOnboarding(true);
            setPwaDismissed(!!data.pwa_banner_dismissed_at);
          }
          setOnboardingLoaded(true);
        });
    });
  }, []);

  const handleSend = useCallback(
    (message: string) => {
      // Complete onboarding on first message (fire-and-forget DB update)
      if (showOnboarding) {
        setShowOnboarding(false);
        const supabase = createClient();
        supabase.auth.getUser().then(({ data: { user } }) => {
          if (user) {
            supabase
              .from("users")
              .update({ onboarding_completed_at: new Date().toISOString() })
              .eq("id", user.id)
              .then(({ error }) => {
                if (error) console.error("[onboarding] update error:", error.message);
                else console.debug("[onboarding]", "first_message_sent");
              });
          }
        });
      }

      // Extract @-mentions to determine leader param
      const mentionPattern = /@(\w+)/g;
      const leaders: string[] = [];
      let m: RegExpExecArray | null;
      while ((m = mentionPattern.exec(message)) !== null) {
        const tag = m[1].toLowerCase();
        const leader = DOMAIN_LEADERS.find(
          (l) => l.id === tag || l.name.toLowerCase() === tag,
        );
        if (leader) leaders.push(leader.id);
      }

      const params = new URLSearchParams();
      params.set("msg", message);
      if (leaders.length > 0) {
        params.set("leader", leaders[0]);
      }
      router.push(`/dashboard/chat/new?${params.toString()}`);
    },
    [router, showOnboarding],
  );

  const handleAtTrigger = useCallback((query: string, cursorPosition: number) => {
    setAtQuery(query);
    setAtPosition(cursorPosition);
    setAtVisible(true);
  }, []);

  const handleAtDismiss = useCallback(() => {
    setAtVisible(false);
  }, []);

  const handleAtSelect = useCallback(
    (leaderId: DomainLeaderId) => {
      setAtVisible(false);
      if (insertRef.current) {
        insertRef.current(`@${leaderId}`, atPosition);
      }
    },
    [atPosition],
  );

  const handlePromptClick = useCallback(
    (promptText: string) => {
      if (insertRef.current) {
        insertRef.current(promptText, 0);
      }
    },
    [],
  );

  const handleLeaderClick = useCallback(
    (leaderId: DomainLeaderId) => {
      if (insertRef.current) {
        insertRef.current(`@${leaderId}`, 0);
      }
    },
    [],
  );

  const handlePwaDismiss = useCallback(() => {
    setPwaDismissed(true);
    console.debug("[onboarding]", "pwa_banner_dismissed");
    const supabase = createClient();
    supabase.auth.getUser().then(({ data: { user } }) => {
      if (user) {
        supabase
          .from("users")
          .update({ pwa_banner_dismissed_at: new Date().toISOString() })
          .eq("id", user.id)
          .then(({ error }) => {
            if (error) console.error("[onboarding] pwa dismiss error:", error.message);
          });
      }
    });
  }, []);

  return (
    <div className="mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col items-center justify-center px-4 py-10">
      {/* Hero */}
      <p className="mb-3 text-xs font-medium tracking-widest text-amber-500">
        COMMAND CENTER
      </p>
      <h1 className="mb-3 text-center text-3xl font-semibold text-white md:text-4xl">
        What are you building today?
      </h1>
      <p className="mb-8 text-center text-sm text-neutral-400">
        Ask anything. Your 8 department leaders will auto-route to the right
        experts.
      </p>

      {/* Welcome card for first-time users */}
      {onboardingLoaded && showOnboarding && <WelcomeCard />}

      {/* iOS Safari PWA install banner */}
      {onboardingLoaded && (
        <PwaInstallBanner dismissed={pwaDismissed} onDismiss={handlePwaDismiss} />
      )}

      {/* Chat input with @-mention dropdown */}
      <div className="relative mb-2 w-full">
        <AtMentionDropdown
          query={atQuery}
          visible={atVisible}
          onSelect={handleAtSelect}
          onDismiss={handleAtDismiss}
        />
        <ChatInput
          onSend={handleSend}
          onAtTrigger={handleAtTrigger}
          onAtDismiss={handleAtDismiss}
          insertRef={insertRef}
        />
      </div>
      <div className="mb-8 flex w-full items-center justify-between text-xs text-neutral-400">
        <span className={showOnboarding ? "animate-pulse text-amber-500/80" : ""}>
          Type @ to mention a specific leader
        </span>
        <span>Enter to send</span>
      </div>

      {/* Suggested prompts */}
      <div className="mb-10 grid w-full grid-cols-2 gap-3 md:grid-cols-4">
        {SUGGESTED_PROMPTS.map((prompt) => (
          <button
            key={prompt.title}
            type="button"
            onClick={() => handlePromptClick(prompt.title)}
            className="flex flex-col gap-2 rounded-xl border border-neutral-800 bg-neutral-900/50 p-4 text-left transition-colors hover:border-neutral-600"
          >
            <span className="text-lg">{prompt.icon}</span>
            <span className="text-sm font-medium text-white">
              {prompt.title}
            </span>
            <div className="flex gap-1">
              {prompt.leaders.map((id) => (
                <span
                  key={id}
                  className="text-xs text-neutral-500"
                >
                  {DOMAIN_LEADERS.find((l) => l.id === id)?.name}
                </span>
              ))}
            </div>
          </button>
        ))}
      </div>

      {/* YOUR ORGANIZATION leader strip */}
      <p className="mb-4 text-xs font-medium tracking-widest text-neutral-400">
        YOUR ORGANIZATION
      </p>
      <div className="flex flex-wrap justify-center gap-3">
        {DOMAIN_LEADERS.map((leader) => (
          <button
            key={leader.id}
            type="button"
            onClick={() => handleLeaderClick(leader.id)}
            className="group flex items-center gap-1.5 rounded-lg px-2 py-1 transition-colors hover:bg-neutral-800/50"
          >
            <span
              className={`flex h-5 w-5 items-center justify-center rounded text-[10px] font-semibold text-white ${LEADER_BG_COLORS[leader.id]}`}
            >
              {leader.name.slice(0, 2)}
            </span>
            <span className="text-xs text-neutral-500 group-hover:text-neutral-300">
              {leader.name}
            </span>
          </button>
        ))}
      </div>
    </div>
  );
}
