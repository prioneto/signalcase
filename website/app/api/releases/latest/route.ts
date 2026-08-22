import { site } from "@/lib/site";

export const dynamic = "force-dynamic";

// Public release manifest consumed by the native update checker. Set
// MAC_RELEASE_VERSION and MAC_RELEASE_BUILD in Vercel whenever a new build is
// published; leave them empty to report that no release is configured yet.
export async function GET() {
  const version = process.env.MAC_RELEASE_VERSION?.trim() || null;
  const build = process.env.MAC_RELEASE_BUILD?.trim() || null;
  const downloadURL = site.macDownloadURL;
  const notesURL = process.env.MAC_RELEASE_NOTES_URL?.trim() || null;

  return Response.json(
    {
      channel: "stable",
      version,
      build,
      downloadUrl: downloadURL,
      notesUrl: notesURL,
      configured: Boolean(version && build && downloadURL),
    },
    {
      headers: {
        "Cache-Control": "public, max-age=300",
        "Access-Control-Allow-Origin": "*",
      },
    },
  );
}
