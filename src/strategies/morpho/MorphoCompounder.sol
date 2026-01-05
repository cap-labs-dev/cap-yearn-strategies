// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {SwapperLib} from "../../utils/SwapperLib.sol";
import {Base4626Compounder, ERC20, SafeERC20} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {IMerklClaimer} from "../../interfaces/merkl/IMerklClaimer.sol";

/// @title MorphoCompounder
/// @author kexley, Cap Labs (adapted from Yearn's MorphoCompounder)
/// @notice Strategy for compounding rewards from Morpho
contract MorphoCompounder is Base4626Compounder {
    using SafeERC20 for ERC20;

    /// @notice Single depositor into this strategy
    address public immutable depositor;

    /// @notice Merkl claimer
    IMerklClaimer public immutable claimer;

    /// @notice Swapper contract
    address public immutable swapper;

    /// @notice Reward tokens to claim and sell
    address[] public rewardTokens;

    /// @notice Minimum amount of each reward token to sell
    mapping(address => uint256) public minAmount;

    /// @notice Constructor for the MorphoCompounder
    constructor(
        address _asset,
        string memory _name,
        address _vault,
        address _depositor,
        address _claimer,
        address _swapper
    ) Base4626Compounder(_asset, _name, _vault) {
        require(_depositor != address(0), "depositor cannot be address(0)");
        depositor = _depositor;
        claimer = IMerklClaimer(_claimer);
        swapper = _swapper;
    }

    /// @notice Add a reward token
    /// @param _token The address of the reward token to add
    function addRewardToken(address _token) external onlyManagement {
        require(
            _token != address(asset) && _token != address(vault),
            "cannot be a reward token"
        );
        rewardTokens.push(_token);
    }

    /// @notice Remove a reward token
    /// @param _token The address of the reward token to remove
    function removeRewardToken(address _token) external onlyManagement {
        address[] memory _rewardTokens = rewardTokens;
        uint256 _length = _rewardTokens.length;

        for (uint256 i = 0; i < _length; i++) {
            if (_rewardTokens[i] == _token) {
                rewardTokens[i] = _rewardTokens[_length - 1];
                rewardTokens.pop();
            }
        }
    }

    /// @notice Set the minimum amount of a reward token to sell
    /// @param _token The address of the reward token to set the minimum amount for
    /// @param _minAmount The minimum amount of the reward token to sell
    function setMinAmount(address _token, uint256 _minAmount) external onlyManagement {
        minAmount[_token] = _minAmount;
    }

    /// @notice Get the reward tokens
    /// @return rewards The reward tokens
    function getRewardTokens() external view returns (address[] memory rewards) {
        return rewardTokens;
    }

    /// @dev Claim and sell rewards
    function _claimAndSellRewards() internal override {
        address[] memory _rewardTokens = rewardTokens;
        uint256 _length = _rewardTokens.length;

        for (uint256 i = 0; i < _length; i++) {
            address token = _rewardTokens[i];
            uint256 balance = ERC20(token).balanceOf(address(this));
            if (balance > minAmount[token]) {
                SwapperLib.swap(swapper, token, address(asset), balance);
            }
        }
    }

    /// @notice Get the available deposit limit for the strategy
    /// @param _owner The owner of the strategy
    /// @return . The available deposit limit for the strategy
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        if (_owner != depositor) return 0;
        return super.availableDepositLimit(_owner);
    }

    /// @notice Get the available withdraw limit for the strategy
    /// @param _owner The owner of the strategy
    /// @return . The available withdraw limit for the strategy
    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
        if (_owner != depositor) return 0;
        return super.availableWithdrawLimit(_owner);
    }

    /// @notice Claim rewards from Merkl
    /// @param _tokens The tokens to claim rewards for
    /// @param _amounts The amounts of the tokens to claim rewards for
    /// @param _proofs The proofs for the tokens to claim rewards for
    function claim(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs
    ) external {
        address[] memory users = new address[](_tokens.length);

        for (uint256 i = 0; i < _tokens.length; i++) {
            users[i] = address(this);
        }

        claimer.claim(users, _tokens, _amounts, _proofs);
    }
}
