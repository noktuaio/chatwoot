<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['select']);

const { t } = useI18n();

// Human-facing summary only — the generated instruction/scaffold is IP and is
// never read here (the serializer hides it in guided mode anyway). `human_card`
// is a plain string on the agent payload (builder stores it via `.to_s`).
const summary = computed(() => props.agent?.human_card || '');

const channelsCount = computed(() => props.agent?.channels_count ?? 0);

// Performance metrics arrive in a later phase; show an em dash until then.
const metricPlaceholder = '—';

// Status drives a small colored pill. Unknown statuses fall back to "draft".
const STATUS_STYLES = {
  active: 'bg-n-teal-3 text-n-teal-11',
  paused: 'bg-n-amber-3 text-n-amber-11',
  draft: 'bg-n-slate-3 text-n-slate-11',
};

// A tiny leading dot inside the pill, tinted to match the status.
const STATUS_DOT = {
  active: 'bg-n-teal-9',
  paused: 'bg-n-amber-9',
  draft: 'bg-n-slate-9',
};

const status = computed(() => props.agent?.status || 'draft');

const statusClass = computed(
  () => STATUS_STYLES[status.value] || STATUS_STYLES.draft
);

const statusDotClass = computed(
  () => STATUS_DOT[status.value] || STATUS_DOT.draft
);

const statusLabel = computed(() =>
  t(`AGENTS.HUB.STATUS.${status.value.toUpperCase()}`)
);
</script>

<template>
  <button
    type="button"
    class="flex flex-col w-full gap-3 p-4 text-left transition-all duration-150 border shadow-sm rounded-xl border-n-weak bg-n-solid-1 hover:border-n-slate-6 hover:shadow-md hover:-translate-y-0.5 outline-1 outline-transparent focus-visible:outline-n-brand"
    @click="emit('select', agent)"
  >
    <div class="flex items-start gap-3">
      <Avatar :name="agent.name" :size="40" rounded-full />
      <div class="flex flex-col min-w-0 gap-1.5">
        <span class="text-sm font-medium truncate text-n-slate-12">
          {{ agent.name }}
        </span>
        <span
          class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs font-medium rounded-full w-fit"
          :class="statusClass"
        >
          <span class="rounded-full size-1.5" :class="statusDotClass" />
          {{ statusLabel }}
        </span>
      </div>
    </div>

    <p class="m-0 text-sm line-clamp-2 text-n-slate-11">
      {{ summary }}
    </p>

    <div
      class="flex items-center gap-4 pt-3 mt-auto text-xs border-t text-n-slate-11 border-n-weak"
    >
      <span class="flex items-center gap-1.5">
        <span class="i-lucide-radio-tower size-3.5" />
        {{ t('AGENTS.HUB.CHANNELS_COUNT', { count: channelsCount }) }}
      </span>
      <span class="flex items-center gap-1.5">
        <span class="i-lucide-bar-chart-3 size-3.5" />
        {{ metricPlaceholder }}
      </span>
    </div>
  </button>
</template>
