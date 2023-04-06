/* We used to use localStorage for some client-side preferences in the past.
 * Only clear the most recent one (the stupid April fools joke), the last use
 * of localStorage before that was long enough ago that it's most likely been
 * cleared for everyone already (43ef1a26d68f2b5dbc8b5ac3cc30e27b7bf89ca3) */
if(window.localStorage) window.localStorage.removeItem('fools6');
