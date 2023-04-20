
struct CollectionData {
    next_item_index: Int;
    collection_content: Cell;
    owner_address: Address;
}
struct RoyaltyParams {
    numerator: Int;
    denominator: Int;
    destination: Address;
}

message(0x693d3950) GetRoyaltyParams {
    query_id: Int as uint64;
}

message(0xa8cb00ad) ReportRoyaltyParams {
    query_id: Int as uint64;
    numerator:  Int as uint16;
    denominator: Int as uint16;
    destination: Address;
}

message Stake {
    duration: Int as uint256;
}

contract NftCollection {
    const minTonsForStorage: Int = ton("0.03");
    const gasConsumption: Int = ton("0.03");
    next_item_index: Int as uint32 = 0;
    owner_address: Address;
    royalty_params: RoyaltyParams;                      
    collection_content: Cell;   

    init(owner_address: Address, collection_content: Cell, royalty_params: RoyaltyParams){
        self.owner_address = owner_address;
        self.collection_content = collection_content; 
        self.royalty_params = royalty_params;
    }

    receive("Mint"){
        let ctx: Context = context(); // get sender Info
        let msgValue: Int = ctx.value;
        let tonBalanceBeforeMsg: Int = myBalance() - msgValue;
        let storageFee: Int = self.minTonsForStorage - min(tonBalanceBeforeMsg, self.minTonsForStorage);
        msgValue = msgValue - (storageFee + self.gasConsumption);

        self.mint(ctx.sender, msgValue);
    }
    // ===== Private Methods ===== //
    fun mint(sender: Address, msgValue: Int) {
        // TODO: if (is_initialized == false) { // next_item_index == -1 }
        require(self.next_item_index >= 0, "non-sequential NFTs");

        let nft_init: StateInit = self.getNftItemInit(self.next_item_index);
        send(SendParameters{
                to: contractAddress(nft_init), 
                value: msgValue, 
                bounce: false,
                mode: SendIgnoreErrors,
                body: Transfer{
                    query_id: 0,
                    new_owner: sender,
                    response_destination: self.owner_address,
                    custom_payload: emptyCell(),
                    forward_amount: 0,
                    forward_payload: emptySlice()
                }.toCell(),
                code: nft_init.code,
                data: nft_init.data
            });
        self.next_item_index = self.next_item_index + 1;
    }

    receive(msg: GetRoyaltyParams) {    // TODO: Test Royalties Fee
        send(SendParameters{
                to: myAddress(),
                value: 0,
                mode: 64, 
                bounce: false,
                body: ReportRoyaltyParams {
                    query_id: msg.query_id,
                    numerator:  self.royalty_params.numerator,
                    denominator: self.royalty_params.denominator,
                    destination: self.owner_address
                }.toCell()
        });        
    }


    // ------------------ Get Function  ------------------ //
    get fun get_collection_data(): CollectionData{     
        let b: StringBuilder = beginString();
        let collectionDataString: String = self.collection_content.asSlice().asString();
        b.append(collectionDataString);
        b.append("meta.json"); // You can changed this your self.

        return CollectionData{
            next_item_index: self.next_item_index, 
            collection_content: b.toCell(), 
            owner_address: self.owner_address
        };
    }

    get fun get_nft_address_by_index(item_index: Int): Address{      
        let initCode: StateInit = self.getNftItemInit(item_index);
        return contractAddress(initCode);
    }

    get fun getNftItemInit(item_index: Int): StateInit {
        return initOf NftItem(myAddress(), item_index, self.owner_address, self.collection_content);
    }
    
    get fun get_nft_content(index: Int, individual_content: Cell): Cell { 
        let b: StringBuilder = beginString();
        let ic: String = individual_content.asSlice().asString();
        b.append(ic);
        return b.toCell();
    }

    get fun royalty_params(): RoyaltyParams {
        return self.royalty_params;
    }
}

// ---------------------------------------------------------------------------------------------------- //

