//! Helpers for cross-platform keyset interop and rotation tests.
//!
//! Both `cross_platform_keyset_interop.rs` and the rotate-share flow
//! reach into frostr-utils (`KeysetBundle`, `Members`, `GroupPackage`)
//! and need to:
//!
//! 1. hex-encode byte slices into 64-char lowercase hex strings;
//! 2. decode the same shape back into a `[u8; 32]` when reconstructing
//!    a `SharePackage` from a cross-decoded `BfOnboardPayload`;
//! 3. extract the x-only share pubkey for a given member, including
//!    emitting a 64-hex string for the contract's pre/post comparison.
//!
//! All helpers live here so the assertions in the consuming tests are
//! only concerned with the cross-platform guarantees themselves.

use bifrost_core::secret::SharePrivateKey;
use bifrost_core::types::SharePackage;

/// Lowercase hex encode of `bytes` (no separators, no leading "0x").
pub fn hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        out.push_str(&format!("{:02x}", b));
    }
    out
}

/// Convert a 64-char lowercase hex string into a 32-byte array. The
/// `cross_platform_keyset_interop` tests call this when reconstructing
/// a `SharePackage` from a decoded `BfOnboardPayload.share_secret`.
pub fn decode_hex32(value: &str) -> Result<[u8; 32], String> {
    let raw = value.trim();
    if raw.len() != 64 {
        return Err(format!("expected 64 hex chars (got {})", raw.len()));
    }
    let mut out = [0u8; 32];
    for (idx, pair) in raw.as_bytes().chunks(2).enumerate() {
        let hi = hex_digit(pair[0]).ok_or_else(|| "non-hex char".to_string())?;
        let lo = hex_digit(pair[1]).ok_or_else(|| "non-hex char".to_string())?;
        out[idx] = (hi << 4) | lo;
    }
    Ok(out)
}

fn hex_digit(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(10 + (b - b'a')),
        b'A'..=b'F' => Some(10 + (b - b'A')),
        _ => None,
    }
}

/// Reconstruct a `SharePackage` from a hex share_secret carried in a
/// decoded `BfOnboardPayload`. `idx` MUST equal the source bundle's
/// member idx so `verify_share` can match the share against its group
/// member row.
pub fn decoded_share_with_idx(share_secret_hex: &str, idx: u16) -> SharePackage {
    let secret_bytes =
        decode_hex32(share_secret_hex).expect("cross-decoded share secret must be 32 bytes");
    SharePackage {
        idx,
        seckey: SharePrivateKey::new(secret_bytes),
    }
}

/// 64-char lowercase hex of `bundle.shares[idx]`'s x-only public key.
/// `Members.pubkey` is the 33-byte SEC1 compressed form, so we slice
/// off the parity byte to get the 32-byte x-only form the contract
/// assertions compare against.
pub fn share_pubkey_for(bundle: &frostr_utils::KeysetBundle, idx: usize) -> String {
    hex(&bundle.group.members[idx].pubkey[1..])
}

/// 64-char lowercase hex of the bundle's group pubkey, directly as it
/// appears in `group.group_pk` (already 32 bytes / 64 hex chars). The
/// helper exists so the cross-platform tests can be explicit about
/// extracting the "full 64-hex value" the contract demands.
#[allow(dead_code)]
pub fn group_pubkey_hex(bundle: &frostr_utils::KeysetBundle) -> String {
    hex(&bundle.group.group_pk)
}
