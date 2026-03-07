// SPDX-License-Identifier: MIT
// Author: Stan At
pragma solidity ^0.8.0;

interface ITRC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/*
  TeamLockVault
  - Holds 4TEEN tokens
  - Locks until releaseTime (1 year by default)
  - After releaseTime anyone can call release()
  - Tokens can ONLY go to beneficiary
  - No owner, no emergency, no early withdraw
*/
contract TeamLockVault {
    ITRC20 public immutable FOURTEEN;
    address public immutable beneficiary;
    uint256 public immutable releaseTime;

    event Released(address indexed to, uint256 amount);

    constructor(
        address _fourteenToken,
        address _beneficiary
    ) {
        require(_fourteenToken != address(0), "FOURTEEN_ZERO");
        require(_beneficiary != address(0), "BENEFICIARY_ZERO");

        FOURTEEN = ITRC20(_fourteenToken);
        beneficiary = _beneficiary;

        // lock for 365 days from deployment
        releaseTime = block.timestamp + 365 days;
    }

    function lockedBalance() external view returns (uint256) {
        return FOURTEEN.balanceOf(address(this));
    }

    function canRelease() external view returns (bool) {
        return block.timestamp >= releaseTime;
    }

    function release() external {
        require(block.timestamp >= releaseTime, "STILL_LOCKED");

        uint256 amount = FOURTEEN.balanceOf(address(this));
        require(amount > 0, "NOTHING_TO_RELEASE");

        require(FOURTEEN.transfer(beneficiary, amount), "TRANSFER_FAILED");
        emit Released(beneficiary, amount);
    }

    // do not accept TRX by mistake
    receive() external payable {
        revert("NO_TRX");
    }
}
