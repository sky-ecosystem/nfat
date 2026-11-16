// NFATFacility.spec — Certora formal verification specification

using GemMock as gem;
using IdentityNetworkMock as identityNetwork;

methods {
    function wards(address)                     external returns (uint256) envfree;
    function buds(address)                      external returns (uint256) envfree;
    function cops(address)                      external returns (uint256) envfree;
    function deposits(address)                  external returns (uint256) envfree;
    function collectable(uint256)               external returns (uint256) envfree;
    function recipient()                        external returns (address) envfree;
    function identityNetwork()                  external returns (address) envfree;
    function stopped()                          external returns (bool)    envfree;
    function baseURI()                          external returns (string)  envfree;
    function balanceOf(address)                 external returns (uint256) envfree;
    function ownerOf(uint256)                   external returns (address) envfree;
    function getApproved(uint256)               external returns (address) envfree;
    function isApprovedForAll(address, address) external returns (bool)    envfree;
    //
    function gem.totalSupply()                  external returns (uint256) envfree;
    function gem.balanceOf(address)             external returns (uint256) envfree;
    function gem.allowance(address, address)    external returns (uint256) envfree;
    function identityNetwork.isMember(address)  external returns (bool)    envfree;
    //
    function _.isMember(address) external => DISPATCHER(true);
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.onERC721Received(address, address, uint256, bytes) external => onERC721ReceivedSummary() expect (bytes4);
}

definition RECIPIENT_KEY()        returns bytes32 = to_bytes32(0x726563697069656e740000000000000000000000000000000000000000000000);
definition IDENTITY_NETWORK_KEY() returns bytes32 = to_bytes32(0x6964656e746974794e6574776f726b0000000000000000000000000000000000);
definition BASE_URI_KEY()         returns bytes32 = to_bytes32(0x6261736555524900000000000000000000000000000000000000000000000000);

persistent ghost bytes4 onERC721ReceivedRetVal;
function onERC721ReceivedSummary() returns (bytes4) {
    return onERC721ReceivedRetVal;
}

ghost mathint sumDeposits {
    init_state axiom sumDeposits == 0;
}

ghost mathint sumCollectable {
    init_state axiom sumCollectable == 0;
}

hook Sstore deposits[KEY address usr] uint256 newVal (uint256 oldVal) {
    sumDeposits = sumDeposits + newVal - oldVal;
    require sumDeposits >= 0;
}

hook Sload uint256 val deposits[KEY address usr] {
    require sumDeposits >= val;
}

hook Sstore collectable[KEY uint256 tokenId] uint256 newVal (uint256 oldVal) {
    sumCollectable = sumCollectable + newVal - oldVal;
    require sumCollectable >= 0;
}

hook Sload uint256 val collectable[KEY uint256 tokenId] {
    require sumCollectable >= val;
}

invariant wardsIsBinary(address usr)
    wards(usr) == 0 || wards(usr) == 1;

invariant budsIsBinary(address usr)
    buds(usr) == 0 || buds(usr) == 1;

invariant copsIsBinary(address usr)
    cops(usr) == 0 || cops(usr) == 1;

// Solvency invariant preserved by non-rescue functions
rule gemBalanceCoversObligations(method f)
    filtered {
        f -> !f.isView &&
             f.selector != sig:rescue(address,address,uint256).selector
    }
{
    env e;
    calldataarg args;

    require e.msg.sender != currentContract;

    require gem.balanceOf(currentContract) >= sumDeposits + sumCollectable;

    f(e, args);

    assert gem.balanceOf(currentContract) >= sumDeposits + sumCollectable, "Assert 1";
}

// approved/approvedForAll users cannot collect
rule collectIsOwnerOnly(uint256 tokenId, uint256 amount) {
    env e;

    address owner = currentContract._owners[tokenId];
    require owner != 0;
    require e.msg.sender != owner;

    collect@withrevert(e, tokenId, amount);

    // Must revert if caller is not the owner, regardless of approval status
    assert lastReverted, "Assert 1";
}

