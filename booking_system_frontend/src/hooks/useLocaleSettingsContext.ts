import { createContext, useContext } from 'react';
import type { LocaleSettingsContextType } from '../types';

export const LocaleSettingsContext = createContext<LocaleSettingsContextType | undefined>(undefined);

export const useLocaleSettings = (): LocaleSettingsContextType => {
  const context = useContext(LocaleSettingsContext);
  if (context === undefined) {
    throw new Error('useLocaleSettings must be used within a LocaleSettingsProvider');
  }
  return context;
};

// Made with Bob
