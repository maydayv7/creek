{
  pkgs ? import <nixpkgs> {
    config = {
      allowUnfree = true;
      cudaSupport = true;
    };
  },
}:

pkgs.mkShell {
  nativeBuildInputs =
    let
      fal-client =
        with pkgs.python3Packages;
        buildPythonPackage rec {
          pname = "fal_client";
          version = "0.10.0";
          pyproject = true;
          src = fetchPypi {
            inherit pname version;
            hash = "sha256-UwNtAwgRerLaddWLTQnpUQk2Oob3sW/FmhhidgKYZh8=";
          };
          propagatedBuildInputs = [
            httpx
            httpx-sse
            msgpack
            setuptools
            setuptools-scm
            websockets
          ];
        };
    in
    [
      pkgs.python3
      (pkgs.python3.withPackages (
        p: with p; [
          accelerate
          bitsandbytes
          diffusers
          einops
          fal-client
          flask
          flask-cors
          hf-xet
          kornia
          numpy
          opencv4
          pillow
          pip
          pycryptodome
          python-dotenv
          requests
          scipy
          tblib
          timm
          toml
          torch
          torchvision
          transformers
        ]
      ))
    ];

  LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib";
}
