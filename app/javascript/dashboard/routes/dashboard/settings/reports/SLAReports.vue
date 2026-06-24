<script>
import V4Button from 'dashboard/components-next/button/Button.vue';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import SLAMetrics from './components/SLA/SLAMetrics.vue';
import SLATable from './components/SLA/SLATable.vue';
import SLAReportFilters from './components/SLA/SLAReportFilters.vue';
import { generateFileName } from 'dashboard/helper/downloadHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import ReportHeader from './components/ReportHeader.vue';
export default {
  name: 'SLAReports',
  components: {
    V4Button,
    ReportHeader,
    SLAMetrics,
    SLATable,
    SLAReportFilters,
  },
  data() {
    return {
      pageNumber: 1,
      activeFilter: {
        from: 0,
        to: 0,
        assigned_agent_id: null,
        inbox_id: null,
        team_id: null,
        sla_policy_id: null,
        label_list: null,
      },
    };
  },
  computed: {
    ...mapGetters({
      slaReports: 'slaReports/getAll',
      slaMetrics: 'slaReports/getMetrics',
      slaMeta: 'slaReports/getMeta',
      uiFlags: 'slaReports/getUIFlags',
      accountId: 'getCurrentAccountId',
    }),
    // SLA is an Enterprise feature: without the account flag the page renders a paywall and
    // fires NO requests (the backend 404s anyway). Mirrors CrmSlaPage.vue.
    isSlaFeatureEnabled() {
      return this.$store.getters['accounts/isFeatureEnabledonAccount'](
        this.accountId,
        FEATURE_FLAGS.SLA
      );
    },
  },
  mounted() {
    if (!this.isSlaFeatureEnabled) return;
    this.$store.dispatch('agents/get');
    this.$store.dispatch('inboxes/get');
    this.$store.dispatch('teams/get');
    this.$store.dispatch('labels/get');
    this.$store.dispatch('sla/get');
    this.fetchSLAMetrics();
    this.fetchSLAReports();
  },
  methods: {
    fetchSLAReports({ pageNumber } = {}) {
      this.$store.dispatch('slaReports/get', {
        page: pageNumber || this.pageNumber,
        ...this.activeFilter,
      });
    },
    fetchSLAMetrics() {
      this.$store.dispatch('slaReports/getMetrics', this.activeFilter);
    },
    onPageChange(pageNumber) {
      this.fetchSLAReports({ pageNumber });
    },
    onFilterChange(params) {
      this.activeFilter = params;
      this.fetchSLAReports();
      this.fetchSLAMetrics();
    },
    downloadReports() {
      const type = 'sla';
      try {
        this.$store.dispatch('slaReports/download', {
          fileName: generateFileName({ type, to: this.activeFilter.to }),
          ...this.activeFilter,
        });
      } catch (error) {
        useAlert(this.$t('SLA_REPORTS.DOWNLOAD_FAILED'));
      }
    },
  },
};
</script>

<template>
  <ReportHeader :header-title="$t('SLA_REPORTS.HEADER')">
    <V4Button
      v-if="isSlaFeatureEnabled"
      :label="$t('SLA_REPORTS.DOWNLOAD_SLA_REPORTS')"
      icon="i-ph-download-simple"
      size="sm"
      @click="downloadReports"
    />
  </ReportHeader>
  <div
    v-if="!isSlaFeatureEnabled"
    class="flex flex-col items-center justify-center flex-1 gap-2 p-8 text-center"
  >
    <span class="i-lucide-lock size-8 text-n-slate-10" />
    <h2 class="m-0 text-lg font-medium text-n-slate-12">
      {{ $t('CRM_SLA.PAYWALL.TITLE') }}
    </h2>
    <p class="max-w-md m-0 text-sm text-n-slate-11">
      {{ $t('CRM_SLA.PAYWALL.DESCRIPTION') }}
    </p>
  </div>
  <div v-else class="flex flex-col flex-1 gap-6">
    <SLAReportFilters @filter-change="onFilterChange" />
    <SLAMetrics
      :hit-rate="slaMetrics.hitRate"
      :no-of-breaches="slaMetrics.numberOfSLAMisses"
      :no-of-conversations="slaMetrics.numberOfConversations"
      :is-loading="uiFlags.isFetchingMetrics"
    />
    <SLATable
      :sla-reports="slaReports"
      :is-loading="uiFlags.isFetching"
      :current-page="Number(slaMeta.currentPage)"
      :total-count="Number(slaMeta.count)"
      @page-change="onPageChange"
    />
  </div>
</template>
