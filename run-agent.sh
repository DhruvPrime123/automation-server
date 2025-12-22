#!/bin/bash

set -e

# Get variables from environment
GITHUB_REPO="${GITHUB_REPO}"
PROMPT="${PROMPT}"
GITHUB_TOKEN="${GITHUB_TOKEN:-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}"

if [ -z "$GITHUB_REPO" ] || [ -z "$PROMPT" ]; then
  echo "GITHUB_REPO or PROMPT not set"
  exit 1
fi

WORK_DIR=$(pwd)
REPO_NAME=$(basename $GITHUB_REPO .git)
REPO_DIR="${WORK_DIR}/repos/$REPO_NAME"

# Extract clean repo path (remove any tokens/protocols from input URL)
CLEAN_URL=$(echo "$GITHUB_REPO" | sed 's|https://.*@github.com/||' | sed 's|https://github.com/||' | sed 's|git@github.com:||' | sed 's|\.git$||')
AUTH_REPO_URL="https://primenayan:${GITHUB_TOKEN}@github.com/${CLEAN_URL}.git"

# Clone or pull repo
if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning repo..."
    git clone "$AUTH_REPO_URL" "$REPO_DIR"
else
    echo "Pulling latest changes..."
    cd "$REPO_DIR"
    
    # Reset remote URL to ensure it's clean
    git remote set-url origin "$AUTH_REPO_URL"
    
    # Switch to main/master branch and discard any local changes
    git fetch origin
    git checkout main 2>/dev/null || git checkout master 2>/dev/null || git checkout $(git remote show origin | grep "HEAD branch" | cut -d' ' -f5)
    git reset --hard origin/$(git branch --show-current)
    git pull
    
    cd ../../
fi

# TODO: HERE FIRST YOU GENERATE A RAG CONTEXT BASED ON THE REPO | VECTOR DATABASE ETC. OR VECTOR STORE 

# -------------------------
# Generate high-quality RAG context
# -------------------------

RAG_FILE="${WORK_DIR}/repos/${REPO_NAME}_rag.txt"
rm -f "$RAG_FILE"
touch "$RAG_FILE"

echo "Generating structured RAG context..."

########################################
# 1️⃣ PROJECT METADATA
########################################

echo "PROJECT METADATA:" >> "$RAG_FILE"

if [ -f "$REPO_DIR/package.json" ]; then
  echo "Project Type: Node.js / JavaScript" >> "$RAG_FILE"
elif [ -f "$REPO_DIR/pom.xml" ]; then
  echo "Project Type: Java / Maven" >> "$RAG_FILE"
elif [ -f "$REPO_DIR/requirements.txt" ]; then
  echo "Project Type: Python" >> "$RAG_FILE"
elif [ -f "$REPO_DIR/go.mod" ]; then
  echo "Project Type: Go" >> "$RAG_FILE"
else
  echo "Project Type: Unknown" >> "$RAG_FILE"
fi

echo -e "\n---\n" >> "$RAG_FILE"

########################################
# 2️⃣ REPOSITORY STRUCTURE (depth 3)
########################################

echo "REPOSITORY STRUCTURE:" >> "$RAG_FILE"
cd "$REPO_DIR"
tree -L 3 -I "node_modules|.git|dist|build" >> "$RAG_FILE" || ls >> "$RAG_FILE"
cd "$WORK_DIR"

echo -e "\n---\n" >> "$RAG_FILE"

########################################
# 3️⃣ CONFIGURATION FILES
########################################

echo "CONFIGURATION FILES:" >> "$RAG_FILE"

for FILE in package.json tsconfig.json next.config.js vite.config.js README.md; do
  if [ -f "$REPO_DIR/$FILE" ]; then
    echo -e "\nFILE: $FILE\n" >> "$RAG_FILE"
    sed -n '1,200p' "$REPO_DIR/$FILE" >> "$RAG_FILE"
  fi
done

echo -e "\n---\n" >> "$RAG_FILE"

