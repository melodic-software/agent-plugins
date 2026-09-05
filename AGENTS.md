# AGENTS.md

## Pull requests

`ci-status` is the single required check. It fails on a title that is not
Conventional Commits (`build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`,
`refactor`, `revert`, `security`, `style`, `test`) and on a `do-not-merge`
label. Every body opens with a closing keyword and issue (`Closes #<issue>`,
`Fixes`, or `Resolves`, cross-repo as `Closes <owner>/<repo>#<issue>`) or with
the literal `No related issue: <reason>`, then carries a non-empty
`## Summary`, `## Fix`, `## Verification` and `## Related`. The linkage rule is
advisory: a body missing the keyword or a section gets a comment and the
`needs-issue-linkage` label, not a red check. Draft the body to
`.github/PULL_REQUEST_TEMPLATE.md` before opening the pull request.
