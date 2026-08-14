-- GitHub is installed as a GitHub App. The installation ID and selected
-- repository are safe metadata; the app private key remains server-only.
alter type public.provider_kind add value if not exists 'github';
