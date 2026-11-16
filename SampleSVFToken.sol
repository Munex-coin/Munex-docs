// SPDX-License-Identifier: MIT
// SampleSVFToken.sol — a sample ERC20-style token guarded by Munex SVF.
//
// TESTNET ONLY — chain 6621. Not audited. Not for mainnet use.
// This file is a sample for developers building on the Munex testnet.
// It shows the guard-call pattern; it is not a deployed contract and
// has not been independently audited.
//
// How the guard works (verified against launch/v10/node.py):
//   * The SVF guard lives at precompile address
//     0x0000000000000000000000000000000000000800.
//   * requirePass() has selector 0x4514a8d5 = keccak256("requirePass()")[:4]
//     (node function _svf_selector). The guard interface is unchanged
//     from the Run 17 version of this sample.
//   * The guard returns a SINGLE byte on success: 0x01. It is NOT a
//     32-byte ABI-encoded bool. A plain `returns (bool)` declaration
//     would fail to decode the 1-byte return, so this contract uses a
//     low-level call and checks the raw return bytes. Do not "fix" this
//     into a normal interface call.
//   * The test token actually deployed on the testnet is NOT this
//     contract. It is a minimal 56-byte EVM forwarder: it copies all
//     calldata and CALLs the guard precompile with all gas, returning
//     the guard's returndata on success and reverting on failure.
//     Its runtime is:
//       3660006000376000600036600034730000000000000000000000000000000000000800
//       5af13d600060003e156033573d6000f35b3d6000fd
//     and its 12-byte init is 6038600c60003960386000f3 (CODECOPY 56 bytes
//     from offset 12, then RETURN). The forwarder has no selector logic
//     of its own: the calldata — including the 0x4514a8d5 selector — is
//     forwarded verbatim to the precompile.
//   * Registration: a token is guarded only after its profile is
//     registered on-chain with registerProfile(bytes), selector
//     0xb58f53b2 = keccak256("registerProfile(bytes)")[:4]. The profile
//     is a 42-byte canonical blob (see registerProfile below). Template
//     "direct_erc20", sha256
//     42ef31de0b91480beda1431b9e447a39c086d343ef6d69d206d94bb71e450437.
//     Satisfiable example: sample_blocks=10, min_distinct_winners=2,
//     min_growth_blocks=0, min_total_attestation_weight=1000.
//     Unsatisfiable example (used by test case (c)): min_weight=10**9.
//   * Read helpers: profileOf(address) selector 0x2f8eb9cb returns the
//     32-byte profile hash, or 32 zero bytes when unregistered.
//     protocolInfo() selector 0x93420cf4 returns 18 bytes: version
//     (uint16, currently 1), SVF activation height (uint64, 0 — SVF is
//     always on), epoch length in blocks (uint64, 100).
//     epochStatus(address,uint64) selector 0xfadbd0d3 currently returns
//     a single 0x00 byte; do not rely on it for status.
//
// Compiled clean with solc 0.8.26 on 2026-11-16 (no errors, no
// warnings), but not yet deployed to, or executed on, the Munex VM. Whether a full
// Solidity ERC20 runs on the node's VM (opcode support, gas
// accounting, storage layout) must be tested on the testnet first.
// The deployed test token is the forwarder above, not this contract.

pragma solidity ^0.8.0;

