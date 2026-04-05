export type Repo = {
  name: string;
  fullName: string;
  private: boolean;
  description: string | null;
  language: string | null;
  updatedAt: string;
};

export type SetupStep = {
  label: string;
  status: "pending" | "active" | "done";
};
