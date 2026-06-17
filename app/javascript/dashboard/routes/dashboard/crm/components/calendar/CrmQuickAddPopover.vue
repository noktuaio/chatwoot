<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import DatePicker from 'vue-datepicker-next';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const props = defineProps({
  date: { type: [Date, String, Number], default: () => new Date() },
  defaultType: { type: String, default: 'reminder' },
  contacts: { type: Array, default: () => [] },
});

const emit = defineEmits(['create', 'moreOptions', 'cancel', 'search']);

const { t, locale } = useI18n();

const toDate = value => {
  if (value instanceof Date) return value;
  if (typeof value === 'number') return new Date(value * 1000);
  return value ? new Date(value) : new Date();
};

const title = ref('');
const type = ref(props.defaultType);
const startsAt = ref(toDate(props.date));
const contactId = ref('');

watch(
  () => props.date,
  value => {
    startsAt.value = toDate(value);
  }
);

watch(
  () => props.defaultType,
  value => {
    type.value = value;
  }
);

const typeOptions = computed(() => [
  { value: 'reminder', label: t('CRM_KANBAN.CALENDAR.TYPE.REMINDER') },
  { value: 'whatsapp', label: t('CRM_KANBAN.CALENDAR.TYPE.WHATSAPP') },
  { value: 'closeDate', label: t('CRM_KANBAN.CALENDAR.TYPE.CLOSE') },
]);

const contactOptions = computed(() =>
  props.contacts.map(contact => ({
    value: contact.id,
    label: contact.name || contact.phone_number || `#${contact.id}`,
  }))
);

const datepickerLang = computed(() => ({
  formatLocale: { firstDayOfWeek: 0 },
  monthBeforeYear: locale.value !== 'pt_BR',
}));

const canSave = computed(() => title.value.trim().length > 0 && startsAt.value);

const buildPayload = () => ({
  title: title.value.trim(),
  type: type.value,
  startsAt: startsAt.value ? startsAt.value.toISOString() : null,
  contactId: contactId.value || null,
});

const onSave = () => {
  if (!canSave.value) return;
  emit('create', buildPayload());
};

const onMoreOptions = () => emit('moreOptions', buildPayload());
</script>

<template>
  <div class="flex w-80 flex-col gap-3 p-4">
    <header class="flex items-center justify-between">
      <h3 class="mb-0 text-sm font-semibold text-n-slate-12">
        {{ t('CRM_KANBAN.CALENDAR.QUICK_ADD.TITLE') }}
      </h3>
      <Button
        variant="ghost"
        color="slate"
        size="xs"
        icon="i-lucide-x"
        @click="emit('cancel')"
      />
    </header>

    <Input
      v-model="title"
      :label="t('CRM_KANBAN.CALENDAR.QUICK_ADD.TITLE_LABEL')"
      :placeholder="t('CRM_KANBAN.CALENDAR.QUICK_ADD.TITLE_LABEL')"
      autofocus
      @keydown.enter="onSave"
    />

    <div class="flex flex-col gap-1.5">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('CRM_KANBAN.CALENDAR.QUICK_ADD.TYPE_LABEL') }}
      </span>
      <ComboBox
        v-model="type"
        :options="typeOptions"
        :placeholder="t('CRM_KANBAN.CALENDAR.QUICK_ADD.TYPE_LABEL')"
      />
    </div>

    <div class="flex flex-col gap-1.5">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('CRM_KANBAN.CALENDAR.QUICK_ADD.DATE_LABEL') }}
      </span>
      <DatePicker
        v-model:value="startsAt"
        type="datetime"
        format="DD/MM/YYYY HH:mm"
        :lang="datepickerLang"
        :clearable="false"
        input-class="mx-input"
        class="w-full"
      />
    </div>

    <div v-if="contactOptions.length" class="flex flex-col gap-1.5">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('CRM_KANBAN.CALENDAR.QUICK_ADD.CONTACT_LABEL') }}
      </span>
      <ComboBox
        v-model="contactId"
        :options="contactOptions"
        use-api-results
        :placeholder="t('CRM_KANBAN.CALENDAR.QUICK_ADD.CONTACT_LABEL')"
        :search-placeholder="t('CRM_KANBAN.CALENDAR.QUICK_ADD.CONTACT_LABEL')"
        @search="emit('search', $event)"
      />
    </div>

    <footer class="flex items-center justify-between gap-2 pt-1">
      <Button
        variant="link"
        color="slate"
        size="sm"
        :label="t('CRM_KANBAN.CALENDAR.QUICK_ADD.MORE_OPTIONS')"
        @click="onMoreOptions"
      />
      <div class="flex items-center gap-2">
        <Button
          variant="faded"
          color="slate"
          size="sm"
          :label="t('CRM_KANBAN.CALENDAR.QUICK_ADD.CANCEL')"
          @click="emit('cancel')"
        />
        <Button
          variant="solid"
          color="blue"
          size="sm"
          :disabled="!canSave"
          :label="t('CRM_KANBAN.CALENDAR.QUICK_ADD.SAVE')"
          @click="onSave"
        />
      </div>
    </footer>
  </div>
</template>
