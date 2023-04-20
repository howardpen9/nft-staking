import { beginCell, Address, contractAddress, ContractProvider, TonClient4, TonClient, fromNano } from "ton";
import { printSeparator } from "./utils/print";
import { getHttpEndpoint } from "@orbs-network/ton-access";

import { NftCollection } from "./output/sample_NftCollection";
import { NftItem, storeStake } from "./output/sample_NftItem";
import { StakingContract } from "./output/sample_StakingContract";



const OFFCHAIN_CONTENT_PREFIX = 0x01;
const string_first = "https://s.getgems.io/nft-staging/c/628f6ab8077060a7a8d52d63/";
let newContent = beginCell().storeInt(OFFCHAIN_CONTENT_PREFIX, 8).storeStringRefTail(string_first).endCell();

// Parameters
let owner = Address.parse(""); // Replace owner with your address

(async () => {

        //create client for testnet sandboxv4 API - alternative endpoint
        const client = new TonClient4({
            endpoint: "https://sandbox-v4.tonhubapi.com",
        });

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
        let contract_dataFormat = NftCollection.fromAddress(address);
        let contract = client.open(contract_dataFormat);
        let item_index = await (await contract.getGetCollectionData()).next_item_index;
        console.log("NFT ItemIndex Next: " + item_index);
        
        let nft_item_address_0 = await contract.getGetNftAddressByIndex(0n);
        let nft_item_0 = client.open(NftItem.fromAddress(nft_item_address_0));
        let staking_address = await nft_item_0.getGetStakingContractAddress();
        
        //// ====== Let's check the staking address in each. ======
        // for (let i = BigInt(0); i <= BigInt(item_index); i++) {
        //     let nft_item_address_1 = await contract.getGetNftAddressByIndex(i);
        //     let nft_item_1 = client.open(NftItem.fromAddress(nft_item_address_1));
        //     let staking_address_1 = await nft_item_1.getGetStakingContractAddress();
        //     console.log("Staking Address_1" + staking_address_1);
        // }

        // Check the NFT Info (weights) in details
        let staking_contract = client.open(StakingContract.fromAddress(staking_address));
        let claimable_qty_0 = await staking_contract.getClaimable(0n);
        let claimable_qty_1  = await staking_contract.getClaimable(1n);
        console.log("Claimable0: " + claimable_qty_0 + " | Claimable1: " + claimable_qty_1);

        let totalWeight = await staking_contract.getStakeData();
        console.log("Total Weight: " + totalWeight.totalWeight);

        for (let i = BigInt(0); i <= BigInt(2); i++) {
            let list_0 = await staking_contract.getGetUserList(i);
            console.log(list_0.sender, list_0.weight, list_0.unlock_time);
        }
})();