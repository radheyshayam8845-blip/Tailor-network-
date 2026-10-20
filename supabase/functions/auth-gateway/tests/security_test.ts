import {
  isAllowedOrigin,
  isValidCompanyCode,
  isValidMobile,
  isValidPin,
  normalizeCompanyCode,
  toAuthAlias,
} from "../security.ts";

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${String(expected)}, got ${String(actual)}`);
  }
}

Deno.test("mobile validation accepts exactly ten ASCII digits", () => {
  assertEquals(isValidMobile("9876543210"), true, "valid mobile");
  assertEquals(isValidMobile("0123456789"), true, "leading zero is preserved");
  assertEquals(isValidMobile("123456789"), false, "nine digits rejected");
  assertEquals(isValidMobile("12345678901"), false, "eleven digits rejected");
  assertEquals(isValidMobile("12345abc90"), false, "letters rejected");
  assertEquals(isValidMobile("１２３４５６７８９０"), false, "non-ASCII digits rejected");
  assertEquals(isValidMobile(null), false, "null rejected");
});

Deno.test("PIN validation accepts exactly ten ASCII digits", () => {
  assertEquals(isValidPin("0012345678"), true, "leading zero is preserved");
  assertEquals(isValidPin("1234"), false, "short PIN rejected");
  assertEquals(isValidPin("12345678901"), false, "long PIN rejected");
  assertEquals(isValidPin("1234567x90"), false, "non-digit PIN rejected");
  assertEquals(isValidPin(undefined), false, "undefined rejected");
});

Deno.test("company code normalization and validation", () => {
  assertEquals(normalizeCompanyCode("  ab-123  "), "AB-123", "trim and uppercase");
  assertEquals(isValidCompanyCode("ab-123"), true, "case-insensitive input accepted");
  assertEquals(isValidCompanyCode("A1"), true, "minimum length accepted");
  assertEquals(isValidCompanyCode("A".repeat(20)), true, "maximum length accepted");
  assertEquals(isValidCompanyCode("A"), false, "too short rejected");
  assertEquals(isValidCompanyCode("A".repeat(21)), false, "too long rejected");
  assertEquals(isValidCompanyCode("AB 12"), false, "spaces rejected");
  assertEquals(isValidCompanyCode("AB_12"), false, "underscore rejected");
  assertEquals(isValidCompanyCode(null), false, "non-string rejected");
});

Deno.test("origin policy fails closed when APP_ORIGIN is missing", () => {
  assertEquals(isAllowedOrigin("https://tailor-network.vercel.app", undefined), false, "missing configuration denied");
  assertEquals(isAllowedOrigin(null, undefined), false, "missing configuration denies originless request");
});

Deno.test("origin policy allows only the configured browser origin", () => {
  const configured = "https://tailor-network.vercel.app";
  assertEquals(isAllowedOrigin(configured, configured), true, "matching origin accepted");
  assertEquals(isAllowedOrigin("https://evil.example", configured), false, "foreign origin rejected");
  assertEquals(isAllowedOrigin("https://tailor-network.vercel.app.evil.example", configured), false, "suffix spoof rejected");
  assertEquals(isAllowedOrigin("http://tailor-network.vercel.app", configured), false, "scheme mismatch rejected");
  assertEquals(isAllowedOrigin(null, configured), true, "originless non-browser request retains existing policy");
});

Deno.test("mobile auth alias uses the expected internal domain", () => {
  assertEquals(toAuthAlias("9876543210"), "9876543210@mobile.auth.tailornetwork.invalid", "internal alias");
});
