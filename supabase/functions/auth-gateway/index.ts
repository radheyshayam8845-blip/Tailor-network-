import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": Deno.env.get("APP_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: corsHeaders });

const validMobile = (value: unknown): value is string =>
  typeof value === "string" && /^\d{10}$/.test(value);
const validPin = (value: unknown): value is string =>
  typeof value === "string" && /^\d{10}$/.test(value);

// Internal alias lets users log in with mobile + PIN without pretending an SMS OTP was sent.
// Real mobile ownership verification (OTP) should be added before enabling sensitive recovery flows.
const authAlias = (mobile: string) => `${mobile}@mobile.auth.tailornetwork.invalid`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return reply(500, { error: "Authentication service is not configured." });
  }

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { error: "Invalid request." }); }
  const action = body.action;
  const mobile = body.mobile;
  const pin = body.pin;
  if (!validMobile(mobile) || !validPin(pin)) {
    return reply(400, { error: "10-digit mobile number aur 10-digit PIN required hai." });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  if (action === "register-company") {
    const companyName = typeof body.companyName === "string" ? body.companyName.trim() : "";
    const name = typeof body.name === "string" ? body.name.trim() : "";
    const companyCode = typeof body.companyCode === "string" ? body.companyCode.trim().toUpperCase() : "";
    if (!companyName || !name || !companyCode || companyName.length > 120 || name.length > 120 || !/^[A-Z0-9-]{2,20}$/.test(companyCode)) {
      return reply(400, { error: "Company name, valid company code aur owner name required hai." });
    }

    // Fail closed: do not create an auth identity unless the server-side signup limiter succeeds.
    const { data: signupAllowed, error: signupLimitError } = await admin.rpc(
      "consume_signup_attempt",
      { p_mobile: mobile },
    );
    if (signupLimitError) {
      return reply(503, { error: "Signup security service unavailable. Please try again later." });
    }
    if (signupAllowed !== true) {
      return reply(429, { error: "Bahut zyada registration attempts. Ek ghante baad try karein." });
    }

    // Create auth identity only after rate limiting; never trust client-supplied role/company_id.
    const { data: authData, error: authError } = await admin.auth.admin.createUser({
      email: authAlias(mobile),
      password: pin,
      email_confirm: true,
      user_metadata: { display_name: name },
    });
    if (authError || !authData.user) {
      // Keep the response generic to avoid leaking whether a mobile number exists.
      return reply(400, { error: "Registration nahi ho saki. Mobile number pehle se registered ho sakta hai." });
    }

    const { data: company, error: companyError } = await admin
      .from("companies")
      .insert({ name: companyName, company_code: companyCode, admin_mobile: mobile })
      .select("id, global_id, name")
      .single();

    if (companyError || !company) {
      await admin.auth.admin.deleteUser(authData.user.id);
      return reply(400, { error: "Company create nahi hui. Company code check karke dobara try karein." });
    }

    const { error: profileError } = await admin.from("profiles").insert({
      id: authData.user.id, role: "admin", name, mobile, company_id: company.id,
    });
    if (profileError) {
      await admin.from("companies").delete().eq("id", company.id);
      await admin.auth.admin.deleteUser(authData.user.id);
      return reply(500, { error: "Registration complete nahi hui. Dobara try karein." });
    }
    return reply(201, { ok: true, message: "Account ban gaya. Ab login karein." });
  }

  if (action === "login") {
    // Atomic server-side limiter. Only the Edge Function/service role can call this RPC.
    const { data: allowed, error: limitError } = await admin.rpc("consume_login_attempt", { p_mobile: mobile });
    if (limitError) return reply(503, { error: "Login security service unavailable." });
    if (allowed !== true) return reply(429, { error: "Bahut zyada login attempts. Kuch der baad try karein." });

    const publicClient = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data, error } = await publicClient.auth.signInWithPassword({
      email: authAlias(mobile),
      password: pin,
    });
    if (error || !data.session || !data.user) {
      return reply(401, { error: "Mobile number ya PIN galat hai." });
    }
    await admin.rpc("clear_login_attempts", { p_mobile: mobile });
    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("id, role, name, mobile, company_id, global_id")
      .eq("id", data.user.id)
      .single();
    if (profileError || !profile) {
      await admin.auth.admin.signOut(data.session.access_token);
      return reply(403, { error: "Account profile available nahi hai." });
    }
    return reply(200, {
      session: data.session,
      profile,
    });
  }

  return reply(400, { error: "Unsupported action." });
});
