// The pulse from the app icon (macOS/Resources/SignalcaseIcon.svg). The
// surrounding lime tile comes from the caller's CSS.
export function BrandMark({ className = "brand-glyph" }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 64 64" fill="none" aria-hidden="true">
      <path d="M12 35h9l4-13 7 25 6-18 4 6h10" stroke="currentColor" strokeWidth="6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
