import { format, parseISO } from 'date-fns';

/**
 * Apply a timezone offset to a UTC Date, returning a new Date whose
 * local fields (hours, minutes, …) match the wall-clock time in that zone.
 * Falls back to the original date if the timezone string is invalid.
 */
const applyTimezone = (date: Date, timezone?: string): Date => {
  if (!timezone) return date;
  try {
    // Use Intl to get the UTC offset for this timezone at this instant,
    // then shift the date so date-fns `format` sees the correct local time.
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    });
    const parts = formatter.formatToParts(date);
    const get = (type: string) =>
      parseInt(parts.find((p) => p.type === type)?.value ?? '0', 10);
    // Build a Date from the zoned wall-clock values (treated as UTC by Date.UTC)
    const zonedMs = Date.UTC(
      get('year'),
      get('month') - 1,
      get('day'),
      get('hour') === 24 ? 0 : get('hour'),
      get('minute'),
      get('second')
    );
    return new Date(zonedMs);
  } catch {
    return date;
  }
};

/**
 * Format a date string to a readable format
 * @param dateString ISO date string
 * @param formatString date-fns format string (default: 'MMM dd, yyyy HH:mm')
 * @param timezone IANA timezone string (e.g. 'America/New_York'). Defaults to local time.
 */
export const formatDate = (
  dateString: string,
  formatString: string = 'MMM dd, yyyy HH:mm',
  timezone?: string
): string => {
  try {
    const date = applyTimezone(parseISO(dateString), timezone);
    return format(date, formatString);
  } catch (error) {
    console.error('Error formatting date:', error);
    return dateString;
  }
};

/**
 * Format date to short format (e.g., "Jan 1, 2099")
 */
export const formatDateShort = (dateString: string): string => {
  return formatDate(dateString, 'MMM dd, yyyy');
};

/**
 * Format time only (e.g., "09:00" or "09:00 AM")
 * @param dateString ISO date string
 * @param use12Hour When true, uses 12-hour clock with AM/PM (default: false)
 * @param timezone IANA timezone string. Defaults to local time.
 */
export const formatTime = (
  dateString: string,
  use12Hour: boolean = false,
  timezone?: string
): string => {
  const formatString = use12Hour ? 'hh:mm a' : 'HH:mm';
  return formatDate(dateString, formatString, timezone);
};

/**
 * Format currency
 * @param amount Amount in dollars
 * @param currency ISO 4217 currency code (default: 'USD')
 * @param locale BCP 47 locale string (default: 'en-US')
 */
export const formatCurrency = (
  amount: number,
  currency: string = 'USD',
  locale: string = 'en-US'
): string => {
  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency,
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(amount);
};

/**
 * Format large numbers with commas
 */
export const formatNumber = (num: number): string => {
  return new Intl.NumberFormat('en-US').format(num);
};

/**
 * Get relative time (e.g., "2 hours ago")
 */
export const getRelativeTime = (dateString: string): string => {
  try {
    const date = parseISO(dateString);
    const now = new Date();
    const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);

    if (diffInSeconds < 60) return 'just now';
    if (diffInSeconds < 3600) return `${Math.floor(diffInSeconds / 60)} minutes ago`;
    if (diffInSeconds < 86400) return `${Math.floor(diffInSeconds / 3600)} hours ago`;
    if (diffInSeconds < 2592000) return `${Math.floor(diffInSeconds / 86400)} days ago`;
    return formatDateShort(dateString);
  } catch {
    return dateString;
  }
};

/**
 * Calculate flight duration in hours
 */
export const calculateDuration = (
  departureTime: string,
  arrivalTime: string
): string => {
  try {
    const departure = parseISO(departureTime);
    const arrival = parseISO(arrivalTime);
    const diffInHours = (arrival.getTime() - departure.getTime()) / (1000 * 60 * 60);
    
    if (diffInHours < 1) {
      return `${Math.round(diffInHours * 60)} min`;
    }
    
    const hours = Math.floor(diffInHours);
    const minutes = Math.round((diffInHours - hours) * 60);
    
    if (minutes === 0) {
      return `${hours}h`;
    }
    
    return `${hours}h ${minutes}m`;
  } catch {
    return 'N/A';
  }
};

// Made with Bob
