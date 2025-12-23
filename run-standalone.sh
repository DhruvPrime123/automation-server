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
IMPORTANT: INTERPRETING THE USER PROMPT
The user prompt may describe:
- A bug, crash, or runtime error
- A feature request
- A refactor or improvement
- A test failure
- A performance or security concern
- or anyother code-related task

You must:
- Translate the prompt into a concrete technical task
- Identify the exact files that need changes
- Avoid scope creep — only address what the prompt asks

If the prompt is too ambiguous:
- Make the smallest reasonable assumption
- Prefer safe, backward-compatible behavior

CRITICAL: CHANGE STRATEGY & RISK CONTROL
**VERY IMPORTANT: MAKE SURE THAT YOUR CHANGE DOESN'T BREAK THE BUILD OR CAUSE ANY OTHER ISSUES AND ENSURE THAT OTHER FEATURES OR PARTS OF THE CODEBASE ARE UNAFFECTED**
- Make the smallest change that fully solves the problem
- Avoid touching unrelated code paths
- Do not refactor unless it directly improves correctness or clarity
- For risky changes:
    - Try Creating a backup branch first so that you can revert if needed 
    - Add safeguards
    - Preserve backward compatibility
    - Prefer explicit behavior over implicit behavior
- Include the original prompt, your plan, key changes, and validation steps.
- Note any risks, trade-offs, or follow-up actions.
- For complex tasks, append a section detailing how you handled edge cases and validation
- Identify dependencies, edge cases, and risks before starting implementation.
- If multiple services are affected:
    - Prefer localized fixes over cross-cutting changes

IMPORTANT: After completing all code changes:
1. Create a new branch with a descriptive name (e.g., feature/add-signup-page)
2. Commit all changes with a clear commit message
3. Push to the new branch using: git push -u origin <branch-name>
4. Use the GITHUB_TOKEN environment variable for authentication if needed
5. DO NOT push directly to main/master branch
6. Once all the changes are done, on the claude-execution.log file, provide a concise summary of changes made and the branch name created.
7. If accurate completion is not possible:
    - Do NOT push partial changes
    - Do NOT guess or hallucinate behavior

IMPORTANT: The GITHUB_TOKEN is available in the environment for authentication.

CONSTRAINTS:
- Prefer minimal, clean commits
- Ensure code compiles and passes tests before committing
- Follow existing code style and conventions
- Avoid large monolithic commits; break changes into logical steps
- Do not include sensitive information in commits
- If unsure about a change, leave a comment in the code for human review OR Create a file with names human-review-needed.txt listing areas needing attention
- Do NOT ask questions
- Do NOT request clarification
- Do NOT output explanations outside claude-execution.md
- Do NOT skip steps
- Operate fully autonomously
- Prioritize correctness over speed

IMPORTANT: 
- Never leak secrets, tokens, or credentials
- Never log sensitive data
- Assume production data is valuable and fragile
- Treat concurrency, async flows, and I/O carefully
- Avoid race conditions and partial writes
"

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
echo "--------------------------------------------------------------------" 
exit 0
