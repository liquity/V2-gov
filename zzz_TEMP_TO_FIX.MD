[FAIL. Reason: EvmError: Revert] test_claimForInitiative() (gas: 835404)

This test tries to claim more than once per epoch, so it correctly fails
We need to enforce that you can only claim once