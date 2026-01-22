# ZfDash Nix Flake

This repository packages [ZfDash](https://github.com/ad4mts/zfdash) for use on
Nix/NixOS systems, along with a module setting up a systemd service.

It creates 2 systemd services, a root service where zfdash runs in daemon mode,
and a dynamic service where zfdash runs in web mode.

This Nix package is built using a very specific revision of nixpkgs, as ZfDash
has some specific dependency requirements. It is therefore recommended to not
override the nixpkgs input of this flake, as this will likely break the build.
The nixpkgs revision used also requires compiling qtwebengine from source, as it
is not cached by cache.nixos.org. This repo contains a workflow to automate this
process, uploading the result to the colorman.cachix.org binary cache.

## Usage

Run ZfDash directly from this repository:

```bash
$ nix run github:TheColorman/zfdash-nix-flake -- --help
usage: main.py [-h] [-w] [--host HOST] [-p PORT] [--debug] [--socket [PATH]]
   or: main.py --connect-socket [PATH]  # Connect only (no auto-launch)
   or: main.py --launch-daemon [PATH]   # Launch daemon and exit
   or: main.py --stop-daemon [PATH]     # Stop running daemon
   or: main.py --daemon --uid UID --gid GID [--listen-socket [PATH]]
...
```

Install and enable the ZfDash service:

```nix
# flake.nix
{
    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
        zfdash-nix-flake.url = "github:thecolorman/zfdash-nix-flake";
    };

    outputs = {
        nixpkgs,
        zfdash-nix-flake,
        ...
    }: {
        nixosConfigurations.my-hostname = nixpkgs.lib.nixosSystem {
            modules = [
                zfdash-nix-flake.nixosModules.default
                ./configuration.nix
            ];
        };
    }
}
```

```nix
# configuration.nix
{
    services.zfdash = {
        enable = true;
        address = "127.0.0.1";
        port = 8765;
    };
}
```

## Agent mode

The NixOS module currently does not support running ZfDash in Agent mode.
Instead, you can create a systemd service similar to the ones provided by the
module, changing the commands so that it runs in Agent mode.
