// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseStrategy} from "@tokenized-strategy/BaseStrategy.sol";
import {ISwapFacility} from "../../interfaces/ISwapFacility.sol";

/// @title RWA Holder
/// @author kexley, Cap Labs
/// @notice A strategy that swaps the asset to RWA tokens for yield.
/// @dev This strategy uses a trusted executor to swap for RWA tokens asynchronously. 
/// Token balances are not directly tracked, we rely on the executor to report changes.
contract RWAHolder is BaseStrategy {
    /// @dev The error thrown when the caller is not authorized
    error CallerNotAuthorized();

    /// @dev The error thrown when the strategy is notified too often
    error NotifyTooOften();
    
    /// @dev The error thrown when the profit is too high
    error ProfitTooHigh();

    /// @dev The error thrown when the loss is too high
    error LossTooHigh();

    /// @dev The error thrown when the address is zero
    error ZeroAddress();

    /// @dev The event emitted when the strategy executes an external call
    event Execute(address indexed target, bytes data);

    /// @dev The event emitted when the strategy is notified of a profit
    event NotifyProfit(uint256 profit);

    /// @dev The event emitted when the strategy is notified of a loss
    event NotifyLoss(uint256 loss);

    /// @dev The event emitted when the maximum amount of profit is set
    event SetMaxProfit(uint256 maxProfit);

    /// @dev The event emitted when the maximum amount of loss is set
    event SetMaxLoss(uint256 maxLoss);

    /// @dev The event emitted when the address of the trusted swap executor is set
    event SetExecutor(address executor);

    /// @dev The event emitted when the address of the swap facility is set
    event SetSwapFacility(address swapFacility);

    /// @dev The event emitted when the address of the RWA token is set
    event SetRWA(address rwa);

    /// @notice Single depositor into this strategy
    address public immutable depositor;

    /// @notice The address of the trusted swap executor
    address public executor;

    /// @notice The address of the swap facility
    address public swapFacility;

    /// @notice The address of the RWA token
    address public rwa;

    /// @notice The maximum amount of profit that can be notified in one day
    uint256 public maxProfit;

    /// @notice The maximum amount of loss that can be notified in one day
    uint256 public maxLoss;

    /// @notice The total amount of profit that has been notified
    uint256 public profit;

    /// @notice The total amount of loss that has been notified
    uint256 public loss;

    /// @notice The last time the strategy was notified of a profit
    uint256 public lastNotifyProfit;

    /// @notice The last time the strategy was notified of a loss
    uint256 public lastNotifyLoss;

    /// @dev Modifier to ensure that the call is coming from the executor
    modifier onlyExecutor() {
        if (msg.sender != executor) revert CallerNotAuthorized();
        _;
    }

    /// @dev Constructor
    /// @param _asset The asset address
    /// @param _name The name of the strategy
    /// @param _depositor The address of the depositor
    /// @param _executor The address of the trusted swap executor
    /// @param _swapFacility The address of the swap facility
    constructor(
        address _asset,
        string memory _name,
        address _depositor,
        address _executor,
        address _swapFacility,
        address _rwa
    ) BaseStrategy(_asset, _name) {
        if (_executor == address(0)) revert ZeroAddress();
        if (_depositor == address(0)) revert ZeroAddress();
        depositor = _depositor;
        executor = _executor;
        swapFacility = _swapFacility;
        rwa = _rwa;
        maxProfit = 100_000e6;
        maxLoss = 100_000e6;

        emit SetExecutor(_executor);
        emit SetSwapFacility(_swapFacility);
        emit SetRWA(_rwa);
        emit SetMaxProfit(100_000e6);
        emit SetMaxLoss(100_000e6);
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
        return asset.balanceOf(address(this));
    }

    /// @dev Asset is swapped for RWA tokens
    /// @param _amount The amount of 'asset' deployed
    function _deployFunds(uint256 _amount) internal override {
        SafeERC20.forceApprove(asset, address(swapFacility), _amount);
        ISwapFacility(swapFacility).swap(address(asset), rwa, _amount, address(this));
    }

    /// @dev Left empty as funds cannot be programmatically freed
    /// @param _amount The amount of 'asset' freed
    function _freeFunds(uint256 _amount) internal override {}

    /// @dev Returns the attestation of the strategy's assets
    /// @return totalAssets_ The total assets of the strategy
    function _harvestAndReport() internal override returns (uint256 totalAssets_) {
        uint256 storedAssets = TokenizedStrategy.totalAssets();
        if (storedAssets + profit > loss) totalAssets_ = storedAssets + profit - loss;
        profit = 0;
        loss = 0;
    }

    /// @dev Executes external arbitrary calls to swap USDC for a yield-bearing RWA
    /// @param _target The address to call
    /// @param _data The data to call with
    function execute(address _target, bytes calldata _data) external onlyExecutor {
        (bool success, bytes memory result) = _target.call(_data);

        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        emit Execute(_target, _data);
    }

    /// @dev Notifies the strategy of a realized profit
    /// @param _profit The amount of profit
    function notifyProfit(uint256 _profit) external onlyExecutor {
        if (lastNotifyProfit + 1 days > block.timestamp) revert NotifyTooOften();
        if (_profit > maxProfit) revert ProfitTooHigh();
        lastNotifyProfit = block.timestamp;
        profit += _profit;
        emit NotifyProfit(_profit);
    }

    /// @dev Notifies the strategy of a realized loss
    /// @param _loss The amount of loss
    function notifyLoss(uint256 _loss) external onlyExecutor {
        if (lastNotifyLoss + 1 days > block.timestamp) revert NotifyTooOften();
        if (_loss > maxLoss) revert LossTooHigh();
        lastNotifyLoss = block.timestamp;
        loss += _loss;
        emit NotifyLoss(_loss);
    }

    /// @dev Sets the maximum amount of profit that can be notified in one day
    /// @param _maxProfit The new maximum amount of profit
    function setMaxProfit(uint256 _maxProfit) external onlyManagement {
        maxProfit = _maxProfit;
        emit SetMaxProfit(_maxProfit);
    }

    /// @dev Sets the maximum amount of loss that can be notified in one day
    /// @param _maxLoss The new maximum amount of loss
    function setMaxLoss(uint256 _maxLoss) external onlyManagement {
        maxLoss = _maxLoss;
        emit SetMaxLoss(_maxLoss);
    }

    /// @dev Sets the address of the trusted swap executor
    /// @param _executor The new address of the trusted swap executor
    function setExecutor(address _executor) external onlyManagement {
        if (_executor == address(0)) revert ZeroAddress();
        executor = _executor;
        emit SetExecutor(_executor);
    }

    /// @dev Sets the address of the swap facility
    /// @param _swapFacility The new address of the swap facility
    function setSwapFacility(address _swapFacility) external onlyManagement {
        if (_swapFacility == address(0)) revert ZeroAddress();
        swapFacility = _swapFacility;
        emit SetSwapFacility(_swapFacility);
    }
}
