import { watch } from 'vue';

// Auto-grow helper for a native <textarea>. The DS TextArea fought the
// bottom-anchored composer layout (it injected its own flex wrapper that pulled
// the buttons to the vertical center as the field grew), so the composer drives
// a plain <textarea> and this composable handles the growth: reset to `auto`,
// then clamp the rendered height to `scrollHeight` so the field grows with the
// content up to the CSS `max-height` and then scrolls.
//
// `elRef`   — template ref to the <textarea>.
// `valueRef`— the reactive model so we resize on every keystroke (and on
//             programmatic clears like sending).
export function useAutoGrowTextarea(elRef, valueRef) {
  const resize = () => {
    const el = elRef.value;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${el.scrollHeight}px`;
  };

  // `flush: 'post'` runs the callback AFTER Vue flushed the DOM for this change,
  // so `scrollHeight` already reflects the new content (or the cleared value on
  // send). This removes the `nextTick` race that left the field tall and empty
  // after sending a multi-line message.
  watch(
    valueRef,
    () => {
      resize();
    },
    { immediate: true, flush: 'post' }
  );

  return { resize };
}
