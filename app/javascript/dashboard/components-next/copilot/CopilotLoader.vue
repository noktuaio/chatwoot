<script setup>
// Copilot Loader Component. `label` overrides the default "thinking" text (the Guia passes its own
// "Pensando…"); default keeps the Captain copilot text so existing call sites are unchanged.
defineProps({
  label: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <div class="flex justify-start">
    <div class="flex items-center space-x-2">
      <span class="text-n-iris-11 font-medium">
        {{ label || $t('CAPTAIN.COPILOT.LOADER') }}
      </span>
      <div class="flex space-x-1">
        <div
          class="w-2 h-2 rounded-full bg-n-iris-9 animate-bounce [animation-delay:-0.3s]"
        />
        <div
          class="w-2 h-2 rounded-full bg-n-iris-9 animate-bounce [animation-delay:-0.15s]"
        />
        <div class="w-2 h-2 rounded-full bg-n-iris-9 animate-bounce" />
      </div>
    </div>
  </div>
</template>
