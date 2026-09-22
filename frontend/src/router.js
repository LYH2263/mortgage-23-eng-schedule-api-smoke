import { createRouter, createWebHistory } from 'vue-router'
import LoanDashboard from './pages/LoanDashboard.vue'
import LoanList from './pages/LoanList.vue'
import LoanDetail from './pages/LoanDetail.vue'
import ScheduleWorkbench from './pages/ScheduleWorkbench.vue'
import RateRules from './pages/RateRules.vue'
import AmortPreview from './pages/AmortPreview.vue'
import PaymentHistory from './pages/PaymentHistory.vue'
import Settings from './pages/Settings.vue'

export default createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', component: LoanDashboard },
    { path: '/loans', component: LoanList },
    { path: '/loans/:id', component: LoanDetail },
    { path: '/schedule', component: ScheduleWorkbench },
    { path: '/rates', component: RateRules },
    { path: '/amort', component: AmortPreview },
    { path: '/history', component: PaymentHistory },
    { path: '/settings', component: Settings },
  ],
})
