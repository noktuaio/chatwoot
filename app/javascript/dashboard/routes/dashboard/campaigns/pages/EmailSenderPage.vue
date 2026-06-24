<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import EmailSenderDomainDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailSender/EmailSenderDomainDialog.vue';
import EmailSenderIdentityCard from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailSender/EmailSenderIdentityCard.vue';

const { t } = useI18n();
const store = useStore();
const [showDialog, toggleDialog] = useToggle();

const identities = useMapGetter('emailSenderIdentities/getIdentities');
const uiFlags = useMapGetter('emailSenderIdentities/getUIFlags');
const globalConfig = useMapGetter('globalConfig/get');

const enabled = computed(
  () =>
    globalConfig.value?.emailCampaignEnabled === true &&
    globalConfig.value?.crmKanbanEnabled === true
);
const isFetching = computed(() => uiFlags.value.isFetching);

const hasPending = computed(() =>
  identities.value.some(
    identity => identity.status === 'pending' || identity.status === 'verifying'
  )
);

const fetchIdentities = () =>
  enabled.value
    ? store.dispatch('emailSenderIdentities/get')
    : Promise.resolve();

// Re-check verification automatically while any domain is still pending, so the
// green check appears on its own (the backend poll job updates the status).
const pollTimer = ref(null);

const stopPolling = () => {
  if (pollTimer.value) {
    clearInterval(pollTimer.value);
    pollTimer.value = null;
  }
};

const startPolling = () => {
  if (pollTimer.value) return;
  pollTimer.value = setInterval(async () => {
    await fetchIdentities();
    if (!hasPending.value) stopPolling();
  }, 20000);
};

const refresh = async () => {
  await fetchIdentities();
  if (hasPending.value) startPolling();
  else stopPolling();
};

const removeIdentity = async id => {
  try {
    await store.dispatch('emailSenderIdentities/delete', id);
    useAlert(t('CAMPAIGN.EMAIL_SENDER.ACTIONS.DELETE_SUCCESS'));
    refresh();
  } catch (error) {
    const message =
      error?.response?.status === 422
        ? t('CAMPAIGN.EMAIL_SENDER.ACTIONS.DELETE_IN_USE')
        : t('CAMPAIGN.EMAIL_SENDER.ACTIONS.ERROR');
    useAlert(message);
  }
};

onMounted(() => {
  refresh();
});

onUnmounted(() => {
  stopPolling();
});
</script>

<template>
  <CampaignLayout
    :header-title="t('CAMPAIGN.EMAIL_SENDER.HEADER_TITLE')"
    :button-label="t('CAMPAIGN.EMAIL_SENDER.NEW_DOMAIN')"
    @click="toggleDialog()"
    @close="toggleDialog(false)"
  >
    <template #action>
      <EmailSenderDomainDialog
        v-if="showDialog"
        @created="refresh()"
        @close="toggleDialog(false)"
      />
    </template>

    <div class="flex flex-col gap-4">
      <p class="max-w-3xl mb-0 text-sm leading-5 text-n-slate-11">
        {{ t('CAMPAIGN.EMAIL_SENDER.DESCRIPTION') }}
      </p>

      <div
        v-if="isFetching"
        class="flex items-center justify-center py-10 text-n-slate-11"
      >
        <Spinner />
      </div>

      <div
        v-else-if="identities.length === 0"
        class="flex flex-col items-center justify-center gap-2 py-16 text-center border rounded-lg border-n-weak"
      >
        <p class="mb-0 text-base font-medium text-n-slate-12">
          {{ t('CAMPAIGN.EMAIL_SENDER.EMPTY_STATE.TITLE') }}
        </p>
        <p class="max-w-xl mb-0 text-sm leading-5 text-n-slate-11">
          {{ t('CAMPAIGN.EMAIL_SENDER.EMPTY_STATE.SUBTITLE') }}
        </p>
      </div>

      <div v-else class="flex flex-col gap-4">
        <EmailSenderIdentityCard
          v-for="identity in identities"
          :key="identity.id"
          :identity="identity"
          @delete="removeIdentity"
          @checked="refresh"
        />
      </div>
    </div>
  </CampaignLayout>
</template>
