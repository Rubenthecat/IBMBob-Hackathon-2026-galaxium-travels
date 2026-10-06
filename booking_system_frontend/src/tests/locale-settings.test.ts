/**
 * Locale Settings Feature — Test Suite
 * =====================================
 * Tests for the currency/time-format/timezone feature added in LOCALE-SETTINGS-PLAN.md.
 *
 * SETUP (run once before executing these tests):
 * -----------------------------------------------
 * 1. Install Vitest and React Testing Library:
 *      cd booking_system_frontend
 *      npm install --save-dev vitest @vitest/coverage-v8 jsdom \
 *        @testing-library/react @testing-library/user-event @testing-library/jest-dom
 *
 * 2. Add a Vitest config block to vite.config.ts (or create vitest.config.ts):
 *      import { defineConfig } from 'vitest/config';
 *      export default defineConfig({
 *        test: {
 *          environment: 'jsdom',
 *          globals: true,
 *          setupFiles: ['./src/tests/setup.ts'],
 *        },
 *      });
 *
 * 3. Create src/tests/setup.ts:
 *      import '@testing-library/jest-dom';
 *
 * 4. Add test script to package.json:
 *      "test": "vitest run",
 *      "test:watch": "vitest",
 *      "test:coverage": "vitest run --coverage"
 *
 * 5. Run:
 *      npm test
 *
 * -----------------------------------------------
 * COVERAGE
 * -----------------------------------------------
 * Section A — formatCurrency()   : currency + locale params, backward compat
 * Section B — formatTime()       : 12h/24h toggle, timezone shift, backward compat
 * Section C — formatDate()       : timezone shift, backward compat
 * Section D — LocaleSettings context: browser auto-detection, localStorage persistence,
 *                                     setters, provider throws outside context
 * Section E — LocaleSettingsDropdown (component): renders, opens/closes,
 *                                     currency change, time-format toggle,
 *                                     timezone change, outside-click, Escape key
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act, render, screen, fireEvent } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import React from 'react';

import { formatCurrency, formatTime, formatDate } from '../utils/formatters';
import { LocaleSettingsProvider } from '../hooks/useLocaleSettings';
import { useLocaleSettings } from '../hooks/useLocaleSettingsContext';
import { LocaleSettingsDropdown } from '../components/layout/LocaleSettingsDropdown';

// ---------------------------------------------------------------------------
// A — formatCurrency
// ---------------------------------------------------------------------------
describe('formatCurrency', () => {
  it('defaults to USD with en-US locale', () => {
    expect(formatCurrency(1500)).toBe('$1,500');
  });

  it('formats EUR with de-DE locale', () => {
    const result = formatCurrency(1500, 'EUR', 'de-DE');
    // de-DE uses period as thousands separator and comma as decimal; no decimals here
    expect(result).toContain('€');
    expect(result).toContain('1');
  });

  it('formats GBP with en-GB locale', () => {
    const result = formatCurrency(2000, 'GBP', 'en-GB');
    expect(result).toContain('£');
    expect(result).toContain('2,000');
  });

  it('formats JPY with ja-JP locale', () => {
    const result = formatCurrency(150000, 'JPY', 'ja-JP');
    // jsdom's Intl may use fullwidth ￥ or narrow ¥ depending on ICU data;
    // assert on the numeric portion which is unambiguous.
    expect(result).toMatch(/150[,.]?000|150000/);
  });

  it('formats CAD with en-CA locale', () => {
    const result = formatCurrency(1000, 'CAD', 'en-CA');
    expect(result).toContain('$');
  });

  it('formats zero correctly', () => {
    expect(formatCurrency(0)).toBe('$0');
  });

  it('formats large amounts (interplanetary prices)', () => {
    const result = formatCurrency(1500000, 'USD', 'en-US');
    expect(result).toBe('$1,500,000');
  });

  it('is backward-compatible: one argument still works', () => {
    // Must not throw; should return a USD string
    expect(() => formatCurrency(500)).not.toThrow();
    expect(formatCurrency(500)).toMatch(/^\$/);
  });
});

// ---------------------------------------------------------------------------
// B — formatTime
// ---------------------------------------------------------------------------
describe('formatTime', () => {
  // The backend returns "YYYY-MM-DD HH:MM" strings which parseISO handles.
  const TIME_14_30 = '2099-01-15 14:30';
  const TIME_09_05 = '2099-01-15 09:05';

  it('defaults to 24-hour format', () => {
    expect(formatTime(TIME_14_30)).toBe('14:30');
  });

  it('returns 24-hour format when use12Hour is false', () => {
    expect(formatTime(TIME_14_30, false)).toBe('14:30');
  });

  it('returns 12-hour format with AM/PM when use12Hour is true', () => {
    const result = formatTime(TIME_14_30, true);
    // date-fns hh:mm a → "02:30 PM"
    expect(result).toMatch(/^02:30 PM$/i);
  });

  it('returns 12-hour AM format correctly', () => {
    const result = formatTime(TIME_09_05, true);
    expect(result).toMatch(/^09:05 AM$/i);
  });

  it('handles midnight in 12-hour format', () => {
    const midnight = '2099-01-15 00:00';
    const result = formatTime(midnight, true);
    expect(result).toMatch(/AM/i);
  });

  it('applies timezone offset — UTC vs Tokyo (JST = UTC+9)', () => {
    // 14:30 UTC should display as 23:30 in Asia/Tokyo
    const resultUTC = formatTime(TIME_14_30, false, 'UTC');
    const resultTokyo = formatTime(TIME_14_30, false, 'Asia/Tokyo');
    expect(resultUTC).toBe('14:30');
    expect(resultTokyo).toBe('23:30');
  });

  it('applies timezone offset — UTC vs New York (EST = UTC-5)', () => {
    // 14:30 UTC → 09:30 EST (non-DST)
    // Note: this test assumes a winter date where DST is not in effect.
    const result = formatTime(TIME_14_30, false, 'America/New_York');
    // Allow 09:30 (EST) or 10:30 (EDT) depending on date
    expect(result).toMatch(/^(09|10):30$/);
  });

  it('falls back gracefully on an invalid timezone', () => {
    expect(() => formatTime(TIME_14_30, false, 'Not/A/Timezone')).not.toThrow();
  });

  it('is backward-compatible: one argument still works', () => {
    expect(() => formatTime(TIME_14_30)).not.toThrow();
    expect(formatTime(TIME_14_30)).toBe('14:30');
  });
});

// ---------------------------------------------------------------------------
// C — formatDate
// ---------------------------------------------------------------------------
describe('formatDate', () => {
  const DATE_STR = '2099-06-15 08:00';

  it('defaults to MMM dd, yyyy HH:mm format', () => {
    // Default format: 'MMM dd, yyyy HH:mm'
    const result = formatDate(DATE_STR);
    expect(result).toMatch(/^Jun 15, 2099 08:00$/);
  });

  it('accepts a custom format string', () => {
    expect(formatDate(DATE_STR, 'MMM dd, yyyy')).toBe('Jun 15, 2099');
  });

  it('applies timezone when provided', () => {
    // 08:00 UTC in Asia/Tokyo (UTC+9) → 17:00
    const result = formatDate(DATE_STR, 'HH:mm', 'Asia/Tokyo');
    expect(result).toBe('17:00');
  });

  it('is backward-compatible: one argument still works', () => {
    expect(() => formatDate(DATE_STR)).not.toThrow();
  });

  it('returns the raw string on an unparseable input', () => {
    const bad = 'not-a-date';
    const result = formatDate(bad);
    expect(result).toBe(bad);
  });
});

// ---------------------------------------------------------------------------
// D — LocaleSettings context
// ---------------------------------------------------------------------------
describe('LocaleSettingsProvider + useLocaleSettings', () => {
  const STORAGE_KEY = 'galaxium_locale_settings';

  beforeEach(() => {
    localStorage.clear();
    // Silence any console.error noise from intentional error-boundary tests
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    localStorage.clear();
    vi.restoreAllMocks();
  });

  const wrapper = ({ children }: { children: React.ReactNode }) =>
    React.createElement(LocaleSettingsProvider, null, children);

  it('provides context values without throwing', () => {
    const { result } = renderHook(() => useLocaleSettings(), { wrapper });
    expect(result.current.currency).toBeTruthy();
    expect(typeof result.current.use12Hour).toBe('boolean');
    expect(typeof result.current.timezone).toBe('string');
    expect(typeof result.current.locale).toBe('string');
  });

  it('exposes setCurrency, setUse12Hour, setTimezone as functions', () => {
    const { result } = renderHook(() => useLocaleSettings(), { wrapper });
    expect(typeof result.current.setCurrency).toBe('function');
    expect(typeof result.current.setUse12Hour).toBe('function');
    expect(typeof result.current.setTimezone).toBe('function');
  });

  it('setCurrency updates the currency value', () => {
    const { result } = renderHook(() => useLocaleSettings(), { wrapper });
    act(() => {
      result.current.setCurrency('EUR');
    });
    expect(result.current.currency).toBe('EUR');
  });

  it('setUse12Hour toggles the time format', () => {
    const { result } = renderHook(() => useLocaleSettings(), { wrapper });
    const initial = result.current.use12Hour;
    act(() => {
      result.current.setUse12Hour(!initial);
    });
    expect(result.current.use12Hour).toBe(!initial);
  });

  it('setTimezone updates the timezone value', () => {
    const { result } = renderHook(() => useLocaleSettings(), { wrapper });
    act(() => {
      result.current.setTimezone('Asia/Tokyo');
    });
    expect(result.current.timezone).toBe('Asia/Tokyo');
  });

  it('persists settings to localStorage on change', () => {
    const { result } = renderHook(() => useLocaleSettings(), { wrapper });
    act(() => {
      result.current.setCurrency('GBP');
    });
    const stored = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '{}');
    expect(stored.currency).toBe('GBP');
  });

  it('loads persisted settings from localStorage on mount', () => {
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({ currency: 'JPY', locale: 'ja-JP', use12Hour: false, timezone: 'Asia/Tokyo' })
    );
    const { result } = renderHook(() => useLocaleSettings(), { wrapper });
    expect(result.current.currency).toBe('JPY');
    expect(result.current.timezone).toBe('Asia/Tokyo');
  });

  it('falls back to browser defaults when localStorage is empty', () => {
    localStorage.clear();
    const { result } = renderHook(() => useLocaleSettings(), { wrapper });
    // Should not throw; currency should be one of the supported values
    const supported = ['USD','EUR','GBP','JPY','CAD','AUD','CHF','CNY','INR','BRL','MXN','SGD','HKD','NZD','KRW'];
    expect(supported).toContain(result.current.currency);
  });

  it('throws when useLocaleSettings is called outside the provider', () => {
    expect(() => renderHook(() => useLocaleSettings())).toThrow(
      'useLocaleSettings must be used within a LocaleSettingsProvider'
    );
  });
});

// ---------------------------------------------------------------------------
// E — LocaleSettingsDropdown component
// ---------------------------------------------------------------------------
describe('LocaleSettingsDropdown', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    localStorage.clear();
    vi.restoreAllMocks();
  });

  const renderDropdown = () => {
    return render(
      React.createElement(
        LocaleSettingsProvider,
        null,
        React.createElement(LocaleSettingsDropdown)
      )
    );
  };

  it('renders the settings gear button', () => {
    renderDropdown();
    expect(screen.getByRole('button', { name: /locale settings/i })).toBeInTheDocument();
  });

  it('dropdown panel is hidden by default', () => {
    renderDropdown();
    expect(screen.queryByText('Display Settings')).not.toBeInTheDocument();
  });

  it('opens the dropdown on gear button click', async () => {
    const user = userEvent.setup();
    renderDropdown();
    await user.click(screen.getByRole('button', { name: /locale settings/i }));
    expect(screen.getByText('Display Settings')).toBeInTheDocument();
  });

  it('closes the dropdown on second gear button click', async () => {
    const user = userEvent.setup();
    renderDropdown();
    const btn = screen.getByRole('button', { name: /locale settings/i });
    await user.click(btn);
    expect(btn).toHaveAttribute('aria-expanded', 'true');
    await user.click(btn);
    // framer-motion AnimatePresence keeps the node in jsdom during exit animation;
    // verify via aria-expanded which is updated synchronously by React state.
    expect(btn).toHaveAttribute('aria-expanded', 'false');
  });

  it('closes on Escape key press', async () => {
    const user = userEvent.setup();
    renderDropdown();
    const btn = screen.getByRole('button', { name: /locale settings/i });
    await user.click(btn);
    expect(btn).toHaveAttribute('aria-expanded', 'true');
    await user.keyboard('{Escape}');
    expect(btn).toHaveAttribute('aria-expanded', 'false');
  });

  it('closes on outside click', async () => {
    const user = userEvent.setup();
    renderDropdown();
    const btn = screen.getByRole('button', { name: /locale settings/i });
    await user.click(btn);
    expect(btn).toHaveAttribute('aria-expanded', 'true');
    await user.click(document.body);
    expect(btn).toHaveAttribute('aria-expanded', 'false');
  });

  it('shows all 15 currency options', async () => {
    const user = userEvent.setup();
    renderDropdown();
    await user.click(screen.getByRole('button', { name: /locale settings/i }));
    const currencySelect = screen.getByDisplayValue(/USD|EUR|GBP|JPY|CAD|AUD|CHF|CNY|INR|BRL|MXN|SGD|HKD|NZD|KRW/);
    expect(currencySelect).toBeInTheDocument();
    const options = currencySelect.querySelectorAll('option');
    expect(options).toHaveLength(15);
  });

  it('changing currency select calls setCurrency and persists', async () => {
    const user = userEvent.setup();
    renderDropdown();
    await user.click(screen.getByRole('button', { name: /locale settings/i }));
    // The currency <select> is the first combobox in the panel (no accessible label text).
    const currencySelect = screen.getAllByRole('combobox')[0];
    fireEvent.change(currencySelect, { target: { value: 'EUR' } });
    const stored = JSON.parse(localStorage.getItem('galaxium_locale_settings') ?? '{}');
    expect(stored.currency).toBe('EUR');
  });

  it('renders 12-hour and 24-hour toggle buttons', async () => {
    const user = userEvent.setup();
    renderDropdown();
    await user.click(screen.getByRole('button', { name: /locale settings/i }));
    expect(screen.getByRole('button', { name: /12-hour/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /24-hour/i })).toBeInTheDocument();
  });

  it('clicking 12-hour button persists use12Hour: true', async () => {
    const user = userEvent.setup();
    renderDropdown();
    await user.click(screen.getByRole('button', { name: /locale settings/i }));
    await user.click(screen.getByRole('button', { name: /12-hour/i }));
    const stored = JSON.parse(localStorage.getItem('galaxium_locale_settings') ?? '{}');
    expect(stored.use12Hour).toBe(true);
  });

  it('clicking 24-hour button persists use12Hour: false', async () => {
    const user = userEvent.setup();
    renderDropdown();
    await user.click(screen.getByRole('button', { name: /locale settings/i }));
    await user.click(screen.getByRole('button', { name: /24-hour/i }));
    const stored = JSON.parse(localStorage.getItem('galaxium_locale_settings') ?? '{}');
    expect(stored.use12Hour).toBe(false);
  });

  it('shows at least 26 timezone options', async () => {
    const user = userEvent.setup();
    renderDropdown();
    await user.click(screen.getByRole('button', { name: /locale settings/i }));
    const selects = screen.getAllByRole('combobox');
    // Second combobox is the timezone select
    const tzSelect = selects[1];
    const options = tzSelect.querySelectorAll('option');
    expect(options.length).toBeGreaterThanOrEqual(26);
  });

  it('changing timezone select persists the new timezone', async () => {
    const user = userEvent.setup();
    renderDropdown();
    await user.click(screen.getByRole('button', { name: /locale settings/i }));
    const selects = screen.getAllByRole('combobox');
    fireEvent.change(selects[1], { target: { value: 'Asia/Tokyo' } });
    const stored = JSON.parse(localStorage.getItem('galaxium_locale_settings') ?? '{}');
    expect(stored.timezone).toBe('Asia/Tokyo');
  });
});
