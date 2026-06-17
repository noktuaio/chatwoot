<script setup>
import { ref, watch, computed } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const STAGE_FALLBACK_COLOR = '#64748b';

const card = ref(null);

const hasStage = computed(() => !!card.value?.stage_name);

const dotStyle = computed(() => ({
  backgroundColor: card.value?.stage_color || STAGE_FALLBACK_COLOR,
}));

// Show pipeline name only when the account has more than one pipeline,
// so a single-pipeline setup stays uncluttered.
const pipelineLabel = computed(() =>
  card.value?.multiple_pipelines ? card.value?.pipeline_name : ''
);

async function fetchCard() {
  if (!props.conversationId) return;
  try {
    const response = await CrmKanbanAPI.getConversationCard(
      props.conversationId
    );
    card.value = response.data?.payload || null;
  } catch {
    card.value = null;
  }
}

watch(
  () => props.conversationId,
  () => {
    card.value = null;
    fetchCard();
  },
  { immediate: true }
);
</script>

<template>
  <div
    v-if="hasStage"
    class="flex items-center gap-2 rounded-lg border border-n-weak bg-n-alpha-black2 px-2.5 py-1.5"
  >
    <span
      class="size-2.5 shrink-0 rounded-full ring-1 ring-inset ring-n-strong"
      :style="dotStyle"
    />
    <div class="flex min-w-0 flex-col">
      <span
        v-if="pipelineLabel"
        class="truncate text-xs leading-4 text-n-slate-11"
      >
        {{ pipelineLabel }}
      </span>
      <span class="truncate text-sm leading-5 text-n-slate-12">
        {{ card.stage_name }}
      </span>
    </div>
  </div>
  <span v-else class="text-xs leading-5 text-n-slate-11">
    {{ $t('CRM_KANBAN.CONVERSATION.STAGE_BADGE_EMPTY') }}
  </span>
</template>
