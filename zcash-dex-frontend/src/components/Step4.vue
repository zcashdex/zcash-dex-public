<script setup>
import { Polygon } from '@renproject/chains-ethereum'
import { Bitcoin, BitcoinCash, Dogecoin, Zcash } from '@renproject/chains-bitcoin'
import { ethers } from 'ethers'
import { inject, computed, ref } from 'vue'
import { useStore } from 'vuex'

const store = useStore()

const gatewayAddress = ref(null)
const status = ref(null)
const targetConfirmations = ref(null)
const currentConfirmations = ref(null)
const renHash = ref(null)
const lockAmount = ref(null)
const lockHash = ref(null)
const polygonHash = ref(null)

const newAmountOut = ref(null)
const newDecimalsOut = ref(null)

const backend = inject('backend')
const coins = inject('coins')
const renJS = inject('renJS')
const web3 = inject('web3')

let foundDeposit
let amountOutMin = store.state.amountOutMin
const srcSymbol = computed(() => coins[store.state.src].symbol)

function formatCurrency(numString) {
    const x = Number(numString)
    if (x >= 10000) {
        return x.toFixed()
    } else {
        return x.toPrecision(6)
    }
}

function wait(millis) {
    return new Promise(function(resolve, reject) {
        setTimeout(resolve, millis)
    })
}

async function handleBackendError(response) {
    if (response.status == 400) {
        const data = await response.json()
        store.commit('error', {
            message: `${ data.error.code } ${ data.error.reason }`,
        })
    } else {
        store.commit('error', {
            message: `Backend error: ${ response.status }`
        })
    }
}

async function findSwap() {
    const latestBlockNumber = await web3.provider.getBlockNumber()
    const logs = await web3.provider.getLogs({
        address: web3.addresses.EXCHANGE,
        topics: [
            // Swap(receiver, mint, dest)
            ['0x11f4b7a3b533a03660188385e81861fb044615f4dafe593932037df7b7836ecd'],
            ethers.utils.defaultAbiCoder.encode(["address"], [store.state.wallet.address]),
            null,
            null,
        ],
        fromBlock: latestBlockNumber - 3600 * 48,
        toBlock: "latest"
    })
    if (logs.length > 0) {
        store.commit('setTxHash', { txHash: logs[0].transactionHash })
        store.commit('goto', { step: 5 })
        return true
    } else {
        console.log('log not found')
        return false
    }
}

function updateAmountOutMin() {
    amountOutMin = newAmountOut.value.toString()
    processDeposit(currentDeposit)
}

async function getSwapMessage(amountWithFee) {
    const block = await web3.provider.getBlock('latest')
    const deadline = block.timestamp + 600
    const [estAmountOutSlippage, decimalsOut] = await web3.estimateAmountOut(amountWithFee, store.state.src, store.state.dest, false, false, true)
    const prevAmountOutSlippage = ethers.BigNumber.from(amountOutMin)
    if (estAmountOutSlippage.mul(100).div(99).lt(prevAmountOutSlippage)) {
        status.value = "slippage"
        currentDeposit = deposit
        newAmountOut.value = estAmountOutSlippage
        newDecimalsOut.value = decimalsOut
        return {}
    }
    const msg = ethers.utils.defaultAbiCoder.encode(
        ["tuple(address,uint256,uint256,address,address,address,bytes)"], [[
            coins[store.state.src].token,
            estAmountOutSlippage.gt(prevAmountOutSlippage) ? estAmountOutSlippage : prevAmountOutSlippage,
            deadline,
            coins[store.state.src].swap.address,
            coins[store.state.dest].swap ? coins[store.state.dest].swap.address : '0x0000000000000000000000000000000000000000',
            coins[store.state.dest].token ? coins[store.state.dest].token : '0x0000000000000000000000000000000000000000',
            store.state.dest == 'MATIC.POLYGON' ? ethers.utils.defaultAbiCoder.encode(["address"], [store.state.destAddress]) : ethers.utils.toUtf8Bytes(store.state.destAddress),
        ]]
    )
    const msgsig = await store.state.wallet.signMessage(
        ethers.utils.arrayify(
            ethers.utils.keccak256(
                ethers.utils.arrayify(msg)
            )
        )
    )
    const vaultsig = await store.state.wallet.signMessage(
        ethers.utils.arrayify(
            ethers.utils.keccak256(
                ethers.utils.arrayify(
                    ethers.utils.defaultAbiCoder.encode(
                        ["string", "address", "uint256"],
                        ["vault-" + coins[store.state.src].symbol, web3.addresses.EXCHANGE, amountWithFee]
                    )
                )
            )
        )
    )
    return {
        msg,
        msgsig,
        vaultsig,
    }
}

