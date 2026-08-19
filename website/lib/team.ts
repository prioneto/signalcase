import { createHash, randomBytes } from "node:crypto";

export function invitationToken() {
  return randomBytes(32).toString("base64url");
}

export function invitationTokenHash(token: string) {
  return createHash("sha256").update(token).digest("hex");
}

export function normalizedEmail(value: unknown) {
  const email = typeof value === "string" ? value.trim().toLowerCase().slice(0, 320) : "";
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}
