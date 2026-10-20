#!/usr/bin/env bash
# Print the assessment documents to PDF with headless Chrome.
#     bash docs/build_docs.sh
set -euo pipefail
cd "$(dirname "$0")"
for name in assessment8_abstract assessment9_stream_relevance assessment10_ppt_r_code; do
  google-chrome-stable --headless=new --disable-gpu --no-pdf-header-footer \
    --virtual-time-budget=10000 --print-to-pdf="$name.pdf" "file://$PWD/$name.html" 2>/dev/null
  echo "wrote docs/$name.pdf"
done
