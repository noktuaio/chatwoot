<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

// V2.1 — emits the chosen starting point PLUS two screen-level choices:
// `actuation` (external|internal) and `withKnowledge` (boolean). Defaults
// reproduce today's behavior exactly (external + with knowledge), so a user who
// ignores the toggles creates the same agent as before. `both` is an advanced
// value set later in the agent's settings, not on this screen.
const emit = defineEmits(['select']);

const { t } = useI18n();

const actuation = ref('external');
const withKnowledge = ref(true);

const ACTUATION_OPTIONS = [
  {
    value: 'external',
    icon: 'i-lucide-globe',
    label: 'AGENTS.TYPES.ACTUATION.EXTERNAL',
  },
  {
    value: 'internal',
    icon: 'i-lucide-headset',
    label: 'AGENTS.TYPES.ACTUATION.INTERNAL',
  },
];
const KNOWLEDGE_OPTIONS = [
  {
    value: true,
    icon: 'i-lucide-book-open',
    label: 'AGENTS.TYPES.KNOWLEDGE.WITH',
  },
  {
    value: false,
    icon: 'i-lucide-sparkles',
    label: 'AGENTS.TYPES.KNOWLEDGE.WITHOUT',
  },
];

const actuationHint = computed(() =>
  actuation.value === 'internal'
    ? 'AGENTS.TYPES.ACTUATION.INTERNAL_HINT'
    : 'AGENTS.TYPES.ACTUATION.EXTERNAL_HINT'
);
const knowledgeHint = computed(() =>
  withKnowledge.value
    ? 'AGENTS.TYPES.KNOWLEDGE.WITH_HINT'
    : 'AGENTS.TYPES.KNOWLEDGE.WITHOUT_HINT'
);

// `style` paints the icon badge and the hover/selected border per type. Classes
// are STATIC (the JIT cannot generate `bg-n-${x}-3`), so the full strings live here.
const TYPE_STYLE = {
  support: {
    badge: 'bg-n-teal-3 text-n-teal-11',
    border: 'hover:border-n-teal-7',
  },
  sdr: { badge: 'bg-n-iris-3 text-n-iris-11', border: 'hover:border-n-iris-7' },
  reception: {
    badge: 'bg-n-amber-3 text-n-amber-11',
    border: 'hover:border-n-amber-7',
  },
  onboarding: {
    badge: 'bg-n-green-3 text-n-green-11',
    border: 'hover:border-n-green-7',
  },
  scheduler: {
    badge: 'bg-n-iris-4 text-n-iris-11',
    border: 'hover:border-n-iris-8',
  },
  reactivation: {
    badge: 'bg-n-coral-3 text-n-coral-11',
    border: 'hover:border-n-coral-7',
  },
  custom: {
    badge: 'bg-n-slate-3 text-n-slate-11',
    border: 'hover:border-n-slate-7',
  },
};

const AGENT_TYPES = [
  { key: 'support', value: 'support', icon: 'i-lucide-life-buoy' },
  { key: 'sdr', value: 'sdr', icon: 'i-lucide-target' },
  { key: 'receptionist', value: 'reception', icon: 'i-lucide-concierge-bell' },
  { key: 'post_sale', value: 'onboarding', icon: 'i-lucide-heart-handshake' },
  { key: 'scheduler', value: 'scheduler', icon: 'i-lucide-calendar-clock' },
  { key: 'reactivation', value: 'reactivation', icon: 'i-lucide-refresh-cw' },
];

const CUSTOM_TYPE = {
  key: 'scratch',
  value: 'custom',
  icon: 'i-lucide-sparkles',
};

const styleFor = value => TYPE_STYLE[value] || TYPE_STYLE.custom;

const onSelect = type =>
  emit('select', {
    type,
    actuation: actuation.value,
    withKnowledge: withKnowledge.value,
  });
</script>

