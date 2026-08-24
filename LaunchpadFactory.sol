// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "./BondingCurve.sol";
import "./Treasury.sol";
import "./CreatorRewards.sol";
import "./IDexAdapter.sol";

/// @title LaunchpadFactory
/// @notice The only entry point users need. Anyone can call createToken() and
///         pay the launch fee — there is no allowlist, no approval step, and
///         no function that lets the owner block or approve a specific launch.
contract LaunchpadFactory is Ownable2Step {
    Treasury public immutable treasury;
    CreatorRewards public immutable creatorRewards;
    IDexAdapter public dexAdapter; // owner can upgrade to a new adapter (new DEX), never touches existing curves' funds

    uint256 public constant LAUNCH_FEE = 0.10 ether; // 0.10 CORE

    address[] public allCurves;
    mapping(address => bool) public isLaunchpadToken;

    event TokenLaunched(
        address indexed creator,
        address indexed token,
        address indexed curve,
        string name,
        string symbol,
        string metadataURI
    );

    constructor(address initialOwner, Treasury treasury_, CreatorRewards creatorRewards_, IDexAdapter dexAdapter_)
        Ownable(initialOwner)
    {
        treasury = treasury_;
        creatorRewards = creatorRewards_;
        dexAdapter = dexAdapter_;
    }

    /// @notice Permissionless: any wallet can call this directly.
    function createToken(string calldata name, string calldata symbol, string calldata metadataURI)
        external
        payable
        returns (address tokenAddr, address curveAddr)
    {
        require(msg.value >= LAUNCH_FEE, "insufficient launch fee");

        BondingCurve curve = new BondingCurve(
            msg.sender,
            treasury,
            creatorRewards,
            dexAdapter,
            name,
            symbol,
            metadataURI
        );

        allCurves.push(address(curve));
        isLaunchpadToken[address(curve.token())] = true;

        (bool ok, ) = address(treasury).call{value: msg.value}("");
        require(ok, "fee transfer failed");

        emit TokenLaunched(msg.sender, address(curve.token()), address(curve), name, symbol, metadataURI);
        return (address(curve.token()), address(curve));
    }

    function allCurvesLength() external view returns (uint256) {
        return allCurves.length;
    }

    /// @notice Owner (multisig) can point new launches at a new/updated DEX
    ///         adapter. Existing, already-graduated curves are unaffected.
    function setDexAdapter(IDexAdapter newAdapter) external onlyOwner {
        dexAdapter = newAdapter;
    }
}
