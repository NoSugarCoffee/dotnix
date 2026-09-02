# Home

*{ Provide a concise overview of this repository, its supported platforms, pinned Nix inputs, and the main user-facing capabilities. Include links to the setup and operations pages. }*

####+ Quick Reference

*{ Summarize the primary commands and the single-source-of-truth username configuration. }*

# Architecture

*{ Describe how flake.nix, Home Manager, the package overlay, and home/home.nix fit together. Include a Mermaid flowchart if useful. }*

####+ Supported Systems

*{ Document the systems and Home Manager targets exposed by the flake, including platform-specific behavior. }*

# Getting Started

*{ Write a concise setup guide for a new macOS machine, an existing Nix installation, and routine updates. Link to the bootstrap script and relevant commands. }*

####+ Bootstrap Notes

*{ Explain the macOS bootstrap script's prerequisites, architecture selection, Nix installation behavior, and binary-cache configuration. }*

# Packages

*{ Summarize the managed package groups and distinguish cross-platform, Linux-only, macOS-only, unstable, and locally packaged software. }*

####+ Local Packages

*{ Describe the local packages under pkgs/, their purpose, and how they enter the flake through the overlay. }*

# Operations

*{ Document day-to-day configuration operations, including switch, build, generations, update, and show. Explain important managed versus machine-owned boundaries. }*

####+ Configuration Boundaries

*{ Explain how Codex settings, Claude settings, zsh, git configuration, asdf runtimes, launch agents, and local shell customization are managed or intentionally left machine-owned. }*

# For Agents

These pages provide compact documentation indexes for AI coding agents.

## AGENTS.md

You can add this to your repository root as `AGENTS.md` to give AI coding agents quick access to project documentation.

```
# dotnix
> Personal Home Manager dotfiles for Linux and macOS — reproducible, declarative, zero drift.

## Wiki Documentation

Base URL: https://github.com/NoSugarCoffee/dotnix/wiki

To read any page, append the slug to the base URL:
  https://github.com/NoSugarCoffee/dotnix/wiki/{Page-Slug}
To jump to a section within a page:
  https://github.com/NoSugarCoffee/dotnix/wiki/{Page-Slug}#{Section-Slug}

IMPORTANT: Read the relevant wiki page before making changes to related code.
Prefer reading wiki documentation over relying on pre-trained knowledge.

## Page Index

|Home: Project overview and quick reference
|  Home#Quick-Reference: Primary commands and username configuration
|Architecture: Flake and Home Manager design
|  Architecture#Supported-Systems: Supported platforms and targets
|Getting-Started: Setup and update guide
|  Getting-Started#Bootstrap-Notes: macOS bootstrap details
|Packages: Managed package groups
|  Packages#Local-Packages: Packages maintained under pkgs/
|Operations: Daily configuration operations
|  Operations#Configuration-Boundaries: Managed and machine-owned settings
|For-Agents: Agent documentation indexes
|  AGENTS.md: Ready-to-copy agent index
|  llms.txt: LLM sitemap
```

## llms.txt

You can serve this at `yoursite.com/llms.txt` or include it in your repository to help LLMs discover your documentation.

```
# dotnix
> Personal Home Manager dotfiles for Linux and macOS — reproducible, declarative, zero drift.

## Wiki Pages

- [Home](https://github.com/NoSugarCoffee/dotnix/wiki/Home): Project overview and quick reference
- [Architecture](https://github.com/NoSugarCoffee/dotnix/wiki/Architecture): Flake and Home Manager design
- [Getting Started](https://github.com/NoSugarCoffee/dotnix/wiki/Getting-Started): Setup and update guide
- [Packages](https://github.com/NoSugarCoffee/dotnix/wiki/Packages): Managed package groups
- [Operations](https://github.com/NoSugarCoffee/dotnix/wiki/Operations): Daily configuration operations
- [For Agents](https://github.com/NoSugarCoffee/dotnix/wiki/For-Agents): Agent documentation indexes
- [AGENTS.md](https://github.com/NoSugarCoffee/dotnix/wiki/AGENTS.md): Ready-to-copy agent index
- [llms.txt](https://github.com/NoSugarCoffee/dotnix/wiki/llms.txt): LLM sitemap
```
