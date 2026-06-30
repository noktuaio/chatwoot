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
  invoiceStatusLabel,
  paymentStatusLabel,
  statusToneClass,
  unwrapCollection,
} from '../helpers';

const { resolvedLocale } = useLocale();

const TEXT = {
  eyebrow: 'Historico de cobranca',
  title: 'Minhas faturas',
  description:
    'Acompanhe faturas emitidas, pagamentos realizados e cobrancas em aberto.',
  open: 'Em aberto',
  openHintSuffix: ' fatura(s) aguardando pagamento.',
  paid: 'Pagas',
  paidHint: 'Faturas conciliadas ou pagas pelo gateway.',
  payments: 'Pagamentos',
  paymentsHint: 'Registros de pagamento associados ao usuario.',
  invoicesTitle: 'Faturas',
  invoicesDescription: 'Lista das cobrancas emitidas para sua assinatura.',
  amount: 'Valor',
  status: 'Status',
  dueDate: 'Vencimento',
  payment: 'Pagamento',
  document: 'Documento',
  openInvoice: 'Abrir fatura',
  unavailable: 'Indisponivel',
  noInvoices: 'Nenhuma fatura encontrada.',
  paymentsTitle: 'Pagamentos',
  paymentsDescription: 'Historico dos pagamentos associados as suas faturas.',
  source: 'Origem',
  paidAt: 'Pago em',
  noPayments: 'Nenhum pagamento registrado.',
  manual: 'manual',
};

const isLoading = ref(true);
const errorMessage = ref('');
const invoices = ref([]);
const payments = ref([]);

const openInvoices = computed(() =>
  invoices.value.filter(invoice =>
    ['pending', 'overdue'].includes(invoice.status)
  )
);
const paidInvoices = computed(() =>
  invoices.value.filter(invoice => invoice.status === 'paid')
);
const openAmount = computed(() =>
  openInvoices.value.reduce(
    (sum, invoice) => sum + Number(invoice.amount || 0),
    0
  )
);
const currency = computed(
  () => invoices.value[0]?.currency || payments.value[0]?.currency || 'BRL'
);

