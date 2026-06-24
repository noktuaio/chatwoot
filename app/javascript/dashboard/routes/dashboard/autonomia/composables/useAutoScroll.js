import { nextTick, onMounted, watch } from 'vue';

// Keeps a scrollable chat container pinned to the bottom so the latest message
// (and the typing indicator) stay visible and the composer is never pushed out
// of view. Pass the container ref and a reactive dependency (or getter that
// returns one — typically the message count + sending flag); every time it
// changes we scroll to the end on the NEXT tick, after the new node rendered.
//
// The contract assumed by callers: the container is `overflow-y-auto` and the
// composer is a sibling `shrink-0` inside the same `flex-col h-full`, so growing
// the conversation scrolls the log instead of covering the input.
export function useAutoScroll(containerRef, dep) {
  const scrollToBottom = async () => {
    await nextTick();
    const el = containerRef.value;
    if (el) el.scrollTop = el.scrollHeight;
  };

  watch(dep, scrollToBottom, { flush: 'post' });

  // Pin to the bottom on first paint too, so a thread that hydrates with
  // pre-existing history (e.g. the Tune re-conversation) opens at the latest
  // message instead of scrolled to the top.
  onMounted(scrollToBottom);

  return { scrollToBottom };
}

export default useAutoScroll;
