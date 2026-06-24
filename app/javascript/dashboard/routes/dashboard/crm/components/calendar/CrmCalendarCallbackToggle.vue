<script setup>
// Atalho do calendário para o toggle POR FUNIL "Lembrete de retorno por IA"
// (config canônica vive em Editar funil → IA). Self-contained: carrega o estado
// atual do pipeline e grava de forma PARCIAL (só callback_enabled) — o updater
// do backend faz merge por chave, então não zera enabled/auto_move/stale.
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

const props = defineProps({
  pipelineId: { type: [String, Number], default: null },
});

const { t } = useI18n();

const enabled = ref(true);
const isReady = ref(false);
const isSaving = ref(false);

const load = async () => {
  if (!props.pipelineId) return;
  isReady.value = false;
  try {
    const response = await CrmKanbanAPI.getAiSettings(props.pipelineId);
    enabled.value = response.data.payload?.callback_enabled !== false;
    isReady.value = true;
  } catch {
    // Silencioso: se não der para ler (sem permissão/IA off), o atalho some.
    isReady.value = false;
  }
};

// v-model já inverteu `enabled` ao clicar; o payload do @change do Switch é o valor
// ANTERIOR, então lemos o estado atual (pós-toggle) em vez do argumento.
const onChange = async () => {
  if (isSaving.value || !props.pipelineId) return;
  const value = enabled.value;
  const previous = !value;
  isSaving.value = true;
  try {
    await CrmKanbanAPI.updateAiSettings(props.pipelineId, {
      ai_settings: { callback_enabled: value },
    });
  } catch {
    enabled.value = previous;
    useAlert(t('CRM_KANBAN.AI_SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

watch(() => props.pipelineId, load, { immediate: true });
</script>

<template>
  <div
    v-if="isReady"
    class="inline-flex items-center gap-2 rounded-lg px-2.5 py-1 text-xs font-medium outline-1 transition-colors duration-100"
    :class="
      enabled
        ? 'bg-n-teal-9/10 text-n-teal-11 outline-n-teal-9'
        : 'bg-n-alpha-1 text-n-slate-10 outline-transparent'
    "
  >
    <span class="i-lucide-sparkles size-3.5" aria-hidden="true" />
    <span>{{ t('CRM_KANBAN.CALENDAR.CALLBACK.LABEL') }}</span>
    <Switch
      v-model="enabled"
      :aria-label="t('CRM_KANBAN.CALENDAR.CALLBACK.LABEL')"
      @change="onChange"
    />
    <span
      v-tooltip.top="t('CRM_KANBAN.CALENDAR.CALLBACK.TOOLTIP')"
      class="i-lucide-info size-3.5 cursor-help opacity-70"
    />
  </div>
  <span v-else class="hidden" aria-hidden="true" />
</template>
