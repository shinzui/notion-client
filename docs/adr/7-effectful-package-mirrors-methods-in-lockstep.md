# ADR 7: `notion-client-effectful` mirrors `Methods` in lockstep

Status: Accepted
Date: 2026-09-15


## Context

`notion-client` exposes the API as a record of `IO` functions, `Methods`, in `src/Notion/V1.hs`.
The companion package `notion-client-effectful` re-exposes each field as an `effectful` effect.
It has a `Notion` GADT constructor and a smart constructor in
`notion-client-effectful/src/Notion/V1/Effectful/Effect.hs`, and one interpreter case in
`Interpreter.hs`. The module header promises that each smart constructor has the same name,
argument order and argument types as its `Methods` field, so migrating a call site means dropping
the `methods` argument.

Both packages live in one `cabal.project`. The parity MasterPlan
(`docs/masterplans/1-reach-parity-with-the-official-notion-js-sdk-on-the-published-rest-api.md`)
had six child plans adding or changing `Methods` fields, often in parallel.


## Decision

Any commit that adds, removes or changes a `Methods` field makes the matching change to the
effect in the same commit: the GADT constructor, the exported smart constructor with identical
name and argument types, and the interpreter case. Verification is `cabal build all`, which builds
both packages. Adding a Servant route likewise edits three places in the same order: the resource
module's `API` type, the pattern binding in `makeMethodsWithEnv`, and the `Methods` field.

`notion-client-effectful` constrains `notion-client` to the current major version. The bound
moves when `notion-client`'s major version does.


## Consequences

- A `Methods` change never leaves the effectful package out of date on any commit.
- Wrapper fields defined in `makeMethodsWithEnv`'s `where` block (for example `createPage` over
  `createPageFiltered`) still get their own effect constructors, because callers see them as
  ordinary `Methods` fields.
- A major version bump of `notion-client` must also update the bound in
  `notion-client-effectful/notion-client-effectful.cabal`.
