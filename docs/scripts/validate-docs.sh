#!/bin/bash

# Documentation validation script
# Validates the structure and basic content of the documentation

set -e

echo "🔍 Validating documentation structure..."

# Check if required directories exist
REQUIRED_DIRS=(
    "docs/features"
    "docs/features/authentication"
    "docs/features/security"
    "docs/features/infrastructure"
    "docs/features/development"
    "docs/features/api-gateway"
    "docs/guides"
    "docs/templates"
    "docs/config"
)

echo "📁 Checking directory structure..."
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "❌ Missing directory: $dir"
        exit 1
    else
        echo "✅ Found: $dir"
    fi
done

# Check if required files exist
REQUIRED_FILES=(
    "docs/README.md"
    "docs/index.md"
    "docs/features/README.md"
    "docs/guides/README.md"
    "docs/templates/feature-template.md"
    "docs/templates/guide-template.md"
    "docs/templates/navigation-template.md"
    "docs/config/documentation-config.md"
    "docs/config/metadata.json"
)

echo "📄 Checking required files..."
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ Missing file: $file"
        exit 1
    else
        echo "✅ Found: $file"
    fi
done

# Check category README files
CATEGORY_READMES=(
    "docs/features/authentication/README.md"
    "docs/features/security/README.md"
    "docs/features/infrastructure/README.md"
    "docs/features/development/README.md"
    "docs/features/api-gateway/README.md"
)

echo "📚 Checking category README files..."
for readme in "${CATEGORY_READMES[@]}"; do
    if [ ! -f "$readme" ]; then
        echo "❌ Missing category README: $readme"
        exit 1
    else
        echo "✅ Found: $readme"
    fi
done

# Validate JSON configuration
echo "🔧 Validating JSON configuration..."
if command -v jq >/dev/null 2>&1; then
    if jq empty docs/config/metadata.json >/dev/null 2>&1; then
        echo "✅ metadata.json is valid JSON"
    else
        echo "❌ metadata.json is invalid JSON"
        exit 1
    fi
else
    echo "⚠️  jq not found, skipping JSON validation"
fi

# Check for basic content in main files
echo "📝 Checking basic content..."

# Check if README has essential sections
if grep -q "# Authentication System Documentation" docs/README.md; then
    echo "✅ Main README has proper title"
else
    echo "❌ Main README missing proper title"
    exit 1
fi

if grep -q "Features Documentation" docs/features/README.md; then
    echo "✅ Features README has proper title"
else
    echo "❌ Features README missing proper title"
    exit 1
fi

if grep -q "Guides Documentation" docs/guides/README.md; then
    echo "✅ Guides README has proper title"
else
    echo "❌ Guides README missing proper title"
    exit 1
fi

# Count documentation files
TOTAL_FILES=$(find docs -name "*.md" | wc -l)
echo "📊 Documentation statistics:"
echo "   Total markdown files: $TOTAL_FILES"
echo "   Feature categories: 5"
echo "   Templates: 3"

echo ""
echo "✅ Documentation structure validation completed successfully!"
echo "🎉 All required files and directories are present."
echo ""
echo "Next steps:"
echo "1. Review the generated structure in docs/"
echo "2. Begin implementing individual feature documentation"
echo "3. Use the templates in docs/templates/ for consistency"
echo "4. Update docs/config/metadata.json as features are added"