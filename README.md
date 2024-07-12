# Liquity v2: Modular Initiative based Governance

Liquity v2 is a decentralized protocol that allows Ether and Liquid Staking Token (LST) holders to obtain
maximum liquidity against their collateral, at an interest that they set. After locking up ETH or LSTs as
collateral in a smart contract and creating an individual position called a "trove", the user can get
instant liquidity by minting BOLD, a USD-pegged stablecoin. Each trove is required to be collateralized
at a minimum level per collateral type. Any owner of BOLD can redeem their stablecoins for the underlying
collateral at any time. The redemption mechanism along with algorithmically adjusted fees guarantee a minimum
stablecoin value of USD 1.

An unprecedented liquidation mechanism based on incentivized stability deposits and a redistribution
cycle from lower interest rate paying troves to higher interest rate paying troves provides for greater
price stability for the BOLD token around the peg, balancing demand and supply for BOLD, without the need for
active governance or monetary interventions.

The protocol has built-in incentives that encourage both price stability as well as liquidity for the BOLD stablecoin.
With 75% of revenues from borrowing activities used to incentivize the Stability Pool (SP), and the remaining 25% of
revenues from borrowing activities (incentive portion) allocated to the Modular Initiative based Governance.

Modular Initiative based Governance allows LQTY holders to allocate votes, earned through staking,
to direct the incentive portion to arbitrary addresses, which are specified as Initiatives. Voting activity is snapshotted
in a decentralized manner and paid out at the end of weekly epochs.

## Staking

Staking allows LQTY token holders to deposit LQTY to accrue voting power which can be used to direct Incentives, while
maintaining eligibility to earn rewards from Liquity v1 (https://docs.liquity.org/faq/staking).

This is managed through the use of a UserProxy, which uses a factory pattern, to create an address specific wrapper for each
LQTY user who stakes LQTY via Governance.sol, and manages accounting and claiming from Liquity v1 staking. While Proxies can
be deployed either via the Governance.sol contract or directly, each instance of UserProxy is accessible by Governance.sol to
allow for Liquity v2 staking and voting accounting to be managed accurately.

Governance.sol uses an internal shares concept, this allows for the weight of a user's LQTY staked to increase in power over time
on a linear basis. Upon deposit, a User's voting power will be equal to 0, and increases at a rate of 1000% of LQTY per year.

Users' LQTY stake can be increased and decreased over time, but each increased LQTY added will require power accrual from 0,
and not assume the power of already deposited LQTY.

In order to unstake and withdraw LQTY, a User must deallocate a sufficient number of shares corresponding to the number of
LQTY to remove.

## Initiatives

Initiative can be added permissionlessly, requiring the payment of a 100 BOLD fee, and in the following epoch become active
for voting. During each snapshot, Initiatives which received as sufficient number of Votes that their incentive payout equals
at least 500 BOLD, will be eligible to Claim. Initiatives failing to meet this threshold will not qualify to claim for that epoch.
Initiatives failing to be eligible for a claim during four consecutive epochs may be deregistered permissionlessly, requiring
reregistration to become eligible for voting again.

Claims for Initiatives which have met the qualifying minimum, can be claimed permissionlessly, but must be claimed by the end of the epoch
in which they are awarded. Failure to do so will result in the unclaimed portion being reused in the following epoch.

As Initiatives are assigned to arbitrary addresses, they can be used for any purpose, including EOAs, Multisigs, or smart contracts designed
for targetted purposes. Smart contracts should be designed in a way that they can support BOLD and include any additional logic about
how BOLD is to be used.

## Voting

Users with LQTY staked in Governance.sol, can allocate shares in the epoch following the epoch in which they were deposited.
Meaning a User should deposit LQTY, and then make allocation decisions at least one epoch later.

Votes can take two forms, a vote for an Initiative or a veto vote. Initiatives which have received vetoes which are both:
three times greater than the minimum qualifying threshold, and greater than the number of votes for will not be eligible for Claims and may
be deregistered as an Initiative.

Users may split their votes for and veto votes across any number of initiatives. But cannot vote for and veto vote the same Initiative.

Each epoch is split into two parts, a six day period where both votes for and veto votes take place, and a final 24 hour period where votes
can only be made as veto votes. This is designed to give a period where any detrimental distributions can be mitigated should there be
sufficient will to do so by voters, but is not envisaged to be a regular occurance.

## Snapshots

Snapshots of results from the voting activity of an epoch takes place on an initiative by initiative basis in a permissionless manner.
User interactions or direct calls following the closure of an epoch trigger the snapshot logic which makes a Claim available to a
qualifying Initiative.
