<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useEmailEditor } from './composables/useEmailEditor';

import PropField from './components/PropField.vue';
import PropSize from './components/PropSize.vue';
import PropColor from './components/PropColor.vue';
import PropAlign from './components/PropAlign.vue';
import PropSpacing from './components/PropSpacing.vue';
import PropFontFamily from './components/PropFontFamily.vue';
import PropTextStyle from './components/PropTextStyle.vue';
import PropLineHeight from './components/PropLineHeight.vue';
import PropImage from './components/PropImage.vue';
import PropLink from './components/PropLink.vue';
import PropRadius from './components/PropRadius.vue';

const { t } = useI18n();

const {
  selectedComponent,
  selectedType,
  styleVersion,
  getProperty,
  upValue,
  getStyleProp,
  applyStyleProp,
  getSectionStyle,
  setSectionStyle,
} = useEmailEditor();

// We NEVER cache property values. `revision` is bumped whenever the selection
// or the style state changes so the curated controls re-read getProperty/getValue.
const revision = ref(0);

const hasSelection = computed(() => Boolean(selectedComponent.value));

// grapesjs-mjml tipa imagens como 'mj-image'.
const isImage = computed(() => selectedType.value === 'mj-image');
// grapesjs-mjml tipa botoes como 'mj-button'.
const isButton = computed(() => selectedType.value === 'mj-button');
// Ícone de rede social (dentro do mj-social do rodapé) — só precisa do campo Link.
const isSocialElement = computed(
  () => selectedType.value === 'mj-social-element'
);

// Look up the live Property objects each time selection/style changes. The
// objects themselves are markRaw (Backbone) — only `revision` is reactive.
const fontSizeProp = ref(null);
const fontFamilyProp = ref(null);
const lineHeightProp = ref(null);
const widthProp = ref(null);
const colorProp = ref(null);
const bgColorProp = ref(null);
const buttonBgProp = ref(null);
const radiusProp = ref(null);
const alignProp = ref(null);
const paddingProp = ref(null);
const marginProp = ref(null);

// Synthetic Property-like object backed by the composable's robust style helpers.
// Exposes the same getValue/upValue contract PropColor reads and upValue() calls,
// so the "Fundo" control works even if the sector doesn't expose the property.
const makeStyleProp = (sector, propName) => ({
  getValue: () => getStyleProp(sector, propName),
  upValue: value => applyStyleProp(sector, propName, value),
});

// Synthetic Property bound to the ANCESTOR mj-section's style — used for the
// block "Fundo" of a button, so the control shows/edits the colored band the user
// actually sees (not the button's usually-empty container-background-color).
const makeSectionProp = propName => ({
  getValue: () => getSectionStyle(propName),
  upValue: value => setSectionStyle(propName, value),
});

const refresh = () => {
  fontSizeProp.value = getProperty('Typography', 'font-size');
  fontFamilyProp.value = getProperty('Typography', 'font-family');
  lineHeightProp.value = getProperty('Typography', 'line-height');
  widthProp.value = getProperty('Dimension', 'width');
  colorProp.value = getProperty('Typography', 'color');
  // "Fundo" = the visible BLOCK background, i.e. the ancestor mj-section's
  // background-color (the colored band the user actually sees) — for EVERY
  // selection, not only buttons. Binding non-buttons to the element's own
  // container-background-color edited the wrong layer (the cell, usually empty),
  // so the control looked broken. makeSectionProp reuses the validated
  // getSectionStyle/setSectionStyle path that maps to the mj-section attribute and
  // survives getMjml/getHtml. For a button we ALSO show "Fundo do botão" (the
  // button's own background-color) + "Arredondamento" (border-radius); mj-button
  // registers those in Decorations, with a synthetic getStyleProp fallback.
  bgColorProp.value = makeSectionProp('background-color');
  buttonBgProp.value = isButton.value
    ? (getProperty('Decorations', 'background-color') ??
      makeStyleProp('Decorations', 'background-color'))
    : null;
  radiusProp.value = isButton.value
    ? (getProperty('Decorations', 'border-radius') ??
      makeStyleProp('Decorations', 'border-radius'))
    : null;
  // MJML aligns blocks via the `align` ATTRIBUTE (mj-text/mj-image/mj-button/
  // mj-section all honor `align`). The grapesjs-mjml two-way binding maps the
  // `align` style -> `align` attribute, which re-renders the canvas. `text-align`
  // is only meaningful for a handful of cases, so we prefer `align` and fall back.
  alignProp.value =
    getProperty('Typography', 'align') ??
    getProperty('Typography', 'text-align');
  paddingProp.value = getProperty('Dimension', 'padding');
  marginProp.value = getProperty('Dimension', 'margin');
  revision.value += 1;
};

watch([selectedComponent, styleVersion], refresh, { immediate: true });

const onChange = (prop, value) => {
  if (!prop) return;
  upValue(prop, value);
  // re-read so the control reflects the normalized value from the editor
  revision.value += 1;
};

