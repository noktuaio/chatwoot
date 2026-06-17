<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { isSameMonth, isToday as dateFnsIsToday, format } from 'date-fns';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import {
  monthMatrix,
  weekdayLabels,
  eventsForDay,
  eventColorClass,
  isOverdue,
  isDraggable,
  isValidDrop,
  filterByOverlays,
  formatTime,
  ptBR,
} from './calendarEvents.js';

const props = defineProps({
  cursorDate: {
    type: Date,
    required: true,
  },
  events: {
    type: Array,
    default: () => [],
  },
  overlays: {
    type: Object,
    default: () => ({ reminders: true, whatsapp: true, closeDates: true }),
  },
});

const emit = defineEmits(['dayClick', 'eventClick', 'slotClick', 'eventDrop']);

const { t } = useI18n();

const MAX_VISIBLE = 2;

const weeks = computed(() => monthMatrix(props.cursorDate));
const weekdays = computed(() => weekdayLabels('EEEEEE'));

// Defensively respect the overlay toggles even though the parent pre-filters.
const shownEvents = computed(() =>
  filterByOverlays(props.events, props.overlays)
);

const dayKey = day => format(day, 'yyyy-MM-dd');

const isOutsideMonth = day => !isSameMonth(day, props.cursorDate);
const isCurrentDay = day => dateFnsIsToday(day);

const dayLabel = day => format(day, 'd', { locale: ptBR });
const fullDayLabel = day => format(day, "EEEE, d 'de' MMMM", { locale: ptBR });

// Memoize the per-day event list once per render (keyed by yyyy-MM-dd) so the
// three consumers below — visibleEvents, overflowCount and the overflow popover
// — share a single eventsForDay pass instead of recomputing it each.
const eventsByDayKey = computed(() => {
  const map = {};
  weeks.value.forEach(week => {
    week.forEach(day => {
      map[dayKey(day)] = eventsForDay(shownEvents.value, day);
    });
  });
  return map;
});

const dayEvents = day => eventsByDayKey.value[dayKey(day)] || [];
const visibleEvents = day => dayEvents(day).slice(0, MAX_VISIBLE);
const overflowCount = day => Math.max(0, dayEvents(day).length - MAX_VISIBLE);

const eventDotClass = event => eventColorClass(event);
const eventTitle = event => event.title || '';

const eventLabelClass = event =>
  isOverdue(event) ? 'text-n-ruby-11' : 'text-n-slate-12';

/* -------------------------------------------------------------------------- */
/* Drag-to-reschedule (native HTML5)                                          */
/* -------------------------------------------------------------------------- */

const draggingEvent = ref(null);
const dragOverKey = ref(null);

const onDragStart = (event, nativeEvent) => {
  if (!isDraggable(event)) {
    nativeEvent.preventDefault();
    return;
  }
  draggingEvent.value = event;
  if (nativeEvent.dataTransfer) {
    nativeEvent.dataTransfer.effectAllowed = 'move';
    nativeEvent.dataTransfer.setData('text/plain', String(event.id));
  }
};

const onDragEnd = () => {
  draggingEvent.value = null;
  dragOverKey.value = null;
};

const canDropOn = day => {
  const event = draggingEvent.value;
  if (!event) return false;
  return isValidDrop(event, day);
};

const onDragOver = (day, nativeEvent) => {
  if (!draggingEvent.value) return;
  if (!canDropOn(day)) {
    if (nativeEvent.dataTransfer) nativeEvent.dataTransfer.dropEffect = 'none';
    return;
  }
  nativeEvent.preventDefault();
  if (nativeEvent.dataTransfer) nativeEvent.dataTransfer.dropEffect = 'move';
  dragOverKey.value = dayKey(day);
};

const onDragLeave = day => {
  if (dragOverKey.value === dayKey(day)) dragOverKey.value = null;
};

const onDrop = day => {
  const event = draggingEvent.value;
  draggingEvent.value = null;
  dragOverKey.value = null;
  if (!event || !canDropOn(day)) return;
  emit('eventDrop', { event, date: day });
};

const isDropTarget = day => dragOverKey.value === dayKey(day);

/* -------------------------------------------------------------------------- */
/* Click handlers                                                             */
/* -------------------------------------------------------------------------- */

const onSlotClick = day => {
  emit('slotClick', { date: day });
};

const onDayNumberClick = day => {
  emit('dayClick', day);
};

const onEventClick = event => {
  emit('eventClick', event);
};
</script>

