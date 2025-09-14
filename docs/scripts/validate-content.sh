#!/bin/bash

# Comprehensive content validation script
# Validates code examples, cross-references, and content consistency

echo "🔍 Validating documentation content..."

ERRORS=0
WARNINGS=0
ERROR_LOG=$(mktemp)
WARNING_LOG=$(mktemp)

# Function to log errors
log_error() {
    echo "❌ ERROR: $1" | tee -a "$ERROR_LOG"
    ((ERRORS++))
}

# Function to log warnings
log_warning() {
    echo "⚠️  WARNING: $1" | tee -a "$WARNING_LOG"
    ((WARNINGS++))
}

# Function to log success
log_success() {
    echo "✅ $1"
}

# Cleanup function
cleanup() {
    rm -f "$ERROR_LOG" "$WARNING_LOG"
}
trap cleanup EXIT

# Check for consistent heading structure
echo "📝 Checking heading structure..."
HEADING_ISSUES=$(mktemp)
find docs -name "*.md" -type f | while read -r file; do
    # Check if file starts with h1
    if ! head -1 "$file" | grep -q "^# "; then
        echo "File $file doesn't start with h1 heading" >> "$HEADING_ISSUES"
    fi
    
    # Check for proper heading hierarchy (no skipping levels going down)
    awk '
    /^```/ {
        in_code_block = !in_code_block
        next
    }
    /^#/ && !in_code_block {
        level = gsub(/#/, "")
        # Only warn about skipping levels when going deeper (increasing level)
        if (prev_level > 0 && level > prev_level + 1) {
            print "Heading level skip in " FILENAME " at line " NR ": " $0
        }
        prev_level = level
    }
    ' "$file" >> "$HEADING_ISSUES"
done

# Process heading issues
if [ -s "$HEADING_ISSUES" ]; then
    while read -r line; do
        log_warning "$line"
    done < "$HEADING_ISSUES"
fi
rm -f "$HEADING_ISSUES"

# Check for broken internal links
echo "🔗 Checking internal links..."
LINK_ISSUES=$(mktemp)
find docs -name "*.md" -type f -not -path "docs/templates/*" | while read -r file; do
    # Extract markdown links
    grep -n '\[.*\](.*\.md)' "$file" | while IFS=: read -r line_num link; do
        # Extract the path from [text](path)
        path=$(echo "$link" | sed -n 's/.*(\([^)]*\.md[^)]*\)).*/\1/p')
        
        # Skip external links
        if [[ "$path" =~ ^https?:// ]]; then
            continue
        fi
        
        # Skip anchor links
        if [[ "$path" =~ ^#.* ]]; then
            continue
        fi
        
        # Convert relative path to absolute path
        if [[ "$path" =~ ^/ ]]; then
            full_path="$path"
        else
            dir=$(dirname "$file")
            full_path="$dir/$path"
        fi
        
        # Normalize the path
        full_path=$(realpath -m "$full_path" 2>/dev/null || echo "$full_path")
        
        if [ ! -f "$full_path" ]; then
            echo "Broken link in $file:$line_num -> $path (resolved to $full_path)" >> "$LINK_ISSUES"
        fi
    done
done

# Process link issues
if [ -s "$LINK_ISSUES" ]; then
    while read -r line; do
        log_error "$line"
    done < "$LINK_ISSUES"
fi
rm -f "$LINK_ISSUES"

# Check for consistent code block formatting
echo "💻 Checking code block formatting..."
CODE_ISSUES=$(mktemp)
find docs -name "*.md" -type f | while read -r file; do
    # Check for code blocks without language specification (opening blocks only)
    awk '
    /^```/ {
        if (!in_code_block) {
            # This is an opening code block
            if ($0 == "```") {
                print "Code block without language specification at line " NR " in " FILENAME
            }
            in_code_block = 1
        } else {
            # This is a closing code block
            in_code_block = 0
        }
    }
    ' "$file" >> "$CODE_ISSUES"
    
    # Check for unclosed code blocks
    code_block_count=$(grep -c '^```' "$file" || true)
    if [ $((code_block_count % 2)) -ne 0 ]; then
        echo "Unclosed code block in $file" >> "$CODE_ISSUES"
    fi
done

# Process code block issues
if [ -s "$CODE_ISSUES" ]; then
    while read -r line; do
        if [[ "$line" == *"Unclosed code block"* ]]; then
            log_error "$line"
        else
            log_warning "$line"
        fi
    done < "$CODE_ISSUES"
fi
rm -f "$CODE_ISSUES"

# Check for consistent cross-reference format
echo "🔄 Checking cross-references..."
XREF_ISSUES=$(mktemp)
find docs -name "*.md" -type f | while read -r file; do
    # Look for "Related Features" sections
    if grep -q "## Related Features" "$file"; then
        # Check if related features section has proper links
        sed -n '/## Related Features/,/^## /p' "$file" | grep -E '^\s*-' | while read -r line; do
            if ! echo "$line" | grep -q '\[.*\](.*\.md)'; then
                echo "Related feature without proper link in $file: $line" >> "$XREF_ISSUES"
            fi
        done
    fi
done

# Process cross-reference issues
if [ -s "$XREF_ISSUES" ]; then
    while read -r line; do
        log_warning "$line"
    done < "$XREF_ISSUES"
fi
rm -f "$XREF_ISSUES"

