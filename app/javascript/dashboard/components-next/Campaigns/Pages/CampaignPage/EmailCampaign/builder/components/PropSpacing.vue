<script setup>
import { computed } from 'vue';

const props = defineProps({
  // Composite Property ('padding' or 'margin') from the Dimension sector.
  property: {
    type: Object,
    default: null,
  },
  revision: {
    type: Number,
    default: 0,
  },
});

// partial=true while dragging (intermediate), false on release -> closes undo step.
const emit = defineEmits(['change', 'partial']);

const MAX = 80;

// Read the first side's numeric value as the slider position. The composite
// upValue applies the scalar (with px) to every side.
const numeric = computed(() => {
  // eslint-disable-next-line no-unused-expressions
  props.revision;
  const raw = props.property?.getValue?.({ noDefault: true }) ?? '';
  const match = String(raw).match(/-?\d+/);
  return match ? Math.min(Math.abs(Number(match[0])), MAX) : 0;
});

const display = computed(() => `${numeric.value}px`);

const onInput = event => {
  if (!props.property) return;
  emit('partial', props.property, `${event.target.value}px`);
};

const onChange = event => {
  if (!props.property) return;
  emit('change', props.property, `${event.target.value}px`);
};
</script>

<template>
  <div class="flex items-center gap-3" :class="{ 'opacity-50': !property }">
    <input
      :value="numeric"
      type="range"
      min="0"
      :max="MAX"
      step="1"
      :disabled="!property"
      class="flex-1 accent-n-brand"
      @input="onInput"
      @change="onChange"
    />
    <span class="w-10 text-xs tabular-nums text-right text-n-slate-11">
      {{ display }}
    </span>
  </div>
</template>
