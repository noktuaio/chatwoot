<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Read-only progress bar for the Construtor wizard:
//   Conversa + materiais › Revisão
// Step 1 merges the interview and the live knowledge panel; "Conectar" lives
// inside the Revisão step. The current step is highlighted (n-iris), completed
// steps show a check, upcoming steps are muted (n-slate-10).
const props = defineProps({
  current: {
    type: String,
    default: 'conversa',
    validator: value => ['conversa', 'revisao'].includes(value),
  },
});

const { t } = useI18n();

// Explicit key -> i18n label map (no dynamic translation keys) so linting can
// statically resolve every string.
const STEP_LABELS = {
  conversa: 'AGENTS.WIZARD.STEPS.CONVERSA',
  revisao: 'AGENTS.WIZARD.STEPS.REVISAO',
};
const STEP_KEYS = ['conversa', 'revisao'];

// Explicit state -> i18n label map (static keys so linting resolves them).
const STATE_LABELS = {
  done: 'AGENTS.WIZARD.STATE.DONE',
  current: 'AGENTS.WIZARD.STATE.CURRENT',
  upcoming: 'AGENTS.WIZARD.STATE.UPCOMING',
};

const steps = computed(() => {
  const currentIndex = STEP_KEYS.indexOf(props.current);
  return STEP_KEYS.map((key, index) => {
    const isCurrent = index === currentIndex;
    const isDone = index < currentIndex;
    let stateKey = 'upcoming';
    if (isDone) stateKey = 'done';
    else if (isCurrent) stateKey = 'current';
    const label = t(STEP_LABELS[key]);
    return {
      key,
      label,
      isCurrent,
      isDone,
      // Full "<label> — <state>" string for screen readers, built in script so
      // the template carries no raw text and no on/off separator.
      srLabel: t('AGENTS.WIZARD.STEP_STATUS', {
        label,
        state: t(STATE_LABELS[stateKey]),
      }),
    };
  });
});
</script>

<template>
  <nav
    :aria-label="t('AGENTS.WIZARD.PROGRESS')"
    class="flex flex-wrap items-center justify-center px-2 text-base gap-x-3 gap-y-2 sm:gap-x-4"
  >
    <template v-for="(step, index) in steps" :key="step.key">
      <div
        class="flex items-center gap-2.5"
        :aria-current="step.isCurrent ? 'step' : undefined"
      >
        <span
          class="flex items-center justify-center text-sm font-semibold rounded-full size-8 shrink-0"
          :class="[
            step.isDone
              ? 'bg-n-iris-9 text-white'
              : step.isCurrent
                ? 'bg-n-iris-3 text-n-iris-11 ring-2 ring-n-iris-7'
                : 'bg-n-alpha-2 text-n-slate-10',
          ]"
        >
          <!-- Screen-reader label carries the full "<label> — <state>" string so
               the visible label below stays free of separators. -->
          <span class="sr-only">{{ step.srLabel }}</span>
          <i
            v-if="step.isDone"
            aria-hidden="true"
            class="i-lucide-check size-5"
          />
          <template v-else>{{ index + 1 }}</template>
        </span>
        <span
          class="font-semibold"
          :class="
            step.isCurrent
              ? 'text-n-iris-11'
              : step.isDone
                ? 'text-n-slate-12'
                : 'text-n-slate-10'
          "
        >
          {{ step.label }}
        </span>
      </div>
      <i
        v-if="index < steps.length - 1"
        aria-hidden="true"
        class="i-lucide-chevron-right size-5 text-n-slate-9 shrink-0"
      />
    </template>
  </nav>
</template>
