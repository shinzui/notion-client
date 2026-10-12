-- OKF profile descriptor written by `okf profile init`.
--
-- Profile: coordination.improvementRequests
-- Source:  https://raw.githubusercontent.com/shinzui/okf-profiles/v0.15.0/package.dhall sha256:e1e7eaac9d08fd3409fe0d19057dba5634a4186733ccbf28323e9aa2a2512dc0
--
-- Existing hashes are preserved and unhashed remote value imports are frozen.
-- Local and environment inputs remain live; this is not a portable snapshot.
-- To update remote imports, remove their hashes and run `dhall freeze profile.dhall`.
-- Never hand-write a sha256 value.
let registry =
      https://raw.githubusercontent.com/shinzui/okf-profiles/v0.15.0/package.dhall
        sha256:e1e7eaac9d08fd3409fe0d19057dba5634a4186733ccbf28323e9aa2a2512dc0

in  registry.coordination.improvementRequests
