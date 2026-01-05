// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { ISwapper } from "../interfaces/ISwapper.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Swapper Library
/// @author kexley, Cap Labs
/// @notice Library for swapper functions
library SwapperLib {
    function swap(address _swapper, address _fromToken, address _toToken, uint256 _amountIn) internal returns (uint256 amountOut) {
        SafeERC20.forceApprove(IERC20(_fromToken), _swapper, _amountIn);
        amountOut = ISwapper(_swapper).swap(_fromToken, _toToken, _amountIn);
        SafeERC20.forceApprove(IERC20(_fromToken), _swapper, 0);
    }
}
