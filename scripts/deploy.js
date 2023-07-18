const { runDeployMarket } = require("./deploy_market")
const { deployBase } = require("./deploy_base")
const { readMarketReaderContract } = require("./market/marketReader")
const { readMarketRouterContract } = require("./market/marketRouter")
const { readMarketFactoryContract } = require("./market/marketFactory")
const { readVaultRouterContract } = require("./vault/vaultRouter")
const { handleTx, deployOrConnect } = require("./utils/helpers")

async function main() {
    const results = await deployBase({
        isInit: true,
        isFirstInit: true
    })
    
}

main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})