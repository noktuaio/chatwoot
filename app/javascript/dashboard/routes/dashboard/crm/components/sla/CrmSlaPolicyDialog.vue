<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { convertSecondsToTimeUnit } from '@chatwoot/utils';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import CrmSlaTimeInput from './CrmSlaTimeInput.vue';

const props = defineProps({
  policy: { type: Object, default: null },
  pipelines: { type: Array, default: () => [] },
});

const emit = defineEmits(['close', 'saved']);

const { t } = useI18n();
const store = useStore();

const uiFlags = useMapGetter('sla/getUIFlags');
const inboxes = useMapGetter('inboxes/getInboxes');

const isEditing = computed(() => Boolean(props.policy?.id));
const isSaving = computed(
  () => uiFlags.value.isCreating || uiFlags.value.isUpdating
);

const nameTouched = ref(false);

// Defaults for create (locked): business hours OFF, groups excluded ON, AI guard ON.
const form = reactive({
  name: '',
  description: '',
  onlyDuringBusinessHours: false,
  excludeGroups: true,
  aiSkipNaturalPause: true,
  autoApplyEnabled: false,
  inboxIds: [],
  pipelineIds: [],
});

// Per-metric tracking toggles (PO decision): FRT and NRT start ON for new
// policies, RT starts OFF. A metric toggled OFF is submitted as null and the
// engine simply does not track it.
const timeInputs = reactive([
  {
    key: 'FRT',
    field: 'first_response_time_threshold',
    enabled: true,
    threshold: null,
    unit: 'Minutes',
    invalid: false,
  },
  {
    key: 'NRT',
    field: 'next_response_time_threshold',
    enabled: true,
    threshold: null,
    unit: 'Minutes',
    invalid: false,
  },
  {
    key: 'RT',
    field: 'resolution_time_threshold',
    enabled: false,
    threshold: null,
    unit: 'Minutes',
    invalid: false,
  },
]);

const hydrate = () => {
  if (!props.policy) return;
  form.name = props.policy.name || '';
  form.description = props.policy.description || '';
  form.onlyDuringBusinessHours = Boolean(
    props.policy.only_during_business_hours
  );
  form.excludeGroups = props.policy.exclude_groups !== false;
  form.aiSkipNaturalPause = props.policy.ai_skip_natural_pause !== false;
  const autoApply = props.policy.auto_apply || {};
  form.autoApplyEnabled = Boolean(autoApply.enabled);
  form.inboxIds = (autoApply.inbox_ids || []).map(Number);
  form.pipelineIds = (autoApply.pipeline_ids || []).map(Number);
  timeInputs.forEach(input => {
    const seconds = props.policy[input.field];
    input.enabled = Boolean(seconds);
    if (!seconds) return;
    const converted = convertSecondsToTimeUnit(seconds, {
      minute: 'Minutes',
      hour: 'Hours',
      day: 'Days',
    });
    input.threshold = converted.time;
    input.unit = converted.unit || 'Minutes';
  });
};
hydrate();

const isNameValid = computed(() => form.name.trim().length >= 2);
const nameError = computed(() =>
  nameTouched.value && !isNameValid.value
    ? t('CRM_SLA.POLICIES.DIALOG.NAME.REQUIRED_ERROR')
    : ''
);
const submitAttempted = ref(false);
// A policy with no tracked metric would never evaluate anything — require one.
const hasEnabledTarget = computed(() =>
  timeInputs.some(input => input.enabled)
);
const canSubmit = computed(
  () =>
    isNameValid.value &&
    hasEnabledTarget.value &&
    !timeInputs.some(input => input.invalid) &&
    !isSaving.value
);

const inboxOptions = computed(() =>
  (inboxes.value || []).map(inbox => ({
    value: Number(inbox.id),
    label: inbox.name,
  }))
);
const pipelineOptions = computed(() =>
  props.pipelines.map(pipeline => ({
    value: Number(pipeline.id),
    label: pipeline.name,
  }))
);