contract NftItem {
    const minTonsForStorage: Int = ton("0.05");
    const gasConsumption: Int = ton("0.05");

    collection_address: Address;
    item_index: Int; 
    owner: Address;
    individual_content: Cell;
    is_initialized: Bool;

    level: Int as uint16 = 0;
    is_staking: Bool;
    init(
        collection_address: Address, 
        item_index: Int,
        owner: Address, 
        individual_content: Cell
    ){
        self.collection_address = collection_address;
        self.item_index = item_index;
        self.owner = owner;
        self.individual_content = individual_content;
        self.is_initialized = false;
        self.is_staking = false;
    }

    receive(msg: Transfer){
        let ctx: Context = context();
        let msgValue: Int = ctx.value; // Check the gasCost for storage
        let tonBalanceBeforeMsg: Int = myBalance() - msgValue;
        let storageFee: Int = self.minTonsForStorage - min(tonBalanceBeforeMsg, self.minTonsForStorage);
        msgValue = msgValue - (storageFee + self.gasConsumption);

        require(ctx.sender == self.collection_address, "not owner");
        require(!self.is_staking, "in staking");

        if (self.is_initialized == false) {  // Initial Transfer, aka Minting.
            self.is_initialized = true;
            self.owner = msg.new_owner;

            self.level = random(1, 101);
            send(SendParameters{
                to: msg.response_destination,
                value: msgValue,
                mode:  SendIgnoreErrors,
                body: Excesses { //0xd53276db
                        query_id: msg.query_id
                    }.toCell()
                });
        } else {
            if (msg.forward_amount > 0) { //  msg: forward_amount => the amount of nano-tons to be sent to the new owner.
                send(SendParameters{
                    to: msg.new_owner,
                    value: msg.forward_amount,
                    mode: SendIgnoreErrors, 
                    bounce: false,
                    body: OwnershipAssigned{
                        query_id: msg.query_id,
                        prev_owner:  self.owner,
                        forward_payload: msg.forward_payload
                    }.toCell()
                }); 
            }
            msgValue = msgValue - ctx.readForwardFee(); 
            if (msg.response_destination != null) { 
                send(SendParameters{ // 0xd53276db
                    to: msg.response_destination,
                    mode: SendIgnoreErrors,
                    value: msgValue,
                    body: Excesses {
                        query_id: msg.query_id
                    }.toCell()
                });
                self.owner = msg.new_owner; // change current owner to the new_owner
            } 
        }
    }
    
    receive(msg: GetStaticData){ 
        let ctx: Context = context();
        send(SendParameters {
            to: ctx.sender,
            value: 0,
            mode: 64,  // (return msg amount except gas fees) 
            bounce: true,
            body: ReportStaticData{
                query_id: msg.query_id,
                index_id: self.item_index,
                collection: self.owner
            }.toCell()
        });
    }

    receive(msg: Stake) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "not owner");

        if (!self.is_staking) {
            self.is_staking = true;
        }

        let init_code: StateInit = initOf StakingContract(self.collection_address);
        send(SendParameters{
            to: contractAddress(init_code),
            value: 0,
            mode:  SendIgnoreErrors + SendRemainingValue,
            code: init_code.code, 
            data: init_code.data,
            body: StakeNFT {
                sender_nft_item_address: myAddress(),
                nftId: self.item_index,
                duration: msg.duration,
                level: self.level
                }.toCell()
            });
    }

    receive("Claim") {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "not owner");
        send(SendParameters{
            to: self.get_staking_contract_address(),
            value: 0,
            mode:  SendIgnoreErrors + SendRemainingValue,
            body: ClaimNFT {
                nftId: self.item_index
                }.toCell()
            });
    }

    receive(msg: Slice) {
        // DO NOTHING
    }

    get fun get_staking_contract_address(): Address {
        let initCode: StateInit = initOf StakingContract(self.collection_address);
        return contractAddress(initCode);
    }

    get fun get_nft_level(): Int {
        return self.level;
    }

    // --------- Get Function  --------- //
    get fun get_nft_data(): GetNftData {
        let b: StringBuilder = beginString();
        let collectionData: String = self.individual_content.asSlice().asString();
        b.append(collectionData);
        b.append(self.item_index.toString());
        b.append(".json");

        return GetNftData {
            is_initialized: self.is_initialized, 
            index: self.item_index, 
            collection_address: self.collection_address, 
            owner_address: self.owner,
            individual_content: b.toCell(),
            level: self.level
        };
    }
}

