{outputs}: {
  lib,
  config,
  pkgs,
  ...
}: let
  flakePkgs = outputs.packages.${pkgs.stdenv.system};
  defaultPackage = flakePkgs.default;
  cfg = config.services.zfdash;
in {
  options.services.zfdash = with lib; {
    enable = mkEnableOption "ZfDash";
    package = mkPackageOption flakePkgs "zfdash" {
      pkgsText = "zfdash-nix-flake.packages.${pkgs.stdenv.system}";
    };

    group = mkOption {
      type = types.str;
      default = "zfdash";
      description = ''
        Group granted access to the ZfDash daemon socket, used for
        communication between daemon and WebUI.
      '';
    };

    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        Network address ZfDash will listen on.
      '';
      example = "0.0.0.0";
    };
    port = mkOption {
      type = types.port;
      default = 5001;
      description = "Port to serve the ZfDash Web UI on.";
    };

    environment = mkOption {
      type = types.attrs;
      default = {};
      example = {
        JELLYFIN_BASE_URL = "http://localhost:8096";
      };
      description = ''
        Set of environment variables that will be exposed to ZfDash.
        This set should NOT be used to store secrets. Use
        {option}`services.zfdash.environmentFile` instead. This
        option and `environmentFile` will be merged, with options from
        `environmentFile` taking precedence.
      '';
    };
    environmentFile = mkOption {
      type = with types; nullOr path;
      default = null;
      example = "/run/secrets/zfdash.en";
      description = ''
        Path to an environment file containing environment variables that will
        be merged with the `environment` option. This is suitable for storing
        secrets, as they will not be exposed in the Nix store.
        If this does not contain `FLASK_SECRET`, a suitable secret will be
        generated for you.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = ! (cfg.environment ? FLASK_SECRET);
        message = ''
          FLASK_SECRET should not be set in `environment` as the value is
          world-readable in the Nix store. Use `environmentFile` instead, or
          let the service generate a suitable secret automatically by removing
          it entirely.
        '';
      }
    ];

    nixpkgs.overlays = [
      (_final: _prev: {
        zfdash = defaultPackage;
      })
    ];

    users.groups."${cfg.group}" = {};

    systemd.services = let
      stateDir = "zfdash";
      statePath = "/var/lib/${stateDir}";
    in {
      zfdash-root-daemon = {
        description = "ZfDash root deamon";
        after = ["zfs.target"];
        wants = ["zfs.target"];

        path = with pkgs; [zfs getent];

        preStart = ''
          mkdir -p /run/zfdash
        '';
        postStop = ''
          rm -rf /run/zfdash
        '';

        serviceConfig = {
          Type = "simple";
          User = "root";
          Group = "root";

          StateDirectory = stateDir;
          WorkingDirectory = statePath;

          ExecStart = lib.getExe (pkgs.writeShellApplication {
            name = "zfdash-deamon-launcher";
            text = ''
              gid=$(getent group ${cfg.group} | cut -d: -f3)
              ${cfg.package}/bin/zfdash \
                --daemon \
                --uid 0 \
                --gid "$gid" \
                --listen-sock /run/zfdash/daemon.sock
            '';
          });

          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      zfdash-web = {
        description = "ZfDash Web UI service";
        after = ["network.target" "zfdash-root-daemon.service"];
        wants = ["network.target" "zfdash-root-daemon.service"];

        path = [pkgs.zfs];

        preStart = ''
          echo "Defining programs"
          grep=${pkgs.gnugrep}/bin/grep
          openssl=${pkgs.openssl}/bin/openssl

          echo "Creating directory"
          environmentFile=${statePath}/environment
          mkdir -p $(dirname "$environmentFile")

          echo "Checking existing environment file"
          # Get preexisting FLASK_SECRET
          if [ -f "$environmentFile" ] && line=$($grep '^FLASK_SECRET=' "$environmentFile" 2>/dev/null); then
            echo "Found flask secret, setting"
            FLASK_SECRET="''${line:13}"
          else
            echo "Did not find flask secret, generating"
            FLASK_SECRET=$($openssl rand -hex 32)
          fi

          ${lib.optionalString (cfg.environmentFile != null) ''
            echo "Checking nix environment file"
            if [ -f "${cfg.environmentFile}" ] && line=$($grep '^FLASK_SECRET=' "${cfg.environmentFile}" 2>/dev/null); then
              echo "found flask secret, setting"
              FLASK_SECRET="''${line:13}"
            fi
          ''}

          echo "Creating environment file with flask secret"
          echo "FLASK_SECRET=$FLASK_SECRET" > $environmentFile

          # Insert everything from `environment`
          echo "Inserting environment"
          ${lib.concatLines (lib.mapAttrsToList (key: value: ''
              echo "${key}=${value}" >> $environmentFile
            '')
            cfg.environment)}

          # Finally, append everything in `environmentFile`
          ${lib.optionalString (cfg.environmentFile != null) ''
            echo "Inserting nix environment file"
            cat ${cfg.environmentFile} >> $environmentFile
          ''}
        '';

        serviceConfig = {
          Type = "simple";
          DynamicUser = true;

          EnvironmentFile = "-/var/lib/zfdash/environment";

          StateDirectory = stateDir;
          WorkingDirectory = statePath;

          ExecStart = ''
            ${cfg.package}/bin/zfdash \
              --web \
              --host ${cfg.address} \
              --port ${toString cfg.port} \
              --connect-socket /run/zfdash/daemon.sock
          '';

          Restart = "on-failure";
          RestartSec = "5s";

          # Allow access to daemon socket
          SupplementaryGroups = [cfg.group];

          # Hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          DevicePolicy = "closed";
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectControlGroups = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
            "AF_NETLINK"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          SystemCallFilter = [
            "~@cpu-emulation"
            "~@debug"
            "~@keyring"
            "~@memlock"
            "~@obsolete"
            "~@privileged"
            "~@setuid"
          ];
        };
      };
    };
  };
}