// Same seconds math as the native SLA form. A toggled-off metric is null.
const toSeconds = input => {
  if (!input.enabled) return null;
  if (input.threshold === null || input.threshold === 0) return null;
  const unitsToSeconds = { Minutes: 60, Hours: 3600, Days: 86400 };
  return Number(input.threshold * (unitsToSeconds[input.unit] || 1));
};

const onSubmit = async () => {
  nameTouched.value = true;
  submitAttempted.value = true;
  if (!canSubmit.value) return;
  const payload = {
    name: form.name.trim(),
    description: form.description,
    first_response_time_threshold: toSeconds(timeInputs[0]),
    next_response_time_threshold: toSeconds(timeInputs[1]),
    resolution_time_threshold: toSeconds(timeInputs[2]),
    only_during_business_hours: form.onlyDuringBusinessHours,
    exclude_groups: form.excludeGroups,
    ai_skip_natural_pause: form.aiSkipNaturalPause,
    auto_apply: {
      enabled: form.autoApplyEnabled,
      event: 'conversation_created',
      inbox_ids: form.inboxIds,
      pipeline_ids: form.pipelineIds,
    },
  };
  try {
    if (isEditing.value) {
      await store.dispatch('sla/update', { id: props.policy.id, ...payload });
    } else {
      await store.dispatch('sla/create', payload);
    }
    useAlert(t('CRM_SLA.POLICIES.API.SAVE_SUCCESS'));
    emit('saved');
    emit('close');
  } catch (error) {
    useAlert(t('CRM_SLA.POLICIES.API.SAVE_ERROR'));
  }
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-black2 p-4"
    @click.self="emit('close')"
  >
    <div
      class="flex max-h-[90vh] w-[36rem] max-w-full flex-col overflow-hidden rounded-xl border border-n-weak bg-n-surface-2 shadow-lg"
    >
      <div
        class="flex items-start justify-between gap-4 border-b border-n-weak px-6 py-4"
      >
        <h2 class="m-0 text-lg font-medium text-n-slate-12">
          {{
            isEditing
              ? t('CRM_SLA.POLICIES.DIALOG.EDIT_TITLE')
              : t('CRM_SLA.POLICIES.DIALOG.ADD_TITLE')
          }}
        </h2>
        <Button icon="i-lucide-x" slate ghost sm @click="emit('close')" />
      </div>

      <div class="grid flex-1 gap-5 overflow-y-auto px-6 py-5">
        <Input
          v-model="form.name"
          :label="t('CRM_SLA.POLICIES.DIALOG.NAME.LABEL')"
          :placeholder="t('CRM_SLA.POLICIES.DIALOG.NAME.PLACEHOLDER')"
          :message="nameError"
          :message-type="nameError ? 'error' : 'info'"
          @blur="nameTouched = true"
        />

        <Input
          v-model="form.description"
          :label="t('CRM_SLA.POLICIES.DIALOG.DESCRIPTION.LABEL')"
          :placeholder="t('CRM_SLA.POLICIES.DIALOG.DESCRIPTION.PLACEHOLDER')"
        />

        <section class="grid gap-2 rounded-xl border border-n-weak px-3 py-2.5">
          <h3 class="m-0 text-sm font-medium text-n-slate-12">
            {{ t('CRM_SLA.POLICIES.DIALOG.THRESHOLDS.TITLE') }}
          </h3>
          <CrmSlaTimeInput
            v-for="input in timeInputs"
            :key="input.key"
            v-model="input.threshold"
            v-model:unit="input.unit"
            v-model:enabled="input.enabled"
            :label="t(`CRM_SLA.POLICIES.DIALOG.${input.key}.LABEL`)"
            :placeholder="t(`CRM_SLA.POLICIES.DIALOG.${input.key}.PLACEHOLDER`)"
            :show-errors="submitAttempted"
            @invalid="input.invalid = $event"
          />
          <p v-if="!hasEnabledTarget" class="mb-0 text-xs text-n-ruby-11">
            {{ t('CRM_SLA.POLICIES.DIALOG.THRESHOLDS.AT_LEAST_ONE') }}
          </p>
        </section>

        <div
          class="flex items-start justify-between gap-3 rounded-xl border border-n-weak px-3 py-2.5"
        >
          <div class="min-w-0">
            <p class="mb-0.5 text-sm text-n-slate-12">
              {{ t('CRM_SLA.POLICIES.DIALOG.BUSINESS_HOURS.LABEL') }}
            </p>
            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{ t('CRM_SLA.POLICIES.DIALOG.BUSINESS_HOURS.NOTE') }}
            </p>
          </div>
          <ToggleSwitch v-model="form.onlyDuringBusinessHours" class="mt-1" />
        </div>

        <div
          class="flex items-start justify-between gap-3 rounded-xl border border-n-weak px-3 py-2.5"
        >
          <div class="min-w-0">
            <p class="mb-0.5 text-sm text-n-slate-12">
              {{ t('CRM_SLA.POLICIES.DIALOG.EXCLUDE_GROUPS.LABEL') }}
            </p>
            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{ t('CRM_SLA.POLICIES.DIALOG.EXCLUDE_GROUPS.NOTE') }}
            </p>
          </div>
          <ToggleSwitch v-model="form.excludeGroups" class="mt-1" />
        </div>

        <div
          class="flex items-start justify-between gap-3 rounded-xl border border-n-weak px-3 py-2.5"
        >
          <div class="min-w-0">
            <p class="mb-0.5 text-sm text-n-slate-12">
              {{ t('CRM_SLA.POLICIES.DIALOG.AI_SKIP.LABEL') }}
            </p>
            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{ t('CRM_SLA.POLICIES.DIALOG.AI_SKIP.NOTE') }}
            </p>
          </div>
          <ToggleSwitch v-model="form.aiSkipNaturalPause" class="mt-1" />
        </div>

        <section class="grid gap-3 border-t border-n-weak pt-4">
          <h3 class="m-0 text-sm font-medium text-n-slate-12">
            {{ t('CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.TITLE') }}
          </h3>

          <div
            class="flex items-start justify-between gap-3 rounded-xl border border-n-weak px-3 py-2.5"
          >
            <div class="min-w-0">
              <p class="mb-0.5 text-sm text-n-slate-12">
                {{ t('CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.ENABLED_LABEL') }}
              </p>
              <p class="mb-0 text-xs leading-5 text-n-slate-11">
                {{ t('CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.NOTE') }}
              </p>
            </div>
            <ToggleSwitch v-model="form.autoApplyEnabled" class="mt-1" />
          </div>

          <template v-if="form.autoApplyEnabled">
            <label class="grid gap-1">
              <span class="text-heading-3 text-n-slate-12">
                {{ t('CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.INBOXES_LABEL') }}
              </span>
              <TagMultiSelectComboBox
                v-model="form.inboxIds"
                :options="inboxOptions"
                :placeholder="
                  t('CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.INBOXES_ALL')
                "
              />
            </label>

            <label class="grid gap-1">
              <span class="text-heading-3 text-n-slate-12">
                {{ t('CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.PIPELINES_LABEL') }}
              </span>
              <TagMultiSelectComboBox
                v-model="form.pipelineIds"
                :options="pipelineOptions"
                :placeholder="
                  t('CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.PIPELINES_ALL')
                "
              />
            </label>
          </template>
        </section>
      </div>

      <div
        class="flex items-center justify-end gap-2 border-t border-n-weak px-6 py-4"
      >
        <Button
          :label="t('CRM_SLA.POLICIES.DIALOG.CANCEL')"
          slate
          faded
          @click="emit('close')"
        />
        <Button
          :label="t('CRM_SLA.POLICIES.DIALOG.SAVE')"
          icon="i-lucide-check"
          :is-loading="isSaving"
          :disabled="!canSubmit"
          @click="onSubmit"
        />
      </div>
    </div>
  </div>
</template>
