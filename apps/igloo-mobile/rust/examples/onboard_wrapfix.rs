//! Compare the original (pre-fix) FfiApp::onboard wrapping pattern against a
//! fix that constructs the timeout INSIDE block_on.

use std::time::{Duration, Instant};

fn main() {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("build runtime");
    let started = Instant::now();

    // Test 1: pre-fix wrapping (tokio::time::timeout constructed outside block_on)
    let outcome_pre = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        rt.block_on(tokio::time::timeout(Duration::from_secs(2), async {
            tokio::time::sleep(Duration::from_millis(50)).await;
            "pre-fix ok"
        }))
    }));
    eprintln!(
        "[diag] pre-fix outcome: {:?}",
        outcome_pre
            .as_ref()
            .map(|r| r.as_ref().map(|s| *s).map_err(|_| "elapsed"))
    );

    // Test 2: post-fix wrapping (async block first, timeout inside)
    let started_fix = Instant::now();
    let outcome_post = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        rt.block_on(async {
            tokio::time::timeout(Duration::from_secs(2), async {
                tokio::time::sleep(Duration::from_millis(50)).await;
                "post-fix ok"
            })
            .await
        })
    }));
    eprintln!(
        "[diag] post-fix outcome: {:?}, elapsed: {:.1}s",
        outcome_post
            .as_ref()
            .map(|r| r.as_ref().map(|s| *s).map_err(|_| "elapsed")),
        started_fix.elapsed().as_secs_f64()
    );

    eprintln!(
        "[diag] total elapsed: {:.1}s",
        started.elapsed().as_secs_f64()
    );
}
