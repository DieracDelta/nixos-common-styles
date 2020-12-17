{
  description = "Common styles for NixOS related web sites.";

  inputs.nixpkgs = { url = "nixpkgs/nixos-unstable"; };

  outputs =
    { self
    , nixpkgs 
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      package = builtins.fromJSON (builtins.readFile ./package.json);
    in rec {

      lib.memoizeAssets = assets:
        pkgs.runCommandNoCC "nixos-site-svg-assets" {
          nativeBuildInputs = with pkgs.nodePackages; [
            svgo
          ];
        }
        ''
          cp -r "${assets}" assets
          chmod -R +w assets

          echo ":: Embedding SVG files"
          (cd assets
          # Skip the source svg files
          rm -f *.src.svg

          # Optimize svg files
          for f in *.svg; do
            svgo $f &
          done 
          # Wait until all `svgo` processes are done
          # According to light testing, it is twice as fast that way.
          wait

          # Embed svg files in svg.less
          for f in *.svg; do
            echo "- $f"
            token=''${f^^}
            token=''${token//[^A-Z0-9]/_}
            token=SVG_''${token/%_SVG/}
            substituteInPlace svg.less --replace "@$token)" "'$(cat $f)')"
            substituteInPlace svg.less --replace "@$token," "'$(cat $f)',"
          done
          )
          mv assets $out
        '';

      defaultPackage."${system}" = packages."${system}".commonStyles;

      checks."${system}".build = defaultPackage."${system}";

      packages."${system}" = rec {

        commonStyles = pkgs.stdenv.mkDerivation {
          name = "nixos-common-styles-${self.lastModifiedDate}";

          src = self;

          enableParallelBuilding = true;

          installPhase = ''
            mkdir $out
            cp -R src/* $out/

            rm -rf $out/assets
            ln -sf ${lib.memoizeAssets ./src/assets} $out/assets
          '';
        };

        storyBookYarnPkg = pkgs.yarn2nix-moretea.mkYarnPackage rec {
          name = "${package.name}-yarn-${package.version}";
          src = null;
          dontUnpack = true;
          packageJSON = ./package.json;
          yarnLock = ./yarn.lock;
          preConfigure = ''
            mkdir ${package.name}
            cd ${package.name}
            ln -s ${packageJSON} ./package.json
            ln -s ${yarnLock} ./yarn.lock
          '';
          yarnPreBuild = ''
            mkdir -p $HOME/.node-gyp/${pkgs.nodejs.version}
            echo 9 > $HOME/.node-gyp/${pkgs.nodejs.version}/installVersion
            ln -sfv ${pkgs.nodejs}/include $HOME/.node-gyp/${pkgs.nodejs.version}
          '';
          publishBinsFor =
            [
              "@storybook/html"
            ];
          postInstall = ''
            sed -i -e "s|node_modules/.cache/storybook|.cache/storybook|" \
              $out/libexec/${package.name}/node_modules/@storybook/core/dist/server/utils/resolve-path-in-sb-cache.js
          '';
        };

        storyBook = pkgs.stdenv.mkDerivation {
          name = "${package.name}-${package.version}";
          src = pkgs.lib.cleanSource ./.;

          buildInputs =
            [
              storyBookYarnPkg
            ] ++
            (with pkgs; [
              nodejs
            ]) ++
            (with pkgs.nodePackages; [
              yarn
            ]);

          patchPhase = ''
            rm -rf node_modules
            ln -sf ${storyBookYarnPkg}/libexec/${package.name}/node_modules .
          '';

          buildPhase = ''
            # Yarn writes cache directories etc to $HOME.
            export HOME=$PWD/yarn_home
            yarn run build-storybook
          '';

          installPhase = ''
            mkdir -p $out
            cp -R ./storybook-static/* $out/
            cp netlify.toml $out/
          '';

          shellHook = ''
            rm -rf node_modules
            ln -sf ${storyBookYarnPkg}/libexec/${package.name}/node_modules .
            export PATH=$PWD/node_modules/.bin:$PATH
            echo "======================================"
            echo "= To develop run: yarn run storybook ="
            echo "======================================"
          '';
        };

      };
    };
}
