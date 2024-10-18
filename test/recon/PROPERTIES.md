## BribeInitiative

| Property | Description | Implemented | Tested |
| --- | --- | --- | --- |
| BI-01 | User should receive percentage of bribes corresponding to their allocation | ✅ |  |
| BI-02 | User can only claim bribes once in an epoch | ✅ |  |
| BI-03 | Accounting for user allocation amount is always correct | ✅ |  |
| BI-04 | Accounting for total allocation amount is always correct | ✅ |  |
| BI-05 | Dust amount remaining after claiming should be less than 100 million wei | ✅ |  |
| BI-06 | Accounting for bribe amount for an epoch is always correct |  |  |
| BI-07 | Sum of user allocations for an epoch = totalLqty allocation for the epoch |  |  |
| BI-08 | User can’t claim bribes for an epoch in which they aren’t allocated |  |  |
| BI-09 | User can’t be allocated for future epoch |  |  |
| BI-10 | totalLQTYAllocatedByEpoch ≥ lqtyAllocatedByUserAtEpoch |  |  |

## Governance
| Property | Description | Tested |
| --- | --- | --- |
| GV-01 | Initiative state should only return one state per epoch | ✅ |

| GV-02 | Initiative in Unregistered state reverts if a user tries to reregister it  |  |
| GV-03 | Initiative in Unregistered state reverts if a user tries to unregister it  |  |
| GV-04 | Initiative in Unregistered state reverts if a user tries to claim rewards for it  |  |

| GV-05 | A user can always vote if an initiative is active |  |
| GV-06 | A user can always remove votes if an initiative is inactive |  |
| GV-07 | A user cannot allocate to an initiative if it’s inactive |  |
| GV-08 | A user cannot vote more than their voting power |  |

| GV-09 | The sum of votes ≤ total votes | ✅ |

| GV-10 | Contributions are linear  |  |

| GV-11 | Initiatives that are removable can’t be blocked from being removed |  | NOTE: currently a removed can go back to being valid

| GV-12 | Removing vote allocation in multiple chunks results in 100% of requested amount being removed  |  |

| GV-13 | If a user has X votes and removes Y votes, they always have X - Y votes left  |  |
| GV-14 | If a user has X votes and removes Y votes, then withdraws X - Y votes they have 0 left  |  |

| GV-15 | A newly created initiative should be in `SKIP` state |  |
| GV-16 | An initiative that didn't meet the threshold should be in `SKIP` |  |
| GV-17 | An initiative that has sufficiently high vetoes in the next epoch should be `UNREGISTERABLE` |  |
| GV-18 | An initiative that has reached sufficient votes in the previous epoch should become `CLAIMABLE` in this epoch |  |
| GV-19 | A `CLAIMABLE` initiative can remain `CLAIMABLE` in the epoch, or can become `CLAIMED` once someone claims the rewards |  |
| GV-20 | A `CLAIMABLE` initiative can become `CLAIMED` once someone claims the rewards |  |