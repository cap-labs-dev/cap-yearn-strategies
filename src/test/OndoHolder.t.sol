// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IInstantManager} from "../interfaces/IInstantManager.sol";
import {OndoHolder} from "../strategies/ondo/OndoHolder.sol";

interface IOndoInstantManager {
    function rwaToken() external view returns (address);
    function rusdy() external view returns (address);
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

interface IOndoPriceOracle {
    function getPrice() external view returns (uint256);
}

interface IRUSDY {
    function oracle() external view returns (address);
    function sharesOf(address account) external view returns (uint256);
    function paused() external view returns (bool);
    function unpause() external;
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
}

contract OndoHolderTest is Test {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant EXCHANGE = 0xa42613C243b67BF6194Ac327795b926B4b491f15;
    address internal constant USDY = 0x96F6eF951840721AdBF46Ac996b59E0235CB985C;
    address internal constant RUSDY = 0xaf37c1167910ebC994e266949387d2c7C326b879;
    address internal constant ONDO_ID_REGISTRY = 0xcf6958D69d535FD03BD6Df3F4fe6CDcd127D97df;

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
            RUSDY
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
        require(manager.rwaToken() == USDY, "unexpected USDY");
        require(manager.rusdy() == RUSDY, "unexpected rUSDY");

        _unpauseRusdy();
        _kycAddress(address(holder));

        vm.label(USDC, "USDC");
        vm.label(EXCHANGE, "USDY InstantManager");
        vm.label(USDY, "USDY");
        vm.label(RUSDY, "rUSDY");
        vm.label(address(holder), "OndoHolder");
        vm.label(depositor, "depositor");
    }

    /// @dev Unpause rUSDY wrap/unwrap if the live token is paused.
    function _unpauseRusdy() internal {
        IRUSDY token = IRUSDY(RUSDY);
        if (!token.paused()) return;
        vm.prank(token.getRoleMember(token.DEFAULT_ADMIN_ROLE(), 0));
        token.unpause();
        require(!token.paused(), "rUSDY still paused");
    }

