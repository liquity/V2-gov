[FAIL. Reason: EvmError: Revert] test_claimForInitiative() (gas: 835404)

This test tries to claim more than once per epoch, so it correctly fails
We need to enforce that you can only claim once


[FAIL. Reason: revert: Governance: initiative-already-registered] test_unregisterInitiative() (gas: 559412)

This rightfully fails because we do not want to re-enable a disabled initiative