# Locale Settings Plan — Currency & Time Format Preferences

## Top-Level Overview

Galaxium Travels currently hardcodes all currency display to USD with `Intl.NumberFormat('en-US')` and all time display to 24-hour format via date-fns `HH:mm`. Users from regions that use 12-hour clocks or non-USD currencies have no way to adjust these.

The goal is to add a **LocaleSettings context** that holds the user's currency, time format (12h/24h), and timezone preferences. These preferences default to **browser locale auto-detection** on first load and are persisted in `localStorage`. A **settings dropdown in the navbar** (always accessible) allows manual override. All existing `formatCurrency()` and `formatTime()` calls are updated to read from this context.

**Scope:**
- New React context (`LocaleSettingsContext`) with `localStorage` persistence
- Updated `formatters.ts` functions to accept locale parameters
- Settings dropdown UI in `Header.tsx`
- All call sites in `FlightCard`, `BookingModal`, `BookingCard`, `HoldCard`, `DestinationDetail` updated to use context-aware formatting
- No backend changes required — all prices come as raw numbers, all times as ISO strings

**Non-goals:**
- No backend currency conversion (display formatting only; prices remain in USD as stored)
- No server-side locale persistence
- No i18n library — native `Intl` APIs are sufficient

---

## Sub-Tasks

---

### Sub-Task 1 — Create the LocaleSettings Context

**Intent:**
Establish the shared state that every component will read for locale preferences. This is the foundation everything else builds on. The context provides currency code, time format (12h/24h), and timezone, with browser auto-detection as the default and `localStorage` for persistence across sessions.

**Expected Outcomes:**
- A new file `booking_system_frontend/src/hooks/useLocaleSettings.tsx` exports `LocaleSettingsProvider` and `useLocaleSettings` hook.
- A new file `booking_system_frontend/src/hooks/useLocaleSettingsContext.ts` exports the raw `LocaleSettingsContext` (mirrors the existing `useUser`/`useUserContext` split pattern).
- The context auto-detects currency from `navigator.language` (e.g. `en-GB` → GBP, `ja-JP` → JPY) using a locale→currency mapping for major currencies (USD, EUR, GBP, JPY, CAD, AUD, CHF, CNY, INR, BRL, MXN, SGD, HKD, NZD, KRW).
- The context auto-detects time format (12h/24h) from `Intl.DateTimeFormat` hourCycle.
- The context auto-detects timezone from `Intl.DateTimeFormat().resolvedOptions().timeZone`.
- All preferences are persisted to `localStorage` under key `galaxium_locale_settings`.
- The `LocaleSettingsProvider` is added to `App.tsx` wrapping the router (same level as `UserProvider`).

**Todo List:**
1. Create `booking_system_frontend/src/hooks/useLocaleSettingsContext.ts` — defines and exports `LocaleSettingsContext` and `useLocaleSettings` hook.
2. Create `booking_system_frontend/src/hooks/useLocaleSettings.tsx` — implements `LocaleSettingsProvider` with browser auto-detection, `localStorage` persistence, and `setters` for each preference.
3. Define a `LocaleSettings` TypeScript interface and `SupportedCurrency` type in `booking_system_frontend/src/types/index.ts`.
4. Wrap the app in `App.tsx` with `LocaleSettingsProvider`.

**Relevant Context:**
- Mirror the existing pattern: [`useUserContext.ts`](booking_system_frontend/src/hooks/useUserContext.ts) + [`useUser.tsx`](booking_system_frontend/src/hooks/useUser.tsx)
- Provider is added in [`App.tsx`](booking_system_frontend/src/App.tsx) alongside the existing `UserProvider`
- `localStorage` key: `galaxium_locale_settings`

**Status:** `[ ] pending`

---

### Sub-Task 2 — Update formatters.ts to Accept Locale Parameters

**Intent:**
Decouple the formatting functions from their hardcoded locale values. Each function gains optional parameters that let callers pass in the current locale settings. Existing call sites without parameters continue to work (backward-compatible defaults remain).

**Expected Outcomes:**
- `formatCurrency(amount, currency?, locale?)` — uses provided currency code and locale string (e.g. `'en-GB'`, `'ja-JP'`) or falls back to `'en-US'`/`'USD'`.
- `formatTime(dateString, use12Hour?, timezone?)` — when `use12Hour` is true, produces `'hh:mm a'` (12-hour with AM/PM) via date-fns; when false, produces `'HH:mm'` (24-hour). Timezone is applied via date-fns-tz `zonedTimeToUtc`/`utcToZonedTime` or native `Intl.DateTimeFormat` if date-fns-tz is not already installed.
- `formatDate(dateString, formatString?, timezone?)` — applies timezone offset before formatting.
- `calculateDuration` is unaffected (pure arithmetic, no locale needed).
- All existing function signatures remain callable without new arguments (backward compatible).

**Todo List:**
1. Check whether `date-fns-tz` is already in `package.json`; if not, add it.
2. Update `formatCurrency` to accept optional `currency: string` and `locale: string` parameters.
3. Update `formatTime` to accept optional `use12Hour: boolean` and `timezone: string` parameters.
4. Update `formatDate` to accept optional `timezone: string` parameter.
5. Verify all existing callers still compile without changes (backward compat check).

**Relevant Context:**
- Current formatters: [`formatters.ts`](booking_system_frontend/src/utils/formatters.ts)
- date-fns is already installed (`^4.1.0` in package.json); check for date-fns-tz separately
- `Intl.DateTimeFormat` can handle timezone conversion natively if date-fns-tz is absent

**Status:** `[ ] pending`

