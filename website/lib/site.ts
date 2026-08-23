// Central place for customer-facing company details shown on legal and
// support pages. Replace the placeholders with real values before launch.
export const site = {
  name: "Signalcase",
  // The legal entity operating Signalcase. Fill in a real registered
  // business name (or your own name) before launch.
  legalEntity: "Signalcase",
  supportEmail: "support@signalcase.app",
  privacyEmail: "privacy@signalcase.app",
  domain: process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3002",
  macDownloadURL: process.env.NEXT_PUBLIC_MAC_DOWNLOAD_URL || null,
} as const;
