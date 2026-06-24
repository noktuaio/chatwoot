<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  // Pre-composed chip label (e.g. "Owner: Jane"). Already i18n'd by the caller.
  label: {
    type: String,
    required: true,
  },
  // Optional raw value, surfaced as a tooltip when the label is truncated.
  value: {
    type: [String, Number],
    default: '',
  },
  // Optional count badge (e.g. number of selected stages).
  count: {
    type: [String, Number],
    default: null,
  },
  // Whether the chip shows its remove (×) affordance.
  removable: {
    type: Boolean,
    default: true,
  },
});

defineEmits(['remove', 'click']);
</script>

<template>
  <span
    v-tooltip.top="
      value ? { content: String(value), delay: { show: 500, hide: 0 } } : null
    "
    class="inline-flex min-w-0 max-w-full items-center gap-1 rounded-md bg-n-alpha-black2 px-2 py-0.5 text-xs font-medium leading-5 text-n-slate-12 outline outline-1 outline-n-weak"
  >
    <button
      type="button"
      class="flex min-w-0 items-center gap-1 truncate"
      @click="$emit('click')"
    >
      <span class="truncate">{{ label }}</span>
      <span
        v-if="count !== null"
        class="shrink-0 rounded-full bg-n-alpha-2 px-1 text-[10px] leading-4 text-n-slate-11"
      >
        {{ count }}
      </span>
    </button>
    <button
      v-if="removable"
      type="button"
      class="flex size-4 shrink-0 items-center justify-center rounded text-n-slate-11 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12"
      @click="$emit('remove')"
    >
      <Icon icon="i-lucide-x" class="size-3" />
    </button>
  </span>
</template>
