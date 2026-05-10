#!/usr/bin/env bash
# Fake reviewer that writes a minimal findings + ## DONE immediately.
# Args: $1 = output file path
out="${1:?out path required}"
cat > "$out" <<'EOF'
<findings>
  <verdict agree="true"><reasoning>fake instant agree</reasoning></verdict>
</findings>
## DONE
EOF
