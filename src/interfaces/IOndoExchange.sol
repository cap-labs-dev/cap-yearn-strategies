// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

/// @title IOndoExchange
/// @author Ondo
/// @notice Interface for the Ondo Exchange
interface IOndoExchange {
    /// @notice Subscribes to a rebasing OUSG token
    /// @param depositToken The address of the token to deposit
    /// @param depositAmount The amount of the token to deposit
    /// @param minimumOUSGReceived The minimum amount of rebasing OUSG tokens to receive
    /// @return rousgAmountOut The amount of rebasing OUSG tokens received
    function subscribeRebasingOUSG(
        address depositToken,
        uint256 depositAmount,
        uint256 minimumOUSGReceived
    ) external returns (uint256 rousgAmountOut);

    /// @notice Redeems a rebasing OUSG token
    /// @param rousgAmount The amount of the rebasing OUSG tokens to redeem
    /// @param receivingToken The address of the token to receive
    /// @param minimumOUSGReceived The minimum amount of rebasing OUSG tokens to receive
    /// @return receiveTokenAmount The amount of tokens received
    function redeemRebasingOUSG(
        uint256 rousgAmount,
        address receivingToken,
        uint256 minimumOUSGReceived
    ) external returns (uint256 receiveTokenAmount);
}
