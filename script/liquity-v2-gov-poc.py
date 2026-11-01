#!/usr/bin/env python3
"""
Proof of concept: under the Amsterdam gas schedule (EIP-8037 state gas, plus
EIP-8038's higher storage-write cost for B), the fixed 350,000 gas that Liquity
V2 `Governance` gives every initiative hook no longer pays for the storage the
initiatives write, and Governance ignores the failure:

  A. every `BribeInitiative.onAfterAllocateLQTY` that has to start a new epoch
     runs out of gas, so the initiatives' vote records freeze while Governance
     keeps accepting votes, and bribes are paid from the frozen records;
  B. `VotiumInitiative.onClaimForInitiative` runs out of gas, so the BOLD that
     Governance has just transferred to the initiative is never deposited into
     Votium and stays in the initiative, which has no function to move it.

HOW TO RUN
----------
  1. Set RPC_URL below (or export RPC_URL=...). A mainnet archive RPC that can
     serve state at blocks 26093811, 26098001 and 26143977 is required.
  2. anvil must support `--hardfork amsterdam`. Results were produced with
     anvil 1.8.3, commit cae51ad458f6abb64852b7709eb784352429825d; other
     versions may implement a different Amsterdam gas schedule.
  3. python3 liquity-v2-gov-poc.py        (stdlib only, no dependencies)

Each part runs on a fresh anvil fork, once with `--hardfork osaka` and once
with `--hardfork amsterdam`. Real mainnet transactions are re-sent from their
original senders (impersonated); calldata, senders, gas limits and timestamps
are fetched from the RPC. Nothing is sent to a live network.

Controls at ample gas: the hook always gets exactly 350,000 gas, so the
transaction gas limit cannot lift it. Instead, on the local fork only,
Governance's MIN_GAS_TO_HOOK (the five PUSH3 350000 in its runtime code) is
patched to 1,000,000 with anvil_setCode ("cap patched out"); the hook's gasUsed
in that run is its real in-transaction cost. evm_revert restores the code.

Part A -- votes. Fork at 26093811, the parent of the first `allocateLQTY` of
epoch 74 (0x273d17cf...).
  A0  control: 0x273d17cf with the cap patched out (2**24 gas): the
      BribeInitiative hooks succeed under Amsterdam too.
  A1  gas sweep of 0x273d17cf (plus its original limit and 2**24): under Osaka
      the BribeInitiative hooks succeed whenever the transaction succeeds, under
      Amsterdam they fail whenever it succeeds.
  A2  the first CurveV2GaugeRewards hook of 0x273d17cf: gas used inside the vote
      (callTracer), and the same hook call sent directly from the Governance
      address with 2,000,000 gas (debug_traceCall: frame gas before refunds,
      gas of each SSTORE).
  A3  SentinelBribeInitiative's real briber deposits 600 BOLD for epoch 74 into
      SentinelBribeInitiative (its real per-epoch amount for epochs 58-70) and,
      hypothetically, into CurveV2GaugeRewards. Then the 7 real epoch-74
      allocation transactions are re-sent in order at their original timestamps
      (Osaka: original gas limits; Amsterdam: 2**24 = 16,777,216, the most gas a
      transaction can have without an EIP-8037 state-gas reservoir).
  A4  permanence: the account that moved 25,000 LQTY to CurveV2GaugeRewards
      resets and re-allocates it there (allocateLQTY, 2**24 gas) in the same
      epoch, and again in epoch 75.
  A5  epoch 75: the 5 accounts that removed their votes from
      SentinelBribeInitiative in epoch 74 claim its epoch-74 bribe, and the 3
      accounts that added votes to CurveV2GaugeRewards claim its bribe.
  The other Governance transactions in that window (deposits, withdrawals and
  epoch-73 claims by other accounts, none of which emits AllocateLQTY) are not
  re-sent.

Part B -- VotiumInitiative. Fork at 26143977, the parent of the keeper's first
epoch-75 `claimForInitiative`; the keeper's claims for CurveV2GaugeRewards (two
instances) are re-sent first (controls).
  B1  gas sweep of the real VotiumInitiative claim 0x74b92836 (plus its original
      limit and 2**24): Osaka never strands BOLD, Amsterdam always does when the
      transaction succeeds.
  B2  control: the same claim with the cap patched out (2**24 gas): the hook
      deposits into Votium under both forks; its gasUsed is the real cost
      (debug_traceCall: gas of each SSTORE inside the hook).
  B3  the Votium claim (Osaka: original gas limit; Amsterdam: 2**24), then the
      keeper's SentinelBribeInitiative claim (control).
  B4  permanence: the Votium claim re-sent with 2**24 gas, a claim in the next
      epoch (76, first claim of a Votium round) and in epoch 77 (second claim of
      the round, VotiumInitiative now holding stranded BOLD; also measured with
      the cap patched out) on the same fork.
  B5  the real epoch-73 claim 0x87972c72 (first claim of Votium round 133) at its
      parent block 26098001, with the cap and with the cap patched out.
  0x74b92836 is the second VotiumInitiative claim of Votium round 133 (the
  gauge's incentive array already has an entry) while VotiumInitiative holds no
  BOLD: the cheapest of the configurations measured.

Part H -- history (set SKIP_HISTORY=1 to skip; needs eth_getLogs). Governance's
AllocateLQTY / ClaimForInitiative / RegisterInitiative / UnregisterInitiative
events and the initiatives' DepositBribe events from block 22516133
(Governance deployment) to block 26157611.

anvil does not model the EIP-8037 state-gas reservoir (tx.gas > 2**24); every
transaction here uses at most 2**24 gas, where the reservoir is empty anyway.
"""
import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.request

# ---------------------------------------------------------------------------
# >>>>>>>>>>>>>>>>>>>>>>>>  FILL THIS IN  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
RPC_URL = "<FILL ME IN>"
# ---------------------------------------------------------------------------
RPC_URL = os.environ.get("RPC_URL", RPC_URL)

GOV = "0x807def5e7d057df05c796f4bc75c3fe82bd6eee1"            # Governance
BOLD = "0x6440f144b7e50d6a8439336510312d2f54beb01d"
CURVE = "0xba415afa8fcd65196764b5e08cb4dbf90bee33b4"          # CurveV2GaugeRewards
CURVE_B = "0x0c76eae597afa2aa163a8c845f7e7e870256ac7e"        # CurveV2GaugeRewards (2nd)
SENTINEL = "0x865c61e03b35975d25442f60ce4621db1e349a2f"       # SentinelBribeInitiative
VOTIUM_INI = "0x69efec83296c711db4a403b1ee281e87f99590d6"     # VotiumInitiative
EKUBO = "0xaeaa52a51e90cfe5d862568fdc99bc7510f53e04"          # EkuboInitiative (unregistered)
VOTIUM = "0x63942e31e98f1833a234077f47880a66136a2d1e"         # Votium
NAMES = {CURVE: "CurveV2", CURVE_B: "CurveV2(2)", SENTINEL: "Sentinel", VOTIUM_INI: "Votium", BOLD: "BOLD",
         VOTIUM: "Votium contract",
         EKUBO: "Ekubo", "0xb42448852a1bfc99d66ed53c65e2b49cf954f615": "UniV4Merkl",
         "0xdc6f869d2d34e4aee3e89a51f2af6d54f0f7f690": "0xdc6f869d"}
