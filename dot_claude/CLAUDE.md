# Communication preferences

- Plain, direct language in all output — prose, chat replies, commit
  messages. No flattery, no praise without reason, no AI writing tells.
  For substantial prose editing, the unslop skill is the authority.
- Never add co-author trailers to commit messages.
- Never add "Generated with Claude Code" attribution (or any AI
  attribution) to GitHub issues, comments, or any other content.
- When reporting completed work, state what changed in a sentence or
  two — no recaps or restated plans.
- Match response length to the question; simple questions get direct
  answers without headers or sections.
- Challenge incorrect assumptions directly and explain why.
- When presenting three or more findings, options, risks, decisions,
  questions, or actions, assign each a short code (F1, O1, R1, D1,
  Q1, A1). Keep codes stable through the conversation. Skip codes
  for short, simple answers.
- Banned phrases: "load-bearing", "the real tension",
  "worth stating plainly", "here's the honest truth".

# Test machines

## sophon (Windows)

- Windows 11 Pro, x64, on my home network. Reach it with `ssh sophon`
  (configured in `~/.ssh/config`, key auth, no prompt). Only reachable
  when I'm on the home network. Use it for testing on Windows.
- For a PR in a project that supports Windows, run the project's test
  suite on sophon when the change could behave differently there
  (process, signal, path, encoding, or file-system code; dependency or
  Ruby version changes). Skip it for docs-only changes. Record the
  result in the PR description. If sophon is unreachable, say so and
  ask me to run it; never report a Windows run that did not happen.
- The remote shell is PowerShell 7, not cmd or bash. Write remote
  commands in PowerShell syntax and wrap them in single quotes locally
  so zsh does not expand `$` variables: `ssh sophon '$PSVersionTable'`.
  `&` backgrounds a job; chain with `;` or `&&`.
- `bash` on the PATH is the WSL launcher (Ubuntu, WSL 2), not Git Bash.
  Don't use it for Windows testing.
- Tools are managed by mise: Ruby (MRI, x64-mingw-ucrt, with `ridk`),
  Node, Python, Go, Java, Rust. Run `mise ls` for the installed
  versions and `mise use` / `mise exec ruby@<version> -- <cmd>` to pick
  one. Git for Windows and `gh` are installed.
- Repos are cloned directly under `C:\Users\james` (for example
  `process_executer`, `ruby-git`, `jruby`). Check for an existing
  checkout there before cloning, and check its branch and status before
  changing anything: it may hold work in progress.
- Machine setup lives in `C:\Users\james\sophon-config` (chezmoi,
  github.com/jcouball/sophon-config).
