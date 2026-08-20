// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface ISwapFacility {
    /**
     * @notice Swaps between two tokens, which can be $M, $M Extensions, or an asset used by JMI Extensions.
     * @param  tokenIn      The address of the token to swap from.
     * @param  tokenOut     The address of the token to swap to.
     * @param  amount       The amount to swap.
     * @param  recipient    The address to receive the swapped tokens.
     */
    function swap(address tokenIn, address tokenOut, uint256 amount, address recipient) external;
}
