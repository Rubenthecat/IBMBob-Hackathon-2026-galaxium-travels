# Currency Conversion Fix Plan

## Top-Level Overview

**Goal:** Fix two related currency display bugs:
1. Changing currency preference only swaps the symbol — the numeric value is never converted from USD.
2. All currencies are forced to 0 decimal places by `formatCurrency`, hiding cents/pence where they are standard (EUR, GBP, CHF, etc.) and incorrectly suppressing sub-unit display.

All backend prices are stored and returned in USD. The frontend must convert those USD values to the user's selected currency and display them with the correct decimal and grouping separator conventions for that currency. The backend values must never be mutated.

**Scope:** Frontend only. No backend changes. Changes are isolated to `formatters.ts` and the six price-display locations across four components:
- `FlightCard.tsx` — seat class prices on the flight selection step
- `BookingModal.tsx` — seat selection (step 1), price quote (step 2), and place-hold (step 3) steps
- `BookingCard.tsx` — past bookings screen
- `HoldCard.tsx` — held itineraries screen

**Approach:**
1. Fix `formatCurrency` in `formatters.ts` to remove the hardcoded `0` fraction-digit overrides, letting `Intl.NumberFormat` apply each currency's standard decimal places automatically (JPY/KRW → 0, most others → 2).
2. Add a static USD exchange-rate table and a `convertCurrency()` utility to `formatters.ts`.
3. For zero-decimal currencies (JPY, KRW), `convertCurrency` must round to the nearest integer. For all others, it should preserve 2 decimal places so the formatter can display them correctly.
4. Replace every raw price pass-through to `formatCurrency()` with a converted value, using the user's current currency preference from `useLocaleSettings`.

**Grouping separators (comma vs period vs space):** `Intl.NumberFormat` handles these automatically from the `locale` string already threaded through every call site. No additional changes are needed — a user with locale `en-US` will see `1,234.56` and a user with `de` will see `1.234,56` for the same amount.

**Non-goals:**
- No live/API exchange rates — a reasonable static table is sufficient for the demo.
- No backend changes.
- No changes to how currency preferences are stored or selected.
- No changes to internal booking values (price_paid, pricePerSeat, totalPrice) — conversion is display-only.

---

## Sub-Task 1 — Fix `formatCurrency`, add exchange-rate table and `convertCurrency` utility

**Intent:**
Fix the two root causes in `formatters.ts`: the suppressed decimal places and the missing conversion logic. This is the only file that needs to change for both issues — all call sites benefit automatically once these are correct.

**Expected Outcomes:**
- `formatCurrency` no longer forces `minimumFractionDigits: 0` / `maximumFractionDigits: 0`. Instead, it lets `Intl.NumberFormat` resolve the correct fraction digits for the given currency code automatically (standard browser behaviour). This means:
  - JPY, KRW → 0 decimal places (e.g. `¥149,500`, `₩1,325,000`)
  - USD, EUR, GBP, CAD, AUD, CHF, CNY, INR, BRL, MXN, SGD, HKD, NZD → 2 decimal places (e.g. `€1,104.00`, `£948.00`)
- `formatters.ts` exports an `EXCHANGE_RATES` constant — a `Record<SupportedCurrency, number>` with static rates where `USD = 1.0` is the base.
- `formatters.ts` exports `convertCurrency(amountUSD: number, toCurrency: SupportedCurrency): number` which multiplies `amountUSD` by the rate. For zero-decimal currencies (JPY, KRW) the result is `Math.round()`ed. For all others the result is rounded to 2 decimal places (`Math.round(x * 100) / 100`) so the formatter can display them correctly.
- Grouping separators (comma/period/space) are already handled correctly by `Intl.NumberFormat` using the `locale` argument passed from context — no changes needed to that logic.

