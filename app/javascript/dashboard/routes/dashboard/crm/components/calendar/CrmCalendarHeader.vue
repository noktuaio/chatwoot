<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import DatePicker from 'vue-datepicker-next';

import Button from 'dashboard/components-next/button/Button.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import { periodTitle } from './calendarEvents.js';

const props = defineProps({
  view: {
    type: String,
    default: 'month',
    validator: v => ['month', 'week', 'day', 'agenda'].includes(v),
  },
  cursorDate: {
    type: Date,
    required: true,
  },
  overlays: {
    type: Object,
    default: () => ({ reminders: true, whatsapp: true, closeDates: true }),
  },
  ownerScope: {
    type: String,
    default: 'all',
    validator: v => ['mine', 'all'].includes(v),
  },
  overdueCount: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits([
  'prev',
  'next',
  'today',
  'update:view',
  'update:cursorDate',
  'update:overlays',
  'update:ownerScope',
  'quickAdd',
]);

const { t } = useI18n();

/* ----------------------------- View switcher ----------------------------- */
const VIEW_ORDER = ['month', 'week', 'day', 'agenda'];

const viewTabs = computed(() => [
  { label: t('CRM_KANBAN.CALENDAR.VIEW.MONTH'), key: 'month' },
  { label: t('CRM_KANBAN.CALENDAR.VIEW.WEEK'), key: 'week' },
  { label: t('CRM_KANBAN.CALENDAR.VIEW.DAY'), key: 'day' },
  { label: t('CRM_KANBAN.CALENDAR.VIEW.AGENDA'), key: 'agenda' },
]);

const activeViewIndex = computed(() => VIEW_ORDER.indexOf(props.view));

const onViewChanged = tab => emit('update:view', tab.key);

/* ----------------------------- Period title ------------------------------ */
const title = computed(() => periodTitle(props.view, props.cursorDate));

/* ----------------------------- Owner scope ------------------------------- */
const ownerScopeTabs = computed(() => [
  { label: t('CRM_KANBAN.CALENDAR.OWNER_SCOPE_ALL'), key: 'all' },
  { label: t('CRM_KANBAN.CALENDAR.OWNER_SCOPE_MINE'), key: 'mine' },
]);

const activeOwnerScopeIndex = computed(() =>
  props.ownerScope === 'mine' ? 1 : 0
);

const onOwnerScopeChanged = tab => emit('update:ownerScope', tab.key);

/* ----------------------------- Overlays ---------------------------------- */
const overlayDefs = computed(() => [
  {
    key: 'reminders',
    label: t('CRM_KANBAN.CALENDAR.OVERLAY.REMINDERS'),
    icon: 'i-lucide-bell',
    activeClass: 'bg-n-teal-9/10 text-n-teal-11 outline-n-teal-9',
    dotClass: 'bg-n-teal-9',
  },
  {
    key: 'whatsapp',
    label: t('CRM_KANBAN.CALENDAR.OVERLAY.WHATSAPP'),
    icon: 'i-lucide-message-circle',
    activeClass: 'bg-n-brand/10 text-n-blue-11 outline-n-brand',
    dotClass: 'bg-n-brand',
  },
  {
    key: 'closeDates',
    label: t('CRM_KANBAN.CALENDAR.OVERLAY.CLOSE_DATES'),
    icon: 'i-lucide-target',
    activeClass: 'bg-n-amber-9/10 text-n-amber-11 outline-n-amber-9',
    dotClass: 'bg-n-amber-9',
  },
]);

const toggleOverlay = key =>
  emit('update:overlays', {
    ...props.overlays,
    [key]: !(props.overlays[key] !== false),
  });

const isOverlayOn = key => props.overlays[key] !== false;

/* ----------------------------- Mini date picker -------------------------- */
const datePickerPopover = ref(null);

const lang = computed(() => ({
  formatLocale: { firstDayOfWeek: 0 },
  monthBeforeYear: false,
}));

const miniDate = computed({
  get: () => props.cursorDate,
  set: value => {
    if (value) emit('update:cursorDate', value);
  },
});

const onMiniDatePick = value => {
  if (value) emit('update:cursorDate', value);
  datePickerPopover.value?.hide();
};
</script>

<template>
  <header class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <!-- Left: today + chevrons + title -->
      <div class="flex items-center gap-2">
        <Button
          variant="outline"
          color="slate"
          size="sm"
          :label="t('CRM_KANBAN.CALENDAR.TODAY')"
          @click="emit('today')"
        />
        <div class="flex items-center">
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-chevron-left"
            :aria-label="t('CRM_KANBAN.CALENDAR.VIEW.MONTH')"
            @click="emit('prev')"
          />
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-chevron-right"
            :aria-label="t('CRM_KANBAN.CALENDAR.VIEW.MONTH')"
            @click="emit('next')"
          />
        </div>

        <Popover ref="datePickerPopover" align="start">
          <template #default>
            <button
              type="button"
              class="inline-flex items-center gap-2 rounded-lg px-2 py-1 text-base font-medium capitalize text-n-slate-12 outline-1 outline-transparent hover:bg-n-alpha-2"
            >
              <span>{{ title }}</span>
              <span class="i-lucide-chevron-down size-4 text-n-slate-10" />
            </button>
          </template>
          <template #content>
            <div class="p-2">
              <DatePicker
                v-model:value="miniDate"
                type="date"
                inline
                :lang="lang"
                @change="onMiniDatePick"
              />
            </div>
          </template>
        </Popover>

        <span
          v-if="overdueCount > 0"
          class="inline-flex items-center gap-1 rounded-full bg-n-ruby-9/10 px-2 py-0.5 text-xs font-medium text-n-ruby-11"
        >
          <span class="i-lucide-alarm-clock size-3" />
          {{ t('CRM_KANBAN.CALENDAR.OVERDUE_COUNT', { n: overdueCount }) }}
        </span>
      </div>

      <!-- Right: view switcher + new -->
      <div class="flex items-center gap-2">
        <TabBar
          :tabs="viewTabs"
          :initial-active-tab="activeViewIndex"
          @tab-changed="onViewChanged"
        />
        <Button
          variant="solid"
          color="blue"
          size="sm"
          icon="i-lucide-plus"
          :label="t('CRM_KANBAN.CALENDAR.NEW')"
          @click="emit('quickAdd')"
        />
      </div>
    </div>

    <!-- Second row: overlays + owner scope -->
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="flex flex-wrap items-center gap-2">
        <button
          v-for="overlay in overlayDefs"
          :key="overlay.key"
          type="button"
          class="inline-flex items-center gap-2 rounded-lg px-2.5 py-1 text-xs font-medium outline-1 transition-colors duration-100"
          :class="
            isOverlayOn(overlay.key)
              ? overlay.activeClass
              : 'bg-n-alpha-1 text-n-slate-10 outline-transparent hover:bg-n-alpha-2'
          "
          @click="toggleOverlay(overlay.key)"
        >
          <span
            class="size-2 rounded-full"
            :class="
              isOverlayOn(overlay.key) ? overlay.dotClass : 'bg-n-slate-7'
            "
          />
          {{ overlay.label }}
        </button>
      </div>

      <TabBar
        :tabs="ownerScopeTabs"
        :initial-active-tab="activeOwnerScopeIndex"
        @tab-changed="onOwnerScopeChanged"
      />
    </div>
  </header>
</template>
