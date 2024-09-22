{ pkgs, lib }:
let
  evaluationFilepath = ../evaluation.jsonl;
in
rec {
  manage = pkgs.writeScriptBin "manage" ''
    exec ${lib.getExe pkgs.python3} ${toString ../src/website/manage.py} $@
  '';

  initialSetup = pkgs.writeScriptBin "initialSetup" ''
    echo foo > .credentials/SECRET_KEY
    echo bar > .credentials/GH_CLIENT_ID
    echo baz > .credentials/GH_SECRET
    echo quux > .credentials/GH_WEBHOOK_SECRET
    ${lib.getExe setup}
  '';

  setup = pkgs.writeScriptBin "setup" ''
    createdb nix-security-tracker
    manage migrate
    manage createsuperuser --username admin  # prompts for password
    manage ingest_bulk_cve --subset 100
    manage initiate_checkout   # Checkout based on LOCAL_NIXPKGS_CHECKOUT
    manage fetch_all_channels  # Fails if LOCAL_NIXPKGS_CHECKOUT is not set
    manage ingest_manual_evaluation cd17fb8b3bfd63bf4a54512cfdd987887e1f15eb nixos-unstable ${evaluationFilepath} --subset 100
  '';

  reset =
    let
      missingEvaluationFile = ''
        Evaluation file is missing:

        ${evaluationFilepath}

        # Run an evaluation (>30 min):

        get-all-hydra-jobs.sh -I nixpkgs=channel:nixos-23.11
        mv evaluation.jsonl ${evaluationFilepath}

        # Or get a pre-made evaluation:

        wget https://files.lahfa.xyz/private/evaluation.jsonl.zst
        zstd -d evaluation.jsonl.zst
      '';
    in
    pkgs.writeShellApplication {
      # Quickly reset the database to a known-good state
      name = "reset";
      runtimeInputs = [ manage ];
      text = ''
        set -e

        if [ ! -f "${evaluationFilepath}" ]; then
          echo ${missingEvaluationFile}
          exit 1
        fi

        dropdb nix-security-tracker
        ${lib.getExe setup}
      '';
    };

  get-all-hydra-jobs = pkgs.writeShellApplication {
    name = "get-all-hydra-jobs";
    text = ''
      NIXPKGS_ARGS="{ config = { allowUnfree = true; inHydra = false; allowInsecurePredicate = (_: true); scrubJobs = false; }; };"
      nix-eval-jobs --force-recurse --meta --repair --quiet \
      --gc-roots-dir /tmp/gcroots \
      --expr "(import <nixpkgs/pkgs/top-level/release.nix> { nixpkgsArgs = $NIXPKGS_ARGS })" \
      "$@" > evaluation.jsonl
    '';
  };
}
