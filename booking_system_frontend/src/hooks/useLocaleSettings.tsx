import { useState } from 'react';
import type { ReactNode } from 'react';
import type { SupportedCurrency, LocaleSettings } from '../types';
import { LocaleSettingsContext } from './useLocaleSettingsContext';

const STORAGE_KEY = 'galaxium_locale_settings';

// Map from navigator.language prefix to SupportedCurrency
const LOCALE_CURRENCY_MAP: Record<string, SupportedCurrency> = {
  'en-US': 'USD',
  'en-CA': 'CAD',
  'en-GB': 'GBP',
  'en-AU': 'AUD',
  'en-NZ': 'NZD',
  'en-HK': 'HKD',
  'en-SG': 'SGD',
  'de':    'EUR',
  'fr':    'EUR',
  'es':    'EUR',
  'it':    'EUR',
  'nl':    'EUR',
  'pt-BR': 'BRL',
  'pt':    'EUR',
  'ja':    'JPY',
  'ko':    'KRW',
  'zh-CN': 'CNY',
  'zh-HK': 'HKD',
  'zh-TW': 'TWD' as SupportedCurrency,
  'zh-SG': 'SGD',
  'zh':    'CNY',
  'hi':    'INR',
  'es-MX': 'MXN',
  'es-419': 'MXN',
  'ar':    'USD',
  'ru':    'USD',
  'ch':    'CHF',
};

function detectCurrency(): SupportedCurrency {
  const lang = navigator.language; // e.g. "en-GB", "ja-JP"
  if (lang in LOCALE_CURRENCY_MAP) {
    return LOCALE_CURRENCY_MAP[lang];
  }
  // Try prefix match (e.g. "de-AT" → "de")
  const prefix = lang.split('-')[0];
  if (prefix in LOCALE_CURRENCY_MAP) {
    return LOCALE_CURRENCY_MAP[prefix];
  }
  return 'USD';
}

function detectLocale(): string {
  return navigator.language || 'en-US';
}

function detectUse12Hour(): boolean {
  try {
    const fmt = new Intl.DateTimeFormat(navigator.language, { hour: 'numeric' });
    const hourCycle = fmt.resolvedOptions().hourCycle;
    return hourCycle === 'h11' || hourCycle === 'h12';
  } catch {
    return false;
  }
}

function detectTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone;
  } catch {
    return 'UTC';
  }
}

function getDefaults(): LocaleSettings {
  return {
    currency: detectCurrency(),
    locale: detectLocale(),
    use12Hour: detectUse12Hour(),
    timezone: detectTimezone(),
  };
}

function loadFromStorage(): LocaleSettings | null {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      return JSON.parse(stored) as LocaleSettings;
    }
  } catch {
    // ignore parse errors
  }
  return null;
}

function saveToStorage(settings: LocaleSettings): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
  } catch {
    // ignore storage errors
  }
}

export const LocaleSettingsProvider = ({ children }: { children: ReactNode }) => {
  const [settings, setSettings] = useState<LocaleSettings>(() => {
    return loadFromStorage() ?? getDefaults();
  });

  const updateSettings = (patch: Partial<LocaleSettings>) => {
    setSettings(prev => {
      const next = { ...prev, ...patch };
      saveToStorage(next);
      return next;
    });
  };

  const setCurrency = (currency: SupportedCurrency) => {
    updateSettings({ currency });
  };

  const setUse12Hour = (use12Hour: boolean) => {
    updateSettings({ use12Hour });
  };

  const setTimezone = (timezone: string) => {
    updateSettings({ timezone });
  };

  return (
    <LocaleSettingsContext.Provider
      value={{
        currency: settings.currency,
        locale: settings.locale,
        use12Hour: settings.use12Hour,
        timezone: settings.timezone,
        setCurrency,
        setUse12Hour,
        setTimezone,
      }}
    >
      {children}
    </LocaleSettingsContext.Provider>
  );
};

// Made with Bob
