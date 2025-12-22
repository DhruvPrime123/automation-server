#!/usr/bin/env node

const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

// Path to the output log file
const LOG_FILE = './claude-execution.log';

// Parse command line arguments
const args = process.argv.slice(2);
let GITHUB_REPO = '';
let PROMPT = '';
let GITHUB_TOKEN_ARG = '';

// Parse arguments (supports --github-repo=value or --github-repo value)
for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--github-repo=')) {
        GITHUB_REPO = args[i].split('=')[1];
    } else if (args[i] === '--github-repo' && args[i + 1]) {
        GITHUB_REPO = args[i + 1];
        i++;
    } else if (args[i].startsWith('--prompt=')) {
        PROMPT = args[i].split('=')[1];
    } else if (args[i] === '--prompt' && args[i + 1]) {
        PROMPT = args[i + 1];
        i++;
    } else if (args[i].startsWith('--github-token=')) {
        GITHUB_TOKEN_ARG = args[i].split('=')[1];
    } else if (args[i] === '--github-token' && args[i + 1]) {
        GITHUB_TOKEN_ARG = args[i + 1];
        i++;
    }
}

// Validate required parameters
if (!GITHUB_REPO || !PROMPT) {
    console.error('Error: GITHUB_REPO and PROMPT are required');
    console.error('\nUsage:');
    console.error('  node run-standalone.js --github-repo <repo-url> --prompt "<prompt-text>" [--github-token <token>]');
    console.error('\nExample:');
    console.error('  node run-standalone.js --github-repo "https://github.com/user/repo" --prompt "Add a signup page"');
    console.error('  node run-standalone.js --github-repo "https://github.com/user/repo" --prompt "Add feature" --github-token "ghp_xxxx"');
    process.exit(1);
}

console.log(`Running auto-editor for repo: ${GITHUB_REPO}`);

// Add git instructions to the prompt for Claude Code
const fullPrompt = `${PROMPT}

IMPORTANT: After completing all code changes:
1. Create a new branch with a descriptive name (e.g., feature/add-signup-page)
2. Commit all changes with a clear commit message
3. Push to the new branch using: git push -u origin <branch-name>
4. Use the GITHUB_TOKEN environment variable for authentication if needed
5. DO NOT push directly to main/master branch

The GITHUB_TOKEN is available in the environment for authentication.`;

// Get GITHUB_TOKEN from command line args, then environment, then default
const GITHUB_TOKEN = GITHUB_TOKEN_ARG || process.env.GITHUB_TOKEN;

// Run the shell script with environment variables
const cmd = `GITHUB_REPO="${GITHUB_REPO}" PROMPT="${fullPrompt}" GITHUB_TOKEN="${GITHUB_TOKEN}" bash run-agent.sh 2>&1`;

const childProcess = exec(cmd, { maxBuffer: 1024 * 1024 * 10 });

let output = '';

// Pipe stdout to console in real-time
childProcess.stdout.on('data', (data) => {
    console.log(data.toString());
    output += data.toString();
});

// Pipe stderr to console in real-time
childProcess.stderr.on('data', (data) => {
    console.error(data.toString());
    output += data.toString();
});

// Handle completion
childProcess.on('close', (code) => {
    console.log(`Process exited with code ${code}`);
    
    // Filter output to keep only content after CONSTRAINTS section
    const marker = "- Prefer minimal, clean commits";
    const markerIndex = output.indexOf(marker);
    const filteredOutput = markerIndex !== -1 
        ? output.substring(markerIndex + marker.length).trim()
        : output;
    
    // Write filtered output to log file (override existing content)
    fs.writeFileSync(LOG_FILE, filteredOutput, 'utf8');
    console.log(`Filtered output saved to ${LOG_FILE}`);
    
    // Read the log file
    const logContent = fs.readFileSync(LOG_FILE, 'utf8');
    
    if (code !== 0) {
        console.error('\n❌ Process failed with exit code:', code);
        process.exit(code);
    }
    
    console.log('\n✅ Process completed successfully!');
    console.log(`\nOutput saved to: ${LOG_FILE}`);
    process.exit(0);
});

// Handle errors
childProcess.on('error', (error) => {
    console.error(`Error: ${error}`);
    const errorMessage = error.message;
    
    // Write error to log file
    fs.writeFileSync(LOG_FILE, errorMessage, 'utf8');
    
    console.error('\n❌ Process failed with error:', errorMessage);
    process.exit(1);
});
