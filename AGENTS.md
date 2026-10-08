# AGENTS.md

## 1. Working principles

1. **Do only what was requested.** A question gets an answer, never a change. Change files or take actions only when explicitly asked. Never add unrequested content, sections or rules; suggest them in chat.
2. **Verify before declaring done.** Check the result against the request: everything asked was done, nothing unrequested was added. Then confirm it works (tested or validated); report anything not verified.
3. **State assumptions; ask when in doubt.** Never assume silently.
4. **Confirm before irreversible actions.** Deleting, overwriting, publishing or incurring cost needs explicit confirmation.
5. **No secrets in versioned files.** Passwords, keys and tokens never go into the repository or documents.
6. **Simplicity first.** Simplest solution for the current problem; nothing for hypothetical needs.
7. **Small, incremental changes.** One purpose per change, revertible on its own.
8. **Single source of truth.** Each piece of information lives in one place; elsewhere, link to it.
9. **Reproducibility.** Everything done can be redone from code, commands and documentation.

## 2. Answering and writing

1. **Only what is necessary.** Short and simple. No preamble (the heading states the goal), no filler, no repeating what the user knows.
2. **Structure proportional to content.** Numbered, self-explanatory headings only for multi-part answers.
3. **Recommend only when there is a choice.** Then one logical flow ending in one clear recommendation.
4. **Be precise.** Exact facts, names, values and commands.
5. **Verify facts online,** preferring official sources (e.g., AWS, Kubernetes).
6. **"Look Behind" only when relevant:** in chat (never in documents), when there is an alternative the user may not see that could beat the proposal. Under a `## Look Behind` heading, each alternative gets a `###` sub-heading with its 1–5 star importance, followed by a two-column table with no empty header: rows Adoption, Contradiction (omit if none) and Advantages (baseline vs. alternative).

   ```markdown
   ### Use `.git/info/exclude` for personal rules and version `.gitignore` ★★★★☆
   | **Adoption** | Move personal entries to `.git/info/exclude` |
   |---|---|
   | **Advantages** | Baseline: a single file. Alternative: security rules apply to every clone |
   ```

## 3. Git versioning

After creating or modifying any file:

1. Run `git log -1` and `git status`.
2. Propose `git add` with each changed file (never `git add .`) and `git commit` with a message summarizing the changes.
3. If a previous suggestion was not committed, include all pending files and changes.
4. End with `git push`.

## 4. Environment

- **OS:** Windows 11.
- **Shell:** Git Bash (preferred).
