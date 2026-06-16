package com.frostr.igloo

/**
 * Platform-correct relay URL defaults for the FROSTR demo harness.
 *
 * The FROSTR demo stack runs the `dev-relay` listener on port `8194` of
 * the host machine. Mobile shells map "host loopback" through different
 * aliases depending on the runtime:
 *
 * - **Android emulator** uses the special alias `10.0.2.2` because the
 *   emulator runs in a QEMU VM that cannot reach the host's `127.0.0.1`
 *   loopback directly; the alias forwards host-loopback traffic from
 *   inside the emulator. Pre-filling forms with `ws://127.0.0.1:8194`
 *   on Android leaves the user staring at a relay-connection timeout
 *   that masquerades as a network problem.
 * - **iOS Simulator** shares the host's loopback namespace, so the
 *   simulator reaches host services via `127.0.0.1`.
 *
 * The default is compile-time per platform: each platform's shell owns
 * its own `RelayDefaults.DEFAULT` literal so the right value ships with
 * the right artifact. The Rust core intentionally keeps a neutral
 * `ws://127.0.0.1:8194` default because it cannot know which shell it
 * runs inside; shells override at form initialization, not on submit.
 *
 * Forms remain editable: users can paste any reachable relay URL
 * (`ws://...` or `wss://...`) and the platform default is just the
 * suggestion that fits our own dev harness. Production relay URLs do
 * not have to match this constant at all.
 *
 * See `apps/igloo-mobile/library/mobile-platform-gotchas.md` (Android
 * Compose section) and the `mobile-android-relay-url-platform-default-fix`
 * mission feature description for the bug this constants object
 * addresses.
 */
internal object RelayDefaults {
    /**
     * Default relay URL surfaced into the Android shell forms when the
     * user has not provided an explicit URL.
     *
     * The `/10.0.2.2:8194` value is the platform-correct alias for the
     * host loopback on the Android emulator. Real devices (or remote
     * installs of the demo harness) must override this in the form; the
     * default is purely a developer-conv affordance.
     */
    const val DEFAULT: String = "ws://10.0.2.2:8194"
}
