// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title Treasury
/// @notice Receives platform fees (launch fees, 0.80% trading fee, graduation fee).
///         Owner should be a multisig in production — see DEPLOYMENT.md.
///         This contract never holds user liquidity or creator rewards, only
///         platform revenue, so it cannot be used to "steal" user funds.
contract Treasury is Ownable2Step {
    event Withdrawn(address indexed to, uint256 amount);
    event Received(address indexed from, uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner) {}

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function withdraw(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "zero address");
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "withdraw failed");
        emit Withdrawn(to, amount);
    }
}
