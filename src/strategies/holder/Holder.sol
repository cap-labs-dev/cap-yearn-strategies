// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy} from "@tokenized-strategy/BaseStrategy.sol";

/// @title Holder
/// @author kexley, Cap Labs
/// @notice A strategy that holds tokens and only does nothing else with them.
contract Holder is BaseStrategy {
    /// @dev Constructor
    /// @param _asset The asset address
    /// @param _name The name of the strategy
    constructor(
        address _asset,
        string memory _name
    ) BaseStrategy(_asset, _name) {}

    /// @dev Left empty as funds do not leave the contract
    /// @param _amount The amount of 'asset' deployed
    function _deployFunds(uint256 _amount) internal override {}

    /// @dev Left empty as funds do not leave the contract
    /// @param _amount The amount of 'asset' freed
    function _freeFunds(uint256 _amount) internal override {}

    /// @dev Returns the balance of 'asset' in the contract
    /// @return _totalAssets The balance of 'asset' in the contract
    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        _totalAssets = asset.balanceOf(address(this));
    }
}
