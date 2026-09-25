// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseStrategy} from "@tokenized-strategy/BaseStrategy.sol";
import {IInstantManager} from "../../interfaces/IInstantManager.sol";

/// @title Ondo Holder
/// @author kexley, Cap Labs
/// @notice A strategy that swaps the asset to Ondo rUSDY for yield via the Ondo InstantManager.
/// @dev Single-depositor strategy. The strategy address itself must be KYC'd on Ondo.
contract OndoHolder is BaseStrategy {
    /// @dev Converts USDC (6 decimals) to rUSDY (18 decimals) at a 1:1 dollar peg
    uint256 internal constant RUSDY_SCALE = 1e12;

    /// @dev The error thrown when the address is zero
    error ZeroAddress();

    /// @dev The event emitted when the address of the exchange is set
    event SetExchange(address exchange);

    /// @notice Single depositor into this strategy
    address public immutable depositor;

    /// @notice The address of the Ondo InstantManager
    address public exchange;

    /// @notice The address of the rUSDY token
    address public rusdy;

    /// @dev Constructor
    /// @param _asset The asset address
    /// @param _name The name of the strategy
    /// @param _depositor The address of the depositor
    /// @param _exchange The address of the InstantManager
    /// @param _rusdy The address of the rUSDY token
    constructor(
        address _asset,
        string memory _name,
        address _depositor,
        address _exchange,
        address _rusdy
    ) BaseStrategy(_asset, _name) {
        if (_depositor == address(0)) revert ZeroAddress();
        if (_exchange == address(0)) revert ZeroAddress();
        if (_rusdy == address(0)) revert ZeroAddress();
        depositor = _depositor;
        exchange = _exchange;
        rusdy = _rusdy;
    }

    /// @notice Get the available deposit limit for the strategy
    /// @param _owner The owner of the strategy
    /// @return . The available deposit limit for the strategy
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        if (_owner != depositor) return 0;
        return type(uint256).max;
    }

    /// @notice Get the available withdraw limit for the strategy
    /// @param _owner The owner of the strategy
    /// @return . The available withdraw limit for the strategy
    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
        if (_owner != depositor) return 0;
        return type(uint256).max;
    }

    /// @dev Asset is subscribed to rUSDY through the InstantManager
    /// @param _amount The amount of 'asset' deployed
    function _deployFunds(uint256 _amount) internal override {
        SafeERC20.forceApprove(asset, exchange, _amount);
        // Min out of 0: InstantManager already prices via the Ondo oracle and may
        // take a fee / round down.
        IInstantManager(exchange).subscribeRebasingUSDY(
            address(asset),
            _amount,
            0
        );
    }

    /// @dev Redeems rUSDY for the requested amount of asset
    /// @param _amount The amount of 'asset' freed
    function _freeFunds(uint256 _amount) internal override {
        uint256 rusdyBal = IERC20(rusdy).balanceOf(address(this));
        // Compare in asset decimals so emergencyWithdraw(max) never overflows the 1e12 scale
        uint256 rusdyAmount = _amount >= rusdyBal / RUSDY_SCALE
            ? rusdyBal
            : _amount * RUSDY_SCALE;
        if (rusdyAmount == 0) return;

        SafeERC20.forceApprove(IERC20(rusdy), exchange, rusdyAmount);
        IInstantManager(exchange).redeemRebasingUSDY(
            rusdyAmount,
            address(asset),
            0
        );
    }

    /// @dev Emergency withdraw just redeems rUSDY
    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(_amount);
    }

    /// @dev Returns idle asset plus the USDC-scaled rUSDY balance
    function _harvestAndReport() internal view override returns (uint256) {
        return _totalAssetValue();
    }

    /// @dev Sets the address of the InstantManager
    /// @param _exchange The new address of the InstantManager
    function setExchange(address _exchange) external onlyManagement {
        if (_exchange == address(0)) revert ZeroAddress();
        exchange = _exchange;
        emit SetExchange(_exchange);
    }

    /// @dev Idle USDC + rUSDY valued 1:1 after the 6->18 decimal conversion
    function _totalAssetValue() internal view returns (uint256) {
        return
            asset.balanceOf(address(this)) +
            IERC20(rusdy).balanceOf(address(this)) /
            RUSDY_SCALE;
    }
}
