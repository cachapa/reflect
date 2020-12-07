#!/bin/sh

echo "Checking sudo…"
sudo echo 👍

git pull
dart pub get

echo "Building binary…"
dart compile exe bin/main.dart -o reflect

echo "Moving binary to /usr/bin…"
sudo mv reflect /usr/bin/
