Failing tests:
Encountered 5 failing tests in test/Governance.t.sol:GovernanceTest
[FAIL. Reason: votes: 0 != 1000000000000000000] test_calculateVotingThreshold() (gas: 5023391)
[FAIL. Reason: assertion failed: 0 != 6027; counterexample: calldata=0xcc3b9002000000000000000000000000000000000000000000000000000000000000178b0000000000000000000000000000000000000000000000000000000000003c43000000000000000000000000000000000000000000000000000000000000470d0000000000000000000000000000000000000000000000000000000000003d0f0000000000000000000000000000000000000000000000000000000000000920 args=[6027, 15427 [1.542e4], 18189 [1.818e4], 15631 [1.563e4], 2336]] test_calculateVotingThreshold_fuzz(uint120,uint16,uint88,uint128,uint88) (runs: 0, μ: 0, ~: 0)
[FAIL. Reason: assertion failed: 0 != 1000000000000000000] test_nonReentrant() (gas: 389879)
[FAIL. Reason: assertion failed: 0 != 1000000000000000000] test_registerInitiative() (gas: 53601)
[FAIL. Reason: assertion failed: 0 != 1000000000000000000] test_unregisterInitiative() (gas: 53585)


All of these tests use vm.store, which is out of wahck

IMO rewrite to do it the proper way

Can debug the slots to make sure we're not doing any weird thing as wel