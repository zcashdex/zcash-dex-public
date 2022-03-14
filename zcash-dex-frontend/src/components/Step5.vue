<script setup>
import { Polygon } from '@renproject/chains-ethereum'
import { Bitcoin, BitcoinCash, Dogecoin, Zcash } from '@renproject/chains-bitcoin'
import { ethers } from 'ethers'
import { inject, ref } from 'vue'
import { useStore } from 'vuex'

const store = useStore()
const status = ref(null)
const targetConfirmations = ref(null)
const currentConfirmations = ref(null)

const coins = inject('coins')
const renJS = inject('renJS')
const web3 = inject('web3')

async function doRelease() {
    const { symbol: asset, chain: toChain } = coins[store.state.dest]
    if (toChain) {
        console.log(store.state.txHash)
        await web3.provider.waitForTransaction(store.state.txHash) 

        status.value = "burn"
        const burnAndRelease = await renJS.burnAndRelease({
            asset,
            from: Polygon(web3.provider, renJS).Transaction(store.state.txHash),
            to: toChain
        })
        targetConfirmations.value = null
        currentConfirmations.value = null
        await burnAndRelease.burn()
            .on("confirmation", (confs, target) => {
                targetConfirmations.value = target
                currentConfirmations.value = confs
            })

        status.value = "release"
        await burnAndRelease.release()
    }
    status.value = "done"
}
doRelease()
</script>

<template>
    <form>
        <div class="card bg-base-200">
            <div class="card-body flex flex-col">
                <div>
                    <label class="label">
                        <span class="label-text">Polygon TxHash</span>
                    </label>
                    <p class="text-right font-mono truncate w-full"><a target="_blank" :href="coins['MATIC.POLYGON'].transactionExplorerLink(store.state.txHash)">{{ store.state.txHash }}</a></p>
                </div>
                <div v-if="!status" class="m-6">
                    <p>Please wait...</p>
                </div>
                <div v-else-if="status == 'burn'">
                    <label class="label">
                        <span class="label-text">Confirmations</span>
                    </label>
                    <p class="text-right">{{ currentConfirmations }} / {{ targetConfirmations  }}</p>
                </div>
                <div v-else-if="status == 'release'" class="m-6">
                    <p>Submitting to RenVM</p>
                </div>
                <div v-else-if="status == 'done'" class="m-6">
                    <p>Done!</p>
                </div>
            </div>
        </div>
    </form>
</template>
