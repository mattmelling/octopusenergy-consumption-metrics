{
  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" ];
      pkgs = import nixpkgs {
        system = "x86_64-linux";
      };
      octopusenergy-consumption-metrics = (pkgs: let
        nodejs = pkgs.nodejs-14_x;
        nodeEnv = import ./node2nix.nix {
          inherit pkgs nodejs;
        };
        npm = "${pkgs.nodePackages.npm}/bin/npm";
        runtime = pkgs.stdenv.mkDerivation {
          name = "octopusenergy-consumption-metrics";
          src = ./.;
          buildInputs = with pkgs; [
            nodejs
          ];
          dontConfigure = true;
          dontBuild = true;
          installPhase = ''
              mkdir -p $out
              cp -R ./ $out/
              ln -s ${nodeEnv.shell.nodeDependencies}/lib/node_modules/ $out/node_modules
            '';
        };
      in pkgs.writeScriptBin "octopusenergy-consumption-metrics" ''
        #!${pkgs.stdenv.shell}
        ${nodejs}/bin/node ${runtime}/index.js
      '');
    in rec {
      hydraJobs = {
        inherit packages;
      };
      devShell = pkgs.lib.genAttrs systems (system: let
        pkgs = import nixpkgs {
          inherit system;
        };
      in pkgs.mkShell {
        buildInputs = with pkgs; [
          nodejs-14_x
          nodePackages.node2nix
        ];
        shellHook = let
          nodeEnv = import ./node2nix.nix { inherit pkgs; };
        in ''
          rm -rf node_modules
          ln -s ${nodeEnv.shell.nodeDependencies}/lib/node_modules node_modules
        '';
      });
      overlay = (final: prev: {
        octopusenergy-consumption-metrics = (octopusenergy-consumption-metrics final);
      });
      packages = pkgs.lib.genAttrs systems (system: let
        pkgs = import nixpkgs {
          inherit system;
        };
      in {
        octopusenergy-consumption-metrics = (octopusenergy-consumption-metrics pkgs);
      });
      nixosModules.octopusenergy-consumption-metrics = { config, lib, pkgs, ... }: let
        cfg = config.services.octopusenergy-consumption-metrics;
      in {
        options = {
          services.octopusenergy-consumption-metrics = with lib.types; {
            enable = lib.mkEnableOption "octopusenergy-consumption-metrics";
            apiKeyFile = lib.mkOption { type = str; };
            accountNumber = lib.mkOption { type = str; };
            loopTime = lib.mkOption {
              type = int;
              default = 3600;
            };
            pageSize = lib.mkOption {
              type = int;
              default = 100;
            };
            electricity = {
              mpan = lib.mkOption { type = str; };
              serial = lib.mkOption { type = str; };
              cost = lib.mkOption {
                type = float;
                default = 0.0;
              };
            };
            gas = {
              mprn = lib.mkOption { type = str; };
              serial = lib.mkOption { type = str; };
              cost = lib.mkOption {
                type = float;
                default = 0.0;
              };
            };
            influxdb = {
              url = lib.mkOption { type = str; };
              tokenFile = lib.mkOption { type = str; };
              org = lib.mkOption { type = str; };
              bucket = lib.mkOption { type = str; };
            };
          };
        };
        config = lib.mkIf cfg.enable {
          nixpkgs.overlays = [ overlay ];
          users = {
            extraGroups.octopus = { };
            extraUsers.octopus = {
              isSystemUser = true;
              group = "octopus";
            };
          };
          systemd.services.octopusenergy-consumption-metrics = {
            description = "octopusenergy-consumption-metrics";
            enable = true;
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Restart = "always";
              ExecStart = let
                package = pkgs.writeScriptBin "octopusenergy-consumption-metrics-wrapped" ''
                  #!${pkgs.stdenv.shell}
                  export OCTO_API_KEY="$(cat ${cfg.apiKeyFile})"
                  export OCTO_ELECTRIC_MPAN="${cfg.electricity.mpan}"
                  export OCTO_ELECTRIC_SN="${cfg.electricity.serial}"
                  export OCTO_GAS_MPRN="${cfg.gas.mprn}"
                  export OCTO_GAS_SN="${cfg.gas.serial}"
                  export INFLUXDB_URL="${cfg.influxdb.url}"
                  export INFLUXDB_TOKEN="$(cat ${cfg.influxdb.tokenFile})"
                  export INFLUXDB_ORG="${cfg.influxdb.org}"
                  export INFLUXDB_BUCKET="${cfg.influxdb.bucket}"
                  export LOOP_TIME="${toString cfg.loopTime}"
                  export OCTO_ELECTRIC_COST="${toString cfg.electricity.cost}"
                  export OCTO_GAS_COST="${toString cfg.gas.cost}"
                  export PAGE_SIZE="${toString cfg.pageSize}"
                  export OCTO_ACCOUNT_NUMBER="${cfg.accountNumber}"
                  ${pkgs.octopusenergy-consumption-metrics}/bin/octopusenergy-consumption-metrics
                '';
              in "${package}/bin/octopusenergy-consumption-metrics-wrapped";
              User = "octopus";
            };
          };
        };
      };
    };
}
