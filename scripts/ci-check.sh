#!/usr/bin/env bash
set -euo pipefail

required=(
  "settings.gradle"
  "build.gradle"
  "gradlew"
  "gradle/wrapper/gradle-wrapper.jar"
  "gradle/wrapper/gradle-wrapper.properties"
  "app/build.gradle"
  "app/src/main/AndroidManifest.xml"
)

for f in "${required[@]}"; do
  test -f "$f" || { echo "Missing required file: $f"; exit 1; }
done

test -x gradlew || chmod +x gradlew

# Catch obvious source corruption before Gradle is invoked.
if grep -RInE 'itbel\(|%02X%02X%02X"[A-Za-z_]+\(' app/src/main/java --include='*.kt'; then
  echo "Suspicious/corrupted Kotlin source token detected"
  exit 1
fi

# Catch accidental duplicate package declarations, which break Kotlin compilation.
bad=0
while IFS= read -r -d '' f; do
  count=$(grep -cE '^package ' "$f" || true)
  if [ "$count" -gt 1 ]; then
    echo "Multiple package declarations: $f"
    bad=1
  fi
done < <(find app/src -name '*.kt' -print0)

if [ "$bad" -ne 0 ]; then
  exit 1
fi

# Keep the Android version in one place and verify the expected release metadata.
# Verify the GitHub Actions license step does not fail on the expected `yes` SIGPIPE.
for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$wf" ] || continue
  if grep -qE 'yes \|.*sdkmanager.*--licenses' "$wf" && ! grep -q 'set \+o pipefail' "$wf"; then
    echo "Unsafe sdkmanager license pipeline in $wf"
    exit 1
  fi
done

version_name=$(grep -oE 'versionName[[:space:]]+"[^"]+"' app/build.gradle | head -1 | sed -E 's/.*"([^"]+)"/\1/')
version_code=$(grep -oE 'versionCode[[:space:]]+[0-9]+' app/build.gradle | head -1 | awk '{print $2}')

test -n "$version_name" || { echo "Could not read versionName"; exit 1; }
test -n "$version_code" || { echo "Could not read versionCode"; exit 1; }

echo "GITLS versionName: $version_name"
echo "GITLS versionCode: $version_code"
echo "Project structure check: OK"


# Keep the distributable source tree clean: no generated documentation/log artifacts.
if find . -type f \( -name '*.md' -o -name '*.txt' -o -name '*.log' \) \
    ! -path './.git/*' ! -path './.gradle/*' | grep -q .; then
  echo "Unexpected documentation/text/log artifact found in project tree."
  find . -type f \( -name '*.md' -o -name '*.txt' -o -name '*.log' \) \
    ! -path './.git/*' ! -path './.gradle/*'
  exit 1
fi

grep -q 'compileSdkVersion 36' app/build.gradle || { echo "compileSdkVersion 36 missing"; exit 1; }
grep -q 'targetSdkVersion 36' app/build.gradle || { echo "targetSdkVersion 36 missing"; exit 1; }
