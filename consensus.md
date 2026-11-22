# Munex consensus

Munex is a testnet chain (chain id 6621). This paper states the rules
that decide whether a block is valid and which chain is the true one.
Every node on the chain enforces the same rules. A block that breaks
any of them is rejected, and a node running different rules cannot
join the chain.

Spatial verification (SVF) is always on. It is described in full in
`SVF.md`; section 11 gives the part of it a reader of this paper
needs.

## 1. The chain

- Chain id **6621**.
- Blocks are numbered from the genesis block, height 0. A block is
  identified by its hash.
- The genesis block is identified by its identity hash, which covers
  the SVF group public key and the approved template hashes. Nodes
  on a chain must agree on the genesis. A fresh node learns the
  genesis from an existing peer and then pins what it learned, so it
  can never afterwards be pulled onto a different chain.

## 2. Proof of Spatial Work — the lottery

A miner proves work by playing a maze. It moves through a
three-dimensional maze, catches the goal to grow the maze, and the
maze slowly shrinks back over time. The bigger the maze, the more
weight it carries in the lottery. Mining is open: anyone can join,
and there is no maximum maze size.

### 2.1 Who can win

Every attested maze over size 5 that the producer knows about is a
candidate. A maze at or under 5x5x5 is never a candidate: 5x5x5 is
the default starting size, and it is subtracted from the weight, so
a size-5 maze has weight 0. A maze can shrink back to 5x5x5 and
become ineligible.

Each candidate's weight is `size^3 - 125`: size 5 has weight 0,
size 6 has weight 91, size 7 has weight 218. The lottery is
global: the winner is picked across all miners' candidates, not
per miner.

### 2.2 The draw

The winner is drawn with probability `weight / total weight`, using
a deterministic weighted ordering with integer arithmetic only.

The ticket is `int(keccak256(previous_block_hash || height ||
timestamp || maze_id))`. The ticket binds the block's own proposed
timestamp, so every retry is a fresh draw while remaining fully
deterministic: every verifier recomputes it from the sealed block.

One eligible miner wins all of the time. Two miners at sizes 6 and
7 win with probability 91/309 (about 29%) and 218/309 (about 71%).

A follower recomputes the draw from the block's sealed
`lottery_draw` (candidates, rank, winner index, takeover flag) and
rejects the block if the draw does not reproduce. The draw is not
taken on trust.

### 2.3 Rank and takeover

The winner is normally the first draw (rank 0). If the rank-0
winner's host is absent or behind, the rank climbs with elapsed
time: `rank = min((elapsed - BLOCK_TIME) // SLOT_TIMEOUT,
len(passing) - 1)`, with `BLOCK_TIME = 50` and `SLOT_TIMEOUT = 30`
by default, so another candidate can take over. This is the
liveness rule, not a second lottery.

### 2.4 No miner, no block

A block needs a lottery candidate. When there is no eligible
candidate (all mazes at or below 5x5x5, or no miners at all), no
block seals. The producer logs a missed round once per 50-second
cycle and waits for the next cycle. The chain does not move without
a miner.

A block with no lottery draw is rejected. There is no block without
a lottery.

A size-5 maze never wins any lottery, not even alone; a size-5 maze
beside a size-6 maze never wins (the size-6 maze always wins).

### 2.5 The winner must sign

A block seals only when the winning miner signs it. The producer
sends the unsigned block to the winner over its WebSocket
connection and waits up to 60 seconds for the signed block back.
If the winner does not sign in time, the block is skipped (and the
winner is slashed for the refusal). There is no fallback in which
the node signs the block itself.

The node can never be a miner. The embedded miner is removed: a
node never registers as a miner, never wins, and never self-signs.
A config that still sets `embedded_miner` logs a warning once and
is ignored.

Every follower checks that the block's signature verifies against
`producer_pub`, and that `producer_pub` equals both the attestation
public key and the winner's registered block-signing key. A
signature made with any other key — including the producer node's
own key — is rejected. The node does not hold the winner's private
key, so it cannot produce a valid signature for a block it sealed
alone.

The only self-signed block in the chain is the genesis block
(block 0), written by the node when the chain is created, before
any miner exists. It is the starting point, not a sealed block, and
it cannot be used to seal any later block.

### 2.6 Reward

The block reward is 1 MCX at the genesis era, paid to the winning
miner's wallet, plus the block's transaction fees. It halves every
2,522,880 blocks.

Genesis allocates 200 MCX. The hard cap is 5,045,958 MCX.

A block's `reward_wallet` is the winner's wallet. Only miners
mint.

## 3. What a block carries

A block's proof is verified over these fields:

```
winner, producer_pub, signature, state_root, transactions,
maze_attestation, reward_wallet, maze_updates, attestation_proof,
global_shrink_factor, slashes, maze_state, svf_epoch_certificates,
lottery_draw
```

