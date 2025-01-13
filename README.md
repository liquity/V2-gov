# Liquity v2 Governance

## Table of Contents

- [Overview](#overview)
- [Core Smart Contracts](#core-smart-contracts)
  - [Governance](#governance)
  - [UserProxyFactory](#userproxyfactory)
  - [UserProxy](#userproxy)
  - [BribeInitiative](#bribeinitiative)
- [Epochs](#epochs)
  - [Epoch Structure](#epoch-structure)
  - [Epoch Transitions](#epoch-transitions)
- [LQTY Deposits, Withdrawals, and v1 Staking](#lqty-deposits-withdrawals-and-v1-staking)
- [Voting Power Accrual](#voting-power-accrual)
  - [Multiple Deposits Over Time](#multiple-deposits-over-time)
  - [Voting Power Calculation and Internal Accounting](#voting-power-calculation-and-internal-accounting)
- [Withdrawals and Voting Power](#withdrawals-and-voting-power)
- [Allocating Voting Power to Initiatives](#allocating-voting-power-to-initiatives)
  - [Allocation in Practice](#allocation-in-practice)
- [Vetoing Initiatives](#vetoing-initiatives)
- [Allocations Across Epochs](#allocations-across-epochs)
- [Path Dependence of Voting Power Actions](#path-dependence-of-voting-power-actions)
- [Registering Initiatives](#registering-initiatives)
- [Unregistering Initiatives](#unregistering-initiatives)
- [Snapshots](#snapshots)
  - [Initiative Vote Snapshots](#initiative-vote-snapshots)
  - [Total Vote Snapshots](#total-vote-snapshots)
  - [Total BOLD Snapshots](#total-bold-snapshots)
  - [Snapshot Mechanics](#snapshot-mechanics)
- [Initiative States](#initiative-states)
- [Voting Threshold Calculation](#voting-threshold-calculation)
- [Claiming for Initiatives](#claiming-for-initiatives)
  - [Claim Frequency](#claim-frequency)
- [Bribes](#bribes)
  - [How Bribing Works](#how-bribing-works)
  - [Claiming Bribes](#claiming-bribes)
  - [Tracking Allocations and Votes](#tracking-allocations-and-votes)
- [Known Issues](#known-issues)
  - [Path Dependency of Depositing/Withdrawing LQTY](#path-dependency-of-depositingwithdrawing-lqty)
  - [Trust Assumption: Bribe Token](#trust-assumption-bribe-token)
  - [Trust Assumption: Initiative](#trust-assumption-initiative)
  - [Impact of Vetoed or Low-Vote Initiatives](#impact-of-vetoed-or-low-vote-initiatives)
- [Testing](#testing)
  - [Running Foundry Tests](#running-foundry-tests)
  - [Invariant Testing](#invariant-testing)




## Overview

The core Liquity v2 protocol has built-in incentives on each collateral branch that encourage both price stability as well as liquidity for the BOLD stablecoin. 75% of revenues from borrowing activities are used to incentivize the core system Stability Pools, and the remaining 25% of revenues from all borrowing activities (incentive portion) are allocated to the Modular Initiative based Governance.

Modular Initiative based Governance allows LQTY holders to allocate votes, earned over time through staking, to direct the incentive portion to arbitrary addresses, which are specified as Initiatives. Initiatives may be registered permissionlessly. 

Users are also able to allocate voting power as vetos, in order to attempt to block rewards to Initiatives they deem unworthy.

The system chunks time into weekly epochs. Voting activity is snapshotted in a decentralized manner and accrued incentives are paid out at the end of epochs to Initiatives that meet the qualifying criteria - primarily the voting threshold. Qualifying Initiatives for a given epoch receive a pro-rata share of the BOLD rewards accrued for that epoch, based on their share of the epoch’s votes.



## Core smart contracts

- `Governance` - the central system contract which manages all governance operations including Initiative registration, staking/unstaking LQTY, voting mechanics, and reward distribution. It handles time-weighted voting power calculations, epoch transitions and BOLD token rewards, while also managing the deployment of and interactions with UserProxy contracts. 

- `UserProxyFactory` - A factory contract that deploys minimal proxy clones of the `UserProxy` implementation using CREATE2 for deterministic addressing. It is inherited by the `Governance` contract to provide `UserProxy` deployment and management capabilities. It also maintains the relationship between Users and their UserProxies.

- `UserProxy` -  Serves as the intermediary between an individual User and the Liquity v1 staking system, holding their staked LQTY position. It handles all direct v1 staking operations and reward collection. Only the `Governance` contract can call its mutating functions. The proxy architecture allows the system to hold _individual_ staked LQTY positions on behalf of its Users.

- `BribeInitative` - A base contract that enables external parties to incentivize votes on Initiatives by depositing BOLD and other tokens as bribes. It records User vote allocations across epochs, ensuring proportional distribution of bribes to voters. The contract provides extensible hooks and functions that allow developers to create specialized Initiatives with custom logic while maintaining the core bribe distribution mechanics.


## Epochs
The Governance system operates on a weekly epoch-based scheme that provides predictable time windows for voting and claiming rewards. Each epoch is exactly `EPOCH_DURATION` (7 days) long. The epoch scheme provides predictable windows for Users to plan their vote and veto actions.
## Epoch Structure
Each epoch has two distinct phases:
**Phase 1: votes and vetos** (First 6 days)
- Users can freely allocate and modify their LQTY votes and vetos to Initiatives
**Phase 2: vetos only** (Final day)
- Users may not increase their vote allocation to any Initiative
- Users are free to decrease their vote allocation or increase their veto allocation to any Initiative


The purpose of Phase 2 is to prevent last-minute vote allocation by a bad-faith actor to Initiatives that are misaligned with the Liquity ecosystem.

The short veto phase at least gives other stakers a chance to veto such bad-faith Initiatives, even if they have to pull voting power away from other Initiatives.
### Epoch Transitions
Epochs transition automatically at fixed 7-day intervals. No manual intervention is required to trigger a new epoch. The first epoch-based operation in a new epoch triggers relevant snapshots - see the snapshots section [LINK].

## LQTY deposits, withdrawals and v1 staking

LQTY token holders may deposit LQTY to the Governance system via `Governance.depositLQTY`. Deposited LQTY is staked in Liquity v1, thus earning ETH and LUSD rewards from v1 fees. See Liquity v1 (https://docs.liquity.org/faq/staking) for further details of v1 staking and rewards.

Deposited LQTY accrues voting power linearly over time. A user’s voting power from deposited LQTY can be allocated and deallocated from Initiatives.

Users may top up their deposited LQTY at any time, and may withdraw part or all of their deposited LQTY via `withdrawLQTY` when they have no active allocations to Initiatives.

Both deposits and withdrawals can be made via ERC2612 permit with `depositLQTYViaPermit` and and `withdrawLQTYViaPermit` respectively.

Deposit and withdrawal functions allow the user to optionally claim their v1 staking rewards (LUSD and ETH) by passing a `_doClaimRewards` boolean.


## Voting power accrual

A user's LQTY deposit accrues voting power linearly over time. That is, the absolute voting power of a given LQTY deposit is proportional to 1) the LQTY deposited and 2) the time passed since deposit. 

Upon deposit of a chunk of LQTY, the voting power associated with that chunk will be equal to 0.

Top-ups of a User’s existing deposit accrue voting power in the same manner: that is, a given top-up accrues votes linearly according to its size and time passed since it was made.

The voting power of a User’s total deposited LQTY equals the sum of the voting power of all of the individual LQTY deposits/top-ups comprising their deposit.


## Withdrawals and voting power

A withdrawal pulls from the User’s unallocated LQTY. Withdrawals don’t “know” anything about the deposit history. A withdrawal of x% of the User’s unallocated LQTY reduces the voting power of their unallocated LQTY by x%  - even though the User may have made deposits at different times, with the older ones having accrued more voting power.

Withdrawals are thus considered “proportional” in that they reduce the voting power of all of the user’s previous deposit chunks by the same percentage.

As such, a User with non-zero unallocated voting power who deposits m LQTY then immediately withdraws m LQTY, will undergo a decrease in unallocated voting power. This natural penalty incentivises users to keep their LQTY deposited in the Governance system.



LQTY may be assigned to:

A User
An Initiative, as allocated “vote” LQTY
An Initiative, as allocated “veto” LQTY

Deposited LQTY accrues voting power continuously over time, for whichever entity it is assigned to (i.e. User or Initiative).

All LQTY accrues voting power at the same rate.



### Multiple deposits over time 

For a composite LQTY amount - i.e. a deposit made up of several deposit “chunks” at different points in time - each chunk earns voting power linearly from the point at which it was deposited.

So, the voting power for an individual User A with `n` deposits of LQTY made over time is given by:

`V_A(t) = m_1* (t - t_1) + m_2* (t - t_2) + ... + m_n* (t - t_n)`

i.e.

`V_A(t) = t*sum(m_i)  - sum(m_i*t_i)`

so:

`V_A(t) = t*M_A - S_A`

Where:

- `i`: Index denoting deposit i’th deposit event
- `t_i`: Time at which the i’th deposit was made
- `V_A`: total voting power for user A from `n` deposits by time `t`
- `M_A`: sum of A’s LQTY deposits 
- `S_A`: The “offset”, i.e. the sum of A’s deposit chunks weighted by time deposited.


### Voting power calculation and internal accounting

Voting power is calculated as above - i.e. `V_A(t) = t*M_A - S_A`.  Accounting is handled by storing the LQTY amount  and the “offset” sum for each user. These trackers are updated any time a user deposits, withdraws or allocates LQTY to Initiatives.


The general approach of using an LQTY amount and an offset tracker sum is used for both users and Initiatives.

LQTY amounts and offsets are recorded for:

- Per-user allocations
- Per-Initative allocations
- Per-user-per-Initiative allocations

The full scheme is outlined in this paper [LINK].



### Allocating voting power to Initiatives

LQTY can be allocated and deallocated to Initiatives by Users via `Governance.allocateLQTY`.  When LQTY is allocated to an Initiative, the corresponding voting power is also allocated.

Allocation from User to Initiative is also “proportional” in the same sense as withdrawals are.

After allocation, the voting power of the allocated LQTY continues growing linearly with time.


### Allocation in practice

A user passes their chosen LQTY allocations per-Initative to `allocateLQTY`.

Under the hood, allocation is performed in two steps internally: all their current allocations are zero’ed by a single call to the internal `_allocateLQTY` function, and then updated to the new values with a second call. 


## Vetoing Initiatives

Users may also allocate vetos to Initiatives via `Governance.allocateLQTY`. Just like voting power, LQTY allocated for vetoing accrues “veto power” linearly, and internal calculations and accounting are identical.

An Initiative which has received a sufficient quantity of vetoes is not claimable, and can be permissionlessly unregistered - see the “Initiative states” section for the precise threshold formulation [LINK]


## Allocations across epochs

LQTY allocations to an Initiative persist across epochs, and thus the corresponding voting power allocated to that Initiative continues growing linearly across epochs.



## Path dependence of voting power actions

**Allocating** and **deallocating** LQTY/voting power is path independent - that is, when a user allocates `x` voting power to an Initiative then immediately deallocates it, their voting power remains the same.

In contrast, **depositing** and **withdrawing** LQTY is path-dependent - for a User with non-zero voting power, a top-up and withdrawal of `x` LQTY will reduce their voting power. This is because the top-up LQTY chunk has 0 voting power, but the proportional nature of the withdrawal (see above - [LINK]) reduces the voting power of all previous LQTY chunks comprising their deposit.


## Registering Initiatives

Initiative can be registered permissionlessly via `registerInitative`.  The caller pays the `REGISTRATION_FEE` in BOLD. The caller must also have accrued sufficient total voting power (i.e. the sum of their allocated and unallocated voting power) in order to register an Initiative.  This threshold is dynamic - it is equal to the snapshot of the previous epoch’s total votes multiplied by the `REGISTRATION_VOTING_THRESHOLD`.  Thus, the greater the total votes in the previous epoch, the more voting power needed in order to register a new Initiative.

If the Initiative meets these requirements it becomes eligible for voting in the subsequent epoch.

Registration records the Initiative’s address and the epoch in which it was registered in the `registeredInitiatives` mapping.


## Unregistering Initiatives

Initiatives may be unregistered permissionlessly via `unregisterInitiative`.

An Initiative can be unregistered if either:


1. It has spent `UNREGISTRATION_AFTER_EPOCHS` (4) epochs in SKIP and/or CLAIMABLE states, without being claimed for


Or:

2. Its vetos exceed both its votes, and the voting threshold multiplied by `UNREGISTRATION_THRESHOLD_FACTOR`


## Snapshots

Since BOLD rewards are distributed based on an Initiative’s pro-rata share of votes at the end of each epoch, and since votes (and vetos) accrue continuously over time, snapshots of an Initiative’s accrued votes and vetos must be taken for given epochs.

Additionally, snapshots of total votes and vetos, and total BOLD rewards accrued, must be taken for each epoch, to perform the pro-rata reward calculations.


### Initiative vote snapshots

Initiative snapshotting is handled by `Governance._snapshotVotesForInitiative`.

It checks when the Initiative was last snapshotted, and if it is before the end of the previous epoch, a new snapshot of the Initiative’s current voting power is recorded. If a more recent snapshot has been taken, this function is a no-op.

Initiative snapshots are taken inside user operations: allocating LQTY to Initiatives (`allocateLQTY`), registering Initiatives (unregisterInitative), and claiming an Initiative’s incentives (`claimForInitative`) all perform Initiative snapshots before updating other Initiative state.

Initiative snapshots may also be recorded permissionlessly via the external `Governance.snapshotVotesForInitiative`  and `Governance.getInitiativeState` functions.


### Total vote snapshots

Total vote count is similarly snapshotted by `Governance._snapshotVotes`, which is called at all the same above user operations, and additionally upon Initiative registration (`registerInitiative`), and permissionlessly via `calculateVotingThreshold`. 



### Total BOLD snapshots

The total BOLD available for claim for the previous epoch  -  `boldAccrued` -  is snapshotted via `Governance._snapshotVotes`.  This is used as the denominator in reward distribution calculations for that epoch.



### Snapshot Mechanics
Since epochs transition seamlessly without need for a manual triggering action, the first relevant operation in a new epoch will trigger a snapshot calculation.

Since voting power is a simple linear function of LQTY and time (see voting power section above [LINK]), snapshots of votes can be calculated retroactively, i.e. _after_ the end of the previous epoch has passed. All that matters is snapshots are taken before LQTY quantities are changed, which is the case. In order to take the snapshot, the previous epoch’s end timestamp is used in the voting power calculation.

BOLD rewards are trickier - they are “lumpy” and arrive in somewhat unpredictable chunks (depending on the dynamics of the v2 core system).  As such, a late BOLD snapshot may take into account some BOLD that has arrived _after_ the epoch has ended. In practice, this slightly benefits Initiatives registered in the previous epoch, and slightly takes away BOLD rewards for the current epoch.

However, the permissionless snapshot function `Governance.calculateVotingThreshold` allows anyone to take a snapshot exactly at or very close to the epoch boundary, and ensure fair BOLD distribution. 

Snapshots are immutable once recorded for a given epoch.

## Initiative States
The governance system uses a state machine to determine the status of each Initiative. The relevant function is `Governance.getInitiativeState`. The state determines what actions can be taken with the Initiative.

In a given epoch, Initiatives can be in one of several states based on the previous epoch's snapshot.

Following are the states Initiatives can be in, the conditions that lead to the states, and their consequences.
_(Note that the state machine checks conditions in the order they are presented below - e.g. an Initiative in the CLAIMABLE state is by definition not in any of the states above CLAIMABLE)_:

<img width="581" alt="image" src="https://github.com/user-attachments/assets/ab9c5df1-0372-43b4-87d9-73c1daea1a62" />



## Voting threshold calculation

The voting threshold is used in two ways: determining whether an Initiative has sufficient net votes to be claimed for, and in part of the calculation for determining whether an Initiative can be unregistered - see Initiative states `CLAIMABLE` and `UNREGISTERABLE` in the Initiative states section [LINK].

It is calculated as the maximum of:

- `VOTING_THRESHOLD_FACTOR * _snapshot.votes`, i.e. 2% of the total votes counted at the snapshot for the previous epoch

and:

- The `minVotes`, which is the minimum number of votes required for an Initiative to meet the `MIN_CLAIM` amount of BOLD tokens, i.e. 500 BOLD.

Thus the voting threshold is dynamic and varies by epoch to epoch. The more total votes accrued in the previous epoch, the more are needed in the current epoch for an Initiative to be claimable. This formulation was chosen because staked LQTY earns voting power that grows linearly over time, and thus the total votes per epoch will tend to increase in the long-run.


## Claiming for Initiatives
Each Initiative that meets the qualifying criteria are eligible for claim, i.e. to have its share of BOLD rewards accrued during the previous epoch transferred to it. Claims are made through `claimForInitiative`and are permissionless - anyone can transfer the rewards from Governance to the qualifying Initiative. This function must be executed during the epoch following the snapshot. 

An Initiative qualifies for claim when its votes exceed both:

- The voting threshold
- The vetos received
  
The reward amount for a qualifying Initiative is calculated as the pro-rata share of the epoch's BOLD accrual, based on the Initiative's share of total votes among all qualifying Initiatives. For example, if an Initiative received 25% of all votes in an epoch, it will receive 25% of that epoch's accrued BOLD rewards.

If a qualifying Initiative fails to claim during the epoch following its snapshot, its potential rewards are automatically rolled over into the next epoch's reward pool. This means unclaimed rewards are not lost, but rather redistributed to the next epoch's qualifying Initiatives.

When a successful claim is made, the BOLD tokens are immediately transferred to the Initiative address, and the `onClaimForInitiative`hook is called on the Initiative contract (if implemented). This hook allows Initiatives to execute custom logic upon receiving rewards, making the system highly flexible for different use cases.
Note that Initiatives must be claimed individually - there is no batch claim mechanism. 

### Claim frequency

It’s possible that an Initiative maintains qualifying voting power across multiple consecutive epochs.

However: 

- An Initiative can be claimed for at most once per epoch
- It cannot be claimed for in consecutive epochs. After a claim in epoch `x`, the earliest new epoch in which a claim can be made is epoch `x+2`. 

These constraints are enforced by the Initiative state machine [LINK].



## Bribes
The system includes a base `BribeInitiative`contract that enables Initiative-specific vote incentivization through token rewards ("bribes"). This provides a framework for external parties to encourage votes on specific Initiatives by offering additional rewards on top of the standard BOLD distributions.

The `BribeInitiative` contract is offered as a reference implementation, and is designed to be inherited by custom Initiatives that may implement more specific bribing logic.
### How Bribing Works
External parties can deposit bribes denominated in two tokens:
- BOLD tokens
- One additional ERC20 token specified during Initiative deployment.


These bribes are allocated to specific future epochs via the `depositBribe`function. Users who vote for the Initiative during that epoch become eligible to claim their proportional share of that epoch's bribes.
### Claiming Bribes
Users can claim their share of bribes through the `claimBribes`function. A User's share of an Initiative’s bribes for a given epoch is calculated based on their pro-rata share of the voting power allocated to the Initiative in that epoch. The share is calculated based on the votes accrued at the epoch end.

Bribe claims can be made at any time after the target epoch - bribes do not expire, and are not carried over between epochs.
### Tracking allocations and votes
The contract maintains linked lists to track vote allocations across epochs:
Per-user lists track individual vote history
A global list tracks total vote allocations
Per-user and total LQTY allocations by epoch are recorded in the above lists every time an allocation is made, via the `onAfterAllocateLQTY` hook, callable only by `Governance`. List entries store both LQTY amount and time-weighted offset, allowing accurate calculation of voting power at each epoch.


## Known issues
 
### Path dependency of depositing/withdrawing LQTY
Depositing and withdrawing LQTY when unallocated voting power is non-zero reduces the User’s unallocated voting power. See this section [LINK]

### Trust assumption: Bribe token is non-malicious standard ERC20
Since an arbitrary bribe token may be used, issues can arise if the token is non-standard - e.g. has fee-on-transfer or is rebasing, or indeed if the token is malicious and/or upgradeable.  

Any of the above situatons could result in Users receiving less bribe rewards than expected.

### Trust-assumption: Initiative will not rug voters

The owner of an upgradeable Initiative could arbitrarily change its logic, and thus change the destination of funds to one different from that which was voted for by Users. 

### Vetoed Initiatives and Initiatives that receive votes that are below the treshold cause a loss of emissions to the voted initiatives

Because the system spits rewards in proportion to: `valid_votes / total_votes`, then by definition, Initiatives that Increase the  total_votes without receiving any rewards are "stealing" the rewards from other initiatives. The rewards will be re-queued in the next epoch.


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
