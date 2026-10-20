import { createClient } from "@supabase/supabase-js";

// Only the publishable/anon key belongs in the browser. Never use service-role keys here.
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const supabase = supabaseUrl && supabaseAnonKey
  ? createClient(supabaseUrl, supabaseAnonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    })
  : null;

export function requireSupabase() {
  if (!supabase) {
    throw new Error("Supabase config missing. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY.");
  }
  return supabase;
}

export const isValidMobile = (value) => /^\d{10}$/.test(String(value ?? ""));
export const isValidPin = (value) => /^\d{10}$/.test(String(value ?? ""));
