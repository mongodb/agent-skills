# Shell Profile Locations and Reload Commands

This is an incomplete table of common shells, their profile file locations, and the commands to source/reload those profiles after making changes.

| Shell | Profile File Location(s) | Source/Reload Command | Env Variable Syntax | Notes |
|-------|-------------------------|----------------------|---------------------|-----|
| **bash** | `~/.bash_profile`, `~/.bashrc`, `~/.profile`, `/etc/profile` | `source ~/.bashrc` or `. ~/.bashrc` | `export VAR_NAME="value"` | Prefer `~/.bash_profile` unless you can confirm `~/.bashrc` is sourced |
| **zsh** | `~/.zshrc`, `~/.zprofile`, `~/.zlogin`, `/etc/zshrc` | `source ~/.zshrc` or `. ~/.zshrc` | `export VAR_NAME="value"` | |
| **fish** | `~/.config/fish/config.fish`, `~/.config/fish/conf.d/*.fish` | `source ~/.config/fish/config.fish` | `set -gx VAR_NAME "value"` | |
| **ksh** (Korn) | `~/.kshrc`, `~/.profile`, `$ENV` variable points to config | `source ~/.kshrc` or `. ~/.kshrc` | `export VAR_NAME="value"` | |
| **tcsh** | `~/.tcshrc`, `~/.cshrc`, `~/.login` | `source ~/.tcshrc` | `setenv VAR_NAME "value"` | |
| **csh** | `~/.cshrc`, `~/.login` | `source ~/.cshrc` | `setenv VAR_NAME "value"` | |
| **dash** | `~/.profile`, `/etc/profile` (no interactive config) | `. ~/.profile` | `export VAR_NAME="value"` | |
| **sh** (POSIX) | `~/.profile`, `/etc/profile`, `$ENV` variable | `. ~/.profile` | `export VAR_NAME="value"` | |
| **PowerShell** | `$PROFILE` (varies by OS/host), e.g., `~/.config/powershell/profile.ps1` | `. $PROFILE` or `. ~/.config/powershell/profile.ps1` | `$env:VAR_NAME = "value"` | Check `$PROFILE` variable for exact path, may need to create the file if it doesn't exist |
| **elvish** | `~/.elvish/rc.elv` | `source ~/.elvish/rc.elv` or `-source ~/.elvish/rc.elv` | `set-env VAR_NAME "value"` | |
| **nushell** | `~/.config/nushell/config.nu`, `~/.config/nushell/env.nu` | `source ~/.config/nushell/config.nu` | `$env.VAR_NAME = "value"` | |
| **xonsh** | `~/.xonshrc` | `source ~/.xonshrc` or `execx(open('~/.xonshrc').read())` | `$VAR_NAME = "value"` | |
| **ion** | `~/.config/ion/initrc` | `source ~/.config/ion/initrc` | `let VAR_NAME=value` | |
