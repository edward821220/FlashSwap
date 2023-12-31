// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Callee} from "v2-core/interfaces/IUniswapV2Callee.sol";

// This is a practice contract for flash swap arbitrage
contract Arbitrage is IUniswapV2Callee, Ownable {
    struct Calldata {
        address priceLowerPool;
        address priceHigherPool;
        uint256 swapAmount;
        uint256 repayAmount;
        address weth;
        address usdc;
    }
    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //

    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //
    function uniswapV2Call(address sender, uint256 amount0, uint256, bytes calldata data) external override {
        require(sender == address(this), "Only this contract can call");
        Calldata memory inputData = abi.decode(data, (Calldata));
        address priceLowerPool = inputData.priceLowerPool;
        address priceHigherPool = inputData.priceHigherPool;
        uint256 swapAmount = inputData.swapAmount;
        uint256 repayAmount = inputData.repayAmount;
        address weth = inputData.weth;
        address usdc = inputData.usdc;

        require(msg.sender == priceLowerPool, "Only priceLowerPool can call");

        // TODO
        IERC20(weth).transfer(priceHigherPool, amount0);
        IUniswapV2Pair(priceHigherPool).swap(0, swapAmount, address(this), new bytes(0));
        IERC20(usdc).transfer(priceLowerPool, repayAmount);
    }

    // Method 1 is
    //  - borrow WETH from lower price pool
    //  - swap WETH for USDC in higher price pool
    //  - repay USDC to lower pool
    // Method 2 is
    //  - borrow USDC from higher price pool
    //  - swap USDC for WETH in lower pool
    //  - repay WETH to higher pool
    // for testing convenient, we implement the method 1 here
    function arbitrage(address priceLowerPool, address priceHigherPool, uint256 borrowETH) external {
        // TODO
        address weth = IUniswapV2Pair(priceLowerPool).token0();
        address usdc = IUniswapV2Pair(priceLowerPool).token1();

        (uint112 lowerReserveWETH, uint112 lowerReserveUSDC,) = IUniswapV2Pair(priceLowerPool).getReserves();
        uint256 repayAmount = _getAmountIn(borrowETH, lowerReserveUSDC, lowerReserveWETH);

        (uint112 higherReserveWETH, uint112 higherReserveUSDC,) = IUniswapV2Pair(priceHigherPool).getReserves();
        uint256 swapAmount = _getAmountOut(borrowETH, higherReserveWETH, higherReserveUSDC);

        Calldata memory data = Calldata(priceLowerPool, priceHigherPool, swapAmount, repayAmount, weth, usdc);

        IUniswapV2Pair(priceLowerPool).swap(borrowETH, 0, address(this), abi.encode(data));
    }

    //
    // INTERNAL PURE
    //

    // copy from UniswapV2Library
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    // copy from UniswapV2Library
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