const onPartial = (prop, value) => {
  if (!prop) return;
  upValue(prop, value, { partial: true });
};

// PropTextStyle writes directly via the composable (property OR getStyle fallback),
// so we only need to re-read the live values afterwards.
const onStyleChange = () => {
  revision.value += 1;
};
</script>

<template>
  <aside
    class="flex flex-col h-full min-h-0 overflow-y-auto bg-n-solid-2 border-l border-n-weak"
  >
    <header class="px-4 py-3 border-b border-n-weak">
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.TITLE') }}
      </h3>
    </header>

    <div
      v-if="!hasSelection"
      class="flex flex-col items-center justify-center flex-1 gap-2 px-6 py-10 text-center"
    >
      <span class="i-lucide-mouse-pointer-click size-6 text-n-slate-10" />
      <p class="text-sm text-n-slate-11">
        {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.EMPTY') }}
      </p>
    </div>

    <div v-else class="flex flex-col gap-6 p-4">
      <!-- Imagem (apenas mj-image) -->
      <section v-if="isImage" class="flex flex-col gap-3">
        <h4
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.IMAGE.TITLE') }}
        </h4>
        <PropImage :revision="revision" />
      </section>

      <!-- Link (mj-button + ícone de rede social; imagens ja tem href no PropImage) -->
      <section v-if="isButton || isSocialElement" class="flex flex-col gap-3">
        <h4
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.LINK.TITLE') }}
        </h4>
        <PropLink :revision="revision" />
      </section>

      <!-- Tamanho -->
      <section class="flex flex-col gap-3">
        <h4
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.SIZE.TITLE') }}
        </h4>
        <PropField
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.SIZE.FONT_SIZE')"
          :revision="revision"
        >
          <PropSize
            :property="fontSizeProp"
            :revision="revision"
            @change="onChange"
          />
        </PropField>
        <PropField
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.SIZE.WIDTH')"
          :revision="revision"
        >
          <PropSize
            :property="widthProp"
            :revision="revision"
            @change="onChange"
          />
        </PropField>
      </section>

      <!-- Texto -->
      <section class="flex flex-col gap-3">
        <h4
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.TEXT.TITLE') }}
        </h4>
        <PropField
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.TEXT.FONT_FAMILY')"
          :revision="revision"
        >
          <PropFontFamily
            :property="fontFamilyProp"
            :revision="revision"
            @change="onChange"
          />
        </PropField>
        <PropField
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.TEXT.STYLE')"
          :revision="revision"
        >
          <PropTextStyle :revision="revision" @change="onStyleChange" />
        </PropField>
        <PropField
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.TEXT.LINE_HEIGHT')"
          :revision="revision"
        >
          <PropLineHeight
            :property="lineHeightProp"
            :revision="revision"
            @change="onChange"
          />
        </PropField>
      </section>

      <!-- Cor -->
      <section class="flex flex-col gap-3">
        <h4
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.COLOR.TITLE') }}
        </h4>
        <PropField
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.COLOR.TEXT')"
          :revision="revision"
        >
          <PropColor
            :property="colorProp"
            :revision="revision"
            @change="onChange"
          />
        </PropField>
        <PropField
          v-if="isButton"
          :label="
            t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.COLOR.BUTTON_BACKGROUND')
          "
          :revision="revision"
        >
          <PropColor
            :property="buttonBgProp"
            :revision="revision"
            @change="onChange"
          />
        </PropField>
        <PropField
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.COLOR.BACKGROUND')"
          :revision="revision"
        >
          <PropColor
            :property="bgColorProp"
            :revision="revision"
            @change="onChange"
          />
        </PropField>
      </section>

      <!-- Alinhamento -->
      <section class="flex flex-col gap-3">
        <h4
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.ALIGN.TITLE') }}
        </h4>
        <PropField
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.ALIGN.LABEL')"
          :revision="revision"
        >
          <PropAlign
            :property="alignProp"
            :revision="revision"
            @change="onChange"
          />
        </PropField>
      </section>

      <!-- Espacamento -->
      <section class="flex flex-col gap-3">
        <h4
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.SPACING.TITLE') }}
        </h4>
        <PropField
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.SPACING.PADDING')"
          :revision="revision"
        >
          <PropSpacing
            :property="paddingProp"
            :revision="revision"
            @change="onChange"
            @partial="onPartial"
          />
        </PropField>
        <PropField
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.SPACING.MARGIN')"
          :revision="revision"
        >
          <PropSpacing
            :property="marginProp"
            :revision="revision"
            @change="onChange"
            @partial="onPartial"
          />
        </PropField>
        <PropField
          v-if="isButton"
          :label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.SPACING.RADIUS')"
          :revision="revision"
        >
          <PropRadius
            :property="radiusProp"
            :revision="revision"
            @change="onChange"
            @partial="onPartial"
          />
        </PropField>
      </section>
    </div>
  </aside>
</template>
