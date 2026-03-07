// SPDX-License-Identifier: MIT
// Author: Stan At
pragma solidity ^0.8.0;

/* =========================
   Minimal Ownable
========================= */
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "NOT_OWNER");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZERO_OWNER");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/* =========================
   TRC20 minimal interface
========================= */
interface ITRC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/* =========================
   FourteenVault
   - Holds 4TEEN tokens
   - Only Bootstrapper can "pull" tokens out to executors
   - Bootstrapper address is set AFTER deploy (to avoid circular dependency)
   - NO owner withdrawal of 4TEEN (by design)
========================= */
contract FourteenVault is Ownable {
    ITRC20 public immutable FOURTEEN;

    address public bootstrapper; // set after deploy

    event BootstrapperUpdated(address indexed oldBootstrapper, address indexed newBootstrapper);
    event Pulled(address indexed caller, address indexed to, uint256 amount);

    modifier onlyBootstrapper() {
        require(msg.sender == bootstrapper, "NOT_BOOTSTRAPPER");
        _;
    }

    constructor(address _fourteenToken) {
        require(_fourteenToken != address(0), "FOURTEEN_ZERO");
        FOURTEEN = ITRC20(_fourteenToken);
    }

    function setBootstrapper(address newBootstrapper) external onlyOwner {
        require(newBootstrapper != address(0), "BOOTSTRAPPER_ZERO");
        address old = bootstrapper;
        bootstrapper = newBootstrapper;
        emit BootstrapperUpdated(old, newBootstrapper);
    }

    /// @notice Sends 4TEEN tokens from the vault directly to `to` (executor).
    /// @dev Only callable by the configured bootstrapper.
    function pull(address to, uint256 amount) external onlyBootstrapper {
        require(to != address(0), "TO_ZERO");
        require(amount > 0, "AMOUNT_ZERO");

        uint256 bal = FOURTEEN.balanceOf(address(this));
        require(bal >= amount, "INSUFFICIENT_VAULT_BALANCE");

        require(FOURTEEN.transfer(to, amount), "TRANSFER_FAILED");
        emit Pulled(msg.sender, to, amount);
    }

    // Vault should not accept TRX by mistake.
    receive() external payable {
        revert("NO_TRX");
    }
}
