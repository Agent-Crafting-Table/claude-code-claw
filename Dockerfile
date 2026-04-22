FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates tmux unzip git openssh-client \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code --legacy-peer-deps

WORKDIR /workspace
CMD ["/workspace/start.sh"]
