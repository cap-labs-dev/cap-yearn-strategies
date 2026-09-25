// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

/// @title IInstantManager
/// @author Ondo
/// @notice Interface for the Ondo USDY InstantManager
interface IInstantManager {
    /// @notice Subscribes to a rebasing USDY token
    /// @param depositToken The address of the token to deposit
    /// @param depositAmount The amount of the token to deposit
    /// @param minimumUSDYReceived The minimum amount of rebasing USDY tokens to receive
    /// @return rusdyAmountOut The amount of rebasing USDY tokens received
    function subscribeRebasingUSDY(
        address depositToken,
        uint256 depositAmount,
        uint256 minimumUSDYReceived
    ) external returns (uint256 rusdyAmountOut);

    /// @notice Redeems a rebasing USDY token
    /// @param rusdyAmount The amount of the rebasing USDY tokens to redeem
    /// @param receivingToken The address of the token to receive
    /// @param minimumUSDYReceived The minimum amount of receiving tokens to receive
    /// @return receiveTokenAmount The amount of tokens received
    function redeemRebasingUSDY(
        uint256 rusdyAmount,
        address receivingToken,
        uint256 minimumUSDYReceived
    ) external returns (uint256 receiveTokenAmount);
}
