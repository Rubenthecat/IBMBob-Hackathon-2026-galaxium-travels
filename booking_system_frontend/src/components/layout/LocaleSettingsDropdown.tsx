import { useRef, useEffect, useState } from 'react';
import { Settings } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { useLocaleSettings } from '../../hooks/useLocaleSettingsContext';
import type { SupportedCurrency } from '../../types';

const CURRENCIES: { code: SupportedCurrency; label: string }[] = [
  { code: 'USD', label: 'USD — US Dollar $' },
  { code: 'EUR', label: 'EUR — Euro €' },
  { code: 'GBP', label: 'GBP — British Pound £' },
  { code: 'JPY', label: 'JPY — Japanese Yen ¥' },
  { code: 'CAD', label: 'CAD — Canadian Dollar C$' },
  { code: 'AUD', label: 'AUD — Australian Dollar A$' },
  { code: 'CHF', label: 'CHF — Swiss Franc Fr' },
  { code: 'CNY', label: 'CNY — Chinese Yuan ¥' },
  { code: 'INR', label: 'INR — Indian Rupee ₹' },
  { code: 'BRL', label: 'BRL — Brazilian Real R$' },
  { code: 'MXN', label: 'MXN — Mexican Peso $' },
  { code: 'SGD', label: 'SGD — Singapore Dollar S$' },
  { code: 'HKD', label: 'HKD — Hong Kong Dollar HK$' },
  { code: 'NZD', label: 'NZD — New Zealand Dollar NZ$' },
  { code: 'KRW', label: 'KRW — South Korean Won ₩' },
];

const TIMEZONES: { value: string; label: string }[] = [
  { value: 'UTC', label: 'UTC — Coordinated Universal Time' },
  { value: 'America/New_York', label: 'America/New_York (ET)' },
  { value: 'America/Chicago', label: 'America/Chicago (CT)' },
  { value: 'America/Denver', label: 'America/Denver (MT)' },
  { value: 'America/Los_Angeles', label: 'America/Los_Angeles (PT)' },
  { value: 'America/Toronto', label: 'America/Toronto (ET)' },
  { value: 'America/Vancouver', label: 'America/Vancouver (PT)' },
  { value: 'America/Sao_Paulo', label: 'America/Sao_Paulo (BRT)' },
  { value: 'America/Mexico_City', label: 'America/Mexico_City (CST)' },
  { value: 'America/Argentina/Buenos_Aires', label: 'America/Buenos_Aires (ART)' },
  { value: 'Europe/London', label: 'Europe/London (GMT/BST)' },
  { value: 'Europe/Paris', label: 'Europe/Paris (CET)' },
  { value: 'Europe/Berlin', label: 'Europe/Berlin (CET)' },
  { value: 'Europe/Moscow', label: 'Europe/Moscow (MSK)' },
  { value: 'Africa/Johannesburg', label: 'Africa/Johannesburg (SAST)' },
  { value: 'Africa/Cairo', label: 'Africa/Cairo (EET)' },
  { value: 'Asia/Dubai', label: 'Asia/Dubai (GST)' },
  { value: 'Asia/Kolkata', label: 'Asia/Kolkata (IST)' },
  { value: 'Asia/Bangkok', label: 'Asia/Bangkok (ICT)' },
  { value: 'Asia/Singapore', label: 'Asia/Singapore (SGT)' },
  { value: 'Asia/Shanghai', label: 'Asia/Shanghai (CST)' },
  { value: 'Asia/Tokyo', label: 'Asia/Tokyo (JST)' },
  { value: 'Asia/Seoul', label: 'Asia/Seoul (KST)' },
  { value: 'Australia/Sydney', label: 'Australia/Sydney (AEST)' },
  { value: 'Pacific/Auckland', label: 'Pacific/Auckland (NZST)' },
  { value: 'Pacific/Honolulu', label: 'Pacific/Honolulu (HST)' },
];

