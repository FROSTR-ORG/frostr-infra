//! Validator-only Cargo example that decodes a `bfprofile1` or `bfshare1`
//! package produced by the mobile `Copy Profile` / `Copy Share` action and
//! prints redacted shape information. This is the canonical proof for the
//! `VAL-SET-007/008/015` export artifacts used by the user-testing validator
//! when gathering clipboard output without committing the package bytes.
//!
//! # Inputs (via environment)
//!
//! * `EXPORT_PACKAGE` — the bech32m package (starts with `bfprofile1` or
//!   `bfshare1`).
//! * `EXPORT_PASSWORD` — the export password chosen at the prompt.
//! * `EXPORT_KIND` — optional. Expected value `profile` (default) or `share`.
//!
//! # Outputs (stdout)
//!
//! Prints a redacted proof panel. Never echoes the package bytes, password,
//! decrypted share secret, share public key, or private key material. Only
//! shape data is emitted:
//!
//! * `kind=profile|share`
//! * `prefix=<prefix_bytes>`
//! * `length=<decimal_byte_count>`
//! * `decrypted_kind=<class_name>`
//! * `device_name_present=yes|no` (profile only)
//! * `device_name_length=<decimal_char_count>` (profile only)
//! * `group_pubkey_present=yes|no` (profile only)
//! * `group_member_count=<decimal>` (profile only)
//! * `share_secret_present=yes|no` (share only)
//! * `relay_count=<decimal>`
//!
//! Exit code is 0 on success and 2 on any decode/validation failure.

use std::env;

fn main() {
    if let Err(err) = run() {
        eprintln!("[export-decode] FAIL: {err}");
        std::process::exit(2);
    }
}

fn run() -> Result<(), String> {
    let package = require_env("EXPORT_PACKAGE")?;
    let password = require_env("EXPORT_PASSWORD")?;
    let expected_kind: Option<String> = env::var("EXPORT_KIND").ok();

    println!(
        "[export-decode] kind_hint={}",
        expected_kind.as_deref().unwrap_or("auto")
    );
    println!("[export-decode] package_length={}", package.len());
    let prefix = first_n_chars(&package, 12);
    println!("[export-decode] prefix=12:{prefix}");

    if !is_contiguous_bech32m(&package) {
        return Err(
            "package is not a contiguous bech32m string (whitespace or control chars detected)"
                .to_string(),
        );
    }

    let is_profile = package.starts_with(frostr_utils::PREFIX_BFPROFILE);
    let is_share = package.starts_with(frostr_utils::PREFIX_BFSHARE);

    match expected_kind.as_deref() {
        Some("profile") => {
            if !is_profile {
                return Err(format!(
                    "expected kind=profile but package prefix is not bfprofile1 (got {prefix:?})"
                ));
            }
        }
        Some("share") => {
            if !is_share {
                return Err(format!(
                    "expected kind=share but package prefix is not bfshare1 (got {prefix:?})"
                ));
            }
        }
        _ => {}
    }

    if is_profile {
        decode_profile(&package, &password)
    } else if is_share {
        decode_share(&package, &password)
    } else {
        Err(format!(
            "package prefix is neither bfprofile1 nor bfshare1 (got {prefix:?})"
        ))
    }
}

fn decode_profile(package: &str, password: &str) -> Result<(), String> {
    let decoded = frostr_utils::decode_bfprofile_package(package.trim(), password)
        .map_err(|e| format!("decode_bfprofile_package: {e}"))?;

    // Proof lines. None of these leak the payload, password, or secrets.
    println!("[export-decode] kind=profile");
    println!("[export-decode] decrypted_kind=BfProfilePayload");
    println!(
        "[export-decode] device_name_present={}",
        if decoded.device.name.is_empty() {
            "no"
        } else {
            "yes"
        }
    );
    println!(
        "[export-decode] device_name_length={}",
        decoded.device.name.chars().count()
    );
    println!(
        "[export-decode] group_pubkey_present={}",
        if decoded.group_package.group_pk.is_empty() {
            "no"
        } else {
            "yes"
        }
    );
    println!(
        "[export-decode] group_member_count={}",
        decoded.group_package.members.len()
    );
    println!(
        "[export-decode] threshold={}",
        decoded.group_package.threshold
    );
    println!(
        "[export-decode] relay_count={}",
        decoded.device.relays.len()
    );
    println!(
        "[export-decode] manual_peer_policy_overrides_count={}",
        decoded.device.manual_peer_policy_overrides.len()
    );
    println!("[export-decode] OK: bfprofile1 decoded");
    Ok(())
}

fn decode_share(package: &str, password: &str) -> Result<(), String> {
    let decoded = frostr_utils::decode_bfshare_package(package.trim(), password)
        .map_err(|e| format!("decode_bfshare_package: {e}"))?;

    println!("[export-decode] kind=share");
    println!("[export-decode] decrypted_kind=BfSharePayload");
    println!(
        "[export-decode] share_secret_present={}",
        if decoded.share_secret.is_empty() {
            "no"
        } else {
            "yes"
        }
    );
    println!(
        "[export-decode] share_secret_length={}",
        decoded.share_secret.chars().count()
    );
    println!("[export-decode] relay_count={}", decoded.relays.len());
    println!("[export-decode] OK: bfshare1 decoded");
    Ok(())
}

fn first_n_chars(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}

fn is_contiguous_bech32m(s: &str) -> bool {
    s.chars().all(|c| !c.is_whitespace())
}

fn require_env(name: &str) -> Result<String, String> {
    env::var(name).map_err(|_| format!("missing required environment variable {name}"))
}
