# mac-dev-config

Configuration for two Macs, **Neuromancer** and **cortex**, used for Ruby, Go
and JRuby development. Managed with [chezmoi](https://chezmoi.io).

Companion to [jcouball/windows-dev-config](https://github.com/jcouball/windows-dev-config)
(Windows 11) and [jcouball/ubuntu-dev-config](https://github.com/jcouball/ubuntu-dev-config)
(Ubuntu). This repo is scoped to one operating system deliberately: no OS
templating, every file is simply the file. The cost is that `.gitconfig`,
`.tool-versions` and `topgrade.toml` now exist in more than one repo and will
drift; the benefit is that nothing here needs a conditional.

The three are worked on together in
[jcouball/dev-config](https://github.com/jcouball/dev-config), the workspace
they are cloned into. Issues that span more than one of them are filed there.

| | |
| --- | --- |
| Hosts | Neuromancer — Apple M2 Max, macOS Golden Gate 27.2.1 |
| | cortex — Apple M4, macOS Golden Gate 27.2.1 |
| Shell | zsh + powerlevel10k |
| Terminal | Warp (installed by `.Brewfile`; its settings are not managed here) |
| Package manager | Homebrew — 84 formulae, 40 casks, 49 VS Code extensions, 14 App Store apps |
| Runtimes | asdf, 5 tools |
| Rebuild | **certified** 2026-11-21 on a clean VM, except the App Store layer |

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
  - [Remote access over SSH](#remote-access-over-ssh) — key-only logins from the LAN and the tailnet
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
chezmoi init --apply --branch stable jcouball/mac-dev-config
```

`stable` is the branch that holds the last certified commit;
[Main and stable](#main-and-stable) says how it moves.

Step 3 asks one question — what this machine is called — and then does the rest:
the Brewfile, the runtimes, every config file, the JDK link, and Remote Login
restricted to keys.

If step 3 stops because a download failed, run `chezmoi apply`. Every script is
written to be run again, and a download fails for reasons that have nothing to
do with this repo.

**Sign in to iCloud and the App Store first**, if you want the App Store apps.
They are separate sign-ins and only the second satisfies `mas`. Skipping it
costs nothing else: the run completes, and the 14 App Store entries can be
picked up later with `brew-bundle-this-mac --file="$HOME/.Brewfile"`.

Afterwards, by hand — the parts a script cannot do:

1. **Redo Warp's settings.** Warp is installed by `.Brewfile`, but this repo
   does not manage its settings. Sign in to Warp, and its own Settings Sync
   brings back the settings it carries. The terminal font is not one of them:
   Warp keeps it on the device, so a rebuilt machine starts with Warp's default
   font. Set Terminal font to `MesloLGS NF` under Settings, Appearance, Text —
   see [Deliberately not managed](#deliberately-not-managed).
2. **Sign in to 1Password** and enable its CLI integration, if you use the
   `op`-templated files — see [Secrets](#secrets).
3. **Sign in to Telegram** by scanning its QR code from the phone app.
4. **Copy in the SSH keys this Mac logs in with.** The rebuilt Mac accepts
   logins at once, because its public key is in this repo. To log in to the
   other machines it needs their private keys from 1Password — see
   [Set up a client](#set-up-a-client).
5. **Sign in to Tailscale.** The rebuild installs it, and the Mac is not on
   the tailnet until someone signs in — see [Tailscale](#tailscale).

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

It also matches [windows-dev-config](https://github.com/jcouball/windows-dev-config),
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
# then commit it on a branch and open a pull request: see "Main and stable"
```

`brew bundle dump` rewrites `~/.Brewfile` from what is actually installed, so
the snapshot and the machine cannot disagree. The descriptive comment above each
entry — most of what makes that file readable — is included by default now;
`--describe` still works but is deprecated.

**A dump drops one Tailscale entry.** The Brewfile declares `brew "tailscale"`
and `cask "tailscale-app"`, and each Mac installs one of them: see
[Tailscale](#tailscale). A dump writes what is installed, so it leaves the
other out. Put the line back before `chezmoi re-add`. Script 99 fails the next
apply while either line is missing, and names it.

#### Uninstall an application

```bash
brew uninstall <formula>          # or: brew uninstall --cask <cask>
brew bundle dump --global --force
chezmoi re-add ~/.Brewfile
# then commit it on a branch and open a pull request: see "Main and stable"
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
# then commit it on a branch and open a pull request: see "Main and stable"
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

#### An extension appeared that you did not declare

`verify.sh` warns when something is installed that `.Brewfile` does not list.
Usually it means an extension pack gained a member upstream, or an extension
pulled in a dependency. Decide which you want, then make the repo agree:

```bash
# adopt it
brew bundle dump --global --force
chezmoi re-add ~/.Brewfile
# then commit it on a branch and open a pull request: see "Main and stable"

# or refuse it
code --uninstall-extension <publisher.name>
```

This is not a new chore — it is the same "the repo must never lag the machine"
rule as everywhere else. The check exists only so you find out on your schedule
rather than during a rebuild. It rides along with `verify.sh`, which the cadence
table already puts at monthly.

**Keeping extension packs is fine.** `vscjava.vscode-java-pack` declares six
members and all six are wanted; dropping it would mean uninstalling it — which
takes its members with it — and reinstalling each by hand to arrive at the same
six extensions without upstream curation. Packs are not what causes the install
races either: the certified run collided on `shellcheck`, a plain formula. The
only real hazard is a pack quietly gaining a member, and that is exactly what
this check catches.

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
# then commit it on a branch and open a pull request: see "Main and stable"
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
./certification/verify.sh
```

1. **Homebrew publishes bottles per major OS.** Until they land, formulae build
   from source, slowly. Casks carrying system extensions often need a reinstall
   rather than an upgrade.
2. **The Command Line Tools usually need reinstalling**, which breaks `xcrun`,
   and therefore `SDKROOT`, and therefore every new shell until fixed.
3. **Rebuild the compiled runtimes.** Ruby and Python were built against the old
   SDK and are the most common post-upgrade breakage.
4. **Rosetta does not survive.** The 26 → 27 upgrade removed it. Nothing this
   repo installs needs it, so the repo no longer installs it either. Install it
   by hand only if you add an Intel-only app, and plan to replace that app:
   macOS 28 keeps only a limited Rosetta meant for older games.
5. Update the macOS version in the host table at the top of this file.
6. **Re-certify, and rebuild the base VM.**

That last point is the one that is easy to skip. A guest cannot be newer than
its host, so the existing base image still boots but no longer represents the OS
you would actually reinstall onto. **A major host upgrade is a change to the
bootstrap path even though no file in this repo changed** — it changes Setup
Assistant, the available bottles, and the SDK the runtimes compile against. It
triggers re-certification exactly as editing a provisioning script would.

### Main and stable

A change merges to `main`. Between `main` and a machine that is not being
worked on is a certification.

| Branch | Holds | Moved by |
| --- | --- | --- |
| `main` | every merged change, certified or not | a pull request |
| `stable` | the last commit that was certified | `certification/record.sh`, and nothing else |

`main` is often ahead of `stable`, and that is the normal state, not a fault:
several changes can merge and be certified together.

```bash
git fetch origin
git log --oneline origin/stable..origin/main    # merged, not yet certified
```

Which branch a Mac's chezmoi source follows depends on what the Mac is being
used for, not on which Mac it is:

| Role | Source follows | Gets | For |
| --- | --- | --- | --- |
| Following | `stable` | certified commits only | a Mac nobody is changing the configuration on, and a rebuild |
| Developing | `main`, or a branch of a change in progress | whatever has merged, and its own edits | the Mac the configuration is being changed on |

```bash
# start developing on this Mac
chezmoi git -- fetch origin && chezmoi git -- switch main && chezmoi update

# go back to following
chezmoi git -- fetch origin && chezmoi git -- switch stable && chezmoi update
```

The fetch comes first because the source may never have seen the branch: a
source cloned before `stable` existed has no `stable` to switch to until it
has fetched.

Either Mac can take either role. A Mac that is being developed on runs
uncertified configuration whatever its source follows: an edit exists there
before any commit does. So `stable` is not for that Mac. It is for the other
one, and for [Rebuild from nothing](#rebuild-from-nothing), which clones
`stable`.

**Changing something on the developing Mac** ends the same way whatever was
changed, and every playbook that says to commit on a branch means this.
`chezmoi re-add` and `chezmoi add` write to the source's working tree and
commit nothing, and `main` takes changes only through a pull request:

```bash
chezmoi re-add ~/.zshrc
chezmoi cd
git switch -c fix/<what>
git add -A                      # chezmoi add makes new files, which commit -a leaves out
git commit -m "<what and why>" && git push -u origin fix/<what>
gh pr create
# after the merge:
git switch main && chezmoi update
```

While the pull request is open the source is on its branch, so the source and
the home directory agree and `chezmoi status` is empty.

**A following Mac is for pulling.** A change made there shows as drift until it
has merged, been certified, and come back through `stable`. Switch the Mac to
developing first.

A ruleset stops `stable` being deleted or moved backwards. Nothing on GitHub
can check that a commit pushed to it was certified. `record.sh` is what keeps
that true: it moves `stable` only to a commit it has just tagged, in the same
push as the tag.

#### The hooks

That leaves one accident GitHub accepts: a commit made in a source that has
`stable` checked out, and then pushed. Two git hooks in `.githooks/` stop it
in the clone:

| Hook | Stops | Lets through |
| --- | --- | --- |
| `pre-commit` | a commit while `main` or `stable` is checked out | any other branch, and a detached `HEAD`, which is what a rebase commits with |
| `pre-push` | a push to `stable`, from any local branch, of a commit with no `certified/` tag | a commit that has the tag in this clone or gets it in the same push, which is what `record.sh` pushes |

git runs a versioned hook only in a clone whose `core.hooksPath` names the
directory. Script 08 sets that in the chezmoi source on every apply, and
`verify.sh` checks it. `clone-repos.sh` in
[dev-config](https://github.com/jcouball/dev-config) sets it in the working
clone. In any other clone:

```bash
git config core.hooksPath .githooks
```

The hooks are a guard against accidents, not a control. Each lives in one
clone, and `--no-verify` skips it. The rulesets are the control.

### Re-certify the rebuild

A pull request does not need a certification run to merge. It needs review, and
whatever shows the change itself works: a script run against stand-ins, a test
of the logic, an apply in a scratch directory. The pull request says what was
done.

Certify `main` when there is something on it to put on the Macs:

```bash
./certification/certify.sh
```

That clones the pristine base VM, boots it, runs the bootstrap from this README
against `main`, and then verifies. Transcripts land in `certification/logs/` —
without a log, failures have to be inferred from wreckage. The bootstrap log
ends with the commit and the tree the VM built, and a copy of the `verify.sh`
that checked the VM is kept beside the logs.

**What needs a run before it reaches `stable`:** anything a rebuild runs or
reads. That is a provisioning script, `.Brewfile`, `.tool-versions`,
`.chezmoi.toml.tmpl`, `.chezmoiignore`, a managed config file, and `verify.sh`.
A tightened check counts exactly as a changed script does, because the previous
run passed a test that no longer exists. A major macOS upgrade needs a run too,
with no commit at all.

**What does not:** the README, `record.sh`, and `prepare-base-vm.sh`. A commit
that changes only those can sit on `main` until the next run takes it along.
`certify.sh` is tested by the next run it makes.

**One run can cover several changes.** It certifies the tip of `main`, and
everything merged since the last tag is in that commit. When a run of several
changes fails, the logs usually name the script. If they do not, certify the
changes one at a time: `--branch` certifies any pushed branch, and `main` can be
certified at an earlier commit by pushing that commit to a branch.

**To try one change in the VM before it merges**, name its branch:

```bash
./certification/certify.sh --branch <branch>
```

This is worth the wait for a new provisioning script or a change to the three
bootstrap commands, where a clean machine finds what nothing else does. The VM
clones the branch from GitHub, and `verify.sh` comes from the local checkout,
copied at the start of the run. So the script stops before booting the VM
unless all three of these hold:

- the branch is pushed,
- the local checkout is at the commit the branch has on GitHub, and
- `certification/verify.sh` has no uncommitted changes.

Run it once, after review, on the commit that will merge: a new commit on the
branch means a new run. A passing branch run can be recorded for the merged
commit when the tree on `main` after the merge is the tree the VM built. That
holds when the branch contained `main`'s tip and nothing else landed in
between; the run says whether the branch contains `main`'s tip. `record.sh`
makes the comparison, and it is what decides.

**To check a change to `verify.sh` alone**, `./certification/certify.sh --verify-only`
runs the new checks against the VM the last run left. It takes about a minute.
It cannot be recorded, because it rebuilds nothing.

#### Record a run and move stable

A run gives the VM result only. To record it, apply the commit on the
developing Mac and run `record.sh` there, in the checkout `certify.sh` ran in:

```bash
chezmoi update
./certification/record.sh       # --dry-run shows the tag and makes nothing
```

`record.sh` reads the VM result from the run's logs, then stops unless all of
these hold:

- this Mac is Neuromancer or cortex,
- the run was CERTIFIED,
- the commit to certify is on `main` and has no `certified/` tag yet,
- `stable` is behind that commit, at it, or ahead of it,
- its tree is the tree the VM built,
- the `verify.sh` that checked the VM is the one at that commit,
- the chezmoi source on this Mac is at that commit, with nothing uncommitted,
  both before `verify.sh` runs and after it,
- the tag and `stable` can be pushed from this session, and
- `verify.sh` passes here with 0 warnings and 0 excluded, which is the
  real-hardware half. A warning or an excluded check there is a check that was
  not made.

The source has to be on `main` for that: a source on `stable` cannot be at a
commit that `stable` does not have yet, and the script says so. Commit a
`chezmoi re-add` to a branch, or set it aside, before recording.

It then shows the tag, creates it on the commit, and pushes the tag and
`stable` together: both arrive or neither does. It certifies the tip of `main`
unless `--commit` names another commit, and reads the newest full run unless
`--log` names another bootstrap log. An older commit recorded with `--commit`
gets its tag and leaves `stable` where it is. If the trees differ, certify
`main` and record that run.

Then on each Mac that follows `stable`: `chezmoi update`.

Nothing is committed, so no pull request is needed to record a certification.
Write a defect the run found into [What a clean machine found](#what-a-clean-machine-found);
that part is still a change to this file.

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

### Why `mac-dev-config` and not `dotfiles`

"dotfiles" names the mechanism, not the scope, and it is only half true here:
plenty of what this repo manages is not dot-prefixed, and plenty of it is not a
file at all — the computer name, the runtimes asdf materialises, the JDK link.
`mac-dev-config` names the operating system and the role, not a host, because
the repo configures more than one Mac. It matches `windows-dev-config` and
`ubuntu-dev-config` so the three read as one system, and it stays
tool-agnostic, so it survives if chezmoi is ever replaced.

The repo was first called `dotfiles`. That name still redirects for
`git clone` and for web traffic. **The `raw.githubusercontent.com` URL in the
bootstrap one-liner of the time was the part that mattered**, though, and it
is served by a different, heavily-cached host whose behaviour on renamed
repositories GitHub does not document.

Measured immediately after that rename, the old raw URL returned `200`:

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
        github.com/jcouball/mac-dev-config
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
sshd-mac.conf                      sshd settings; script 07 installs it (ignored)
.chezmoi.toml.tmpl                 asks the machine's name once, at init
.chezmoiignore                     keeps the ignored files out of the home directory
.gitattributes                     * text=auto eol=lf
.githooks/pre-commit               stops a commit on main or stable
.githooks/pre-push                 stops a push to stable of a commit that was not certified

dot_Brewfile                       84 formulae, 40 casks, 49 extensions, 14 App Store apps
dot_tool-versions                  the five pinned runtimes
dot_default-npm-packages           replayed on every new Node install
dot_asdfrc                         asdf behaviour

dot_zshenv                         always sourced: JAVA_HOME, path_helper; Homebrew, asdf, ~/.local/bin when not a login shell
dot_zprofile                       login shells: Homebrew, asdf, ~/.local/bin
dot_zshrc                          interactive shells: p10k, completions, aliases
dot_p10k.zsh                       the prompt (generated by `p10k configure`)
empty_dot_zlogin                   deliberately empty
dot_profile / dot_bash_profile / dot_bashrc    bash equivalents

dot_gitconfig                      identity, editor, aliases
dot_gitignore / dot_gitignore_global
private_dot_ssh/private_config     SSH config; the private keys are not managed
private_dot_ssh/private_authorized_keys.tmpl   the public key that opens this Mac
dot_config/topgrade.toml           update policy
dot_homebrew/brew.env              HOMEBREW_NO_ANALYTICS
dot_pip/pip.conf
dot_local/bin/executable_clear-warp-quarantine   clears Homebrew's quarantine flag from Warp
dot_local/bin/executable_brew-bundle-this-mac    `brew bundle`, without the Tailscale entry this Mac does not run
empty_dot_irbrc

dot_claude/settings.json           Claude Code: plugins, model, permission mode
dot_claude/CLAUDE.md               Claude Code: global communication preferences

.chezmoiscripts/
  run_onchange_00_set_computer_name.sh.tmpl                        computer, host and local host names
  run_onchange_after_02_brew_bundle_install.sh.tmpl                everything in .Brewfile
  run_onchange_after_03_asdf_plugin_add.sh.tmpl                    plugins, derived from .tool-versions
  run_onchange_after_04_asdf_tool_install.sh.tmpl                  the runtimes themselves
  run_onchange_after_05_link_openjdk.sh.tmpl                       makes Homebrew's openjdk visible to macOS
  run_onchange_after_06_install_amphetamine_power_protect.sh.tmpl  Amphetamine Power Protect, laptops only
  run_onchange_after_07_sshd_remote_login.sh.tmpl                  key-only sshd, then Remote Login on
  run_after_08_git_hooks_path.sh.tmpl                              points the source's git at .githooks
  run_after_09_tailscale_daemon.sh                                 the Tailscale daemon, on a Mac with no battery
  run_after_99_brew_bundle_check.sh                                fails the apply if a .Brewfile entry is missing

certification/
  certify.sh                       host side: clone a VM, rebuild it, verify it
  verify.sh                        guest side: assert outcomes, not exit codes
  record.sh                        host side: tag the certified commit with the result
  logs/                            transcripts (gitignored)
```

### Two path traps

**Anything in the source root without a leading dot becomes a target.**
`README.md`, `LICENSE.txt`, `sshd-mac.conf` and `certification/` would all be
written into the home directory; all four are in `.chezmoiignore`. This is not
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
installs it — but this repo does not manage its settings, so a rebuild restores
only what Warp's own Settings Sync carries.

### Which zsh file, and why

This is the part that is easy to get wrong, because the three files are sourced
in different circumstances and by different kinds of shell:

| File | Sourced by | Holds |
| --- | --- | --- |
| `.zshenv` | **every** zsh, including non-interactive ones | `JAVA_HOME`, `path_helper`. Things a script invoked by an app must see. In a zsh that is not a login shell, also what `.zprofile` holds. |
| `.zprofile` | login shells | Homebrew's `shellenv`, asdf's shims, `~/.local/bin`. |
| `.zshrc` | interactive shells | The prompt, completions, aliases, options. Runs `brew shellenv` again and then puts asdf's shims back in front of it. |

asdf is initialised in `.zprofile` rather than `.zshrc` deliberately: a
non-interactive shell — a git hook, a `Makefile`, an editor task — never reads
`.zshrc`, and without the shims on `PATH` it gets the system Ruby instead of the
pinned one, which fails in confusing ways much later.

That covers a shell a login shell started, because it inherits the login
shell's `PATH`. It does not cover `ssh cortex <command>`: sshd runs the command
as `zsh -c`, which is not a login shell and reads `.zshenv` only. So `.zshenv`
does the same three things as `.zprofile` when the shell is not a login shell.
Without that, `ssh cortex 'chezmoi status'` fails with `command not found`,
while an interactive `ssh cortex` works. A login shell is left to `.zprofile`
because `/etc/zprofile` runs `path_helper` after `.zshenv` and would move the
system directories back in front. The two blocks are copies; change them
together.

`.zshrc` still has to touch `PATH`, for two reasons. `path_helper` in `.zshenv`
moves the system directories to the front in every zsh, so `.zshrc` runs
`brew shellenv` again to put Homebrew back ahead of them. That in turn puts
Homebrew ahead of the shims, so the next line prepends the shims again. Without
it, `python3` is Homebrew's copy, installed as a dependency of other formulae,
and not the version pinned in `.tool-versions`.

**Everything that touches Homebrew or the Command Line Tools is guarded.** Those
files are written by chezmoi during the very first apply, *before* Homebrew and
the runtimes exist, so an unguarded `eval "$(brew shellenv)"` or
`xcrun --show-sdk-path` errors on every shell you open during provisioning.

---

## Remote access over SSH

Each Mac can be reached over ssh from the other, and from any machine on the
LAN or the tailnet that holds its key. A session logs in as `james`, an administrator, so a
login is close to full control of the machine. Three things limit who gets one,
the same three [ubuntu-dev-config](https://github.com/jcouball/ubuntu-dev-config)
and [windows-dev-config](https://github.com/jcouball/windows-dev-config) use:

- **Keys only.** [sshd-mac.conf](sshd-mac.conf) is installed as
  `/etc/ssh/sshd_config.d/00-mac-dev-config.conf`. It allows public keys alone,
  so the account password does not open a session, and it refuses root.
- **Keys from this repo.** chezmoi writes `~/.ssh/authorized_keys` from
  [private_dot_ssh/private_authorized_keys.tmpl](private_dot_ssh/private_authorized_keys.tmpl).
  Each line must start with `restrict` or `restrict,pty`; script 07 fails the
  apply on any other.
- **LAN and tailnet only.** macOS has no ufw, so sshd does this itself:
  `AllowUsers` admits `james` from `192.168.0.0/16`, the LAN, and from
  `100.64.0.0/10`, the tailnet, and nobody else. The addresses are IPv4, so a
  login over IPv6 is refused. The `Host` blocks in
  [private_dot_ssh/private_config](private_dot_ssh/private_config) set
  `AddressFamily inet` for that reason: a `.local` name and a tailnet name both
  resolve to an IPv6 address as well.

**The tailnet is the Tailscale network the machines are signed in to.** Each
has an address in `100.64.0.0/10` and a name there: `neuromancer`, `cortex`,
`sophon`, `rama`. The `Host` blocks for neuromancer, cortex and sophon use
those names, so `ssh cortex` works from anywhere Neuromancer has a network.

- **It needs Tailscale running at both ends,** on the LAN too. With it off at
  either end, name the LAN address: `ssh -o HostName=cortex.local cortex`.
- **`100.64.0.0/10` is not Tailscale's alone.** Carriers use it for shared
  addresses. On a network that hands those out, a neighbour's login gets as
  far as the key check, which is where a login from the LAN gets.
- **This repo installs Tailscale and does not sign it in.**
  [Tailscale](#tailscale) has both halves.

Forwarding is off: `DisableForwarding yes` covers ports, the agent, X11, and
tunnels, and no key option can turn it back on. Use `scp` or `sftp` to move
files; both still work.

Script 07 installs the drop-in, checks it with `sshd -t` and `sshd -T`, puts
the previous file back if either fails, and only then turns Remote Login on. It
uses `launchctl`, not `systemsetup -setremotelogin on`, which needs Full Disk
Access for the terminal. Nothing is reloaded: launchd starts a new sshd for
each connection, and each reads the configuration and the key file afresh.

There is one key for each Mac, named for the Mac it opens:

| Key | Opens | Private half is on |
| --- | --- | --- |
| `id_ed25519_neuromancer` | Neuromancer | Neuromancer, and 1Password |
| `id_ed25519_cortex` | cortex | Neuromancer, and 1Password |

Both private halves are kept on Neuromancer and on no other machine. cortex's
`Host neuromancer` block names `~/.ssh/id_ed25519_neuromancer`, so cortex can
open Neuromancer only while a copy of that key is put there by hand.

The template picks the line by the machine's name, so each Mac accepts its own
key and no other. Each copy of a private key should have a passphrase, so a
copy of the key file is useless on its own. Nothing here can enforce that.

**A sleeping Mac does not answer.** Nothing here keeps one awake.

**`AllowUsers` also names `certuser`**, from `192.168.64.0/24`, the network
tart gives its VMs. That is the certification VM's account. No Mac has it, so
on a Mac the entry admits nobody.

### After a restart

FileVault is on, so after a restart the disk stays locked until someone enters
the account password. Until then a key login is refused. The Mac can be
unlocked over ssh, from a terminal on the LAN. Nothing on the Mac runs while
the disk is locked, Tailscale included, so it is not on the tailnet and the
`.local` name has to be given:

```text
$ ssh -o HostName=cortex.local cortex
This system is locked. To unlock it, use a local
account name and password. Once successfully
unlocked, you will be able to connect normally.
(james@cortex.local) Password:
System successfully unlocked.
You may now use SSH to authenticate normally.
```

Type the Mac account password. The session does not return after the last
line: press Ctrl-C and run the same command again, which logs in with the key.

What brings the Mac back onto the tailnet depends on which Tailscale it runs:

| Mac | Runs | `ssh cortex` by its tailnet name works |
| --- | --- | --- |
| no battery (cortex) | the daemon | a minute or two after the unlock, with nobody logged in |
| MacBook (Neuromancer) | the app | once someone has logged in at the desktop |

**From outside the LAN, unlock through a machine that is on it.** The unlock
asks for the account password and no key, so the machine in between needs
nothing of cortex's:

```bash
ssh -t rama ssh james@cortex.local
```

Tested from rama on 2026-11-25, with Neuromancer on another network.

- **The password unlocks the disk and opens no session.** This is the one
  prompt the keys-only setting does not cover.
- **It needs a terminal.** A command that cannot ask for the password, such as
  one a script runs, gets `Permission denied`.
- **The disk stays unlocked until the next restart.** Logging out at the
  desktop does not lock it again, so a key login works with nobody logged in.
- **It needs the network before login.** Apple supports this on a Mac with
  Apple silicon running macOS 26 or later, with Remote Login on, over Ethernet
  or a Wi-Fi network that is open or uses WPA2 with a password.

Tested on cortex on 2026-11-23, running macOS 27.2.1 on Ethernet.

This is also how to reach cortex after a power cut. It is set to start up when
power returns ("Start up automatically after a power failure" in System
Settings, Energy; `pmset -g` shows `autorestart 1`). That setting was made by
hand and nothing in this repo sets it. Once it has started, unlock it as above.

### Tailscale

The tailnet is what makes the Macs reachable from outside the LAN. Tailscale
comes two ways on macOS, and which one a Mac runs depends on whether it has a
battery:

| Mac | Runs | Installed from | Starts |
| --- | --- | --- | --- |
| MacBook (Neuromancer) | the app | `cask "tailscale-app"` | when someone logs in at the desktop |
| no battery (cortex, the certification VM) | the daemon, `tailscaled` | `brew "tailscale"` | at boot |

A Mac with no battery is one that is reached with nobody at it, so it has to
come back onto the tailnet without a desktop login. The daemon does that. It
has no menu bar item, cannot use an exit node, and is updated by Homebrew and
not by itself. A MacBook keeps the app, which has all three.

The Brewfile declares both entries, and a plain `brew bundle` installs both.
**Use `brew-bundle-this-mac` wherever `brew bundle` would install or check.**
It is `brew bundle` with the entry this Mac does not run added to Homebrew's
skip list (`HOMEBREW_BUNDLE_BREW_SKIP` or `HOMEBREW_BUNDLE_CASK_SKIP`), and it
passes its arguments on:

```bash
brew-bundle-this-mac --file="$HOME/.Brewfile"
```

Scripts 02 and 99 run it. `verify.sh` applies the same rule itself, and fails
if the variant left out is installed, so the skip hides nothing. `brew bundle
dump` and `brew bundle cleanup` are used as they are: neither installs.

**Script 09 installs the daemon** with `tailscaled install-system-daemon`. That
copies the binary to `/usr/local/bin/tailscaled`, owned by root, and loads
`/Library/LaunchDaemons/com.tailscale.tailscaled.plist`.

- **Not `sudo brew services start tailscale`.** That hands the formula's files
  to root, and the next `brew upgrade` cannot remove them without sudo.
- **The copy does not follow an upgrade of the formula.** Script 09 runs on
  every apply, compares the two versions, and installs again when they differ.
  That restarts the daemon, and a session that came in over the tailnet stalls
  for the seconds it takes.
- **launchd does not restart the daemon if it exits.** The plist has no
  `KeepAlive`. Script 09 installs again when the job is loaded and not running,
  so an apply brings it back, and so does a restart. Until one of those the Mac
  is off the tailnet.

**Signing in is done by hand, once for each Mac.** It needs a browser.

- **The daemon:** `sudo tailscale up` prints an address. Open it on any machine
  and approve the login.
- **The app:** open Tailscale, approve the VPN configuration and the system
  extension, sign in, and turn on "Launch at login" in its settings.
- **Both:** in the [admin console](https://login.tailscale.com/admin/machines),
  turn off key expiry for the Mac. With it on, the Mac leaves the tailnet after
  180 days and has to be signed in again at its console.

A Mac that was signed in before a rebuild comes back as a new machine. Delete
the old entry in the admin console first, or the new one is named `cortex-1`
and `ssh cortex` reaches nothing.

**To move a Mac from the app to the daemon,** work at its console: the Mac is
off the tailnet from the first step to the last.

```bash
brew uninstall --cask tailscale-app
sudo shutdown -r now
# after the restart:
sudo -v && chezmoi apply
sudo tailscale up
```

Tailscale's documentation says to remove the app and restart before another
variant is installed. Script 09 stops the apply while the app is still there.

**To take the daemon off:** `sudo tailscaled uninstall-system-daemon`.

**Check a machine that has restarted with `ssh <name> hostname`, not
`tailscale ping`.** From the Mac app, `tailscale ping` to a machine that has
just restarted fails until some other connection is made to it:
[dev-config#7](https://github.com/jcouball/dev-config/issues/7).

### Set up a client

The public keys are already in the repo, so a client needs only its own copy
of the private half. Nothing changes on the Mac being logged in to.

On the client, save the private key from the item of the same name in
1Password to `~/.ssh`, here for cortex. If 1Password hands the key over without
a passphrase, give the copy one:

```bash
chmod 600 ~/.ssh/id_ed25519_cortex
ssh-keygen -p -f ~/.ssh/id_ed25519_cortex
```

A Mac set up from this repo already has the `Host` blocks. On another client,
add one to `~/.ssh/config`. `UseKeychain` is for a Mac, and stores the
passphrase in the Keychain so commands run without a prompt; leave it out
elsewhere.

```text
Host cortex
  HostName cortex
  User james
  IdentityFile ~/.ssh/id_ed25519_cortex
  IdentitiesOnly yes
  ForwardAgent no
  AddressFamily inet
  AddKeysToAgent yes
  UseKeychain yes
```

Check from the client: `ssh cortex 'scutil --get ComputerName'` prints
`cortex`. The first login asks for the passphrase once and stores it.

### Add a Mac

Make a key named for the new Mac. `ssh-keygen` asks for a passphrase; give it
one.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_<name> -C id_ed25519_<name>
```

Store the private key in 1Password as an SSH Key item of the same name. In a
checkout of this repo, add an `else if` branch for the machine's name to
`private_dot_ssh/private_authorized_keys.tmpl`, holding
`restrict,pty` and the contents of `~/.ssh/id_ed25519_<name>.pub`, and add a
`Host` block to `private_dot_ssh/private_config`. The name is compared in lower
case with the computer name chezmoi asked for at `chezmoi init`. Open a pull
request and merge it. The developing Mac gets the change at its next
`chezmoi update`. A Mac that follows `stable`, the new Mac included, gets it
only after the change has been certified and recorded: see
[Record a run and move stable](#record-a-run-and-move-stable). Then run
`chezmoi update` on each of them.

A Mac whose name has no branch gets a key file with no key: Remote Login is on,
and nobody can log in. Script 07 warns, and `verify.sh` fails, until the branch
exists.

### Replace a key

Make the new key as in [Add a Mac](#add-a-mac), under the same name, and
replace the private key in the 1Password item. In a checkout of this repo,
replace the key on that Mac's line in
`private_dot_ssh/private_authorized_keys.tmpl`, then open a pull request and
merge it.

The old key stays authorized on a Mac until that Mac has the change. The
developing Mac has it at its next `chezmoi update`. A Mac that follows
`stable` has it only after the change has been certified and recorded, and
`chezmoi update` has run there. If the old key cannot wait for that, make the
Mac a developing one:

```bash
chezmoi git -- fetch origin && chezmoi git -- switch main && chezmoi update
```

Leave it on `main` until the change has been certified and recorded. Switching
back sooner applies `stable`'s copy of the template, which still has the old
key: the old key would be authorized again and the new one removed. Switch
back once `stable` has the change: `chezmoi git -- fetch origin`, then
`chezmoi git -- log origin/stable` shows it.

Run that `chezmoi update` at the machine or over a session that is already
open, because the old key stops working once its line is gone. Then repeat
[Set up a client](#set-up-a-client) on each client.

### Revoke a key

Delete the key's line from `private_dot_ssh/private_authorized_keys.tmpl` and
run `chezmoi apply` on the Mac it opens. sshd reads the file on every login, so
the key stops working at once. A session the key already opened stays open
until it is closed or its sshd process is killed.

### Change sshd's settings

Edit `sshd-mac.conf`, then `chezmoi apply`. Script 07 installs the file and
makes the checks above. `certification/verify.sh` makes the same checks, so
change the settings it expects in the same commit. An edit made directly in
`/etc/ssh/sshd_config.d/00-mac-dev-config.conf` lasts until the next apply
that runs the script.

### Turn Remote Login off

System Settings, General, Sharing, Remote Login. Script 07 runs only when
`sshd-mac.conf`, the key template, the account or the machine's name changes,
so it does not turn Remote Login back on at the next apply. `verify.sh` reports
it as a failure while it is off.

---

## Recreating this repo from scratch

Only needed to recreate the *repo*; a rebuild of the *machine* is the one
command at the top.

1. **Install Homebrew and chezmoi.**
   `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`,
   then `brew install chezmoi gh`, then `gh auth login`. Neither will be on
   `PATH` in an already-running shell — start a new terminal.
2. **Create the repo.** `gh repo create jcouball/mac-dev-config --public`
3. **Initialise.** `chezmoi init jcouball/mac-dev-config`
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
| When `main` has something to put on the Macs | `./certification/certify.sh` | See [Re-certify the rebuild](#re-certify-the-rebuild). |
| After a certified run, with its commit applied on the developing Mac | `./certification/record.sh` | Tags the commit with the result and moves `stable` to it. See [Record a run and move stable](#record-a-run-and-move-stable). |
| After `stable` moves, on each Mac that follows it | `chezmoi update` | Brings in the newly certified commits. |

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

Each certification is an annotated tag on the commit it certifies, named
`certified/<date>-<short commit>`. The tag's message holds the result:

```bash
git fetch --tags
git tag -l 'certified/*' --sort=-creatordate | head -1    # the latest
git tag -n99 -l 'certified/*'                             # all of them, with results
```

```text
Certified 0248e29 on 2026-11-23

VM result:            51 passed, 0 failed, 0 warnings, 2 excluded
Real-hardware result: 51 passed, 0 failed, 0 warnings, 0 excluded

Guest:        macOS 27.0.1, 6 CPU / 8 GB / 100 GB, user certuser
Host:         Neuromancer, macOS 27.2.1
Built from:   branch fix/homebrew-path-in-ssh-commands at 2b947d7
Tree:         1eb83e81fa018a022927a871678fbc6dac43537e
```

What changed between two certifications is in the commits between their tags:
`git log <older tag>..<newer tag>`. A tag has one more line, `Triggered by:`,
when `record.sh` was given `--reason "<one line>"`. That is for a trigger no
commit records: a macOS upgrade, a new base VM, or a second run of a commit
that has not changed.

Certification is two halves, and a tag records both. `certify.sh` proves
the *procedure* against a machine with nothing on it. `verify.sh` run here,
without `SKIP_MAS`, proves the three entries a VM structurally cannot reach —
so nothing is excluded on that side, and nothing is taken on trust.

`certification/record.sh` makes the tag, and makes it only when both halves
are about the same commit; it then moves `stable` to that commit.
[Record a run and move stable](#record-a-run-and-move-stable) says when to run
it. A tag that exists therefore always means a full
certification. `Built from` names what the VM cloned: `main`, or the branch
and the commit it was at before a rebase merge gave the change a new commit.

The real-hardware half comes from the Mac that recorded the certification,
which is the one being developed on at the time; the `Host` line says which.
A commit has one tag, from one Mac. On the other Mac, after `stable` has moved
and `chezmoi update` has run, `verify.sh` should give the same counts.

The tags are not signed. A ruleset on `certified/*` stops one being deleted or
moved, so a record cannot change after it is made. To correct a wrong tag,
turn the ruleset off first, on purpose.

The certifications made before `record.sh` existed were tagged by hand from
the table this section used to hold. Their messages have the same fields, say
`not recorded` where the table did not have a value, and end with a line saying
they were tagged by hand. The two oldest are VM runs with no real-hardware
half. The three newest also give cortex's result. The count of checks
changes from tag to tag as `verify.sh` gains or drops checks; that is
expected, and is why a tightened check triggers re-certification.

The two exclusions are the things an Apple Silicon VM structurally cannot
do — the 14 App Store apps and `zoom`. (`postgresql@17`'s service was a third
until the formula was removed from `.Brewfile`.) They are
reported as `SKIP`, never `WARN`: a warning you are expected to ignore on every
run teaches you to ignore warnings, which is the same argument this README makes
about false chezmoi drift. `WARN` means look at it; `SKIP` means a declared,
permanent limitation with nothing to be done about it here.

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
| **`graalvm/tap` could not be tapped at all**: current Homebrew rejects it with "invalid syntax in tap!", and `brew bundle check` failed on it. Nothing in `.Brewfile` came from it | the tap was cloned years ago, and Homebrew does not re-validate a tap that is already there |
| tart's formula in the abandoned `cirruslabs/cli` tap stopped loading on current Homebrew, so `brew bundle dump` silently dropped tart from `.Brewfile`. Tart now comes from `openai/tools` | tart was still installed and still ran; only the dump's diff showed the missing line |

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

**Almost nothing is version-pinned.** One entry in `.Brewfile` carries a version
in the formula *name* — `openssl@3` — and that is all. The
other 119 install whatever is current on the day. Only `.tool-versions` pins
exactly, which is the point: versions matter for the runtimes a project builds
against, and not for `ripgrep`. A rebuild next month gives a working machine
with different bytes, and that is the intended trade.

**Parallel installs race, and which ones race is luck.** Two certified runs,
five first-pass failures each, and almost entirely different sets:

| Run | Failed the parallel pass |
| --- | --- |
| `4a2974c` | `postgresql@17`, `shellcheck`, `tyriar.sort-lines`, `usernamehw.errorlens`, `vscjava.vscode-java-test` |
| `6ed8da6` | `postgresql@17`, `shellcheck`, `@github/copilot`, `ms-vscode-remote.remote-containers`, `ms-vscode.extension-test-runner` |
| `0b6a6b3` | `postgresql@17`, `@github/copilot`, `ms-vscode.remote-server` |

Both times every entry except `postgresql@17` installed cleanly on the serial
retry. `postgresql@17` is the structural VM limitation, not a race. The retry
turns a random failure into a random slowdown; it does not make the first pass
deterministic, and two collisions on the same entry in a row remain possible.

Note that `shellcheck` appears in both — a plain formula with no extension pack
in sight, which is the clearest evidence that packs are not the cause and
removing them would not have helped.

**The network is a dependency.** Homebrew's installer, the git clone, 121
downloads and the asdf plugin clones all have to succeed. Only `brew bundle`
retries. asdf plugins are cloned at HEAD, so plugin code itself changes between
runs.

**`--from-ipsw=latest` moves.** The base image is fixed once built — never
booted, automatic updates declined — but rebuilding it later gets a different
macOS. Record which IPSW a base image was built from if that matters.

What *is* deterministic, and deliberately so: script ordering (explicit
`after_`, not luck), the base image itself, and chezmoi's script state (every
run is a fresh clone).

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

One more entry turned out to be structurally impossible in a VM, and is
named individually in `verify.sh` rather than waved away — an exception you
cannot enumerate is indistinguishable from a bug you have stopped noticing:

| Entry | Why a VM cannot do it |
| --- | --- |
| **zoom** | The installer package's postinstall scripts fail. `installer` reports "An error occurred while running scripts from the package". It installs fine on real hardware. |

Zoom is worth a note of its own: it does not merely fail, it **hangs first**. The
postinstall script launches `ZoomUpdater`, which waits on a GUI session that will
never appear, so `installer` sits at 0% CPU for minutes with no output before
erroring. `certify.sh` skips it with `HOMEBREW_BUNDLE_CASK_SKIP=zoom` to buy that
time back; `verify.sh` still lists it as unverified, so it cannot be forgotten.

**The VM never turns Remote Login on.** `certify.sh` drives the VM over ssh, so
the base image has Remote Login on before the apply starts, and script 07
finds it on and skips that step. The run does prove the rest: the drop-in is
installed while the run is logged in, the key file is replaced by the
template's, and every connection `certify.sh` opens after the apply goes
through the new settings. Turning Remote Login on from off, without Full Disk
Access, is proved only by the first apply on a real Mac.

**Certification cannot see upgrade paths at all.** Every run starts from a
pristine image, so it only ever exercises a *fresh install*. A defect that only
affects a machine moving from an older state is invisible to it — by
construction, not by oversight.

That is not hypothetical. Adding `.chezmoi.toml.tmpl` introduced a
`computerName` key, and script 00 read it directly. On a fresh machine
`chezmoi init` always writes that key, so six certification runs passed. On this
Mac, whose chezmoi config predated the template, the key did not exist — and
chezmoi renders with `missingkey=error`, so the script did not skip, it failed
to render, and took the whole apply down with it. The script now uses `hasKey`
and degrades to a no-op.

The general rule: **a from-scratch certification says nothing about migration.**
Anything that reads state written by an earlier version of this repo needs
testing on a machine that has that state — which means this one. Run
`./certification/verify.sh` here after pulling, not just in the VM.

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

ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519_neuromancer_certvm \
  -C 'mac-dev-config certification VM'

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
cp ~/.ssh/id_ed25519_neuromancer_certvm.pub certification/
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

The public key is also in
`private_dot_ssh/private_authorized_keys.tmpl`, on the line for the account
`certuser`. The apply replaces the VM's `~/.ssh/authorized_keys` with that
file, and `certify.sh` logs in again afterwards. So a new certification key
has to go in the template in the same change, or the run locks itself out of
the VM partway through and ends with `verify.sh` unable to connect.

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
*config*. `private_dot_ssh/private_authorized_keys.tmpl` holds public keys,
which are safe to publish. The private keys (`id_ed25519_cortex`,
`id_rsa_proxmox_admin` and friends) are
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
chezmoi init --apply --branch stable jcouball/mac-dev-config
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
- **Warp's settings.** Warp writes them to `~/.warp/settings.toml` and carries
  some of them between devices with its own Settings Sync, but not the terminal
  font. The file is not managed here: Warp is being replaced by another
  terminal, and whether Warp reads a restored `settings.toml` on a fresh machine
  has not been tested. A rebuild brings back the application and whatever
  Settings Sync carries; the rest is step one of the by-hand list in
  [Rebuild from nothing](#rebuild-from-nothing).
- **VS Code settings** (as opposed to the extension list). Settings Sync owns
  those; the Brewfile owns which extensions are installed.
- **macOS system preferences.** No `defaults write` bank here. They are
  reproducible in principle and miserable in practice: undocumented keys, values
  that change between releases, and settings that need a logout to take effect.
  The computer name is one exception, because a rebuild must not silently
  answer to the wrong hostname. Remote Login is the other, because the other
  machines drive this one over ssh.
- **Per-project dependencies.** Gemfiles, `package.json`, project-level
  `.tool-versions`. These belong to their repos.
- **App Store app *data*.** The apps are declared; their contents are not.
- **Signing in to Tailscale.** It needs a person and a browser. The repo
  installs the right variant and starts the daemon:
  [Tailscale](#tailscale) has the by-hand part.
- **Anything you'd reinstall in under a minute.** This repo is for what is
  painful to reconstruct, not an inventory.

---

## Small gotchas

- **`brew bundle check` reports outdated packages as unsatisfied.** Set
  `HOMEBREW_BUNDLE_NO_UPGRADE=1` when you want to know what is *missing* rather
  than what is merely stale — `verify.sh` does exactly this, or the genuinely
  missing entries drown in a list of things that just want upgrading.
- **Script 06 runs only when Power Protect's state changes.** If it skips
  taking ownership of `powerProtect.scpt` because sudo was not available, it
  warns once and does not try again on the next apply. To make it run again,
  clear its record and re-apply:

  ```bash
  chezmoi state delete --bucket=entryState \
    --key="$HOME/.chezmoiscripts/06_install_amphetamine_power_protect.sh"
  sudo -v && chezmoi apply
  ```

  Do not delete the whole `entryState` bucket for this: that reruns every
  `run_onchange_` script, `brew bundle` included.
- **Warp fails Gatekeeper after a Homebrew install or upgrade.** Homebrew
  quarantines every cask it installs, and Warp staples its notarization ticket
  to the DMG rather than the app, so the first launch can fail with "Apple
  could not verify Warp is free of malware". Homebrew removed `--no-quarantine`
  in version 6, so the flag has to be cleared afterwards.
  `~/.local/bin/clear-warp-quarantine` removes it, but only when Homebrew
  manages Warp and the bundle's code signature verifies. Script 02 runs it
  after `brew bundle`, and a `post_commands` entry in `topgrade.toml` runs it
  after each topgrade run; it prints a line when it removes the flag or leaves
  one in place, and nothing when Warp is not quarantined. After any other
  install or upgrade (`brew upgrade --cask warp`, `brew reinstall --cask warp`,
  `brew-bundle-this-mac --file="$HOME/.Brewfile"` with `HOMEBREW_BUNDLE_NO_UPGRADE`
  unset, or a topgrade run interrupted before its post commands), run it by
  hand. `verify.sh` warns if Warp is still quarantined.

  For a copy of Warp that Homebrew did not install, or where the script is not
  deployed, clear the flag yourself, but only on a copy you trust:
  `xattr -drs com.apple.quarantine /Applications/Warp.app`.
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
- **Three provisioning scripts need sudo** — 00 (computer name), 05 (linking
  openjdk) and 06 (Power Protect's script) — but **never run
  `sudo chezmoi apply`.** The scripts call `sudo` themselves for the one command
  that needs it. Running chezmoi *as*
  root breaks the Brewfile step outright, because Homebrew refuses to run as
  root, and risks chezmoi writing root-owned files into your home directory.
  Scripts 00 and 02 refuse to start as root for that reason. The correct
  incantation caches the credential first:

  ```bash
  sudo -v && chezmoi apply -v
  ```

- **A failed script stays pending only if it exits non-zero.** Script 02
  deliberately does not: it reports a failing `brew bundle` and exits 0, so that
  one bad package cannot abort the whole apply. The cost is that chezmoi records
  it as done and will not retry until `.Brewfile` changes. That is the trade,
  and it is why `verify.sh` is the arbiter rather than `chezmoi status` — a clean
  status has already, once, sat over a Brewfile step that never ran.

- **A changed `.chezmoi.toml.tmpl` needs `chezmoi init`, not `chezmoi apply`.**
  chezmoi says so itself — *"config file template has changed, run chezmoi init
  to regenerate config file"* — and until you do, any template reading a new key
  fails to render. `chezmoi init` re-prompts for anything unanswered and leaves
  the rest alone.
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
  `HOMEBREW_NO_ANALYTICS: set`). A stale, unmanaged `~/.config/homebrew/brew.env`
  also exists, setting `HOMEBREW_NO_ANALYTICS` and `HOMEBREW_REQUIRE_TAP_TRUST`;
  it is inert only because `XDG_CONFIG_HOME` is unset. Set that variable and
  Homebrew reads that file instead, and also looks for `trust.json` in
  `~/.config/homebrew/`, where there is none, so every third-party tap entry
  stops loading until it is trusted again.
- **Formulae, casks and commands from third-party taps must be trusted.**
  Homebrew refuses to load them otherwise. `brew trust <tap>` (or
  `--formula`/`--cask`/`--command <name>`) records trust in
  `~/.homebrew/trust.json`, which chezmoi does not manage; `brew bundle dump`
  copies it into `.Brewfile` as `trusted: true`, and `brew bundle` on a new
  machine trusts those entries again. So after `brew install <tap>/<name>`, run
  `brew trust` before the dump, or the Brewfile line will be written without
  trust and fail to load on the next machine.
- **A pty is required to test an interactive shell.** `zsh -ic exit` without one
  cannot enable job control, and powerlevel10k's gitstatus emits six lines of
  alarming and completely meaningless output. `script -q /dev/null zsh -ic exit`
  gives it a pty and the noise disappears.
- **`chezmoi status` compares file contents only.** It will happily report a
  clean machine that has no Ruby installed. `./certification/verify.sh` is the
  one that looks at outcomes.
