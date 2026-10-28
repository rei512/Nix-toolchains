# toolchains

組み込み開発用の共通ツールチェーン (Nix flake)。

## 環境 (devShells)

| 名前 | 対象 | 中身 |
|---|---|---|
| `default` | STM32, RP2040/RP2350, CH32V | arm-none-eabi-gcc 14.3.rel1, riscv-none-elf-gcc 14.3.0 (xPack), WCH gcc 8.2.0, openocd (5088db4c9), openocd-wch, probe-rs, picotool, wchisp, wlink, platformio-core, cmake, ninja, python3 |
| `esp` | ESP32-C3/C6/H2/P4 (RISC-V) | ESP-IDF v5.5.2 (nixpkgs-esp-dev `esp-idf-riscv`) |
| `esp-xtensa` | ESP32/S2/S3 (Xtensa) | ESP-IDF v5.5.2 (nixpkgs-esp-dev `esp-idf-xtensa`)。未検証 |

## 使い方

プロジェクトに `.envrc` を置く:

```sh
use flake ~/src/toolchains          # default
use flake ~/src/toolchains#esp      # ESP (RISC-V)
```

```sh
direnv allow
```

CI やほかの PC では `use flake github:rei512/Nix-toolchains#esp` のように GitHub から参照する。

コマンドだけをどこからでも使う場合:

```sh
nix profile add ~/src/toolchains#embedded-tools
```

## 更新

```sh
nix flake update   # nixpkgs を更新 → flake.lock が変わる
nix profile upgrade embedded-tools
```