/// @title SampleSVFToken — ERC20-style token gated by the Munex SVF guard.
/// @notice Guarded functions call requirePass() on the guard precompile
///         BEFORE doing anything else. If the guard refuses (the token's
///         profile is not yet certified, or its profile does not pass
///         against the certified epoch), the whole call reverts.
contract SampleSVFToken {
    // The SVF guard precompile. Verified in the node file:
    // SVF_GUARD_ADDRESS = bytes.fromhex("0000000000000000000000000000000000000800")
    address internal constant SVF_GUARD =
        0x0000000000000000000000000000000000000800;

    // requirePass() selector: 0x4514a8d5.
    // Computed as keccak256("requirePass()")[:4] — the same derivation
    // the node uses in _svf_selector. Confirm against the deployed
    // token's ABI before use in production tooling.
    bytes4 internal constant REQUIRE_PASS_SELECTOR = 0x4514a8d5;

    // registerProfile(bytes) selector: 0xb58f53b2.
    bytes4 internal constant REGISTER_PROFILE_SELECTOR = 0xb58f53b2;

    // profileOf(address) selector: 0x2f8eb9cb.
    bytes4 internal constant PROFILE_OF_SELECTOR = 0x2f8eb9cb;

    string public name = "Sample SVF Token";
    string public symbol = "SVF";
    uint8 public decimals = 0;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(uint256 initialSupply) {
        totalSupply = initialSupply;
        balanceOf[msg.sender] = initialSupply;
        emit Transfer(address(0), msg.sender, initialSupply);
    }

    /// @notice Calls the SVF guard and requires it to pass.
    /// @dev The guard returns exactly one byte, 0x01, on success — not
    ///      a 32-byte ABI bool. A low-level call is required.
    ///      On failure the precompile reverts (or returns 0x), so the
    ///      low-level call itself fails and this function reverts.
    function _requirePass() internal view {
        (bool ok, bytes memory ret) = SVF_GUARD.staticcall(
            abi.encodeWithSelector(REQUIRE_PASS_SELECTOR)
        );
        require(ok, "SVF guard call failed");
        require(
            ret.length == 1 && ret[0] == 0x01,
            "SVF requirePass refused"
        );
    }

    /// @notice Guarded transfer. Passes only once the token's profile is
    ///         registered AND the target epoch is certified AND the
    ///         profile passes against that epoch's sampled evidence.
    ///         Before any certificate exists, this reverts (test case (a)).
    function transfer(address to, uint256 value) external returns (bool) {
        _requirePass();
        require(to != address(0), "transfer to zero address");
        require(balanceOf[msg.sender] >= value, "insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Guarded transferFrom, same guard as transfer.
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        _requirePass();
        require(to != address(0), "transfer to zero address");
        require(balanceOf[from] >= value, "insufficient balance");
        require(
            allowance[from][msg.sender] >= value,
            "insufficient allowance"
        );
        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @notice Registers this token's SVF profile on-chain.
    /// @dev Call layout: selector 0xb58f53b2, then the standard ABI
    ///      encoding of a bytes argument — offset word (32), length
    ///      word, profile bytes, zero-padded to a 32-byte boundary.
    ///      `abi.encodeWithSelector` produces exactly this layout.
    ///      The profile is 42 bytes, canonical layout
    ///      (node function svf_profile_bytes):
    ///        "MCXS" (4 bytes magic) |
    ///        schema_version uint16 (= 1) |
    ///        family_id uint8 (= 1) |
    ///        sample_blocks uint8 (1..100) |
    ///        min_distinct_winners uint8 |
    ///        min_growth_blocks uint8 |
    ///        min_total_attestation_weight uint256 (32 bytes, big-endian)
    ///      A re-register with the IDENTICAL profile succeeds (idempotent
    ///      replay); a re-register with a DIFFERENT profile for the same
    ///      token is refused. The profile becomes effective at
    ///      effective_epoch (the epoch after registration).
    /// @param profile The 42-byte canonical profile blob.
    function registerProfile(bytes calldata profile) external {
        (bool ok, ) = SVF_GUARD.call(
            abi.encodeWithSelector(REGISTER_PROFILE_SELECTOR, profile)
        );
        require(ok, "SVF registerProfile failed");
    }

    /// @notice Reads this token's registered profile hash from the guard.
    /// @return The 32-byte profile hash, or 32 zero bytes if unregistered.
    function profileOf() external view returns (bytes32) {
        (bool ok, bytes memory ret) = SVF_GUARD.staticcall(
            abi.encodeWithSelector(PROFILE_OF_SELECTOR, address(this))
        );
        require(ok, "SVF profileOf failed");
        require(ret.length == 32, "SVF profileOf bad return");
        return abi.decode(ret, (bytes32));
    }
}