async function processDepositSlow(deposit) {
    status.value = "confirming"
    switch (deposit.status) {
        default: {
            await deposit
                .confirmed()
                .on("target", (target) => targetConfirmations.value = target)
                .on("confirmation", (confs, target) => {
                    targetConfirmations.value = target
                    currentConfirmations.value = confs
                })
            status.value = "signing"
            await deposit.signed()
        }
        case "signed": {
            const tx = await deposit.queryTx()
            status.value = "minting"
            renHash.value = tx.hash
            const amountWithFee = ethers.BigNumber.from(tx.out.amount.toString())
            const { msg, msgsig, vaultsig } = await getSwapMessage(amountWithFee)
            if (msg === undefined) {
                return
            }
            let response
            try {
                response = await backend.mintAndSwap({
                    src: store.state.src,
                    receiver: store.state.wallet.address,
                    amount: amountWithFee.toString(),
                    msg,
                    msgsig,
                    vaultsig,
                })
            } catch (e) {
                store.commit('error', {
                    message: 'Failed to contact backend server, try again'
                })
                return
            }
            if (response.ok) {
                const data = await response.json()
                polygonHash.value = data.hash
                await web3.provider.waitForTransaction(data.hash)
                await findSwap()
            } else {
                await handleBackendError(response)
            }
        }
    }
    if (await findSwap()) {
        return
    } else {
        store.commit('error', {
            message: `Failed to find log, status: ${ deposit.status }`
        })
        return
    }
}

async function processDepositFast(deposit) {
    status.value = "confirmingFast"
    const requiredConfirmations = 2
    targetConfirmations.value = requiredConfirmations
    while (true) {
        try {
            const response = await coins[store.state.src].chain.api.fetchUTXO(deposit.depositDetails.transaction.txHash, 0)
            currentConfirmations.value = response.confirmations
            if (response.confirmations >= requiredConfirmations) {
                break
            }
            await wait(10000)
        } catch (e) {
            console.log(e)
            store.commit('error', {
                message: 'Failed to retrieve lock tx'
            })
            return
        }
    }
    const amountWithFee = ethers.BigNumber.from(deposit.depositDetails.amount)
            .sub(ethers.BigNumber.from(store.state.fees[store.state.src].lock))
            .mul(10000 - store.state.fees[store.state.src].mint)
            .div(10000)
    const { msg, msgsig, vaultsig } = await getSwapMessage(amountWithFee)
    if (msg === undefined) {
        return
    }
    let response
    try {
        response = await backend.fastMintAndSwap({
            src: store.state.src,
            receiver: store.state.wallet.address,
            amount: amountWithFee.toString(),
            msg,
            msgsig,
            vaultsig,
        })
    } catch (e) {
        store.commit('error', {
            message: 'Failed to contact backend server, try again'
        })
        return
    }
    if (response.ok) {
        const data = await response.json()
        if (data.hash) {
            polygonHash.value = data.hash
            await web3.provider.waitForTransaction(data.hash)
            await findSwap()
        } else {
            // fallback to slow transfer
            await processDepositSlow(deposit)
        }
    } else {
        await handleBackendError(response)
    }
}

async function processDeposit(deposit) {
    console.log("deposit", deposit)
    lockAmount.value = ethers.utils.formatUnits(deposit.depositDetails.amount, 8)
    lockHash.value = deposit.depositDetails.transaction.txHash

    try {
        if (await findSwap()) {
            return
        }
    } catch (e) {
        store.commit('error', {
            message: 'Failed to search for logs'
        })
        return
    }

    await processDepositFast(deposit)

    try {
        await findSwap()
    } catch (e) {
        store.commit('error', {
            message: 'Failed to search for logs'
        })
        return
    }
}

