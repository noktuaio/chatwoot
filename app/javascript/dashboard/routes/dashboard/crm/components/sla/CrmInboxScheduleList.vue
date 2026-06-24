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
const loadError = ref(false);
const hasLoaded = ref(false);
const editingInbox = ref(null);

const fetchSchedules = async () => {
  isLoading.value = true;
  try {
    const response = await CrmServiceSchedulesAPI.get();
    schedules.value = response.data.payload || [];
    loadError.value = false;
    hasLoaded.value = true;
  } catch (error) {
    // NÃO renderizar tudo como "não configurado" no escuro: se o fetch falhar, um inbox com calendário
    // real apareceria vazio e salvar (upsert) sobrescreveria o real. Mostramos erro + retry.
    schedules.value = [];
    loadError.value = true;
    useAlert(t('CRM_SLA.SCHEDULES.EDITOR.API.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

onMounted(fetchSchedules);

const scheduleFor = inboxId =>
  schedules.value.find(
    schedule => schedule.owner_type === 'Inbox' && schedule.owner_id === inboxId
  );

// Só monta as linhas (com botão editar) DEPOIS de um fetch bem-sucedido. Senão, durante o load
// inicial (inboxes já no store, schedules ainda não), tudo apareceria "não configurado" e dava p/
// abrir o editor e salvar por cima de um calendário real.
const rows = computed(() =>
  hasLoaded.value
    ? (inboxes.value || []).map(inbox => ({
        id: inbox.id,
        name: inbox.name,
        schedule: scheduleFor(inbox.id),
      }))
    : []
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

    <div
      v-if="loadError"
      class="flex flex-col items-start gap-2 rounded-lg border border-n-weak p-4"
    >
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('CRM_SLA.SCHEDULES.EDITOR.API.LOAD_ERROR') }}
      </p>
      <Button
        sm
        slate
        faded
        :label="t('CRM_SLA.SCHEDULES.LIST.RETRY')"
        :is-loading="isLoading"
        @click="fetchSchedules"
      />
    </div>

    <BaseTable
      v-else
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
      v-if="editingInbox && hasLoaded && !loadError"
      owner-type="Inbox"
      :owner-id="editingInbox.id"
      :owner-name="editingInbox.name"
      :schedule="editingInbox.schedule"
      @saved="onScheduleSaved"
      @close="editingInbox = null"
    />
  </section>
</template>