const load = async () => {
  isLoading.value = true;
  errorMessage.value = '';

  try {
    const [invoicesResponse, paymentsResponse] = await Promise.all([
      AutonomiaFinancialAPI.invoices(),
      AutonomiaFinancialAPI.payments(),
    ]);
    invoices.value = unwrapCollection(invoicesResponse.data);
    payments.value = unwrapCollection(paymentsResponse.data);
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
        <section class="grid gap-3 md:grid-cols-3">
          <article class="p-4 border rounded-lg bg-n-solid-1 border-n-weak">
            <p class="text-sm text-n-slate-11">{{ TEXT.open }}</p>
            <strong class="block mt-2 text-xl font-semibold text-n-slate-12">
              {{ formatMoney(openAmount, currency, resolvedLocale) }}
            </strong>
            <p class="mt-2 text-xs text-n-slate-10">
              {{ openInvoices.length }}{{ TEXT.openHintSuffix }}
            </p>
          </article>
          <article class="p-4 border rounded-lg bg-n-solid-1 border-n-weak">
            <p class="text-sm text-n-slate-11">{{ TEXT.paid }}</p>
            <strong class="block mt-2 text-xl font-semibold text-n-slate-12">
              {{ paidInvoices.length }}
            </strong>
            <p class="mt-2 text-xs text-n-slate-10">
              {{ TEXT.paidHint }}
            </p>
          </article>
          <article class="p-4 border rounded-lg bg-n-solid-1 border-n-weak">
            <p class="text-sm text-n-slate-11">{{ TEXT.payments }}</p>
            <strong class="block mt-2 text-xl font-semibold text-n-slate-12">
              {{ payments.length }}
            </strong>
            <p class="mt-2 text-xs text-n-slate-10">
              {{ TEXT.paymentsHint }}
            </p>
          </article>
        </section>

        <section class="p-5 border rounded-lg bg-n-solid-1 border-n-weak">
          <h2 class="text-lg font-semibold text-n-slate-12">
            {{ TEXT.invoicesTitle }}
          </h2>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ TEXT.invoicesDescription }}
          </p>
          <div class="mt-4 overflow-hidden border rounded-lg border-n-weak">
            <table class="w-full text-sm">
              <thead class="bg-n-alpha-1 text-n-slate-11">
                <tr>
                  <th class="px-4 py-3 text-left">{{ TEXT.amount }}</th>
                  <th class="px-4 py-3 text-left">{{ TEXT.status }}</th>
                  <th class="px-4 py-3 text-left">{{ TEXT.dueDate }}</th>
                  <th class="px-4 py-3 text-left">{{ TEXT.payment }}</th>
                  <th class="px-4 py-3 text-left">{{ TEXT.document }}</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="invoice in invoices"
                  :key="invoice.id"
                  class="border-t border-n-weak"
                >
                  <td class="px-4 py-3 font-medium text-n-slate-12">
                    {{
                      formatMoney(
                        invoice.amount,
                        invoice.currency,
                        resolvedLocale
                      )
                    }}
                  </td>
                  <td class="px-4 py-3">
                    <span
                      class="px-2 py-1 text-xs font-medium rounded-full"
                      :class="statusToneClass(invoice.status)"
                    >
                      {{ invoiceStatusLabel(invoice.status) }}
                    </span>
                  </td>
                  <td class="px-4 py-3 text-n-slate-11">
                    {{ formatDate(invoice.dueDate, resolvedLocale) }}
                  </td>
                  <td class="px-4 py-3 text-n-slate-11">
                    {{ formatDate(invoice.paidAt, resolvedLocale) }}
                  </td>
                  <td class="px-4 py-3">
                    <a
                      v-if="invoice.invoiceUrl"
                      :href="invoice.invoiceUrl"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-n-brand"
                    >
                      {{ TEXT.openInvoice }}
                    </a>
                    <span v-else class="text-n-slate-10">
                      {{ TEXT.unavailable }}
                    </span>
                  </td>
                </tr>
                <tr v-if="!invoices.length">
                  <td colspan="5" class="px-4 py-8 text-center text-n-slate-11">
                    {{ TEXT.noInvoices }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="p-5 border rounded-lg bg-n-solid-1 border-n-weak">
          <h2 class="text-lg font-semibold text-n-slate-12">
            {{ TEXT.paymentsTitle }}
          </h2>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ TEXT.paymentsDescription }}
          </p>
          <div class="mt-4 overflow-hidden border rounded-lg border-n-weak">
            <table class="w-full text-sm">
              <thead class="bg-n-alpha-1 text-n-slate-11">
                <tr>
                  <th class="px-4 py-3 text-left">{{ TEXT.amount }}</th>
                  <th class="px-4 py-3 text-left">{{ TEXT.status }}</th>
                  <th class="px-4 py-3 text-left">{{ TEXT.source }}</th>
                  <th class="px-4 py-3 text-left">{{ TEXT.paidAt }}</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="payment in payments"
                  :key="payment.id"
                  class="border-t border-n-weak"
                >
                  <td class="px-4 py-3 font-medium text-n-slate-12">
                    {{
                      formatMoney(
                        payment.amount,
                        payment.currency,
                        resolvedLocale
                      )
                    }}
                  </td>
                  <td class="px-4 py-3">
                    <span
                      class="px-2 py-1 text-xs font-medium rounded-full"
                      :class="statusToneClass(payment.status)"
                    >
                      {{ paymentStatusLabel(payment.status) }}
                    </span>
                  </td>
                  <td class="px-4 py-3 text-n-slate-11">
                    {{ payment.gateway || TEXT.manual }}
                  </td>
                  <td class="px-4 py-3 text-n-slate-11">
                    {{ formatDate(payment.paidAt, resolvedLocale) }}
                  </td>
                </tr>
                <tr v-if="!payments.length">
                  <td colspan="4" class="px-4 py-8 text-center text-n-slate-11">
                    {{ TEXT.noPayments }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </template>
    </section>
  </main>
</template>
