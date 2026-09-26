// Deletes the calling user's Supabase Auth account. Schedule rows are removed by the
// ON DELETE CASCADE foreign keys from public.semesters/courses/course_meetings/course_events.
//
// Security model:
// - The gateway rejects requests without a valid JWT (verify_jwt = true in config.toml).
// - This function re-validates the bearer token with Auth (`GET /auth/v1/user`), which also
//   rejects signed-out sessions, and deletes only the user ID returned by Auth. A client-supplied
//   user ID is never read.
// - The service-role key exists only in the Edge Function environment. It is never returned,
//   logged, or shipped in the app.
// - Tokens and request bodies are never logged.

const confirmationPhrase = "delete-my-account";

type AuthUser = { id?: unknown };

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function bearerToken(request: Request): string | null {
  const header = request.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+([A-Za-z0-9._~+/=-]+)$/.exec(header.trim());
  return match ? match[1] : null;
}

// Legacy API keys are JWTs and may also be sent as a bearer token. The newer sb_secret_ keys
// belong only in the apikey header.
function adminHeaders(key: string): Record<string, string> {
  const headers: Record<string, string> = { apikey: key, "Content-Type": "application/json" };
  if (key.split(".").length === 3) headers.Authorization = `Bearer ${key}`;
  return headers;
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

export async function handleDeleteAccount(
  request: Request,
  env: { url?: string; anonKey?: string; serviceRoleKey?: string },
  fetcher: typeof fetch = fetch,
): Promise<Response> {
  if (request.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }
  const { url, anonKey, serviceRoleKey } = env;
  if (!url || !anonKey || !serviceRoleKey) {
    return json(500, { error: "server_not_configured" });
  }

  const token = bearerToken(request);
  if (!token) {
    return json(401, { error: "missing_session" });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "confirmation_required" });
  }
  if (
    typeof body !== "object" || body === null ||
    (body as Record<string, unknown>).confirmation !== confirmationPhrase
  ) {
    return json(400, { error: "confirmation_required" });
  }

  const userResponse = await fetcher(`${url}/auth/v1/user`, {
    headers: { apikey: anonKey, Authorization: `Bearer ${token}` },
  });
  if (userResponse.status === 401 || userResponse.status === 403) {
    return json(401, { error: "invalid_session" });
  }
  if (!userResponse.ok) {
    return json(502, { error: "auth_unavailable" });
  }
  const user = (await userResponse.json()) as AuthUser;
  if (!isUUID(user.id)) {
    return json(401, { error: "invalid_session" });
  }

  const deleteResponse = await fetcher(`${url}/auth/v1/admin/users/${user.id}`, {
    method: "DELETE",
    headers: adminHeaders(serviceRoleKey),
    body: JSON.stringify({ should_soft_delete: false }),
  });
  if (deleteResponse.status === 404) {
    // Already deleted, for example by a retried request after a lost response.
    return json(200, { deleted: true });
  }
  if (!deleteResponse.ok) {
    return json(502, { error: "delete_failed" });
  }
  return json(200, { deleted: true });
}

Deno.serve((request) =>
  handleDeleteAccount(request, {
    url: Deno.env.get("SUPABASE_URL"),
    anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY"),
    serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY"),
  })
);