const SELECT_CLASS =
  'w-full px-3 py-2 bg-white/5 border border-white/10 rounded-lg text-star-white text-sm ' +
  'focus:outline-none focus:ring-2 focus:ring-cosmic-purple';

export const LocaleSettingsDropdown = () => {
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const { currency, use12Hour, timezone, setCurrency, setUse12Hour, setTimezone } =
    useLocaleSettings();

  // Close on outside click
  useEffect(() => {
    if (!isOpen) return;
    const handleOutsideClick = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener('mousedown', handleOutsideClick);
    return () => document.removeEventListener('mousedown', handleOutsideClick);
  }, [isOpen]);

  // Close on Escape
  useEffect(() => {
    if (!isOpen) return;
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setIsOpen(false);
    };
    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [isOpen]);

  return (
    <div ref={containerRef} className="relative">
      {/* Gear button */}
      <button
        onClick={() => setIsOpen((prev) => !prev)}
        aria-label="Locale settings"
        aria-expanded={isOpen}
        className={`p-2 rounded-lg transition-colors ${
          isOpen
            ? 'bg-cosmic-purple/20 text-cosmic-purple'
            : 'text-star-white/70 hover:text-star-white hover:bg-white/5'
        }`}
      >
        <Settings size={20} />
      </button>

      {/* Dropdown panel */}
      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ opacity: 0, y: -8, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -8, scale: 0.97 }}
            transition={{ duration: 0.15 }}
            className={
              'absolute right-0 top-full mt-2 z-50 ' +
              'w-screen max-w-xs sm:max-w-sm ' +
              'bg-space-dark/95 backdrop-blur-xl ' +
              'border border-white/10 rounded-2xl shadow-2xl shadow-cosmic-purple/20 ' +
              'p-5 space-y-5'
            }
          >
            {/* Panel title */}
            <div className="flex items-center gap-2 pb-3 border-b border-white/10">
              <Settings size={16} className="text-cosmic-purple" />
              <span className="text-sm font-semibold text-star-white">Display Settings</span>
            </div>

            {/* Currency */}
            <div className="space-y-2">
              <label className="text-xs font-medium text-star-white/70 uppercase tracking-wide">
                Currency
              </label>
              <select
                value={currency}
                onChange={(e) => setCurrency(e.target.value as SupportedCurrency)}
                className={SELECT_CLASS}
              >
                {CURRENCIES.map(({ code, label }) => (
                  <option key={code} value={code} className="bg-space-dark text-star-white">
                    {label}
                  </option>
                ))}
              </select>
            </div>

            {/* Time Format */}
            <div className="space-y-2">
              <label className="text-xs font-medium text-star-white/70 uppercase tracking-wide">
                Time Format
              </label>
              <div className="flex gap-2">
                <button
                  onClick={() => setUse12Hour(true)}
                  className={`flex-1 px-3 py-2 rounded-lg text-sm font-medium transition-all ${
                    use12Hour
                      ? 'bg-cosmic-purple text-white'
                      : 'bg-white/5 text-star-white/70 hover:bg-white/10'
                  }`}
                >
                  12-hour (AM/PM)
                </button>
                <button
                  onClick={() => setUse12Hour(false)}
                  className={`flex-1 px-3 py-2 rounded-lg text-sm font-medium transition-all ${
                    !use12Hour
                      ? 'bg-cosmic-purple text-white'
                      : 'bg-white/5 text-star-white/70 hover:bg-white/10'
                  }`}
                >
                  24-hour
                </button>
              </div>
            </div>

            {/* Timezone */}
            <div className="space-y-2">
              <label className="text-xs font-medium text-star-white/70 uppercase tracking-wide">
                Timezone
              </label>
              <select
                value={timezone}
                onChange={(e) => setTimezone(e.target.value)}
                className={SELECT_CLASS}
              >
                {TIMEZONES.map(({ value, label }) => (
                  <option key={value} value={value} className="bg-space-dark text-star-white">
                    {label}
                  </option>
                ))}
              </select>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};

// Made with Bob