---

### Sub-Task 3 — Update All Call Sites to Use Context-Aware Formatting

**Intent:**
Wire the locale context into every component that renders a price or time so that selecting a currency or time format in settings immediately changes the displayed values everywhere.

**Expected Outcomes:**
- Every call to `formatCurrency(...)` passes the `currency` and `locale` from `useLocaleSettings()`.
- Every call to `formatTime(...)` passes `use12Hour` and `timezone` from `useLocaleSettings()`.
- Every call to `formatDate(...)` passes `timezone` from `useLocaleSettings()`.
- All affected components import and destructure `useLocaleSettings()` at the top.
- No hardcoded `'USD'`, `'en-US'`, or `'HH:mm'` strings remain in component files.

**Affected Files (all call sites identified during research):**
- [`FlightCard.tsx`](booking_system_frontend/src/components/flights/FlightCard.tsx) — departure/arrival times + seat-class prices
- [`BookingModal.tsx`](booking_system_frontend/src/components/bookings/BookingModal.tsx) — quote prices, flight times
- [`BookingCard.tsx`](booking_system_frontend/src/components/bookings/BookingCard.tsx) — booking time + price paid
- [`HoldCard.tsx`](booking_system_frontend/src/components/bookings/HoldCard.tsx) — hold total price
- [`DestinationDetail.tsx`](booking_system_frontend/src/pages/DestinationDetail.tsx) — "from" price + departure time

**Todo List:**
1. Update `FlightCard.tsx` — add `useLocaleSettings`, pass `currency`/`locale` to `formatCurrency`, pass `use12Hour`/`timezone` to `formatTime`/`formatDate`.
2. Update `BookingModal.tsx` — same pattern for all price and time renders.
3. Update `BookingCard.tsx` — same pattern.
4. Update `HoldCard.tsx` — same pattern for price.
5. Update `DestinationDetail.tsx` — same pattern for price and time.

**Status:** `[ ] pending`

---

### Sub-Task 4 — Add Settings Dropdown to the Navbar

**Intent:**
Give users a persistent, accessible control to change their locale preferences without leaving any page. The settings dropdown lives in the navbar next to the existing user/login section and is always visible regardless of auth state.

**Expected Outcomes:**
- A settings gear icon (from `lucide-react`, which is already used in the project) appears in `Header.tsx` to the left of the user/login section.
- Clicking it opens a dropdown panel (similar in visual style to other glass-card elements) with:
  - **Currency** — a `<select>` listing the supported currencies (USD, EUR, GBP, JPY, CAD, AUD, CHF, CNY, INR, BRL, MXN, SGD, HKD, NZD, KRW) with their symbols
  - **Time Format** — a toggle/radio between "12-hour (AM/PM)" and "24-hour"
  - **Timezone** — a `<select>` with major IANA timezone options grouped by region (or a searchable subset of common ones)
- The dropdown closes on outside click.
- Each control immediately calls the corresponding setter from `useLocaleSettings()`, which persists to `localStorage` and triggers a re-render of all formatted values.
- The dropdown is mobile-responsive (full-width on small screens).

**Todo List:**
1. Create `booking_system_frontend/src/components/layout/LocaleSettingsDropdown.tsx` — standalone component with its own open/close state and outside-click handling.
2. Import `Settings` icon from `lucide-react` and add the `LocaleSettingsDropdown` to `Header.tsx` in the user action area.
3. Style the dropdown to match the existing glass-card / cosmic palette conventions from `tailwind.config.js`.
4. Populate the currency list with display names and symbols (e.g. "USD — US Dollar $").
5. Populate the timezone list with a curated set of IANA zones covering major regions.

**Relevant Context:**
- [`Header.tsx`](booking_system_frontend/src/components/layout/Header.tsx) — add the settings icon in the `flex items-center gap-4` user section div
- [`tailwind.config.js`](booking_system_frontend/tailwind.config.js) — use `cosmic-purple`, `star-white`, `glass-card` tokens
- `lucide-react` is already a dependency (`Settings` icon available)
- `motion` from `framer-motion` is already used in Header for animation — can animate the dropdown

**Status:** `[ ] pending`

---

### Sub-Task 5 — Verification

**Intent:**
Confirm the feature works correctly end-to-end and that no existing tests are broken.

**Expected Outcomes:**
- Frontend lint passes (`npm run lint` in `booking_system_frontend/`).
- Frontend build passes (`npm run build` in `booking_system_frontend/`).
- Python backend tests are unaffected (`pytest` in `booking_system_backend/`).

**Todo List:**
1. Run `npm run lint` in `booking_system_frontend/` — fix any TypeScript or ESLint errors.
2. Run `npm run build` in `booking_system_frontend/` — fix any type errors.
3. Run `pytest` in `booking_system_backend/` — confirm no regressions.

**Status:** `[ ] pending`

---

## Architecture Summary

```
LocaleSettingsContext  (new)
  currency: SupportedCurrency   ← "USD" | "EUR" | "GBP" | ...
  locale: string                ← "en-US" | "en-GB" | "ja-JP" | ...
  use12Hour: boolean            ← true | false
  timezone: string              ← IANA timezone string

formatters.ts  (updated)
  formatCurrency(amount, currency?, locale?)
  formatTime(dateString, use12Hour?, timezone?)
  formatDate(dateString, formatString?, timezone?)

Header.tsx  (updated)
  + <LocaleSettingsDropdown />  ← always visible, persists prefs

Components  (updated to consume context)
  FlightCard, BookingModal, BookingCard, HoldCard, DestinationDetail
```
