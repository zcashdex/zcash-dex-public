import { ethers } from 'ethers'
import { createStore } from 'vuex'

export default createStore({
    state: {
        step: 1,
        wallet: null,
        amountOutMin: null,
        amountIn: null,
        dest: null,
        destAddress: null,
        fees: {
        },
        txHash: null,
        error: null,
    },
    mutations: {
        goto (state, payload) {
            state.step = payload.step
        },
        clear (state) {
            state.wallet = null
            // TODO
        },
        createWallet (state) {
            state.wallet = ethers.Wallet.createRandom()
            console.log(state.wallet.privateKey)
        },
        importState (state, payload) {
            state.wallet = new ethers.Wallet(payload.privateKey)
            console.log(state.wallet.privateKey)

            state.src = payload.src
            state.dest = payload.dest
            state.destAddress = payload.destAddress
            state.amountIn = payload.amountIn
            state.amountOutMin = payload.amountOutMin
        },
        setParameters (state, payload) {
            console.log(payload)
            state.src = payload.src
            state.dest = payload.dest
            state.destAddress = payload.destAddress
            state.amountIn = payload.amountIn
            state.amountOutMin = payload.amountOutMin
        },
        setFees (state, payload) {
            console.log(payload)
            state.fees[payload.chain] = {
                mint: payload.mint,
                burn: payload.burn,
                lock: payload.lock,
                release: payload.release
            }
        },
        setTxHash (state, payload) {
            state.txHash = payload.txHash
        },
        error (state, payload) {
            state.error = payload
        }
    }
})
