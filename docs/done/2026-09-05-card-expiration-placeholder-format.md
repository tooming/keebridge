# Card expiration autofill assumed "MM/YYYY" for any placeholder mentioning "yyyy"

`content.js`'s `formatValue()` formats the combined `.expiration` card field to match the
target input's own placeholder hint. Its `"yyyy"` branch only checked whether the
substring `"yyyy"` appeared anywhere in the placeholder, then unconditionally returned a
hardcoded month-first, slash-separated string:

```js
if (placeholder.includes("yyyy")) return `${month}/${year}`;
```

This ignores what the placeholder actually says about token order and separator. A field
with placeholder `"YYYY-MM"` or `"YYYY/MM"` (year-first) or `"MM-YYYY"` (dash-separated)
would get `"04/2027"` written into it regardless — for a `"YYYY-MM"` field that's the wrong
order **and** the wrong separator, not just a stylistic mismatch; a page that
validates/parses the field against its own stated format would reject or misinterpret it.
Real and reachable: any card-expiration `<input>` without a `maxlength` attribute (common —
most sites don't set one on free-text expiry fields) and a placeholder using either a
year-first or dash-separated convention hits exactly this path.

## Fix

The `"yyyy"` branch now derives both the token order and the separator from the placeholder
itself — `yyyy`'s index relative to `mm`'s decides year-first vs. month-first, and whether
the placeholder contains `"-"` decides the separator — instead of assuming the one
`"MM/YYYY"` layout the old code produced correctly and silently getting every other layout
wrong.

Found via a second, independent adversarial review pass this run (after #60–#63, all
already merged and unrelated to this file's formatting logic — the earlier `content.js` fix
today gated frame trust, a completely separate concern from this value-formatting bug).

**Verification**: this repo's CI has no JS lint/test step at all (confirmed in
`docs/backlog/2026-09-03-action-needed-backlog-blocked.md`), so unlike every Swift fix this
run, this one couldn't be validated via `make ci`. Went further than the prior JS-only fix's
precedent (`docs/done/2026-09-04-card-picker-cross-origin-iframe-block.md`, verified by
reading alone): extracted `formatValue` into a standalone Node.js harness (this executor's
environment has `node`, confirmed via `node -c` for a syntax check first) with minimal
`HTMLInputElement`/`HTMLSelectElement` stubs, and ran it against 10 concrete cases —
`MM/YYYY`, `YYYY-MM`, `MM-YYYY`, `YYYY/MM`, `MM/YY`, no placeholder, `maxLength` 4/6, native
`type="month"`, and a year-first *source* value against a `YYYY-MM` placeholder — all pass,
including every previously-correct case (regression-checked, not just the new ones). Still
not wired into CI (no test file added — this repo has no JS test infrastructure to add one
to), so **still needs a human eyeball** in real Safari against a real page using one of
these less-common placeholder conventions, same headless-verification limit every
`content.js` change in this ROADMAP carries.

## PR

See the PR that accompanies this file.
