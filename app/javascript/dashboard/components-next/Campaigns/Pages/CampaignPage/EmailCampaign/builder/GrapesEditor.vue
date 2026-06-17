<script setup>
// Casca fina: monta o canvas e delega TODO o estado/IO ao composable
// singleton useEmailEditor(). SEM defineExpose — a pagina fala com o
// composable (observa isReady), nao com este ref.
import {
  onMounted,
  onBeforeUnmount,
  onActivated,
  onDeactivated,
  nextTick,
  ref,
} from 'vue';
import { useEmailEditor } from './composables/useEmailEditor';
// Builder-scoped GrapesJS canvas theming (third-party chrome re-skin only).
import './grapes-theme.css';

const props = defineProps({
  mjml: {
    type: String,
    default: '',
  },
});

const containerRef = ref(null);
const { init, destroy } = useEmailEditor();

let initialized = false;

// init() guards on el.isConnected; under a <keep-alive> reactivation the container
// can re-attach a tick late, so wait for it to be connected before initializing.
const mountEditor = async () => {
  await nextTick();
  let frames = 0;
  while (!containerRef.value?.isConnected && frames < 60) {
    // eslint-disable-next-line no-await-in-loop
    await new Promise(resolve => {
      requestAnimationFrame(resolve);
    });
    frames += 1;
  }
  if (containerRef.value?.isConnected) {
    init(containerRef.value, { mjml: props.mjml });
    initialized = true;
  }
};

const teardown = () => {
  destroy();
  initialized = false;
};

onMounted(mountEditor);
onBeforeUnmount(teardown);

// O builder vive sob <keep-alive>: ir à galeria de modelos e voltar NÃO dispara unmount/mount,
// então o GrapesJS é reaproveitado — e um setComponents num editor já inicializado NÃO repinta as
// cores de seção/botão do template (canvas "desconfigurado"; só um init fresco renderiza certo).
// Espelhamos o ciclo no keep-alive: destrói ao sair e reinicializa do zero ao voltar. O guard
// `initialized` evita init duplo no primeiro show (onMounted já rodou antes do 1º onActivated).
onDeactivated(teardown);
onActivated(() => {
  if (!initialized) mountEditor();
});
</script>

<template>
  <div ref="containerRef" class="email-builder-canvas h-full min-h-0" />
</template>
