#!/bin/bash

# Path to the output log file
LOG_FILE="./claude-execution.log"

# Initialize variables
GITHUB_REPO=""
PROMPT=""
GITHUB_TOKEN_ARG=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --github-repo)
            GITHUB_REPO="$2"
            shift 2
            ;;
        --github-repo=*)
            GITHUB_REPO="${1#*=}"
            shift
            ;;
        --prompt)
            PROMPT="$2"
            shift 2
            ;;
        --prompt=*)
            PROMPT="${1#*=}"
            shift
            ;;
        --github-token)
            GITHUB_TOKEN_ARG="$2"
            shift 2
            ;;
        --github-token=*)
            GITHUB_TOKEN_ARG="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$GITHUB_REPO" ] || [ -z "$PROMPT" ]; then
    echo "Error: GITHUB_REPO and PROMPT are required"
    echo ""
    echo "Usage:"
    echo "  ./run-standalone.sh --github-repo <repo-url> --prompt \"<prompt-text>\" [--github-token <token>]"
    echo ""
    echo "Example:"
    echo "  ./run-standalone.sh --github-repo \"https://github.com/user/repo\" --prompt \"Add a signup page\""
    echo "  ./run-standalone.sh --github-repo \"https://github.com/user/repo\" --prompt \"Add feature\" --github-token \"ghp_xxxx\""
    exit 1
fi

echo "Running auto-editor for repo: $GITHUB_REPO"

# Add git instructions to the prompt for Claude Code
FULL_PROMPT="$PROMPT

IMPORTANT: After completing all code changes:
1. Create a new branch with a descriptive name (e.g., feature/add-signup-page)
2. Commit all changes with a clear commit message
3. Push to the new branch using: git push -u origin <branch-name>
4. Use the GITHUB_TOKEN environment variable for authentication if needed
5. DO NOT push directly to main/master branch

The GITHUB_TOKEN is available in the environment for authentication."

# Get GITHUB_TOKEN from command line args, then environment, then default
if [ -n "$GITHUB_TOKEN_ARG" ]; then
    GITHUB_TOKEN="$GITHUB_TOKEN_ARG"
elif [ -n "$GITHUB_TOKEN" ]; then
    GITHUB_TOKEN="$GITHUB_TOKEN"
else
    GITHUB_TOKEN=""
fi

# Export environment variables
export GITHUB_REPO
export PROMPT="$FULL_PROMPT"
export GITHUB_TOKEN

# Check if we're on Linux and need sudo
if [[ "$OSTYPE" == "linux-gnu"* ]] && [ "$EUID" -ne 0 ]; then
    echo "Linux detected - running with sudo (preserving environment variables)..."
    # Run the shell script with sudo, preserving environment variables
    OUTPUT=$(sudo -E bash run-agent.sh 2>&1)
    EXIT_CODE=$?
else
    # Run the shell script normally and capture output
    OUTPUT=$(bash run-agent.sh 2>&1)
    EXIT_CODE=$?
fi

echo "$OUTPUT"

# Filter output to keep only content after CONSTRAINTS section
MARKER="- Prefer minimal, clean commits"
if echo "$OUTPUT" | grep -qF -- "$MARKER"; then
    FILTERED_OUTPUT=$(echo "$OUTPUT" | sed -n "/$(printf '%s\n' "$MARKER" | sed 's/[]\/$*.^[]/\\&/g')/,\$p" | tail -n +2)
else
    FILTERED_OUTPUT="$OUTPUT"
fi

# Write filtered output to log file
echo "$FILTERED_OUTPUT" > "$LOG_FILE"
echo "Filtered output saved to $LOG_FILE"

# Exit with the same code as the child process
if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "❌ Process failed with exit code: $EXIT_CODE"
    exit $EXIT_CODE
fi

echo ""
echo "✅ Process completed successfully!"
echo ""
echo "Output saved to: $LOG_FILE"
exit 0
