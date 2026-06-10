<script>
import IframeLoader from 'shared/components/IframeLoader.vue';

export default {
  name: 'ArticleViewer',
  components: {
    IframeLoader,
  },
};
</script>

<template>
  <div class="bg-white h-full">
    <!--
      Key by fullPath (not just the link) so the iframe remounts on every
      navigation here, including re-opening the same article via the SDK after
      the iframe was browsed to another help-center page. See App.vue#openArticle.
    -->
    <IframeLoader :key="$route.fullPath" :url="$route.query.link" />
  </div>
</template>
