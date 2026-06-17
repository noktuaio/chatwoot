/**
 * calendarEvents.js — pure helpers for the CRM calendar (Lista & Calendário v2).
 *
 * The calendar shows three overlapping "calendars" (overlays), keyed by event TYPE:
 *   - reminder   → follow-up reminder-only / snooze-conversation (task-like, can be overdue)
 *   - whatsapp   → scheduled WhatsApp auto-send (precise instant, cannot move to the past)
 *   - closeDate  → expected_close forecast (a deal milestone, drag mutates the deal date)
 *
 * Calendar events come from `GET /crm/calendar/events`, each:
 *   { id, event_type, title, starts_at (ISO8601), status, card_id, conversation_id,
 *     contact_id, inbox_id, assignee_id }
 *
 * pt_BR / CLDR: the week starts on SUNDAY (weekStartsOn: 0). All range builders and
 * grouping default to Sunday-first.
 *
 * No new npm deps: date-fns + date-fns/locale/pt-BR only.
 */
import {
  startOfMonth,
  endOfMonth,
  startOfWeek,
  endOfWeek,
  startOfDay,
  endOfDay,
  addDays,
  isSameDay,
  isBefore,
  format,
} from 'date-fns';
import { ptBR } from 'date-fns/locale';

/* -------------------------------------------------------------------------- */
/* Event type → overlay group                                                 */
/* -------------------------------------------------------------------------- */

export const OVERLAY_GROUP = {
  REMINDER: 'reminder',
  WHATSAPP: 'whatsapp',
  CLOSE_DATE: 'closeDate',
};

/**
 * Map a backend `event_type` to one of the three overlay groups.
 * @param {String} eventType
 * @returns {'reminder'|'whatsapp'|'closeDate'}
 */
export const EVENT_TYPE_GROUP = eventType => {
  switch (eventType) {
    case 'expected_close':
      return OVERLAY_GROUP.CLOSE_DATE;
    case 'follow_up_auto_send_message':
      return OVERLAY_GROUP.WHATSAPP;
    case 'follow_up_reminder_only':
    case 'follow_up_snooze_conversation':
    default:
      return OVERLAY_GROUP.REMINDER;
  }
};

/**
 * Visual metadata per overlay group: color token + i-lucide icon.
 *  - reminder  → teal  + bell
 *  - whatsapp  → brand + message-circle
 *  - closeDate → amber + target
 */
export const EVENT_TYPE_META = {
  [OVERLAY_GROUP.REMINDER]: {
    group: OVERLAY_GROUP.REMINDER,
    icon: 'i-lucide-bell',
    dotClass: 'bg-n-teal-9',
    textClass: 'text-n-teal-11',
    pillClass: 'bg-n-teal-9/10 text-n-teal-11',
    overlayKey: 'reminders',
  },
  [OVERLAY_GROUP.WHATSAPP]: {
    group: OVERLAY_GROUP.WHATSAPP,
    icon: 'i-lucide-message-circle',
    dotClass: 'bg-n-brand',
    textClass: 'text-n-blue-11',
    pillClass: 'bg-n-brand/10 text-n-blue-11',
    overlayKey: 'whatsapp',
  },
  [OVERLAY_GROUP.CLOSE_DATE]: {
    group: OVERLAY_GROUP.CLOSE_DATE,
    icon: 'i-lucide-target',
    dotClass: 'bg-n-amber-9',
    textClass: 'text-n-amber-11',
    pillClass: 'bg-n-amber-9/10 text-n-amber-11',
    overlayKey: 'closeDates',
  },
};

/** Metadata for a raw event. */
export const eventMeta = event =>
  EVENT_TYPE_META[EVENT_TYPE_GROUP(event.event_type)];

/** i-lucide icon class for an event. */
export const eventIconClass = event => eventMeta(event).icon;

/** Colored dot / text classes for an event (Tailwind tokens only). */
export const eventColorClass = event => eventMeta(event).dotClass;
export const eventTextClass = event => eventMeta(event).textClass;
export const eventPillClass = event => eventMeta(event).pillClass;

/* -------------------------------------------------------------------------- */
/* Timestamp parsing — accept ISO8601 strings AND epoch seconds/ms            */
/* (mirrors the list's `toDate` so realtime upserts stay consistent)          */
/* -------------------------------------------------------------------------- */

