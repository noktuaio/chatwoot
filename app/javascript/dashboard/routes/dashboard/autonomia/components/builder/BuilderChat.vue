<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import ChatBubble from './ChatBubble.vue';
import ChatComposer from './ChatComposer.vue';
import { useAutoScroll } from '../../composables/useAutoScroll.js';

// The Construtor conversation. An AI interviews the user and, turn by turn,
// renders the next question as an assistant bubble (the parent/store injects it
// between builds). This component only renders the conversation + composer; the
// parent (AgentBuilderPage) owns the thread/store and the wizard transitions.
//
// LAYOUT CONTRACT (fixes "input some"): the message log is `flex-1 min-h-0
// overflow-y-auto` and the composer is its `shrink-0` sibling in the same
// `flex-col h-full`, so a growing conversation scrolls the log instead of
// pushing the input off-screen. `useAutoScroll` keeps the log pinned to the
// bottom on every new message and whenever the thinking indicator toggles.
// IP OCULTO: only human-facing turns are rendered.
const props = defineProps({
  messages: {
    type: Array,
    default: () => [],
  },
  isSending: {
    type: Boolean,
    default: false,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  // Forwarded to the composer: render the clip once a draft agent exists, and
  // reflect the in-flight upload state on it.
  canAttach: {
    type: Boolean,
    default: false,
  },
  isAttaching: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['send', 'attach']);

const { t } = useI18n();

const messageContainer = ref(null);
useAutoScroll(messageContainer, () => [props.messages.length, props.isSending]);

const onSend = content => emit('send', content);
const onAttach = payload => emit('attach', payload);
</script>

<template>
  <div class="flex flex-col h-full min-h-0">
    <div
      ref="messageContainer"
      role="log"
      aria-live="polite"
      :aria-label="t('AGENTS.BUILDER.CONVERSATION')"
      class="flex-1 min-h-0 px-2 py-4 space-y-6 overflow-y-auto"
    >
      <ChatBubble
        v-for="(message, index) in messages"
        :key="index"
        :role="message.role"
        :content="message.content"
      />
      <ChatBubble v-if="isSending" role="assistant" thinking />
    </div>

    <div class="mt-2 shrink-0">
      <ChatComposer
        :placeholder="t('AGENTS.BUILDER.PLACEHOLDER')"
        :disabled="disabled"
        :is-sending="isSending"
        :can-attach="canAttach"
        :is-attaching="isAttaching"
        @send="onSend"
        @attach="onAttach"
      />
    </div>
  </div>
</template>
