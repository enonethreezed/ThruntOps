Agent Instructions

This project uses bd (beads) for issue tracking. Run bd onboard to get started.
Quick Reference

bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git

Landing the Plane (Session Completion)

When ending a work session, you MUST complete ALL steps below. Work is NOT complete until git push succeeds.

MANDATORY WORKFLOW:

    File issues for remaining work - Create issues for anything that needs follow-up
    Run quality gates (if code changed) - Tests, linters, builds
    Update issue status - Close finished work, update in-progress items
    PUSH TO REMOTE - This is MANDATORY:

    git pull --rebase
    bd sync
    git push
    git status  # MUST show "up to date with origin"

    Clean up - Clear stashes, prune remote branches
    Verify - All changes committed AND pushed
    Hand off - Provide context for next session

CRITICAL RULES:

    Work is NOT complete until git push succeeds
    NEVER stop before pushing - that leaves work stranded locally
    NEVER say "ready to push when you are" - YOU must push
    If push fails, resolve and retry until it succeeds

Scope And Execution Guardrails

    If anything is unclear, stop execution and resolve the decision path before continuing.
    Do not add unrequested functionality under any circumstances.
    Do not change the project idea unless an explicit change is requested.
    Do not propose changes, modifications, or improvements until all Beads tasks are closed.
