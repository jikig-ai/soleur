#!/bin/bash
# Filter out test functions from LCOV coverage report
set -e

INPUT_FILE="${1:-lcov.info}"
OUTPUT_FILE="${2:-lcov_filtered.info}"

# Process the LCOV file to:
# 1. Remove FN/FNDA lines for test functions (containing "5testss_")
# 2. Recalculate FNF/FNH counts per file

awk '
BEGIN { fn_count = 0; fnh_count = 0; in_file = 0; }

# Start of new file
/^SF:/ {
    if (in_file) {
        # Output recalculated counts for previous file
        print "FNF:" fn_count
        print "FNH:" fnh_count
    }
    print $0
    fn_count = 0
    fnh_count = 0
    in_file = 1
    next
}

# Function definition - keep non-test functions
/^FN:/ {
    if ($0 !~ /5tests[s_:]/) {
        print $0
        fn_count++
    }
    next
}

# Function data - keep non-test functions
/^FNDA:/ {
    if ($0 !~ /5tests[s_:]/) {
        print $0
        # Extract hit count to determine if function was hit
        split($0, parts, ",")
        if (parts[1] ~ /^FNDA:[0-9]+$/) {
            hits = substr(parts[1], 6)
            if (hits > 0) {
                fnh_count++
            }
        }
    }
    next
}

# Skip old FNF/FNH lines - we will recalculate
/^FNF:/ { next }
/^FNH:/ { next }

# End of record
/^end_of_record$/ {
    # Output final counts for this file
    if (in_file) {
        print "FNF:" fn_count
        print "FNH:" fnh_count
    }
    print $0
    in_file = 0
    next
}

# All other lines
{ print $0 }

END {
    # Handle case where file does not end with end_of_record
    if (in_file) {
        print "FNF:" fn_count
        print "FNH:" fnh_count
    }
}
' "$INPUT_FILE" > "$OUTPUT_FILE"

echo "Filtered LCOV written to $OUTPUT_FILE"