- `maze_state` is in the block and covered by the proof.
- `lottery_draw` carries the draw (candidates, rank, winner index,
  takeover flag) so a follower can recompute it.
- `svf_epoch_certificates` carries at most the certificates the
  block seals (see section 11).

## 4. Time

`M < T <= M + 7200`, where `M` is the median of the up to 11 most
recent block timestamps and `T` is the candidate block's
timestamp.

Validity reads no clock. The check uses only sealed block
timestamps. A block whose timestamp is outside the window is
invalid, whenever it arrives.

The producer stamps `T = clamp(now, M + 1, M + 7200)`.

If a node's wall clock drifts far from the chain, the node logs a
time-drift warning. Drift never changes validity.

## 5. Attestation

A block's attestation size above 10 (the maze floor of 5 plus a
buffer of 5) must be backed by a proven catch: an entry in the
block's own `maze_updates` or `attestation_proof` with `new_size`
equal to the attested size, or a reorg base, or a local
`maze_attestations` row with `last_size` at least the attested
size. Otherwise the block is rejected.

Every `maze_updates` entry that grows a maze past its live size
must carry `caught_at_nonce`. A block growing a maze from 5 to some
larger size with no catch proof is rejected.

Catch proofs are retained per (maze, size) in the never-pruned
`maze_proofs` table, and the producer stores its own sealed blocks'
proofs on seal. `maze_attestations` is never pruned.

Attestation proofs are not state. `attestation_proof` is carried in
the block and replay-validated, but it is not applied to state and
is not in the state-root formula.

The maze floor is 5. Block validity requires the attested size to
be at least 5; lottery eligibility requires it to be strictly
greater than 5.

## 6. The state root

The state root is a pure function of a snapshot of the chain's
state. The snapshot covers:

| Prefix | Contents |
|--------|----------|
| `height:{id}` | block height |
| `bal:{wallet}` | MCX balances |
| `tok:{token}:{wallet}` | token balances |
| `cst:{contract}:{key}`, `cst2:{contract}:{key}` | contract storage |
| `htlc:{id}` | HTLC contracts |
| `maze:{maze_id}` | committed maze columns |
| `toki:{address}` | token info |
| `conv:{address}` | contracts (owner, code hash) |
| `mazeatt:{maze_id}` | maze attestations |
| `svfreg:{token}` | registered SVF profiles |
| `svfepoch:{epoch}` | SVF epoch roots |
| `svfcert:{epoch}` | SVF certificates |

Two ordering facts matter:

- Block N's root commits to attestation state as of N−1.
- Certificate ordering. The producer computes the root before a
  newly prepared certificate enters its in-memory certificate
  store, so the declared root has no `svfcert:{epoch}` for the
  block's own certificate. The follower therefore verifies the
  carried certificate but does not store it during verification;
  it applies it only after the root check. Storing it earlier
  makes the follower's root differ from the producer's.

## 7. Gas and fees

The gas model is Ethereum's: intrinsic 21000, plus calldata 4 per
zero byte and 16 per non-zero byte, plus 32000 for contract
creation, plus 200 per byte of code deposited; virtual-machine gas
costs are pre-Berlin. The fee is `gas_used x gasPrice`.

The gas field on a transaction is a cap only. The sender is
charged for gas actually used, and the unused part is refunded. A
failed transaction is excluded from the block and its fee is
refunded.

There is no per-transaction gas cap and no minimum fee.
`gasPrice` is sender-chosen, including 0. The default gas price is
1 and the default gas cap is 100000.

A block holds at most 10,000,000 gas and at most 1000
transactions.

SVF fees are hardcoded and node-computed, not sender-chosen:
`token_create` 500000 flat; `token_transfer` and `token_burn`
1000 plus 1 per canonical byte. The producer, the executor, and
the verifier all recompute them; a block whose fee or gas used
does not match the recomputation is rejected.

These constants are bound in the genesis ruleset, so a node running
different constants cannot join the chain.

## 8. Transactions and nonces

Transactions are checked read-only on mempool admission and
executed exactly once when sealed into a block.

The next nonce for a wallet is the maximum of the database, the
mempool's confirmed nonces, and the durable `account_nonces`
table. The `account_nonces` table is never pruned, is updated on
seal and import, and is rolled back on reorg, so a restarted node
reports the correct nonce even when its transaction history is
pruned.

## 9. Reorganisations

A reorganisation rolls back local blocks above the common height
and adopts the peer chain when the peer chain is heavier.

Reorganisations deeper than the prune window are refused before
any state is touched.

New blocks are pre-verified against ancestor attestation state
before any rollback; a failed pre-verification aborts with all
state untouched.

