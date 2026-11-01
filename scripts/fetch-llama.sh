#!/usr/bin/env bash
# Downloads the official llama.cpp iOS XCFramework into Frameworks/.
set -euo pipefail
TAG="${LLAMA_TAG:-b11960}"
cd "$(dirname "$0")/.."
if [ -d Frameworks/llama.xcframework ]; then echo "llama.xcframework already present"; exit 0; fi
mkdir -p Frameworks build
curl -fL --retry 4 -o build/llama.zip "https://github.com/ggml-org/llama.cpp/releases/download/${TAG}/llama-${TAG}-xcframework.zip"
rm -rf build/llama-unzip && mkdir -p build/llama-unzip
unzip -q build/llama.zip -d build/llama-unzip
XC=$(find build/llama-unzip -type d -name "llama.xcframework" | head -1)
[ -n "$XC" ] || { echo "llama.xcframework not found in archive"; find build/llama-unzip -maxdepth 3; exit 1; }
mv "$XC" Frameworks/
ls Frameworks/llama.xcframework
