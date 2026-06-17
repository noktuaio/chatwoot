<script setup>
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, isSameDay } from 'date-fns';
import { ptBR, enUS } from 'date-fns/locale';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  EVENT_TYPE_GROUP,
  EVENT_TYPE_META,
  eventStart,
  isOverdue,
} from './calendarEvents.js';

const props = defineProps({
  events: { type: Array, default: () => [] },
  overlays: {
    type: Object,
    default: () => ({ reminders: true, whatsapp: true, closeDates: true }),
  },
  isLoading: { type: Boolean, default: false },
  hasError: { type: Boolean, default: false },
});

const emit = defineEmits(['eventClick', 'quickAdd', 'retry']);

const { t, locale } = useI18n();

const dateFnsLocale = computed(() => (locale.value === 'pt_BR' ? ptBR : enUS));

// Live "now" — refreshed every 60s so the overdue/upcoming partition never
// goes stale (mirrors the now-line clock in CrmCalendarWeekGrid/DayGrid).
const now = ref(new Date());
let nowTimer = null;

onMounted(() => {
  nowTimer = setInterval(() => {
    now.value = new Date();
  }, 60 * 1000);
});

onBeforeUnmount(() => {
  if (nowTimer) clearInterval(nowTimer);
});

const overlayKeyForGroup = {
  reminder: 'reminders',
  whatsapp: 'whatsapp',
  closeDate: 'closeDates',
};

const typeKeyForGroup = {
  reminder: 'REMINDER',
  whatsapp: 'WHATSAPP',
  closeDate: 'CLOSE',
};

const visibleEvents = computed(() =>
  props.events.filter(event => {
    const group = EVENT_TYPE_GROUP(event.event_type);
    const overlayKey = overlayKeyForGroup[group];
    return props.overlays?.[overlayKey] !== false;
  })
);

const sortedEvents = computed(() =>
  [...visibleEvents.value].sort(
    (a, b) => eventStart(a).getTime() - eventStart(b).getTime()
  )
);

const overdueEvents = computed(() =>
  sortedEvents.value.filter(event => isOverdue(event, now.value))
);

const upcomingEvents = computed(() =>
  sortedEvents.value.filter(event => !isOverdue(event, now.value))
);

const dayBuckets = computed(() => {
  const buckets = [];
  upcomingEvents.value.forEach(event => {
    const start = eventStart(event);
    const last = buckets[buckets.length - 1];
    if (last && isSameDay(last.date, start)) {
      last.events.push(event);
    } else {
      buckets.push({ date: start, events: [event] });
    }
  });
  return buckets;
});

const dayLabel = date =>
  format(date, "EEEE, dd 'de' MMMM", { locale: dateFnsLocale.value });

const timeLabel = event =>
  format(eventStart(event), 'HH:mm', { locale: dateFnsLocale.value });

const metaFor = event => EVENT_TYPE_META[EVENT_TYPE_GROUP(event.event_type)];

const typeKeyFor = event => typeKeyForGroup[EVENT_TYPE_GROUP(event.event_type)];

const hasEvents = computed(
  () => overdueEvents.value.length > 0 || upcomingEvents.value.length > 0
);

