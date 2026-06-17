//! Per-run smoke harness for the validator export pipeline.
//!
//! Drives the same `FfiApp::set_active_profile_material` +
//! `FfiApp::export_profile` / `FfiApp::export_share` flow that the
//! `Copy Profile` / `Copy Share` SwiftUI / Compose buttons trigger, prints
//! each artifact to stdout (redacted), and verifies the result decodes as
//! a real `bfprofile1`/`bfshare1` package via `frostr-utils`.
//!
//! Output: emits NDJSON-style proof lines:
//!
//! ```
//! {"step":"export_profile","ok":true,"package_length":N,"prefix":"bfprofile1"}
//! {"step":"decode_profile","ok":true,"device_name_length":...,"group_member_count":...}
//! {"step":"export_share","ok":true,"package_length":N,"prefix":"bfshare1"}
//! {"step":"decode_share","ok":true,"share_secret_length":...,"relay_count":...}
//! ```
//!
//! Reads the material JSON and the export password from `SMOKE_MATERIAL`
//! and `SMOKE_PASSWORD` env vars. Exits 0 on full success; 2 on any
//! `FfiApp` failure or invalid decodes.

use frostr_utils::{
    decode_bfprofile_package, decode_bfshare_package, derive_profile_id_from_share_secret,
    PREFIX_BFPROFILE, PREFIX_BFSHARE,
};
use igloo_mobile_core::{FfiApp, MaterialMember, OnboardProfileMaterial, SignerSettings};
use std::env;

fn main() -> Result<(), String> {
    let material_arg = env::var("SMOKE_MATERIAL").unwrap_or_default();
    let password = env::var("SMOKE_PASSWORD").unwrap_or_default();

    let (material, password) = if material_arg.is_empty() {
        // Fall back to a synthetic demo material so the smoke run still
        // exercises both export paths without an iOS device pre-load.
        let shared_password = if password.is_empty() {
            "smoke-export-password".to_string()
        } else {
            password.clone()
        };
        let material = synthetic_demo_material();
        (material, shared_password)
    } else {
        let parsed: OnboardProfileMaterial = serde_json::from_str(&material_arg).map_err(|e| {
            format!("SMOKE_MATERIAL must parse as OnboardProfileMaterial JSON: {e}")
        })?;
        (parsed, password)
    };

    let app = FfiApp::new(std::env::temp_dir().to_string_lossy().to_string());
    let material_json = serde_json::to_string(&material).map_err(|e| e.to_string())?;
    app.set_active_profile_material(material_json);

    // Export profile.
    let exported_profile = app.export_profile(password.clone());
    let profile_ok = exported_profile.starts_with(PREFIX_BFPROFILE);
    emit(
        "export_profile",
        profile_ok,
        &[
            ("package_length", exported_profile.len().to_string()),
            ("prefix", PREFIX_BFPROFILE.to_string()),
        ],
    );
    if !profile_ok {
        return Err(format!(
            "export_profile did not produce a bfprofile1 package (got prefix {:?})",
            exported_profile.chars().take(12).collect::<String>()
        ));
    }

    // Decode profile.
    let decoded_profile = decode_bfprofile_package(&exported_profile, &password)
        .map_err(|e| format!("decode_bfprofile_package: {e}"))?;
    emit(
        "decode_profile",
        true,
        &[
            (
                "device_name_length",
                decoded_profile.device.name.chars().count().to_string(),
            ),
            (
                "group_member_count",
                decoded_profile.group_package.members.len().to_string(),
            ),
            (
                "threshold",
                decoded_profile.group_package.threshold.to_string(),
            ),
            (
                "relay_count",
                decoded_profile.device.relays.len().to_string(),
            ),
            (
                "share_pubkey_length",
                decoded_profile
                    .device
                    .share_secret
                    .chars()
                    .count()
                    .to_string(),
            ),
        ],
    );

    // Export share.
    let exported_share = app.export_share(password.clone());
    let share_ok = exported_share.starts_with(PREFIX_BFSHARE);
    emit(
        "export_share",
        share_ok,
        &[
            ("package_length", exported_share.len().to_string()),
            ("prefix", PREFIX_BFSHARE.to_string()),
        ],
    );
    if !share_ok {
        return Err(format!(
            "export_share did not produce a bfshare1 package (got prefix {:?})",
            exported_share.chars().take(12).collect::<String>()
        ));
    }

    // Decode share.
    let decoded_share = decode_bfshare_package(&exported_share, &password)
        .map_err(|e| format!("decode_bfshare_package: {e}"))?;
    emit(
        "decode_share",
        true,
        &[
            (
                "share_secret_length",
                decoded_share.share_secret.chars().count().to_string(),
            ),
            ("relay_count", decoded_share.relays.len().to_string()),
        ],
    );

    // Wrong-password negative proof (VAL-SET-015 binding).
    let wrong = "this-password-is-wrong";
    let profile_wrong_fails = decode_bfprofile_package(&exported_profile, wrong).is_err();
    let share_wrong_fails = decode_bfshare_package(&exported_share, wrong).is_err();
    emit(
        "password_binding",
        profile_wrong_fails && share_wrong_fails,
        &[
            (
                "profile_wrong_password_rejected",
                profile_wrong_fails.to_string(),
            ),
            (
                "share_wrong_password_rejected",
                share_wrong_fails.to_string(),
            ),
        ],
    );
    if !profile_wrong_fails || !share_wrong_fails {
        return Err(
            "exported packages decrypt with a password other than the export password".to_string(),
        );
    }

    Ok(())
}

fn emit(step: &str, ok: bool, fields: &[(&str, String)]) {
    let mut s = format!("{{\"step\":\"{step}\",\"ok\":{ok}");
    for (k, v) in fields {
        // Escape quotes/backslashes so the JSON is well-formed.
        let escaped = v.replace('\\', r"\\").replace('"', r#"\""#);
        s.push_str(&format!(",\"{k}\":\"{escaped}\""));
    }
    s.push('}');
    println!("{s}");
}

fn synthetic_demo_material() -> OnboardProfileMaterial {
    let local_pub = "33".repeat(32);
    let alice_pub = "11".repeat(32);
    let carol_pub = "22".repeat(32);
    let profile_id =
        derive_profile_id_from_share_secret(&"aa".repeat(32)).expect("derive profile id");
    OnboardProfileMaterial {
        share_seckey_hex: "aa".repeat(32),
        share_pubkey: local_pub.clone(),
        group_pubkey: "ee".repeat(32),
        relays: vec!["ws://127.0.0.1:8194".to_string()],
        device_state_hex: String::new(),
        profile_id,
        share_idx: 0,
        peer_pubkeys: vec![alice_pub.clone(), carol_pub.clone()],
        members: vec![
            MaterialMember {
                idx: 0,
                pubkey_hex: format!("02{local_pub}"),
            },
            MaterialMember {
                idx: 1,
                pubkey_hex: format!("02{alice_pub}"),
            },
            MaterialMember {
                idx: 2,
                pubkey_hex: format!("02{carol_pub}"),
            },
        ],
        device_name: "smoke-demo".to_string(),
        settings: SignerSettings::default(),
    }
}
