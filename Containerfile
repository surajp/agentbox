# agentbox: the Linux userland a coding agent runs in.
# Each `container run` boots this image in its own lightweight VM.
FROM docker.io/library/node:22-bookworm-slim

# Everyday dev tools an agent reaches for. Keep this list honest: every
# extra tool is more surface area, but a box without git/rg is useless.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates curl ripgrep jq less procps \
        python3 python3-venv python3-pip build-essential openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Jujutsu (jj) isn't packaged for bookworm, so install the static musl build
# from GitHub releases, pinned by version and checksum.
ARG JJ_VERSION=0.47.1
RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
        arm64) arch=aarch64; sha=0f300e1576de8dabe0a9dedf0b87ae44f8accea5cf54d9a342a51061c1fb1bcd ;; \
        amd64) arch=x86_64;  sha=d4b657f622ee50929c8916466dfa3d6a6c17a0a32b50e7b2c793707ec9ebcad7 ;; \
        *) echo "unsupported arch for jj" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/jj.tar.gz \
        "https://github.com/jj-vcs/jj/releases/download/v${JJ_VERSION}/jj-v${JJ_VERSION}-${arch}-unknown-linux-musl.tar.gz"; \
    echo "${sha}  /tmp/jj.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/jj.tar.gz -C /usr/local/bin ./jj; \
    rm /tmp/jj.tar.gz; \
    jj --version

# Install agents globally under /usr/local, NOT in $HOME:
# /home/agent is replaced by a host bind mount at runtime and would hide them.
RUN npm install -g @anthropic-ai/claude-code && npm cache clean --force

# Match the host user's uid/gid so files the agent writes into /workspace
# come out owned by you on macOS. (macOS gid 20 = staff; in Debian gid 20
# already exists as "dialout", so reuse whatever group holds that gid.)
ARG UID=501
ARG GID=20
RUN getent group "${GID}" >/dev/null || groupadd -g "${GID}" agent; \
    userdel -r node 2>/dev/null || true; \
    useradd -m -u "${UID}" -g "${GID}" -s /bin/bash agent

# container's virtiofs doesn't pass through host ownership: a file reports the
# uid of whichever guest process first looked it up, and the workspace root is
# looked up by root at mount time. git then calls the repo "dubious". The check
# guards against other users' repos, which can't exist in a one-user VM.
RUN git config --system --add safe.directory '*'

USER agent
ENV HOME=/home/agent \
    PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin \
    IS_SANDBOX=1 \
    TERM=xterm-256color
WORKDIR /workspace
CMD ["bash"]
