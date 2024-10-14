
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";
import {IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {console2} from "forge-std/Test.sol";
import {Properties} from "./Properties.sol";
import {MaliciousInitiative} from "../mocks/MaliciousInitiative.sol";
import {ILQTYStaking} from "../../src/interfaces/ILQTYStaking.sol";
import {IInitiative} from "../../src/interfaces/IInitiative.sol";
import {IUserProxy} from "../../src/interfaces/IUserProxy.sol";
import {PermitParams} from "../../src/utils/Types.sol";


abstract contract TargetFunctions is BaseTargetFunctions, Properties {

    // clamps to a single initiative to ensure coverage in case both haven't been registered yet
    function governance_allocateLQTY_clamped_single_initiative(uint8 initiativesIndex, uint96 deltaLQTYVotes, uint96 deltaLQTYVetos) withChecks public {
        // clamp using the user's staked balance
        uint96 stakedAmount = IUserProxy(governance.deriveUserProxyAddress(user)).staked();
        
        address[] memory initiatives = new address[](1);
        initiatives[0] = _getDeployedInitiative(initiativesIndex);
        int88[] memory deltaLQTYVotesArray = new int88[](1);
        deltaLQTYVotesArray[0] = int88(uint88(deltaLQTYVotes % stakedAmount));
        int88[] memory deltaLQTYVetosArray = new int88[](1);
        deltaLQTYVetosArray[0] = int88(uint88(deltaLQTYVetos % stakedAmount));
        
        governance.allocateLQTY(initiatives, deltaLQTYVotesArray, deltaLQTYVetosArray);
    }

    function governance_allocateLQTY(int88[] calldata _deltaLQTYVotes, int88[] calldata _deltaLQTYVetos) withChecks public {
        governance.allocateLQTY(deployedInitiatives, _deltaLQTYVotes, _deltaLQTYVetos);
    }

    function governance_claimForInitiative(uint8 initiativeIndex) withChecks public {
        address initiative = _getDeployedInitiative(initiativeIndex);
        governance.claimForInitiative(initiative);
    }

    function governance_claimFromStakingV1(uint8 recipientIndex) withChecks public {
        address rewardRecipient = _getRandomUser(recipientIndex);
        governance.claimFromStakingV1(rewardRecipient);
    }

    function governance_deployUserProxy() withChecks public {
        governance.deployUserProxy();
    }

    function governance_depositLQTY(uint88 lqtyAmount) withChecks public {
        lqtyAmount = uint88(lqtyAmount % lqty.balanceOf(user));
        governance.depositLQTY(lqtyAmount);
    }

    function governance_depositLQTYViaPermit(uint88 _lqtyAmount) withChecks public {
         // Get the current block timestamp for the deadline
        uint256 deadline = block.timestamp + 1 hours;

        // Create the permit message
        bytes32 permitTypeHash = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 domainSeparator = IERC20Permit(address(lqty)).DOMAIN_SEPARATOR();

        
        uint256 nonce = IERC20Permit(address(lqty)).nonces(user);
        
        bytes32 structHash = keccak256(abi.encode(
            permitTypeHash,
            user,
            address(governance),
            _lqtyAmount,
            nonce,
            deadline
        ));

        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            structHash
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user2Pk, digest);

        PermitParams memory permitParams = PermitParams({
            owner: user2,
            spender: user,
            value: _lqtyAmount,
            deadline: deadline,
            v: v,
            r: r,
            s: s
        });

        governance.depositLQTYViaPermit(_lqtyAmount, permitParams);
    }

    function governance_registerInitiative(uint8 initiativeIndex) withChecks public {
        address initiative = _getDeployedInitiative(initiativeIndex);
        governance.registerInitiative(initiative);
    }

    function governance_snapshotVotesForInitiative(address _initiative) withChecks public {
        governance.snapshotVotesForInitiative(_initiative);
    }

    function governance_unregisterInitiative(uint8 initiativeIndex) withChecks public {
        address initiative = _getDeployedInitiative(initiativeIndex);
        governance.unregisterInitiative(initiative);
    }

    function governance_withdrawLQTY(uint88 _lqtyAmount) withChecks public {
        governance.withdrawLQTY(_lqtyAmount);
    }

    // helper to deploy initiatives for registering that results in more bold transferred to the Governance contract
    function governance_deployInitiative() withChecks public {
        address initiative = address(new MaliciousInitiative());
        deployedInitiatives.push(initiative);
    }

    // helper to simulate bold accrual in Governance contract
    function governance_accrueBold(uint88 boldAmount) withChecks public {
        boldAmount = uint88(boldAmount % lusd.balanceOf(user));
        lusd.transfer(address(governance), boldAmount); // target contract is the user so it can transfer directly
    }


}