`8a326e5fd6c4af1ce158609dc23f639795bb3c3a7a40cc832005f5ceb6dc85d8`
macOS-only activation for the optional `pkgs.nosugarcoffee.qingjian` package. Copies Qingjian.app into `~/Library/Input Methods`, stages replacement safely, stops existing Qingjian processes, clears relevant input-source caches, registers the new input source, and records the source path in an XDG state marker.
