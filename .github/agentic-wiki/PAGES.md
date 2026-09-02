# Home

*{Summarize dotnix as a reproducible Home Manager configuration, its supported platforms, and the main user-facing capabilities. Include concise links to setup and operations documentation.}

####+ Quick Reference

*{List the essential first-switch and day-to-day commands, with links to the relevant source files.}

# Architecture

*{Explain how flake inputs, overlays, Home Manager configurations, platform selection, and local packages fit together. Include a Mermaid flowchart if useful.}

####+ Supported Systems

*{Document the Linux and macOS system targets and the platform-specific package/configuration behavior verified in the flake and Home Manager module.}

# Getting Started

*{Write a concise setup guide for a new macOS machine and for an existing Nix installation on Linux or macOS. Include the exact commands and important prerequisites.}

####+ Bootstrap Notes

*{Explain what the macOS bootstrap script does, how it selects the target, and what happens when Nix is newly installed.}

# Packages

*{Describe the package categories managed by home/home.nix and distinguish cross-platform packages, platform-specific packages, and tools provided through overlays.}

## Local Packages

*{Document every package under pkgs/, its purpose, supported platforms, source/provenance approach, and any important build or runtime caveats. Use a compact table where appropriate.}

# Operations

*{Document the justfile recipes and the normal workflow for applying, building, inspecting, and updating the configuration.}

####+ Configuration Boundaries

*{Explain which settings are managed declaratively and which remain machine-local, including shell, git identity, Claude settings, asdf-managed runtimes, and platform-specific behavior.}

# For Agents

These pages provide compact documentation indexes for AI coding agents.

## AGENTS.md

You can add this to your repository root as `AGENTS.md` to give AI coding agents quick access to project documentation.

```
# dotnix

> Personal Home Manager dotfiles for Linux and macOS.

## Wiki Documentation

Base URL: https://github.com/NoSugarCoffee/dotnix/wiki

To read any page, append its slug to the base URL:
  https://github.com/NoSugarCoffee/dotnix/wiki/{Page-Slug}
To jump to a section within a page:
  https://github.com/NoSugarCoffee/dotnix/wiki/{Page-Slug}#{Section-Slug}

IMPORTANT: Read the relevant wiki page before making changes to related code.
Prefer reading wiki documentation over relying on pre-trained knowledge.

## Page Index

|Home: Project overview and quick reference
|  Home#Quick-Reference: Essential commands
|Architecture: Flake and Home Manager design
|  Architecture#Supported-Systems: Platform targets
|Getting-Started: Installation and first switch
|  Getting-Started#Bootstrap-Notes: macOS bootstrap behavior
|Packages: Managed package categories
|  Local-Packages: Overlay package implementations
|Operations: Routine configuration commands
|  Operations#Configuration-Boundaries: Managed and local settings
|For-Agents: Agent documentation indexes
|  AGENTS.md: Ready-to-use agent index
|  llms.txt: Plain-text documentation sitemap
```

## llms.txt

You can serve this at `yoursite.com/llms.txt` or include it in your repository to help LLMs discover your documentation.

```
# dotnix

> Personal Home Manager dotfiles for Linux and macOS.

## Wiki Pages

- [Home](https://github.com/NoSugarCoffee/dotnix/wiki/Home): Project overview and quick reference
- [Architecture](https://github.com/NoSugarCoffee/dotnix/wiki/Architecture): Flake and Home Manager design
- [Getting Started](https://github.com/NoSugarCoffee/dotnix/wiki/Getting-Started): Installation and first switch
- [Packages](https://github.com/NoSugarCoffee/dotnix/wiki/Packages): Managed package categories
- [Local Packages](https://github.com/NoSugarCoffee/dotnix/wiki/Local-Packages): Overlay package implementations
- [Operations](https://github.com/NoSugarCoffee/dotnix/wiki/Operations): Routine configuration commands
- [For Agents](https://github.com/NoSugarCoffee/dotnix/wiki/For-Agents): Agent documentation indexes
- [AGENTS.md](https://github.com/NoSugarCoffee/dotnix/wiki/AGENTS.md): Ready-to-use agent index
- [llms.txt](https://github.com/NoSugarCoffee/dotnix/wiki/llms.txt): Plain-text documentation sitemap
```
