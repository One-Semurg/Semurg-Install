# Install Semurg

Semurg is a self-hosted memory for AI agents (a knowledge graph, vectors and graph RAG in one store) and a database for
the data around them. The first node is free, needs no account and no licence key, and sends nothing home.

**Requirements:** an Intel or AMD x86-64 processor with AVX2 or newer, 2 CPU threads and 4 GB of memory or more. Ubuntu
24.04 for the installer; any x86-64 Linux with Docker for the container.

## In Docker

```bash
docker run -d --name semurg -p 127.0.0.1:4000:4000 \
  --ulimit memlock=-1 --ulimit nofile=1048576:1048576 --security-opt seccomp=unconfined \
  -v semurg-data:/var/lib/semurg one.semurg.io/semurg
until docker logs semurg 2>&1 | grep -q 'Your API token'; do sleep 1; done
export SEMURG_API_TOKEN=$(docker exec semurg cat /var/lib/semurg/.api_token)
```

## With the installer (Ubuntu 24.04)

```bash
curl -fsSL https://one.semurg.io/install | less        # read it first
curl -fsSL https://one.semurg.io/install | sudo bash
```

## From Python

```bash
pip install semurg
python -m semurg up
```

Then connect an agent over MCP, or use the REST API and the clients: [one.semurg.io/install](https://one.semurg.io/install)
has every step, and [github.com/One-Semurg/semurg-mcp](https://github.com/One-Semurg/semurg-mcp) the agent setup.
Tested examples for eleven agent frameworks: [github.com/One-Semurg/semurg-examples](https://github.com/One-Semurg/semurg-examples).