// depositors can always exit
rule withdrawWorksWhenStopped(uint256 amount) {
    env e;

    require e.msg.value == 0;
    require stopped() == true;
    require amount > 0;
    require deposits(e.msg.sender) >= amount;

    // Ensure gem has sufficient balance and the contract is not the sender
    require gem.balanceOf(currentContract) >= amount;
    require gem.totalSupply() >= gem.balanceOf(currentContract) + gem.balanceOf(e.msg.sender);
    require e.msg.sender != currentContract;

    withdraw@withrevert(e, amount);

    assert !lastReverted, "Assert 1";
}

// ERC721 transfer preserves financial state
rule transferDoesNotAffectFunds(address from, address to, uint256 tokenId) {
    env e;

    mathint depositsFrom       = deposits(from);
    mathint depositsTo         = deposits(to);
    mathint collectableTokenId = collectable(tokenId);

    transferFrom(e, from, to, tokenId);

    assert deposits(from)       == depositsFrom, "Assert 1";
    assert deposits(to)         == depositsTo, "Assert 2";
    assert collectable(tokenId) == collectableTokenId, "Assert 3";
}

rule storageAffected(method f) {
    env e;

    address anyAddr;
    address anyAddr2;
    uint256 anyUint256;

    mathint wardsBefore            = wards(anyAddr);
    mathint budsBefore             = buds(anyAddr);
    mathint copsBefore             = cops(anyAddr);
    mathint depositsBefore         = deposits(anyAddr);
    mathint collectableBefore      = collectable(anyUint256);
    address recipientBefore        = recipient();
    address identityNetworkBefore  = identityNetwork();
    bool    stoppedBefore          = stopped();
    mathint balanceOfBefore        = balanceOf(anyAddr);
    address ownerOfBefore          = currentContract._owners[anyUint256];
    address tokenApprovalBefore    = getApproved(anyUint256);
    bool    operatorApprovalBefore = isApprovedForAll(anyAddr, anyAddr2);

    calldataarg args;
    f(e, args);

    mathint wardsAfter            = wards(anyAddr);
    mathint budsAfter             = buds(anyAddr);
    mathint copsAfter             = cops(anyAddr);
    mathint depositsAfter         = deposits(anyAddr);
    mathint collectableAfter      = collectable(anyUint256);
    address recipientAfter        = recipient();
    address identityNetworkAfter  = identityNetwork();
    bool    stoppedAfter          = stopped();
    mathint balanceOfAfter        = balanceOf(anyAddr);
    address ownerOfAfter          = currentContract._owners[anyUint256];
    address tokenApprovalAfter    = getApproved(anyUint256);
    bool    operatorApprovalAfter = isApprovedForAll(anyAddr, anyAddr2);

    assert wardsAfter != wardsBefore =>
        f.selector == sig:rely(address).selector ||
        f.selector == sig:deny(address).selector, "Assert 1";
    assert budsAfter != budsBefore =>
        f.selector == sig:kiss(address).selector ||
        f.selector == sig:diss(address).selector, "Assert 2";
    assert copsAfter != copsBefore =>
        f.selector == sig:addFreezer(address).selector ||
        f.selector == sig:removeFreezer(address).selector, "Assert 3";
    assert depositsAfter != depositsBefore =>
        f.selector == sig:subscribe(uint256,bytes).selector ||
        f.selector == sig:withdraw(uint256).selector ||
        f.selector == sig:issue(address,uint256,uint256).selector ||
        f.selector == sig:rescueDeposit(address,address,uint256).selector, "Assert 4";
    assert collectableAfter != collectableBefore =>
        f.selector == sig:repay(uint256,uint256).selector ||
        f.selector == sig:collect(uint256,uint256).selector ||
        f.selector == sig:rescueCollectable(uint256,address,uint256).selector, "Assert 5";
    assert recipientAfter != recipientBefore =>
        f.selector == sig:file(bytes32,address).selector, "Assert 6";
    assert identityNetworkAfter != identityNetworkBefore =>
        f.selector == sig:file(bytes32,address).selector, "Assert 7";
    assert stoppedAfter != stoppedBefore =>
        f.selector == sig:stop().selector ||
        f.selector == sig:start().selector, "Assert 8";
    assert balanceOfAfter != balanceOfBefore =>
        f.selector == sig:issue(address,uint256,uint256).selector ||
        f.selector == sig:transferFrom(address,address,uint256).selector ||
        f.selector == sig:safeTransferFrom(address,address,uint256).selector ||
        f.selector == sig:safeTransferFrom(address,address,uint256,bytes).selector, "Assert 9";
    assert ownerOfAfter != ownerOfBefore =>
        f.selector == sig:issue(address,uint256,uint256).selector ||
        f.selector == sig:transferFrom(address,address,uint256).selector ||
        f.selector == sig:safeTransferFrom(address,address,uint256).selector ||
        f.selector == sig:safeTransferFrom(address,address,uint256,bytes).selector, "Assert 10";
    assert tokenApprovalAfter != tokenApprovalBefore =>
        f.selector == sig:approve(address,uint256).selector ||
        f.selector == sig:issue(address,uint256,uint256).selector ||
        f.selector == sig:transferFrom(address,address,uint256).selector ||
        f.selector == sig:safeTransferFrom(address,address,uint256).selector ||
        f.selector == sig:safeTransferFrom(address,address,uint256,bytes).selector, "Assert 11";
    assert operatorApprovalAfter != operatorApprovalBefore =>
        f.selector == sig:setApprovalForAll(address,bool).selector, "Assert 12";
}

