// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV3MintCallback.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";
import "./lib/Position.sol";
import "./lib/Tick.sol";

// src/UniswapV3Pool.sol
contract UniswapV3Pool {
    // Every pool contract is an exchange market, so we must have two token addresses
    // They will be static because they are set once and forever

    // Each pool is also a set of liquidity positions, we'll store them in a mapping

    // Each pool also must maintain a registry of ticks

    // we must also track the current price, and related tick. This will be stored in one storage slot to optimise gas consumption

    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    
    error InsufficientInputAmount();
    error InvalidTickRange();
    error ZeroLiquidity();

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    address public immutable token0;
    address public immutable token1;

    struct Slot0 {
        uint160 sqrtPriceX96;
        int24 tick;
    }

    struct CallbackData {
        address token0;
        address token1;
        address payer;
    }

    Slot0 public slot0;

    // Amount of liquidity, L
    uint128 public liquidity;

    // Ticks Info
    mapping(int24 => Tick.Info) public ticks;

    // Positions Info
    mapping(bytes32 => Position.Info) public positions;

    constructor(
        address token0_,
        address token1_,
        uint160 sqrtPriceX96,
        int24 tick
    ) {
        token0 = token0_;
        token1 = token1_;

        slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick});
    }

    // Let’s outline a quick plan of how minting will work:

    // a user specifies a price range and an amount of liquidity;
    // the contract updates the ticks and positions mappings;
    // the contract calculates token amounts the user must send (we’ll pre-calculate and hard code them);
    // the contract takes tokens from the user and verifies that correct amounts were set.

    function mint(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1) {
        if (
            tickLower >= tickUpper ||
            tickLower < MIN_TICK ||
            tickUpper > MAX_TICK
        ) {
            revert InvalidTickRange();
        }

        if (amount == 0) {
            revert ZeroLiquidity();
        }

        ticks.update(tickLower, amount);
        ticks.update(tickUpper, amount);

        Position.Info storage position = positions.get(
            owner,
            tickLower,
            tickUpper
        );

        position.update(amount);

        amount0 = 0.998976618347425280 ether;
        amount1 = 5000 ether;

        liquidity += uint128(amount);

        uint256 balance0Before;
        uint256 balance1Before;

        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();

        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(
            amount0,
            amount1,
            data
        );

        if (amount0 > 0 && balance0Before + amount0 > balance0())
            revert InsufficientInputAmount();
        if (amount1 > 0 && balance1Before + amount1 > balance1())
            revert InsufficientInputAmount();

        emit Mint(msg.sender, owner, tickLower, tickUpper, amount, amount0, amount1);
        
    }

    function swap(address recipient, bytes calldata data)
        public
        returns (int256 amount0, int256 amount1)
    {
        int24 nextTick = 85184;
        uint160 nextPrice = 5604469350942327889444743441197;

        amount0 = -0.008396714242162444 ether;
        amount1 = 42 ether;

        (slot0.tick, slot0.sqrtPriceX96) = (nextTick, nextPrice);

        IERC20(token0).transfer(recipient, uint256(-amount0));

        uint256 balance1Before = balance1();
        IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
            amount0,
            amount1,
            data
        );
        if (balance1Before + uint256(amount1) > balance1())
            revert InsufficientInputAmount();

        emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            slot0.sqrtPriceX96,
            liquidity,
            slot0.tick
        );
    }

    function balance0() internal returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }


}