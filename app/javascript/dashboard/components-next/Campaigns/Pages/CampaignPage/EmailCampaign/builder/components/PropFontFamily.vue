<script setup>
import { computed } from 'vue';

const props = defineProps({
  // grapesjs-mjml Typography 'font-family' Property instance or undefined.
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

// Email-safe web fonts.
const FONTS = [
  'Arial',
  'Helvetica',
  'Georgia',
  'Times New Roman',
  'Verdana',
  'Tahoma',
  'Trebuchet MS',
  'Courier New',
];

// The stored font-family is often a STACK ("Arial, Helvetica, sans-serif"); take
// the first family so the select can reflect the current font.
const currentFamily = computed(() => {
  // eslint-disable-next-line no-unused-expressions
  props.revision;
  const raw = (
    props.property?.getValue?.({ noDefault: true }) ?? ''
  ).toString();
  return raw.split(',')[0].trim().replace(/['"]/g, '');
});

// Match the current family to a known option (case-insensitive). If the element
// uses a font outside our list, surface it as an extra option so the select still
// shows the real current value instead of going blank.
const matched = computed(() =>
  FONTS.find(f => f.toLowerCase() === currentFamily.value.toLowerCase())
);
const options = computed(() =>
  !currentFamily.value || matched.value
    ? FONTS
    : [currentFamily.value, ...FONTS]
);
const selected = computed(() => matched.value ?? currentFamily.value);

const onChange = event => {
  emit('change', props.property, event.target.value);
};
</script>

<template>
  <select
    :value="selected"
    :disabled="!property"
    class="w-full px-2.5 py-1.5 text-sm rounded-lg border border-n-weak bg-n-alpha-black1 text-n-slate-12 focus:outline-none focus:border-n-brand disabled:opacity-50"
    @change="onChange"
  >
    <option v-for="font in options" :key="font" :value="font">
      {{ font }}
    </option>
  </select>
</template>
