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

## Initiatives

Initiative can be added permissionlessly, requiring the payment of a 100 BOLD fee, and in the following epoch become active
for voting. During each snapshot, Initiatives which received as sufficient number of Votes that their incentive payout equals
at least 500 BOLD, will be eligible to Claim. Initiatives failing to meet this threshold will not qualify to claim for that epoch.
Initiatives failing to be eligible for a claim during four consecutive epochs may be deregistered permissionlessly, requiring
reregistration to become eligible for voting again.

## Voting
