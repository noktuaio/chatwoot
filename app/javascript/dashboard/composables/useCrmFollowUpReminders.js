import { computed, ref } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

const queue = ref([]);
const seenIds = new Set();

const isCrmEnabled = () =>
  window.globalConfig?.CRM_KANBAN_ENABLED === 'true' ||
  window.globalConfig?.crmKanbanEnabled === true;

export function useCrmFollowUpReminders() {
  const activeReminder = computed(() => queue.value[0] || null);
  const hasReminder = computed(() => queue.value.length > 0);

  const normalizeReminder = payload => ({
    ...payload,
    account_id:
      payload.account_id ||
      window.chatwootConfig?.accountId ||
      window.chatwootConfig?.account_id,
  });

  const enqueueReminder = payload => {
    if (!isCrmEnabled() || !payload?.id) return;
    if (seenIds.has(payload.id)) return;
    if (queue.value.some(item => item.id === payload.id)) return;

    seenIds.add(payload.id);
    queue.value.push(normalizeReminder(payload));
  };

  const dequeueReminder = () => {
    const removed = queue.value.shift();
    if (removed?.id !== undefined) {
      seenIds.delete(removed.id);
    }
  };

  const fetchMissedReminders = async () => {
    if (!isCrmEnabled()) return;

    try {
      const response = await CrmKanbanAPI.getFollowUpReminders();
      (response.data.payload || []).forEach(enqueueReminder);
    } catch {
      // Non-blocking bootstrap for popup reminders.
    }
  };

  const completeReminder = async (id, accountId) => {
    try {
      await CrmKanbanAPI.completeFollowUpForAccount(accountId, id);
    } finally {
      // Always dismiss the popup on click, even if the API rejects
      // (e.g. cross-account 404 or an already-completed reminder).
      dequeueReminder();
    }
  };

  const dismissReminder = async (id, accountId) => {
    try {
      await CrmKanbanAPI.dismissFollowUpReminderForAccount(accountId, id);
    } finally {
      dequeueReminder();
    }
  };

  return {
    activeReminder,
    hasReminder,
    enqueueReminder,
    dequeueReminder,
    fetchMissedReminders,
    completeReminder,
    dismissReminder,
    isCrmEnabled,
  };
}
