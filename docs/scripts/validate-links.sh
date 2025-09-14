#!/bin/bash

# Link validation script for documentation
# Checks for broken internal links and missing referenced files

set -e

echo "🔗 Validating documentation links..."

BROKEN_LINKS=0
TOTAL_LINKS=0

# Function to check if a file exists
check_file_exists() {
    local file_path="$1"
    local source_file="$2"
    
    if [ ! -f "$file_path" ]; then
        echo "❌ Broken link in $source_file: $file_path (file not found)"
        ((BROKEN_LINKS++))
        return 1
    else
        echo "✅ Valid link: $file_path"
        return 0
    fi
}

# Find all markdown files and check their internal links
echo "📄 Checking internal markdown links..."

find docs -name "*.md" -type f | while read -r file; do
    echo "Checking links in: $file"
    
    # Extract markdown links [text](path.md)
    grep -oE '\[.*\]\([^)]*\.md[^)]*\)' "$file" | while read -r link; do
        # Extract the path from [text](path)
        path=$(echo "$link" | sed -n 's/.*(\([^)]*\)).*/\1/p')
        
        # Skip external links (http/https)
        if [[ "$path" =~ ^https?:// ]]; then
            continue
        fi
        
        # Skip anchor links within the same file
        if [[ "$path" =~ ^#.* ]]; then
            continue
        fi
        
        ((TOTAL_LINKS++))
        
        # Convert relative path to absolute path
        if [[ "$path" =~ ^/ ]]; then
            # Absolute path from root
            full_path="$path"
        else
            # Relative path from current file's directory
            dir=$(dirname "$file")
            full_path="$dir/$path"
        fi
        
        # Normalize the path
        full_path=$(realpath -m "$full_path" 2>/dev/null || echo "$full_path")
        
        check_file_exists "$full_path" "$file"
    done
done

echo ""
echo "📊 Link validation summary:"
echo "   Total internal links checked: $TOTAL_LINKS"
echo "   Broken links found: $BROKEN_LINKS"

if [ $BROKEN_LINKS -eq 0 ]; then
    echo "✅ All internal links are valid!"
else
    echo "❌ Found $BROKEN_LINKS broken links"
    exit 1
fi