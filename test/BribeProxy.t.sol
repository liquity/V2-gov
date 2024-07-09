// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import {Test} from "forge-std/Test.sol";
// import {VmSafe} from "forge-std/Vm.sol";
// // import {console} from "forge-std/console.sol";

// import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// import {IGovernance} from "../src/interfaces/IGovernance.sol";
// import {Governance} from "../src/Governance.sol";
// import {BribeProxy} from "../src/BribeProxy.sol";
// import {WAD, PermitParams} from "../src/utils/Types.sol";

// interface ILQTY {
//     function domainSeparator() external view returns (bytes32);
// }

// contract BribeProxyTest is Test {
//     IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
//     IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
//     address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
//     address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
//     address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);
//     address private constant initiative = address(0x1);
//     address private constant initiative2 = address(0x2);
//     address private constant initiative3 = address(0x3);

//     uint256 private constant REGISTRATION_FEE = 1e18;
//     uint256 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
//     uint256 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
//     uint256 private constant MIN_CLAIM = 500e18;
//     uint256 private constant MIN_ACCRUAL = 1000e18;
//     uint256 private constant EPOCH_DURATION = 604800;
//     uint256 private constant EPOCH_VOTING_CUTOFF = 518400;

//     Governance private governance;
//     address[] private initialInitiatives;

//     BribeProxy private bribeProxy;

//     function setUp() public {
//         vm.createSelectFork(vm.rpcUrl("mainnet"));

//         initialInitiatives.push(initiative);
//         initialInitiatives.push(initiative2);

//         governance = new Governance(
//             address(lqty),
//             address(lusd),
//             stakingV1,
//             address(lusd),
//             IGovernance.Configuration({
//                 registrationFee: REGISTRATION_FEE,
//                 regstrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
//                 votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
//                 minClaim: MIN_CLAIM,
//                 minAccrual: MIN_ACCRUAL,
//                 epochStart: block.timestamp,
//                 epochDuration: EPOCH_DURATION,
//                 epochVotingCutoff: EPOCH_VOTING_CUTOFF
//             }),
//             initialInitiatives
//         );

//         bribeProxy = new BribeProxy(address(governance), address(lqty), address(lusd), initiative, address(lusd));
//     }

//     function test_bribe() public {
//         vm.startPrank(address(bribeProxy));
//         governance.deployUserProxy();
//         vm.stopPrank();

//         vm.startPrank(user);

//         address userProxy = governance.deployUserProxy();

//         lqty.approve(address(userProxy), 1e18);
//         assertEq(governance.depositLQTY(1e18), 1e18);

//         governance.transferShares(1e18, address(bribeProxy), address(user));

//         assertEq(governance.sharesByUser(user), 0);
//         assertEq(governance.sharesByUser(address(bribeProxy)), 1e18);

//         vm.warp(block.timestamp + 365 days);
//         bribeProxy.sync();

//         assertEq(governance.sharesByUser(address(bribeProxy)), 1e18);
//         (uint sharesAllocated,) = governance.sharesAllocatedByUser(address(bribeProxy));
//         assertEq(sharesAllocated, 1e18);
//         (sharesAllocated,) = governance.sharesAllocatedByUserToInitiative(address(bribeProxy), initiative);
//         assertEq(sharesAllocated, 1e18);

//         vm.stopPrank();
//     }
// }
