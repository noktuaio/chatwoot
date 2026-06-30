<script setup>
import { computed, onMounted, ref } from 'vue';
import { useLocale } from 'shared/composables/useLocale';
import AutonomiaFinancialAPI from 'dashboard/api/autonomia/financial';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  extractErrorMessage,
  formatDate,
  formatMoney,
  statusToneClass,
  subscriptionStatusLabel,
} from '../helpers';

const { resolvedLocale } = useLocale();

const TEXT = {
  eyebrow: 'Assinatura e consumo',
  title: 'Minha assinatura',
  description: 'Veja o plano contratado e a composicao da cobranca.',
  noSubscriptionTitle: 'Nenhuma assinatura encontrada',
  noSubscriptionDescription:
    'Quando o checkout for concluido, a assinatura aparecera aqui.',
  planSummaryTitle: 'Resumo do plano',
  planSummaryDescription:
    'Plano base contratado e itens que compoem a cobranca.',
  plan: 'Plano',
  cycle: 'Ciclo',
  yearly: 'Anual',
  monthly: 'Mensal',
  quantity: 'Quantidade',
  compositionTitle: 'Composicao da cobranca',
  descriptionColumn: 'Descricao',
  typeColumn: 'Tipo',
  quantityColumn: 'Qtd.',
  totalColumn: 'Total',
  noItems: 'Nenhum item de cobranca encontrado.',
  unavailable: 'Indisponivel',
};

const isLoading = ref(true);
const errorMessage = ref('');
const subscription = ref(null);
const billingPreview = ref(null);

const productItem = computed(() =>
  (billingPreview.value?.items || []).find(
    item => item.itemType === 'product_subscription'
  )
);

const currency = computed(() => billingPreview.value?.currency || 'BRL');
const monthlyAmount = computed(() => billingPreview.value?.monthlyAmount || 0);
const yearlyAmount = computed(() => billingPreview.value?.yearlyAmount || 0);
const nextDueDate = computed(() => {
  return subscription.value?.currentPeriodEnd || subscription.value?.trialEndAt;
});

const cards = computed(() => [
  {
    label: 'Status',
    value: subscriptionStatusLabel(subscription.value?.status),
    hint: 'Situacao atual da assinatura vinculada ao usuario.',
    status: subscription.value?.status,
  },
  {
    label: 'Total mensal',
    value: formatMoney(
      monthlyAmount.value,
      currency.value,
      resolvedLocale.value
    ),
    hint: 'Soma dos itens com cobranca mensal.',
  },
  {
    label: 'Total anual',
    value: formatMoney(
      yearlyAmount.value,
      currency.value,
      resolvedLocale.value
    ),
    hint: 'Soma dos itens com cobranca anual.',
  },
  {
    label: 'Proximo vencimento',
    value: formatDate(nextDueDate.value, resolvedLocale.value),
    hint: 'Data prevista pelo periodo atual da assinatura.',
  },
]);

const previewItems = computed(() => billingPreview.value?.items || []);

