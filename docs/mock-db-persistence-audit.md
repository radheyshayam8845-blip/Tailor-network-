# TailorNetwork MOCK_DB / PERSISTED Audit

Audited from `App.jsx` on `main` (blob SHA `6f8828ba23b818e116f8c7edb18fa002af31e510`). This is a code audit, not proof that browser storage or production data was tested.

## MOCK_DB top-level objects

| Object | Shape / observed fields | Main purpose / likely UI area | Persistence observation |
|---|---|---|---|
| `currentUser` | object: `id, name, mobile, role, tenantName, companyId` | Current signed-in UI identity / role and tenant context | Not included in `saveMockParts`; saved `user` is explicitly deleted when old app state is loaded. Real session should come from Supabase Auth, not this mock object. |
| `companies` | array: `id, name, companyCode, adminMobile` | Company registration / tenant setup | Saved in `TWE_MOCK_KEY` by `saveMockParts`; restored by `PERSISTED`. |
| `tailorAccounts` | array; registry of tailor accounts (sample list is empty) | Tailor account / tailor portal | Saved and restored through `TWE_MOCK_KEY`. |
| `idRegistry` | object: `tailor, company, retired` (restore also reads optional `scheme`) | Generates separate tailor/company IDs and tracks retired IDs | Saved and restored through `TWE_MOCK_KEY`. |
| `invitations` | array: invitation records include `id, companyId, tailorId, status` (status examples: pending/accepted/rejected) | Company–tailor invitation and connection flow | Saved and restored through `TWE_MOCK_KEY`. |
| `companyOwners` | array: `id, name, mobile, password, companyId, tenantName, role` | Company owner/admin demo account and role | Saved and restored through `TWE_MOCK_KEY`. **Security issue:** demo passwords are present in client-side mock data; never use this as real authentication or ship real credentials here. |
| `workers` | array: `companyId, id, name, staffId, mobile, line, lineId, joinDate, status, designation, skill` | Worker directory / worker profile and line assignment | Not in `saveMockParts` payload. `PERSISTED` does sync `d.workers` into `MOCK_DB.workers` if present in `TWE_STATE_KEY`. |
| `lines` | array: `companyId, id, lineCode, name, color, deptHead, workerCount, dailyTarget` | Department/production-line management and supervisor/line assignment | Not included in `saveMockParts`; likely carried in the broader app-state payload if that state serializer includes it. Verify the serializer before assuming durable persistence. |
| `operations` | array: `companyId, id, name, pieceRate, garmentType, line` | Operation management and piece-rate configuration | Saved and restored through `TWE_MOCK_KEY`. |
| `styles` | array: `companyId, id, styleNumber, styleName, totalQuantity, completedQty, status, lines, opNames, combos` | Style creation and style production progress | Not included in `saveMockParts`; verify broader state serialization before assuming persistence. |
| `workEntries` | array: `companyId, id, date, workerId, styleId, operationId, workerName, staffId, styleName, operation, pieces, pieceRate, amount, line` | Daily work/production entries and piece-rate amount calculation | Not included in `saveMockParts`; verify broader state serialization before assuming persistence. |
| `selfEntries` | array: `companyId, id, workerName, staffId, date, style, operation, pieces, status` | Worker-submitted production entries and approval status | Not included in `saveMockParts`; verify broader state serialization before assuming persistence. |

## Browser persistence behavior confirmed in code

- `saveMockParts()` writes a versioned JSON object (`v: 1`) under `TWE_MOCK_KEY`. It includes only `operations, companies, companyOwners, tailorAccounts, idRegistry, invitations`.
- `PERSISTED` reads `TWE_MOCK_KEY`, restores arrays for `operations, companies, companyOwners, tailorAccounts, invitations`, and restores `idRegistry`.
- `PERSISTED` separately reads `TWE_STATE_KEY`; invalid/missing versioned state returns `null`. It deletes `d.user` so old localStorage auth data cannot establish a session, and syncs `d.workers` into `MOCK_DB.workers` when present.
- Startup code deletes legacy keys `twe_state_v3`, `twe_state_v4`, `twe_state_v5`, `twe_state_v6`, and `twe_mock_v1`. This can intentionally discard older browser demo state.
- Storage helpers catch errors; a localStorage quota/privacy failure may cause persistence to fail. UI should surface save failure instead of silently claiming data was saved.
- Client-side localStorage is device/browser-specific and is not shared between factories, users, or devices. It is not a replacement for Supabase multi-tenant persistence.

## Recommended next steps

1. Treat `MOCK_DB` as demo/fallback data only. Move all real company, owner, worker, line, style, operation, invitation, and work-entry records to Supabase.
2. Remove mock passwords from shipped frontend code and use Supabase Auth plus server-verified role/company membership.
3. Define a single explicit persistence adapter and tests that prove each collection is loaded/saved, including storage failure behavior.
4. Add integration tests for tenant isolation (company A cannot read or mutate company B data).
5. Keep Inventory Management and Machine Management out of scope, as requested.

## Limits of this audit

The fields above are the fields in the first representative object / declared shape found in the source; they are not a guarantee that every record has identical optional fields. The screen mappings are functional interpretations from the data model, not a full UI click-through test. No database migration, production data, Auth user, or deployment was changed by this audit.
