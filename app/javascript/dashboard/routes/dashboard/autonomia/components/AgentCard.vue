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

// V2.2 — actuation surface. `external` is the default (today's behavior) and
// shows no badge to avoid noise; `internal`/`both` get a tinted pill. Reads the
// agent's `actuation` field (exposed by the serializer since V2.1).
const actuation = computed(() => props.agent?.actuation || 'external');

const isInternal = computed(() => actuation.value === 'internal');

// Pill styling per actuation. Static, full class names so Tailwind's JIT picks
// them up.
const ACTUATION_STYLES = {
  internal: 'bg-n-iris-3 text-n-iris-11',
  both: 'bg-n-teal-3 text-n-teal-11',
};

const ACTUATION_ICONS = {
  internal: 'i-lucide-shield',
  both: 'i-lucide-split',
};

const actuationLabel = computed(() =>
  t(`AGENTS.CARD.ACTUATION_${actuation.value.toUpperCase()}`)
);

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
        <div class="flex flex-wrap items-center gap-1.5">
          <span
            class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs font-medium rounded-full w-fit"
            :class="statusClass"
          >
            <span class="rounded-full size-1.5" :class="statusDotClass" />
            {{ statusLabel }}
          </span>
          <span
            v-if="actuation !== 'external'"
            class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-full w-fit"
            :class="ACTUATION_STYLES[actuation]"
          >
            <span :class="ACTUATION_ICONS[actuation]" class="size-3" />
            {{ actuationLabel }}
          </span>
        </div>
      </div>
    </div>

    <p class="m-0 text-sm line-clamp-2 text-n-slate-11">
      {{ summary }}
    </p>

    <div
      class="flex items-center gap-4 pt-3 mt-auto text-xs border-t text-n-slate-11 border-n-weak"
    >
      <span class="flex items-center gap-1.5">
        <span
          :class="isInternal ? 'i-lucide-shield' : 'i-lucide-radio-tower'"
          class="size-3.5"
        />
        <template v-if="isInternal">
          {{ t('AGENTS.CARD.INTERNAL_COPILOT') }}
        </template>
        <template v-else>
          {{ t('AGENTS.HUB.CHANNELS_COUNT', { count: channelsCount }) }}
        </template>
      </span>
      <span class="flex items-center gap-1.5">
        <span class="i-lucide-bar-chart-3 size-3.5" />
        {{ metricPlaceholder }}
      </span>
    </div>
  </button>
</template>
