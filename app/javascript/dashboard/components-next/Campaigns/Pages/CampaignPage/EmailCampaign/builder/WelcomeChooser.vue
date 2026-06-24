<script setup>
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';

defineEmits(['chooseAi', 'chooseTemplate', 'startBlank']);

const { t } = useI18n();
</script>

<template>
  <div
    class="flex items-center justify-center w-full h-full p-6 overflow-y-auto"
  >
    <div class="flex flex-col w-full max-w-4xl gap-8">
      <div class="flex flex-col gap-1 text-center">
        <h2 class="text-xl font-semibold text-n-slate-12">
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.WELCOME.TITLE') }}
        </h2>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.WELCOME.SUBTITLE') }}
        </p>
      </div>

      <div class="grid grid-cols-1 gap-5 md:grid-cols-2">
        <button
          type="button"
          class="relative flex flex-col gap-4 p-6 text-left transition-colors border-2 rounded-xl md:row-span-2 border-n-blue-7 bg-n-blue-2 hover:border-n-blue-9 hover:bg-n-blue-3"
          @click="$emit('chooseAi')"
        >
          <span
            class="absolute px-2 py-1 text-xs font-medium rounded-md ltr:right-4 rtl:left-4 top-4 text-n-blue-11 bg-n-blue-3"
          >
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.WELCOME.AI_BADGE') }}
          </span>
          <span
            class="flex items-center justify-center rounded-lg size-12 bg-n-blue-9 text-white"
          >
            <span class="i-lucide-sparkles size-6" />
          </span>
          <div class="flex flex-col gap-1">
            <h3 class="text-lg font-semibold text-n-slate-12">
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.WELCOME.AI_TITLE') }}
            </h3>
            <p class="mb-0 text-sm leading-5 text-n-slate-11">
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.WELCOME.AI_SUBTITLE') }}
            </p>
          </div>
          <Button
            type="button"
            color="blue"
            icon="i-lucide-sparkles"
            :label="t('CAMPAIGN.EMAIL_CAMPAIGN.WELCOME.AI_CTA')"
            class="mt-auto w-fit"
            @click.stop="$emit('chooseAi')"
          />
        </button>

        <button
          type="button"
          class="flex flex-col gap-3 p-6 text-left transition-colors border rounded-xl border-n-weak bg-n-solid-2 hover:border-n-slate-7 hover:bg-n-alpha-2"
          @click="$emit('chooseTemplate')"
        >
          <span
            class="flex items-center justify-center rounded-lg size-10 bg-n-alpha-2 text-n-slate-11"
          >
            <span class="i-lucide-layout-template size-5" />
          </span>
          <div class="flex flex-col gap-1">
            <h3 class="font-medium text-n-slate-12">
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.WELCOME.TEMPLATE_TITLE') }}
            </h3>
            <p class="mb-0 text-sm leading-5 text-n-slate-11">
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.WELCOME.TEMPLATE_SUBTITLE') }}
            </p>
          </div>
          <span class="mt-1 text-sm font-medium text-n-blue-11">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.WELCOME.TEMPLATE_CTA') }}
          </span>
        </button>

        <button
          type="button"
          class="flex flex-col gap-3 p-6 text-left transition-colors border rounded-xl border-n-weak bg-n-solid-2 hover:border-n-slate-7 hover:bg-n-alpha-2"
          @click="$emit('startBlank')"
        >
          <span
            class="flex items-center justify-center rounded-lg size-10 bg-n-alpha-2 text-n-slate-11"
          >
            <span class="i-lucide-file-plus size-5" />
          </span>
          <div class="flex flex-col gap-1">
            <h3 class="font-medium text-n-slate-12">
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.WELCOME.BLANK_TITLE') }}
            </h3>
            <p class="mb-0 text-sm leading-5 text-n-slate-11">
              {{ t('CAMPAIGN.EMAIL_CAMPAIGN.WELCOME.BLANK_SUBTITLE') }}
            </p>
          </div>
          <span class="mt-1 text-sm font-medium text-n-blue-11">
            {{ t('CAMPAIGN.EMAIL_CAMPAIGN.WELCOME.BLANK_CTA') }}
          </span>
        </button>
      </div>
    </div>
  </div>
</template>
