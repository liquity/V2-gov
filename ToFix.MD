- Add properties check to ensure that the math is sound

Specifically, if a user removes their votes, we need to see that reflect correctly
Because that's key

- From there, try fixing with a reset on deposit and withdraw

- From there, reason around the deeper rounding errors


Optimizations
Put the data in the storage
Remove all castings that are not safe
Invariant test it