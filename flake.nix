{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = { nixpkgs, flake-parts, ... }@inputs: flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      inputs.flake-parts.flakeModules.easyOverlay
    ];
    perSystem = { config, self', inputs', pkgs, system, ... }:
      with pkgs;
      {
        devShells.default = mkShell {
          buildInputs = [
            go-jsonnet
            jsonnet-bundler
            gojsontoyaml
          ];
        };
      };
    systems = nixpkgs.lib.systems.flakeExposed;
  };
}


