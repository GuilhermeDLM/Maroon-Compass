# Google sign-in handoff

The user chose Google sign-in for cloud accounts because the current Apple Personal Team cannot provision Sign in with Apple. Keep on-device mode independent of any account. Google sign-in requests identity and email only; Maroon Compass does not request Gmail or Google Calendar API access.

## Backend owner: Opus

1. Change `supabase/config.toml` and hosted Auth setup from the planned Apple provider to the Google provider. Keep Apple disabled for this build. Preserve the provider-independent owner RLS, snapshot RPC, and account-deletion function.
2. In Google Auth Platform, create a Web application OAuth client. Put the Supabase callback URL (`https://<project-ref>.supabase.co/auth/v1/callback`) in Google's authorized redirect URIs. Configure only `openid`, email, and profile scopes. Keep the Google client secret in the Supabase dashboard or a local environment variable, never Git or the iOS app.
3. Enable Google in Supabase Auth, add `marooncompass://auth/callback` to its redirect allow list, and deploy/test the account-deletion Edge Function before enabling real accounts. For local Supabase CLI use `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_SECRET` and a nonsecret `client_id` in `[auth.external.google]`.
4. Run database/RLS/RPC and account-deletion tests with Google-authenticated sessions. An email address is not an owner key; continue using the Supabase Auth user ID. Do not enable hosted anonymous sign-in for real schedules.
5. Provide a public Supabase project URL and publishable key for a local build. Never provide a service-role key to the client. Document how to configure them with the `MCSUPABASE_URL` and `MCSUPABASE_PUBLISHABLE_KEY` Xcode build settings.

## iOS owner: Codex

The `codex/google-auth-20260926` branch adds the Supabase Auth Swift package, PKCE browser sign-in with Google, Keychain-backed sessions, local sign-out, and the cloud account deletion UI. The local schedule remains available without configuration or network access. OAuth uses `marooncompass://auth/callback`; the URL scheme is registered in the main app's Info.plist. The signed-in session's access token can be passed to `SupabaseScheduleRepository` when the explicit sync flow is ready.

The iOS OAuth flow cannot be validated live until the Google OAuth client and Supabase provider are configured. The existing signed app and known-good backup remain the device recovery points. No App Groups or Sign in with Apple entitlement is required for Google OAuth.
