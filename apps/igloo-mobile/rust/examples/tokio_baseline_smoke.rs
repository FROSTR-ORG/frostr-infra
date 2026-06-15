//! Minimal diagnostic: confirm that tokio::time::timeout works in this crate
//! when used standalone, without nostr-sdk involvement.

use std::time::Duration;

fn main() {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("build runtime");
    let started = std::time::Instant::now();
    let result = rt.block_on(tokio::time::timeout(Duration::from_secs(5), async {
        tokio::time::sleep(Duration::from_millis(100)).await;
        "completed"
    }));
    eprintln!(
        "[tokio-baseline] result: {:?}, elapsed: {:.1}s",
        result,
        started.elapsed().as_secs_f64()
    );
}
