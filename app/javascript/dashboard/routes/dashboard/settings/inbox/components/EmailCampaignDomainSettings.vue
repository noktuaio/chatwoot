<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import EmailSenderIdentityCard from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailSender/EmailSenderIdentityCard.vue';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();

const identities = useMapGetter('emailSenderIdentities/getIdentities');
const uiFlags = useMapGetter('emailSenderIdentities/getUIFlags');

const domain = computed(() => {
  const email = props.inbox?.email || '';
  return email.includes('@') ? email.split('@').pop().toLowerCase() : '';
});

// Webmail público não pode ser autenticado para disparo (você não controla o DNS
// dele). Campanha exige um domínio PRÓPRIO com SPF/DKIM/DMARC.
const WEBMAIL_DOMAINS = [
  'gmail.com',
  'googlemail.com',
  'hotmail.com',
  'hotmail.com.br',
  'outlook.com',
  'outlook.com.br',
  'live.com',
  'msn.com',
  'yahoo.com',
  'yahoo.com.br',
  'ymail.com',
  'icloud.com',
  'me.com',
  'mac.com',
  'aol.com',
  'gmx.com',
  'proton.me',
  'protonmail.com',
  'bol.com.br',
  'uol.com.br',
  'terra.com.br',
];
const isWebmailDomain = computed(() => WEBMAIL_DOMAINS.includes(domain.value));

const identity = computed(() =>
  identities.value.find(item => item.domain === domain.value)
);

const isVerified = computed(() => identity.value?.status === 'verified');

const isPending = computed(
  () =>
    identity.value?.status === 'pending' ||
    identity.value?.status === 'verifying'
);

// Re-check verification automatically while the domain is still pending.
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
    await store.dispatch('emailSenderIdentities/get');
    if (!isPending.value) stopPolling();
  }, 20000);
};

const refresh = async () => {
  await store.dispatch('emailSenderIdentities/get');
  if (isPending.value) startPolling();
  else stopPolling();
};

const provision = async () => {
  try {
    await store.dispatch('emailSenderIdentities/create', {
      domain: domain.value,
      from_email: props.inbox.email,
    });
    useAlert(t('CAMPAIGN.EMAIL_SENDER.DIALOG.SUCCESS'));
    refresh();
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_SENDER.DIALOG.ERROR'));
  }
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
  if (domain.value && !isWebmailDomain.value) refresh();
});

onUnmounted(() => {
  stopPolling();
});
</script>

<template>
  <SettingsFieldSection
    :label="t('CAMPAIGN.EMAIL_SENDER.INBOX_SECTION.TITLE')"
    :help-text="t('CAMPAIGN.EMAIL_SENDER.INBOX_SECTION.HELP')"
  >
    <div class="flex flex-col gap-3">
      <div
        v-if="isWebmailDomain"
        class="px-3 py-2 outline outline-1 -outline-offset-1 bg-n-amber-3 outline-n-amber-4 text-n-amber-11 rounded-xl"
      >
        <p class="mb-0 text-body-para">
          {{ t('CAMPAIGN.EMAIL_SENDER.INBOX_SECTION.WEBMAIL', { domain }) }}
        </p>
      </div>

      <template v-else>
        <div
          v-if="!isVerified"
          class="px-3 py-2 outline outline-1 -outline-offset-1 bg-n-amber-3 outline-n-amber-4 text-n-amber-11 rounded-xl"
        >
          <p class="mb-0 text-body-para">
            {{ t('CAMPAIGN.EMAIL_SENDER.INBOX_SECTION.WARNING') }}
          </p>
        </div>

        <div
          v-if="isVerified"
          class="px-3 py-2 outline outline-1 -outline-offset-1 bg-n-teal-3 outline-n-teal-4 text-n-teal-11 rounded-xl"
        >
          <p class="mb-0 text-body-para">
            {{ t('CAMPAIGN.EMAIL_SENDER.INBOX_SECTION.VERIFIED') }}
          </p>
        </div>

        <EmailSenderIdentityCard
          v-if="identity"
          :identity="identity"
          @delete="removeIdentity"
          @checked="refresh"
        />

        <div v-else class="flex flex-col items-start gap-2">
          <p class="mb-0 text-sm leading-5 text-n-slate-11">
            {{
              t('CAMPAIGN.EMAIL_SENDER.INBOX_SECTION.NOT_CONFIGURED', {
                domain,
              })
            }}
          </p>
          <Button
            :label="t('CAMPAIGN.EMAIL_SENDER.INBOX_SECTION.SETUP')"
            icon="i-lucide-shield-check"
            color="blue"
            size="sm"
            :is-loading="uiFlags.isCreating"
            @click="provision"
          />
        </div>
      </template>
    </div>
  </SettingsFieldSection>
</template>