rule rely(address usr) {
    env e;

    rely(e, usr);

    assert wards(usr) == 1, "Assert 1";
}

rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

rule deny(address usr) {
    env e;

    deny(e, usr);

    assert wards(usr) == 0, "Assert 1";
}

rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

rule kiss(address usr) {
    env e;

    kiss(e, usr);

    assert buds(usr) == 1, "Assert 1";
}

rule kiss_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    kiss@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

rule diss(address usr) {
    env e;

    diss(e, usr);

    assert buds(usr) == 0, "Assert 1";
}

rule diss_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    diss@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

rule addFreezer(address usr) {
    env e;

    addFreezer(e, usr);

    assert cops(usr) == 1, "Assert 1";
}

rule addFreezer_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    addFreezer@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

rule removeFreezer(address usr) {
    env e;

    removeFreezer(e, usr);

    assert cops(usr) == 0, "Assert 1";
}

rule removeFreezer_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    removeFreezer@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

rule stop() {
    env e;

    stop(e);

    assert stopped(), "Assert 1";
}

rule stop_revert() {
    env e;

    mathint copsSender = cops(e.msg.sender);

    stop@withrevert(e);

    bool revert1 = e.msg.value > 0;
    bool revert2 = copsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

rule start() {
    env e;

    start(e);

    assert !stopped(), "Assert 1";
}

rule start_revert() {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    start@withrevert(e);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

rule file_address(bytes32 what, address data) {
    env e;

    address recipientBefore = recipient();
    address identityNetworkBefore = identityNetwork();

    file(e, what, data);

    assert what == RECIPIENT_KEY()        => recipient() == data, "Assert 1";
    assert what != RECIPIENT_KEY()        => recipient() == recipientBefore, "Assert 2";
    assert what == IDENTITY_NETWORK_KEY() => identityNetwork() == data, "Assert 3";
    assert what != IDENTITY_NETWORK_KEY() => identityNetwork() == identityNetworkBefore, "Assert 4";
}

rule file_address_revert(bytes32 what, address data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != RECIPIENT_KEY() && what != IDENTITY_NETWORK_KEY();

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

rule file_string(bytes32 what, string data) {
    env e;

    file(e, what, data);

    assert baseURI() == data, "Assert 1";
}

rule file_string_revert(bytes32 what, string data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    baseURI(); // avoid exiting malformed string revert path
    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != BASE_URI_KEY();

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

rule rescue(address token, address to, uint256 amount) {
    env e;

    address anyUsr;
    uint256 anyTokenId;
    mathint depositsAnyBefore    = deposits(anyUsr);
    mathint collectableAnyBefore = collectable(anyTokenId);

    require token == gem;
    mathint gemBalanceOfToBefore       = gem.balanceOf(to);
    mathint gemBalanceOfContractBefore = gem.balanceOf(currentContract);

    rescue(e, token, to, amount);

    assert deposits(anyUsr)        == depositsAnyBefore, "Assert 1";
    assert collectable(anyTokenId) == collectableAnyBefore, "Assert 2";
    assert to != currentContract => gem.balanceOf(to) == gemBalanceOfToBefore + amount, "Assert 3";
    assert to != currentContract => gem.balanceOf(currentContract) == gemBalanceOfContractBefore - amount, "Assert 4";
}

rule rescue_revert(address token, address to, uint256 amount) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    require token == gem;
    require gem.balanceOf(currentContract) >= amount;
    require gem.balanceOf(to) + amount <= max_uint256;

    rescue@withrevert(e, token, to, amount);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

rule rescueDeposit(address depositor, address to, uint256 amount) {
    env e;

    address otherUsr;
    require otherUsr != depositor;

    mathint depositsDepositorBefore    = deposits(depositor);
    mathint depositsOtherBefore        = deposits(otherUsr);
    mathint gemBalanceOfToBefore       = gem.balanceOf(to);
    mathint gemBalanceOfContractBefore = gem.balanceOf(currentContract);

    rescueDeposit(e, depositor, to, amount);

    assert deposits(depositor) == depositsDepositorBefore - amount, "Assert 1";
    assert deposits(otherUsr) == depositsOtherBefore, "Assert 2";
    assert to != currentContract => gem.balanceOf(to) == gemBalanceOfToBefore + amount, "Assert 3";
    assert to != currentContract => gem.balanceOf(currentContract) == gemBalanceOfContractBefore - amount, "Assert 4";
}

rule rescueDeposit_revert(address depositor, address to, uint256 amount) {
    env e;

    mathint wardsSender = wards(e.msg.sender);
    uint256 depositsDepositor  = deposits(depositor);

    require gem.balanceOf(currentContract) >= amount;
    require gem.balanceOf(to) + amount <= max_uint256;

    rescueDeposit@withrevert(e, depositor, to, amount);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = depositsDepositor < amount;

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

rule rescueCollectable(uint256 tokenId, address to, uint256 amount) {
    env e;

    uint256 otherTokenId;
    require otherTokenId != tokenId;

    mathint collectableTokenIdBefore   = collectable(tokenId);
    mathint collectableOtherBefore     = collectable(otherTokenId);
    mathint gemBalanceOfToBefore       = gem.balanceOf(to);
    mathint gemBalanceOfContractBefore = gem.balanceOf(currentContract);

    rescueCollectable(e, tokenId, to, amount);

    assert collectable(tokenId) == collectableTokenIdBefore - amount, "Assert 1";
    assert collectable(otherTokenId) == collectableOtherBefore, "Assert 2";
    assert to != currentContract => gem.balanceOf(to) == gemBalanceOfToBefore + amount, "Assert 3";
    assert to != currentContract => gem.balanceOf(currentContract) == gemBalanceOfContractBefore - amount, "Assert 4";
}

rule rescueCollectable_revert(uint256 tokenId, address to, uint256 amount) {
    env e;

    mathint wardsSender = wards(e.msg.sender);
    mathint collectableTokenId  = collectable(tokenId);

    require gem.balanceOf(currentContract) >= amount;
    require gem.balanceOf(to) + amount <= max_uint256;

    rescueCollectable@withrevert(e, tokenId, to, amount);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = collectableTokenId < amount;

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

rule subscribe(uint256 amount, bytes data) {
    env e;

    require e.msg.sender != currentContract;

    mathint depositsSenderBefore       = deposits(e.msg.sender);
    mathint gemBalanceOfSenderBefore   = gem.balanceOf(e.msg.sender);
    mathint gemBalanceOfContractBefore = gem.balanceOf(currentContract);

    subscribe(e, amount, data);

    assert deposits(e.msg.sender) == depositsSenderBefore + amount, "Assert 1";
    assert gem.balanceOf(e.msg.sender) == gemBalanceOfSenderBefore - amount, "Assert 2";
    assert gem.balanceOf(currentContract) == gemBalanceOfContractBefore + amount, "Assert 3";
}

rule subscribe_revert(uint256 amount, bytes data) {
    env e;

    bool stopped = stopped();

    require gem.balanceOf(e.msg.sender) >= amount;
    require gem.allowance(e.msg.sender, currentContract) >= amount;
    require gem.balanceOf(currentContract) + amount <= max_uint256;

    mathint depositsSender = deposits(e.msg.sender);

    subscribe@withrevert(e, amount, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = stopped;
    bool revert3 = depositsSender + amount > max_uint256;

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

rule withdraw(uint256 amount) {
    env e;

    require e.msg.sender != currentContract;

    mathint depositsSenderBefore       = deposits(e.msg.sender);
    mathint gemBalanceOfSenderBefore   = gem.balanceOf(e.msg.sender);
    mathint gemBalanceOfContractBefore = gem.balanceOf(currentContract);

    withdraw(e, amount);

    assert deposits(e.msg.sender) == depositsSenderBefore - amount, "Assert 1";
    assert gem.balanceOf(e.msg.sender) == gemBalanceOfSenderBefore + amount, "Assert 2";
    assert gem.balanceOf(currentContract) == gemBalanceOfContractBefore - amount, "Assert 3";
}

rule withdraw_revert(uint256 amount) {
    env e;

    mathint depositsSender = deposits(e.msg.sender);

    require gem.balanceOf(currentContract) >= amount;
    require gem.balanceOf(e.msg.sender) + amount <= max_uint256;

    withdraw@withrevert(e, amount);

    bool revert1 = e.msg.value > 0;
    bool revert2 = amount == 0;
    bool revert3 = depositsSender < amount;

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

rule issue(address to, uint256 tokenId, uint256 amount) {
    env e;

    mathint depositsToBefore            = deposits(to);
    address recipient                   = recipient();
    mathint gemBalanceOfRecipientBefore = gem.balanceOf(recipient);
    mathint gemBalanceOfContractBefore  = gem.balanceOf(currentContract);

    require recipient != currentContract;

    issue(e, to, tokenId, amount);

    assert deposits(to) == depositsToBefore - amount, "Assert 1";
    assert currentContract._owners[tokenId] == to, "Assert 2";
    assert gem.balanceOf(recipient) == gemBalanceOfRecipientBefore + amount, "Assert 3";
    assert gem.balanceOf(currentContract) == gemBalanceOfContractBefore - amount, "Assert 4";
}

rule issue_revert(address to, uint256 tokenId, uint256 amount) {
    env e;

    require identityNetwork() == identityNetwork;

    uint256 budsSender = buds(e.msg.sender);
    bool    stopped    = stopped();
    uint256 depositsTo = deposits(to);
    address owner      = currentContract._owners[tokenId];
    bool    isMemberTo = identityNetwork.isMember(to);

    require gem.balanceOf(currentContract) >= amount;
    require gem.balanceOf(recipient()) + amount <= max_uint256;
    require balanceOf(to) + 1 <= max_uint256;

    issue@withrevert(e, to, tokenId, amount);

    bool revert1 = e.msg.value > 0;
    bool revert2 = budsSender != 1;
    bool revert3 = stopped;
    bool revert4 = tokenId == 0;
    bool revert5 = depositsTo < amount;
    bool revert6 = owner != 0;
    bool revert7 = to == 0;
    bool revert8 = identityNetwork != 0 && !isMemberTo;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5 || revert6 ||
                            revert7 || revert8, "Revert rules failed";
}

rule repay(uint256 tokenId, uint256 amount) {
    env e;

    require e.msg.sender != currentContract;

    mathint collectableTokenIdBefore   = collectable(tokenId);
    mathint gemBalanceOfSenderBefore   = gem.balanceOf(e.msg.sender);
    mathint gemBalanceOfContractBefore = gem.balanceOf(currentContract);

    repay(e, tokenId, amount);

    assert collectable(tokenId) == collectableTokenIdBefore + amount, "Assert 1";
    assert gem.balanceOf(e.msg.sender) == gemBalanceOfSenderBefore - amount, "Assert 2";
    assert gem.balanceOf(currentContract) == gemBalanceOfContractBefore + amount, "Assert 3";
}

rule repay_revert(uint256 tokenId, uint256 amount) {
    env e;

    bool    stopped            = stopped();
    address owner              = currentContract._owners[tokenId];
    mathint collectableTokenId = collectable(tokenId);

    require gem.balanceOf(e.msg.sender) >= amount;
    require gem.allowance(e.msg.sender, currentContract) >= amount;
    require gem.balanceOf(currentContract) + amount <= max_uint256;

    repay@withrevert(e, tokenId, amount);

    bool revert1 = e.msg.value > 0;
    bool revert2 = stopped;
    bool revert3 = amount == 0;
    bool revert4 = owner == 0;
    bool revert5 = collectableTokenId + amount > max_uint256;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5, "Revert rules failed";
}

rule collect(uint256 tokenId, uint256 amount) {
    env e;

    require e.msg.sender != currentContract;

    mathint collectableTokenIdBefore = collectable(tokenId);
    mathint gemBalanceOfSenderBefore   = gem.balanceOf(e.msg.sender);
    mathint gemBalanceOfContractBefore = gem.balanceOf(currentContract);

    collect(e, tokenId, amount);

    assert collectable(tokenId) == collectableTokenIdBefore - amount, "Assert 1";
    assert gem.balanceOf(e.msg.sender) == gemBalanceOfSenderBefore + amount, "Assert 2";
    assert gem.balanceOf(currentContract) == gemBalanceOfContractBefore - amount, "Assert 3";
}

rule collect_revert(uint256 tokenId, uint256 amount) {
    env e;

    require identityNetwork() == identityNetwork;

    bool    stopped            = stopped();
    mathint collectableTokenId = collectable(tokenId);
    address owner              = currentContract._owners[tokenId];
    bool    isMemberSender     = identityNetwork.isMember(e.msg.sender);

    require gem.balanceOf(currentContract) >= amount;
    require gem.balanceOf(e.msg.sender) + amount <= max_uint256;

    collect@withrevert(e, tokenId, amount);

    bool revert1 = e.msg.value > 0;
    bool revert2 = stopped;
    bool revert3 = amount == 0;
    bool revert4 = collectableTokenId < amount;
    bool revert5 = e.msg.sender != owner;
    bool revert6 = identityNetwork != 0 && !isMemberSender;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5 || revert6, "Revert rules failed";
}

rule transferFrom(address from, address to, uint256 tokenId) {
    env e;

    address other;
    require other != from && other != to;
    uint256 otherTokenId;
    require otherTokenId != tokenId;

    mathint balanceOfFromBefore  = balanceOf(from);
    mathint balanceOfToBefore    = balanceOf(to);
    mathint balanceOfOtherBefore = balanceOf(other);
    address ownerOfOtherBefore   = currentContract._owners[otherTokenId];
    address approvalOtherBefore  = getApproved(otherTokenId);

    require balanceOfFromBefore >= 1;
    require from != to => balanceOfToBefore <= max_uint256 - 1;

    transferFrom(e, from, to, tokenId);

    mathint balanceOfFromAfter   = balanceOf(from);
    mathint balanceOfToAfter     = balanceOf(to);
    mathint balanceOfOtherAfter  = balanceOf(other);
    address ownerOfTokenIdAfter  = currentContract._owners[tokenId];
    address ownerOfOtherAfter    = currentContract._owners[otherTokenId];
    address approvalTokenIdAfter = getApproved(tokenId);
    address approvalOtherAfter   = getApproved(otherTokenId);

    assert from != to => balanceOfFromAfter == balanceOfFromBefore - 1, "Assert 1";
    assert from != to => balanceOfToAfter == balanceOfToBefore + 1, "Assert 2";
    assert from == to => balanceOfFromAfter == balanceOfFromBefore, "Assert 3";
    assert balanceOfOtherAfter == balanceOfOtherBefore, "Assert 4";
    assert ownerOfTokenIdAfter == to, "Assert 5";
    assert ownerOfOtherAfter == ownerOfOtherBefore, "Assert 6";
    assert approvalTokenIdAfter == 0, "Assert 7";
    assert approvalOtherAfter == approvalOtherBefore, "Assert 8";
}

rule transferFrom_revert(address from, address to, uint256 tokenId) {
    env e;

    require e.msg.sender != 0;
    require identityNetwork() == identityNetwork;

    address owner      = currentContract._owners[tokenId];
    address approved   = getApproved(tokenId);
    bool    isOperator = isApprovedForAll(owner, e.msg.sender);
    bool    isMemberTo = identityNetwork.isMember(to);

    require balanceOf(to) + 1 <= max_uint256;

    transferFrom@withrevert(e, from, to, tokenId);

    bool revert1 = e.msg.value > 0;
    bool revert2 = owner == 0;
    bool revert3 = owner != from;
    bool revert4 = to == 0;
    bool revert5 = e.msg.sender != owner && e.msg.sender != approved && !isOperator;
    bool revert6 = identityNetwork != 0 && !isMemberTo;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5 || revert6, "Revert rules failed";
}

rule safeTransferFrom(address from, address to, uint256 tokenId) {
    env e;

    address other;
    require other != from && other != to;
    uint256 otherTokenId;
    require otherTokenId != tokenId;

    mathint balanceOfFromBefore  = balanceOf(from);
    mathint balanceOfToBefore    = balanceOf(to);
    mathint balanceOfOtherBefore = balanceOf(other);
    address ownerOfOtherBefore   = currentContract._owners[otherTokenId];
    address approvalOtherBefore  = getApproved(otherTokenId);

    require balanceOfFromBefore >= 1;
    require from != to => balanceOfToBefore <= max_uint256 - 1;

    safeTransferFrom(e, from, to, tokenId);

    mathint balanceOfFromAfter   = balanceOf(from);
    mathint balanceOfToAfter     = balanceOf(to);
    mathint balanceOfOtherAfter  = balanceOf(other);
    address ownerOfTokenIdAfter  = currentContract._owners[tokenId];
    address ownerOfOtherAfter    = currentContract._owners[otherTokenId];
    address approvalTokenIdAfter = getApproved(tokenId);
    address approvalOtherAfter   = getApproved(otherTokenId);

    assert from != to => balanceOfFromAfter == balanceOfFromBefore - 1, "Assert 1";
    assert from != to => balanceOfToAfter == balanceOfToBefore + 1, "Assert 2";
    assert from == to => balanceOfFromAfter == balanceOfFromBefore, "Assert 3";
    assert balanceOfOtherAfter == balanceOfOtherBefore, "Assert 4";
    assert ownerOfTokenIdAfter == to, "Assert 5";
    assert ownerOfOtherAfter == ownerOfOtherBefore, "Assert 6";
    assert approvalTokenIdAfter == 0, "Assert 7";
    assert approvalOtherAfter == approvalOtherBefore, "Assert 8";
}

persistent ghost address to_;
persistent ghost uint256 toCodesize;
hook EXTCODESIZE(address addr) uint256 size {
    if (addr == to_) {
        toCodesize = size;
    }
}

rule safeTransferFrom_revert(address from, address to, uint256 tokenId) {
    env e;

    require e.msg.sender != 0;
    require identityNetwork() == identityNetwork;

    address owner      = currentContract._owners[tokenId];
    address approved   = getApproved(tokenId);
    bool    isOperator = isApprovedForAll(owner, e.msg.sender);
    bool    isMemberTo = identityNetwork.isMember(to);

    to_ = to;

    safeTransferFrom@withrevert(e, from, to, tokenId);

    bool revert1 = e.msg.value > 0;
    bool revert2 = owner == 0;
    bool revert3 = owner != from;
    bool revert4 = to == 0;
    bool revert5 = e.msg.sender != owner && e.msg.sender != approved && !isOperator;
    bool revert6 = identityNetwork != 0 && !isMemberTo;
    bool revert7 = toCodesize > 0 && onERC721ReceivedRetVal != to_bytes4(0x150b7a02);

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5 || revert6 ||
                            revert7, "Revert rules failed";
}

rule safeTransferFromWithData(address from, address to, uint256 tokenId, bytes data) {
    env e;

    address other;
    require other != from && other != to;
    uint256 otherTokenId;
    require otherTokenId != tokenId;

    mathint balanceOfFromBefore  = balanceOf(from);
    mathint balanceOfToBefore    = balanceOf(to);
    mathint balanceOfOtherBefore = balanceOf(other);
    address ownerOfOtherBefore   = currentContract._owners[otherTokenId];
    address approvalOtherBefore  = getApproved(otherTokenId);

    require balanceOfFromBefore >= 1;
    require from != to => balanceOfToBefore <= max_uint256 - 1;

    safeTransferFrom(e, from, to, tokenId, data);

    mathint balanceOfFromAfter   = balanceOf(from);
    mathint balanceOfToAfter     = balanceOf(to);
    mathint balanceOfOtherAfter  = balanceOf(other);
    address ownerOfTokenIdAfter  = currentContract._owners[tokenId];
    address ownerOfOtherAfter    = currentContract._owners[otherTokenId];
    address approvalTokenIdAfter = getApproved(tokenId);
    address approvalOtherAfter   = getApproved(otherTokenId);

    assert from != to => balanceOfFromAfter == balanceOfFromBefore - 1, "Assert 1";
    assert from != to => balanceOfToAfter == balanceOfToBefore + 1, "Assert 2";
    assert from == to => balanceOfFromAfter == balanceOfFromBefore, "Assert 3";
    assert balanceOfOtherAfter == balanceOfOtherBefore, "Assert 4";
    assert ownerOfTokenIdAfter == to, "Assert 5";
    assert ownerOfOtherAfter == ownerOfOtherBefore, "Assert 6";
    assert approvalTokenIdAfter == 0, "Assert 7";
    assert approvalOtherAfter == approvalOtherBefore, "Assert 8";
}

rule safeTransferFromWithData_revert(address from, address to, uint256 tokenId, bytes data) {
    env e;

    require e.msg.sender != 0;
    require identityNetwork() == identityNetwork;

    address owner    = currentContract._owners[tokenId];
    address approved = getApproved(tokenId);
    bool    isOperator = isApprovedForAll(owner, e.msg.sender);
    bool    isMemberTo = identityNetwork.isMember(to);

    to_ = to;

    safeTransferFrom@withrevert(e, from, to, tokenId, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = owner == 0;
    bool revert3 = owner != from;
    bool revert4 = to == 0;
    bool revert5 = e.msg.sender != owner && e.msg.sender != approved && !isOperator;
    bool revert6 = identityNetwork != 0 && !isMemberTo;
    bool revert7 = toCodesize > 0 && onERC721ReceivedRetVal != to_bytes4(0x150b7a02);

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5 || revert6 ||
                            revert7, "Revert rules failed";
}

rule approve(address to, uint256 tokenId) {
    env e;

    uint256 otherTokenId;
    require otherTokenId != tokenId;

    address approvalOtherBefore = getApproved(otherTokenId);

    approve(e, to, tokenId);

    address approvalTokenIdAfter = getApproved(tokenId);
    address approvalOtherAfter   = getApproved(otherTokenId);

    assert approvalTokenIdAfter == to, "Assert 1";
    assert approvalOtherAfter == approvalOtherBefore, "Assert 2";
}

rule approve_revert(address to, uint256 tokenId) {
    env e;

    require e.msg.sender != 0;

    address owner      = currentContract._owners[tokenId];
    bool    isOperator = isApprovedForAll(owner, e.msg.sender);

    approve@withrevert(e, to, tokenId);

    bool revert1 = e.msg.value > 0;
    bool revert2 = owner == 0;
    bool revert3 = e.msg.sender != owner && !isOperator;

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

rule setApprovalForAll(address operator, bool approved) {
    env e;

    address otherOwner; address otherOperator;
    require otherOwner != e.msg.sender || otherOperator != operator;

    bool approvalOtherBefore = isApprovedForAll(otherOwner, otherOperator);

    setApprovalForAll(e, operator, approved);

    bool approvalOperatorAfter = isApprovedForAll(e.msg.sender, operator);
    bool approvalOtherAfter    = isApprovedForAll(otherOwner, otherOperator);

    assert approvalOperatorAfter == approved, "Assert 1";
    assert approvalOtherAfter == approvalOtherBefore, "Assert 2";
}

rule setApprovalForAll_revert(address operator, bool approved) {
    env e;

    setApprovalForAll@withrevert(e, operator, approved);

    bool revert1 = e.msg.value > 0;
    bool revert2 = operator == 0;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}
