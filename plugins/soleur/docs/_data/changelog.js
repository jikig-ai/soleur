import github from "./github.js";

export default async function () {
  const data = await github();
  return data.changelog;
}
