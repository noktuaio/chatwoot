<script setup>
import { onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  agentId: {
    type: Number,
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();

const connected = useMapGetter('autonomiaChannels/getConnected');
const eligible = useMapGetter('autonomiaChannels/getEligible');
const uiFlags = useMapGetter('autonomiaChannels/getUIFlags');

const fetchChannels = () => {
  store.dispatch('autonomiaChannels/fetch', { agentId: props.agentId });
};

// Eligible entries carry the real inbox `id`; connected entries are
// agent-inbox joins exposing `inbox_id`/`inbox_name`.
const onConnect = async inbox => {
  try {
    await store.dispatch('autonomiaChannels/connect', {
      agentId: props.agentId,
      inboxId: inbox.id,
    });
  } catch (error) {
    useAlert(t('AGENTS.CHANNELS.CONNECT_ERROR'));
  }
};

const onDisconnect = async inbox => {
  try {
    await store.dispatch('autonomiaChannels/disconnect', {
      agentId: props.agentId,
      inboxId: inbox.inbox_id,
    });
  } catch (error) {
    useAlert(t('AGENTS.CHANNELS.DISCONNECT_ERROR'));
  }
};

onMounted(fetchChannels);
</script>

<template>
  <div class="flex flex-col w-full h-full max-w-3xl gap-6 px-6 py-6 mx-auto">
    <div
      class="flex items-start gap-2 px-4 py-3 text-xs rounded-lg bg-n-alpha-1 text-n-slate-11"
    >
      <Icon icon="i-lucide-info" class="flex-shrink-0 mt-0.5" />
      <span>{{ t('AGENTS.CHANNELS.ONE_PER_INBOX') }}</span>
    </div>

    <div
      v-if="uiFlags.fetching && !connected.length && !eligible.length"
      class="flex items-center justify-center flex-1 text-n-slate-11"
    >
      <Spinner :size="24" />
    </div>

    <template v-else>
      <section class="flex flex-col gap-3">
        <h2 class="flex items-center gap-2 text-sm font-medium text-n-slate-12">
          <Icon icon="i-lucide-plug-zap" class="text-n-teal-11" />
          {{ t('AGENTS.CHANNELS.CONNECTED') }}
        </h2>
        <p
          v-if="!connected.length"
          class="px-4 py-3 text-xs border border-dashed rounded-lg text-n-slate-10 border-n-weak"
        >
          {{ t('AGENTS.CHANNELS.EMPTY') }}
        </p>
        <ul v-else class="flex flex-col gap-2">
          <li
            v-for="inbox in connected"
            :key="inbox.id"
            class="flex items-center gap-3 px-4 py-3 transition-colors border rounded-lg border-n-weak bg-n-solid-1 hover:border-n-slate-6"
          >
            <Icon icon="i-lucide-inbox" class="flex-shrink-0 text-n-slate-11" />
            <span class="flex-1 text-sm truncate text-n-slate-12">
              {{ inbox.inbox_name }}
            </span>
            <NextButton
              outline
              xs
              ruby
              :label="t('AGENTS.CHANNELS.DISCONNECT')"
              :is-loading="uiFlags.disconnecting"
              @click="onDisconnect(inbox)"
            />
          </li>
        </ul>
      </section>

      <section class="flex flex-col gap-3">
        <h2 class="flex items-center gap-2 text-sm font-medium text-n-slate-12">
          <Icon icon="i-lucide-inbox" class="text-n-slate-11" />
          {{ t('AGENTS.CHANNELS.ELIGIBLE') }}
        </h2>
        <ul v-if="eligible.length" class="flex flex-col gap-2">
          <li
            v-for="inbox in eligible"
            :key="inbox.id"
            class="flex items-center gap-3 px-4 py-3 transition-colors border rounded-lg border-n-weak bg-n-solid-1 hover:border-n-slate-6"
          >
            <Icon icon="i-lucide-inbox" class="flex-shrink-0 text-n-slate-11" />
            <span class="flex-1 text-sm truncate text-n-slate-12">
              {{ inbox.name }}
            </span>
            <span v-if="inbox.occupied" class="text-xs text-n-slate-10">
              {{ t('AGENTS.CHANNELS.OCCUPIED') }}
            </span>
            <NextButton
              v-else
              solid
              xs
              :label="t('AGENTS.CHANNELS.CONNECT')"
              :is-loading="uiFlags.connecting"
              @click="onConnect(inbox)"
            />
          </li>
        </ul>
        <p
          v-else
          class="px-4 py-3 text-xs border border-dashed rounded-lg text-n-slate-10 border-n-weak"
        >
          {{ t('AGENTS.CHANNELS.NO_ELIGIBLE') }}
        </p>
      </section>
    </template>
  </div>
</template>
