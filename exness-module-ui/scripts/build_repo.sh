#!/bin/sh
set -eu

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 BASE_URL package.deb [package.deb ...]" >&2
  exit 2
fi

BASE_URL="${1%/}"
shift
ROOT="repo/public"
POOL="$ROOT/pool"

rm -rf "$ROOT"
mkdir -p "$POOL"
for package in "$@"; do
  cp "$package" "$POOL/"
done

(
  cd "$ROOT"
  dpkg-scanpackages --multiversion pool /dev/null > Packages
  gzip -9c Packages > Packages.gz
)

cat > "$ROOT/Release" <<EOF
Origin: Exness Module UI
Label: Exness Module UI
Suite: stable
Version: 1.0
Codename: ios-rootless
Date: $(date -u "+%a, %d %b %Y %H:%M:%S UTC")
Architectures: iphoneos-arm64
Components: main
Description: Rootless Exness Module UI packages for iOS 15-16
MD5Sum:
EOF

for metadata in Packages Packages.gz; do
  digest="$(openssl dgst -md5 -r "$ROOT/$metadata" | awk '{print $1}')"
  size="$(wc -c < "$ROOT/$metadata" | tr -d ' ')"
  printf ' %s %s %s\n' "$digest" "$size" "$metadata" >> "$ROOT/Release"
done

printf 'SHA256:\n' >> "$ROOT/Release"
for metadata in Packages Packages.gz; do
  digest="$(openssl dgst -sha256 -r "$ROOT/$metadata" | awk '{print $1}')"
  size="$(wc -c < "$ROOT/$metadata" | tr -d ' ')"
  printf ' %s %s %s\n' "$digest" "$size" "$metadata" >> "$ROOT/Release"
done

cat > "$ROOT/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Exness Module UI Repository</title>
  <style>
    body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#0b1020;color:#f7f9ff;margin:0;padding:40px 20px}
    main{max-width:620px;margin:auto;background:#151d33;border:1px solid #2b385e;border-radius:22px;padding:28px;box-shadow:0 20px 60px #0007}
    h1{margin-top:0}.button{display:inline-block;background:#3c82ff;color:white;text-decoration:none;padding:13px 18px;border-radius:12px;font-weight:700}
    code{display:block;overflow-wrap:anywhere;background:#0a0f1d;padding:12px;border-radius:10px;margin:18px 0;color:#b8ccff}
    p{line-height:1.55;color:#cdd6eb}
  </style>
</head>
<body><main>
  <h1>Exness Module UI</h1>
  <p>Rootless visual UI editor for Exness on iOS 15-16. Built for arm64 and arm64e.</p>
  <a class="button" href="sileo://source/$BASE_URL/">Add source to Sileo</a>
  <code>$BASE_URL/</code>
  <p>After installation, open a compatible Exness build and hold three fingers for 0.8 seconds to open the editor.</p>
</main></body></html>
EOF

touch "$ROOT/.nojekyll"
echo "APT repository created at $ROOT for $BASE_URL/"
