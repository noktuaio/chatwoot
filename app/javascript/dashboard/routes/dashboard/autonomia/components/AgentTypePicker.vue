<script setup>
import { useI18n } from 'vue-i18n';

const emit = defineEmits(['select']);

const { t } = useI18n();

// Seven starting points. `value` is the backend enum
// (Autonomia::Agents::Agent::AGENT_TYPES = support sdr reception onboarding
// scheduler reactivation custom) — the wire value MUST match it so the chosen
// preset is a valid, persistable seed and never ships an unknown enum. `key`
// drives the i18n label (kept distinct from the enum to preserve product copy
// like "Receptionist" / "Post-sale" / "Start from scratch").
//
// `style` paints the icon badge and the hover/selected border per type. Classes
// are STATIC (the JIT cannot generate `bg-n-${x}-3`), so the full class strings
// live in the map. `custom` is rendered apart (full-width, dashed) — it has no
// ready skeleton on the backend and means "build from scratch".
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

const onSelect = type => emit('select', type);
</script>

<template>
  <section class="flex flex-col w-full max-w-4xl gap-6 mx-auto">
    <header class="flex flex-col gap-1 text-center">
      <h2 class="text-xl font-semibold text-n-slate-12">
        {{ t('AGENTS.TYPES.PICK_TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ t('AGENTS.TYPES.PICK_SUBTITLE') }}
      </p>
    </header>

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <button
        v-for="agentType in AGENT_TYPES"
        :key="agentType.key"
        type="button"
        class="flex flex-col gap-3 p-5 text-left transition-all duration-150 border group rounded-xl border-n-weak bg-n-solid-1 hover:-translate-y-0.5 hover:shadow-sm outline-1 outline-transparent focus-visible:outline-n-brand"
        :class="styleFor(agentType.value).border"
        @click="onSelect(agentType.value)"
      >
        <span
          class="flex items-center justify-center rounded-lg size-10 shrink-0"
          :class="styleFor(agentType.value).badge"
        >
          <span :class="agentType.icon" class="size-5" />
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

    <!-- "Outros" / custom: no ready skeleton, build from a blank page. Set apart
         below the grid, full width, dashed border. -->
    <button
      type="button"
      class="flex items-center w-full gap-3 p-5 text-left transition-all duration-150 border border-dashed group rounded-xl border-n-weak bg-n-solid-1 hover:-translate-y-0.5 hover:shadow-sm outline-1 outline-transparent focus-visible:outline-n-brand"
      :class="styleFor(CUSTOM_TYPE.value).border"
      @click="onSelect(CUSTOM_TYPE.value)"
    >
      <span
        class="flex items-center justify-center rounded-lg size-10 shrink-0"
        :class="styleFor(CUSTOM_TYPE.value).badge"
      >
        <span :class="CUSTOM_TYPE.icon" class="size-5" />
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
