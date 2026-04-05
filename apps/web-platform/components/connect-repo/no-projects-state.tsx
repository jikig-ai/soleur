"use client";

import { FolderIcon } from "@/components/icons";
import { Badge } from "@/components/ui/badge";
import { GoldButton } from "@/components/ui/gold-button";
import { OutlinedButton } from "@/components/ui/outlined-button";
import { Card } from "@/components/ui/card";
import { serif } from "./fonts";

interface NoProjectsStateProps {
  onUpdateAccess: () => void;
  onBack: () => void;
}

export function NoProjectsState({ onUpdateAccess, onBack }: NoProjectsStateProps) {
  return (
    <div className="mx-auto max-w-lg space-y-6">
      <div className="flex items-center gap-3">
        <Badge>CONNECT PROJECT</Badge>
      </div>

      <div className="space-y-2">
        <h1 className={`${serif.className} text-3xl font-semibold`}>
          Select a Project
        </h1>
      </div>

      <Card className="flex flex-col items-center py-12 text-center">
        <FolderIcon className="mb-4 h-12 w-12 text-neutral-600" />
        <h3 className="text-lg font-medium text-neutral-200">No projects found</h3>
        <p className="mt-2 max-w-sm text-sm text-neutral-500">
          We could not find any repositories you have granted access to. You may
          need to update the GitHub App permissions to include the repositories
          you want to connect.
        </p>
      </Card>

      <div className="flex items-center gap-3">
        <GoldButton onClick={onUpdateAccess}>Update Access on GitHub</GoldButton>
        <OutlinedButton onClick={onBack}>Go Back</OutlinedButton>
      </div>
    </div>
  );
}
