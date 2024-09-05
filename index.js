const fs = require('fs');
const path = require('path');
const readline = require('readline');

// File extensions to look for
const extensions = [
    '.js', '.jsx', '.ts', '.tsx', // JavaScript and TypeScript
    '.cpp', '.c', '.h', // C and C++
    '.json', // JSON
    '.dart', // Dart
    '.py', // Python
    '.java', // Java
    '.rb', // Ruby
    '.php', // PHP
    '.html', '.htm', // HTML
    '.css', // CSS
    '.scss', '.sass', // SASS/SCSS
    '.md', // Markdown
    '.go', // Go
    '.rs', // Rust
    '.swift', // Swift
    '.kt', '.kts', // Kotlin
    '.sh', '.bash', '.zsh', // Shell scripts
    '.pl', '.pm', // Perl
    '.r', // R
    '.jl', // Julia
    '.lua', // Lua
    '.sql' // SQL
];

// Create an interface for user input
const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});

// Function to scan directories and gather code files
const scanDirectories = (dirs) => {
    let codeFiles = [];

    const scanDirectory = (dir) => {
        const files = fs.readdirSync(dir);
        files.forEach(file => {
            const filePath = path.join(dir, file);
            const stats = fs.statSync(filePath);
            if (stats.isDirectory()) {
                scanDirectory(filePath);
            } else if (extensions.includes(path.extname(file))) {
                const content = fs.readFileSync(filePath, 'utf8');
                codeFiles.push({ filePath, content });
            }
        });
    };

    dirs.forEach(dir => {
        if (fs.existsSync(dir)) {
            scanDirectory(dir);
        } else {
            console.log(`Directory ${dir} does not exist.`);
        }
    });

    return codeFiles;
};

// Function to generate unique output file name
const generateOutputFileName = (baseName, ext) => {
    const dirFiles = fs.readdirSync('.');
    let counter = 1;
    let outputFile = `${baseName}${ext}`;
    
    while (dirFiles.includes(outputFile)) {
        outputFile = `${baseName}${counter}${ext}`;
        counter++;
    }

    return outputFile;
};

// Function to write code files to a single .md file
const writeToFile = (codeFiles, outputFile) => {
    const outputStream = fs.createWriteStream(outputFile, { flags: 'w' });
    codeFiles.forEach(file => {
        outputStream.write(`${file.filePath}\n\n\`\`\`${path.extname(file.filePath).substring(1)}\n${file.content}\n\`\`\`\n\n`);
    });
    outputStream.end();
};

// Ask the user for folder names
rl.question('Enter folder names to scan (comma separated): ', (input) => {
    const folders = input.split(',').map(folder => folder.trim());
    const codeFiles = scanDirectories(folders);

    rl.question('Enter output file name (default: output.md): ', (outputFileName) => {
        const baseName = outputFileName.trim() || 'output';
        const ext = path.extname(baseName) || '.md';
        const baseNameWithoutExt = path.basename(baseName, ext);
        const outputFile = generateOutputFileName(baseNameWithoutExt, ext);

        writeToFile(codeFiles, outputFile);
        console.log(`Scanning complete. Check the ${outputFile} file for results.`);
        rl.close();
    });
});