# Automatic Emscripten SDK Setup

## Overview

The build system now automatically downloads and installs the Emscripten SDK on **Windows** if it's not already present. This eliminates manual setup steps and makes the build process much smoother.

## How It Works

### 1. First Build (No emsdk Present)

```bash
PS> zig build -Dtarget=wasm32-emscripten
```

Output:
```
========================================
Emscripten SDK not found!
========================================

Downloading and installing emsdk...
This may take a few minutes.

[1/3] Cloning emsdk repository...
[2/3] Installing latest emsdk version...
[3/3] Activating emsdk...

✅ Emscripten SDK installed successfully!
Location: C:\Users\...\zig-particle-life-emscripten\emsdk

Using Emscripten from: C:\Users\...\zig-particle-life-emscripten\emsdk\upstream\emscripten
...
```

### 2. Subsequent Builds

Once emsdk is installed, it's detected automatically:

```bash
PS> zig build -Dtarget=wasm32-emscripten
```

Output:
```
Using Emscripten from: C:\Users\...\zig-particle-life-emscripten\emsdk\upstream\emscripten
...
```

## Implementation Details

### Functions in `build.zig`

1. **`checkEmsdkExists()`**
   - Checks if `emsdk/` directory exists in project root
   - Returns `true` if found, `false` otherwise

2. **`setupEmsdk()`** (Windows only)
   - Clones emsdk repository using git
   - Runs `emsdk.bat install latest`
   - Runs `emsdk.bat activate latest`
   - Shows progress output to user

3. **`getEmscriptenPath()`**
   - Returns sysroot path if explicitly provided via `--sysroot`
   - Otherwise, checks if local emsdk exists
   - If not, calls `setupEmsdk()` on Windows
   - Returns path to `emsdk/upstream/emscripten`

### Requirements

- **Git** must be installed and in PATH
- **Internet connection** for first build
- **~2GB disk space** for emsdk installation
- **Windows** OS (for automatic setup)

### Manual Override

You can still provide an explicit sysroot:

```bash
zig build -Dtarget=wasm32-emscripten --sysroot C:/custom/emsdk/upstream/emscripten
```

This bypasses the automatic setup and uses your specified path.

## Platform Support

### ✅ Windows (Fully Automatic)

No manual steps required! Just run:
```bash
zig build -Dtarget=wasm32-emscripten
```

### ⚠️ Linux/macOS (Manual Setup Required)

Currently, Linux and macOS require manual emsdk installation:

```bash
# Clone emsdk
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk

# Install and activate
./emsdk install latest
./emsdk activate latest

# Build with explicit sysroot
cd ../zig-particle-life-emscripten
zig build -Dtarget=wasm32-emscripten --sysroot ~/emsdk/upstream/emscripten
```

**TODO:** Automatic setup for Linux and macOS will be added in the future.

## Troubleshooting

### Git Not Found

**Error:**
```
Error cloning emsdk:
'git' is not recognized as an internal or external command...
```

**Solution:**
- Install Git for Windows from https://git-scm.com/download/win
- Make sure it's in your PATH
- Restart your terminal

### Network Issues

**Error:**
```
fatal: unable to access 'https://github.com/emscripten-core/emsdk.git/':
Failed to connect to github.com
```

**Solution:**
- Check your internet connection
- If behind a corporate firewall, configure git proxy
- Alternatively, manually clone emsdk and retry

### Incomplete Installation

**Error:**
```
Error: Emscripten path not found: ...\emsdk\upstream\emscripten
The emsdk installation may be incomplete.
```

**Solution:**
- Delete the `emsdk/` directory
- Run the build again to re-download

### Permission Issues

**Error:**
```
Access denied when creating emsdk directory
```

**Solution:**
- Run terminal as Administrator
- Or choose a different project location with write permissions

## Git Ignore

The `emsdk/` directory is automatically ignored via `.gitignore`:

```gitignore
# Emscripten SDK (auto-downloaded)
emsdk/
```

This keeps your repository clean and lets each developer have their own local emsdk installation.

## Benefits

1. **Zero Configuration** - No manual emsdk setup for Windows users
2. **Project-Local SDK** - Each project has its own emsdk (no global installation conflicts)
3. **Consistent Versions** - Everyone gets the same "latest" version
4. **Easy CI/CD** - Can be automated in build pipelines
5. **No Repository Bloat** - emsdk is gitignored, not committed

## Future Enhancements

- [ ] Add support for Linux (using `emsdk` bash script)
- [ ] Add support for macOS (using `emsdk` bash script)
- [ ] Cache emsdk across multiple projects (optional global cache)
- [ ] Add version pinning (e.g., install specific emsdk version)
- [ ] Add progress bars for long downloads
- [ ] Verify emsdk integrity after installation

