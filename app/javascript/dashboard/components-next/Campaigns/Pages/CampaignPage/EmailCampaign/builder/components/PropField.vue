<script setup>
import { computed } from 'vue';

const props = defineProps({
  label: {
    type: String,
    required: true,
  },
  // `revision` is bumped by the parent on component:selected / styleVersion so
  // the slot re-reads the live property value (we never cache values locally).
  revision: {
    type: Number,
    default: 0,
  },
});

const rev = computed(() => props.revision);
</script>

<template>
  <label class="flex flex-col gap-1.5">
    <span class="text-xs font-medium text-n-slate-11">{{ label }}</span>
    <slot :revision="rev" />
  </label>
</template>
