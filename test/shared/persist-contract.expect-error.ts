// Negative/adversarial type test for the persist contract (ADR-013 P1). This file
// is compiled by the normal `test:typecheck` lanes; it has no runtime role.
//
// The whole point of routing profile seeds through `PersistableStoredProfile` is
// that a seed setting a field the app would NOT persist must fail to compile. We
// assert that here with `@ts-expect-error`: if the contract still rejects the
// non-persisted field, the error is expected and this file compiles clean; if a
// future change ever defangs the contract (the field stops being rejected), the
// `@ts-expect-error` becomes unused and the typecheck FAILS — surfacing the
// regression. In other words, this test passing is what proves the guard's teeth.
import type { PersistableStoredProfile } from '../../repos/igloo-shared/src/persist-contract';

declare const validSeed: PersistableStoredProfile;

// `stored_password` is a cleartext secret the app never persists; the contract
// must reject it as an excess property. The directive sits immediately before the
// offending property (where TS reports the excess-property error).
export const seedWithNonPersistedField: PersistableStoredProfile = {
  ...validSeed,
  // @ts-expect-error - stored_password is not a persistable profile field
  stored_password: 'this-must-not-typecheck',
};
