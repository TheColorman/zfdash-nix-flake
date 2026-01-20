{
  fetchFromGitHub,
  uv2nix,
  callPackage,
  pyproject-nix,
  lib,
  pythonInterpreters,
  pyproject-build-systems,
  libxkbcommon,
  kdePackages,
  gst_all_1,
  speechd-minimal,
  pcsclite,
  mysql80,
  python310Packages,
  gdk-pixbuf,
  cairo,
  at-spi2-atk,
  pango,
  gtk3,
  writeShellApplication,
  stdenv,
}: let
  src = stdenv.mkDerivation {
    name = "zfdash-source-patched";
    src = fetchFromGitHub {
      owner = "ad4mts";
      repo = "zfdash";
      tag = "v1.9.6-beta";
      hash = "sha256-KF8QESleNFKm0BcCI2lIAtz+lMieSOPUK4rW9B2cWCA=";
    };

    # Remove hardcoded persistent data dir, assume cwd is set up for persistent
    # data for the daemon
    patchPhase = ''
      substituteInPlace src/paths.py \
        --replace-fail '"/opt/zfdash/data"' 'Path.cwd()'
    '';

    installPhase = ''
      mkdir -p $out
      cp -r * $out
    '';
  };

  workspace = uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = src;
  };

  python = lib.head (pyproject-nix.lib.util.filterPythonInterpreters {
    inherit pythonInterpreters;
    inherit (workspace) requires-python;
  });
  pythonBase = callPackage pyproject-nix.build.packages {inherit python;};
  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };
  pythonSet = pythonBase.overrideScope (lib.composeManyExtensions [
    pyproject-build-systems.overlays.wheel
    overlay
    (_final: prev: {
      pyside6-essentials = let
        p = prev.pyside6-essentials;
      in
        p.overrideAttrs {
          nativeBuildInputs =
            (p.nativeBuildInputs or [])
            ++ [
              libxkbcommon
              kdePackages.wayland
              kdePackages.qtwayland
              kdePackages.qtvirtualkeyboard
              kdePackages.qt3d
              kdePackages.qtwebengine
              kdePackages.qtscxml
              kdePackages.qtbase
              mysql80
              gdk-pixbuf
              cairo
              at-spi2-atk
              pango
              gtk3
              python310Packages.shiboken6
            ];
          dontWrapQtApps = true;
          autoPatchelfIgnoreMissingDeps =
            (p.autoPatchelfIgnoreMissingDeps or [])
            ++ ["libmimerapi.so" "libQt6EglFsKmsGbmSupport.so.6"];
        };
      pyside6-addons = let
        p = prev.pyside6-addons;
      in
        p.overrideAttrs {
          nativeBuildInputs =
            (p.nativeBuildInputs or [])
            ++ [
              kdePackages.qtbase
              kdePackages.qtdeclarative
              kdePackages.qtwebview
              kdePackages.qtquicktimeline
              gst_all_1.gstreamer
              gst_all_1.gst-plugins-base
              speechd-minimal
              pcsclite.lib
              python310Packages.shiboken6
              python310Packages.pyside6
            ];
          dontWrapQtApps = true;
        };
    })
  ]);

  venv = pythonSet.mkVirtualEnv "zfdash" workspace.deps.default;
in
  writeShellApplication {
    name = "zfdash";
    text = ''
      ${venv}/bin/python ${src}/src/main.py "$@"
    '';
  }