BRIBE_INITIATIVES = {CURVE, CURVE_B, SENTINEL, VOTIUM_INI, EKUBO}

FORK_A = 26093811
EPOCH74_TXS = [
    "0x273d17cfd30cd76a0d659544576cdc788b3c155634012da0d6c208f03e28aa37",
    "0x01e19b67087d91dca23fa4c9e912d9d15c7cdc43a9d38e0be4748d230bd1a47b",
    "0x3091b994a478c87191fe2c85963fefe88f7564d8c6f3164b093230bce5a7faf6",
    "0x7fd8dbcd706fac86eeb8378940b2efce1166ee68bb51bfc98402122bfb7e447a",
    "0xdb2edcfed7d03a517dae3453c11c73d9d2e397fdcd34ed7014ecfcdc7ce73810",
    "0x25c352825342c0c871f4ae544b95afaac718a4df1b1a9ce091c79b030718b056",
    "0x36b9fd02dae986500a65ab01cbf5096d31ca3ba31d24495e7df2e1100d321f46",
]
BRIBER = "0x32787cd59244581a358a068d52e460eb00df6543"         # SentinelBribeInitiative's real briber
BRIBE = 600 * 10**18
LEAVERS = [  # removed all their SentinelBribeInitiative votes in epoch 74
    "0x847938a29b72e9b7150023c9423b43a760a834fc",
    "0x59512422af0709c7cab8285838975cd8d7c7ce7d",
    "0x943228378d4f29252ddd317faee5b86e01cff2b1",
    "0x0a653bd08e2b0a80d1d212d33032953db8298efd",
    "0x561a8431b23fe6a524ce874a029cdaadc9642bf4",
]
JOINERS = [  # added CurveV2GaugeRewards votes in epoch 74
    "0x847938a29b72e9b7150023c9423b43a760a834fc",
    "0x636df4bd62e1eb3477c0dbafc8cd8c5dd8b3a972",
    "0x59512422af0709c7cab8285838975cd8d7c7ce7d",
]
REVOTER = "0x847938a29b72e9b7150023c9423b43a760a834fc"        # moved 25,000 LQTY to CurveV2 in epoch 74

QUEST = "0xa58fbe38aab33b9fadef1b5aaff4d7bc27c43ad4"            # QuestInitiative (unregistered)
BALANCER = "0x6a1d08b715a79bbb0a2d2e1927e96c18a345586a"         # BalancerGaugeRewards (unregistered)
NAMES.update({QUEST: "Quest", BALANCER: "Balancer"})
ALL_BRIBE_INITIATIVES = [CURVE, CURVE_B, SENTINEL, VOTIUM_INI, EKUBO, QUEST, BALANCER]
HISTORY_FROM, HISTORY_TO = 22516133, 26157611    # Governance deployment .. block used for the history scan

FORK_B = 26143977
KEEPER_CLAIMS = [  # the keeper's real epoch-75 claimForInitiative txs, in mainnet order
    ("CurveV2", "0xa0b26d298a11470697dad2ebeeaeb7e9b587b52205fa87d9cee224462f219bd5"),
    ("CurveV2(2)", "0x9a11a4c8dea68c8abf4d50ead9263613b24cf66c1e906d5e29fa4f711fa752e5"),
    ("Votium", "0x74b9283625b9f1cc959ee8b586f2c248637465bb4c0591874501477fbed1505b"),
    ("Sentinel", "0x8d27d4a7919a12ad053141b4979eaab961dccea34f762c9951573f03b4765b1e"),
]
ROUND_START_CLAIM = "0x87972c728f3224fe0ef37c77f004845004f04ad3febc807aa7cb2df5b1ddae1d"  # epoch-73 Votium claim

GAS_MAX = 2**24                                   # 16,777,216: no state-gas reservoir
HOOK_GAS = 350_000                                # Governance.MIN_GAS_TO_HOOK
UNCAPPED = 1_000_000                              # patched hook cap of the controls
SWEEP_A = list(range(900_000, 2_500_001, 10_000))
SWEEP_B = list(range(450_000, 900_001, 5_000))

SEL = {  # 4-byte selectors (keccak256 of the signature)
    "balanceOf": "70a08231",                  # balanceOf(address)
    "approve": "095ea7b3",                    # approve(address,uint256)
    "transfer": "a9059cbb",                   # transfer(address,uint256)
    "depositBribe": "5bab17b1",               # depositBribe(uint256,uint256,uint256)
    "claimBribes": "81c4fea5",                # claimBribes((uint256,uint256,uint256)[])
    "getMostRecentUserEpoch": "e6fc3786",     # getMostRecentUserEpoch(address)
    "getMostRecentTotalEpoch": "f0f2698d",    # getMostRecentTotalEpoch()
    "lqtyAllocatedByUserAtEpoch": "e89946e2",  # lqtyAllocatedByUserAtEpoch(address,uint256)
    "lqtyAllocatedByUserToInitiative": "91050f40",  # lqtyAllocatedByUserToInitiative(address,address)
    "epoch": "900cf0cf",                      # epoch()
    "EPOCH_START": "46d62a63",                # EPOCH_START()
    "EPOCH_DURATION": "a70b9f0c",             # EPOCH_DURATION()
    "remainder": "a0684251",                  # remainder()
    "allocateLQTY": "82a15be1",               # allocateLQTY(address[],address[],int256[],int256[])
    "claimForInitiative": "c20fb59e",         # claimForInitiative(address)
    "onClaimForInitiative": "1e18de1a",       # onClaimForInitiative(uint256,uint256)
    "activeRound": "11f0281e",                # Votium.activeRound()
    "incentivesLength": "dd07b719",           # Votium.incentivesLength(uint256,address)
    "gauge": "a6f19c84",                      # VotiumInitiative.gauge()
}
T_ALLOCATE = "0x361311c5372a81d4ab4bce0bf1b7dbfc61da467667c2097deb69b4b24bc12d28"  # AllocateLQTY(address,address,int256,int256,uint256,uint8)
T_CLAIM = "0x023acf63ebe0add874abd78d1a9b96f3384a3128bfdb97bf6c23e91f3d2e6e5a"     # ClaimForInitiative(address,uint256,uint256,uint8)
T_DEPOSIT_VOTIUM = "0xee9bb9d64dc7a862b35597075c1e50fe65bfeb95c00fbfd71543605a5bcc005b"  # DepositIntoVotium(uint256)
T_REGISTER = "0x40318a3f9214cb8917bf252f11a84a919bf9acee5e9b12049e1c99cb52b3b71c"   # RegisterInitiative(address,address,uint256,uint8)
T_UNREGISTER = "0x4b2a06fb31ab5670eed8302066f58582b640ec5a17d06ddd383d30e3e11f1b64"  # UnregisterInitiative(address,uint256,uint8)
T_DEPOSIT_BRIBE = "0x8da751404c1c12bd225230d318ca0913aab7a5f98c004ae97cf1b7072e7f119d"  # DepositBribe(address,uint256,uint256,uint256)
HOOK = {0: "Failed", 1: "Succeeded", 2: "NotCalled"}


