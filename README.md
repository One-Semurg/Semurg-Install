# Install Semurg

Semurg is a self-hosted memory for AI agents (a knowledge graph, vectors and graph RAG in one store) and a database for
the data around them. The first node is free, needs no account and no licence key, and sends nothing home.

**Requirements:** Linux on an Intel or AMD x86-64 processor with AVX2 or newer, glibc 2.34 or newer, 2 CPU threads, 4 GB of
memory and 20 GB of free disk. The installer is tested with every release on Ubuntu 24.04 and also passes on Ubuntu 22.04,
Debian 12 and 13, Rocky Linux 9, AlmaLinux 9, Fedora 41 and Arch Linux; any other x86-64 Linux with Docker runs the
container. There is no Mac or ARM build yet; on Windows, WSL2 is being tested.

## In Docker

```bash
docker run -d --name semurg -p 127.0.0.1:4000:4000 \
  --ulimit memlock=-1 --ulimit nofile=1048576:1048576 --security-opt seccomp=unconfined \
  -v semurg-data:/var/lib/semurg one.semurg.io/semurg
until docker logs semurg 2>&1 | grep -q 'Your API token'; do sleep 1; done
export SEMURG_API_TOKEN="$(docker exec semurg cat /var/lib/semurg/.api_token)"
```

The API token is never printed, so it stays out of terminal logs and agent transcripts: the container log says when it is
ready, and the last line reads it into your shell.

## With the installer

```bash
curl -fsSL https://one.semurg.io/install | less        # read it first
curl -fsSL https://one.semurg.io/install | sudo bash
export SEMURG_API_TOKEN="$(sudo grep '^SEMURG_API_TOKEN=' /etc/semurg/semurg.env | cut -d= -f2-)"
```

The installer ends with a SUCCESS banner that names where the token is kept and the one command that reads it (the last
line above).

## From Python

```bash
pip install semurg
python -m semurg up        # starts a node in Docker, or reuses the running one; the client reads its token itself
```

Then connect an agent over MCP, or use the REST API and the clients: [one.semurg.io/install](https://one.semurg.io/install)
has every step, and [github.com/One-Semurg/semurg-mcp](https://github.com/One-Semurg/semurg-mcp) the agent setup.
Tested examples for eleven agent frameworks: [github.com/One-Semurg/semurg-examples](https://github.com/One-Semurg/semurg-examples).
What changed in each release: [CHANGELOG](https://github.com/One-Semurg/semurg-mcp/blob/main/CHANGELOG.md).