async function doLockAndMint() {
    const { symbol: asset, chain: fromChain, vault } = coins[store.state.src]
    try {
        const lockAndMint = await renJS.lockAndMint({
            asset: asset,
            from: fromChain,
            to: Polygon(web3.provider, renJS).Contract({
                sendTo: vault,
                contractFn: 'mint',
                // this needs to match with hash in solidity contract
                contractParams: [{
                    name: "receiver",
                    type: "address",
                    value: store.state.wallet.address
                }],
            }),
        }, {
            loadCompletedDeposits: true
        })
        gatewayAddress.value = lockAndMint.gatewayAddress

        status.value = "waiting"
        lockAndMint.once("deposit", processDeposit)
    } catch (e) {
        console.log(e)
        store.commit('error', {
            message: 'Unable to query Ren network for gateway'
        })
    }
}
doLockAndMint()
</script>

<template>
    <form>
        <div class="card bg-base-200">
            <div class="card-body flex flex-col gap-6">
                <div v-if="gatewayAddress" class="card card-compact bg-accent text-accent-content">
                    <div class="card-body">
                        <h2 class="card-title">Gateway Address</h2>
                        <p class="font-mono">{{ gatewayAddress }}</p>
                    </div>
                </div>
                <div v-if="!status">
                    <p>Please wait...</p>
                </div>
                <div v-else-if="status == 'waiting'" class="space-y-4">
                    <p>Send {{ store.state.amountIn }} {{ srcSymbol }} in one transaction</p>
                    <p>Do NOT use this address more than once</p>
                    <p>Do NOT send funds after 24 hours</p>
                </div>
                <div v-else-if="status == 'confirmingFast' || status == 'confirming'">
                    <label class="label">
                        <span class="label-text">Deposit TxHash</span>
                    </label>
                    <p class="text-right font-mono truncate w-full"><a target="_blank" :href="coins[store.state.src].transactionExplorerLink(lockHash)">{{ lockHash }}</a></p>
                    <label class="label">
                        <span class="label-text">Deposit Amount</span>
                    </label>
                    <p class="text-right">{{ lockAmount }} {{ srcSymbol }}</p>
                    <label class="label">
                        <span class="label-text">Confirmations</span>
                    </label>
                    <p class="text-right">{{ currentConfirmations }} / {{ targetConfirmations  }} ({{ status == 'confirmingFast' ? 'FAST' : 'Normal' }})</p>
                </div>
                <div v-else-if="status == 'signing'">
                    <p>Waiting for RenVM transaction</p>
                </div>
                <div v-else-if="status == 'minting'">
                    <label class="label">
                        <span class="label-text">Ren TxHash</span>
                    </label>
                    <p class="text-right font-mono truncate w-full"><a target="_blank" href="https://explorer.renproject.io/#/tx/{{ renHash }}">{{ renHash }}</a></p>
                    <label class="label" v-if="polygonHash">
                        <span class="label-text">Polygon TxHash</span>
                    </label>
                    <p class="text-right font-mono truncate w-full" v-if="polygonHash"><a target="_blank" :href="coins['MATIC.POLYGON'].transactionExplorerLink(polygonHash)">{{ polygonHash }}</a></p>
                </div>
                <div v-else-if="status == 'slippage'" class="space-y-4">
                    <div class="alert alert-warning shadow-lg">
                        <div>
                            <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current flex-shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>
                            <span>Warning: Estimated amount out has changed</span>
                        </div>
                    </div>
                    <div>
                        <label class="label">
                            <span class="label-text">Old Estimate</span>
                        </label>
                        <p class="text-right">
                            ~{{ formatCurrency(ethers.utils.formatUnits(amountOutMin, newDecimalsOut)) }} {{ coins[store.state.dest].symbol }}
                        </p>
                        <label class="label">
                            <span class="label-text">New Estimate</span>
                        </label>
                        <p class="text-right">
                            ~{{ formatCurrency(ethers.utils.formatUnits(newAmountOut, newDecimalsOut)) }} {{ coins[store.state.dest].symbol }}
                        </p>
                    </div>
                    <div>
                        <button type="button" @click="updateAmountOutMin" class="btn btn-primary">Confirm</button>
                    </div>
                </div>
                <div v-else>
                    <p>{{ status }}</p>
                </div>
            </div>
        </div>
    </form>
</template>
