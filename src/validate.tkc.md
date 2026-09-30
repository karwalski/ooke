---
source_file: "validate.tk"
source_hash: "fb66ed9e5b6a12f0d2ad0063854e88a7257cf5245c8bf124d43e5af9b73406d7"
compiler_version: "3.0.0"
generated_at: "2026-10-01T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.validate`

Content-model validation for the ooke CMS. It loads a content type's field
schema from a per-type TOML model file, validates a content document's metadata
against that schema (presence of required fields, and `int`/`bool` type
checks), and provides helpers to merge and log the resulting error/warning
sets.

**Imports:**
- `std.file` (alias `file`) — test for and read the model TOML file.
- `std.str` (alias `str`) — string concatenation, splitting, trimming, length,
  and integer parsing (`str.toint`) for type checks.
- `std.path` (alias `path`) — join the models directory with the type filename.
- `std.toml` (alias `toml`) — parse the model file and read typed
  keys/sections.
- `std.log` (alias `log`) — emit validation errors/warnings to the log.

## Types

### `$fielddef`

One field declaration within a content model.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `$str` | The field name. |
| `fieldtype` | `$str` | The declared type, e.g. `"str"`, `"int"`, `"bool"`. |
| `required` | `bool` | Whether the field must be present and non-empty. |

### `$modeldef`

A complete content-model definition.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `$str` | The model name (defaults to the type name if absent). |
| `fields` | `@$fielddef` | Array of field declarations. |

### `$valerror`

A single validation error or warning.

| Field | Type | Description |
|-------|------|-------------|
| `filepath` | `$str` | The content file the error pertains to. |
| `field` | `$str` | The offending field name. |
| `msg` | `$str` | Human-readable description. |

### `$valresult`

The outcome of validating one document (or of merging several).

| Field | Type | Description |
|-------|------|-------------|
| `errors` | `@$valerror` | Hard validation errors. |
| `warnings` | `@$valerror` | Non-fatal warnings. |

### `$validateerr`

Error type for `validateloadmodel`.

| Field | Type | Description |
|-------|------|-------------|
| `msg` | `$str` | Failure description (no model file, read or TOML parse failure, missing `[fields]`/`list`). |

## Functions

### `validateloadmodel(modelspath: $str; typename: $str): $modeldef!$validateerr`

**Purpose:** Load a content model's field schema from
`<modelspath>/<typename>.toml`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `modelspath` | `$str` | Directory containing model TOML files. |
| `typename` | `$str` | The content type / model file stem. |

**Returns:** `$modeldef!$validateerr` — the parsed model, or `$validateerr` if
the model file does not exist, cannot be read or parsed, or has no
`[fields]` section with a `list` key.

**Logic:**

1. Build `tomlpath` by joining `modelspath` with `str.concat(typename, ".toml")`
   via `path.join`.
2. If `!file.exists(tomlpath)`, return
   `$validateerr{msg:"no model file: <tomlpath>"}` — checked explicitly
   rather than relying on `file.read`'s error under `!` (story 134.8: a
   failed stdlib call under `!` could yield a null value instead of an error).
   Read the file with `file.read`, propagating failure as `$validateerr` via
   `!$validateerr`.
3. Parse the source with `toml.load`, propagating failure as `$validateerr`.
4. Read the top-level `name` key with `toml.str(tab, "name")`, matched
   `{$ok:v v; $err:e typename}` — absent name falls back to `typename`.
5. Read the `fields` section with `toml.section(tab, "fields")`, propagating
   failure as `$validateerr`.
6. Read the `list` key (comma-separated field names) from the `fields` section
   with `toml.str`, propagating failure as `$validateerr`.
7. Split `list` on `","` into `parts`.
8. Initialise a mutable array `fields` of `$fielddef` (`mut.@($fielddef)`).
9. Loop `i` from `0` to `parts.len` (exclusive), incrementing by `1`:
   a. Trim `parts.get(i)` into `fname`.
   b. If `str.len(fname) > 0`:
      - Look up the per-field subsection `toml.section(fieldsec, fname)`,
        matched `{$ok:v v; $err:e fieldsec}` (a missing subsection falls back to
        the enclosing `fields` section).
      - Read `type` from that subsection with `toml.str`, matched
        `{$ok:v v; $err:e "str"}` (default `"str"`).
      - Read `required` with `toml.bool`, matched `{$ok:v v; $err:e false}`
        (default `false`).
      - Append `$fielddef{name:fname; fieldtype:ftype; required:freq}` to
        `fields`.
      - Otherwise (empty name) do nothing.
10. Return `$modeldef{name:modelname; fields:fields}`.

**Error handling:** A missing model file returns `$validateerr` explicitly;
`file.read`, `toml.load`, `toml.section(fields)`, and `toml.str(list)` raise
`$validateerr` (via `!`). The name and per-field
lookups are total (they fall back to defaults).

### `validatecontent(model: $modeldef; meta: @($str:$str); filepath: $str): $valresult`

