# Munex-docs

Documentation for the Munex testnet (chain 6621): the consensus
rules, the SVF verification layer, and a sample guarded token
contract.

## What is inside

- `consensus.md` — the consensus rules: Proof of Spatial Work (the
  maze lottery), block format, timestamp rule, state root, gas and
  fees, reorgs, pruning, and SVF in brief.
- `SVF.md` — SVF in full: the committee key and templates, profiles,
  evidence and epoch roots, certificates, the requirePass guard, SVF
  fees, the four guard cases, and the test token.
- `SampleSVFToken.sol` — a sample ERC20-style token guarded by the
  SVF guard precompile (`0x0800`). Compiled clean with solc 0.8.26;
  not yet deployed to or executed on the Munex VM.

## The chain in brief

Munex is a testnet (chain 6621). Blocks are won by a maze lottery:
only mazes above 5x5x5 are eligible, weight is size^3 − 125, a block
seals every 50 seconds only when an eligible miner exists, and the
winning miner must sign the block. SVF is always on: a token's
`requirePass()` call passes only when its registered profile is
satisfied by a certified epoch. The block reward is 1 MCX; the hard
cap is 5,045,958 MCX.

## Status

Testnet documentation. TESTNET CANDIDATE. The code it describes has
not been independently audited. See [NOTICE.md](NOTICE.md).

## Related repositories

- [Munex-node](https://github.com/Munex-coin/Munex-node) — the node
- [Miner-codes](https://github.com/Munex-coin/Miner-codes) — miners
- [Munex-API](https://github.com/Munex-coin/Munex-API) — developer API scripts
