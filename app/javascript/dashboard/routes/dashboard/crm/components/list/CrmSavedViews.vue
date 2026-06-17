<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  views: {
    type: Array,
    default: () => [],
  },
  // Current list state used as the saved-view config:
  // { columns, filters, sort, group_by, density }
  currentConfig: {
    type: Object,
    default: () => ({}),
  },
  pipelineId: {
    type: [Number, String],
    default: null,
  },
});

const emit = defineEmits(['apply', 'create', 'update', 'delete']);

const { t } = useI18n();

const popoverRef = ref(null);
const confirmDeleteRef = ref(null);

const isCreating = ref(false);
const draftName = ref('');
const draftVisibility = ref('private_view');
const viewPendingDelete = ref(null);

const visibilityOptions = computed(() => [
  {
    value: 'private_view',
    label: t('CRM_KANBAN.LIST.SAVED_VIEWS.PRIVATE'),
  },
  {
    value: 'team',
    label: t('CRM_KANBAN.LIST.SAVED_VIEWS.TEAM'),
  },
  {
    // CUSTOM maps to the account-wide visibility value.
    value: 'account',
    label: t('CRM_KANBAN.LIST.SAVED_VIEWS.CUSTOM'),
  },
]);

const visibilityLabel = visibility =>
  visibilityOptions.value.find(option => option.value === visibility)?.label ||
  t('CRM_KANBAN.LIST.SAVED_VIEWS.PRIVATE');

const draftVisibilityLabel = computed(() =>
  visibilityLabel(draftVisibility.value)
);

const applyView = view => {
  emit('apply', { view });
  popoverRef.value?.hide?.();
};

const startCreate = () => {
  draftName.value = '';
  draftVisibility.value = 'private_view';
  isCreating.value = true;
};

const cancelCreate = () => {
  isCreating.value = false;
  draftName.value = '';
};

const submitCreate = () => {
  const name = draftName.value.trim();
  if (!name) return;
  emit('create', {
    name,
    visibility: draftVisibility.value,
    pipeline_id: props.pipelineId,
    config: props.currentConfig,
  });
  isCreating.value = false;
  draftName.value = '';
};

const changeVisibility = (view, visibility) => {
  if (view.visibility === visibility) return;
  emit('update', { id: view.id, visibility });
};

const requestDelete = view => {
  viewPendingDelete.value = view;
  confirmDeleteRef.value?.open?.();
};

const confirmDelete = () => {
  if (viewPendingDelete.value) {
    emit('delete', { id: viewPendingDelete.value.id });
  }
  viewPendingDelete.value = null;
};
</script>

<template>
  <Popover ref="popoverRef" align="end">
    <Button
      icon="i-lucide-bookmark"
      size="sm"
      variant="faded"
      color="slate"
      :label="t('CRM_KANBAN.LIST.SAVED_VIEWS.SAVE')"
    />
    <template #content>
      <div class="flex w-72 flex-col gap-1 p-2">
        <ul v-if="views.length" class="flex flex-col gap-0.5">
          <li
            v-for="view in views"
            :key="view.id"
            class="group flex items-center gap-2 rounded-md px-1.5 py-1.5 text-sm transition-colors hover:bg-n-alpha-2"
          >
            <span
              class="i-lucide-bookmark size-4 flex-shrink-0 text-n-slate-10"
            />
            <button
              type="button"
              class="min-w-0 flex-1 truncate text-left text-n-slate-12"
              @click="applyView(view)"
            >
              {{ view.name }}
            </button>
            <SelectMenu
              :model-value="view.visibility"
              :options="visibilityOptions"
              :label="visibilityLabel(view.visibility)"
              sub-menu-position="bottom"
              @update:model-value="value => changeVisibility(view, value)"
            />
            <Button
              icon="i-lucide-trash-2"
              size="sm"
              variant="ghost"
              color="ruby"
              @click="requestDelete(view)"
            />
          </li>
        </ul>

        <div v-if="!isCreating" class="border-t border-n-weak pt-1">
          <Button
            icon="i-lucide-plus"
            size="sm"
            variant="ghost"
            color="slate"
            class="!w-full !justify-start"
            :label="t('CRM_KANBAN.LIST.SAVED_VIEWS.NEW')"
            @click="startCreate"
          />
        </div>

        <div v-else class="flex flex-col gap-2 border-t border-n-weak pt-2">
          <Input
            v-model="draftName"
            size="sm"
            autofocus
            :placeholder="t('CRM_KANBAN.LIST.SAVED_VIEWS.NEW')"
            @enter="submitCreate"
          />
          <div class="flex items-center justify-between gap-2">
            <SelectMenu
              v-model="draftVisibility"
              :options="visibilityOptions"
              :label="draftVisibilityLabel"
              sub-menu-position="bottom"
            />
            <div class="flex items-center gap-1">
              <Button
                size="sm"
                variant="faded"
                color="slate"
                :label="t('CRM_KANBAN.CONFIRM.CANCEL')"
                @click="cancelCreate"
              />
              <Button
                size="sm"
                variant="solid"
                color="blue"
                :disabled="!draftName.trim()"
                :label="t('CRM_KANBAN.LIST.SAVED_VIEWS.SAVE')"
                @click="submitCreate"
              />
            </div>
          </div>
        </div>
      </div>
    </template>
  </Popover>

  <Dialog
    ref="confirmDeleteRef"
    type="alert"
    :title="t('CRM_KANBAN.LIST.SAVED_VIEWS.DELETE')"
    :description="viewPendingDelete?.name"
    :confirm-button-label="t('CRM_KANBAN.LIST.SAVED_VIEWS.DELETE')"
    @confirm="confirmDelete"
  />
</template>