<template>
  <div class="flex flex-col w-full h-full min-h-0">
    <div class="grid grid-cols-7 border-b border-n-weak shrink-0">
      <div
        v-for="(label, idx) in weekdays"
        :key="`wd-${idx}`"
        class="px-2 py-2 text-xs font-medium text-center uppercase text-n-slate-10 truncate"
      >
        {{ label }}
      </div>
    </div>

    <div
      class="grid flex-1 grid-cols-7 auto-rows-[minmax(7rem,1fr)] min-h-0 overflow-y-auto"
    >
      <template v-for="(week, wIdx) in weeks" :key="`w-${wIdx}`">
        <div
          v-for="day in week"
          :key="dayKey(day)"
          class="flex flex-col min-h-[7rem] gap-1 p-1 border-b border-r border-n-weak transition-colors"
          :class="[
            isOutsideMonth(day) ? 'bg-n-alpha-black2' : 'bg-n-surface-1',
            isDropTarget(day)
              ? 'ring-2 ring-inset ring-n-brand bg-n-brand/5'
              : '',
          ]"
          @click="onSlotClick(day)"
          @dragover="onDragOver(day, $event)"
          @dragleave="onDragLeave(day)"
          @drop.prevent="onDrop(day)"
        >
          <div class="flex items-center justify-between px-1 shrink-0">
            <button
              type="button"
              class="inline-flex items-center justify-center w-6 h-6 text-xs font-medium rounded-full hover:bg-n-alpha-2"
              :class="[
                isCurrentDay(day)
                  ? 'bg-n-brand text-white'
                  : isOutsideMonth(day)
                    ? 'text-n-slate-9'
                    : 'text-n-slate-11',
              ]"
              :aria-label="fullDayLabel(day)"
              @click.stop="onDayNumberClick(day)"
            >
              {{ dayLabel(day) }}
            </button>
          </div>

          <div class="flex flex-col gap-0.5">
            <button
              v-for="event in visibleEvents(day)"
              :key="event.id"
              type="button"
              :draggable="isDraggable(event)"
              class="flex items-center w-full gap-1 px-1 py-0.5 text-left rounded cursor-pointer hover:bg-n-alpha-2"
              :class="{ 'cursor-grab': isDraggable(event) }"
              @click.stop="onEventClick(event)"
              @dragstart="onDragStart(event, $event)"
              @dragend="onDragEnd"
            >
              <span
                class="w-1.5 h-1.5 rounded-full shrink-0"
                :class="eventDotClass(event)"
              />
              <span
                v-if="formatTime(event.starts_at)"
                class="text-[10px] tabular-nums shrink-0 text-n-slate-10"
              >
                {{ formatTime(event.starts_at) }}
              </span>
              <span class="text-xs truncate" :class="eventLabelClass(event)">
                {{ eventTitle(event) }}
              </span>
            </button>

            <Popover v-if="overflowCount(day) > 0" align="start" @click.stop>
              <template #default>
                <button
                  type="button"
                  class="w-full px-1 py-0.5 text-xs font-medium text-left rounded text-n-slate-10 hover:bg-n-alpha-2"
                  @click.stop
                >
                  {{ t('CRM_KANBAN.CALENDAR.MORE', { n: overflowCount(day) }) }}
                </button>
              </template>
              <template #content="{ hide }">
                <div class="flex flex-col w-64 gap-1 p-3">
                  <div class="px-1 pb-1 text-xs font-medium text-n-slate-10">
                    {{ fullDayLabel(day) }}
                  </div>
                  <button
                    v-for="event in dayEvents(day)"
                    :key="`more-${event.id}`"
                    type="button"
                    class="flex items-center w-full gap-2 px-2 py-1.5 text-left rounded-md hover:bg-n-alpha-2"
                    @click.stop="
                      onEventClick(event);
                      hide();
                    "
                  >
                    <span
                      class="w-2 h-2 rounded-full shrink-0"
                      :class="eventDotClass(event)"
                    />
                    <span
                      v-if="formatTime(event.starts_at)"
                      class="text-[11px] tabular-nums shrink-0 text-n-slate-10"
                    >
                      {{ formatTime(event.starts_at) }}
                    </span>
                    <span
                      class="text-sm truncate"
                      :class="eventLabelClass(event)"
                    >
                      {{ eventTitle(event) }}
                    </span>
                  </button>
                </div>
              </template>
            </Popover>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
