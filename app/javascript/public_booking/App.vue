<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { getProfile, getSlots, createBooking, confirmBooking } from './api';

const { t } = useI18n();

const globalConfig = window.globalConfig || {};
const installationName = globalConfig.INSTALLATION_NAME || '';
const logo = globalConfig.LOGO_THUMBNAIL || '';

// Paths: /book/:slug  OR  /book/:slug/confirm?token=...
const pathSegments = window.location.pathname.split('/').filter(Boolean);
const isConfirmPath =
  pathSegments[pathSegments.length - 1] === 'confirm' &&
  pathSegments.length >= 3;

const slug = computed(() => {
  if (isConfirmPath) return pathSegments[pathSegments.length - 2];
  return pathSegments[pathSegments.length - 1];
});

const confirmToken =
  new URLSearchParams(window.location.search).get('token') || '';

const EMAIL_REGEX = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
// Honeypot label kept off the i18n bundle on purpose — it must look like a real
// field name to bots while staying invisible to humans.
const honeypotLabel = 'Company';

const isLoadingProfile = ref(true);
const notFound = ref(false);
const profile = ref(null);

const selectedDate = ref('');
const slots = ref([]);
const isLoadingSlots = ref(false);
const selectedSlot = ref('');

const name = ref('');
const email = ref('');
const company = ref(''); // honeypot — must stay empty
const formLoadedAt = ref(0);

const isSubmitting = ref(false);
const isConfirmed = ref(false);
const joinUrl = ref('');
const confirmedTime = ref('');
const formError = ref('');

// Email-verification flow state.
const verificationSent = ref(false);
const isConfirming = ref(false);
const confirmError = ref(false);

const formatDateLabel = date =>
  new Intl.DateTimeFormat(undefined, {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  }).format(date);

const formatTime = iso =>
  new Intl.DateTimeFormat(undefined, {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));

const formatFull = iso =>
  new Intl.DateTimeFormat(undefined, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));

// Build the next N days (within the profile booking window) for the date picker.
const availableDates = computed(() => {
  if (!profile.value) return [];
  const days = Math.min(profile.value.booking_window_days || 14, 60);
  const out = [];
  const today = new Date();
  for (let i = 0; i <= days; i += 1) {
    const d = new Date(today);
    d.setDate(today.getDate() + i);
    const iso = d.toISOString().slice(0, 10);
    out.push({ iso, label: formatDateLabel(d) });
  }
  return out;
});

const durationLabel = computed(() =>
  profile.value
    ? t('BOOKING.DURATION', { minutes: profile.value.duration_minutes })
    : ''
);

const canConfirm = computed(
  () =>
    !!selectedSlot.value &&
    !!name.value.trim() &&
    EMAIL_REGEX.test(email.value.trim())
);

async function selectDate(date) {
  selectedDate.value = date;
  selectedSlot.value = '';
  isLoadingSlots.value = true;
  slots.value = [];
  try {
    const data = await getSlots(slug.value, date);
    slots.value = data.slots || [];
  } catch (e) {
    slots.value = [];
  } finally {
    isLoadingSlots.value = false;
  }
}

async function loadProfile() {
  isLoadingProfile.value = true;
  try {
    profile.value = await getProfile(slug.value);
    if (availableDates.value.length) {
      await selectDate(availableDates.value[0].iso);
    }
  } catch (e) {
    notFound.value = true;
  } finally {
    isLoadingProfile.value = false;
    formLoadedAt.value = Date.now();
  }
}

function selectSlot(iso) {
  selectedSlot.value = iso;
  formError.value = '';
}

