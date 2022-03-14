<script setup>
import { ethers } from 'ethers'
import { provide, ref } from 'vue'
import RenJS from '@renproject/ren'
import { Polygon } from '@renproject/chains-ethereum'
import { Bitcoin, BitcoinCash, Dogecoin, Zcash } from '@renproject/chains-bitcoin'

import Step1 from './components/Step1.vue'
import Step2 from './components/Step2.vue'
import Step3 from './components/Step3.vue'
import Step4 from './components/Step4.vue'
import Step5 from './components/Step5.vue'
import store from './store'

const loading = ref(true)

const backend = {
    SENDER_FEE: ethers.utils.parseUnits('0.5', 18),
    POLYGON_RPC_URL: 'https://zcashdex.com/api/v3/polygon/rpc',
    async fastMintAndSwap(params) {
        return await fetch('https://zcashdex.com/api/v3/polygon/fastMintAndSwapForNativeAndTokenAndBridge', {
        //return await fetch('http://localhost:3001/polygon/fastMintAndSwapForNativeAndTokenAndBridge', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(params)
        })
    },
    async mintAndSwap(params) {
        return await fetch('https://zcashdex.com/api/v3/polygon/mintAndSwapForNativeAndTokenAndBridge', {
        //return await fetch('http://localhost:3001/polygon/mintAndSwapForNativeAndTokenAndBridge', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(params)
        })
    },
}
const provider = new ethers.providers.JsonRpcProvider(backend.POLYGON_RPC_URL)
const addresses = {
    RENBCH: '0xc3fEd6eB39178A541D274e6Fc748d48f0Ca01CC3',
    RENBTC: '0xDBf31dF14B66535aF65AaC99C32e9eA844e14501',
    RENDOGE: '0xcE829A89d4A55a63418bcC43F00145adef0eDB8E',
    RENZEC: '0x31a0D1A199631D244761EEba67e8501296d2E383',
    EXCHANGE: '0xA42b9873678ad5670698c960a3fED857c530Af5e',
    SWAP_BITCOIN: '0x18409b99A2cAA1f13be9fc3d3D42aD547F529a82',
    SWAP_ZCASH: '0x987A6BAE403621f4830b45eaA0261a52B555263b',
    SWAP_BITCOINCASH: '0xF7f5c9Ff39A46784A7E1891F7Eb30a43A264AA9b',
    SWAP_DOGECOIN: '0x7e0514A3F42Fe581E7275Ee89Aef561ADf6673A8',
    VAULT_BITCOIN: '0x7E2Dd21A6f370c8D20BB6047C644239d5547A8f7',
    VAULT_BITCOINCASH: '0x3ef1d8ef559cbE27f8C7FEc7bC75309F55c9ceC5',
    VAULT_DOGECOIN: '0xE2812357719eB1f67561f6369564A066Ba269361',
    VAULT_ZCASH: '0x8E12AD358676dFe4eF73C3Be4C8861A70cE2cd8f',
}
const swapAbi = [
    'function estimateFromNativeToToken(uint256 amountIn) view returns (uint256)',
    'function fromNativeToToken(uint256 amountOutMin) payable returns (uint256)',
    'function estimateFromTokenToNative(uint256 amountIn) view returns (uint256)',
]
const swapBitcoin = new ethers.Contract(addresses.SWAP_BITCOIN, swapAbi, provider)
const swapZcash = new ethers.Contract(addresses.SWAP_ZCASH, swapAbi, provider)
const swapBitcoinCash = new ethers.Contract(addresses.SWAP_BITCOINCASH, swapAbi, provider)
const swapDogecoin = new ethers.Contract(addresses.SWAP_DOGECOIN, swapAbi, provider)

// RenJS
const renJS = new RenJS({
    name: 'mainnet',
    lightnode: 'https://lightnode-mainnet.herokuapp.com',
    isTestnet: false,
})
renJS.renVM.sendMessage("ren_queryBlockState", {}).then(({ state }) => {
    console.log(state)
    for (const chain of Object.keys(coins)) {
        const coinState = state.v[coins[chain].symbol]
        console.log(chain, coinState)
        if (coinState) {
            const fees = coinState.fees.chains.filter(x => x.chain == 'Polygon')[0]
            const gasFees = ethers.BigNumber.from(coinState.gasCap).mul(coinState.gasLimit)
            store.commit('setFees', {
                chain,
                mint: Number(fees.mintFee),
                burn: Number(fees.burnFee),
                lock: gasFees.toString(),
                release: gasFees.toString()
            })
        }
    }
    loading.value = false
}).catch(error => {
    console.log(error)
    store.commit('error', {
        message: 'Unable to query Ren network' 
    })
})

