{
  description = "toku-web build environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      toolsFor = pkgs: with pkgs; [
        gcc gnumake pkg-config perl
        lua5_1 luarocks
        openresty
        nodejs nodePackages.npm
        emscripten
        sqlite
        git curl wget
        imagemagick librsvg
        python3
        inotify-tools
      ];
    in {
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          default = pkgs.buildEnv {
            name = "toku-web";
            paths = toolsFor pkgs;
          };
        });

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          default = pkgs.mkShell {
            packages = toolsFor pkgs;
          };
        });

      overlays.default = final: prev: {
        toku-web = self.packages.${prev.system}.default;
      };
    };
}
