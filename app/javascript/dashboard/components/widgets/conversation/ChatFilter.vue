<template>
  <select v-model="activeIndex" class="status--filter" @change="onTabChange()">
    <option
      v-for="item in $t('CHAT_LIST.CHAT_STAUTUS_ITEMS')"
      :key="item['TEXT']"
      :value="item['VALUE']"
    >
      {{ item['TEXT'] }}
    </option>
  </select>
</template>

<script>
export default {
  data: () => ({
    activeIndex: 0,
  }),
  methods: {
    onTabChange() {
      this.$store.dispatch('setChatFilter', this.activeIndex);
      this.$emit('statusFilterChange', this.activeIndex);
    },
  },
};
</script>