const coins = {
    'MATIC.POLYGON': {
        symbol: 'MATIC',
        chain: null,
        swap: null,
        token: null,
        vault: null,
        validateAddress: Polygon.utils.addressIsValid,
        transactionExplorerLink: Polygon.utils.transactionExplorerLink,
    },
    'BTC.BTC': {
        symbol: 'BTC',
        chain: Bitcoin(),
        swap: swapBitcoin,
        token: addresses.RENBTC,
        vault: addresses.VAULT_BITCOIN,
        validateAddress: Bitcoin.utils.addressIsValid,
        transactionExplorerLink: Bitcoin.utils.transactionExplorerLink,
    },
    'BCH.BCH': {
        symbol: 'BCH',
        chain: BitcoinCash(),
        swap: swapBitcoinCash,
        token: addresses.RENBCH,
        vault: addresses.VAULT_BITCOINCASH,
        validateAddress: BitcoinCash.utils.addressIsValid,
        transactionExplorerLink: BitcoinCash.utils.transactionExplorerLink,
    },
    'DOGE.DOGE': {
        symbol: 'DOGE',
        chain: Dogecoin(),
        swap: swapDogecoin,
        token: addresses.RENDOGE,
        vault: addresses.VAULT_DOGECOIN,
        validateAddress: Dogecoin.utils.addressIsValid,
        transactionExplorerLink: Dogecoin.utils.transactionExplorerLink,
    },
    'ZEC.ZEC': {
        symbol: 'ZEC',
        chain: Zcash(),
        swap: swapZcash,
        token: addresses.RENZEC,
        vault: addresses.VAULT_ZCASH,
        validateAddress: Zcash.utils.addressIsValid,
        transactionExplorerLink: Zcash.utils.transactionExplorerLink,
    },
}

provide('backend', backend)
provide('coins', coins)
provide('renJS', renJS)
provide('store', store)
provide('web3', {
    addresses,
    provider,
    swapBitcoin,
    swapZcash,
    async estimateAmountOut(amountIn, src, dest, withBurnFee, withMintFee, withSenderFee) {
        // mint fees
        if (withMintFee) {
            amountIn = amountIn.sub(store.state.fees[src].lock)
            amountIn = amountIn.mul(10000 - store.state.fees[src].mint).div(10000)
        }
        if (amountIn.lt(0)) {
            amountIn = ethers.BigNumber.from(0)
        }

        let amountMatic = await coins[src].swap.estimateFromTokenToNative(amountIn)
        // slippage
        amountMatic = amountMatic.mul(99).div(100)
        // sender fee
        if (withSenderFee) {
            amountMatic = amountMatic.sub(backend.SENDER_FEE)
        }
        if (amountMatic.lt(0)) {
            amountMatic = ethers.BigNumber.from(0)
        }

        switch (dest) {
            case 'MATIC.POLYGON': {
                return [amountMatic, 18]
            }
            default: {
                let amountDest = await coins[dest].swap.estimateFromNativeToToken(amountMatic)
                // burn fees
                if (withBurnFee) {
                    amountDest = amountDest.mul(10000 - store.state.fees[dest].burn).div(10000)
                    amountDest = amountDest.sub(store.state.fees[dest].release)
                }
                return [amountDest, 8]
            }
        }
    },
})

window.onerror = () => {
    store.commit('error', {
        message: 'Unexpected error'
    })
}
</script>

<template>
    <div class="flex flex-col min-h-screen">
        <div class="navbar bg-base-200">
            <a class="btn btn-ghost normal-case text-xl" href="/"><img src="/logo.png" class="max-h-8 pr-4">ZcashDex</a>
        </div>
        <div class="grow columns-1 w-full max-w-xl self-center">
            <div v-if="store.state.error">
                <h3>Error</h3>
                <p>{{ store.state.error.message }}</p>
                <p>(some errors can be fixed by trying again in a few minutes)</p>
            </div>
            <div v-else-if="loading" class="m-10">
                <div class="card bg-base-200">
                    <div class="card-body">
                        Please wait...
                    </div>
                </div>
            </div>
            <div v-else class="flex flex-col gap-10 m-10">
                <ul class="steps w-full">
                    <li class="step" :class="{ 'step-primary': store.state.step >= 1 }">Start</li> 
                    <li class="step" :class="{ 'step-primary': store.state.step >= 2 }">Options</li> 
                    <li class="step" :class="{ 'step-primary': store.state.step >= 3 }">Backup</li> 
                    <li class="step" :class="{ 'step-primary': store.state.step >= 4 }">Transfer</li> 
                    <li class="step" :class="{ 'step-primary': store.state.step >= 5 }">Finalize</li> 
                </ul>
                <div>
                    <Step1 v-if="store.state.step == 1"/>
                    <Step2 v-if="store.state.step == 2"/>
                    <Step3 v-if="store.state.step == 3"/>
                    <Step4 v-if="store.state.step == 4"/>
                    <Step5 v-if="store.state.step == 5"/>
                </div>
            </div>
        </div>
        <footer class="footer items-center p-4 bg-neutral text-neutral-content flex-none">
          <div class="items-center grid-flow-col">
            <p>Copyright © 2022 - All right reserved</p>
          </div> 
          <div class="grid-flow-col gap-4 md:place-self-center md:justify-self-end">
            <p>support@zcashdex.com (<a href="/zcashdex.asc">GPG</a>) <a target="_blank" href="https://github.com/zcashdex/zcash-dex-public"><img src="/github.png" class="inline max-h-4 align-sub pl-2"></a></p>
          </div>
        </footer>
    </div>
</template>

<style>
#app {
  font-family: Avenir, Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  text-align: center;
}
</style>
