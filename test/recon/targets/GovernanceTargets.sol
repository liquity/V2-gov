// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";
import {IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {console2} from "forge-std/Test.sol";

import {Properties} from "../Properties.sol";
import {MaliciousInitiative} from "../../mocks/MaliciousInitiative.sol";
import {BribeInitiative} from "../../../src/BribeInitiative.sol";
import {ILQTYStaking} from "../../../src/interfaces/ILQTYStaking.sol";
import {IInitiative} from "../../../src/interfaces/IInitiative.sol";
import {IUserProxy} from "../../../src/interfaces/IUserProxy.sol";
import {PermitParams} from "../../../src/utils/Types.sol";
import {add} from "../../../src/utils/Math.sol";

abstract contract GovernanceTargets is BaseTargetFunctions, Properties {
    // clamps to a single initiative to ensure coverage in case both haven't been registered yet
    function governance_allocateLQTY_clamped_single_initiative(
        uint8 initiativesIndex,
        uint96 deltaLQTYVotes,
        uint96 deltaLQTYVetos
    ) public withChecks {
        uint16 currentEpoch = governance.epoch();
        uint96 stakedAmount = IUserProxy(governance.deriveUserProxyAddress(user)).staked(); // clamp using the user's staked balance

        address[] memory initiatives = new address[](1);
        initiatives[0] = _getDeployedInitiative(initiativesIndex);
        int88[] memory deltaLQTYVotesArray = new int88[](1);
        deltaLQTYVotesArray[0] = int88(uint88(deltaLQTYVotes % stakedAmount));
        int88[] memory deltaLQTYVetosArray = new int88[](1);
        deltaLQTYVetosArray[0] = int88(uint88(deltaLQTYVetos % stakedAmount));

        governance.allocateLQTY(deployedInitiatives, initiatives, deltaLQTYVotesArray, deltaLQTYVetosArray);

        // if call was successful update the ghost tracking variables
        // allocation only allows voting OR vetoing at a time so need to check which was executed
        if (deltaLQTYVotesArray[0] > 0) {
            ghostLqtyAllocationByUserAtEpoch[user] = add(ghostLqtyAllocationByUserAtEpoch[user], deltaLQTYVotesArray[0]);
            ghostTotalAllocationAtEpoch[currentEpoch] =
                add(ghostTotalAllocationAtEpoch[currentEpoch], deltaLQTYVotesArray[0]);
        } else {
            ghostLqtyAllocationByUserAtEpoch[user] = add(ghostLqtyAllocationByUserAtEpoch[user], deltaLQTYVetosArray[0]);
            ghostTotalAllocationAtEpoch[currentEpoch] =
                add(ghostTotalAllocationAtEpoch[currentEpoch], deltaLQTYVetosArray[0]);
        }
    }

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

    // For every previous epoch go grab ghost values and ensure they match snapshot
    // For every initiative, make ghost values and ensure they match
    // For all operations, you also need to add the VESTED AMT?

    /// TODO: This is not really working
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
