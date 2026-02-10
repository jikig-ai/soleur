# Soleur Telegram Bridge

A lightweight bridge that connects Telegram to the Claude Code CLI via a
WebSocket transport layer. Send messages to your Telegram bot, and they are
forwarded to a Claude Code session running with the Soleur plugin. Responses
stream back to Telegram in real time. The bot uses long-polling (outbound only),
so no public HTTP endpoint or TLS certificate is required.

## Architecture

```
Telegram App
    |
    v  (Telegram Bot API -- long polling)
Bridge Server  (Bun + grammY)
    |
    v  (WebSocket, localhost)
Claude Code CLI + Soleur Plugin
    |
    v
Project Files
```

## Prerequisites

- **Telegram bot token** -- create via [@BotFather](https://t.me/BotFather)
- **Hetzner Cloud account** -- [hetzner.com/cloud](https://www.hetzner.com/cloud)
- **Terraform** >= 1.0
- **Docker** (local builds) or access to GHCR
- **SSH key pair** (ed25519 recommended)

## Quick Start

1. **Create a Telegram bot.** Open [@BotFather](https://t.me/BotFather) in
   Telegram, run `/newbot`, and copy the token.

2. **Get your Telegram user ID.** Message
   [@userinfobot](https://t.me/userinfobot) and note the numeric ID.

3. **Create a Hetzner API token.** In the Hetzner Cloud console, go to
   Security > API Tokens and generate a read/write token.

4. **Fill in Terraform variables.** Copy the example below into
   `infra/terraform.tfvars`:

   ```hcl
   hcloud_token = "your-hetzner-api-token"
   admin_ips    = ["YOUR.IP.ADDR.HERE/32"]
   ```

5. **Provision the server.**

   ```sh
   cd infra
   terraform init
   terraform apply
   ```

   Note the `server_ip` output.

6. **Upload the environment file.** Create a local `.env` with the values from
   the environment variables table below, then copy it to the server:

   ```sh
   scp .env root@<server_ip>:/mnt/data/.env
   ```

7. **Authenticate Claude Code.** SSH into the server and run the login flow
   inside the container:

   ```sh
   ssh root@<server_ip>
   docker exec -it soleur-bridge claude login
   ```

8. **Restart the container** so it picks up the new `.env`:

   ```sh
   docker restart soleur-bridge
   ```

9. **Send your first message.** Open Telegram, find your bot, and type
   `/start`. You should receive a greeting from the bridge.

## Local Development

```sh
# Install dependencies
bun install

# Copy and fill environment variables
cp .env.example .env
# Edit .env with your TELEGRAM_BOT_TOKEN and TELEGRAM_ALLOWED_USER_ID

# Start in watch mode
bun run dev
```

## Deployment

The `scripts/deploy.sh` script builds the Docker image, pushes it to GHCR, and
restarts the container on the remote server. It requires:

- `BRIDGE_HOST` environment variable set to the server IP
- Docker logged in to GHCR (`docker login ghcr.io`)

```sh
BRIDGE_HOST=<server_ip> ./scripts/deploy.sh
```

## Operations

Use `scripts/remote.sh` for day-to-day server management. Set `BRIDGE_HOST`
first:

```sh
export BRIDGE_HOST=<server_ip>

./scripts/remote.sh status   # Docker ps, memory, disk
./scripts/remote.sh logs     # Last 100 log lines
./scripts/remote.sh logs 50  # Last 50 log lines
./scripts/remote.sh restart  # Restart the container
./scripts/remote.sh health   # Hit the /health endpoint
```

## Cost Breakdown

| Resource        | Monthly Cost |
|-----------------|-------------|
| Hetzner CX22   | EUR 3.49    |
| Primary IPv4    | EUR 0.50    |
| 10 GB Volume    | EUR 0.44    |
| **Total**       | **~EUR 4.43 (~$4.80 USD)** |

## Environment Variables

| Variable                   | Required | Description                                      |
|----------------------------|----------|--------------------------------------------------|
| `TELEGRAM_BOT_TOKEN`       | Yes      | Bot API token from @BotFather                    |
| `TELEGRAM_ALLOWED_USER_ID` | Yes      | Numeric Telegram user ID (single-user lockdown)  |
| `WS_PORT`                  | No       | WebSocket port for CLI communication (default: 8765) |
