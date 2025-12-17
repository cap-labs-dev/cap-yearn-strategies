// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {MorphoCompounder} from "./MorphoCompounder.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

contract MorphoCompounderFactory {
    /// @notice Revert message for when a strategy has already been deployed.
    error AlreadyDeployed(address _strategy);

    event NewMorphoCompounder(address indexed strategy, address indexed asset);

    address public immutable SMS;

    address public immutable claimer;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    /// @notice Track the deployments. vault => strategy
    mapping(address => address) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _sms,
        address _claimer
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        SMS = _sms;
        claimer = _claimer;
    }

    /**
     * @notice Deploy a new Morpho Compounder.
     * @param _vault The morpho vault to deploy the strategy for.
     * @param _depositor The depositor of the strategy.
     * @return . The address of the new strategy.
     */
    function newMorphoCompounder(address _vault, address _depositor) external returns (address) {
        require(msg.sender == management, "!management");

        if (deployments[_vault] != address(0))
            revert AlreadyDeployed(deployments[_vault]);

        address _asset = IStrategyInterface(_vault).asset();
        string memory _name = string(
            abi.encodePacked(
                "Morpho ",
                IStrategyInterface(_vault).name(),
                " Compounder"
            )
        );

        // We need to use the custom interface with the
        // tokenized strategies setters.
        IStrategyInterface newStrategy = IStrategyInterface(
            address(new MorphoCompounder(_asset, _name, _vault, _depositor, claimer))
        );

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setEmergencyAdmin(SMS);

        newStrategy.setProfitMaxUnlockTime(0);

        newStrategy.setPendingManagement(management);

        emit NewMorphoCompounder(address(newStrategy), _asset);

        deployments[_vault] = address(newStrategy);
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
        address _vault = address(MorphoCompounder(_strategy).vault());
        return deployments[_vault] == _strategy;
    }
}