async function confirm() {
  formError.value = '';
  if (!name.value.trim()) {
    formError.value = t('BOOKING.ERROR_NAME');
    return;
  }
  if (!EMAIL_REGEX.test(email.value.trim())) {
    formError.value = t('BOOKING.ERROR_EMAIL');
    return;
  }
  if (!selectedSlot.value) {
    formError.value = t('BOOKING.ERROR_SLOT');
    return;
  }

  isSubmitting.value = true;
  try {
    // STEP 1: request an email-verification link. NO meeting is created yet.
    await createBooking(slug.value, {
      name: name.value.trim(),
      email: email.value.trim(),
      starts_at: selectedSlot.value,
      company: company.value, // honeypot
      form_loaded_at: formLoadedAt.value,
    });
    verificationSent.value = true;
  } catch (e) {
    formError.value = t('BOOKING.ERROR_GENERIC');
    // The slot may have just been taken — refresh availability.
    if (selectedDate.value) selectDate(selectedDate.value);
  } finally {
    isSubmitting.value = false;
  }
}

// STEP 2: the booker opened the email link (/book/:slug/confirm?token=...).
async function runConfirm() {
  isConfirming.value = true;
  confirmError.value = false;
  try {
    const data = await confirmBooking(slug.value, confirmToken);
    isConfirmed.value = true;
    joinUrl.value = data.join_url || '';
    confirmedTime.value = data.starts_at || '';
  } catch (e) {
    confirmError.value = true;
  } finally {
    isConfirming.value = false;
    isLoadingProfile.value = false;
  }
}

function reset() {
  isConfirmed.value = false;
  joinUrl.value = '';
  confirmedTime.value = '';
  selectedSlot.value = '';
  formError.value = '';
  verificationSent.value = false;
  formLoadedAt.value = Date.now();
  if (selectedDate.value) selectDate(selectedDate.value);
}

onMounted(() => {
  if (isConfirmPath) {
    if (!confirmToken) {
      confirmError.value = true;
      isLoadingProfile.value = false;
      return;
    }
    runConfirm();
    return;
  }
  loadProfile();
});
</script>

