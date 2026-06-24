import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import App from '../public_booking/App.vue';
import i18nMessages from '../public_booking/i18n';

const app = createApp(App);

const resolveLocale = () => {
  const browserLocale = (window.navigator.language || 'en').replace('-', '_');
  if (i18nMessages[browserLocale]) return browserLocale;
  const base = browserLocale.split('_')[0];
  return i18nMessages[base] ? base : 'en';
};
const locale = resolveLocale();

const i18n = createI18n({
  // App.vue uses the Composition API (`useI18n()`), so the instance MUST run in
  // Composition mode — otherwise `useI18n()` resolves against the legacy path and
  // the message resolver throws at setup. Mirrors the dashboard entrypoint.
  legacy: false,
  locale,
  fallbackLocale: 'en',
  messages: i18nMessages,
});

app.use(i18n);

window.onload = () => {
  app.mount('#app');
};
