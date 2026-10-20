export const isValidMobile = (value: unknown): value is string =>
  typeof value === "string" && /^[0-9]{10}$/.test(value);

export const isValidPin = (value: unknown): value is string =>
  typeof value === "string" && /^[0-9]{10}$/.test(value);

export const normalizeCompanyCode = (value: unknown): string =>
  typeof value === "string" ? value.trim().toUpperCase() : "";

export const isValidCompanyCode = (value: unknown): boolean =>
  /^[A-Z0-9-]{2,20}$/.test(normalizeCompanyCode(value));

/**
 * Matches the gateway's intended CORS policy:
 * - fail closed when APP_ORIGIN is missing;
 * - allow requests from the configured origin;
 * - reject a supplied, mismatched Origin;
 * - permit requests without an Origin header (e.g. non-browser clients), which
 *   must still be protected by authentication, rate limiting, and server checks.
 */
export const isAllowedOrigin = (
  requestOrigin: string | null,
  appOrigin: string | undefined,
): boolean => Boolean(appOrigin) && (requestOrigin === null || requestOrigin === appOrigin);

export const toAuthAlias = (mobile: string): string =>
  `${mobile}@mobile.auth.tailornetwork.invalid`;
