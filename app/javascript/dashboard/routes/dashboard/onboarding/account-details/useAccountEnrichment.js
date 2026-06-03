import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useConfig } from 'dashboard/composables/useConfig';

const ENRICHMENT_TIMEOUT = 30000;

// Manages the post-signup enrichment lifecycle for the account-details form.
// After signup the account is enriched asynchronously (onboarding_step ===
// 'enrichment'); this fills empty form fields from the enriched
// custom_attributes/brand_info as it arrives — idempotently, so it never
// clobbers a value the user has already typed — waits the step out (with a
// timeout fallback), and tracks which enrichable fields the user edited.
//
// `fields` is the set of form refs to populate, owned by the component so it can
// still wire them to validation and the template.
export function useAccountEnrichment(fields) {
  const { currentAccount } = useAccount();
  const { enabledLanguages } = useConfig();

  const enrichmentTimedOut = ref(false);
  const isEnriching = computed(
    () =>
      !enrichmentTimedOut.value &&
      currentAccount.value?.custom_attributes?.onboarding_step === 'enrichment'
  );

  // Best-effort match browser language to enabled Chatwoot locales: exact match
  // first (e.g. 'pt_BR'), then base language (e.g. 'pt'), else the account
  // locale or 'en'.
  const detectBestLocale = () => {
    const codes = (enabledLanguages || []).map(l => l.iso_639_1_code);
    const browserLang = navigator.language?.replace('-', '_');
    const accountLocale = currentAccount.value?.locale || 'en';
    if (!browserLang) return accountLocale;

    if (codes.includes(browserLang)) return browserLang;
    const base = browserLang.split('_')[0];
    if (codes.includes(base)) return base;

    return accountLocale;
  };

  // Snapshot of the auto-populated values, used to detect user edits at submit.
  const initialValues = ref({});
  const snapshotInitialValues = () => {
    initialValues.value = {
      website: fields.website.value,
      company_size: fields.companySize.value,
      industry: fields.industry.value,
    };
  };

  // Idempotent: only fills empty fields, so late-arriving enrichment data
  // populates untouched fields without clobbering user edits.
  const populateFormFields = () => {
    const attrs = currentAccount.value?.custom_attributes || {};
    const brandInfo = attrs.brand_info;

    if (!fields.locale.value) fields.locale.value = detectBestLocale();
    if (!fields.website.value) {
      fields.website.value = attrs.website || brandInfo?.domain || '';
    }
    if (!fields.timezone.value) {
      fields.timezone.value =
        attrs.timezone ||
        Intl.DateTimeFormat().resolvedOptions().timeZone ||
        '';
    }
    if (!fields.companySize.value) {
      fields.companySize.value = attrs.company_size || '';
    }
    if (!fields.industry.value) {
      fields.industry.value =
        attrs.industry || brandInfo?.industries?.[0]?.industry || '';
    }
    if (!fields.referralSource.value) {
      fields.referralSource.value = attrs.referral_source || '';
    }

    snapshotInitialValues();
  };

  let enrichmentTimer = null;
  const startEnrichmentTimer = () => {
    if (enrichmentTimer) clearTimeout(enrichmentTimer);
    enrichmentTimer = setTimeout(() => {
      enrichmentTimedOut.value = true;
      populateFormFields();
    }, ENRICHMENT_TIMEOUT);
  };

  onMounted(() => {
    populateFormFields();
    if (isEnriching.value) startEnrichmentTimer();
  });

  onUnmounted(() => {
    if (enrichmentTimer) clearTimeout(enrichmentTimer);
  });

  watch(isEnriching, enriching => {
    if (enriching) {
      startEnrichmentTimer();
    } else {
      if (enrichmentTimer) clearTimeout(enrichmentTimer);
      populateFormFields();
    }
  });

  // Re-populate when account data arrives after mount, or when brand_info
  // appears after enrichment. populateFormFields is idempotent so this is safe.
  watch(
    () => currentAccount.value?.custom_attributes,
    () => populateFormFields()
  );

  // Enrichable fields the user actually edited since they were auto-filled.
  // Compare against the snapshot *before* the caller normalizes any values —
  // otherwise an untouched auto-filled domain (acme.com -> https://acme.com)
  // compares unequal and gets falsely reported as changed.
  const getChangedFields = () => {
    const init = initialValues.value;
    const current = {
      website: fields.website.value,
      company_size: fields.companySize.value,
      industry: fields.industry.value,
    };
    return Object.entries(current)
      .filter(([key, value]) => value !== init[key])
      .map(([key]) => key);
  };

  return { isEnriching, getChangedFields };
}
