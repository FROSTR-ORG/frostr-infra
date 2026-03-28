# Documentation Guidance

## Current Expectation

Architecture and workflow docs should move with the code.

## Preferred Split

- top-level `docs/` for shared protocol, architecture, ADRs, and cross-repo guidance
- repo-local docs for implementation, build, operations, testing, and release detail

## Review Prompts

- does this change affect protocol, architecture, runtime ownership, persistence, or E2E boundaries?
- if so, which shared top-level docs should change?
- does the repo-local README/testing/API material still describe the current implementation accurately?

## Good Outcomes

- contributors can find the canonical architecture story without reading chat history
- reviewers can compare changes to the documented design
- repo-local manuals stay focused and do not drift from the top-level architecture layer
