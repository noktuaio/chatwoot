<script setup>
// Ouvinte global (montado no Dashboard) para a geração de e-mail por IA: mostra um toast quando
// a geração conclui/falha, mesmo que o usuário esteja em outra tela. O connector do ActionCable
// não tem i18n próprio, por isso o toast vive aqui (com useI18n + useAlert).
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const { t } = useI18n();

useEmitter(BUS_EVENTS.EMAIL_CAMPAIGN_AI_READY, data => {
  useAlert(
    t('CAMPAIGN.EMAIL_CAMPAIGN.AI.TOAST.READY', { name: data?.name || '' })
  );
});

useEmitter(BUS_EVENTS.EMAIL_CAMPAIGN_AI_FAILED, data => {
  useAlert(
    t('CAMPAIGN.EMAIL_CAMPAIGN.AI.TOAST.FAILED', { name: data?.name || '' })
  );
});
</script>

<template>
  <!-- sem UI própria: só dispara toasts globais -->
  <span class="hidden" />
</template>
