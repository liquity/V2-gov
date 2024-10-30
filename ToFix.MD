- Add properties check to ensure that the math is sound <- HUGE, let's add it now

A vote is: User TS * Votes
So an allocation should use that
We need to remove the data from the valid allocation
And not from a random one

I think the best test is to simply store the contribution done
And see whether removing it is idempotent

We would need a ton of work to make it even better


Specifically, if a user removes their votes, we need to see that reflect correctly
Because that's key

- From there, try fixing with a reset on deposit and withdraw

- Add a test that checks every: initiative, user allocation, ensure they are zero after a deposit and a withdrawal
- Add a test that checks every: X, ensure they use the correct TS

- From there, reason around the deeper rounding errors

---------

Optimizations
Put the data in the storage
Remove all castings that are not safe
Invariant test it

---------

TODO: Most likely need to review this
https://github.com/liquity/V2-gov/blob/81f3e55ab9c145cf185d1aeb2417f03807a4caf3/src/BribeInitiative.sol#L129-L142

```solidity
if (boldAmount != 0) {
            uint256 max = bold.balanceOf(address(this));
            if (boldAmount > max) {
                boldAmount = max;
            }
            bold.safeTransfer(msg.sender, boldAmount);
        }
        if (bribeTokenAmount != 0) {
            uint256 max = bribeToken.balanceOf(address(this));
            if (bribeTokenAmount > max) {
                bribeTokenAmount = max;
            }
            bribeToken.safeTransfer(msg.sender, bribeTokenAmount);
        }
```
And find revert cases
--
