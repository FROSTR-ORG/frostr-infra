# Testing Guidance

## Layering

- repo-local unit and integration tests should live with the code they verify
- cross-repo browser and live-runtime tests should live in top-level `test/`

## Preferred E2E Shape

- build shared artifacts once before the suite
- reuse worker-scoped live fixtures where safe
- keep onboarding worker-scoped unless a test is explicitly about onboarding
- reserve isolated live startup for tests that truly require fresh single-use onboarding material

## Review Prompts

- is this behavior covered at the lowest useful layer first?
- does this browser test really need a fresh live backend?
- is a cross-repo test being added in the right place?
- does the change keep the E2E harness fast enough to stay practical?
