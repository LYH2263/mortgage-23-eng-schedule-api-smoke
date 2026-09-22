<script setup>
import { onMounted, ref } from 'vue'
import { getJSON } from '../api'
const items = ref([])
onMounted(async () => { items.value = (await getJSON('/api/loans')).items })
</script>
<template><div class="page"><h1>贷款列表</h1>
<table><tr v-for="l in items" :key="l.id"><td>{{ l.name }}</td><td>{{ l.principal }}</td><td><router-link :to="`/loans/${l.id}`">详情</router-link></td></tr></table>
</div></template>
