# Contributing Guide

Thank you for your interest in contributing to ThruntOps. This is a
generic guide that details how to contribute in a way that is efficient
for everyone.

## Reporting Bugs

We use [GitHub Issues](https://github.com/enonethreezed/ThruntOps/issues)
for bug tracking. Before filing a new issue, try to make sure your
problem doesn't already exist.

If you found a bug, please report it with:

- a detailed explanation of steps to reproduce the error
- relevant configuration files or logs

If you found a bug that is better discussed in private (for example:
security bugs), please open a confidential issue or contact the
maintainer directly.

**There is no formal bug bounty program; this is an open source project
and your contribution will be recognized in the changelog.**

## Pull Requests

If you want to propose a change or bug fix via Pull Request, please
read the **DCO** section below and format your commits accordingly.

If you intend to fix a bug it's fine to submit a pull request right
away, but we still recommend filing an issue detailing what you're
fixing.

If you want to implement a new feature, please open a discussion issue
first. No pull request will be accepted without prior discussion,
regardless of whether it is a new feature, a planned feature, or a
small quick win.

## Commit Guidelines

Commit messages follow the Conventional Commits format:

```
<type> <subject>

[body]

[footer]
```

Where type is:

- `fix:` 🐛 a commit that fixes a bug
- `feat:` ✨ a commit with a new feature
- `refactor:` 🔨 a commit that introduces a refactor
- `style:` 💄 a commit with cosmetic changes
- `docs:` 📚 a commit that improves or adds documentation
- `wip:` 🚧 a work in progress commit
- `perf:` ⚡ a commit with performance improvements
- `revert:` ⏪ a commit that reverts changes
- `test:` 🚨 a commit that adds or corrects tests
- `chore:` 🧹 other changes that don't modify src or test files
- `build:` 📦 changes that affect the build system or dependencies
- `ci:` 🤖 changes to CI configuration files and scripts

Each commit should have:

- A concise subject using imperative mood
- First letter capitalised, no period at the end, no longer than 65 characters
- A blank line between the subject line and the body

Examples:

- `fix: 🐛 correct domain join failure on cloned templates`
- `feat: ✨ add MSSQL VM to range configuration`
- `docs: 📚 update architecture diagram in README`
- `chore: 🧹 rename logo file to logo.png`

More info:
- https://www.conventionalcommits.org/en/v1.0.0/#summary

## Developer's Certificate of Origin (DCO)

By submitting code you agree to and can certify the below:

```
Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

All patches should contain a sign-off at the end of the commit
description. It can be added automatically with:

```bash
git commit -s
```
