const axios = require('axios')
const ethers = require('ethers')
const { v4: uuidv4 } = require('uuid')
const { Lock } = require('./lock.js')
const Exchange = require('./artifacts/Exchange.json')
const FastVaultZcash = require('./artifacts/FastVaultZcash.json')

const RenJS = require('@renproject/ren')
const { Bitcoin, BitcoinCash, Dogecoin, Zcash } = require('@renproject/chains-bitcoin')
const { Polygon } = require('@renproject/chains-ethereum')

const cluster = require('cluster')
const cors = require('cors')
const express = require('express')
const app = express()
const port = 3001

const POLYGON_RPC_URL = process.env.POLYGON_RPC_URL

const provider = new ethers.providers.JsonRpcProvider(POLYGON_RPC_URL)
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider)
const walletLock = new Lock()
const exchangeFactory = new ethers.ContractFactory(Exchange.abi, Exchange.data.bytecode.object, wallet)
const exchangeContract = exchangeFactory.attach('0xA42b9873678ad5670698c960a3fED857c530Af5e')
const vaultFactory = new ethers.ContractFactory(FastVaultZcash.abi, FastVaultZcash.data.bytecode.object, wallet)

const coins = {
    'BTC.BTC': {
        chain: Bitcoin(),
        name: 'Bitcoin',
        symbol: 'BTC',
        vault: vaultFactory.attach('0x7E2Dd21A6f370c8D20BB6047C644239d5547A8f7'),
        maxFastAmount: ethers.BigNumber.from(0)
    },
    'BCH.BCH': {
        chain: BitcoinCash(),
        name: 'BitcoinCash',
        symbol: 'BCH',
        vault: vaultFactory.attach('0x3ef1d8ef559cbE27f8C7FEc7bC75309F55c9ceC5'),
        maxFastAmount: ethers.BigNumber.from(0)
    },
    'DOGE.DOGE': {
        chain: Dogecoin(),
        name: 'Dogecoin',
        symbol: 'DOGE',
        vault: vaultFactory.attach('0xE2812357719eB1f67561f6369564A066Ba269361'),
        maxFastAmount: ethers.BigNumber.from(0)
    },
    'ZEC.ZEC': {
        chain: Zcash(),
        name: 'Zcash',
        symbol: 'ZEC',
        vault: vaultFactory.attach('0x8E12AD358676dFe4eF73C3Be4C8861A70cE2cd8f'),
        maxFastAmount: ethers.utils.parseUnits('1', 7)
    },
}

const renJS = new RenJS({
       name: 'mainnet',
       lightnode: 'https://zcashdex.com/lightnode',
       isTestnet: false
})

app.set('trust proxy', 'loopback')
app.use(cors())
app.use(express.json())

function findDeposit(src, receiver) {
    return new Promise(async function (resolve, reject) {
        const lockAndMint = await renJS.lockAndMint({
            asset: src.symbol,
            from: src.chain,
            to: Polygon(provider, renJS).Contract({
                sendTo: src.vault.address,
                contractFn: 'mint',
                contractParams: [{
                    name: "receiver",
                    type: "address",
                    value: receiver
                }],
            })
        }, {
            loadCompletedDeposits: true
        })
        console.log(lockAndMint.gatewayAddress)
        lockAndMint.once('deposit', deposit => resolve(deposit))
        setTimeout(() => {
            lockAndMint.removeAllListeners()
            resolve(null)
        }, 30000)
    })
}

app.get('/', (req, res) => {
    res.send('Hello')
})

app.post('/polygon/mintVault', async (req, res) => {
    const src = coins[req.body.src]
    const overrides = {
        gasLimit: 1000000,
        gasPrice: ethers.utils.parseUnits('40', 'gwei'),
    }
    const deposit = await findDeposit(src, req.body.receiver)
    if (deposit === null) {
        res.status(404).json({
            error: {
                code: 'DEPOSIT_NOT_FOUND',
                reason: 'Timeout waiting for deposit',
            }
        })
        return
    }
    if (deposit.depositDetails.transaction.confirmations <= 24) {
        res.json({
            status: 'confirming'
        })
        return
    }
    if (deposit.status !== 'submitted') {
        await deposit.confirmed()
        await deposit.signed()
        const tx = await deposit.queryTx()
        const params = [
            req.body.receiver,
            tx.out.amount.toString(),
            ethers.utils.hexlify(tx.out.nhash),
            ethers.utils.hexlify(tx.out.signature)
        ]
        await walletLock.acquire()
        try {
            // test to avoid wasting gas
            await src.vault.callStatic.mint(
                ...params,
                overrides
            )
            // submit
            const txResp = await src.vault.mint(
                ...params,
                overrides
            )
            // wait for a confirmation
            await txResp.wait()
        } catch (e) {
            console.log(e)
            res.status(400).json({
                error: {
                    code: e.code,
                    reason: e.reason
                }
            })
            return
        } finally {
            walletLock.release()
        }
    }
    res.json({
        status: 'submitted'
    })
})

