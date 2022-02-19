{ pkgs ? import (builtins.fetchTarball "https://github.com/nixos/nixpkgs/archive/b66b39216b1fef2d8c33cc7a5c72d8da80b79970.tar.gz") { }
}:

with pkgs;
mkShell rec {
  buildInputs = [
    go-jsonnet
    jsonnet-bundler
    gojsontoyaml
  ];

  shellHook = let
    concatVersions = x: lib.concatStringsSep "\n" (lib.flatten x);
    mapper = builtins.map (x: if builtins.typeOf x == "list" then concatVersions (mapper x) else x.name);
    versions = mapper buildInputs;
  in ''
    getVersion () {
      echo "${concatVersions versions}"
    }
    getVersion
  '';
}
