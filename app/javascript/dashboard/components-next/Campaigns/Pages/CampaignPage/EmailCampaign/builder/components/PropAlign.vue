<script setup>
import { computed } from 'vue';

const props = defineProps({
  // Either the Typography 'text-align' or, as a fallback, 'align' Property.
  property: {
    type: Object,
    default: null,
  },
  revision: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['change']);

// Static i-lucide icons (no dynamic icon names).
const OPTIONS = [
  { value: 'left', icon: 'i-lucide-align-left' },
  { value: 'center', icon: 'i-lucide-align-center' },
  { value: 'right', icon: 'i-lucide-align-right' },
  { value: 'justify', icon: 'i-lucide-align-justify' },
];

const current = computed(() => {
  // eslint-disable-next-line no-unused-expressions
  props.revision;
  return props.property?.getValue?.({ noDefault: true }) ?? '';
});

const select = value => {
  if (!props.property) return;
  emit('change', props.property, value);
};
</script>

<template>
  <div
    class="inline-flex p-0.5 rounded-lg border border-n-weak bg-n-alpha-black1"
    :class="{ 'opacity-50 pointer-events-none': !property }"
  >
    <button
      v-for="option in OPTIONS"
      :key="option.value"
      type="button"
      class="flex items-center justify-center rounded-md size-7"
      :class="
        current === option.value
          ? 'bg-n-solid-3 text-n-slate-12'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
      @click="select(option.value)"
    >
      <span class="size-4" :class="[option.icon]" />
    </button>
  </div>
</template>