export const toDate = value => {
  if (value === null || value === undefined || value === '') return null;
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }
  if (typeof value === 'number') {
    // epoch seconds (board/realtime) vs ms — seconds are < 1e12.
    const ms = value < 1e12 ? value * 1000 : value;
    const d = new Date(ms);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (/^\d+$/.test(value)) {
    return toDate(Number(value));
  }
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
};

/** The Date an event starts at (or null). */
export const eventStart = event => toDate(event?.starts_at);

/* -------------------------------------------------------------------------- */
/* Overdue / draggable rules (the 3 types are NOT symmetric)                  */
/* -------------------------------------------------------------------------- */

const DONE_STATUSES = ['done', 'completed', 'sent', 'cancelled', 'canceled'];

const isEventDone = event =>
  DONE_STATUSES.includes(String(event?.status || '').toLowerCase());

/**
 * A reminder/forecast is overdue when its start is in the past and it is not done.
 * A WhatsApp auto-send in the past = already sent (done), never "overdue".
 */
export const isOverdue = (event, now = new Date()) => {
  if (isEventDone(event)) return false;
  if (EVENT_TYPE_GROUP(event.event_type) === OVERLAY_GROUP.WHATSAPP)
    return false;
  const start = eventStart(event);
  if (!start) return false;
  return isBefore(start, now);
};

/** Count of overdue events in a set. */
export const overdueCount = (events = [], now = new Date()) =>
  events.reduce((acc, e) => (isOverdue(e, now) ? acc + 1 : acc), 0);

/**
 * Drag-to-reschedule eligibility:
 *  - done/sent/cancelled events are read-only;
 *  - WhatsApp already in the past is read-only.
 */
export const isDraggable = (event, now = new Date()) => {
  if (isEventDone(event)) return false;
  if (EVENT_TYPE_GROUP(event.event_type) === OVERLAY_GROUP.WHATSAPP) {
    const start = eventStart(event);
    if (start && isBefore(start, now)) return false;
  }
  return true;
};

/** WhatsApp drops cannot target the past. */
export const isValidDrop = (event, targetDate, now = new Date()) => {
  if (!isDraggable(event, now)) return false;
  if (EVENT_TYPE_GROUP(event.event_type) === OVERLAY_GROUP.WHATSAPP) {
    return !isBefore(endOfDay(targetDate), now);
  }
  return true;
};

/* -------------------------------------------------------------------------- */
/* Overlay + owner filtering                                                  */
/* -------------------------------------------------------------------------- */

/**
 * Keep only events whose overlay group is toggled on.
 * @param {Array} events
 * @param {{reminders:Bool, whatsapp:Bool, closeDates:Bool}} overlays
 */
export const filterByOverlays = (events = [], overlays = {}) => {
  const enabled = {
    reminders: overlays.reminders !== false,
    whatsapp: overlays.whatsapp !== false,
    closeDates: overlays.closeDates !== false,
  };
  return events.filter(e => enabled[eventMeta(e).overlayKey]);
};

/**
 * Filter by owner scope. scope 'mine' keeps events assigned to the current user;
 * 'all' keeps everything.
 */
export const filterByOwner = (events = [], scope = 'all', userId = null) => {
  if (scope !== 'mine' || userId === null || userId === undefined)
    return events;
  return events.filter(e => Number(e.assignee_id) === Number(userId));
};

/* -------------------------------------------------------------------------- */
/* Range builders (pt_BR / CLDR — Sunday first)                               */
/* -------------------------------------------------------------------------- */

const WEEK_OPTS = { weekStartsOn: 0, locale: ptBR };

/**
 * Visible range for the Month view: the full weeks (Sun..Sat) that the month
 * touches — what the 7-column grid actually renders. Returns { from, to }.
 */
export const monthRange = cursorDate => {
  const from = startOfWeek(startOfMonth(cursorDate), WEEK_OPTS);
  const to = endOfWeek(endOfMonth(cursorDate), WEEK_OPTS);
  return { from, to };
};