app.post('/polygon/fastMintAndSwapForNativeAndTokenAndBridge', async (req, res) => {
    const src = coins[req.body.src]

    if (ethers.BigNumber.from(req.body.amount).gt(src.maxFastAmount)) {
        res.json({
            hash: null,
            reason: 'Amount too high'
        })
        return
    }

    const fees = await renJS.renVM.estimateTransactionFee(src.symbol, { name: src.name }, { name: "Polygon" })
    const deposit = await findDeposit(src, req.body.receiver)
    if (deposit === null) {
        res.status(404).json({
            error: {
                code: 'DEPOSIT_NOT_FOUND',
                reason: 'Timeout waiting for deposit',
            }
        })
        return
    }
    // validate: amount
    const amountWithFee = ethers.BigNumber.from(deposit.depositDetails.amount)
        .sub(ethers.BigNumber.from(fees.lock.toString()))
        .mul(10000 - fees.mint)
        .div(10000)
    if (amountWithFee.toString() !== req.body.amount) {
        res.status(200).json({
            hash: null,
            reason: `Wrong amount, expected: ${amountWithFee.toString()}`
        })
        return
    }

    // validate: confirmations
    if (deposit.depositDetails.transaction.confirmations < 2) {
        res.status(200).json({
            hash: null,
            reason: `Need confirmations, current: ${zcashTx.data.confirmations}`
        })
        return
    }

    const overrides = {
        gasLimit: 2000000,
        gasPrice: ethers.utils.parseUnits('40', 'gwei'),
    }
    const params = [
        req.body.receiver,
        req.body.msg,
        req.body.msgsig,
        src.vault.address,
        req.body.vaultsig,
        ethers.BigNumber.from(req.body.amount),
    ]
    const data = exchangeContract.interface.encodeFunctionData(
        'fastMintAndSwapForNativeAndTokenAndBridge',
        params
    )
    const allowAndCallParams = [
        // validate: nonce prevents replay
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes(deposit.depositDetails.transaction.txHash)),
        req.body.receiver,
        req.body.amount,
        exchangeContract.address,
        data
    ]

    await walletLock.acquire()
    try {
        // test to avoid wasting gas
        await src.vault.callStatic.allowAndCall(
            ...allowAndCallParams,
            overrides
        )
        // submit
        const txResp = await src.vault.allowAndCall(
            ...allowAndCallParams,
            overrides
        )
        res.json({
            hash: txResp.hash
        })
    } catch (e) {
        console.log(e)
        res.status(400).json({
            error: {
                code: e.code,
                reason: e.reason
            }
        })
    } finally {
        walletLock.release()
    }
})

app.post('/polygon/mintAndSwapForNativeAndTokenAndBridge', async (req, res) => {
    const src = coins[req.body.src]
    const deposit = await findDeposit(src, req.body.receiver)
    if (deposit === null) {
        res.status(404).json({
            error: {
                code: 'DEPOSIT_NOT_FOUND',
                reason: 'Timeout waiting for deposit',
            }
        })
        return
    }
    if (deposit.depositDetails.transaction.confirmations <= 24) {
        res.json({
            status: 'confirming'
        })
        return
    }
    if (deposit.status !== 'submitted') {
        await deposit.confirmed()
        await deposit.signed()
        const tx = await deposit.queryTx()
        const overrides = {
            gasLimit: 3000000,
            gasPrice: ethers.utils.parseUnits('40', 'gwei'),
        }
        const params = [
            req.body.receiver,
            req.body.msg,
            req.body.msgsig,
            src.vault.address,
            req.body.vaultsig,
            tx.out.amount.toString(),
            ethers.utils.hexlify(tx.out.nhash),
            ethers.utils.hexlify(tx.out.signature)
        ]

        await walletLock.acquire()
        try {
            // test to avoid wasting gas
            await exchangeContract.callStatic.mintAndSwapForNativeAndTokenAndBridge(
                ...params,
                overrides
            )
            // submit
            const txResp = await exchangeContract.mintAndSwapForNativeAndTokenAndBridge(
                ...params,
                overrides
            )
            res.json({
                status: 'submitted',
                hash: txResp.hash
            })
        } catch (e) {
            console.log(e)
            res.status(400).json({
                error: {
                    code: e.code,
                    reason: e.reason
                }
            })
        } finally {
            walletLock.release()
        }
    } else {
        res.json({
            status: 'submitted',
            hash: null
        })
    }
})

app.post('/polygon/tx/:txHash', async (req, res) => {
    try {
        const txResp = await provider.getTransaction(req.txHash)
        const txReceipt = await txResp.wait(0)
        res.json({
            status: txReceipt && txReceipt.status
        })
    } catch (e) {
        console.log(e)
        res.status(400).json({
            error: {
                code: e.code,
                reason: e.reason
            }
        })
    }
})

app.post('/polygon/rpc', async (req, res) => {
    if (req.body.method == 'eth_chainId') {
        res.json({
            jsonrpc: '2.0',
            result: '0x89',
            id: req.body.id,
        })
        return
    }
    axios({
        url: POLYGON_RPC_URL,
        method: 'post',
        headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
        },
        data: JSON.stringify({
            ...req.body,
            id: uuidv4()
        }),
        responseType: 'json',
        maxRedirects: 0
    }).then(function (response) {
        res.status(response.status).json({
            ...response.data,
            id: req.body.id
        })
    }).catch(function (error) {
        if (error.response) {
            res.status(error.response.status).send(error.response.data)
        } else {
            res.status(400).end()
        }
    })
})

if (cluster.isPrimary) {
    cluster.fork()
    cluster.on('exit', (worker, code, signal) => {
        console.log('exit', code, signal)
        cluster.fork()
    })
} else {
    app.listen(port, () => {
        console.log('Ready')
    })
}
