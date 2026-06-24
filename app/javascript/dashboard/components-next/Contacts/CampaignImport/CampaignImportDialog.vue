<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const emit = defineEmits(['create']);
const { t } = useI18n();

const uiFlags = useMapGetter('campaignImports/getUIFlags');
const isCreating = computed(() => uiFlags.value.isCreating);

const dialogRef = ref(null);
const fileInput = ref(null);
const campaignName = ref('');
const batchCount = ref(1);
const selectedFile = ref(null);

const selectedFileName = computed(() => selectedFile.value?.name || '');
const canSubmit = computed(
  () =>
    selectedFile.value &&
    campaignName.value.trim() &&
    Number(batchCount.value) > 0
);

const handleFileClick = () => fileInput.value?.click();

const handleFileChange = () => {
  selectedFile.value = fileInput.value?.files[0] || null;
};

const removeFile = () => {
  selectedFile.value = null;
  if (fileInput.value) fileInput.value.value = null;
};

const reset = () => {
  campaignName.value = '';
  batchCount.value = 1;
  removeFile();
};

const submit = () => {
  if (!canSubmit.value) return;
  emit('create', {
    file: selectedFile.value,
    campaignName: campaignName.value.trim(),
    batchCount: Number(batchCount.value),
  });
};

defineExpose({ dialogRef, reset });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    position="top"
    overflow-y-auto
    :title="t('CAMPAIGN_IMPORT.DIALOG.TITLE')"
    :confirm-button-label="t('CAMPAIGN_IMPORT.DIALOG.SUBMIT')"
    :is-loading="isCreating"
    :disable-confirm-button="!canSubmit || isCreating"
    @confirm="submit"
    @close="reset"
  >
    <template #description>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('CAMPAIGN_IMPORT.DIALOG.DESCRIPTION') }}
      </p>
    </template>

    <div class="grid gap-5 md:grid-cols-[240px_1fr]">
      <aside class="flex flex-col gap-3 p-4 border rounded-lg border-n-weak">
        <div class="flex gap-3">
          <span
            class="flex items-center justify-center flex-shrink-0 w-6 h-6 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-12"
          >
            {{ t('CAMPAIGN_IMPORT.DIALOG.STEPS.FILE.NUMBER') }}
          </span>
          <div>
            <p class="mb-1 text-sm font-medium text-n-slate-12">
              {{ t('CAMPAIGN_IMPORT.DIALOG.STEPS.FILE.TITLE') }}
            </p>
            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{ t('CAMPAIGN_IMPORT.DIALOG.STEPS.FILE.BODY') }}
            </p>
          </div>
        </div>
        <div class="flex gap-3">
          <span
            class="flex items-center justify-center flex-shrink-0 w-6 h-6 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-12"
          >
            {{ t('CAMPAIGN_IMPORT.DIALOG.STEPS.BATCHES.NUMBER') }}
          </span>
          <div>
            <p class="mb-1 text-sm font-medium text-n-slate-12">
              {{ t('CAMPAIGN_IMPORT.DIALOG.STEPS.BATCHES.TITLE') }}
            </p>
            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{ t('CAMPAIGN_IMPORT.DIALOG.STEPS.BATCHES.BODY') }}
            </p>
          </div>
        </div>
        <div class="flex gap-3">
          <span
            class="flex items-center justify-center flex-shrink-0 w-6 h-6 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-12"
          >
            {{ t('CAMPAIGN_IMPORT.DIALOG.STEPS.REVIEW.NUMBER') }}
          </span>
          <div>
            <p class="mb-1 text-sm font-medium text-n-slate-12">
              {{ t('CAMPAIGN_IMPORT.DIALOG.STEPS.REVIEW.TITLE') }}
            </p>
            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{ t('CAMPAIGN_IMPORT.DIALOG.STEPS.REVIEW.BODY') }}
            </p>
          </div>
        </div>
      </aside>

      <div class="flex flex-col gap-5">
        <Input
          v-model="campaignName"
          :label="t('CAMPAIGN_IMPORT.FIELDS.CAMPAIGN_NAME')"
          :placeholder="t('CAMPAIGN_IMPORT.FIELDS.CAMPAIGN_NAME_PLACEHOLDER')"
        />

        <label class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN_IMPORT.FIELDS.BATCH_COUNT') }}
          </span>
          <input
            v-model.number="batchCount"
            type="number"
            min="1"
            class="block w-full h-10 px-3 py-2.5 mb-0 text-sm border rounded-lg reset-base bg-n-alpha-black2 border-n-weak text-n-slate-12"
          />
          <span class="text-xs leading-5 text-n-slate-11">
            {{ t('CAMPAIGN_IMPORT.FIELDS.BATCH_COUNT_HELP') }}
          </span>
          <span class="text-xs leading-5 text-n-slate-10">
            {{ t('CAMPAIGN_IMPORT.FIELDS.BATCH_COUNT_EXAMPLE') }}
          </span>
        </label>

        <div
          class="flex flex-col gap-3 p-4 border border-dashed rounded-lg border-n-weak bg-n-alpha-1"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="mb-1 text-sm font-medium text-n-slate-12">
                {{ t('CAMPAIGN_IMPORT.FIELDS.FILE') }}
              </p>
              <p class="mb-0 text-sm truncate text-n-slate-11">
                {{
                  selectedFileName ||
                  t('CAMPAIGN_IMPORT.FIELDS.FILE_PLACEHOLDER')
                }}
              </p>
            </div>
            <div class="flex items-center gap-1">
              <Button
                :label="t('CAMPAIGN_IMPORT.ACTIONS.CHOOSE_FILE')"
                icon="i-lucide-upload"
                color="slate"
                variant="ghost"
                size="sm"
                class="!w-fit"
                @click="handleFileClick"
              />
              <Button
                v-if="selectedFile"
                icon="i-lucide-trash"
                color="ruby"
                variant="ghost"
                size="sm"
                @click="removeFile"
              />
            </div>
          </div>
          <p class="mb-0 text-xs leading-5 text-n-slate-11">
            {{ t('CAMPAIGN_IMPORT.FIELDS.FILE_HELP') }}
          </p>
        </div>
      </div>
    </div>

    <input
      ref="fileInput"
      type="file"
      accept=".csv,.xlsx,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      class="hidden"
      @change="handleFileChange"
    />
  </Dialog>
</template>
