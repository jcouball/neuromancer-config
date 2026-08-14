# neuromancer-config

Configuration for **Neuromancer**, an Apple Silicon Mac used for Ruby, Go and
JRuby development. Managed with [chezmoi](https://chezmoi.io).

Companion to [jcouball/sophon-config](https://github.com/jcouball/sophon-config)
(Windows 11). This repo is scoped to one machine deliberately: no OS templating,
every file is simply the file. The cost is that `.gitconfig`, `.tool-versions`
and `topgrade.toml` now exist in two repos and will drift; the benefit is that
nothing here needs a conditional.

| | |
| --- | --- |
| Host | Neuromancer — Apple M2 Max, macOS Tahoe 26.6.1 |
| Shell | zsh + powerlevel10k |
| Terminal | Warp (installed by `.Brewfile`; its settings cannot be versioned) |
| Package manager | Homebrew — 84 formulae, 37 casks, 49 VS Code extensions, 14 App Store apps |
| Runtimes | asdf, 5 tools |
| Rebuild | **certified** 2026-08-14 on a clean VM, except the App Store layer |

---

## Contents

- **Do something**
  - [Rebuild from nothing](#rebuild-from-nothing) — the emergency procedure
  - [Playbooks](#playbooks) — everyday tasks, grouped by the layer that owns them
- **Understand it**
  - [System tools vs project runtimes](#system-tools-vs-project-runtimes)
  - [The stack](#the-stack) — the layers, and who owns what
  - [Repository layout](#repository-layout) — every file, and two path traps
  - [Which shell](#which-shell)
  - [Recreating this repo from scratch](#recreating-this-repo-from-scratch) — not the machine
  - [How often to run what](#how-often-to-run-what)
- **Why it is the way it is**
  - [Ownership decisions](#ownership-decisions)
  - [Certification](#certification) — what a clean machine found
  - [Secrets](#secrets)
  - [Deliberately not managed](#deliberately-not-managed)
  - [Small gotchas](#small-gotchas)

---

## Rebuild from nothing

**The emergency procedure.** On a freshly installed Mac, with nothing else
installed and no prerequisites beyond macOS itself:

```bash
# 1. Homebrew. Its installer pulls in the Command Line Tools on the way.
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. chezmoi.
eval "$(/opt/homebrew/bin/brew shellenv)"
brew install chezmoi

# 3. Everything else.
chezmoi init --apply jcouball/neuromancer-config
```

Step 3 asks one question — what this machine is called — and then does the rest:
Rosetta, the Brewfile, the runtimes, every config file, the JDK link.

**Sign in to iCloud and the App Store first**, if you want the App Store apps.
They are separate sign-ins and only the second satisfies `mas`. Skipping it
costs nothing else: the run completes, and the 14 App Store entries can be
picked up later with `brew bundle --file="$HOME/.Brewfile"`.

Afterwards, by hand — the parts a script cannot do:

1. **Redo Warp's settings.** Warp is installed by `.Brewfile`, but it keeps its
   configuration in a binary SQLite database with no file to version, so a
   rebuilt machine gets the application and none of your setup. This is the
   single largest thing a rebuild does not restore — see
   [Deliberately not managed](#deliberately-not-managed).
2. **Sign in to 1Password** and enable its CLI integration, if you use the
   `op`-templated files — see [Secrets](#secrets).

### Why three commands and not one

There was a `provision.sh` here, fetched with `curl | sh`. It is gone, and the
reason is worth keeping.

A hosted bootstrap script has to be delivered by `raw.githubusercontent.com`,
which **caches for about five minutes**. Fix the script, push, rebuild, and the
machine fetches the previous version — so it fails for the reason you just
eliminated, with a log byte-identical to the last run. That cost a full
certification cycle.

`chezmoi init` clones over **git**, which has no cache. What the machine gets is
always what was last pushed. The bootstrap also stops depending on a script this
repo hosts: the only `curl` left points at Homebrew's own installer, which is
their problem to keep working, not yours.

It also matches [sophon-config](https://github.com/jcouball/sophon-config),
whose bootstrap is the same shape — install chezmoi, then `chezmoi init --apply`
— so the two repos are rebuilt the same way on both platforms.

The cost is one command becoming three. In an emergency that is arguably the
better trade: three short commands you can retype from memory beat one long URL
that has to be transcribed exactly.

This path is **certified** — run end to end on a clean macOS VM, as a user who
is not `james`, from nothing but a fresh macOS install. See
[Certification](#certification) for what that took and what it cannot cover.

---

## Playbooks

The rule underlying all of them: **the repo must never lag the machine.**
Whenever you install, remove or re-pin something, the corresponding file goes
back into the repo in the same sitting.

### Layer 2 — applications and core tools

#### Install an application

```bash
brew install <formula>            # or: brew install --cask <cask>
brew bundle dump --global --force
chezmoi re-add ~/.Brewfile
chezmoi cd; git commit -am "Add <name>"; git push
```

`brew bundle dump` rewrites `~/.Brewfile` from what is actually installed, so
the snapshot and the machine cannot disagree. The descriptive comment above each
entry — most of what makes that file readable — is included by default now;
`--describe` still works but is deprecated.

#### Uninstall an application

```bash
brew uninstall <formula>          # or: brew uninstall --cask <cask>
brew bundle dump --global --force
chezmoi re-add ~/.Brewfile
chezmoi cd; git commit -am "Remove <name>"; git push
```

The Brewfile has **no cleanup semantics** during a normal apply. Deleting a line
never uninstalls anything; it only stops a rebuild reinstalling it. To actually
remove what is no longer declared, `brew bundle cleanup --global` — and read the
list before confirming.

#### Install an App Store app

```bash
mas install <id>
brew bundle dump --global --force
chezmoi re-add ~/.Brewfile
```

Find the id with `mas search <name>`. These are the entries a VM rebuild cannot
verify — see [Certification](#certification).

#### Hold a version back

```bash
brew pin <formula>
brew list --pinned
brew unpin <formula>
```

Casks cannot be pinned. For those, exclude them from topgrade instead.

### Layer 3 — language runtimes

#### Upgrade a language version

```bash
asdf install ruby 4.0.7
asdf set --home ruby 4.0.7
chezmoi re-add ~/.tool-versions
chezmoi cd; git commit -am "ruby 4.0.6 -> 4.0.7"; git push
```

`asdf set --home` rewrites `~/.tool-versions`, so that file must go back to the
repo — it is the declaration a rebuild replays. The plugin list is derived from
it, so there is nothing else to update.

#### Add a new runtime

```bash
asdf plugin add deno
asdf install deno latest
asdf set --home deno latest
chezmoi re-add ~/.tool-versions
```

#### Pin a runtime for one project

```bash
cd ~/src/my-project
asdf set ruby 4.0.6
asdf install
```

No `--home`. That file belongs to the *project's* repo, never to this one.

#### Retire a runtime

```bash
asdf uninstall ruby 4.0.6
asdf plugin remove deno          # if nothing else needs it
chezmoi re-add ~/.tool-versions
```

### Layer 4 and the editor

#### Install a global CLI tool

```bash
npm i -g prettier
gem install rubocop
```

These live *inside* the runtime asdf installed, so re-pinning that runtime loses
them. Record anything you would miss in `~/.default-npm-packages`, which asdf's
nodejs plugin replays on every new Node install.

#### Install a VS Code extension

```bash
code --install-extension <publisher.name>
brew bundle dump --global --force
chezmoi re-add ~/.Brewfile
```

Homebrew's Brewfile records VS Code extensions as `vscode` lines, so they are
part of the same snapshot as everything else. **Do not also enable Settings
Sync for extensions** — two managers, one list, no arbiter.

### chezmoi

#### Change a managed config

```bash
chezmoi re-add ~/.zshrc
# or, from the source side:
chezmoi edit ~/.zshrc --apply
```

#### Start managing a new file

```bash
chezmoi add ~/.some-config
chezmoi cd; git commit -am "Manage some-config"
```

#### Stop managing a file

```bash
chezmoi forget ~/.some-file
```

`forget` drops it from the repo and leaves your copy alone. `destroy` deletes
both — be sure.

#### Update everything

```bash
topgrade --dry-run
topgrade
```

#### Find out what drifted

```bash
chezmoi status
chezmoi diff
./certification/verify.sh    # the stronger version: checks outcomes, not files
```

#### Pull changes made elsewhere

```bash
chezmoi update --dry-run
chezmoi update
```

### Upgrading macOS

#### Minor update (26.6.1 → 26.7)

Already covered — topgrade's `only` list includes `system`, so the weekly sweep
takes it. Afterwards, if new terminals start complaining about `xcrun`, the
Command Line Tools came unregistered:

```bash
sudo xcode-select --reset
xcrun --show-sdk-path        # should print a path
```

No re-certification: the bootstrap path did not change.

#### Major upgrade (26 → 27)

In order:

```bash
brew update && brew upgrade && brew doctor
sudo xcode-select --install            # usually needed again
asdf uninstall ruby 4.0.6 && asdf install    # and likewise python
pgrep oahd || sudo softwareupdate --install-rosetta --agree-to-license
./certification/verify.sh
```

1. **Homebrew publishes bottles per major OS.** Until they land, formulae build
   from source, slowly. Casks carrying system extensions often need a reinstall
   rather than an upgrade.
2. **The Command Line Tools usually need reinstalling**, which breaks `xcrun`,
   and therefore `SDKROOT`, and therefore every new shell until fixed.
3. **Rebuild the compiled runtimes.** Ruby and Python were built against the old
   SDK and are the most common post-upgrade breakage.
4. **Rosetta survives**, but `run_once_01` will not reinstall it if it does not —
   see [Small gotchas](#small-gotchas).
5. Update the macOS version in the host table at the top of this file.
6. **Re-certify, and rebuild the base VM.**

That last point is the one that is easy to skip. A guest cannot be newer than
its host, so the existing base image still boots but no longer represents the OS
you would actually reinstall onto. **A major host upgrade is a change to the
bootstrap path even though no file in this repo changed** — it changes Setup
Assistant, the available bottles, and the SDK the runtimes compile against. It
triggers re-certification exactly as editing a provisioning script would.

### Re-certify the rebuild

Do this after **any change to the bootstrap path**: an edited provisioning
script, a new package manager, a change to `.chezmoi.toml.tmpl`, a renamed repo,
or a major macOS upgrade. Not needed for adding a package or bumping a runtime —
those exercise proven ground.

**Also re-certify when `verify.sh` gets stricter.** A tightened check invalidates
the badge exactly as surely as a changed script, because the previous run passed
a test that no longer exists. This is easy to miss: nothing about the machine
changed, so it does not feel like a change at all. It happened immediately after
the first certified run — the VS Code check moved from comparing totals to
checking each declared extension by name, and the certified run had never been
asked that question.

```bash
./certification/certify.sh
```

That clones the pristine base VM, boots it, runs the bootstrap **unmodified**
from this README's URL, and then verifies. Transcripts land in
`certification/logs/` — without a log, failures have to be inferred from
wreckage.

Verify **outcomes, not exit codes**. A script returning zero has proved nothing;
that is the entire argument of [Certification](#certification), and it is why
`certify.sh` verifies even when the bootstrap exits non-zero.

---

## System tools vs project runtimes

> I use Topgrade to manage overall system and core tools, not the dependencies
> for individual software projects. This prevents a global update from
> accidentally breaking a project that depends on specific package versions.
>
> — from `dot_config/topgrade.toml`

**System and core tools** can be swept forward in bulk. **Project runtimes** are
pinned, and are never upgraded by a command that also upgrades your browser.
When adding something new, that question decides which layer owns it.

### Why `neuromancer-config` and not `dotfiles`

"dotfiles" names the mechanism, not the scope, and it is only half true here:
plenty of what this repo manages is not dot-prefixed, and plenty of it is not a
file at all — Rosetta, the computer name, the runtimes asdf materialises.
`neuromancer-config` leads with the scope (the machine), matches
`sophon-config` so the pair reads as one system, and stays tool-agnostic, so it
survives if chezmoi is ever replaced.

The old name still redirects for `git clone` and for web traffic. **The
`raw.githubusercontent.com` URL in the bootstrap one-liner is the part that
matters**, though, and it is served by a different, heavily-cached host whose
behaviour on renamed repositories GitHub does not document.

Measured immediately after the rename, the old raw URL returned `200`:

```console
$ curl -fsIL -o /dev/null -w '%{http_code}\n' \
    https://raw.githubusercontent.com/jcouball/dotfiles/main/README.md
200
```

That is **encouraging but not conclusive** — a response that recent is
indistinguishable from a cache hit. Treat the old URL as unreliable, use the
new one everywhere, and if you ever want a real answer, re-run that `curl` well
after a cache lifetime has passed.

One rule regardless: **never create a new repository called `dotfiles`.** Doing
so permanently breaks the redirect for everything that still points at the old
name, including any copy of the old bootstrap line you are reading in an
emergency.

---

## The stack

| Layer | Tool | Owns |
| --- | --- | --- |
| 0 | git + gh | **Transport.** If a setting exists only on the machine and not here, it is not managed and will be lost. |
| 1 | **chezmoi** | **Declaration and orchestrator.** Config file contents, and the manifest of what should be installed. Its scripts call the layers below; it installs nothing itself. |
| 2 | **Homebrew** (+ `mas`) | **Applications and stable CLI tools.** Formulae, casks, VS Code extensions and App Store apps, all from `.Brewfile`. |
| 3 | **asdf** | **The five runtimes** — go, node, python, ruby, rust. Pinned exactly in `.tool-versions`; never swept. |
| 4 | npm · gem · cargo · pip | **Libraries and runtime-scoped tools.** Subordinate to layer 3: re-pin a runtime and these go with it. |
| 5 | **topgrade** | **Owns nothing.** Dispatches layers 2 and 4 plus macOS updates, VS Code, gh extensions and chezmoi. |

### How the layers call each other

```text
        github.com/jcouball/neuromancer-config
                       │
                       │  chezmoi update
                       ▼
                    chezmoi                 renders files, runs scripts
                       │
                       │  scripts invoke
          ┌────────────┼────────────┐
          ▼            ▼            ▼
       Homebrew       asdf     npm · gem · cargo
      apps & CLI    runtimes       libraries
          ▲            ▲            ▲
          └────────────┼────────────┘
                       │
                    topgrade                updates, never installs
```

Top-down is **provisioning**. Bottom-up is **maintenance**. The rule that keeps
it coherent: **topgrade never introduces anything new.** If a tool appears on
this machine that isn't in the repo, the system has a hole in it.

### Ownership rules

| Situation | Owner | Recorded in |
| --- | --- | --- |
| GUI app or stable CLI tool | Homebrew | `dot_Brewfile` |
| App Store app | `mas`, via Homebrew | `dot_Brewfile` (`mas` lines) |
| VS Code extension | Homebrew | `dot_Brewfile` (`vscode` lines) |
| Language runtime, version matters | asdf | `dot_tool-versions` |
| Library inside a runtime | npm / gem / cargo | `dot_default-npm-packages` etc. |
| Config file contents | chezmoi | the `dot_*` file itself |

---

## Repository layout

```text
README.md                          this document (ignored, not deployed)
LICENSE.txt                        MIT (ignored)
.chezmoi.toml.tmpl                 asks the machine's name once, at init
.chezmoiignore                     keeps the four above out of the home directory
.gitattributes                     * text=auto eol=lf

dot_Brewfile                       84 formulae, 37 casks, 49 extensions, 14 App Store apps
dot_tool-versions                  the five pinned runtimes
dot_default-npm-packages           replayed on every new Node install
dot_asdfrc                         asdf behaviour

dot_zshenv                         always sourced: JAVA_HOME, path_helper
dot_zprofile                       login shells: Homebrew, asdf, ~/.local/bin
dot_zshrc                          interactive shells: p10k, completions, aliases
dot_p10k.zsh                       the prompt (generated by `p10k configure`)
empty_dot_zlogin                   deliberately empty
dot_profile / dot_bash_profile / dot_bashrc    bash equivalents

dot_gitconfig                      identity, editor, aliases
dot_gitignore / dot_gitignore_global
private_dot_ssh/private_config     SSH config; the keys themselves are not managed
dot_config/topgrade.toml           update policy
dot_homebrew/brew.env              HOMEBREW_NO_ANALYTICS
dot_pip/pip.conf
empty_dot_irbrc

.chezmoiscripts/
  run_once_01_install_rosetta.sh.tmpl                Rosetta 2
  run_onchange_after_02_brew_bundle_install.sh.tmpl  everything in .Brewfile
  run_onchange_after_03_asdf_plugin_add.sh.tmpl      plugins, derived from .tool-versions
  run_onchange_after_04_asdf_tool_install.sh.tmpl    the runtimes themselves

certification/
  certify.sh                       host side: clone a VM, rebuild it, verify it
  verify.sh                        guest side: assert outcomes, not exit codes
  logs/                            transcripts (gitignored)
```

### Two path traps

**Anything in the source root without a leading dot becomes a target.**
`README.md`, `LICENSE.txt` and `certification/` would all be written into the
home directory; all three are in `.chezmoiignore`. This is not
hypothetical — `README.md` was missing from that list for a long time, and
`~/README.md` was quietly a copy of this file. Dot-prefixed source entries are
ignored by chezmoi automatically, which is why real dotfiles need the `dot_`
prefix.

**The `after_` attribute is required, not stylistic.** chezmoi applies targets in
ASCII order of target name, and a script's target name includes its
`.chezmoiscripts/` prefix. So the numeric prefixes on the script filenames order
the scripts *relative to each other* and nothing else — what decides whether a
script runs before or after a managed file is the letter `c`:

| Target | First letters | vs `.chezmoiscripts/` |
| --- | --- | --- |
| `.Brewfile` | `.B` (0x42) | **before** — script 02 sees it |
| `.chezmoiscripts/…` | `.c` (0x63) | — |
| `.tool-versions` | `.t` (0x74) | **after** — scripts 03 and 04 do *not* see it |

That is not a theory. Applying a stripped-down copy of this repo to an empty
destination, with one script carrying `after_` and one without:

```text
NO-AFTER script: .tool-versions exists? NO;  .Brewfile exists? YES
AFTER script:    .tool-versions exists? YES; .Brewfile exists? YES
```

Every script that reads a chezmoi-managed file therefore uses `run_..._after_`,
which runs it once every file has been written. See
[Certification](#certification) for what this cost before it was fixed.

---

## Which shell

Keep the two ideas separate: the **terminal** is the window, the **shell** is
what runs in it.

**zsh is the shell**, macOS's default, with
[powerlevel10k](https://github.com/romkatv/powerlevel10k) for the prompt. The
bash files exist because scripts and older tooling still land in bash, not
because anything is run there interactively.

**Warp is the terminal.** It is declared as a cask in `.Brewfile`, so a rebuild
installs it — but its settings live in a binary SQLite database and cannot be
versioned, so a rebuild does not restore them.

That is a real cost, and it was accepted deliberately. This repo previously
carried an iTerm2 preferences plist, and iTerm2's settings *can* be versioned —
which was a genuine argument for it as the primary terminal. The argument lost
to preferring Warp day to day. What the repo cannot do is manage the settings of
a terminal you do not use: that plist was for an application that was not
installed and not declared anywhere, and it survived only because a stale
`com.googlecode.iterm2` defaults domain made it look live.

### Which zsh file, and why

This is the part that is easy to get wrong, because the three files are sourced
in different circumstances and by different kinds of shell:

| File | Sourced by | Holds |
| --- | --- | --- |
| `.zshenv` | **every** zsh, including non-interactive ones | `JAVA_HOME`, `path_helper`. Things a script invoked by an app must see. |
| `.zprofile` | login shells | Homebrew's `shellenv`, asdf's shims, `~/.local/bin`. |
| `.zshrc` | interactive shells | The prompt, completions, aliases, options. |

asdf is initialised in `.zprofile` rather than `.zshrc` deliberately: a
non-interactive shell — a git hook, a `Makefile`, an editor task — never reads
`.zshrc`, and without the shims on `PATH` it gets the system Ruby instead of the
pinned one, which fails in confusing ways much later.

**Everything that touches Homebrew or the Command Line Tools is guarded.** Those
files are written by chezmoi during the very first apply, *before* Homebrew and
the runtimes exist, so an unguarded `eval "$(brew shellenv)"` or
`xcrun --show-sdk-path` errors on every shell you open during provisioning.

---

## Recreating this repo from scratch

Only needed to recreate the *repo*; a rebuild of the *machine* is the one
command at the top.

1. **Install Homebrew and chezmoi.**
   `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`,
   then `brew install chezmoi gh`, then `gh auth login`. Neither will be on
   `PATH` in an already-running shell — start a new terminal.
2. **Create the repo.** `gh repo create jcouball/neuromancer-config --public`
3. **Initialise.** `chezmoi init jcouball/neuromancer-config`
4. **Set line endings before the first commit.** `chezmoi cd`, then write
   `.gitattributes` containing `* text=auto eol=lf`.
5. **Capture the package set.** `brew bundle dump --global --force`,
   then `chezmoi add ~/.Brewfile`.
6. **Capture the runtimes.** `chezmoi add ~/.tool-versions ~/.asdfrc`
7. **Add configs.** `chezmoi add ~/.zshrc ~/.zprofile ~/.zshenv ~/.gitconfig` …
8. **Add `.chezmoiignore`** before anything non-dot-prefixed exists in the source
   root, or you will deploy this README to your home directory.
9. **Review, then apply.** `chezmoi diff`, then `chezmoi apply -v`
10. **Push.** `chezmoi cd; git add -A; git commit; git push -u origin main`
11. **Certify.** Build the base VM and run `./certification/certify.sh`. Until
    that passes, the repo is a backup, not a rebuild.

---

## How often to run what

| When | Command | Why |
| --- | --- | --- |
| Immediately after editing any config by hand | `chezmoi re-add` | The single habit that makes this work. Skip it once and the repo starts lying to you. |
| Immediately after `brew install` / `uninstall` | `brew bundle dump --global --force` | Install, then re-snapshot. Commit both together. |
| Weekly | `topgrade` | Sweeps Homebrew, App Store, macOS, VS Code, gh extensions, and pulls this repo. |
| Weekly, before topgrade | `chezmoi status` | Catches files changed on disk that never made it back. |
| Monthly | `./certification/verify.sh` | The stronger audit: proves the machine still matches the repo in outcome, not just in file contents. |
| Per project | `asdf install` | Runtimes are project-scoped. Never on a schedule. |
| After any bootstrap-path change | `./certification/certify.sh` | See [Re-certify the rebuild](#re-certify-the-rebuild). |

---

## Ownership decisions

### Runtimes belong to asdf, applications belong to Homebrew

The line is version sensitivity. If a project can break because a tool moved
from 4.0.6 to 4.0.7, asdf owns it and it is pinned in `.tool-versions`. If it
cannot — `ripgrep`, Chrome, Warp — Homebrew owns it and topgrade may sweep it
forward without asking.

The one place this gets subtle is Node: `.Brewfile` declares
`brew "node", link: false`. Some formulae depend on a Node being present, so it
is installed, but leaving it unlinked keeps it off `PATH` where it would shadow
the asdf-managed version. **If `brew bundle check` ever reports "node needs to
be unlinked", that shadowing has come back** — `brew unlink node` fixes it.

### VS Code extensions belong to the Brewfile, not Settings Sync

Homebrew's Brewfile records extensions as `vscode` lines, so they ride along with
the same snapshot as everything else and a rebuild reproduces them. Settings Sync
would do the same job from a different source of truth; running both produces
conflicts with no arbiter. Sync is fine for *settings* — this is about the
extension list.

### `mas` for App Store apps, accepting that it cannot be certified

The 14 App Store apps are declared in `.Brewfile` like everything else, which
keeps one manifest rather than two. The price is that they are the only part of
a rebuild a VM cannot prove — see below.

---

## Certification

A clean `chezmoi diff` proves the repo describes this machine. It says nothing
about whether the repo can *produce* one. So the rebuild is run against a
throwaway macOS VM, as a user who is not `james`.

### The certified run

| | |
| --- | --- |
| Date | 2026-08-14 |
| Commit | `4a2974c` |
| Guest | macOS Tahoe 26.6.1, 6 CPU / 8 GB / 100 GB, user `certuser` |
| Result | **40 passed, 0 failed, 2 warnings** |

The warnings are the three things an Apple Silicon VM structurally cannot do —
the 14 App Store apps, `zoom`, and `postgresql@17`'s service — each named
individually by `verify.sh` rather than waved away, and each to be checked on
real hardware.

It took six runs. One repo defect was found by the very first bootstrap that
executed; three more were found once it got further; and four were defects in
the harness itself, which is its own lesson. The table below is the whole
inventory.

### What a clean machine found

Every one of these was invisible on Neuromancer, and all of them sat in the
recovery path you would only exercise under pressure.

| Defect | Why the live machine masked it |
| --- | --- |
| **Parallel `brew bundle` installs raced each other**, failing with `ENOTEMPTY: directory not empty` — an extension pack and its own members unpacking into the same directory at once | one machine, installed once, over years; a rebuild does all 121 at speed and in parallel |
| **One failing cask aborted the entire rebuild.** Zoom's installer fails inside a VM; `brew bundle` exited non-zero, script 02 died under `set -e`, chezmoi stopped the apply, and scripts 03, 04 and 05 never ran — leaving a machine with every application and no runtimes at all | on a real Mac every package installs, so the abort path was never taken |
| `pgrep oahd` reported a working Rosetta as "not installed" | the daemon runs only while something is being translated, and the live Mac is always translating something |
| **The asdf scripts ran before `~/.tool-versions` existed, installed nothing, and exited zero** | `run_once_` had already fired once, years ago, on a machine where the file happened to exist — so it could never run again, and never fail again |
| Both asdf scripts sourced `$(brew --prefix asdf)/libexec/asdf.sh`, which asdf 0.16 deleted | asdf was already on `PATH`, so the dead `source` line looked like it worked |
| `brew bundle` could never re-run — `run_once_` meant a package added to `.Brewfile` was never installed | packages were added by hand at the same time, so the repo and the machine agreed by coincidence |
| `softwareupdate --install-rosetta` stopped on a licence prompt | Rosetta already installed, so the script exited early every time |
| `brew bundle` aborted entirely when the App Store was not signed in | always signed in |
| `README.md` was missing from `.chezmoiignore` and was deployed to `~/README.md` | harmless-looking, and invisible unless you list your home directory |
| `.gitconfig` hardcoded `excludesfile = /Users/james/...` | correct for exactly one user — the one who never noticed |
| `JAVA_HOME` pointed at a GraalVM install that no longer existed | nothing in daily use read it, so a dead path survived for years |
| `xcrun --show-sdk-path` and the powerlevel10k `source` were unguarded | both dependencies were long since installed |
| `.profile` sourced `~/.cargo/env` unguarded | Rust was installed before that file was ever read on a cold machine |
| `provision.sh` (since removed) appended `brew shellenv` to `~/.zprofile`, which chezmoi then overwrote | the line was already in `dot_zprofile`, so the wrong code produced the right result |
| `provision.sh` (since removed) skipped the apply entirely if `~/.local/share/chezmoi` existed | a second run was never needed, because the first had never failed |
| `wait_for_icloud_login` looped forever with no timeout | a human was always sitting there to sign in |
| `provision.sh --unattended` (since removed) refused to start on a correctly configured machine, because it probed with `sudo -n -v` | never run unattended; interactively `sudo -v` is correct, and the difference only shows up under NOPASSWD, where there is no credential to cache |
| An iTerm2 preferences plist was managed for an application that was not installed and not declared | a leftover `com.googlecode.iterm2` defaults domain still answered `defaults read`, so the config looked live long after the app was gone |

### The one that justifies the exercise

The asdf install script had no `after_` attribute, and it was not merely
theoretically wrong — it **ran before chezmoi had written `~/.tool-versions`**.
`.chezmoiscripts/` sorts before `.tool-versions`, as the table in
[Repository layout](#two-path-traps) shows and as a controlled apply confirms.

So on a genuinely clean machine, `asdf install` read no configuration, found
nothing to install, and exited **zero**.

The run would finish clean. No error, no warning, no missing step — and the
machine would have had no Ruby, no Node, no Go, no Python and no Rust,
discovered whenever you next tried to work. Every other defect in the table
announces itself. This one reported success.

It was invisible here for the most ordinary reason: `run_once_` meant it had
executed exactly once, long ago, on a machine where `~/.tool-versions` already
happened to exist. It could never run again, so it could never fail again.

Two fixes, because one is not enough. The `after_` attribute makes the ordering
correct. The check at the bottom of script 04 makes it *provable* — it reads
`asdf current` and fails if any declared tool is not installed, so the script
can no longer report success without having done anything. This is also why
`certify.sh` runs `verify.sh` **even when the bootstrap exits non-zero**, and
why `verify.sh` checks that `ruby` resolves to an asdf shim rather than merely
that asdf is installed.

### The raw CDN serves stale scripts

`raw.githubusercontent.com` caches for around five minutes. When the bootstrap
was a `provision.sh` hosted here, pushing a fix and re-running certification
immediately meant the VM fetched the **previous** version — so the run failed
for the exact reason just eliminated, with a bootstrap log byte-identical to the
one before it. That reads as "the fix did not work" rather than "the fix was not
there", and it cost a full cycle.

The workaround was to fetch by commit SHA, which is immutable. The actual fix
was to stop hosting a bootstrap script at all: `chezmoi init` clones over git,
which has no cache. See
[Why three commands and not one](#why-three-commands-and-not-one).

### The harness fell for it too

Worth recording, because it is the same defect wearing different clothes.

The first complete run printed **✅ CERTIFIED** against a VM with no Homebrew,
no chezmoi and not one managed file. `certify.sh` had piped `verify.sh` into
`bash -s` over SSH, which makes stdin the script itself — so the first check
that read stdin (`script`, used to get a pty for the interactive-shell test)
consumed the rest of the file. bash hit EOF partway through, exited 0 because
the last command it had managed to run succeeded, and ssh reported success. The
harness believed it.

That is exactly the failure the asdf script had: *a zero exit from a program
that never did the work* — written into this repo by someone who had spent the
day documenting that precise hazard.

Two fixes, because one is never enough for this class of bug. `verify.sh` is now
copied to the guest and run as a file, so nothing can consume it. And it prints
`VERIFY-COMPLETE` as its final act, which `certify.sh` requires — a run that
dies partway through can no longer be mistaken for a clean one. **A zero exit is
not evidence; positive proof of completion is.**

### What is not deterministic

A certified run proves the **procedure** works. It does not promise the next
rebuild produces the same machine, and it is worth being clear about why.

**Almost nothing is version-pinned.** Two entries in `.Brewfile` carry a version
in the formula *name* — `openssl@3`, `postgresql@17` — and that is all. The
other 119 install whatever is current on the day. Only `.tool-versions` pins
exactly, which is the point: versions matter for the runtimes a project builds
against, and not for `ripgrep`. A rebuild next month gives a working machine
with different bytes, and that is the intended trade.

**Parallel installs race, and which ones race is luck.** The certified run had
five entries fail the parallel pass — `postgresql@17`, `shellcheck`,
`tyriar.sort-lines`, `usernamehw.errorlens`, `vscjava.vscode-java-test` — and
four installed cleanly on the serial retry. A different run collides on a
different set. The retry turns a random failure into a random slowdown; it does
not make the first pass deterministic, and two collisions on the same entry in
a row remain possible.

**The network is a dependency.** Homebrew's installer, the git clone, 121
downloads and the asdf plugin clones all have to succeed. Only `brew bundle`
retries. asdf plugins are cloned at HEAD, so plugin code itself changes between
runs.

**`--from-ipsw=latest` moves.** The base image is fixed once built — never
booted, automatic updates declined — but rebuilding it later gets a different
macOS. Record which IPSW a base image was built from if that matters.

What *is* deterministic, and deliberately so: script ordering (explicit
`after_`, not luck), the base image itself, `run_once` state (every run is a
fresh clone), and the Rosetta check (`arch -x86_64`, which tests behaviour
rather than a daemon that comes and goes).

The practical consequence: **certification has a shelf life.** It says the
procedure worked against the world as it was that day. That is why
re-certification is triggered by changes to the bootstrap path *and* by a major
macOS upgrade — the ground moves underneath a claim that was true when made.

### What certification cannot cover

**The Mac App Store cannot be signed into inside a VM.** This is a restriction
in Apple's Virtualization framework, not a limitation of the tooling, and it
applies to every virtualization product on Apple Silicon. Apple Account and
iCloud sign-in *do* work, provided host and guest both run macOS 15 or later.

So the 14 `mas` entries in `.Brewfile` are excluded from certification, via
`HOMEBREW_BUNDLE_MAS_SKIP`, whose ids `verify.sh` derives from `.Brewfile`
itself so there is no second list to drift. `verify.sh` reports them as a
warning rather than silently passing over them. **They must be checked on real
hardware.**

Two more entries turned out to be structurally impossible in a VM, and are
named individually in `verify.sh` rather than waved away — an exception you
cannot enumerate is indistinguishable from a bug you have stopped noticing:

| Entry | Why a VM cannot do it |
| --- | --- |
| **zoom** | The installer package's postinstall scripts fail. `installer` reports "An error occurred while running scripts from the package". It installs fine on real hardware. |
| **postgresql@17** | `restart_service` needs a GUI launchd domain. Over SSH there is no Aqua session, so `launchctl enable gui/501/homebrew.mxcl.postgresql@17` exits 125 with "Domain does not support specified action". |

Zoom is worth a note of its own: it does not merely fail, it **hangs first**. The
postinstall script launches `ZoomUpdater`, which waits on a GUI session that will
never appear, so `installer` sits at 0% CPU for minutes with no output before
erroring. `certify.sh` skips it with `HOMEBREW_BUNDLE_CASK_SKIP=zoom` to buy that
time back; `verify.sh` still lists it as unverified, so it cannot be forgotten.

Beyond that: anything hardware-bound (Touch ID, the printer utility) and any
cask whose installer wants a system extension may behave differently in a VM
than on metal. Certification proves the *procedure*, not every pixel of the
result.

### Building the base VM

One-time, and worth keeping forever: reverting costs seconds, rebuilding this
environment costs an hour.

tart is declared in `.Brewfile`, so a rebuilt Mac can re-certify itself without
an undeclared prerequisite in the recovery path. The cost is that the
certification VM installs tart too, where it is useless — Apple Silicon has no
nested virtualization, so a VM cannot create VMs. A few unused megabytes in a
throwaway machine is cheaper than a hole in the emergency procedure.

```bash
# --disk-size MUST be set here. It cannot be fixed later: `tart set --disk-size`
# grows the virtual disk but not the APFS container inside it, and the container
# cannot be grown afterwards either, because macOS puts the Recovery partition
# *after* the data container -- so the new space is on the far side of it and
# `diskutil apfs resizeContainer` fails with -69519.
#
# The default 50 GB yields ~41 GiB usable, and `brew bundle` exhausts it partway
# through, reporting 113 failed package installs rather than "the disk is full".
tart create --from-ipsw=latest --disk-size 100 neuromancer-base

# CPU and memory *can* be changed later; only the disk cannot.
# --display units are POINTS for macOS guests, not pixels, so 1920x1080 is a
# logical display larger than a 14" MacBook Pro's own screen and the window will
# not fit. 1280x800 fits any laptop; --display-refit then lets the guest follow
# the window as you resize it.
tart set neuromancer-base --cpu 6 --memory 8192 \
                          --display 1280x800 --display-refit

ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519_neuromancer_cert \
  -C 'neuromancer-config certification VM'

tart run neuromancer-base
```

Complete Setup Assistant, naming the account **`certuser`, not `james`** —
several of the defects above are only visible to a user who is not you, and
`.gitconfig` was broken for every other account for years. `certify.sh` expects
that name; override with `CERT_USER` if you pick another.

**Decline everything optional.** The base image should be as close to bare macOS
as possible: anything switched on is machine state that is not in this repo, and
it widens the gap between "clean machine" and the machine certification actually
runs on.

| Setup Assistant asks | Answer | Why |
| --- | --- | --- |
| **FileVault** | **No** | Not merely unnecessary — it *breaks the harness*. FileVault requires pre-boot authentication, and `certify.sh` boots the clone with `--no-graphics` and waits for SSH. An encrypted guest sits at an unlock screen nobody can type into, never brings up the network, and times out every run. On a real Mac, turn it on. |
| **Location Services** | No | Nothing in the Brewfile or the scripts uses it. Declining means macOS asks for a time zone by hand — **set it correctly**. Every step of the bootstrap is an HTTPS download, and a badly wrong clock fails TLS validation with certificate errors rather than anything that says "your clock is wrong". `sudo sntp -sS time.apple.com` fixes it after the fact. |
| **Apple ID** | No | The App Store cannot be signed into in a VM at all, and iCloud has nothing to sync here. |
| **Automatic updates** | No | The base image must be a *fixed* macOS version. If it updates itself, a failing run might be failing because macOS moved rather than because the repo did — and the clean image you revert to is no longer the one you certified against. Clones inherit the setting too, so a run could pull a multi-gigabyte OS update while competing for the same disk and bandwidth as 121 packages. On the real Mac, topgrade's `system` step does this deliberately instead. |
| **Siri, analytics, Screen Time, Apple Pay, Find My** | No | Background services that add noise and state, and buy nothing. |

Everything after that is one command, because typing into a VM window is
miserable and error-prone. Boot the base image with this repo's
`certification/` directory shared in:

```bash
cp ~/.ssh/id_ed25519_neuromancer_cert.pub certification/
tart run --dir=cert:"$PWD/certification":ro neuromancer-base
```

Then, in the VM's Terminal:

```bash
"/Volumes/My Shared Files/cert/prepare-base-vm.sh"
```

That installs the public key, grants passwordless sudo, and turns on Remote
Login — the three things `certify.sh` needs to drive the VM unattended, none of
which are part of the rebuild being certified. It verifies each one rather than
assuming, and stops if Remote Login needs the GUI toggle, which it does on a
fresh install: `systemsetup` requires Full Disk Access that a new Terminal.app
does not have.

Then **shut down and never boot `neuromancer-base` again.** `certify.sh` clones
it; booting the base itself lets it drift, at which point it is no longer a
clean machine.

Display changes only take effect at the next boot — `tart set` accepts them on a
running VM and exits zero, which looks like it worked. To resize a VM that is
already running, change the resolution inside the guest instead: System Settings
→ Displays.

### Why not copy and paste

tart does support clipboard sharing, but on a macOS guest it requires
`tart-guest-agent` installed *inside* the VM — which is itself something you
would have to get in there first. The directory share above works from first
boot with no agent, no networking and no clipboard. `tart run --vnc` is the
other option: Screen Sharing supports copy and paste, but it needs Remote Login
already on, so it cannot help with the step that turns Remote Login on.

Apple's licence permits two macOS VMs on a Mac host. The clone is APFS
copy-on-write, so it costs seconds and almost no disk.

---

## Secrets

This repo is **public**. A value committed and deleted in the next commit is
still in the history, in every clone, and in GitHub's API. Rotation is the only
remedy.

| Situation | Mechanism |
| --- | --- |
| Mostly-public file, one secret field | **1Password at render time.** The template holds a reference; the value is fetched on apply. `{{ onepasswordRead "op://Private/npm/token" }}` |
| Whole file is secret | **age encryption.** `chezmoi add --encrypt ~/.gem/credentials` |
| SSH private keys, signing keys | **Don't manage it at all.** Encryption reduces exposure; it does not make a public repo an appropriate home for a private key. Provision by hand, per machine. |

`private_dot_ssh/private_config` is managed and public — it is only the SSH
*config*. The keys it references (`id_rsa_proxmox_admin` and friends) are
deliberately not in this repo, and `dot_gitignore` blocks `.ssh/id_*` and
`.ssh/*.pub` from ever being committed by accident. Note that this config sets
`StrictHostKeyChecking no`, which is a convenience on a trusted LAN and a bad
default anywhere else.

### The bootstrap ordering problem

1Password templates create a chicken-and-egg: `chezmoi apply` needs `op`, but
`op` arrives via the Brewfile, which *is* the apply. The `op` CLI is also a
separate package from the desktop app and needs CLI integration enabled there
before it will unlock. A rebuild using secret templates is three steps:

```bash
brew install --cask 1password 1password-cli
op signin
chezmoi init --apply jcouball/neuromancer-config
```

Worth weighing against keeping secret-bearing files out entirely, which keeps
the bootstrap at one command.

### If something leaks

**Rotate first, clean up second.** Public repositories are scraped continuously
and automatically; assume any committed credential was harvested within minutes.
`git filter-repo` and a force-push are housekeeping, not remediation, and doing
them first wastes the window in which rotation matters. GitHub also retains
unreachable objects, so the old commit may remain fetchable by SHA afterwards.

---

## Deliberately not managed

- **Secrets and keys.** 1Password holds them; `op` reads them at render time.
- **Warp's settings** — not by choice, and the biggest gap in a rebuild. Warp
  keeps them in a binary SQLite database with no config file to version, so the
  application comes back and your setup does not. Nothing here can fix that; the
  only mitigation is knowing it in advance, which is why it is step one of the
  by-hand list in [Rebuild from nothing](#rebuild-from-nothing).
- **VS Code settings** (as opposed to the extension list). Settings Sync owns
  those; the Brewfile owns which extensions are installed.
- **macOS system preferences.** No `defaults write` bank here. They are
  reproducible in principle and miserable in practice: undocumented keys, values
  that change between releases, and settings that need a logout to take effect.
  The computer name is the exception, because a rebuild must not silently answer
  to the wrong hostname.
- **Per-project dependencies.** Gemfiles, `package.json`, project-level
  `.tool-versions`. These belong to their repos.
- **App Store app *data*.** The apps are declared; their contents are not.
- **Anything you'd reinstall in under a minute.** This repo is for what is
  painful to reconstruct, not an inventory.

---

## Small gotchas

- **`brew bundle check` reports outdated packages as unsatisfied.** Set
  `HOMEBREW_BUNDLE_NO_UPGRADE=1` when you want to know what is *missing* rather
  than what is merely stale — `verify.sh` does exactly this, or the genuinely
  missing entries drown in a list of things that just want upgrading.
- **`run_once_` scripts never run again**, so Rosetta will not be reinstalled if
  it is ever removed. `arch -x86_64 /usr/bin/true` tells you; `verify.sh` checks
  it. Do **not** use `pgrep oahd` for this: the daemon only runs while something
  is actively being translated, so it reports "not installed" on a machine that
  simply has not run an Intel binary since boot.
- **Sign in to iCloud and the App Store separately.** They are different
  sign-ins, and only the second one satisfies `mas`.
- **`brew bundle dump` rewrites the whole file.** Re-add it to chezmoi in the
  same sitting, or the next `chezmoi apply` will quietly put the old one back.
- **VS Code extension packs are always double-declared, and can race.** A pack
  installs its members, `brew bundle dump` records everything installed, so the
  pack *and* each member end up in `.Brewfile`. `brew bundle` then installs in
  parallel and two processes can unpack the same extension into the same
  directory, failing with `ENOTEMPTY: directory not empty`. This is structural,
  not a mistake to be tidied away: `vscjava.vscode-java-pack` declares six of
  its own members, and all six are wanted. Script 02 retries once with
  `HOMEBREW_BUNDLE_JOBS=1`, which cannot collide.
- **Uninstalling a pack uninstalls its members too.** Removing
  `vscode-remote-extensionpack` also removed `remote-containers` and
  `remote-server`, which had to be reinstalled. Check `code --list-extensions`
  after removing any pack.
- **`brew bundle` upgrades by default**, which is why script 02 exports
  `HOMEBREW_BUNDLE_NO_UPGRADE=1`. Without it, a one-line Brewfile edit turned
  `chezmoi apply` into a bulk upgrade of every outdated package — 19 of them on
  the run that caught this, Docker Desktop and Chrome among them, while they
  were running. Installing what is declared is layer 1's job; upgrading is
  layer 5's. `topgrade` is how you ask for the second one.
- **`brew bundle dump` cannot see through asdf shims.** Homebrew runs
  subprocesses with a scrubbed `PATH` — `Library/Homebrew/shims/shared`,
  `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin` and nothing else — so an asdf shim,
  whose body is `exec asdf exec "go" "$@"`, cannot find `asdf`:

  ```console
  $ env -i PATH="$HOME/.asdf/shims:/usr/bin:/bin" ~/.asdf/shims/go version
  /Users/james/.asdf/shims/go: line 6: exec: asdf: not found
  ```

  Homebrew Bundle can record `go` and `cargo` entries, so `dump` probes those
  toolchains and silently records none. If you ever start relying on `go` or
  `cargo` lines in the Brewfile, they will be quietly empty. Nothing else in the
  dump is affected — formulae, casks, taps, `vscode` and `mas` are all fine.
- **Three provisioning scripts need sudo** — 00 (computer name), 01 (Rosetta)
  and 05 (linking openjdk). Run `chezmoi apply` from an interactive shell so
  sudo can prompt, or `sudo -v` first. Both scripts now say so rather than
  emitting a bare `sudo: a password is required` from a script you did not know
  was running. A failed script stays pending in `chezmoi status`, so it retries
  — it does not silently record success.
- **`chezmoi init` does not pull on an already-initialised machine.** Running
  `chezmoi init --apply <repo>` where `~/.local/share/chezmoi` already exists
  applies the checkout that is *already there*, so a fix you have just pushed is
  silently not used. It cost a whole diagnostic cycle: the run behaved exactly
  as before, because it was running exactly the code as before. Use `chezmoi
  update`, which pulls and then applies. A real rebuild is unaffected — a fresh
  machine has nothing to be stale.
- **`chezmoi re-add` writes to the chezmoi source directory**, which is
  `~/.local/share/chezmoi`, *not* whatever clone of this repo you happen to be
  editing in. Keeping a second working copy (say `~/github/jcouball/`) means
  `re-add` silently updates the other one, and a `git diff` where you are
  standing shows nothing at all. `chezmoi cd` goes to the source directory, and
  is the reason every playbook above is written that way.
- **`--global` resolves to `~/.Brewfile` only by fallback.** Homebrew looks at
  `$HOMEBREW_BUNDLE_FILE_GLOBAL`, then `$XDG_CONFIG_HOME/homebrew/Brewfile` if
  `XDG_CONFIG_HOME` is set, then `~/.homebrew/Brewfile`, and only then
  `~/.Brewfile`. `~/.homebrew/` **does** exist here — `dot_homebrew/brew.env`
  puts it there — so if a `Brewfile` ever lands in it, every `dump` in this
  README silently starts writing to a file chezmoi does not manage. `brew bundle
  list --global | head` tells you which file is really being read.
- **There are two possible `brew.env` locations and both exist here.** The
  managed one, `~/.homebrew/brew.env`, is live (`brew config` confirms
  `HOMEBREW_NO_REQUIRE_TAP_TRUST: set`). A stale `~/.config/homebrew/brew.env`
  also exists with the *opposite* tap-trust setting; it is inert only because
  `XDG_CONFIG_HOME` is unset. Set that variable and the unmanaged file silently
  takes over.
- **A pty is required to test an interactive shell.** `zsh -ic exit` without one
  cannot enable job control, and powerlevel10k's gitstatus emits six lines of
  alarming and completely meaningless output. `script -q /dev/null zsh -ic exit`
  gives it a pty and the noise disappears.
- **`chezmoi status` compares file contents only.** It will happily report a
  clean machine that has no Ruby installed. `./certification/verify.sh` is the
  one that looks at outcomes.
