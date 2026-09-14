// SPDX-FileCopyrightText: © 2026 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.24;

interface GemLike {
    function transferFrom(address from, address to, uint256 amount) external;
    function transfer(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external;
}

interface FacilityLike {
    function gem() external view returns (address);
    function repay(uint256 tokenId, uint256 amount) external;
}

// One escrow per NFAT facility. Holds the pre-minted payout for each NFAT until its term
// elapses, after which anyone may release it into the facility for the holder to collect.
contract TEJRCEscrow {

    mapping(address usr     => uint256 allowed) public wards;
    mapping(address usr     => uint256 allowed) public buds;    // Operator(s)
    mapping(uint256 tokenId => uint256 amount)  public balances;
    mapping(uint256 tokenId => uint256 time)    public termEnds;
    address public almProxy; // Sole depositor, and the only destination for withdrawals
    uint256 public minTerm;  // Minimum time between a first deposit and its term end

    address public immutable facility;
    GemLike public immutable gem;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, uint256 data);
    event Deposit(uint256 indexed tokenId, uint256 amount, uint256 termEnd);
    event Withdraw(uint256 indexed tokenId, uint256 amount);
    event Repay(uint256 indexed tokenId, uint256 amount);

    // --- Modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "TEJRCEscrow/not-authorized");
        _;
    }

    modifier toll() {
        require(buds[msg.sender] == 1, "TEJRCEscrow/not-operator");
        _;
    }

    // --- Constructor ---

    constructor(address facility_) {
        facility = facility_;
        gem      = GemLike(FacilityLike(facility_).gem());

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- auth Functions ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function kiss(address usr) external auth {
        buds[usr] = 1;
        emit Kiss(usr);
    }

    function diss(address usr) external auth {
        buds[usr] = 0;
        emit Diss(usr);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "almProxy") almProxy = data;
        else revert("TEJRCEscrow/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "minTerm") minTerm = data;
        else revert("TEJRCEscrow/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Operator Functions ---

    // Note: the term end is fixed by the first deposit for a tokenId and can never be changed,
    // so later deposits cannot delay a payout that is already committed
    // Note: deposits are expected to precede issuance, so that no NFAT is ever outstanding
    // without its payout already held here
    function deposit(uint256 tokenId, uint256 amount, uint256 termEnd) external {
        require(msg.sender == almProxy, "TEJRCEscrow/not-alm-proxy");
        require(tokenId != 0, "TEJRCEscrow/token-id-zero");
        require(amount   > 0, "TEJRCEscrow/zero-amount");

        // Note: applied to every deposit, not just the first. Otherwise a later deposit could
        // attach to an existing term end that is about to elapse, and be released without ever
        // having been immobile - which is the whole basis for this contract having no rate limits
        require(termEnd >= block.timestamp + minTerm, "TEJRCEscrow/term-end-too-soon");

        uint256 termEnd_ = termEnds[tokenId];
        if (termEnd_ == 0) termEnds[tokenId] = termEnd;
        else require(termEnd == termEnd_, "TEJRCEscrow/term-end-mismatch");

        balances[tokenId] += amount;

        gem.transferFrom(msg.sender, address(this), amount);

        emit Deposit(tokenId, amount, termEnd);
    }

    // Note: funds can only ever return to `almProxy`, so this contract cannot be a route to
    // move value elsewhere - it returns it to the paired proxy, where the ordinary rate limits
    // apply. Only governance can repoint it
    // Note: this is how an attested loss is applied - the haircut is withdrawn before term,
    // leaving exactly what the holder is owed
    function withdraw(uint256 tokenId, uint256 amount) external toll {
        require(amount > 0, "TEJRCEscrow/zero-amount");

        uint256 balance = balances[tokenId];
        require(balance >= amount, "TEJRCEscrow/insufficient-balance");
        unchecked { balance -= amount; }
        balances[tokenId] = balance;

        // Note: emptying the balance releases the term end too, so the id can be redeposited
        // against a fresh one. That is the only way to correct a term end set in error. A
        // partial withdrawal keeps it, so applying a haircut cannot move a committed payout
        if (balance == 0) termEnds[tokenId] = 0;

        gem.transfer(almProxy, amount);

        emit Withdraw(tokenId, amount);
    }

    // --- Permissionless Release ---

    // Note: deliberately takes no amount - it releases the whole balance, so the caller has
    // no say in the figure. Whatever remains after any haircut is what the holder is owed
    // Note: reverts while the facility is stopped, since `repay` is gated on it there. The
    // facility's freezer therefore covers this contract too and no separate one is needed
    function repay(uint256 tokenId) external {
        uint256 amount = balances[tokenId];
        require(amount > 0, "TEJRCEscrow/nothing-to-repay");
        require(block.timestamp >= termEnds[tokenId], "TEJRCEscrow/before-term-end");

        balances[tokenId] = 0;

        // Note: the facility pulls exactly `amount`, so no allowance is left outstanding
        gem.approve(facility, amount);
        FacilityLike(facility).repay(tokenId, amount);

        emit Repay(tokenId, amount);
    }

}
