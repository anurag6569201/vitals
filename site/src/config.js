// Fill these in once — every page and button uses them.
export const APP_STORE_URL = 'https://apps.apple.com/app/id6817354726';
export const SUPPORT_EMAIL = 'support@vitalsformac.com';
export const SITE_URL = 'https://vitalsformac.com';
/** Full (direct-download) edition. scripts/release.sh copies each notarized build to public/vitals/Vitals.dmg. */
export const DOWNLOAD_URL = '/vitals/Vitals.dmg';
/** Lemon Squeezy checkout for a license key. Until it's set, the full version is unlocked with an App Store purchase's key. */
export const BUY_URL = 'https://vitals.lemonsqueezy.com/buy/REPLACE-WITH-YOUR-PRODUCT';
export const canBuyDirect = !BUY_URL.includes('REPLACE');

export const PRICE = '$9.99';
export const TRIAL_DAYS = 7;
export const MIN_MACOS = 'macOS 14 Sonoma';
