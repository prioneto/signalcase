import { createSign } from "node:crypto";

const githubAPI = "https://api.github.com";
const githubAPIVersion = process.env.GITHUB_API_VERSION ?? "2022-11-28";

export type GitHubInstallation = {
  id: number;
  account?: {
    login?: string;
    avatar_url?: string;
    type?: string;
  };
  repository_selection?: string;
  suspended_at?: string | null;
};

export type GitHubRepository = {
  id: number;
  name: string;
  full_name: string;
  private: boolean;
  html_url: string;
  default_branch: string;
  archived?: boolean;
  owner?: {
    login?: string;
    avatar_url?: string;
  };
};

function requiredEnvironment(name: string) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing server environment variable: ${name}`);
  return value;
}

function encodeJSON(value: unknown) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

export function githubCallbackURL() {
  const site = requiredEnvironment("NEXT_PUBLIC_SITE_URL").replace(/\/$/, "");
  return `${site}/api/integrations/github/callback`;
}

export function githubInstallationURL(state: string) {
  const slug = requiredEnvironment("GITHUB_APP_SLUG");
  const url = new URL(`https://github.com/apps/${slug}/installations/new`);
  url.searchParams.set("state", state);
  return url.toString();
}

export function githubAppJWT(now = Math.floor(Date.now() / 1000)) {
  const appID = requiredEnvironment("GITHUB_APP_ID");
  const privateKey = requiredEnvironment("GITHUB_APP_PRIVATE_KEY").replace(/\\n/g, "\n");
  const header = encodeJSON({ alg: "RS256", typ: "JWT" });
  const payload = encodeJSON({ iat: now - 60, exp: now + 9 * 60, iss: appID });
  const unsigned = `${header}.${payload}`;
  const signer = createSign("RSA-SHA256");
  signer.update(unsigned);
  signer.end();
  return `${unsigned}.${signer.sign(privateKey).toString("base64url")}`;
}

async function githubRequest<T>(
  path: string,
  token: string,
  init: RequestInit = {},
): Promise<T> {
  const response = await fetch(`${githubAPI}${path}`, {
    ...init,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": githubAPIVersion,
      "User-Agent": "Signalcase",
      ...init.headers,
    },
    cache: "no-store",
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = payload?.message ?? `GitHub returned ${response.status}.`;
    throw new Error(String(message));
  }
  return payload as T;
}

export async function getGitHubInstallation(installationID: number) {
  return githubRequest<GitHubInstallation>(
    `/app/installations/${installationID}`,
    githubAppJWT(),
  );
}

export async function githubInstallationToken(installationID: number) {
  const token = await githubRequest<{ token: string; expires_at: string }>(
    `/app/installations/${installationID}/access_tokens`,
    githubAppJWT(),
    { method: "POST" },
  );
  return token.token;
}

export async function listGitHubRepositories(installationID: number) {
  const token = await githubInstallationToken(installationID);
  const repositories: GitHubRepository[] = [];
  for (let page = 1; page <= 10; page += 1) {
    const payload = await githubRequest<{ repositories?: GitHubRepository[] }>(
      `/installation/repositories?per_page=100&page=${page}`,
      token,
    );
    const batch = Array.isArray(payload.repositories) ? payload.repositories : [];
    repositories.push(...batch);
    if (batch.length < 100) break;
  }
  return repositories
    .filter((repository) => !repository.archived)
    .sort((left, right) => left.full_name.localeCompare(right.full_name));
}

export async function githubRepositoryEvidence(input: {
  installationID: number;
  repositoryFullName: string;
  start: Date;
  end: Date;
}) {
  const token = await githubInstallationToken(input.installationID);
  const repository = input.repositoryFullName.split("/").map(encodeURIComponent).join("/");
  const url = new URL(`${githubAPI}/repos/${repository}/actions/runs`);
  url.searchParams.set("per_page", "100");
  url.searchParams.set("created", `${input.start.toISOString()}..${input.end.toISOString()}`);
  const path = `${url.pathname}${url.search}`;
  const payload = await githubRequest<{ workflow_runs?: unknown[] }>(path, token);
  return Array.isArray(payload.workflow_runs) ? payload.workflow_runs : [];
}
