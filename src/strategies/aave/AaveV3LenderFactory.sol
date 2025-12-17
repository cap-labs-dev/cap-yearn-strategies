// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {AaveV3Lender, ERC20} from "./AaveV3Lender.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {IVaultInterface} from "../../interfaces/IVaultInterface.sol";
import {IRegistry} from "../../interfaces/IRegistry.sol";

contract AaveV3LenderFactory {
    /// @notice Revert message for when a strategy has already been deployed.
    error AlreadyDeployed(address _strategy);

    /// @notice Revert message for when the asset is not the same as the vault asset.
    error InvalidVault(address _asset, address _vault);

    event NewAaveV3Lender(address indexed strategy, address indexed asset);

    address public immutable sms;

    address public immutable lendingPool;
    address public immutable router;
    address public immutable base;
    address public immutable registry;
    address public immutable claimer;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    /// @notice Track the deployments. asset => pool => strategy
    mapping(address => address) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _sms,
        address _lendingPool,
        address _router,
        address _base,
        address _registry,
        address _claimer
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        sms = _sms;
        lendingPool = _lendingPool;
        router = _router;
        base = _base;
        registry = _registry;
        claimer = _claimer;
    }

    /**
     * @notice Deploy a new Aave V3 Lender.
     * @param _asset The underlying asset for the lender to use.
     * @param _vault The vault that can deposit and withdraw.
     * @return . The address of the new lender.
     */
    function newAaveV3Lender(address _asset, address _vault) external returns (address) {
        require(msg.sender == management, "!management");

        if (deployments[_asset] != address(0))
            revert AlreadyDeployed(deployments[_asset]);

        if (
            !IRegistry(registry).isEndorsed(_vault) ||
            _asset != IVaultInterface(_vault).asset()
        ) revert InvalidVault(_asset, _vault);

        string memory _name = string(
            abi.encodePacked("Aave V3 ", ERC20(_asset).symbol(), " Lender")
        );

        // We need to use the custom interface with the
        // tokenized strategies available setters.
        IStrategyInterface newStrategy = IStrategyInterface(
            address(new AaveV3Lender(_asset, _name, lendingPool, router, base, _vault, claimer))
        );

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        newStrategy.setEmergencyAdmin(sms);

        newStrategy.setPerformanceFee(0);

        newStrategy.setProfitMaxUnlockTime(0);

        emit NewAaveV3Lender(address(newStrategy), _asset);

        deployments[_asset] = address(newStrategy);
        return address(newStrategy);
    }

    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }

    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        return deployments[_asset] == _strategy;
    }
}
