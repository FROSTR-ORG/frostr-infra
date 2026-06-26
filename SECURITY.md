# Security Policy

FROSTR is a threshold-signing system that handles private key material. We take
security seriously and welcome responsible disclosure.

## Reporting a Vulnerability

**Do not open a public issue for security problems.** Report privately via
**GitHub Private Vulnerability Reporting**: on the affected repository, go to the
**Security** tab → **Report a vulnerability**. This opens a private advisory
visible only to maintainers.

We aim to acknowledge reports within 72 hours and to keep you updated as we
investigate and remediate.

## Scope

FROSTR is in **public beta** and has been self-audited but has **not** undergone
an independent external security audit. The signing core (`bifrost-rs`), the
shared runtime (`igloo-shared`), and the launch clients (`igloo-pwa`,
`igloo-chrome`, `igloo-home`) are all in scope. Reference-only material
(`igloo-paper`) is out of scope.

## Supported Versions

During beta, only the latest released version of each client is supported.
