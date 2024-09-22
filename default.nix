{
  sources ? import ./npins,
  overlay ? import ./nix/overlay.nix,
  pkgs ? import sources.nixpkgs { overlays = [ overlay ]; },
}:
let
  helpers = pkgs.callPackage ./nix/helpers.nix { };

  self = rec {
    inherit (pkgs) python3;
    localPythonPackages = import ./pkgs { inherit pkgs python3; };

    # For exports.
    overlays = [ overlay ];
    package = pkgs.web-security-tracker;
    module = import ./nix/web-security-tracker.nix;

    pre-commit-check = pkgs.pre-commit-hooks {
      src = ./.;

      settings.statix.ignore = [ "staging" ];

      hooks =
        let
          pythonExcludes = [
            "/migrations/" # auto-generated code
          ];
        in
        {
          # Nix setup
          nixfmt = {
            enable = true;
            entry = pkgs.lib.mkForce "${pkgs.lib.getExe pkgs.nixfmt}";
          };
          statix.enable = true;
          deadnix.enable = true;

          # Python setup
          ruff = {
            enable = true;
            excludes = pythonExcludes;
          };
          ruff-format = {
            enable = true;
            name = "Format python code with ruff";
            types = [
              "text"
              "python"
            ];
            entry = "${pkgs.lib.getExe pkgs.ruff} format";
            excludes = pythonExcludes;
          };

          pyright =
            let
              pyEnv = pkgs.python3.withPackages (_: pkgs.web-security-tracker.propagatedBuildInputs);
              wrappedPyright = pkgs.runCommand "pyright" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
                makeWrapper ${pkgs.pyright}/bin/pyright $out \
                  --set PYTHONPATH ${pyEnv}/${pyEnv.sitePackages} \
                  --prefix PATH : ${pyEnv}/bin \
                  --set PYTHONHOME ${pyEnv}
              '';
            in
            {
              enable = true;
              entry = pkgs.lib.mkForce (builtins.toString wrappedPyright);
              excludes = pythonExcludes;
            };

          # Global setup
          prettier = {
            enable = true;
            excludes = [
              "\\.min.css$"
              "\\.html$"
            ];
          };
          commitizen.enable = true;
        };
    };

    shell = pkgs.mkShell {
      DATA_CACHE_DIRECTORY = toString ./. + "/.data_cache";
      REDIS_SOCKET_URL = "unix:///run/redis/redis.sock";
      # `./src/website/tracker/settings.py` by default looks for LOCAL_NIXPKGS_CHECKOUT
      # in the root of the repo. Make it the default here for local development.
      LOCAL_NIXPKGS_CHECKOUT = toString ./. + "/nixpkgs";

      packages = [
        package
        pkgs.nix-eval-jobs
        pkgs.commitizen
        pkgs.npins
        pkgs.nixfmt
        pkgs.hivemind
      ] ++ (with pkgs.lib; collect isDerivation helpers);

      shellHook = ''
        ${pre-commit-check.shellHook}

        mkdir -p .credentials
        export DATABASE_URL=postgres:///nix-security-tracker
        export CREDENTIALS_DIRECTORY=${builtins.toString ./.credentials}
      '';
    };

    tests = import ./nix/tests/vm-basic.nix {
      inherit pkgs;
      wstModule = module;
    };
  };
in
self // self.tests
