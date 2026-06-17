<script setup>
import { computed } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  // Visible text. Already i18n'd by the caller.
  label: {
    type: String,
    required: true,
  },
  // Named color token. Use `hexColor` instead for a stage's dynamic hex.
  color: {
    type: String,
    default: 'slate',
    validator: value =>
      ['slate', 'teal', 'ruby', 'amber', 'brand'].includes(value),
  },
  // Optional explicit hex (stage color). When set it overrides `color`
  // and is the single allowed dynamic :style exception.
  hexColor: {
    type: String,
    default: '',
  },
  // Optional leading lucide icon (e.g. 'i-lucide-bell').
  icon: {
    type: String,
    default: '',
  },
  // Size variant.
  size: {
    type: String,
    default: 'sm',
    validator: value => ['xs', 'sm'].includes(value),
  },
  // Render in a muted/inactive style.
  dimmed: {
    type: Boolean,
    default: false,
  },
});

const colorClasses = {
  slate: 'bg-n-alpha-2 text-n-slate-11',
  teal: 'bg-n-teal-9/10 text-n-teal-11',
  ruby: 'bg-n-ruby-9/10 text-n-ruby-11',
  amber: 'bg-n-amber-9/10 text-n-amber-11',
  brand: 'bg-n-brand/10 text-n-brand',
};

const sizeClasses = {
  xs: 'px-1.5 py-0.5 text-[10px] leading-4',
  sm: 'px-2 py-0.5 text-xs leading-5',
};

const iconSizeClasses = {
  xs: 'size-2.5',
  sm: 'size-3',
};

const toneClass = computed(() =>
  props.hexColor ? '' : colorClasses[props.color] || colorClasses.slate
);

// Dynamic hex tag for stage colors — the one sanctioned :style exception.
const hexStyle = computed(() =>
  props.hexColor
    ? { backgroundColor: `${props.hexColor}1a`, color: props.hexColor }
    : null
);
</script>

<template>
  <span
    class="inline-flex min-w-0 max-w-full items-center gap-1 rounded-md font-medium"
    :class="[toneClass, sizeClasses[size], dimmed ? 'opacity-50' : '']"
    :style="hexStyle"
  >
    <Icon
      v-if="icon"
      :icon="icon"
      class="shrink-0"
      :class="iconSizeClasses[size]"
    />
    <span class="truncate">{{ label }}</span>
  </span>
</template>
