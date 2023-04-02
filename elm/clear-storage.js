/* We used to use localStorage for some client-side preferences, no need to
 * keep that data around now that that feature is gone. */
if(window.localStorage) window.localStorage.clear();
