#!/usr/bin/env bash
set -e

echo "==> Checking for Node.js..."
if ! command -v node &> /dev/null; then
    echo "Node.js is not installed. Install Node 20+ first: https://nodejs.org"
    exit 1
fi

NODE_MAJOR=$(node -v | sed -E 's/v([0-9]+).*/\1/')
if [ "$NODE_MAJOR" -lt 20 ]; then
    echo "Node.js 20+ is required. You have $(node -v)."
    exit 1
fi

echo "==> Cloning gentree..."
if [ -d "gentree" ]; then
    echo "Folder 'gentree' already exists, pulling latest instead."
    cd gentree
    git pull
else
    git clone https://github.com/errorcatch/gentree.git
    cd gentree
fi

echo "==> Installing dependencies..."
npm install

echo "==> Building..."
npm run build

echo "==> Linking gentree globally..."
npm link

echo ""
echo "Done. Try running 'gentree' from any Rojo project folder."