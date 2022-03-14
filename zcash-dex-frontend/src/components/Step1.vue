<script setup>
import { ref } from 'vue'
import { useStore } from 'vuex'

const filePicker = ref(null)

const store = useStore()
store.commit('clear')

function newTransaction() {
    store.commit('createWallet')
    store.commit('goto', { step: 2 })
}

function resumeTransaction() {
    filePicker.value.click()
}

async function selectedFile() {
    if (filePicker.value.files.length != 1) {
        return
    }

    const file = filePicker.value.files[0]
    const data = JSON.parse(await file.text())
    // TODO validate data

    store.commit('importState', data)
    store.commit('goto', { step: 4 })
}
</script>

<template>
    <form>
        <div class="card bg-base-200">
            <div class="card-body flex flex-col gap-6">
                <div>
                    <button type="button" class="btn btn-primary w-52" @click="newTransaction">New transaction</button>
                </div>
                <div>
                    <button type="button" class="btn btn-secondary w-52" @click="resumeTransaction">Resume transaction</button>
                </div>
                <input type="file" ref="filePicker" style="display:none" @change="selectedFile">
            </div>
        </div>
    </form>
</template>

<style scoped>
</style>
