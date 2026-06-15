---
source_file: "_handlers.tk"
source_hash: "33a5ab84d5a36be067ef285630b270f61a6db0188b2bf0dc81d6074b7bae27d0"
compiler_version: "0.3.9"
generated_at: "2026-06-16T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.handlers`

The central route table for ooke's dynamic API surface. It binds API endpoints
to their handler functions in the global HTTP router and reports back the list
of registered paths. Today it registers exactly one route — `GET /api/health` —
delegating to `ooke.apihealth`. New API endpoints are added here by writing a
thin `h<name>` adapter and a matching `http.<verb>` registration line.

**Imports:**
- `std.http` (alias `http`) — `http.get` registers a path → handler-reference
  route on the process-global HTTP router.
- `ooke.apihealth` (alias `apihealth`) — the health-check endpoint handler that
  `hapihealthget` delegates to.

## Types

None. This module declares no record types; it deals only in `i64` request/
response handles and an `@$str` of route paths.

## Functions

### `hapihealthget(req: i64): i64`

**Purpose:** Handler adapter for `GET /api/health`. Forwards the incoming
request handle to `apihealth.get` and returns its response handle unchanged.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `req` | `i64` | Opaque request handle supplied by the HTTP router at dispatch time. |

**Returns:** `i64` — the opaque response handle produced by `apihealth.get`.

**Logic:** A single tail expression `<apihealth.get(req)` — pure delegation, no
local state. Exists so `registerall` has a concrete top-level function whose
address (`&hapihealthget`) can be passed to `http.get` as the route's handler.

### `registerall(): @$str`

**Purpose:** Register every dynamic API route on the global HTTP router and
return the list of paths that were registered (loke-parity contract: the
returned `@$str` is the authoritative inventory of bound routes).

**Parameters:** None.

**Returns:** `@$str` — the registered route paths, in registration order.
Currently exactly `["/api/health"]`.

**Logic:**

1. Start an empty mutable `@$str` accumulator (`mut.@($str)`).
2. Register `GET /api/health` against `&hapihealthget` via `http.get`. This is a
   side effect on the process-global router; the call's result is discarded
   (statement form `( … )`).
3. Append the just-registered path string to the accumulator.
4. Return the accumulator.

Each route is two coupled lines — one `http.<verb>` registration and one
matching `paths.append`. Keeping them adjacent keeps the registry and the
returned inventory in lock-step as routes are added.

## Constants

None.

## Control Flow

Straight-line. `hapihealthget` is a one-expression delegate. `registerall` is a
linear sequence (init accumulator → register → record → return) with no loops,
no recursion, no branching, and no error channel — both functions are total.

## Notes

- **No fallible result type here.** Neither function returns `T!E`, so there are
  no match arms; the canonical `$ok`/`$err` variant convention (toke-spec-prompt:
  "Variants are `$lowercase`") does not arise in this module. Nothing to migrate
  from the legacy `Ok`/`Err` form.
- **Both imports are load-bearing.** `http` is used for route registration and
  `apihealth` for delegation; there are no unused imports to drop.
- **`registerall` is integration-shaped; `hapihealthget` and the return value
  are unit-testable.** Registration mutates the process-global router, so the
  *binding* itself (does a request to `/api/health` dispatch correctly?) is an
  e2e concern. What the unit test (`test/handlers/test_handlers.tk`) covers is
  the observable, deterministic surface: `hapihealthget(0)` returns a non-zero
  response handle (delegation works), and `registerall()` returns exactly the
  `["/api/health"]` inventory (length 1, element `/api/health`).
- **Behaviour-faithful to the reference.** Signatures (`hapihealthget(i64):i64`,
  `registerall():@$str`) and observable behaviour match the parity reference
  `toke-ooke/src/_handlers.tk` exactly — required for loke to run on this ooke.
