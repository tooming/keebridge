# content.js always wrote a 4-digit year into a stand-alone year field

## The bug

`content.js`'s `formatValue(type, value, element)` handles six payment-card
field types. For `type === "expirationYear"`:

```js
if (type === "expirationYear") {
  const digits = value.replace(/\D/g, "");
  if (element instanceof HTMLSelectElement) {
    return [...element.options].find((option) => {
      const optionDigits = option.value.replace(/\D/g, "");
      return optionDigits && optionDigits.slice(-2) === digits.slice(-2);
    })?.value || digits;
  }
  const optionsUseTwoDigits = element instanceof HTMLSelectElement &&
    [...element.options].some((option) => /^\d{2}$/.test(option.value));
  return optionsUseTwoDigits ? digits.slice(-2) : (digits.length === 2 ? `20${digits}` : digits);
}
```

The `if (element instanceof HTMLSelectElement)` branch returns
unconditionally — every `<select>` year field is fully handled and exits
there. So by the time execution reaches `const optionsUseTwoDigits = element
instanceof HTMLSelectElement && ...`, `element` is guaranteed **not** to be a
`HTMLSelectElement` (control flow only reaches this line when the first
check's condition was false). `optionsUseTwoDigits` is therefore always
`false` — dead code that can never take its intended branch.

The practical effect: every plain `<input>` year field always fell through to
`digits.length === 2 ? "20"+digits : digits"` — which always *produces* a
4-digit year (`"2027"`), never a 2-digit one, no matter what the target field
actually expects. Unlike the sibling `expiration` (combined month+year) case a
few lines below — which already disambiguates a target field's expected
format via `element.maxLength`/placeholder tokens (`"yyyy"` vs not) — the
stand-alone `expirationYear` case had no such check at all for a plain input.

This is real and reachable: separate month/year text inputs where the year
field expects exactly 2 digits (`maxLength="2"`, placeholder `"YY"`) are a
common card-form pattern, distinct from the `<select>` case (already handled
correctly) and from a 4-digit year text input (already correct by
coincidence). Writing `"2027"` into a field expecting `"27"` is a wrong value
the site's own validation may reject outright — `maxLength` is not enforced
by the DOM for a programmatic `.value =` assignment, so the overflow isn't
even visually truncated for the user to notice before submitting.

Found via a full, fresh read of `content.js` this cycle — the file had never
been cited by filename anywhere in this ROADMAP before, despite carrying the
card-fill autofill logic since its original implementation and one later
security fix (the cross-origin-iframe gate).

## The fix

Replaced the dead `optionsUseTwoDigits` check with a real heuristic for a
plain-input year field, reusing the same two signals (`maxLength`,
placeholder token) the combined `expiration` case already uses just below it:

```js
const placeholder = (element.getAttribute("placeholder") || "").toLowerCase();
const wantsTwoDigits = element.maxLength === 2 || (/\byy\b/.test(placeholder) && !placeholder.includes("yyyy"));
return wantsTwoDigits ? digits.slice(-2) : (digits.length === 2 ? `20${digits}` : digits);
```

`maxLength === 2` is the strongest, most direct signal (mirroring the
combined case's own `element.maxLength === 4` check); the placeholder check
is a fallback for a field with no `maxlength` attribute at all, guarding
`"yy"` against also matching inside `"yyyy"` the same way the combined case's
`yyyyIndex`/`mmIndex` logic already does.

The `HTMLSelectElement` branch above is completely untouched — this only
changes behavior for a plain-input stand-alone year field, which previously
had no 2-vs-4-digit detection whatsoever.

## Verification

No CI JS lint/test step exists for this repo (only the Swift targets —
`KeeBridgeCore`, the app, both extensions, `VaultProbe` — are built/tested by
`make ci`), same constraint the cross-origin-iframe card fix
(`docs/done/2026-09-04-card-picker-cross-origin-iframe-block.md`) already
documented for this exact file. Verified instead by:

- `node --check KeeBridgeCardExtension/Resources/content.js` — confirms no
  syntax error was introduced.
- A standalone Node script extracting just the fixed `expirationYear`
  formatting logic and exercising it against six `(value, maxLength,
  placeholder)` combinations covering both the 2-digit and 4-digit expected
  cases, with and without a `maxLength`/placeholder signal present — all six
  produced the correct output.

This is a "still needs a human eyeball" caveat in the same sense every other
JS-only change in this ROADMAP carries: real-Safari verification against an
actual card-form site would be the final confirmation, but the logic itself
is a pure, deterministic string-formatting function with no browser-specific
behavior beyond `element.maxLength`/`getAttribute`, both exercised directly
above.
