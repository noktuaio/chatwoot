<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useEmailEditor } from '../composables/useEmailEditor';

const props = defineProps({
  // bumped on selection/style change -> forces attribute re-read
  revision: {
    type: Number,
    default: 0,
  },
});

const { t } = useI18n();

const { getSelectedAttribute, setSelectedAttribute } = useEmailEditor();

// Local reactive model so edits reflect instantly. Re-initialized from the
// selected component on selection/revision change (mirrors PropImage). This
// keeps the input from going stale when the selection switches.
const hrefModel = ref('');

watch(
  () => props.revision,
  () => {
    hrefModel.value = getSelectedAttribute('href') ?? '';
  },
  { immediate: true }
);

// Accept any normal link (external/relative/parameterized URLs + Liquid
// placeholders). Reject dangerous schemes. Strip ASCII control chars AND
// whitespace FIRST so obfuscations like "java\nscript:" / "java\tscript:"
// (which a mail client may collapse and execute) can't slip past the check.
// eslint-disable-next-line no-control-regex
const CONTROL_WS = /[\u0000-\u0020\u007f]+/g;
const isUnsafe = value => {
  const scheme = String(value).replace(CONTROL_WS, '').toLowerCase();
  return /^(javascript|data|vbscript):/.test(scheme);
};

const onHrefChange = event => {
  const value = event.target.value;
  if (isUnsafe(value)) {
    // revert to the persisted value
    hrefModel.value = getSelectedAttribute('href') ?? '';
    return;
  }
  hrefModel.value = value;
  setSelectedAttribute('href', value);
};
</script>

<template>
  <label class="flex flex-col gap-1.5">
    <span class="text-xs font-medium text-n-slate-11">
      {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.LINK.HREF') }}
    </span>
    <input
      :value="hrefModel"
      type="text"
      spellcheck="false"
      :placeholder="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.LINK.PLACEHOLDER')"
      class="w-full px-2.5 py-1.5 text-sm rounded-lg border border-n-weak bg-n-alpha-black1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:border-n-brand"
      @input="onHrefChange"
    />
  </label>
</template>
