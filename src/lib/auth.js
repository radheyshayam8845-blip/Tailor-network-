import { requireSupabase, isValidMobile, isValidPin } from "./supabase.js";

async function callAuthGateway(action, payload) {
  const client = requireSupabase();
  const { data, error } = await client.functions.invoke("auth-gateway", {
    body: { action, ...payload },
  });
  if (error) throw new Error(error.message || "Authentication service se connect nahi ho paya.");
  if (!data) throw new Error("Authentication service ne response nahi diya.");
  if (data.error) throw new Error(data.error);
  if (data.session) {
    const { error: sessionError } = await client.auth.setSession({
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
    });
    if (sessionError) throw sessionError;
  }
  return data;
}

export async function registerCompanyAccount({ mobile, pin, companyName, companyCode, name }) {
  if (!isValidMobile(mobile)) throw new Error("10-digit mobile number daalein.");
  if (!isValidPin(pin)) throw new Error("PIN exactly 10 digits ka hona chahiye.");
  return callAuthGateway("register-company", { mobile, pin, companyName, companyCode, name });
}

export async function loginWithMobilePin({ mobile, pin }) {
  if (!isValidMobile(mobile)) throw new Error("10-digit mobile number daalein.");
  if (!isValidPin(pin)) throw new Error("PIN exactly 10 digits ka hona chahiye.");
  const result = await callAuthGateway("login", { mobile, pin });
  return result.profile;
}

export async function signOut() {
  const client = requireSupabase();
  const { error } = await client.auth.signOut();
  if (error) throw error;
}

export async function getCurrentAuthUser() {
  const client = requireSupabase();
  const { data, error } = await client.auth.getUser();
  if (error) throw error;
  return data.user;
}
