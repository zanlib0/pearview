# Pearview

A 2-user household shopping-list app whose distinguishing feature is a **route-ordered, AI-categorised** list: items are grouped and ordered by the sections of whichever store the shopper picks, so the list follows the walk through that store.

## Technical

The stack is Elixir + Phoenix + HTMX (NOT LiveView).

The application uses the Masthead design system which is a custom design system.

- For detailed, agent-specific usage guide, use the `/masthead` skill for a cheat sheet.
- If specific design guidelines are needed (you are not sure what direction drive the design or add custom caller code), fetch https://raw.githubusercontent.com/zanlib0/masthead/refs/heads/master/DESIGN.md which contains design direction.
- For example usage (if you are not sure how to use specific classes), fetch https://raw.githubusercontent.com/zanlib0/masthead/refs/heads/master/index.html which contains a in-situ showcase of how the elements are used.

The project uses Gitea (CLI: `tea`) for issue tracking.

## Additional information

- See ./CONTEXT.md for a bounded context and ubiquitous language description.
- See ./docs/adr/ for Architecture Decision Records (whenever any technical decision needs to be made or questioned)
- See ./docs/prd/ for Product Requirements Documents (contains detailed descriptions of specific product areas - load only if issue is not clear enough on its own)

## Project specific guideliens
- Before working on a feature:
    - If the user asks to work on a feature that is described in a Gitea issue, fetch the issue with `tea issue [issue-number]`.
    - Assess if you have sufficient information to complete the issue unsupervised, if not, use /grill-with-docs skill to ask any questions from the user.
    - Create a new git branch named `pv[issue-number]-[description]`. Whenever you reach a reasonable checkpoint, create a commit following this format: `[scope](pv-[issue-number]): [commit message]`.
- Before you declare a feature as done:
    - Make sure `mix precommit` passes.
- When you complete a feature:
    - Push the branch (without pushing a PR cannot be created)
    - Create a PR using `tea pr create`, it should contain the word "closes" and the number of current issue.
    - Report what files were modified.
    - If I should review them chronologically commit-by-commit or if there is a good reason to not do it this way.
    - List all the test case titles that were added or modified.

## Anti-advertising clauses
You should not specify that a feature was created using an agent in the PR description or in the commit message.
