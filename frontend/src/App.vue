<template>
  <div class="ledger-app">
    <aside class="ledger-rail">
      <h2>房贷台账</h2>
      <router-link to="/">概览</router-link>
      <router-link to="/loans">贷款</router-link>
      <router-link to="/schedule">月供试算</router-link>
      <router-link to="/rates">利率说明</router-link>
      <router-link to="/amort">摊还预览</router-link>
      <router-link to="/history">记录</router-link>
      <router-link to="/settings">设置</router-link>
    </aside>
    <main class="ledger-main"><router-view /></main>
  </div>
</template>
