{
  inputs = {
    # Pin nixpkgs to a version where pyside6 matches uv.lock of upstream
    nixpkgs.url = "github:nixos/nixpkgs/0d534853a55b";
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pyproject-nix.follows = "pyproject-nix";
      };
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        uv2nix.follows = "uv2nix";
        pyproject-nix.follows = "pyproject-nix";
      };
    };
  };

  outputs = {
    nixpkgs,
    uv2nix,
    pyproject-nix,
    pyproject-build-systems,
    self,
  }: let
    forAllPkgs = f:
      nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed (
        system: f nixpkgs.legacyPackages.${system}
      );
  in {
    packages = forAllPkgs (pkgs: {
      default = pkgs.callPackage ./package.nix {
        inherit
          uv2nix
          pyproject-nix
          pyproject-build-systems
          ;
      };
      zfdash = self.packages.${pkgs.stdenv.system}.default;
    });

    nixosModules.default = import ./module.nix {
      inherit (self) outputs;
    };
  };

  nixConfig = {
    extra-substituters = ["https://colorman.cachix.org"];
    extra-trusted-public-keys = ["colorman.cachix.org-1:HbmIr3Upj+ghnP8EYogEn73eCUSDeFBJ+JoItkw8EbQ="];
  };
}
