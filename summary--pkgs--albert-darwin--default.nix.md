`49c72e2b10bc4ace781069f0b55883f4e94d41a3787ff31c4ea0d544c6bfcb15`
Builds Albert from the unstable nixpkgs source on Apple Silicon macOS. Removes Linux-only Qt inputs, fixes Darwin CMake paths and Homebrew hints, moves the bundle into Applications, wraps only the main executable, links the framework, and re-signs the resulting bundle components.
