<script setup>
import { computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';

const props = defineProps({
  show: { type: Boolean, default: false },
  inboxes: { type: Array, default: () => [] },
  settings: { type: Array, default: () => [] },
  pipelines: { type: Array, default: () => [] },
  stagesByPipeline: { type: Object, default: () => ({}) },
  isLoading: { type: Boolean, default: false },
  isSaving: { type: Boolean, default: false },
  isLoadingStages: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'save', 'loadPipelineStages']);

const { t } = useI18n();
const forms = reactive({});

const settingByInboxId = computed(() =>
  props.settings.reduce((result, setting) => {
    result[Number(setting.inbox_id)] = setting;
    return result;
  }, {})
);

const sortedInboxes = computed(() =>
  [...props.inboxes].sort((first, second) =>
    String(first.name || '').localeCompare(String(second.name || ''))
  )
);

const resetForms = () => {
  Object.keys(forms).forEach(key => {
    delete forms[key];
  });

  sortedInboxes.value.forEach(inbox => {
    const setting = settingByInboxId.value[Number(inbox.id)] || {};
    forms[inbox.id] = {
      crm_enabled: Boolean(setting.crm_enabled),
      visibility_mode: setting.visibility_mode || 'all_inbox_cards',
      auto_create_card: Boolean(setting.auto_create_card),
      default_pipeline_id: setting.default_pipeline_id || '',
      default_stage_id: setting.default_stage_id || '',
    };
  });
};

const formFor = inbox => forms[inbox.id] || {};

const stagesFor = inbox => {
  const pipelineId = formFor(inbox).default_pipeline_id;
  if (!pipelineId) return [];
  return props.stagesByPipeline[String(pipelineId)] || [];
};

const onPipelineChange = inbox => {
  const form = formFor(inbox);
  form.default_stage_id = '';
  if (form.default_pipeline_id) {
    emit('loadPipelineStages', form.default_pipeline_id);
  }
};

const onCrmEnabledChange = inbox => {
  const form = formFor(inbox);
  if (!form.crm_enabled) {
    form.auto_create_card = false;
  }
};

const saveInbox = inbox => {
  const form = formFor(inbox);
  emit('save', {
    inboxId: inbox.id,
    crm_enabled: form.crm_enabled,
    visibility_mode: form.visibility_mode,
    auto_create_card: form.crm_enabled && form.auto_create_card,
    default_pipeline_id: form.default_pipeline_id || null,
    default_stage_id: form.default_stage_id || null,
  });
};

watch(
  () => [props.show, props.inboxes, props.settings],
  () => {
    if (props.show) resetForms();
  },
  { immediate: true }
);

useKeyboardEvents({
  Escape: {
    action: () => {
      if (props.show) emit('close');
    },
    allowOnFocusedInput: true,
  },
});
</script>

<template>
  <transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="ltr:translate-x-full rtl:-translate-x-full opacity-0"
    leave-active-class="transition duration-150 ease-in"
    leave-to-class="ltr:translate-x-[30%] rtl:-translate-x-[30%] opacity-0"
  >
    <div
      v-if="show"
      class="fixed inset-y-0 ltr:right-0 rtl:left-0 z-50 flex h-full w-[44rem] max-w-full flex-col overflow-hidden border-n-weak bg-n-surface-2 shadow-lg ltr:border-l rtl:border-r"
    >
      <div
        class="flex items-start justify-between gap-4 border-b border-n-weak px-6 py-5"
      >
        <div class="min-w-0">
          <h2 class="mb-1 text-lg font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.INBOX_SETTINGS.TITLE') }}
          </h2>
          <p class="mb-0 text-sm leading-5 text-n-slate-11">
            {{ t('CRM_KANBAN.INBOX_SETTINGS.SUBTITLE') }}
          </p>
        </div>
        <Button icon="i-lucide-x" slate ghost sm @click="$emit('close')" />
      </div>

      <div class="flex-1 overflow-y-auto px-6 py-5">
        <div v-if="isLoading" class="flex h-full items-center justify-center">
          <Spinner />
        </div>

        <div v-else-if="sortedInboxes.length === 0" class="py-12 text-center">
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.INBOX_SETTINGS.EMPTY_TITLE') }}
          </p>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('CRM_KANBAN.INBOX_SETTINGS.EMPTY_DESCRIPTION') }}
          </p>
        </div>

        <div v-else class="grid gap-4">
          <section
            v-for="inbox in sortedInboxes"
            :key="inbox.id"
            class="grid gap-4 rounded-lg border border-n-weak bg-n-alpha-black2 p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <p class="mb-1 truncate text-sm font-medium text-n-slate-12">
                  {{ inbox.name }}
                </p>
                <p class="mb-0 truncate text-xs text-n-slate-11">
                  {{ inbox.channel_type }}
                </p>
              </div>
              <label
                class="flex shrink-0 items-center gap-2 text-sm text-n-slate-12"
              >
                <input
                  v-model="formFor(inbox).crm_enabled"
                  type="checkbox"
                  class="h-4 w-4 rounded border-n-weak bg-n-alpha-black2 text-n-brand"
                  @change="onCrmEnabledChange(inbox)"
                />
                <span>{{ t('CRM_KANBAN.INBOX_SETTINGS.CRM_ENABLED') }}</span>
              </label>
            </div>

            <div class="grid gap-3 md:grid-cols-[1fr_1fr]">
              <label class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.INBOX_SETTINGS.VISIBILITY') }}
                </span>
                <select
                  v-model="formFor(inbox).visibility_mode"
                  class="reset-base !mb-0 h-10 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                >
                  <option value="all_inbox_cards">
                    {{ t('CRM_KANBAN.INBOX_SETTINGS.ALL_INBOX_CARDS') }}
                  </option>
                  <option value="assigned_only">
                    {{ t('CRM_KANBAN.INBOX_SETTINGS.ASSIGNED_ONLY') }}
                  </option>
                </select>
              </label>

              <label class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.INBOX_SETTINGS.DEFAULT_PIPELINE') }}
                </span>
                <select
                  v-model="formFor(inbox).default_pipeline_id"
                  class="reset-base !mb-0 h-10 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                  @change="onPipelineChange(inbox)"
                >
                  <option value="">
                    {{ t('CRM_KANBAN.INBOX_SETTINGS.NO_DEFAULT_PIPELINE') }}
                  </option>
                  <option
                    v-for="pipeline in pipelines"
                    :key="pipeline.id"
                    :value="pipeline.id"
                  >
                    {{ pipeline.name }}
                  </option>
                </select>
              </label>

              <label class="grid gap-1">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CRM_KANBAN.INBOX_SETTINGS.DEFAULT_STAGE') }}
                </span>
                <select
                  v-model="formFor(inbox).default_stage_id"
                  class="reset-base !mb-0 h-10 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
                  :disabled="!formFor(inbox).default_pipeline_id"
                >
                  <option value="">
                    {{ t('CRM_KANBAN.INBOX_SETTINGS.FIRST_STAGE') }}
                  </option>
                  <option
                    v-for="stage in stagesFor(inbox)"
                    :key="stage.id"
                    :value="stage.id"
                  >
                    {{ stage.name }}
                  </option>
                </select>
              </label>

              <div class="flex items-end justify-between gap-3">
                <label
                  class="flex min-w-0 items-center gap-2 text-sm text-n-slate-12"
                >
                  <input
                    v-model="formFor(inbox).auto_create_card"
                    type="checkbox"
                    class="h-4 w-4 rounded border-n-weak bg-n-alpha-black2 text-n-brand"
                    :disabled="!formFor(inbox).crm_enabled"
                  />
                  <span>
                    {{ t('CRM_KANBAN.INBOX_SETTINGS.AUTO_CREATE') }}
                  </span>
                </label>
                <Button
                  :label="t('CRM_KANBAN.INBOX_SETTINGS.SAVE')"
                  icon="i-lucide-check"
                  sm
                  :is-loading="isSaving || isLoadingStages"
                  @click="saveInbox(inbox)"
                />
              </div>
            </div>
          </section>
        </div>
      </div>
    </div>
  </transition>
</template>
