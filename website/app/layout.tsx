import type { Metadata, Viewport } from "next";
import "./globals.css";

const title = "Signalcase — Bug evidence, ready";
const description =
  "A free, open-source macOS app that turns logs from Supabase, Render, GitHub, and your application into evidence-backed bug cases.";

export const metadata: Metadata = {
  metadataBase: process.env.NEXT_PUBLIC_SITE_URL ? new URL(process.env.NEXT_PUBLIC_SITE_URL) : undefined,
  title,
  description,
  applicationName: "Signalcase",
  openGraph: { title, description, siteName: "Signalcase", type: "website" },
  twitter: { card: "summary_large_image", title, description },
};

export const viewport: Viewport = {
  themeColor: "#0c0e0d",
  colorScheme: "dark",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
