// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title CreatorRewards
/// @notice Holds the 0.20% creator share of trading fees per token, claimable
///         by the creator at any time. The platform (or any admin key) has
///         NO function that can move a creator's accrued balance — only the
///         creator can withdraw their own balance.
contract CreatorRewards is ReentrancyGuard {
    // creator => curve => claimable balance (wei)
    mapping(address => mapping(address => uint256)) public claimable;
    // creator => curve => total ever claimed (wei), for dashboard display
    mapping(address => mapping(address => uint256)) public totalClaimed;

    event Deposited(address indexed creator, address indexed curve, uint256 amount);
    event Claimed(address indexed creator, address indexed curve, uint256 amount);

    /// @notice Called only by a BondingCurve contract when trading fees accrue.
    function deposit(address creator, address curve) external payable {
        require(msg.value > 0, "zero deposit");
        claimable[creator][curve] += msg.value;
        emit Deposited(creator, curve, msg.value);
    }

    /// @notice Creator claims their own accrued rewards for one token. No
    ///         approval or admin action required.
    function claim(address curve) external nonReentrant {
        uint256 amount = claimable[msg.sender][curve];
        require(amount > 0, "nothing to claim");
        claimable[msg.sender][curve] = 0;
        totalClaimed[msg.sender][curve] += amount;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "claim transfer failed");
        emit Claimed(msg.sender, curve, amount);
    }
}
