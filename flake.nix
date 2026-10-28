{
  description = "組み込み開発用の共通ツールチェーン";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  # ESP-IDF 一式 (コンパイラ・Python 環境・openocd-esp32)。独自の nixpkgs を使うので follows しない
  inputs.esp-dev.url = "github:mirrexagon/nixpkgs-esp-dev";

  outputs = { self, nixpkgs, esp-dev }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # 汎用 RISC-V gcc (CH32V, RP2350 Hazard3)。nixpkgs にビルド済みがないので xPack の配布物を固定する
      riscv-none-elf-gcc = pkgs.stdenv.mkDerivation rec {
        pname = "xpack-riscv-none-elf-gcc";
        version = "14.3.0-1";
        src = pkgs.fetchurl {
          url = "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${version}/xpack-riscv-none-elf-gcc-${version}-linux-x64.tar.gz";
          hash = "sha256-vhdo7yJ4n02cQThOAmGZb1FyS4TC76lA2XXdfZk4xyY=";
        };
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.zlib pkgs.ncurses ];
        # gdb-py3 は python 前提なので外す (通常の riscv-none-elf-gdb は残る)
        autoPatchelfIgnoreMissingDeps = [ "libpython3*" ];
        dontStrip = true;
        installPhase = ''
          rm -f bin/*-gdb-py3
          mkdir -p $out
          mv ./* $out/   # 展開後が数 GiB あるのでコピーせず移動
          # pico-sdk は riscv32-unknown-elf-* を探すので別名を張る
          for f in $out/bin/riscv-none-elf-*; do
            ln -s $(basename $f) $out/bin/riscv32-unknown-elf-''${f##*/riscv-none-elf-}
          done
        '';
      };

      # WCH gcc 8.2.0 (CH32V)。WCH SDK の __attribute__((interrupt("WCH-Interrupt-fast"))) を解釈できるのはこれだけ
      # (汎用 gcc は属性を無視して ret を出し、割り込みで暴走する)。PlatformIO 用の再パッケージを GitHub から直接取る
      wch-riscv-gcc = pkgs.stdenv.mkDerivation {
        pname = "wch-riscv-none-embed-gcc";
        version = "8.2.0";
        src = pkgs.fetchurl {
          url = "https://github.com/Community-PIO-CH32V/toolchain-riscv-linux/archive/e8e7ba93c9c1ea30366d98f28318d4ad09b369e2.tar.gz";
          hash = "sha256-i+NJ6NH2WK7U4BfMKRo+NvBdFh2UppSqIyD30f7wM0o=";
        };
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [ pkgs.stdenv.cc.cc.lib ];
        autoPatchelfIgnoreMissingDeps = [ "libpython2.7.so.1.0" ];   # gdb-py 用。通常の gdb は不要
        dontStrip = true;
        installPhase = ''
          rm -f bin/*-gdb-py bin/*-gdb-add-index-py
          mkdir -p $out
          mv ./* $out/
        '';
      };

      # WCH 版 openocd (WCH-LinkE で CH32V をデバッグする唯一の手段)。本家と衝突しないよう openocd-wch として公開
      openocd-wch = pkgs.stdenv.mkDerivation {
        pname = "openocd-wch";
        version = "2.1100.260228";
        src = pkgs.fetchurl {
          url = "https://dl.registry.platformio.org/download/community-ch32v/tool/tool-openocd-riscv-wch/2.1100.260228/tool-openocd-riscv-wch-linux_x86_64-2.1100.260228.tar.gz";
          hash = "sha256-wSuD6WBz46btbzLqrh8BGmcTTUWu8f5DYEe7StwMLlo=";
        };
        sourceRoot = ".";
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.udev ];
        installPhase = ''
          mkdir -p $out/libexec/openocd-wch $out/bin
          mv bin share $out/libexec/openocd-wch/
          cp $out/libexec/openocd-wch/bin/wch-*.cfg $out/libexec/openocd-wch/share/openocd/scripts/
          ln -s ../libexec/openocd-wch/bin/openocd $out/bin/openocd-wch
        '';
      };

      # openocd は probe-rs で困ったときの予備。jimtcl は既定で SDL 付き (依存が 2.5GiB に膨らむ) なので外す
      jimtcl = pkgs.jimtcl.override { SDLSupport = false; };

      # nixpkgs の openocd 0.12.0 は STM32C0 非対応なので、固定コミットからビルドする
      openocd = (pkgs.openocd.override { inherit jimtcl; }).overrideAttrs (old: {
        version = "0.12.0-unstable-5088db4c9";
        src = pkgs.fetchurl {
          url = "https://github.com/openocd-org/openocd/archive/5088db4c9154ca833c6d558381074b33672e127a.tar.gz";
          hash = "sha256-1mkV3/fmdPBTPhmDBBQ43zzNER5BrAGkcMqFbw+PCj4=";
        };
        nativeBuildInputs = old.nativeBuildInputs ++ (with pkgs; [ autoconf automake libtool texinfo which ]);
        preConfigure = "./bootstrap nosubmodule";
      });
      # どこからでも使う道具 (nix profile add .#embedded-tools でグローバルに入れる)。
      # python3 / cmake / ninja はシステムのものに影響するので含めず、プロジェクトの環境の中だけで使う
      tools = with pkgs; [
        gcc-arm-embedded-14    # arm-none-eabi-gcc / gdb 14.3.rel1 (STM32, RP2040, RP2350 Arm)
        riscv-none-elf-gcc     # riscv-none-elf-gcc / gdb 14.3.0 (RP2350 Hazard3)
        wch-riscv-gcc          # riscv-none-embed-gcc / gdb 8.2.0 (CH32V。WCH SDK 用)
        openocd-wch            # CH32V のデバッグ (WCH-LinkE)
        probe-rs-tools         # 書き込み・デバッグ (ST-LINK, DAPLink, J-Link, WCH-Link)
        openocd
        picotool               # RP2040 / RP2350
        wchisp                 # CH32V の USB ブートローダー書き込み
        wlink                  # CH32V の WCH-LinkE 書き込み
        platformio-core        # pio 本体。フレームワーク等は pio が ~/.platformio に入れる
      ];
    in
    {
      packages.${system} = {
        inherit openocd riscv-none-elf-gcc wch-riscv-gcc openocd-wch;
        embedded-tools = pkgs.buildEnv {
          name = "embedded-tools";
          paths = tools;
          pathsToLink = [ "/bin" ];   # コンパイラ同士で lib/ のファイル名が衝突するのでコマンドだけ
        };
      };

      devShells.${system} = {
        default = pkgs.mkShell {
          packages = tools ++ (with pkgs; [
            cmake
            ninja
            python3            # pico-sdk / ESP-IDF / PlatformIO が使う
          ]);
          # pico-sdk が picotool をネットから取ってビルドしないように
          picotool_DIR = "${pkgs.picotool}/lib/cmake/picotool";
        };

        # ESP-IDF はフレームワークとコンパイラが一体なので別環境にする。
        # full (全チップ) は esp-clang で数 GiB 増えるので、アーキテクチャごとに分ける
        esp = pkgs.mkShell {          # RISC-V: ESP32-C3/C6/H2/P4 など
          buildInputs = [ esp-dev.packages.${system}.esp-idf-riscv ];
        };
        esp-xtensa = pkgs.mkShell {   # Xtensa: ESP32/S2/S3
          buildInputs = [ esp-dev.packages.${system}.esp-idf-xtensa ];
        };
      };
    };
}
