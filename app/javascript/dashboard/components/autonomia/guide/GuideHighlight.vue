<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useGuideHighlight } from 'dashboard/store/modules/guideHighlight';
import { resolveHighlightElement } from 'dashboard/helper/guideHighlightRegistry';

// Guia da Plataforma V2 — draws a pulsing ring + "é aqui" balloon anchored to a DOM element after the
// guide navigates. READ-ONLY: the overlay is pointer-events-none (never blocks/clicks for the user).
// Auto-dismiss on any click, Escape, or timeout; follows the element on scroll/resize.
const PAD = 6; // gap around the element
const GLOW =
  '0 0 0 4px rgba(39,129,246,0.30), 0 0 22px 6px rgba(39,129,246,0.55)';
const TIMEOUT_MS = 8000;
const POLL_MS = 120;
const POLL_MAX = 60; // ~7.2s — gives data-heavy screens (reports/campaigns/CRM) time to render the target

const { state, clear } = useGuideHighlight();

const box = ref(null); // { top, left, width, height } in viewport px
const placeAbove = ref(true);

let targetEl = null;
let pollTimer = null;
let dismissTimer = null;
let settleTimer = null;
let resizeObs = null;
let listening = false;
// Declared up-front (real impl assigned below) so compute()/handlers can reference it without a
// use-before-define on the compute↔stop↔detach↔handlers cycle.
let stop = () => {};

const compute = () => {
  if (!targetEl || targetEl.offsetParent === null) {
    stop();
    return;
  }
  const r = targetEl.getBoundingClientRect();
  box.value = {
    top: r.top - PAD,
    left: r.left - PAD,
    width: r.width + PAD * 2,
    height: r.height + PAD * 2,
  };
  placeAbove.value = r.top > 84;
};

const onScrollResize = () => compute();
const onPointerDown = () => stop();
const onKeydown = e => {
  if (e.key === 'Escape') stop();
};

const attach = () => {
  if (listening) return;
  listening = true;
  window.addEventListener('scroll', onScrollResize, true);
  window.addEventListener('resize', onScrollResize);
  window.addEventListener('pointerdown', onPointerDown, true);
  window.addEventListener('keydown', onKeydown, true);
  // Reposition when the page reflows after the highlight shows (e.g. async data loads shift layout).
  if (typeof ResizeObserver !== 'undefined') {
    resizeObs = new ResizeObserver(() => compute());
    resizeObs.observe(document.body);
  }
};

const detach = () => {
  if (!listening) return;
  listening = false;
  window.removeEventListener('scroll', onScrollResize, true);
  window.removeEventListener('resize', onScrollResize);
  window.removeEventListener('pointerdown', onPointerDown, true);
  window.removeEventListener('keydown', onKeydown, true);
  if (resizeObs) {
    resizeObs.disconnect();
    resizeObs = null;
  }
};

stop = () => {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
  if (dismissTimer) {
    clearTimeout(dismissTimer);
    dismissTimer = null;
  }
  if (settleTimer) {
    clearTimeout(settleTimer);
    settleTimer = null;
  }
  detach();
  targetEl = null;
  box.value = null;
  clear();
};

const start = anchor => {
  stop();
  if (!anchor) return;
  let tries = 0;
  pollTimer = setInterval(() => {
    tries += 1;
    const el = resolveHighlightElement(anchor);
    if (el) {
      clearInterval(pollTimer);
      pollTimer = null;
      targetEl = el;
      try {
        el.scrollIntoView({ block: 'center', behavior: 'smooth' });
      } catch (e) {
        // noop — scrollIntoView unsupported/edge
      }
      compute();
      if (!box.value) return;
      attach();
      settleTimer = setTimeout(compute, 350); // recompute after smooth scroll settles
      dismissTimer = setTimeout(stop, TIMEOUT_MS);
    } else if (tries >= POLL_MAX) {
      stop(); // element never appeared — clear timers + store state, no stale anchor left behind
    }
  }, POLL_MS);
};

const ringStyle = computed(() =>
  box.value
    ? {
        top: `${box.value.top}px`,
        left: `${box.value.left}px`,
        width: `${box.value.width}px`,
        height: `${box.value.height}px`,
      }
    : {}
);

const balloonStyle = computed(() => {
  if (!box.value) return {};
  const cx = box.value.left + box.value.width / 2;
  return placeAbove.value
    ? {
        left: `${cx}px`,
        top: `${box.value.top - 8}px`,
        transform: 'translate(-50%, -100%)',
      }
    : {
        left: `${cx}px`,
        top: `${box.value.top + box.value.height + 8}px`,
        transform: 'translateX(-50%)',
      };
});

watch(
  () => state.nonce,
  () => start(state.anchor)
);

onBeforeUnmount(stop);
</script>

<template>
  <div v-if="box" class="fixed inset-0 z-[60] pointer-events-none">
    <div
      class="absolute rounded-xl border-2 border-n-blue-9/60 animate-ping"
      :style="ringStyle"
    />
    <div
      class="absolute rounded-xl border-[3px] border-n-blue-9 animate-pulse"
      :style="{ ...ringStyle, boxShadow: GLOW }"
    />
    <div
      class="absolute bg-n-blue-9 text-white text-xs font-semibold px-3 py-1.5 rounded-lg shadow-lg whitespace-nowrap"
      :style="balloonStyle"
    >
      {{ placeAbove ? '👇 ' : '👆 ' }}{{ $t('AUTONOMIA_GUIDE.HIGHLIGHT_HERE') }}
    </div>
  </div>
</template>
