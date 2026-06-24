<script setup>
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

defineProps({
  placeholders: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['insert']);

const { t } = useI18n();

const chipLabel = key => `{{ ${key} }}`;

const onChipClick = async key => {
  await copyTextToClipboard(chipLabel(key));
  useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.PLACEHOLDERS.COPY_SUCCESS'));
  emit('insert', key);
};
</script>

<template>
  <div class="flex flex-wrap gap-2">
    <button
      v-for="key in placeholders"
      :key="key"
      type="button"
      class="inline-flex items-center gap-1 px-2 py-1 font-mono text-xs rounded-md text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3"
      @click="onChipClick(key)"
    >
      <span class="i-lucide-copy size-3 text-n-slate-11" />
      {{ chipLabel(key) }}
    </button>
  </div>
</template>
