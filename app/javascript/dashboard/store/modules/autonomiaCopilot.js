// V2.3 — LOCAL message store for the "Copiloto Autonom.ia" chat widget.
//
// Self-contained reactive store (NOT a registered Vuex module, so it needs no change to
// store/index.js and stays update-safe). The thread is ephemeral and lives only while the
// widget is open. Records mirror the shape the components-next/copilot presentational pieces
// expect, so they can be reused without modification:
//   { id, message_type: 'user' | 'assistant', message: { content, reply_suggestion } }
import { reactive, readonly } from 'vue';

const state = reactive({
  messages: [],
});

let nextId = 1;

const addUserMessage = content => {
  const record = {
    id: nextId,
    message_type: 'user',
    message: { content },
  };
  nextId += 1;
  state.messages.push(record);
  return record;
};

const addAssistantMessage = ({ content, replySuggestion = false } = {}) => {
  const record = {
    id: nextId,
    message_type: 'assistant',
    message: { content, reply_suggestion: replySuggestion },
  };
  nextId += 1;
  state.messages.push(record);
  return record;
};

const reset = () => {
  state.messages.splice(0, state.messages.length);
};

// History for the backend chat call: [{ role: 'user' | 'assistant', content }].
const toHistory = () =>
  state.messages
    .filter(m => m.message?.content)
    .map(m => ({
      role: m.message_type === 'assistant' ? 'assistant' : 'user',
      content: m.message.content,
    }));

export const useAutonomiaCopilotStore = () => ({
  messages: readonly(state).messages,
  addUserMessage,
  addAssistantMessage,
  reset,
  toHistory,
});

export default useAutonomiaCopilotStore;
