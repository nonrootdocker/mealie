{
  description = "minimalbase + mealie service";
  inputs = {
    # Mealie is built from nixpkgs (pkgs.mealie) — NOT pinned in this repo.
    # nixpkgs is its own input (not `follows`) so update-flake-lock can bump it,
    # which is what advances Mealie to the latest packaged release.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    minimalbase.url = "github:nonrootdocker/minimalbase";
  };
  outputs = { self, nixpkgs, minimalbase }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    # Mealie, straight from nixpkgs (frontend yarn build + python backend already
    # solved + maintained upstream). No version/hash pinned here.
    mealie = pkgs.mealie;

    # NLTK tagger data needed at runtime for ingredient parsing.
    nltkData = pkgs.nltk-data.averaged-perceptron-tagger-eng;

    # ----------------------------
    # Startup: initialise the DB, then run the gunicorn server (bin/mealie).
    # ----------------------------
    startScript = pkgs.writeShellScript "mealie-start" ''
      ${mealie}/libexec/init_db
      exec ${mealie}/bin/mealie -b 0.0.0.0:9000
    '';

    # ----------------------------
    # User database configuration (/etc/passwd)
    # ----------------------------
    passwdFile = pkgs.writeTextDir "etc/passwd" ''
      root:x:0:0:root:/root:/bin/sh
      mealie:x:1000:1000:mealie:/data:/bin/sh
    '';

    # ----------------------------
    # ABI descriptor for container-init
    # ----------------------------
    mealieAbi = pkgs.writeTextFile {
      name = "mealie-abi.json";
      text = builtins.toJSON {
        version = 2;
        process = {
          exec = "${startScript}";
          args = [ ];
        };
      };
      destination = "/app/main";
    };

  in {
    packages.${system} = {
      default = self.packages.${system}.mealie-image;
      # Authoritative version from nixpkgs' mealie; exposed for CI tagging.
      version = pkgs.writeText "mealie-version" mealie.version;
      mealie-image = pkgs.dockerTools.buildImage {
        name = "mealie";
        tag = "latest";
        fromImage = minimalbase.packages.${system}.base-image;
        copyToRoot = pkgs.buildEnv {
          name = "root";
          paths = [
            pkgs.coreutils
            pkgs.tzdata
            pkgs.cacert
            pkgs.ffmpeg
            mealie
            mealieAbi
            passwdFile
          ];
        };
        config = {
          Entrypoint = [ "${minimalbase.packages.${system}.container-init}/bin/container-init" ];
          User = "1000:1000";
          Env = [
            "PATH=/bin"
            "TZ=UTC"
            "LANG=en_US.UTF-8"
            "PRODUCTION=true"
            "DATA_DIR=/data"
            "NLTK_DATA=${nltkData}"
          ];
        };
      };
    };
  };
}
