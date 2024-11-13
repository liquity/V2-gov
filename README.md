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

A user's LQTY stake increases in voting power over time on a linear basis depending on the time it has been staked.
Upon deposit, a User's voting power will be equal to 0.

Users' LQTY stake can be increased and decreased over time, but each increased LQTY added will require power accrual from 0,
and not assume the power of already deposited LQTY for the new staked LQTY.

In order to unstake and withdraw LQTY, a User must first deallocate a sufficient number of LQTY from initiatives.

## Initiatives

Initiative can be added permissionlessly, requiring the payment of a 100 BOLD fee, and in the following epoch become active
for voting. During each snapshot, Initiatives which received as sufficient number of Votes that their incentive payout equals
at least 500 BOLD, will be eligible to Claim ("minimum qualifying threshold"). Initiatives failing to meet the minimum qualifying threshold will not qualify to claim for that epoch.
Initiatives failing to meet the minimum qualifying threshold for a claim during four consecutive epochs may be deregistered permissionlessly, requiring reregistration to become eligible for voting again.

Claims for Initiatives which have met the minimum qualifying threshold, can be claimed permissionlessly, but must be claimed by the end of the epoch in which they are awarded. Failure to do so will result in the unclaimed portion being reused in the following epoch.

As Initiatives are assigned to arbitrary addresses, they can be used for any purpose, including EOAs, Multisigs, or smart contracts designed for targetted purposes. Smart contracts should be designed in a way that they can support BOLD and include any additional logic about how BOLD is to be used.

### Malicious Initiatives

It's important to note that initiatives could be malicious, and the system does it's best effort to prevent any DOS to happen, however, a malicious initiative could drain all rewards if voted on.

## Voting

Users with LQTY staked in Governance.sol, can allocate LQTY in the same epoch in which they were deposited. But the effective voting power at that point would be insignificant.

Votes can take two forms, a vote for an Initiative or a veto vote. Initiatives which have received vetoes which are both:
three times greater than the minimum qualifying threshold, and greater than the number of votes for will not be eligible for claims by being excluded from the vote count and maybe deregistered as an Initiative.

Users may split their votes for and veto votes across any number of initiatives. But cannot vote for and veto vote the same Initiative.

Each epoch is split into two parts, a six day period where both votes for and veto votes take place, and a final 24 hour period where votes can only be made as veto votes. This is designed to give a period where any detrimental distributions can be mitigated should there be sufficient will to do so by voters, but is not envisaged to be a regular occurance.

## Snapshots

Snapshots of results from the voting activity of an epoch takes place on an initiative by initiative basis in a permissionless manner.
User interactions or direct calls following the closure of an epoch trigger the snapshot logic which makes a Claim available to a qualifying Initiative.

## Bribing

LQTY depositors can also receive bribes in the form of ERC20s in exchange for voting for a specified initiative.
This is done externally to the Governance.sol logic and should be implemented at the initiative level.
BaseInitiative.sol is a reference implementation which allows for bribes to be set and paid in BOLD + another token, all claims for bribes are made by directly interacting with the implemented BaseInitiative contract.

## Example Initiatives

To facilitate the development of liquidity for BOLD and other relevant tokens after the launch of Liquity v2, initial example initiatives will be added.
They will be available from the first epoch in which claims are available (epoch 1), added in the construtor. Following epoch 1, these examples have no further special status and can be removed by LQTY voters

### Curve v2

Simple adapter to Claim from Governance.sol and deposit into a Curve v2 gauge, which must be preconfigured, and release rewards over a specified duration.
Claiming and depositing to gauges must be done manually after each epoch in which this Initiative has a Claim.

### Uniswap v4

Simple hook for Uniswap v4 which implements a donate to a preconfigured pool. Allowing for adjustments to liquidity positions to make Claims which are smoothed over a vesting epoch.

## Known Issues

### Vetoed Initiatives and Initiatives that receive votes that are below the treshold cause a loss of emissions to the voted initiatives

Because the system counts: valid_votes / total_votes
By definition, initiatives that increase the  total_votes without receiving any rewards are stealing the rewards from other initiatives

The rewards will be re-queued in the next epoch

see: `test_voteVsVeto` as well as the miro and comments

### User Votes, Initiative Votes and Global State Votes can desynchronize

See `test_property_sum_of_lqty_global_user_matches_0`

## Testing

To run foundry, just 
```
forge test
```


Please note the `TrophiesToFoundry`, which are repros of broken invariants, left failing on purpose

### Invariant Testing

We had a few issues with Medusa due to the use of `vm.warp`, we recommend using Echidna

Run echidna with:

```
echidna . --contract CryticTester --config echidna.yaml
```

You can also run Echidna on Recon by simply pasting the URL of the Repo / Branch