const load = async () => {
  isLoading.value = true;
  errorMessage.value = '';

  try {
    const [subscriptionResponse, previewResponse] = await Promise.all([
      AutonomiaFinancialAPI.subscription(),
      AutonomiaFinancialAPI.billingPreview(),
    ]);
    subscription.value = subscriptionResponse.data;
    billingPreview.value = previewResponse.data;
  } catch (error) {
    errorMessage.value = extractErrorMessage(error);
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);
</script>

<template>
  <main class="h-full overflow-auto bg-n-surface-1">
    <section class="max-w-6xl px-6 py-8 mx-auto space-y-6">
      <header class="flex flex-col gap-1">
        <span
          class="text-xs font-medium tracking-wide uppercase text-n-slate-11"
        >
          {{ TEXT.eyebrow }}
        </span>
        <div class="flex items-center justify-between gap-3">
          <div>
            <h1 class="text-2xl font-semibold text-n-slate-12">
              {{ TEXT.title }}
            </h1>
            <p class="mt-1 text-sm text-n-slate-11">
              {{ TEXT.description }}
            </p>
          </div>
          <Button
            icon="i-lucide-refresh-cw"
            label="Atualizar"
            color="slate"
            variant="faded"
            size="sm"
            @click="load"
          />
        </div>
      </header>

      <div v-if="isLoading" class="flex items-center justify-center py-24">
        <Spinner />
      </div>

      <div
        v-else-if="errorMessage"
        class="p-4 border rounded-lg border-red-200 bg-red-50 text-red-900 dark:bg-red-950/30 dark:text-red-100 dark:border-red-900"
      >
        {{ errorMessage }}
      </div>

      <template v-else>
        <div
          v-if="!subscription"
          class="p-6 border rounded-lg bg-n-solid-1 border-n-weak"
        >
          <h2 class="text-lg font-semibold text-n-slate-12">
            {{ TEXT.noSubscriptionTitle }}
          </h2>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ TEXT.noSubscriptionDescription }}
          </p>
        </div>

        <template v-else>
          <section class="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
            <article
              v-for="card in cards"
              :key="card.label"
              class="p-4 border rounded-lg bg-n-solid-1 border-n-weak"
            >
              <p class="text-sm text-n-slate-11">{{ card.label }}</p>
              <div class="flex items-center gap-2 mt-2">
                <span
                  v-if="card.status"
                  class="px-2 py-1 text-xs font-medium rounded-full"
                  :class="statusToneClass(card.status)"
                >
                  {{ card.value }}
                </span>
                <strong v-else class="text-xl font-semibold text-n-slate-12">
                  {{ card.value }}
                </strong>
              </div>
              <p class="mt-2 text-xs text-n-slate-10">{{ card.hint }}</p>
            </article>
          </section>

          <section class="p-5 border rounded-lg bg-n-solid-1 border-n-weak">
            <h2 class="text-lg font-semibold text-n-slate-12">
              {{ TEXT.planSummaryTitle }}
            </h2>
            <p class="mt-1 text-sm text-n-slate-11">
              {{ TEXT.planSummaryDescription }}
            </p>

            <div class="grid gap-3 mt-4 md:grid-cols-3">
              <div class="p-4 rounded-lg bg-n-alpha-1">
                <p class="text-xs uppercase text-n-slate-10">
                  {{ TEXT.plan }}
                </p>
                <p class="mt-1 text-base font-medium text-n-slate-12">
                  {{ productItem?.description || TEXT.unavailable }}
                </p>
              </div>
              <div class="p-4 rounded-lg bg-n-alpha-1">
                <p class="text-xs uppercase text-n-slate-10">
                  {{ TEXT.cycle }}
                </p>
                <p class="mt-1 text-base font-medium text-n-slate-12">
                  {{
                    billingPreview?.billingCycle === 'yearly'
                      ? TEXT.yearly
                      : TEXT.monthly
                  }}
                </p>
              </div>
              <div class="p-4 rounded-lg bg-n-alpha-1">
                <p class="text-xs uppercase text-n-slate-10">
                  {{ TEXT.quantity }}
                </p>
                <p class="mt-1 text-base font-medium text-n-slate-12">
                  {{ productItem?.quantity || 1 }}
                </p>
              </div>
            </div>
          </section>

          <section class="p-5 border rounded-lg bg-n-solid-1 border-n-weak">
            <h2 class="text-lg font-semibold text-n-slate-12">
              {{ TEXT.compositionTitle }}
            </h2>
            <div class="mt-4 overflow-hidden border rounded-lg border-n-weak">
              <table class="w-full text-sm">
                <thead class="bg-n-alpha-1 text-n-slate-11">
                  <tr>
                    <th class="px-4 py-3 text-left">
                      {{ TEXT.descriptionColumn }}
                    </th>
                    <th class="px-4 py-3 text-left">
                      {{ TEXT.typeColumn }}
                    </th>
                    <th class="px-4 py-3 text-right">
                      {{ TEXT.quantityColumn }}
                    </th>
                    <th class="px-4 py-3 text-right">
                      {{ TEXT.totalColumn }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="item in previewItems"
                    :key="`${item.itemType}-${item.planPriceId}-${item.description}`"
                    class="border-t border-n-weak"
                  >
                    <td class="px-4 py-3 text-n-slate-12">
                      {{ item.description }}
                    </td>
                    <td class="px-4 py-3 text-n-slate-11">
                      {{ item.itemType }}
                    </td>
                    <td class="px-4 py-3 text-right text-n-slate-11">
                      {{ item.quantity }}
                    </td>
                    <td
                      class="px-4 py-3 text-right font-medium text-n-slate-12"
                    >
                      {{
                        formatMoney(item.totalAmount, currency, resolvedLocale)
                      }}
                    </td>
                  </tr>
                  <tr v-if="!previewItems.length">
                    <td
                      colspan="4"
                      class="px-4 py-8 text-center text-n-slate-11"
                    >
                      {{ TEXT.noItems }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </template>
      </template>
    </section>
  </main>
</template>
