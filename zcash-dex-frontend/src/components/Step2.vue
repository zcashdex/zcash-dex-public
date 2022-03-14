<script setup>
import { ethers } from 'ethers'
import throttle from 'lodash/throttle'
import { inject, ref, watch, computed } from 'vue'
import { useStore } from 'vuex'
import { Polygon } from '@renproject/chains-ethereum'
import { Bitcoin, BitcoinCash, Dogecoin, Zcash } from '@renproject/chains-bitcoin'

const coins = inject('coins')
const web3 = inject('web3')
const processing = ref(false)
const amount = ref(null)
const src = ref('ZEC.ZEC')
const dest = ref(null)
const destAddress = ref(null)
const amountOut = ref(null)
const amountFees = ref(null)
const decimalsOut = ref(null)

function formatCurrency(numString) {
    const x = Number(numString)
    if (x >= 10000) {
        return x.toFixed()
    } else {
        return x.toPrecision(6)
    }
}

function validateAddress(address, dest) {
    try {
        return coins[dest].validateAddress(address)
    } catch (e) {
        return false
    }
}

watch([amount, src, dest], throttle(async ([amount, src, dest], [prevAmount, prevSrc, prevDest], onCleanup) => {
    let cancelled = false
    onCleanup(() => cancelled = true)
    if (amount && src && dest) {
        processing.value = true
        destAddress.value = ""
        try {
            const [estAmountOut, decimals] = await web3.estimateAmountOut(ethers.utils.parseUnits(amount, 8), src, dest, true, true, true)
            const [estAmountOutNoFees, decimalsFees] = await web3.estimateAmountOut(ethers.utils.parseUnits(amount, 8), src, dest, false, false, false)
            if (!cancelled) {
                amountOut.value = estAmountOut
                amountFees.value = estAmountOutNoFees.sub(estAmountOut)
                decimalsOut.value = decimals
            }
        } finally {
            processing.value = false
        }
    }
}, 1000, { leading: false }))

const store = useStore()

const invalidAddress = computed(() => {
    return !validateAddress(destAddress.value, dest.value)
})

const invalid = computed(() => {
    return invalidAddress.value || amountOut.value.lt(0)
})

async function saveParameters() {
    if (invalid.value) {
        return
    }
    processing.value = true
    const [estAmountOut, decimals] = await web3.estimateAmountOut(ethers.utils.parseUnits(amount.value, 8), src.value, dest.value, false, true, true)
    store.commit('setParameters', {
        src: src.value,
        dest: dest.value,
        destAddress: destAddress.value,
        amountIn: amount.value,
        amountOutMin: estAmountOut.toString()
    })
    store.commit('goto', { step: 3 })
}
</script>

<template>
    <form>
        <div class="card bg-base-200">
            <div class="card-body flex flex-col gap-6">
                <div class="w-full">
                    <label class="label">
                        <span class="label-text">Source</span>
                    </label>
                    <select v-model="src" :disabled="processing" class="select w-full">
                        <option value="ZEC.ZEC">ZEC (Zcash)</option>
                        <option value="BTC.BTC">BTC (Bitcoin)</option>
                        <option value="BCH.BCH">BCH (Bitcoin Cash)</option>
                        <option value="DOGE.DOGE">DOGE (Dogecoin)</option>
                        <!--
                        <option value="ETH.ETH">ETH (Ethereum)</option>
                        <option value="UST.TERRA">UST (Terra)</option>
                        -->
                    </select>
                </div>
                <div class="">
                    <input v-model="amount" type="text" placeholder="Amount" :disabled="processing" class="input w-full">
                </div>
                <div>
                    <label class="label">
                        <span class="label-text">Destination</span>
                    </label>
                    <select v-model="dest" :disabled="processing" class="select w-full">
                        <option value="MATIC.POLYGON">MATIC (Polygon)</option>
                        <option value="BTC.BTC">BTC (Bitcoin)</option>
                        <option value="BCH.BCH">BCH (Bitcoin Cash)</option>
                        <option value="DOGE.DOGE">DOGE (Dogecoin)</option>
                        <option value="ZEC.ZEC">ZEC (Zcash)</option>
                        <!--
                        <option value="ETH.ETH">ETH (Ethereum)</option>
                        <option value="UST.TERRA">UST (Terra)</option>
                        -->
                    </select>
                </div>
                <div>
                    <input id="destAddress" :class="{ 'input-bordered': invalidAddress, 'input-error': invalidAddress }" v-model="destAddress" type="text" placeholder="Receiver" :disabled="!dest || processing" class="input w-full">
                </div>
                <div v-if="processing">
                    Please wait...
                </div>
                <div v-else-if="amountOut">
                    <label class="label">
                        <span class="label-text">Estimate</span>
                    </label>
                    <p class="text-right">
                        ~{{ formatCurrency(ethers.utils.formatUnits(amountOut, decimalsOut)) }} {{ coins[dest].symbol }}
                    </p>
                    <p class="text-right">
                        (includes {{ formatCurrency(ethers.utils.formatUnits(amountFees, decimalsOut)) }} {{ coins[dest].symbol }} fee)
                    </p>
                </div>
                <div>
                    <button type="button" @click="saveParameters" :disabled="processing || invalid || !amountOut" class="btn btn-primary">Confirm</button>
                </div>
            </div>
        </div>
    </form>
</template>

<style scoped>
.error {
    background-color: #ee5c5c;
}
</style>