**Purpose:** Validate a document's metadata map against a model's field schema.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `model` | `$modeldef` | The schema to validate against. |
| `meta` | `@($str:$str)` | The document's metadata (string-to-string map). |
| `filepath` | `$str` | The document path, recorded in each error. |

**Returns:** `$valresult` — collected errors and warnings (warnings is always
empty here).

**Logic:**

1. Initialise a mutable empty `errors` array and an immutable empty
   `warnings` array of `$valerror`.
2. Loop `i` from `0` to `model.fields.len` (exclusive), incrementing by `1`:
   a. Bind `fd = model.fields.get(i)`.
   b. Look up the field value: `val = mt meta.get(fd.name) {$ok:v v; $err:e ""}`
      — absent key yields `""`.
   c. If `str.len(val) = 0` (empty/absent):
      - If `fd.required`, append a `$valerror` with message
        `"required field missing: " ++ fd.name`.
      - Otherwise do nothing.
   d. Else (non-empty value):
      - If `fd.fieldtype = "int"`: attempt `str.toint(val)`, matched
        `{$ok:v true; $err:e false}` into `isnum`. If `!isnum`, append a
        `$valerror` with message `"field '" ++ fd.name ++ "' expected int"`.
      - Else if `fd.fieldtype = "bool"`: compute `isbool = val="true" ||
        val="false"`. If `!isbool`, append a `$valerror` with message
        `"field '" ++ fd.name ++ "' expected bool"`. Other field types are not
        checked.
3. Return `$valresult{errors:errors; warnings:warnings}`.

**Error handling:** Total — never raises. All problems are recorded as
`$valerror` entries in the returned result.

### `validatelogresult(result: $valresult): i64`

**Purpose:** Emit every error and warning in `result` to the log.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `result` | `$valresult` | The result whose entries are logged. |

**Returns:** `i64` — always `0`.

**Logic:**

1. Loop `i` from `0` to `result.errors.len` (exclusive): bind `e =
   result.errors.get(i)` and call `log.info` with
   `"[validate] ERROR " ++ e.filepath ++ ": " ++ e.msg` and an empty context
   `@()`.
2. Loop `j` from `0` to `result.warnings.len` (exclusive): bind `w =
   result.warnings.get(j)` and call `log.info` with
   `"[validate] WARN " ++ w.filepath ++ ": " ++ w.msg` and an empty context
   `@()`.
3. Return `0`.

**Error handling:** None. Both errors and warnings are logged at info level.

### `validatemerge(a: $valresult; b: $valresult): $valresult`

**Purpose:** Combine two validation results into one.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `a` | `$valresult` | First result (its entries come first). |
| `b` | `$valresult` | Second result (its entries are appended). |

**Returns:** `$valresult` — the concatenation of both results' errors and
warnings.

**Logic:**

1. Initialise mutable `errs = mut.a.errors`. Loop `i` from `0` to
   `b.errors.len` (exclusive), appending `b.errors.get(i)` to `errs`.
2. Initialise mutable `warns = mut.a.warnings`. Loop `j` from `0` to
   `b.warnings.len` (exclusive), appending `b.warnings.get(j)` to `warns`.
3. Return `$valresult{errors:errs; warnings:warns}`.

**Error handling:** None.

### `validateempty(): $valresult`

**Purpose:** Construct an empty validation result.

**Parameters:** None.

**Returns:** `$valresult` with empty `errors` and `warnings` arrays.

**Logic:** Return `$valresult{errors:@($valerror); warnings:@($valerror)}`.

**Error handling:** None.

## Control Flow

There is no single entry point; the module is a library consumed by the build
and serve pipelines. The typical flow is: `validateloadmodel` reads a model
schema once per content type; `validatecontent` is then called per document to
produce a `$valresult`; multiple results are combined with `validatemerge`
(seeded from `validateempty`); finally `validatelogresult` reports the
accumulated errors/warnings.

`validateloadmodel` is the only fallible function (a missing model file, and
file/TOML failures via `!`).
The remaining functions are total. The only loops are: the field-parsing loop
in `validateloadmodel`, the per-field validation loop in `validatecontent`, and
the two append loops each in `validatelogresult` and `validatemerge`.

## Notes

- **Canonical result form.** Match arms use `$ok`/`$err`.
- **`i64` return on `validatelogresult`.** It returned `void` in an earlier
  revision; it now returns `0` (story 134.2, which made every .tk file checkable
  under current tkc), and `src/ooke.validate.tki` records `i64`.
- **Missing model file is checked first** (story 134.8), so `ooke build`
  fails loudly on it instead of carrying a null value forward.
- **Type checks are minimal by design.** Only `int` and `bool` field types are
  format-checked; `str` and any other declared type are accepted as long as
  required fields are present. `validatecontent` never produces warnings; the
  `warnings` slot exists for `validatemerge` symmetry.
- **`meta.get` is matched as a result.** `validatecontent` reads
  `mt meta.get(fd.name) {$ok:v v;$err:e ""}`, whereas `ooke.store` treats
  `map.get` as returning the raw value. Recorded, not changed here.