**Todo List:**
1. Open `booking_system_frontend/src/utils/formatters.ts`.
2. In `formatCurrency`, remove the `minimumFractionDigits: 0` and `maximumFractionDigits: 0` lines — let `Intl.NumberFormat` use currency-default fraction digits.
3. Add an `EXCHANGE_RATES` constant of type `Record<SupportedCurrency, number>` (see Exchange Rate Reference section below for values).
4. Add a `ZERO_DECIMAL_CURRENCIES` set containing `'JPY'` and `'KRW'`.
5. Add `convertCurrency(amountUSD: number, toCurrency: SupportedCurrency): number` — multiply by rate, then round to 0 decimals if the currency is in `ZERO_DECIMAL_CURRENCIES`, or to 2 decimal places otherwise.
6. Export `EXCHANGE_RATES` and `convertCurrency`.

**Relevant Context:**
- `booking_system_frontend/src/utils/formatters.ts` lines 89-100 — `formatCurrency` currently hardcodes `minimumFractionDigits: 0` and `maximumFractionDigits: 0`; these two lines must be removed.
- `booking_system_frontend/src/types/index.ts` line 77-79 — `SupportedCurrency` union type; import it into `formatters.ts` for the `EXCHANGE_RATES` type and `convertCurrency` signature.
- `Intl.NumberFormat` currency-default fraction digits are part of the CLDR standard and are reliable across all modern browsers.

**Status:** `[ ] pending`

---

## Sub-Task 2 — Fix `FlightCard.tsx` — flight selection seat class prices

**Intent:**
The seat class prices shown on the flight selection step display raw USD values regardless of the selected currency. Apply conversion before formatting.

**Expected Outcomes:**
- Seat class prices (economy, business, galaxium) are shown in the user's selected currency with the correct converted amount.
- No change to the underlying `seatClass.price` data.

**Todo List:**
1. Open `booking_system_frontend/src/components/flights/FlightCard.tsx`.
2. Import `convertCurrency` from `../../utils/formatters`.
3. At line 144, wrap the raw price: change `formatCurrency(seatClass.price, currency, locale)` to `formatCurrency(convertCurrency(seatClass.price, currency), currency, locale)`.

**Relevant Context:**
- `booking_system_frontend/src/components/flights/FlightCard.tsx` line 16: already imports `useLocaleSettings` and destructures `currency` and `locale`.
- `booking_system_frontend/src/components/flights/FlightCard.tsx` line 144: the single price render call.

**Status:** `[ ] pending`

---

## Sub-Task 3 — Fix `BookingModal.tsx` — all three booking steps

**Intent:**
The multi-step booking modal has three places where prices are shown raw. Step 1 (seat selection) doesn't even pass currency/locale. All three must be fixed.

**Expected Outcomes:**
- Step 1 (seat selection, line ~278): prices shown in user's selected currency with correct conversion; currency and locale are passed.
- Step 2 (quote review, lines ~336 and ~342): `quote.pricePerSeat` and `quote.totalPrice` displayed with correct conversion.
- Step 3 (hold confirmation, line ~409): `quote.totalPrice` displayed with correct conversion.

**Todo List:**
1. Open `booking_system_frontend/src/components/bookings/BookingModal.tsx` (or equivalent path).
2. Import `convertCurrency` from the formatters utility.
3. Ensure `currency` and `locale` are destructured from `useLocaleSettings()` at the top of the component (they may already be present — confirm first).
4. Step 1 (~line 278): Change `formatCurrency(sc.price)` → `formatCurrency(convertCurrency(sc.price, currency), currency, locale)`.
5. Step 2 (~line 336): Change `formatCurrency(quote?.pricePerSeat || 0, currency, locale)` → `formatCurrency(convertCurrency(quote?.pricePerSeat || 0, currency), currency, locale)`.
6. Step 2 (~line 342): Same pattern for `quote?.totalPrice`.
7. Step 3 (~line 409): Same pattern for `quote?.totalPrice`.

**Relevant Context:**
- Component file: likely `booking_system_frontend/src/components/bookings/BookingModal.tsx`.
- `useLocaleSettings` hook is already available in the project.
- All quote prices (`pricePerSeat`, `totalPrice`) come from the Java hold service and are in USD.

