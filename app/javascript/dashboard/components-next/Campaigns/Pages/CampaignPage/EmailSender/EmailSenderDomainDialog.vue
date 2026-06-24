<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['created', 'close']);

const { t } = useI18n();
const store = useStore();

const uiFlags = useMapGetter('emailSenderIdentities/getUIFlags');

const initialState = {
  domain: '',
  fromEmail: '',
};

const state = reactive({ ...initialState });
const showDomainError = ref(false);

const isCreating = computed(() => uiFlags.value.isCreating);
const canSubmit = computed(() => state.domain.trim().length > 0);

const reset = () => {
  Object.assign(state, { ...initialState });
  showDomainError.value = false;
};

const close = () => {
  reset();
  emit('close');
};

const submit = async () => {
  if (!canSubmit.value) {
    showDomainError.value = true;
    return;
  }

  try {
    await store.dispatch('emailSenderIdentities/create', {
      domain: state.domain.trim(),
      from_email: state.fromEmail.trim() || null,
    });
    useAlert(t('CAMPAIGN.EMAIL_SENDER.DIALOG.SUCCESS'));
    emit('created');
    close();
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_SENDER.DIALOG.ERROR'));
  }
};
</script>

<template>
  <form
    class="absolute z-50 flex max-h-[82vh] w-[min(32rem,calc(100vw-3rem))] min-w-0 flex-col overflow-hidden rounded-xl border border-n-weak bg-n-alpha-3 shadow-xl backdrop-blur-[100px] ltr:right-0 rtl:left-0 top-10"
    @submit.prevent="submit"
    @click.stop
  >
    <div class="flex flex-col gap-2 p-6 pb-4">
      <h3 class="text-base font-medium leading-6 text-n-slate-12">
        {{ t('CAMPAIGN.EMAIL_SENDER.DIALOG.TITLE') }}
      </h3>
      <p class="mb-0 text-sm leading-5 text-n-slate-11">
        {{ t('CAMPAIGN.EMAIL_SENDER.DESCRIPTION') }}
      </p>
    </div>

    <div class="flex flex-col gap-5 px-6 pb-5 overflow-y-auto">
      <Input
        v-model="state.domain"
        :label="t('CAMPAIGN.EMAIL_SENDER.DIALOG.DOMAIN_LABEL')"
        :placeholder="t('CAMPAIGN.EMAIL_SENDER.DIALOG.DOMAIN_PLACEHOLDER')"
        :message="
          showDomainError ? t('CAMPAIGN.EMAIL_SENDER.DIALOG.DOMAIN_ERROR') : ''
        "
        :message-type="showDomainError ? 'error' : 'info'"
        @input="showDomainError = false"
      />
      <Input
        v-model="state.fromEmail"
        :label="t('CAMPAIGN.EMAIL_SENDER.DIALOG.FROM_EMAIL_LABEL')"
        :placeholder="t('CAMPAIGN.EMAIL_SENDER.DIALOG.FROM_EMAIL_PLACEHOLDER')"
      />
    </div>

    <div
      class="flex items-center justify-between w-full gap-3 p-6 pt-4 border-t border-n-weak bg-n-alpha-2"
    >
      <Button
        variant="faded"
        color="slate"
        type="button"
        :label="t('CAMPAIGN.EMAIL_SENDER.DIALOG.CANCEL')"
        class="w-full"
        @click="close"
      />
      <Button
        type="submit"
        color="blue"
        :label="t('CAMPAIGN.EMAIL_SENDER.DIALOG.SUBMIT')"
        class="w-full"
        :is-loading="isCreating"
        :disabled="!canSubmit || isCreating"
      />
    </div>
  </form>
</template>
