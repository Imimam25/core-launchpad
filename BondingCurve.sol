// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./LaunchToken.sol";
import "./BondingCurveLib.sol";
import "./IDexAdapter.sol";
import "./Treasury.sol";
import "./CreatorRewards.sol";

contract BondingCurve is ReentrancyGuard {
    using BondingCurveLib for uint256;

    enum State { TRADING, GRADUATING, GRADUATED }

    LaunchToken public immutable token;
    address public immutable creator;
    Treasury public immutable treasury;
    CreatorRewards public immutable creatorRewards;
    IDexAdapter public dexAdapter;

    uint256 public soldSupply;      // wad tokens sold via the curve so far
    uint256 public coreReserve;     // wei CORE currently held by the curve (post-fees)
    State public state;

    uint256 public constant CURVE_SUPPLY = 800_000_000 * 1e18;
    uint256 public constant GRAD_LIQUIDITY_SUPPLY = 200_000_000 * 1e18;
    uint256 public constant GRADUATION_RESERVE = 10_000 ether;

    uint256 public constant TRADE_FEE_BPS = 100;      // 1.00% total
    uint256 public constant PLATFORM_FEE_BPS = 80;    // 0.80%
    uint256 public constant CREATOR_FEE_BPS = 20;      // 0.20%
    uint256 public constant GRAD_FEE_BPS = 100;        // 1.00% of graduation liquidity CORE

    event Buy(address indexed buyer, uint256 coreIn, uint256 tokensOut, uint256 newPrice);
    event Sell(address indexed seller, uint256 tokensIn, uint256 coreOut, uint256 newPrice);
    event Graduated(address indexed pool, uint256 coreLiquidity, uint256 tokenLiquidity);
    event GraduationFailed(string reason);

    error NotTrading();
    error SlippageExceeded();
    error ZeroAmount();

    constructor(
        address creator_,
        Treasury treasury_,
        CreatorRewards creatorRewards_,
        IDexAdapter dexAdapter_,
        string memory name_,
        string memory symbol_,
        string memory metadataURI_
    ) {
        creator = creator_;
        treasury = treasury_;
        creatorRewards = creatorRewards_;
        dexAdapter = dexAdapter_;
        token = new LaunchToken(name_, symbol_, metadataURI_, creator_, address(this));
        state = State.TRADING;
    }

    // ---------- Views ----------

    function currentPrice() external view returns (uint256) {
        return BondingCurveLib.priceAt(soldSupply);
    }

    function remainingCurveSupply() external view returns (uint256) {
        return CURVE_SUPPLY - soldSupply;
    }

    function circulatingSupply() external view returns (uint256) {
        return soldSupply;
    }

    function quoteBuy(uint256 coreIn) public view returns (uint256 tokensOut) {
        tokensOut = BondingCurveLib.tokensOutForReserveIn(soldSupply, coreIn);
        if (soldSupply + tokensOut > CURVE_SUPPLY) {
            tokensOut = CURVE_SUPPLY - soldSupply; // capped at curve exhaustion
        }
    }

    // ---------- Trading ----------

    /// @param minTokensOut slippage protection
    function buy(uint256 minTokensOut) external payable nonReentrant {
        if (state != State.TRADING) revert NotTrading();
        if (msg.value == 0) revert ZeroAmount();

        uint256 fee = (msg.value * TRADE_FEE_BPS) / 10_000;
        uint256 netIn = msg.value - fee;

        uint256 tokensOut = BondingCurveLib.tokensOutForReserveIn(soldSupply, netIn);
        if (soldSupply + tokensOut > CURVE_SUPPLY) {
            tokensOut = CURVE_SUPPLY - soldSupply;
        }
        if (tokensOut < minTokensOut) revert SlippageExceeded();

        soldSupply += tokensOut;
        coreReserve += netIn;

        _distributeFee(fee);
        require(IERC20(address(token)).transfer(msg.sender, tokensOut), "transfer failed");

        emit Buy(msg.sender, msg.value, tokensOut, BondingCurveLib.priceAt(soldSupply));

        if (coreReserve >= GRADUATION_RESERVE) {
            _graduate();
        }
    }

    /// @param minCoreOut slippage protection
    function sell(uint256 tokensIn, uint256 minCoreOut) external nonReentrant {
        if (state != State.TRADING) revert NotTrading();
        if (tokensIn == 0) revert ZeroAmount();

        require(IERC20(address(token)).transferFrom(msg.sender, address(this), tokensIn), "transfer failed");

        uint256 grossOut = BondingCurveLib.reserveAt(soldSupply) - BondingCurveLib.reserveAt(soldSupply - tokensIn);
        uint256 fee = (grossOut * TRADE_FEE_BPS) / 10_000;
        uint256 netOut = grossOut - fee;
        if (netOut < minCoreOut) revert SlippageExceeded();

        soldSupply -= tokensIn;
        coreReserve -= grossOut;

        _distributeFee(fee);
        (bool ok, ) = msg.sender.call{value: netOut}("");
        require(ok, "CORE transfer failed");

        emit Sell(msg.sender, tokensIn, netOut, BondingCurveLib.priceAt(soldSupply));
    }

    function _distributeFee(uint256 fee) internal {
        uint256 platformCut = (fee * PLATFORM_FEE_BPS) / TRADE_FEE_BPS;
        uint256 creatorCut = fee - platformCut;
        if (platformCut > 0) {
            (bool ok1, ) = address(treasury).call{value: platformCut}("");
            require(ok1, "treasury transfer failed");
        }
        if (creatorCut > 0) {
            creatorRewards.deposit{value: creatorCut}(creator, address(this));
        }
    }

    // ---------- Graduation ----------

    function _graduate() internal {
        state = State.GRADUATING;

        uint256 gradFee = (coreReserve * GRAD_FEE_BPS) / 10_000;
        uint256 liquidityCore = coreReserve - gradFee;

        require(IERC20(address(token)).approve(address(dexAdapter), GRAD_LIQUIDITY_SUPPLY), "approve failed");

        try dexAdapter.createPoolAndAddLiquidity{value: liquidityCore}(address(token), GRAD_LIQUIDITY_SUPPLY)
            returns (address pool, uint256 /*lpAmount*/)
        {
            (bool ok, ) = address(treasury).call{value: gradFee}("");
            require(ok, "treasury transfer failed");
            state = State.GRADUATED;
            emit Graduated(pool, liquidityCore, GRAD_LIQUIDITY_SUPPLY);
        } catch Error(string memory reason) {
            // Roll back to TRADING — funds never left the curve, nothing is
            // marked graduated. Off-chain systems must not display
            // "Graduated" until the Graduated event is observed.
            state = State.TRADING;
            emit GraduationFailed(reason);
        } catch {
            state = State.TRADING;
            emit GraduationFailed("unknown");
        }
    }

    receive() external payable {}
}
