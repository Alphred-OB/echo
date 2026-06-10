// Echo Key service worker — cache static shell for offline-capable startup.
// API calls always go to the network.
// Scope: /phone/ — serves only the phone PWA assets.
const CACHE = 'echo-phone-v1';
const ASSETS = [
  '/phone/phone.html',
  '/phone/manifest.webmanifest',
  '/phone/icon-192.png',
  '/phone/icon-512.png',
  '/echo.css',
  '/ggwave.js',
  '/icons.js'
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (url.pathname.startsWith('/api/') || url.pathname === '/ws') return; // network only
  if (e.request.method !== 'GET') return;
  e.respondWith(
    caches.match(e.request, { ignoreSearch: url.pathname.endsWith('phone.html') })
      .then(hit => hit || fetch(e.request).then(r => {
        const copy = r.clone();
        caches.open(CACHE).then(c => c.put(e.request, copy));
        return r;
      }))
  );
});
