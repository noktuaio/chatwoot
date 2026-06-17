<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import BaseTable from 'dashboard/components-next/table/BaseTable.vue';
import BaseTableRow from 'dashboard/components-next/table/BaseTableRow.vue';
import BaseTableCell from 'dashboard/components-next/table/BaseTableCell.vue';
import CrmScheduleEditor from './CrmScheduleEditor.vue';
import CrmServiceSchedulesAPI from 'dashboard/api/crmServiceSchedules';

const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');

const schedules = ref([]);
const isLoading = ref(false);
const editingInbox = ref(null);

const fetchSchedules = async () => {
  isLoading.value = true;
  try {
    const response = await CrmServiceSchedulesAPI.get();
    schedules.value = response.data.payload || [];
  } catch (error) {
    schedules.value = [];
  } finally {
    isLoading.value = false;
  }
};

onMounted(fetchSchedules);

const scheduleFor = inboxId =>
  schedules.value.find(
    schedule => schedule.owner_type === 'Inbox' && schedule.owner_id === inboxId
  );

const rows = computed(() =>
  (inboxes.value || []).map(inbox => ({
    id: inbox.id,
    name: inbox.name,
    schedule: scheduleFor(inbox.id),
  }))
);

const tableHeaders = computed(() => [
  t('CRM_SLA.SCHEDULES.LIST.INBOX'),
  t('CRM_SLA.SCHEDULES.LIST.STATUS'),
  t('CRM_SLA.SCHEDULES.LIST.TIMEZONE'),
  t('CRM_SLA.SCHEDULES.LIST.ACTIONS'),
]);

const onScheduleSaved = saved => {
  const index = schedules.value.findIndex(
    schedule =>
      schedule.owner_type === saved.owner_type &&
      schedule.owner_id === saved.owner_id
  );
  if (index === -1) schedules.value.push(saved);
  else schedules.value.splice(index, 1, saved);
  editingInbox.value = null;
};

const removeSchedule = async schedule => {
  try {
    await CrmServiceSchedulesAPI.delete(schedule.id);
    schedules.value = schedules.value.filter(item => item.id !== schedule.id);
    useAlert(t('CRM_SLA.SCHEDULES.EDITOR.API.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(t('CRM_SLA.SCHEDULES.EDITOR.API.DELETE_ERROR'));
  }
};
</script>

<template>
  <section class="flex flex-col gap-2">
    <div class="flex flex-col gap-1">
      <h2 class="text-base font-medium text-n-slate-12">
        {{ t('CRM_SLA.SCHEDULES.TITLE') }}
      </h2>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('CRM_SLA.SCHEDULES.DESCRIPTION') }}
      </p>
    </div>

    <BaseTable
      :headers="tableHeaders"
      :items="rows"
      :loading="isLoading"
      :no-data-message="t('CRM_SLA.SCHEDULES.EMPTY')"
    >
      <template #row="{ items }">
        <BaseTableRow v-for="row in items" :key="row.id" :item="row">
          <BaseTableCell>
            <span class="text-n-slate-12">{{ row.name }}</span>
          </BaseTableCell>
          <BaseTableCell>
            {{
              row.schedule
                ? t('CRM_SLA.SCHEDULES.LIST.CONFIGURED')
                : t('CRM_SLA.SCHEDULES.LIST.NOT_CONFIGURED')
            }}
          </BaseTableCell>
          <BaseTableCell>
            <span :class="row.schedule ? '' : 'text-n-slate-10'">
              {{ row.schedule?.timezone || '—' }}
            </span>
          </BaseTableCell>
          <BaseTableCell>
            <div class="flex items-center gap-1">
              <Button
                ghost
                slate
                sm
                icon="i-lucide-calendar-cog"
                type="button"
                :title="t('CRM_SLA.SCHEDULES.LIST.EDIT')"
                @click="editingInbox = row"
              />
              <Button
                v-if="row.schedule"
                ghost
                ruby
                sm
                icon="i-lucide-trash-2"
                type="button"
                :title="t('CRM_SLA.SCHEDULES.LIST.REMOVE')"
                @click="removeSchedule(row.schedule)"
              />
            </div>
          </BaseTableCell>
        </BaseTableRow>
      </template>
    </BaseTable>

    <CrmScheduleEditor
      v-if="editingInbox"
      owner-type="Inbox"
      :owner-id="editingInbox.id"
      :owner-name="editingInbox.name"
      :schedule="editingInbox.schedule"
      @saved="onScheduleSaved"
      @close="editingInbox = null"
    />
  </section>
</template>
