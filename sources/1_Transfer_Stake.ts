import { beginCell, contractAddress, toNano, Cell, Address, TonClient4 } from "ton";
import { testAddress } from "ton-emulator";
import { deploy } from "./utils/deploy";
import { printAddress, printDeploy, printHeader } from "./utils/print";
// ================================================================= //
import { NftCollection } from "./output/sample_NftCollection";
import { NftItem, storeStake } from "./output/sample_NftItem";

// ================================================================= //
(async () => {

    const client = new TonClient4({
        endpoint: "https://sandbox-v4.tonhubapi.com",
    });

    const OFFCHAIN_CONTENT_PREFIX = 0x01;
    const string_first = "https://s.getgems.io/nft-staging/c/628f6ab8077060a7a8d52d63/";
    let newContent = beginCell().storeInt(OFFCHAIN_CONTENT_PREFIX, 8).storeStringRefTail(string_first).endCell();

    let body = beginCell().storeUint(0, 32).storeStringTail("Mint").endCell();

    // Parameters
    let owner = Address.parse(""); // Replace owner with your address
    let init = await NftCollection.init(
        owner, 
        newContent, 
        {
            $$type: "RoyaltyParams",
            numerator: 350n, // 350n = 35%
            denominator: 1000n,
            destination: owner,
        }
    );

    let address = contractAddress(0, init);
    let deployAmount = toNano("0.5");
    let testnet = true;
    printAddress(address);
    
    // Collection Address // 
    let contract_dataFormat = NftCollection.fromAddress(address);
    let contract = client.open(contract_dataFormat);
    // let itemAddress = await contract.getGetNftAddressByIndex(1n);

    let nft_item_init = await NftItem.init(contract.address, 0n, owner, newContent);

    let packed = beginCell().store(
        storeStake({
            $$type: 'Stake',
            duration: 86400n
    })).endCell(); 

    printHeader("sampleNFT_Contract");

    // Do deploy
    await deploy(nft_item_init, deployAmount, packed, testnet);
    printAddress(contractAddress(0, nft_item_init));
})();
