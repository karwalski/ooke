---
source_file: "apihealth.tk"
source_hash: "4c5e51fbba037eeee7c4c1caa9fd657bcab92ca7cb88ebef45c6884df4d1e033"
compiler_version: "0.3.9"
generated_at: "2026-06-15T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.apihealth`

A built-in API health-check endpoint for an ooke site. It exposes a fixed,
machine-readable status document and an HTTP `GET` handler that serves that
document as a `200 OK` JSON response. It is wired into the route table by the
generated `ooke.handlers` module at `/api/health`.

**Imports:**
- `std.http` (alias `http`) — build the JSON HTTP response (`http.resjson`).

## Functions

### `apigetjson(): $str`

**Purpose:** Produce the canonical health-check JSON document as a string.

**Parameters:** None.

**Returns:** `$str` — the literal JSON string
`{"status":"ok","service":"ooke"}` (the inner double quotes are escaped in the
source with `\"`).

**Logic:**

1. Return the string literal `"{\"status\":\"ok\",\"service\":\"ooke\"}"`
   directly. There is no computation, no input, and no branching — the body is
   a constant.

**Error handling:** None. The function is total.

### `get(req: i64): i64`

**Purpose:** HTTP `GET` handler for the health endpoint. Returns a `200 OK`
JSON response whose body is the health document.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `req` | `i64` | Opaque request handle from the HTTP runtime. It is accepted to satisfy the handler signature but is not inspected — the response is constant. |

**Returns:** `i64` — an opaque response handle produced by
`http.resjson(200; apigetjson())`. The handle is non-zero on success.

**Logic:**

1. Call `apigetjson()` to obtain the health JSON string.
2. Call `http.resjson(200; <that string>)` to construct a JSON HTTP response
   with status `200` and the JSON `Content-Type` header set by the runtime.
3. Return the resulting response handle.

**Error handling:** None. The handler does not fail; `http.resjson` always
returns a response handle.

## Control Flow

`get` is the registered route handler (mounted at `/api/health` by
`ooke.handlers`). When invoked it ignores its request argument, calls
`apigetjson` to obtain the constant body, wraps it in a `200` JSON response via
`http.resjson`, and returns the response handle. `apigetjson` is the single data
source and is also callable standalone (e.g. from tests). No loops, no
recursion, no mutable state, no error paths.

## Notes

- **Behaviourally faithful to the reference.** The module body, signatures, and
  the exact JSON literal are unchanged from the parity reference, because loke
  and the generated `ooke.handlers` registration depend on the observable
  behaviour and the `apigetjson`/`get` signatures.
- **No match arms.** This module has no fallible calls or sum-type matches, so
  there are no `$ok`/`$err` arms to canonicalise; the source is already
  spec-canonical (lowercase, `$`-sigil types, `;`-separated args, `<` return).
- **`http.resjson` body argument.** The `.tki` types `http.resjson` as
  `(i64, i64): i64`; the runtime treats the second argument as a string body
  pointer, so passing the `$str` from `apigetjson` is the intended call form.
