// Guia da Plataforma V2 — tiny reactive trigger for the on-screen highlight. The Guia container calls
// show(anchor) after navigating; GuideHighlight.vue (mounted globally) reacts and draws the ring+balloon.
// `nonce` bumps on every show() so re-asking the same anchor re-triggers the effect.
import { reactive, readonly } from 'vue';

const state = reactive({
  anchor: null,
  nonce: 0,
});

const show = anchor => {
  if (!anchor) return;
  state.anchor = anchor;
  state.nonce += 1;
};

const clear = () => {
  state.anchor = null;
};

export const useGuideHighlight = () => ({
  state: readonly(state),
  show,
  clear,
});

export default useGuideHighlight;
