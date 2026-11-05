# agentbox

Run Claude Code (or any command) inside an Apple [`container`](https://github.com/apple/container)
VM that sees only the current project. Because the VM is the sandbox, Claude runs with
`--dangerously-skip-permissions` and doesn't stop to ask before each action.

    cd ~/projects/foo
    agentbox            # Claude Code, permissions skipped

## Requirements

- A Mac with Apple silicon, running macOS 26 or later
- Apple `container` 1.6 or later
- `bash`, `shasum` and `readlink -f` (all built into macOS)
- `jq` (optional): lets new projects skip Claude's onboarding screens

## Setup

1. **Install Apple container.** Download the signed `.pkg` from the
   [releases page](https://github.com/apple/container/releases), install it, then start the service once:

       container system start      # the first run offers to download a Linux kernel: accept
       container --version         # must be 1.6 or later

2. **Install agentbox.** Clone the repo anywhere and put the script on your `PATH`. A symlink is fine:
   the script finds its `Containerfile` through it.

       git clone <this-repo-url> ~/src/agentbox
       mkdir -p ~/.local/bin
       ln -s ~/src/agentbox/agentbox ~/.local/bin/agentbox   # make sure ~/.local/bin is on PATH

3. **Build the image.** This takes a few minutes the first time. It also happens automatically on first use.

       agentbox build

4. **Create a projects folder.** agentbox only runs inside `~/projects/<name>` or `/tmp/<name>`:

       mkdir -p ~/projects

5. **Log in once.** Either:
   - start `agentbox` in any project and run `/login` inside Claude. The login is shared by all projects.
   - or `export ANTHROPIC_API_KEY=...` on the host. It's forwarded into the VM only when set.

## Usage

    agentbox                 # Claude Code in the current project
    agentbox claude [args]   # same, with extra Claude Code arguments
    agentbox shell           # interactive bash in the box
    agentbox run CMD...      # run any command in the box
    agentbox build           # (re)build the image
    agentbox build --no-cache --pull   # rebuild from scratch: updates Claude Code and the base image
    agentbox clean           # force-remove leaked agentbox VMs

Each invocation boots a fresh VM and removes it when the command exits, including on Ctrl-C,
SIGTERM and closing the terminal.

### Configuration

| Variable          | Default                      | Purpose                                     |
|-------------------|------------------------------|---------------------------------------------|
| `AGENTBOX_DNS`    | `1.1.1.1`                    | DNS server for builds and VMs               |
| `AGENTBOX_CPUS`   | `4`                          | CPUs per VM                                 |
| `AGENTBOX_MEM`    | `8G`                         | Memory per VM                               |
| `AGENTBOX_IMAGE`  | `agentbox:latest`            | Image name                                  |
| `AGENTBOX_DATA`   | `~/.local/share/agentbox`    | Agent homes and shared login                |

DNS is always passed explicitly because the vmnet gateway's DNS refuses queries on some Macs. If your
network blocks public DNS, point `AGENTBOX_DNS` at your LAN resolver in your shell profile.

## What the box can and can't touch

- **Only one project.** agentbox runs only in `~/projects/<name>` or `/tmp/<name>` (or deeper).
  It refuses everything else, including `$HOME`, `~/.ssh` and `~/projects` itself. The current
  directory is mounted read-write at the same path, so file paths match on both sides.
- **Nothing else from your Mac.** Your home directory, SSH keys, cloud credentials, keychain, real
  Claude config and other repos are never mounted. There's no SSH agent forwarding, so the agent
  can't push. Your git name and email are passed in so its commits are attributed to you.
- **Host-execution guard.** git hooks and repo config (`core.fsmonitor`, `core.hooksPath`, ...) and
  jj repo config run *on your Mac* the next time you use git/jj there. So `.git/hooks`, `.git/config`
  and `.jj/repo/config.toml` are mounted read-only. This means the agent can't run `git config`,
  `git remote add` or `git push -u`. agentbox also snapshots nested repos, submodules and
  worktrees, and prints a red warning on exit listing any hook or config that changed.
  The check runs after the session ends, so don't run git inside nested repos on the host while a
  session is still running.
- **Per-project agent home.** Each project gets its own `/home/agent`, stored in
  `$AGENTBOX_DATA/homes/<name>-<hash>`, so transcripts, history and memory never leak between
  projects. Only the login is shared, via `$AGENTBOX_DATA/shared`: it's copied in before each run
  and copied back if Claude refreshed it. `shared/settings.json` is copied into project homes but
  never synced back, so one project can't plant settings (hooks) in another.
- **Locked-down VM.** It runs with `--cap-drop ALL` and `--init`, as a non-root user with your
  uid/gid, so files it writes are owned by you.

### Known gaps

- **Unrestricted network.** The VM can reach the internet and your LAN, so a compromised agent
  could send out the project's contents or probe local services.
- **The agent can delete or rewrite the project, history included.** Push often.
- **`ANTHROPIC_API_KEY`, if forwarded, is readable by anything in the VM**, including package
  install scripts.
- **Claude Code inside the image doesn't auto-update.** Run `agentbox build --no-cache --pull` to update it.

## Files

- `agentbox`: the CLI wrapper (bash)
- `Containerfile`: the VM image (Debian + Node 22, git, ripgrep, python3, build tools, Claude Code)