// ---------------------------------------------------------------------------------------------------- //
// [Collection Contract] -> Transfer -> OwnershipAssigned -> NFTExcesses
message(0x5fcc3d14) Transfer { 
    query_id: Int as uint64;            
    new_owner: Address; 
    response_destination: Address; 
    custom_payload: Cell?; 
    forward_amount: Int as coins; 
    forward_payload: Slice as remaining; 
}
message(0x05138d91) OwnershipAssigned{
    query_id: Int as uint64;
    prev_owner: Address;
    forward_payload: Slice as remaining; 
}
message(0xd53276db) Excesses {
    query_id: Int as uint64;
}
message(0x2fcb26a2) GetStaticData { 
    query_id: Int as uint64;
}
message(0x8b771735) ReportStaticData{
    query_id: Int as uint64;
    index_id: Int;
    collection: Address;
}
// -------------------------------- Customized Message -------------------------------- //
struct GetNftData { 
    is_initialized: Bool;
    index: Int;
    collection_address: Address; 
    owner_address: Address;
    individual_content: Cell;
    level: Int;
}

// ============================================================ //
message StakeNFT {
    sender_nft_item_address: Address; 
    nftId: Int as uint32; // NFT ID
    duration: Int as uint256;
    level: Int;
}

message ClaimNFT {
    nftId: Int as uint32; // NFT ID
}

struct Info {
    sender: Address;
    weight: Int;
    unlock_time: Int;
}

contract StakingContract {
    totalWeight: Int as uint256 = 0;
    minDuration: Int as uint256 = 86400;
    maxDuration: Int as uint256 = 86400 * 180;

    collection_address: Address;
    stake_records: map<Int, Info>;

    init(_nft: Address) {
        self.collection_address = _nft;    
    }

    receive(msg: StakeNFT) {
        let ctx: Context = context();
        require(ctx.sender == msg.sender_nft_item_address, "Not from NFT Item Address");
        self.stake(msg.nftId, ctx.sender, msg.duration, msg.level);

        send(SendParameters{
            to: ctx.sender,
            value: 0,
            mode: SendRemainingValue + SendIgnoreErrors,
            bounce: false,
            body: "StakeSuccess".asComment()
        });
    }

    fun stake(_nftId: Int, _sender: Address, _duration: Int, _level: Int) {
        require(_duration >= self.minDuration && _duration <= self.maxDuration, "NFTStaking: invalid duration");

        let weight: Int = _level * _duration;
        let unlock_time: Int = now() + _duration;
        let new_info: Info = Info{
            sender: _sender, 
            weight: weight, 
            unlock_time: unlock_time
        };

        self.stake_records.set(_nftId, new_info);
        self.totalWeight = self.totalWeight + weight;
    }

    receive(msg: ClaimNFT) {
        let ctx: Context = context();
        let Info: Info = self.stake_records.get(msg.nftId)!!;
        require(ctx.sender == Info.sender, "Not from NFT Item Address");

        // TODO: CoolDown Time
        self.claim(msg.nftId);
    }

    fun claim(_nftId: Int) {
        let token: Int = myBalance() * self.claimable(_nftId) / pow(10, 9);
        let temp: Info = self.stake_records.get(_nftId)!!;

        send(SendParameters{
            to: temp.sender,
            value: token,
            mode:  SendIgnoreErrors
        });
    }

    get fun claimable(nft_id: Int): Int {
        let temp_info: Info = self.stake_records.get(nft_id)!!;
        let ratio: Int = pow(10, 9) * temp_info.weight / self.totalWeight; // TODO
        return ratio;
    }

    get fun stake_data(): StakeData {
        return StakeData {
            totalWeight: self.totalWeight
        };
    }

    get fun get_user_list(_nftID: Int): Info {
        return self.stake_records.get(_nftID)!!;
    }
    
    receive(){
        // DONOTHING
    }
}

struct StakeData {
    totalWeight: Int;
}