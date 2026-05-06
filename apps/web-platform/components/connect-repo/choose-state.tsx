"use client";

import { PlusIcon, LinkIcon } from "@/components/icons";
import { Badge } from "@/components/ui/badge";
import { GoldButton } from "@/components/ui/gold-button";
import { OutlinedButton } from "@/components/ui/outlined-button";
import { Card } from "@/components/ui/card";
import { serif } from "./fonts";

interface ChooseStateProps {
  onCreateNew: () => void;
  onConnectExisting: () => void;
  onSkip: () => void;
}

export function ChooseState({ onCreateNew, onConnectExisting, onSkip }: ChooseStateProps) {
  return (
    <div className="space-y-8">
      <div className="space-y-4 text-center">
        <Badge>GETTING STARTED</Badge>
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Give Your AI Team the Full Picture
        </h1>
        <p className="mx-auto max-w-lg text-base text-soleur-text-secondary">
          Your AI team works best when it understands your actual business — your
          decisions, your patterns, what you have built so far. Connect a project
          so your team starts with real context, not a blank slate.
        </p>
        <p className="text-sm text-soleur-text-muted">
          You stay in control — your AI team proposes changes, you decide what ships.
        </p>
      </div>

      <div className="mx-auto grid max-w-2xl grid-cols-1 gap-4 sm:grid-cols-2">
        {/* Card A: Start Fresh */}
        <Card className="flex flex-col justify-between">
          <div className="space-y-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2">
              <PlusIcon className="h-5 w-5 text-soleur-text-secondary" />
            </div>
            <h2 className={`${serif.className} text-xl font-semibold`}>Start Fresh</h2>
            <p className="text-sm text-soleur-text-secondary">
              Starting from scratch? We create a project workspace on GitHub
              (owned by Microsoft) under your own account — you keep full
              ownership of your code and data. Your AI team gets a home base
              from day one.
            </p>
          </div>
          <div className="mt-6">
            <GoldButton onClick={onCreateNew}>Create Project</GoldButton>
          </div>
        </Card>

        {/* Card B: Connect Existing Project */}
        <Card className="flex flex-col justify-between">
          <div className="space-y-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2">
              <LinkIcon className="h-5 w-5 text-soleur-text-secondary" />
            </div>
            <h2 className={`${serif.className} text-xl font-semibold`}>
              Connect Existing Project
            </h2>
            <p className="text-sm text-soleur-text-secondary">
              Already have code on GitHub? Connect it and your AI team starts
              with full context — your architecture, your patterns, your
              decisions.
            </p>
          </div>
          <div className="mt-6">
            <OutlinedButton onClick={onConnectExisting}>Connect Project</OutlinedButton>
          </div>
        </Card>
      </div>

      <p className="text-center text-sm text-soleur-text-muted">
        <button
          type="button"
          onClick={onSkip}
          className="underline decoration-soleur-border-default underline-offset-2 transition-colors hover:text-soleur-text-secondary"
        >
          Skip this step
        </button>{" "}
        — you can connect a project later from Settings.
      </p>
    </div>
  );
}