    /// @dev Register `account` on OndoIDRegistry for USDY.
    function _kycAddress(address account) internal {
        IOndoIDRegistry registry = IOndoIDRegistry(ONDO_ID_REGISTRY);
        bytes32 role = registry.MASTER_CONFIGURER_ROLE();
        require(registry.getRoleMemberCount(role) > 0, "no OndoID configurer");

        address[] memory users = new address[](1);
        users[0] = account;

        vm.prank(registry.getRoleMember(role, 0));
        registry.setUserID(USDY, users, keccak256(abi.encode("cap-yearn-ondo-kyc", account)));

        require(registry.getRegisteredID(USDY, account) != bytes32(0), "OndoID registration failed");
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
        assertEq(holder.rusdy(), RUSDY);
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
            RUSDY
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

    function test_deposit_subscribes_to_rusdy() public {
        _deposit(depositAmount);

        assertEq(asset.balanceOf(address(holder)), 0, "idle USDC");
        assertGt(ERC20(RUSDY).balanceOf(address(holder)), 0, "no rUSDY");
        assertEq(strategy.totalAssets(), depositAmount, "totalAssets");
        // rUSDY is 18 decimals and ~$1, so balance / 1e12 ~= USDC deposited
        assertApproxEqRel(
            ERC20(RUSDY).balanceOf(address(holder)) / 1e12,
            depositAmount,
            0.01e18,
            "rUSDY value"
        );
    }

    function test_withdraw_redeems_rusdy() public {
        _deposit(depositAmount);

        uint256 shares = strategy.balanceOf(depositor);
        assertEq(strategy.maxRedeem(depositor), shares, "maxRedeem");

        // InstantManager / oracle rounding can realize a few units of loss vs the 1:1 report.
        vm.prank(depositor);
        strategy.redeem(shares, depositor, depositor, 50);

        assertApproxEqAbs(asset.balanceOf(depositor), depositAmount, 3, "depositor USDC");
        assertEq(strategy.balanceOf(depositor), 0, "shares remain");
    }

    function test_partial_withdraw_allows_zero_loss() public {
        _deposit(depositAmount);
        uint256 amount = depositAmount / 2;

        // The three-argument withdraw allows no loss, including one USDC base unit.
        vm.prank(depositor);
        strategy.withdraw(amount, depositor, depositor);

        assertEq(asset.balanceOf(depositor), amount, "withdrawal shortfall");
        assertEq(strategy.totalAssets(), depositAmount - amount, "unexpected loss");
        assertGt(ERC20(RUSDY).balanceOf(address(holder)), 0, "position fully redeemed");
    }

    function test_withdraw_caps_rounding_buffer_at_rusdy_balance() public {
        _deposit(depositAmount);
        uint256 rusdyBalance = ERC20(RUSDY).balanceOf(address(holder));
        uint256 amount = rusdyBalance / 1e12;
        assertGt((amount + 1) * 1e12, rusdyBalance, "buffer fits within balance");

        // When the buffer would exceed the balance, redeem only the balance.
        vm.expectCall(
            EXCHANGE,
            abi.encodeCall(
                IInstantManager.redeemRebasingUSDY,
                (rusdyBalance, USDC, 0)
            )
        );
        vm.prank(depositor);
        strategy.withdraw(amount, depositor, depositor);

        assertEq(asset.balanceOf(depositor), amount, "withdrawal shortfall");
        assertEq(ERC20(RUSDY).balanceOf(address(holder)), 0, "rUSDY leftover");
    }

    function test_report_accounts_rusdy() public {
        _deposit(depositAmount);

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Fresh subscribe is ~1:1; flooring rUSDY/1e12 can show 1 unit of loss.
        assertLe(loss, 2, "loss");
        assertApproxEqAbs(strategy.totalAssets(), depositAmount, 2e6, "reported assets");
        profit;
    }

    /// @dev Mock the oracle price, leaving the real rUSDY share/balance accounting intact.
    function _rebaseRusdy(uint256 priceBps) internal {
        address oracle = IRUSDY(RUSDY).oracle();
        uint256 price = IOndoPriceOracle(oracle).getPrice();
        vm.mockCall(
            oracle,
            abi.encodeCall(IOndoPriceOracle.getPrice, ()),
            abi.encode(price * priceBps / 10_000)
        );
    }

    function test_report_locks_profit_after_positive_rebase() public {
        _deposit(depositAmount);

        uint256 assetsBefore = strategy.totalAssets();
        uint256 balanceBefore = ERC20(RUSDY).balanceOf(address(holder));
        uint256 rusdySharesBefore = IRUSDY(RUSDY).sharesOf(address(holder));
        uint256 depositorShares = strategy.balanceOf(depositor);
        uint256 depositorAssetsBefore = strategy.convertToAssets(depositorShares);

        // A 10% increase in USDY's price rebases the existing rUSDY balance upward.
        _rebaseRusdy(11_000);

        uint256 rebasedBalance = ERC20(RUSDY).balanceOf(address(holder));
        assertGt(rebasedBalance, balanceBefore, "rUSDY did not rebase upward");
        assertApproxEqAbs(rebasedBalance, balanceBefore * 11 / 10, 1, "positive rebase");
        assertEq(IRUSDY(RUSDY).sharesOf(address(holder)), rusdySharesBefore, "rUSDY shares changed");
        assertEq(strategy.totalAssets(), assetsBefore, "profit recognized before report");
        assertEq(strategy.convertToAssets(depositorShares), depositorAssetsBefore, "unreported profit unlocked");

        uint256 expectedAssets = asset.balanceOf(address(holder)) + rebasedBalance / 1e12;
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertGt(profit, 0, "no profit reported");
        assertEq(profit, expectedAssets - assetsBefore, "reported profit");
        assertEq(loss, 0, "unexpected loss");
        assertEq(strategy.totalAssets(), expectedAssets, "profit not accounted for");
        assertEq(strategy.balanceOf(depositor), depositorShares, "depositor shares changed");
        assertGt(strategy.balanceOf(address(strategy)), 0, "profit not locked");
        assertApproxEqAbs(strategy.convertToAssets(depositorShares), depositorAssetsBefore, 1, "profit unlocked immediately");
        assertEq(strategy.fullProfitUnlockDate(), block.timestamp + strategy.profitMaxUnlockTime(), "unlock date");

        vm.warp(strategy.fullProfitUnlockDate());
        assertEq(strategy.balanceOf(address(strategy)), 0, "profit still locked");
        assertEq(strategy.convertToAssets(depositorShares), expectedAssets, "profit not available after unlock");

        vm.prank(keeper);
        (profit, loss) = strategy.report();
        assertEq(profit, 0, "profit counted twice");
        assertEq(loss, 0, "unexpected loss on second report");
        assertEq(strategy.totalAssets(), expectedAssets, "assets changed on second report");
    }

    function test_report_realizes_loss_after_negative_rebase() public {
        _deposit(depositAmount);

        uint256 assetsBefore = strategy.totalAssets();
        uint256 balanceBefore = ERC20(RUSDY).balanceOf(address(holder));
        uint256 rusdySharesBefore = IRUSDY(RUSDY).sharesOf(address(holder));
        uint256 depositorShares = strategy.balanceOf(depositor);
        uint256 depositorAssetsBefore = strategy.convertToAssets(depositorShares);

        // Simulate a 10% downward price correction with the same underlying shares.
        _rebaseRusdy(9_000);

        uint256 rebasedBalance = ERC20(RUSDY).balanceOf(address(holder));
        assertLt(rebasedBalance, balanceBefore, "rUSDY did not rebase downward");
        assertApproxEqAbs(rebasedBalance, balanceBefore * 9 / 10, 1, "negative rebase");
        assertEq(IRUSDY(RUSDY).sharesOf(address(holder)), rusdySharesBefore, "rUSDY shares changed");
        assertEq(strategy.totalAssets(), assetsBefore, "loss recognized before report");
        assertEq(strategy.convertToAssets(depositorShares), depositorAssetsBefore, "loss realized before report");

        uint256 expectedAssets = asset.balanceOf(address(holder)) + rebasedBalance / 1e12;
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(profit, 0, "unexpected profit");
        assertGt(loss, 0, "no loss reported");
        assertEq(loss, assetsBefore - expectedAssets, "reported loss");
        assertEq(strategy.totalAssets(), expectedAssets, "loss not accounted for");
        assertEq(strategy.balanceOf(depositor), depositorShares, "depositor shares changed");
        assertEq(strategy.balanceOf(address(strategy)), 0, "unexpected locked shares");
        assertEq(strategy.fullProfitUnlockDate(), 0, "unexpected profit unlock schedule");
        assertEq(strategy.convertToAssets(depositorShares), expectedAssets, "loss not reflected in share value");
        assertLt(strategy.convertToAssets(depositorShares), depositorAssetsBefore, "share value did not fall");

        vm.prank(keeper);
        (profit, loss) = strategy.report();
        assertEq(profit, 0, "unexpected profit on second report");
        assertEq(loss, 0, "loss counted twice");
        assertEq(strategy.totalAssets(), expectedAssets, "assets changed on second report");
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

    function test_emergency_withdraw_zero_does_not_redeem() public {
        _deposit(depositAmount);
        uint256 rusdyBalance = ERC20(RUSDY).balanceOf(address(holder));

        vm.prank(management);
        strategy.shutdownStrategy();
        vm.prank(management);
        strategy.emergencyWithdraw(0);

        assertEq(ERC20(RUSDY).balanceOf(address(holder)), rusdyBalance, "rUSDY redeemed");
        assertEq(asset.balanceOf(address(holder)), 0, "unexpected USDC");
    }

    function test_emergency_withdraw() public {
        _deposit(depositAmount);

        vm.prank(management);
        strategy.shutdownStrategy();
        vm.prank(management);
        strategy.emergencyWithdraw(type(uint256).max);

        assertGt(asset.balanceOf(address(holder)), 0, "no USDC freed");
        assertEq(ERC20(RUSDY).balanceOf(address(holder)), 0, "rUSDY leftover");
    }
}