<template>
  <div
    class="min-h-screen w-full bg-slate-50 flex flex-col items-center px-4 py-8 sm:py-16"
  >
    <div class="w-full max-w-xl">
      <!-- Brand header (neutral / white-label) -->
      <div class="flex items-center justify-center gap-2 mb-6">
        <img
          v-if="logo"
          :src="logo"
          :alt="installationName"
          class="h-7 w-auto"
        />
        <span v-else class="text-base font-semibold text-slate-700">
          {{ installationName }}
        </span>
      </div>

      <!-- Loading -->
      <div
        v-if="isLoadingProfile && !isConfirming && !confirmError"
        class="bg-white rounded-2xl shadow-sm border border-slate-200 p-10 text-center text-slate-500"
      >
        {{ t('BOOKING.LOADING') }}
      </div>

      <!-- Confirming (email link opened) -->
      <div
        v-else-if="isConfirming"
        class="bg-white rounded-2xl shadow-sm border border-slate-200 p-10 text-center"
      >
        <div
          class="mx-auto mb-4 h-12 w-12 rounded-full bg-slate-100 flex items-center justify-center text-slate-400"
          aria-hidden="true"
        >
          <span class="i-lucide-loader-circle text-2xl animate-spin" />
        </div>
        <h1 class="text-lg font-semibold text-slate-800 mb-2">
          {{ t('BOOKING.CONFIRMING_TITLE') }}
        </h1>
        <p class="text-sm text-slate-500">{{ t('BOOKING.CONFIRMING_DESC') }}</p>
      </div>

      <!-- Confirmation failed (expired / reused / invalid token) -->
      <div
        v-else-if="confirmError"
        class="bg-white rounded-2xl shadow-sm border border-slate-200 p-10 text-center"
      >
        <div
          class="mx-auto mb-4 h-12 w-12 rounded-full bg-red-50 flex items-center justify-center text-red-400"
          aria-hidden="true"
        >
          <span class="i-lucide-calendar-x text-2xl" />
        </div>
        <h1 class="text-lg font-semibold text-slate-800 mb-2">
          {{ t('BOOKING.CONFIRM_ERROR_TITLE') }}
        </h1>
        <p class="text-sm text-slate-500">
          {{ t('BOOKING.CONFIRM_ERROR_DESC') }}
        </p>
      </div>

      <!-- Not found / disabled -->
      <div
        v-else-if="notFound"
        class="bg-white rounded-2xl shadow-sm border border-slate-200 p-10 text-center"
      >
        <div
          class="mx-auto mb-4 h-12 w-12 rounded-full bg-slate-100 flex items-center justify-center text-slate-400"
          aria-hidden="true"
        >
          <span class="i-lucide-calendar-x text-2xl" />
        </div>
        <h1 class="text-lg font-semibold text-slate-800 mb-2">
          {{ t('BOOKING.NOT_FOUND_TITLE') }}
        </h1>
        <p class="text-sm text-slate-500">{{ t('BOOKING.NOT_FOUND_DESC') }}</p>
      </div>

      <!-- Success -->
      <div
        v-else-if="isConfirmed"
        class="bg-white rounded-2xl shadow-sm border border-slate-200 p-8 text-center"
      >
        <div
          class="mx-auto mb-4 h-12 w-12 rounded-full bg-green-100 flex items-center justify-center"
          aria-hidden="true"
        >
          <span class="i-lucide-check text-green-600 text-2xl" />
        </div>
        <h1 class="text-xl font-semibold text-slate-800 mb-1">
          {{ t('BOOKING.SUCCESS_TITLE') }}
        </h1>
        <p class="text-sm text-slate-500 mb-4">
          {{ t('BOOKING.SUCCESS_DESC') }}
        </p>
        <p v-if="confirmedTime" class="text-sm font-medium text-slate-700 mb-5">
          {{ formatFull(confirmedTime) }}
        </p>
        <a
          v-if="joinUrl"
          :href="joinUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex w-full justify-center items-center rounded-lg bg-slate-900 px-4 py-3 text-sm font-medium text-white hover:bg-slate-800 transition mb-3"
        >
          {{ t('BOOKING.JOIN_LINK') }}
        </a>
        <button
          type="button"
          class="text-sm text-slate-500 hover:text-slate-700"
          @click="reset"
        >
          {{ t('BOOKING.BOOK_ANOTHER') }}
        </button>
      </div>

      <!-- Verification email sent (STEP 1 done, awaiting email confirmation) -->
      <div
        v-else-if="verificationSent"
        class="bg-white rounded-2xl shadow-sm border border-slate-200 p-8 text-center"
      >
        <div
          class="mx-auto mb-4 h-12 w-12 rounded-full bg-slate-100 flex items-center justify-center text-slate-500"
          aria-hidden="true"
        >
          <span class="i-lucide-mail text-2xl" />
        </div>
        <h1 class="text-xl font-semibold text-slate-800 mb-2">
          {{ t('BOOKING.VERIFY_SENT_TITLE') }}
        </h1>
        <p class="text-sm text-slate-500">
          {{ t('BOOKING.VERIFY_SENT_DESC') }}
        </p>
      </div>

      <!-- Booking flow -->
      <div
        v-else-if="profile"
        class="bg-white rounded-2xl shadow-sm border border-slate-200 overflow-hidden"
      >
        <!-- Agent header -->
        <div class="px-6 pt-6 pb-4 border-b border-slate-100">
          <p class="text-xs uppercase tracking-wide text-slate-400">
            {{ t('BOOKING.WITH') }}
          </p>
          <h1 class="text-xl font-semibold text-slate-800">
            {{ profile.agent_name }}
          </h1>
          <p
            v-if="profile.title"
            class="text-sm font-medium text-slate-600 mt-0.5"
          >
            {{ profile.title }}
          </p>
          <p v-if="profile.description" class="text-sm text-slate-500 mt-1">
            {{ profile.description }}
          </p>
          <p class="text-xs text-slate-400 mt-2">
            {{ durationLabel }}
            <span aria-hidden="true">·</span>
            {{ profile.timezone }}
          </p>
        </div>

        <div class="p-6 space-y-6">
          <!-- Date picker -->
          <div>
            <p class="text-sm font-medium text-slate-700 mb-2">
              {{ t('BOOKING.PICK_DATE') }}
            </p>
            <div class="flex gap-2 overflow-x-auto pb-1">
              <button
                v-for="d in availableDates"
                :key="d.iso"
                type="button"
                class="shrink-0 rounded-lg border px-3 py-2 text-sm transition"
                :class="
                  selectedDate === d.iso
                    ? 'border-slate-900 bg-slate-900 text-white'
                    : 'border-slate-200 text-slate-600 hover:border-slate-400'
                "
                @click="selectDate(d.iso)"
              >
                {{ d.label }}
              </button>
            </div>
          </div>

          <!-- Time slots -->
          <div>
            <p class="text-sm font-medium text-slate-700 mb-2">
              {{ t('BOOKING.PICK_TIME') }}
            </p>
            <div v-if="isLoadingSlots" class="text-sm text-slate-400 py-4">
              {{ t('BOOKING.SLOTS_LOADING') }}
            </div>
            <div v-else-if="!slots.length" class="text-sm text-slate-400 py-4">
              {{ t('BOOKING.NO_SLOTS') }}
            </div>
            <div v-else class="grid grid-cols-3 sm:grid-cols-4 gap-2">
              <button
                v-for="s in slots"
                :key="s"
                type="button"
                class="rounded-lg border px-2 py-2 text-sm transition"
                :class="
                  selectedSlot === s
                    ? 'border-slate-900 bg-slate-900 text-white'
                    : 'border-slate-200 text-slate-700 hover:border-slate-400'
                "
                @click="selectSlot(s)"
              >
                {{ formatTime(s) }}
              </button>
            </div>
          </div>

          <!-- Details form -->
          <form v-if="selectedSlot" class="space-y-4" @submit.prevent="confirm">
            <div
              class="rounded-lg bg-slate-50 border border-slate-200 px-3 py-2 text-sm text-slate-600"
            >
              <span class="text-slate-400">
                {{ t('BOOKING.SELECTED_TIME') }}
              </span>
              {{ formatFull(selectedSlot) }}
            </div>

            <p class="text-sm font-medium text-slate-700">
              {{ t('BOOKING.YOUR_DETAILS') }}
            </p>

            <div>
              <label
                class="block text-xs text-slate-500 mb-1"
                for="booking-name"
              >
                {{ t('BOOKING.NAME_LABEL') }}
              </label>
              <input
                id="booking-name"
                v-model="name"
                type="text"
                autocomplete="name"
                :placeholder="t('BOOKING.NAME_PLACEHOLDER')"
                class="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-slate-900 focus:outline-none"
              />
            </div>

            <div>
              <label
                class="block text-xs text-slate-500 mb-1"
                for="booking-email"
              >
                {{ t('BOOKING.EMAIL_LABEL') }}
              </label>
              <input
                id="booking-email"
                v-model="email"
                type="email"
                autocomplete="email"
                :placeholder="t('BOOKING.EMAIL_PLACEHOLDER')"
                class="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-slate-900 focus:outline-none"
              />
            </div>

            <!-- Honeypot: visually hidden, off-screen, ignored by humans -->
            <div class="hidden" aria-hidden="true">
              <input
                v-model="company"
                type="text"
                name="company"
                :aria-label="honeypotLabel"
                tabindex="-1"
                autocomplete="off"
              />
            </div>

            <p v-if="formError" class="text-sm text-red-600">{{ formError }}</p>

            <button
              type="submit"
              :disabled="!canConfirm || isSubmitting"
              class="w-full rounded-lg bg-slate-900 px-4 py-3 text-sm font-medium text-white hover:bg-slate-800 transition disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {{
                isSubmitting ? t('BOOKING.CONFIRMING') : t('BOOKING.CONFIRM')
              }}
            </button>
          </form>
        </div>
      </div>
    </div>
  </div>
</template>

<style lang="scss">
// Standalone public bundle: pull in Tailwind (base/components/utilities) so the
// page is styled outside the dashboard. Mirrors the survey entrypoint.
@import './assets/tailwind.scss';
</style>
