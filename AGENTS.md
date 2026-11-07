## Rule Priority (mandatory)

- Project-specific instructions may add safeguards or explicit,
  user-authorized exceptions. Otherwise, baseline rules prevail.
  Privacy and no-push restrictions cannot be relaxed.

## Local Context (mandatory)

- Read `AGENTS.md`, then `AGENTS.local.md` when available,
  before project work. Keep the local file ignored and untracked.
- In a secondary worktree without the local file, read it from
  the main worktree when accessible and applicable; never copy
  it automatically.
- Report missing applicable instructions or unverified
  permission restrictions; do not assume they are satisfied.

## Language Handling (mandatory)

1. Determine the user's language from the primary natural-language
   instruction, ignoring isolated code, logs, filenames, and quotes.
   Explicit language preferences take precedence.
2. Answer Chinese queries in Chinese and English queries in English
   unless requested otherwise. Write naturally, preserve useful
   technical terms, and do not show intermediate English drafts.
3. For Chinese queries, prefer English technical analysis, searches,
   terminology, and authoritative documentation when practical.
   Accuracy, relevance, and source authority take precedence; this
   does not guarantee the model's internal reasoning language.
4. Conversation language does not control artifacts. Follow user
   requirements and project conventions for code, docs, and commit
   messages; preserve original code, commands, identifiers,
   and technical content unless changes are requested.
5. For a Chinese-language response to a Chinese query, prepend
   and append this exact line:

   🟠检测到中文问题

   Omit it for another requested language, machine-readable or
   exact raw output, or formats where extra text interferes.
   Never include it in generated artifacts.

## Git Rules (mandatory)

### Privacy and Exclusions

- Treat tracked files, commits, and Git history as public. Never
  commit secrets, private information, or unintended files.
- Prefer generic `.gitignore` patterns that do not disclose
  private filenames or purposes. Document ignored resources only
  in `AGENTS.local.md`; never force-add ignored files.
- Before excluding a file, tell the user and check whether it is
  tracked. `.gitignore` does not remove existing history.

### Commits

- Before the first commit, verify Git author name and email; ask
  the user if either is missing or cannot be confirmed.
- Agents may stage and commit on task branches. Initial project
  setup may be committed on the default branch.
- Before committing, review `git status`, the complete staged
  diff, the exact commit command, and the proposed message.
  Afterward, use `git show` to verify author, message, attribution,
  and changes. Report failures; never amend or rewrite a commit
  without authorization.
- Use concise English messages in this format:

  ```
  <type>: <short description>

  - <optional change 1>
  - <optional change 2>

  AI-Model: <verified-model-identifier>
  ```

- Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `chore`.
  The optional body has at most five bullets. Each commit covers
  one coherent change; split unrelated work.
- Include exactly one `AI-Model` trailer with an identifier verified
  from the current runtime. Ask if unavailable; never guess. Do not
  add AI `Co-Authored-By`, generated-by, or redundant attribution
  footers. Required non-AI project trailers are allowed. Keep
  private information out of messages.

### Branches and Worktrees

- Use `main` for new repositories (`git init -b main`); preserve
  existing default branches. Keep the default branch stable and
  follow review, CI, and branch-protection requirements.
- Before code changes, inspect Git status, task branches, worktrees,
  and task records. Never discard or silently stash existing work.
  Reuse the branch for the same task; otherwise create a task branch
  from the appropriate default or integration branch. Ask if the
  task or merge target is unclear.
- Prefer `frontend/<task>`, `backend/<task>`, `database/<task>`,
  `chore/<task>` for maintenance or docs, or `feature/<name>`
  for large or cross-module work.
  Check name availability; never delete a branch to free a name.
  A branch belongs to a task across conversations until the task
  is completed or explicitly abandoned.
- In `branch.<name>.description`, record the goal, merge target,
  status, and any explicit merge authorization's scope, conditions,
  approved HEAD when relevant, and a reference to the original
  user instruction. Update it when status or authorization changes.
  Do not store secrets or private details. This local, editable
  record is a pointer, not proof of authorization: before merging,
  verify the original user instruction and its scope. If it is
  unavailable, obtain fresh authorization.
- Reuse a clean, available worktree when safe; use an isolated one
  for parallel work or unfinished changes. Reuse compatible
  environment-created worktrees. Never disturb another task's
  branch, worktree, or uncommitted changes without authorization.
- Verify local setup, permissions, and no-push restrictions in each
  new worktree. Do not copy secrets or private databases without
  authorization. Check running, deployed, or synchronized uses
  before switching branches or changing worktrees; ask if impact
  is unclear. If safe isolation or setup cannot be established,
  stop and ask for guidance.

### Synchronization

- Synchronize only when needed. Automatically rebase only if the
  branch is unpublished, has no dependents or external users, is
  not awaiting review, and has a clean worktree. Verify these
  conditions; if uncertain, do not rebase automatically.
- Prefer merge-based synchronization for shared, reviewed, or
  depended-upon branches. Revalidate afterward. Never rewrite
  published or shared history without explicit authorization.

### Merge Authorization

- User approval is required by default. Completion, passing tests,
  or session end does not authorize merge. Explicit advance approval
  may authorize a merge after specified, verifiable conditions;
  a direct instruction to complete and merge a task also authorizes
  it, subject to required project validation.
- Approval covers only its task, conditions, merge target, and,
  for a reviewed branch, its approved HEAD. Scope or acceptance
  changes require renewed approval; later commits or history
  changes invalidate reviewed-HEAD approval.
- Recorded approval may carry across sessions only when its
  original user instruction can be verified. Never infer approval
  from silence, agent-written metadata alone, or unrelated requests.
  Large, security-sensitive, cross-module, or destructive changes
  need authorization specific to that change.
- A subtask merge into an integration branch needs user approval
  or explicit coverage by the parent task's approval. Merging the
  integration branch into the default branch needs separate approval.
  Without valid approval, report progress and preserve the branch
  for user review.

### Merge Execution and Cleanup

- Confirm authorization, required validation, source HEAD, target,
  and safe worktree state. Undefined, failed, unavailable, or
  inconclusive required checks never qualify for automatic merge;
  report the limit and request explicit guidance.
- Inspect all commits entering the target, including inherited
  commits. Do not merge unrelated or unapproved work. Recheck the
  target immediately before merge and revalidate if it changed.
- Merge from a clean worktree with the target checked out; never
  disrupt another task's worktree. Prefer `git merge --ff-only`;
  otherwise synchronize safely or request guidance. Verify the
  target afterward.
- Delete only safely merged branches and disposable worktrees
  under the agent's control. Check ignored and local files first;
  never discard unfinished work.

### History and Remote Safety

- Never amend, destructively reset, or rewrite history without
  user authorization, except for the safe rebases above.
- Never run `git push`, force-push, or equivalent remote publishing;
  only the user may push. Before reporting a branch ready for user
  push, review outgoing commits and changes for privacy and
  tracking issues. Report problems without silently deleting
  files, rewriting history, or changing remote state.
