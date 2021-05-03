{ pkgs ? import <nixpkgs> { } }:

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
