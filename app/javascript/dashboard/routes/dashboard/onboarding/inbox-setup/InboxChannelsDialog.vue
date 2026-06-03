<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import { useChannelConnect } from './useChannelConnect';
import { CHANNEL_LIST } from './constants';
import { isChannelConnected } from './channelMatchers';
import InboxChannelForm from './InboxChannelForm.vue';
import InboxFacebookForm from './InboxFacebookForm.vue';

const props = defineProps({
  inboxes: { type: Array, default: () => [] },
});

const emit = defineEmits(['connected']);

const { t } = useI18n();
const { connectViaOAuth, connectWhatsapp } = useChannelConnect();
const globalConfig = useMapGetter('globalConfig/get');

// Maps the dialog's display types to the OAuth client key the flow expects.
// Types without an entry (manual-setup channels) are no-ops for now.
const OAUTH_PROVIDERS = {
  gmail: 'google',
  outlook: 'microsoft',
  instagram: 'instagram',
  tiktok: 'tiktok',
};

// OAuth channels need installation-level app credentials to be usable. When the
// credential is missing the channel is "not configured" — shown muted and not
// clickable. Mirrors the availability checks in ChannelItem.vue.
const installationConfig = window.chatwootConfig || {};
const CHANNEL_CONFIGURED = {
  // WhatsApp is onboarded only via Meta embedded signup, which needs both the
  // app id (not the 'none' sentinel) and the signup configuration id.
  whatsapp: () =>
    Boolean(installationConfig.whatsappAppId) &&
    installationConfig.whatsappAppId !== 'none' &&
    Boolean(installationConfig.whatsappConfigurationId),
  facebook: () => Boolean(installationConfig.fbAppId),
  instagram: () => Boolean(installationConfig.instagramAppId),
  tiktok: () => Boolean(installationConfig.tiktokAppId),
  gmail: () => Boolean(installationConfig.googleOAuthClientId),
  outlook: () => Boolean(globalConfig.value.azureAppId),
};

const isConfigured = channel => CHANNEL_CONFIGURED[channel.type]?.() ?? true;

// A card's availability — what the user can do with it right now:
//   available    — usable now (configured, not deferred)
//   unconfigured — a real channel whose installation credential is missing
//   setupLater   — deferred to in-app setup (SMS/API/Voice/Email cards)
// `connected` (a real inbox already backs it) is orthogonal and tracked
// separately, since a connected channel can still be in any of these states.
const channelAvailability = channel => {
  if (channel.setupLater) return 'setupLater';
  if (!isConfigured(channel)) return 'unconfigured';
  return 'available';
};

const CARD_CLASS = {
  available: 'bg-n-solid-1 hover:outline-n-slate-6 cursor-pointer',
  unconfigured: 'bg-n-solid-1 opacity-50 cursor-not-allowed',
  setupLater: 'bg-n-slate-2 cursor-not-allowed',
};

// Decorate the catalog with per-render state so the template reads plain fields
// rather than calling predicates for each card.
const channelCards = computed(() =>
  CHANNEL_LIST.map(channel => ({
    ...channel,
    availability: channelAvailability(channel),
    connected: isChannelConnected(props.inboxes, channel.inbox),
  }))
);

const dialogRef = ref(null);

// Credential-form channels (Line, Telegram) and Facebook swap the grid for an
// inline view; OAuth channels redirect; the rest are no-ops for now.
const selectedChannel = ref(null);

// An inbox was created by an in-dialog form (Line/Telegram credentials or the
// Facebook page picker); close the dialog (its @close resets the form view) and
// let the parent refetch so the connected state and real channel icons update.
const onCreated = () => {
  dialogRef.value?.close();
  emit('connected');
};

const onCardClick = channel => {
  if (channel.availability !== 'available') return;
  if (channel.form) {
    selectedChannel.value = channel;
    return;
  }
  // WhatsApp uses Meta's embedded-signup popup, not the redirect OAuth flow.
  if (channel.type === 'whatsapp') {
    connectWhatsapp();
    return;
  }
  // Facebook swaps to an in-dialog page picker (FB.login → choose a Page).
  if (channel.type === 'facebook') {
    selectedChannel.value = channel;
    return;
  }
  connectViaOAuth(OAUTH_PROVIDERS[channel.type]);
};

