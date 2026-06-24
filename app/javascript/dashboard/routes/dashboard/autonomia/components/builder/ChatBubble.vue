<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

// A single chat turn, reused across the Builder conversation, the Test sandbox
// and the Tune re-conversation. DARK-MODE / WHITE-LABEL: every surface/text
// token here has a light/dark pair, so the bubble never renders white-on-white
// on a near-black background and never assumes the brand colour is dark enough
// for white text (n-brand is configurable):
//   - user      -> `bg-n-slate-12 text-n-slate-1` (inverted surface; always
//                  high-contrast in both themes, independent of n-brand)
//   - assistant -> `bg-n-alpha-2 text-n-slate-12` (adaptive alpha surface)
// The `thinking` variant reuses the assistant frame with an animated 3-dot
// indicator instead of content. IP OCULTO: only human-facing content is shown.
// Markdown is rendered for the assistant only — user text is shown verbatim so a
// pasted `#`/`*` isn't reinterpreted as formatting.
const props = defineProps({
  role: {
    type: String,
    default: 'assistant',
    validator: value => ['user', 'assistant'].includes(value),
  },
  content: {
    type: String,
    default: '',
  },
  name: {
    type: String,
    default: '',
  },
  thinking: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const { formatMessage } = useMessageFormatter();

const isUser = computed(() => props.role === 'user');

const avatarName = computed(
  () =>
    props.name ||
    (isUser.value ? t('AGENTS.BUILDER.YOU') : t('AGENTS.BUILDER.BUILDER_NAME'))
);

// Adaptive bubble tokens. NEVER bg-white / text-black / hardcoded text-white on
// brand: each of these resolves to a readable pair in both themes and survives a
// white-label brand colour.
const bubbleClass = computed(() =>
  isUser.value
    ? 'bg-n-slate-12 text-n-slate-1 rounded-br-sm rounded-bl-xl rounded-t-xl'
    : 'bg-n-alpha-2 text-n-slate-12 rounded-bl-sm rounded-br-xl rounded-t-xl'
);
</script>

<template>
  <div class="flex" :class="isUser ? 'justify-end' : 'justify-start'">
    <div
      class="flex items-end gap-1.5 max-w-[90%] md:max-w-[75%]"
      :class="isUser ? 'flex-row-reverse' : 'flex-row'"
    >
      <Avatar
        :name="avatarName"
        rounded-full
        :size="24"
        class="shrink-0"
        aria-hidden="true"
      />
      <div
        class="px-4 py-3 text-sm [overflow-wrap:break-word]"
        :class="bubbleClass"
      >
        <div v-if="thinking" role="status" class="flex gap-1">
          <span class="sr-only">{{ t('AGENTS.BUILDER.THINKING') }}</span>
          <span
            aria-hidden="true"
            class="rounded-full size-2 bg-n-slate-10 animate-bounce"
          />
          <span
            aria-hidden="true"
            class="rounded-full size-2 bg-n-slate-10 animate-bounce [animation-delay:0.2s]"
          />
          <span
            aria-hidden="true"
            class="rounded-full size-2 bg-n-slate-10 animate-bounce [animation-delay:0.4s]"
          />
        </div>
        <div v-else-if="isUser" class="whitespace-pre-wrap">
          {{ content }}
        </div>
        <div v-else v-dompurify-html="formatMessage(content)" />
      </div>
    </div>
  </div>
</template>
