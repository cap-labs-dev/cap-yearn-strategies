// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {MorphoCompounder} from "./MorphoCompounder.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

/// @title MorphoCompounderFactory
/// @author kexley, Cap Labs (adapted from Yearn's MorphoCompounderFactory)
/// @notice Factory for deploying MorphoCompounder strategies
contract MorphoCompounderFactory {
    /// @notice Event emitted when a new Morpho Compounder is deployed
    event NewMorphoCompounder(address indexed strategy, address indexed asset);

    /// @notice Security multisig address
    address public immutable SMS;

    /// @notice Merkl claimer
    address public immutable claimer;

    /// @notice Swapper contract
    address public immutable swapper;

    /// @notice Management address
    address public management;

    /// @notice Performance fee recipient
    address public performanceFeeRecipient;

    /// @notice Keeper address
    address public keeper;

    /// @notice Constructor for the MorphoCompounderFactory
    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _sms,
        address _claimer,
        address _swapper
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        SMS = _sms;
        claimer = _claimer;
        swapper = _swapper;
    }

    /// @notice Deploy a new Morpho Compounder
    /// @param _vault The morpho vault to deploy the strategy for
    /// @param _depositor The depositor of the strategy
    /// @return . The address of the new strategy
    function newMorphoCompounder(address _vault, address _depositor) external returns (address) {
        require(msg.sender == management, "!management");

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
            address(new MorphoCompounder(_asset, _name, _vault, _depositor, claimer, swapper))
        );

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setEmergencyAdmin(SMS);

        newStrategy.setProfitMaxUnlockTime(0);

        newStrategy.setPendingManagement(management);

        emit NewMorphoCompounder(address(newStrategy), _asset);

        return address(newStrategy);
    }

    /// @notice Set the addresses
    /// @param _management The management address
    /// @param _performanceFeeRecipient The performance fee recipient address
    /// @param _keeper The keeper address
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
}