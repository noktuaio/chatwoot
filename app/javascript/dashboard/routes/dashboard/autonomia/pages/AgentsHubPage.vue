<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import AgentCard from '../components/AgentCard.vue';

// HUB "Meus Agentes" — the entry point. Lists the account's agents and the
// hero "create with AI" affordance. Creating routes to the Builder, whose
// STEP 0 is the type picker (single entry point, also reached from the sidebar
// "Agent builder" link). IP OCULTO: cards render only human_card.
const { t } = useI18n();
const store = useStore();
const router = useRouter();

const loadError = ref(false);

const agents = useMapGetter('autonomiaAgents/getRecords');
const uiFlags = useMapGetter('autonomiaAgents/getUIFlags');

const isLoading = computed(
  () => uiFlags.value.fetchingList && !agents.value.length
);

const goToCreate = () => {
  router.push({ name: 'autonomia_agents_builder' });
};

const openAgent = agent => {
  router.push({
    name: 'autonomia_agent_panel',
    params: { agentId: agent.id, tab: 'test' },
  });
};

// The `get` factory action does not expose an error flag in uiFlags, so a network
// failure would otherwise fall through to the (misleading) empty state. Track the
// failure locally via try/catch and surface a dedicated error state with retry.
// A transient blip (e.g. the server restarting during a deploy) is retried once
// silently before the error state is shown, so a momentary 502 self-heals.
const loadAgents = async ({ retry = true } = {}) => {
  try {
    loadError.value = false;
    await store.dispatch('autonomiaAgents/get');
  } catch {
    if (retry) {
      await new Promise(resolve => {
        setTimeout(resolve, 1500);
      });
      await loadAgents({ retry: false });
      return;
    }
    loadError.value = true;
  }
};

onMounted(() => loadAgents());
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header
      class="flex items-center justify-between flex-shrink-0 gap-4 px-6 py-4 border-b border-n-weak"
    >
      <div class="flex items-center min-w-0 gap-3">
        <span
          class="flex items-center justify-center rounded-lg shrink-0 size-9 bg-n-iris-3 text-n-iris-11"
        >
          <span class="i-lucide-bot size-5" />
        </span>
        <div class="flex flex-col min-w-0">
          <h1 class="text-base font-medium leading-tight text-n-slate-12">
            {{ t('AGENTS.HUB.TITLE') }}
          </h1>
          <p class="text-xs truncate text-n-slate-11">
            {{ t('AGENTS.HUB.SUBTITLE') }}
          </p>
        </div>
      </div>
      <NextButton
        v-if="agents.length"
        solid
        blue
        icon="i-lucide-sparkles"
        :label="t('AGENTS.HUB.CREATE')"
        @click="goToCreate"
      />
    </header>

    <div class="flex-1 min-h-0 overflow-y-auto">
      <div
        v-if="isLoading"
        class="flex items-center justify-center w-full h-full text-n-slate-11"
      >
        <Spinner :size="28" />
      </div>

      <div
        v-else-if="loadError"
        class="flex flex-col items-center justify-center w-full h-full gap-3 px-6 text-center"
        role="alert"
      >
        <Icon icon="i-lucide-circle-alert" class="text-3xl text-n-ruby-9" />
        <p class="text-sm text-n-slate-11">{{ t('AGENTS.HUB.ERROR') }}</p>
        <NextButton
          outline
          slate
          sm
          :label="t('AGENTS.BUILDER.RETRY')"
          @click="loadAgents"
        />
      </div>

      <EmptyStateLayout
        v-else-if="!agents.length && !loadError"
        :title="t('AGENTS.HUB.EMPTY.TITLE')"
        :subtitle="t('AGENTS.HUB.EMPTY.SUBTITLE')"
        :show-backdrop="false"
      >
        <template #actions>
          <NextButton
            solid
            blue
            icon="i-lucide-sparkles"
            :label="t('AGENTS.HUB.CREATE')"
            @click="goToCreate"
          />
        </template>
      </EmptyStateLayout>

      <div
        v-else
        class="grid grid-cols-1 gap-4 p-6 sm:grid-cols-2 lg:grid-cols-3"
      >
        <AgentCard
          v-for="agent in agents"
          :key="agent.id"
          :agent="agent"
          @select="openAgent"
        />
      </div>
    </div>
  </div>
</template>