**Status:** `[ ] pending`

---

## Sub-Task 4 — Fix `BookingCard.tsx` — bookings screen

**Intent:**
Past booking prices (`price_paid`) are stored in USD on the backend and must be displayed in the user's currently selected currency with the correct conversion.

**Expected Outcomes:**
- `booking.price_paid` is displayed in the user's selected currency with the correct converted value.

**Todo List:**
1. Open `booking_system_frontend/src/components/bookings/BookingCard.tsx`.
2. Import `convertCurrency` from the formatters utility.
3. At line ~141, change `formatCurrency(booking.price_paid, currency, locale)` → `formatCurrency(convertCurrency(booking.price_paid, currency), currency, locale)`.

**Relevant Context:**
- `booking_system_frontend/src/components/bookings/BookingCard.tsx` line 16: already has `currency` and `locale` from `useLocaleSettings`.
- `booking_system_frontend/src/components/bookings/BookingCard.tsx` line 141: single price render.

**Status:** `[ ] pending`

---

## Sub-Task 5 — Fix `HoldCard.tsx` — held itineraries screen

**Intent:**
Held itinerary prices (`storedHold.totalPrice`) are stored in USD and must be converted for display.

**Expected Outcomes:**
- `storedHold.totalPrice` is displayed in the user's selected currency with the correct converted value.

**Todo List:**
1. Open `booking_system_frontend/src/components/bookings/HoldCard.tsx`.
2. Import `convertCurrency` from the formatters utility.
3. At line ~158, change `formatCurrency(storedHold.totalPrice, currency, locale)` → `formatCurrency(convertCurrency(storedHold.totalPrice, currency), currency, locale)`.

**Relevant Context:**
- `booking_system_frontend/src/components/bookings/HoldCard.tsx` line 21: already has `currency` and `locale` from `useLocaleSettings`.
- `booking_system_frontend/src/components/bookings/HoldCard.tsx` line 158: single price render.

**Status:** `[ ] pending`

---

## Sub-Task 6 — Verification

**Intent:**
Confirm all price-display locations have been fixed and no new TypeScript or lint errors have been introduced.

**Expected Outcomes:**
- Frontend lints cleanly (`npm run lint` passes with no new errors).
- TypeScript type-check passes (`npm run build` or `tsc --noEmit` succeeds).
- Manually: switching currency in preferences changes both the symbol AND the numeric value consistently across all six price-display locations.

**Todo List:**
1. Run `cd booking_system_frontend && npm run lint` — fix any issues.
2. Run `cd booking_system_frontend && npm run build` — fix any type errors.
3. Use the `verify` skill to confirm all relevant checks pass.

**Relevant Context:**
- Use the `verify` skill after implementation.
- The six locations to spot-check: FlightCard seat prices, BookingModal step 1/2/3, BookingCard, HoldCard.

**Status:** `[ ] pending`

---

## Exchange Rate Reference (for Sub-Task 1)

Approximate static USD-base rates for the 15 supported currencies (to be used in `EXCHANGE_RATES`):

| Currency | Code | Rate (1 USD =) |
|----------|------|----------------|
| US Dollar | USD | 1.00 |
| Euro | EUR | 0.92 |
| British Pound | GBP | 0.79 |
| Japanese Yen | JPY | 149.50 |
| Canadian Dollar | CAD | 1.36 |
| Australian Dollar | AUD | 1.53 |
| Swiss Franc | CHF | 0.90 |
| Chinese Yuan | CNY | 7.24 |
| Indian Rupee | INR | 83.50 |
| Brazilian Real | BRL | 4.97 |
| Mexican Peso | MXN | 17.15 |
| Singapore Dollar | SGD | 1.34 |
| Hong Kong Dollar | HKD | 7.82 |
| New Zealand Dollar | NZD | 1.63 |
| South Korean Won | KRW | 1325.00 |
