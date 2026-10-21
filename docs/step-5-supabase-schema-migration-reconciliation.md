# Step 5 — Supabase schema and migration reconciliation (read-only)

**Target checked:** Supabase project `hvsgcrnvlwsjydbyhsmx` (region `ap-southeast-1`).  
**Safety boundary:** Read-only metadata/catalog queries only. No SQL DDL/DML, migration repair, migration application, secrets, Auth users, or deployment changes were performed.

## Executive result

**Reconciliation is not yet clean. Do not run `supabase db push` or migration repair.** The live schema is understandable at a high level, but Git's migration directory and remote migration history disagree on timestamps.

## Live database snapshot

- 11 application tables in `public`; all 11 have RLS enabled.
- The table listing reports zero rows in each table.
- Live tables: `companies`, `profiles`, `invitations`, `lines`, `workers`, `operations`, `styles`, `dept_allocations`, `work_entries`, `subscription_invoices`, `auth_login_attempts`.
- Live helper functions include `private.my_company()`, `private.is_my_worker(uuid)`, `private.set_work_entry_rate()`, `private.assign_profile_global_id()`, `public.consume_login_attempt(text)`, and `public.clear_login_attempts(text)`.
- Tenant-scoped foreign keys exist for workers, styles, operations and work entries; operation rate enforcement is handled by a trigger. `profiles.role` currently allows only `admin` and `tailor`.
- `companies.company_code` has no unique constraint in the live catalog. Do not add one until intended uniqueness rules are confirmed.

## Migration history mismatch

Remote `supabase_migrations.schema_migrations` reports:

| Remote version | Remote name |
| --- | --- |
| `20261020141622` | `initial_secure_tailornetwork_schema` |
| `20261020144123` | `mobile_pin_login_rate_limit` |
| `20261020144259` | `fix_login_rate_limit_mobile_validation` |

The repository's `main` branch currently contains:

| Repository version | File |
| --- | --- |
| `20261020141622` | `20261020141622_initial_secure_tailornetwork_schema.sql` |
| `20261020170000` | `20261020170000_mobile_pin_login_rate_limit.sql` |

Consequences:
1. The remote has two applied versions (`144123`, `144259`) that do not have matching migration files in the inspected repository directory.
2. The repository has version `170000` which is not in the remote history.
3. The remote schema contains `auth_login_attempts` and both login-throttling functions, so blindly applying the repository's `170000` migration may be redundant or conflict with existing objects.
4. Do not rename timestamps or use `migration repair` just to make the lists look aligned. Migration history tracks timestamps, while schema state must be verified independently.

## Product scope / missing planned modules

The existing schema does not yet include:
- department-wise supervisor assignments and per-supervisor permissions;
- worker attendance history (present/absent/half-day/leave);
- job posts and job applications.

These are known schema gaps, not migration-drift fixes. Inventory Management and Machine Management remain excluded. Operation rates remain inside Operation Management.

## Safe next steps

1. Retrieve the exact SQL for remote versions `20261020144123` and `20261020144259` from the original source that applied them, or recover them from a trusted repository/backup. Do not reconstruct them from names alone.
2. Compare those SQL files with `20261020170000_mobile_pin_login_rate_limit.sql` and live function definitions, grants, RLS, and constraints.
3. Establish a disposable local database or isolated Supabase development branch and replay a corrected, ordered migration set there. Do not reset the current remote project.
4. Generate and review a schema snapshot/diff from the selected project, including policies, triggers, functions, grants, and constraints. A table-only comparison is insufficient.
5. Only after the history and schema match, prepare a separate forward-only migration for the planned supervisor/attendance/job modules and test it off the live project.
6. Any later remote change requires separate explicit approval and dry-run review. This report authorizes no database changes.

## Verification sources

- Live project catalog and migration list queried read-only through Supabase tools on 2026-10-21.
- Repository source files: `schema.sql`, `supabase/migrations/20261020141622_initial_secure_tailornetwork_schema.sql`, and `supabase/migrations/20261020170000_mobile_pin_login_rate_limit.sql`.
- Supabase migration guidance: https://supabase.com/docs/guides/deployment/database-migrations
