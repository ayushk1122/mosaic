// Password sign-in by @username. The account's email or phone is looked up here with the
// service role and never returned, so usernames cannot be mapped to contact details.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseURL = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

const admin = createClient(supabaseURL, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const usernamePattern = /^[a-z0-9_]{3,20}$/;

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Unknown usernames, wrong passwords, and unconfirmed accounts all look the same.
function rejected(): Response {
  return json({ error: "invalid_credentials", error_description: "Invalid login credentials" }, 400);
}

async function credentialsFor(username: string): Promise<Record<string, string> | null> {
  const { data: profile } = await admin
    .from("profiles")
    .select("id")
    .eq("username", username)
    .maybeSingle();
  if (!profile) return null;
  const { data } = await admin.auth.admin.getUserById(profile.id);
  const user = data?.user;
  if (user?.email) return { email: user.email };
  if (user?.phone) return { phone: user.phone };
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  let payload: { username?: unknown; password?: unknown };
  try {
    payload = await req.json();
  } catch {
    return rejected();
  }

  const username = String(payload.username ?? "").trim().replace(/^@+/, "").toLowerCase();
  const password = String(payload.password ?? "");
  if (!usernamePattern.test(username) || password.length === 0 || password.length > 72) {
    return rejected();
  }

  const credentials = await credentialsFor(username);
  // Unknown usernames still make one password check, so response time doesn't reveal them.
  const attempt = credentials ?? { email: `${crypto.randomUUID()}@unknown.invalid` };

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    apikey: anonKey,
  };
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) headers["X-Forwarded-For"] = forwarded;

  const response = await fetch(`${supabaseURL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers,
    body: JSON.stringify({ ...attempt, password }),
  });

  if (response.status === 429) {
    return json({ error: "rate_limited", error_description: "Too many attempts" }, 429);
  }
  if (!credentials || !response.ok) {
    return rejected();
  }
  return new Response(await response.text(), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
