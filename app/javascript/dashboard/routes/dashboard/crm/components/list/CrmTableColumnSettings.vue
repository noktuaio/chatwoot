<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

const props = defineProps({
  // Each column: { id:String, label:String, visible:Boolean, hideable:Boolean }
  columns: {
    type: Array,
    required: true,
  },
  density: {
    type: String,
    default: 'comfortable',
    validator: value => ['comfortable', 'compact'].includes(value),
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const popoverRef = ref(null);
const dragIndex = ref(null);
const dragOverIndex = ref(null);

const orderedColumns = computed(() => props.columns);

const emitUpdate = patch => {
  emit('update', {
    columns: props.columns.map(column => ({ ...column })),
    density: props.density,
    ...patch,
  });
};

const toggleColumn = column => {
  if (column.hideable === false) return;
  const next = props.columns.map(item =>
    item.id === column.id ? { ...item, visible: !item.visible } : { ...item }
  );
  emitUpdate({ columns: next });
};

const setDensity = density => {
  if (density === props.density) return;
  emitUpdate({ density });
};

const reset = () => {
  emit('update', { reset: true });
};

const onDragStart = index => {
  dragIndex.value = index;
};

const onDragOver = index => {
  dragOverIndex.value = index;
};

const onDrop = index => {
  const from = dragIndex.value;
  dragIndex.value = null;
  dragOverIndex.value = null;
  if (from === null || from === index) return;
  const next = [...props.columns];
  const [moved] = next.splice(from, 1);
  next.splice(index, 0, moved);
  emitUpdate({ columns: next.map(item => ({ ...item })) });
};

const onDragEnd = () => {
  dragIndex.value = null;
  dragOverIndex.value = null;
};
</script>

<template>
  <Popover ref="popoverRef" align="end">
    <Button
      icon="i-lucide-settings-2"
      size="sm"
      variant="faded"
      color="slate"
      :label="t('CRM_KANBAN.LIST.COLUMN_SETTINGS')"
    />
    <template #content>
      <div class="flex w-64 flex-col gap-1 p-2">
        <div
          class="flex items-center justify-between px-1.5 pb-1 text-xs font-medium text-n-slate-11"
        >
          <span>{{ t('CRM_KANBAN.LIST.COLUMN_SETTINGS') }}</span>
          <button
            type="button"
            class="rounded px-1.5 py-0.5 text-xs text-n-brand hover:bg-n-alpha-2"
            @click="reset"
          >
            {{ t('CRM_KANBAN.LIST.RESET_COLUMNS') }}
          </button>
        </div>

        <ul class="flex flex-col gap-0.5">
          <li
            v-for="(column, index) in orderedColumns"
            :key="column.id"
            draggable="true"
            class="flex items-center gap-2 rounded-md px-1.5 py-1.5 text-sm transition-colors hover:bg-n-alpha-2"
            :class="{
              'opacity-50': dragIndex === index,
              'border-t border-n-brand':
                dragOverIndex === index && dragIndex !== index,
            }"
            @dragstart="onDragStart(index)"
            @dragover.prevent="onDragOver(index)"
            @drop.prevent="onDrop(index)"
            @dragend="onDragEnd"
          >
            <span
              class="i-lucide-grip-vertical size-4 flex-shrink-0 cursor-grab text-n-slate-10"
            />
            <Checkbox
              :model-value="column.visible"
              :disabled="column.hideable === false"
              @change="toggleColumn(column)"
            />
            <span
              class="min-w-0 flex-1 cursor-pointer truncate text-n-slate-12"
              @click="toggleColumn(column)"
            >
              {{ column.label }}
            </span>
          </li>
        </ul>

        <div class="mt-1 border-t border-n-weak pt-2">
          <p class="mb-1 px-1.5 text-xs font-medium text-n-slate-11">
            {{ t('CRM_KANBAN.LIST.DENSITY') }}
          </p>
          <div class="flex gap-1 px-1.5">
            <Button
              size="sm"
              class="flex-1"
              :variant="density === 'comfortable' ? 'solid' : 'faded'"
              color="slate"
              :label="t('CRM_KANBAN.LIST.DENSITY_COMFORTABLE')"
              @click="setDensity('comfortable')"
            />
            <Button
              size="sm"
              class="flex-1"
              :variant="density === 'compact' ? 'solid' : 'faded'"
              color="slate"
              :label="t('CRM_KANBAN.LIST.DENSITY_COMPACT')"
              @click="setDensity('compact')"
            />
          </div>
        </div>
      </div>
    </template>
  </Popover>
</template>