# --------------------------------------------------------------------------- RPC / anvil
def rpc(url, method, params, retries=1):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, body, {"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=600) as resp:
                out = json.loads(resp.read())
            if "error" in out:
                raise RuntimeError(f"{method}: {out['error']}")
            return out["result"]
        except Exception:
            if attempt == retries - 1:
                raise
            time.sleep(2 + 2 * attempt)


def upstream(method, params):
    return rpc(RPC_URL, method, params, retries=5)


def fetch_tx(h):
    tx = upstream("eth_getTransactionByHash", [h])
    blk = upstream("eth_getBlockByNumber", [tx["blockNumber"], False])
    return {"hash": h, "from": tx["from"], "to": tx["to"], "input": tx["input"], "gas": int(tx["gas"], 16),
            "block": int(tx["blockNumber"], 16), "ts": int(blk["timestamp"], 16)}


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Anvil:
    def __init__(self, block, hardfork):
        self.port = free_port()
        self.url = f"http://127.0.0.1:{self.port}"
        self.proc = subprocess.Popen(
            ["anvil", "--fork-url", RPC_URL, "--fork-block-number", str(block), "--hardfork", hardfork,
             "--port", str(self.port), "--silent"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(240):
            try:
                self.call("eth_blockNumber", [])
                break
            except Exception:
                if self.proc.poll() is not None:
                    raise RuntimeError("anvil exited; does it support this --hardfork?")
                time.sleep(0.5)
        else:
            raise RuntimeError("anvil did not start")
        self.snap = None

    def call(self, method, params):
        return rpc(self.url, method, params)

    def close(self):
        self.proc.kill()
        self.proc.wait()

    def revert(self):
        """Back to the last snapshot, and take a new one (anvil consumes snapshots)."""
        assert self.call("evm_revert", [self.snap])
        self.snap = self.call("evm_snapshot", [])

    def mark(self):
        self.snap = self.call("evm_snapshot", [])

    def warm(self, frm, to, data):
        """eth_call the transaction once so anvil caches the forked state it reads before the snapshot is
        taken (evm_revert drops state fetched after the snapshot, which makes every sweep run re-fetch it)."""
        try:
            self.call("eth_call", [{"from": frm, "to": to, "data": data, "gas": hex(GAS_MAX)}, "latest"])
        except RuntimeError:
            pass

    def view(self, to, data):
        return self.call("eth_call", [{"to": to, "data": data}, "latest"])

    def uint(self, to, sel, *args):
        return int(self.view(to, "0x" + SEL[sel] + "".join(enc(x) for x in args))[:66], 16)

    def send(self, frm, to, data, gas, ts=None):
        self.call("anvil_impersonateAccount", [frm])
        self.call("anvil_setBalance", [frm, hex(10**21)])
        if ts is not None:
            self.call("evm_setNextBlockTimestamp", [ts])
        h = self.call("eth_sendTransaction", [{"from": frm, "to": to, "data": data, "gas": hex(gas)}])
        for _ in range(1200):
            r = self.call("eth_getTransactionReceipt", [h])
            if r:
                return r
            time.sleep(0.1)
        raise RuntimeError("receipt timeout")

    def warp_to_epoch_start(self, offset=60):
        es, ed, ep = self.uint(GOV, "EPOCH_START"), self.uint(GOV, "EPOCH_DURATION"), self.uint(GOV, "epoch")
        self.call("evm_setNextBlockTimestamp", [es + ep * ed + offset])
        self.call("evm_mine", [])
        return self.uint(GOV, "epoch")

    def uncap(self):
        """Control only: replace Governance's five PUSH3 350000 (MIN_GAS_TO_HOOK) with PUSH3 1,000,000."""
        code = bytearray(bytes.fromhex(self.call("eth_getCode", [GOV, "latest"])[2:]))
        i = n = 0
        while i < len(code):
            k = code[i] - 0x5f if 0x60 <= code[i] <= 0x7f else 0      # PUSH1..PUSH32 data length
            if k == 3 and int.from_bytes(code[i + 1:i + 4], "big") == HOOK_GAS:
                code[i + 1:i + 4] = UNCAPPED.to_bytes(3, "big")
                n += 1
            i += 1 + k
        assert n == 5, n
        self.call("anvil_setCode", [GOV, "0x" + code.hex()])

    def hook_sstores(self, frm, to, data, initiative):
        """Gas cost of each SSTORE inside the uncapped hook of a call (debug_traceCall, struct logger)."""
        logs = self.call("debug_traceCall", [{"from": frm, "to": to, "data": data, "gas": hex(GAS_MAX)}, "latest",
                                             {"disableStorage": True}])["structLogs"]
        i = next(i for i, x in enumerate(logs) if x["op"] == "CALL" and x["depth"] == 1
                 and int(x["stack"][-1], 16) == UNCAPPED and int(x["stack"][-2], 16) == int(initiative, 16))
        out = []
        for x in logs[i + 1:]:
            if x["depth"] == 1:
                break
            if x["op"] == "SSTORE":
                out.append(x["gasCost"])
        return out

    def hook_frames(self, txh, target=None, cap=HOOK_GAS):
        """callTracer frames of Governance -> initiative calls made with exactly `cap` gas."""
        tr = self.call("debug_traceTransaction", [txh, {"tracer": "callTracer"}])
        out, stack = [], [tr]
        while stack:
            c = stack.pop(0)
            if (c.get("from") or "").lower() == GOV and c.get("type") == "CALL" \
                    and int(c.get("gas", "0x0"), 16) == cap \
                    and (target is None or (c.get("to") or "").lower() == target):
                out.append({"to": c["to"].lower(), "used": int(c.get("gasUsed", "0x0"), 16),
                            "error": c.get("error"), "input": c.get("input"),
                            "calls": [(NAMES.get((x.get("to") or "").lower(), (x.get("to") or "")[:10]),
                                       (x.get("input") or "")[:10], int(x.get("gas", "0x0"), 16),
                                       int(x.get("gasUsed", "0x0"), 16), x.get("error"))
                                      for x in c.get("calls", []) or []]})
            stack[0:0] = c.get("calls", []) or []
        return out

    def frame_cost(self, frm, to, data, gas):
        """Gas used inside a direct call frame before refunds (struct logger), and the cost of each SSTORE in it."""
        t = self.call("debug_traceCall", [{"from": frm, "to": to, "data": data, "gas": hex(gas)}, "latest",
                                          {"disableStorage": True, "disableStack": True}])
        logs = t["structLogs"]
        last = [x for x in logs if x["depth"] == 1][-1]
        return {"used": logs[0]["gas"] - (last["gas"] - last["gasCost"]), "failed": t["failed"],
                "sstore": [x["gasCost"] for x in logs if x["op"] == "SSTORE" and x["depth"] == 1]}


# --------------------------------------------------------------------------- encoding / decoding
def enc(x):
    if isinstance(x, str):
        return x[2:].lower().rjust(64, "0")
    return format(x % 2**256, "064x")


def calldata(sel, *args):
    return "0x" + SEL[sel] + "".join(enc(x) for x in args)


def ok(r):
    return int(r["status"], 16) == 1


def words(data):
    d = data[2:]
    return [int(d[i:i + 64], 16) for i in range(0, len(d), 64)]


def alloc_hooks(r):
    """AllocateLQTY(user idx, initiative idx, deltaVoteLQTY, deltaVetoLQTY, atEpoch, hookStatus) from Governance."""
    return [("0x" + lg["topics"][2][-40:], words(lg["data"])[3]) for lg in r["logs"]
            if lg["address"].lower() == GOV and lg["topics"][0] == T_ALLOCATE]


def bribe_hooks(r):
    return [s for ini, s in alloc_hooks(r) if ini in BRIBE_INITIATIVES]


def claim_events(r):
    """ClaimForInitiative(initiative idx, bold, forEpoch, hookStatus) from Governance."""
    out = []
    for lg in r["logs"]:
        if lg["address"].lower() == GOV and lg["topics"][0] == T_CLAIM:
            w = words(lg["data"])
            out.append(("0x" + lg["topics"][1][-40:], w[0], w[1], w[2]))
    return out


def votium_deposits(r):
    return [words(lg["data"])[0] for lg in r["logs"]
            if lg["address"].lower() == VOTIUM_INI and lg["topics"][0] == T_DEPOSIT_VOTIUM]


def bold(x):
    return f"{x / 1e18:,.4f}"


def hooks_str(r):
    return ", ".join(f"{NAMES.get(i, i[:10])}={HOOK[s]}" for i, s in alloc_hooks(r))


def allocate_calldata(initiative, lqty):
    """allocateLQTY([initiative], [initiative], [lqty], [0]): reset the initiative and re-allocate lqty to it."""
    return ("0x" + SEL["allocateLQTY"] + enc(128) + enc(192) + enc(256) + enc(320)
            + enc(1) + enc(initiative) + enc(1) + enc(initiative) + enc(1) + enc(lqty) + enc(1) + enc(0))


def claim_bribe(a, user, initiative, ep):
    """claimBribes([(ep, prevUserEpoch, prevTotalEpoch)]) using the initiative's own head pointers."""
    pu = a.uint(initiative, "getMostRecentUserEpoch", user)
    pt = a.uint(initiative, "getMostRecentTotalEpoch")
    data = "0x" + SEL["claimBribes"] + enc(32) + enc(1) + enc(ep) + enc(pu) + enc(pt)
    b0 = a.uint(BOLD, "balanceOf", user)
    r = a.send(user, initiative, data, 1_000_000)
    return {"user": user, "ok": ok(r), "bold": a.uint(BOLD, "balanceOf", user) - b0, "hints": (pu, pt)}


def records(a, user, initiative):
    head = a.uint(initiative, "getMostRecentUserEpoch", user)
    return {"gov": a.uint(GOV, "lqtyAllocatedByUserToInitiative", user, initiative), "head": head,
            "lqty": a.uint(initiative, "lqtyAllocatedByUserAtEpoch", user, head)}


# --------------------------------------------------------------------------- Part A: votes
def part_a(hf, txs, fork_ts):
    a = Anvil(FORK_A, hf)
    res = {"hardfork": hf}
    try:
        t0 = txs[0]
        ep = a.uint(GOV, "epoch")
        res["epoch"] = ep
        a.warm(t0["from"], t0["to"], t0["input"])
        a.mark()
        code0 = a.call("eth_getCode", [GOV, "latest"])
        # A0: control -- the same vote with the hook cap patched out
        a.uncap()
        r = a.send(t0["from"], t0["to"], t0["input"], GAS_MAX, ts=t0["ts"])
        res["uncapped"] = {"ok": ok(r), "bribe_hooks": bribe_hooks(r), "head": a.uint(CURVE, "getMostRecentTotalEpoch"),
                           "used": [f["used"] for f in a.hook_frames(r["transactionHash"], CURVE, UNCAPPED)]}
        a.revert()
        assert a.call("eth_getCode", [GOV, "latest"]) == code0
        # A1: gas sweep of the first epoch-74 vote
        sweep = []
        for g in sorted(set(SWEEP_A + [t0["gas"], GAS_MAX])):
            r = a.send(t0["from"], t0["to"], t0["input"], g, ts=t0["ts"])
            sweep.append({"gas": g, "ok": ok(r), "bribe_hooks": bribe_hooks(r)})
            a.revert()
        res["sweep"] = sweep
        # A2: the first CurveV2GaugeRewards hook, capped (in the vote) and uncapped (direct call)
        r = a.send(t0["from"], t0["to"], t0["input"], GAS_MAX, ts=t0["ts"])
        capped = a.hook_frames(r["transactionHash"], CURVE)[0]
        a.revert()
        res["hook_capped"] = {"used": capped["used"], "error": capped["error"]}
        res["hook_uncapped"] = a.frame_cost(GOV, CURVE, capped["input"], 2_000_000)
        # A3: epoch-74 bribes, then the 7 real epoch-74 allocation transactions in order
        ts = fork_ts   # mine the deposits between the fork block and the first vote
        for ini in (SENTINEL, CURVE):
            ts += 1
            assert ok(a.send(BRIBER, BOLD, calldata("approve", ini, BRIBE), 300_000, ts=ts))
            ts += 1
            assert ok(a.send(BRIBER, ini, calldata("depositBribe", BRIBE, 0, ep), 1_000_000, ts=ts)), "depositBribe"
        assert ts < t0["ts"]
        rows = []
        for t in txs:
            gas = t["gas"] if hf == "osaka" else GAS_MAX
            r = a.send(t["from"], t["to"], t["input"], gas, ts=t["ts"])
            rows.append({"hash": t["hash"], "gas": gas, "ok": ok(r), "used": int(r["gasUsed"], 16),
                         "hooks": alloc_hooks(r), "hooks_str": hooks_str(r)})
        res["replay"] = rows
        res["heads"] = {NAMES[i]: a.uint(i, "getMostRecentTotalEpoch") for i in (SENTINEL, CURVE, VOTIUM_INI, EKUBO)}
        res["records"] = {"leaver 0x0a653bd0 / Sentinel": records(a, LEAVERS[3], SENTINEL),
                          "joiner 0x847938a2 / CurveV2": records(a, REVOTER, CURVE)}
        # A4: same-epoch re-allocation (undone afterwards)
        lqty = a.uint(GOV, "lqtyAllocatedByUserToInitiative", REVOTER, CURVE)
        a.mark()
        r = a.send(REVOTER, GOV, allocate_calldata(CURVE, lqty), GAS_MAX)
        res["realloc_same_epoch"] = {"ok": ok(r), "hooks": [s for i, s in alloc_hooks(r) if i == CURVE],
                                     "head": a.uint(CURVE, "getMostRecentTotalEpoch"), "lqty": lqty}
        a.revert()
        # A5: epoch 75 -- claim the epoch-74 bribes
        res["epoch_after_warp"] = a.warp_to_epoch_start()
        res["leaver_claims"] = [claim_bribe(a, u, SENTINEL, ep) for u in LEAVERS]
        res["joiner_claims"] = [claim_bribe(a, u, CURVE, ep) for u in JOINERS]
        # A4 (cont.): re-allocation in epoch 75
        r = a.send(REVOTER, GOV, allocate_calldata(CURVE, lqty), GAS_MAX)
        res["realloc_next_epoch"] = {"ok": ok(r), "hooks": [s for i, s in alloc_hooks(r) if i == CURVE],
                                     "head": a.uint(CURVE, "getMostRecentTotalEpoch")}
    finally:
        a.close()
    return res


# --------------------------------------------------------------------------- Part B: VotiumInitiative
def votium_claim(a, t, gas, ts=True, cap=HOOK_GAS):
    """Send a claimForInitiative transaction; read Governance's ClaimForInitiative log, VotiumInitiative's
    DepositIntoVotium log, the hook frame (callTracer), BOLD balances, `remainder` and the Votium round."""
    vb0, vt0 = a.uint(BOLD, "balanceOf", VOTIUM_INI), a.uint(BOLD, "balanceOf", VOTIUM)
    rem0 = a.uint(VOTIUM_INI, "remainder")
    r = a.send(t["from"], t["to"], t["input"], gas, ts=t["ts"] if ts else None)
    fr = a.hook_frames(r["transactionHash"], cap=cap) if ok(r) else []
    deps = votium_deposits(r)
    rnd = a.uint(VOTIUM, "activeRound")
    gauge = "0x" + a.view(VOTIUM_INI, "0x" + SEL["gauge"])[-40:]
    return {"gas": gas, "ok": ok(r), "used": int(r["gasUsed"], 16), "claims": claim_events(r),
            "deposits": deps, "hook_used": [f["used"] for f in fr],
            "hook_error": [f["error"] for f in fr], "hook_calls": [f["calls"] for f in fr],
            "held_before": vb0, "stranded": a.uint(BOLD, "balanceOf", VOTIUM_INI) - vb0,
            "to_votium": a.uint(BOLD, "balanceOf", VOTIUM) - vt0,
            "remainder_delta": a.uint(VOTIUM_INI, "remainder") - rem0,
            "round": rnd, "round_incentives_before": a.uint(VOTIUM, "incentivesLength", rnd, gauge) - len(deps)}


def part_b(hf, claims):
    a = Anvil(FORK_B, hf)
    res = {"hardfork": hf, "controls": {}}
    try:
        def gas_for(t):
            return t["gas"] if hf == "osaka" else GAS_MAX

        for name, t in claims[:2]:
            res["controls"][name] = votium_claim(a, t, gas_for(t))
        vt = claims[2][1]
        a.warm(vt["from"], vt["to"], vt["input"])
        a.mark()
        code0 = a.call("eth_getCode", [GOV, "latest"])
        # B1: gas sweep of the Votium claim
        sweep = []
        for g in sorted(set(SWEEP_B + [vt["gas"], GAS_MAX])):
            sweep.append(votium_claim(a, vt, g))
            a.revert()
        res["sweep"] = sweep
        # B2: control -- the same claim with the hook cap patched out
        a.uncap()
        res["uncapped_sstores"] = a.hook_sstores(vt["from"], vt["to"], vt["input"], VOTIUM_INI)
        res["uncapped"] = votium_claim(a, vt, GAS_MAX, cap=UNCAPPED)
        a.revert()
        assert a.call("eth_getCode", [GOV, "latest"]) == code0
        # B3: the Votium claim, then the keeper's Sentinel claim (control)
        res["votium"] = votium_claim(a, vt, gas_for(vt))
        res["controls"]["Sentinel"] = votium_claim(a, claims[3][1], gas_for(claims[3][1]))
        # B4: permanence -- re-claim in the same epoch, then claim in the next two epochs
        res["reclaim"] = votium_claim(a, vt, GAS_MAX, ts=False)
        nxt = {"from": vt["from"], "to": GOV, "input": calldata("claimForInitiative", VOTIUM_INI), "ts": None}
        res["epoch_after_warp"] = a.warp_to_epoch_start()
        res["next_epoch"] = votium_claim(a, nxt, GAS_MAX)
        res["epoch_after_warp2"] = a.warp_to_epoch_start()
        a.mark()
        a.uncap()
        res["third_epoch_uncapped"] = votium_claim(a, nxt, GAS_MAX, cap=UNCAPPED)
        a.revert()
        res["third_epoch"] = votium_claim(a, nxt, GAS_MAX)
        res["votium_ini_balance"] = a.uint(BOLD, "balanceOf", VOTIUM_INI)
    finally:
        a.close()
    return res


def part_b5(hf, t):
    """The real epoch-73 VotiumInitiative claim (first of Votium round 133) at its parent block."""
    a = Anvil(t["block"] - 1, hf)
    try:
        a.warm(t["from"], t["to"], t["input"])
        a.mark()
        res = {"hardfork": hf, "block": t["block"] - 1,
               "capped": votium_claim(a, t, t["gas"] if hf == "osaka" else GAS_MAX)}
        a.revert()
        a.uncap()
        res["uncapped"] = votium_claim(a, t, GAS_MAX, cap=UNCAPPED)
    finally:
        a.close()
    return res


# --------------------------------------------------------------------------- history (event logs)
def get_logs(address, topic0):
    out, b, step = [], HISTORY_FROM, 1_000_000
    while b <= HISTORY_TO:
        e = min(b + step - 1, HISTORY_TO)
        try:
            out += rpc(RPC_URL, "eth_getLogs", [{"address": address, "topics": [topic0], "fromBlock": hex(b),
                                                 "toBlock": hex(e)}], retries=2)
            b = e + 1
        except Exception:
            if step <= 2_000:
                raise
            step = max(2_000, step // 4)
    return out


def history():
    h = {}
    alloc = get_logs(GOV, T_ALLOCATE)
    per = {}
    for lg in alloc:
        ini = "0x" + lg["topics"][2][-40:]
        st = words(lg["data"])[3]
        per.setdefault(ini, {}).setdefault(st, 0)
        per[ini][st] += 1
    h["alloc_events"] = len(alloc)
    h["bribe_alloc_hooks"] = {NAMES[i]: per.get(i, {}) for i in ALL_BRIBE_INITIATIVES}
    h["bribe_alloc_failed"] = sum(per.get(i, {}).get(0, 0) for i in ALL_BRIBE_INITIATIVES)
    h["other_alloc_failed"] = {i: c[0] for i, c in per.items() if i not in ALL_BRIBE_INITIATIVES and c.get(0)}
    claims = [("0x" + lg["topics"][1][-40:],) + tuple(words(lg["data"])[:3]) for lg in get_logs(GOV, T_CLAIM)]
    bc = [c for c in claims if c[0] in ALL_BRIBE_INITIATIVES]
    h["bribe_claims"] = len(bc)
    h["bribe_claims_failed"] = sum(1 for c in bc if c[3] != 1)
    h["votium_claims"] = [(c[2], c[1], c[3]) for c in claims if c[0] == VOTIUM_INI]
    reg = {"0x" + lg["data"][26:66]: words(lg["data"])[2] for lg in get_logs(GOV, T_REGISTER)}
    unreg = {"0x" + lg["data"][26:66]: words(lg["data"])[1] for lg in get_logs(GOV, T_UNREGISTER)}
    h["status"] = {NAMES[i]: (reg.get(i), unreg.get(i)) for i in ALL_BRIBE_INITIATIVES}
    dep = {}
    for lg in get_logs(ALL_BRIBE_INITIATIVES, T_DEPOSIT_BRIBE):
        w = words(lg["data"])
        d = dep.setdefault(NAMES[lg["address"].lower()], {"n": 0, "bold": 0, "token": 0, "epochs": []})
        d["n"] += 1
        d["bold"] += w[1]
        d["token"] += w[2]
        d["epochs"].append(w[3])
    h["bribes"] = dep
    return h


def print_history(h):
    print(f"\n[HISTORY] mainnet event logs, blocks {HISTORY_FROM:,}-{HISTORY_TO:,}")
    print(f"  AllocateLQTY events: {h['alloc_events']:,}; hooks of BribeInitiatives (0=Failed 1=Succeeded 2=NotCalled): "
          f"{h['bribe_alloc_hooks']}")
    print(f"  Failed BribeInitiative allocation hooks: {h['bribe_alloc_failed']}; failed hooks of other initiatives: "
          f"{h['other_alloc_failed']}")
    print(f"  ClaimForInitiative events of BribeInitiatives: {h['bribe_claims']}, hooks not Succeeded: "
          f"{h['bribe_claims_failed']}")
    vc = h["votium_claims"]
    if vc:
        print(f"  VotiumInitiative claims: {len(vc)}, epochs {vc[0][0]}-{vc[-1][0]}, total {bold(sum(c[1] for c in vc))} BOLD, "
              f"hooks {sorted({HOOK[c[2]] for c in vc})}; per epoch: " + ", ".join(f"{c[0]}: {bold(c[1])}" for c in vc))
    print("  registered at epoch / unregistered at epoch: " + ", ".join(f"{k} {v[0]}/{v[1]}" for k, v in h["status"].items()))
    for k, d in h["bribes"].items():
        print(f"  DepositBribe {k}: {d['n']} deposits, {bold(d['bold'])} BOLD + {bold(d['token'])} bribe token, "
              f"epochs {min(d['epochs'])}-{max(d['epochs'])}")


# --------------------------------------------------------------------------- report
def lowest(rows):
    return f"{rows[0]['gas']:,}" if rows else "-"


def print_part_a(r):
    hf = r["hardfork"].upper()
    print(f"\n[{hf}] Part A -- fork {FORK_A}, epoch {r['epoch']}")
    ok_rows = [s for s in r["sweep"] if s["ok"]]
    drop = [s for s in ok_rows if any(h == 0 for h in s["bribe_hooks"])]
    rec = [s for s in ok_rows if s["bribe_hooks"] and all(h == 1 for h in s["bribe_hooks"])]
    print(f"  A1 sweep of {EPOCH74_TXS[0][:10]} gas {SWEEP_A[0]:,}-{SWEEP_A[-1]:,} step {SWEEP_A[1] - SWEEP_A[0]:,}"
          f" plus {EPOCH74_GAS0:,} (original) and {GAS_MAX:,}: {len(r['sweep'])} runs, "
          f"{len(r['sweep']) - len(ok_rows)} reverted, {len(rec)} succeeded with all BribeInitiative hooks Succeeded, "
          f"{len(drop)} succeeded with a BribeInitiative hook Failed; lowest successful limit {lowest(ok_rows)}")
    for s in r["sweep"]:
        if s["gas"] in (EPOCH74_GAS0, GAS_MAX):
            print(f"      gas {s['gas']:>10,}: tx ok={s['ok']} BribeInitiative hooks={[HOOK[h] for h in s['bribe_hooks']]}")
    u = r["uncapped"]
    print(f"  A0 control, {EPOCH74_TXS[0][:10]} with the hook cap patched to {UNCAPPED:,} (gas 2**24): tx ok={u['ok']} "
          f"BribeInitiative hooks={[HOOK[h] for h in u['bribe_hooks']]} CurveV2 hooks gasUsed={u['used']} "
          f"CurveV2 head={u['head']}")
    hc, hu = r["hook_capped"], r["hook_uncapped"]
    print(f"  A2 first CurveV2GaugeRewards hook of {EPOCH74_TXS[0][:10]}: in the vote gasUsed={hc['used']:,} of "
          f"{HOOK_GAS:,} error={hc['error']}; direct call with 2,000,000 gas: used before refunds={hu['used']:,} "
          f"failed={hu['failed']} SSTORE costs={hu['sstore']}")
    print(f"  A3 7 real epoch-74 allocation txs ({'original gas limits' if r['hardfork'] == 'osaka' else 'gas 2**24'}):")
    for x in r["replay"]:
        print(f"      {x['hash'][:10]} gas={x['gas']:>10,} ok={x['ok']} gasUsed={x['used']:>9,}  {x['hooks_str']}")
    print(f"      getMostRecentTotalEpoch(): {r['heads']}")
    for k, v in r["records"].items():
        print(f"      {k}: Governance voteLQTY={v['gov'] / 1e18:,.0f}; initiative head epoch={v['head']} "
              f"lqty={v['lqty'] / 1e18:,.0f}")
    s = r["realloc_same_epoch"]
    print(f"  A4 {REVOTER[:10]} re-allocates {s['lqty'] / 1e18:,.0f} LQTY to CurveV2 in epoch {r['epoch']}: "
          f"tx ok={s['ok']} hooks={[HOOK[h] for h in s['hooks']]} CurveV2 head={s['head']}")
    n = r["realloc_next_epoch"]
    print(f"     same re-allocation in epoch {r['epoch_after_warp']}: tx ok={n['ok']} "
          f"hooks={[HOOK[h] for h in n['hooks']]} CurveV2 head={n['head']}")
    print(f"  A5 epoch-{r['epoch']} bribe claims (600 BOLD each) in epoch {r['epoch_after_warp']}:")
    for label, lst in (("Sentinel, account that left", r["leaver_claims"]), ("CurveV2, account that joined", r["joiner_claims"])):
        for c in lst:
            print(f"      {label} {c['user'][:10]}: hints {c['hints']} claim ok={c['ok']} BOLD={bold(c['bold'])}")
        print(f"      {label}: total {bold(sum(c['bold'] for c in lst))} BOLD, "
              f"{sum(c['ok'] for c in lst)}/{len(lst)} claims succeed")


def vc_str(c):
    return (f"Votium round {c['round']} (gauge incentives before: {c['round_incentives_before']}), VotiumInitiative "
            f"held {bold(c['held_before'])} BOLD: tx ok={c['ok']} claim={[(bold(x[1]), x[2], HOOK[x[3]]) for x in c['claims']]} "
            f"hook gasUsed={c['hook_used']} error={c['hook_error']} DepositIntoVotium={[bold(x) for x in c['deposits']]} "
            f"stranded delta={bold(c['stranded'])}")


def print_calls(c):
    for calls in c["hook_calls"]:
        print("     calls made by the hook (to, selector, gas, gasUsed, error): " + "; ".join(
            f"({n}, {sel}, {g:,}, {u:,}, {e})" for n, sel, g, u, e in calls))


def print_part_b(r):
    hf = r["hardfork"].upper()
    print(f"\n[{hf}] Part B -- fork {FORK_B}")
    ok_rows = [s for s in r["sweep"] if s["ok"]]
    strand = [s for s in ok_rows if s["stranded"] > 0 and not s["deposits"]]
    dep = [s for s in ok_rows if s["deposits"] and s["stranded"] == 0]
    print(f"  B1 sweep of {KEEPER_CLAIMS[2][1][:10]} gas {SWEEP_B[0]:,}-{SWEEP_B[-1]:,} step {SWEEP_B[1] - SWEEP_B[0]:,}"
          f" plus {VOTIUM_GAS0:,} (original) and {GAS_MAX:,}: {len(r['sweep'])} runs, "
          f"{len(r['sweep']) - len(ok_rows)} reverted, {len(dep)} deposited into Votium, "
          f"{len(strand)} succeeded with the BOLD stranded; lowest successful limit {lowest(ok_rows)}")
    for s in r["sweep"]:
        if s["gas"] in (VOTIUM_GAS0, GAS_MAX):
            print(f"      gas {s['gas']:>10,}: tx ok={s['ok']} hook={[HOOK[c[3]] for c in s['claims']]} "
                  f"stranded={bold(s['stranded'])}")
    print(f"  B2 control, the same claim with the hook cap patched to {UNCAPPED:,} (gas 2**24): " + vc_str(r["uncapped"]))
    print_calls(r["uncapped"])
    print(f"     SSTORE costs inside the hook (debug_traceCall): {r['uncapped_sstores']}")
    for name, c in r["controls"].items():
        print(f"  control {name:10s}: tx ok={c['ok']} claim={[(bold(x[1]), x[2], HOOK[x[3]]) for x in c['claims']]} "
              f"hook gasUsed={c['hook_used']}")
    v = r["votium"]
    print(f"  B3 Votium claim gas={v['gas']:,}: gasUsed={v['used']:,} " + vc_str(v)
          + f"; BOLD into Votium={bold(v['to_votium'])} remainder delta={v['remainder_delta']}")
    print_calls(v)
    c = r["reclaim"]
    print(f"  B4 re-claim with 2**24 gas: tx ok={c['ok']} ClaimForInitiative events={len(c['claims'])} "
          f"stranded delta={bold(c['stranded'])}")
    print(f"     claim in epoch {r['epoch_after_warp']}: " + vc_str(r["next_epoch"]))
    print(f"     claim in epoch {r['epoch_after_warp2']}, cap patched to {UNCAPPED:,} (snapshot, undone): "
          + vc_str(r["third_epoch_uncapped"]))
    print(f"     claim in epoch {r['epoch_after_warp2']}: " + vc_str(r["third_epoch"])
          + f"; VotiumInitiative now holds {bold(r['votium_ini_balance'])} BOLD")


def print_part_b5(r):
    print(f"\n[{r['hardfork'].upper()}] B5 -- real epoch-73 VotiumInitiative claim {ROUND_START_CLAIM[:10]}, fork {r['block']}")
    print(f"  with the cap (gas {r['capped']['gas']:,}): " + vc_str(r["capped"]))
    print(f"  cap patched to {UNCAPPED:,} (gas 2**24): " + vc_str(r["uncapped"]))


def main():
    global EPOCH74_GAS0, VOTIUM_GAS0
    if "<FILL ME IN>" in RPC_URL or not RPC_URL:
        sys.exit("ERROR: set RPC_URL at the top of this file, or export RPC_URL=<mainnet archive rpc>.")
    if shutil.which("anvil") is None:
        sys.exit("ERROR: anvil not found on PATH.")
    print(subprocess.run(["anvil", "--version"], capture_output=True, text=True).stdout.strip()
          .splitlines()[:2])
    txs = [fetch_tx(h) for h in EPOCH74_TXS]
    claims = [(n, fetch_tx(h)) for n, h in KEEPER_CLAIMS]
    EPOCH74_GAS0, VOTIUM_GAS0 = txs[0]["gas"], claims[2][1]["gas"]
    rc = upstream("eth_getTransactionReceipt", [KEEPER_CLAIMS[2][1]])
    votium_amount = claim_events(rc)[0][1]

    fork_ts = int(upstream("eth_getBlockByNumber", [hex(FORK_A), False])["timestamp"], 16)
    A = {hf: part_a(hf, txs, fork_ts) for hf in ("osaka", "amsterdam")}
    for hf in A:
        print_part_a(A[hf])
    Bp = {hf: part_b(hf, claims) for hf in ("osaka", "amsterdam")}
    for hf in Bp:
        print_part_b(Bp[hf])
    t73 = fetch_tx(ROUND_START_CLAIM)
    B5 = {hf: part_b5(hf, t73) for hf in ("osaka", "amsterdam")}
    for hf in B5:
        print_part_b5(B5[hf])
    H = None
    if os.environ.get("SKIP_HISTORY") != "1":
        H = history()
        print_history(H)
    if os.environ.get("POC_JSON"):
        json.dump({"A": A, "B": Bp, "B5": B5, "H": H}, open(os.environ["POC_JSON"], "w"), indent=1, default=str)

    o, m = A["osaka"], A["amsterdam"]
    def all_bribe(rows, want):
        hs = [s for x in rows for i, s in x["hooks"] if i in BRIBE_INITIATIVES]
        return bool(hs) and all(s == want for s in hs)
    sweep_ok = lambda r: [s for s in r["sweep"] if s["ok"]]
    bo, bm = Bp["osaka"], Bp["amsterdam"]
    v = {
        "osaka_votes_recorded": all_bribe(o["replay"], 1) and all(x["ok"] for x in o["replay"])
                                and all(h == o["epoch"] for h in o["heads"].values()),
        "amsterdam_votes_dropped": all_bribe(m["replay"], 0) and all(x["ok"] for x in m["replay"])
                                   and all(h < m["epoch"] for h in m["heads"].values()),
        "osaka_sweep_never_drops": bool(sweep_ok(o)) and all(s["bribe_hooks"] and all(h == 1 for h in s["bribe_hooks"])
                                                            for s in sweep_ok(o)),
        "amsterdam_sweep_always_drops": bool(sweep_ok(m)) and all(s["bribe_hooks"] and all(h == 0 for h in s["bribe_hooks"])
                                                                 for s in sweep_ok(m)),
        "amsterdam_control_uncapped_vote_recorded": all(r["uncapped"]["ok"] and r["uncapped"]["bribe_hooks"] == [1, 1]
                                                        and r["uncapped"]["head"] == r["epoch"] for r in (o, m))
                                                    and m["uncapped"]["used"][0] > HOOK_GAS > o["uncapped"]["used"][0],
        "hook_cost": o["hook_capped"]["error"] is None and o["hook_uncapped"]["used"] < HOOK_GAS
                     and m["hook_capped"]["error"] == "out of gas" and m["hook_uncapped"]["used"] > HOOK_GAS
                     and not m["hook_uncapped"]["failed"],
        "amsterdam_realloc_still_dropped": m["realloc_same_epoch"]["ok"] and m["realloc_same_epoch"]["hooks"] == [0, 0]
                                           and m["realloc_next_epoch"]["ok"] and m["realloc_next_epoch"]["hooks"] == [0, 0]
                                           and m["realloc_next_epoch"]["head"] == m["heads"]["CurveV2"]
                                           and o["realloc_next_epoch"]["hooks"] == [1, 1],
        "bribes_follow_frozen_records": all(not c["ok"] for c in o["leaver_claims"])
                                        and all(c["ok"] and c["bold"] > 0 for c in m["leaver_claims"])
                                        and all(c["ok"] and c["bold"] > 0 for c in o["joiner_claims"])
                                        and all(not c["ok"] for c in m["joiner_claims"]),
        "votium_osaka_deposits": bo["votium"]["ok"] and [c[3] for c in bo["votium"]["claims"]] == [1]
                                 and len(bo["votium"]["deposits"]) == 1 and bo["votium"]["stranded"] == 0,
        "votium_amsterdam_stranded": bm["votium"]["ok"] and [c[3] for c in bm["votium"]["claims"]] == [0]
                                     and not bm["votium"]["deposits"] and bm["votium"]["stranded"] == votium_amount
                                     and bm["votium"]["remainder_delta"] == 0,
        "votium_amsterdam_control_uncapped_deposits": all([c[3] for c in r["uncapped"]["claims"]] == [1]
                                                          and len(r["uncapped"]["deposits"]) == 1
                                                          and r["uncapped"]["stranded"] == 0 for r in (bo, bm))
                                                      and bm["uncapped"]["hook_used"][0] > HOOK_GAS > bo["uncapped"]["hook_used"][0],
        "votium_round_start_claim": [c[3] for c in B5["osaka"]["capped"]["claims"]] == [1]
                                    and B5["osaka"]["capped"]["stranded"] == 0
                                    and [c[3] for c in B5["amsterdam"]["capped"]["claims"]] == [0]
                                    and B5["amsterdam"]["capped"]["stranded"] == B5["amsterdam"]["capped"]["claims"][0][1]
                                    and B5["amsterdam"]["uncapped"]["hook_used"][0] > HOOK_GAS,
        "votium_permanent": bm["reclaim"]["ok"] and not bm["reclaim"]["claims"] and bm["reclaim"]["stranded"] == 0
                            and [c[3] for c in bm["next_epoch"]["claims"]] == [0] and bm["next_epoch"]["stranded"] > 0
                            and [c[3] for c in bm["third_epoch"]["claims"]] == [0] and bm["third_epoch"]["stranded"] > 0
                            and bm["third_epoch_uncapped"]["hook_used"][0] > HOOK_GAS
                            and bm["votium_ini_balance"] == votium_amount + bm["next_epoch"]["stranded"]
                                                            + bm["third_epoch"]["stranded"],
        "votium_osaka_sweep_never_strands": bool(sweep_ok(bo)) and all(s["deposits"] and s["stranded"] == 0
                                                                      for s in sweep_ok(bo)),
        "votium_amsterdam_sweep_always_strands": bool(sweep_ok(bm)) and all(not s["deposits"] and s["stranded"] > 0
                                                                           for s in sweep_ok(bm)),
        "other_claim_hooks_still_fit": all([c[3] for c in x["claims"]] == [1]
                                           for r in (bo, bm) for x in r["controls"].values()),
    }
    if H is not None:
        v["history_no_bribeinitiative_hook_ever_failed"] = (H["alloc_events"] > 0 and H["bribe_alloc_failed"] == 0
                                                            and H["bribe_claims"] > 0 and H["bribe_claims_failed"] == 0)
    print("\nVERDICT")
    for k, x in v.items():
        print(f"  {'PASS' if x else 'FAIL'}  {k}")
    if H is None:
        print("  SKIP  history_no_bribeinitiative_hook_ever_failed (SKIP_HISTORY=1)")
    overall = all(v.values())
    print(f"  OVERALL: {'PASS' if overall else 'FAIL'}")
    sys.exit(0 if overall else 1)


EPOCH74_GAS0 = VOTIUM_GAS0 = None

if __name__ == "__main__":
    main()
