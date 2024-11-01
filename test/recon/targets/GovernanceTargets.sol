// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";
import {IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {console2} from "forge-std/Test.sol";

import {Properties} from "../Properties.sol";
import {MaliciousInitiative} from "../../mocks/MaliciousInitiative.sol";
import {BribeInitiative} from "src/BribeInitiative.sol";
import {Governance} from "src/Governance.sol";
import {ILQTYStaking} from "src/interfaces/ILQTYStaking.sol";
import {IInitiative} from "src/interfaces/IInitiative.sol";
import {IUserProxy} from "src/interfaces/IUserProxy.sol";
import {PermitParams} from "src/utils/Types.sol";
import {add} from "src/utils/Math.sol";

abstract contract GovernanceTargets is BaseTargetFunctions, Properties {
    // clamps to a single initiative to ensure coverage in case both haven't been registered yet
    function governance_allocateLQTY_clamped_single_initiative(
        uint8 initiativesIndex,
        uint96 deltaLQTYVotes,
        uint96 deltaLQTYVetos
    ) public withChecks {
        uint96 stakedAmount = IUserProxy(governance.deriveUserProxyAddress(user)).staked(); // clamp using the user's staked balance

        address[] memory initiatives = new address[](1);
        initiatives[0] = _getDeployedInitiative(initiativesIndex);
        int88[] memory deltaLQTYVotesArray = new int88[](1);
        deltaLQTYVotesArray[0] = int88(uint88(deltaLQTYVotes % stakedAmount));
        int88[] memory deltaLQTYVetosArray = new int88[](1);
        deltaLQTYVetosArray[0] = int88(uint88(deltaLQTYVetos % stakedAmount));

        // User B4
        // (uint88 b4_user_allocatedLQTY,) = governance.userStates(user); // TODO
        // StateB4
        (uint88 b4_global_allocatedLQTY,) = governance.globalState();

        (Governance.InitiativeStatus status, ,) = governance.getInitiativeState(initiatives[0]);


        governance.allocateLQTY(deployedInitiatives, initiatives, deltaLQTYVotesArray, deltaLQTYVetosArray);

        // The test here should be:
        // If initiative was DISABLED
        // No Global State accounting should change
        // User State accounting should change

        // If Initiative was anything else
        // Global state and user state accounting should change


        // (uint88 after_user_allocatedLQTY,) = governance.userStates(user); // TODO
        (uint88 after_global_allocatedLQTY,) = governance.globalState();

        if(status == Governance.InitiativeStatus.DISABLED) {
            // State allocation must never change
            // Whereas for the user it could | TODO
            eq(after_global_allocatedLQTY, b4_global_allocatedLQTY, "Same alloc");
        }
    }

    function governance_allocateLQTY_clamped_single_initiative_2nd_user(
        uint8 initiativesIndex,
        uint96 deltaLQTYVotes,
        uint96 deltaLQTYVetos
    ) public withChecks {

        uint96 stakedAmount = IUserProxy(governance.deriveUserProxyAddress(user2)).staked(); // clamp using the user's staked balance

        address[] memory initiatives = new address[](1);
        initiatives[0] = _getDeployedInitiative(initiativesIndex);
        int88[] memory deltaLQTYVotesArray = new int88[](1);
        deltaLQTYVotesArray[0] = int88(uint88(deltaLQTYVotes % stakedAmount));
        int88[] memory deltaLQTYVetosArray = new int88[](1);
        deltaLQTYVetosArray[0] = int88(uint88(deltaLQTYVetos % stakedAmount));

        require(stakedAmount > 0, "0 stake");

        vm.prank(user2);
        governance.allocateLQTY(deployedInitiatives, initiatives, deltaLQTYVotesArray, deltaLQTYVetosArray);
    }

    function governance_resetAllocations() public {
        governance.resetAllocations(deployedInitiatives, true);
    }
    function governance_resetAllocations_user_2() public {
        vm.prank(user2);
        governance.resetAllocations(deployedInitiatives, true);
    }

    // TODO: if userState.allocatedLQTY != 0 deposit and withdraw must always revert

    // Resetting never fails and always resets
    function property_resetting_never_reverts() public withChecks {
        int88[] memory zeroes = new int88[](deployedInitiatives.length);

        try governance.allocateLQTY(deployedInitiatives, deployedInitiatives, zeroes, zeroes) {}
        catch {
            t(false, "must never revert");
        }

        (uint88 user_allocatedLQTY,) = governance.userStates(user);

        eq(user_allocatedLQTY, 0, "User has 0 allocated on a reset");
    }

    function depositTsIsRational(uint88 lqtyAmount) public withChecks {
        uint88 stakedAmount = IUserProxy(governance.deriveUserProxyAddress(user)).staked(); // clamp using the user's staked balance

        // Deposit on zero
        if(stakedAmount == 0) {
            lqtyAmount = uint88(lqtyAmount % lqty.balanceOf(user));
            governance.depositLQTY(lqtyAmount);

            // assert that user TS is now * WAD
            (, uint120 ts) = governance.userStates(user);
            eq(ts, block.timestamp * 1e18, "User TS is scaled by WAD");
        }
    }
    function depositMustFailOnNonZeroAlloc(uint88 lqtyAmount) public withChecks {
        (uint88 user_allocatedLQTY,) = governance.userStates(user);

        require(user_allocatedLQTY != 0, "0 alloc");

        lqtyAmount = uint88(lqtyAmount % lqty.balanceOf(user));
        try governance.depositLQTY(lqtyAmount) {
            t(false, "Deposit Must always revert when user is not reset");
        } catch {
        }
    }
    
    function withdrwaMustFailOnNonZeroAcc(uint88 _lqtyAmount) public withChecks {
        (uint88 user_allocatedLQTY,) = governance.userStates(user);

        require(user_allocatedLQTY != 0);

        try governance.withdrawLQTY(_lqtyAmount) {
            t(false, "Withdraw Must always revert when user is not reset");
        } catch {
        }
    }

    // For every previous epoch go grab ghost values and ensure they match snapshot
    // For every initiative, make ghost values and ensure they match
    // For all operations, you also need to add the VESTED AMT?

    function governance_allocateLQTY(int88[] calldata _deltaLQTYVotes, int88[] calldata _deltaLQTYVetos)
        public
        withChecks
    {
        governance.allocateLQTY(deployedInitiatives, deployedInitiatives, _deltaLQTYVotes, _deltaLQTYVetos);
    }

    function governance_claimForInitiative(uint8 initiativeIndex) public withChecks {
        address initiative = _getDeployedInitiative(initiativeIndex);
        governance.claimForInitiative(initiative);
    }

    function governance_claimForInitiativeFuzzTest(uint8 initiativeIndex) public withChecks {
        address initiative = _getDeployedInitiative(initiativeIndex);

        // TODO Use view functions to get initiative and snapshot data
        // Pass those and verify the claim amt matches received
        // Check if we can claim

        // TODO: Check FSM as well, the initiative can be CLAIMABLE
        // And must become CLAIMED right after

        uint256 received = governance.claimForInitiative(initiative);
        uint256 secondReceived = governance.claimForInitiative(initiative);
        if (received != 0) {
            eq(secondReceived, 0, "Cannot claim twice");
        }
    }

    function governance_claimForInitiativeDoesntRevert(uint8 initiativeIndex) public withChecks {
        require(governance.epoch() > 2); // Prevent reverts due to timewarp
        address initiative = _getDeployedInitiative(initiativeIndex);

        try governance.claimForInitiative(initiative) {
        } catch {
            t(false, "claimForInitiative should never revert");
        }
    }

    function governance_claimFromStakingV1(uint8 recipientIndex) public withChecks {
        address rewardRecipient = _getRandomUser(recipientIndex);
        governance.claimFromStakingV1(rewardRecipient);
    }

    function governance_deployUserProxy() public withChecks {
        governance.deployUserProxy();
    }

    function governance_depositLQTY(uint88 lqtyAmount) public withChecks {
        lqtyAmount = uint88(lqtyAmount % lqty.balanceOf(user));
        governance.depositLQTY(lqtyAmount);
    }
    function governance_depositLQTY_2(uint88 lqtyAmount) public withChecks {
        // Deploy and approve since we don't do it in constructor
        vm.prank(user2);
        try governance.deployUserProxy() returns (address proxy) {
             vm.prank(user2);
             lqty.approve(proxy, type(uint88).max);
        } catch {

        }

        lqtyAmount = uint88(lqtyAmount % lqty.balanceOf(user2));
        vm.prank(user2);
        governance.depositLQTY(lqtyAmount);
    }

    function governance_depositLQTYViaPermit(uint88 _lqtyAmount) public withChecks {
        // Get the current block timestamp for the deadline
        uint256 deadline = block.timestamp + 1 hours;

        // Create the permit message
        bytes32 permitTypeHash =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 domainSeparator = IERC20Permit(address(lqty)).DOMAIN_SEPARATOR();

        uint256 nonce = IERC20Permit(address(lqty)).nonces(user);

        bytes32 structHash =
            keccak256(abi.encode(permitTypeHash, user, address(governance), _lqtyAmount, nonce, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user2Pk, digest);

        PermitParams memory permitParams =
            PermitParams({owner: user2, spender: user, value: _lqtyAmount, deadline: deadline, v: v, r: r, s: s});
        // TODO: BROKEN
        governance.depositLQTYViaPermit(_lqtyAmount, permitParams);
    }

    function governance_registerInitiative(uint8 initiativeIndex) public withChecks {
        address initiative = _getDeployedInitiative(initiativeIndex);
        governance.registerInitiative(initiative);
    }

    function governance_snapshotVotesForInitiative(address _initiative) public withChecks {
        governance.snapshotVotesForInitiative(_initiative);
    }

    function governance_unregisterInitiative(uint8 initiativeIndex) public withChecks {
        address initiative = _getDeployedInitiative(initiativeIndex);
        governance.unregisterInitiative(initiative);
    }

    function governance_withdrawLQTY(uint88 _lqtyAmount) public withChecks {
        governance.withdrawLQTY(_lqtyAmount);
    }
}
