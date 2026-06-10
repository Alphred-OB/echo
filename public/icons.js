// Echo icon sprite (Feather-style outline icons, stroke currentColor).
// Include right after <body>; use: <svg class="ic"><use href="#i-key"/></svg>
document.currentScript.insertAdjacentHTML('afterend', `
<svg xmlns="http://www.w3.org/2000/svg" style="display:none" aria-hidden="true">
<symbol id="i-phone" viewBox="0 0 24 24"><rect x="6" y="2" width="12" height="20" rx="2.5"/><line x1="11" y1="18.5" x2="13" y2="18.5"/></symbol>
<symbol id="i-shield" viewBox="0 0 24 24"><path d="M12 22s8-3.5 8-10V5l-8-3-8 3v7c0 6.5 8 10 8 10z"/></symbol>
<symbol id="i-shield-check" viewBox="0 0 24 24"><path d="M12 22s8-3.5 8-10V5l-8-3-8 3v7c0 6.5 8 10 8 10z"/><polyline points="9 11.5 11.5 14 15.5 9.5"/></symbol>
<symbol id="i-key" viewBox="0 0 24 24"><circle cx="7.5" cy="15.5" r="4.5"/><path d="M10.8 12.2 21 2m-4 4 3 3"/></symbol>
<symbol id="i-refresh" viewBox="0 0 24 24"><polyline points="23 4 23 10 17 10"/><path d="M20.5 15a9 9 0 1 1-2-9.5L23 10"/></symbol>
<symbol id="i-plus" viewBox="0 0 24 24"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></symbol>
<symbol id="i-x" viewBox="0 0 24 24"><line x1="6" y1="6" x2="18" y2="18"/><line x1="18" y1="6" x2="6" y2="18"/></symbol>
<symbol id="i-check" viewBox="0 0 24 24"><polyline points="4.5 12.5 9.5 17.5 19.5 7"/></symbol>
<symbol id="i-alert" viewBox="0 0 24 24"><path d="M10.3 3.9 1.8 18.1A2 2 0 0 0 3.5 21h17a2 2 0 0 0 1.7-2.9L13.7 3.9a2 2 0 0 0-3.4 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></symbol>
<symbol id="i-clock" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9.5"/><polyline points="12 7 12 12 15.5 14"/></symbol>
<symbol id="i-mic" viewBox="0 0 24 24"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v1a7 7 0 0 0 14 0v-1"/><line x1="12" y1="18" x2="12" y2="22"/></symbol>
<symbol id="i-volume" viewBox="0 0 24 24"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13"/></symbol>
<symbol id="i-user" viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 3.6-6.5 8-6.5s8 2.5 8 6.5"/></symbol>
<symbol id="i-logout" viewBox="0 0 24 24"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></symbol>
<symbol id="i-activity" viewBox="0 0 24 24"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></symbol>
<symbol id="i-copy" viewBox="0 0 24 24"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></symbol>
<symbol id="i-arrow-right" viewBox="0 0 24 24"><line x1="4" y1="12" x2="20" y2="12"/><polyline points="13 5 20 12 13 19"/></symbol>
<symbol id="i-ruler" viewBox="0 0 24 24"><rect x="2" y="9" width="20" height="6" rx="1.5"/><line x1="6.5" y1="9" x2="6.5" y2="12"/><line x1="11" y1="9" x2="11" y2="12"/><line x1="15.5" y1="9" x2="15.5" y2="12"/></symbol>
<symbol id="i-bell" viewBox="0 0 24 24"><path d="M18 9a6 6 0 1 0-12 0c0 7-3 8-3 8h18s-3-1-3-8"/><path d="M10.5 21a2 2 0 0 0 3 0"/></symbol>
<symbol id="i-download" viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></symbol>
</svg>`);
