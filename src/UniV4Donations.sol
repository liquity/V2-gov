// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

import {BaseHook, Hooks} from "./utils/BaseHook.sol";
import {BribeInitiative} from "./BribeInitiative.sol";

contract UniV4Donations is BribeInitiative, BaseHook {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    event DonateToPool(uint256 amount);
    event RestartVesting(uint256 epoch, uint256 amount);

    uint256 public immutable VESTING_EPOCH_START;
    uint256 public immutable VESTING_EPOCH_DURATION;

    address private immutable currency0;
    address private immutable currency1;
    uint24 private immutable fee;
    int24 private immutable tickSpacing;

    struct Vesting {
        uint256 amount;
        uint256 epoch;
        uint256 released;
    }

    Vesting public vesting;

    constructor(
        address _governance,
        address _bold,
        address _bribeToken,
        uint256 _vestingEpochStart,
        uint256 _vestingEpochDuration,
        address _poolManager,
        address _token,
        uint24 _fee,
        int24 _tickSpacing
    ) BribeInitiative(_governance, _bold, _bribeToken) BaseHook(IPoolManager(_poolManager)) {
        VESTING_EPOCH_START = _vestingEpochStart;
        VESTING_EPOCH_DURATION = _vestingEpochDuration;

        if (uint256(uint160(address(_bold))) <= uint256(uint160(address(_token)))) {
            currency0 = _bold;
            currency1 = _token;
        } else {
            currency0 = _token;
            currency1 = _bold;
        }
        fee = _fee;
        tickSpacing = _tickSpacing;
    }

    function vestingEpoch() public view returns (uint256) {
        return ((block.timestamp - VESTING_EPOCH_START) / VESTING_EPOCH_DURATION) + 1;
    }

    function vestingEpochStart() public view returns (uint256) {
        return VESTING_EPOCH_START + ((vestingEpoch() - 1) * VESTING_EPOCH_DURATION);
    }

    function _restartVesting(uint256 claimed) internal returns (Vesting memory) {
        uint256 epoch = vestingEpoch();
        Vesting memory _vesting = vesting;
        if (_vesting.epoch < epoch) {
            _vesting.amount = claimed + _vesting.amount - uint256(_vesting.released); // roll over unclaimed amount
            _vesting.epoch = epoch;
            _vesting.released = 0;
            vesting = _vesting;
            emit RestartVesting(epoch, _vesting.amount);
        }
        return _vesting;
    }

    /// @dev TO FIX
    uint256 public received;

    /// @notice On claim we deposit the rewards - This is to prevent a griefing
    function onClaimForInitiative(uint256, uint256 _bold) external override onlyGovernance {
        received += _bold;
    }

    function _donateToPool() internal returns (uint256) {
        /// @audit TODO: Need to use storage value here I think
        /// TODO: Test and fix release speed, which looks off

        // Claim again // NOTE: May be grifed
        governance.claimForInitiative(address(this));

        /// @audit Includes the queued rewards
        uint256 toUse = received;

        // Reset
        received = 0;

        // Rest of logic
        Vesting memory _vesting = _restartVesting(toUse);
        uint256 amount =
            (_vesting.amount * (block.timestamp - vestingEpochStart()) / VESTING_EPOCH_DURATION) - _vesting.released;

        if (amount != 0) {
            PoolKey memory key = poolKey();

            manager.donate(key, amount, 0, bytes(""));
            manager.sync(key.currency0);
            IERC20(Currency.unwrap(key.currency0)).safeTransfer(address(manager), amount);
            manager.settle(key.currency0);

            vesting.released += amount;

            emit DonateToPool(amount);
        }

        return amount;
    }

    function donateToPool() public returns (uint256) {
        return abi.decode(manager.unlock(abi.encode(address(this), poolKey())), (uint256));
    }

    function poolKey() public view returns (PoolKey memory key) {
        key = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(this))
        });
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function afterInitialize(address, PoolKey calldata key, uint160, int24, bytes calldata)
        external
        view
        override
        onlyByManager
        returns (bytes4)
    {
        require(PoolId.unwrap(poolKey().toId()) == PoolId.unwrap(key.toId()), "UniV4Donations: invalid-pool-id");
        return this.afterInitialize.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyByManager returns (bytes4, BalanceDelta) {
        require(PoolId.unwrap(poolKey().toId()) == PoolId.unwrap(key.toId()), "UniV4Donations: invalid-pool-id");
        _donateToPool();
        return (this.afterAddLiquidity.selector, delta);
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        (address sender, PoolKey memory key) = abi.decode(data, (address, PoolKey));
        require(sender == address(this), "UniV4Donations: invalid-sender");
        require(PoolId.unwrap(poolKey().toId()) == PoolId.unwrap(key.toId()), "UniV4Donations: invalid-pool-id");
        return abi.encode(_donateToPool());
    }
}
