<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import CreationStatusRow from './CreationStatusRow.vue';

const POLL_INTERVAL = 5000;

const { t } = useI18n();
const store = useStore();

// The web widget inbox is created asynchronously during account setup. We poll
// the inboxes endpoint until it shows up, then stop — much simpler than the
// event-driven help center flow.
const websiteInboxes = useMapGetter('inboxes/getWebsiteInboxes');
const isReady = computed(() => websiteInboxes.value.length > 0);

let timer = null;
const isFetching = ref(false);

const stopPolling = () => {
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
};

const poll = async () => {
  if (isFetching.value) return;
  isFetching.value = true;
  try {
    await store.dispatch('inboxes/get');
  } finally {
    isFetching.value = false;
  }
  if (isReady.value) stopPolling();
};

onMounted(() => {
  poll();
  if (!isReady.value) timer = setInterval(poll, POLL_INTERVAL);
});

onBeforeUnmount(stopPolling);
</script>

<template>
  <CreationStatusRow
    :ready="isReady"
    :title="t('ONBOARDING_INBOX_SETUP.CREATED_FOR_YOU.LIVE_CHAT')"
    :description="
      t('ONBOARDING_INBOX_SETUP.CREATED_FOR_YOU.LIVE_CHAT_DESCRIPTION')
    "
    :status="
      isReady
        ? t('ONBOARDING_INBOX_SETUP.CREATED_FOR_YOU.LIVE_CHAT_READY')
        : t('ONBOARDING_INBOX_SETUP.CREATED_FOR_YOU.LIVE_CHAT_STATUS')
    "
  />
</template>
