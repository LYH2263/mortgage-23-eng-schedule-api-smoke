<script setup>
import { ref } from 'vue'
import { postJSON } from '../api'
const out = ref(null)
const load = async () => { out.value = await postJSON('/api/schedule', { principal: 1000000, annual_rate: 3.5, months: 360, persist: false, preview_rows: 12 }) }
load()
</script>
<template><div class="page"><h1>摊还表预览</h1>
<table v-if="out"><tr v-for="r in out.preview" :key="r.period"><td>第{{ r.period }}期</td><td>{{ r.payment }}</td><td>{{ r.balance }}</td></tr></table>
</div></template>
