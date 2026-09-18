// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {OndoHolder} from "../strategies/ondo/OndoHolder.sol";

interface IOndoInstantManager {
    function rwaToken() external view returns (address);
    function rousg() external view returns (address);
    function ondoIDRegistry() external view returns (address);
    function minimumDepositUSD() external view returns (uint256);
    function minimumRedemptionUSD() external view returns (uint256);
    function subscribePaused() external view returns (bool);
    function redeemPaused() external view returns (bool);
    function acceptedSubscriptionTokens(address) external view returns (bool);
    function acceptedRedemptionTokens(address) external view returns (bool);
}

interface IOndoIDRegistry {
    function MASTER_CONFIGURER_ROLE() external view returns (bytes32);
    function getRegisteredID(address rwaToken, address user) external view returns (bytes32);
    function setUserID(address rwaToken, address[] calldata userAddresses, bytes32 newUserID) external;
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
}

interface IOndoIDRegistryView {
    function getKYCStatus(uint256 kycRequirementGroup, address account) external view returns (bool);
}

interface IROUSG {
    function paused() external view returns (bool);
    function unpause() external;
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
}

contract OndoHolderTest is Test {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant EXCHANGE = 0x93358db73B6cd4b98D89c8F5f230E81a95c2643a;
    address internal constant OUSG = 0x1B19C19393e2d034D8Ff31ff34c81252FcBbee92;
    address internal constant ROUSG = 0x54043c656F0FAd0652D9Ae2603cDF347c5578d00;
    address internal constant ONDO_ID_REGISTRY = 0xcf6958D69d535FD03BD6Df3F4fe6CDcd127D97df;
    address internal constant ONDO_ID_REGISTRY_VIEW = 0x56A5D911052323D688C731d516530878557463e7;

    ERC20 internal asset;
    IOndoInstantManager internal manager;
    OndoHolder internal holder;
    IStrategy internal strategy;

    address internal depositor;
    address internal management;
    address internal keeper;
    address internal stranger;

    uint256 internal depositAmount;

    function setUp() public {
        asset = ERC20(USDC);
        manager = IOndoInstantManager(EXCHANGE);

        depositor = makeAddr("depositor");
        management = makeAddr("management");
        keeper = makeAddr("keeper");
        stranger = makeAddr("stranger");

        holder = new OndoHolder(
            USDC,
            "Ondo USDC Holder",
            depositor,
            EXCHANGE,
            ROUSG
        );
        strategy = IStrategy(address(holder));

        strategy.setKeeper(keeper);
        strategy.setPerformanceFeeRecipient(makeAddr("rewards"));
        strategy.setPerformanceFee(0);
        strategy.setPendingManagement(management);
        vm.prank(management);
        strategy.acceptManagement();

        // InstantManager enforces a USD minimum. Size deposits above it.
        uint256 minDepositUsd = manager.minimumDepositUSD();
        depositAmount = minDepositUsd / 1e12;
        if (depositAmount < 100e6) depositAmount = 100e6;
        // Add a buffer so we stay above min after any fee / rounding.
        depositAmount += 1e6;

        require(!manager.subscribePaused(), "subscribe paused");
        require(!manager.redeemPaused(), "redeem paused");
        require(manager.acceptedSubscriptionTokens(USDC), "USDC not accepted for subscribe");
        require(manager.acceptedRedemptionTokens(USDC), "USDC not accepted for redeem");
        require(manager.rwaToken() == OUSG, "unexpected OUSG");
        require(manager.rousg() == ROUSG, "unexpected rOUSG");

        _unpauseRousg();
        _kycAddress(address(holder));

        vm.label(USDC, "USDC");
        vm.label(EXCHANGE, "OUSG InstantManager");
        vm.label(OUSG, "OUSG");
        vm.label(ROUSG, "rOUSG");
        vm.label(address(holder), "OndoHolder");
        vm.label(depositor, "depositor");
    }

    /// @dev rOUSG wrap/unwrap is currently paused on mainnet; unpause so InstantManager can mint.
    function _unpauseRousg() internal {
        IROUSG rousg = IROUSG(ROUSG);
        if (!rousg.paused()) return;
        vm.prank(rousg.getRoleMember(rousg.DEFAULT_ADMIN_ROLE(), 0));
        rousg.unpause();
        require(!rousg.paused(), "rOUSG still paused");
    }

    /// @dev Register `account` on OndoIDRegistry for OUSG.
    ///      InstantManager checks this directly; rOUSG transfers check it via OndoIDRegistryView.
    function _kycAddress(address account) internal {
        IOndoIDRegistry registry = IOndoIDRegistry(ONDO_ID_REGISTRY);
        bytes32 role = registry.MASTER_CONFIGURER_ROLE();
        require(registry.getRoleMemberCount(role) > 0, "no OndoID configurer");

        address[] memory users = new address[](1);
        users[0] = account;

        vm.prank(registry.getRoleMember(role, 0));
        registry.setUserID(OUSG, users, keccak256(abi.encode("cap-yearn-ondo-kyc", account)));

        require(registry.getRegisteredID(OUSG, account) != bytes32(0), "OndoID registration failed");
        require(
            IOndoIDRegistryView(ONDO_ID_REGISTRY_VIEW).getKYCStatus(1, account),
            "rOUSG KYC view failed"
        );
    }

    function _deposit(uint256 amount) internal {
        deal(USDC, depositor, amount);
        vm.startPrank(depositor);
        asset.approve(address(strategy), amount);
        strategy.deposit(amount, depositor);
        vm.stopPrank();
    }

    function test_setup() public {
        assertEq(strategy.asset(), USDC);
        assertEq(holder.depositor(), depositor);
        assertEq(holder.exchange(), EXCHANGE);
        assertEq(holder.rousg(), ROUSG);
        assertEq(strategy.management(), management);
        assertEq(strategy.keeper(), keeper);
        assertEq(holder.availableDepositLimit(depositor), type(uint256).max);
        assertEq(holder.availableDepositLimit(stranger), 0);
        assertEq(holder.availableWithdrawLimit(stranger), 0);
    }

    function test_deposit_reverts_without_kyc() public {
        OndoHolder unkyced = new OndoHolder(
            USDC,
            "UnKYC'd Ondo Holder",
            depositor,
            EXCHANGE,
            ROUSG
        );

        deal(USDC, depositor, depositAmount);
        vm.startPrank(depositor);
        asset.approve(address(unkyced), depositAmount);
        vm.expectRevert();
        IStrategy(address(unkyced)).deposit(depositAmount, depositor);
        vm.stopPrank();
    }

    function test_only_depositor_can_deposit() public {
        deal(USDC, stranger, depositAmount);
        vm.startPrank(stranger);
        asset.approve(address(strategy), depositAmount);
        vm.expectRevert("ERC4626: deposit more than max");
        strategy.deposit(depositAmount, stranger);
        vm.stopPrank();
    }

    function test_deposit_subscribes_to_rousg() public {
        _deposit(depositAmount);

        assertEq(asset.balanceOf(address(holder)), 0, "idle USDC");
        assertGt(ERC20(ROUSG).balanceOf(address(holder)), 0, "no rOUSG");
        assertEq(strategy.totalAssets(), depositAmount, "totalAssets");
        // rOUSG is 18 decimals and ~$1, so balance / 1e12 ~= USDC deposited
        assertApproxEqRel(
            ERC20(ROUSG).balanceOf(address(holder)) / 1e12,
            depositAmount,
            0.01e18,
            "rOUSG value"
        );
    }

    function test_withdraw_redeems_rousg() public {
        _deposit(depositAmount);

        uint256 shares = strategy.balanceOf(depositor);
        assertEq(strategy.maxRedeem(depositor), shares, "maxRedeem");

        // InstantManager / oracle rounding can realize a few units of loss vs the 1:1 report.
        vm.prank(depositor);
        strategy.redeem(shares, depositor, depositor, 50);

        assertApproxEqAbs(asset.balanceOf(depositor), depositAmount, 3, "depositor USDC");
        assertEq(strategy.balanceOf(depositor), 0, "shares remain");
    }

    function test_report_accounts_rousg() public {
        _deposit(depositAmount);

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Fresh subscribe is ~1:1; flooring rOUSG/1e12 can show 1 unit of loss.
        assertLe(loss, 2, "loss");
        assertApproxEqAbs(strategy.totalAssets(), depositAmount, 2e6, "reported assets");
        profit;
    }

    function test_set_exchange() public {
        address next = makeAddr("nextExchange");
        vm.prank(management);
        holder.setExchange(next);
        assertEq(holder.exchange(), next);

        vm.prank(stranger);
        vm.expectRevert("!management");
        holder.setExchange(next);
    }

    function test_emergency_withdraw() public {
        _deposit(depositAmount);

        vm.prank(management);
        strategy.shutdownStrategy();
        vm.prank(management);
        strategy.emergencyWithdraw(type(uint256).max);

        assertGt(asset.balanceOf(address(holder)), 0, "no USDC freed");
        assertEq(ERC20(ROUSG).balanceOf(address(holder)), 0, "rOUSG leftover");
    }
}