const dialogTitle = computed(() =>
  selectedChannel.value
    ? t('ONBOARDING_INBOX_SETUP.CHANNELS_DIALOG.CONNECT_TITLE', {
        name: selectedChannel.value.label,
      })
    : t('ONBOARDING_INBOX_SETUP.CHANNELS_DIALOG.TITLE')
);

const dialogDescription = computed(() => {
  if (!selectedChannel.value) {
    return t('ONBOARDING_INBOX_SETUP.CHANNELS_DIALOG.SUBTITLE');
  }
  if (selectedChannel.value.type === 'facebook') {
    return t('ONBOARDING_INBOX_SETUP.CHANNELS_DIALOG.FACEBOOK_SUBTITLE');
  }
  return t('ONBOARDING_INBOX_SETUP.CHANNELS_DIALOG.CONNECT_SUBTITLE');
});

const open = preselectType => {
  const entry = preselectType
    ? channelCards.value.find(channel => channel.type === preselectType)
    : null;
  // Only jump straight into a channel's view when it's actually usable;
  // otherwise show the grid (with its muted card) rather than launching SDK
  // auth with a missing credential.
  selectedChannel.value = entry?.availability === 'available' ? entry : null;
  dialogRef.value?.open();
};
const close = () => dialogRef.value?.close();

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="dialogTitle"
    :description="dialogDescription"
    width="lg"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="selectedChannel = null"
  >
    <InboxFacebookForm
      v-if="selectedChannel?.type === 'facebook'"
      @back="selectedChannel = null"
      @created="onCreated"
    />
    <InboxChannelForm
      v-else-if="selectedChannel"
      :channel="selectedChannel"
      @back="selectedChannel = null"
      @created="onCreated"
    />
    <template v-else>
      <div class="grid grid-cols-2 gap-3">
        <button
          v-for="channel in channelCards"
          :key="channel.type"
          type="button"
          :disabled="channel.availability !== 'available'"
          class="flex items-center gap-3 p-3 rounded-xl outline outline-1 outline-n-weak shadow-[0px_1px_2px_0px_rgba(27,28,29,0.036)] transition-colors text-start"
          :class="CARD_CLASS[channel.availability]"
          @click="onCardClick(channel)"
        >
          <div
            class="size-9 rounded-[10px] outline outline-1 outline-n-weak flex items-center justify-center flex-shrink-0"
          >
            <ChannelIcon
              v-if="channel.inbox"
              :inbox="channel.inbox"
              use-brand-icon
              class="size-5 text-n-slate-11"
            />
            <Icon
              v-else
              :icon="channel.fallbackIcon"
              class="size-4 text-n-slate-11"
            />
          </div>
          <div class="flex-1 min-w-0">
            <span class="block text-sm font-medium text-n-slate-12">
              {{ channel.label }}
            </span>
            <span
              v-if="channel.availability === 'unconfigured'"
              class="block text-xs text-n-slate-11"
            >
              {{ t('ONBOARDING_INBOX_SETUP.CHANNELS_DIALOG.NOT_CONFIGURED') }}
            </span>
            <span
              v-else-if="channel.availability === 'setupLater'"
              class="block text-xs text-n-slate-11"
            >
              {{ t('ONBOARDING_INBOX_SETUP.CHANNELS_DIALOG.SETUP_LATER') }}
            </span>
          </div>
          <Icon
            v-if="channel.connected"
            icon="i-lucide-circle-check"
            class="size-5 text-n-teal-11"
          />
          <Icon
            v-else-if="channel.availability === 'available'"
            icon="i-lucide-chevron-right"
            class="size-5 text-n-slate-9"
          />
        </button>
      </div>
      <p class="text-sm text-n-slate-11">
        {{ t('ONBOARDING_INBOX_SETUP.CHANNELS_DIALOG.NOTE') }}
      </p>
    </template>
  </Dialog>
</template>