Virtual-machine state (storage, balances, token balances) is
reverted from the contract execution journal; MCX and token-balance
debits are signed deltas settled at the end, not order-dependent
subtractions.

Checkpoints are advisory, not a veto: a reorganisation whose fork
point is below the last checkpoint still heals by weight.

A final cumulative gate, inside the same transaction, checks:
adopted blocks are parent-linked from the anchor and present
hash-equal in the block store; tip height and hash are mirrored;
total minted is conserved (pre-fork mint, minus rewound orphan
mint, plus adopted mint, by a single formula); and each adopted
block's persisted transaction set equals its sealed transaction
hashes.

## 10. Pruning

`prune_blocks` must be an integer in [100, 10^9] (default 10000).

Pruning deletes `blocks` and `transactions` rows older than the
window. It never deletes `transaction_receipts`, `contract_v2`,
`svf_evidence`, `svf_certificates`, `maze_attestations`,
`maze_proofs`, or the durable `account_nonces` table.

Pruning must never delete a block that is an anchor referenced by
a certificate the chain still needs, or a proof source for an epoch
not yet certified. This floor is the start (epoch x 100) of the
earliest epoch that can still certify and has no certificate
stored. Epoch 0 is never protected (it has only 99 evidence
records and can never certify). Once an epoch's certificate is
stored, it stops protecting its blocks.

The floor is computed from the durable database tables, never from
volatile in-memory state. If either database read fails, or the
evidence query returns no rows while the chain is past height 100,
the floor is 0: protect everything, delete nothing this cycle.
Only when the reads succeed and genuinely no epoch needs
protection does the floor return nothing.

The `prune_blocks` value itself is not consensus. It is excluded
from the genesis ruleset comparison: nodes with different prune
windows run on the same chain. What is consensus is that validity
never reads pruned history, and every rule that once did
(attestation proofs, certificate anchors, guard maturity) instead
uses carried proofs, the prune floor, or a chain-global constant.

## 11. Spatial verification, in brief

SVF is the chain's built-in verification layer. It is always on
and it is described in full in `SVF.md`. The rules a reader of
this paper needs:

- **Epochs.** One epoch is 100 blocks. Epoch `e` covers blocks
  `e*100` through `e*100+99`. Epoch 0 has only 99 evidence
  records (genesis gets none) and can never certify. The first
  certifiable epoch is epoch 1 (blocks 100–199).
- **Preparation timing.** A certificate for epoch `e` is prepared
  only when the block height is past `(e*100 + 99) +
  prune_blocks`: the epoch has ended and a full prune window has
  passed. With a prune window of 100, the epoch-1 certificate is
  first prepared at block 300.
- **Anchor.** The certificate's anchor is the hash of the epoch's
  last block (height `e*100+99`). The anchor lookup searches only
  the node's in-memory block list; if it is absent the
  certificate is skipped.
- **Signed message.** The threshold signature is over the
  canonical message `MCX-SVF-EPOCH-BEACON-V1` plus version
  (uint16 1), chain id, committee epoch, evidence epoch, window
  start, window end, anchor hash, and evidence root.
  `prune_blocks` is deliberately not part of the signed message:
  it is a local config value, and including it made a certificate
  signed by a prune-100 node unverifiable on a prune-200 node.
- **Verification.** A follower carrying a certificate checks, in
  order: the anchor equals the canonical block hash at the
  epoch-end height; the evidence root equals the committed epoch
  root (never taken from the certificate itself); the threshold
  signature verifies against the group public key. Any failure
  rejects the block.
- **Storage.** A carried certificate is stored in
  `svf_certificates` with its evidence epoch, chain id,
  committee epoch, window start and end heights, anchor block
  hash, evidence root, group public key id, threshold signature,
  inclusion block, and usable-from height. A certificate in block
  N is usable from block N+1.
- **Maturity.** Guard targets use epoch `(block_h - 100 - 100) //
  100`: a chain-global lag of 100. The local `prune_blocks` value
  does not enter this computation.

## 12. What is not part of consensus

- `BLOCK_TIME = 50` is seal pacing only. It is not in the
  consensus ruleset.
- The `prune_blocks` value itself (100 versus 200) — see
  section 10.
- The `global_shrink_factor` value: it is sealed in every block
  and adopted verbatim; it is data, not a rule change.
- Log lines and warnings. A time-drift warning never changes
  validity.
- Peer discovery. How a node or miner finds other nodes — DNS
  seed, bootstrap list, peer cache, or the Munex registry list —
  is not consensus. The registry is not part of the chain: it
  holds no chain state and no rule depends on it. The node never
  pushes its IP to the registry; the registry learns nodes from
  the seed DNS and by fetching each node's existing `GET /peers`
  HTTP API. A down registry changes nothing — the seed stays as
  the fallback.
