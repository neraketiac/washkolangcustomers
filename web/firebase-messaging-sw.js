// Firebase Messaging Service Worker — required for background push notifications
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
  const title = payload.notification?.title ?? '🛵 Rider Update';
  const body  = payload.notification?.body  ?? 'Rider is now available!';
  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  });
});
