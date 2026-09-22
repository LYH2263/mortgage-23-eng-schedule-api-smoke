<script setup>
import { onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { getJSON, postJSON } from '../api'
const route = useRoute()
const loan = ref(null)
const sch = ref(null)
const load = async () => {
  loan.value = await getJSON(`/api/loans/${route.params.id}`)
  sch.value = await postJSON('/api/schedule', { principal: loan.value.principal, annual_rate: loan.value.annual_rate, months: loan.value.months, loan_id: loan.value.id, persist: false, preview_rows: 6 })
}
onMounted(load); watch(() => route.params.id, load)
</script>
<template><div class="page" v-if="loan"><h1>{{ loan.name }}</h1>
<p>月供 <span class="hero-num">{{ sch?.monthly_payment }}</span></p>
<table><tr v-for="r in sch?.preview" :key="r.period"><td>{{ r.period }}</td><td>{{ r.payment }}</td><td>{{ r.principal }}</td><td>{{ r.interest }}</td></tr></table>
</div></template>