########################################
# 4️⃣ INTENT-AWARE SOURCE FILES
########################################

PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

echo "RELEVANT SOURCE FILES:" >> "$RAG_FILE"

INCLUDE_DIRS=()

if [[ "$PROMPT_LOWER" == *"login"* || "$PROMPT_LOWER" == *"auth"* ]]; then
  INCLUDE_DIRS=("src/pages" "src/components" "src/services" "src/routes")
elif [[ "$PROMPT_LOWER" == *"api"* || "$PROMPT_LOWER" == *"backend"* ]]; then
  INCLUDE_DIRS=("src/routes" "src/controllers" "src/services")
else
  INCLUDE_DIRS=("src")
fi

for DIR in "${INCLUDE_DIRS[@]}"; do
  if [ -d "$REPO_DIR/$DIR" ]; then
    find "$REPO_DIR/$DIR" -type f \
      \( -name "*.js" -o -name "*.ts" -o -name "*.tsx" \) \
      | head -n 10 \
      | while read FILE; do
          echo -e "\nFILE: ${FILE#$REPO_DIR/}\n" >> "$RAG_FILE"
          sed -n '1,200p' "$FILE" >> "$RAG_FILE"
        done
  fi
done

echo -e "\n---\n" >> "$RAG_FILE"

########################################
# 5️⃣ CONSTRAINTS
########################################

cat <<EOF >> "$RAG_FILE"
CONSTRAINTS:
- Modify only files relevant to the user request
- Follow existing project structure and coding style
- Do NOT introduce new libraries unless absolutely necessary
- Reuse existing components and services
- Avoid breaking existing functionality
- Prefer minimal, clean commits
EOF

echo "RAG generation complete."

# TODO: HERE YOU GENERATE A VECTOR FROM THE PROMPT + MATCH WITH THE RAG 
# AND THEN YOU SEND RESULT AFTER MATCHING AS CONTEXT TO CLAUDE CODE


# Create Claude Code settings to bypass all permissions
echo "Setting up Claude Code auto-accept mode..."
mkdir -p "$REPO_DIR/.claude"
cat > "$REPO_DIR/.claude/settings.json" << 'EOF'
{
  "permissions": {
    "defaultMode": "acceptEdits"
  }
}
EOF

# ============================================
# ROOT BYPASS SETUP - Create Non-Root User (Linux/Docker only)
# ============================================
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    TEMP_USER="claude-runner"

    # Create temporary user if doesn't exist
    if ! id "$TEMP_USER" &>/dev/null; then
        echo "Creating temporary user: $TEMP_USER"
        useradd -m -s /bin/bash "$TEMP_USER" 2>/dev/null || adduser -D -s /bin/bash "$TEMP_USER" 2>/dev/null || true
    fi

    # Grant sudo privileges without password
    mkdir -p /etc/sudoers.d
    if [ ! -f "/etc/sudoers.d/$TEMP_USER" ]; then
        echo "$TEMP_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$TEMP_USER"
        chmod 440 "/etc/sudoers.d/$TEMP_USER" 2>/dev/null || true
    fi

    # Copy Claude authentication to temp user (from /root/.claude, not .config)
    if [ -d "/root/.claude" ]; then
        echo "Copying Claude auth to $TEMP_USER..."
        cp -r /root/.claude /home/$TEMP_USER/ 2>/dev/null || true
        cp /root/.claude.json /home/$TEMP_USER/ 2>/dev/null || true
        chown -R "$TEMP_USER:$TEMP_USER" /home/$TEMP_USER/.claude /home/$TEMP_USER/.claude.json 2>/dev/null || true
        echo "✓ Claude authentication copied"
    fi
else
    # On macOS/other systems, use current user
    TEMP_USER=$(whoami)
    echo "Running as current user: $TEMP_USER"
fi

# Find Claude CLI path
CLAUDE_PATH=$(which claude 2>/dev/null || echo "/root/.npm-global/bin/claude")
if [ ! -x "$CLAUDE_PATH" ]; then
    echo "ERROR: Claude CLI not found at $CLAUDE_PATH"
    exit 1
