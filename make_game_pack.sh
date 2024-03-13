#!/bin/sh
mkdir game_pack
zig build --prefix .
cp -r assets/ main.wasm wasm-bind.js index.html game_pack
zip -r game_pack.zip game_pack
rm -rf game_pack
