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



Optimizations
Put the data in the storage
Remove all castings that are not safe
Invariant test it

--