const onEventClick = event => emit('eventClick', event);
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col">
    <div
      v-if="isLoading"
      class="flex h-56 items-center justify-center"
      data-testid="agenda-loading"
    >
      <Spinner />
    </div>

    <div
      v-else-if="hasError"
      class="flex h-56 flex-col items-center justify-center gap-3 rounded-lg border border-dashed border-n-weak px-6 text-center"
    >
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('CRM_KANBAN.CALENDAR.RESCHEDULE_ERROR') }}
      </p>
      <Button
        variant="outline"
        color="slate"
        size="sm"
        icon="i-lucide-refresh-cw"
        :label="t('CRM_KANBAN.CALENDAR.RETRY')"
        @click="emit('retry')"
      />
    </div>

    <div
      v-else-if="!hasEvents"
      class="flex h-56 flex-col items-center justify-center gap-3 rounded-lg border border-dashed border-n-weak px-6 text-center"
    >
      <div>
        <p class="mb-1 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.CALENDAR.EMPTY_TITLE') }}
        </p>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('CRM_KANBAN.CALENDAR.EMPTY_HELP') }}
        </p>
      </div>
      <Button
        variant="solid"
        color="blue"
        size="sm"
        icon="i-lucide-plus"
        :label="t('CRM_KANBAN.CALENDAR.NEW')"
        @click="emit('quickAdd')"
      />
    </div>

    <div v-else class="flex flex-col gap-6">
      <section v-if="overdueEvents.length" class="flex flex-col gap-2">
        <header class="flex items-center gap-2">
          <span class="i-lucide-alert-triangle size-4 text-n-ruby-9" />
          <h3
            class="mb-0 text-xs font-semibold uppercase tracking-wide text-n-ruby-11"
          >
            {{
              t('CRM_KANBAN.CALENDAR.OVERDUE_COUNT', {
                n: overdueEvents.length,
              })
            }}
          </h3>
        </header>
        <ul class="flex flex-col gap-2">
          <li
            v-for="event in overdueEvents"
            :key="`${event.event_type}-${event.id}`"
          >
            <button
              type="button"
              class="grid w-full grid-cols-[auto_1fr_auto] items-start gap-3 rounded-lg border border-n-ruby-9/40 bg-n-ruby-9/5 p-3 text-left transition-colors hover:bg-n-ruby-9/10"
              @click="onEventClick(event)"
            >
              <span
                class="mt-0.5 flex size-8 items-center justify-center rounded-lg bg-n-ruby-9/15"
              >
                <span
                  class="size-4 text-n-ruby-11"
                  :class="[metaFor(event).icon]"
                />
              </span>
              <span class="min-w-0">
                <span
                  class="block truncate text-sm font-medium text-n-slate-12"
                >
                  {{ event.title }}
                </span>
                <span class="block truncate text-xs text-n-ruby-11">
                  {{ t(`CRM_KANBAN.CALENDAR.TYPE.${typeKeyFor(event)}`) }}
                </span>
              </span>
              <span
                class="whitespace-nowrap text-xs font-medium text-n-ruby-11"
              >
                {{ timeLabel(event) }}
              </span>
            </button>
          </li>
        </ul>
      </section>

      <section
        v-for="bucket in dayBuckets"
        :key="bucket.date.toISOString()"
        class="flex flex-col gap-2"
      >
        <header class="flex items-center gap-2">
          <h3
            class="mb-0 text-xs font-semibold uppercase tracking-wide text-n-slate-11"
          >
            {{ dayLabel(bucket.date) }}
          </h3>
        </header>
        <ul class="flex flex-col gap-2">
          <li
            v-for="event in bucket.events"
            :key="`${event.event_type}-${event.id}`"
          >
            <button
              type="button"
              class="grid w-full grid-cols-[auto_1fr_auto] items-start gap-3 rounded-lg border border-n-weak bg-n-surface-2 p-3 text-left transition-colors hover:bg-n-alpha-2"
              :class="{
                'opacity-60':
                  event.status === 'sent' || event.status === 'done',
              }"
              @click="onEventClick(event)"
            >
              <span
                class="mt-0.5 flex size-8 items-center justify-center rounded-lg bg-n-alpha-2"
              >
                <span
                  class="size-4"
                  :class="[metaFor(event).icon, metaFor(event).textClass]"
                />
              </span>
              <span class="min-w-0">
                <span
                  class="block truncate text-sm font-medium text-n-slate-12"
                >
                  {{ event.title }}
                </span>
                <span class="block truncate text-xs text-n-slate-11">
                  {{ t(`CRM_KANBAN.CALENDAR.TYPE.${typeKeyFor(event)}`) }}
                </span>
              </span>
              <span class="whitespace-nowrap text-xs text-n-slate-11">
                {{ timeLabel(event) }}
              </span>
            </button>
          </li>
        </ul>
      </section>
    </div>
  </div>
</template>
