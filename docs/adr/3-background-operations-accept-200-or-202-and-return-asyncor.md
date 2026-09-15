# ADR 3: Operations that may run in the background accept 200 or 202 and return `AsyncOr`

Status: Accepted
Date: 2026-09-15


## Context

Some Notion operations can be queued instead of finished within the request. Page creation
with Markdown and Markdown page updates do this when the body carries `"allow_async": true`,
and the agent batch route in
`docs/masterplans/2-add-the-custom-agents-and-sessions-api-with-sse-streaming.md` always
does. A queued operation answers with an `async_task` object, which the caller polls with
`GET /v1/async_tasks/{task_id}`.

`docs/plans/8-add-comment-mutation-async-task-and-meeting-notes-endpoints.md` found two facts
that are not visible in the official JS SDK types:

- Notion answers a queued operation with **HTTP 202 Accepted**, not 200. The JS SDK accepts any
  2xx status, so its types say nothing about the status code.
- servant-client's `Verb` instance accepts only the verb's own status: `Post '[JSON] a` and
  `Patch '[JSON] a` reject a 202 as a `FailureResponse`, which this library's runtime turns into
  `UnknownHTTPResponseError`. `FakeNotion` test middleware bypasses that status check, so only a
  live request reveals the problem.

The first live `createPageAsync` call failed with `Request to Notion API failed with status: 202`.


## Decision

- **Task type.** `Notion.V1.AsyncTasks` owns the task type `AsyncTask`. Its status is a sum type
  with an `UnknownAsyncTaskStatus` fallback, per [ADR 1](1-tolerant-response-decoders.md). A
  failed task's error uses `APIErrorCode`, per [ADR 2](2-client-runtime-retry-policy-and-typed-errors.md).
  No other module defines an async-task type.
- **Response type.** A response that may be either the result or a task is `AsyncOr a`
  (`AcceptedAsync AsyncTask | CompletedSync a`). It decodes by the body's `object` key, not by
  the HTTP status.
- **Route type.** Routes for such operations use
  `AsyncVerb method a = UVerb method '[JSON] '[WithStatus 200 (AsyncOr a), WithStatus 202 (AsyncOr a)]`.
  `makeMethods` collapses the union with `fromAsyncUnion`, so `Methods` fields have the type
  `IO (AsyncOr a)`.
- **A route that always returns a task** (such as agent batch) must still accept 202. It uses a
  `UVerb` that lists the statuses Notion may send, not a plain `Post '[JSON] AsyncTask`.
- **Opting in.** The opt-in flag is sent by dedicated methods (`createPageAsync`,
  `updatePageMarkdownAsync`) through the `AllowAsync` request wrapper, not by a field on the
  synchronous request records. That way the synchronous methods keep their exact result types.
- **Polling.** `waitForAsyncTask` takes the retrieve function as an argument and works in any
  `MonadIO`, so the `IO` and `effectful` interfaces share it. It returns the last task it saw
  instead of throwing.


## Consequences

- A queued operation surfaces as an ordinary value that the caller must pattern-match.
- Any future endpoint that can return 202 (or 201) needs a `UVerb` route. A plain verb compiles,
  passes `FakeNotion` tests, and fails only against the real API. New endpoints that may run in
  the background should be checked live once.
- Exported Servant `API` types for these routes mention `UVerb` and `WithStatus`. Code that
  derives its own client from them receives a `Union` rather than `AsyncOr`.
