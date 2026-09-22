<script setup>
import { onMounted, ref } from 'vue'
import { getJSON } from '../api'
const s = ref({})
onMounted(async () => { s.value = await getJSON('/api/settings') })
</script>
<template><div class="page"><h1>设置</h1><pre>{{ s }}</pre></div></template>