/** Visible range for the Week view (Sun..Sat). */
export const weekRange = cursorDate => {
  const from = startOfWeek(cursorDate, WEEK_OPTS);
  const to = endOfWeek(cursorDate, WEEK_OPTS);
  return { from, to };
};

/** Visible range for the Day view. */
export const dayRange = cursorDate => ({
  from: startOfDay(cursorDate),
  to: endOfDay(cursorDate),
});

/** The matrix of Date cells (rows of 7) covering the month grid. */
export const monthMatrix = cursorDate => {
  const { from, to } = monthRange(cursorDate);
  const days = [];
  let cursor = from;
  while (cursor <= to) {
    days.push(cursor);
    cursor = addDays(cursor, 1);
  }
  const weeks = [];
  for (let i = 0; i < days.length; i += 7) {
    weeks.push(days.slice(i, i + 7));
  }
  return weeks;
};

/** The 7 Date cells (Sun..Sat) of the week containing cursorDate. */
export const weekDays = cursorDate => {
  const start = startOfWeek(cursorDate, WEEK_OPTS);
  return Array.from({ length: 7 }, (_, i) => addDays(start, i));
};

/** The localized one-letter / short weekday headers, Sunday-first. */
export const weekdayLabels = (formatStr = 'EEEEEE') => {
  const start = startOfWeek(new Date(), WEEK_OPTS);
  return Array.from({ length: 7 }, (_, i) =>
    format(addDays(start, i), formatStr, { locale: ptBR })
  );
};

/* -------------------------------------------------------------------------- */
/* Grouping / lookup                                                          */
/* -------------------------------------------------------------------------- */

/** Events that fall on a given calendar day, sorted chronologically. */
export const eventsForDay = (events, day) =>
  (events || [])
    .filter(e => {
      const start = eventStart(e);
      return start && isSameDay(start, day);
    })
    .sort((a, b) => {
      const sa = eventStart(a);
      const sb = eventStart(b);
      return (sa ? sa.getTime() : 0) - (sb ? sb.getTime() : 0);
    });

/**
 * Group events by day for the Agenda view.
 * Returns an ordered array of { date: Date, key: 'yyyy-MM-dd', events: [] }.
 */
export const groupEventsByDay = (events = []) => {
  const buckets = new Map();
  events.forEach(event => {
    const start = eventStart(event);
    if (!start) return;
    const key = format(start, 'yyyy-MM-dd');
    if (!buckets.has(key)) {
      buckets.set(key, { date: startOfDay(start), key, events: [] });
    }
    buckets.get(key).events.push(event);
  });
  return Array.from(buckets.values())
    .sort((a, b) => a.date.getTime() - b.date.getTime())
    .map(bucket => ({
      ...bucket,
      events: bucket.events.sort((a, b) => {
        const sa = eventStart(a);
        const sb = eventStart(b);
        return (sa ? sa.getTime() : 0) - (sb ? sb.getTime() : 0);
      }),
    }));
};

/* -------------------------------------------------------------------------- */
/* pt_BR formatters                                                           */
/* -------------------------------------------------------------------------- */

/** Period title for the header, by view ('month'|'week'|'day'|'agenda'). */
export const periodTitle = (view, cursorDate) => {
  switch (view) {
    case 'week': {
      const { from, to } = weekRange(cursorDate);
      return `${format(from, "d 'de' MMM", { locale: ptBR })} – ${format(
        to,
        "d 'de' MMM 'de' yyyy",
        { locale: ptBR }
      )}`;
    }
    case 'day':
      return format(cursorDate, "EEEE, d 'de' MMMM 'de' yyyy", {
        locale: ptBR,
      });
    case 'month':
    case 'agenda':
    default:
      return format(cursorDate, "MMMM 'de' yyyy", { locale: ptBR });
  }
};

/** Short day-label for an agenda bucket ("seg, 10 de jun"). */
export const dayHeading = date =>
  format(date, "EEE, d 'de' MMM", { locale: ptBR });

/** Time-only label (24h). */
export const formatTime = value => {
  const d = toDate(value);
  if (!d) return '';
  return format(d, 'HH:mm', { locale: ptBR });
};

/** The hours rendered in week/day time-grids. */
export const DAY_HOURS = Array.from({ length: 24 }, (_, h) => h);

export { isSameDay, ptBR };
