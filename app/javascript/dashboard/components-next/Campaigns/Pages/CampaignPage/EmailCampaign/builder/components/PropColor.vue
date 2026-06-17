<script setup>
import { computed, ref, watch } from 'vue';

const props = defineProps({
  // grapesjs-mjml Property instance (color type) or undefined.
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

// Compact curated palette for quick picks. These are email *content* colors
// (arbitrary by nature), so each `cls` is a STATIC arbitrary-value Tailwind
// background class written as a literal so the JIT scanner emits it (never build
// the class from the hex at runtime — JIT would purge it). `hex` is committed to
// the canvas and used for selected-state matching. The visible `border-n-strong`
// ring keeps white/black readable in both light/dark themes.
const SWATCHES = [
  { hex: '#ffffff', cls: 'bg-[#ffffff]' },
  { hex: '#1f2937', cls: 'bg-[#1f2937]' },
  { hex: '#6b7280', cls: 'bg-[#6b7280]' },
  { hex: '#000000', cls: 'bg-[#000000]' },
  { hex: '#2563eb', cls: 'bg-[#2563eb]' },
  { hex: '#0ea5e9', cls: 'bg-[#0ea5e9]' },
  { hex: '#16a34a', cls: 'bg-[#16a34a]' },
  { hex: '#dc2626', cls: 'bg-[#dc2626]' },
];

const HEX_RE = /^#?[0-9a-fA-F]{6}$/;
const HEX_PLACEHOLDER = '#1F2937';

const normalize = value => {
  if (!value) return '';
  const v = value.trim().toLowerCase();
  if (!HEX_RE.test(v)) return '';
  return v.startsWith('#') ? v : `#${v}`;
};

const current = computed(() => {
  // eslint-disable-next-line no-unused-expressions
  props.revision;
  return normalize(props.property?.getValue?.({ noDefault: true }) ?? '');
});

// Local text buffer so the user can type freely; committed on change/blur.
const hexInput = ref('');
watch(
  current,
  value => {
    hexInput.value = value;
  },
  { immediate: true }
);

const commit = color => {
  if (!props.property) return;
  emit('change', props.property, color);
};

const onPicker = event => {
  commit(normalize(event.target.value));
};

const onHexChange = () => {
  const normalized = normalize(hexInput.value);
  if (!normalized) {
    hexInput.value = current.value;
    return;
  }
  hexInput.value = normalized;
  commit(normalized);
};
</script>

<template>
  <div
    class="flex flex-col gap-2"
    :class="{ 'opacity-50 pointer-events-none': !property }"
  >
    <div class="flex items-center gap-2">
      <input
        type="color"
        :value="current || '#000000'"
        :disabled="!property"
        class="border rounded-md cursor-pointer size-8 shrink-0 border-n-strong bg-n-alpha-black1"
        @input="onPicker"
      />
      <input
        v-model="hexInput"
        type="text"
        spellcheck="false"
        :placeholder="HEX_PLACEHOLDER"
        :disabled="!property"
        class="w-full px-2.5 py-1.5 text-sm rounded-lg border border-n-weak bg-n-alpha-black1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:border-n-brand disabled:opacity-50"
        @change="onHexChange"
        @blur="onHexChange"
      />
    </div>

    <div class="flex flex-wrap gap-1.5">
      <button
        v-for="swatch in SWATCHES"
        :key="swatch.hex"
        type="button"
        :title="swatch.hex"
        class="relative border rounded-md size-6 border-n-strong"
        :class="[
          swatch.cls,
          current === swatch.hex
            ? 'ring-2 ring-n-brand ring-offset-1 ring-offset-n-solid-2'
            : '',
        ]"
        @click="commit(swatch.hex)"
      />
    </div>
  </div>
</template>
