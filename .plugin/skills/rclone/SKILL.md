---
name: rclone
description: "Upload, sync, or manage files across cloud storage providers using rclone. Handles transfers to S3, Cloudflare R2, Backblaze B2, Google Drive, Dropbox, or any S3-compatible storage."
triggers:
- rclone
- cloud storage transfer
- file sync remote
- s3 upload
---

# rclone File Transfer Skill

## Setup Check (Always Run First)

Before any rclone operation, verify installation and configuration:

```bash
# Check if rclone is installed
command -v rclone >/dev/null 2>&1 && rclone version || echo "NOT INSTALLED"

# List configured remotes
rclone listremotes 2>/dev/null || echo "NO REMOTES CONFIGURED"
```

### If rclone is NOT installed

Guide the user to install:

```bash
# macOS
brew install rclone

# Linux (static binary to ~/.local/bin)
mkdir -p ~/.local/bin && curl -sfL https://downloads.rclone.org/rclone-current-linux-amd64.zip -o /tmp/rclone.zip && unzip -q /tmp/rclone.zip -d /tmp && cp /tmp/rclone-*/rclone ~/.local/bin/ && chmod +x ~/.local/bin/rclone
# For arm64: replace amd64 with arm64 in the URL above
```

### If NO remotes are configured

Walk the user through interactive configuration:

```bash
rclone config
```

**Common provider setup quick reference:**

| Provider | Type | Key Settings |
|----------|------|--------------|
| AWS S3 | `s3` | access_key_id, secret_access_key, region |
| Cloudflare R2 | `s3` | access_key_id, secret_access_key, endpoint (account_id.r2.cloudflarestorage.com) |
| Backblaze B2 | `b2` | account (keyID), key (applicationKey) |
| DigitalOcean Spaces | `s3` | access_key_id, secret_access_key, endpoint (region.digitaloceanspaces.com) |
| Google Drive | `drive` | OAuth flow (opens browser) |
| Dropbox | `dropbox` | OAuth flow (opens browser) |

**Example: Configure Cloudflare R2**

```bash
rclone config create r2 s3 \
  provider=Cloudflare \
  access_key_id=YOUR_ACCESS_KEY \
  secret_access_key=YOUR_SECRET_KEY \
  endpoint=ACCOUNT_ID.r2.cloudflarestorage.com \
  acl=private
```

**Example: Configure AWS S3**

```bash
rclone config create aws s3 \
  provider=AWS \
  access_key_id=YOUR_ACCESS_KEY \
  secret_access_key=YOUR_SECRET_KEY \
  region=us-east-1
```

## Common Operations

### Upload single file

```bash
rclone copy /path/to/file.mp4 remote:bucket/path/ --progress
```

### Upload directory

```bash
rclone copy /path/to/folder remote:bucket/folder/ --progress
```

### Sync directory (mirror, deletes removed files)

```bash
rclone sync /local/path remote:bucket/path/ --progress
```

### List remote contents

```bash
rclone ls remote:bucket/
rclone lsd remote:bucket/  # directories only
```

### Check what would be transferred (dry run)

```bash
rclone copy /path remote:bucket/ --dry-run
```

## Useful Flags

| Flag | Purpose |
|------|---------|
| `--progress` | Show transfer progress |
| `--dry-run` | Preview without transferring |
| `-v` | Verbose output |
| `--transfers=N` | Parallel transfers (default 4) |
| `--bwlimit=RATE` | Bandwidth limit (e.g., `10M`) |
| `--checksum` | Compare by checksum, not size/time |
| `--exclude="*.tmp"` | Exclude patterns |
| `--include="*.mp4"` | Include only matching |
| `--min-size=SIZE` | Skip files smaller than SIZE |
| `--max-size=SIZE` | Skip files larger than SIZE |

## Large File Uploads

For videos and large files, use chunked uploads:

```bash
# S3 multipart upload (automatic for >200MB)
rclone copy large_video.mp4 remote:bucket/ --s3-chunk-size=64M --progress

# Resume interrupted transfers
rclone copy /path remote:bucket/ --progress --retries=5
```

## Verify Upload

```bash
# Check file exists and matches
rclone check /local/file remote:bucket/file

# Get file info
rclone lsl remote:bucket/path/to/file
```

## Troubleshooting

```bash
# Test connection
rclone lsd remote:

# Debug connection issues
rclone lsd remote: -vv

# Check config
rclone config show remote
```
