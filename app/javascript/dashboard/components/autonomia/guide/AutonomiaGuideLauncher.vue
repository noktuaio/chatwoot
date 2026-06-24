<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMapGetter } from 'dashboard/composables/store';

// V1 — global launcher for the "Guia da Plataforma" (onboarding/suporte). GLOBAL: shows on every
// screen (including conversations) for EVERY role (admin + atendente) — the guide is role-aware.
// Gate = `autonomia_guide_available` (the backend's EXACT eligibility: master ENV + account flag +
// a resolvable AI credential), so the launcher never appears when the guide would be unavailable.
// Own uiSetting key (is_autonomia_guide_panel_open). Sits above the copilot launcher.
const { uiSettings, updateUISettings } = useUISettings();
const currentAccount = useMapGetter('accounts/getAccount');
const accountId = useMapGetter('getCurrentAccountId');

const isEnabled = computed(
  () =>
    currentAccount.value(accountId.value)?.autonomia_guide_available === true
);

const showLauncher = computed(
  () => isEnabled.value && !uiSettings.value.is_autonomia_guide_panel_open
);

const toggleSidebar = () => {
  updateUISettings({
    is_autonomia_guide_panel_open:
      !uiSettings.value.is_autonomia_guide_panel_open,
    is_autonomia_copilot_panel_open: false,
    is_contact_sidebar_open: false,
  });
};
</script>

<template>
  <div v-if="showLauncher" class="fixed bottom-4 ltr:right-4 rtl:left-4 z-50">
    <ButtonGroup
      class="rounded-full bg-n-alpha-2 backdrop-blur-lg p-1 shadow hover:shadow-md"
    >
      <Button
        icon="i-lucide-life-buoy"
        no-animation
        :title="$t('AUTONOMIA_GUIDE.LAUNCHER')"
        class="!rounded-full !bg-n-solid-3 dark:!bg-n-alpha-2 !text-n-slate-12 text-xl transition-all duration-200 ease-out hover:brightness-110"
        lg
        @click="toggleSidebar"
      />
    </ButtonGroup>
  </div>
  <template v-else />
</template>
