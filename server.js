const express = require('express');
const bodyParser = require('body-parser');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const app = express();
const port = 5002;

app.use(bodyParser.json());

// Path to the output log file
const LOG_FILE = 'claude-execution.log';

// API endpoint for n8n
app.get('/', (req, res) => {
    return res.json({
        success: true,
        output: "Running", 
    });
})
app.post('/run', (req, res) => {
    const { GITHUB_REPO, PROMPT } = req.body;

    if (!GITHUB_REPO || !PROMPT) {
        return res.status(400).send("GITHUB_REPO and PROMPT are required");
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

    // Run the shell script with environment variables
    const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
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
        
        // Read the log file and return it
        const logContent = fs.readFileSync(LOG_FILE, 'utf8');
        
        if (code !== 0) {
            return res.status(500).json({
                success: false,
                exitCode: code,
                output: logContent,
                timestamp: new Date().toLocaleString()
            });
        }
        
        res.json({
            success: true,
            exitCode: code,
            output: logContent, 
            timestamp: new Date().toLocaleString()
        });
    });

    // Handle errors
    childProcess.on('error', (error) => {
        console.error(`Error: ${error}`);
        const errorMessage = error.message;
        
        // Write error to log file
        fs.writeFileSync(LOG_FILE, errorMessage, 'utf8');
        
        res.status(500).json({
            success: false,
            error: errorMessage,
            output: errorMessage,
            timestamp: new Date().toLocaleString()
        });
    });
});

app.listen(port, () => {
    console.log(`Auto-editor API running on port ${port}`);
});