# Check for required sections in feature documents
echo "📋 Checking required sections in feature documents..."
SECTION_ISSUES=$(mktemp)
find docs/features -name "*.md" -not -name "README.md" -type f | while read -r file; do
    required_sections=("Overview" "Implementation" "Configuration" "Usage" "Testing" "Troubleshooting")
    
    for section in "${required_sections[@]}"; do
        if ! grep -q "^## $section" "$file"; then
            echo "Missing required section '$section' in $file" >> "$SECTION_ISSUES"
        fi
    done
done

# Process section issues
if [ -s "$SECTION_ISSUES" ]; then
    while read -r line; do
        log_warning "$line"
    done < "$SECTION_ISSUES"
fi
rm -f "$SECTION_ISSUES"

# Check for required sections in guide documents
echo "📖 Checking required sections in guide documents..."
GUIDE_ISSUES=$(mktemp)
find docs/guides -name "*.md" -not -name "README.md" -type f | while read -r file; do
    required_sections=("Overview" "Prerequisites" "Validation" "Troubleshooting")
    
    for section in "${required_sections[@]}"; do
        if ! grep -q "^## $section" "$file"; then
            echo "Missing recommended section '$section' in $file" >> "$GUIDE_ISSUES"
        fi
    done
done

# Process guide issues
if [ -s "$GUIDE_ISSUES" ]; then
    while read -r line; do
        log_warning "$line"
    done < "$GUIDE_ISSUES"
fi
rm -f "$GUIDE_ISSUES"

# Check for consistent table formatting
echo "📊 Checking table formatting..."
TABLE_ISSUES=$(mktemp)
find docs -name "*.md" -type f | while read -r file; do
    # Check for tables with inconsistent column counts
    awk '
    /^\|.*\|$/ {
        cols = gsub(/\|/, "")
        if (prev_cols > 0 && cols != prev_cols && !in_header) {
            print "Inconsistent table columns in " FILENAME " at line " NR
        }
        if (prev_line ~ /^\|.*\|$/ && $0 ~ /^[\|\-\s:]+$/) {
            in_header = 1
        } else if (in_header && !($0 ~ /^\|.*\|$/)) {
            in_header = 0
        }
        prev_cols = cols
        prev_line = $0
    }
    ' "$file" >> "$TABLE_ISSUES"
done

# Process table issues
if [ -s "$TABLE_ISSUES" ]; then
    while read -r line; do
        log_warning "$line"
    done < "$TABLE_ISSUES"
fi
rm -f "$TABLE_ISSUES"

# Check for TODO or FIXME comments
echo "🚧 Checking for TODO/FIXME comments..."
TODO_ISSUES=$(mktemp)
find docs -name "*.md" -type f | while read -r file; do
    grep -n -i "TODO\|FIXME\|XXX" "$file" | while IFS=: read -r line_num content; do
        echo "TODO/FIXME found in $file:$line_num: $content" >> "$TODO_ISSUES"
    done
done

# Process TODO issues
if [ -s "$TODO_ISSUES" ]; then
    while read -r line; do
        log_warning "$line"
    done < "$TODO_ISSUES"
fi
rm -f "$TODO_ISSUES"

# Check for placeholder content
echo "🔍 Checking for placeholder content..."
PLACEHOLDER_ISSUES=$(mktemp)
find docs -name "*.md" -type f | while read -r file; do
    if grep -q "Lorem ipsum\|placeholder\|TODO\|CHANGEME\|FIXME" "$file"; then
        echo "Placeholder content found in $file" >> "$PLACEHOLDER_ISSUES"
    fi
done

# Process placeholder issues
if [ -s "$PLACEHOLDER_ISSUES" ]; then
    while read -r line; do
        log_warning "$line"
    done < "$PLACEHOLDER_ISSUES"
fi
rm -f "$PLACEHOLDER_ISSUES"

# Validate JSON files
echo "🔧 Validating JSON configuration..."
JSON_ISSUES=$(mktemp)
if command -v jq >/dev/null 2>&1; then
    find docs -name "*.json" -type f | while read -r file; do
        if ! jq empty "$file" >/dev/null 2>&1; then
            echo "Invalid JSON in $file" >> "$JSON_ISSUES"
        else
            log_success "Valid JSON: $file"
        fi
    done
    
    # Process JSON issues
    if [ -s "$JSON_ISSUES" ]; then
        while read -r line; do
            log_error "$line"
        done < "$JSON_ISSUES"
    fi
else
    log_warning "jq not found, skipping JSON validation"
fi
rm -f "$JSON_ISSUES"

# Check for consistent file naming
echo "📁 Checking file naming conventions..."
NAMING_ISSUES=$(mktemp)
find docs -name "*.md" -type f | while read -r file; do
    filename=$(basename "$file")
    
    # Check for kebab-case naming (except README.md)
    if [[ "$filename" != "README.md" ]] && ! echo "$filename" | grep -q '^[a-z0-9-]*\.md$'; then
        echo "File name not in kebab-case: $file" >> "$NAMING_ISSUES"
    fi
done

# Process naming issues
if [ -s "$NAMING_ISSUES" ]; then
    while read -r line; do
        log_warning "$line"
    done < "$NAMING_ISSUES"
fi
rm -f "$NAMING_ISSUES"

# Summary
echo ""
echo "📊 Content validation summary:"
echo "   Errors: $ERRORS"
echo "   Warnings: $WARNINGS"

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "❌ ERRORS FOUND:"
    cat "$ERROR_LOG"
fi

if [ $WARNINGS -gt 0 ]; then
    echo ""
    echo "⚠️  WARNINGS FOUND:"
    cat "$WARNING_LOG"
fi

echo ""
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "✅ All content validation checks passed!"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo "⚠️  Content validation completed with warnings"
    exit 0
else
    echo "❌ Content validation failed with errors"
    exit 1
fi