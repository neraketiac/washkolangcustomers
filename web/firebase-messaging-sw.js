importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyAY9RKLaW6ngSCHvQqiujNxpRwJ9kzssgU",
  authDomain: "zpos-d985c.firebaseapp.com",
  projectId: "zpos-d985c",
  storageBucket: "zpos-d985c.firebasestorage.app",
  messagingSenderId: "368198382683",
  appId: "1:368198382683:web:1c00691fe118faa041fb7e"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.data?.title ?? '🛵 Rider Update';
  const body  = payload.data?.body  ?? 'Rider is now available!';
  const url   = payload.data?.url ?? 'https://washkolang.online';

  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: 'rider-status',       // replaces previous notification instead of stacking
    renotify: true,            // still vibrates/sounds even if replacing same tag
    data: { url },
  });
});

// Open or focus the app when notification is tapped
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = event.notification.data?.url ?? 'https://washkolang.online';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if (client.url.startsWith('https://washkolang.online') && 'focus' in client) {
          return client.focus();
        }
      }
      return clients.openWindow(url);
    })
  );
});
