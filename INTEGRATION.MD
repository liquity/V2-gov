# Risks to integrators

Somebody could claim on your behalf

Votes not meeting the threshold may result in 0 rewards

Claiming more than once will return 0

## INVARIANT: You can only claim for previous epoch

assert(votesSnapshot_.forEpoch == epoch() - 1); /// @audit INVARIANT: You can only claim for previous epoch
/// All unclaimed rewards are always recycled