<script setup>
import { computed, ref } from 'vue'
import { useStore } from 'vuex'

const store = useStore()

const downloaded = ref(false)
const backupObjectUrl = computed(() => {
    return URL.createObjectURL(new Blob([JSON.stringify({
        // required fields, otherwise funds are lost
        src: store.state.src,
        privateKey: store.state.wallet.privateKey,

        // convenience only
        dest: store.state.dest,
        destAddress: store.state.destAddress,
        amountIn: store.state.amountIn,
        amountOutMin: store.state.amountOutMin,
    })]))
})
</script>

<template>
    <form>
        <div class="card bg-base-200">
            <div class="card-body flex flex-col gap-6">
                <div>
                    <h3>IMPORTANT!</h3>
                    <p>Download and keep this backup file until entire process has completed. This file can be used to steal your funds. Do NOT share it with anyone.</p>
                </div>
                <div>
                    <a @click="downloaded = true" :href="backupObjectUrl" download="zcash-dex-backup.txt" class="btn btn-primary">Download Backup</a>
                </div>
                <div>
                    <button type="button" :disabled="!downloaded" @click="store.commit('goto', { step: 4 })" class="btn btn-primary">Continue</button>
                </div>
            </div>
        </div>
    </form>
</template>
<style scoped>
div {
    margin: 1rem;
}
button {
    width: 10rem;
}
</style>
