import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Signalcase — Bug evidence, ready",
  description: "Turn logs from Supabase, Render, and your application into evidence-backed bug cases.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
