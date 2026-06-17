<script setup>
import { computed } from 'vue';

import { useEmailEditor } from '../composables/useEmailEditor';

const props = defineProps({
  // bumped on selection/style change -> forces style re-read
  revision: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['change']);

const { getStyleProp, applyStyleProp } = useEmailEditor();

// Each toggle reads/writes a single CSS style. font-weight/font-style live under
// Typography; text-decoration under Decorations. The composable helpers fall
// back to component.getStyle()/addStyle() when the property is not registered.
const fontWeight = computed(() => {
  // eslint-disable-next-line no-unused-expressions
  props.revision;
  return getStyleProp('Typography', 'font-weight');
});
const fontStyle = computed(() => {
  // eslint-disable-next-line no-unused-expressions
  props.revision;
  return getStyleProp('Typography', 'font-style');
});
const textDecoration = computed(() => {
  // eslint-disable-next-line no-unused-expressions
  props.revision;
  return getStyleProp('Decorations', 'text-decoration');
});

const isBold = computed(() => String(fontWeight.value) === 'bold');
const isItalic = computed(() => fontStyle.value === 'italic');
const isUnderline = computed(() => textDecoration.value === 'underline');
const isStrike = computed(() => textDecoration.value === 'line-through');

const toggle = (sectorId, propName, activeValue, inactiveValue, isActive) => {
  applyStyleProp(sectorId, propName, isActive ? inactiveValue : activeValue);
  emit('change');
};

const toggleBold = () =>
  toggle('Typography', 'font-weight', 'bold', 'normal', isBold.value);
const toggleItalic = () =>
  toggle('Typography', 'font-style', 'italic', 'normal', isItalic.value);
const toggleUnderline = () =>
  toggle(
    'Decorations',
    'text-decoration',
    'underline',
    'none',
    isUnderline.value
  );
const toggleStrike = () =>
  toggle(
    'Decorations',
    'text-decoration',
    'line-through',
    'none',
    isStrike.value
  );
</script>

<template>
  <div
    class="inline-flex p-0.5 rounded-lg border border-n-weak bg-n-alpha-black1"
  >
    <button
      type="button"
      class="flex items-center justify-center rounded-md size-7"
      :class="
        isBold
          ? 'bg-n-alpha-2 text-n-slate-12'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
      @click="toggleBold"
    >
      <span class="i-lucide-bold size-4" />
    </button>
    <button
      type="button"
      class="flex items-center justify-center rounded-md size-7"
      :class="
        isItalic
          ? 'bg-n-alpha-2 text-n-slate-12'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
      @click="toggleItalic"
    >
      <span class="i-lucide-italic size-4" />
    </button>
    <button
      type="button"
      class="flex items-center justify-center rounded-md size-7"
      :class="
        isUnderline
          ? 'bg-n-alpha-2 text-n-slate-12'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
      @click="toggleUnderline"
    >
      <span class="i-lucide-underline size-4" />
    </button>
    <button
      type="button"
      class="flex items-center justify-center rounded-md size-7"
      :class="
        isStrike
          ? 'bg-n-alpha-2 text-n-slate-12'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
      @click="toggleStrike"
    >
      <span class="i-lucide-strikethrough size-4" />
    </button>
  </div>
</template>