<template>
  <section class="flex flex-col w-full gap-6 mx-auto max-w-4xl">
    <header class="flex flex-col gap-1 text-center">
      <h2 class="text-xl font-semibold text-n-slate-12">
        {{ t('AGENTS.TYPES.PICK_TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ t('AGENTS.TYPES.PICK_SUBTITLE') }}
      </p>
    </header>

    <div class="flex flex-wrap justify-center gap-x-10 gap-y-4">
      <div class="flex flex-col items-center gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('AGENTS.TYPES.ACTUATION.LABEL') }}
        </span>
        <div
          role="radiogroup"
          :aria-label="t('AGENTS.TYPES.ACTUATION.LABEL')"
          class="inline-flex gap-1 p-1 rounded-xl bg-n-alpha-black2"
        >
          <button
            v-for="opt in ACTUATION_OPTIONS"
            :key="opt.value"
            type="button"
            role="radio"
            :aria-checked="actuation === opt.value"
            class="flex items-center gap-2 px-3.5 py-2 text-sm transition-colors rounded-lg outline-1 outline-transparent focus-visible:outline-n-brand"
            :class="
              actuation === opt.value
                ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            @click="actuation = opt.value"
          >
            <span :class="opt.icon" class="size-4" />
            {{ t(opt.label) }}
          </button>
        </div>
        <span class="text-xs text-center text-n-slate-10 max-w-[15rem]">
          {{ t(actuationHint) }}
        </span>
      </div>

      <div class="flex flex-col items-center gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('AGENTS.TYPES.KNOWLEDGE.LABEL') }}
        </span>
        <div
          role="radiogroup"
          :aria-label="t('AGENTS.TYPES.KNOWLEDGE.LABEL')"
          class="inline-flex gap-1 p-1 rounded-xl bg-n-alpha-black2"
        >
          <button
            v-for="opt in KNOWLEDGE_OPTIONS"
            :key="String(opt.value)"
            type="button"
            role="radio"
            :aria-checked="withKnowledge === opt.value"
            class="flex items-center gap-2 px-3.5 py-2 text-sm transition-colors rounded-lg outline-1 outline-transparent focus-visible:outline-n-brand"
            :class="
              withKnowledge === opt.value
                ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            @click="withKnowledge = opt.value"
          >
            <span :class="opt.icon" class="size-4" />
            {{ t(opt.label) }}
          </button>
        </div>
        <span class="text-xs text-center text-n-slate-10 max-w-[15rem]">
          {{ t(knowledgeHint) }}
        </span>
      </div>
    </div>

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <button
        v-for="agentType in AGENT_TYPES"
        :key="agentType.key"
        type="button"
        class="flex flex-col gap-3 p-6 text-left transition-all duration-150 border group rounded-xl border-n-weak bg-n-solid-1 hover:-translate-y-0.5 hover:shadow-sm outline-1 outline-transparent focus-visible:outline-n-brand min-h-[8.5rem]"
        :class="styleFor(agentType.value).border"
        @click="onSelect(agentType.value)"
      >
        <span
          class="flex items-center justify-center rounded-lg size-12 shrink-0"
          :class="styleFor(agentType.value).badge"
        >
          <span :class="agentType.icon" class="size-6" />
        </span>
        <span class="flex flex-col gap-1 min-w-0">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t(`AGENTS.TYPES.${agentType.key.toUpperCase()}.TITLE`) }}
          </span>
          <span class="text-xs leading-snug text-n-slate-11">
            {{ t(`AGENTS.TYPES.${agentType.key.toUpperCase()}.SUBTITLE`) }}
          </span>
        </span>
      </button>
    </div>

    <!-- "Outros" / custom: no ready skeleton, build from a blank page. -->
    <button
      type="button"
      class="flex items-center w-full gap-3 p-6 text-left transition-all duration-150 border border-dashed group rounded-xl border-n-weak bg-n-solid-1 hover:-translate-y-0.5 hover:shadow-sm outline-1 outline-transparent focus-visible:outline-n-brand"
      :class="styleFor(CUSTOM_TYPE.value).border"
      @click="onSelect(CUSTOM_TYPE.value)"
    >
      <span
        class="flex items-center justify-center rounded-lg size-12 shrink-0"
        :class="styleFor(CUSTOM_TYPE.value).badge"
      >
        <span :class="CUSTOM_TYPE.icon" class="size-6" />
      </span>
      <span class="flex flex-col gap-1 min-w-0">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t(`AGENTS.TYPES.${CUSTOM_TYPE.key.toUpperCase()}.TITLE`) }}
        </span>
        <span class="text-xs leading-snug text-n-slate-11">
          {{ t(`AGENTS.TYPES.${CUSTOM_TYPE.key.toUpperCase()}.SUBTITLE`) }}
        </span>
      </span>
    </button>
  </section>
</template>
