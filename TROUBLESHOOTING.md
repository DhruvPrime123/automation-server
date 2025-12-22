# Troubleshooting Guide

## Common Issues and Solutions

### Issue: Permission Denied on EC2/Linux

**Error:**
```
run-agent.sh: line 179: /etc/sudoers.d/claude-runner: Permission denied
❌ Process failed with exit code: 1
```

**Solution:**
The script needs to be run with `sudo` on Linux systems. The wrapper script now automatically handles this.

Simply run:
```bash
./run-standalone.sh --github-repo "https://github.com/user/repo" --prompt "Your prompt" --github-token "ghp_xxx"
```

The script will automatically use `sudo -E` (which preserves environment variables) when needed on Linux.

---

### Issue: adduser command showing help text

**Error:**
```
Creating temporary user: claude-runner
adduser [--uid id] [--firstuid id] [--lastuid id]
...
```

**Solution:**
This has been fixed. The script now:
1. Checks for `useradd` first (available on most Linux distros)
2. Falls back to `adduser --disabled-password --gecos ""` with the correct syntax for Debian/Ubuntu

---

### Issue: tree command not found

**Error:**
```
run-agent.sh: line 81: tree: command not found
```

**Solution:**
This has been fixed. The script now gracefully handles missing `tree` command by using `find` instead.

If you want the nicer tree output, you can install it:
```bash
# Ubuntu/Debian
sudo apt-get install tree

# Amazon Linux/RHEL/CentOS
sudo yum install tree

# macOS
brew install tree
```

---

## Usage on EC2

On EC2/Linux instances, you can run the script directly without explicitly using sudo:

```bash
./run-standalone.sh \
  --github-repo "https://github.com/DhruvPrime123/basic-frontend" \
  --prompt "Add authentication signup feature" \
  --github-token "ghp_xxxxxxxxxxxxx"
```

The script will automatically invoke `sudo` internally when needed.

---

## Usage on macOS

On macOS, the script runs without sudo:

```bash
./run-standalone.sh \
  --github-repo "https://github.com/user/repo" \
  --prompt "Your task" \
  --github-token "ghp_xxxxxxxxxxxxx"
```

---

## Environment Variables

All environment variables (GITHUB_TOKEN, GITHUB_REPO, PROMPT) are preserved when the script invokes sudo using the `-E` flag.

---

## Manual Sudo Usage

If you prefer to run with sudo manually:

```bash
sudo -E ./run-standalone.sh --github-repo "..." --prompt "..." --github-token "..."
```

The `-E` flag ensures your environment variables are preserved.
