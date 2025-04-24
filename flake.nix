{
  
  description = "rules_pyo3";
  inputs = {
    systems.url = "github:nix-systems/x86_64-linux";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-utils.inputs.systems.follows = "systems";
  };
  outputs = { self, systems, nixpkgs, flake-utils }:
    (flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
          src = ./.;
          patched_qemu = pkgs.qemu_kvm.overrideAttrs (oldAttrs: rec {
            patches = [ 
                (pkgs.fetchpatch {
                  name = "qemu-physmem.patch";
                  url = "https://github.com/dingelish/qemu/commit/876e262744a6483a3bcb37a07767e6c75f9cf4ee.diff";
                  sha256 = "sha256-zSSykwOadwmzSfWOe9Sj30Lni1uHShzKvkCcCJN/X8Y=";
                })
             ];
          });
        in
        {
          packages = {  };
          formatter = pkgs.nixpkgs-fmt;
          # We define a recursive set of shells, so that we can easily create a shell with a subset
          # of the dependencies for specific CI steps, without having to pull everything all the time.
          #
          # To add a new dependency, you can search it on https://search.nixos.org/packages and add its
          # name to one of the shells defined below.
          devShells = rec {
            # Base shell with shared dependencies.
            base = with pkgs; mkShell {
              packages = [
                cachix
                just
                ps
                which
              ];
            };
            containers = with pkgs; mkShell {
              # We need access to the kernel source and configuration, not just the binaries, to
              # build the system image with nvidia drivers in it.
              # See oak_containers/system_image/build-base.sh (and nvidia_base_image.Dockerfile) for
              # more details.
              inputsFrom = [
                base
                bazelShell
              ];
              packages = [
                bc
                bison
                cpio
                curl
                docker
                elfutils
                fakeroot
                nodejs_22
                flex
                jq
                libelf
                perl
                strip-nondeterminism
                glibc
                glibc.static
                ncurses
                netcat
                umoci
              ];
            };
            # Minimal shell with only the dependencies needed to run the Rust tests.
            # Shell for oak_containers_kernel.
            # Minimal shell with only the dependencies needed to run the bazel steps.
            bazelShell = with pkgs; mkShell {
              packages = [
                autoconf
                autogen
                automake
                bazel_7
                bazel-buildtools
                coreutils
              ];
            };
            toolsShell = with pkgs; mkShell {
              packages = [
                nodePackages.pnpm
                nodePackages.prettier
                nodePackages.ts-node
                htop
                pkgs.coreutils
                nmap
                tcpdump
                patched_qemu
		            shfmt
                netcat
              ];
            };
            wasm_build = with pkgs; pkgs.mkShell {
              packages = [
                wasm-pack
                protobuf
                nodePackages.ts-node
                nodePackages.pnpm
              ];
            };

            ci = pkgs.mkShell {
              packages = [];
              inputsFrom = [
                base
                bazelShell
                wasm_build
                containers
              ];
            };
            # By default create a shell with all the inputs.
            default = pkgs.mkShell {
              packages = [];
              inputsFrom = [
                containers
                toolsShell
                bazelShell
              ];
            };
          };
        }));
}