fi

# Change to repo directory
cd "$REPO_DIR"
echo "Current directory: $(pwd)"

# Step 1: Test Token Validity
echo "==========================================="
echo "Step 1: Testing GitHub token validity..."
echo "==========================================="
CLEAN_REPO_PATH=$(git remote get-url origin | sed 's|https://.*@github.com/||' | sed 's|https://github.com/||' | sed 's|git@github.com:||' | sed 's|\.git$||')

# if git ls-remote "https://${GITHUB_TOKEN}@github.com/${CLEAN_REPO_PATH}.git" HEAD &>/dev/null; then
#     echo "✓ GitHub token is valid and has access to the repository"
# else
#     echo "✗ ERROR: GitHub token is invalid or doesn't have access to the repository"
#     echo "Please check your GITHUB_TOKEN in docker-compose.yml"
#     exit 1
# fi

# Step 2: Configure Git and Set Remote Origin
echo "==========================================="
echo "Step 2: Configuring git and setting remote origin..."
echo "==========================================="
git config user.email "dhruv@primedemo.in"
git config user.name "DhruvPrime123"
git remote set-url origin "https://${GITHUB_TOKEN}@github.com/${CLEAN_REPO_PATH}.git"
echo "✓ Git configured with credentials"
echo "✓ Remote origin set with authenticated URL"

# Transfer repo ownership to temp user
echo "Transferring ownership to $TEMP_USER..."
chown -R "$TEMP_USER:$TEMP_USER" "$REPO_DIR" 2>/dev/null || true
chown "$TEMP_USER:$TEMP_USER" ./run-claude.expect 2>/dev/null || true

# Step 3: Run Claude Code as Non-Root User
echo "==========================================="
echo "Step 3: Running Claude Code as non-root user..."
echo "==========================================="

# Build the full prompt
FULL_PROMPT="User prompt: $PROMPT

Repository context:
$(cat $RAG_FILE)"

echo "Running Claude with expect script..."

# Use expect to automate Claude CLI interaction
chmod +x "${WORK_DIR}/run-claude.expect"

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux/EC2: Run as non-root user with su
    su "$TEMP_USER" -c "
        export GITHUB_TOKEN='${GITHUB_TOKEN}'
        export PATH=/root/.npm-global/bin:\$PATH
        cd '$REPO_DIR'
        '${WORK_DIR}/run-claude.expect' '$FULL_PROMPT' 2>&1
    " | tee "${WORK_DIR}/claude-execution.log"
    
    CLAUDE_EXIT_CODE=${PIPESTATUS[0]}
    
    # Restore ownership back to root
    chown -R root:root "$REPO_DIR" 2>/dev/null || true
else
    # macOS: Run directly as current user
    export GITHUB_TOKEN="${GITHUB_TOKEN}"
    cd "$REPO_DIR"
    "${WORK_DIR}/run-claude.expect" "$FULL_PROMPT" 2>&1 | tee "${WORK_DIR}/claude-execution.log"
    
    CLAUDE_EXIT_CODE=${PIPESTATUS[0]}
fi

echo "==========================================="
echo "Claude execution completed with exit code: $CLAUDE_EXIT_CODE"
echo "==========================================="

# Check for error messages in output
if grep -q "Invalid API key\|Please run /login\|Error:\|Failed" "${WORK_DIR}/claude-execution.log"; then
    echo "ERROR: Claude execution failed. Check output above."
    cat "${WORK_DIR}/claude-execution.log"
    exit 1
fi

# # Check if there are changes to commit
# if [ -n "$(git status --porcelain)" ]; then
#     echo "Committing and pushing changes..."
#     git add .
#     git commit -m "AI: auto-edits applied by Claude Code"
#     git push origin main || git push origin master
#     echo "Successfully pushed changes!"
# else
#     echo "No changes to commit"
# fi

echo "Completed auto-editing for $REPO_NAME"
