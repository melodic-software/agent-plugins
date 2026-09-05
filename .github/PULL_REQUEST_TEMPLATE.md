Closes #

<!--
Complete the `Closes #` line above with the issue number to auto-close it on
merge, one closing keyword per issue (cross-repo:
`Closes <owner>/<repo>#<issue-number>`). Supported keywords are GitHub's:
https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue

If this PR closes no issue, replace that line with `No related issue: <reason>`
for an orphan PR (drift sweep, hotfix, refactor).

Every `##` section below must be filled with real content — HTML comments like
this one are stripped before validation, so an untouched template is reported
as missing every section rather than passing vacuously. The linkage rule is
advisory: the `pr-contract` step inside `ci-status` leaves a comment and the
`needs-issue-linkage` label instead of failing. That step's output reports the
exact rule it applied and is authoritative over this comment.
-->

## Summary

<!-- What changes and why — a sentence or two of problem context. -->

## Fix

<!-- The concrete change and how it addresses the problem. -->

## Verification

<!-- How this was proven: tests run, commands executed, evidence observed. -->

## Related

<!--
Issues, PRs, or decision records this change touches without closing
(one per line, e.g. `- Refs #<issue-number>`). If nothing applies, state
`No linked issue` and why.
-->
