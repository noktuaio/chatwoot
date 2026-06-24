<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  // grapesjs-mjml Property instance (base/integer type). May be undefined when
  // the selected component does not expose it.
  property: {
    type: Object,
    default: null,
  },
  // bumped on selection/style change -> forces getValue() re-read
  revision: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['change']);

const { t } = useI18n();

const value = computed(() => {
  // eslint-disable-next-line no-unused-expressions
  props.revision;
  return props.property?.getValue?.({ noDefault: true }) ?? '';
});

const onInput = event => {
  emit('change', props.property, event.target.value);
};
</script>

<template>
  <input
    :value="value"
    type="text"
    inputmode="numeric"
    :disabled="!property"
    class="w-full px-2.5 py-1.5 text-sm rounded-lg border border-n-weak bg-n-alpha-black1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:border-n-brand disabled:opacity-50"
    :placeholder="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.SIZE.AUTO')"
    @change="onInput"
  />
</template>
